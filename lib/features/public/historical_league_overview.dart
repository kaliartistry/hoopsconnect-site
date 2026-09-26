import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/public_league_snapshot.dart';
import 'public_team_identity.dart';

/// Historical aggregates are not a schedule, official standing, or live roster.
class HistoricalLeagueOverview extends StatelessWidget {
  const HistoricalLeagueOverview({
    super.key,
    required this.snapshot,
    required this.league,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;

  @override
  Widget build(BuildContext context) {
    final games =
        snapshot.schedule
            .where(
              (game) =>
                  league.divisionIds.contains(game.divisionId) && game.isFinal,
            )
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final teams = snapshot.teams
        .where((team) => league.divisionIds.contains(team.divisionId))
        .toList();
    final players = snapshot.leaderboards
        .where(
          (board) =>
              league.divisionIds.contains(board.divisionId) &&
              board.category == 'ppg',
        )
        .expand((board) => board.rankings)
        .toList();
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          key: const Key('historical-league-scroll'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              league.seasonLabel ?? 'Historical statistics',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${teams.length} teams · ${players.length} recorded players',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${league.description ?? ''}. Explore teams and player statistics. Per-game averages use each player’s recorded appearances.',
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('historical-view-leaders'),
                onPressed: () => context.go(PublicRoutePaths.leaders),
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('Explore player statistics'),
              ),
            ),
            const SizedBox(height: 24),
            if (games.isNotEmpty) ...[
              Text('Recorded results', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'Available game reports. Player season totals and standings retain their own reporting dates.',
              ),
              const SizedBox(height: 8),
              for (final game in games)
                _HistoricalResultCard(
                  snapshot: snapshot,
                  game: game,
                  onTap: () => context.push(PublicRoutePaths.game(game.gameId)),
                ),
              const SizedBox(height: 24),
            ],
            Text('Teams', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 860
                    ? 3
                    : constraints.maxWidth >= 550
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final team in teams)
                      SizedBox(
                        width: width,
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          shadowColor: const Color(0x28000000),
                          surfaceTintColor: Colors.transparent,
                          child: InkWell(
                            key: Key('historical-team-${team.teamId}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.push(
                              PublicRoutePaths.team(team.teamId),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  if (team.logoUrl != null)
                                    SponsorLogo(
                                      reference: team.logoUrl!,
                                      width: 64,
                                      height: 64,
                                      semanticLabel: '${team.name} team logo',
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          team.name,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${players.where((player) => player.teamId == team.teamId).length} recorded players',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (league.supportingSponsorExamples.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Demo supporting sponsor examples',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Illustrative placements only. These are not confirmed JBL sponsors.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  for (final example in league.supportingSponsorExamples.where(
                    (sponsor) => sponsor.isActive,
                  ))
                    SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (example.logoUrl != null)
                            SponsorLogo(
                              reference: example.logoUrl!,
                              width: 150,
                              height: 52,
                              semanticLabel:
                                  '${example.name}, demo supporting sponsor example',
                            ),
                          const SizedBox(height: 6),
                          Text(
                            example.name,
                            style: theme.textTheme.labelMedium,
                          ),
                          Text(
                            'Demo example',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoricalResultCard extends StatelessWidget {
  const _HistoricalResultCard({
    required this.snapshot,
    required this.game,
    required this.onTap,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicGame game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final homeWon = (game.homeScore ?? -1) > (game.awayScore ?? -1);
    final awayWon = (game.awayScore ?? -1) > (game.homeScore ?? -1);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shadowColor: const Color(0x220B1D3A),
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            children: [
              _HistoricalResultTeamRow(
                snapshot: snapshot,
                teamId: game.homeTeamId,
                name: game.homeTeamName ?? 'Home team',
                score: game.homeScore,
                winner: homeWon,
              ),
              const SizedBox(height: 8),
              _HistoricalResultTeamRow(
                snapshot: snapshot,
                teamId: game.awayTeamId,
                name: game.awayTeamName ?? 'Away team',
                score: game.awayScore,
                winner: awayWon,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    DateFormat.yMMMd().format(game.startTime.toUtc()),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoricalResultTeamRow extends StatelessWidget {
  const _HistoricalResultTeamRow({
    required this.snapshot,
    required this.teamId,
    required this.name,
    required this.score,
    required this.winner,
  });

  final PublicLeagueSnapshot snapshot;
  final String? teamId;
  final String name;
  final int? score;
  final bool winner;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      PublicTeamMark(
        snapshot: snapshot,
        teamId: teamId,
        name: name,
        size: 34,
        onDarkSurface: false,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          compactTeamName(name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF0B1D3A),
            fontWeight: winner ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
      if (winner)
        const Icon(Icons.arrow_drop_up, color: Color(0xFFE7BC5A), size: 22),
      Text(
        score?.toString() ?? '—',
        style: TextStyle(
          color: winner ? const Color(0xFF234EBD) : const Color(0xFF5F6F86),
          fontSize: 22,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
