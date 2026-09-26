import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/public/public_detail_route_screen.dart';
import 'features/public/public_league_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/public_league_provider.dart';
import 'services/presentation_public_snapshot.dart';
import 'services/public_artifact_release_validator.dart';

/// Loopback-only, offline rendering harness. No Firebase initialization, private
/// routes, notifications, credentials, or backend writes. Not a release target.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb ||
      !const bool.fromEnvironment('HOOPSCONNECT_LOCAL_PRESENTATION_QA') ||
      !const ['localhost', '127.0.0.1', '::1'].contains(Uri.base.host)) {
    throw StateError(
      'Presentation QA requires an explicit flag and loopback web host.',
    );
  }
  usePathUrlStrategy();
  final reader = PresentationPublicSnapshotReader();
  final router = GoRouter(
    initialLocation: '/public/games',
    routes: [
      for (final entry in {
        'games': 0,
        'media': 1,
        'standings': 2,
        'leaders': 3,
      }.entries)
        GoRoute(
          path: '/public/${entry.key}',
          builder: (_, _) => PublicLeagueScreen(initialTab: entry.value),
        ),
      for (final entry in {
        'teams': PublicDetailRouteKind.team,
        'players': PublicDetailRouteKind.player,
        'games': PublicDetailRouteKind.game,
      }.entries)
        GoRoute(
          path: '/public/${entry.key}/:id',
          builder: (_, state) => PublicDetailRouteScreen(
            kind: entry.value,
            id: state.pathParameters['id']!,
          ),
        ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: Text('Sign-in is not connected in this offline QA harness.'),
          ),
        ),
      ),
    ],
  );
  runApp(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(const AsyncValue.data(null)),
        publicLeagueSnapshotProvider.overrideWith(
          (ref) => reader.watchCurrentSnapshot(),
        ),
        publicArtifactReleaseValidatorProvider.overrideWithValue(
          PublicArtifactReleaseValidator(reader),
        ),
      ],
      child: MaterialApp.router(
        title: 'HoopsConnect Local Presentation QA',
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
}
