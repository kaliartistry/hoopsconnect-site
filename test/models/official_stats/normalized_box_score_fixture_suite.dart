import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/calculators/normalized_box_score.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';

typedef FixtureLoader = Future<String> Function();

const _reviewedFixtureHashes = <String, String>{
  'complete_zero_disciplinary_incidents':
      '6d464d01c32b6feda8d4051248beaa9d5a11e665b9239f083323756cad7e2755',
  'own_basket_is_credited_and_included_once':
      '4326f46698936f0977d2cfaf5179a56d768a7c133aef7cabf3bbb58382d65c7b',
  'reject_dnp_with_assist':
      '60a709756764e4d82408d925c2cdb324c7d32ee16e72b2444134b7c198e49cae',
  'partial_period_keeps_nominal_and_elapsed_separate':
      'ea717faf4c9993e71c8ed6fe8cb7249aac230769603c303aac75f07ebc61a1a2',
  'fiba_reference_groups_q4_and_repeated_overtime':
      '405f2024121b6a3962b55acfab84aa8eb9b67557afb379c0c9f4948c16de51d8',
  'reject_safe_integer_arithmetic_overflow':
      '54d9b13316c81b5733c8a949c9beda857070386e4aa9a0de848eddaea471b110',
  'reject_post_nfc_expansion_above_preflight_limit':
      '909eac28350df309bc96fe60155df0c0f117dc6b090726f27ebed753ae900ef7',
  'post_nfc_expansion_at_field_byte_boundary':
      '90bfb823a4bcdda03e83a1d3aaca4d0bbe2ef87f2824cdb3aed69b334799f47c',
  'reject_post_nfc_expansion_above_field_byte_boundary':
      'ebe8a68a97419a75ae8642093fcad3b2f5079096e64e5f98e4469cbab40e61e3',
  'post_nfc_contraction_near_source_byte_boundary':
      '4f95821d3632179f0b3c5dcdae3908d0188e6b7f2d57e6154a0952da86effdad',
};

final class _SecondPassExpandsMap extends MapBase<Object?, Object?> {
  _SecondPassExpandsMap(this._delegate);

  final Map<Object?, Object?> _delegate;
  var enumerationCount = 0;

  @override
  Iterable<Object?> get keys {
    enumerationCount += 1;
    if (enumerationCount == 1) return _delegate.keys;
    return Iterable<Object?>.generate(50000, (index) => 'hostile_$index');
  }

  @override
  Object? operator [](Object? key) => _delegate[key];

  @override
  void operator []=(Object? key, Object? value) => _delegate[key] = value;

  @override
  void clear() => _delegate.clear();

  @override
  Object? remove(Object? key) => _delegate.remove(key);
}

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

Map<String, dynamic> _exactTime(int value) => {
  'playedTimeMs': {'state': 'known', 'value': value},
  'roundingMode': 'notApplicable',
  'timePrecisionMs': {'state': 'known', 'value': 1},
  'timeSource': 'liveClock',
};

void _moveExceptionalCreditToPeriodTwo(Map<String, dynamic> input) {
  final rules = input['rules'] as Map<String, dynamic>;
  rules['regulationPeriodCount'] = 2;
  rules['penaltyAccumulationGroups'] = [
    for (final number in [1, 2])
      {
        'groupId': 'period_$number',
        'penaltyStartsAtFoul': {'state': 'known', 'value': 5},
        'periodNumbers': [number],
      },
  ];
  final periods = input['periods'] as List<dynamic>;
  final scoringPeriod = _clone(periods.first)..['number'] = 2;
  final first = periods.first as Map<String, dynamic>;
  first['homeScore'] = 0;
  (first['playerCounterPoints'] as Map<String, dynamic>)['home'] = 0;
  (first['exceptionalScoringPoints'] as Map<String, dynamic>)['home'] = 0;
  periods.add(scoringPeriod);
  final adjustment =
      (input['playedScoreAdjustments'] as List<dynamic>).first
          as Map<String, dynamic>;
  adjustment['periodNumber'] = {'state': 'known', 'value': 2};
}

Map<Object?, Object?> _map(Object? value) => value! as Map<Object?, Object?>;
List<Object?> _items(Object? value) => value! as List<Object?>;
Map<Object?, Object?> _firstError(Map<String, Object?> outcome) =>
    _map(_items(outcome['errors']).first);

Object? _valueAt(Object? value, String dottedPath) {
  var current = value;
  for (final segment in dottedPath.split('.')) {
    if (segment == 'length' && current is List) {
      current = current.length;
    } else if (current is List) {
      current = current[int.parse(segment)];
    } else {
      current = _map(current)[segment];
    }
  }
  return current;
}

void registerNormalizedBoxScoreFixtureTests(FixtureLoader loadFixture) {
  test('shared calculator versions and vocabularies are pinned', () async {
    final fixture = _decodeFixture(await loadFixture());
    expect(fixture['fixtureSchemaVersion'], 2);
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
    'every shared case matches semantics, exact bytes, and SHA-256',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      for (final entry
          in (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final input = entry['input'];
        final before = OfficialStatCanonicalEncoding.encode(input);
        final outcome = calculateNormalizedBoxScore(input);
        final semantics = entry['expectedSemantics'] as Map<String, dynamic>;
        expect(outcome['status'], semantics['status'], reason: entry['name']);
        if (outcome['status'] == 'accepted') {
          for (final check
              in (semantics['checks'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()) {
            expect(
              _valueAt(outcome, check['path']! as String),
              check['value'],
              reason: '${entry['name']}: ${check['path']}',
            );
          }
        } else {
          expect(
            _firstError(outcome),
            semantics['error'],
            reason: entry['name'],
          );
        }
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

  test(
    'reviewed sentinel hashes are independent of the fixture generator',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      for (final entry in _reviewedFixtureHashes.entries) {
        expect(_caseByName(fixture, entry.key)['expectedSha256'], entry.value);
      }
    },
  );

  test(
    'preflight snapshots a caller-controlled map in one bounded pass',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final hostile = _SecondPassExpandsMap(_base(fixture));
      expect(calculateNormalizedBoxScore(hostile)['status'], 'accepted');
      expect(hostile.enumerationCount, 1);

      final cyclic = <String, Object?>{};
      cyclic['cycle'] = cyclic;
      expect(_firstError(calculateNormalizedBoxScore(cyclic)), {
        'code': 'invalidCanonicalValue',
        'path': r'$.cycle',
      });
    },
  );

  test('accepted and rejected result graphs are deeply immutable', () async {
    final fixture = _decodeFixture(await loadFixture());
    final accepted = calculateNormalizedBoxScore(_base(fixture));
    final normalized = _map(accepted['normalizedBoxScore']);
    expect(
      () => _map(normalized['playedScore'])['home'] = 99,
      throwsUnsupportedError,
    );
    expect(() => _items(normalized['teams']).add({}), throwsUnsupportedError);

    final rejected = calculateNormalizedBoxScore(<String, Object?>{});
    expect(
      () => _firstError(rejected)['path'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test(
    'mathematical integers normalize at object and raw JSON boundaries',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final runtime = _base(fixture)..['schemaVersion'] = 2.0;
      expect(calculateNormalizedBoxScore(runtime)['status'], 'accepted');

      final raw = jsonEncode(_base(fixture));
      for (final spelling in ['2.0', '2e0']) {
        final variant = raw.replaceFirst(
          '"schemaVersion":2',
          '"schemaVersion":$spelling',
        );
        final outcome = calculateNormalizedBoxScoreFromJson(variant);
        expect(outcome['status'], 'accepted', reason: spelling);
        expect(_map(outcome['normalizedBoxScore'])['schemaVersion'], 2);
      }
    },
  );

  test(
    'invalid numbers and malformed or oversized raw JSON fail closed',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      for (final value in <num>[
        0.5,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final input = _base(fixture);
        final home =
            (input['teams'] as List<dynamic>)[0] as Map<String, dynamic>;
        final line =
            (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
        final counts = line['counts'] as Map<String, dynamic>;
        (counts['turnovers'] as Map<String, dynamic>)['value'] = value;
        expect(
          _firstError(calculateNormalizedBoxScore(input))['code'],
          'invalidNonnegativeSafeInteger',
        );
      }
      expect(
        _firstError(calculateNormalizedBoxScoreFromJson('{'))['code'],
        'invalidCanonicalValue',
      );
      final rawPadding = List<String>.filled(
        NormalizedBoxScoreLimits.maxRawTransportBytes,
        'x',
      ).join();
      final oversized = '{"padding":"$rawPadding"}';
      expect(
        _firstError(calculateNormalizedBoxScoreFromJson(oversized))['code'],
        'resourceLimitExceeded',
      );
    },
  );

  test(
    'preflight bounds width, depth, strings, players, and canonical bytes',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final oversizedString = _base(fixture);
      (oversizedString['provenance'] as Map<String, dynamic>)['sourceLabel'] =
          List<String>.filled(1025, 'x').join();
      expect(
        _firstError(calculateNormalizedBoxScore(oversizedString))['code'],
        'resourceLimitExceeded',
      );

      final wide = _base(fixture)
        ..['probe'] = {
          for (var index = 0; index < 129; index += 1) 'k$index': 0,
        };
      expect(
        _firstError(calculateNormalizedBoxScore(wide))['code'],
        'resourceLimitExceeded',
      );

      Object? nested = 0;
      for (var index = 0; index < 18; index += 1) {
        nested = [nested];
      }
      final deep = _base(fixture)..['probe'] = nested;
      expect(
        _firstError(calculateNormalizedBoxScore(deep))['code'],
        'resourceLimitExceeded',
      );

      final heavy = _base(fixture)
        ..['probe'] = List<String>.filled(
          1024,
          List<String>.filled(1024, 'x').join(),
        );
      expect(
        _firstError(calculateNormalizedBoxScore(heavy))['code'],
        'resourceLimitExceeded',
      );

      final players = _base(fixture);
      final home =
          (players['teams'] as List<dynamic>)[0] as Map<String, dynamic>;
      final prototype = (home['players'] as List<dynamic>)[0];
      home['players'] = [
        for (var index = 0; index < 65; index += 1)
          {
            ..._clone(prototype),
            'participantId': 'participant_resource_$index',
            'playerId': 'player_resource_$index',
            'rosterMembershipId': 'membership_resource_$index',
            'rosterMembershipVersionId': 'membership_version_resource_$index',
          },
      ];
      expect(
        _firstError(calculateNormalizedBoxScore(players))['code'],
        'resourceLimitExceeded',
      );
    },
  );

  test('departure opportunity is cumulative across earlier periods', () async {
    final fixture = _decodeFixture(await loadFixture());
    final input = _clone(
      _caseByName(fixture, 'legitimate_double_overtime_50_minutes')['input'],
    );
    final home = (input['teams'] as List<dynamic>)[0] as Map<String, dynamic>;
    final line = (home['players'] as List<dynamic>)[0] as Map<String, dynamic>;
    line['departure'] = {
      'clockRemainingMs': {'state': 'known', 'value': 500000},
      'evidenceRefs': {
        'state': 'known',
        'value': ['departure_period_2'],
      },
      'kind': 'ejected',
      'periodNumber': {'state': 'known', 'value': 2},
    };
    line['time'] = {
      'playedTimeMs': {'state': 'known', 'value': 700000},
      'roundingMode': 'notApplicable',
      'timePrecisionMs': {'state': 'known', 'value': 1},
      'timeSource': 'liveClock',
    };
    expect(calculateNormalizedBoxScore(input)['status'], 'accepted');
    final playedTimeFact = _map(_map(line['time'])['playedTimeMs']);
    playedTimeFact['value'] = 700001;
    expect(_firstError(calculateNormalizedBoxScore(input)), {
      'code': 'departureTimeConflict',
      'path': r'$.participants.participant_home_1.time',
    });
  });

  test(
    'time feasibility uses nominal, aggregate, and departure upper bounds',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final aggregate = _base(fixture);
      final rules = aggregate['rules'] as Map<String, dynamic>;
      (rules['teamTimeCapacityMultiplier'] as Map<String, dynamic>)['value'] =
          5;
      final teams = aggregate['teams'] as List<dynamic>;
      final home = teams[0] as Map<String, dynamic>;
      final away = teams[1] as Map<String, dynamic>;
      final homePlayers = home['players'] as List<dynamic>;
      (homePlayers.first as Map<String, dynamic>)['time'] = _exactTime(600000);
      final prototype = (away['players'] as List<dynamic>).first;
      homePlayers.addAll([
        for (var index = 0; index < 5; index += 1)
          {
            ..._clone(prototype),
            'participantId': 'participant_capacity_$index',
            'playerId': 'player_capacity_$index',
            'rosterMembershipId': 'membership_capacity_$index',
            'rosterMembershipVersionId': 'membership_version_capacity_$index',
            'teamEntryId': 'team_home',
            'time': _exactTime(600000),
          },
      ]);
      expect(
        _firstError(calculateNormalizedBoxScore(aggregate))['code'],
        'timeOutsideGameDuration',
      );

      final nominal = _clone(
        _caseByName(
          fixture,
          'partial_period_keeps_nominal_and_elapsed_separate',
        )['input'],
      );
      final period =
          (nominal['periods'] as List<dynamic>).first as Map<String, dynamic>;
      period['elapsedDurationMs'] = {
        'state': 'unknown',
        'value': null,
        'reasonCode': 'not_recorded',
      };
      final nominalHome =
          (nominal['teams'] as List<dynamic>).first as Map<String, dynamic>;
      ((nominalHome['players'] as List<dynamic>).first
          as Map<String, dynamic>)['time'] = _exactTime(
        900000,
      );
      expect(
        _firstError(calculateNormalizedBoxScore(nominal))['code'],
        'timeOutsideGameDuration',
      );

      final departure = _clone(
        _caseByName(fixture, 'legitimate_double_overtime_50_minutes')['input'],
      );
      final departureHome =
          (departure['teams'] as List<dynamic>).first as Map<String, dynamic>;
      final line =
          (departureHome['players'] as List<dynamic>).first
              as Map<String, dynamic>;
      line['time'] = _exactTime(3000000);
      line['departure'] = {
        'clockRemainingMs': {
          'state': 'unknown',
          'value': null,
          'reasonCode': 'not_recorded',
        },
        'evidenceRefs': {
          'state': 'known',
          'value': ['ejection_period_1'],
        },
        'kind': 'ejected',
        'periodNumber': {'state': 'known', 'value': 1},
      };
      expect(
        _firstError(calculateNormalizedBoxScore(departure))['code'],
        'departureTimeConflict',
      );
    },
  );

  test('complete labels cannot fabricate play in an empty game', () async {
    final fixture = _decodeFixture(await loadFixture());
    final input = _clone(
      _caseByName(fixture, 'pregame_default_administrative_only')['input'],
    );
    input['statisticsDisposition'] = 'complete';
    (input['administrativeResult']
            as Map<String, dynamic>)['playerStatisticsTreatment'] =
        'includePlayedStatistics';
    final home =
        (input['teams'] as List<dynamic>).first as Map<String, dynamic>;
    final line =
        (home['players'] as List<dynamic>).first as Map<String, dynamic>;
    line['participationStatus'] = 'active';
    line['enteredPlay'] = true;
    line['participationReasonCode'] = {
      'state': 'notApplicable',
      'value': null,
      'reasonCode': 'entered_play',
    };
    line['starter'] = {'state': 'known', 'value': true};
    final noTime = _caseByName(
      fixture,
      'stats_only_capture_never_invents_time',
    )['input'];
    final noTimeHome =
        (noTime['teams'] as List<dynamic>).first as Map<String, dynamic>;
    line['time'] = _clone(
      (noTimeHome['players'] as List<dynamic>).first,
    )['time'];
    expect(
      _firstError(calculateNormalizedBoxScore(input))['code'],
      'invalidNoPlayStatistics',
    );
  });

  test('a zero-elapsed period row cannot conceal no-play counters', () async {
    final fixture = _decodeFixture(await loadFixture());
    final input = _clone(
      _caseByName(
        fixture,
        'partial_period_keeps_nominal_and_elapsed_separate',
      )['input'],
    );
    final period =
        (input['periods'] as List<dynamic>).first as Map<String, dynamic>;
    period['elapsedDurationMs'] = {'state': 'known', 'value': 0};
    period['homeScore'] = 0;
    period['awayScore'] = 0;
    period['playerCounterPoints'] = {'away': 0, 'home': 0};
    period['exceptionalScoringPoints'] = {'away': 0, 'home': 0};
    input['playedScore'] = {'away': 0, 'home': 0};
    final officialScore = input['officialScore'] as Map<String, dynamic>;
    (officialScore['score'] as Map<String, dynamic>)['value'] = {
      'away': 0,
      'home': 0,
    };
    for (final teamValue in input['teams'] as List<dynamic>) {
      final team = teamValue as Map<String, dynamic>;
      final reported = team['reportedTotals'] as Map<String, dynamic>;
      for (final field in playerCountFields) {
        (reported[field] as Map<String, dynamic>)['value'] = 0;
      }
      for (final playerValue in team['players'] as List<dynamic>) {
        final player = playerValue as Map<String, dynamic>;
        final counts = player['counts'] as Map<String, dynamic>;
        for (final field in playerCountFields) {
          (counts[field] as Map<String, dynamic>)['value'] = 0;
        }
        player['time'] = _exactTime(0);
      }
    }
    final home =
        (input['teams'] as List<dynamic>).first as Map<String, dynamic>;
    final homePlayer =
        (home['players'] as List<dynamic>).first as Map<String, dynamic>;
    ((homePlayer['counts'] as Map<String, dynamic>)['turnovers']
            as Map<String, dynamic>)['value'] =
        1;
    ((home['reportedTotals'] as Map<String, dynamic>)['turnovers']
            as Map<String, dynamic>)['value'] =
        1;
    expect(_firstError(calculateNormalizedBoxScore(input)), {
      'code': 'invalidNoPlayStatistics',
      'path': r'$.teams',
    });
  });

  test(
    'exceptional credits require period eligibility for both scoring kinds',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      for (final name in [
        'own_basket_is_credited_and_included_once',
        'defensive_goaltending_credits_shooter_and_counters',
      ]) {
        final later = _clone(_caseByName(fixture, name)['input']);
        _moveExceptionalCreditToPeriodTwo(later);
        final home =
            (later['teams'] as List<dynamic>).first as Map<String, dynamic>;
        final player =
            (home['players'] as List<dynamic>).first as Map<String, dynamic>;
        player['time'] = _exactTime(1000);
        player['departure'] = {
          'clockRemainingMs': {'state': 'known', 'value': 599000},
          'evidenceRefs': {
            'state': 'known',
            'value': ['ejection_period_1'],
          },
          'kind': 'ejected',
          'periodNumber': {'state': 'known', 'value': 1},
        };
        expect(
          _firstError(calculateNormalizedBoxScore(later))['code'],
          'invalidScoreAdjustment',
          reason: name,
        );

        final samePeriod = _clone(_caseByName(fixture, name)['input']);
        final sameHome =
            (samePeriod['teams'] as List<dynamic>).first
                as Map<String, dynamic>;
        final samePlayer =
            (sameHome['players'] as List<dynamic>).first
                as Map<String, dynamic>;
        samePlayer['time'] = _exactTime(600000);
        samePlayer['departure'] = {
          'clockRemainingMs': {'state': 'known', 'value': 0},
          'evidenceRefs': {
            'state': 'known',
            'value': ['departure_period_1_end'],
          },
          'kind': 'ejected',
          'periodNumber': {'state': 'known', 'value': 1},
        };
        expect(
          calculateNormalizedBoxScore(samePeriod)['status'],
          'accepted',
          reason: name,
        );
      }

      final disqualified = _clone(
        _caseByName(
          fixture,
          'own_basket_is_credited_and_included_once',
        )['input'],
      );
      _moveExceptionalCreditToPeriodTwo(disqualified);
      disqualified['disciplineIncidents'] = [
        {
          'chargedParticipantId': {
            'state': 'known',
            'value': 'participant_home_1',
          },
          'chargedPartyKind': 'player',
          'clockRemainingMs': {'state': 'known', 'value': 0},
          'context': 'onCourt',
          'countsTowardPlayerDisqualification': true,
          'countsTowardTeamFoul': true,
          'evidenceRefs': {
            'state': 'known',
            'value': ['disqualification_period_1'],
          },
          'incidentId': 'disqualification_period_1',
          'incidentType': 'disqualifying',
          'periodNumber': {'state': 'known', 'value': 1},
          'relatedParticipantId': {
            'state': 'unknown',
            'value': null,
            'reasonCode': 'not_recorded',
          },
          'scoresheetCode': 'D',
          'teamEntryId': 'team_home',
        },
      ];
      expect(
        _firstError(calculateNormalizedBoxScore(disqualified))['code'],
        'invalidScoreAdjustment',
      );
    },
  );

  test('score-adjustment shape precedes unrelated discipline errors', () async {
    final fixture = _decodeFixture(await loadFixture());
    final input = _clone(
      _caseByName(fixture, 'own_basket_is_credited_and_included_once')['input'],
    );
    final adjustment =
        (input['playedScoreAdjustments'] as List<dynamic>).first
            as Map<String, dynamic>;
    adjustment['points'] = 3;
    input['disciplineIncidents'] = [
      {
        'chargedParticipantId': {
          'state': 'notApplicable',
          'value': null,
          'reasonCode': 'not_player_charge',
        },
        'chargedPartyKind': 'coach',
        'clockRemainingMs': {'state': 'known', 'value': 300000},
        'context': 'onCourt',
        'countsTowardPlayerDisqualification': false,
        'countsTowardTeamFoul': false,
        'evidenceRefs': {
          'state': 'known',
          'value': ['invalid_coach_on_court'],
        },
        'incidentId': 'invalid_coach_on_court',
        'incidentType': 'technical',
        'periodNumber': {'state': 'known', 'value': 1},
        'relatedParticipantId': {
          'state': 'notApplicable',
          'value': null,
          'reasonCode': 'no_related_participant',
        },
        'scoresheetCode': 'C',
        'teamEntryId': 'team_home',
      },
    ];
    expect(_firstError(calculateNormalizedBoxScore(input)), {
      'code': 'invalidScoreAdjustment',
      'path': r'$.playedScoreAdjustments[0].points',
    });
  });

  test(
    'penalty groups reset in regulation and continue through repeated OT',
    () async {
      final fixture = _decodeFixture(await loadFixture());
      final input = _clone(
        _caseByName(
          fixture,
          'fiba_reference_groups_q4_and_repeated_overtime',
        )['input'],
      );
      final template = _clone((input['disciplineIncidents'] as List).first);
      input['disciplineIncidents'] = [
        for (var index = 0; index < 4; index += 1)
          {
            ..._clone(template),
            'incidentId': 'q1_$index',
            'periodNumber': {'state': 'known', 'value': 1},
          },
        {
          ..._clone(template),
          'incidentId': 'q2_1',
          'periodNumber': {'state': 'known', 'value': 2},
        },
      ];
      final outcome = calculateNormalizedBoxScore(input);
      expect(outcome['status'], 'accepted');
      final home = _map(
        _items(_map(outcome['normalizedBoxScore'])['teams'])[0],
      );
      final discipline = _map(home['discipline']);
      final groups = _items(discipline['penaltyGroups']);
      expect(_map(groups[0])['teamFouls'], 4);
      expect(_map(groups[1])['teamFouls'], 1);

      for (final foulCount in [3, 4, 5]) {
        final transition = _clone(
          _caseByName(
            fixture,
            'fiba_reference_groups_q4_and_repeated_overtime',
          )['input'],
        );
        final incidents = transition['disciplineIncidents'] as List<dynamic>;
        final transitionTemplate = _clone(incidents.first);
        transition['disciplineIncidents'] = [
          for (var index = 0; index < foulCount; index += 1)
            {
              ..._clone(transitionTemplate),
              'incidentId': 'q4_transition_${foulCount}_$index',
              'periodNumber': {'state': 'known', 'value': 4},
            },
        ];
        final transitionOutcome = calculateNormalizedBoxScore(transition);
        final transitionHome = _map(
          _items(_map(transitionOutcome['normalizedBoxScore'])['teams'])[0],
        );
        final transitionState = _map(
          _map(_map(transitionHome['discipline'])['penaltyStateByPeriod'])['4'],
        );
        expect(_map(transitionState['inPenalty'])['value'], foulCount >= 4);
      }

      final overtime = calculateNormalizedBoxScore(
        _caseByName(
          fixture,
          'fiba_reference_groups_q4_and_repeated_overtime',
        )['input'],
      );
      final overtimeHome = _map(
        _items(_map(overtime['normalizedBoxScore'])['teams'])[0],
      );
      final overtimeGroups = _items(
        _map(overtimeHome['discipline'])['penaltyGroups'],
      );
      expect(_map(overtimeGroups[3])['teamFouls'], 6);
      final overtimeStates = _map(
        _map(overtimeHome['discipline'])['penaltyStateByPeriod'],
      );
      expect(_map(_map(overtimeStates['4'])['inPenalty'])['value'], true);
      expect(_map(_map(overtimeStates['5'])['inPenalty'])['value'], true);

      final alternative = _clone(
        _caseByName(
          fixture,
          'alternative_league_resets_each_overtime',
        )['input'],
      );
      final alternativeRules = alternative['rules'] as Map<String, dynamic>;
      for (final groupValue
          in alternativeRules['penaltyAccumulationGroups'] as List<dynamic>) {
        final group = groupValue as Map<String, dynamic>;
        (group['penaltyStartsAtFoul'] as Map<String, dynamic>)['value'] = 5;
      }
      final alternativeOutcome = calculateNormalizedBoxScore(alternative);
      final alternativeHome = _map(
        _items(_map(alternativeOutcome['normalizedBoxScore'])['teams'])[0],
      );
      final alternativeStates = _map(
        _map(alternativeHome['discipline'])['penaltyStateByPeriod'],
      );
      expect(_map(_map(alternativeStates['4'])['inPenalty'])['value'], true);
      expect(_map(_map(alternativeStates['5'])['inPenalty'])['value'], false);
      expect(_map(_map(alternativeStates['6'])['inPenalty'])['value'], false);
    },
  );

  test('bounded shooting grid preserves arithmetic invariants', () async {
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
                final home = (input['teams'] as List)[0] as Map;
                final line = (home['players'] as List)[0] as Map;
                final counts = line['counts'] as Map;
                final reported = home['reportedTotals'] as Map;
                final values = {
                  'freeAttempted': freeAttempted,
                  'freeMade': freeMade,
                  'threeAttempted': threeAttempted,
                  'threeMade': threeMade,
                  'twoAttempted': twoAttempted,
                  'twoMade': twoMade,
                };
                for (final entry in values.entries) {
                  (counts[entry.key] as Map)['value'] = entry.value;
                  (reported[entry.key] as Map)['value'] = entry.value;
                }
                final points = twoMade * 2 + threeMade * 3 + freeMade;
                (input['rules'] as Map)['completedTiesAllowed'] = points == 0;
                (input['playedScore'] as Map)['home'] = points;
                final period = (input['periods'] as List).first as Map;
                period['homeScore'] = points;
                (period['playerCounterPoints'] as Map)['home'] = points;
                (_map((input['officialScore'] as Map)['score'])['value']
                        as Map)['home'] =
                    points;
                final outcome = calculateNormalizedBoxScore(input);
                expect(outcome['status'], 'accepted', reason: '$values');
                final normalizedHome = _map(
                  _items(_map(outcome['normalizedBoxScore'])['teams'])[0],
                );
                expect(_map(normalizedHome['totals'])['points'], points);
              }
            }
          }
        }
      }
    }
  });
}
