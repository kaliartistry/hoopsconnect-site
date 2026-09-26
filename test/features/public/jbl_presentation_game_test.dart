import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/public/jbl_presentation_game.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

void main() {
  final sourceFile = File(
    '.local/jbl-live-migration/backup-S0o7LA/hoopsconnect-jba-staging-game-results-plan.json',
  );
  test(
    'all imported presentation games reconcile without changing source records',
    () {
      final input =
          jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;
      final snapshot = PublicLeagueSnapshot.fromMap(
        input['snapshot'] as Map<String, dynamic>,
      );
      final games = snapshot.schedule
          .where((g) => g.gameId.startsWith('jbl-2025-'))
          .toList();
      expect(games.length, 46);
      for (final source in games) {
        final original = jsonEncode(source.resultContent);
        final game = completeJblPresentationGame(source, snapshot);
        expect(game.playerLines, isNotEmpty, reason: source.gameId);
        expect(game.hasVersionedResult, isTrue);
        for (final team in [source.homeTeamId, source.awayTeamId]) {
          final lines = game.playerLines
              .where((p) => p.teamId == team)
              .toList();
          expect(
            lines.fold<int>(0, (sum, p) => sum + p.points!),
            team == source.homeTeamId ? source.homeScore : source.awayScore,
          );
          expect(lines.fold<int>(0, (sum, p) => sum + p.minutes!), 200);
          for (final line in lines) {
            expect(
              line.twoPointMade! * 2 +
                  line.threePointMade! * 3 +
                  line.freeThrowMade!,
              line.points,
            );
            expect(line.twoPointMade! <= line.twoPointAttempted!, isTrue);
            expect(line.threePointMade! <= line.threePointAttempted!, isTrue);
            expect(line.freeThrowMade! <= line.freeThrowAttempted!, isTrue);
          }
        }
        expect(
          game.periodScores.fold<int>(0, (sum, p) => sum + p.homeScore),
          game.homeScore,
        );
        expect(
          game.periodScores.fold<int>(0, (sum, p) => sum + p.awayScore),
          game.awayScore,
        );
        expect(jsonEncode(source.resultContent), original);
        expect(source.playerLines, isEmpty);
      }
    },
    skip: !sourceFile.existsSync()
        ? 'Local supplied reports are not checked into Git'
        : false,
  );
}
