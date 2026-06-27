import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/game_stats_model.dart';

void main() {
  // ─────────────────────── PlayerStatLine ───────────────────────

  group('PlayerStatLine', () {
    test('reb getter returns oreb + dreb', () {
      const line = PlayerStatLine(
        name: 'John',
        teamId: 'team1',
        oreb: 3,
        dreb: 5,
      );
      expect(line.reb, equals(8));
    });

    test('reb is 0 when both oreb and dreb are 0', () {
      const line = PlayerStatLine(name: 'John', teamId: 'team1');
      expect(line.reb, equals(0));
    });

    test('fromMap parses all fields correctly', () {
      final map = {
        'name': 'Jane',
        'teamId': 'team2',
        'pts': 20,
        'oreb': 2,
        'dreb': 4,
        'ast': 6,
        'stl': 3,
        'blk': 1,
        'fls': 2,
        'min': 30,
      };

      final line = PlayerStatLine.fromMap(map);

      expect(line.name, 'Jane');
      expect(line.teamId, 'team2');
      expect(line.pts, 20);
      expect(line.oreb, 2);
      expect(line.dreb, 4);
      expect(line.ast, 6);
      expect(line.stl, 3);
      expect(line.blk, 1);
      expect(line.fls, 2);
      expect(line.min, 30);
    });

    test('fromMap uses 0 defaults for missing numeric fields', () {
      final map = {'name': 'Jane', 'teamId': 'team2'};

      final line = PlayerStatLine.fromMap(map);

      expect(line.pts, 0);
      expect(line.oreb, 0);
      expect(line.dreb, 0);
      expect(line.ast, 0);
      expect(line.stl, 0);
      expect(line.blk, 0);
      expect(line.fls, 0);
      expect(line.min, 0);
    });

    test('toMap includes computed reb field', () {
      const line = PlayerStatLine(
        name: 'John',
        teamId: 'team1',
        oreb: 3,
        dreb: 5,
      );

      final map = line.toMap();

      expect(map['reb'], equals(8));
      expect(map['oreb'], equals(3));
      expect(map['dreb'], equals(5));
      expect(map['name'], 'John');
      expect(map['teamId'], 'team1');
    });

    test('toMap round-trips through fromMap (excluding computed reb)', () {
      const original = PlayerStatLine(
        name: 'Test',
        teamId: 'team1',
        pts: 10,
        oreb: 1,
        dreb: 2,
        ast: 3,
        stl: 4,
        blk: 5,
        fls: 2,
        min: 25,
      );

      final restored = PlayerStatLine.fromMap(original.toMap());

      expect(restored.name, original.name);
      expect(restored.teamId, original.teamId);
      expect(restored.pts, original.pts);
      expect(restored.oreb, original.oreb);
      expect(restored.dreb, original.dreb);
      expect(restored.ast, original.ast);
      expect(restored.stl, original.stl);
      expect(restored.blk, original.blk);
      expect(restored.fls, original.fls);
      expect(restored.min, original.min);
    });

    test('copyWith overrides specified fields and keeps others', () {
      const line = PlayerStatLine(
        name: 'John',
        teamId: 'team1',
        pts: 10,
        oreb: 2,
        dreb: 3,
      );

      final updated = line.copyWith(pts: 12, stl: 1);

      expect(updated.pts, 12);
      expect(updated.stl, 1);
      expect(updated.name, 'John');
      expect(updated.oreb, 2);
      expect(updated.dreb, 3);
    });

    test('copyWith with no arguments returns equivalent object', () {
      const line = PlayerStatLine(name: 'John', teamId: 'team1', pts: 10);

      final copy = line.copyWith();

      expect(copy.name, line.name);
      expect(copy.pts, line.pts);
      expect(copy.teamId, line.teamId);
    });
  });

  // ─────────────────────── GameStatsModel ───────────────────────

  group('GameStatsModel', () {
    test('winnerTeamId returns homeTeamId when home wins', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
        homeScore: 80,
        awayScore: 70,
      );

      expect(model.winnerTeamId, 'home');
    });

    test('winnerTeamId returns awayTeamId when away wins', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
        homeScore: 60,
        awayScore: 70,
      );

      expect(model.winnerTeamId, 'away');
    });

    test('winnerTeamId returns homeTeamId on a tie', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
        homeScore: 75,
        awayScore: 75,
      );

      // Per implementation: homeScore >= awayScore -> homeTeamId
      expect(model.winnerTeamId, 'home');
    });

    test('toFirestore produces correct map', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'ev1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home Team',
        awayTeamName: 'Away Team',
        homeScore: 90,
        awayScore: 85,
        status: GameStatsStatus.submitted,
        entryMode: GameStatsEntryMode.postGame,
        playerLines: {
          'p1': PlayerStatLine(name: 'Alice', teamId: 'home', pts: 20),
        },
      );

      final map = model.toFirestore();

      expect(map['eventId'], 'ev1');
      expect(map['seasonId'], 's1');
      expect(map['homeScore'], 90);
      expect(map['awayScore'], 85);
      expect(map['status'], 'submitted');
      expect(map['entryMode'], 'postGame');
      expect(map['homeTeamName'], 'Home Team');
      expect(map['awayTeamName'], 'Away Team');
      expect(map['playerLines'], isA<Map<String, dynamic>>());
      expect((map['playerLines'] as Map)['p1']['pts'], 20);
    });

    test('toFirestore omits entryMode when not set', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
      );

      final map = model.toFirestore();

      expect(map.containsKey('entryMode'), isFalse);
    });

    test('toFirestore encodes null timestamps as null', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
      );

      final map = model.toFirestore();
      expect(map['submittedAt'], isNull);
      expect(map['approvedAt'], isNull);
      expect(map['submittedBy'], isNull);
      expect(map['approvedBy'], isNull);
    });

    test('default status is draft', () {
      const model = GameStatsModel(
        id: 'g1',
        eventId: 'g1',
        seasonId: 's1',
        divisionId: 'd1',
        homeTeamId: 'home',
        awayTeamId: 'away',
        homeTeamName: 'Home',
        awayTeamName: 'Away',
      );

      expect(model.status, GameStatsStatus.notStarted);
    });

    test('GameStatsStatus enum has expected values', () {
      expect(GameStatsStatus.values.length, 5);
      expect(GameStatsStatus.values, contains(GameStatsStatus.notStarted));
      expect(GameStatsStatus.values, contains(GameStatsStatus.inProgress));
      expect(GameStatsStatus.values, contains(GameStatsStatus.submitted));
      expect(GameStatsStatus.values, contains(GameStatsStatus.approved));
      expect(GameStatsStatus.values, contains(GameStatsStatus.rejected));
    });
  });
}
