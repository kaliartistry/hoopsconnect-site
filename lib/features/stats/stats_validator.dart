import '../../models/game_stats_model.dart';
import '../../models/official_stats/canonical_encoding.dart';

enum StatsRulesDecisionState { unresolved, referenceOnly, adopted }

/// Named, versioned rule constraints supplied by league policy.
///
/// A null limit means the selected profile does not establish that rule. The
/// validator never substitutes 48 minutes, five fouls, 240 team-minutes, or a
/// universal box-score cap.
class StatsValidationRulesProfile {
  StatsValidationRulesProfile({
    required this.profileId,
    required this.rulesetVersion,
    required this.decisionState,
    this.playerMinutesLimit,
    this.teamMinutesLimit,
    this.disqualifyingFoulCount,
    Map<String, int> playerStatReviewLimits = const {},
  }) : playerStatReviewLimits = Map.unmodifiable(playerStatReviewLimits) {
    OfficialStatIdentifiers.requireValid('profileId', profileId);
    OfficialStatIdentifiers.requireValid('rulesetVersion', rulesetVersion);
    for (final limit in [
      playerMinutesLimit,
      teamMinutesLimit,
      disqualifyingFoulCount,
      ...this.playerStatReviewLimits.values,
    ]) {
      if (limit != null && limit <= 0) {
        throw ArgumentError('Rules-profile limits must be positive integers');
      }
    }
    const supportedReviewLimits = {'PTS', 'REB', 'AST', 'STL', 'BLK'};
    if (!supportedReviewLimits.containsAll(this.playerStatReviewLimits.keys)) {
      throw ArgumentError('Unsupported player stat review limit');
    }
  }

  /// Current explicit state until JBA/NBL records the adopted rules and local
  /// exceptions. It deliberately supplies no playing-rule limits.
  static final pendingJbaAdoption = StatsValidationRulesProfile(
    profileId: 'jba_rules_decision_pending_v1',
    rulesetVersion: 'jba_rules_decision_pending_v1',
    decisionState: StatsRulesDecisionState.unresolved,
  );

  final String profileId;
  final String rulesetVersion;
  final StatsRulesDecisionState decisionState;
  final int? playerMinutesLimit;
  final int? teamMinutesLimit;
  final int? disqualifyingFoulCount;

  /// Optional profile-specific review bounds keyed by the legacy wire labels
  /// PTS, REB, AST, STL, or BLK. They are not universal basketball rules.
  final Map<String, int> playerStatReviewLimits;
}

/// Pre-submission validation for legacy game stats.
///
/// V2 normalization and certification use the separate exact calculator and
/// revision contracts. This compatibility validator now requires an explicit
/// named rules profile and applies only the limits that profile establishes.
class StatsValidator {
  StatsValidator._();

  static List<String> validate(
    GameStatsModel stats, {
    required StatsValidationRulesProfile rulesProfile,
  }) {
    final errors = <String>[];
    var homeMinutes = 0;
    var awayMinutes = 0;

    for (final line in stats.playerLines.values) {
      final negativeStat = _firstNegative(line);
      if (negativeStat != null) {
        errors.add('${line.name}: $negativeStat cannot be negative.');
      }

      _checkOptionalLimit(
        errors,
        playerName: line.name,
        label: 'MIN',
        value: line.min,
        limit: rulesProfile.playerMinutesLimit,
      );
      _checkOptionalLimit(
        errors,
        playerName: line.name,
        label: 'FLS',
        value: line.fls,
        limit: rulesProfile.disqualifyingFoulCount,
      );
      for (final entry in <String, int>{
        'PTS': line.pts,
        'REB': line.reb,
        'AST': line.ast,
        'STL': line.stl,
        'BLK': line.blk,
      }.entries) {
        _checkOptionalLimit(
          errors,
          playerName: line.name,
          label: entry.key,
          value: entry.value,
          limit: rulesProfile.playerStatReviewLimits[entry.key],
        );
      }

      if (line.teamId == stats.homeTeamId) {
        homeMinutes += line.min;
      } else if (line.teamId == stats.awayTeamId) {
        awayMinutes += line.min;
      }
    }

    final teamLimit = rulesProfile.teamMinutesLimit;
    if (teamLimit != null && homeMinutes > teamLimit) {
      errors.add(
        '${stats.homeTeamName} total MIN ($homeMinutes) exceeds $teamLimit '
        'under ${rulesProfile.profileId}.',
      );
    }
    if (teamLimit != null && awayMinutes > teamLimit) {
      errors.add(
        '${stats.awayTeamName} total MIN ($awayMinutes) exceeds $teamLimit '
        'under ${rulesProfile.profileId}.',
      );
    }

    return errors;
  }

  static void _checkOptionalLimit(
    List<String> errors, {
    required String playerName,
    required String label,
    required int value,
    required int? limit,
  }) {
    if (limit != null && value > limit) {
      errors.add('$playerName: $label exceeds $limit in the selected profile.');
    }
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
