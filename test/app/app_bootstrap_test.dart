import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/app_bootstrap.dart';

void main() {
  testWidgets(
    'shows a Flutter startup screen before initialization completes',
    (tester) async {
      final initialization = Completer<void>();

      await tester.pumpWidget(
        AppBootstrap(
          initialize: () => initialization.future,
          child: const MaterialApp(home: Text('App ready')),
        ),
      );

      expect(find.text('Starting HoopsConnect'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('App ready'), findsNothing);

      initialization.complete();
      await tester.pumpAndSettle();

      expect(find.text('App ready'), findsOneWidget);
      expect(find.text('Starting HoopsConnect'), findsNothing);
    },
  );

  testWidgets('continues into the app when initialization times out', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppBootstrap(
        initialize: () => Completer<void>().future,
        timeout: const Duration(milliseconds: 25),
        child: const MaterialApp(home: Text('App ready')),
      ),
    );

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.text('App ready'), findsOneWidget);
  });
}
