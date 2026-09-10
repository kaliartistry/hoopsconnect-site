import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../models/leaderboard_model.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_display.dart';
import '../../core/widgets/empty_state.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _categories = ['ppg', 'rpg', 'apg', 'spg', 'bpg'];
  static const _categoryLabels = ['PTS', 'REB', 'AST', 'STL', 'BLK'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = ref.watch(activeSeasonIdProvider).value;
    final selectedDivision = ref.watch(selectedDivisionProvider);
    final selectedDivisionId = ref.watch(selectedDivisionIdProvider);
    final category = _categories[_tabController.index];
    final leaderboardAsync = seasonId == null
        ? null
        : ref.watch(
            leaderboardProvider((
              seasonId: seasonId,
              divisionId: selectedDivisionId,
              category: category,
            )),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Season Leaderboard'),
        actions: [_buildShareAction(context, category, leaderboardAsync)],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: _categoryLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: leaderboardAsync == null
          ? const SkeletonListTileList()
          : leaderboardAsync.when(
              data: (leaderboard) {
                if (leaderboard == null || leaderboard.rankings.isEmpty) {
                  return EmptyState(
                    icon: Icons.leaderboard_outlined,
                    title: 'No leaderboard data',
                    subtitle: selectedDivision == null
                        ? 'Stats will appear after games are played'
                        : 'Stats for ${selectedDivision.name} will appear after games are played',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: leaderboard.rankings.length,
                  itemBuilder: (context, index) {
                    final entry = leaderboard.rankings[index];
                    return _buildRankingItem(context, entry, index + 1);
                  },
                );
              },
              loading: () => const SkeletonListTileList(),
              error: (e, _) => ErrorDisplay(
                error: e,
                onRetry: () {
                  if (seasonId != null) {
                    ref.invalidate(
                      leaderboardProvider((
                        seasonId: seasonId,
                        divisionId: selectedDivisionId,
                        category: category,
                      )),
                    );
                  }
                },
              ),
            ),
    );
  }

  Widget _buildShareAction(
    BuildContext context,
    String category,
    AsyncValue<LeaderboardModel?>? leaderboardAsync,
  ) {
    return IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: 'Share leaderboard',
      onPressed: () {
        final leaderboard = leaderboardAsync?.valueOrNull;
        if (leaderboard == null || leaderboard.rankings.isEmpty) return;
        final branding = ref.read(effectiveAssociationBrandingProvider);
        showBrandedShareSheet(
          context: context,
          branding: branding,
          payload: BrandedSharePayload.leaderboard(
            rankings: leaderboard.rankings,
            category: category,
            branding: branding,
          ),
        );
      },
    );
  }

  Widget _buildRankingItem(
    BuildContext context,
    LeaderboardEntry entry,
    int rank,
  ) {
    return GestureDetector(
      onTap: () => context.push('/stats/player/${entry.playerId}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 32,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _rankColor(rank),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Player name + team
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.teamName} \u00b7 ${entry.gp} GP',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Stat value
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.value.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.statHighlight,
                  ),
                ),
                const Text(
                  'per game',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.medalGold;
      case 2:
        return AppColors.medalSilver;
      case 3:
        return AppColors.medalBronze;
      default:
        return AppColors.textMuted;
    }
  }
}
