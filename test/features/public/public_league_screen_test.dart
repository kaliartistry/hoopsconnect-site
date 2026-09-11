import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/public/public_league_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

void main() {
  testWidgets('guest discovers a result and opens public-only details', (
    tester,
  ) async {
    await _pump(tester, _snapshot());

    expect(find.textContaining('Version aaaaaaaaaaaa'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Game details'), findsOneWidget);
    expect(find.text('Home Team won a close game.'), findsOneWidget);
    expect(find.text('Share published result'), findsOneWidget);
    expect(find.textContaining('Publication aaaaaaaaaaaa'), findsOneWidget);
  });

  testWidgets('standings expose games played and team detail destination', (
    tester,
  ) async {
    await _pump(tester, _snapshot());

    await tester.tap(find.text('Standings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 GP'), findsOneWidget);
    expect(
      find.text('Winning percentage; tied ranks remain tied'),
      findsOneWidget,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Load 1 more games'));
    await tester.pumpAndSettle();

    expect(find.text('Home 0'), findsOneWidget);
    expect(find.text('Load 1 more games'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  PublicLeagueSnapshot? snapshot, {
  Size size = const Size(900, 1200),
  Stream<PublicLeagueSnapshot?>? stream,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        publicLeagueSnapshotProvider.overrideWith(
          (ref) => stream ?? Stream.value(snapshot),
        ),
      ],
      child: const MaterialApp(home: PublicLeagueScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

PublicLeagueSnapshot _snapshot({
  List<PublicGame>? schedule,
  List<PublicLeaderboard>? leaderboards,
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
  divisions: const [PublicDivision(divisionId: 'premier', name: 'Premier')],
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
