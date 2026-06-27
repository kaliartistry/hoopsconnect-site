/// StateNotifier that drives the live stat-taking screen.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/game_stats_model.dart';
import 'live_stats_state.dart';

class LiveStatsNotifier extends StateNotifier<LiveGameState> {
  Timer? _clockTimer;

  LiveStatsNotifier(super.initial);

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  // ──────────────────────────── Initialization ──────────────────────────────

  /// Replace the current state with a fully configured game state.
  void initGame({
    required String homeTeamId,
    required String awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
    required Map<String, LivePlayerStats> players,
    String? seasonId,
    String? eventId,
    String? divisionId,
    ClockMode clockMode = ClockMode.statsOnly,
  }) {
    state = LiveGameState(
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeTeamName: homeTeamName,
      awayTeamName: awayTeamName,
      players: players,
      seasonId: seasonId,
      eventId: eventId,
      divisionId: divisionId,
      clockMode: clockMode,
    );
  }

  /// Change the clock mode (e.g. from setup screen toggle).
  void setClockMode(ClockMode mode) {
    state = state.copyWith(clockMode: mode);
  }

  // ──────────────────────────── Player Selection ────────────────────────────

  /// Tapping a player toggles selection: tap once to select, tap again to
  /// deselect. Wireframe §04 L2 — this is the safety latch on the two-tap rule.
  void selectPlayer(String playerId) {
    if (state.subMode && state.subOutPlayerId != null) return;
    if (state.selectedPlayerId == playerId) {
      // Same player tapped → deselect.
      state = state.copyWith(selectedPlayerId: () => null);
      return;
    }
    state = state.copyWith(
      selectedPlayerId: () => playerId,
      subMode: false,
      subOutPlayerId: () => null,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      selectedPlayerId: () => null,
      subMode: false,
      subOutPlayerId: () => null,
    );
  }

  // ──────────────────────────── Stat Recording ─────────────────────────────

  /// Record a stat action. Returns a message string if a foul alert is needed.
  String? recordStat(String action) {
    final pid = state.selectedPlayerId;
    if (pid == null) return null;
    final player = state.players[pid];
    if (player == null || !player.onCourt) return null;

    // Fouled-out players cannot record stats (except via SUB).
    if (player.isFouledOut) return null;

    final newPlayers = Map<String, LivePlayerStats>.from(state.players);
    int points = 0;
    bool isMiss = false;
    String description;

    switch (action) {
      case '2PT_MAKE':
        points = 2;
        description = '2PT Made';
        newPlayers[pid] = player.copyWith(pts: player.pts + 2);
      case '2PT_MISS':
        isMiss = true;
        description = '2PT Missed';
        // No stat change for a miss.
        newPlayers[pid] = player;
      case '3PT_MAKE':
        points = 3;
        description = '3PT Made';
        newPlayers[pid] = player.copyWith(pts: player.pts + 3);
      case '3PT_MISS':
        isMiss = true;
        description = '3PT Missed';
        newPlayers[pid] = player;
      case 'FT_MAKE':
        points = 1;
        description = 'FT Made';
        newPlayers[pid] = player.copyWith(pts: player.pts + 1);
      case 'FT_MISS':
        isMiss = true;
        description = 'FT Missed';
        newPlayers[pid] = player;
      case 'OREB':
        description = 'Off. Rebound';
        newPlayers[pid] = player.copyWith(oreb: player.oreb + 1);
      case 'DREB':
        description = 'Def. Rebound';
        newPlayers[pid] = player.copyWith(dreb: player.dreb + 1);
      case 'AST':
        description = 'Assist';
        newPlayers[pid] = player.copyWith(ast: player.ast + 1);
      case 'STL':
        description = 'Steal';
        newPlayers[pid] = player.copyWith(stl: player.stl + 1);
      case 'BLK':
        description = 'Block';
        newPlayers[pid] = player.copyWith(blk: player.blk + 1);
      case 'TO':
        description = 'Turnover';
        newPlayers[pid] = player.copyWith(to: player.to + 1);
      case 'FLS':
        if (player.fls >= 5) return '${player.name} already has 5 fouls!';
        description = 'Foul';
        newPlayers[pid] = player.copyWith(fls: player.fls + 1);
      default:
        return null;
    }

    final play = GamePlay(
      localId: GamePlay.newLocalId(),
      playerId: pid,
      playerName: player.name,
      playerNum: player.num,
      teamId: player.teamId,
      action: action,
      description: description,
      quarter: state.quarter,
      clockSeconds: state.clockSeconds,
      pointsScored: points,
      isMiss: isMiss,
      type: 'action',
      undoData: {
        'playerId': pid,
        'action': action,
        'isMiss': isMiss,
        'points': points,
      },
    );

    state = state.copyWith(players: newPlayers, plays: [play, ...state.plays]);

    // Foul alerts
    if (action == 'FLS') {
      final updatedFls = newPlayers[pid]!.fls;
      if (updatedFls >= 5) {
        return 'FOUL_OUT:$pid';
      } else if (updatedFls == 4) {
        return '${player.name} has 4 fouls — 1 more and they foul out!';
      }
    }

    return null;
  }

  // ──────────────────────────── Substitution ───────────────────────────────

  /// Start sub mode for the currently selected on-court player.
  void startSub() {
    final pid = state.selectedPlayerId;
    if (pid == null) return;
    final player = state.players[pid];
    if (player == null || !player.onCourt) return;

    state = state.copyWith(subMode: true, subOutPlayerId: () => pid);
  }

  /// Start sub mode for a specific player (e.g. foul-out forced sub).
  void startFoulOutSub(String playerId) {
    state = state.copyWith(
      selectedPlayerId: () => playerId,
      subMode: true,
      subOutPlayerId: () => playerId,
    );
  }

  /// Complete the substitution by selecting a bench player.
  void completeSub(String benchPlayerId) {
    if (!state.subMode || state.subOutPlayerId == null) return;

    final outP = state.players[state.subOutPlayerId!];
    final inP = state.players[benchPlayerId];
    if (outP == null || inP == null || outP.teamId != inP.teamId) return;

    final newPlayers = Map<String, LivePlayerStats>.from(state.players);

    // Accumulate minutes for outgoing player.
    int minAdded = 0;
    if (outP.minutesEnteredAt != null) {
      final raw = ((outP.minutesEnteredAt! - state.clockSeconds) / 60).round();
      minAdded = raw < 0 ? 0 : (raw > 999 ? 999 : raw);
    }
    final prevEnteredAt = outP.minutesEnteredAt;

    newPlayers[outP.id] = outP.copyWith(
      onCourt: false,
      min: outP.min + minAdded,
      minutesEnteredAt: () => null,
    );
    newPlayers[inP.id] = inP.copyWith(
      onCourt: true,
      minutesEnteredAt: () => state.clockSeconds,
    );

    final play = GamePlay(
      localId: GamePlay.newLocalId(),
      playerId: inP.id,
      playerName: inP.name,
      playerNum: inP.num,
      teamId: outP.teamId,
      action: 'SUB',
      description: '#${inP.num} ${inP.name} IN for #${outP.num} ${outP.name}',
      quarter: state.quarter,
      clockSeconds: state.clockSeconds,
      type: 'sub',
      undoData: {
        'subIn': inP.id,
        'subOut': outP.id,
        'outMinutesEnteredAt': prevEnteredAt,
        'outMinAdded': minAdded,
        'inMinutesEnteredAt': state.clockSeconds,
      },
    );

    state = state.copyWith(
      players: newPlayers,
      plays: [play, ...state.plays],
      subMode: false,
      subOutPlayerId: () => null,
      selectedPlayerId: () => null,
    );
  }

  void cancelSub() {
    state = state.copyWith(subMode: false, subOutPlayerId: () => null);
  }

  // ──────────────────────────── Stat Reversal Helper ──────────────────────

  /// Reverse the stat effect of a single play within [players].
  /// Returns the modified player map.
  Map<String, LivePlayerStats> _reversePlay(
    GamePlay play,
    Map<String, LivePlayerStats> players,
  ) {
    if (play.type == 'sub') {
      final subInId = play.undoData['subIn'] as String;
      final subOutId = play.undoData['subOut'] as String;
      final outMinEnteredAt = play.undoData['outMinutesEnteredAt'] as int?;
      final outMinAdded = play.undoData['outMinAdded'] as int? ?? 0;

      final inP = players[subInId]!;
      final outP = players[subOutId]!;

      players[subInId] = inP.copyWith(
        onCourt: false,
        minutesEnteredAt: () => null,
      );
      players[subOutId] = outP.copyWith(
        onCourt: true,
        min: outP.min - outMinAdded,
        minutesEnteredAt: () => outMinEnteredAt ?? state.clockSeconds,
      );
    } else if (play.type == 'action') {
      final pid = play.undoData['playerId'] as String;
      final action = play.undoData['action'] as String;
      final wasMiss = play.undoData['isMiss'] as bool? ?? false;
      final pts = play.undoData['points'] as int? ?? 0;
      final p = players[pid]!;

      if (!wasMiss) {
        switch (action) {
          case '2PT_MAKE' || '3PT_MAKE' || 'FT_MAKE':
            players[pid] = p.copyWith(pts: p.pts - pts);
          case 'OREB':
            players[pid] = p.copyWith(oreb: p.oreb - 1);
          case 'DREB':
            players[pid] = p.copyWith(dreb: p.dreb - 1);
          case 'AST':
            players[pid] = p.copyWith(ast: p.ast - 1);
          case 'STL':
            players[pid] = p.copyWith(stl: p.stl - 1);
          case 'BLK':
            players[pid] = p.copyWith(blk: p.blk - 1);
          case 'TO':
            players[pid] = p.copyWith(to: p.to - 1);
          case 'FLS':
            players[pid] = p.copyWith(fls: p.fls - 1);
        }
      }
    }
    return players;
  }

  /// Apply the stat effect of an action for a given player within [players].
  /// Returns (updated players map, points scored, isMiss, description) or
  /// null if the action is invalid.
  ({
    Map<String, LivePlayerStats> players,
    int points,
    bool isMiss,
    String description,
  })?
  _applyAction(
    String playerId,
    String action,
    Map<String, LivePlayerStats> players,
  ) {
    final player = players[playerId];
    if (player == null) return null;

    int points = 0;
    bool isMiss = false;
    String description;

    switch (action) {
      case '2PT_MAKE':
        points = 2;
        description = '2PT Made';
        players[playerId] = player.copyWith(pts: player.pts + 2);
      case '2PT_MISS':
        isMiss = true;
        description = '2PT Missed';
      case '3PT_MAKE':
        points = 3;
        description = '3PT Made';
        players[playerId] = player.copyWith(pts: player.pts + 3);
      case '3PT_MISS':
        isMiss = true;
        description = '3PT Missed';
      case 'FT_MAKE':
        points = 1;
        description = 'FT Made';
        players[playerId] = player.copyWith(pts: player.pts + 1);
      case 'FT_MISS':
        isMiss = true;
        description = 'FT Missed';
      case 'OREB':
        description = 'Off. Rebound';
        players[playerId] = player.copyWith(oreb: player.oreb + 1);
      case 'DREB':
        description = 'Def. Rebound';
        players[playerId] = player.copyWith(dreb: player.dreb + 1);
      case 'AST':
        description = 'Assist';
        players[playerId] = player.copyWith(ast: player.ast + 1);
      case 'STL':
        description = 'Steal';
        players[playerId] = player.copyWith(stl: player.stl + 1);
      case 'BLK':
        description = 'Block';
        players[playerId] = player.copyWith(blk: player.blk + 1);
      case 'TO':
        description = 'Turnover';
        players[playerId] = player.copyWith(to: player.to + 1);
      case 'FLS':
        description = 'Foul';
        players[playerId] = player.copyWith(fls: player.fls + 1);
      default:
        return null;
    }

    return (
      players: players,
      points: points,
      isMiss: isMiss,
      description: description,
    );
  }

  // ──────────────────────────── Undo ───────────────────────────────────────

  void undo() {
    if (state.plays.isEmpty) return;
    final play = state.plays.first;
    final newPlays = state.plays.sublist(1);
    final newPlayers = _reversePlay(
      play,
      Map<String, LivePlayerStats>.from(state.players),
    );

    state = state.copyWith(players: newPlayers, plays: newPlays);
  }

  // ──────────────────────────── Delete Play ─────────────────────────────────

  /// Remove a play at any position and reverse its stat effect.
  void deletePlay(int index) {
    if (index < 0 || index >= state.plays.length) return;

    final play = state.plays[index];
    final newPlays = List<GamePlay>.from(state.plays)..removeAt(index);
    final newPlayers = _reversePlay(
      play,
      Map<String, LivePlayerStats>.from(state.players),
    );

    state = state.copyWith(players: newPlayers, plays: newPlays);
  }

  // ──────────────────────────── Edit Play ───────────────────────────────────

  /// Change the action of a play at any position. Reverses the old stat
  /// and applies the new one. Cannot edit SUB plays (use delete instead).
  /// Returns an alert string if the new action triggers a foul alert, or
  /// null otherwise.
  String? editPlay(int index, String newAction) {
    if (index < 0 || index >= state.plays.length) return null;

    final oldPlay = state.plays[index];
    // SUB plays cannot be edited — only deleted.
    if (oldPlay.type == 'sub') return null;

    final playerId = oldPlay.playerId;

    // 1. Reverse old stat
    var newPlayers = _reversePlay(
      oldPlay,
      Map<String, LivePlayerStats>.from(state.players),
    );

    // 2. Apply new stat
    final result = _applyAction(playerId, newAction, newPlayers);
    if (result == null) return null;

    newPlayers = result.players;

    // 3. Build the updated play entry
    final updatedPlay = oldPlay.copyWith(
      action: newAction,
      description: result.description,
      pointsScored: result.points,
      isMiss: result.isMiss,
      undoData: {
        'playerId': playerId,
        'action': newAction,
        'isMiss': result.isMiss,
        'points': result.points,
      },
    );

    final newPlays = List<GamePlay>.from(state.plays);
    newPlays[index] = updatedPlay;

    state = state.copyWith(players: newPlayers, plays: newPlays);

    // Foul alert for edited play
    if (newAction == 'FLS') {
      final updatedFls = newPlayers[playerId]!.fls;
      if (updatedFls >= 5) {
        return 'FOUL_OUT:$playerId';
      } else if (updatedFls == 4) {
        return '${oldPlay.playerName} has 4 fouls — 1 more and they foul out!';
      }
    }

    return null;
  }

  // ──────────────────────────── Clock ──────────────────────────────────────

  void startClock() {
    if (state.clockMode == ClockMode.statsOnly) return;
    if (state.clockRunning || state.gameEnded) return;
    state = state.copyWith(clockRunning: true);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.clockSeconds > 0) {
        state = state.copyWith(clockSeconds: state.clockSeconds - 1);
      } else {
        stopClock();
      }
    });
  }

  void stopClock() {
    if (state.clockMode == ClockMode.statsOnly) return;
    _clockTimer?.cancel();
    _clockTimer = null;
    state = state.copyWith(clockRunning: false);
  }

  void toggleClock() {
    if (state.clockMode == ClockMode.statsOnly) return;
    if (state.clockRunning) {
      stopClock();
    } else {
      startClock();
    }
  }

  /// Advance to next quarter. Returns false if already Q4.
  bool nextQuarter() {
    if (state.quarter >= 4) return false;

    if (state.clockMode == ClockMode.statsOnly) {
      // Stats-only: just increment quarter and finalize minutes.
      final newPlayers = Map<String, LivePlayerStats>.from(state.players);
      for (final entry in newPlayers.entries) {
        final p = entry.value;
        if (p.onCourt && p.minutesEnteredAt != null) {
          final rawAdded = (p.minutesEnteredAt! / 60).round();
          final added = rawAdded < 0 ? 0 : (rawAdded > 999 ? 999 : rawAdded);
          newPlayers[entry.key] = p.copyWith(
            min: p.min + added,
            minutesEnteredAt: () => 600,
          );
        }
      }
      state = state.copyWith(quarter: state.quarter + 1, players: newPlayers);
      return true;
    }

    // With-clock mode: stop clock, reset to 600, finalize minutes.
    if (state.clockRunning) {
      _clockTimer?.cancel();
      _clockTimer = null;
      state = state.copyWith(clockRunning: false);
    }

    final newPlayers = Map<String, LivePlayerStats>.from(state.players);
    for (final entry in newPlayers.entries) {
      final p = entry.value;
      if (p.onCourt && p.minutesEnteredAt != null) {
        final rawAdded = (p.minutesEnteredAt! / 60).round();
        final added = rawAdded < 0 ? 0 : (rawAdded > 999 ? 999 : rawAdded);
        newPlayers[entry.key] = p.copyWith(
          min: p.min + added,
          minutesEnteredAt: () => 600,
        );
      }
    }

    state = state.copyWith(
      quarter: state.quarter + 1,
      clockSeconds: 600,
      players: newPlayers,
    );
    return true;
  }

  // ──────────────────────────── End Game ───────────────────────────────────

  /// End the game and finalize all player minutes.
  /// Returns a [GameStatsModel] ready for Firestore.
  GameStatsModel endGame() {
    // Always cancel timer directly (stopClock is a no-op in statsOnly mode).
    _clockTimer?.cancel();
    _clockTimer = null;
    if (state.clockRunning) {
      state = state.copyWith(clockRunning: false);
    }

    final newPlayers = Map<String, LivePlayerStats>.from(state.players);
    for (final entry in newPlayers.entries) {
      final p = entry.value;
      if (p.onCourt && p.minutesEnteredAt != null) {
        final rawMin = ((p.minutesEnteredAt! - state.clockSeconds) / 60)
            .round();
        final added = rawMin < 0 ? 0 : (rawMin > 999 ? 999 : rawMin);
        newPlayers[entry.key] = p.copyWith(
          min: p.min + added,
          minutesEnteredAt: () => null,
        );
      }
    }

    state = state.copyWith(gameEnded: true, players: newPlayers);

    // Convert to GameStatsModel.
    final Map<String, PlayerStatLine> playerLines = {};
    for (final p in newPlayers.values) {
      if (p.pts > 0 ||
          p.reb > 0 ||
          p.ast > 0 ||
          p.stl > 0 ||
          p.blk > 0 ||
          p.fls > 0 ||
          p.min > 0 ||
          p.to > 0) {
        playerLines[p.id] = PlayerStatLine(
          name: p.name,
          teamId: p.teamId,
          pts: p.pts,
          oreb: p.oreb,
          dreb: p.dreb,
          ast: p.ast,
          stl: p.stl,
          blk: p.blk,
          fls: p.fls,
          min: p.min,
        );
      }
    }

    // Build quarter scores from play-by-play.
    final qScores = state.quarterScores;
    final homeQScores = <int, int>{};
    final awayQScores = <int, int>{};
    for (final entry in qScores.entries) {
      homeQScores[entry.key] = entry.value.home;
      awayQScores[entry.key] = entry.value.away;
    }

    // Build per-quarter player stats from play-by-play.
    final pqStats = <String, Map<int, Map<String, int>>>{};
    for (final pid in playerLines.keys) {
      final byQ = state.playerStatsByQuarter(pid);
      if (byQ.isNotEmpty) {
        pqStats[pid] = byQ.map(
          (q, pqs) => MapEntry(q, {
            'pts': pqs.pts,
            'oreb': pqs.oreb,
            'dreb': pqs.dreb,
            'reb': pqs.reb,
            'ast': pqs.ast,
            'stl': pqs.stl,
            'blk': pqs.blk,
            'to': pqs.to,
            'fls': pqs.fls,
          }),
        );
      }
    }

    return GameStatsModel(
      id: state.eventId ?? 'live_${DateTime.now().millisecondsSinceEpoch}',
      eventId: state.eventId ?? 'live_${DateTime.now().millisecondsSinceEpoch}',
      seasonId: state.seasonId ?? '',
      divisionId: state.divisionId ?? '',
      homeTeamId: state.homeTeamId,
      awayTeamId: state.awayTeamId,
      homeTeamName: state.homeTeamName,
      awayTeamName: state.awayTeamName,
      homeScore: state.homeScore,
      awayScore: state.awayScore,
      status: GameStatsStatus.submitted,
      entryMode: GameStatsEntryMode.live,
      playerLines: playerLines,
      homeQuarterScores: homeQScores,
      awayQuarterScores: awayQScores,
      playerQuarterStats: pqStats.isNotEmpty ? pqStats : null,
    );
  }
}
