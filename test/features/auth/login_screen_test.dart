import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/auth/login_auth_actions.dart';
import 'package:hoops_connect/features/auth/login_screen.dart';

void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(375, 844),
    _FakeLoginAuthActions? auth,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginAuthActionsProvider.overrideWithValue(
            auth ?? _FakeLoginAuthActions(),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: textScaler),
            child: const LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the real sign-in screen with useful semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpLogin(tester);

    expect(find.text('Jamaica HoopsConnect'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Jamaica Basketball Association logo'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('login-email-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(_editable(tester, const Key('login-password-field')).autofillHints, [
      AutofillHints.password,
    ]);
    expect(find.text('Browse scores & schedule as a guest'), findsOneWidget);

    final headingSemantics = tester.getSemantics(
      find.text('Jamaica HoopsConnect'),
    );
    expect(headingSemantics.flagsCollection.isHeader, isTrue);
    semantics.dispose();
  });

  testWidgets('Return in password submits once and exposes pending state', (
    tester,
  ) async {
    final pending = Completer<void>();
    final auth = _FakeLoginAuthActions()..signInPending = pending;
    await pumpLogin(tester, auth: auth);

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      ' member@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'correct horse',
    );
    await tester.showKeyboard(find.byKey(const Key('login-password-field')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(auth.signInSubmissions, [
      (email: 'member@example.com', password: 'correct horse'),
    ]);
    expect(find.text('Signing in'), findsOneWidget);
    expect(find.bySemanticsLabel('Signing in'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.signInSubmissions, hasLength(1));

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sign In'), findsNWidgets(2));
  });

  testWidgets('field actions move focus in the expected order', (tester) async {
    await pumpLogin(tester);

    await tester.showKeyboard(find.byKey(const Key('login-email-field')));
    expect(
      _editable(tester, const Key('login-email-field')).focusNode.hasFocus,
      isTrue,
    );

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      _editable(tester, const Key('login-password-field')).focusNode.hasFocus,
      isTrue,
    );

    await tester.tap(find.text('Create Account').first);
    await tester.pump();
    expect(
      _editable(tester, const Key('login-name-field')).focusNode.hasFocus,
      isTrue,
    );

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      _editable(tester, const Key('login-email-field')).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('auth mode controls support keyboard activation', (tester) async {
    await pumpLogin(tester);

    final createAccount = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('login-mode-create-account')),
        matching: find.byType(InkWell),
      ),
    );
    createAccount.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(find.byKey(const Key('login-name-field')), findsOneWidget);
    final createModeSemantics = tester.getSemantics(
      find.byKey(const Key('login-mode-create-account')),
    );
    expect(createModeSemantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(
      createModeSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    final material = tester.widget<Material>(
      find.byKey(const Key('login-mode-create-account')),
    );
    expect((material.shape! as RoundedRectangleBorder).side.width, 3);
  });

  testWidgets('create-account mode uses new-password autofill and sign-up', (
    tester,
  ) async {
    final auth = _FakeLoginAuthActions();
    await pumpLogin(tester, auth: auth);

    await tester.tap(find.text('Create Account').first);
    await tester.pump();
    expect(_editable(tester, const Key('login-password-field')).autofillHints, [
      AutofillHints.newPassword,
    ]);

    await tester.enterText(
      find.byKey(const Key('login-name-field')),
      'Member Name',
    );
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'new password',
    );
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(auth.signInSubmissions, isEmpty);
    expect(auth.signUpSubmissions, [
      (
        email: 'member@example.com',
        password: 'new password',
        displayName: 'Member Name',
      ),
    ]);
  });

  testWidgets('validation and transport errors are rendered and announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final auth = _FakeLoginAuthActions()
      ..signInError = Exception('[firebase_auth/wrong-password] rejected');
    await pumpLogin(tester, auth: auth);

    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password'), findsOneWidget);
    expect(
      find.bySemanticsLabel('We could not sign you in. Incorrect password'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'corrected',
    );
    await tester.pump();
    expect(find.text('Incorrect password'), findsNothing);
    semantics.dispose();
  });

  testWidgets('phone, desktop, dark mode, and large text remain usable', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      theme: AppTheme.dark,
      size: const Size(1440, 1000),
      textScaler: const TextScaler.linear(1.5),
    );

    final contentSize = tester.getSize(
      find.byKey(const Key('login-form-content')),
    );
    expect(contentSize.width, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);

    final heading = tester.widget<Text>(find.text('Jamaica HoopsConnect'));
    expect(heading.style?.color, AppTheme.dark.colorScheme.onSurface);
    expect(
      _contrastRatio(
        heading.style!.color!,
        AppTheme.dark.scaffoldBackgroundColor,
      ),
      greaterThanOrEqualTo(4.5),
    );

    await pumpLogin(tester, size: const Size(375, 844));
    expect(
      tester.getSize(find.byKey(const Key('login-form-content'))).width,
      lessThanOrEqualTo(375 - 48),
    );
    expect(tester.takeException(), isNull);
  });
}

class _FakeLoginAuthActions implements LoginAuthActions {
  final signInSubmissions = <({String email, String password})>[];
  final signUpSubmissions =
      <({String email, String password, String displayName})>[];
  Completer<void>? signInPending;
  Object? signInError;
  int googleSignIns = 0;
  int appleSignIns = 0;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInSubmissions.add((email: email, password: password));
    if (signInError case final error?) throw error;
    await signInPending?.future;
  }

  @override
  Future<void> signUpFan({
    required String email,
    required String password,
    required String displayName,
  }) async {
    signUpSubmissions.add((
      email: email,
      password: password,
      displayName: displayName,
    ));
  }

  @override
  Future<void> signInWithApple() async {
    appleSignIns++;
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignIns++;
  }
}

EditableText _editable(WidgetTester tester, Key fieldKey) {
  return tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(EditableText),
    ),
  );
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}
