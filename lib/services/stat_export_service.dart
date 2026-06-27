import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_stats_model.dart';
import '../models/leaderboard_model.dart';
import '../models/player_season_stats_model.dart';

class StatExportService {
  /// Format a box score as copyable text.
  static String formatBoxScore(GameStatsModel stats) {
    final buf = StringBuffer();

    // Header
    buf.writeln('${stats.homeTeamName} ${stats.homeScore} - ${stats.awayTeamName} ${stats.awayScore}');
    buf.writeln(stats.status == GameStatsStatus.approved ? 'FINAL' : stats.status.name.toUpperCase());
    buf.writeln();

    final homePlayers = stats.playerLines.entries
        .where((e) => e.value.teamId == stats.homeTeamId)
        .toList();
    final awayPlayers = stats.playerLines.entries
        .where((e) => e.value.teamId == stats.awayTeamId)
        .toList();

    _writeTeamTable(buf, stats.homeTeamName, homePlayers);
    buf.writeln();
    _writeTeamTable(buf, stats.awayTeamName, awayPlayers);

    return buf.toString();
  }

  static void _writeTeamTable(
    StringBuffer buf,
    String teamName,
    List<MapEntry<String, PlayerStatLine>> players,
  ) {
    buf.writeln(teamName);
    buf.writeln(_padRight('Player', 18) +
        _padCenter('MIN', 5) +
        _padCenter('PTS', 5) +
        _padCenter('REB', 5) +
        _padCenter('AST', 5) +
        _padCenter('STL', 5) +
        _padCenter('BLK', 5) +
        _padCenter('FLS', 5));
    buf.writeln('-' * 53);

    int totalMin = 0, totalPts = 0, totalReb = 0, totalAst = 0;
    int totalStl = 0, totalBlk = 0, totalFls = 0;

    for (final entry in players) {
      final p = entry.value;
      totalMin += p.min;
      totalPts += p.pts;
      totalReb += p.reb;
      totalAst += p.ast;
      totalStl += p.stl;
      totalBlk += p.blk;
      totalFls += p.fls;

      buf.writeln(_padRight(p.name, 18) +
          _padCenter('${p.min}', 5) +
          _padCenter('${p.pts}', 5) +
          _padCenter('${p.reb}', 5) +
          _padCenter('${p.ast}', 5) +
          _padCenter('${p.stl}', 5) +
          _padCenter('${p.blk}', 5) +
          _padCenter('${p.fls}', 5));
    }

    buf.writeln('-' * 53);
    buf.writeln(_padRight('TOTAL', 18) +
        _padCenter('$totalMin', 5) +
        _padCenter('$totalPts', 5) +
        _padCenter('$totalReb', 5) +
        _padCenter('$totalAst', 5) +
        _padCenter('$totalStl', 5) +
        _padCenter('$totalBlk', 5) +
        _padCenter('$totalFls', 5));
  }

  /// Format leaderboard as text.
  static String formatLeaderboard(
    List<LeaderboardEntry> entries,
    String category,
  ) {
    final buf = StringBuffer();

    final label = _categoryLabel(category);
    buf.writeln('$label Leaders');
    buf.writeln('=' * 30);

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.writeln('${i + 1}. ${e.name} (${e.teamName}) - ${e.value.toStringAsFixed(1)}');
    }

    return buf.toString();
  }

  /// Format player card as text.
  static String formatPlayerCard(PlayerSeasonStatsModel stats) {
    final buf = StringBuffer();

    buf.writeln(stats.playerName);
    buf.writeln('${stats.teamName ?? 'Unknown Team'} | GP: ${stats.gamesPlayed}');
    buf.writeln();
    buf.writeln('Season Averages');
    buf.writeln('-' * 25);
    buf.writeln('PPG: ${stats.ppg.toStringAsFixed(1)}');
    buf.writeln('RPG: ${stats.rpg.toStringAsFixed(1)}');
    buf.writeln('APG: ${stats.apg.toStringAsFixed(1)}');
    buf.writeln('SPG: ${stats.spg.toStringAsFixed(1)}');
    buf.writeln('BPG: ${stats.bpg.toStringAsFixed(1)}');

    return buf.toString();
  }

  /// Copy to clipboard and show a snackbar.
  static void copyToClipboard(String text, BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  // -- helpers --

  static String _padRight(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }

  static String _padCenter(String s, int width) {
    if (s.length >= width) return s;
    final left = (width - s.length) ~/ 2;
    final right = width - s.length - left;
    return ' ' * left + s + ' ' * right;
  }

  static String _categoryLabel(String category) {
    switch (category) {
      case 'ppg':
        return 'PPG';
      case 'rpg':
        return 'RPG';
      case 'apg':
        return 'APG';
      case 'spg':
        return 'SPG';
      case 'bpg':
        return 'BPG';
      default:
        return category.toUpperCase();
    }
  }
}
