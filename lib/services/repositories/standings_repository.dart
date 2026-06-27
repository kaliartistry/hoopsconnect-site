import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/standings_model.dart';

class StandingsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<StandingsModel> _standingsRef(String assocId) {
    return _db
        .collection(FirestorePaths.standings(assocId))
        .withConverter<StandingsModel>(
          fromFirestore: (snap, _) => StandingsModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<StandingsModel?> watchStandings(
    String assocId,
    String seasonId, {
    String? divisionId,
  }) {
    final compositeId = '${seasonId}_${divisionId ?? 'all'}';
    return _standingsRef(assocId).doc(compositeId).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }
}
