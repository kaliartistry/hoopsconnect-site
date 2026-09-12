import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/public_league_snapshot.dart';
import '../public_artifact_release_validator.dart';

abstract interface class PublicLeagueSnapshotDocumentReader {
  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot();

  Future<PublicLeagueSnapshot?> readCurrentSnapshot({
    required GetOptions options,
  });
}

class FirestorePublicLeagueSnapshotDocumentReader
    implements PublicLeagueSnapshotDocumentReader {
  final DocumentReference<PublicLeagueSnapshot> _currentSnapshot;

  FirestorePublicLeagueSnapshotDocumentReader({FirebaseFirestore? firestore})
    : _currentSnapshot = (firestore ?? FirebaseFirestore.instance)
          .doc(PublicLeagueRepository.currentSnapshotPath)
          .withConverter<PublicLeagueSnapshot>(
            fromFirestore: (snapshot, _) =>
                PublicLeagueSnapshot.fromMap(snapshot.data()!),
            toFirestore: (_, _) => throw UnsupportedError(
              'Public snapshots are server-written and read-only to app clients.',
            ),
          );

  @override
  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot() => _currentSnapshot
      .snapshots()
      .map((snapshot) => snapshot.exists ? snapshot.data() : null);

  @override
  Future<PublicLeagueSnapshot?> readCurrentSnapshot({
    required GetOptions options,
  }) async {
    final snapshot = await _currentSnapshot.get(options);
    return snapshot.exists ? snapshot.data() : null;
  }
}

class PublicLeagueRepository implements PublicCurrentReleaseReader {
  static const currentSnapshotPath = 'publicData/jba/snapshots/current';

  final PublicLeagueSnapshotDocumentReader _documents;

  PublicLeagueRepository({FirebaseFirestore? firestore})
    : _documents = FirestorePublicLeagueSnapshotDocumentReader(
        firestore: firestore,
      );

  PublicLeagueRepository.withDocumentReader(this._documents);

  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot() =>
      _documents.watchCurrentSnapshot();

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() => _documents
      .readCurrentSnapshot(options: const GetOptions(source: Source.server));
}
