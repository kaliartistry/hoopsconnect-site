import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/app/router/app_route_contract.dart';
import 'package:hoops_connect/features/public/public_detail_route_screen.dart';
import 'package:hoops_connect/features/public/public_league_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

void main() {
  testWidgets('guest discovers a result and opens public-only details', (
    tester,
  ) async {
    final router = await _pump(tester, _snapshot());

    expect(find.textContaining('Version aaaaaaaaaaaa'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Away'), findsWidgets);

    await tester.tap(find.byKey(const Key('public-game-card-game-1')));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      PublicRoutePaths.game('game-1'),
    );
    expect(find.text('Game details'), findsOneWidget);
    expect(find.text('Home Team won a close game.'), findsOneWidget);
    expect(find.text('Share published result'), findsOneWidget);
    expect(find.textContaining('Publication aaaaaaaaaaaa'), findsOneWidget);
  });

  testWidgets('guest sees the latest final score and next scheduled game', (
    tester,
  ) async {
    final router = await _pump(
      tester,
      _snapshot(
        schedule: [
          PublicGame(
            gameId: 'latest-game',
            title: 'Latest Home vs Latest Away',
            startTime: DateTime.utc(2000, 9, 10, 20),
            venue: 'National Arena',
            divisionId: 'premier',
            homeTeamId: 'home',
            homeTeamName: 'Latest Home',
            awayTeamId: 'away',
            awayTeamName: 'Latest Away',
            homeScore: 88,
            awayScore: 82,
            status: PublicGameStatus.finalResult,
          ).withComputedResultVersion(),
          PublicGame(
            gameId: 'next-game',
            title: 'Next Home vs Next Away',
            startTime: DateTime.utc(2099, 9, 11, 23),
            venue: 'GC Foster College',
            divisionId: 'premier',
            homeTeamId: 'home',
            homeTeamName: 'Next Home',
            awayTeamId: 'away',
            awayTeamName: 'Next Away',
            status: PublicGameStatus.scheduled,
          ),
        ],
      ),
    );

    expect(find.text('LATEST RESULT'), findsOneWidget);
    expect(find.text('NEXT GAME'), findsOneWidget);
    expect(find.text('Latest Home'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('public-latest-result-card')),
        matching: find.text('88'),
      ),
      findsOneWidget,
    );
    expect(find.text('Latest Away'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('public-latest-result-card')),
        matching: find.text('82'),
      ),
      findsOneWidget,
    );
    expect(find.text('Next Home'), findsWidgets);
    expect(find.text('Next Away'), findsWidgets);
    expect(find.text('GC Foster College'), findsWidgets);

    await tester.tap(find.byKey(const Key('public-next-game-card')));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      PublicRoutePaths.game('next-game'),
    );
    expect(find.text('Game details'), findsOneWidget);
  });

  testWidgets('standings expose games played and team detail destination', (
    tester,
  ) async {
    final router = await _pump(tester, _snapshot());

    await tester.tap(find.text('Standings'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      PublicRoutePaths.standings,
    );
    expect(find.text('Premier'), findsOneWidget);
    expect(find.text('1 GP · PF 82 · PA 79'), findsOneWidget);
    expect(
      find.text('Winning percentage; tied ranks remain tied'),
      findsOneWidget,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      PublicRoutePaths.team('home'),
    );
    expect(find.text('Team details'), findsOneWidget);
    expect(find.text('1 game played'), findsWidgets);
  });

  testWidgets('leaders use PTS first and open a cleared player detail', (
    tester,
  ) async {
    await _pump(tester, _snapshot());

    await tester.tap(find.text('Leaders'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PTS'), findsOneWidget);
    expect(find.textContaining('AST'), findsOneWidget);

    await tester.tap(find.text('Player One'));
    await tester.pumpAndSettle();
    expect(find.text('Player details'), findsOneWidget);
    expect(find.text('Published season stats'), findsOneWidget);
    expect(
      find.textContaining(
        'No profile, contact, school, guardian, or account data',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty public leader board explains identity suppression', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(
        leaderboards: const [
          PublicLeaderboard(
            category: 'ppg',
            divisionId: 'premier',
            rankings: [],
          ),
        ],
      ),
    );

    await tester.tap(find.text('Leaders'));
    await tester.pumpAndSettle();

    expect(find.text('No cleared leaders published'), findsOneWidget);
    expect(find.textContaining('No player identity rows'), findsOneWidget);
  });

  testWidgets('withdrawn release never renders stale rows', (tester) async {
    final published = _snapshot();
    final withdrawn = PublicLeagueSnapshot(
      leagueName: published.leagueName,
      leagueShortName: published.leagueShortName,
      seasonId: published.seasonId,
      seasonName: published.seasonName,
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: published.version.contractVersion,
        snapshotVersion: published.version.snapshotVersion,
        verificationStatus: published.version.verificationStatus,
        state: PublicReleaseState.retracted,
        privacyEpoch: published.version.privacyEpoch,
        generatedAt: published.version.generatedAt,
      ),
      schedule: const [],
      standings: const [],
      leaderboards: const [],
    );

    await _pump(tester, withdrawn);

    expect(find.text('This public release was withdrawn'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Away'), findsNothing);
  });

  testWidgets(
    'missing and failed public data never fall back to private rows',
    (tester) async {
      await _pump(tester, null);
      expect(find.text('Published data unavailable'), findsOneWidget);
      expect(find.textContaining('No private data is shown'), findsOneWidget);

      await _pump(
        tester,
        null,
        stream: Stream.error(StateError('private implementation detail')),
      );
      expect(find.text('Published data could not be loaded'), findsOneWidget);
      expect(find.textContaining('No private league records'), findsOneWidget);
      expect(
        find.textContaining('private implementation detail'),
        findsNothing,
      );
    },
  );

  testWidgets('game discovery paginates without silently truncating results', (
    tester,
  ) async {
    final games = List.generate(
      26,
      (index) => PublicGame(
        gameId: 'game-$index',
        title: 'Home $index vs Away $index',
        startTime: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
        divisionId: 'premier',
        homeTeamId: 'home',
        homeTeamName: 'Home $index',
        awayTeamId: 'away',
        awayTeamName: 'Away $index',
        homeScore: 80,
        awayScore: 70,
        status: PublicGameStatus.finalResult,
      ).withComputedResultVersion(),
    );
    await _pump(
      tester,
      _snapshot(schedule: games),
      size: const Size(900, 6000),
    );

    expect(find.text('Home 0'), findsNothing);
    expect(find.text('Load 1 more games'), findsOneWidget);
    final loadMore = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Load 1 more games'),
    );
    loadMore.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Home 0'), findsOneWidget);
    expect(find.text('Load 1 more games'), findsNothing);
  });

  testWidgets(
    'guest switches from a dated schedule to a calendar day in Jamaica time',
    (tester) async {
      final games = [
        PublicGame(
          gameId: 'late-game',
          title: 'Late Home vs Late Away',
          startTime: DateTime.utc(2026, 9, 10, 4, 30),
          divisionId: 'premier',
          homeTeamId: 'home',
          homeTeamName: 'Late Home',
          awayTeamId: 'away',
          awayTeamName: 'Late Away',
          status: PublicGameStatus.scheduled,
        ),
        PublicGame(
          gameId: 'morning-game',
          title: 'Morning Home vs Morning Away',
          startTime: DateTime.utc(2026, 9, 10, 5, 30),
          divisionId: 'premier',
          homeTeamId: 'home',
          homeTeamName: 'Morning Home',
          awayTeamId: 'away',
          awayTeamName: 'Morning Away',
          status: PublicGameStatus.scheduled,
        ),
        PublicGame(
          gameId: 'october-game',
          title: 'October Home vs October Away',
          startTime: DateTime.utc(2026, 10, 15, 23),
          divisionId: 'premier',
          homeTeamId: 'home',
          homeTeamName: 'October Home',
          awayTeamId: 'away',
          awayTeamName: 'October Away',
          status: PublicGameStatus.scheduled,
        ),
      ];
      await _pump(tester, _snapshot(schedule: games));

      expect(find.byKey(const Key('public-games-schedule-view')), findsOne);
      expect(find.text('Wednesday, September 9, 2026'), findsOne);
      expect(find.text('Thursday, September 10, 2026'), findsOne);

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('public-games-calendar')), findsOne);
      await tester.ensureVisible(
        find.byKey(const Key('public-game-day-2026-10-15')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('public-game-day-2026-10-15')));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('public-games-calendar-results')),
          matching: find.text('October Home'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('public-game-day-2026-09-09')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('public-game-day-2026-09-09')));
      await tester.pumpAndSettle();

      final calendarResults = find.byKey(
        const Key('public-games-calendar-results'),
      );
      expect(
        find.descendant(of: calendarResults, matching: find.text('Late Home')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: calendarResults,
          matching: find.text('Morning Home'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: calendarResults,
          matching: find.text('October Home'),
        ),
        findsNothing,
      );
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Wednesday, September 9, 2026'), findsOne);
    },
  );

  testWidgets('public games layout fits desktop without overflow', (
    tester,
  ) async {
    await _pump(tester, _snapshot(), size: const Size(1440, 1000));

    expect(find.text('Games & scores'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('public-games-calendar-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest switches leagues and sees league-scoped highlights', (
    tester,
  ) async {
    final games = [
      ..._snapshot().schedule,
      PublicGame(
        gameId: 'schools-final',
        title: 'School Home vs School Away',
        startTime: DateTime.utc(2026, 9, 9, 20),
        divisionId: 'schoolboy-a',
        homeTeamId: 'school-home',
        homeTeamName: 'School Home',
        awayTeamId: 'school-away',
        awayTeamName: 'School Away',
        homeScore: 68,
        awayScore: 64,
        status: PublicGameStatus.finalResult,
      ).withComputedResultVersion(),
    ];
    await _pump(
      tester,
      _snapshot(
        schedule: games,
        divisions: const [
          PublicDivision(divisionId: 'premier', name: 'Premier'),
          PublicDivision(divisionId: 'schoolboy-a', name: 'Schoolboy A'),
        ],
        leagues: const [
          PublicLeagueDefinition(
            leagueId: 'nbl',
            name: 'National Basketball League',
            shortName: 'NBL',
            divisionIds: ['premier'],
          ),
          PublicLeagueDefinition(
            leagueId: 'schools',
            name: 'School Leagues',
            shortName: 'Schools',
            divisionIds: ['schoolboy-a'],
            sponsor: PublicSponsor(
              enabled: true,
              name: 'Campus Courts',
              label: 'Title sponsor',
            ),
          ),
        ],
      ),
      size: const Size(1100, 1000),
    );

    expect(find.text('Home'), findsWidgets);
    await tester.tap(find.byKey(const Key('public-league-schools')));
    await tester.pumpAndSettle();
    expect(find.text('Title sponsor Campus Courts'), findsOneWidget);
    expect(find.text('School Home'), findsWidgets);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('fresh public detail URLs resolve and unknown IDs stay public', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(),
      initialLocation: PublicRoutePaths.game('game-1'),
    );
    expect(find.text('Game details'), findsOneWidget);
    expect(find.text('Home Team won a close game.'), findsOneWidget);

    await _pump(
      tester,
      _snapshot(),
      initialLocation: PublicRoutePaths.game('missing-game'),
    );
    expect(find.text('Published game not found'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
  });
}

Future<GoRouter> _pump(
  WidgetTester tester,
  PublicLeagueSnapshot? snapshot, {
  Size size = const Size(900, 1200),
  Stream<PublicLeagueSnapshot?>? stream,
  String initialLocation = PublicRoutePaths.games,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: PublicRoutePaths.games,
        builder: (_, _) => const PublicLeagueScreen(),
      ),
      GoRoute(
        path: PublicRoutePaths.standings,
        builder: (_, _) => const PublicLeagueScreen(initialTab: 1),
      ),
      GoRoute(
        path: PublicRoutePaths.leaders,
        builder: (_, _) => const PublicLeagueScreen(initialTab: 2),
      ),
      GoRoute(
        path: '${PublicRoutePaths.games}/:gameId',
        builder: (_, state) => PublicDetailRouteScreen(
          kind: PublicDetailRouteKind.game,
          id: state.pathParameters['gameId']!,
        ),
      ),
      GoRoute(
        path: '${PublicRoutePaths.root}/teams/:teamId',
        builder: (_, state) => PublicDetailRouteScreen(
          kind: PublicDetailRouteKind.team,
          id: state.pathParameters['teamId']!,
        ),
      ),
      GoRoute(
        path: '${PublicRoutePaths.root}/players/:playerId',
        builder: (_, state) => PublicDetailRouteScreen(
          kind: PublicDetailRouteKind.player,
          id: state.pathParameters['playerId']!,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        publicLeagueSnapshotProvider.overrideWith(
          (ref) => stream ?? Stream.value(snapshot),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

PublicLeagueSnapshot _snapshot({
  List<PublicGame>? schedule,
  List<PublicLeaderboard>? leaderboards,
  List<PublicDivision>? divisions,
  List<PublicLeagueDefinition>? leagues,
}) => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  standingsPolicyLabel: 'Winning percentage; tied ranks remain tied',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    verificationStatus: 'legacyApproved',
    state: PublicReleaseState.published,
    privacyEpoch: 7,
    generatedAt: DateTime.utc(2026, 9, 10, 21),
  ),
  divisions:
      divisions ??
      const [PublicDivision(divisionId: 'premier', name: 'Premier')],
  leagues: leagues ?? const [],
  teams: const [
    PublicTeam(teamId: 'home', name: 'Home', divisionId: 'premier'),
    PublicTeam(teamId: 'away', name: 'Away', divisionId: 'premier'),
  ],
  schedule:
      schedule ??
      [
        PublicGame(
          gameId: 'game-1',
          title: 'Home vs Away',
          startTime: DateTime.utc(2026, 9, 10, 20),
          venue: 'National Arena',
          divisionId: 'premier',
          homeTeamId: 'home',
          homeTeamName: 'Home',
          awayTeamId: 'away',
          awayTeamName: 'Away',
          homeScore: 82,
          awayScore: 79,
          status: PublicGameStatus.finalResult,
          recap: 'Home Team won a close game.',
          playerLines: const [
            PublicPlayerGameLine(
              playerId: 'player-1',
              displayName: 'Player One',
              teamId: 'home',
              points: 20,
              turnovers: 2,
            ),
          ],
        ).withComputedResultVersion(),
      ],
  standings: const [
    PublicStanding(
      teamId: 'home',
      teamName: 'Home',
      divisionId: 'premier',
      rank: 1,
      rankStatus: PublicRankStatus.ranked,
      wins: 1,
      losses: 0,
      pct: 1,
      pointsFor: 82,
      pointsAgainst: 79,
    ),
  ],
  leaderboards:
      leaderboards ??
      const [
        PublicLeaderboard(
          category: 'ppg',
          divisionId: 'premier',
          qualificationLabel: 'Minimum 1 game',
          rankings: [
            PublicLeader(
              playerId: 'player-1',
              displayName: 'Player One',
              teamId: 'home',
              teamName: 'Home',
              divisionId: 'premier',
              value: 20,
              gamesPlayed: 1,
            ),
          ],
        ),
        PublicLeaderboard(
          category: 'apg',
          divisionId: 'premier',
          qualificationLabel: 'Minimum 1 game',
          rankings: [
            PublicLeader(
              playerId: 'player-1',
              displayName: 'Player One',
              teamId: 'home',
              teamName: 'Home',
              divisionId: 'premier',
              value: 4,
              gamesPlayed: 1,
            ),
          ],
        ),
      ],
);
