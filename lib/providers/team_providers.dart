import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/player_season_stats_model.dart';
import '../models/team_model.dart';
import '../services/repositories/stats_repository.dart';
import '../services/repositories/team_repository.dart';
import 'auth_providers.dart';
import 'season_providers.dart';

final teamRepositoryProvider = Provider((ref) => TeamRepository());

/// Stream all teams for the current association.
final teamsStreamProvider =
    StreamProvider<List<TeamModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return ref.watch(teamRepositoryProvider).watchTeams(assocId);
});

/// Watch a specific team by ID.
final teamDetailProvider =
    StreamProvider.family<TeamModel?, String>((ref, teamId) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(teamRepositoryProvider).watchTeam(assocId, teamId);
});

/// Watch player roster (season stats) for a team.
final teamRosterProvider =
    StreamProvider.family<List<PlayerSeasonStatsModel>, String>((ref, teamId) {
  final assocId = ref.watch(currentAssociationIdProvider);
  final seasonId = ref.watch(activeSeasonIdProvider).value;
  if (assocId == null || seasonId == null) return Stream.value([]);

  return StatsRepository().watchTeamRoster(assocId, teamId, seasonId);
});
