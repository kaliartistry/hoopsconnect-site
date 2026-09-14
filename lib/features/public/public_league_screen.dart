import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';

class PublicLeagueScreen extends ConsumerWidget {
  const PublicLeagueScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(publicLeagueSnapshotProvider);
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Jamaica Basketball'),
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () => context.go('/login'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Sign in'),
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xB3FFFFFF),
            indicatorColor: AppColors.accent,
            onTap: (index) {
              final destination = switch (index) {
                1 => PublicRoutePaths.standings,
                2 => PublicRoutePaths.leaders,
                _ => PublicRoutePaths.games,
              };
              if (GoRouterState.of(context).uri.path != destination) {
                context.go(destination);
              }
            },
            tabs: [
              Tab(text: 'Games', icon: Icon(Icons.sports_basketball)),
              Tab(text: 'Standings', icon: Icon(Icons.emoji_events_outlined)),
              Tab(text: 'Leaders', icon: Icon(Icons.leaderboard_outlined)),
            ],
          ),
        ),
        body: snapshot.when(
          loading: () => const Center(
            child: AppLoadingState(label: 'Loading published league data'),
          ),
          error: (_, _) => _PublicState(
            title: 'Published data could not be loaded',
            message:
                'No private league records were used as a fallback. Check your connection and try again.',
            tone: AppStateTone.error,
            onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
          ),
          data: (data) {
            if (data == null) {
              return _PublicState(
                title: 'Published data unavailable',
                message:
                    'The league has not published a public snapshot yet. No private data is shown.',
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              );
            }
            return switch (data.version.state) {
              PublicReleaseState.retracted => _PublicState(
                title: 'This public release was withdrawn',
                message:
                    'Previously loaded scores and exports are not presented as current. Try again later for a new release.',
                tone: AppStateTone.warning,
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              ),
              PublicReleaseState.unavailable => _PublicState(
                title: 'Public league data unavailable',
                message:
                    'There is no active public release. No private source records were used.',
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              ),
              PublicReleaseState.published => _PublishedLeague(snapshot: data),
            };
          },
        ),
      ),
    );
  }
}

class _PublishedLeague extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;

  const _PublishedLeague({required this.snapshot});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PublicHeader(snapshot: snapshot),
      Expanded(
        child: TabBarView(
          children: [
            _GamesTab(snapshot: snapshot),
            _StandingsTab(snapshot: snapshot),
            _LeadersTab(snapshot: snapshot),
          ],
        ),
      ),
    ],
  );
}

class _PublicHeader extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;

  const _PublicHeader({required this.snapshot});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.primaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                snapshot.leagueName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${snapshot.seasonName} · No account needed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                snapshot.version.isVersioned
                    ? 'Published ${LeagueTime.formatJamaicaDate(snapshot.generatedAt, pattern: 'MMM d')} at ${LeagueTime.formatJamaicaTime(snapshot.generatedAt)} · Version ${snapshot.version.shortLabel}'
                    : 'Legacy public snapshot · sharing and exports unavailable',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum _GamesViewMode { schedule, calendar }

class _GamesTab extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;

  const _GamesTab({required this.snapshot});

  @override
  ConsumerState<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends ConsumerState<_GamesTab> {
  static const _pageSize = 25;
  String? _divisionId;
  int _visibleCount = _pageSize;
  _GamesViewMode _viewMode = _GamesViewMode.schedule;
  DateTime? _selectedDay;

  @override
  void didUpdateWidget(covariant _GamesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_divisionId != null &&
        !widget.snapshot.divisions.any(
          (division) => division.divisionId == _divisionId,
        )) {
      _divisionId = null;
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.snapshot.schedule
            .where(
              (game) => _divisionId == null || game.divisionId == _divisionId,
            )
            .toList(growable: false)
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final visible = filtered.take(_visibleCount).toList(growable: false);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(publicLeagueSnapshotProvider);
        await ref.read(publicLeagueSnapshotProvider.future);
      },
      child: ListView(
        key: const Key('public-games-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControls(context, filtered),
                    const SizedBox(height: 18),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: AppStateMessage(
                          title: 'No games published',
                          message:
                              'There are no public games for this division in the current snapshot.',
                          icon: Icons.event_busy_outlined,
                        ),
                      )
                    else if (_viewMode == _GamesViewMode.calendar)
                      _buildCalendar(context, filtered)
                    else
                      _buildSchedule(context, filtered, visible),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, List<PublicGame> games) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final selector = SegmentedButton<_GamesViewMode>(
              key: const Key('public-games-view-selector'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _GamesViewMode.schedule,
                  icon: Icon(Icons.view_agenda_outlined),
                  label: Text('Schedule'),
                ),
                ButtonSegment(
                  value: _GamesViewMode.calendar,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Calendar'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) => setState(() {
                _viewMode = selection.first;
                if (_viewMode == _GamesViewMode.calendar) {
                  _selectedDay ??= _defaultCalendarDay(games);
                }
              }),
            );
            final division = _DivisionFilter(
              snapshot: widget.snapshot,
              value: _divisionId,
              padding: EdgeInsets.zero,
              onChanged: (value) => setState(() {
                _divisionId = value;
                _visibleCount = _pageSize;
                final scoped = widget.snapshot.schedule
                    .where((game) => value == null || game.divisionId == value)
                    .toList(growable: false);
                _selectedDay = _defaultCalendarDay(scoped);
              }),
            );

            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Games & scores',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Browse the full schedule by date or choose a day on the calendar.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 16),
                  selector,
                  const SizedBox(height: 14),
                  division,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    selector,
                    const SizedBox(width: 16),
                    Expanded(child: division),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSchedule(
    BuildContext context,
    List<PublicGame> filtered,
    List<PublicGame> visible,
  ) {
    final sections = _gamesByDay(visible);
    return Column(
      key: const Key('public-games-schedule-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections.entries) ...[
          _GameDateHeading(date: section.key, count: section.value.length),
          const SizedBox(height: 8),
          _ResponsiveGameCards(snapshot: widget.snapshot, games: section.value),
          const SizedBox(height: 20),
        ],
        if (visible.length < filtered.length)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _visibleCount += _pageSize),
              icon: const Icon(Icons.expand_more),
              label: Text(
                'Load ${(_pageSize).clamp(0, filtered.length - visible.length)} more games',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context, List<PublicGame> games) {
    final ascendingDays = _gamesByDay(games, ascending: true);
    final firstGameDay = ascendingDays.keys.first;
    final lastGameDay = ascendingDays.keys.last;
    final firstDate = DateTime(firstGameDay.year, firstGameDay.month);
    final lastDate = DateTime(lastGameDay.year, lastGameDay.month + 1, 0);
    final preferredDay = _selectedDay ?? _defaultCalendarDay(games)!;
    final selectedDay = _clampDay(preferredDay, firstDate, lastDate);
    final selectedGames =
        games
            .where(
              (game) =>
                  _sameDay(_jamaicaCalendarDay(game.startTime), selectedDay),
            )
            .toList(growable: false)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final calendar = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Choose a date',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              key: const Key('public-games-calendar'),
              child: CalendarDatePicker(
                key: ValueKey(selectedDay),
                initialDate: selectedDay,
                firstDate: firstDate,
                lastDate: lastDate,
                currentDate: _currentJamaicaDay(),
                onDateChanged: (value) => setState(() {
                  _selectedDay = DateTime(value.year, value.month, value.day);
                }),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                'Game-day shortcuts',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final entry in ascendingDays.entries) ...[
                    ChoiceChip(
                      key: Key(_gameDayKey(entry.key)),
                      selected: _sameDay(entry.key, selectedDay),
                      label: Text(
                        '${DateFormat('MMM d').format(entry.key)} · ${entry.value.length}',
                      ),
                      onSelected: (_) => setState(() {
                        _selectedDay = entry.key;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final dayGames = Column(
      key: const Key('public-games-calendar-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GameDateHeading(date: selectedDay, count: selectedGames.length),
        const SizedBox(height: 8),
        if (selectedGames.isEmpty)
          const AppStateMessage(
            title: 'No games on this date',
            message:
                'Choose another date or use one of the game-day shortcuts.',
            icon: Icons.event_available_outlined,
          )
        else
          _ResponsiveGameCards(snapshot: widget.snapshot, games: selectedGames),
      ],
    );

    return LayoutBuilder(
      key: const Key('public-games-calendar-view'),
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [calendar, const SizedBox(height: 20), dayGames],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 400, child: calendar),
            const SizedBox(width: 24),
            Expanded(child: dayGames),
          ],
        );
      },
    );
  }
}

class _GameDateHeading extends StatelessWidget {
  const _GameDateHeading({required this.date, required this.count});

  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, y').format(date),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              '$count ${count == 1 ? 'game' : 'games'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ResponsiveGameCards extends StatelessWidget {
  const _ResponsiveGameCards({required this.snapshot, required this.games});

  final PublicLeagueSnapshot snapshot;
  final List<PublicGame> games;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = games.length > 1 && constraints.maxWidth >= 760 ? 2 : 1;
      final cardWidth = columns == 2
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final game in games)
            SizedBox(
              width: cardWidth,
              child: _GameCard(snapshot: snapshot, game: game),
            ),
        ],
      );
    },
  );
}

Map<DateTime, List<PublicGame>> _gamesByDay(
  List<PublicGame> games, {
  bool ascending = false,
}) {
  final sorted = [...games]
    ..sort(
      (a, b) => ascending
          ? a.startTime.compareTo(b.startTime)
          : b.startTime.compareTo(a.startTime),
    );
  final result = <DateTime, List<PublicGame>>{};
  for (final game in sorted) {
    result.putIfAbsent(_jamaicaCalendarDay(game.startTime), () => []).add(game);
  }
  return result;
}

DateTime _jamaicaCalendarDay(DateTime instant) {
  final day = LeagueTime.jamaicaDate(instant);
  return DateTime(day.year, day.month, day.day);
}

DateTime _currentJamaicaDay() {
  final day = LeagueTime.nowJamaicaCivil();
  return DateTime(day.year, day.month, day.day);
}

DateTime? _defaultCalendarDay(List<PublicGame> games) {
  if (games.isEmpty) return null;
  final days = _gamesByDay(games, ascending: true).keys.toList(growable: false);
  final today = _currentJamaicaDay();
  return days.firstWhere(
    (day) => !day.isBefore(today),
    orElse: () => days.last,
  );
}

DateTime _clampDay(DateTime value, DateTime first, DateTime last) {
  if (value.isBefore(first)) return first;
  if (value.isAfter(last)) return last;
  return value;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _gameDayKey(DateTime date) =>
    'public-game-day-${DateFormat('yyyy-MM-dd').format(date)}';

class _GameCard extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGame game;

  const _GameCard({required this.snapshot, required this.game});

  @override
  Widget build(BuildContext context) {
    final home = game.homeTeamName ?? 'Home team unavailable';
    final away = game.awayTeamName ?? 'Away team unavailable';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => context.go(PublicRoutePaths.game(game.gameId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'EEE, MMM d')} · ${LeagueTime.formatJamaicaTime(game.startTime)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _StatusChip(status: game.status),
                ],
              ),
              const SizedBox(height: 12),
              _ScoreRow(name: home, score: game.homeScore),
              const SizedBox(height: 6),
              _ScoreRow(name: away, score: game.awayScore),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      game.venue ?? 'Venue not published',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
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
        score?.toString() ?? 'Not available',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  final PublicGameStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isFinal = status == PublicGameStatus.finalResult;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isFinal
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _gameStatusLabel(status).toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StandingsTab extends StatefulWidget {
  final PublicLeagueSnapshot snapshot;

  const _StandingsTab({required this.snapshot});

  @override
  State<_StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends State<_StandingsTab> {
  String? _divisionId;

  @override
  void didUpdateWidget(covariant _StandingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_divisionId != null &&
        !widget.snapshot.divisions.any(
          (division) => division.divisionId == _divisionId,
        )) {
      _divisionId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final standings = widget.snapshot.standings
        .where(
          (standing) =>
              _divisionId == null || standing.divisionId == _divisionId,
        )
        .toList(growable: false);
    final standingSections = <String?, List<PublicStanding>>{};
    for (final standing in standings) {
      standingSections
          .putIfAbsent(standing.divisionId, () => <PublicStanding>[])
          .add(standing);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DivisionFilter(
                    snapshot: widget.snapshot,
                    value: _divisionId,
                    onChanged: (value) => setState(() => _divisionId = value),
                  ),
                  if (widget.snapshot.standingsPolicyLabel == null) ...[
                    const AppStateMessage(
                      title: 'Ranking policy not published',
                      message:
                          'Rows stay in the league-published order. HoopsConnect does not use alphabetical order as a tie-breaker.',
                      tone: AppStateTone.warning,
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Text(
                      widget.snapshot.standingsPolicyLabel!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (standings.isEmpty)
                    const AppStateMessage(
                      title: 'No standings published',
                      message:
                          'There are no public standings for this division in the current snapshot.',
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final section in standingSections.entries) ...[
                            if (_divisionId == null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  6,
                                ),
                                child: Text(
                                  widget.snapshot.divisionName(section.key),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            for (final row in section.value)
                              Builder(
                                builder: (context) {
                                  final recordDetails =
                                      '${_known(row.gamesPlayed)} GP · PF ${_known(row.pointsFor)} · PA ${_known(row.pointsAgainst)}';
                                  return ListTile(
                                    onTap: row.teamId == null
                                        ? null
                                        : () => context.go(
                                            PublicRoutePaths.team(row.teamId!),
                                          ),
                                    leading: CircleAvatar(
                                      child: Text(_rankLabel(row)),
                                    ),
                                    title: Text(
                                      row.teamName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(recordDetails),
                                    trailing: Text(
                                      _record(row.wins, row.losses),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeadersTab extends StatefulWidget {
  final PublicLeagueSnapshot snapshot;

  const _LeadersTab({required this.snapshot});

  @override
  State<_LeadersTab> createState() => _LeadersTabState();
}

class _LeadersTabState extends State<_LeadersTab> {
  String? _divisionId;
  int _selected = 0;

  @override
  void didUpdateWidget(covariant _LeadersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_divisionId != null &&
        !widget.snapshot.divisions.any(
          (division) => division.divisionId == _divisionId,
        )) {
      _divisionId = null;
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boards = widget.snapshot.leaderboards
        .where(
          (board) => _divisionId == null || board.divisionId == _divisionId,
        )
        .toList(growable: false);
    final safeIndex = boards.isEmpty
        ? 0
        : _selected.clamp(0, boards.length - 1);
    final board = boards.isEmpty ? null : boards[safeIndex];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _DivisionFilter(
                  snapshot: widget.snapshot,
                  value: _divisionId,
                  onChanged: (value) => setState(() {
                    _divisionId = value;
                    _selected = 0;
                  }),
                ),
              ),
              if (boards.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < boards.length; i++)
                        ButtonSegment(
                          value: i,
                          label: Text(
                            _leaderboardSegmentLabel(
                              widget.snapshot,
                              boards[i],
                              includeDivision: _divisionId == null,
                            ),
                          ),
                        ),
                    ],
                    selected: {safeIndex},
                    onSelectionChanged: (value) =>
                        setState(() => _selected = value.first),
                  ),
                ),
              Expanded(
                child: board == null
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: AppStateMessage(
                          title: 'No leaders published',
                          message:
                              'There are no cleared player leader rows for this division.',
                        ),
                      )
                    : ListView(
                        children: [
                          if (board.qualificationLabel == null)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: AppStateMessage(
                                title: 'Qualification criteria unavailable',
                                message:
                                    'The league has not published the minimum-games rule for this category.',
                                tone: AppStateTone.warning,
                                compact: true,
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Text(board.qualificationLabel!),
                            ),
                          if (board.rankings.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: AppStateMessage(
                                title: 'No cleared leaders published',
                                message:
                                    'No player identity rows are available for this category and division.',
                              ),
                            )
                          else
                            for (
                              var index = 0;
                              index < board.rankings.length;
                              index++
                            )
                              ListTile(
                                onTap: board.rankings[index].playerId == null
                                    ? null
                                    : () => context.go(
                                        PublicRoutePaths.player(
                                          board.rankings[index].playerId!,
                                        ),
                                      ),
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(board.rankings[index].displayName),
                                subtitle: Text(
                                  '${board.rankings[index].teamName} · ${_known(board.rankings[index].gamesPlayed)} GP',
                                ),
                                trailing: Text(
                                  _metric(board.rankings[index].value),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
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

class _DivisionFilter extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final String? value;
  final ValueChanged<String?> onChanged;
  final EdgeInsetsGeometry padding;

  const _DivisionFilter({
    required this.snapshot,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    if (snapshot.divisions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        decoration: const InputDecoration(
          labelText: 'Division',
          prefixIcon: Icon(Icons.filter_list),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All divisions'),
          ),
          ...snapshot.divisions.map(
            (division) => DropdownMenuItem<String?>(
              value: division.divisionId,
              child: Text(division.name),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _PublicState extends StatelessWidget {
  final String title;
  final String message;
  final AppStateTone tone;
  final VoidCallback onRetry;

  const _PublicState({
    required this.title,
    required this.message,
    this.tone = AppStateTone.neutral,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AppStateMessage(
        title: title,
        message: message,
        tone: tone,
        actionLabel: 'Try again',
        onAction: onRetry,
      ),
    ),
  );
}

String _rankLabel(PublicStanding standing) => switch (standing.rankStatus) {
  PublicRankStatus.ranked => standing.rank?.toString() ?? '?',
  PublicRankStatus.tied => 'T${standing.rank ?? '?'}',
  PublicRankStatus.unresolved => '?',
};

String _known(int? value) => value?.toString() ?? 'Unknown';

String _record(int? wins, int? losses) =>
    wins == null || losses == null ? 'Unknown' : '$wins-$losses';

String _metric(double? value) => value?.toStringAsFixed(1) ?? 'Unknown';

String _leaderboardSegmentLabel(
  PublicLeagueSnapshot snapshot,
  PublicLeaderboard board, {
  required bool includeDivision,
}) {
  if (!includeDivision || board.divisionId == null) {
    return board.categoryLabel;
  }
  return '${board.categoryLabel} · ${snapshot.divisionName(board.divisionId)}';
}

String _gameStatusLabel(PublicGameStatus status) => switch (status) {
  PublicGameStatus.finalResult => 'Final',
  PublicGameStatus.scheduled => 'Scheduled',
  PublicGameStatus.postponed => 'Postponed',
  PublicGameStatus.canceled => 'Canceled',
};
