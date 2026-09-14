import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/constants/app_constants.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';

void main() {
  test('light theme retains JBA green with accessible foreground', () {
    final theme = AppTheme.light;
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(
      _contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.extension<AppSemanticColors>(), isNotNull);
  });

  test('dark theme derives readable controls and semantic states', () {
    final theme = AppTheme.dark;
    final semantic = theme.extension<AppSemanticColors>()!;

    expect(theme.brightness, Brightness.dark);
    expect(
      _contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(semantic.onSuccessContainer, semantic.successContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(semantic.onWarningContainer, semantic.warningContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('high contrast variants strengthen the Material contrast level', () {
    final light = AppTheme.highContrastLight;
    final dark = AppTheme.highContrastDark;

    expect(light.colorScheme.primary, isNot(light.colorScheme.surface));
    expect(dark.brightness, Brightness.dark);
    expect(
      _contrastRatio(dark.colorScheme.onSurface, dark.colorScheme.surface),
      greaterThanOrEqualTo(7),
    );
  });

  testWidgets('semantic colors have a safe fallback in an embedded theme', (
    tester,
  ) async {
    AppSemanticColors? observed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            observed = context.semanticColors;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(observed, isNotNull);
    expect(observed!.successContainer, isNot(observed!.onSuccessContainer));
  });
}

double _contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
