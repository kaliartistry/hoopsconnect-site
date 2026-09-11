import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../models/standings_model.dart';
import '../../models/team_season_stats_model.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/standings_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';
import 'roster_management_panel.dart';

class TeamViewScreen extends ConsumerWidget {
  final String teamId;

  const TeamViewScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamDetailProvider(teamId));
    final team = teamAsync.valueOrNull;
    final rosterAsync = ref.watch(teamRosterProvider(teamId));
    final divisions =
        ref.watch(divisionsStreamProvider).valueOrNull ?? const [];
    final seasonId = ref.watch(activeSeasonIdProvider).value;
    final teamStatsAsync = seasonId == null
        ? null
        : ref.watch(
            teamSeasonStatsProvider((teamId: teamId, seasonId: seasonId)),
          );
    final standingsAsync = seasonId == null || team == null
        ? null
        : ref.watch(
            standingsStreamProvider((
              seasonId: seasonId,
              divisionId: team.divisionId,
            )),
          );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Team Details'),
      ),
      body: teamAsync.when(
        data: (team) {
          if (team == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Team not found',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          final roster = rosterAsync.valueOrNull ?? [];
          var divisionName = team.divisionId;
          for (final division in divisions) {
            if (division.id == team.divisionId) {
              divisionName = division.name;
              break;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Team header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(
                        Icons.sports_basketball,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      team.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.divisionTint(team.divisionId),
                        border: Border.all(
                          color: AppColors.divisionBorder(team.divisionId),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        divisionName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.divisionColor(team.divisionId),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick stats
              Row(
                children: [
                  Expanded(
                    child: _infoCard(
                      'Players',
                      '${roster.length}',
                      Icons.people,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _infoCard(
                      'Reps',
                      '${team.repIds.length}',
                      Icons.person,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Team season stats section
              if (teamStatsAsync != null)
                teamStatsAsync.when(
                  data: (stats) {
                    if (stats == null || stats.gamesPlayed == 0) {
                      return _buildEmptyTeamStatsSection();
                    }
                    final standing = standingsAsync?.valueOrNull?.standings
                        .where((s) => s.teamId == teamId)
                        .firstOrNull;
                    return _buildTeamStatsSection(context, stats, standing);
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => _buildEmptyTeamStatsSection(
                    title: 'Team stats unavailable',
                    subtitle:
                        'This team page is active, but its season stats could not be loaded right now.',
                  ),
                ),

              TeamRosterManagementPanel(
                team: team,
                seasonId: seasonId,
                legacyRoster: rosterAsync,
              ),
              const SizedBox(height: 24),
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

  Widget _buildTeamStatsSection(
    BuildContext context,
    TeamSeasonStats stats,
    TeamStanding? standing,
  ) {
    final avg = stats.averages;
    final tot = stats.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Record banner
        if (standing != null) ...[
          const Text(
            'RECORD',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.textMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Column(
              children: [
                // W-L and PCT
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${standing.wins}-${standing.losses}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '.${(standing.pct * 1000).round().toString().padLeft(3, '0')}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Detail row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _recordCell('STREAK', standing.streak),
                    _recordCell('LAST 10', standing.lastTen),
                    _recordCell(
                      'PF',
                      (standing.pointsFor / stats.gamesPlayed).toStringAsFixed(
                        1,
                      ),
                    ),
                    _recordCell(
                      'PA',
                      (standing.pointsAgainst / stats.gamesPlayed)
                          .toStringAsFixed(1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Season averages
        const Text(
          'SEASON AVERAGES',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            runSpacing: 12,
            children: [
              _avgStatCell('PPG', avg.ppg),
              _avgStatCell('RPG', avg.rpg),
              _avgStatCell('APG', avg.apg),
              _avgStatCell('SPG', avg.spg),
              _avgStatCell('BPG', avg.bpg),
              _avgStatCell('TOPG', avg.topg),
              _avgStatCell('FPG', avg.fpg),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Season totals
        const Text(
          'SEASON TOTALS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.darkBg),
              headingTextStyle: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('GP')),
                DataColumn(label: Text('PTS')),
                DataColumn(label: Text('REB')),
                DataColumn(label: Text('AST')),
                DataColumn(label: Text('STL')),
                DataColumn(label: Text('BLK')),
                DataColumn(label: Text('TO')),
                DataColumn(label: Text('FLS')),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(Text('${stats.gamesPlayed}')),
                    DataCell(
                      Text(
                        '${tot.pts}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    DataCell(Text('${tot.reb}')),
                    DataCell(Text('${tot.ast}')),
                    DataCell(Text('${tot.stl}')),
                    DataCell(Text('${tot.blk}')),
                    DataCell(Text('${tot.to}')),
                    DataCell(Text('${tot.fls}')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Compare button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/press/head-to-head?teamA=$teamId'),
            icon: const Icon(Icons.compare_arrows, size: 18),
            label: const Text('Compare with another team'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Game log
        const Text(
          'GAME LOG',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        _buildGameLogTable(context, stats.gameLog),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEmptyTeamStatsSection({
    String title = 'No approved team stats yet',
    String subtitle =
        'Approve box scores for this team to unlock season record, totals, averages, and game log.',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TEAM STATS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 34,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _recordCell(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _avgStatCell(String label, double value) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildGameLogTable(BuildContext context, List<TeamGameLog> gameLog) {
    if (gameLog.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: const Center(
          child: Text(
            'No games played yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    final dateFormat = DateFormat('MMM d');
    // Sort most recent first
    final sorted = List<TeamGameLog>.from(gameLog)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            color: AppColors.darkBg,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: const Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    'W/L',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    'PTS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    'REB',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    'AST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    'STL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    'BLK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final g = entry.value;
            final isEven = i.isEven;
            final isWin = g.result == 'W';
            return GestureDetector(
              onTap: () => context.push('/box-score/${g.eventId}'),
              child: Container(
                color: isEven ? Colors.white : AppColors.surface,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        g.result,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isWin ? AppColors.success : AppColors.urgent,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: g.opponentTeamId == null
                                ? null
                                : () =>
                                      context.push('/team/${g.opponentTeamId}'),
                            child: Text(
                              g.opponentName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: g.opponentTeamId == null
                                    ? AppColors.textPrimary
                                    : AppColors.infoDark,
                                decoration: g.opponentTeamId == null
                                    ? TextDecoration.none
                                    : TextDecoration.underline,
                                decorationColor: g.opponentTeamId == null
                                    ? Colors.transparent
                                    : AppColors.infoDark,
                              ),
                            ),
                          ),
                          Text(
                            dateFormat.format(g.date),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${g.pts}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    _gameLogCell('${g.reb}'),
                    _gameLogCell('${g.ast}'),
                    _gameLogCell('${g.stl}'),
                    _gameLogCell('${g.blk}'),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _gameLogCell(String value) {
    return SizedBox(
      width: 32,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
