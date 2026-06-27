import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/live_stats_providers.dart';
import '../live_stats_state.dart';

/// Home or Away roster column for the live stat-taking screen.
class RosterPanel extends ConsumerWidget {
  final String teamId;
  final String teamName;
  final bool isHome;

  const RosterPanel({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.isHome,
  });

  static const _homeBg = Color(0xFFFFF7ED);
  static const _awayBg = Color(0xFFEFF6FF);
  static const _homeLabelColor = Color(0xFFC2410C);
  static const _awayLabelColor = Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(liveGameProvider);
    final notifier = ref.read(liveGameProvider.notifier);

    final allPlayers = gameState.players.values
        .where((p) => p.teamId == teamId)
        .toList();
    final onCourt = allPlayers.where((p) => p.onCourt).toList();
    final bench = allPlayers.where((p) => !p.onCourt).toList();

    return Container(
      color: isHome ? _homeBg : _awayBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Team label
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              teamName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: isHome ? _homeLabelColor : _awayLabelColor,
              ),
            ),
          ),
          // Scrollable roster
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                // On-court players
                ...onCourt.map((p) => _PlayerRow(
                      player: p,
                      isHome: isHome,
                      isOnCourt: true,
                      isSelected: gameState.selectedPlayerId == p.id,
                      isSubTarget: false,
                      clockSeconds: gameState.clockSeconds,
                      onTap: () => notifier.selectPlayer(p.id),
                    )),

                // Bench divider
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: AppColors.border,
                          style: BorderStyle.solid,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 6),
                    child: const Text(
                      'BENCH',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                // Bench players
                ...bench.map((p) {
                  final isSubTarget = gameState.subMode &&
                      gameState.subOutPlayerId != null &&
                      gameState.players[gameState.subOutPlayerId]?.teamId ==
                          teamId &&
                      !p.isFouledOut;

                  return _PlayerRow(
                    player: p,
                    isHome: isHome,
                    isOnCourt: false,
                    isSelected: gameState.selectedPlayerId == p.id,
                    isSubTarget: isSubTarget,
                    clockSeconds: gameState.clockSeconds,
                    onTap: () {
                      if (isSubTarget) {
                        notifier.completeSub(p.id);
                      } else {
                        notifier.selectPlayer(p.id);
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final LivePlayerStats player;
  final bool isHome;
  final bool isOnCourt;
  final bool isSelected;
  final bool isSubTarget;
  final int clockSeconds;
  final VoidCallback onTap;

  const _PlayerRow({
    required this.player,
    required this.isHome,
    required this.isOnCourt,
    required this.isSelected,
    required this.isSubTarget,
    required this.clockSeconds,
    required this.onTap,
  });

  static const _homeJerseyColor = Color(0xFFC2410C);
  static const _awayJerseyColor = Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context) {
    final isFouledOut = player.isFouledOut;
    final minutes = player.currentMinutes(clockSeconds);

    // Selection border color
    Color borderColor = Colors.transparent;
    Color? bgColor;
    BoxShadow? shadow;

    if (isFouledOut && !isSubTarget) {
      // Grayed out
    } else if (isSubTarget) {
      borderColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFF0FDF4);
    } else if (isSelected) {
      borderColor = isHome ? const Color(0xFFEA580C) : const Color(0xFF3B82F6);
      bgColor = Colors.white;
      shadow = BoxShadow(
        color: isHome
            ? const Color(0xFFEA580C).withValues(alpha: 0.2)
            : const Color(0xFF3B82F6).withValues(alpha: 0.2),
        blurRadius: 8,
        offset: const Offset(0, 2),
      );
    }

    return Opacity(
      opacity: isFouledOut && !isSubTarget
          ? 0.35
          : (!isOnCourt && !isSubTarget ? 0.6 : 1.0),
      child: GestureDetector(
        onTap: (isFouledOut && !isSubTarget) ? null : onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: EdgeInsets.symmetric(
            horizontal: isOnCourt ? 8 : 6,
            vertical: isOnCourt ? 8 : 3,
          ),
          constraints: BoxConstraints(minHeight: isOnCourt ? 52 : 34),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: shadow != null ? [shadow] : null,
          ),
          child: Row(
            children: [
              // Jersey number badge
              Container(
                width: isOnCourt ? 38 : 26,
                height: isOnCourt ? 38 : 26,
                decoration: BoxDecoration(
                  color: isOnCourt
                      ? (isHome ? _homeJerseyColor : _awayJerseyColor)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: isHome
                                ? const Color(0xFFEA580C)
                                : const Color(0xFF3B82F6),
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${player.num}',
                  style: TextStyle(
                    fontSize: isOnCourt ? 18 : 12,
                    fontWeight: FontWeight.w800,
                    color: isOnCourt ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Name + inline stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            player.name,
                            style: TextStyle(
                              fontSize: isOnCourt ? 14 : 12,
                              fontWeight:
                                  isOnCourt ? FontWeight.w600 : FontWeight.w500,
                              color: AppColors.textPrimary,
                              decoration: isFouledOut
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (player.fls >= 3) ...[
                          const SizedBox(width: 4),
                          _FoulBadge(fouls: player.fls),
                        ],
                      ],
                    ),
                    if (isSelected && isOnCourt)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${player.pts}pts ${player.oreb}or ${player.dreb}dr ${player.ast}a',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Minutes
              SizedBox(
                width: 28,
                child: Text(
                  isOnCourt
                      ? '${minutes}m'
                      : (player.min > 0 ? '${player.min}m' : ''),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 2),

              // Points
              SizedBox(
                width: 28,
                child: Text(
                  isOnCourt
                      ? '${player.pts}p'
                      : (player.pts > 0 ? '${player.pts}p' : ''),
                  style: TextStyle(
                    fontSize: isOnCourt ? 16 : 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoulBadge extends StatelessWidget {
  final int fouls;
  const _FoulBadge({required this.fouls});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    if (fouls >= 5) {
      bg = const Color(0xFFDC2626);
      fg = Colors.white;
      label = '5F OUT';
    } else if (fouls == 4) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
      label = '4F';
    } else {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
      label = '3F';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
