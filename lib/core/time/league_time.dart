import 'package:intl/intl.dart';

/// League scheduling uses America/Jamaica as its canonical civil timezone.
///
/// Firestore timestamps remain UTC instants. Jamaica is UTC-05:00 year-round,
/// so this utility intentionally does not depend on the device timezone. The
/// New York conversion exists for comparison/acceptance tests and follows the
/// post-2007 US daylight-saving transition rules.
abstract final class LeagueTime {
  static const Duration jamaicaUtcOffset = Duration(hours: -5);
  static const Duration newYorkStandardUtcOffset = Duration(hours: -5);
  static const Duration newYorkDaylightUtcOffset = Duration(hours: -4);

  static DateTime nowJamaicaCivil({DateTime? utcNow}) =>
      jamaicaCivilFromInstant(utcNow ?? DateTime.now().toUtc());

  /// Returns a UTC-backed civil value whose components represent Jamaica.
  /// Callers must not persist this synthetic civil value as an instant.
  static DateTime jamaicaCivilFromInstant(DateTime instant) =>
      instant.toUtc().add(jamaicaUtcOffset);

  /// Converts Jamaica wall-clock components to the corresponding UTC instant.
  static DateTime jamaicaWallClockToUtc({
    required DateTime date,
    required int hour,
    required int minute,
  }) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be between 0 and 23');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(minute, 'minute', 'must be between 0 and 59');
    }
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour - jamaicaUtcOffset.inHours,
      minute,
    );
  }

  /// A date-only UTC-backed value using the Jamaica calendar day.
  static DateTime jamaicaDate(DateTime instant) {
    final civil = jamaicaCivilFromInstant(instant);
    return DateTime.utc(civil.year, civil.month, civil.day);
  }

  static DateTime startOfJamaicaDayUtc(DateTime civilDate) =>
      jamaicaWallClockToUtc(date: civilDate, hour: 0, minute: 0);

  static DateTime endExclusiveOfJamaicaDayUtc(DateTime civilDate) =>
      startOfJamaicaDayUtc(
        DateTime.utc(civilDate.year, civilDate.month, civilDate.day + 1),
      );

  static String formatJamaicaTime(DateTime instant, {bool includeZone = true}) {
    final text = DateFormat('h:mm a').format(jamaicaCivilFromInstant(instant));
    return includeZone ? '$text JA' : text;
  }

  static String formatJamaicaDate(
    DateTime instant, {
    String pattern = 'EEEE, MMMM d, y',
  }) => DateFormat(pattern).format(jamaicaCivilFromInstant(instant));

  static DateTime newYorkCivilFromInstant(DateTime instant) {
    final utc = instant.toUtc();
    final offset = isNewYorkDaylightTime(utc)
        ? newYorkDaylightUtcOffset
        : newYorkStandardUtcOffset;
    return utc.add(offset);
  }

  static bool isNewYorkDaylightTime(DateTime instant) {
    final utc = instant.toUtc();
    final year = utc.year;
    final marchSecondSunday = _nthWeekdayOfMonthUtc(
      year: year,
      month: DateTime.march,
      weekday: DateTime.sunday,
      occurrence: 2,
    );
    final novemberFirstSunday = _nthWeekdayOfMonthUtc(
      year: year,
      month: DateTime.november,
      weekday: DateTime.sunday,
      occurrence: 1,
    );

    // 02:00 EST is 07:00 UTC; 02:00 EDT is 06:00 UTC.
    final starts = DateTime.utc(year, DateTime.march, marchSecondSunday, 7);
    final ends = DateTime.utc(year, DateTime.november, novemberFirstSunday, 6);
    return !utc.isBefore(starts) && utc.isBefore(ends);
  }

  static int _nthWeekdayOfMonthUtc({
    required int year,
    required int month,
    required int weekday,
    required int occurrence,
  }) {
    final first = DateTime.utc(year, month, 1);
    final daysUntilWeekday = (weekday - first.weekday + 7) % 7;
    return 1 + daysUntilWeekday + ((occurrence - 1) * 7);
  }
}
