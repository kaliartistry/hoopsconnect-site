import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/core/widgets/app_constrained_content.dart';
import 'package:hoops_connect/core/widgets/app_form_controls.dart';
import 'package:hoops_connect/core/widgets/app_state_message.dart';

void main() {
  Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('state messages announce content and retain action semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var retried = false;

    await tester.pumpWidget(
      host(
        AppStateMessage(
          title: 'Could not load games',
          message: 'Check your connection and try again.',
          tone: AppStateTone.error,
          actionLabel: 'Try Again',
          onAction: () => retried = true,
        ),
        theme: AppTheme.dark,
      ),
    );

    expect(
      find.bySemanticsLabel(
        'Could not load games. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Try Again'),
    );
    final actionColor = action.style!.foregroundColor!.resolve({})!;
    expect(actionColor, AppTheme.dark.colorScheme.onErrorContainer);
    expect(
      _contrastRatio(actionColor, AppTheme.dark.colorScheme.errorContainer),
      greaterThanOrEqualTo(4.5),
    );
    semantics.dispose();
  });

  testWidgets('enabled async action exposes its tap semantics action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(
      host(
        AppAsyncActionButton(label: 'Submit stats', onPressed: () => calls++),
      ),
    );

    final node = tester.getSemantics(find.byType(AppAsyncActionButton));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.byType(AppAsyncActionButton));
    expect(calls, 1);
    semantics.dispose();
  });

  testWidgets('async action prevents duplicates and names pending state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;

    await tester.pumpWidget(
      host(
        AppAsyncActionButton(
          label: 'Submit stats',
          busyLabel: 'Submitting stats',
          isBusy: true,
          onPressed: () => calls++,
        ),
      ),
    );

    expect(find.bySemanticsLabel('Submitting stats'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(calls, 0);
    semantics.dispose();
  });

  testWidgets('disabled action explains why it is unavailable', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        const AppAsyncActionButton(
          label: 'Start game',
          onPressed: null,
          disabledHint: 'Select five starters for each team',
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(AppAsyncActionButton));
    expect(node.label, 'Start game');
    expect(node.hint, 'Select five starters for each team');
    semantics.dispose();
  });

  testWidgets('form focus group supports Escape cancellation', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      host(
        AppFormFocusGroup(
          onCancel: () => cancelled = true,
          child: const TextField(autofocus: true),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, isTrue);
  });

  testWidgets('constrained content stays readable on wide screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        const AppConstrainedContent(
          maxWidth: 600,
          child: SizedBox(key: Key('content'), height: 100),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('content'))).width, 600);
  });

  testWidgets('loading state has a live accessible name', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const AppLoadingState(label: 'Loading standings')),
    );
    expect(find.bySemanticsLabel('Loading standings'), findsOneWidget);
    semantics.dispose();
  });
}

double _contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
