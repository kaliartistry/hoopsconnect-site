import '../../models/game_stats_model.dart';

/// Pre-submission validation for game stats — wireframe §02-A2.
///
/// Returns a list of human-readable error messages. Empty list means valid.
/// All callers must block submission when the list is non-empty.
class StatsValidator {
  StatsValidator._();

  /// Hard caps that catch fat-finger mistakes without blocking edge cases.
  static const _maxMin = 48;
  static const _maxPts = 100;
  static const _maxFls = 5;
  static const _maxReb = 50;
  static const _maxAst = 50;
  static const _maxStl = 20;
  static const _maxBlk = 20;
  static const _maxTeamMin = 240; // 5 players × 48 minutes

  static List<String> validate(GameStatsModel stats) {
    final errors = <String>[];
    int homeMin = 0;
    int awayMin = 0;

    for (final line in stats.playerLines.values) {
      // Negatives — guards against bad data shape, not user input directly.
      final negStat = _firstNegative(line);
      if (negStat != null) {
        errors.add('${line.name}: $negStat cannot be negative.');
      }

      if (line.min > _maxMin) {
        errors.add('${line.name}: MIN must be 0–$_maxMin.');
      }
      if (line.pts > _maxPts) {
        errors.add('${line.name}: PTS must be 0–$_maxPts.');
      }
      if (line.fls > _maxFls) {
        errors.add(
          '${line.name}: FLS must be 0–$_maxFls — player would have fouled out.',
        );
      }
      if (line.reb > _maxReb) {
        errors.add('${line.name}: REB must be 0–$_maxReb.');
      }
      if (line.ast > _maxAst) {
        errors.add('${line.name}: AST must be 0–$_maxAst.');
      }
      if (line.stl > _maxStl) {
        errors.add('${line.name}: STL must be 0–$_maxStl.');
      }
      if (line.blk > _maxBlk) {
        errors.add('${line.name}: BLK must be 0–$_maxBlk.');
      }

      if (line.teamId == stats.homeTeamId) {
        homeMin += line.min;
      } else if (line.teamId == stats.awayTeamId) {
        awayMin += line.min;
      }
    }

    if (homeMin > _maxTeamMin) {
      errors.add(
        '${stats.homeTeamName} total MIN ($homeMin) exceeds $_maxTeamMin '
        '(5 players × 48 minutes).',
      );
    }
    if (awayMin > _maxTeamMin) {
      errors.add(
        '${stats.awayTeamName} total MIN ($awayMin) exceeds $_maxTeamMin '
        '(5 players × 48 minutes).',
      );
    }

    return errors;
  }

  static String? _firstNegative(PlayerStatLine line) {
    if (line.min < 0) return 'MIN';
    if (line.pts < 0) return 'PTS';
    if (line.oreb < 0) return 'OREB';
    if (line.dreb < 0) return 'DREB';
    if (line.ast < 0) return 'AST';
    if (line.stl < 0) return 'STL';
    if (line.blk < 0) return 'BLK';
    if (line.fls < 0) return 'FLS';
    return null;
  }
}
