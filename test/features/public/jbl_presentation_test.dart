import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/public_share_branding.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/public/public_league_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';
import 'package:hoops_connect/services/presentation_public_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PublicLeagueSnapshot snapshot;
  setUpAll(() async {
    snapshot = await PresentationPublicSnapshotReader().load();
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('JBL historical home and team navigation at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/public/games',
        routes: [
          GoRoute(
            path: '/public/games',
            builder: (_, _) => const PublicLeagueScreen(),
          ),
          GoRoute(
            path: '/public/teams/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Team ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(const AsyncValue.data(null)),
            publicLeagueSnapshotProvider.overrideWith(
              (ref) => Stream.value(snapshot),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jamaica Basketball League'), findsOneWidget);
      expect(find.text('MAIN SPONSOR'), findsOneWidget);
      expect(find.text('FOSKA Oats'), findsOneWidget);
      expect(find.text('10 teams · 188 recorded players'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('historical-league-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(
          'Illustrative placements only. These are not confirmed JBL sponsors.',
        ),
        300,
        scrollable: scrollable,
      );
      expect(
        find.text(
          'Illustrative placements only. These are not confirmed JBL sponsors.',
        ),
        findsOneWidget,
      );
      final firstTeam = find.byKey(
        const Key('historical-team-central-celtics'),
      );
      await tester.scrollUntilVisible(firstTeam, -220, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(firstTeam);
      await tester.pumpAndSettle();
      expect(find.text('Team central-celtics'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'historical player and leaderboard share preserve period and primary sponsor',
    () async {
      final snapshot = await PresentationPublicSnapshotReader().load();
      final league = snapshot.leagueById('jbl');
      final branding = publicShareBranding(snapshot, league);
      expect(branding.sponsor.label, 'Main Sponsor');
      expect(branding.sponsor.name, 'FOSKA Oats');
      final player = snapshot.playerDetail(
        'jbl-2025-tivoli-wizards-kimary-brown',
      )!;
      final payload = BrandedSharePayload.publicPlayer(
        snapshot: snapshot,
        player: player,
        branding: branding,
      );
      expect(payload.divisionLabel, '2025 Season');
      expect(payload.sourceLabel, contains('Per-game averages'));
      expect(payload.shareText, contains('Historical cumulative statistics'));
      expect(payload.shareText, contains('FOSKA Oats'));
      expect(payload.shareText, isNot(contains('ShipSafe')));
      expect(
        payload.teams.single.logoUrl,
        'asset:assets/images/jbl_tivoli.png',
      );
      final board = snapshot.leaderboards.firstWhere(
        (b) => b.divisionId == 'jbl-2025-first-round' && b.category == 'ppg',
      );
      final leaders = BrandedSharePayload.publicLeaderboard(
        snapshot: snapshot,
        leaderboard: board,
        branding: branding,
      );
      expect(leaders.divisionLabel, '2025 Season');
      expect(leaders.shareText, contains('Per-game averages'));
    },
  );
}
