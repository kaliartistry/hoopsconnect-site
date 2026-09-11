import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/stats/stats_validator.dart';
import 'package:hoops_connect/models/game_stats_model.dart';

GameStatsModel _stats({int minutes = 50, int fouls = 6, int points = 101}) =>
    GameStatsModel(
      id: 'game_1',
      eventId: 'game_1',
      seasonId: 'season_2026',
      divisionId: 'division_1',
      homeTeamId: 'home',
      awayTeamId: 'away',
      homeTeamName: 'Home',
      awayTeamName: 'Away',
      playerLines: {
        'player_1': PlayerStatLine(
          name: 'Player One',
          teamId: 'home',
          min: minutes,
          fls: fouls,
          pts: points,
        ),
      },
    );

void main() {
  test('unresolved JBA profile does not invent universal limits', () {
    final errors = StatsValidator.validate(
      _stats(),
      rulesProfile: StatsValidationRulesProfile.pendingJbaAdoption,
    );

    expect(
      StatsValidationRulesProfile.pendingJbaAdoption.decisionState,
      StatsRulesDecisionState.unresolved,
    );
    expect(errors, isEmpty);
  });

  test('an injected named profile applies only its explicit constraints', () {
    final profile = StatsValidationRulesProfile(
      profileId: 'fixture_rules_v1',
      rulesetVersion: 'fixture_ruleset_v1',
      decisionState: StatsRulesDecisionState.referenceOnly,
      playerMinutesLimit: 40,
      teamMinutesLimit: 200,
      disqualifyingFoulCount: 5,
      playerStatReviewLimits: {'PTS': 100},
    );
    final errors = StatsValidator.validate(_stats(), rulesProfile: profile);

    expect(errors, hasLength(3));
    expect(errors, contains(contains('MIN exceeds 40')));
    expect(errors, contains(contains('FLS exceeds 5')));
    expect(errors, contains(contains('PTS exceeds 100')));
    expect(errors, isNot(contains(contains('REB'))));
  });

  test('structural negative validation remains fail closed', () {
    final errors = StatsValidator.validate(
      _stats(minutes: -1, fouls: 0, points: 0),
      rulesProfile: StatsValidationRulesProfile.pendingJbaAdoption,
    );
    expect(errors, contains('Player One: MIN cannot be negative.'));
  });
}
