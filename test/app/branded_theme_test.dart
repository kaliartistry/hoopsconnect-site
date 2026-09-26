import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/branded_theme.dart';
import 'package:hoops_connect/core/constants/app_constants.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/models/association_branding_model.dart';

void main() {
  const mediumBrand = AssociationBrandingModel(
    associationId: 'medium',
    leagueName: 'Medium Brand League',
    shortName: 'Medium',
    primaryColorHex: '#5B8C00',
    secondaryColorHex: '#8B5E00',
    accentColorHex: '#6C63C7',
  );
  const darkBrand = AssociationBrandingModel(
    associationId: 'dark',
    leagueName: 'Dark Brand League',
    shortName: 'Dark',
    primaryColorHex: '#123A2A',
    secondaryColorHex: '#171717',
    accentColorHex: '#4A235A',
  );
  const paleBrand = AssociationBrandingModel(
    associationId: 'pale',
    leagueName: 'Pale Brand League',
    shortName: 'Pale',
    primaryColorHex: '#EEEEEE',
    secondaryColorHex: '#F5F5F5',
    accentColorHex: '#E8E8E8',
  );

  test('ordinary light branding preserves royal product chrome', () {
    final theme = buildBrandedTheme(AppTheme.light, mediumBrand);

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(
      theme.colorScheme.onPrimary,
      highestContrastForeground(AppColors.primary),
    );
    expect(theme.colorScheme.secondary, AppColors.accent);
    expect(
      theme.colorScheme.onSecondary,
      highestContrastForeground(AppColors.accent),
    );
    expect(theme.appBarTheme.backgroundColor, AppColors.primary);
    expect(
      theme.appBarTheme.foregroundColor,
      highestContrastForeground(AppColors.primary),
    );
    expect(
      contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(theme.colorScheme.onSecondary, theme.colorScheme.secondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(
        theme.appBarTheme.foregroundColor!,
        theme.appBarTheme.backgroundColor!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    final outlinedForeground = theme.outlinedButtonTheme.style!.foregroundColor!
        .resolve(const <WidgetState>{});
    expect(
      contrastRatio(outlinedForeground!, theme.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('JBA artwork colors do not take over product chrome', () {
    final branding = AssociationBrandingModel.jba();
    final light = buildBrandedTheme(AppTheme.light, branding);
    final dark = buildBrandedTheme(AppTheme.dark, branding);
    final highContrastDark = buildBrandedTheme(
      AppTheme.highContrastDark,
      branding,
      highContrast: true,
    );

    expect(light.colorScheme.primary, AppColors.primary);
    expect(light.colorScheme.primary, isNot(branding.primaryColor));
    expect(dark.colorScheme.primary, isNot(branding.primaryColor));
    expect(highContrastDark.colorScheme.primary, isNot(branding.primaryColor));
  });

  test('all branded variants retain semantic colors and readable controls', () {
    final fixtures = <AssociationBrandingModel>[
      AssociationBrandingModel.jba(),
      mediumBrand,
      darkBrand,
    ];

    for (final branding in fixtures) {
      final variants = <ThemeData>[
        buildBrandedTheme(AppTheme.light, branding),
        buildBrandedTheme(AppTheme.dark, branding),
        buildBrandedTheme(
          AppTheme.highContrastLight,
          branding,
          highContrast: true,
        ),
        buildBrandedTheme(
          AppTheme.highContrastDark,
          branding,
          highContrast: true,
        ),
      ];

      for (final theme in variants) {
        expect(theme.extension<AppSemanticColors>(), isNotNull);
        expect(
          contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(
            theme.colorScheme.onSecondary,
            theme.colorScheme.secondary,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(
            theme.appBarTheme.foregroundColor!,
            theme.appBarTheme.backgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        if (theme.brightness == Brightness.dark) {
          expect(
            contrastRatio(theme.colorScheme.primary, theme.colorScheme.surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }
  });

  test(
    'component themes resolve the active brand and preserve disabled states',
    () {
      final theme = buildBrandedTheme(AppTheme.light, mediumBrand);
      final enabled = const <WidgetState>{};
      final disabled = const <WidgetState>{WidgetState.disabled};
      final elevated = theme.elevatedButtonTheme.style!;

      expect(elevated.backgroundColor!.resolve(enabled), AppColors.primary);
      expect(
        elevated.backgroundColor!.resolve(disabled),
        isNot(AppColors.primary),
      );
      expect(
        elevated.foregroundColor!.resolve(disabled),
        isNot(theme.colorScheme.onPrimary),
      );
      final outlined = theme.outlinedButtonTheme.style!;
      expect(
        contrastRatio(
          outlined.foregroundColor!.resolve(enabled)!,
          theme.colorScheme.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        outlined.foregroundColor!.resolve(disabled),
        isNot(outlined.foregroundColor!.resolve(enabled)),
      );
      expect(
        (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
            .borderSide
            .color,
        theme.colorScheme.primary,
      );
      expect(theme.navigationBarTheme.indicatorColor, AppColors.primary);
      expect(
        theme.segmentedButtonTheme.style!.backgroundColor!.resolve(
          const <WidgetState>{WidgetState.selected},
        ),
        theme.colorScheme.primary,
      );
      expect(theme.navigationRailTheme.indicatorColor, AppColors.primary);
      expect(
        theme.navigationRailTheme.selectedIconTheme!.color,
        highestContrastForeground(AppColors.primary),
      );
      expect(
        elevated.overlayColor!.resolve(const <WidgetState>{
          WidgetState.hovered,
        }),
        theme.colorScheme.onPrimary.withValues(alpha: 0.08),
      );
      expect(
        elevated.backgroundColor!.resolve(disabled),
        theme.colorScheme.onSurface.withValues(alpha: 0.12),
      );
    },
  );

  test('pale brands receive visible interaction and focus colors', () {
    final theme = buildBrandedTheme(AppTheme.light, paleBrand);
    final surface = theme.colorScheme.surface;
    final focusColor =
        (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
            .borderSide
            .color;
    final selectedBackground = theme
        .segmentedButtonTheme
        .style!
        .backgroundColor!
        .resolve(const <WidgetState>{WidgetState.selected})!;

    expect(contrastRatio(focusColor, surface), greaterThanOrEqualTo(3));
    expect(contrastRatio(selectedBackground, surface), greaterThanOrEqualTo(3));
    expect(focusColor, isNot(paleBrand.primaryColor));
  });

  testWidgets('rendered controls inherit branded state-aware themes', (
    tester,
  ) async {
    final theme = buildBrandedTheme(AppTheme.light, mediumBrand);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('League'),
            actions: const <Widget>[Icon(Icons.settings)],
          ),
          body: const Column(
            children: <Widget>[
              ElevatedButton(onPressed: null, child: Text('Disabled')),
              OutlinedButton(onPressed: null, child: Text('Unavailable')),
              TextField(decoration: InputDecoration(labelText: 'Team')),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.list), label: 'Games'),
            ],
          ),
        ),
      ),
    );

    final context = tester.element(find.text('League'));
    expect(
      Theme.of(context).appBarTheme.foregroundColor,
      highestContrastForeground(AppColors.primary),
    );
    expect(
      Theme.of(context).navigationBarTheme.indicatorColor,
      AppColors.primary,
    );
    expect(
      DefaultTextStyle.of(context).style.color,
      highestContrastForeground(AppColors.primary),
    );
    final iconContext = tester.element(find.byIcon(Icons.settings));
    expect(
      IconTheme.of(iconContext).color,
      highestContrastForeground(AppColors.primary),
    );
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
    'MediaQuery high contrast selects the branded high-contrast theme',
    (tester) async {
      final ordinary = buildBrandedTheme(AppTheme.light, mediumBrand);
      final highContrast = buildBrandedTheme(
        AppTheme.highContrastLight,
        mediumBrand,
        highContrast: true,
      );
      late ThemeData rendered;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(highContrast: true),
          child: MaterialApp(
            theme: ordinary,
            highContrastTheme: highContrast,
            home: Builder(
              builder: (context) {
                rendered = Theme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(rendered.colorScheme.primary, highContrast.colorScheme.primary);
      expect(rendered.colorScheme.primary, isNot(ordinary.colorScheme.primary));
      expect(
        contrastRatio(
          rendered.appBarTheme.foregroundColor!,
          rendered.appBarTheme.backgroundColor!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final ordinaryAppBarContrast = contrastRatio(
        ordinary.appBarTheme.foregroundColor!,
        ordinary.appBarTheme.backgroundColor!,
      );
      expect(
        contrastRatio(
          rendered.appBarTheme.foregroundColor!,
          rendered.appBarTheme.backgroundColor!,
        ),
        greaterThanOrEqualTo(ordinaryAppBarContrast),
      );
    },
  );

  test('application wires both high-contrast theme variants', () {
    final source = File('lib/app/app.dart').readAsStringSync();

    expect(source, contains('highContrastTheme: buildBrandedTheme('));
    expect(source, contains('highContrastDarkTheme: buildBrandedTheme('));
    expect(source, isNot(contains('estimateBrightnessForColor')));

    final shellSource = File('lib/app/app_shell.dart').readAsStringSync();
    final railSource = shellSource.substring(
      shellSource.indexOf('NavigationRail('),
      shellSource.indexOf('destinations: tabs'),
    );
    expect(railSource, isNot(contains('selectedIconTheme:')));
    expect(railSource, isNot(contains('indicatorColor:')));
  });
}
