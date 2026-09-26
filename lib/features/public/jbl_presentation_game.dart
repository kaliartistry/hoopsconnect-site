import '../../models/public_league_snapshot.dart';
import 'complete_game_example.dart';

/// Meeting-only completion of partial reports. Pure, deterministic and never
/// persisted, aggregated into season totals, or substituted for source records.
PublicGame completeJblPresentationGame(
  PublicGame source,
  PublicLeagueSnapshot snapshot,
) {
  final lines = <PublicPlayerGameLine>[];
  for (final side in [0, 1]) {
    final teamId = side == 0 ? source.homeTeamId! : source.awayTeamId!;
    final teamName = side == 0 ? source.homeTeamName! : source.awayTeamName!;
    final finalScore = side == 0 ? source.homeScore! : source.awayScore!;
    final roster = snapshot.leaderboards
        .where((b) => b.category == 'ppg')
        .expand((b) => b.rankings)
        .where((p) => p.teamId == teamId)
        .toList();
    final performers = <Map<String, Object>>[];
    var inTeam = false;
    for (final text in (source.recap ?? '').split('\n')) {
      if (text == teamName) {
        inTeam = true;
        continue;
      }
      if (text == source.homeTeamName || text == source.awayTeamName) {
        inTeam = false;
        continue;
      }
      if (!inTeam || !text.contains(': ')) continue;
      final parts = text.split(': ');
      final stats = <String, Object>{'name': parts.first};
      for (final match in RegExp(
        r'(\d+) (PTS|REB|AST|STL|BLK)',
      ).allMatches(parts.last)) {
        stats[match.group(2)!] = int.parse(match.group(1)!);
      }
      if (stats['PTS'] is int) performers.add(stats);
    }
    final suppliedPoints = performers.fold<int>(
      0,
      (sum, p) => sum + (p['PTS'] as int),
    );
    if (suppliedPoints > finalScore) return source;
    String identity(String name) =>
        name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    bool resembles(String a, String b) {
      final x = identity(a), y = identity(b);
      return x == y ||
          (x.length > 5 &&
              y.length > 5 &&
              x.substring(0, 3) == y.substring(0, 3) &&
              x.substring(x.length - 4) == y.substring(y.length - 4));
    }

    for (final player in roster) {
      if (performers.length >= 10) break;
      if (performers.any(
        (p) => resembles(p['name'] as String, player.displayName),
      )) {
        continue;
      }
      performers.add({'name': player.displayName, 'PTS': 0, 'fill': true});
    }
    final fillers = performers.where((p) => p['fill'] == true).toList();
    if (fillers.isEmpty && suppliedPoints != finalScore) return source;
    for (
      var remaining = finalScore - suppliedPoints, i = 0;
      remaining > 0;
      remaining--, i++
    ) {
      final row = fillers[i % fillers.length];
      row['PTS'] = (row['PTS'] as int) + 1;
    }
    for (var i = 0; i < performers.length; i++) {
      final p = performers[i];
      final name = p['name'] as String;
      final points = p['PTS'] as int;
      final rebounds = p['REB'] as int? ?? (3 + i % 5);
      final threeMade = points ~/ 9;
      final ftMade = (points - threeMade * 3) % 2 + (points >= 8 ? 2 : 0);
      final twoMade = (points - threeMade * 3 - ftMade) ~/ 2;
      final matching = roster
          .where((r) => resembles(name, r.displayName))
          .firstOrNull;
      lines.add(
        PublicPlayerGameLine(
          playerId: matching?.playerId ?? 'presentation-$teamId-$i',
          displayName: matching?.displayName ?? name,
          teamId: teamId,
          minutes:
              200 ~/ performers.length + (i < 200 % performers.length ? 1 : 0),
          points: points,
          offensiveRebounds: rebounds ~/ 3,
          defensiveRebounds: rebounds - rebounds ~/ 3,
          assists: p['AST'] as int? ?? i % 4,
          steals: p['STL'] as int? ?? i % 2,
          blocks: p['BLK'] as int? ?? (i % 4 == 0 ? 1 : 0),
          turnovers: 1 + i % 3,
          fouls: 1 + i % 4,
          twoPointMade: twoMade,
          twoPointAttempted: twoMade + 2 + i % 3,
          threePointMade: threeMade,
          threePointAttempted: threeMade + i % 3,
          freeThrowMade: ftMade,
          freeThrowAttempted: ftMade + (i % 3 == 0 ? 1 : 0),
        ),
      );
    }
  }
  final periods = source.periodScores.isNotEmpty
      ? source.periodScores
      : presentationQuarterScores(source);
  return PublicGame(
    gameId: source.gameId,
    title: source.title,
    startTime: source.startTime,
    dateOnly: source.dateOnly,
    venue: source.venue,
    divisionId: source.divisionId,
    homeTeamId: source.homeTeamId,
    homeTeamName: source.homeTeamName,
    awayTeamId: source.awayTeamId,
    awayTeamName: source.awayTeamName,
    homeScore: source.homeScore,
    awayScore: source.awayScore,
    status: source.status,
    periodScores: periods,
    playerLines: lines,
    recap:
        'Final: ${source.homeTeamName} ${source.homeScore}, ${source.awayTeamName} ${source.awayScore}.',
  ).withComputedResultVersion();
}
