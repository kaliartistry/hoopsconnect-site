import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/game_stats_model.dart';
import '../../providers/stats_providers.dart';
import '../../services/game_summary_generator.dart';

class GameSummaryScreen extends ConsumerWidget {
  final String eventId;

  const GameSummaryScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(gameStatsProvider(eventId));

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Game Summary'),
        actions: [
          statsAsync.whenOrNull(
                data: (stats) {
                  if (stats == null) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Summary',
                    onPressed: () => _copySummary(context, stats),
                  );
                },
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: statsAsync.when(
        data: (stats) {
          if (stats == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined,
                      size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'Game summary not available',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return _SummaryBody(stats: stats);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _copySummary(BuildContext context, GameStatsModel stats) {
    final text = GameSummaryGenerator.generateFullSummary(stats);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Summary copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  final GameStatsModel stats;
  const _SummaryBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final headline = GameSummaryGenerator.generateHeadline(stats);
    final narrative = GameSummaryGenerator.generateNarrative(stats);
    final quarterLine = GameSummaryGenerator.generateQuarterScoreLine(stats);
    final quarterNarrative = GameSummaryGenerator.generateQuarterNarrative(stats);
    final performers = GameSummaryGenerator.getTopPerformers(stats);
    final milestones = GameSummaryGenerator.detectGameMilestones(stats);

    return ListView(
      padding: const EdgeInsets.all(AppSizes.paddingMd),
      children: [
        // Score header
        _ScoreHeader(stats: stats),
        const SizedBox(height: 20),

        // Headline
        Text(
          headline,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),

        // Quarter score line
        if (quarterLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            quarterLine,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Narrative
        Text(
          narrative,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),

        // Quarter narrative
        if (quarterNarrative.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            quarterNarrative,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Top Performers
        if (performers.isNotEmpty) ...[
          const Text(
            'TOP PERFORMERS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          ...performers.map((p) => _PerformerRow(performer: p)),
          const SizedBox(height: 20),
        ],

        // Milestones
        if (milestones.isNotEmpty) ...[
          const Text(
            'MILESTONES',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: milestones.entries.expand((entry) {
              return entry.value.map((milestone) => _MilestoneBadge(
                    playerName: entry.key,
                    milestone: milestone,
                  ));
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Action buttons
        _ActionButtons(stats: stats),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Score header
// ---------------------------------------------------------------------------

class _ScoreHeader extends StatelessWidget {
  final GameStatsModel stats;
  const _ScoreHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: stats.status == GameStatsStatus.approved
                  ? AppColors.success
                  : AppColors.ack,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stats.status == GameStatsStatus.approved
                  ? 'FINAL'
                  : stats.status.name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(
                    stats.homeTeamName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.homeScore}',
                    style: TextStyle(
                      color: stats.homeScore >= stats.awayScore
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Text(
                '-',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Column(
                children: [
                  Text(
                    stats.awayTeamName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.awayScore}',
                    style: TextStyle(
                      color: stats.awayScore >= stats.homeScore
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top Performer row
// ---------------------------------------------------------------------------

class _PerformerRow extends StatelessWidget {
  final TopPerformer performer;
  const _PerformerRow({required this.performer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          // Points badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.statBg,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Center(
              child: Text(
                '${performer.pts}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.statHighlight,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  performer.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  performer.teamName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Stat line
          Text(
            performer.statLine,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Milestone badge
// ---------------------------------------------------------------------------

class _MilestoneBadge extends StatelessWidget {
  final String playerName;
  final String milestone;
  const _MilestoneBadge(
      {required this.playerName, required this.milestone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accentLight,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                milestone,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.medalGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            playerName,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action buttons
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  final GameStatsModel stats;
  const _ActionButtons({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Copy Summary button
        OutlinedButton.icon(
          onPressed: () {
            final text = GameSummaryGenerator.generateFullSummary(stats);
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Summary copied to clipboard'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy Summary'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Share button (copies to clipboard with share-style message)
        OutlinedButton.icon(
          onPressed: () {
            final headline =
                GameSummaryGenerator.generateHeadline(stats);
            final text =
                '$headline\n\n${GameSummaryGenerator.generateNarrative(stats)}';
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Summary copied — ready to share'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Share'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // View Full Box Score link
        TextButton.icon(
          onPressed: () => context.push('/box-score/${stats.eventId}'),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('View Full Box Score'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
