import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/settings/settings_screen.dart';
import 'package:hoops_connect/features/public/public_team_detail_screen.dart';
import 'package:hoops_connect/features/public/public_player_detail_screen.dart';
import 'package:hoops_connect/features/press/head_to_head_screen.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';
import 'package:hoops_connect/services/presentation_public_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PublicLeagueSnapshot snapshot;
  setUpAll(() async {
    snapshot = await PresentationPublicSnapshotReader().load();
  });
  for (final isPlayer in [false, true]) {
    testWidgets(
      '${isPlayer ? 'Player' : 'Team'} follow and compare remain usable on a narrow phone with large text',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playerId = snapshot.leaderboards
            .expand((board) => board.rankings)
            .firstWhere((entry) => entry.playerId != null)
            .playerId!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(
                const AsyncValue.data(null),
              ),
              publicLeagueSnapshotProvider.overrideWith(
                (ref) => Stream.value(snapshot),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: isPlayer
                  ? PublicPlayerDetailScreen(
                      snapshot: snapshot,
                      detail: snapshot.playerDetail(playerId)!,
                    )
                  : PublicTeamDetailScreen(
                      snapshot: snapshot,
                      detail: snapshot.teamDetail('st-georges-slayers')!,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final follow = find.byKey(
          Key(isPlayer ? 'follow-player-button' : 'follow-team-button'),
        );
        final compare = find.widgetWithText(TextButton, 'Compare');
        expect(follow.hitTestable(), findsOneWidget);
        expect(compare.hitTestable(), findsOneWidget);
        for (final control in [follow, compare]) {
          final rect = tester.getRect(control);
          expect(rect.left, greaterThanOrEqualTo(control == compare ? 56 : 0));
          expect(rect.right, lessThanOrEqualTo(375));
        }
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${isPlayer ? 'Player' : 'Team'} profile has visible Compare and both comparison choices',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playerId = snapshot.leaderboards
            .expand((board) => board.rankings)
            .firstWhere((entry) => entry.playerId != null)
            .playerId!;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => isPlayer
                  ? PublicPlayerDetailScreen(
                      snapshot: snapshot,
                      detail: snapshot.playerDetail(playerId)!,
                    )
                  : PublicTeamDetailScreen(
                      snapshot: snapshot,
                      detail: snapshot.teamDetail('st-georges-slayers')!,
                    ),
            ),
            GoRoute(
              path: '/public/compare',
              builder: (_, state) => HeadToHeadScreen(
                initialPlayerAId: state.uri.queryParameters['player'],
                initialTeamAId: state.uri.queryParameters['team'],
              ),
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
        expect(find.text('Compare').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Compare'));
        await tester.pumpAndSettle();
        expect(find.text('Season averages & head-to-head'), findsOneWidget);
        expect(find.text('Players').last.hitTestable(), findsOneWidget);
        expect(find.text('Teams').last.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Team games show upcoming fixtures and open past box scores', (
    tester,
  ) async {
    final source = snapshot.teamDetail('st-georges-slayers')!;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PublicTeamDetailScreen(
            snapshot: snapshot,
            detail: PublicTeamDetail(
              team: source.team,
              standing: null,
              leaderboards: source.leaderboards,
              games: [
                PublicGame(
                  gameId: 'previous',
                  title: 'Previous game',
                  startTime: DateTime.utc(2025, 2, 13),
                  dateOnly: true,
                  status: PublicGameStatus.finalResult,
                  homeTeamName: 'St George’s Slayers',
                  awayTeamName: 'Rae Town Raptors',
                  homeScore: 71,
                  awayScore: 60,
                ),
                PublicGame(
                  gameId: 'next',
                  title: 'Next game',
                  startTime: DateTime.now().add(const Duration(days: 1)),
                  status: PublicGameStatus.scheduled,
                  homeTeamName: 'St George’s Slayers',
                  awayTeamName: 'Upper Room Eagles',
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/public/games/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Box score ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upcoming games'), findsOneWidget);
    expect(find.byKey(const Key('team-game-next')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('team-game-previous')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byKey(const ValueKey('team-games')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-game-previous')));
    await tester.pumpAndSettle();
    expect(find.text('Box score previous'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Follow opens expanded teams with notifications and visible save',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AsyncValue.data(
                UserModel(
                  id: 'fan',
                  email: 'fan@example.com',
                  displayName: 'Fan',
                  associationId: 'jba',
                  role: UserRole.fan,
                  capabilities: {'association.read'},
                ),
              ),
            ),
            publicLeagueSnapshotProvider.overrideWith(
              (ref) => Stream.value(snapshot),
            ),
          ],
          child: const MaterialApp(
            home: SettingsScreen(focusFavorites: true, leagueId: 'jbl'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Choose teams to follow').hitTestable(), findsOneWidget);
      expect(find.text('Team notifications').hitTestable(), findsOneWidget);
      expect(find.text('Save').hitTestable(), findsOneWidget);
      expect(
        find.text('Jamaica Basketball League').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Jamaica Basketball League'));
      await tester.pumpAndSettle();
      expect(find.text('10 teams followed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Team stat category and per-game/totals controls update in place',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: PublicTeamDetailScreen(
              snapshot: snapshot,
              detail: snapshot.teamDetail('st-georges-slayers')!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Upcoming games'), findsOneWidget);
      expect(find.text('Past games'), findsOneWidget);
      await tester.tap(find.text('Players & stats'));
      await tester.pumpAndSettle();
      expect(find.text('Team averages'), findsOneWidget);
      await tester.tap(find.text('Totals'));
      await tester.pumpAndSettle();
      expect(find.text('Team totals'), findsOneWidget);
      await tester.tap(find.text('Rebounds'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Rebounds'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Points'))
            .selected,
        isFalse,
      );
      await tester.tap(find.text('Per game'));
      await tester.pumpAndSettle();
      expect(find.text('Team averages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
