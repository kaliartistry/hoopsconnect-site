import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/game_stats_model.dart';
import 'package:hoops_connect/services/milestone_detector.dart';

void main() {
  /// Helper to create a PlayerStatLine with given stats.
  PlayerStatLine makeLine({
    int pts = 0,
    int oreb = 0,
    int dreb = 0,
    int ast = 0,
    int stl = 0,
    int blk = 0,
  }) {
    return PlayerStatLine(
      name: 'Player',
      teamId: 'team1',
      pts: pts,
      oreb: oreb,
      dreb: dreb,
      ast: ast,
      stl: stl,
      blk: blk,
    );
  }

  group('MilestoneDetector.detectGameMilestones', () {
    test('20+ PTS detection', () {
      final line = makeLine(pts: 22);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('20+ PTS'));
      expect(milestones, isNot(contains('30+ PTS')));
    });

    test('exactly 20 PTS triggers 20+ PTS', () {
      final line = makeLine(pts: 20);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('20+ PTS'));
    });

    test('30+ PTS detection (replaces 20+ PTS)', () {
      final line = makeLine(pts: 35);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('30+ PTS'));
      // 30+ replaces 20+ due to else-if
      expect(milestones, isNot(contains('20+ PTS')));
    });

    test('exactly 30 PTS triggers 30+ PTS', () {
      final line = makeLine(pts: 30);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('30+ PTS'));
    });

    test('10+ REB detection', () {
      final line = makeLine(oreb: 4, dreb: 6); // reb = 10
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('10+ REB'));
    });

    test('10+ AST detection', () {
      final line = makeLine(ast: 12);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('10+ AST'));
    });

    test('5+ STL detection', () {
      final line = makeLine(stl: 5);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('5+ STL'));
    });

    test('5+ BLK detection', () {
      final line = makeLine(blk: 7);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('5+ BLK'));
    });

    test('Double-Double: pts + reb', () {
      final line = makeLine(pts: 15, oreb: 3, dreb: 8); // reb = 11
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Double-Double'));
      expect(milestones, isNot(contains('Triple-Double')));
    });

    test('Double-Double: pts + ast', () {
      final line = makeLine(pts: 18, ast: 11);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Double-Double'));
    });

    test('Double-Double: reb + ast', () {
      final line = makeLine(oreb: 5, dreb: 7, ast: 10); // reb=12
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Double-Double'));
    });

    test('Triple-Double: pts + reb + ast', () {
      final line = makeLine(pts: 20, oreb: 4, dreb: 6, ast: 10);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Triple-Double'));
      // Triple-Double replaces Double-Double
      expect(milestones, isNot(contains('Double-Double')));
    });

    test('no milestones for average stats', () {
      final line = makeLine(pts: 8, oreb: 1, dreb: 2, ast: 3, stl: 1, blk: 0);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, isEmpty);
    });

    test('no milestones for zero stats', () {
      final line = makeLine();
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, isEmpty);
    });

    test('multiple milestones in one game', () {
      final line = makeLine(pts: 32, oreb: 5, dreb: 6, ast: 11, stl: 5);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('30+ PTS'));
      expect(milestones, contains('10+ REB'));
      expect(milestones, contains('10+ AST'));
      expect(milestones, contains('5+ STL'));
      expect(milestones, contains('Triple-Double'));
    });

    test('4 STL does not trigger 5+ STL', () {
      final line = makeLine(stl: 4);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, isNot(contains('5+ STL')));
    });

    test('19 PTS does not trigger 20+ PTS', () {
      final line = makeLine(pts: 19);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, isNot(contains('20+ PTS')));
    });

    test('9 REB does not trigger 10+ REB', () {
      final line = makeLine(oreb: 4, dreb: 5); // reb = 9
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, isNot(contains('10+ REB')));
    });

    test('double-double with stl >= 10', () {
      final line = makeLine(pts: 15, stl: 10);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Double-Double'));
      expect(milestones, contains('5+ STL'));
    });

    test('double-double with blk >= 10', () {
      final line = makeLine(pts: 12, blk: 10);
      final milestones = MilestoneDetector.detectGameMilestones(line);
      expect(milestones, contains('Double-Double'));
      expect(milestones, contains('5+ BLK'));
    });
  });
}
