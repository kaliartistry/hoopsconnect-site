import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/firestore_paths.dart';
import '../models/game_stats_model.dart';
import '../models/event_model.dart';
import 'auth_providers.dart';

/// Last 5 approved game results, ordered by approvedAt descending.
final recentResultsProvider = StreamProvider<List<GameStatsModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection(FirestorePaths.gameStats(assocId))
      .where('status', isEqualTo: 'approved')
      .orderBy('approvedAt', descending: true)
      .limit(5)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => GameStatsModel.fromFirestore(doc))
          .toList());
});

/// Today's games — events where type == 'game' and startTime falls today.
final todaysGamesProvider = StreamProvider<List<EventModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  return FirebaseFirestore.instance
      .collection(FirestorePaths.events(assocId))
      .where('type', isEqualTo: 'game')
      .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .where('startTime', isLessThan: Timestamp.fromDate(endOfDay))
      .orderBy('startTime')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => EventModel.fromFirestore(doc))
          .toList());
});
