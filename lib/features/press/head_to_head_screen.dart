import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../public/public_stats_navigation.dart';
import '../public/public_team_stats_screen.dart';

import '../../core/constants/app_constants.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../services/public_artifact_release_validator.dart';

enum _CompareMode { teams, players }

/// Media comparison backed exclusively by the current public release.
///
/// This screen intentionally has no import of team, roster, season, or private
/// statistics providers. Retraction and privacy-epoch enforcement therefore
/// stay identical to the guest-facing public experience.
class HeadToHeadScreen extends ConsumerStatefulWidget {
  final String? initialTeamAId;
  final String? initialPlayerAId;

  const HeadToHeadScreen({
    super.key,
    this.initialTeamAId,
    this.initialPlayerAId,
  });

  @override
  ConsumerState<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends ConsumerState<HeadToHeadScreen> {
  _CompareMode _mode = _CompareMode.teams;
  String? _teamAId;
  String? _teamBId;
  String? _playerAId;
  String? _playerBId;
  bool _sharing = false;
  String? _leagueId;

  @override
  void initState() {
    super.initState();
    _teamAId = widget.initialTeamAId;
    _playerAId = widget.initialPlayerAId;
    if (_playerAId != null) _mode = _CompareMode.players;
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ReleaseUnavailable(
          message:
              'The published comparison data could not be loaded. No private stats were used.',
          onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
        ),
        data: (snapshot) {
          if (snapshot == null || !snapshot.version.isPublished) {
            return _ReleaseUnavailable(
              message:
                  'There is no active public release for comparisons. No private stats were used.',
              onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
            );
          }
          return _buildPublished(snapshot);
        },
      ),
    );
  }

  Widget _buildPublished(PublicLeagueSnapshot snapshot) {
    final leagues = snapshot.availableLeagues;
    final initialDivision =
        snapshot.teamDetail(_teamAId ?? '')?.team.divisionId ??
        snapshot
            .playerDetail(_playerAId ?? '')
            ?.categories
            .firstOrNull
            ?.divisionId;
    _leagueId ??= initialDivision != null
        ? snapshot.leagueForDivision(initialDivision).leagueId
        : ref.read(publicSelectedLeagueIdProvider);
    final league =
        leagues.where((l) => l.leagueId == _leagueId).firstOrNull ??
        leagues.first;
    final teams =
        snapshot.teams
            .where(
              (t) =>
                  league.divisionIds.isEmpty ||
                  league.divisionIds.contains(t.divisionId),
            )
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    final players = _publicPlayers(snapshot)
      ..removeWhere(
        (_, p) =>
            !teams.any((t) => t.teamId == p.categories.first.value.teamId),
      );

    if (_teamAId != null && !teams.any((team) => team.teamId == _teamAId)) {
      _teamAId = null;
    }
    if (_teamBId != null && !teams.any((team) => team.teamId == _teamBId)) {
      _teamBId = null;
    }
    if (_playerAId != null && !players.containsKey(_playerAId)) {
      _playerAId = null;
    }
    if (_playerBId != null && !players.containsKey(_playerBId)) {
      _playerBId = null;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSizes.paddingMd),
      children: [
        const PublicStatsNavigation(selected: 'compare'),
        DropdownButtonFormField<String>(
          initialValue: league.leagueId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'League / season'),
          items: [
            for (final l in leagues)
              DropdownMenuItem(
                value: l.leagueId,
                child: Text(
                  '${l.name} · ${l.seasonLabel ?? snapshot.seasonName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            _leagueId = id;
            _teamAId = null;
            _teamBId = null;
            _playerAId = null;
            _playerBId = null;
          }),
        ),
        const SizedBox(height: 16),
        Text(
          'Season averages & head-to-head',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Choose two teams or players. Share the comparison and start the conversation.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SegmentedButton<_CompareMode>(
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
          onSelectionChanged: (selection) {
            setState(() => _mode = selection.first);
          },
        ),
        const SizedBox(height: 20),
        if (_mode == _CompareMode.teams)
          _teamComparison(snapshot, teams)
        else
          _playerComparison(snapshot, players),
      ],
    );
  }

  Widget _teamComparison(
    PublicLeagueSnapshot snapshot,
    List<PublicTeam> teams,
  ) {
    if (teams.length < 2) {
      return const _Hint('Two public teams are required for comparison.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selector(
          label: 'Team A',
          value: _teamAId,
          entries: {for (final team in teams) team.teamId: team.name},
          onChanged: (value) => setState(() => _teamAId = value),
        ),
        const SizedBox(height: 12),
        _selector(
          label: 'Team B',
          value: _teamBId,
          entries: {for (final team in teams) team.teamId: team.name},
          onChanged: (value) => setState(() => _teamBId = value),
        ),
        const SizedBox(height: 20),
        if (_teamAId == null || _teamBId == null)
          const _Hint('Select two teams to compare.')
        else if (_teamAId == _teamBId)
          const _Hint('Choose two different teams.')
        else
          _TeamComparison(
            snapshot: snapshot,
            teamAId: _teamAId!,
            teamBId: _teamBId!,
          ),
        if (_teamAId != null &&
            _teamBId != null &&
            _teamAId != _teamBId &&
            snapshot.canCreatePublishedArtifacts)
          FilledButton.icon(
            onPressed: _sharing ? null : () => _shareTeams(snapshot),
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Share team comparison'),
          ),
      ],
    );
  }

  Widget _playerComparison(
    PublicLeagueSnapshot snapshot,
    Map<String, PublicPlayerDetail> players,
  ) {
    if (snapshot.version.privacyEpoch == null) {
      return const _Hint(
        'Player comparisons are unavailable until the public privacy policy is versioned.',
      );
    }
    if (players.length < 2) {
      return const _Hint(
        'Two public player records are required for comparison.',
      );
    }
    final entries = {
      for (final entry in players.entries)
        entry.key: '${entry.value.displayName} · ${entry.value.teamName}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _playerSelector(
          label: 'Player A',
          value: _playerAId,
          entries: entries,
          onChanged: (value) => setState(() => _playerAId = value),
        ),
        const SizedBox(height: 12),
        _playerSelector(
          label: 'Player B',
          value: _playerBId,
          entries: entries,
          onChanged: (value) => setState(() => _playerBId = value),
        ),
        const SizedBox(height: 20),
        if (_playerAId == null || _playerBId == null)
          const _Hint('Select two players to compare.')
        else if (_playerAId == _playerBId)
          const _Hint('Choose two different players.')
        else
          _PlayerComparison(
            playerA: players[_playerAId!]!,
            playerB: players[_playerBId!]!,
          ),
        if (_playerAId != null &&
            _playerBId != null &&
            _playerAId != _playerBId)
          _RecentMeetings(
            snapshot: snapshot,
            first: players[_playerAId!]!.categories.first.value.teamId,
            second: players[_playerBId!]!.categories.first.value.teamId,
            playerA: _playerAId,
            playerB: _playerBId,
          ),
        if (_playerAId != null &&
            _playerBId != null &&
            _playerAId != _playerBId &&
            snapshot.canCreatePublishedArtifacts) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('share-player-comparison'),
            onPressed: _sharing ? null : () => _sharePlayers(snapshot),
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(
              _sharing ? 'Preparing comparison…' : 'Share player comparison',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _sharePlayers(PublicLeagueSnapshot snapshot) async {
    if (_sharing) return;
    final firstId = _playerAId!;
    final secondId = _playerBId!;
    setState(() => _sharing = true);
    try {
      final binding = PublicArtifactBinding.snapshot(snapshot);
      final validator = ref.read(publicArtifactReleaseValidatorProvider);
      final current = await validator.requireCurrent(binding);
      final first = current.snapshot.playerDetail(firstId);
      final second = current.snapshot.playerDetail(secondId);
      if (first == null || second == null) return;
      final leagueA = current.snapshot.leagueForDivision(
        first.categories.first.divisionId,
      );
      final leagueB = current.snapshot.leagueForDivision(
        second.categories.first.divisionId,
      );
      final branding = leagueA.leagueId == leagueB.leagueId
          ? publicShareBranding(current.snapshot, leagueA)
          : publicOverviewShareBranding(current.snapshot);
      if (!mounted) return;
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.publicPlayerComparison(
          snapshot: current.snapshot,
          first: first,
          second: second,
          branding: branding,
        ),
        validateCurrent: () async {
          await validator.requireCurrent(binding);
        },
      );
    } on PublicArtifactReleaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not prepare this comparison. Refresh and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareTeams(PublicLeagueSnapshot snapshot) async {
    final firstId = _teamAId!;
    final secondId = _teamBId!;
    setState(() => _sharing = true);
    try {
      final binding = PublicArtifactBinding.snapshot(snapshot);
      final validator = ref.read(publicArtifactReleaseValidatorProvider);
      final current = (await validator.requireCurrent(binding)).snapshot;
      final first = current.teamDetail(firstId)?.team;
      final second = current.teamDetail(secondId)?.team;
      if (first == null || second == null) return;
      final leagueA = current.leagueForDivision(first.divisionId);
      final leagueB = current.leagueForDivision(second.divisionId);
      final branding = leagueA.leagueId == leagueB.leagueId
          ? publicShareBranding(current, leagueA)
          : publicOverviewShareBranding(current);
      final a = publicTeamMetrics(current, firstId);
      final b = publicTeamMetrics(current, secondId);
      final rows = [
        for (final key in ['W', 'L', 'PPG', 'RPG', 'APG', 'SPG'])
          (key, a[key]!, b[key]!),
      ];
      if (!mounted) return;
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload(
          title: '${first.name} vs ${second.name}',
          sheetTitle: 'Share team comparison',
          eyebrow: 'TEAM COMPARISON',
          headline: '${first.name} vs ${second.name}',
          detail: 'Season averages · ${a['GP']} / ${b['GP']} games',
          divisionLabel: leagueA.seasonLabel ?? current.seasonName,
          sourceLabel: 'Published statistics · — means unavailable',
          comparisonRows: rows,
          teams: [
            BrandedShareTeam(name: first.name, logoUrl: first.logoUrl),
            BrandedShareTeam(name: second.name, logoUrl: second.logoUrl),
          ],
          shareText: [
            '${first.name} vs ${second.name}',
            for (final row in rows) '${row.$1}: ${row.$2} / ${row.$3}',
            'https://hoopsconnect-jba-staging.web.app/public/compare',
          ].join('\n'),
          fileName:
              'team-comparison-$firstId-$secondId-${current.version.shortLabel}.png',
        ),
        validateCurrent: () async {
          await validator.requireCurrent(binding);
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Comparison could not be prepared. Refresh and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _playerSelector({
    required String label,
    required String? value,
    required Map<String, String> entries,
    required ValueChanged<String?> onChanged,
  }) {
    return OutlinedButton(
      onPressed: () async {
        var query = '';
        final chosen = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(
                builder: (context, update) {
                  final matches =
                      entries.entries
                          .where(
                            (e) => e.value.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                          )
                          .toList()
                        ..sort((a, b) => a.value.compareTo(b.value));
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Choose $label',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search player or team',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => update(() => query = v),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, i) => ListTile(
                              title: Text(matches[i].value),
                              onTap: () =>
                                  Navigator.pop(context, matches[i].key),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        if (chosen != null && mounted) onChanged(chosen);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text('$label: ${entries[value] ?? 'Choose player'}'),
            ),
            const Icon(Icons.search),
          ],
        ),
      ),
    );
  }

  Widget _selector({
    required String label,
    required String? value,
    required Map<String, String> entries,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: entries.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

class _TeamComparison extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final String teamAId;
  final String teamBId;

  const _TeamComparison({
    required this.snapshot,
    required this.teamAId,
    required this.teamBId,
  });

  @override
  Widget build(BuildContext context) {
    final teamA = snapshot.teamDetail(teamAId)!;
    final teamB = snapshot.teamDetail(teamBId)!;
    final games = snapshot.schedule
        .where(
          (game) =>
              game.isFinal &&
              ((game.homeTeamId == teamAId && game.awayTeamId == teamBId) ||
                  (game.homeTeamId == teamBId && game.awayTeamId == teamAId)),
        )
        .toList(growable: false);
    var winsA = 0;
    var winsB = 0;
    for (final game in games) {
      if (game.homeScore == game.awayScore) continue;
      final homeWon = game.homeScore! > game.awayScore!;
      if ((homeWon && game.homeTeamId == teamAId) ||
          (!homeWon && game.awayTeamId == teamAId)) {
        winsA++;
      } else {
        winsB++;
      }
    }
    final statsA = publicTeamMetrics(snapshot, teamAId);
    final statsB = publicTeamMetrics(snapshot, teamBId);
    return Column(
      children: [
        _ComparisonCard(
          first: teamA.team.name,
          second: teamB.team.name,
          rows: [
            ('Record', _record(teamA.standing), _record(teamB.standing)),
            for (final key in ['GP', 'PPG', 'RPG', 'APG', 'SPG', 'BPG'])
              (key, statsA[key]!, statsB[key]!),
            ('Head-to-head wins', '$winsA', '$winsB'),
            ('Head-to-head games', '${games.length}', '${games.length}'),
          ],
        ),
        _RecentMeetings(snapshot: snapshot, first: teamAId, second: teamBId),
      ],
    );
  }

  static String _record(PublicStanding? standing) {
    if (standing?.wins == null || standing?.losses == null) return 'Unknown';
    return '${standing!.wins}-${standing.losses}';
  }
}

class _RecentMeetings extends StatelessWidget {
  const _RecentMeetings({
    required this.snapshot,
    required this.first,
    required this.second,
    this.playerA,
    this.playerB,
  });
  final PublicLeagueSnapshot snapshot;
  final String? first, second, playerA, playerB;

  @override
  Widget build(BuildContext context) {
    if (first == null || second == null || first == second) {
      return const SizedBox.shrink();
    }
    final games =
        snapshot.schedule
            .where(
              (g) =>
                  g.isFinal &&
                  ((g.homeTeamId == first && g.awayTeamId == second) ||
                      (g.homeTeamId == second && g.awayTeamId == first)),
            )
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          'Last five meetings',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Available game records. Tap a result for the box score.'),
        if (games.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No published meetings between these teams yet.'),
          ),
        for (final game in games.take(5))
          Card(
            child: ListTile(
              title: Text(
                '${game.homeTeamName} ${game.homeScore} · ${game.awayScore} ${game.awayTeamName}',
              ),
              subtitle: Text(
                [
                  DateFormat.yMMMd().format(game.startTime),
                  if (playerA != null) _playerLine(game, playerA!),
                  if (playerB != null) _playerLine(game, playerB!),
                ].join('\n'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/public/games/${Uri.encodeComponent(game.gameId)}',
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _playerLine(PublicGame game, String id) {
    final player = snapshot.playerDetail(id);
    final line = game.playerLines.where((p) => p.playerId == id).firstOrNull;
    final points = line?.points ?? recordedMatchupPoints(game, player);
    return '${player?.displayName ?? 'Player'}: ${points == null ? 'points not recorded' : '$points PTS'}';
  }
}

/// Older imports keep selected performances in the team-scoped recap rather
/// than playerLines. Only match a full normalized name within that player's team.
int? recordedMatchupPoints(PublicGame game, PublicPlayerDetail? player) {
  if (player == null || player.categories.isEmpty) return null;
  final teamId = player.categories.first.value.teamId;
  final teamName = game.homeTeamId == teamId
      ? game.homeTeamName
      : game.awayTeamId == teamId
      ? game.awayTeamName
      : null;
  if (teamName == null) return null;
  String normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  var inTeam = false;
  for (final text in (game.recap ?? '').split('\n')) {
    if (text == game.homeTeamName || text == game.awayTeamName) {
      inTeam = text == teamName;
      continue;
    }
    if (!inTeam || !text.contains(': ')) continue;
    final parts = text.split(': ');
    if (normalize(parts.first) != normalize(player.displayName)) continue;
    final value = RegExp(r'(\d+) PTS\b').firstMatch(parts.last)?.group(1);
    if (value != null) return int.tryParse(value);
  }
  return null;
}

class _PlayerComparison extends StatelessWidget {
  final PublicPlayerDetail playerA;
  final PublicPlayerDetail playerB;

  const _PlayerComparison({required this.playerA, required this.playerB});

  @override
  Widget build(BuildContext context) {
    final valuesA = {
      for (final entry in playerA.categories)
        entry.category.toLowerCase(): entry.value.value,
    };
    final valuesB = {
      for (final entry in playerB.categories)
        entry.category.toLowerCase(): entry.value.value,
    };
    final categories = <String>{...valuesA.keys, ...valuesB.keys}.toList()
      ..sort();
    return _ComparisonCard(
      first: playerA.displayName,
      second: playerB.displayName,
      rows: categories
          .map(
            (category) => (
              category.toUpperCase(),
              _metric(valuesA[category]),
              _metric(valuesB[category]),
            ),
          )
          .toList(growable: false),
    );
  }

  static String _metric(double? value) =>
      value == null ? 'Unknown' : value.toStringAsFixed(1);
}

class _ComparisonCard extends StatelessWidget {
  final String first;
  final String second;
  final List<(String, String, String)> rows;

  const _ComparisonCard({
    required this.first,
    required this.second,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(first, textAlign: TextAlign.center)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('vs'),
                ),
                Expanded(child: Text(second, textAlign: TextAlign.center)),
              ],
            ),
            const Divider(height: 24),
            if (rows.isEmpty)
              const Text('No matching public metrics are available.')
            else
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(row.$2, textAlign: TextAlign.center),
                      ),
                      SizedBox(
                        width: 130,
                        child: Text(row.$1, textAlign: TextAlign.center),
                      ),
                      Expanded(
                        child: Text(row.$3, textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

Map<String, PublicPlayerDetail> _publicPlayers(PublicLeagueSnapshot snapshot) {
  final ids = <String>{};
  for (final board in snapshot.leaderboards) {
    for (final leader in board.rankings) {
      if (leader.playerId != null) ids.add(leader.playerId!);
    }
  }
  final players = <String, PublicPlayerDetail>{};
  for (final id in ids) {
    final detail = snapshot.playerDetail(id);
    if (detail != null) players[id] = detail;
  }
  return players;
}

class _ReleaseUnavailable extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReleaseUnavailable({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String message;

  const _Hint(this.message);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
