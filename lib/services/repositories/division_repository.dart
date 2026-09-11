import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math';
import '../../core/constants/firestore_paths.dart';
import '../../models/division_model.dart';

class DivisionRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions? _functions;
  final Future<Map<String, dynamic>> Function(String, Map<String, Object?>)?
  _callable;
  final Random _random;

  DivisionRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Future<Map<String, dynamic>> Function(String, Map<String, Object?>)?
    callable,
    Random? random,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions,
       _callable = callable,
       _random = random ?? Random.secure();

  String newDeleteOperationId({DateTime? now}) {
    final entropy = List.generate(
      12,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'division_${(now ?? DateTime.now()).toUtc().microsecondsSinceEpoch}_$entropy';
  }

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
  ) async {
    if (data.containsKey('version') || data.containsKey('deletionPending')) {
      throw ArgumentError(
        'Division versions and deletion guards are server controlled',
      );
    }
    final reference = _db.doc(FirestorePaths.division(assocId, divisionId));
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw StateError('Division not found');
      final storedVersion = snapshot.data()?['version'];
      if (storedVersion is! int || storedVersion < 1) {
        throw StateError(
          'Division must be migrated to a versioned record before editing',
        );
      }
      transaction.update(reference, {
        ...data,
        'version': storedVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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

  Future<DivisionDeleteReceipt> deleteIfUnreferenced({
    required String operationId,
    required String divisionId,
    required int expectedDivisionVersion,
  }) async {
    final request = <String, Object?>{
      'schemaVersion': 1,
      'operationId': operationId,
      'divisionId': divisionId,
      'expectedDivisionVersion': expectedDivisionVersion,
    };
    try {
      final Map<String, dynamic> result;
      if (_callable != null) {
        result = await _callable('deleteDivisionIfUnreferenced', request);
      } else {
        final response = await (_functions ?? FirebaseFunctions.instance)
            .httpsCallable('deleteDivisionIfUnreferenced')
            .call<Map<Object?, Object?>>(request);
        result = response.data.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return DivisionDeleteReceipt.fromMap(result);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(
        error.message ??
            'The division deletion service could not complete this request.',
      );
    }
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
