import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/division_model.dart';

class DivisionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<DivisionModel> _divisionsRef(String assocId) {
    return _db
        .collection(FirestorePaths.divisions(assocId))
        .withConverter<DivisionModel>(
          fromFirestore: (snap, _) => DivisionModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<List<DivisionModel>> watchDivisions(String assocId) {
    return _divisionsRef(assocId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> createDivision(String assocId, DivisionModel division) {
    final docRef = division.id.isEmpty
        ? _divisionsRef(assocId).doc()
        : _divisionsRef(assocId).doc(division.id);
    return docRef.set(division);
  }

  Future<void> updateDivision(
    String assocId,
    String divisionId,
    Map<String, dynamic> data,
  ) {
    return _db
        .doc(FirestorePaths.division(assocId, divisionId))
        .update(data);
  }

  Future<void> deleteDivision(String assocId, String divisionId) {
    return _db
        .doc(FirestorePaths.division(assocId, divisionId))
        .delete();
  }
}
