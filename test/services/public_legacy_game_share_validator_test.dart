import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/public_artifact_release_validator.dart';

void main() {
  test('current already-public legacy score can be previewed', () async {
    final displayed = _snapshot();
    final validated = await PublicLegacyGameShareValidator(_Reader(displayed))
        .requireCurrent(
          displayed: displayed,
          displayedGame: displayed.schedule.single,
        );

    expect(validated.game!.homeScore, 82);
    expect(displayed.canCreatePublishedArtifacts, isFalse);
  });

  test('a changed or withdrawn legacy score cannot be shared', () async {
    final displayed = _snapshot();
    for (final current in [
      _snapshot(homeScore: 83),
      _snapshot(state: PublicReleaseState.retracted),
    ]) {
      expect(
        () => PublicLegacyGameShareValidator(_Reader(current)).requireCurrent(
          displayed: displayed,
          displayedGame: displayed.schedule.single,
        ),
        throwsA(isA<PublicArtifactReleaseException>()),
      );
    }
  });

  test('a candidate legacy snapshot never gains preview eligibility', () {
    final candidate = _snapshot(verificationStatus: 'compatibilityCandidate');
    expect(
      isLegacyPublicScoreShareEligible(candidate, candidate.schedule.single),
      isFalse,
    );
  });

  test('legacy public team standings bind to the exact current rows', () async {
    final displayed = _snapshot();
    final validator = PublicLegacyStandingsShareValidator(_Reader(displayed));
    expect(await validator.requireCurrent(displayed), same(displayed));
    expect(
      () => PublicLegacyStandingsShareValidator(
        _Reader(_snapshot(wins: 2)),
      ).requireCurrent(displayed),
      throwsA(isA<PublicArtifactReleaseException>()),
    );
  });
}

PublicLeagueSnapshot _snapshot({
  int homeScore = 82,
  int wins = 1,
  String verificationStatus = 'certified',
  PublicReleaseState state = PublicReleaseState.published,
}) => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1',
    snapshotVersion: null,
    verificationStatus: verificationStatus,
    state: state,
    privacyEpoch: null,
    generatedAt: DateTime.utc(2026, 9, 10),
  ),
  schedule: [
    PublicGame(
      gameId: 'game-1',
      title: 'Home vs Away',
      startTime: DateTime.utc(2026, 9, 10),
      homeTeamName: 'Home',
      awayTeamName: 'Away',
      homeScore: homeScore,
      awayScore: 79,
      status: PublicGameStatus.finalResult,
    ),
  ],
  standings: [
    PublicStanding(
      teamId: 'home',
      teamName: 'Home',
      divisionId: 'nbl-premier',
      rank: 1,
      rankStatus: PublicRankStatus.ranked,
      wins: wins,
      losses: 0,
      pct: 1.0,
      pointsFor: 82,
      pointsAgainst: 79,
    ),
  ],
  leaderboards: const [],
);

class _Reader implements PublicCurrentReleaseReader {
  const _Reader(this.snapshot);

  final PublicLeagueSnapshot snapshot;

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async => snapshot;
}
