import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/firestore_paths.dart';
import '../models/season_model.dart';
import '../services/repositories/season_repository.dart';
import 'auth_providers.dart';

final seasonRepositoryProvider = Provider((ref) => SeasonRepository());

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

final seasonsStreamProvider = StreamProvider<List<SeasonModel>>((ref) {
  final associationId = ref.watch(currentAssociationIdProvider);
  if (associationId == null) return Stream.value(const []);
  return ref.watch(seasonRepositoryProvider).watchSeasons(associationId);
});
