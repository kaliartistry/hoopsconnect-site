import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/box_score_screen.dart';
import 'package:hoops_connect/models/game_stats_model.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';
import 'package:hoops_connect/providers/stats_providers.dart';

void main() {
  testWidgets('approved private box score can preview its already-public score', (
    tester,
  ) async {
    const stats = GameStatsModel(
      id: 'game-1',
      eventId: 'game-1',
      seasonId: 'season-1',
      divisionId: 'nbl-premier',
      homeTeamId: 'home',
      awayTeamId: 'away',
      homeTeamName: 'Public Home',
      awayTeamName: 'Public Away',
      homeScore: 82,
      awayScore: 79,
      status: GameStatsStatus.approved,
    );
    final snapshot = PublicLeagueSnapshot(
      leagueName: 'National Basketball League',
      leagueShortName: 'NBL',
      seasonId: 'season-1',
      version: PublicSnapshotVersion(
        schemaVersion: 1,
        contractVersion: 'legacy-public-snapshot-v1',
        snapshotVersion: null,
        verificationStatus: 'certified',
        state: PublicReleaseState.published,
        privacyEpoch: null,
        generatedAt: DateTime.utc(2026, 9, 15),
      ),
      schedule: [
        PublicGame(
          gameId: 'game-1',
          title: 'Public Home vs Public Away',
          startTime: DateTime.utc(2026, 9, 15, 20),
          homeTeamId: 'home',
          homeTeamName: 'Public Home',
          awayTeamId: 'away',
          awayTeamName: 'Public Away',
          homeScore: 82,
          awayScore: 79,
          status: PublicGameStatus.finalResult,
        ),
      ],
      standings: const [],
      leaderboards: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameStatsProvider('game-1').overrideWith(
            (ref) => Stream.value(stats),
          ),
          publicLeagueSnapshotProvider.overrideWith(
            (ref) => Stream.value(snapshot),
          ),
        ],
        child: const MaterialApp(home: BoxScoreScreen(eventId: 'game-1')),
      ),
    );
    await tester.pumpAndSettle();
    final share = find.byKey(const Key('box-score-legacy-score-share'));
    expect(share, findsOneWidget);
    expect(tester.widget<IconButton>(share).onPressed, isNotNull);
    expect(find.byKey(const Key('box-score-demo-share')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing posted box score does not share an unrelated matchup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameStatsProvider('game-1').overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: BoxScoreScreen(eventId: 'game-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('box-score-demo-share')), findsNothing);
    expect(find.byKey(const Key('box-score-legacy-score-share')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
