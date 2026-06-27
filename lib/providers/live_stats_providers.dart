import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/stats/live_stats_notifier.dart';
import '../features/stats/live_stats_state.dart';

/// Main provider for the live game state.
///
/// NOT auto-disposed — must survive the setup → game-phase transition.
/// The [LiveStatsScreen] invalidates this provider when it is disposed so
/// that the next session starts with a clean state.
final liveGameProvider =
    StateNotifierProvider<LiveStatsNotifier, LiveGameState>((ref) {
  return LiveStatsNotifier(
    const LiveGameState(
      homeTeamId: '',
      awayTeamId: '',
      homeTeamName: '',
      awayTeamName: '',
    ),
  );
});
