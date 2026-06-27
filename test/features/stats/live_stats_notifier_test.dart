import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/live_stats_notifier.dart';
import 'package:hoops_connect/features/stats/live_stats_state.dart';
import 'package:hoops_connect/models/game_stats_model.dart';

/// Helper to create a notifier with a pre-configured game.
LiveStatsNotifier _createNotifier({
  int homePlayersOnCourt = 5,
  int homeBenchPlayers = 3,
  int awayPlayersOnCourt = 5,
  int awayBenchPlayers = 3,
  ClockMode clockMode = ClockMode.statsOnly,
}) {
  final notifier = LiveStatsNotifier(
    const LiveGameState(
      homeTeamId: '',
      awayTeamId: '',
      homeTeamName: '',
      awayTeamName: '',
    ),
  );

  final players = <String, LivePlayerStats>{};

  for (int i = 0; i < homePlayersOnCourt; i++) {
    final id = 'hp$i';
    players[id] = LivePlayerStats(
      id: id,
      name: 'Home Player $i',
      teamId: 'home',
      num: 10 + i,
      onCourt: true,
      minutesEnteredAt: 600,
    );
  }
  for (int i = 0; i < homeBenchPlayers; i++) {
    final id = 'hb$i';
    players[id] = LivePlayerStats(
      id: id,
      name: 'Home Bench $i',
      teamId: 'home',
      num: 20 + i,
      onCourt: false,
    );
  }
  for (int i = 0; i < awayPlayersOnCourt; i++) {
    final id = 'ap$i';
    players[id] = LivePlayerStats(
      id: id,
      name: 'Away Player $i',
      teamId: 'away',
      num: 30 + i,
      onCourt: true,
      minutesEnteredAt: 600,
    );
  }
  for (int i = 0; i < awayBenchPlayers; i++) {
    final id = 'ab$i';
    players[id] = LivePlayerStats(
      id: id,
      name: 'Away Bench $i',
      teamId: 'away',
      num: 40 + i,
      onCourt: false,
    );
  }

  notifier.initGame(
    homeTeamId: 'home',
    awayTeamId: 'away',
    homeTeamName: 'Home Team',
    awayTeamName: 'Away Team',
    players: players,
    seasonId: 'season1',
    eventId: 'event1',
    divisionId: 'div1',
    clockMode: clockMode,
  );

  return notifier;
}

/// Helper to read state from the notifier using the addListener pattern.
LiveGameState _state(LiveStatsNotifier n) {
  // ignore: invalid_use_of_protected_member
  return n.state;
}

void main() {
  // ─────────────────────── initGame ───────────────────────

  group('initGame', () {
    test('creates correct number of players', () {
      final n = _createNotifier();
      final s = _state(n);

      expect(s.players.length, 16); // 5+3 home + 5+3 away
      expect(s.players.values.where((p) => p.teamId == 'home').length, 8);
      expect(s.players.values.where((p) => p.teamId == 'away').length, 8);
    });

    test('sets team names and IDs', () {
      final n = _createNotifier();
      final s = _state(n);

      expect(s.homeTeamId, 'home');
      expect(s.awayTeamId, 'away');
      expect(s.homeTeamName, 'Home Team');
      expect(s.awayTeamName, 'Away Team');
    });

    test('on-court players count is correct', () {
      final n = _createNotifier();
      final s = _state(n);

      final onCourt = s.players.values.where((p) => p.onCourt).length;
      expect(onCourt, 10); // 5 home + 5 away
    });

    test('initial scores are 0', () {
      final n = _createNotifier();
      final s = _state(n);

      expect(s.homeScore, 0);
      expect(s.awayScore, 0);
    });
  });

  // ─────────────────────── selectPlayer ───────────────────────

  group('selectPlayer', () {
    test('updates selectedPlayerId', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      expect(_state(n).selectedPlayerId, 'hp0');
    });

    test('selecting another player replaces selection', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.selectPlayer('hp1');
      expect(_state(n).selectedPlayerId, 'hp1');
    });

    test('clearSelection sets selectedPlayerId to null', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.clearSelection();
      expect(_state(n).selectedPlayerId, isNull);
    });
  });

  // ─────────────────────── recordStat ───────────────────────

  group('recordStat', () {
    test('2PT_MAKE adds 2 points', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');

      expect(_state(n).players['hp0']!.pts, 2);
    });

    test('3PT_MAKE adds 3 points', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('3PT_MAKE');

      expect(_state(n).players['hp0']!.pts, 3);
    });

    test('FT_MAKE adds 1 point', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('FT_MAKE');

      expect(_state(n).players['hp0']!.pts, 1);
    });

    test('misses do not change points', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MISS');
      n.recordStat('3PT_MISS');
      n.recordStat('FT_MISS');

      expect(_state(n).players['hp0']!.pts, 0);
    });

    test('OREB increments offensive rebounds', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('OREB');

      expect(_state(n).players['hp0']!.oreb, 1);
    });

    test('DREB increments defensive rebounds', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('DREB');

      expect(_state(n).players['hp0']!.dreb, 1);
    });

    test('AST increments assists', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('AST');

      expect(_state(n).players['hp0']!.ast, 1);
    });

    test('STL increments steals', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('STL');

      expect(_state(n).players['hp0']!.stl, 1);
    });

    test('BLK increments blocks', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('BLK');

      expect(_state(n).players['hp0']!.blk, 1);
    });

    test('TO increments turnovers', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('TO');

      expect(_state(n).players['hp0']!.to, 1);
    });

    test('FLS increments fouls', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('FLS');

      expect(_state(n).players['hp0']!.fls, 1);
    });

    test('scoring updates team score via homeScore getter', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('3PT_MAKE');

      expect(_state(n).homeScore, 5);
      expect(_state(n).awayScore, 0);
    });

    test('returns null when no player selected', () {
      final n = _createNotifier();
      final result = n.recordStat('2PT_MAKE');
      expect(result, isNull);
    });

    test('creates play-by-play entry', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');

      expect(_state(n).plays.length, 1);
      expect(_state(n).plays.first.action, '2PT_MAKE');
      expect(_state(n).plays.first.pointsScored, 2);
    });

    test('returns null for unknown action', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      final result = n.recordStat('UNKNOWN_ACTION');
      expect(result, isNull);
    });

    test('returns null for bench player', () {
      final n = _createNotifier();
      n.selectPlayer('hb0'); // bench player
      final result = n.recordStat('2PT_MAKE');
      expect(result, isNull);
    });
  });

  // ─────────────────────── 5-foul limit ───────────────────────

  group('foul-out detection', () {
    test('4th foul returns warning message', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('FLS');
      n.recordStat('FLS');
      n.recordStat('FLS');
      final result = n.recordStat('FLS');

      expect(result, contains('4 fouls'));
      expect(_state(n).players['hp0']!.fls, 4);
    });

    test('5th foul triggers FOUL_OUT message', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      for (int i = 0; i < 4; i++) {
        n.recordStat('FLS');
      }
      final result = n.recordStat('FLS');

      expect(result, startsWith('FOUL_OUT:'));
      expect(_state(n).players['hp0']!.fls, 5);
      expect(_state(n).players['hp0']!.isFouledOut, true);
    });

    test('cannot record 6th foul', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      for (int i = 0; i < 5; i++) {
        n.recordStat('FLS');
      }
      // Player is fouled out (isFouledOut == true), so recordStat returns null
      // and fls stays at 5 (not incremented further)
      final result = n.recordStat('FLS');

      expect(result, isNull);
      expect(_state(n).players['hp0']!.fls, 5);
      expect(_state(n).players['hp0']!.isFouledOut, isTrue);
    });

    test('fouled-out player cannot record other stats', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      for (int i = 0; i < 5; i++) {
        n.recordStat('FLS');
      }

      // Player is fouled out, stats should not be recorded
      final result = n.recordStat('2PT_MAKE');
      expect(result, isNull);
      expect(_state(n).players['hp0']!.pts, 0);
    });
  });

  // ─────────────────────── undo ───────────────────────

  group('undo', () {
    test('undo reverses a scoring play', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('3PT_MAKE');

      expect(_state(n).players['hp0']!.pts, 3);

      n.undo();

      expect(_state(n).players['hp0']!.pts, 0);
      expect(_state(n).plays, isEmpty);
    });

    test('undo reverses an assist', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('AST');
      expect(_state(n).players['hp0']!.ast, 1);

      n.undo();
      expect(_state(n).players['hp0']!.ast, 0);
    });

    test('undo reverses a foul', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('FLS');
      n.recordStat('FLS');
      expect(_state(n).players['hp0']!.fls, 2);

      n.undo();
      expect(_state(n).players['hp0']!.fls, 1);
    });

    test('undo does nothing when no plays exist', () {
      final n = _createNotifier();
      n.undo(); // should not throw
      expect(_state(n).plays, isEmpty);
    });

    test('undo does not revert a miss (since no stat was changed)', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MISS');
      expect(_state(n).players['hp0']!.pts, 0);

      n.undo();
      // Points should still be 0 (misses have no stat to revert)
      expect(_state(n).players['hp0']!.pts, 0);
      expect(_state(n).plays, isEmpty);
    });

    test('undo removes the most recent play log entry', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('AST');

      expect(_state(n).plays.length, 2);

      n.undo();
      expect(_state(n).plays.length, 1);
      expect(_state(n).plays.first.action, '2PT_MAKE');
    });
  });

  // ─────────────────────── substitution ───────────────────────

  group('substitution', () {
    test('startSub enters sub mode', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();

      expect(_state(n).subMode, true);
      expect(_state(n).subOutPlayerId, 'hp0');
    });

    test('completeSub swaps players on/off court', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();
      n.completeSub('hb0');

      final s = _state(n);
      expect(s.players['hp0']!.onCourt, false);
      expect(s.players['hb0']!.onCourt, true);
      expect(s.subMode, false);
      expect(s.selectedPlayerId, isNull);
    });

    test('completeSub creates a SUB play entry', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();
      n.completeSub('hb0');

      expect(_state(n).plays.length, 1);
      expect(_state(n).plays.first.action, 'SUB');
      expect(_state(n).plays.first.type, 'sub');
    });

    test('completeSub rejects cross-team sub', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();
      // Try to sub in an away bench player for a home player
      n.completeSub('ab0');

      // Should not swap
      expect(_state(n).players['hp0']!.onCourt, true);
      expect(_state(n).players['ab0']!.onCourt, false);
    });

    test('cancelSub exits sub mode', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();
      n.cancelSub();

      expect(_state(n).subMode, false);
      expect(_state(n).subOutPlayerId, isNull);
    });

    test('undo reverses a substitution', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.startSub();
      n.completeSub('hb0');

      // Verify swap happened
      expect(_state(n).players['hp0']!.onCourt, false);
      expect(_state(n).players['hb0']!.onCourt, true);

      n.undo();

      // Swap should be reversed
      expect(_state(n).players['hp0']!.onCourt, true);
      expect(_state(n).players['hb0']!.onCourt, false);
    });

    test('startFoulOutSub sets subMode for specific player', () {
      final n = _createNotifier();
      n.startFoulOutSub('hp0');

      expect(_state(n).subMode, true);
      expect(_state(n).subOutPlayerId, 'hp0');
      expect(_state(n).selectedPlayerId, 'hp0');
    });
  });

  // ─────────────────────── endGame ───────────────────────

  group('endGame', () {
    test('produces valid GameStatsModel with submitted status', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('3PT_MAKE');

      n.selectPlayer('ap0');
      n.recordStat('FT_MAKE');

      final model = n.endGame();

      expect(model, isA<GameStatsModel>());
      expect(model.status, GameStatsStatus.submitted);
      expect(model.entryMode, GameStatsEntryMode.live);
      expect(model.homeTeamId, 'home');
      expect(model.awayTeamId, 'away');
      expect(model.homeTeamName, 'Home Team');
      expect(model.awayTeamName, 'Away Team');
      expect(model.seasonId, 'season1');
      expect(model.divisionId, 'div1');
      expect(model.eventId, 'event1');
    });

    test('endGame includes players who recorded stats', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');

      final model = n.endGame();

      expect(model.playerLines.containsKey('hp0'), true);
      expect(model.playerLines['hp0']!.pts, 2);
    });

    test('endGame excludes players with zero stats and zero minutes', () {
      final n = _createNotifier();
      // Only hp0 scores
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');

      final model = n.endGame();

      // hp0 should be included (has pts and minutes)
      expect(model.playerLines.containsKey('hp0'), true);
      // Bench players with no stats and no minutes should be excluded
      expect(model.playerLines.containsKey('hb0'), false);
    });

    test('endGame sets gameEnded flag', () {
      final n = _createNotifier();
      n.endGame();

      expect(_state(n).gameEnded, true);
    });

    test('endGame scores match state scores', () {
      final n = _createNotifier();
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE'); // home +2
      n.selectPlayer('ap0');
      n.recordStat('3PT_MAKE'); // away +3

      final model = n.endGame();

      expect(model.homeScore, 2);
      expect(model.awayScore, 3);
    });

    test('endGame winnerTeamId is correct', () {
      final n = _createNotifier();
      n.selectPlayer('ap0');
      n.recordStat('3PT_MAKE'); // away leads 3-0

      final model = n.endGame();

      expect(model.winnerTeamId, 'away');
    });
  });

  // ─────────────────────── clock ───────────────────────

  group('clock / quarter', () {
    test('initial quarter is 1 and clock is 600', () {
      final n = _createNotifier();
      expect(_state(n).quarter, 1);
      expect(_state(n).clockSeconds, 600);
    });

    test('nextQuarter advances quarter and resets clock', () {
      final n = _createNotifier();
      final advanced = n.nextQuarter();

      expect(advanced, true);
      expect(_state(n).quarter, 2);
      expect(_state(n).clockSeconds, 600);
    });

    test('nextQuarter returns false in Q4', () {
      final n = _createNotifier();
      n.nextQuarter(); // Q2
      n.nextQuarter(); // Q3
      n.nextQuarter(); // Q4

      final result = n.nextQuarter();
      expect(result, false);
      expect(_state(n).quarter, 4);
    });
  });

  // ─────────────────────── clock modes ───────────────────────

  group('clock modes', () {
    test('initGame with statsOnly mode → clockMode is statsOnly', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);
      expect(_state(n).clockMode, ClockMode.statsOnly);
    });

    test('initGame with withClock mode → clockMode is withClock', () {
      final n = _createNotifier(clockMode: ClockMode.withClock);
      expect(_state(n).clockMode, ClockMode.withClock);
    });

    test(
      'toggleClock in statsOnly mode → no-op (clockRunning stays false)',
      () {
        final n = _createNotifier(clockMode: ClockMode.statsOnly);
        expect(_state(n).clockRunning, false);

        n.toggleClock();
        expect(_state(n).clockRunning, false);
      },
    );

    test(
      'toggleClock in withClock mode → starts clock (clockRunning becomes true)',
      () {
        final n = _createNotifier(clockMode: ClockMode.withClock);
        expect(_state(n).clockRunning, false);

        n.toggleClock();
        expect(_state(n).clockRunning, true);

        // Clean up timer by stopping the clock.
        n.stopClock();
      },
    );

    test('startClock in statsOnly mode → no-op', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);
      n.startClock();
      expect(_state(n).clockRunning, false);
    });
  });

  // ─────────────────────── stats-only quarter advancement ───────────────────────

  group('stats-only quarter advancement', () {
    test(
      'nextQuarter in statsOnly mode → quarter increments, clockSeconds unchanged',
      () {
        final n = _createNotifier(clockMode: ClockMode.statsOnly);
        final initialClock = _state(n).clockSeconds;

        n.nextQuarter();
        expect(_state(n).quarter, 2);
        // In statsOnly mode, clockSeconds is not explicitly reset to 600 — it
        // stays at whatever it was (which is already 600 by default).
        expect(_state(n).clockSeconds, initialClock);
      },
    );

    test(
      'nextQuarter in withClock mode → quarter increments, clockSeconds resets to 600',
      () {
        final n = _createNotifier(clockMode: ClockMode.withClock);

        // Start clock to let it tick down, then advance quarter.
        // Since we can't easily tick the timer in a unit test, we verify the
        // nextQuarter explicitly resets clockSeconds to 600.
        n.nextQuarter();
        expect(_state(n).quarter, 2);
        expect(_state(n).clockSeconds, 600);
      },
    );

    test('can record stats in Q1 then advance to Q2 and record more', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      expect(_state(n).players['hp0']!.pts, 2);
      expect(_state(n).quarter, 1);

      n.nextQuarter();
      expect(_state(n).quarter, 2);

      // Selection survives quarter advance — no need to re-select.
      n.recordStat('3PT_MAKE');
      expect(_state(n).players['hp0']!.pts, 5); // 2 + 3
    });

    test(
      'stats recorded in different quarters have correct quarter field in plays',
      () {
        final n = _createNotifier(clockMode: ClockMode.statsOnly);

        n.selectPlayer('hp0');
        n.recordStat('2PT_MAKE'); // Q1
        n.nextQuarter();
        n.recordStat('3PT_MAKE'); // Q2

        final plays = _state(n).plays;
        // plays is newest-first: [Q2 play, Q1 play]
        expect(plays.length, 2);
        expect(plays[0].quarter, 2); // newest (Q2)
        expect(plays[0].action, '3PT_MAKE');
        expect(plays[1].quarter, 1); // older (Q1)
        expect(plays[1].action, '2PT_MAKE');
      },
    );
  });

  // ─────────────────────── quarter scores ───────────────────────

  group('quarter scores', () {
    test(
      'quarterScores computed correctly after recording plays in multiple quarters',
      () {
        final n = _createNotifier(clockMode: ClockMode.statsOnly);

        // Q1: home scores 5 points (2PT + 3PT)
        n.selectPlayer('hp0');
        n.recordStat('2PT_MAKE'); // +2
        n.recordStat('3PT_MAKE'); // +3

        n.nextQuarter(); // advance to Q2

        // Q2: away scores 4 points (2PT + 2PT)
        n.selectPlayer('ap0');
        n.recordStat('2PT_MAKE'); // +2
        n.recordStat('2PT_MAKE'); // +2

        final qs = _state(n).quarterScores;
        expect(qs[1]!.home, 5);
        expect(qs[1]!.away, 0);
        expect(qs[2]!.home, 0);
        expect(qs[2]!.away, 4);
      },
    );

    test('quarterScores empty when no scoring plays', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      // Record only non-scoring plays
      n.selectPlayer('hp0');
      n.recordStat('AST');
      n.recordStat('DREB');

      final qs = _state(n).quarterScores;
      expect(qs, isEmpty);
    });

    test('quarterScores handles missed shots (no points) correctly', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      n.selectPlayer('hp0');
      n.recordStat('2PT_MISS');
      n.recordStat('3PT_MISS');

      final qs = _state(n).quarterScores;
      // Misses have pointsScored == 0, so they should not appear in quarterScores
      expect(qs, isEmpty);
    });

    test('quarter scores only count makes (not misses)', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      n.selectPlayer('hp0');
      n.recordStat('2PT_MISS'); // 0 pts
      n.recordStat('2PT_MAKE'); // 2 pts
      n.recordStat('3PT_MISS'); // 0 pts
      n.recordStat('FT_MAKE'); // 1 pt

      final qs = _state(n).quarterScores;
      expect(qs[1]!.home, 3); // 2 + 1
      expect(qs[1]!.away, 0);
    });
  });

  // ─────────────────────── playerStatsByQuarter ───────────────────────

  group('playerStatsByQuarter', () {
    test('playerStatsByQuarter returns correct breakdown', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      // Q1: hp0 records 2PT_MAKE, AST, DREB
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('AST');
      n.recordStat('DREB');

      n.nextQuarter(); // Q2

      // Q2: hp0 records 3PT_MAKE, STL — selection persists across quarters.
      n.recordStat('3PT_MAKE');
      n.recordStat('STL');

      final byQ = _state(n).playerStatsByQuarter('hp0');

      // Q1 stats
      expect(byQ[1]!.pts, 2);
      expect(byQ[1]!.ast, 1);
      expect(byQ[1]!.dreb, 1);
      expect(byQ[1]!.stl, 0);

      // Q2 stats
      expect(byQ[2]!.pts, 3);
      expect(byQ[2]!.ast, 0);
      expect(byQ[2]!.dreb, 0);
      expect(byQ[2]!.stl, 1);
    });

    test('playerStatsByQuarter returns empty map for player with no plays', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      // hp1 never records anything
      final byQ = _state(n).playerStatsByQuarter('hp1');
      expect(byQ, isEmpty);
    });

    test('misses don\'t add to stats but ARE in the quarter\'s play list', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      n.selectPlayer('hp0');
      n.recordStat('2PT_MISS');
      n.recordStat('3PT_MISS');
      n.recordStat('2PT_MAKE');

      final byQ = _state(n).playerStatsByQuarter('hp0');
      // Only the make should contribute points
      expect(byQ[1]!.pts, 2);

      // But the plays list should have all 3 entries
      final plays = _state(n).plays;
      expect(plays.length, 3);

      // Verify misses are present in play log with correct quarter
      final misses = plays.where((p) => p.isMiss).toList();
      expect(misses.length, 2);
      expect(misses.every((p) => p.quarter == 1), true);
    });
  });

  // ─────────────────────── endGame with quarter data ───────────────────────

  group('endGame with quarter data', () {
    test(
      'endGame returns GameStatsModel with homeQuarterScores and awayQuarterScores',
      () {
        final n = _createNotifier(clockMode: ClockMode.statsOnly);

        // Q1: home scores
        n.selectPlayer('hp0');
        n.recordStat('2PT_MAKE'); // home +2

        n.nextQuarter(); // Q2

        // Q2: away scores
        n.selectPlayer('ap0');
        n.recordStat('3PT_MAKE'); // away +3

        final model = n.endGame();

        expect(model.homeQuarterScores[1], 2);
        expect(model.homeQuarterScores[2] ?? 0, 0); // no home scoring in Q2
        expect(model.awayQuarterScores[2], 3);
        expect(model.awayQuarterScores[1] ?? 0, 0); // no away scoring in Q1
      },
    );

    test('endGame returns GameStatsModel with playerQuarterStats', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('AST');

      n.nextQuarter();

      // Selection persists across quarters.
      n.recordStat('FT_MAKE');

      final model = n.endGame();

      expect(model.playerQuarterStats, isNotNull);
      expect(model.playerQuarterStats!.containsKey('hp0'), true);

      final hp0Q1 = model.playerQuarterStats!['hp0']![1]!;
      expect(hp0Q1['pts'], 2);
      expect(hp0Q1['ast'], 1);

      final hp0Q2 = model.playerQuarterStats!['hp0']![2]!;
      expect(hp0Q2['pts'], 1);
      expect(hp0Q2['ast'], 0);
    });

    test('quarter data matches what was recorded during game', () {
      final n = _createNotifier(clockMode: ClockMode.statsOnly);

      // Q1: home 7 pts (2PT + 2PT + 3PT), away 2 pts (2PT)
      n.selectPlayer('hp0');
      n.recordStat('2PT_MAKE');
      n.recordStat('2PT_MAKE');
      n.selectPlayer('hp1');
      n.recordStat('3PT_MAKE');
      n.selectPlayer('ap0');
      n.recordStat('2PT_MAKE');

      n.nextQuarter();

      // Q2: home 1 pt (FT), away 6 pts (3PT + 3PT)
      n.selectPlayer('hp0');
      n.recordStat('FT_MAKE');
      n.selectPlayer('ap0');
      n.recordStat('3PT_MAKE');
      n.recordStat('3PT_MAKE');

      final model = n.endGame();

      // Verify total scores
      expect(model.homeScore, 8); // 7 + 1
      expect(model.awayScore, 8); // 2 + 6

      // Verify quarter scores
      expect(model.homeQuarterScores[1], 7);
      expect(model.homeQuarterScores[2], 1);
      expect(model.awayQuarterScores[1], 2);
      expect(model.awayQuarterScores[2], 6);

      // Verify player quarter stats
      expect(model.playerQuarterStats!['hp0']![1]!['pts'], 4); // 2+2
      expect(model.playerQuarterStats!['hp0']![2]!['pts'], 1); // FT
      expect(model.playerQuarterStats!['hp1']![1]!['pts'], 3); // 3PT
      expect(model.playerQuarterStats!['ap0']![1]!['pts'], 2); // 2PT
      expect(model.playerQuarterStats!['ap0']![2]!['pts'], 6); // 3+3
    });
  });
}
