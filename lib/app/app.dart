import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/association_branding_providers.dart';
import '../providers/theme_providers.dart';
import '../services/notification_service.dart';
import 'branded_theme.dart';
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
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
