import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../../models/public_league_snapshot.dart';

class PublicReleaseIntegrityException implements Exception {
  final String message;

  const PublicReleaseIntegrityException(this.message);

  @override
  String toString() => message;
}

/// Canonical digest shared with the dormant public-release-v2 projector.
abstract final class PublicReleaseIntegrity {
  static String digest(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  static Object? _canonical(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const PublicReleaseIntegrityException(
          'Public release contains a non-finite number.',
        );
      }
      if (value == 0) return 0;
      return value.truncateToDouble() == value ? value.toInt() : value;
    }
    if (value is num) return _canonical(value.toDouble());
    if (value is List) return value.map(_canonical).toList(growable: false);
    if (value is Map) {
      final entries = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const PublicReleaseIntegrityException(
            'Public release map keys must be strings.',
          );
        }
        entries[entry.key as String] = entry.value;
      }
      final keys = entries.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(entries[key])};
    }
    throw PublicReleaseIntegrityException(
      'Unsupported public release value ${value.runtimeType}.',
    );
  }
}

/// Verifies and joins one immutable manifest and every referenced page.
///
/// Kept separate from Firestore so integrity behavior has deterministic unit
/// coverage before the v2 rules and provider are activated together.
abstract final class VersionedPublicReleaseAssembler {
  static const protocolVersion = 'public-release-v2';
  static const maxPages = 64;
  static const maxDocumentBytes = 480 * 1024;
  static const _contentOrder = [
    'divisions',
    'teams',
    'schedule',
    'standings',
    'leaderboards',
  ];
  static final _sha256 = RegExp(r'^[a-f0-9]{64}$');

  static PublicLeagueSnapshot assemble({
    required Map<String, dynamic> pointer,
    required Map<String, dynamic> manifest,
    required List<Map<String, dynamic>> pages,
  }) {
    _require(pointer['protocolVersion'] == protocolVersion, 'pointer protocol');
    _require(
      manifest['protocolVersion'] == protocolVersion,
      'manifest protocol',
    );
    final releaseId = _hash(pointer['releaseId'], 'pointer releaseId');
    final sourceVersion = _hash(
      pointer['sourceVersion'],
      'pointer sourceVersion',
    );
    final releaseDigest = _hash(
      pointer['releaseDigest'],
      'pointer releaseDigest',
    );
    final sourceSequence = _integer(
      pointer['sourceSequence'],
      'sourceSequence',
    );
    _require(sourceSequence >= 0, 'sourceSequence');
    final sourceCommittedAt = _timestamp(
      pointer['sourceCommittedAt'],
      'sourceCommittedAt',
    );
    _require(manifest['releaseId'] == releaseId, 'manifest releaseId');
    _require(
      manifest['sourceVersion'] == sourceVersion,
      'manifest sourceVersion',
    );
    _require(
      manifest['releaseDigest'] == releaseDigest,
      'manifest releaseDigest',
    );
    _require(
      manifest['sourceSequence'] == sourceSequence,
      'manifest source sequence',
    );
    _require(
      manifest['sourceCommittedAt'] == sourceCommittedAt,
      'manifest source time',
    );
    _require(
      utf8.encode(jsonEncode(manifest)).length <= maxDocumentBytes,
      'manifest size',
    );
    _require(pointer['state'] == manifest['state'], 'publication state');
    _require(pointer['seasonId'] == manifest['seasonId'], 'season scope');
    _require(
      pointer['privacyEpoch'] == manifest['privacyEpoch'],
      'privacy epoch',
    );

    final metadata = _map(manifest['metadata'], 'metadata');
    final snapshotVersion = _hash(
      metadata['snapshotVersion'],
      'snapshotVersion',
    );
    final expectedReleaseId = PublicReleaseIntegrity.digest({
      'protocolVersion': protocolVersion,
      'snapshotVersion': snapshotVersion,
      'sourceVersion': sourceVersion,
      'sourceSequence': sourceSequence,
      'sourceCommittedAt': sourceCommittedAt,
    });
    _require(expectedReleaseId == releaseId, 'release identity');

    final pageRefs = _mapList(manifest['pages'], 'manifest pages');
    final pageCount = _integer(manifest['pageCount'], 'pageCount');
    _require(pageCount == pageRefs.length, 'page count');
    _require(pageCount <= maxPages, 'page bound');
    _require(pages.length == pageRefs.length, 'page coverage');
    final pagesById = <String, Map<String, dynamic>>{};
    for (final page in pages) {
      final id = _text(page['id'], 'page id');
      _require(!pagesById.containsKey(id), 'duplicate page id');
      pagesById[id] = page;
    }

    final assembled = {for (final type in _contentOrder) type: <Object?>[]};
    final expectedIndexes = {for (final type in _contentOrder) type: 0};
    for (final reference in pageRefs) {
      final id = _text(reference['id'], 'page reference id');
      final type = _text(reference['contentType'], 'content type');
      _require(_contentOrder.contains(type), 'content type');
      final pageIndex = _integer(reference['pageIndex'], 'page index');
      _require(pageIndex == expectedIndexes[type], 'page ordering');
      expectedIndexes[type] = pageIndex + 1;
      _require(
        id == '$type-${pageIndex.toString().padLeft(4, '0')}',
        'page id',
      );
      final page = pagesById[id];
      _require(page != null, 'missing page');
      final storedPage = Map<String, dynamic>.from(page!)..remove('id');
      _require(
        utf8.encode(jsonEncode(storedPage)).length <= maxDocumentBytes,
        'page size',
      );
      _require(page['protocolVersion'] == protocolVersion, 'page protocol');
      _require(page['releaseId'] == releaseId, 'page releaseId');
      _require(page['sourceVersion'] == sourceVersion, 'page sourceVersion');
      _require(page['contentType'] == type, 'page content type');
      _require(page['pageIndex'] == pageIndex, 'page index');
      final items = _list(page['items'], 'page items');
      _require(page['itemCount'] == items.length, 'page item count');
      _require(reference['itemCount'] == items.length, 'reference item count');
      final pageDigest = _hash(page['pageDigest'], 'page digest');
      _require(reference['pageDigest'] == pageDigest, 'reference page digest');
      final withoutDigest = Map<String, dynamic>.from(page)
        ..remove('id')
        ..remove('pageDigest');
      _require(
        PublicReleaseIntegrity.digest(withoutDigest) == pageDigest,
        'page digest verification',
      );
      assembled[type]!.addAll(items);
    }

    final counts = _map(manifest['counts'], 'counts');
    for (final type in _contentOrder) {
      _require(counts[type] == assembled[type]!.length, '$type coverage');
    }
    final expectedManifestDigest = PublicReleaseIntegrity.digest({
      'releaseId': releaseId,
      'sourceVersion': sourceVersion,
      'sourceSequence': sourceSequence,
      'sourceCommittedAt': sourceCommittedAt,
      'metadata': metadata,
      'pageRefs': pageRefs,
      'counts': counts,
    });
    _require(expectedManifestDigest == releaseDigest, 'manifest digest');

    final map = <String, dynamic>{...metadata};
    for (final type in _contentOrder) {
      map[type] = assembled[type];
    }
    final snapshot = PublicLeagueSnapshot.fromMap(map);
    _require(snapshot.seasonId == pointer['seasonId'], 'assembled season');
    _require(
      snapshot.version.snapshotVersion == snapshotVersion,
      'assembled version',
    );
    _require(
      snapshot.version.privacyEpoch == pointer['privacyEpoch'],
      'assembled privacy epoch',
    );
    _require(
      snapshot.version.state.name == pointer['state'],
      'assembled state',
    );
    _require(
      snapshot.generatedAt.toUtc().toIso8601String() == sourceCommittedAt,
      'assembled source time',
    );
    return snapshot;
  }

  static Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _mapList(Object? value, String field) {
    if (value is! List) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return value.map((item) => _map(item, field)).toList(growable: false);
  }

  static List<Object?> _list(Object? value, String field) {
    if (value is! List) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return List<Object?>.from(value);
  }

  static String _text(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return value;
  }

  static String _hash(Object? value, String field) {
    final result = _text(value, field);
    if (!_sha256.hasMatch(result)) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return result;
  }

  static int _integer(Object? value, String field) {
    if (value is! int) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return value;
  }

  static String _timestamp(Object? value, String field) {
    final result = _text(value, field);
    final parsed = DateTime.tryParse(result);
    if (parsed == null || parsed.toUtc().toIso8601String() != result) {
      throw PublicReleaseIntegrityException('$field is invalid.');
    }
    return result;
  }

  static void _require(bool condition, String field) {
    if (!condition) {
      throw PublicReleaseIntegrityException('$field failed verification.');
    }
  }
}

/// Dormant v2 client. Do not connect this to the active provider until its
/// rules, source-token writer, projector, and path cut over atomically.
class DormantVersionedPublicReleaseRepository {
  static const currentPointerPath = 'publicData/jba/releasePointers/current';
  static const releaseRootPath = 'publicData/jba/releases';

  final FirebaseFirestore _db;

  DormantVersionedPublicReleaseRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Stream<PublicLeagueSnapshot?> watchCurrentRelease() => _db
      .doc(currentPointerPath)
      .snapshots()
      .asyncMap((pointer) => pointer.exists ? _load(pointer.data()!) : null);

  Future<PublicLeagueSnapshot> _load(Map<String, dynamic> pointer) async {
    final releaseId = pointer['releaseId'];
    if (releaseId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(releaseId)) {
      throw const PublicReleaseIntegrityException(
        'Pointer releaseId is invalid.',
      );
    }
    final expectedManifestPath = '$releaseRootPath/$releaseId';
    if (pointer['manifestPath'] != expectedManifestPath) {
      throw const PublicReleaseIntegrityException(
        'Pointer manifest path is invalid.',
      );
    }
    final manifestRef = _db.doc(expectedManifestPath);
    final manifestSnapshot = await manifestRef.get();
    if (!manifestSnapshot.exists) {
      throw const PublicReleaseIntegrityException(
        'Public manifest is missing.',
      );
    }
    final manifest = manifestSnapshot.data()!;
    final pageRefs = VersionedPublicReleaseAssembler._mapList(
      manifest['pages'],
      'manifest pages',
    );
    if (pageRefs.length > VersionedPublicReleaseAssembler.maxPages) {
      throw const PublicReleaseIntegrityException(
        'Public page bound exceeded.',
      );
    }
    final pages = await Future.wait(
      pageRefs.map((reference) async {
        final id = VersionedPublicReleaseAssembler._text(
          reference['id'],
          'page id',
        );
        final snapshot = await manifestRef.collection('pages').doc(id).get();
        if (!snapshot.exists) {
          throw PublicReleaseIntegrityException('Public page $id is missing.');
        }
        return <String, dynamic>{'id': id, ...snapshot.data()!};
      }),
    );
    final result = VersionedPublicReleaseAssembler.assemble(
      pointer: pointer,
      manifest: manifest,
      pages: pages,
    );
    final current = await _db.doc(currentPointerPath).get();
    if (!current.exists || !_samePointer(pointer, current.data()!)) {
      throw const PublicReleaseIntegrityException(
        'Public release changed while pages were loading.',
      );
    }
    return result;
  }

  bool _samePointer(Map<String, dynamic> first, Map<String, dynamic> second) {
    const fields = [
      'protocolVersion',
      'releaseId',
      'releaseDigest',
      'sourceVersion',
      'sourceSequence',
      'sourceCommittedAt',
      'state',
      'seasonId',
      'privacyEpoch',
      'manifestPath',
    ];
    return fields.every((field) => first[field] == second[field]);
  }
}
