import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/firestore_paths.dart';
import 'auth_providers.dart';

/// The active season ID from the association document's `currentSeasonId` field.
final activeSeasonIdProvider = StreamProvider<String?>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .doc(FirestorePaths.association(assocId))
      .snapshots()
      .map((snap) => snap.data()?['currentSeasonId'] as String?);
});

/// The active season name from the season document.
final activeSeasonNameProvider = StreamProvider<String?>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  final seasonId = ref.watch(activeSeasonIdProvider).value;
  if (assocId == null || seasonId == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .doc(FirestorePaths.season(assocId, seasonId))
      .snapshots()
      .map((snap) => snap.data()?['name'] as String?);
});
