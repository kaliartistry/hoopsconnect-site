import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/public/public_league_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

void main() {
  testWidgets('public Sign in goes explicitly to the login route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/public/games',
      routes: [
        GoRoute(
          path: '/public/games',
          builder: (_, _) => const PublicLeagueScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicLeagueSnapshotProvider.overrideWith(
            (ref) => Stream<PublicLeagueSnapshot?>.value(null),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login destination'), findsOneWidget);
  });

  testWidgets('public association brand and home-marked Games return home', (
    tester,
  ) async {
    final snapshot = PublicLeagueSnapshot(
      leagueName: 'Jamaica Basketball Association',
      leagueShortName: 'JBA',
      seasonId: 'demo-season',
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1',
        snapshotVersion: null,
        verificationStatus: 'legacyUnverified',
        state: PublicReleaseState.published,
        privacyEpoch: null,
        generatedAt: DateTime.utc(2026, 9, 14),
      ),
      schedule: const [],
      standings: const [],
      leaderboards: const [],
    );
    final router = GoRouter(
      initialLocation: '/public/standings',
      routes: [
        GoRoute(
          path: '/public/games',
          builder: (_, _) => const PublicLeagueScreen(),
        ),
        GoRoute(
          path: '/public/standings',
          builder: (_, _) => const PublicLeagueScreen(initialTab: 2),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicLeagueSnapshotProvider.overrideWith(
            (ref) => Stream.value(snapshot),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('public-games-home-tab')), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('public-association-home')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/public/games');
  });
}
