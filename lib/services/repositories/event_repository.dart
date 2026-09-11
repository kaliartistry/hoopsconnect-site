import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/event_model.dart';

class EventRepository {
  final FirebaseFirestore? _firestore;
  final Random _random;

  EventRepository({FirebaseFirestore? firestore, Random? random})
    : _firestore = firestore,
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
}
