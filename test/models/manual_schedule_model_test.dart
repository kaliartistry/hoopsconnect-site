import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/event_model.dart';

void main() {
  test('cancelled games are visible but do not need stats or block a slot', () {
    final cancelled = EventModel(
      id: 'game-cancelled',
      title: 'Cancelled game',
      type: 'game',
      startTime: DateTime.utc(2026, 9, 12, 1),
      endTime: DateTime.utc(2026, 9, 12, 3),
      teamIds: const ['team-a', 'team-b'],
      createdBy: 'scheduler',
      statsStatus: StatsStatus.cancelled,
      lifecycleStatus: EventLifecycleStatus.cancelled,
    );

    expect(cancelled.needsStats, isFalse);
    expect(
      findManualScheduleConflicts(
        existingEvents: [cancelled],
        homeTeamId: 'team-a',
        awayTeamId: 'team-b',
        startTimeUtc: DateTime.utc(2026, 9, 12, 1),
        endTimeUtc: DateTime.utc(2026, 9, 12, 3),
      ),
      isEmpty,
    );
  });

  final start = DateTime.utc(2026, 9, 13, 1);
  final end = DateTime.utc(2026, 9, 13, 3);

  test('manual schedule contract requires explicit UTC instants', () {
    expect(
      () => ManualGameScheduleRequest(
        operationId: 'schedule_1',
        seasonId: 'season_1',
        divisionId: 'division_1',
        homeTeamId: 'home_1',
        awayTeamId: 'away_1',
        startTimeUtc: DateTime(2026, 9, 12, 20),
        endTimeUtc: DateTime(2026, 9, 12, 22),
      ),
      throwsArgumentError,
    );
  });

  test('exact retries retain the caller supplied operation ID', () {
    final request = ManualGameScheduleRequest(
      operationId: 'schedule_retry_1',
      seasonId: 'season_1',
      divisionId: 'division_1',
      homeTeamId: 'home_1',
      awayTeamId: 'away_1',
      startTimeUtc: start,
      endTimeUtc: end,
    );

    expect(request.toMap()['operationId'], 'schedule_retry_1');
    expect(request.toMap()['operationId'], request.toMap()['operationId']);
  });

  test('same pair at same instant is a duplicate regardless of order', () {
    final conflicts = findManualScheduleConflicts(
      existingEvents: [
        EventModel(
          id: 'game_1',
          title: 'Away vs Home',
          type: 'game',
          startTime: start,
          endTime: end,
          divisionId: 'division_1',
          teamIds: const ['away_1', 'home_1'],
          createdBy: 'admin_1',
        ),
      ],
      homeTeamId: 'home_1',
      awayTeamId: 'away_1',
      startTimeUtc: start,
      endTimeUtc: end,
    );

    expect(conflicts, hasLength(1));
    expect(conflicts.single.kind, ManualScheduleConflictKind.duplicate);
  });

  test('overlapping game for either team is rejected', () {
    final conflicts = findManualScheduleConflicts(
      existingEvents: [
        EventModel(
          id: 'game_2',
          title: 'Home vs Another',
          type: 'game',
          startTime: start.add(const Duration(hours: 1)),
          endTime: end.add(const Duration(hours: 1)),
          teamIds: const ['home_1', 'another_1'],
          createdBy: 'admin_1',
        ),
      ],
      homeTeamId: 'home_1',
      awayTeamId: 'away_1',
      startTimeUtc: start,
      endTimeUtc: end,
    );

    expect(conflicts.single.kind, ManualScheduleConflictKind.teamOverlap);
  });

  test('back-to-back games that only touch at the boundary are allowed', () {
    final conflicts = findManualScheduleConflicts(
      existingEvents: [
        EventModel(
          id: 'game_3',
          title: 'Earlier game',
          type: 'game',
          startTime: start.subtract(const Duration(hours: 2)),
          endTime: start,
          teamIds: const ['home_1', 'another_1'],
          createdBy: 'admin_1',
        ),
      ],
      homeTeamId: 'home_1',
      awayTeamId: 'away_1',
      startTimeUtc: start,
      endTimeUtc: end,
    );

    expect(conflicts, isEmpty);
  });

  test('cross-midnight overlap is still detected by UTC interval', () {
    final lateStart = DateTime.utc(2026, 9, 13, 4);
    final lateEnd = DateTime.utc(2026, 9, 13, 6);
    final conflicts = findManualScheduleConflicts(
      existingEvents: [
        EventModel(
          id: 'game_4',
          title: 'After midnight in Jamaica',
          type: 'game',
          startTime: DateTime.utc(2026, 9, 13, 5, 30),
          endTime: DateTime.utc(2026, 9, 13, 7, 30),
          teamIds: const ['away_1', 'another_1'],
          createdBy: 'admin_1',
        ),
      ],
      homeTeamId: 'home_1',
      awayTeamId: 'away_1',
      startTimeUtc: lateStart,
      endTimeUtc: lateEnd,
    );

    expect(conflicts.single.kind, ManualScheduleConflictKind.teamOverlap);
  });
}
