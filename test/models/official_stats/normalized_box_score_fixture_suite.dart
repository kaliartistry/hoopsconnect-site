import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/calculators/normalized_box_score.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';

typedef FixtureLoader = Future<String> Function();

Map<String, dynamic> _decodeFixture(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

Map<String, dynamic> _clone(Object? value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

Map<String, dynamic> _caseByName(Map<String, dynamic> fixture, String name) =>
    (fixture['cases'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['name'] == name);

Map<String, dynamic> _base(Map<String, dynamic> fixture) => _clone(
  _caseByName(fixture, 'complete_zero_disciplinary_incidents')['input'],
);

Map<String, dynamic> _firstError(Map<String, Object?> outcome) =>
    (outcome['errors']! as List<Object?>).first! as Map<String, dynamic>;

void registerNormalizedBoxScoreFixtureTests(FixtureLoader loadFixture) {
  test('shared calculator versions and vocabularies are pinned', () async {
    final fixture = _decodeFixture(await loadFixture());
    expect(fixture['calculatorVersion'], normalizedBoxScoreCalculatorVersion);
    expect(
      fixture['unicodeNormalizationVersion'],
      normalizedBoxScoreUnicodeVersion,
    );
    expect(
      fixture['canonicalEncodingVersion'],
      OfficialStatContractVersions.canonicalEncoding,
    );
    expect(playerCountFields.toSet().length, playerCountFields.length);
    expect(calculatorErrorCodes.toSet().length, calculatorErrorCodes.length);
  });

  test(
    'consumes every shared fixture and matches exact bytes and SHA-256',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      for (final entry
          in (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final input = entry['input'];
        final before = OfficialStatCanonicalEncoding.encode(input);
        final outcome = calculateNormalizedBoxScore(input);
        final canonical = OfficialStatCanonicalEncoding.encode(outcome);
        expect(canonical, entry['expectedCanonical'], reason: entry['name']);
        expect(
          utf8.encode(canonical).length,
          entry['expectedCanonicalByteLength'],
          reason: entry['name'],
        );
        expect(
          OfficialStatCanonicalEncoding.sha256Hex(outcome),
          entry['expectedSha256'],
          reason: entry['name'],
        );
        expect(
          OfficialStatCanonicalEncoding.encode(input),
          before,
          reason: '${entry['name']} mutated its input',
        );
      }
    },
  );

  test('fractional, non-finite, and negative inputs reject', () async {
    final fixture = _decodeFixture(await loadFixture());
    for (final value in <num>[
      0.5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final input = _base(fixture);
      final teams = input['teams'] as List<dynamic>;
      final home = teams[0] as Map<String, dynamic>;
      final players = home['players'] as List<dynamic>;
      final line = players[0] as Map<String, dynamic>;
      final counts = line['counts'] as Map<String, dynamic>;
      (counts['turnovers'] as Map<String, dynamic>)['value'] = value;
      final outcome = calculateNormalizedBoxScore(input);
      expect(outcome['status'], 'rejected');
      expect(_firstError(outcome)['code'], 'invalidNonnegativeSafeInteger');
      expect(_firstError(outcome)['path'], endsWith('.turnovers.value'));
    }

    final negativeTime = _base(fixture);
    final teams = negativeTime['teams'] as List<dynamic>;
    final home = teams[0] as Map<String, dynamic>;
    final line = (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
    final time = line['time'] as Map<String, dynamic>;
    (time['playedTimeMs'] as Map<String, dynamic>)['value'] = -1;
    expect(_firstError(calculateNormalizedBoxScore(negativeTime)), {
      'code': 'invalidNonnegativeSafeInteger',
      'path': r'$.teams[0].players[0].time.playedTimeMs.value',
    });
  });

  test(
    'time interval and unknown time semantics do not invent seconds',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final rounded = calculateNormalizedBoxScore(_base(fixture));
      final normalized = rounded['normalizedBoxScore']! as Map<String, dynamic>;
      final home =
          (normalized['teams'] as List<dynamic>)[0] as Map<String, dynamic>;
      final player =
          (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
      final time = player['time'] as Map<String, dynamic>;
      expect(time['possibleIntervalMs'], {
        'state': 'known',
        'value': {'lowerInclusive': 570000, 'upperExclusive': 630000},
      });

      final missing = calculateNormalizedBoxScore(
        _caseByName(fixture, 'stats_only_capture_never_invents_time')['input'],
      );
      final missingNormalized =
          missing['normalizedBoxScore']! as Map<String, dynamic>;
      for (final teamValue in missingNormalized['teams'] as List<dynamic>) {
        final team = teamValue as Map<String, dynamic>;
        final missingPlayer =
            (team['players'] as List<dynamic>)[0] as Map<String, dynamic>;
        final missingTime = missingPlayer['time'] as Map<String, dynamic>;
        expect(
          (missingTime['playedTimeMs'] as Map<String, dynamic>)['state'],
          'unknown',
        );
        expect(
          (missingTime['possibleIntervalMs'] as Map<String, dynamic>)['state'],
          'unknown',
        );
      }
    },
  );

  test(
    'OT, DNP discipline, and administrative result semantics survive',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final overtime = calculateNormalizedBoxScore(
        _caseByName(fixture, 'legitimate_double_overtime_50_minutes')['input'],
      );
      final overtimeNormalized =
          overtime['normalizedBoxScore']! as Map<String, dynamic>;
      expect((overtimeNormalized['periods'] as List<dynamic>).length, 6);
      expect(
        (((overtimeNormalized['periods'] as List<dynamic>)[5]
                as Map<String, dynamic>)['overtimeIndex']
            as Map<String, dynamic>)['value'],
        2,
      );

      final bench = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'dnp_bench_technical_preserves_discipline_without_gp',
        )['input'],
      );
      final benchNormalized =
          bench['normalizedBoxScore']! as Map<String, dynamic>;
      final home =
          (benchNormalized['teams'] as List<dynamic>)[0]
              as Map<String, dynamic>;
      final dnp = (home['players'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (line) => line['participantId'] == 'participant_home_dnp',
          );
      expect(dnp['gamesPlayed'], 0);
      expect(
        (dnp['discipline'] as Map<String, dynamic>)['relatedIncidentIds'],
        ['incident_bench_1'],
      );
      expect((home['discipline'] as Map<String, dynamic>)['chargedFouls'], 1);

      final adjudicated = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'played_score_separate_from_administrative_result',
        )['input'],
      );
      final adjudicatedNormalized =
          adjudicated['normalizedBoxScore']! as Map<String, dynamic>;
      expect(adjudicatedNormalized['playedScore'], {'away': 0, 'home': 2});
      final administrative =
          adjudicatedNormalized['administrativeResult'] as Map<String, dynamic>;
      expect(
        (administrative['awardedScore'] as Map<String, dynamic>)['value'],
        {'away': 20, 'home': 0},
      );

      final pregameDefault = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'pregame_default_allows_zero_played_periods',
        )['input'],
      );
      final defaultNormalized =
          pregameDefault['normalizedBoxScore']! as Map<String, dynamic>;
      expect(defaultNormalized['periods'], isEmpty);
      expect(defaultNormalized['playedScore'], {'away': 0, 'home': 0});
      for (final teamValue in defaultNormalized['teams'] as List<dynamic>) {
        final team = teamValue as Map<String, dynamic>;
        final player =
            (team['players'] as List<dynamic>)[0] as Map<String, dynamic>;
        expect(player['gamesPlayed'], 0);
      }
    },
  );

  test(
    'team-only totals, departures, and foul subtype counts stay explicit',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final teamOnly = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'team_only_rebounds_and_turnovers_are_separate',
        )['input'],
      );
      final teamOnlyNormalized =
          teamOnly['normalizedBoxScore']! as Map<String, dynamic>;
      final teamOnlyHome =
          (teamOnlyNormalized['teams'] as List<dynamic>)[0]
              as Map<String, dynamic>;
      expect(teamOnlyHome['teamOnly'], {
        'defensiveRebounds': 3,
        'offensiveRebounds': 2,
        'turnovers': 4,
      });
      expect(
        (teamOnlyHome['totals'] as Map<String, dynamic>)['totalRebounds'],
        8,
      );

      final discipline = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'departure_vocabulary_and_typed_discipline',
        )['input'],
      );
      final disciplineNormalized =
          discipline['normalizedBoxScore']! as Map<String, dynamic>;
      final home =
          (disciplineNormalized['teams'] as List<dynamic>)[0]
              as Map<String, dynamic>;
      final players = (home['players'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        players
            .skip(1)
            .map((line) => (line['departure'] as Map<String, dynamic>)['kind']),
        ['fouledOut', 'ejected', 'injured', 'other'],
      );
      final summary = home['discipline'] as Map<String, dynamic>;
      expect(summary['chargedFouls'], 3);
      expect(summary['byType'], {
        'disqualifying': 0,
        'personal': 0,
        'technical': 2,
        'unsportsmanlike': 1,
      });
      expect((summary['penaltyStateByPeriod'] as Map<String, dynamic>)['1'], {
        'state': 'known',
        'value': {'inPenalty': false, 'teamFouls': 1, 'threshold': 5},
      });
    },
  );

  test('resource and Unicode-version limits fail closed', () async {
    final fixture = _decodeFixture(await loadFixture());
    final longString = _base(fixture);
    (longString['provenance'] as Map<String, dynamic>)['sourceLabel'] =
        'x' * 1025;
    expect(
      _firstError(calculateNormalizedBoxScore(longString))['code'],
      'resourceLimitExceeded',
    );

    final wrongUnicode = _base(fixture);
    wrongUnicode['unicodeNormalizationVersion'] = 'unicode-runtime-default';
    expect(_firstError(calculateNormalizedBoxScore(wrongUnicode)), {
      'code': 'unsupportedUnicodeNormalizationVersion',
      'path': r'$.unicodeNormalizationVersion',
    });

    final impossibleTime = _base(fixture);
    final teams = impossibleTime['teams'] as List<dynamic>;
    final home = teams[0] as Map<String, dynamic>;
    final player =
        (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
    final time = player['time'] as Map<String, dynamic>;
    (time['playedTimeMs'] as Map<String, dynamic>)['value'] = 1200000;
    expect(
      _firstError(calculateNormalizedBoxScore(impossibleTime))['code'],
      'timeOutsideGameDuration',
    );

    final oversizedKey = _base(fixture);
    oversizedKey['x' * 1025] = true;
    expect(_firstError(calculateNormalizedBoxScore(oversizedKey)), {
      'code': 'resourceLimitExceeded',
      'path': r'$',
    });
  });

  test(
    'scope, participation, evidence, and adjudication invariants fail closed',
    () async {
      final fixture = _decodeFixture(await loadFixture());

      final missingScope = _base(fixture);
      (missingScope['scope'] as Map<String, dynamic>).remove('seasonId');
      expect(_firstError(calculateNormalizedBoxScore(missingScope)), {
        'code': 'invalidShape',
        'path': r'$.scope',
      });

      final invalidParticipation = _base(fixture);
      final home =
          (invalidParticipation['teams'] as List<dynamic>)[0]
              as Map<String, dynamic>;
      final active =
          (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
      active['participationReasonCode'] = {
        'state': 'known',
        'value': 'coach_decision',
      };
      expect(
        _firstError(calculateNormalizedBoxScore(invalidParticipation))['code'],
        'invalidParticipation',
      );

      final invalidAdjustment = _clone(
        _caseByName(fixture, 'explicit_own_basket_not_balance_score')['input'],
      );
      ((invalidAdjustment['playedScoreAdjustments'] as List<dynamic>)[0]
              as Map<String, dynamic>)['points'] =
          3;
      expect(_firstError(calculateNormalizedBoxScore(invalidAdjustment)), {
        'code': 'invalidScoreAdjustment',
        'path': r'$.playedScoreAdjustments[0].points',
      });

      final missingFoulPeriod = _clone(
        _caseByName(
          fixture,
          'departure_vocabulary_and_typed_discipline',
        )['input'],
      );
      final incident =
          (missingFoulPeriod['disciplineIncidents'] as List<dynamic>)[0]
              as Map<String, dynamic>;
      incident['periodNumber'] = {
        'reasonCode': 'not_recorded',
        'state': 'unknown',
        'value': null,
      };
      incident['clockRemainingMs'] = {
        'reasonCode': 'not_recorded',
        'state': 'unknown',
        'value': null,
      };
      expect(_firstError(calculateNormalizedBoxScore(missingFoulPeriod)), {
        'code': 'invalidDisciplineIncident',
        'path': r'$.disciplineIncidents[0].periodNumber',
      });

      final wrongAwardedWinner = _clone(
        _caseByName(
          fixture,
          'played_score_separate_from_administrative_result',
        )['input'],
      );
      (wrongAwardedWinner['administrativeResult']
          as Map<String, dynamic>)['winnerTeamEntryId'] = {
        'state': 'known',
        'value': 'team_home',
      };
      expect(_firstError(calculateNormalizedBoxScore(wrongAwardedWinner)), {
        'code': 'invalidAdministrativeResult',
        'path': r'$.administrativeResult.winnerTeamEntryId',
      });

      final incompletePlayedGame = _base(fixture);
      (incompletePlayedGame['rules']
              as Map<String, dynamic>)['regulationPeriodCount'] =
          4;
      expect(_firstError(calculateNormalizedBoxScore(incompletePlayedGame)), {
        'code': 'invalidPeriodSequence',
        'path': r'$.periods',
      });

      final emptyRoster = _base(fixture);
      (((emptyRoster['teams'] as List<dynamic>)[0]
                  as Map<String, dynamic>)['players']
              as List<dynamic>)
          .clear();
      expect(_firstError(calculateNormalizedBoxScore(emptyRoster)), {
        'code': 'invalidTeamStructure',
        'path': r'$.teams[0].players',
      });
    },
  );

  test('all retained human text and reason codes normalize to NFC', () async {
    final fixture = _decodeFixture(await loadFixture());
    final input = _base(fixture);
    final rules = input['rules'] as Map<String, dynamic>;
    final thresholds =
        rules['teamFoulPenaltyThresholds'] as Map<String, dynamic>;
    thresholds['overtime'] = {
      'reasonCode': 'Cafe\u0301',
      'state': 'unknown',
      'value': null,
    };
    final outcome = calculateNormalizedBoxScore(input);
    expect(outcome['status'], 'accepted');
    final normalized = outcome['normalizedBoxScore'] as Map<String, dynamic>;
    final normalizedRules = normalized['rules'] as Map<String, dynamic>;
    final normalizedThresholds =
        normalizedRules['teamFoulPenaltyThresholds'] as Map<String, dynamic>;
    expect(
      (normalizedThresholds['overtime'] as Map<String, dynamic>)['reasonCode'],
      'Café',
    );
  });

  test('bounded shooting grid preserves every arithmetic invariant', () async {
    final fixture = _decodeFixture(await loadFixture());
    for (var twoAttempted = 0; twoAttempted <= 2; twoAttempted += 1) {
      for (var twoMade = 0; twoMade <= twoAttempted; twoMade += 1) {
        for (var threeAttempted = 0; threeAttempted <= 2; threeAttempted += 1) {
          for (var threeMade = 0; threeMade <= threeAttempted; threeMade += 1) {
            for (
              var freeAttempted = 0;
              freeAttempted <= 2;
              freeAttempted += 1
            ) {
              for (var freeMade = 0; freeMade <= freeAttempted; freeMade += 1) {
                final input = _base(fixture);
                final teams = input['teams'] as List<dynamic>;
                final home = teams[0] as Map<String, dynamic>;
                final player =
                    (home['players'] as List<dynamic>)[0]
                        as Map<String, dynamic>;
                final counts = player['counts'] as Map<String, dynamic>;
                final reported = home['reportedTotals'] as Map<String, dynamic>;
                final values = {
                  'twoMade': twoMade,
                  'twoAttempted': twoAttempted,
                  'threeMade': threeMade,
                  'threeAttempted': threeAttempted,
                  'freeMade': freeMade,
                  'freeAttempted': freeAttempted,
                };
                for (final entry in values.entries) {
                  (counts[entry.key] as Map<String, dynamic>)['value'] =
                      entry.value;
                  (reported[entry.key] as Map<String, dynamic>)['value'] =
                      entry.value;
                }
                final points = 2 * twoMade + 3 * threeMade + freeMade;
                (input['rules']
                        as Map<String, dynamic>)['completedTiesAllowed'] =
                    points == 0;
                input['playedScore'] = {'away': 0, 'home': points};
                ((input['periods'] as List<dynamic>)[0]
                        as Map<String, dynamic>)['homeScore'] =
                    points;
                final official = input['officialScore'] as Map<String, dynamic>;
                (official['score'] as Map<String, dynamic>)['value'] = {
                  'away': 0,
                  'home': points,
                };

                final outcome = calculateNormalizedBoxScore(input);
                expect(outcome['status'], 'accepted', reason: '$values');
                final normalized =
                    outcome['normalizedBoxScore'] as Map<String, dynamic>;
                final normalizedHome =
                    (normalized['teams'] as List<dynamic>)[0]
                        as Map<String, dynamic>;
                final totals = normalizedHome['totals'] as Map<String, dynamic>;
                expect(totals['fieldMade'], twoMade + threeMade);
                expect(totals['fieldAttempted'], twoAttempted + threeAttempted);
                expect(totals['points'], points);
              }
            }
          }
        }
      }
    }
  });

  test(
    'validation result is deterministic across map insertion order',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final invalid = _clone(
        _caseByName(
          fixture,
          'reject_player_79_scoreboard_80_periods_78',
        )['input'],
      );

      Object? reverseRecords(Object? value) {
        if (value is List) return value.map(reverseRecords).toList();
        if (value is Map) {
          final keys = value.keys.cast<String>().toList().reversed;
          return {for (final key in keys) key: reverseRecords(value[key])};
        }
        return value;
      }

      expect(
        calculateNormalizedBoxScore(reverseRecords(invalid)),
        calculateNormalizedBoxScore(invalid),
      );
    },
  );
}
