import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/auth/login_screen.dart';

void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(375, 844),
    LoginEmailPasswordHandler? onSubmit,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: textScaler),
            child: LoginScreen(onEmailPasswordSubmit: onSubmit),
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
    final submissions = <({String email, String password, String? name})>[];
    await pumpLogin(
      tester,
      onSubmit: ({required email, required password, displayName}) {
        submissions.add((email: email, password: password, name: displayName));
        return pending.future;
      },
    );

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

    expect(submissions, [
      (email: 'member@example.com', password: 'correct horse', name: null),
    ]);
    expect(find.text('Signing in'), findsOneWidget);
    expect(find.bySemanticsLabel('Signing in'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submissions, hasLength(1));

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
      find.byKey(const Key('login-mode-create-account')),
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
  });

  testWidgets('validation and transport errors are rendered and announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpLogin(
      tester,
      onSubmit: ({required email, required password, displayName}) async {
        throw Exception('[firebase_auth/wrong-password] rejected');
      },
    );

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
