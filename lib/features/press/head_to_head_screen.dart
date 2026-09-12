import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';

enum _CompareMode { teams, players }

/// Media comparison backed exclusively by the current public release.
///
/// This screen intentionally has no import of team, roster, season, or private
/// statistics providers. Retraction and privacy-epoch enforcement therefore
/// stay identical to the guest-facing public experience.
class HeadToHeadScreen extends ConsumerStatefulWidget {
  final String? initialTeamAId;

  const HeadToHeadScreen({super.key, this.initialTeamAId});

  @override
  ConsumerState<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends ConsumerState<HeadToHeadScreen> {
  _CompareMode _mode = _CompareMode.teams;
  String? _teamAId;
  String? _teamBId;
  String? _playerAId;
  String? _playerBId;

  @override
  void initState() {
    super.initState();
    _teamAId = widget.initialTeamAId;
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Head to Head')),
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
    final teams = snapshot.teams.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    final players = _publicPlayers(snapshot);

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
        Text(
          '${snapshot.seasonName} published data',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Publication ${snapshot.version.shortLabel}. Comparisons update or disappear with the public release.',
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
        _selector(
          label: 'Player A',
          value: _playerAId,
          entries: entries,
          onChanged: (value) => setState(() => _playerAId = value),
        ),
        const SizedBox(height: 12),
        _selector(
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
      ],
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
    return _ComparisonCard(
      first: teamA.team.name,
      second: teamB.team.name,
      rows: [
        ('Record', _record(teamA.standing), _record(teamB.standing)),
        ('Head-to-head wins', '$winsA', '$winsB'),
        ('Head-to-head games', '${games.length}', '${games.length}'),
      ],
    );
  }

  static String _record(PublicStanding? standing) {
    if (standing?.wins == null || standing?.losses == null) return 'Unknown';
    return '${standing!.wins}-${standing.losses}';
  }
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
