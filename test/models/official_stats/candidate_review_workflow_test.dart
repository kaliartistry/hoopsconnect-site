import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/candidate_review_workflow.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';

GameScope _scope() => GameScope(
  associationId: 'jba',
  competitionId: 'nbl',
  seasonId: 'season_2026',
  divisionId: 'division_1',
  phaseId: 'regular',
  gameId: 'game_1',
);

CandidateRevisionReference _revision(int number, String hashCharacter) =>
    CandidateRevisionReference(
      revisionId: 'revision_$number',
      revisionNumber: number,
      revisionHash: List.filled(64, hashCharacter).join(),
    );

CandidateReviewCommand _command({
  required String id,
  required CandidateReviewCommandType type,
  required int version,
  required CandidateRevisionReference target,
  CandidateRevisionReference? successor,
  String? reasonCode,
  String? reason,
}) => CandidateReviewCommand(
  commandId: id,
  type: type,
  actorAccountId:
      type == CandidateReviewCommandType.submit ||
          type == CandidateReviewCommandType.resubmit
      ? 'statistician_1'
      : 'reviewer_1',
  expectedWorkflowVersion: version,
  targetRevision: target,
  successorRevision: successor,
  reasonCode: reasonCode,
  reason: reason,
);

CandidateStatsWorkflow _acceptActiveRevision(CandidateStatsWorkflow state) =>
    state
        .withDeliveryState(JournalDeliveryState.queued)
        .withDeliveryState(JournalDeliveryState.sending)
        .withDeliveryState(JournalDeliveryState.accepted);

CandidateWorkflowException _workflowError(void Function() action) {
  try {
    action();
  } on CandidateWorkflowException catch (error) {
    return error;
  }
  throw TestFailure('Expected CandidateWorkflowException');
}

void main() {
  group('candidate exact-revision review workflow', () {
    test(
      'traces submit N, send back N, resubmit N+1, stale rejection, approve N+1',
      () {
        final n = _revision(1, 'a');
        final nPlusOne = _revision(2, 'b');
        var state = CandidateStatsWorkflow.preparing(
          scope: _scope(),
          playState: PlayState.completed,
        ).openDraft(revision: n, captureMode: CaptureMode.officialSheet);

        expect(state.captureStage, CandidateCaptureStage.postGameDraft);
        expect(state.playState, PlayState.completed);
        expect(state.reviewState, CandidateReviewState.draft);
        expect(state.deliveryState, JournalDeliveryState.savedOnDevice);

        state = _acceptActiveRevision(state);
        final submitN = _command(
          id: 'submit_n',
          type: CandidateReviewCommandType.submit,
          version: 0,
          target: n,
        );
        state = state.apply(submitN);
        expect(state.reviewState, CandidateReviewState.submitted);
        expect(state.submittedRevision!.hasSameIdentity(n), isTrue);

        state = state.apply(
          _command(
            id: 'review_n',
            type: CandidateReviewCommandType.beginReview,
            version: 1,
            target: n,
          ),
        );
        state = state.apply(
          _command(
            id: 'send_back_n',
            type: CandidateReviewCommandType.requestChanges,
            version: 2,
            target: n,
            reasonCode: 'score_evidence_mismatch',
            reason: 'Quarter two does not reconcile with the signed sheet.',
          ),
        );
        expect(state.reviewState, CandidateReviewState.changesRequested);
        expect(state.events.last.reasonCode, 'score_evidence_mismatch');
        expect(
          state.events.last.reason,
          'Quarter two does not reconcile with the signed sheet.',
        );

        state = state.openSuccessorDraft(nPlusOne);
        expect(state.workflowVersion, 4);
        expect(state.submittedRevision!.hasSameIdentity(n), isTrue);
        expect(state.activeRevision!.hasSameIdentity(nPlusOne), isTrue);
        expect(state.deliveryState, JournalDeliveryState.savedOnDevice);
        state = _acceptActiveRevision(state);

        final resubmit = _command(
          id: 'resubmit_n_plus_1',
          type: CandidateReviewCommandType.resubmit,
          version: 4,
          target: n,
          successor: nPlusOne,
          reasonCode: 'score_evidence_corrected',
          reason: 'Reconciled quarter two against the signed sheet.',
        );
        state = state.apply(resubmit);
        expect(state.reviewState, CandidateReviewState.resubmitted);
        expect(state.submittedRevision!.hasSameIdentity(nPlusOne), isTrue);

        final afterRetry = state.apply(resubmit);
        expect(identical(afterRetry, state), isTrue);
        expect(afterRetry.events.length, 4);

        state = state.apply(
          _command(
            id: 'review_n_plus_1',
            type: CandidateReviewCommandType.beginReview,
            version: 5,
            target: nPlusOne,
          ),
        );
        final stale = _workflowError(
          () => state.apply(
            _command(
              id: 'approve_stale_n',
              type: CandidateReviewCommandType.approve,
              version: 6,
              target: n,
            ),
          ),
        );
        expect(stale.code, 'staleRevision');

        state = state.apply(
          _command(
            id: 'approve_n_plus_1',
            type: CandidateReviewCommandType.approve,
            version: 6,
            target: nPlusOne,
          ),
        );
        expect(state.reviewState, CandidateReviewState.approved);
        expect(state.workflowVersion, 7);
        expect(
          state.events.last.targetRevision.hasSameIdentity(nPlusOne),
          true,
        );
      },
    );

    test('changed reuse of a command ID rejects as payload conflict', () {
      final revision = _revision(1, 'c');
      var state = CandidateStatsWorkflow.preparing(
        scope: _scope(),
        playState: PlayState.completed,
      ).openDraft(revision: revision, captureMode: CaptureMode.officialSheet);
      state = _acceptActiveRevision(state);
      state = state.apply(
        _command(
          id: 'submit_once',
          type: CandidateReviewCommandType.submit,
          version: 0,
          target: revision,
        ),
      );

      final conflict = _workflowError(
        () => state.apply(
          _command(
            id: 'submit_once',
            type: CandidateReviewCommandType.beginReview,
            version: 1,
            target: revision,
          ),
        ),
      );
      expect(conflict.code, 'payloadKeyConflict');
      expect(state.events, hasLength(1));
    });

    test('submission cannot treat saved-on-device as server acceptance', () {
      final revision = _revision(1, 'd');
      final state = CandidateStatsWorkflow.preparing(
        scope: _scope(),
        playState: PlayState.completed,
      ).openDraft(revision: revision, captureMode: CaptureMode.officialSheet);
      final error = _workflowError(
        () => state.apply(
          _command(
            id: 'submit_without_receipt',
            type: CandidateReviewCommandType.submit,
            version: 0,
            target: revision,
          ),
        ),
      );
      expect(error.code, 'unacceptedJournalHead');
    });

    test('submitter cannot approve their own revision', () {
      final revision = _revision(1, 'f');
      var state = CandidateStatsWorkflow.preparing(
        scope: _scope(),
        playState: PlayState.completed,
      ).openDraft(revision: revision, captureMode: CaptureMode.officialSheet);
      state = _acceptActiveRevision(state);
      state = state.apply(
        _command(
          id: 'self_submit',
          type: CandidateReviewCommandType.submit,
          version: 0,
          target: revision,
        ),
      );
      state = state.apply(
        _command(
          id: 'self_review',
          type: CandidateReviewCommandType.beginReview,
          version: 1,
          target: revision,
        ),
      );
      final denied = _workflowError(
        () => state.apply(
          CandidateReviewCommand(
            commandId: 'self_approve',
            type: CandidateReviewCommandType.approve,
            actorAccountId: 'statistician_1',
            expectedWorkflowVersion: 2,
            targetRevision: revision,
          ),
        ),
      );
      expect(denied.code, 'separationOfDutiesDenied');
    });

    test('post-game draft requires an explicit completed play state', () {
      final state = CandidateStatsWorkflow.preparing(scope: _scope());
      final error = _workflowError(
        () => state.openDraft(
          revision: _revision(1, 'e'),
          captureMode: CaptureMode.officialSheet,
        ),
      );
      expect(error.code, 'playStateMismatch');
    });

    test('live draft keeps play and review states separate', () {
      final revision = _revision(1, '9');
      final state = CandidateStatsWorkflow.preparing(
        scope: _scope(),
        playState: PlayState.inProgress,
      ).openDraft(revision: revision, captureMode: CaptureMode.liveCapture);
      expect(state.playState, PlayState.inProgress);
      expect(state.captureStage, CandidateCaptureStage.liveDraft);
      expect(state.reviewState, CandidateReviewState.draft);
      expect(state.deliveryState, JournalDeliveryState.savedOnDevice);

      final accepted = _acceptActiveRevision(state);
      final error = _workflowError(
        () => accepted.apply(
          _command(
            id: 'submit_midgame',
            type: CandidateReviewCommandType.submit,
            version: 0,
            target: revision,
          ),
        ),
      );
      expect(error.code, 'playNotComplete');
    });
  });

  group('explicit workflow-state queue', () {
    StatsWorkItem item({
      required PlayState play,
      CandidateReviewState review = CandidateReviewState.draft,
      bool assigned = true,
    }) => StatsWorkItem(
      gameId: 'game_1',
      isAssigned: assigned,
      playState: play,
      captureStage: CandidateCaptureStage.preparation,
      reviewState: review,
    );

    test('scheduled work stays in preparation even if its date is old', () {
      expect(
        item(play: PlayState.scheduled).queueSection,
        StatsWorkQueueSection.preparation,
      );
    });

    test('completed work needs stats regardless of its scheduled date', () {
      expect(
        item(play: PlayState.completed).queueSection,
        StatsWorkQueueSection.needsStats,
      );
    });

    test('review and correction sections are explicit', () {
      expect(
        item(
          play: PlayState.completed,
          review: CandidateReviewState.changesRequested,
        ).queueSection,
        StatsWorkQueueSection.changesRequested,
      );
      expect(
        item(
          play: PlayState.completed,
          review: CandidateReviewState.resubmitted,
        ).queueSection,
        StatsWorkQueueSection.awaitingReview,
      );
      expect(
        item(
          play: PlayState.completed,
          review: CandidateReviewState.approved,
        ).queueSection,
        StatsWorkQueueSection.complete,
      );
    });

    test('unassigned and cancelled games are not actionable', () {
      expect(
        item(play: PlayState.completed, assigned: false).queueSection,
        StatsWorkQueueSection.notActionable,
      );
      expect(
        item(play: PlayState.cancelled).queueSection,
        StatsWorkQueueSection.notActionable,
      );
    });
  });
}
