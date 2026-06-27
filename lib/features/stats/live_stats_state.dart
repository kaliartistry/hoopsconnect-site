/// Immutable state classes for the live stat-taking screen.
library;

import 'package:flutter/foundation.dart';

/// Whether the statistician manages a countdown clock or just tracks quarters.
enum ClockMode { withClock, statsOnly }

/// Per-player stats broken down by quarter.
@immutable
class PlayerQuarterStats {
  final int pts;
  final int oreb;
  final int dreb;
  final int ast;
  final int stl;
  final int blk;
  final int to;
  final int fls;

  int get reb => oreb + dreb;

  const PlayerQuarterStats({
    this.pts = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.to = 0,
    this.fls = 0,
  });

  PlayerQuarterStats add({
    int pts = 0,
    int oreb = 0,
    int dreb = 0,
    int ast = 0,
    int stl = 0,
    int blk = 0,
    int to = 0,
    int fls = 0,
  }) {
    return PlayerQuarterStats(
      pts: this.pts + pts,
      oreb: this.oreb + oreb,
      dreb: this.dreb + dreb,
      ast: this.ast + ast,
      stl: this.stl + stl,
      blk: this.blk + blk,
      to: this.to + to,
      fls: this.fls + fls,
    );
  }
}

/// A single play in the play-by-play log.
@immutable
class GamePlay {
  /// Stable local id used to key the corresponding Firestore event doc so
  /// undo can write a tombstone instead of mutating history.
  final String localId;
  final String playerId;
  final String playerName;
  final int playerNum;
  final String teamId;
  final String action; // e.g. '2PT_MAKE', 'OREB', 'SUB', etc.
  final String description;
  final int quarter;
  final int clockSeconds;
  final int? pointsScored;
  final bool isMiss;
  final String type; // 'action' or 'sub'

  /// Data needed to reverse this play.
  final Map<String, dynamic> undoData;

  const GamePlay({
    required this.localId,
    required this.playerId,
    required this.playerName,
    required this.playerNum,
    required this.teamId,
    required this.action,
    required this.description,
    required this.quarter,
    required this.clockSeconds,
    this.pointsScored,
    this.isMiss = false,
    this.type = 'action',
    this.undoData = const {},
  });

  /// Generate a unique id for a new play.
  static String newLocalId() =>
      'p_${DateTime.now().microsecondsSinceEpoch}_'
      '${(_seq = (_seq + 1) % 1000000).toString().padLeft(6, '0')}';

  static int _seq = 0;

  String get clockFormatted {
    final m = clockSeconds ~/ 60;
    final s = clockSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  GamePlay copyWith({
    String? localId,
    String? playerId,
    String? playerName,
    int? playerNum,
    String? teamId,
    String? action,
    String? description,
    int? quarter,
    int? clockSeconds,
    int? pointsScored,
    bool? isMiss,
    String? type,
    Map<String, dynamic>? undoData,
  }) {
    return GamePlay(
      localId: localId ?? this.localId,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      playerNum: playerNum ?? this.playerNum,
      teamId: teamId ?? this.teamId,
      action: action ?? this.action,
      description: description ?? this.description,
      quarter: quarter ?? this.quarter,
      clockSeconds: clockSeconds ?? this.clockSeconds,
      pointsScored: pointsScored ?? this.pointsScored,
      isMiss: isMiss ?? this.isMiss,
      type: type ?? this.type,
      undoData: undoData ?? this.undoData,
    );
  }

  /// Firestore representation for the events subcollection (audit trail).
  Map<String, dynamic> toEventMap() => {
        'localId': localId,
        'playerId': playerId,
        'playerName': playerName,
        'playerNum': playerNum,
        'teamId': teamId,
        'action': action,
        'description': description,
        'quarter': quarter,
        'clockSeconds': clockSeconds,
        'pointsScored': pointsScored,
        'isMiss': isMiss,
        'type': type,
      };
}

/// Per-player live statistics.
@immutable
class LivePlayerStats {
  final String id;
  final String name;
  final String teamId;
  final int num; // jersey number
  final bool onCourt;
  final int pts;
  final int oreb;
  final int dreb;
  final int ast;
  final int stl;
  final int blk;
  final int fls;
  final int to; // turnovers
  final int min; // accumulated minutes (finalized segments)

  /// Clock value (in seconds) when this player last entered the court.
  /// Null if the player is on the bench.
  final int? minutesEnteredAt;

  int get reb => oreb + dreb;

  const LivePlayerStats({
    required this.id,
    required this.name,
    required this.teamId,
    required this.num,
    this.onCourt = false,
    this.pts = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.fls = 0,
    this.to = 0,
    this.min = 0,
    this.minutesEnteredAt,
  });

  /// Current minutes including live session.
  int currentMinutes(int currentClockSeconds) {
    int total = min;
    if (onCourt && minutesEnteredAt != null) {
      final elapsed = ((minutesEnteredAt! - currentClockSeconds) / 60).round();
      total += elapsed < 0 ? 0 : (elapsed > 999 ? 999 : elapsed);
    }
    return total;
  }

  bool get isFouledOut => fls >= 5;

  LivePlayerStats copyWith({
    String? id,
    String? name,
    String? teamId,
    int? num,
    bool? onCourt,
    int? pts,
    int? oreb,
    int? dreb,
    int? ast,
    int? stl,
    int? blk,
    int? fls,
    int? to,
    int? min,
    int? Function()? minutesEnteredAt,
  }) {
    return LivePlayerStats(
      id: id ?? this.id,
      name: name ?? this.name,
      teamId: teamId ?? this.teamId,
      num: num ?? this.num,
      onCourt: onCourt ?? this.onCourt,
      pts: pts ?? this.pts,
      oreb: oreb ?? this.oreb,
      dreb: dreb ?? this.dreb,
      ast: ast ?? this.ast,
      stl: stl ?? this.stl,
      blk: blk ?? this.blk,
      fls: fls ?? this.fls,
      to: to ?? this.to,
      min: min ?? this.min,
      minutesEnteredAt:
          minutesEnteredAt != null ? minutesEnteredAt() : this.minutesEnteredAt,
    );
  }
}

/// Top-level game state for live stat-taking.
@immutable
class LiveGameState {
  final String homeTeamId;
  final String awayTeamId;
  final String homeTeamName;
  final String awayTeamName;
  final int quarter; // 1-4
  final int clockSeconds; // countdown from 600
  final bool clockRunning;
  final List<GamePlay> plays; // play-by-play log (newest first)
  final String? selectedPlayerId;
  final Map<String, LivePlayerStats> players;
  final bool subMode;
  final String? subOutPlayerId;
  final bool gameEnded;
  final ClockMode clockMode;

  /// Optional event/season context for syncing back.
  final String? eventId;
  final String? seasonId;
  final String? divisionId;

  const LiveGameState({
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeTeamName,
    required this.awayTeamName,
    this.quarter = 1,
    this.clockSeconds = 600,
    this.clockRunning = false,
    this.plays = const [],
    this.selectedPlayerId,
    this.players = const {},
    this.subMode = false,
    this.subOutPlayerId,
    this.gameEnded = false,
    this.clockMode = ClockMode.statsOnly,
    this.eventId,
    this.seasonId,
    this.divisionId,
  });

  int get homeScore => players.values
      .where((p) => p.teamId == homeTeamId)
      .fold(0, (sum, p) => sum + p.pts);

  int get awayScore => players.values
      .where((p) => p.teamId == awayTeamId)
      .fold(0, (sum, p) => sum + p.pts);

  LivePlayerStats? get selectedPlayer =>
      selectedPlayerId != null ? players[selectedPlayerId] : null;

  String get clockFormatted {
    final m = clockSeconds ~/ 60;
    final s = clockSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Compute per-quarter scores from the play-by-play log.
  Map<int, ({int home, int away})> get quarterScores {
    final scores = <int, ({int home, int away})>{};
    for (final play in plays) {
      if (play.pointsScored != null && play.pointsScored! > 0) {
        final q = play.quarter;
        final current = scores[q] ?? (home: 0, away: 0);
        final playerTeam = players[play.playerId]?.teamId;
        if (playerTeam == homeTeamId) {
          scores[q] = (home: current.home + play.pointsScored!, away: current.away);
        } else {
          scores[q] = (home: current.home, away: current.away + play.pointsScored!);
        }
      }
    }
    return scores;
  }

  /// Compute per-quarter stats for a single player from the play-by-play log.
  Map<int, PlayerQuarterStats> playerStatsByQuarter(String playerId) {
    final result = <int, PlayerQuarterStats>{};
    for (final play in plays) {
      if (play.playerId != playerId) continue;
      if (play.type != 'action') continue;

      final q = play.quarter;
      final current = result[q] ?? const PlayerQuarterStats();
      final action = play.undoData['action'] as String? ?? play.action;
      final wasMiss = play.undoData['isMiss'] as bool? ?? play.isMiss;

      if (wasMiss) {
        // Misses don't add stats
        result[q] = current;
        continue;
      }

      switch (action) {
        case '2PT_MAKE':
          result[q] = current.add(pts: 2);
        case '3PT_MAKE':
          result[q] = current.add(pts: 3);
        case 'FT_MAKE':
          result[q] = current.add(pts: 1);
        case 'OREB':
          result[q] = current.add(oreb: 1);
        case 'DREB':
          result[q] = current.add(dreb: 1);
        case 'AST':
          result[q] = current.add(ast: 1);
        case 'STL':
          result[q] = current.add(stl: 1);
        case 'BLK':
          result[q] = current.add(blk: 1);
        case 'TO':
          result[q] = current.add(to: 1);
        case 'FLS':
          result[q] = current.add(fls: 1);
        default:
          result[q] = current;
      }
    }
    return result;
  }

  LiveGameState copyWith({
    String? homeTeamId,
    String? awayTeamId,
    String? homeTeamName,
    String? awayTeamName,
    int? quarter,
    int? clockSeconds,
    bool? clockRunning,
    List<GamePlay>? plays,
    String? Function()? selectedPlayerId,
    Map<String, LivePlayerStats>? players,
    bool? subMode,
    String? Function()? subOutPlayerId,
    bool? gameEnded,
    ClockMode? clockMode,
    String? Function()? eventId,
    String? Function()? seasonId,
    String? Function()? divisionId,
  }) {
    return LiveGameState(
      homeTeamId: homeTeamId ?? this.homeTeamId,
      awayTeamId: awayTeamId ?? this.awayTeamId,
      homeTeamName: homeTeamName ?? this.homeTeamName,
      awayTeamName: awayTeamName ?? this.awayTeamName,
      quarter: quarter ?? this.quarter,
      clockSeconds: clockSeconds ?? this.clockSeconds,
      clockRunning: clockRunning ?? this.clockRunning,
      plays: plays ?? this.plays,
      selectedPlayerId: selectedPlayerId != null
          ? selectedPlayerId()
          : this.selectedPlayerId,
      players: players ?? this.players,
      subMode: subMode ?? this.subMode,
      subOutPlayerId: subOutPlayerId != null
          ? subOutPlayerId()
          : this.subOutPlayerId,
      gameEnded: gameEnded ?? this.gameEnded,
      clockMode: clockMode ?? this.clockMode,
      eventId: eventId != null ? eventId() : this.eventId,
      seasonId: seasonId != null ? seasonId() : this.seasonId,
      divisionId: divisionId != null ? divisionId() : this.divisionId,
    );
  }
}
