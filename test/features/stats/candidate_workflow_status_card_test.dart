import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/widgets/candidate_workflow_status_card.dart';
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

CandidateRevisionReference _revision() => CandidateRevisionReference(
  revisionId: 'revision_1',
  revisionNumber: 1,
  revisionHash: List.filled(64, 'a').join(),
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
    expect(find.textContaining('Revision 1'), findsOneWidget);
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
}
