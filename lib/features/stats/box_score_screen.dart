import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../models/association_branding_model.dart';
import '../../models/game_stats_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';
import '../../providers/stats_providers.dart';
import '../../services/milestone_detector.dart';
import '../../services/stat_export_service.dart';

class BoxScoreScreen extends ConsumerStatefulWidget {
  final String eventId;

  const BoxScoreScreen({super.key, required this.eventId});

  @override
  ConsumerState<BoxScoreScreen> createState() => _BoxScoreScreenState();
}

class _BoxScoreScreenState extends ConsumerState<BoxScoreScreen> {
  static const _statColumns = [
    'MIN',
    'PTS',
    'OREB',
    'DREB',
    'REB',
    'AST',
    'STL',
    'BLK',
    'FLS',
  ];
  static const _quarterStatColumns = [
    'PTS',
    'OREB',
    'DREB',
    'REB',
    'AST',
    'STL',
    'BLK',
    'FLS',
  ];

  bool _showByQuarter = false;
  int _selectedQuarter = 1;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(gameStatsProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Box Score'),
        actions: [_ShareBoxScoreButton(eventId: widget.eventId)],
      ),
      body: statsAsync.when(
        data: (stats) {
          if (stats == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.scoreboard_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Box score not available',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          final homePlayers = stats.playerLines.entries
              .where((e) => e.value.teamId == stats.homeTeamId)
              .toList();
          final awayPlayers = stats.playerLines.entries
              .where((e) => e.value.teamId == stats.awayTeamId)
              .toList();

          final hasQuarterData =
              stats.homeQuarterScores.isNotEmpty ||
              stats.awayQuarterScores.isNotEmpty;
          final hasPlayerQuarterData =
              stats.playerQuarterStats != null &&
              stats.playerQuarterStats!.isNotEmpty;

          // Determine which quarters exist
          final playedQuarters = <int>{
            ...stats.homeQuarterScores.keys,
            ...stats.awayQuarterScores.keys,
          }.toList()..sort();

          return Column(
            children: [
              // Dark score header
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 24,
                ),
                color: AppColors.darkBg,
                child: Column(
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                            GestureDetector(
                              onTap: () =>
                                  context.push('/team/${stats.homeTeamId}'),
                              child: Text(
                                stats.homeTeamName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white70,
                                ),
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
                            GestureDetector(
                              onTap: () =>
                                  context.push('/team/${stats.awayTeamId}'),
                              child: Text(
                                stats.awayTeamName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white70,
                                ),
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

                    // Quarter score summary row
                    if (hasQuarterData) ...[
                      const SizedBox(height: 12),
                      _buildQuarterScoreSummary(stats, playedQuarters),
                    ],
                  ],
                ),
              ),

              // View toggle (only if quarter player data exists)
              if (hasPlayerQuarterData)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _ViewToggleChip(
                        label: 'Game Totals',
                        isActive: !_showByQuarter,
                        onTap: () => setState(() => _showByQuarter = false),
                      ),
                      const SizedBox(width: 8),
                      _ViewToggleChip(
                        label: 'By Quarter',
                        isActive: _showByQuarter,
                        onTap: () => setState(() => _showByQuarter = true),
                      ),
                    ],
                  ),
                ),

              // Quarter tabs (only when By Quarter is selected)
              if (hasPlayerQuarterData &&
                  _showByQuarter &&
                  playedQuarters.isNotEmpty)
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      for (final q in playedQuarters)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedQuarter = q),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _selectedQuarter == q
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                'Q$q',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedQuarter == q
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // Stats tables
              Expanded(
                child: _showByQuarter && hasPlayerQuarterData
                    ? ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildTeamComparison(stats, homePlayers, awayPlayers),
                          const SizedBox(height: 16),
                          _buildQuarterTeamTable(
                            stats.homeTeamId,
                            stats.homeTeamName,
                            homePlayers,
                            stats,
                            _selectedQuarter,
                          ),
                          const SizedBox(height: 16),
                          _buildQuarterTeamTable(
                            stats.awayTeamId,
                            stats.awayTeamName,
                            awayPlayers,
                            stats,
                            _selectedQuarter,
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildTeamComparison(stats, homePlayers, awayPlayers),
                          const SizedBox(height: 16),
                          _buildTeamTable(
                            stats.homeTeamId,
                            stats.homeTeamName,
                            homePlayers,
                          ),
                          const SizedBox(height: 16),
                          _buildTeamTable(
                            stats.awayTeamId,
                            stats.awayTeamName,
                            awayPlayers,
                          ),
                        ],
                      ),
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

  // ---------------------------------------------------------------------------
  // Quarter score summary (inside dark header)
  // ---------------------------------------------------------------------------

  Widget _buildQuarterScoreSummary(
    GameStatsModel stats,
    List<int> playedQuarters,
  ) {
    return DefaultTextStyle(
      style: const TextStyle(
        fontSize: 11,
        fontFeatures: [FontFeature.tabularFigures()],
        color: Colors.white70,
      ),
      child: Table(
        columnWidths: {
          0: const FlexColumnWidth(2),
          for (int i = 0; i < playedQuarters.length; i++)
            i + 1: const FlexColumnWidth(1),
          playedQuarters.length + 1: const FlexColumnWidth(1.2),
        },
        children: [
          // Header
          TableRow(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(''),
              ),
              ...playedQuarters.map(
                (q) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Q$q',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'TOT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          // Home
          _quarterScoreTableRow(
            stats.homeTeamName,
            playedQuarters,
            stats.homeQuarterScores,
            stats.homeScore,
            stats.homeScore >= stats.awayScore,
          ),
          // Away
          _quarterScoreTableRow(
            stats.awayTeamName,
            playedQuarters,
            stats.awayQuarterScores,
            stats.awayScore,
            stats.awayScore >= stats.homeScore,
          ),
        ],
      ),
    );
  }

  TableRow _quarterScoreTableRow(
    String teamName,
    List<int> quarters,
    Map<int, int> qScores,
    int total,
    bool isWinning,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            teamName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isWinning ? Colors.white : Colors.white54,
            ),
          ),
        ),
        ...quarters.map(
          (q) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${qScores[q] ?? 0}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            '$total',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isWinning ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Team comparison
  // ---------------------------------------------------------------------------

  Widget _buildTeamComparison(
    GameStatsModel stats,
    List<MapEntry<String, PlayerStatLine>> homePlayers,
    List<MapEntry<String, PlayerStatLine>> awayPlayers,
  ) {
    int hPts = 0, hReb = 0, hAst = 0, hStl = 0, hBlk = 0, hFls = 0;
    for (final p in homePlayers) {
      hPts += p.value.pts;
      hReb += p.value.reb;
      hAst += p.value.ast;
      hStl += p.value.stl;
      hBlk += p.value.blk;
      hFls += p.value.fls;
    }
    int aPts = 0, aReb = 0, aAst = 0, aStl = 0, aBlk = 0, aFls = 0;
    for (final p in awayPlayers) {
      aPts += p.value.pts;
      aReb += p.value.reb;
      aAst += p.value.ast;
      aStl += p.value.stl;
      aBlk += p.value.blk;
      aFls += p.value.fls;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Text(
              'TEAM STATS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _comparisonRow('Points', hPts, aPts),
          _comparisonRow('Rebounds', hReb, aReb),
          _comparisonRow('Assists', hAst, aAst),
          _comparisonRow('Steals', hStl, aStl),
          _comparisonRow('Blocks', hBlk, aBlk),
          _comparisonRow('Fouls', hFls, aFls),
        ],
      ),
    );
  }

  Widget _comparisonRow(String label, int homeVal, int awayVal) {
    final total = homeVal + awayVal;
    final homePct = total > 0 ? homeVal / total : 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '$homeVal',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: homeVal >= awayVal
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$awayVal',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: awayVal >= homeVal
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Row(
                children: [
                  Expanded(
                    flex: (homePct * 100).round().clamp(1, 99),
                    child: Container(color: AppColors.primary),
                  ),
                  Expanded(
                    flex: ((1 - homePct) * 100).round().clamp(1, 99),
                    child: Container(
                      color: AppColors.textMuted.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Team table (game totals)
  // ---------------------------------------------------------------------------

  Widget _buildTeamTable(
    String teamId,
    String teamName,
    List<MapEntry<String, PlayerStatLine>> players,
  ) {
    int totalMin = 0, totalPts = 0, totalOreb = 0, totalDreb = 0;
    int totalReb = 0, totalAst = 0;
    int totalStl = 0, totalBlk = 0, totalFls = 0;
    for (final p in players) {
      totalMin += p.value.min;
      totalPts += p.value.pts;
      totalOreb += p.value.oreb;
      totalDreb += p.value.dreb;
      totalReb += p.value.reb;
      totalAst += p.value.ast;
      totalStl += p.value.stl;
      totalBlk += p.value.blk;
      totalFls += p.value.fls;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/team/$teamId'),
                child: Text(
                  teamName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  'Player',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ..._statColumns.map(
                (col) => SizedBox(
                  width: 36,
                  child: Text(
                    col,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...players.map((entry) {
          final milestones = MilestoneDetector.detectGameMilestones(
            entry.value,
          );
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: GestureDetector(
                        onTap: () => context.push('/stats/player/${entry.key}'),
                        child: Text(
                          entry.value.name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.infoDark,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.infoDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    _statCell(entry.value.min),
                    _statCell(entry.value.pts, highlight: true),
                    _statCell(entry.value.oreb),
                    _statCell(entry.value.dreb),
                    _statCell(entry.value.reb),
                    _statCell(entry.value.ast),
                    _statCell(entry.value.stl),
                    _statCell(entry.value.blk),
                    _statCell(entry.value.fls),
                  ],
                ),
                if (milestones.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 2,
                      children: milestones
                          .map((m) => MilestoneDetector.milestoneBadge(m))
                          .toList(),
                    ),
                  ),
              ],
            ),
          );
        }),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _statCell(totalMin, bold: true),
              _statCell(totalPts, bold: true, highlight: true),
              _statCell(totalOreb, bold: true),
              _statCell(totalDreb, bold: true),
              _statCell(totalReb, bold: true),
              _statCell(totalAst, bold: true),
              _statCell(totalStl, bold: true),
              _statCell(totalBlk, bold: true),
              _statCell(totalFls, bold: true),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Team table (per-quarter view)
  // ---------------------------------------------------------------------------

  Widget _buildQuarterTeamTable(
    String teamId,
    String teamName,
    List<MapEntry<String, PlayerStatLine>> players,
    GameStatsModel stats,
    int quarter,
  ) {
    final pqStats = stats.playerQuarterStats ?? {};

    int tPts = 0, tOreb = 0, tDreb = 0, tReb = 0;
    int tAst = 0, tStl = 0, tBlk = 0, tFls = 0;

    // Build a list of (player entry, quarter stat map)
    final rows = <(MapEntry<String, PlayerStatLine>, Map<String, int>)>[];
    for (final entry in players) {
      final playerQMap = pqStats[entry.key];
      final qStats = playerQMap?[quarter] ?? const {};
      rows.add((entry, qStats));

      tPts += qStats['pts'] ?? 0;
      tOreb += qStats['oreb'] ?? 0;
      tDreb += qStats['dreb'] ?? 0;
      tReb += qStats['reb'] ?? 0;
      tAst += qStats['ast'] ?? 0;
      tStl += qStats['stl'] ?? 0;
      tBlk += qStats['blk'] ?? 0;
      tFls += qStats['fls'] ?? 0;
    }

    // Sort by quarter points desc
    rows.sort((a, b) => (b.$2['pts'] ?? 0).compareTo(a.$2['pts'] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/team/$teamId'),
                child: Text(
                  '$teamName  -  Q$quarter',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  'Player',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ..._quarterStatColumns.map(
                (col) => SizedBox(
                  width: 36,
                  child: Text(
                    col,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...rows.map((row) {
          final entry = row.$1;
          final qs = row.$2;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: GestureDetector(
                    onTap: () => context.push('/stats/player/${entry.key}'),
                    child: Text(
                      entry.value.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.infoDark,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.infoDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _statCell(qs['pts'] ?? 0, highlight: true),
                _statCell(qs['oreb'] ?? 0),
                _statCell(qs['dreb'] ?? 0),
                _statCell(qs['reb'] ?? 0),
                _statCell(qs['ast'] ?? 0),
                _statCell(qs['stl'] ?? 0),
                _statCell(qs['blk'] ?? 0),
                _statCell(qs['fls'] ?? 0),
              ],
            ),
          );
        }),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: AppColors.surface,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _statCell(tPts, bold: true, highlight: true),
              _statCell(tOreb, bold: true),
              _statCell(tDreb, bold: true),
              _statCell(tReb, bold: true),
              _statCell(tAst, bold: true),
              _statCell(tStl, bold: true),
              _statCell(tBlk, bold: true),
              _statCell(tFls, bold: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCell(int value, {bool bold = false, bool highlight = false}) {
    return SizedBox(
      width: 36,
      child: Text(
        '$value',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: highlight ? AppColors.statHighlight : AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// View toggle chip (shared style)
// ---------------------------------------------------------------------------

class _ViewToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewToggleChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export button
// ---------------------------------------------------------------------------

class _ShareBoxScoreButton extends ConsumerWidget {
  final String eventId;
  const _ShareBoxScoreButton({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(gameStatsProvider(eventId));
    return statsAsync.when(
      data: (stats) {
        if (stats == null) return const SizedBox.shrink();
        if (stats.status != GameStatsStatus.approved) {
          final user = ref.watch(currentUserProvider).value;
          if (user == null || !user.canExportStats) {
            return const SizedBox.shrink();
          }
          return IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy draft box score',
            onPressed: () async {
              final text = StatExportService.formatBoxScore(stats);
              await StatExportService.copyToClipboard(text, context);
            },
          );
        }
        final publicSnapshot = ref
            .watch(publicLeagueSnapshotProvider)
            .valueOrNull;
        final publishedGame = publicSnapshot?.gameDetail(eventId)?.game;
        if (publicSnapshot == null ||
            publishedGame == null ||
            !publicSnapshot.canCreatePublishedArtifacts ||
            !publishedGame.hasVersionedResult) {
          return const IconButton(
            icon: Icon(Icons.share_outlined),
            tooltip: 'Published result is not available to share',
            onPressed: null,
          );
        }
        final branding =
            AssociationBrandingModel.jba(
              associationId: publicSnapshot.associationId,
            ).copyWith(
              leagueName: publicSnapshot.leagueName,
              shortName: publicSnapshot.leagueShortName,
            );
        return IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Share final result',
          onPressed: () => showBrandedShareSheet(
            context: context,
            branding: branding,
            payload: BrandedSharePayload.publicGame(
              snapshot: publicSnapshot,
              game: publishedGame,
              branding: branding,
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
