import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/public_league_snapshot.dart';

class PublicTeamDetailScreen extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicTeamDetail detail;

  const PublicTeamDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(PublicRoutePaths.standings),
          tooltip: 'Back to public standings',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Team details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          Text(
            detail.team.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.seasonName} · ${snapshot.divisionName(detail.team.divisionId)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text('Standing', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          detail.standing == null
              ? const AppStateMessage(
                  title: 'Standing unavailable',
                  message: 'No published standing was found for this team.',
                )
              : _StandingCard(standing: detail.standing!),
          const SizedBox(height: 20),
          Text('Games', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (detail.games.isEmpty)
            const AppStateMessage(
              title: 'No published games',
              message: 'This team has no games in the current public snapshot.',
            )
          else
            ...detail.games.map(
              (game) => Card(
                child: ListTile(
                  onTap: () {
                    final gameDetail = snapshot.gameDetail(game.gameId);
                    if (gameDetail == null) return;
                    context.go(PublicRoutePaths.game(game.gameId));
                  },
                  title: Text(
                    '${game.homeTeamName ?? 'Home'} vs ${game.awayTeamName ?? 'Away'}',
                  ),
                  subtitle: Text(
                    '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'MMM d, yyyy')} · ${LeagueTime.formatJamaicaTime(game.startTime)}',
                  ),
                  trailing: Text(
                    game.isFinal
                        ? '${game.homeScore}-${game.awayScore}'
                        : _statusLabel(game.status),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Published leaders',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (detail.leaderboards.isEmpty)
            const AppStateMessage(
              title: 'No published leaders',
              message:
                  'No cleared player leader rows were found for this team.',
            )
          else
            ...detail.leaderboards.map((board) {
              final rows = board.rankings
                  .where((leader) => leader.teamId == detail.team.teamId)
                  .toList(growable: false);
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        '${board.categoryLabel} · ${snapshot.divisionName(board.divisionId)}',
                      ),
                    ),
                    ...rows.map(
                      (leader) => ListTile(
                        onTap: leader.playerId == null
                            ? null
                            : () => context.go(
                                PublicRoutePaths.player(leader.playerId!),
                              ),
                        title: Text(leader.displayName),
                        subtitle: Text(_gamesPlayed(leader.gamesPlayed)),
                        trailing: Text(_metric(leader.value)),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _StandingCard extends StatelessWidget {
  final PublicStanding standing;

  const _StandingCard({required this.standing});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _record(standing.wins, standing.losses),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(_gamesPlayed(standing.gamesPlayed)),
              ],
            ),
          ),
          Text(
            standing.rankStatus == PublicRankStatus.unresolved
                ? 'Rank unresolved'
                : standing.rankStatus == PublicRankStatus.tied
                ? 'Tied at ${standing.rank ?? '?'}'
                : 'Rank ${standing.rank ?? '?'}',
          ),
        ],
      ),
    ),
  );
}

String _statusLabel(PublicGameStatus status) => switch (status) {
  PublicGameStatus.finalResult => 'Final',
  PublicGameStatus.scheduled => 'Scheduled',
  PublicGameStatus.postponed => 'Postponed',
  PublicGameStatus.canceled => 'Canceled',
};

String _gamesPlayed(int? count) => count == null
    ? 'Games played unavailable'
    : '$count ${count == 1 ? 'game' : 'games'} played';

String _record(int? wins, int? losses) =>
    wins == null || losses == null ? 'Record unavailable' : '$wins-$losses';

String _metric(double? value) => value?.toStringAsFixed(1) ?? 'Unknown';
