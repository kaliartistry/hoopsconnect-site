import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/team_model.dart';
import '../../models/team_season_stats_model.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';

enum _CompareMode { teams, players }

enum _TeamViewMode { seasonAverages, headToHead }

class HeadToHeadScreen extends ConsumerStatefulWidget {
  final String? initialTeamAId;

  const HeadToHeadScreen({super.key, this.initialTeamAId});

  @override
  ConsumerState<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends ConsumerState<HeadToHeadScreen> {
  _CompareMode _mode = _CompareMode.teams;
  _TeamViewMode _teamViewMode = _TeamViewMode.seasonAverages;

  // Team mode
  String? _teamAId;
  String? _teamBId;

  // Player mode
  String? _playerAId;
  String? _playerBId;

  @override
  void initState() {
    super.initState();
    _teamAId = widget.initialTeamAId;
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsStreamProvider);
    final seasonId = ref.watch(activeSeasonIdProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Head to Head')),
      body: Column(
        children: [
          // Toggle: Teams | Players
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SegmentedButton<_CompareMode>(
              segments: const [
                ButtonSegment(
                  value: _CompareMode.teams,
                  label: Text('Teams'),
                  icon: Icon(Icons.groups_outlined),
                ),
                ButtonSegment(
                  value: _CompareMode.players,
                  label: Text('Players'),
                  icon: Icon(Icons.person_outline),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (sel) => setState(() => _mode = sel.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary;
                  }
                  return AppColors.surface;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return AppColors.textPrimary;
                }),
              ),
            ),
          ),

          Expanded(
            child: teamsAsync.when(
              data: (teams) {
                if (_mode == _CompareMode.teams) {
                  return _buildTeamComparison(teams, seasonId);
                } else {
                  return _buildPlayerComparison(teams, seasonId);
                }
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TEAM COMPARISON ───────────────────────────────────────────────

  Widget _buildTeamComparison(List<TeamModel> teams, String? seasonId) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Selectors
        Row(
          children: [
            Expanded(child: _teamDropdown(teams, _teamAId, (v) => setState(() => _teamAId = v), 'Team A')),
            const SizedBox(width: 12),
            const Text('vs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(child: _teamDropdown(teams, _teamBId, (v) => setState(() => _teamBId = v), 'Team B')),
          ],
        ),
        const SizedBox(height: 12),

        // Season Averages / Head-to-Head toggle
        if (_teamAId != null && _teamBId != null) ...[
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_TeamViewMode>(
              segments: const [
                ButtonSegment(
                  value: _TeamViewMode.seasonAverages,
                  label: Text('Season Averages'),
                ),
                ButtonSegment(
                  value: _TeamViewMode.headToHead,
                  label: Text('Head-to-Head'),
                ),
              ],
              selected: {_teamViewMode},
              onSelectionChanged: (sel) =>
                  setState(() => _teamViewMode = sel.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary;
                  }
                  return AppColors.surface;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return AppColors.textPrimary;
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_teamAId != null && _teamBId != null && seasonId != null)
          _TeamComparisonBody(
            teamAId: _teamAId!,
            teamBId: _teamBId!,
            seasonId: seasonId,
            viewMode: _teamViewMode,
          )
        else
          const _SelectBothHint(label: 'Select two teams to compare'),
      ],
    );
  }

  Widget _teamDropdown(List<TeamModel> teams, String? value, ValueChanged<String?> onChanged, String hint) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      hint: Text(hint, style: const TextStyle(fontSize: 13)),
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
      ),
      items: teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name, style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: onChanged,
    );
  }

  // ─── PLAYER COMPARISON ─────────────────────────────────────────────

  Widget _buildPlayerComparison(List<TeamModel> teams, String? seasonId) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Player A selector
        _PlayerSelector(
          teams: teams,
          seasonId: seasonId,
          selectedPlayerId: _playerAId,
          label: 'Player A',
          onSelected: (id) => setState(() => _playerAId = id),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('vs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textSecondary))),
        const SizedBox(height: 8),
        // Player B selector
        _PlayerSelector(
          teams: teams,
          seasonId: seasonId,
          selectedPlayerId: _playerBId,
          label: 'Player B',
          onSelected: (id) => setState(() => _playerBId = id),
        ),
        const SizedBox(height: 20),

        if (_playerAId != null && _playerBId != null && seasonId != null)
          _PlayerComparisonBody(
            playerAId: _playerAId!,
            playerBId: _playerBId!,
            seasonId: seasonId,
          )
        else
          const _SelectBothHint(label: 'Select two players to compare'),
      ],
    );
  }
}

// ─── TEAM COMPARISON BODY (watches providers) ──────────────────────────

class _TeamComparisonBody extends ConsumerWidget {
  final String teamAId;
  final String teamBId;
  final String seasonId;
  final _TeamViewMode viewMode;

  const _TeamComparisonBody({
    required this.teamAId,
    required this.teamBId,
    required this.seasonId,
    this.viewMode = _TeamViewMode.seasonAverages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aAsync = ref.watch(teamSeasonStatsProvider((teamId: teamAId, seasonId: seasonId)));
    final bAsync = ref.watch(teamSeasonStatsProvider((teamId: teamBId, seasonId: seasonId)));

    return aAsync.when(
      data: (a) => bAsync.when(
        data: (b) {
          if (a == null || b == null) {
            return const Center(child: Text('Stats not available for one or both teams.'));
          }
          return _buildContent(context, a, b);
        },
        loading: () => const _LoadingIndicator(),
        error: (e, _) => Text('Error: $e'),
      ),
      loading: () => const _LoadingIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }

  Widget _buildContent(BuildContext context, TeamSeasonStats a, TeamSeasonStats b) {
    // Win / Loss records
    final aWins = a.gameLog.where((g) => g.result == 'W').length;
    final aLosses = a.gameLog.where((g) => g.result == 'L').length;
    final bWins = b.gameLog.where((g) => g.result == 'W').length;
    final bLosses = b.gameLog.where((g) => g.result == 'L').length;

    // Head-to-head matchups from game logs (prefer opponentTeamId, fall back to name)
    final h2hGamesA = a.gameLog.where((g) =>
        g.opponentTeamId == teamBId ||
        (g.opponentTeamId == null && g.opponentName == b.teamName)).toList();

    final h2hWinsA = h2hGamesA.where((g) => g.result == 'W').length;
    final h2hWinsB = h2hGamesA.where((g) => g.result == 'L').length;

    // Last matchups
    final lastMatchups = h2hGamesA.toList()..sort((x, y) => y.date.compareTo(x.date));
    final last3 = lastMatchups.take(3).toList();

    return Column(
      children: [
        // Team name headers
        Row(
          children: [
            Expanded(child: _teamHeader(a.teamName, AppColors.primary)),
            const SizedBox(width: 8),
            Expanded(child: _teamHeader(b.teamName, AppColors.info)),
          ],
        ),
        const SizedBox(height: 12),

        if (viewMode == _TeamViewMode.seasonAverages) ...[
          // Season record
          _statRow('Record', '$aWins-$aLosses', '$bWins-$bLosses'),
          const Divider(height: 1),

          // Averages
          _statRow('PPG', a.averages.ppg.toStringAsFixed(1), b.averages.ppg.toStringAsFixed(1)),
          _statRow('RPG', a.averages.rpg.toStringAsFixed(1), b.averages.rpg.toStringAsFixed(1)),
          _statRow('APG', a.averages.apg.toStringAsFixed(1), b.averages.apg.toStringAsFixed(1)),
          _statRow('SPG', a.averages.spg.toStringAsFixed(1), b.averages.spg.toStringAsFixed(1)),
          _statRow('BPG', a.averages.bpg.toStringAsFixed(1), b.averages.bpg.toStringAsFixed(1)),
          _statRow('TPG', a.averages.topg.toStringAsFixed(1), b.averages.topg.toStringAsFixed(1)),
          _statRow('FPG', a.averages.fpg.toStringAsFixed(1), b.averages.fpg.toStringAsFixed(1)),
        ] else ...[
          // Head-to-head record
          _statRow('H2H Record', '$h2hWinsA W', '$h2hWinsB W'),
          const SizedBox(height: 16),

          // Recent matchups
          if (last3.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Matchups',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            ...last3.map((g) => _matchupRow(a.teamName, g)),
          ] else
            const Text(
              'No head-to-head matchups this season',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
        ],
      ],
    );
  }

  Widget _teamHeader(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _statRow(String label, String valA, String valB) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(valA, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
          SizedBox(
            width: 80,
            child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(valB, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.info)),
          ),
        ],
      ),
    );
  }

  Widget _matchupRow(String teamAName, TeamGameLog game) {
    final isWin = game.result == 'W';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$teamAName vs ${game.opponentName}',
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isWin ? AppColors.success : AppColors.urgent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${game.pts} pts (${game.result})',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PLAYER SELECTOR (team then player) ────────────────────────────────

class _PlayerSelector extends ConsumerStatefulWidget {
  final List<TeamModel> teams;
  final String? seasonId;
  final String? selectedPlayerId;
  final String label;
  final ValueChanged<String?> onSelected;

  const _PlayerSelector({
    required this.teams,
    required this.seasonId,
    required this.selectedPlayerId,
    required this.label,
    required this.onSelected,
  });

  @override
  ConsumerState<_PlayerSelector> createState() => _PlayerSelectorState();
}

class _PlayerSelectorState extends ConsumerState<_PlayerSelector> {
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    final rosterAsync = _teamId != null
        ? ref.watch(teamRosterProvider(_teamId!))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Row(
          children: [
            // Team dropdown
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _teamId,
                hint: const Text('Team', style: TextStyle(fontSize: 13)),
                isExpanded: true,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
                ),
                items: widget.teams.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) {
                  setState(() {
                    _teamId = v;
                  });
                  widget.onSelected(null);
                },
              ),
            ),
            const SizedBox(width: 8),
            // Player dropdown
            Expanded(
              child: rosterAsync == null
                  ? DropdownButtonFormField<String>(
                      initialValue: null,
                      hint: const Text('Select team first', style: TextStyle(fontSize: 13)),
                      items: const [],
                      onChanged: null,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
                      ),
                    )
                  : rosterAsync.when(
                      data: (roster) => DropdownButtonFormField<String>(
                        initialValue: widget.selectedPlayerId,
                        hint: const Text('Player', style: TextStyle(fontSize: 13)),
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusSm)),
                        ),
                        items: roster
                            .map((p) => DropdownMenuItem(
                                  value: p.playerId,
                                  child: Text(p.playerName, style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: widget.onSelected,
                      ),
                      loading: () => const SizedBox(
                        height: 48,
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                      error: (e, _) => Text('Error: $e', style: const TextStyle(fontSize: 11)),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── PLAYER COMPARISON BODY ────────────────────────────────────────────

class _PlayerComparisonBody extends ConsumerWidget {
  final String playerAId;
  final String playerBId;
  final String seasonId;

  const _PlayerComparisonBody({
    required this.playerAId,
    required this.playerBId,
    required this.seasonId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aAsync = ref.watch(playerSeasonStatsProvider((playerId: playerAId, seasonId: seasonId)));
    final bAsync = ref.watch(playerSeasonStatsProvider((playerId: playerBId, seasonId: seasonId)));

    return aAsync.when(
      data: (a) => bAsync.when(
        data: (b) {
          if (a == null || b == null) {
            return const Center(child: Text('Stats not available for one or both players.'));
          }
          return _buildContent(context, a, b);
        },
        loading: () => const _LoadingIndicator(),
        error: (e, _) => Text('Error: $e'),
      ),
      loading: () => const _LoadingIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }

  Widget _buildContent(BuildContext context, PlayerSeasonStatsModel a, PlayerSeasonStatsModel b) {
    // Recent 5 games
    final aRecent = a.gameLog.toList()
      ..sort((x, y) => y.date.compareTo(x.date));
    final bRecent = b.gameLog.toList()
      ..sort((x, y) => y.date.compareTo(x.date));

    return Column(
      children: [
        // Player name headers
        Row(
          children: [
            Expanded(child: _playerHeader(a)),
            const SizedBox(width: 8),
            Expanded(child: _playerHeader(b)),
          ],
        ),
        const SizedBox(height: 12),

        // Season averages
        _statRow('GP', '${a.gamesPlayed}', '${b.gamesPlayed}'),
        _statRow('PPG', a.ppg.toStringAsFixed(1), b.ppg.toStringAsFixed(1)),
        _statRow('RPG', a.rpg.toStringAsFixed(1), b.rpg.toStringAsFixed(1)),
        _statRow('APG', a.apg.toStringAsFixed(1), b.apg.toStringAsFixed(1)),
        _statRow('SPG', a.spg.toStringAsFixed(1), b.spg.toStringAsFixed(1)),
        _statRow('BPG', a.bpg.toStringAsFixed(1), b.bpg.toStringAsFixed(1)),
        const SizedBox(height: 16),

        // Recent 5 games
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Recent Games', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _recentGames(aRecent.take(5).toList(), AppColors.primary)),
            const SizedBox(width: 8),
            Expanded(child: _recentGames(bRecent.take(5).toList(), AppColors.info)),
          ],
        ),
      ],
    );
  }

  Widget _playerHeader(PlayerSeasonStatsModel p) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Column(
        children: [
          Text(
            p.playerName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            p.teamName ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String valA, String valB) {
    final numA = double.tryParse(valA) ?? 0;
    final numB = double.tryParse(valB) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              valA,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: numA >= numB ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              valB,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: numB >= numA ? AppColors.info : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentGames(List<GameLogEntry> games, Color accent) {
    if (games.isEmpty) {
      return const Text('No games yet', style: TextStyle(fontSize: 11, color: AppColors.textMuted));
    }
    return Column(
      children: games.map((g) {
        final isWin = g.result == 'W';
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isWin ? AppColors.success : AppColors.urgent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(g.result, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${g.pts}p ${g.reb}r ${g.ast}a',
                  style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── SHARED WIDGETS ────────────────────────────────────────────────────

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

class _SelectBothHint extends StatelessWidget {
  final String label;
  const _SelectBothHint({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.compare_arrows, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}
