import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/event_model.dart';

typedef EventCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> data,
    );

class ScheduleWorkflowException implements Exception {
  final String code;
  final String message;

  const ScheduleWorkflowException(this.code, this.message);

  @override
  String toString() => message;
}

class EventRepository {
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final EventCallable? _callable;
  final Random _random;

  EventRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    EventCallable? callable,
    Random? random,
  }) : _firestore = firestore,
       _functions = functions,
       _callable = callable,
       _random = random ?? Random.secure();

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  String newScheduleOperationId({DateTime? now}) {
    final entropy = List.generate(
      12,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'schedule_${(now ?? DateTime.now()).toUtc().microsecondsSinceEpoch}_$entropy';
  }

  CollectionReference<EventModel> _eventsRef(String assocId) {
    return _db
        .collection(FirestorePaths.events(assocId))
        .withConverter<EventModel>(
          fromFirestore: (snap, _) => EventModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<List<EventModel>> watchEvents(
    String assocId, {
    String? divisionId,
    DateTime? from,
    DateTime? to,
  }) {
    Query<EventModel> query = _eventsRef(assocId).orderBy('startTime');

    if (from != null) {
      query = query.where(
        'startTime',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where(
        'startTime',
        isLessThanOrEqualTo: Timestamp.fromDate(to),
      );
    }

    return query.snapshots().map((snap) {
      final events = snap.docs.map((d) => d.data());
      return events
          .where(
            (event) => divisionId == null || event.divisionId == divisionId,
          )
          .toList();
    });
  }

  /// Games that still need stats entered.
  Stream<List<EventModel>> watchGamesNeedingStats(String assocId) {
    return _eventsRef(assocId)
        .where('type', isEqualTo: 'game')
        .where('statsStatus', isEqualTo: 'pending')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// All games (any stats status) sorted by most recent first.
  Stream<List<EventModel>> watchAllGames(String assocId) {
    return _eventsRef(assocId)
        .where('type', isEqualTo: 'game')
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Watch a single event by ID.
  Stream<EventModel?> watchEvent(String assocId, String eventId) {
    return _eventsRef(
      assocId,
    ).doc(eventId).snapshots().map((snap) => snap.exists ? snap.data() : null);
  }

  Future<void> createEvent(String assocId, EventModel event) {
    final docRef = event.id.isEmpty
        ? _eventsRef(assocId).doc()
        : _eventsRef(assocId).doc(event.id);
    return docRef.set(event);
  }

  Future<void> updateEvent(
    String assocId,
    String eventId,
    Map<String, dynamic> data,
  ) {
    return _db.doc(FirestorePaths.event(assocId, eventId)).update(data);
  }

  Future<ScheduleOperationReceipt> scheduleGame(
    ManualGameScheduleRequest request,
  ) async {
    final result = await _invoke('scheduleGame', request.toMap());
    return ScheduleOperationReceipt.fromMap(result);
  }

  Future<ScheduleOperationReceipt> mutateScheduledGame(
    ScheduledGameMutationRequest request,
  ) async {
    final result = await _invoke('mutateScheduledGame', request.toMap());
    return ScheduleOperationReceipt.fromMap(result);
  }

  Future<List<ScheduleOperationReceipt>> createScheduleBatch({
    required String operationId,
    required List<Map<String, Object?>> games,
  }) async {
    final result = await _invoke('createScheduleBatch', {
      'schemaVersion': ManualGameScheduleRequest.schemaVersion,
      'operationId': operationId,
      'games': games,
    });
    final rows = result['results'];
    if (result['status'] != 'created' || rows is! List) {
      throw const FormatException('Invalid schedule batch receipt');
    }
    return rows
        .map(
          (row) => ScheduleOperationReceipt.fromMap(
            Map<String, dynamic>.from(row as Map),
            parentOperationId: operationId,
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      if (_callable != null) return await _callable(name, data);
      final result = await (_functions ?? FirebaseFunctions.instance)
          .httpsCallable(name)
          .call<Map<Object?, Object?>>(data);
      return result.data.map((key, value) => MapEntry(key.toString(), value));
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        throw const ScheduleWorkflowException(
          'workflow-unavailable',
          'Scheduling is temporarily unavailable. No game was changed.',
        );
      }
      if (error.code == 'permission-denied') {
        throw const ScheduleWorkflowException(
          'permission-denied',
          'Your current league access does not allow this schedule change.',
        );
      }
      if (error.code == 'aborted') {
        throw const ScheduleWorkflowException(
          'stale-schedule',
          'The schedule changed while you were working. Reload it before trying again.',
        );
      }
      throw ScheduleWorkflowException(
        error.code,
        error.message ??
            'The schedule service could not complete this request.',
      );
    }
  }
}
