import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/live_stats_state.dart';

/// Tests for ActionPanel's enable/disable logic.
///
/// The actual ActionPanel widget relies on Riverpod providers and the full
/// widget tree. Rather than mocking the entire provider chain, we test the
/// same boolean conditions that the widget evaluates:
///
///   canAct  = hasSelection && isOnCourt && !isFouledOut
///   canSub  = hasSelection && isOnCourt
///   canUndo = plays.isNotEmpty

void main() {
  LiveGameState makeState({
    String? selectedPlayerId,
    Map<String, LivePlayerStats>? players,
    List<GamePlay>? plays,
  }) {
    return LiveGameState(
      homeTeamId: 'home',
      awayTeamId: 'away',
      homeTeamName: 'Home',
      awayTeamName: 'Away',
      selectedPlayerId: selectedPlayerId,
      players: players ?? {},
      plays: plays ?? [],
    );
  }

  LivePlayerStats makePlayer({
    String id = 'p1',
    bool onCourt = true,
    int fls = 0,
  }) {
    return LivePlayerStats(
      id: id,
      name: 'Player',
      teamId: 'home',
      num: 10,
      onCourt: onCourt,
      fls: fls,
    );
  }

  group('Button enable conditions', () {
    test('all disabled when no player selected', () {
      final state = makeState();
      final selected = state.selectedPlayer;
      final hasSelection = selected != null;

      expect(hasSelection, false);
      // canAct and canSub both require hasSelection, so both are false
      expect(selected, isNull);
    });

    test('all disabled when bench player selected', () {
      final player = makePlayer(onCourt: false);
      final state = makeState(
        selectedPlayerId: 'p1',
        players: {'p1': player},
      );
      final selected = state.selectedPlayer;
      final hasSelection = selected != null;
      final isOnCourt = selected?.onCourt ?? false;

      expect(hasSelection, true);
      expect(isOnCourt, false);
      // canAct = hasSelection && isOnCourt && !isFouledOut -> false
      expect(hasSelection && isOnCourt, false);
    });

    test('stat buttons enabled when on-court player selected', () {
      final player = makePlayer(onCourt: true);
      final state = makeState(
        selectedPlayerId: 'p1',
        players: {'p1': player},
      );
      final selected = state.selectedPlayer;
      final hasSelection = selected != null;
      final isOnCourt = selected?.onCourt ?? false;
      final isFouledOut = selected?.isFouledOut ?? false;

      final canAct = hasSelection && isOnCourt && !isFouledOut;
      final canSub = hasSelection && isOnCourt;

      expect(canAct, true);
      expect(canSub, true);
    });

    test('stat buttons disabled for fouled-out player, but SUB still enabled',
        () {
      final player = makePlayer(onCourt: true, fls: 5);
      final state = makeState(
        selectedPlayerId: 'p1',
        players: {'p1': player},
      );
      final selected = state.selectedPlayer;
      final hasSelection = selected != null;
      final isOnCourt = selected?.onCourt ?? false;
      final isFouledOut = selected?.isFouledOut ?? false;

      final canAct = hasSelection && isOnCourt && !isFouledOut;
      final canSub = hasSelection && isOnCourt;

      expect(isFouledOut, true);
      expect(canAct, false);
      expect(canSub, true); // Can still substitute fouled-out player
    });

    test('undo disabled when no plays', () {
      final state = makeState(plays: []);
      expect(state.plays.isNotEmpty, false);
    });

    test('undo enabled when plays exist', () {
      final play = GamePlay(
        localId: 'test_1',
        playerId: 'p1',
        playerName: 'Player',
        playerNum: 10,
        teamId: 'home',
        action: '2PT_MAKE',
        description: '2PT Made',
        quarter: 1,
        clockSeconds: 500,
      );
      final state = makeState(plays: [play]);
      expect(state.plays.isNotEmpty, true);
    });
  });

  group('isFouledOut threshold', () {
    test('player with 4 fouls is not fouled out', () {
      final player = makePlayer(fls: 4);
      expect(player.isFouledOut, false);
    });

    test('player with 5 fouls is fouled out', () {
      final player = makePlayer(fls: 5);
      expect(player.isFouledOut, true);
    });

    test('player with 0 fouls is not fouled out', () {
      final player = makePlayer(fls: 0);
      expect(player.isFouledOut, false);
    });
  });

  group('LiveGameState computed properties', () {
    test('homeScore sums pts for home team players', () {
      final state = makeState(
        players: {
          'p1': LivePlayerStats(
            id: 'p1', name: 'A', teamId: 'home', num: 1, pts: 10,
          ),
          'p2': LivePlayerStats(
            id: 'p2', name: 'B', teamId: 'home', num: 2, pts: 5,
          ),
          'p3': LivePlayerStats(
            id: 'p3', name: 'C', teamId: 'away', num: 3, pts: 20,
          ),
        },
      );

      expect(state.homeScore, 15);
      expect(state.awayScore, 20);
    });

    test('selectedPlayer returns null when no selection', () {
      final state = makeState();
      expect(state.selectedPlayer, isNull);
    });

    test('selectedPlayer returns the correct player', () {
      final player = makePlayer(id: 'p1');
      final state = makeState(
        selectedPlayerId: 'p1',
        players: {'p1': player},
      );
      expect(state.selectedPlayer, isNotNull);
      expect(state.selectedPlayer!.id, 'p1');
    });

    test('clockFormatted displays correct format', () {
      const state = LiveGameState(
        homeTeamId: 'h',
        awayTeamId: 'a',
        homeTeamName: 'H',
        awayTeamName: 'A',
        clockSeconds: 125, // 2:05
      );
      expect(state.clockFormatted, '2:05');
    });

    test('clockFormatted at 600 seconds shows 10:00', () {
      const state = LiveGameState(
        homeTeamId: 'h',
        awayTeamId: 'a',
        homeTeamName: 'H',
        awayTeamName: 'A',
        clockSeconds: 600,
      );
      expect(state.clockFormatted, '10:00');
    });

    test('clockFormatted at 0 seconds shows 0:00', () {
      const state = LiveGameState(
        homeTeamId: 'h',
        awayTeamId: 'a',
        homeTeamName: 'H',
        awayTeamName: 'A',
        clockSeconds: 0,
      );
      expect(state.clockFormatted, '0:00');
    });
  });
}
