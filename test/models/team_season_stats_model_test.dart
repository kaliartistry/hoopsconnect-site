import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/team_season_stats_model.dart';

void main() {
  // ─────────────────────── TeamGameLog ───────────────────────

  group('TeamGameLog', () {
    test('fromMap parses all fields including opponentTeamId', () {
      final map = {
        'eventId': 'e1',
        'opponentName': 'Strikers',
        'opponentTeamId': 'team_strikers',
        'date': Timestamp.fromDate(DateTime(2025, 1, 15)),
        'pts': 85,
        'oreb': 10,
        'dreb': 25,
        'reb': 35,
        'ast': 20,
        'stl': 8,
        'blk': 3,
        'to': 12,
        'fls': 15,
        'result': 'W',
      };

      final log = TeamGameLog.fromMap(map);

      expect(log.eventId, 'e1');
      expect(log.opponentName, 'Strikers');
      expect(log.opponentTeamId, 'team_strikers');
      expect(log.pts, 85);
      expect(log.reb, 35);
      expect(log.result, 'W');
    });

    test('fromMap handles missing opponentTeamId (legacy data)', () {
      final map = {
        'eventId': 'e1',
        'opponentName': 'Strikers',
        'date': Timestamp.fromDate(DateTime(2025, 1, 15)),
        'pts': 80,
        'result': 'L',
      };

      final log = TeamGameLog.fromMap(map);

      expect(log.opponentTeamId, isNull);
      expect(log.opponentName, 'Strikers');
    });

    test('toMap includes opponentTeamId when present', () {
      final log = TeamGameLog(
        eventId: 'e1',
        opponentName: 'Strikers',
        opponentTeamId: 'team_strikers',
        date: DateTime(2025, 1, 15),
        pts: 85,
        result: 'W',
      );

      final map = log.toMap();

      expect(map['opponentTeamId'], 'team_strikers');
      expect(map['opponentName'], 'Strikers');
    });

    test('toMap omits opponentTeamId when null', () {
      final log = TeamGameLog(
        eventId: 'e1',
        opponentName: 'Strikers',
        date: DateTime(2025, 1, 15),
        pts: 85,
        result: 'W',
      );

      final map = log.toMap();

      expect(map.containsKey('opponentTeamId'), isFalse);
    });

    test('copyWith preserves opponentTeamId', () {
      final log = TeamGameLog(
        eventId: 'e1',
        opponentName: 'Strikers',
        opponentTeamId: 'team_strikers',
        date: DateTime(2025, 1, 15),
        pts: 85,
        result: 'W',
      );

      final updated = log.copyWith(pts: 90);

      expect(updated.pts, 90);
      expect(updated.opponentTeamId, 'team_strikers');
      expect(updated.opponentName, 'Strikers');
    });

    test('copyWith can override opponentTeamId', () {
      final log = TeamGameLog(
        eventId: 'e1',
        opponentName: 'Strikers',
        date: DateTime(2025, 1, 15),
        pts: 85,
        result: 'W',
      );

      final updated = log.copyWith(opponentTeamId: 'new_id');

      expect(updated.opponentTeamId, 'new_id');
    });

    test('toMap round-trips through fromMap', () {
      final original = TeamGameLog(
        eventId: 'e1',
        opponentName: 'Strikers',
        opponentTeamId: 'team_strikers',
        date: DateTime(2025, 1, 15),
        pts: 85,
        oreb: 10,
        dreb: 25,
        reb: 35,
        ast: 20,
        stl: 8,
        blk: 3,
        to: 12,
        fls: 15,
        result: 'W',
      );

      final restored = TeamGameLog.fromMap(original.toMap());

      expect(restored.eventId, original.eventId);
      expect(restored.opponentName, original.opponentName);
      expect(restored.opponentTeamId, original.opponentTeamId);
      expect(restored.pts, original.pts);
      expect(restored.reb, original.reb);
      expect(restored.ast, original.ast);
      expect(restored.result, original.result);
    });
  });

  // ─────────────────────── TeamStatTotals ───────────────────────

  group('TeamStatTotals', () {
    test('fromMap parses all fields with defaults', () {
      final totals = TeamStatTotals.fromMap({
        'pts': 500,
        'reb': 200,
        'ast': 120,
      });

      expect(totals.pts, 500);
      expect(totals.reb, 200);
      expect(totals.ast, 120);
      expect(totals.stl, 0); // default
      expect(totals.blk, 0); // default
    });
  });

  // ─────────────────────── TeamStatAverages ──────────────────────

  group('TeamStatAverages', () {
    test('fromMap parses all average fields', () {
      final avg = TeamStatAverages.fromMap({
        'ppg': 85.5,
        'rpg': 40.0,
        'apg': 22.3,
        'spg': 8.1,
        'bpg': 3.2,
        'topg': 12.4,
        'fpg': 15.0,
      });

      expect(avg.ppg, 85.5);
      expect(avg.rpg, 40.0);
      expect(avg.topg, 12.4);
      expect(avg.fpg, 15.0);
    });
  });

  // ─────────────────────── TeamSeasonStats ──────────────────────

  group('TeamSeasonStats', () {
    test('constructor and fields work with new opponentTeamId in gameLog', () {
      final stats = TeamSeasonStats(
        id: 'team1_s1',
        teamId: 'team1',
        teamName: 'Warriors',
        seasonId: 's1',
        divisionId: 'd1',
        gamesPlayed: 5,
        totals: TeamStatTotals.fromMap({
          'pts': 400,
          'oreb': 50,
          'dreb': 120,
          'reb': 170,
          'ast': 100,
          'stl': 40,
          'blk': 15,
          'to': 60,
          'fls': 75,
        }),
        averages: TeamStatAverages.fromMap({
          'ppg': 80.0,
          'rpg': 34.0,
          'apg': 20.0,
          'spg': 8.0,
          'bpg': 3.0,
          'topg': 12.0,
          'fpg': 15.0,
        }),
        gameLog: [
          TeamGameLog.fromMap({
            'eventId': 'e1',
            'opponentName': 'Strikers',
            'opponentTeamId': 'team_strikers',
            'date': Timestamp.fromDate(DateTime(2025, 1, 15)),
            'pts': 85,
            'oreb': 10,
            'dreb': 25,
            'reb': 35,
            'ast': 20,
            'stl': 8,
            'blk': 3,
            'to': 12,
            'fls': 15,
            'result': 'W',
          }),
        ],
      );

      expect(stats.id, 'team1_s1');
      expect(stats.teamName, 'Warriors');
      expect(stats.gamesPlayed, 5);
      expect(stats.totals.pts, 400);
      expect(stats.averages.ppg, 80.0);
      expect(stats.gameLog.length, 1);
      expect(stats.gameLog.first.opponentTeamId, 'team_strikers');
    });

    test('handles empty gameLog', () {
      final stats = TeamSeasonStats(
        id: 'team1_s1',
        teamId: 'team1',
        teamName: 'Warriors',
        seasonId: 's1',
        gamesPlayed: 0,
      );

      expect(stats.gameLog, isEmpty);
      expect(stats.gamesPlayed, 0);
    });
  });
}
