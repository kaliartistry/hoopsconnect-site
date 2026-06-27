import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/live_stats_providers.dart';
import '../live_stats_state.dart';

/// Live box score table with quarter score summary, team toggle,
/// and "Game Totals" / "By Quarter" view toggle.
class LiveBoxScore extends ConsumerStatefulWidget {
  const LiveBoxScore({super.key});

  @override
  ConsumerState<LiveBoxScore> createState() => _LiveBoxScoreState();
}

class _LiveBoxScoreState extends ConsumerState<LiveBoxScore> {
  bool _showHome = true;
  bool _showByQuarter = false;
  int _selectedQuarter = 1;

  static const _columns = ['MIN', 'PTS', 'OREB', 'DREB', 'REB', 'AST', 'STL', 'BLK', 'TO', 'FLS'];
  static const _quarterColumns = ['PTS', 'OREB', 'DREB', 'REB', 'AST', 'STL', 'BLK', 'TO', 'FLS'];

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(liveGameProvider);
    final qScores = gameState.quarterScores;
    final playedQuarters = List<int>.from(qScores.keys)..sort();

    return Column(
      children: [
        // Quarter score summary row
        _QuarterScoreSummary(
          homeTeamName: gameState.homeTeamName,
          awayTeamName: gameState.awayTeamName,
          quarterScores: qScores,
          currentQuarter: gameState.quarter,
          homeTotal: gameState.homeScore,
          awayTotal: gameState.awayScore,
        ),

        // Team toggle tabs
        Row(
          children: [
            _TeamTab(
              name: gameState.homeTeamName,
              isActive: _showHome,
              isHome: true,
              onTap: () => setState(() => _showHome = true),
            ),
            _TeamTab(
              name: gameState.awayTeamName,
              isActive: !_showHome,
              isHome: false,
              onTap: () => setState(() => _showHome = false),
            ),
          ],
        ),

        // View toggle: Game Totals | By Quarter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

        // Quarter tabs (only shown when By Quarter is active)
        if (_showByQuarter && playedQuarters.isNotEmpty)
          SizedBox(
            height: 32,
            child: Row(
              children: [
                for (int q = 1; q <= gameState.quarter; q++)
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

        // Stats table
        Expanded(
          child: _showByQuarter
              ? _buildQuarterTable(gameState)
              : _buildGameTotalsTable(gameState),
        ),
      ],
    );
  }

  Widget _buildGameTotalsTable(LiveGameState gameState) {
    final teamId = _showHome ? gameState.homeTeamId : gameState.awayTeamId;

    final players = gameState.players.values
        .where((p) => p.teamId == teamId)
        .toList()
      ..sort((a, b) {
        if (a.onCourt != b.onCourt) return a.onCourt ? -1 : 1;
        return b.pts.compareTo(a.pts);
      });

    var tMin = 0, tPts = 0, tOreb = 0, tDreb = 0, tReb = 0;
    var tAst = 0, tStl = 0, tBlk = 0, tTo = 0, tFls = 0;
    for (final p in players) {
      final mins = p.currentMinutes(gameState.clockSeconds);
      tMin += mins;
      tPts += p.pts;
      tOreb += p.oreb;
      tDreb += p.dreb;
      tReb += p.reb;
      tAst += p.ast;
      tStl += p.stl;
      tBlk += p.blk;
      tTo += p.to;
      tFls += p.fls;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DataTable(
          columnSpacing: 12,
          horizontalMargin: 8,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 12,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          columns: [
            const DataColumn(label: Text('Player')),
            ..._columns.map(
              (c) => DataColumn(label: Text(c), numeric: true),
            ),
          ],
          rows: [
            ...players.map((p) {
              final mins = p.currentMinutes(gameState.clockSeconds);
              return DataRow(cells: [
                DataCell(SizedBox(
                  width: 100,
                  child: Text(
                    '${p.onCourt ? "\u2605 " : ""}${p.name}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: p.onCourt ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                )),
                DataCell(Text('$mins')),
                DataCell(Text('${p.pts}')),
                DataCell(Text('${p.oreb}')),
                DataCell(Text('${p.dreb}')),
                DataCell(Text('${p.reb}')),
                DataCell(Text('${p.ast}')),
                DataCell(Text('${p.stl}')),
                DataCell(Text('${p.blk}')),
                DataCell(Text('${p.to}')),
                DataCell(Text('${p.fls}')),
              ]);
            }),
            DataRow(
              color: WidgetStateProperty.all(AppColors.surface),
              cells: [
                const DataCell(Text('TOTALS', style: TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tMin', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tPts', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tOreb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tDreb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tReb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tAst', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tStl', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tBlk', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tTo', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tFls', style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuarterTable(LiveGameState gameState) {
    final teamId = _showHome ? gameState.homeTeamId : gameState.awayTeamId;
    final q = _selectedQuarter;

    final players = gameState.players.values
        .where((p) => p.teamId == teamId)
        .toList();

    // Get per-quarter stats for each player
    final playerQStats = <String, PlayerQuarterStats>{};
    for (final p in players) {
      final byQ = gameState.playerStatsByQuarter(p.id);
      playerQStats[p.id] = byQ[q] ?? const PlayerQuarterStats();
    }

    // Sort by quarter pts desc
    players.sort((a, b) {
      final aPts = playerQStats[a.id]?.pts ?? 0;
      final bPts = playerQStats[b.id]?.pts ?? 0;
      return bPts.compareTo(aPts);
    });

    // Quarter totals
    var tPts = 0, tOreb = 0, tDreb = 0, tReb = 0;
    var tAst = 0, tStl = 0, tBlk = 0, tTo = 0, tFls = 0;
    for (final p in players) {
      final qs = playerQStats[p.id]!;
      tPts += qs.pts;
      tOreb += qs.oreb;
      tDreb += qs.dreb;
      tReb += qs.reb;
      tAst += qs.ast;
      tStl += qs.stl;
      tBlk += qs.blk;
      tTo += qs.to;
      tFls += qs.fls;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DataTable(
          columnSpacing: 12,
          horizontalMargin: 8,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 12,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          columns: [
            const DataColumn(label: Text('Player')),
            ..._quarterColumns.map(
              (c) => DataColumn(label: Text(c), numeric: true),
            ),
          ],
          rows: [
            ...players.map((p) {
              final qs = playerQStats[p.id]!;
              return DataRow(cells: [
                DataCell(SizedBox(
                  width: 100,
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text('${qs.pts}')),
                DataCell(Text('${qs.oreb}')),
                DataCell(Text('${qs.dreb}')),
                DataCell(Text('${qs.reb}')),
                DataCell(Text('${qs.ast}')),
                DataCell(Text('${qs.stl}')),
                DataCell(Text('${qs.blk}')),
                DataCell(Text('${qs.to}')),
                DataCell(Text('${qs.fls}')),
              ]);
            }),
            DataRow(
              color: WidgetStateProperty.all(AppColors.surface),
              cells: [
                const DataCell(Text('TOTALS', style: TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tPts', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tOreb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tDreb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tReb', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tAst', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tStl', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tBlk', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tTo', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('$tFls', style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quarter score summary row
// ---------------------------------------------------------------------------

class _QuarterScoreSummary extends StatelessWidget {
  final String homeTeamName;
  final String awayTeamName;
  final Map<int, ({int home, int away})> quarterScores;
  final int currentQuarter;
  final int homeTotal;
  final int awayTotal;

  const _QuarterScoreSummary({
    required this.homeTeamName,
    required this.awayTeamName,
    required this.quarterScores,
    required this.currentQuarter,
    required this.homeTotal,
    required this.awayTotal,
  });

  @override
  Widget build(BuildContext context) {
    // Show quarters that have been played (or are in progress)
    final quarters = <int>[];
    for (int q = 1; q <= currentQuarter; q++) {
      quarters.add(q);
    }

    if (quarters.isEmpty) return const SizedBox.shrink();

    return Container(
      color: AppColors.darkBg,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 11,
          fontFeatures: [FontFeature.tabularFigures()],
          color: Colors.white70,
        ),
        child: Table(
          columnWidths: {
            0: const FlexColumnWidth(2),
            for (int i = 0; i < quarters.length; i++)
              i + 1: const FlexColumnWidth(1),
            quarters.length + 1: const FlexColumnWidth(1.2),
          },
          children: [
            // Header row
            TableRow(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text('', style: TextStyle(fontSize: 10)),
                ),
                ...quarters.map((q) => Padding(
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
                    )),
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
            // Home team row
            _teamScoreRow(homeTeamName, quarters, true),
            // Away team row
            _teamScoreRow(awayTeamName, quarters, false),
          ],
        ),
      ),
    );
  }

  TableRow _teamScoreRow(String teamName, List<int> quarters, bool isHome) {
    final total = isHome ? homeTotal : awayTotal;
    final isWinning = isHome ? homeTotal >= awayTotal : awayTotal >= homeTotal;

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
        ...quarters.map((q) {
          final qData = quarterScores[q];
          final score = isHome ? (qData?.home ?? 0) : (qData?.away ?? 0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '$score',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          );
        }),
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
}

// ---------------------------------------------------------------------------
// View toggle chip
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
// Team tab
// ---------------------------------------------------------------------------

class _TeamTab extends StatelessWidget {
  final String name;
  final bool isActive;
  final bool isHome;
  final VoidCallback onTap;

  const _TeamTab({
    required this.name,
    required this.isActive,
    required this.isHome,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        isHome ? const Color(0xFFEA580C) : const Color(0xFF1D4ED8);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? activeColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? activeColor : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
