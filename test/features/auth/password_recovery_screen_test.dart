import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/app/router/app_route_contract.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/auth/password_recovery_screen.dart';

void main() {
  Future<void> pumpRecovery(
    WidgetTester tester, {
    _FakeRecoveryActions? actions,
    String? email,
  }) async {
    final router = GoRouter(
      initialLocation: Uri(
        path: AppRouteContract.passwordRecovery,
        queryParameters: email == null ? null : {'email': email},
      ).toString(),
      routes: [
        GoRoute(
          path: AppRouteContract.passwordRecovery,
          builder: (_, state) => PasswordRecoveryScreen(
            initialEmail: state.uri.queryParameters['email'],
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passwordRecoveryActionsProvider.overrideWithValue(
            actions ?? _FakeRecoveryActions(),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('prefills email and Return submits once while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final actions = _FakeRecoveryActions()..pending = pending;
    await pumpRecovery(tester, actions: actions, email: ' member@example.com ');

    expect(find.text('member@example.com'), findsOneWidget);
    await tester.showKeyboard(find.byKey(const Key('recovery-email-field')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(actions.emails, ['member@example.com']);
    expect(find.text('Sending reset link'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(actions.emails, hasLength(1));

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('If an email account matches'), findsOneWidget);
  });

  testWidgets('failure keeps input and does not expose provider internals', (
    tester,
  ) async {
    final actions = _FakeRecoveryActions()
      ..error = Exception('project-secret-provider-detail');
    await pumpRecovery(tester, actions: actions);

    await tester.enterText(
      find.byKey(const Key('recovery-email-field')),
      'member@example.com',
    );
    await tester.tap(find.byKey(const Key('recovery-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('member@example.com'), findsOneWidget);
    expect(find.textContaining('project-secret-provider-detail'), findsNothing);
    expect(find.text('We could not send the reset link'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recovery-email-field')),
      'corrected@example.com',
    );
    await tester.pump();
    expect(find.text('We could not send the reset link'), findsNothing);
  });

  testWidgets('invalid email is rejected before transport', (tester) async {
    final actions = _FakeRecoveryActions();
    await pumpRecovery(tester, actions: actions);
    await tester.enterText(
      find.byKey(const Key('recovery-email-field')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('recovery-submit-button')));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(actions.emails, isEmpty);
  });
}

class _FakeRecoveryActions implements PasswordRecoveryActions {
  final emails = <String>[];
  Completer<void>? pending;
  Object? error;

  @override
  Future<void> sendResetEmail(String email) async {
    emails.add(email);
    if (error case final value?) throw value;
    await pending?.future;
  }
}
