import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/widgets/candidate_workflow_status_card.dart';
import 'package:hoops_connect/models/official_stats/candidate_review_workflow.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';

GameScope _scope() => GameScope(
  associationId: 'jba',
  competitionId: 'nbl',
  seasonId: 'season_2026',
  divisionId: 'division_1',
  phaseId: 'regular',
  gameId: 'game_1',
);

CandidateRevisionReference _revision({
  int number = 1,
  String hashCharacter = 'a',
  String? predecessorId,
}) => CandidateRevisionReference(
  scope: _scope(),
  revisionId: 'revision_$number',
  revisionNumber: number,
  revisionHash: List.filled(64, hashCharacter).join(),
  supersedesRevisionId: number == 1
      ? const Fact.notApplicable(reasonCode: 'no_predecessor')
      : Fact.known(predecessorId ?? 'revision_${number - 1}'),
);

Widget _app(CandidateStatsWorkflow workflow, {VoidCallback? onRetry}) =>
    MaterialApp(
      home: Scaffold(
        body: CandidateWorkflowStatusCard(
          workflow: workflow,
          onRetryDelivery: onRetry,
        ),
      ),
    );

void main() {
  testWidgets('preparation does not claim nonexistent work is saved', (
    tester,
  ) async {
    final workflow = CandidateStatsWorkflow.preparing(scope: _scope());

    await tester.pumpWidget(_app(workflow));

    expect(find.text('Preparing game package'), findsOneWidget);
    expect(find.text('Not ready for review'), findsOneWidget);
    expect(find.textContaining('No stat revision exists yet'), findsOneWidget);
    expect(find.textContaining('create and seal a revision'), findsOneWidget);
    expect(find.text('Saved on this device'), findsNothing);
    expect(find.text('Queued for upload'), findsNothing);
  });

  testWidgets('states saved-on-device separately from review status', (
    tester,
  ) async {
    final workflow = CandidateStatsWorkflow.preparing(
      scope: _scope(),
      playState: PlayState.completed,
    ).openDraft(revision: _revision(), captureMode: CaptureMode.officialSheet);

    await tester.pumpWidget(_app(workflow));

    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('Draft, not submitted'), findsOneWidget);
    expect(find.textContaining('not uploaded yet'), findsOneWidget);
    expect(find.textContaining('Revision 1'), findsNWidgets(2));
  });

  testWidgets('needs-attention copy preserves work and offers retry', (
    tester,
  ) async {
    var retries = 0;
    final workflow =
        CandidateStatsWorkflow.preparing(
              scope: _scope(),
              playState: PlayState.completed,
            )
            .openDraft(
              revision: _revision(),
              captureMode: CaptureMode.officialSheet,
            )
            .withDeliveryState(JournalDeliveryState.needsAttention);

    await tester.pumpWidget(_app(workflow, onRetry: () => retries += 1));

    expect(find.text('Upload needs attention'), findsOneWidget);
    expect(find.textContaining('preserved on this device'), findsOneWidget);
    await tester.tap(find.text('Try upload again'));
    expect(retries, 1);
  });

  testWidgets('correction shows reviewed N and delivered active N+1', (
    tester,
  ) async {
    final n = _revision();
    final nPlusOne = _revision(
      number: 2,
      hashCharacter: 'b',
      predecessorId: n.revisionId,
    );
    var workflow = CandidateStatsWorkflow.preparing(
      scope: _scope(),
      playState: PlayState.completed,
    ).openDraft(revision: n, captureMode: CaptureMode.officialSheet);
    workflow = workflow
        .withDeliveryState(JournalDeliveryState.queued)
        .withDeliveryState(JournalDeliveryState.sending)
        .withDeliveryState(JournalDeliveryState.accepted)
        .apply(
          CandidateReviewCommand(
            commandId: 'submit_n',
            type: CandidateReviewCommandType.submit,
            actorAccountId: 'statistician_1',
            expectedWorkflowVersion: 0,
            targetRevision: n,
          ),
        )
        .apply(
          CandidateReviewCommand(
            commandId: 'send_back_n',
            type: CandidateReviewCommandType.requestChanges,
            actorAccountId: 'reviewer_1',
            expectedWorkflowVersion: 1,
            targetRevision: n,
            reasonCode: 'period_score_mismatch',
            reason: 'Quarter two must match the signed sheet.',
          ),
        )
        .openSuccessorDraft(nPlusOne)
        .withDeliveryState(JournalDeliveryState.queued)
        .withDeliveryState(JournalDeliveryState.sending)
        .withDeliveryState(JournalDeliveryState.accepted);

    await tester.pumpWidget(_app(workflow));

    expect(find.text('Accepted by the server'), findsOneWidget);
    expect(find.textContaining('Revision 2 · revision_2'), findsNWidgets(2));
    expect(
      find.textContaining('Feedback targets Revision 1 · revision_1'),
      findsOneWidget,
    );
    expect(find.textContaining('Quarter two must match'), findsOneWidget);
  });
}
