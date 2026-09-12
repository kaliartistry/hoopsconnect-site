# Stage 0 UI integration-owner request

Owner: integration owner, because `lib/app/app.dart` is a shared root outside
workstream B's write set.

## Required patch before accepting the UI packet

1. Wire all four theme variants in `MaterialApp.router`:

```dart
theme: buildBrandedTheme(AppTheme.light, branding),
darkTheme: buildBrandedTheme(AppTheme.dark, branding),
highContrastTheme: buildBrandedTheme(
  AppTheme.highContrastLight,
  branding,
  highContrast: true,
),
highContrastDarkTheme: buildBrandedTheme(
  AppTheme.highContrastDark,
  branding,
  highContrast: true,
),
```

2. Move `_brandedTheme` to `lib/app/branded_theme.dart` as a testable
`buildBrandedTheme` function. Add a `highContrast` named argument. Do not copy
the raw branding primary into dark or high-contrast control foregrounds. Derive
an accessible tonal primary from the brand seed. For any exact brand color that
is retained, calculate the contrast ratio for both black and white and choose
the higher-contrast foreground. Do not use
`ThemeData.estimateBrightnessForColor`; its brightness threshold does not
guarantee the best contrast candidate:

```dart
double _contrastRatio(Color foreground, Color background) {
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

Color _highestContrastForeground(Color background) {
  final blackContrast = _contrastRatio(Colors.black, background);
  final whiteContrast = _contrastRatio(Colors.white, background);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

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
final preserveExactLightBrand =
    base.brightness == Brightness.light && !highContrast;
final controlPrimary = preserveExactLightBrand
    ? branding.primaryColor
    : generated.primary;
final onControlPrimary = preserveExactLightBrand
    ? _highestContrastForeground(controlPrimary)
    : generated.onPrimary;
final controlAccent = preserveExactLightBrand
    ? branding.accentColor
    : generatedAccent.primary;
final onControlAccent = preserveExactLightBrand
    ? _highestContrastForeground(controlAccent)
    : generatedAccent.onPrimary;
final colorScheme = generated.copyWith(
  primary: controlPrimary,
  onPrimary: onControlPrimary,
  secondary: controlAccent,
  onSecondary: onControlAccent,
);
```

Use `controlPrimary`/`onControlPrimary` as the elevated background/foreground.
Use `controlPrimary` for the outlined foreground and side.
Keep the app bar's independent `secondaryColor`, but set its foreground with
`_highestContrastForeground(branding.secondaryColor)`. Preserve the
`AppSemanticColors` extension from the base theme.

## Required integration tests

Add `test/app/branded_theme_test.dart` using
`AssociationBrandingModel.jba()`, at least one valid custom dark brand, and a
valid medium-luminance brand fixture whose primary is `#5B8C00`. Give that
fixture explicit accent and secondary/app-bar colors so every retained exact
brand-color path is exercised. Assert:

- JBA's ordinary light primary remains `#2E7D32`.
- For `#5B8C00`, `onPrimary` is whichever of black or white has the larger
  calculated contrast ratio. Make the same higher-ratio assertion for the
  fixture's accent/`onSecondary` pair and its secondary app-bar
  background/foreground pair. These checks must compare both candidate ratios,
  not merely assert a brightness classification.
- Dark and high-contrast dark control primaries are generated tonal values, not
  the raw `#2E7D32` branding value.
- Across the JBA, medium-luminance, and dark-brand fixtures, `onPrimary` against
  `primary`, `onSecondary` against `secondary`, outlined-button foreground
  against the dark surface, and app-bar foreground against its background each
  meet a 4.5:1 contrast ratio.
- `AppSemanticColors` remains installed after branding.
- `JamaicaHoopsConnectApp` supplies non-null `highContrastTheme` and
  `highContrastDarkTheme` to its `MaterialApp.router`.

Do not satisfy the test by weakening contrast assertions or removing dynamic
branding. This request changes presentation tokens only; it must not change
authorization, routing, or provider behavior.
