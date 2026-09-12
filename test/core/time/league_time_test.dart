import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/time/league_time.dart';

void main() {
  group('LeagueTime', () {
    test('converts Jamaica wall time to a UTC instant year-round', () {
      final instant = LeagueTime.jamaicaWallClockToUtc(
        date: DateTime.utc(2026, 7, 12),
        hour: 19,
        minute: 30,
      );

      expect(instant, DateTime.utc(2026, 7, 13, 0, 30));
      expect(LeagueTime.formatJamaicaTime(instant), '7:30 PM JA');
    });

    test('groups a UTC instant into the correct Jamaica day at midnight', () {
      expect(
        LeagueTime.jamaicaDate(DateTime.utc(2026, 1, 1, 4, 59)),
        DateTime.utc(2025, 12, 31),
      );
      expect(
        LeagueTime.jamaicaDate(DateTime.utc(2026, 1, 1, 5)),
        DateTime.utc(2026, 1, 1),
      );
    });

    test('builds exclusive Jamaica day boundaries across UTC dates', () {
      final date = DateTime.utc(2026, 12, 31);
      expect(
        LeagueTime.startOfJamaicaDayUtc(date),
        DateTime.utc(2026, 12, 31, 5),
      );
      expect(
        LeagueTime.endExclusiveOfJamaicaDayUtc(date),
        DateTime.utc(2027, 1, 1, 5),
      );
    });

    test('New York moves one hour ahead of Jamaica during DST', () {
      final before = DateTime.utc(2026, 3, 8, 6, 59);
      final after = DateTime.utc(2026, 3, 8, 7);

      expect(LeagueTime.newYorkCivilFromInstant(before).hour, 1);
      expect(LeagueTime.jamaicaCivilFromInstant(before).hour, 1);
      expect(LeagueTime.newYorkCivilFromInstant(after).hour, 3);
      expect(LeagueTime.jamaicaCivilFromInstant(after).hour, 2);
    });

    test('New York returns to Jamaica time after the DST fall transition', () {
      final before = DateTime.utc(2026, 11, 1, 5, 59);
      final after = DateTime.utc(2026, 11, 1, 6);

      expect(LeagueTime.isNewYorkDaylightTime(before), isTrue);
      expect(LeagueTime.newYorkCivilFromInstant(before).hour, 1);
      expect(LeagueTime.isNewYorkDaylightTime(after), isFalse);
      expect(LeagueTime.newYorkCivilFromInstant(after).hour, 1);
      expect(LeagueTime.jamaicaCivilFromInstant(after).hour, 1);
    });
  });
}
