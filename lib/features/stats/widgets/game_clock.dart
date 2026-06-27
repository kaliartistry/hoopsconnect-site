import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/live_stats_providers.dart';
import '../live_stats_notifier.dart';
import '../live_stats_state.dart';

/// Clock display with Start/Stop and Next Quarter controls.
/// In [ClockMode.statsOnly], shows only a quarter badge and "Next Q" button.
class GameClock extends ConsumerWidget {
  final ClockMode clockMode;

  const GameClock({super.key, required this.clockMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(liveGameProvider);
    final notifier = ref.read(liveGameProvider.notifier);

    if (clockMode == ClockMode.statsOnly) {
      return _buildStatsOnlyWidget(context, gameState, notifier);
    }

    return _buildWithClockWidget(context, gameState, notifier);
  }

  /// Stats-only mode: large quarter badge + "Next Q" button, no clock.
  Widget _buildStatsOnlyWidget(
    BuildContext context,
    LiveGameState gameState,
    LiveStatsNotifier notifier,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Large quarter badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEA580C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Q${gameState.quarter}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Next Quarter button
        _ClockButton(
          label: 'Next Q \u2192',
          onTap: () {
            final ok = notifier.nextQuarter();
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Already in Q4 \u2014 end game when ready'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  /// With-clock mode: full clock display, start/stop, and next quarter.
  Widget _buildWithClockWidget(
    BuildContext context,
    LiveGameState gameState,
    LiveStatsNotifier notifier,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quarter badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Q${gameState.quarter}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Clock display
        SizedBox(
          width: 80,
          child: Text(
            gameState.clockFormatted,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Start/Pause button
        _ClockButton(
          label: gameState.clockRunning ? 'Pause' : 'Start',
          isRunning: gameState.clockRunning,
          onTap: () => notifier.toggleClock(),
        ),
        const SizedBox(width: 6),

        // Next Quarter button
        _ClockButton(
          label: 'Next Q',
          onTap: () {
            final ok = notifier.nextQuarter();
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Already in Q4 \u2014 end game when ready'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

class _ClockButton extends StatelessWidget {
  final String label;
  final bool isRunning;
  final VoidCallback onTap;

  const _ClockButton({
    required this.label,
    this.isRunning = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isRunning ? const Color(0xFF16A34A) : Colors.transparent,
          border: Border.all(
            color: isRunning
                ? const Color(0xFF16A34A)
                : Colors.white.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
