import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/press/head_to_head_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  testWidgets('media comparison reads only the current public snapshot', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Stream.value(_publishedSnapshot())));
    await tester.pumpAndSettle();

    expect(find.text('2026 NBL published data'), findsOneWidget);
    expect(find.text('Home Team'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.textContaining('Private'), findsNothing);
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
