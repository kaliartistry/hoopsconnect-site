import '../models/game_stats_model.dart';

/// Data class for a top performer extracted from game stats.
class TopPerformer {
  final String name;
  final String teamId;
  final String teamName;
  final int pts;
  final int reb;
  final int ast;
  final int stl;
  final int blk;

  const TopPerformer({
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.pts,
    required this.reb,
    required this.ast,
    required this.stl,
    required this.blk,
  });

  /// Summary stat line, e.g. "25 pts, 12 reb, 5 ast"
  String get statLine {
    final parts = <String>[];
    if (pts > 0) parts.add('$pts pts');
    if (reb > 0) parts.add('$reb reb');
    if (ast > 0) parts.add('$ast ast');
    if (stl > 0) parts.add('$stl stl');
    if (blk > 0) parts.add('$blk blk');
    return parts.join(', ');
  }
}

/// Generates press-ready game summaries from box score data.
class GameSummaryGenerator {
  GameSummaryGenerator._();

  /// Generate a headline like "Kingston Titans defeat Montego Bay Storm 87-72".
  static String generateHeadline(GameStatsModel stats) {
    final margin = (stats.homeScore - stats.awayScore).abs();
    final homeWon = stats.homeScore > stats.awayScore;
    final tied = stats.homeScore == stats.awayScore;

    if (tied) {
      return '${stats.homeTeamName} and ${stats.awayTeamName} '
          'tied ${stats.homeScore}-${stats.awayScore}';
    }

    final winner = homeWon ? stats.homeTeamName : stats.awayTeamName;
    final loser = homeWon ? stats.awayTeamName : stats.homeTeamName;
    final winScore = homeWon ? stats.homeScore : stats.awayScore;
    final loseScore = homeWon ? stats.awayScore : stats.homeScore;

    final verb = _victoryVerb(margin);
    return '$winner $verb $loser $winScore-$loseScore';
  }

  /// Generate a narrative paragraph describing the game.
  static String generateNarrative(GameStatsModel stats) {
    final performers = getTopPerformers(stats);
    if (performers.isEmpty) {
      return generateHeadline(stats);
    }

    final homeWon = stats.homeScore > stats.awayScore;
    final winnerTeamId = homeWon ? stats.homeTeamId : stats.awayTeamId;
    final winnerName = homeWon ? stats.homeTeamName : stats.awayTeamName;
    final loserName = homeWon ? stats.awayTeamName : stats.homeTeamName;
    final margin = (stats.homeScore - stats.awayScore).abs();
    final verb = _victoryVerb(margin, past: true);

    final buffer = StringBuffer();

    // Lead scorer for the winning team
    final winnerPerformers =
        performers.where((p) => p.teamId == winnerTeamId).toList();
    final loserPerformers =
        performers.where((p) => p.teamId != winnerTeamId).toList();

    if (winnerPerformers.isNotEmpty) {
      final star = winnerPerformers.first;
      buffer.write(
        '${star.name} led all scorers with ${star.pts} points '
        'as the $winnerName $verb the $loserName '
        '${stats.homeScore > stats.awayScore ? stats.homeScore : stats.awayScore}-'
        '${stats.homeScore > stats.awayScore ? stats.awayScore : stats.homeScore}. ',
      );

      // Second performer for the winning team
      if (winnerPerformers.length > 1) {
        final second = winnerPerformers[1];
        final extras = <String>[];
        if (second.reb >= 10) extras.add('${second.reb} rebounds');
        if (second.ast >= 5) extras.add('${second.ast} assists');
        final extraText =
            extras.isNotEmpty ? ' and ${extras.join(' and ')}' : '';
        buffer.write(
          '${second.name} added ${second.pts} points$extraText '
          'for the $winnerName. ',
        );
      }
    }

    // Top performer for the losing team
    if (loserPerformers.isNotEmpty) {
      final loserStar = loserPerformers.first;
      buffer.write(
        'For the $loserName, ${loserStar.name} had '
        '${loserStar.pts} points in the losing effort.',
      );
    }

    return buffer.toString().trim();
  }

  /// Generate a quarter score line, e.g. "Quarter scores: 25-20, 18-22, 22-18, 20-15".
  static String generateQuarterScoreLine(GameStatsModel stats) {
    if (stats.homeQuarterScores.isEmpty && stats.awayQuarterScores.isEmpty) {
      return '';
    }
    final quarters = <int>{
      ...stats.homeQuarterScores.keys,
      ...stats.awayQuarterScores.keys,
    }.toList()
      ..sort();

    if (quarters.isEmpty) return '';

    final parts = quarters.map((q) {
      final h = stats.homeQuarterScores[q] ?? 0;
      final a = stats.awayQuarterScores[q] ?? 0;
      return '$h-$a';
    }).join(', ');

    return 'Quarter scores (${stats.homeTeamName}-${stats.awayTeamName}): $parts';
  }

  /// Generate a narrative paragraph about quarter-level trends.
  /// Detects: wire-to-wire lead, comeback, largest quarter, close quarters.
  static String generateQuarterNarrative(GameStatsModel stats) {
    if (stats.homeQuarterScores.isEmpty && stats.awayQuarterScores.isEmpty) {
      return '';
    }

    final quarters = <int>{
      ...stats.homeQuarterScores.keys,
      ...stats.awayQuarterScores.keys,
    }.toList()
      ..sort();

    if (quarters.isEmpty) return '';

    final homeWon = stats.homeScore > stats.awayScore;
    final winnerName = homeWon ? stats.homeTeamName : stats.awayTeamName;

    // Build running totals
    int homeRunning = 0;
    int awayRunning = 0;
    bool winnerAlwaysLed = true;
    bool loserEverLed = false;
    int? comebackQuarter;
    int largestMarginQ = quarters.first;
    int largestMargin = 0;
    int? closestQ;
    int closestDiff = 999;

    for (final q in quarters) {
      final hq = stats.homeQuarterScores[q] ?? 0;
      final aq = stats.awayQuarterScores[q] ?? 0;
      homeRunning += hq;
      awayRunning += aq;

      final winnerRunning = homeWon ? homeRunning : awayRunning;
      final loserRunning = homeWon ? awayRunning : homeRunning;

      if (loserRunning > winnerRunning) {
        winnerAlwaysLed = false;
        loserEverLed = true;
      } else if (loserRunning == winnerRunning) {
        winnerAlwaysLed = false;
      }

      // Detect comeback: winner was behind but then took the lead
      if (loserEverLed && winnerRunning > loserRunning && comebackQuarter == null) {
        comebackQuarter = q;
      }

      // Quarter margin (for individual quarter scoring)
      final qMargin = (hq - aq).abs();
      if (qMargin > largestMargin) {
        largestMargin = qMargin;
        largestMarginQ = q;
      }

      // Closest quarter
      final qDiff = (hq - aq).abs();
      if (qDiff < closestDiff) {
        closestDiff = qDiff;
        closestQ = q;
      }
    }

    final buffer = StringBuffer();

    // Wire-to-wire lead
    if (winnerAlwaysLed && stats.homeScore != stats.awayScore) {
      final firstH = stats.homeQuarterScores[quarters.first] ?? 0;
      final firstA = stats.awayQuarterScores[quarters.first] ?? 0;
      buffer.write(
        'The $winnerName led $firstH-$firstA after the first quarter and never trailed. ',
      );
    }
    // Comeback narrative
    else if (comebackQuarter != null) {
      final qNames = ['', 'first', 'second', 'third', 'fourth'];
      final qName = comebackQuarter <= 4 ? qNames[comebackQuarter] : 'Q$comebackQuarter';
      buffer.write(
        'The $winnerName trailed early but took the lead in the $qName quarter. ',
      );
    }

    // Largest quarter margin
    if (largestMargin > 0) {
      final hq = stats.homeQuarterScores[largestMarginQ] ?? 0;
      final aq = stats.awayQuarterScores[largestMarginQ] ?? 0;
      final qNames = ['', 'first', 'second', 'third', 'fourth'];
      final qName = largestMarginQ <= 4 ? qNames[largestMarginQ] : 'Q$largestMarginQ';
      final higherTeam = hq > aq ? stats.homeTeamName : stats.awayTeamName;
      final lowerTeam = hq > aq ? stats.awayTeamName : stats.homeTeamName;
      final high = hq > aq ? hq : aq;
      final low = hq > aq ? aq : hq;
      buffer.write(
        'The $higherTeam outscored the $lowerTeam $high-$low in the $qName quarter. ',
      );
    }

    // Close quarter
    if (closestQ != null && closestDiff <= 2 && closestDiff < largestMargin) {
      final qNames = ['', 'first', 'second', 'third', 'fourth'];
      final qName = closestQ <= 4 ? qNames[closestQ] : 'Q$closestQ';
      buffer.write('The $qName quarter was tightly contested. ');
    }

    return buffer.toString().trim();
  }

  /// Combines headline + quarter line + narrative + top performers table.
  static String generateFullSummary(GameStatsModel stats) {
    final headline = generateHeadline(stats);
    final narrative = generateNarrative(stats);
    final quarterLine = generateQuarterScoreLine(stats);
    final quarterNarrative = generateQuarterNarrative(stats);
    final performers = getTopPerformers(stats);

    final buffer = StringBuffer();
    buffer.writeln(headline);
    if (quarterLine.isNotEmpty) {
      buffer.writeln(quarterLine);
    }
    buffer.writeln();
    buffer.writeln(narrative);
    if (quarterNarrative.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(quarterNarrative);
    }

    if (performers.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('TOP PERFORMERS');
      buffer.writeln('-' * 40);
      for (final p in performers) {
        buffer.writeln('${p.name} (${p.teamName}): ${p.statLine}');
      }
    }

    return buffer.toString().trim();
  }

  /// Top performers: top 3 scorers, top rebounder, top assist leader.
  /// Returns a deduplicated list ordered by points desc.
  static List<TopPerformer> getTopPerformers(GameStatsModel stats) {
    if (stats.playerLines.isEmpty) return [];

    final allPlayers = stats.playerLines.entries.map((e) {
      final line = e.value;
      // Determine which team name to use
      final teamName = line.teamId == stats.homeTeamId
          ? stats.homeTeamName
          : stats.awayTeamName;
      return TopPerformer(
        name: line.name,
        teamId: line.teamId,
        teamName: teamName,
        pts: line.pts,
        reb: line.reb,
        ast: line.ast,
        stl: line.stl,
        blk: line.blk,
      );
    }).toList();

    // Collect unique performers by name
    final seen = <String>{};
    final result = <TopPerformer>[];

    // Top 3 scorers
    final byPts = List<TopPerformer>.from(allPlayers)
      ..sort((a, b) => b.pts.compareTo(a.pts));
    for (final p in byPts.take(3)) {
      if (seen.add(p.name)) result.add(p);
    }

    // Top rebounder
    final byReb = List<TopPerformer>.from(allPlayers)
      ..sort((a, b) => b.reb.compareTo(a.reb));
    if (byReb.isNotEmpty && seen.add(byReb.first.name)) {
      result.add(byReb.first);
    }

    // Top assist leader
    final byAst = List<TopPerformer>.from(allPlayers)
      ..sort((a, b) => b.ast.compareTo(a.ast));
    if (byAst.isNotEmpty && seen.add(byAst.first.name)) {
      result.add(byAst.first);
    }

    return result;
  }

  /// Choose a verb based on margin of victory.
  static String _victoryVerb(int margin, {bool past = false}) {
    if (margin <= 3) return past ? 'edged' : 'edge';
    if (margin <= 7) return past ? 'held off' : 'hold off';
    if (margin <= 14) return past ? 'defeated' : 'defeat';
    if (margin <= 24) return past ? 'overcame' : 'overcome';
    return past ? 'routed' : 'rout';
  }

  /// Simple milestone checks for a single player stat line.
  static List<String> detectMilestones(PlayerStatLine line) {
    final milestones = <String>[];
    if (line.pts >= 30) milestones.add('30+ Point Game');
    if (line.pts >= 40) milestones.add('40+ Point Game');
    if (line.reb >= 15) milestones.add('15+ Rebound Game');
    if (line.ast >= 10) milestones.add('10+ Assist Game');

    // Double-double check
    final statCategories = [line.pts, line.reb, line.ast, line.stl, line.blk];
    final doubleDigits = statCategories.where((s) => s >= 10).length;
    if (doubleDigits >= 2) milestones.add('Double-Double');
    if (doubleDigits >= 3) milestones.add('Triple-Double');

    return milestones;
  }

  /// All milestones across all players in the game.
  static Map<String, List<String>> detectGameMilestones(GameStatsModel stats) {
    final result = <String, List<String>>{};
    for (final entry in stats.playerLines.entries) {
      final milestones = detectMilestones(entry.value);
      if (milestones.isNotEmpty) {
        result[entry.value.name] = milestones;
      }
    }
    return result;
  }
}
