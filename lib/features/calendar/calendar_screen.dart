import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../models/event_model.dart';
import '../../models/game_stats_model.dart';
import '../../models/team_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';
import 'widgets/date_scroller.dart';
import 'widgets/game_card.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = LeagueTime.jamaicaDate(DateTime.now());
  DateTime _selectedDay = LeagueTime.jamaicaDate(DateTime.now());
  bool _showMonthView = true;

  @override
  Widget build(BuildContext context) {
    final firstCivil = DateTime.utc(_focusedDay.year, _focusedDay.month - 1, 1);
    final lastCivilExclusive = DateTime.utc(
      _focusedDay.year,
      _focusedDay.month + 2,
      1,
    );
    final firstDay = LeagueTime.startOfJamaicaDayUtc(firstCivil);
    final lastDay = LeagueTime.startOfJamaicaDayUtc(
      lastCivilExclusive,
    ).subtract(const Duration(microseconds: 1));
    final selectedDivisionId = ref.watch(selectedDivisionIdProvider);

    final eventsAsync = ref.watch(
      eventsStreamProvider((
        from: firstDay,
        to: lastDay,
        divisionId: selectedDivisionId,
      )),
    );
    final teamsAsync = ref.watch(teamsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            icon: Icon(
              _showMonthView
                  ? Icons.view_agenda_outlined
                  : Icons.calendar_month_outlined,
            ),
            tooltip: _showMonthView ? 'List view' : 'Month view',
            onPressed: () => setState(() => _showMonthView = !_showMonthView),
          ),
        ],
      ),
      body: eventsAsync.when(
        data: (events) {
          final teams = teamsAsync.valueOrNull ?? <TeamModel>[];

          // Group events by day
          final eventsByDay = <DateTime, List<EventModel>>{};
          for (final event in events) {
            final day = LeagueTime.jamaicaDate(event.startTime);
            eventsByDay.putIfAbsent(day, () => []).add(event);
          }

          final selectedDayNorm = DateTime.utc(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day,
          );
          final selectedEvents = eventsByDay[selectedDayNorm] ?? [];

          if (_showMonthView) {
            return _MonthView(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              eventsByDay: eventsByDay,
              selectedEvents: selectedEvents,
              teams: teams,
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
              },
              onPageChanged: (focused) {
                setState(() => _focusedDay = focused);
              },
              onEventTap: _onEventTap,
            );
          }

          return _ListView(
            selectedDay: _selectedDay,
            selectedEvents: selectedEvents,
            teams: teams,
            onDateSelected: (date) {
              setState(() {
                _selectedDay = date;
                _focusedDay = date;
              });
            },
            onEventTap: _onEventTap,
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _onEventTap(EventModel event) {
    if (event.isGame) {
      context.push('/box-score/${event.id}');
    }
  }
}

/// List view: date scroller + game cards
class _ListView extends ConsumerWidget {
  final DateTime selectedDay;
  final List<EventModel> selectedEvents;
  final List<TeamModel> teams;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<EventModel> onEventTap;

  const _ListView({
    required this.selectedDay,
    required this.selectedEvents,
    required this.teams,
    required this.onDateSelected,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Date scroller
        DateScroller(selectedDate: selectedDay, onDateSelected: onDateSelected),

        // Selected date header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingMd,
            vertical: 8,
          ),
          child: Row(
            children: [
              Text(
                DateFormat('EEEE, MMMM d').format(selectedDay),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (selectedEvents.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${selectedEvents.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Event cards
        Expanded(
          child: selectedEvents.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSizes.paddingMd),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, i) {
                    final event = selectedEvents[i];
                    return _GameCardWithStats(
                      event: event,
                      teams: teams,
                      onTap: () => onEventTap(event),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Month calendar view using TableCalendar
class _MonthView extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final Map<DateTime, List<EventModel>> eventsByDay;
  final List<EventModel> selectedEvents;
  final List<TeamModel> teams;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<EventModel> onEventTap;

  const _MonthView({
    required this.focusedDay,
    required this.selectedDay,
    required this.eventsByDay,
    required this.selectedEvents,
    required this.teams,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar<EventModel>(
          firstDay: DateTime(2025, 1, 1),
          lastDay: DateTime(2027, 12, 31),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          calendarFormat: CalendarFormat.month,
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          eventLoader: (day) {
            final norm = DateTime.utc(day.year, day.month, day.day);
            return eventsByDay[norm] ?? [];
          },
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            markerSize: 6,
            markersMaxCount: 3,
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const Divider(height: 1),

        // Selected day header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingMd,
            vertical: 10,
          ),
          child: Row(
            children: [
              Text(
                DateFormat('EEEE, MMMM d').format(selectedDay),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (selectedEvents.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${selectedEvents.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Event cards
        Expanded(
          child: selectedEvents.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingMd,
                  ),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, i) {
                    final event = selectedEvents[i];
                    return _GameCardWithStats(
                      event: event,
                      teams: teams,
                      onTap: () => onEventTap(event),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Wraps GameCard and fetches game stats for completed games.
/// Shows "Record Stats" or "View Box Score" action based on user role and game status.
class _GameCardWithStats extends ConsumerWidget {
  final EventModel event;
  final List<TeamModel> teams;
  final VoidCallback onTap;

  const _GameCardWithStats({
    required this.event,
    required this.teams,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!event.isGame) {
      return GameCard(
        event: event,
        teams: teams,
        onTap: onTap,
        onTeamTap: null,
      );
    }

    final statsAsync = ref.watch(gameStatsProvider(event.id));
    final gameStats = statsAsync.valueOrNull;
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    final isApproved =
        event.statsStatus == StatsStatus.approved ||
        gameStats?.status == GameStatsStatus.approved;
    final isSubmitted =
        !isApproved &&
        (event.statsStatus == StatsStatus.submitted ||
            gameStats?.status == GameStatsStatus.submitted);
    final hasStats = isApproved || isSubmitted;
    final canEnter = currentUser?.canEnterStats ?? false;
    final isPending =
        event.statsStatus == StatsStatus.pending ||
        (gameStats == null && event.statsStatus == StatsStatus.pending);

    final hasPostGameDraft =
        (gameStats?.status.isEditable ?? false) &&
        gameStats?.entryMode == GameStatsEntryMode.postGame;

    return Column(
      children: [
        GameCard(
          event: event,
          teams: teams,
          gameStats: gameStats,
          onTap: onTap,
          onTeamTap: (teamId) => context.push('/team/$teamId'),
        ),
        // Stat action row
        if (hasStats ||
            (canEnter && isPending) ||
            (canEnter && hasPostGameDraft))
          Transform.translate(
            offset: const Offset(0, -10), // overlap with card bottom margin
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppSizes.radiusMd),
                  bottomRight: Radius.circular(AppSizes.radiusMd),
                ),
              ),
              child: Row(
                children: [
                  if (hasStats) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/box-score/${event.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF16A34A,
                            ).withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(
                                0xFF16A34A,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.scoreboard_outlined,
                                color: Color(0xFF16A34A),
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Box Score',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (canEnter && isSubmitted) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => context.push('/admin/stats/${event.id}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF2563EB,
                              ).withValues(alpha: 0.08),
                              border: Border.all(
                                color: const Color(
                                  0xFF2563EB,
                                ).withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.edit_note,
                                  color: Color(0xFF2563EB),
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Correct',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else if (canEnter && hasPostGameDraft) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/admin/stats/${event.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF2563EB,
                            ).withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(
                                0xFF2563EB,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.edit_calendar_outlined,
                                color: Color(0xFF2563EB),
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Resume Post-Game Draft',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else if (canEnter && isPending) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            context.push('/live-stats?eventId=${event.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Live Stats',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/admin/stats/${event.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF3B82F6,
                            ).withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(
                                0xFF3B82F6,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.edit_note,
                                color: Color(0xFF3B82F6),
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Post-Game',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_outlined, size: 40, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text(
            'No events this day',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
