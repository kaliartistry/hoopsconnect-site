import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import 'historical_league_standings.dart';
import 'public_stats_navigation.dart';

/// Averages use the same period as the source totals, never player appearances.
Map<String, String> publicTeamMetrics(
  PublicLeagueSnapshot snapshot,
  String id,
) {
  final detail = snapshot.teamDetail(id)!;
  final league = snapshot.leagueForDivision(detail.team.divisionId);
  final standing = detail.standing;
  final historical = league.historicalStatistics;
  final gp = historical
      ? (league.leagueId == 'jbl' &&
                league.seasonLabel?.contains('2025') == true
            ? 9
            : null)
      : standing?.gamesPlayed;
  final totals = historical
      ? recordedTeamTotals(snapshot, id)
      : <String, int?>{};
  String avg(int? total) => total == null || gp == null || gp <= 0
      ? '—'
      : (total / gp).toStringAsFixed(1);
  return {
    'GP': '${gp ?? '—'}',
    'W': '${standing?.wins ?? '—'}',
    'L': '${standing?.losses ?? '—'}',
    'PPG': avg(historical ? totals['ppg'] : standing?.pointsFor),
    'RPG': avg(totals['rpg']),
    'APG': avg(totals['apg']),
    'SPG': avg(totals['spg']),
    'BPG': avg(totals['bpg']),
    'OPP PPG': avg(standing?.pointsAgainst),
  };
}

class PublicTeamStatsScreen extends ConsumerStatefulWidget {
  const PublicTeamStatsScreen({super.key});
  @override
  ConsumerState<PublicTeamStatsScreen> createState() => _PublicTeamStatsState();
}

class _PublicTeamStatsState extends ConsumerState<PublicTeamStatsScreen> {
  String _metric = 'PPG';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Team statistics')),
    body: ref
        .watch(publicLeagueSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Statistics could not be loaded.')),
          data: (snapshot) {
            if (snapshot == null || !snapshot.version.isPublished) {
              return const Center(
                child: Text('No published statistics available.'),
              );
            }
            final selected = ref.watch(publicSelectedLeagueIdProvider);
            final leagues = snapshot.availableLeagues;
            final league =
                leagues.where((l) => l.leagueId == selected).firstOrNull ??
                leagues.first;
            final teams = snapshot.teams
                .where((t) => league.divisionIds.contains(t.divisionId))
                .toList();
            final values = {
              for (final t in teams)
                t.teamId: publicTeamMetrics(snapshot, t.teamId),
            };
            teams.sort(
              (a, b) => (double.tryParse(values[b.teamId]![_metric]!) ?? -1)
                  .compareTo(
                    double.tryParse(values[a.teamId]![_metric]!) ?? -1,
                  ),
            );
            return Column(
              children: [
                const PublicStatsNavigation(selected: 'teams'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    initialValue: league.leagueId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'League'),
                    items: [
                      for (final l in leagues)
                        DropdownMenuItem(
                          value: l.leagueId,
                          child: Text(l.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) =>
                        ref
                                .read(publicSelectedLeagueIdProvider.notifier)
                                .state =
                            id,
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<String>(
                    segments: [
                      for (final m in [
                        'PPG',
                        'RPG',
                        'APG',
                        'SPG',
                        'BPG',
                        'W',
                        'L',
                      ])
                        ButtonSegment(value: m, label: Text(m)),
                    ],
                    selected: {_metric},
                    onSelectionChanged: (v) =>
                        setState(() => _metric = v.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${league.seasonLabel ?? snapshot.seasonName} · Per-game averages. — means unavailable.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: teams.length,
                    itemBuilder: (context, index) {
                      final team = teams[index];
                      final stats = values[team.teamId]!;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(team.name),
                          subtitle: Text(
                            '${stats['GP']} GP · ${stats['W']} W · ${stats['L']} L',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                stats[_metric]!,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(_metric),
                            ],
                          ),
                          onTap: () => context.push(
                            '/public/teams/${Uri.encodeComponent(team.teamId)}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
  );
}
