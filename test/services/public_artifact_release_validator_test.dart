import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/public_artifact_release_validator.dart';

const _snapshotA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _snapshotB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test(
    'accepts only the exact current snapshot and content-bound result',
    () async {
      final snapshot = _snapshot();
      final reader = _QueueReader([snapshot]);
      final validator = PublicArtifactReleaseValidator(reader);

      final result = await validator.requireCurrent(
        PublicArtifactBinding.game(snapshot, snapshot.schedule.single),
      );

      expect(result.snapshot, same(snapshot));
      expect(result.game, same(snapshot.schedule.single));
      expect(reader.reads, 1);
    },
  );

  test('retraction and release replacement fail closed', () async {
    final displayed = _snapshot();
    final binding = PublicArtifactBinding.game(
      displayed,
      displayed.schedule.single,
    );

    for (final current in [
      _snapshot(state: PublicReleaseState.retracted),
      _snapshot(snapshotVersion: _snapshotB),
      _snapshot(generatedAt: DateTime.utc(2026, 9, 11, 0, 0, 1)),
      null,
    ]) {
      final validator = PublicArtifactReleaseValidator(_QueueReader([current]));
      await expectLater(
        validator.requireCurrent(binding),
        throwsA(isA<PublicArtifactReleaseException>()),
      );
    }
  });

  test('corrected content cannot reuse the displayed result version', () async {
    final displayed = _snapshot();
    final staleVersion = displayed.schedule.single.resultVersion!;
    final corrected = _snapshot(
      homeScore: 83,
      forcedResultVersion: staleVersion,
    );
    final validator = PublicArtifactReleaseValidator(_QueueReader([corrected]));

    await expectLater(
      validator.requireCurrent(
        PublicArtifactBinding.game(displayed, displayed.schedule.single),
      ),
      throwsA(
        isA<PublicArtifactReleaseException>().having(
          (error) => error.message,
          'message',
          contains('result changed'),
        ),
      ),
    );
  });

  test('offline authoritative verification fails closed truthfully', () async {
    final displayed = _snapshot();
    final validator = PublicArtifactReleaseValidator(
      _ThrowingReader(StateError('server unavailable')),
    );

    await expectLater(
      validator.requireCurrent(
        PublicArtifactBinding.game(displayed, displayed.schedule.single),
      ),
      throwsA(
        isA<PublicArtifactReleaseException>()
            .having((error) => error.message, 'message', contains('server'))
            .having(
              (error) => error.message,
              'message',
              contains('connection'),
            ),
      ),
    );
  });
}

PublicLeagueSnapshot _snapshot({
  String snapshotVersion = _snapshotA,
  PublicReleaseState state = PublicReleaseState.published,
  int homeScore = 82,
  String? forcedResultVersion,
  DateTime? generatedAt,
}) {
  final unbound = PublicGame(
    gameId: 'game-1',
    title: 'Home vs Away',
    startTime: DateTime.utc(2026, 9, 11),
    homeTeamId: 'home',
    homeTeamName: 'Home',
    awayTeamId: 'away',
    awayTeamName: 'Away',
    homeScore: homeScore,
    awayScore: 79,
    status: PublicGameStatus.finalResult,
    recap: 'Published recap',
  );
  final game = forcedResultVersion == null
      ? unbound.withComputedResultVersion()
      : PublicGame(
          gameId: unbound.gameId,
          title: unbound.title,
          startTime: unbound.startTime,
          homeTeamId: unbound.homeTeamId,
          homeTeamName: unbound.homeTeamName,
          awayTeamId: unbound.awayTeamId,
          awayTeamName: unbound.awayTeamName,
          homeScore: unbound.homeScore,
          awayScore: unbound.awayScore,
          status: unbound.status,
          resultVersion: forcedResultVersion,
          recap: unbound.recap,
        );
  return PublicLeagueSnapshot(
    leagueName: 'Jamaica Basketball Association',
    leagueShortName: 'JBA',
    seasonId: 'season-1',
    version: PublicSnapshotVersion(
      schemaVersion: 1,
      contractVersion: 'legacy-public-snapshot-v1.1',
      snapshotVersion: snapshotVersion,
      verificationStatus: 'legacyApproved',
      state: state,
      privacyEpoch: 7,
      generatedAt: generatedAt ?? DateTime.utc(2026, 9, 11),
    ),
    schedule: state == PublicReleaseState.published ? [game] : const [],
    standings: const [],
    leaderboards: const [],
  );
}

class _QueueReader implements PublicCurrentReleaseReader {
  final List<PublicLeagueSnapshot?> snapshots;
  int reads = 0;

  _QueueReader(this.snapshots);

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async {
    final index = reads < snapshots.length ? reads : snapshots.length - 1;
    reads++;
    return snapshots[index];
  }
}

class _ThrowingReader implements PublicCurrentReleaseReader {
  final Object error;

  _ThrowingReader(this.error);

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() => Future.error(error);
}
