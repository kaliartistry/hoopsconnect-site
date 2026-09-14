import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/time/league_time.dart';
import '../../models/association_branding_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../providers/public_league_provider.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../services/public_artifact_release_validator.dart';

class PlayerCardScreen extends ConsumerWidget {
  final String playerId;

  const PlayerCardScreen({super.key, required this.playerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonId = ref.watch(activeSeasonIdProvider).value;
    final statsAsync = seasonId == null
        ? null
        : ref.watch(
            playerSeasonStatsProvider((playerId: playerId, seasonId: seasonId)),
          );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Player Stats'),
        actions: [_PlayerStatsShareButton(stats: statsAsync?.valueOrNull)],
      ),
      body: statsAsync == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : statsAsync.when(
              data: (stats) {
                if (stats == null) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 48,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Player not found',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Player header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      ),
                      child: Column(
                        children: [
                          Text(
                            stats.playerName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => context.push('/team/${stats.teamId}'),
                            child: Text(
                              '${stats.teamName ?? 'Unknown Team'} · ${seasonId ?? ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.infoDark,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.infoDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats grid (3x2)
                    GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: 1.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _statCell('GP', stats.gamesPlayed.toString()),
                        _statCell('PPG', stats.ppg.toStringAsFixed(1)),
                        _statCell('RPG', stats.rpg.toStringAsFixed(1)),
                        _statCell('APG', stats.apg.toStringAsFixed(1)),
                        _statCell('SPG', stats.spg.toStringAsFixed(1)),
                        _statCell('BPG', stats.bpg.toStringAsFixed(1)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Game Log section
                    const Text(
                      'Game Log',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (stats.gameLog.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.sports_basketball_outlined,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No games played yet',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Game stats will appear here',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...stats.gameLog.map(
                        (game) => _gameLogRow(context, game),
                      ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
    );
  }

  Widget _statCell(String label, String value) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.statHighlight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameLogRow(BuildContext context, GameLogEntry game) {
    final dateStr = LeagueTime.formatJamaicaDate(game.date, pattern: 'MMM d');

    return GestureDetector(
      onTap: () => context.push('/box-score/${game.eventId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + W/L badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                _resultBadge(game.result),
              ],
            ),
            const SizedBox(height: 4),

            // vs opponent
            Text(
              'vs ${game.vs}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),

            // Stat summary
            Text(
              '${game.pts} PTS · ${game.reb} REB · ${game.ast} AST',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultBadge(String result) {
    final isWin = result == 'W';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isWin ? AppColors.success : AppColors.urgent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        result,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PlayerStatsShareButton extends ConsumerWidget {
  final PlayerSeasonStatsModel? stats;

  const _PlayerStatsShareButton({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerStats = stats;
    if (playerStats == null || playerStats.gamesPlayed == 0) {
      return const SizedBox.shrink();
    }
    final snapshot = ref.watch(publicLeagueSnapshotProvider).valueOrNull;
    final publicPlayer = snapshot?.playerDetail(playerStats.playerId);
    final canShare =
        snapshot != null &&
        snapshot.canCreatePublishedArtifacts &&
        snapshot.version.privacyEpoch != null &&
        publicPlayer != null;
    return IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: canShare
          ? 'Share published player stats'
          : 'Published player stats are not available to share',
      onPressed: !canShare
          ? null
          : () {
              final branding =
                  AssociationBrandingModel.jba(
                    associationId: snapshot.associationId,
                  ).copyWith(
                    leagueName: snapshot.leagueName,
                    shortName: snapshot.leagueShortName,
                  );
              final releaseBinding = PublicArtifactBinding.snapshot(snapshot);
              showBrandedShareSheet(
                context: context,
                branding: branding,
                payload: BrandedSharePayload.publicPlayer(
                  snapshot: snapshot,
                  player: publicPlayer,
                  branding: branding,
                ),
                validateCurrent: () async {
                  await ref
                      .read(publicArtifactReleaseValidatorProvider)
                      .requireCurrent(releaseBinding);
                },
              );
            },
    );
  }
}
