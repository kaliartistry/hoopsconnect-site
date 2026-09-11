import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/public_league_snapshot.dart';
import '../public_artifact_release_validator.dart';

class PublicLeagueRepository implements PublicCurrentReleaseReader {
  static const currentSnapshotPath = 'publicData/jba/snapshots/current';

  final FirebaseFirestore _db;

  PublicLeagueRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<PublicLeagueSnapshot> get _currentSnapshot => _db
      .doc(currentSnapshotPath)
      .withConverter<PublicLeagueSnapshot>(
        fromFirestore: (snapshot, _) =>
            PublicLeagueSnapshot.fromMap(snapshot.data()!),
        toFirestore: (_, _) => throw UnsupportedError(
          'Public snapshots are server-written and read-only to app clients.',
        ),
      );

  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot() => _currentSnapshot
      .snapshots()
      .map((snapshot) => snapshot.exists ? snapshot.data() : null);

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async {
    final snapshot = await _currentSnapshot.get();
    return snapshot.exists ? snapshot.data() : null;
  }
}
