import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import 'historical_league_standings.dart';
import 'public_stats_navigation.dart';
import 'public_team_identity.dart';

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
      ? (league.isNbl2025Archive ? 9 : null)
      : standing?.gamesPlayed;
  final reported = league.reportedStandings
      .where((r) => r.teamId == id)
      .firstOrNull;
  final totals = historical
      ? recordedTeamTotals(snapshot, id)
      : <String, int?>{};
  String avg(int? total) => total == null || gp == null || gp <= 0
      ? '—'
      : (total / gp).toStringAsFixed(1);
  return {
    'GP': '${gp ?? '—'}',
    'W': '${(historical ? reported?.wins : standing?.wins) ?? '—'}',
    'L': '${(historical ? reported?.losses : standing?.losses) ?? '—'}',
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
            final hasWins = values.values.any((v) => v['W'] != '—');
            final hasLosses = values.values.any((v) => v['L'] != '—');
            final metrics = {
              'PPG': 'Points per game',
              'RPG': 'Rebounds per game',
              'APG': 'Assists per game',
              'SPG': 'Steals per game',
              'BPG': 'Blocks per game',
              if (hasWins) 'W': 'Wins',
              if (hasLosses) 'L': 'Losses',
            };
            final metric = metrics.containsKey(_metric) ? _metric : 'PPG';
            teams.sort(
              (a, b) => (double.tryParse(values[b.teamId]![metric]!) ?? -1)
                  .compareTo(double.tryParse(values[a.teamId]![metric]!) ?? -1),
            );
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  primary: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    const PublicStatsNavigation(selected: 'teams'),
                    if (leagues.length > 1)
                      DropdownButtonFormField<String>(
                        initialValue: league.leagueId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'League'),
                        items: [
                          for (final l in leagues)
                            DropdownMenuItem(
                              value: l.leagueId,
                              child: Text(
                                l.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) =>
                            ref
                                    .read(
                                      publicSelectedLeagueIdProvider.notifier,
                                    )
                                    .state =
                                id,
                      )
                    else
                      Text(
                        league.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (league.seasonLabel case final String season)
                      Text(season),
                    const SizedBox(height: 8),
                    Text(
                      league.isNbl2025Archive
                          ? '${league.firstRoundStatisticsLabel}. Team averages use the nine-game reporting period.'
                          : 'Published per-game averages. A dash means unavailable.',
                    ),
                    if (metric == 'W' || metric == 'L')
                      const Text('Records are from the published standings.'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (final m in metrics.entries)
                          ChoiceChip(
                            label: Text(m.key, semanticsLabel: m.value),
                            selected: metric == m.key,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _metric = m.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final (index, team) in teams.indexed)
                      Card(
                        child: ListTile(
                          leading: PublicTeamMark(
                            snapshot: snapshot,
                            teamId: team.teamId,
                            name: team.name,
                            size: 36,
                          ),
                          title: Text('${index + 1}. ${team.name}'),
                          subtitle: Text(
                            [
                              '${values[team.teamId]!['GP']} GP',
                              if (hasWins) '${values[team.teamId]!['W']} W',
                              if (hasLosses) '${values[team.teamId]!['L']} L',
                            ].join(' · '),
                          ),
                          trailing: Text(
                            values[team.teamId]![metric]!,
                            semanticsLabel:
                                '${values[team.teamId]![metric]} ${metrics[metric]}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          onTap: () => context.push(
                            '/public/teams/${Uri.encodeComponent(team.teamId)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
  );
}
