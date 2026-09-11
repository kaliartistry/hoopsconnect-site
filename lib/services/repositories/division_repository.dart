import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/division_model.dart';

class DivisionRepository {
  final FirebaseFirestore _db;

  DivisionRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

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
    return _db.doc(FirestorePaths.division(assocId, divisionId)).update(data);
  }

  Future<void> setArchived(
    String assocId,
    String divisionId, {
    required bool archived,
  }) {
    return updateDivision(assocId, divisionId, {
      'status': archived
          ? DivisionStatus.archived.name
          : DivisionStatus.active.name,
      'archivedAt': archived ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<DivisionDependencyReport> inspectDependencies(
    String assocId,
    String divisionId,
  ) async {
    final results = await Future.wait([
      _db
          .collection(FirestorePaths.teams(assocId))
          .where('divisionId', isEqualTo: divisionId)
          .get(),
      _db
          .collection(FirestorePaths.events(assocId))
          .where('divisionId', isEqualTo: divisionId)
          .get(),
    ]);
    final teams = results[0].docs
        .map((doc) => doc.data()['name'])
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
    final events = results[1].docs
        .map((doc) => doc.data()['title'])
        .whereType<String>()
        .where((title) => title.trim().isNotEmpty)
        .toList(growable: false);
    return DivisionDependencyReport(teamNames: teams, eventTitles: events);
  }

  /// Best-effort legacy protection. The integration request replaces this
  /// client-side check with one server transaction before release.
  Future<DivisionDependencyReport> deleteIfUnreferenced(
    String assocId,
    String divisionId,
  ) async {
    final dependencies = await inspectDependencies(assocId, divisionId);
    if (!dependencies.canDelete) return dependencies;
    await deleteDivision(assocId, divisionId);
    return dependencies;
  }

  Future<void> deleteDivision(String assocId, String divisionId) {
    return _db.doc(FirestorePaths.division(assocId, divisionId)).delete();
  }
}

class DivisionDependencyReport {
  final List<String> teamNames;
  final List<String> eventTitles;

  const DivisionDependencyReport({
    this.teamNames = const [],
    this.eventTitles = const [],
  });

  bool get canDelete => teamNames.isEmpty && eventTitles.isEmpty;

  int get totalReferences => teamNames.length + eventTitles.length;

  String get summary {
    final parts = <String>[];
    if (teamNames.isNotEmpty) {
      parts.add('${teamNames.length} team${teamNames.length == 1 ? '' : 's'}');
    }
    if (eventTitles.isNotEmpty) {
      parts.add(
        '${eventTitles.length} scheduled event${eventTitles.length == 1 ? '' : 's'}',
      );
    }
    return parts.join(' and ');
  }
}
