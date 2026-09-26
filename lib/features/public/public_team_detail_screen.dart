import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'public_team_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/public_brand_context.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';
import 'historical_league_standings.dart';

class PublicTeamDetailScreen extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicTeamDetail detail;
  final Uri? canonicalUri;

  const PublicTeamDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
    this.canonicalUri,
  });

  @override
  ConsumerState<PublicTeamDetailScreen> createState() =>
      _PublicTeamDetailScreenState();
}

class _PublicTeamDetailScreenState
    extends ConsumerState<PublicTeamDetailScreen> {
  PublicLeagueSnapshot get snapshot => widget.snapshot;
  PublicTeamDetail get detail => widget.detail;
  Uri? get canonicalUri => widget.canonicalUri;
  bool _saving = false;
  String _category = 'ppg';
  bool _perGame = true;
  bool _gamesView = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isFollowing =
        user?.favoriteTeamIds.contains(widget.detail.team.teamId) ?? false;
    final viaLeague =
        user?.favoriteLeagueIds.any(
          (leagueId) => snapshot.availableLeagues.any(
            (league) =>
                league.leagueId == leagueId &&
                league.divisionIds.contains(detail.team.divisionId),
          ),
        ) ??
        false;
    final league = snapshot.leagueForDivision(detail.team.divisionId);
    return Scaffold(
      backgroundColor: publicSportsCanvas,
      appBar: AppBar(
        backgroundColor: const Color(0xFF234EBD),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: publicRoyalGradient),
        ),
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(PublicRoutePaths.standings),
          tooltip: 'Back to public standings',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Team details'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_gamesView ? 64 : 170),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Column(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Games'),
                      icon: Icon(Icons.sports_basketball_outlined),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Players & stats'),
                      icon: Icon(Icons.people_outline),
                    ),
                  ],
                  selected: {_gamesView},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _gamesView = value.first),
                ),
                if (!_gamesView) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Statistics',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Per game')),
                          ButtonSegment(value: false, label: Text('Totals')),
                        ],
                        selected: {_perGame},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            setState(() => _perGame = value.first),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in const {
                          'ppg': 'Points',
                          'rpg': 'Rebounds',
                          'apg': 'Assists',
                          'spg': 'Steals',
                          'bpg': 'Blocks',
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: _category == entry.key,
                              onSelected: (_) =>
                                  setState(() => _category = entry.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            key: const Key('follow-team-button'),
            onPressed: _saving || (viaLeague && !isFollowing)
                ? null
                : () async {
                    if (user == null) {
                      context.go(
                        AppRouteContract.loginFor(
                          Uri.parse(
                            PublicRoutePaths.team(widget.detail.team.teamId),
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => _saving = true);
                    try {
                      await ref.read(authRepositoryProvider).updateUser(
                        user.id,
                        {
                          'favoriteTeamIds': isFollowing
                              ? FieldValue.arrayRemove([
                                  widget.detail.team.teamId,
                                ])
                              : FieldValue.arrayUnion([
                                  widget.detail.team.teamId,
                                ]),
                        },
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not update team follow. Try again.',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            icon: Icon(
              isFollowing || viaLeague ? Icons.check : Icons.favorite_border,
            ),
            label: Text(
              isFollowing
                  ? 'Following team'
                  : viaLeague
                  ? 'Via league'
                  : 'Follow',
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.compare_arrows, size: 20),
            label: const Text('Compare'),
            onPressed: () => context.push(
              '/public/compare?team=${Uri.encodeComponent(detail.team.teamId)}',
            ),
          ),
          if (snapshot.canCreatePublishedArtifacts && detail.standing != null)
            IconButton(
              onPressed: () => _share(context, ref, league),
              tooltip: 'Share team snapshot',
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
      body: Theme(
        data: publicSportsTheme(context),
        child: ListView(
          key: ValueKey(_gamesView ? 'team-games' : 'team-statistics'),
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          children: [
            PublicBrandContext(
              snapshot: snapshot,
              league: league,
              divisionName: snapshot.divisionName(detail.team.divisionId),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (detail.team.logoUrl != null)
                  SponsorLogo(
                    reference: detail.team.logoUrl!,
                    semanticLabel: '${detail.team.name} team logo',
                    width: 72,
                    height: 72,
                  )
                else
                  CircleAvatar(
                    radius: 36,
                    child: Text(_initials(detail.team.name)),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    detail.team.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              league.seasonLabel ??
                  '${snapshot.seasonName} · ${snapshot.divisionName(detail.team.divisionId)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_gamesView)
              _TeamGames(games: detail.games, snapshot: snapshot)
            else ...[
              if (league.historicalStatistics) ...[
                Text(
                  '${league.description}. Team totals are summed from the recorded player statistics.',
                ),
                const SizedBox(height: 12),
                Text(
                  _perGame ? 'Team averages' : 'Team totals',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (league.leagueId == 'jbl')
                  const Text('9 games · 2025 statistical period'),
                RecordedTeamTotals(
                  snapshot: snapshot,
                  teamId: detail.team.teamId,
                  showAverages: _perGame,
                  gamesPlayed: league.leagueId == 'jbl' ? 9 : null,
                ),
                const SizedBox(height: 20),
              ] else ...[
                Text('Standing', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                detail.standing == null
                    ? const AppStateMessage(
                        title: 'Standing unavailable',
                        message:
                            'No published standing was found for this team.',
                      )
                    : _StandingCard(standing: detail.standing!),
                const SizedBox(height: 20),
                Text('Games', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (detail.games.isEmpty)
                  const AppStateMessage(
                    title: 'No published games',
                    message:
                        'This team has no games in the current public snapshot.',
                  )
                else
                  ...detail.games.map(
                    (game) => Card(
                      child: ListTile(
                        onTap: () {
                          final gameDetail = snapshot.gameDetail(game.gameId);
                          if (gameDetail == null) return;
                          context.push(PublicRoutePaths.game(game.gameId));
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
              ],
              Text(
                league.historicalStatistics
                    ? 'Player statistics · ${_perGame ? 'Per game' : 'Totals'}'
                    : 'Published leaders',
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
                ...detail.leaderboards
                    .where((board) => board.category == _category)
                    .map((board) {
                      final rows =
                          board.rankings
                              .where(
                                (leader) => leader.teamId == detail.team.teamId,
                              )
                              .toList(growable: false)
                            ..sort(
                              (a, b) => _perGame
                                  ? (b.value ?? -1).compareTo(a.value ?? -1)
                                  : (b.cumulativeTotal ?? -1).compareTo(
                                      a.cumulativeTotal ?? -1,
                                    ),
                            );
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
                                    : () => context.push(
                                        PublicRoutePaths.player(
                                          leader.playerId!,
                                        ),
                                      ),
                                title: Text(leader.displayName),
                                subtitle: Text(
                                  _gamesPlayed(leader.gamesPlayed),
                                ),
                                trailing: Text(
                                  _perGame
                                      ? _metric(leader.value)
                                      : '${leader.cumulativeTotal ?? '—'}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    PublicLeagueDefinition league,
  ) async {
    try {
      final binding = PublicArtifactBinding.snapshot(snapshot);
      final validator = ref.read(publicArtifactReleaseValidatorProvider);
      await validator.requireCurrent(binding);
      if (!context.mounted) return;
      final branding = publicShareBranding(snapshot, league);
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.publicTeam(
          snapshot: snapshot,
          team: detail,
          branding: branding,
          canonicalUri: canonicalUri,
        ),
        validateCurrent: () async {
          await validator.requireCurrent(binding);
        },
      );
    } on PublicArtifactReleaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${error.message} Refresh before sharing.')),
      );
    }
  }
}

class _TeamGames extends StatelessWidget {
  const _TeamGames({required this.games, required this.snapshot});
  final List<PublicGame> games;
  final PublicLeagueSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final upcoming =
        games
            .where(
              (game) =>
                  !game.isFinal &&
                  game.status != PublicGameStatus.canceled &&
                  !game.startTime.isBefore(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final past = games.where((game) => game.isFinal).toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    Widget tile(PublicGame game) => Card(
      child: InkWell(
        key: Key('team-game-${game.gameId}'),
        onTap: () => context.push(PublicRoutePaths.game(game.gameId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      LeagueTime.formatJamaicaDate(
                        game.startTime,
                        pattern: 'MMM d, yyyy',
                      ),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    game.isFinal ? 'FINAL' : _statusLabel(game.status),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final home in [true, false])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PublicTeamMark(
                        snapshot: snapshot,
                        teamId: home ? game.homeTeamId : game.awayTeamId,
                        name:
                            (home ? game.homeTeamName : game.awayTeamName) ??
                            'Team',
                        size: 42,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Tooltip(
                          message:
                              (home ? game.homeTeamName : game.awayTeamName) ??
                              'Team',
                          child: Text(
                            compactTeamName(
                              (home ? game.homeTeamName : game.awayTeamName) ??
                                  'Team',
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      Text(
                        '${(home ? game.homeScore : game.awayScore) ?? '—'}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      game.isFinal
                          ? 'View box score'
                          : '${game.dateOnly ? '' : '${LeagueTime.formatJamaicaTime(game.startTime)} · '}${game.venue ?? 'Venue to be announced'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upcoming games', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('No upcoming games published yet.'),
          )
        else
          ...upcoming.map(tile),
        const SizedBox(height: 16),
        Text('Past games', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Open a result to see the game statistics and box score.'),
        const SizedBox(height: 8),
        if (past.isEmpty) const Text('No published results yet.'),
        ...past.take(5).map(tile),
        if (past.length > 5)
          ExpansionTile(
            title: Text('Show ${past.length - 5} more results'),
            children: past.skip(5).map(tile).toList(),
          ),
        const SizedBox(height: 20),
        const Text(
          'Select Players & stats above to explore player profiles, averages and totals.',
        ),
      ],
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

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final value = words.map((word) => word[0]).join().toUpperCase();
  return value.isEmpty ? 'T' : value;
}
