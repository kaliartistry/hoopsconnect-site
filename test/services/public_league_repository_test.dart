import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/repositories/public_league_repository.dart';

void main() {
  test('artifact read requires the Firestore server source', () async {
    final expected = _snapshot();
    final reader = _FakeSnapshotDocumentReader(snapshot: expected);
    final repository = PublicLeagueRepository.withDocumentReader(reader);

    final result = await repository.readCurrentRelease();

    expect(result, same(expected));
    expect(reader.readSources, [Source.server]);
  });

  test(
    'display stream does not trigger an authoritative document get',
    () async {
      final expected = _snapshot();
      final reader = _FakeSnapshotDocumentReader(snapshot: expected);
      final repository = PublicLeagueRepository.withDocumentReader(reader);

      expect(await repository.watchCurrentSnapshot().first, same(expected));
      expect(reader.readSources, isEmpty);
    },
  );

  test(
    'offline server read propagates instead of returning cached data',
    () async {
      final reader = _FakeSnapshotDocumentReader(
        readError: StateError('server unavailable'),
      );
      final repository = PublicLeagueRepository.withDocumentReader(reader);

      await expectLater(repository.readCurrentRelease(), throwsStateError);
      expect(reader.readSources, [Source.server]);
    },
  );
}

PublicLeagueSnapshot _snapshot() => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    verificationStatus: 'legacyApproved',
    state: PublicReleaseState.published,
    privacyEpoch: 7,
    generatedAt: DateTime.utc(2026, 9, 11),
  ),
  schedule: const [],
  standings: const [],
  leaderboards: const [],
);

class _FakeSnapshotDocumentReader
    implements PublicLeagueSnapshotDocumentReader {
  final PublicLeagueSnapshot? snapshot;
  final Object? readError;
  final List<Source> readSources = [];

  _FakeSnapshotDocumentReader({this.snapshot, this.readError});

  @override
  Future<PublicLeagueSnapshot?> readCurrentSnapshot({
    required GetOptions options,
  }) async {
    readSources.add(options.source);
    if (readError != null) throw readError!;
    return snapshot;
  }

  @override
  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot() async* {
    yield snapshot;
  }
}
