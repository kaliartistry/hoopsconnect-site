import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../models/event_model.dart';
import '../../models/game_stats_model.dart';
import '../../providers/stats_providers.dart';

class StatGameSelectScreen extends ConsumerWidget {
  const StatGameSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(allGamesForStatsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Game Stats'),
      ),
      body: gamesAsync.when(
        data: (games) {
          if (games.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sports_score_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No games found',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Schedule games first to enter stats',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: games.length,
            itemBuilder: (context, index) {
              final game = games[index];
              return _GameCard(game: game);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _GameCard extends ConsumerWidget {
  final EventModel game;

  const _GameCard({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameStatsAsync = ref.watch(gameStatsProvider(game.id));
    final gameStats = gameStatsAsync.valueOrNull;
    final dateStr = LeagueTime.formatJamaicaDate(
      game.startTime,
      pattern: 'EEE, MMM d',
    );
    final timeStr = LeagueTime.formatJamaicaTime(game.startTime);
    final isApproved =
        game.statsStatus == StatsStatus.approved ||
        gameStats?.status == GameStatsStatus.approved;
    final isSubmitted =
        !isApproved &&
        (game.statsStatus == StatsStatus.submitted ||
            gameStats?.status == GameStatsStatus.submitted);
    final hasStats = isApproved || isSubmitted;
    final isPending = game.statsStatus == StatsStatus.pending;
    final hasPostGameDraft =
        (gameStats?.status.isEditable ?? false) &&
        gameStats?.entryMode == GameStatsEntryMode.postGame;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        children: [
          // Game info row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Game icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasStats
                        ? const Color(0xFFDCFCE7)
                        : AppColors.statBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasStats
                        ? Icons.check_circle_outline
                        : Icons.sports_basketball,
                    color: hasStats
                        ? const Color(0xFF16A34A)
                        : AppColors.statHighlight,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Game info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dateStr at $timeStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (game.location != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          game.location!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Status badge
                _StatusBadge(status: game.statsStatus),
              ],
            ),
          ),

          // Action buttons
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (hasStats) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.scoreboard_outlined,
                          label: 'View Box Score',
                          color: const Color(0xFF16A34A),
                          onTap: () => context.push('/box-score/${game.id}'),
                        ),
                      ),
                      if (isSubmitted) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.edit_note,
                            label: 'Correct Stats',
                            color: const Color(0xFF2563EB),
                            onTap: () =>
                                context.push('/admin/stats/${game.id}'),
                          ),
                        ),
                      ],
                    ] else if (hasPostGameDraft) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.edit_calendar_outlined,
                          label: 'Resume Post-Game Draft',
                          color: const Color(0xFF2563EB),
                          onTap: () => context.push('/admin/stats/${game.id}'),
                        ),
                      ),
                    ] else if (isPending) ...[
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.play_circle_outline,
                          label: 'Live Stats',
                          color: const Color(0xFFEA580C),
                          onTap: () =>
                              context.push('/live-stats?eventId=${game.id}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.edit_note,
                          label: 'Post-Game Entry',
                          color: const Color(0xFF3B82F6),
                          onTap: () => context.push('/admin/stats/${game.id}'),
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasPostGameDraft) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'A post-game draft already exists for this game. Resume it to finish totals entry.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else if (isSubmitted) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Stats are submitted and awaiting approval. Use Correct Stats to make adjustments.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else if (!hasStats && isPending) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Live Stats is play-by-play. Post-Game Entry is totals-based after the final whistle.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final StatsStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case StatsStatus.pending:
        bgColor = AppColors.ackBg;
        textColor = AppColors.ack;
        label = 'PENDING';
      case StatsStatus.submitted:
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFD97706);
        label = 'SUBMITTED';
      case StatsStatus.approved:
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF16A34A);
        label = 'APPROVED';
      case StatsStatus.cancelled:
        bgColor = AppColors.urgentBg;
        textColor = AppColors.urgent;
        label = 'CANCELLED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
