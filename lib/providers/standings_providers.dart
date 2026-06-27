import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/standings_model.dart';
import '../services/repositories/standings_repository.dart';
import 'auth_providers.dart';

final standingsRepositoryProvider =
    Provider((ref) => StandingsRepository());

final standingsStreamProvider = StreamProvider.family<StandingsModel?,
    ({String seasonId, String? divisionId})>(
  (ref, params) {
    final assocId = ref.watch(currentAssociationIdProvider);
    if (assocId == null) return Stream.value(null);

    return ref.watch(standingsRepositoryProvider).watchStandings(
          assocId,
          params.seasonId,
          divisionId: params.divisionId,
        );
  },
);
