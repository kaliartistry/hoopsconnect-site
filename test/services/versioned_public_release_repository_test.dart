import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/repositories/versioned_public_release_repository.dart';

const _snapshotVersion =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _sourceVersion =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _otherSourceVersion =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

void main() {
  test('assembles all exact manifest pages into one public snapshot', () {
    final fixture = _releaseFixture();

    final snapshot = VersionedPublicReleaseAssembler.assemble(
      pointer: fixture.pointer,
      manifest: fixture.manifest,
      pages: fixture.pages,
    );

    expect(snapshot.version.state, PublicReleaseState.published);
    expect(snapshot.version.releaseId, fixture.pointer['releaseId']);
    expect(snapshot.teams.single.name, 'Home Team');
    expect(snapshot.schedule.single.gameId, 'game-1');
  });

  test('rejects a page changed after the manifest was created', () {
    final fixture = _releaseFixture();
    final pages = fixture.pages
        .map((page) => Map<String, dynamic>.from(page))
        .toList(growable: false);
    final schedulePage = pages.singleWhere(
      (page) => page['contentType'] == 'schedule',
    );
    schedulePage['items'] = [
      {
        ...Map<String, dynamic>.from((schedulePage['items'] as List).single),
        'title': 'Tampered result',
      },
    ];

    expect(
      () => VersionedPublicReleaseAssembler.assemble(
        pointer: fixture.pointer,
        manifest: fixture.manifest,
        pages: pages,
      ),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );
  });

  test('rejects missing, duplicate, oversized, and stale release data', () {
    final fixture = _releaseFixture();
    expect(
      () => VersionedPublicReleaseAssembler.assemble(
        pointer: fixture.pointer,
        manifest: fixture.manifest,
        pages: fixture.pages.take(1).toList(),
      ),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );
    expect(
      () => VersionedPublicReleaseAssembler.assemble(
        pointer: fixture.pointer,
        manifest: fixture.manifest,
        pages: [...fixture.pages, fixture.pages.first],
      ),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );
    expect(
      () => VersionedPublicReleaseAssembler.assemble(
        pointer: {...fixture.pointer, 'sourceVersion': _otherSourceVersion},
        manifest: fixture.manifest,
        pages: fixture.pages,
      ),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );

    final oversized = Map<String, dynamic>.from(fixture.manifest)
      ..['unusedPadding'] = List.filled(
        VersionedPublicReleaseAssembler.maxDocumentBytes,
        'x',
      ).join();
    expect(
      () => VersionedPublicReleaseAssembler.assemble(
        pointer: fixture.pointer,
        manifest: oversized,
        pages: fixture.pages,
      ),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );
  });

  test('assembles a retraction without carrying published rows', () {
    final fixture = _releaseFixture(retracted: true);

    final snapshot = VersionedPublicReleaseAssembler.assemble(
      pointer: fixture.pointer,
      manifest: fixture.manifest,
      pages: fixture.pages,
    );

    expect(snapshot.version.state, PublicReleaseState.retracted);
    expect(snapshot.schedule, isEmpty);
    expect(snapshot.teams, isEmpty);
  });

  test(
    'repository loads the manifest and every page through its adapter',
    () async {
      final fixture = _releaseFixture();
      final reader = _FakeDocumentReader.fromFixture(fixture);
      final repository =
          DormantVersionedPublicReleaseRepository.withDocumentReader(reader);

      final snapshot = await repository.readCurrentRelease();

      expect(snapshot?.teams.single.name, 'Home Team');
      expect(snapshot?.schedule.single.gameId, 'game-1');
      expect(reader.pointerReads, 2);
      expect(reader.readRequests, hasLength(fixture.pages.length + 3));
      expect(
        reader.readRequests.map((request) => request.source),
        everyElement(Source.server),
      );
      expect(
        reader.readPaths.where((path) => path.contains('/pages/')).length,
        fixture.pages.length,
      );
    },
  );

  test(
    'repository rejects a pointer changed while pages are loading',
    () async {
      final fixture = _releaseFixture();
      final changedPointer = {
        ...fixture.pointer,
        'sourceSequence': (fixture.pointer['sourceSequence'] as int) + 1,
      };
      final reader = _FakeDocumentReader.fromFixture(
        fixture,
        pointerReads: [fixture.pointer, changedPointer],
      );
      final repository =
          DormantVersionedPublicReleaseRepository.withDocumentReader(reader);

      await expectLater(
        repository.readCurrentRelease(),
        throwsA(
          isA<PublicReleaseIntegrityException>().having(
            (error) => error.message,
            'message',
            contains('changed while pages were loading'),
          ),
        ),
      );
    },
  );

  test('repository fails closed when a referenced page is absent', () async {
    final fixture = _releaseFixture();
    final reader = _FakeDocumentReader.fromFixture(fixture);
    final pageId = fixture.pages.first['id'];
    reader.documents.remove('${fixture.pointer['manifestPath']}/pages/$pageId');
    final repository =
        DormantVersionedPublicReleaseRepository.withDocumentReader(reader);

    await expectLater(
      repository.readCurrentRelease(),
      throwsA(isA<PublicReleaseIntegrityException>()),
    );
  });

  test('repository never falls back to cached release data offline', () async {
    final fixture = _releaseFixture();
    final reader = _FakeDocumentReader.fromFixture(
      fixture,
      readError: StateError('server unavailable'),
    );
    final repository =
        DormantVersionedPublicReleaseRepository.withDocumentReader(reader);

    await expectLater(repository.readCurrentRelease(), throwsStateError);
    expect(reader.readRequests, hasLength(1));
    expect(reader.readRequests.single.source, Source.server);
  });
}

({
  Map<String, dynamic> pointer,
  Map<String, dynamic> manifest,
  List<Map<String, dynamic>> pages,
})
_releaseFixture({bool retracted = false}) {
  final state = retracted ? 'retracted' : 'published';
  final metadata = <String, dynamic>{
    'associationId': 'jba',
    'schemaVersion': 1,
    'contractVersion': 'legacy-public-snapshot-v1.1',
    'published': !retracted,
    'certificationStatus': 'compatibilityCandidate',
    'publicationState': state,
    'snapshotVersion': _snapshotVersion,
    'generatedAt': '2026-09-11T12:00:00.000Z',
    'privacyEpoch': 7,
    'publication': {
      'state': state,
      'contractVersion': 'legacy-public-snapshot-v1.1',
      'snapshotVersion': _snapshotVersion,
      'verificationStatus': 'compatibilityCandidate',
      'privacyEpoch': 7,
      'generatedAt': '2026-09-11T12:00:00.000Z',
    },
    'league': {'name': 'Jamaica Basketball Association', 'shortName': 'JBA'},
    'seasonId': 'season-1',
    'season': {'seasonId': 'season-1', 'name': '2026 NBL'},
    'standingsPolicyLabel': null,
  };
  final content = <String, List<Object?>>{
    'divisions': [],
    'teams': retracted
        ? []
        : [
            {'teamId': 'home', 'name': 'Home Team', 'divisionId': null},
          ],
    'schedule': retracted
        ? []
        : [
            {
              'gameId': 'game-1',
              'title': 'Home Team vs Away Team',
              'startTime': '2026-09-11T20:00:00.000Z',
              'status': 'scheduled',
            },
          ],
    'standings': [],
    'leaderboards': [],
  };
  final releaseId = PublicReleaseIntegrity.digest({
    'protocolVersion': VersionedPublicReleaseAssembler.protocolVersion,
    'snapshotVersion': _snapshotVersion,
    'sourceVersion': _sourceVersion,
    'sourceSequence': 42,
    'sourceCommittedAt': '2026-09-11T12:00:00.000Z',
  });
  final pages = <Map<String, dynamic>>[];
  final pageRefs = <Map<String, dynamic>>[];
  for (final entry in content.entries) {
    if (entry.value.isEmpty) continue;
    final id = '${entry.key}-0000';
    final body = <String, dynamic>{
      'protocolVersion': VersionedPublicReleaseAssembler.protocolVersion,
      'releaseId': releaseId,
      'sourceVersion': _sourceVersion,
      'contentType': entry.key,
      'pageIndex': 0,
      'itemCount': entry.value.length,
      'items': entry.value,
    };
    final pageDigest = PublicReleaseIntegrity.digest(body);
    pages.add({'id': id, ...body, 'pageDigest': pageDigest});
    pageRefs.add({
      'id': id,
      'contentType': entry.key,
      'pageIndex': 0,
      'itemCount': entry.value.length,
      'pageDigest': pageDigest,
    });
  }
  final counts = {
    for (final entry in content.entries) entry.key: entry.value.length,
  };
  final releaseDigest = PublicReleaseIntegrity.digest({
    'releaseId': releaseId,
    'sourceVersion': _sourceVersion,
    'sourceSequence': 42,
    'sourceCommittedAt': '2026-09-11T12:00:00.000Z',
    'metadata': metadata,
    'pageRefs': pageRefs,
    'counts': counts,
  });
  final manifest = <String, dynamic>{
    'protocolVersion': VersionedPublicReleaseAssembler.protocolVersion,
    'releaseId': releaseId,
    'sourceVersion': _sourceVersion,
    'sourceSequence': 42,
    'sourceCommittedAt': '2026-09-11T12:00:00.000Z',
    'releaseDigest': releaseDigest,
    'state': state,
    'seasonId': 'season-1',
    'privacyEpoch': 7,
    'pageCount': pages.length,
    'pages': pageRefs,
    'counts': counts,
    'metadata': metadata,
  };
  final pointer = <String, dynamic>{
    'protocolVersion': VersionedPublicReleaseAssembler.protocolVersion,
    'associationId': 'jba',
    'releaseId': releaseId,
    'manifestPath': 'publicData/jba/releases/$releaseId',
    'releaseDigest': releaseDigest,
    'sourceVersion': _sourceVersion,
    'sourceSequence': 42,
    'sourceCommittedAt': '2026-09-11T12:00:00.000Z',
    'state': state,
    'seasonId': 'season-1',
    'privacyEpoch': 7,
  };
  return (pointer: pointer, manifest: manifest, pages: pages);
}

class _FakeDocumentReader implements PublicReleaseDocumentReader {
  final Map<String, Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> _pointerResponses;
  final Object? readError;
  final List<String> readPaths = [];
  final List<({String path, Source source})> readRequests = [];
  int pointerReads = 0;

  _FakeDocumentReader(this.documents, this._pointerResponses, {this.readError});

  factory _FakeDocumentReader.fromFixture(
    ({
      Map<String, dynamic> pointer,
      Map<String, dynamic> manifest,
      List<Map<String, dynamic>> pages,
    })
    fixture, {
    List<Map<String, dynamic>>? pointerReads,
    Object? readError,
  }) {
    final manifestPath = fixture.pointer['manifestPath'] as String;
    return _FakeDocumentReader(
      {
        manifestPath: fixture.manifest,
        for (final page in fixture.pages)
          '$manifestPath/pages/${page['id']}': Map<String, dynamic>.from(page)
            ..remove('id'),
      },
      pointerReads ?? [fixture.pointer],
      readError: readError,
    );
  }

  @override
  Future<Map<String, dynamic>?> readDocument(
    String path, {
    required GetOptions options,
  }) async {
    readPaths.add(path);
    readRequests.add((path: path, source: options.source));
    if (readError != null) throw readError!;
    if (path == DormantVersionedPublicReleaseRepository.currentPointerPath) {
      final index = pointerReads < _pointerResponses.length
          ? pointerReads
          : _pointerResponses.length - 1;
      pointerReads++;
      return Map<String, dynamic>.from(_pointerResponses[index]);
    }
    final value = documents[path];
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Stream<Map<String, dynamic>?> watchDocument(String path) async* {
    yield Map<String, dynamic>.from(_pointerResponses.first);
  }
}
