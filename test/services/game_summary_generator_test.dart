import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/game_stats_model.dart';
import 'package:hoops_connect/services/game_summary_generator.dart';

void main() {
  /// Helper to create a GameStatsModel with given scores and player lines.
  GameStatsModel makeGame({
    int homeScore = 80,
    int awayScore = 70,
    String homeTeamName = 'Kingston Titans',
    String awayTeamName = 'Montego Bay Storm',
    String homeTeamId = 'home1',
    String awayTeamId = 'away1',
    Map<String, PlayerStatLine>? playerLines,
  }) {
    return GameStatsModel(
      id: 'game1',
      eventId: 'event1',
      seasonId: 'season1',
      divisionId: 'div1',
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeTeamName: homeTeamName,
      awayTeamName: awayTeamName,
      homeScore: homeScore,
      awayScore: awayScore,
      playerLines: playerLines ?? {},
    );
  }

  PlayerStatLine makeLine({
    required String name,
    required String teamId,
    int pts = 0,
    int oreb = 0,
    int dreb = 0,
    int ast = 0,
    int stl = 0,
    int blk = 0,
  }) {
    return PlayerStatLine(
      name: name,
      teamId: teamId,
      pts: pts,
      oreb: oreb,
      dreb: dreb,
      ast: ast,
      stl: stl,
      blk: blk,
    );
  }

  // ─────────────────────── Headline generation ───────────────────────

  group('generateHeadline', () {
    test('blowout (margin > 24) uses "rout"', () {
      final game = makeGame(homeScore: 100, awayScore: 70);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('rout'));
      expect(headline, contains('Kingston Titans'));
      expect(headline, contains('100-70'));
    });

    test('large margin (15-24) uses "overcome"', () {
      final game = makeGame(homeScore: 90, awayScore: 72);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('overcome'));
    });

    test('normal margin (8-14) uses "defeat"', () {
      final game = makeGame(homeScore: 87, awayScore: 77);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('defeat'));
    });

    test('moderate margin (4-7) uses "hold off"', () {
      final game = makeGame(homeScore: 80, awayScore: 75);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('hold off'));
    });

    test('close game (margin <= 3) uses "edge"', () {
      final game = makeGame(homeScore: 78, awayScore: 76);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('edge'));
    });

    test('margin of exactly 1 uses "edge"', () {
      final game = makeGame(homeScore: 71, awayScore: 70);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('edge'));
    });

    test('away team winning appears as winner first', () {
      final game = makeGame(homeScore: 60, awayScore: 90);
      final headline = GameSummaryGenerator.generateHeadline(game);
      // Away team won by 30 -> rout
      expect(headline, startsWith('Montego Bay Storm rout'));
      expect(headline, contains('90-60'));
    });

    test('tied game', () {
      final game = makeGame(homeScore: 75, awayScore: 75);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(headline, contains('tied'));
      expect(headline, contains('75-75'));
    });
  });

  // ─────────────────────── Narrative generation ───────────────────────

  group('generateNarrative', () {
    test('includes top scorer name and points', () {
      final game = makeGame(
        homeScore: 85,
        awayScore: 72,
        playerLines: {
          'p1': makeLine(
              name: 'Marcus Johnson', teamId: 'home1', pts: 28, dreb: 5),
          'p2': makeLine(
              name: 'Devon Brown', teamId: 'away1', pts: 18, dreb: 3),
        },
      );
      final narrative = GameSummaryGenerator.generateNarrative(game);
      expect(narrative, contains('Marcus Johnson'));
      expect(narrative, contains('28 points'));
    });

    test('narrative mentions losing team top performer', () {
      final game = makeGame(
        homeScore: 85,
        awayScore: 72,
        playerLines: {
          'p1': makeLine(name: 'Marcus Johnson', teamId: 'home1', pts: 28),
          'p2': makeLine(name: 'Devon Brown', teamId: 'away1', pts: 22),
        },
      );
      final narrative = GameSummaryGenerator.generateNarrative(game);
      expect(narrative, contains('Devon Brown'));
      expect(narrative, contains('22 points'));
      expect(narrative, contains('losing effort'));
    });

    test('empty player lines falls back to headline', () {
      final game = makeGame(homeScore: 80, awayScore: 70);
      final narrative = GameSummaryGenerator.generateNarrative(game);
      final headline = GameSummaryGenerator.generateHeadline(game);
      expect(narrative, headline);
    });

    test('uses past-tense verb in narrative', () {
      final game = makeGame(
        homeScore: 100,
        awayScore: 70,
        playerLines: {
          'p1': makeLine(name: 'Player A', teamId: 'home1', pts: 30),
        },
      );
      final narrative = GameSummaryGenerator.generateNarrative(game);
      // margin 30 -> "routed"
      expect(narrative, contains('routed'));
    });
  });

  // ─────────────────────── Top performers ───────────────────────

  group('getTopPerformers', () {
    test('returns empty for no player lines', () {
      final game = makeGame();
      expect(GameSummaryGenerator.getTopPerformers(game), isEmpty);
    });

    test('returns correct ordering by points', () {
      final game = makeGame(
        playerLines: {
          'p1': makeLine(name: 'Low', teamId: 'home1', pts: 5),
          'p2': makeLine(name: 'Mid', teamId: 'home1', pts: 15),
          'p3': makeLine(name: 'High', teamId: 'away1', pts: 25),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      expect(performers.first.name, 'High');
      expect(performers.first.pts, 25);
    });

    test('top 3 scorers are included', () {
      final game = makeGame(
        playerLines: {
          'p1': makeLine(name: 'A', teamId: 'home1', pts: 30),
          'p2': makeLine(name: 'B', teamId: 'home1', pts: 20),
          'p3': makeLine(name: 'C', teamId: 'away1', pts: 15),
          'p4': makeLine(name: 'D', teamId: 'away1', pts: 10),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      final names = performers.map((p) => p.name).toList();
      expect(names, contains('A'));
      expect(names, contains('B'));
      expect(names, contains('C'));
    });

    test('top rebounder included if not already in top 3 scorers', () {
      final game = makeGame(
        playerLines: {
          'p1': makeLine(name: 'Scorer1', teamId: 'home1', pts: 25),
          'p2': makeLine(name: 'Scorer2', teamId: 'home1', pts: 20),
          'p3': makeLine(name: 'Scorer3', teamId: 'away1', pts: 18),
          'p4': makeLine(
              name: 'Rebounder', teamId: 'away1', pts: 5, oreb: 5, dreb: 10),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      final names = performers.map((p) => p.name).toList();
      expect(names, contains('Rebounder'));
    });

    test('top assist leader included if unique', () {
      final game = makeGame(
        playerLines: {
          'p1': makeLine(name: 'Scorer1', teamId: 'home1', pts: 25),
          'p2': makeLine(name: 'Scorer2', teamId: 'home1', pts: 20),
          'p3': makeLine(name: 'Scorer3', teamId: 'away1', pts: 18),
          'p4': makeLine(name: 'Playmaker', teamId: 'away1', pts: 4, ast: 12),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      final names = performers.map((p) => p.name).toList();
      expect(names, contains('Playmaker'));
    });

    test('minimal data: 1 player per team', () {
      final game = makeGame(
        homeScore: 60,
        awayScore: 55,
        playerLines: {
          'p1': makeLine(name: 'HomeGuy', teamId: 'home1', pts: 20),
          'p2': makeLine(name: 'AwayGuy', teamId: 'away1', pts: 15),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      expect(performers.length, 2);
      expect(performers.first.name, 'HomeGuy');
    });

    test('deduplicates players across categories', () {
      // If the top scorer is also the top rebounder and assister,
      // they should appear only once.
      final game = makeGame(
        playerLines: {
          'p1': makeLine(
            name: 'AllStar',
            teamId: 'home1',
            pts: 30,
            oreb: 5,
            dreb: 10,
            ast: 10,
          ),
        },
      );
      final performers = GameSummaryGenerator.getTopPerformers(game);
      expect(performers.length, 1);
      expect(performers.first.name, 'AllStar');
    });
  });

  // ─────────────────────── TopPerformer.statLine ───────────────────────

  group('TopPerformer.statLine', () {
    test('formats non-zero stats correctly', () {
      const performer = TopPerformer(
        name: 'Test',
        teamId: 't1',
        teamName: 'Team',
        pts: 25,
        reb: 12,
        ast: 5,
        stl: 0,
        blk: 0,
      );
      expect(performer.statLine, '25 pts, 12 reb, 5 ast');
    });

    test('omits zero-value stats', () {
      const performer = TopPerformer(
        name: 'Test',
        teamId: 't1',
        teamName: 'Team',
        pts: 10,
        reb: 0,
        ast: 0,
        stl: 0,
        blk: 3,
      );
      expect(performer.statLine, '10 pts, 3 blk');
    });
  });
}
