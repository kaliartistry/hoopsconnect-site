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
        .map(
          (doc) => DivisionReference(
            kind: DivisionReferenceKind.team,
            id: doc.id,
            path: doc.reference.path,
            displayName: divisionReferenceDisplayName(
              doc.data()['name'],
              fallback: 'Unnamed team (${doc.id})',
            ),
          ),
        )
        .toList(growable: false);
    final events = results[1].docs
        .map(
          (doc) => DivisionReference(
            kind: DivisionReferenceKind.event,
            id: doc.id,
            path: doc.reference.path,
            displayName: divisionReferenceDisplayName(
              doc.data()['title'],
              fallback: 'Untitled scheduled event (${doc.id})',
            ),
          ),
        )
        .toList(growable: false);
    return DivisionDependencyReport(
      teamReferences: teams,
      eventReferences: events,
    );
  }
}

enum DivisionReferenceKind { team, event }

class DivisionReference {
  final DivisionReferenceKind kind;
  final String id;
  final String path;
  final String displayName;

  const DivisionReference({
    required this.kind,
    required this.id,
    required this.path,
    required this.displayName,
  });
}

class DivisionDependencyReport {
  final List<DivisionReference> teamReferences;
  final List<DivisionReference> eventReferences;

  const DivisionDependencyReport({
    this.teamReferences = const [],
    this.eventReferences = const [],
  });

  bool get hasReferences =>
      teamReferences.isNotEmpty || eventReferences.isNotEmpty;

  int get totalReferences => teamReferences.length + eventReferences.length;

  String get summary {
    final parts = <String>[];
    if (teamReferences.isNotEmpty) {
      parts.add(
        '${teamReferences.length} team${teamReferences.length == 1 ? '' : 's'}',
      );
    }
    if (eventReferences.isNotEmpty) {
      parts.add(
        '${eventReferences.length} scheduled event${eventReferences.length == 1 ? '' : 's'}',
      );
    }
    return parts.join(' and ');
  }
}

String divisionReferenceDisplayName(Object? value, {required String fallback}) {
  if (value is! String || value.trim().isEmpty) return fallback;
  return value.trim();
}
