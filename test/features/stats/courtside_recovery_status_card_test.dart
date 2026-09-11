import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/widgets/courtside_recovery_status_card.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/services/local_game_journal/courtside_recovery.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';

CourtsideRecoverySnapshot _snapshot({
  CourtsideRecoveryPhase phase = CourtsideRecoveryPhase.ready,
  JournalDeliveryState state = JournalDeliveryState.savedOnDevice,
  bool responseUnknown = false,
  LocalWorkspaceRecoveryState recoveryState =
      LocalWorkspaceRecoveryState.active,
  WorkspaceSubmissionState submissionState =
      WorkspaceSubmissionState.captureOpen,
}) => CourtsideRecoverySnapshot(
  phase: phase,
  operations: [
    CourtsideOperationStatus(
      operationId: 'operation_1',
      commandId: 'command_1',
      localSequence: 0,
      state: state,
      responseUnknown: responseUnknown,
      lastErrorCode: state == JournalDeliveryState.needsAttention
          ? 'assignmentRequired'
          : null,
      pauseReason: state == JournalDeliveryState.needsAttention
          ? 'operatorResolutionRequired'
          : null,
    ),
  ],
  captureAvailability: LocalCaptureAvailability.ready,
  workspaceRecoveryState: recoveryState,
  workspaceSubmissionState: submissionState,
  lastFailureCode: null,
);

Widget _app({
  required CourtsideRecoverySnapshot snapshot,
  VoidCallback? onRecover,
  ValueChanged<String>? onRetry,
  bool includeTextField = false,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        if (includeTextField) const TextField(key: ValueKey('stat-note-field')),
        CourtsideRecoveryStatusCard(
          snapshot: snapshot,
          onRecoverForeground: onRecover,
          onRetryOperation: onRetry,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('shows distinct local states and an honest closed-PWA boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        snapshot: _snapshot(
          state: JournalDeliveryState.queued,
          responseUnknown: true,
        ),
      ),
    );

    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.text('On device: 0'), findsOneWidget);
    expect(find.text('Queued: 1'), findsOneWidget);
    expect(find.text('Sending: 0'), findsOneWidget);
    expect(find.text('Accepted: 0'), findsOneWidget);
    expect(find.text('Needs attention: 0'), findsOneWidget);
    expect(find.textContaining('response unknown'), findsOneWidget);
    expect(
      find.textContaining('Closing the web app stops delivery'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        snapshot: _snapshot(
          state: JournalDeliveryState.accepted,
          submissionState: WorkspaceSubmissionState.submitted,
        ),
      ),
    );
    expect(find.text('Revision delivery accepted'), findsOneWidget);
    expect(find.textContaining('exact durable receipt'), findsOneWidget);
  });

  testWidgets('buttons are focus-driven and never fire while typing', (
    tester,
  ) async {
    var recoveries = 0;
    String? retriedOperation;
    await tester.pumpWidget(
      _app(
        snapshot: _snapshot(
          phase: CourtsideRecoveryPhase.needsAttention,
          state: JournalDeliveryState.needsAttention,
        ),
        includeTextField: true,
        onRecover: () => recoveries++,
        onRetry: (operationId) => retriedOperation = operationId,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('stat-note-field')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(recoveries, 0);
    expect(retriedOperation, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(recoveries, 1);
    expect(retriedOperation, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(retriedOperation, 'operation_1');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(recoveries, 2);
  });

  testWidgets('writer conflict preserves work without offering unsafe retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        snapshot: _snapshot(
          phase: CourtsideRecoveryPhase.needsAttention,
          state: JournalDeliveryState.needsAttention,
          recoveryState: LocalWorkspaceRecoveryState.conflictBranch,
        ),
        onRetry: (_) {},
      ),
    );

    expect(find.text('Writer conflict needs attention'), findsOneWidget);
    expect(find.textContaining('branch is preserved'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('courtside-retry-operation')),
      findsNothing,
    );
  });
}
