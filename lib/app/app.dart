import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
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

    return MaterialApp.router(
      title: 'Jamaica HoopsConnect',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
