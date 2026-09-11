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
an accessible tonal primary from the brand seed:

```dart
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
    ? (ThemeData.estimateBrightnessForColor(controlPrimary) == Brightness.dark
          ? Colors.white
          : Colors.black)
    : generated.onPrimary;
final controlAccent = preserveExactLightBrand
    ? branding.accentColor
    : generatedAccent.primary;
final onControlAccent = preserveExactLightBrand
    ? (ThemeData.estimateBrightnessForColor(controlAccent) == Brightness.dark
          ? Colors.white
          : Colors.black)
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
Keep the app bar's independent `secondaryColor` contrast calculation. Preserve
the `AppSemanticColors` extension from the base theme.

## Required integration tests

Add `test/app/branded_theme_test.dart` using
`AssociationBrandingModel.jba()` and at least one valid custom dark brand.
Assert:

- JBA's ordinary light primary remains `#2E7D32`.
- Dark and high-contrast dark control primaries are generated tonal values, not
  the raw `#2E7D32` branding value.
- `onPrimary` against `primary`, outlined-button foreground against the dark
  surface, and app-bar foreground against its background each meet a 4.5:1
  contrast ratio.
- `AppSemanticColors` remains installed after branding.
- `JamaicaHoopsConnectApp` supplies non-null `highContrastTheme` and
  `highContrastDarkTheme` to its `MaterialApp.router`.

Do not satisfy the test by weakening contrast assertions or removing dynamic
branding. This request changes presentation tokens only; it must not change
authorization, routing, or provider behavior.
