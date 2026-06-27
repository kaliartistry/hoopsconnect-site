import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event_model.dart';
import '../models/game_stats_model.dart';
import '../models/leaderboard_model.dart';
import '../models/player_season_stats_model.dart';
import '../models/team_season_stats_model.dart';
import '../services/repositories/event_repository.dart';
import '../services/repositories/stats_repository.dart';
import 'auth_providers.dart';

final statsRepositoryProvider = Provider((ref) => StatsRepository());
final eventRepositoryProvider = Provider((ref) => EventRepository());

/// Games that need stats entered.
final gamesNeedingStatsProvider =
    StreamProvider<List<EventModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return ref.watch(eventRepositoryProvider).watchGamesNeedingStats(assocId);
});

/// All games (any stats status) for the game select screen.
final allGamesForStatsProvider =
    StreamProvider<List<EventModel>>((ref) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return ref.watch(eventRepositoryProvider).watchAllGames(assocId);
});

/// Watch a single event by ID.
final eventDetailProvider =
    StreamProvider.family<EventModel?, String>((ref, eventId) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(eventRepositoryProvider).watchEvent(assocId, eventId);
});

/// Watch game stats for a specific event.
final gameStatsProvider =
    StreamProvider.family<GameStatsModel?, String>((ref, eventId) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(statsRepositoryProvider).watchGameStats(assocId, eventId);
});

/// Watch a player's season stats.
final playerSeasonStatsProvider = StreamProvider.family<
    PlayerSeasonStatsModel?,
    ({String playerId, String seasonId})>((ref, params) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(statsRepositoryProvider).watchPlayerSeasonStats(
        assocId,
        params.playerId,
        params.seasonId,
      );
});

/// Watch all events (for calendar screen).
final eventsStreamProvider = StreamProvider.family<List<EventModel>,
    ({DateTime? from, DateTime? to, String? divisionId})>((ref, params) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  return ref.watch(eventRepositoryProvider).watchEvents(
        assocId,
        divisionId: params.divisionId,
        from: params.from,
        to: params.to,
      );
});

/// Watch team season stats.
final teamSeasonStatsProvider = StreamProvider.family<TeamSeasonStats?,
    ({String teamId, String seasonId})>((ref, params) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(statsRepositoryProvider).watchTeamSeasonStats(
        assocId,
        params.teamId,
        params.seasonId,
      );
});

/// Watch leaderboard for a specific category.
final leaderboardProvider = StreamProvider.family<LeaderboardModel?,
    ({String seasonId, String? divisionId, String category})>(
  (ref, params) {
    final assocId = ref.watch(currentAssociationIdProvider);
    if (assocId == null) return Stream.value(null);

    return ref.watch(statsRepositoryProvider).watchLeaderboard(
          assocId,
          params.seasonId,
          params.divisionId,
          params.category,
        );
  },
);
