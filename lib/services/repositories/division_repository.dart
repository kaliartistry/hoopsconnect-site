import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/firestore_paths.dart';
import '../../models/division_model.dart';

class DivisionRepository {
  final FirebaseFirestore? _configuredFirestore;
  final FirebaseFunctions? _functions;
  final Future<Map<String, dynamic>> Function(String, Map<String, Object?>)?
  _callable;
  final Random _random;
  final DivisionDeleteOperationStore _deleteOperationStore;

  DivisionRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Future<Map<String, dynamic>> Function(String, Map<String, Object?>)?
    callable,
    Random? random,
    DivisionDeleteOperationStore? deleteOperationStore,
  }) : _configuredFirestore = firestore,
       _functions = functions,
       _callable = callable,
       _random = random ?? Random.secure(),
       _deleteOperationStore =
           deleteOperationStore ??
           SharedPreferencesDivisionDeleteOperationStore();

  FirebaseFirestore get _db =>
      _configuredFirestore ?? FirebaseFirestore.instance;

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
    required String actorId,
    required String associationId,
    required String divisionId,
    required int expectedDivisionVersion,
  }) async {
    final saved = await _deleteOperationStore.load(
      actorId: actorId,
      associationId: associationId,
      divisionId: divisionId,
    );
    if (saved != null &&
        saved.expectedDivisionVersion != expectedDivisionVersion) {
      throw StateError(
        'A protected deletion for an earlier division version must be resumed before starting another.',
      );
    }
    final operation =
        saved ??
        DivisionDeleteOperation(
          actorId: actorId,
          associationId: associationId,
          divisionId: divisionId,
          expectedDivisionVersion: expectedDivisionVersion,
          operationId: newDeleteOperationId(),
        );
    if (saved == null) await _deleteOperationStore.save(operation);
    final request = <String, Object?>{
      'schemaVersion': 1,
      'operationId': operation.operationId,
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
      final receipt = DivisionDeleteReceipt.fromMap(result);
      if (receipt.operationId != operation.operationId ||
          receipt.divisionVersion != operation.expectedDivisionVersion) {
        throw const FormatException(
          'Division deletion receipt does not match the saved operation',
        );
      }
      await _deleteOperationStore.clear(operation);
      return receipt;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(
        error.message ??
            'The division deletion service could not complete this request.',
      );
    }
  }

  Future<DivisionDeleteOperation?> pendingDeleteOperation({
    required String actorId,
    required String associationId,
    required String divisionId,
  }) {
    return _deleteOperationStore.load(
      actorId: actorId,
      associationId: associationId,
      divisionId: divisionId,
    );
  }
}

class DivisionDeleteOperation {
  static const schemaVersion = 1;

  final String actorId;
  final String associationId;
  final String divisionId;
  final int expectedDivisionVersion;
  final String operationId;

  const DivisionDeleteOperation({
    required this.actorId,
    required this.associationId,
    required this.divisionId,
    required this.expectedDivisionVersion,
    required this.operationId,
  });

  Map<String, Object> toMap() => {
    'schemaVersion': schemaVersion,
    'actorId': actorId,
    'associationId': associationId,
    'divisionId': divisionId,
    'expectedDivisionVersion': expectedDivisionVersion,
    'operationId': operationId,
  };

  factory DivisionDeleteOperation.fromMap(Map<String, dynamic> map) {
    const allowedKeys = {
      'schemaVersion',
      'actorId',
      'associationId',
      'divisionId',
      'expectedDivisionVersion',
      'operationId',
    };
    final actorId = map['actorId'];
    final associationId = map['associationId'];
    final divisionId = map['divisionId'];
    final operationId = map['operationId'];
    final scopeIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
    final operationIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$');
    if (map.length != allowedKeys.length ||
        map.keys.any((key) => !allowedKeys.contains(key)) ||
        map['schemaVersion'] != schemaVersion ||
        map['actorId'] is! String ||
        map['associationId'] is! String ||
        map['divisionId'] is! String ||
        map['expectedDivisionVersion'] is! int ||
        (map['expectedDivisionVersion'] as int) < 1 ||
        map['operationId'] is! String ||
        (actorId as String).isEmpty ||
        actorId.length > 128 ||
        !scopeIdPattern.hasMatch(associationId as String) ||
        !scopeIdPattern.hasMatch(divisionId as String) ||
        !operationIdPattern.hasMatch(operationId as String)) {
      throw const FormatException('Invalid saved division deletion operation');
    }
    return DivisionDeleteOperation(
      actorId: map['actorId'] as String,
      associationId: map['associationId'] as String,
      divisionId: map['divisionId'] as String,
      expectedDivisionVersion: map['expectedDivisionVersion'] as int,
      operationId: map['operationId'] as String,
    );
  }

  bool matches(DivisionDeleteOperation other) =>
      actorId == other.actorId &&
      associationId == other.associationId &&
      divisionId == other.divisionId &&
      expectedDivisionVersion == other.expectedDivisionVersion &&
      operationId == other.operationId;
}

abstract interface class DivisionDeleteOperationStore {
  Future<DivisionDeleteOperation?> load({
    required String actorId,
    required String associationId,
    required String divisionId,
  });

  Future<void> save(DivisionDeleteOperation operation);

  Future<void> clear(DivisionDeleteOperation operation);
}

class SharedPreferencesDivisionDeleteOperationStore
    implements DivisionDeleteOperationStore {
  static const _keyPrefix = 'hoopsconnect.division-delete.v1';

  String _key(String actorId, String associationId, String divisionId) =>
      '$_keyPrefix.${Uri.encodeComponent(actorId)}.'
      '${Uri.encodeComponent(associationId)}.${Uri.encodeComponent(divisionId)}';

  @override
  Future<DivisionDeleteOperation?> load({
    required String actorId,
    required String associationId,
    required String divisionId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(actorId, associationId, divisionId));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid saved division deletion operation');
    }
    final operation = DivisionDeleteOperation.fromMap(
      Map<String, dynamic>.from(decoded),
    );
    if (operation.actorId != actorId ||
        operation.associationId != associationId ||
        operation.divisionId != divisionId) {
      throw const FormatException('Saved division deletion scope mismatch');
    }
    return operation;
  }

  @override
  Future<void> save(DivisionDeleteOperation operation) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(
      operation.actorId,
      operation.associationId,
      operation.divisionId,
    );
    if (preferences.containsKey(key)) {
      throw StateError('A protected division deletion is already pending');
    }
    final saved = await preferences.setString(
      key,
      jsonEncode(operation.toMap()),
    );
    if (!saved) {
      throw StateError('The protected division deletion could not be saved');
    }
  }

  @override
  Future<void> clear(DivisionDeleteOperation operation) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(
      operation.actorId,
      operation.associationId,
      operation.divisionId,
    );
    final raw = preferences.getString(key);
    if (raw == null) {
      throw StateError('The protected division deletion operation was lost');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        !DivisionDeleteOperation.fromMap(
          Map<String, dynamic>.from(decoded),
        ).matches(operation)) {
      throw StateError('The protected division deletion operation changed');
    }
    final removed = await preferences.remove(key);
    if (!removed) {
      throw StateError('The completed division deletion could not be cleared');
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
