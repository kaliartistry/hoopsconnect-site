import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/division_model.dart';
import '../services/repositories/division_repository.dart';
import 'auth_providers.dart';

final divisionRepositoryProvider = Provider((ref) => DivisionRepository());

final selectedDivisionIdProvider = StateProvider<String?>((ref) => null);

/// Stream all divisions for the current association.
final divisionsStreamProvider = StreamProvider<List<DivisionModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return ref.watch(divisionRepositoryProvider).watchDivisions(assocId);
});

final selectedDivisionProvider = Provider<DivisionModel?>((ref) {
  final selectedDivisionId = ref.watch(selectedDivisionIdProvider);
  if (selectedDivisionId == null) return null;

  final divisions =
      ref.watch(divisionsStreamProvider).valueOrNull ?? const <DivisionModel>[];

  for (final division in divisions) {
    if (division.id == selectedDivisionId) return division;
  }

  return null;
});

final selectedDivisionNameProvider = Provider<String?>((ref) {
  return ref.watch(selectedDivisionProvider)?.name;
});

final activeDivisionsProvider = Provider<List<DivisionModel>>((ref) {
  final divisions = ref.watch(divisionsStreamProvider).valueOrNull ?? const [];
  return divisions
      .where((division) => !division.isArchived)
      .toList(growable: false);
});
