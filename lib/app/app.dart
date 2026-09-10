import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../models/association_branding_model.dart';
import '../providers/association_branding_providers.dart';
import '../providers/theme_providers.dart';
import '../services/notification_service.dart';
import 'router/app_router.dart';

class JamaicaHoopsConnectApp extends ConsumerStatefulWidget {
  const JamaicaHoopsConnectApp({super.key});

  @override
  ConsumerState<JamaicaHoopsConnectApp> createState() =>
      _JamaicaHoopsConnectAppState();
}

class _JamaicaHoopsConnectAppState
    extends ConsumerState<JamaicaHoopsConnectApp> {
  bool _routerLinked = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Link the router to the notification service once after the first build.
    if (!_routerLinked) {
      _routerLinked = true;
      ref.read(notificationServiceProvider).setRouter(router);
    }

    final themeMode = ref.watch(themeModeProvider);
    final branding = ref.watch(effectiveAssociationBrandingProvider);

    return MaterialApp.router(
      title: '${branding.shortName} | HoopsConnect',
      theme: _brandedTheme(AppTheme.light, branding),
      darkTheme: _brandedTheme(AppTheme.dark, branding),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

ThemeData _brandedTheme(ThemeData base, AssociationBrandingModel branding) {
  final primary = branding.primaryColor;
  final secondary = branding.secondaryColor;
  final accent = branding.accentColor;
  final onPrimary =
      ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
      ? Colors.white
      : Colors.black;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    secondary: accent,
    brightness: base.brightness,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: secondary,
      foregroundColor:
          ThemeData.estimateBrightnessForColor(secondary) == Brightness.dark
          ? Colors.white
          : Colors.black,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(primary),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(primary),
        side: WidgetStatePropertyAll(BorderSide(color: primary)),
      ),
    ),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      selectedItemColor: primary,
    ),
  );
}
