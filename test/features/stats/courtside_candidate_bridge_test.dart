import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/courtside_candidate_bridge.dart';
import 'package:hoops_connect/models/official_stats/candidate_review_workflow.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/courtside_recovery.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';

GameScope _scope({String gameId = 'game_1'}) => GameScope(
  associationId: 'jba',
  competitionId: 'nbl',
  seasonId: 'season_2026',
  divisionId: 'division_1',
  phaseId: 'regular',
  gameId: gameId,
);

CandidateRevisionReference _revision(int number, {String? predecessor}) =>
    CandidateRevisionReference(
      scope: _scope(),
      revisionId: 'revision_$number',
      revisionNumber: number,
      revisionHash: List.filled(64, number == 1 ? 'a' : 'b').join(),
      supersedesRevisionId: number == 1
          ? const Fact.notApplicable(reasonCode: 'no_predecessor')
          : Fact.known(predecessor!),
    );

CourtsideRecoverySnapshot _acceptedSnapshot() => CourtsideRecoverySnapshot(
  phase: CourtsideRecoveryPhase.ready,
  operations: const [
    CourtsideOperationStatus(
      operationId: 'operation_1',
      commandId: 'command_1',
      localSequence: 0,
      state: JournalDeliveryState.accepted,
      responseUnknown: false,
      lastErrorCode: null,
      pauseReason: null,
    ),
  ],
  captureAvailability: LocalCaptureAvailability.ready,
  workspaceRecoveryState: LocalWorkspaceRecoveryState.active,
  workspaceSubmissionState: WorkspaceSubmissionState.submitted,
  lastFailureCode: null,
);

void main() {
  test('exact N and N+1 bridges preserve revision review identity', () {
    final n = _revision(1);
    final nPlusOne = _revision(2, predecessor: n.revisionId);
    var workflow = CandidateStatsWorkflow.preparing(
      scope: _scope(),
      playState: PlayState.completed,
    ).openDraft(revision: n, captureMode: CaptureMode.officialSheet);

    workflow = CourtsideCandidateBridge(
      revision: n,
    ).synchronize(workflow, _acceptedSnapshot());
    expect(workflow.deliveryState, JournalDeliveryState.accepted);
    expect(workflow.acceptedDeliveryRevision!.revisionId, n.revisionId);
    workflow = workflow.apply(
      CandidateReviewCommand(
        commandId: 'submit_n',
        type: CandidateReviewCommandType.submit,
        actorAccountId: 'statistician_1',
        expectedWorkflowVersion: 0,
        targetRevision: n,
      ),
    );
    workflow = workflow.apply(
      CandidateReviewCommand(
        commandId: 'changes_n',
        type: CandidateReviewCommandType.requestChanges,
        actorAccountId: 'reviewer_1',
        expectedWorkflowVersion: 1,
        targetRevision: n,
        reasonCode: 'sheet_mismatch',
        reason: 'Quarter two needs correction.',
      ),
    );
    workflow = workflow.openSuccessorDraft(nPlusOne);
    expect(workflow.deliveryState, JournalDeliveryState.savedOnDevice);

    workflow = CourtsideCandidateBridge(
      revision: nPlusOne,
    ).synchronize(workflow, _acceptedSnapshot());
    expect(workflow.acceptedDeliveryRevision!.revisionId, nPlusOne.revisionId);
    workflow = workflow.apply(
      CandidateReviewCommand(
        commandId: 'resubmit_n_plus_1',
        type: CandidateReviewCommandType.resubmit,
        actorAccountId: 'statistician_1',
        expectedWorkflowVersion: 3,
        targetRevision: n,
        successorRevision: nPlusOne,
        reasonCode: 'sheet_corrected',
        reason: 'Corrected against the signed sheet.',
      ),
    );
    workflow = workflow.apply(
      CandidateReviewCommand(
        commandId: 'review_n_plus_1',
        type: CandidateReviewCommandType.beginReview,
        actorAccountId: 'reviewer_1',
        expectedWorkflowVersion: 4,
        targetRevision: nPlusOne,
      ),
    );

    expect(
      () => workflow.apply(
        CandidateReviewCommand(
          commandId: 'stale_approval_n',
          type: CandidateReviewCommandType.approve,
          actorAccountId: 'reviewer_1',
          expectedWorkflowVersion: 5,
          targetRevision: n,
        ),
      ),
      throwsA(
        isA<CandidateWorkflowException>().having(
          (error) => error.code,
          'code',
          'staleRevision',
        ),
      ),
    );
    workflow = workflow.apply(
      CandidateReviewCommand(
        commandId: 'approve_n_plus_1',
        type: CandidateReviewCommandType.approve,
        actorAccountId: 'reviewer_1',
        expectedWorkflowVersion: 5,
        targetRevision: nPlusOne,
      ),
    );
    expect(workflow.reviewState, CandidateReviewState.approved);
    expect(workflow.submittedRevision!.revisionId, nPlusOne.revisionId);
  });

  test('bridge refuses a different active revision or scope', () {
    final n = _revision(1);
    final other = CandidateRevisionReference(
      scope: _scope(gameId: 'game_2'),
      revisionId: 'revision_other',
      revisionNumber: 1,
      revisionHash: List.filled(64, 'c').join(),
      supersedesRevisionId: const Fact.notApplicable(
        reasonCode: 'no_predecessor',
      ),
    );
    final workflow = CandidateStatsWorkflow.preparing(
      scope: _scope(),
      playState: PlayState.completed,
    ).openDraft(revision: n, captureMode: CaptureMode.officialSheet);

    expect(
      () => CourtsideCandidateBridge(
        revision: other,
      ).synchronize(workflow, _acceptedSnapshot()),
      throwsA(
        isA<CandidateWorkflowException>().having(
          (error) => error.code,
          'code',
          'courtsideRevisionMismatch',
        ),
      ),
    );
  });
}
