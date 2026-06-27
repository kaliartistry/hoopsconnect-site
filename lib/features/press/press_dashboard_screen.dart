import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../models/game_stats_model.dart';
import '../../models/event_model.dart';
import '../../models/leaderboard_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/press_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';

class PressDashboardScreen extends ConsumerWidget {
  const PressDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: const [
          _PressCredentialCard(),
          SizedBox(height: 20),
          _RecentResultsSection(),
          SizedBox(height: 20),
          _TodaysGamesSection(),
          SizedBox(height: 20),
          _SeasonLeadersSection(),
          SizedBox(height: 20),
          _CompareButton(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A. Digital Press Credential Card
// ---------------------------------------------------------------------------

class _PressCredentialCard extends ConsumerWidget {
  const _PressCredentialCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final seasonName = ref.watch(activeSeasonNameProvider).value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // slate-800
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: badge + accredited label
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Icon(
                  Icons.sports_basketball,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACCREDITED MEDIA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Jamaica Basketball Association',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Name
          Text(
            user?.displayName ?? 'Press Member',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
          if (seasonName != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  seasonName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// B. Recent Results Section
// ---------------------------------------------------------------------------

class _RecentResultsSection extends ConsumerWidget {
  const _RecentResultsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(recentResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Results',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        resultsAsync.when(
          data: (results) {
            if (results.isEmpty) {
              return const _MiniEmpty(
                icon: Icons.scoreboard_outlined,
                text: 'No recent results',
              );
            }
            return Column(
              children:
                  results.map((g) => _RecentResultCard(stats: g)).toList(),
            );
          },
          loading: () => const SkeletonListTileList(count: 3),
          error: (e, _) => Text('Error loading results: $e',
              style: const TextStyle(color: AppColors.urgent)),
        ),
      ],
    );
  }
}

class _RecentResultCard extends StatelessWidget {
  final GameStatsModel stats;
  const _RecentResultCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final dateStr = stats.approvedAt != null
        ? DateFormat('MMM d, yyyy').format(stats.approvedAt!)
        : '';

    return GestureDetector(
      onTap: () => context.push('/box-score/${stats.eventId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            // Teams & score
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stats.homeTeamName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: stats.homeScore >= stats.awayScore
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${stats.homeScore}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: stats.homeScore >= stats.awayScore
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stats.awayTeamName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: stats.awayScore >= stats.homeScore
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${stats.awayScore}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: stats.awayScore >= stats.homeScore
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Date + arrow
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'FINAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// C. Today's Schedule Section
// ---------------------------------------------------------------------------

class _TodaysGamesSection extends ConsumerWidget {
  const _TodaysGamesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamesAsync = ref.watch(todaysGamesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Games",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        gamesAsync.when(
          data: (games) {
            if (games.isEmpty) {
              return const _MiniEmpty(
                icon: Icons.event_busy_outlined,
                text: 'No games scheduled today',
              );
            }
            return Column(
              children:
                  games.map((e) => _TodayGameCard(event: e)).toList(),
            );
          },
          loading: () => const SkeletonListTileList(count: 2),
          error: (e, _) => Text('Error: $e',
              style: const TextStyle(color: AppColors.urgent)),
        ),
      ],
    );
  }
}

class _TodayGameCard extends StatelessWidget {
  final EventModel event;
  const _TodayGameCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(event.startTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: const Icon(
              Icons.sports_basketball,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (event.location != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          event.location!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// D. Quick Stats / Season Leaders Section
// ---------------------------------------------------------------------------

class _SeasonLeadersSection extends ConsumerWidget {
  const _SeasonLeadersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonId = ref.watch(activeSeasonIdProvider).value;

    if (seasonId == null) {
      return const _MiniEmpty(
        icon: Icons.leaderboard_outlined,
        text: 'No active season',
      );
    }

    // Watch ppg, rpg, apg leaderboards
    final ppgAsync = ref.watch(leaderboardProvider(
        (seasonId: seasonId, divisionId: null, category: 'ppg')));
    final rpgAsync = ref.watch(leaderboardProvider(
        (seasonId: seasonId, divisionId: null, category: 'rpg')));
    final apgAsync = ref.watch(leaderboardProvider(
        (seasonId: seasonId, divisionId: null, category: 'apg')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Season Leaders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _LeaderRow(
          label: 'TOP SCORER',
          icon: Icons.whatshot,
          iconColor: AppColors.urgent,
          leaderboardAsync: ppgAsync,
          unit: 'ppg',
        ),
        const SizedBox(height: 8),
        _LeaderRow(
          label: 'TOP REBOUNDER',
          icon: Icons.sports_handball,
          iconColor: AppColors.info,
          leaderboardAsync: rpgAsync,
          unit: 'rpg',
        ),
        const SizedBox(height: 8),
        _LeaderRow(
          label: 'TOP ASSISTS',
          icon: Icons.handshake_outlined,
          iconColor: AppColors.success,
          leaderboardAsync: apgAsync,
          unit: 'apg',
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final AsyncValue<LeaderboardModel?> leaderboardAsync;
  final String unit;

  const _LeaderRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.leaderboardAsync,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return leaderboardAsync.when(
      data: (lb) {
        if (lb == null || lb.rankings.isEmpty) {
          return _miniLeaderPlaceholder(label);
        }
        final leader = lb.rankings.first;
        return GestureDetector(
          onTap: () => context.push('/stats/player/${leader.playerId}'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        leader.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        leader.teamName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      leader.value.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.statHighlight,
                      ),
                    ),
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      },
      loading: () => _miniLeaderPlaceholder(label),
      error: (_, _) => _miniLeaderPlaceholder(label),
    );
  }

  Widget _miniLeaderPlaceholder(String lbl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor.withValues(alpha: 0.4), size: 22),
          const SizedBox(width: 10),
          Text(
            lbl,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          const Spacer(),
          const Text(
            '--',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// E. Head-to-Head Compare Button
// ---------------------------------------------------------------------------

class _CompareButton extends StatelessWidget {
  const _CompareButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => context.push('/press/head-to-head'),
        icon: const Icon(Icons.compare_arrows, size: 22),
        label: const Text(
          'Head-to-Head Compare',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small empty state widget
// ---------------------------------------------------------------------------

class _MiniEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
