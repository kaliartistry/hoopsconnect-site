import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../models/association_branding_model.dart';

/// Applies association branding without sacrificing readable controls.
///
/// Exact brand colors are retained for the ordinary light theme. Dark and
/// high-contrast themes use tonal colors generated from the same seeds so
/// controls remain readable on their surfaces.
ThemeData buildBrandedTheme(
  ThemeData base,
  AssociationBrandingModel branding, {
  bool highContrast = false,
}) {
  final generated = ColorScheme.fromSeed(
    seedColor: branding.primaryColor,
    brightness: base.brightness,
    contrastLevel: highContrast ? 1 : 0,
  );
  final generatedAccent = ColorScheme.fromSeed(
    seedColor: branding.accentColor,
    brightness: base.brightness,
    contrastLevel: highContrast ? 1 : 0,
  );
  final generatedSecondary = ColorScheme.fromSeed(
    seedColor: branding.secondaryColor,
    brightness: base.brightness,
    contrastLevel: highContrast ? 1 : 0,
  );
  final preserveExactLightBrand =
      base.brightness == Brightness.light && !highContrast;
  final controlPrimary = preserveExactLightBrand
      ? branding.primaryColor
      : generated.primary;
  final onControlPrimary = preserveExactLightBrand
      ? highestContrastForeground(controlPrimary)
      : generated.onPrimary;
  final controlAccent = preserveExactLightBrand
      ? branding.accentColor
      : generatedAccent.primary;
  final onControlAccent = preserveExactLightBrand
      ? highestContrastForeground(controlAccent)
      : generatedAccent.onPrimary;
  final appBarBackground = highContrast
      ? generatedSecondary.primary
      : branding.secondaryColor;
  final appBarForeground = highestContrastForeground(appBarBackground);
  final colorScheme = generated.copyWith(
    primary: controlPrimary,
    onPrimary: onControlPrimary,
    secondary: controlAccent,
    onSecondary: onControlAccent,
  );
  final outlinedForeground = _accessibleBrandForeground(
    preferred: controlPrimary,
    tonal: generated.primary,
    background: colorScheme.surface,
  );
  final interactionPrimary = _accessibleInteractionColor(
    preferred: controlPrimary,
    tonal: generated.primary,
    background: colorScheme.surface,
  );
  final interactionOnPrimary = highestContrastForeground(interactionPrimary);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
    borderSide: BorderSide(color: colorScheme.outline),
  );
  final elevatedStyle = base.elevatedButtonTheme.style;
  final outlinedStyle = base.outlinedButtonTheme.style;
  final textStyle = base.textButtonTheme.style;

  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    focusColor: interactionPrimary.withValues(
      alpha: base.brightness == Brightness.dark ? 0.28 : 0.16,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: appBarBackground,
      foregroundColor: appBarForeground,
      iconTheme: base.appBarTheme.iconTheme?.copyWith(color: appBarForeground),
      actionsIconTheme: base.appBarTheme.actionsIconTheme?.copyWith(
        color: appBarForeground,
      ),
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        color: appBarForeground,
      ),
      toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(
        color: appBarForeground,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: elevatedStyle?.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return interactionPrimary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.48);
          }
          return interactionOnPrimary;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return interactionOnPrimary.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return interactionOnPrimary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return interactionOnPrimary.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outlinedStyle?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.48);
          }
          return outlinedForeground;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
            );
          }
          return BorderSide(color: outlinedForeground);
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return outlinedForeground.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return outlinedForeground.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return outlinedForeground.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: textStyle?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.48);
          }
          return outlinedForeground;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return outlinedForeground.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return outlinedForeground.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return outlinedForeground.withValues(alpha: 0.10);
          }
          return null;
        }),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: colorScheme.surfaceContainerLowest,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: interactionPrimary, width: 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: base.segmentedButtonTheme.style?.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return states.contains(WidgetState.selected)
              ? interactionOnPrimary
              : colorScheme.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? interactionPrimary
              : colorScheme.surfaceContainerLow;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: colorScheme.outlineVariant),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorColor: interactionPrimary,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? interactionOnPrimary
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? outlinedForeground
              : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      indicatorColor: interactionPrimary,
      selectedIconTheme: IconThemeData(color: interactionOnPrimary),
      selectedLabelTextStyle: TextStyle(
        color: outlinedForeground,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      unselectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 13,
      ),
    ),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      selectedItemColor: outlinedForeground,
      unselectedItemColor: colorScheme.onSurfaceVariant,
    ),
  );
}

Color _accessibleBrandForeground({
  required Color preferred,
  required Color tonal,
  required Color background,
}) {
  if (contrastRatio(preferred, background) >= 4.5) return preferred;
  if (contrastRatio(tonal, background) >= 4.5) return tonal;
  return highestContrastForeground(background);
}

Color _accessibleInteractionColor({
  required Color preferred,
  required Color tonal,
  required Color background,
}) {
  if (contrastRatio(preferred, background) >= 3) return preferred;
  if (contrastRatio(tonal, background) >= 3) return tonal;
  return highestContrastForeground(background);
}

@visibleForTesting
double contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

@visibleForTesting
Color highestContrastForeground(Color background) {
  final blackContrast = contrastRatio(Colors.black, background);
  final whiteContrast = contrastRatio(Colors.white, background);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}
