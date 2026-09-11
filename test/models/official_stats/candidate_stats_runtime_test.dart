import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/candidate_stats_runtime.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/models/official_stats/legacy_game_stats_v2_adapter.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'contracts/official_stats/v2/box_score_calculator_fixtures.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, Object?> _caseInput(String name) {
  final fixtureCase = (_fixture()['cases'] as List).cast<Map>().singleWhere(
    (candidate) => candidate['name'] == name,
  );
  return Map<String, Object?>.from(fixtureCase['input'] as Map);
}

CandidateRulesProfile _profileFor(
  Map<String, Object?> input, {
  RulesProfileDecisionState state = RulesProfileDecisionState.referenceOnly,
}) {
  final scope = Map<String, Object?>.from(input['scope'] as Map);
  final provenance = Map<String, Object?>.from(input['provenance'] as Map);
  final rules = Map<String, Object?>.from(input['rules'] as Map);
  return CandidateRulesProfile(
    rulesProfileId: rules['rulesProfileId']! as String,
    rulesetVersion: VersionReference(
      associationId: scope['associationId']! as String,
      versionId: provenance['rulesetVersion']! as String,
      sha256: List.filled(64, 'a').join(),
    ),
    decisionState: state,
  );
}

GameScope _legacyScope() => GameScope(
  associationId: 'jba',
  competitionId: 'nbl',
  seasonId: 'season_2026',
  divisionId: 'division_1',
  phaseId: 'regular',
  gameId: 'game_1',
);

CandidateRulesProfile _unresolvedJbaProfile() => CandidateRulesProfile(
  rulesProfileId: 'jba_rules_decision_pending_v1',
  rulesetVersion: VersionReference(
    associationId: 'jba',
    versionId: 'jba_rules_decision_pending_v1',
    sha256: List.filled(64, 'b').join(),
  ),
  decisionState: RulesProfileDecisionState.unresolved,
);

Map<String, Object?> _legacyDocument() => {
  'eventId': 'game_1',
  'seasonId': 'season_2026',
  'divisionId': 'division_1',
  'homeTeamId': 'home_legacy',
  'awayTeamId': 'away_legacy',
  'homeTeamName': 'Home',
  'awayTeamName': 'Away',
  'homeScore': 2,
  'awayScore': 0,
  'status': 'approved',
  'homeQuarterScores': {'1': 2},
  'awayQuarterScores': {'1': 0},
  'playerLines': {
    'player_legacy_1': {
      'name': 'Unknown shooter',
      'teamId': 'home_legacy',
      'pts': 2,
    },
  },
  'legacyExtension': {'unreviewed': true},
};

void main() {
  group('candidate calculator bridge', () {
    for (final scenario in [
      'legitimate_double_overtime_50_minutes',
      'played_score_separate_from_administrative_result',
      'own_basket_is_credited_and_included_once',
      'defensive_goaltending_credits_shooter_and_counters',
      'alternative_league_resets_each_overtime',
    ]) {
      test('$scenario runs only through its injected named profile', () {
        final input = _caseInput(scenario);
        final result = CandidateOfficialStatsRuntime(
          profile: _profileFor(input),
        ).calculateReviewedV2Input(input);

        expect(result.calculatorInvoked, isTrue);
        expect(result.arithmeticAccepted, isTrue);
        expect(result.calculatorResult['status'], 'accepted');
        expect(result.activationAllowed, isFalse);
        expect(result.certificationAllowed, isFalse);
        expect(result.blockers, contains('rules_profile_adoption_unresolved'));
      });
    }

    test('rules-profile mismatch rejects before calculator invocation', () {
      final input = _caseInput('legitimate_double_overtime_50_minutes');
      var calculatorCalls = 0;
      final mismatched = CandidateRulesProfile(
        rulesProfileId: 'different_profile_v1',
        rulesetVersion: VersionReference(
          associationId: 'association_fixture_1',
          versionId: 'rules_fixture_1',
          sha256: List.filled(64, 'c').join(),
        ),
        decisionState: RulesProfileDecisionState.referenceOnly,
      );
      final runtime = CandidateOfficialStatsRuntime(
        profile: mismatched,
        calculator: (value) {
          calculatorCalls += 1;
          return const {'status': 'accepted'};
        },
      );

      expect(
        () => runtime.calculateReviewedV2Input(input),
        throwsA(isA<FormatException>()),
      );
      expect(calculatorCalls, 0);
    });

    test('adopted state cannot be asserted without evidence', () {
      expect(
        () => CandidateRulesProfile(
          rulesProfileId: 'claimed_adopted_v1',
          rulesetVersion: VersionReference(
            associationId: 'jba',
            versionId: 'claimed_adopted_v1',
            sha256: List.filled(64, 'd').join(),
          ),
          decisionState: RulesProfileDecisionState.adopted,
        ),
        throwsArgumentError,
      );
    });
  });

  test('legacy unknowns and unmapped source provenance stay blocked', () {
    var calculatorCalls = 0;
    final runtime = CandidateOfficialStatsRuntime(
      profile: _unresolvedJbaProfile(),
      calculator: (value) {
        calculatorCalls += 1;
        return const {'status': 'accepted'};
      },
    );
    final candidate = runtime.adaptLegacy(
      source: LegacyGameStatsSourceReference(
        documentId: 'game_1',
        sourcePath: 'associations/jba/gameStats/game_1',
        sourcePayloadHash: List.filled(64, 'e').join(),
      ),
      legacyDocument: _legacyDocument(),
      scope: _legacyScope(),
    );
    final result = runtime.inspectLegacy(candidate);

    expect(calculatorCalls, 0);
    expect(result.calculatorInvoked, isFalse);
    expect(result.arithmeticAccepted, isFalse);
    expect(result.activationAllowed, isFalse);
    expect(result.certificationAllowed, isFalse);
    expect(
      result.blockers,
      containsAll([
        'shooting_breakdown_not_recorded',
        'turnovers_not_recorded',
        'rules_profile_adoption_unresolved',
      ]),
    );
    expect(
      result.provenance['unmappedSourcePaths'],
      contains(r'$.legacyExtension'),
    );
    expect(result.provenance['sourcePayloadHash'], List.filled(64, 'e').join());
    expect(candidate.playerLines.single.reportedPoints.state, FactState.known);
    final normalized = Map<String, Object?>.from(
      candidate.playerLines.single.toContractMap()['normalizedInputFacts']
          as Map,
    );
    final twoMade = Map<String, Object?>.from(normalized['twoMade'] as Map);
    expect(twoMade['state'], 'unknown');
  });
}
