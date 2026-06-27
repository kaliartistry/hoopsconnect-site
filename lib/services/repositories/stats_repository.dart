import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/game_stats_model.dart';
import '../../models/leaderboard_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/team_season_stats_model.dart';

class StatsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- Game Stats ---

  CollectionReference<GameStatsModel> _gameStatsRef(String assocId) {
    return _db
        .collection(FirestorePaths.gameStats(assocId))
        .withConverter<GameStatsModel>(
          fromFirestore: (snap, _) => GameStatsModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<GameStatsModel?> watchGameStats(String assocId, String eventId) {
    return _gameStatsRef(assocId).doc(eventId).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  Future<GameStatsModel?> getGameStats(
      String assocId, String eventId) async {
    final snap = await _gameStatsRef(assocId).doc(eventId).get();
    return snap.exists ? snap.data() : null;
  }

  Future<void> saveGameStats(String assocId, GameStatsModel stats) {
    return _gameStatsRef(assocId)
        .doc(stats.id)
        .set(stats, SetOptions(merge: true));
  }

  /// Append a single play to the live events subcollection. Wireframe §04 L4 —
  /// the subcollection is the audit trail; deletes are tombstoned via
  /// [tombstoneLiveEvent] rather than removed.
  Future<void> appendLiveEvent(
    String assocId,
    String gameId,
    String localId,
    Map<String, dynamic> playMap,
  ) {
    return _db
        .collection('${FirestorePaths.gameStat(assocId, gameId)}/events')
        .doc(localId)
        .set({
      ...playMap,
      'recordedAt': Timestamp.now(),
      'revoked': false,
    });
  }

  /// Mark a previously appended event as revoked (live-stats undo). The doc
  /// stays in place for audit purposes.
  Future<void> tombstoneLiveEvent(
    String assocId,
    String gameId,
    String localId,
  ) {
    return _db
        .collection('${FirestorePaths.gameStat(assocId, gameId)}/events')
        .doc(localId)
        .set({
      'revoked': true,
      'revokedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> updateGameStatsStatus(
    String assocId,
    String eventId,
    GameStatsStatus status, {
    String? userId,
    String? rejectionNote,
  }) {
    final data = <String, dynamic>{'status': status.name};
    if (status == GameStatsStatus.submitted) {
      data['submittedBy'] = userId;
      data['submittedAt'] = Timestamp.now();
      // Clear any prior rejection on resubmit.
      data['rejectionNote'] = null;
      data['rejectedBy'] = null;
      data['rejectedAt'] = null;
    } else if (status == GameStatsStatus.approved) {
      data['approvedBy'] = userId;
      data['approvedAt'] = Timestamp.now();
    } else if (status == GameStatsStatus.rejected) {
      data['rejectedBy'] = userId;
      data['rejectedAt'] = Timestamp.now();
      data['rejectionNote'] = rejectionNote;
    }
    return _db
        .doc(FirestorePaths.gameStat(assocId, eventId))
        .update(data);
  }

  // --- Player Season Stats ---

  Future<PlayerSeasonStatsModel?> getPlayerSeasonStats(
    String assocId,
    String playerId,
    String seasonId,
  ) async {
    final compositeId = '${playerId}_$seasonId';
    final snap = await _db
        .doc(FirestorePaths.playerSeasonStat(assocId, compositeId))
        .get();
    if (!snap.exists) return null;
    return PlayerSeasonStatsModel.fromFirestore(snap);
  }

  Stream<PlayerSeasonStatsModel?> watchPlayerSeasonStats(
    String assocId,
    String playerId,
    String seasonId,
  ) {
    final compositeId = '${playerId}_$seasonId';
    return _db
        .doc(FirestorePaths.playerSeasonStat(assocId, compositeId))
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return PlayerSeasonStatsModel.fromFirestore(snap);
    });
  }

  /// All player season stats for a given team in a season.
  Stream<List<PlayerSeasonStatsModel>> watchTeamRoster(
    String assocId,
    String teamId,
    String seasonId,
  ) {
    return _db
        .collection(FirestorePaths.playerSeasonStats(assocId))
        .where('teamId', isEqualTo: teamId)
        .where('seasonId', isEqualTo: seasonId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => PlayerSeasonStatsModel.fromFirestore(doc))
            .toList()
          ..sort((a, b) => b.ppg.compareTo(a.ppg)));
  }

  // --- Team Season Stats ---

  CollectionReference<TeamSeasonStats> _teamSeasonStatsRef(String assocId) {
    return _db
        .collection(FirestorePaths.teamSeasonStats(assocId))
        .withConverter<TeamSeasonStats>(
          fromFirestore: (snap, _) => TeamSeasonStats.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<TeamSeasonStats?> watchTeamSeasonStats(
    String assocId,
    String teamId,
    String seasonId,
  ) {
    final compositeId = '${teamId}_$seasonId';
    return _teamSeasonStatsRef(assocId).doc(compositeId).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  // --- Roster Management ---

  /// Add a player to a team roster by creating a PlayerSeasonStatsModel doc
  /// with zero stats.
  Future<void> addPlayerToRoster({
    required String assocId,
    required String playerId,
    required String playerName,
    required String teamId,
    required String? teamName,
    required String seasonId,
    required String? divisionId,
  }) {
    final compositeId = '${playerId}_$seasonId';
    final model = PlayerSeasonStatsModel(
      id: compositeId,
      playerId: playerId,
      playerName: playerName,
      teamId: teamId,
      teamName: teamName,
      seasonId: seasonId,
      divisionId: divisionId,
    );
    return _db
        .doc(FirestorePaths.playerSeasonStat(assocId, compositeId))
        .set(model.toFirestore());
  }

  /// Remove a player from the roster.
  Future<void> removePlayerFromRoster(String assocId, String compositeId) {
    return _db
        .doc(FirestorePaths.playerSeasonStat(assocId, compositeId))
        .delete();
  }

  // --- Leaderboards ---

  CollectionReference<LeaderboardModel> _leaderboardRef(String assocId) {
    return _db
        .collection(FirestorePaths.leaderboards(assocId))
        .withConverter<LeaderboardModel>(
          fromFirestore: (snap, _) =>
              LeaderboardModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<LeaderboardModel?> watchLeaderboard(
    String assocId,
    String seasonId,
    String? divisionId,
    String category,
  ) {
    final compositeId =
        '${seasonId}_${divisionId ?? 'all'}_$category';
    return _leaderboardRef(assocId).doc(compositeId).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }
}
