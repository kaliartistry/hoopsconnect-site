import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/press/head_to_head_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';
import 'package:hoops_connect/features/public/public_team_stats_screen.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/models/association_branding_model.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test('matchup points read the correct team-scoped imported performer', () {
    final game = PublicGame(
      gameId: 'report',
      title: 'Report',
      startTime: DateTime.utc(2025),
      homeTeamId: 'home',
      homeTeamName: 'Home Team',
      awayTeamId: 'away',
      awayTeamName: 'Away Team',
      status: PublicGameStatus.finalResult,
      homeScore: 82,
      awayScore: 79,
      recap:
          'Home Team\nPUBLIC PLAYER ONE: 24 PTS · 6 REB\nAway Team\nPUBLIC PLAYER TWO: 20 PTS · 2 AST',
    );
    expect(
      recordedMatchupPoints(
        game,
        _publishedSnapshot().playerDetail('player-1'),
      ),
      24,
    );
    expect(
      recordedMatchupPoints(
        game,
        _publishedSnapshot().playerDetail('player-2'),
      ),
      20,
    );
    expect(recordedMatchupPoints(game, null), isNull);
  });
  testWidgets('media comparison reads only the current public snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Stream.value(_publishedSnapshot())));
    await tester.pumpAndSettle();

    expect(find.text('Season averages & head-to-head'), findsOneWidget);
    expect(find.text('Home Team'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    expect(find.textContaining('Private'), findsNothing);
  });

  test('team averages use team games and keep absent rebounds unknown', () {
    final stats = publicTeamMetrics(_publishedSnapshot(), 'home');
    expect(stats['PPG'], '82.0');
    expect(stats['RPG'], '—');
    expect(stats['W'], '1');
  });

  test(
    'player comparison exports public averages and preserves missing metrics',
    () {
      final snapshot = _publishedSnapshot();
      final payload = BrandedSharePayload.publicPlayerComparison(
        snapshot: snapshot,
        first: snapshot.playerDetail('player-1')!,
        second: snapshot.playerDetail('player-2')!,
        branding: AssociationBrandingModel.jba(),
      );
      expect(payload.comparisonRows, contains(('PPG', '20.0', '18.0')));
      expect(payload.comparisonRows, contains(('RPG', 'N/A', 'N/A')));
      expect(payload.teams.length, 2);
      expect(
        () => BrandedSharePayload.publicPlayerComparison(
          snapshot: snapshot,
          first: snapshot.playerDetail('player-1')!,
          second: snapshot.playerDetail('player-1')!,
          branding: AssociationBrandingModel.jba(),
        ),
        throwsArgumentError,
      );
    },
  );

  testWidgets('player picker is searchable and makes sharing discoverable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Stream.value(_publishedSnapshot())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Players').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player A: Choose player'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'One');
    await tester.pumpAndSettle();
    expect(find.text('Public Player Two · Away Team'), findsNothing);
    await tester.tap(find.text('Public Player One · Home Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player B: Choose player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public Player Two · Away Team'));
    await tester.pumpAndSettle();
    expect(find.text('Last five meetings'), findsOneWidget);
    expect(find.byKey(const Key('share-player-comparison')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('withdrawn comparison never falls back to private providers', (
    tester,
  ) async {
    final published = _publishedSnapshot();
    final withdrawn = PublicLeagueSnapshot(
      leagueName: published.leagueName,
      leagueShortName: published.leagueShortName,
      seasonId: published.seasonId,
      seasonName: published.seasonName,
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1.1',
        snapshotVersion: _hashB,
        verificationStatus: 'legacyApproved',
        state: PublicReleaseState.retracted,
        privacyEpoch: 7,
        generatedAt: DateTime.utc(2026, 9, 11),
      ),
      schedule: const [],
      standings: const [],
      leaderboards: const [],
    );

    await tester.pumpWidget(_app(Stream.value(withdrawn)));
    await tester.pumpAndSettle();

    expect(find.textContaining('no active public release'), findsOneWidget);
    expect(find.textContaining('No private stats were used'), findsOneWidget);
    expect(find.text('Home Team'), findsNothing);
  });
}

Widget _app(Stream<PublicLeagueSnapshot?> stream) => ProviderScope(
  overrides: [publicLeagueSnapshotProvider.overrideWith((ref) => stream)],
  child: const MaterialApp(home: HeadToHeadScreen(initialTeamAId: 'home')),
);

PublicLeagueSnapshot _publishedSnapshot() => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion: _hashA,
    verificationStatus: 'legacyApproved',
    state: PublicReleaseState.published,
    privacyEpoch: 7,
    generatedAt: DateTime.utc(2026, 9, 11),
  ),
  teams: const [
    PublicTeam(teamId: 'home', name: 'Home Team'),
    PublicTeam(teamId: 'away', name: 'Away Team'),
  ],
  schedule: [
    PublicGame(
      gameId: 'game-1',
      title: 'Home Team vs Away Team',
      startTime: DateTime.utc(2026, 9, 11),
      homeTeamId: 'home',
      homeTeamName: 'Home Team',
      awayTeamId: 'away',
      awayTeamName: 'Away Team',
      homeScore: 82,
      awayScore: 79,
      status: PublicGameStatus.finalResult,
    ).withComputedResultVersion(),
  ],
  standings: const [
    PublicStanding(
      teamId: 'home',
      teamName: 'Home Team',
      wins: 1,
      losses: 0,
      pct: 1,
      pointsFor: 82,
      pointsAgainst: 79,
    ),
    PublicStanding(
      teamId: 'away',
      teamName: 'Away Team',
      wins: 0,
      losses: 1,
      pct: 0,
      pointsFor: 79,
      pointsAgainst: 82,
    ),
  ],
  leaderboards: const [
    PublicLeaderboard(
      category: 'ppg',
      rankings: [
        PublicLeader(
          playerId: 'player-1',
          displayName: 'Public Player One',
          teamId: 'home',
          teamName: 'Home Team',
          value: 20,
          gamesPlayed: 1,
        ),
        PublicLeader(
          playerId: 'player-2',
          displayName: 'Public Player Two',
          teamId: 'away',
          teamName: 'Away Team',
          value: 18,
          gamesPlayed: 1,
        ),
      ],
    ),
  ],
);
