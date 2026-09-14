import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/ack/widgets/acknowledgment_action.dart';

void main() {
  testWidgets('pending state prevents duplicate acknowledgment calls', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AcknowledgmentAction(
            onAcknowledge: () {
              calls += 1;
              return completion.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Acknowledge This Post'));
    await tester.pump();

    expect(find.text('Recording acknowledgment'), findsOneWidget);
    expect(calls, 1);

    await tester.tap(
      find.text('Recording acknowledgment'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, 1);

    completion.complete();
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgment recorded'), findsOneWidget);
    expect(find.textContaining('admin'), findsNothing);
  });

  testWidgets('failure is honest and retryable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AcknowledgmentAction(
            onAcknowledge: () async {
              calls += 1;
              if (calls == 1) throw StateError('UNAVAILABLE');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Acknowledge This Post'));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgment not recorded'), findsOneWidget);
    expect(
      find.text('Service temporarily unavailable. Please try again'),
      findsOneWidget,
    );
    expect(find.text('Retry acknowledgment'), findsOneWidget);

    await tester.tap(find.text('Retry acknowledgment'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Acknowledgment recorded'), findsOneWidget);
  });
}
