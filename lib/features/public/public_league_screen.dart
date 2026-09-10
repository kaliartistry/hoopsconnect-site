import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';

class PublicLeagueScreen extends ConsumerWidget {
  const PublicLeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(publicLeagueSnapshotProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Jamaica Basketball'),
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Sign in'),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xB3FFFFFF),
            indicatorColor: AppColors.accent,
            tabs: [
              Tab(text: 'Games', icon: Icon(Icons.sports_basketball)),
              Tab(text: 'Standings', icon: Icon(Icons.emoji_events_outlined)),
              Tab(text: 'Leaders', icon: Icon(Icons.leaderboard_outlined)),
            ],
          ),
        ),
        body: snapshot.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _PublicError(
            onRetry: () {
              ref.invalidate(publicLeagueSnapshotProvider);
            },
          ),
          data: (data) => data == null
              ? _PublicError(
                  onRetry: () {
                    ref.invalidate(publicLeagueSnapshotProvider);
                  },
                )
              : Column(
                  children: [
                    _PublicHeader(snapshot: data),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _GamesTab(games: data.schedule),
                          _StandingsTab(standings: data.standings),
                          _LeadersTab(leaderboards: data.leaderboards),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PublicHeader extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  const _PublicHeader({required this.snapshot});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.primary.withValues(alpha: 0.08),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.leagueName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        const Text(
          'Public scores and league information • No account needed',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _GamesTab extends ConsumerWidget {
  final List<PublicGame> games;
  const _GamesTab({required this.games});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (games.isEmpty) {
      return const _EmptyPublicData(label: 'No games published yet');
    }
    final ordered = [...games]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(publicLeagueSnapshotProvider);
        await ref.read(publicLeagueSnapshotProvider.future);
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final game = ordered[index];
          final home = game.homeTeamName ?? 'Home';
          final away = game.awayTeamName ?? 'Away';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat(
                            'EEE, MMM d • h:mm a',
                          ).format(game.startTime.toLocal()),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _StatusChip(isFinal: game.isFinal),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ScoreRow(name: home, score: game.homeScore),
                  const SizedBox(height: 6),
                  _ScoreRow(name: away, score: game.awayScore),
                  if (game.venue != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      game.venue!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final String name;
  final int? score;
  const _ScoreRow({required this.name, required this.score});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
      Text(
        score?.toString() ?? '—',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  final bool isFinal;
  const _StatusChip({required this.isFinal});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: isFinal
          ? AppColors.primary.withValues(alpha: 0.12)
          : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      isFinal ? 'FINAL' : 'SCHEDULED',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );
}

class _StandingsTab extends StatelessWidget {
  final List<PublicStanding> standings;
  const _StandingsTab({required this.standings});

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const _EmptyPublicData(label: 'No standings published yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: standings.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = standings[index];
        return ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(
            row.teamName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('PF ${row.pointsFor}  •  PA ${row.pointsAgainst}'),
          trailing: Text(
            '${row.wins}-${row.losses}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}

class _LeadersTab extends StatefulWidget {
  final List<PublicLeaderboard> leaderboards;
  const _LeadersTab({required this.leaderboards});

  @override
  State<_LeadersTab> createState() => _LeadersTabState();
}

class _LeadersTabState extends State<_LeadersTab> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.leaderboards.isEmpty) {
      return const _EmptyPublicData(label: 'No leaders published yet');
    }
    final safeIndex = selected.clamp(0, widget.leaderboards.length - 1);
    final board = widget.leaderboards[safeIndex];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < widget.leaderboards.length; i++)
                ButtonSegment(
                  value: i,
                  label: Text(widget.leaderboards[i].category.toUpperCase()),
                ),
            ],
            selected: {safeIndex},
            onSelectionChanged: (value) =>
                setState(() => selected = value.first),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: board.rankings.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = board.rankings[index];
              return ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(row.displayName),
                subtitle: Text('${row.teamName} • ${row.gamesPlayed} GP'),
                trailing: Text(
                  row.value.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PublicError extends StatelessWidget {
  final VoidCallback onRetry;
  const _PublicError({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('Public league information is temporarily unavailable.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _EmptyPublicData extends StatelessWidget {
  final String label;
  const _EmptyPublicData({required this.label});

  @override
  Widget build(BuildContext context) => Center(
    child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
  );
}
