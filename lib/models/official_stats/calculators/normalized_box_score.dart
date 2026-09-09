import 'dart:collection';
import 'dart:convert';

import '../canonical_encoding.dart';
import '../contract_versions.dart';
import '../unicode_normalization.dart';

const normalizedBoxScoreCalculatorVersion =
    'hoopsconnect-normalized-box-score-v2';
const normalizedBoxScoreUnicodeVersion = 'official-stat-unicode-nfc-v2';

const playerCountFields = <String>[
  'twoMade',
  'twoAttempted',
  'threeMade',
  'threeAttempted',
  'freeMade',
  'freeAttempted',
  'offensiveRebounds',
  'defensiveRebounds',
  'assists',
  'steals',
  'blocks',
  'turnovers',
];

const calculatorErrorCodes = <String>[
  'invalidCanonicalValue',
  'resourceLimitExceeded',
  'invalidShape',
  'unsupportedSchemaVersion',
  'unsupportedCalculatorVersion',
  'unsupportedCanonicalEncodingVersion',
  'unsupportedUnicodeNormalizationVersion',
  'invalidIdentifier',
  'invalidString',
  'invalidNonnegativeSafeInteger',
  'arithmeticOverflow',
  'invalidFact',
  'requiredKnownCount',
  'invalidTeamStructure',
  'duplicateParticipant',
  'participantTeamMismatch',
  'invalidParticipation',
  'dnpOrdinaryStat',
  'invalidTimeProvenance',
  'timeOutsideGameDuration',
  'invalidDeparture',
  'departureTimeConflict',
  'eventClockOutsidePeriod',
  'makesExceedAttempts',
  'reportedTeamTotalMismatch',
  'invalidRulesProfile',
  'invalidPenaltyPolicy',
  'invalidPeriodSequence',
  'invalidPeriodState',
  'invalidOvertimeSequence',
  'playedScorePeriodMismatch',
  'playedScoreAttributionMismatch',
  'invalidScoreAdjustment',
  'invalidDisciplineIncident',
  'playerNotEnteredForIncident',
  'invalidAdministrativeResult',
  'invalidNoPlayStatistics',
  'officialScoreEvidenceRequired',
  'officialScoreMismatch',
];

abstract final class NormalizedBoxScoreLimits {
  static const maxCanonicalPayloadBytes = 128 * 1024;
  static const maxRawTransportBytes = 128 * 1024;
  static const maxContainerEntries = 1024;
  static const maxObjectKeys = 128;
  static const maxDepth = 16;
  static const maxEvidenceRefsPerFact = 64;
  static const maxIncidents = 512;
  static const maxNodes = 20000;
  static const maxPenaltyGroups = 64;
  static const maxPeriods = 64;
  static const maxPlayedScoreAdjustments = 128;
  static const maxPlayersPerTeam = 64;
  static const maxStringBytes = 1024;
}

final class _ValidationFailure implements Exception {
  final String code;
  final String path;

  const _ValidationFailure(this.code, this.path);
}

Never _fail(String code, String path) => throw _ValidationFailure(code, path);

final _opaqueId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
final _asciiKey = RegExp(r'^[\x21-\x7e]+$');

int _utf8Length(String value) => utf8.encode(value).length;

/// Builds a bounded, ordinary Dart snapshot before any schema parser can
/// enumerate caller-controlled containers a second time.
Object? _preflight(Object? value) {
  var nodes = 0;
  var canonicalBytes = 0;
  final activeContainers = HashSet<Object>.identity();

  void charge(int bytes, String path) {
    canonicalBytes += bytes;
    if (canonicalBytes > NormalizedBoxScoreLimits.maxCanonicalPayloadBytes) {
      _fail('resourceLimitExceeded', path);
    }
  }

  Object? visit(Object? current, String path, int depth) {
    nodes += 1;
    if (nodes > NormalizedBoxScoreLimits.maxNodes ||
        depth > NormalizedBoxScoreLimits.maxDepth) {
      _fail('resourceLimitExceeded', path);
    }
    if (current == null) {
      charge(4, path);
      return null;
    }
    if (current is bool) {
      charge(current ? 4 : 5, path);
      return current;
    }
    if (current is String) {
      if (_utf8Length(current) > NormalizedBoxScoreLimits.maxStringBytes) {
        _fail('resourceLimitExceeded', path);
      }
      final normalized = OfficialStatUnicodeNormalization.nfc(current);
      if (_utf8Length(normalized) > NormalizedBoxScoreLimits.maxStringBytes) {
        _fail('resourceLimitExceeded', path);
      }
      charge(_utf8Length(jsonEncode(normalized)), path);
      return normalized;
    }
    if (current is num) {
      if (!current.isFinite ||
          current < 0 ||
          current > OfficialStatCanonicalEncoding.maxSafeInteger ||
          current != current.truncateToDouble()) {
        _fail('invalidNonnegativeSafeInteger', path);
      }
      final normalized = current == 0 ? 0 : current.toInt();
      charge(_utf8Length(jsonEncode(normalized)), path);
      return normalized;
    }
    if (current is List) {
      if (!activeContainers.add(current)) {
        _fail('invalidCanonicalValue', path);
      }
      final items = <Object?>[];
      final iterator = current.iterator;
      while (iterator.moveNext()) {
        if (items.length >= NormalizedBoxScoreLimits.maxContainerEntries) {
          _fail('resourceLimitExceeded', path);
        }
        items.add(iterator.current);
      }
      charge(2 + (items.isEmpty ? 0 : items.length - 1), path);
      final snapshot = <Object?>[
        for (var index = 0; index < items.length; index += 1)
          visit(items[index], '$path[$index]', depth + 1),
      ];
      activeContainers.remove(current);
      return snapshot;
    }
    if (current is Map) {
      if (!activeContainers.add(current)) {
        _fail('invalidCanonicalValue', path);
      }
      final entries = <MapEntry<String, Object?>>[];
      final keys = <String>{};
      final iterator = current.entries.iterator;
      while (iterator.moveNext()) {
        if (entries.length >= NormalizedBoxScoreLimits.maxObjectKeys) {
          _fail('resourceLimitExceeded', path);
        }
        final entry = iterator.current;
        final key = entry.key;
        if (key is! String || !_asciiKey.hasMatch(key)) {
          _fail('invalidCanonicalValue', path);
        }
        if (_utf8Length(key) > NormalizedBoxScoreLimits.maxStringBytes) {
          _fail('resourceLimitExceeded', path);
        }
        if (!keys.add(key)) _fail('invalidCanonicalValue', path);
        entries.add(MapEntry<String, Object?>(key, entry.value));
      }
      entries.sort((left, right) => left.key.compareTo(right.key));
      charge(2 + (entries.isEmpty ? 0 : entries.length - 1), path);
      final snapshot = <String, Object?>{};
      for (final entry in entries) {
        charge(_utf8Length(jsonEncode(entry.key)) + 1, path);
        snapshot[entry.key] = visit(
          entry.value,
          '$path.${entry.key}',
          depth + 1,
        );
      }
      activeContainers.remove(current);
      return snapshot;
    }
    _fail('invalidCanonicalValue', path);
  }

  return visit(value, r'$', 0);
}

Map<String, Object?> _record(
  Object? value,
  String path, [
  List<String>? exactKeys,
]) {
  if (value is! Map) _fail('invalidShape', path);
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) _fail('invalidShape', path);
    result[entry.key as String] = entry.value;
  }
  if (exactKeys != null) {
    final actual = result.keys.toList()..sort();
    final expected = [...exactKeys]..sort();
    if (actual.length != expected.length) _fail('invalidShape', path);
    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) _fail('invalidShape', path);
    }
  }
  return result;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List) _fail('invalidShape', path);
  return List<Object?>.from(value);
}

String _text(Object? value, String path, [int maxBytes = 512]) {
  if (value is! String || value.isEmpty || _utf8Length(value) > maxBytes) {
    _fail('invalidString', path);
  }
  final normalized = OfficialStatUnicodeNormalization.nfc(value);
  if (_utf8Length(normalized) > maxBytes) _fail('invalidString', path);
  return normalized;
}

String _identifier(Object? value, String path) {
  if (value is! String || !_opaqueId.hasMatch(value)) {
    _fail('invalidIdentifier', path);
  }
  return value;
}

int _nonnegativeInteger(Object? value, String path) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > OfficialStatCanonicalEncoding.maxSafeInteger ||
      value != value.truncateToDouble()) {
    _fail('invalidNonnegativeSafeInteger', path);
  }
  return value.toInt();
}

int _positiveInteger(Object? value, String path) {
  final parsed = _nonnegativeInteger(value, path);
  if (parsed == 0) _fail('invalidNonnegativeSafeInteger', path);
  return parsed;
}

bool _boolean(Object? value, String path) {
  if (value is! bool) _fail('invalidShape', path);
  return value;
}

String _enumeration(Object? value, String path, List<String> values) {
  if (value is! String || !values.contains(value)) {
    _fail('invalidShape', path);
  }
  return value;
}

Map<String, Object?> _fact(
  Object? value,
  String path,
  Object? Function(Object? known, String knownPath) parseKnown,
) {
  final raw = _record(value, path);
  final state = raw['state'];
  if (state is! String ||
      !const ['known', 'unknown', 'notApplicable'].contains(state)) {
    _fail('invalidFact', path);
  }
  final keys = raw.keys.toList()..sort();
  if (state == 'known') {
    if (keys.join(',') != 'state,value') _fail('invalidFact', path);
    return {'state': 'known', 'value': parseKnown(raw['value'], '$path.value')};
  }
  if (keys.join(',') != 'reasonCode,state,value' || raw['value'] != null) {
    _fail('invalidFact', path);
  }
  final reasonCode = raw['reasonCode'];
  if (state == 'unknown') {
    if (reasonCode != null && (reasonCode is! String || reasonCode.isEmpty)) {
      _fail('invalidFact', '$path.reasonCode');
    }
    return {
      'reasonCode': reasonCode == null
          ? null
          : _text(reasonCode, '$path.reasonCode'),
      'state': 'unknown',
      'value': null,
    };
  }
  if (reasonCode is! String || reasonCode.isEmpty) {
    _fail('invalidFact', '$path.reasonCode');
  }
  return {
    'reasonCode': _text(reasonCode, '$path.reasonCode'),
    'state': 'notApplicable',
    'value': null,
  };
}

Map<String, Object?> _validateScope(Object? value) {
  final raw = _record(value, r'$.scope', [
    'associationId',
    'competitionId',
    'divisionId',
    'gameId',
    'phaseId',
    'seasonId',
  ]);
  return {
    'associationId': _identifier(
      raw['associationId'],
      r'$.scope.associationId',
    ),
    'competitionId': _identifier(
      raw['competitionId'],
      r'$.scope.competitionId',
    ),
    'divisionId': _identifier(raw['divisionId'], r'$.scope.divisionId'),
    'gameId': _identifier(raw['gameId'], r'$.scope.gameId'),
    'phaseId': _identifier(raw['phaseId'], r'$.scope.phaseId'),
    'seasonId': _identifier(raw['seasonId'], r'$.scope.seasonId'),
  };
}

Map<String, Object?> _countFact(Object? value, String path) =>
    _fact(value, path, _nonnegativeInteger);

int _knownCount(Object? value, String path) {
  final parsed = _countFact(value, path);
  if (parsed['state'] != 'known') _fail('requiredKnownCount', path);
  return parsed['value']! as int;
}

List<Object?> _stringList(Object? value, String path) {
  final raw = _list(value, path);
  if (raw.length > NormalizedBoxScoreLimits.maxEvidenceRefsPerFact) {
    _fail('resourceLimitExceeded', path);
  }
  return [
    for (var index = 0; index < raw.length; index += 1)
      _text(raw[index], '$path[$index]'),
  ];
}

Map<String, Object?> _scorePair(Object? value, String path) {
  final raw = _record(value, path, ['away', 'home']);
  return {
    'home': _nonnegativeInteger(raw['home'], '$path.home'),
    'away': _nonnegativeInteger(raw['away'], '$path.away'),
  };
}

int _safeAdd(int left, int right, String path) {
  final result = left + right;
  if (result > OfficialStatCanonicalEncoding.maxSafeInteger) {
    _fail('arithmeticOverflow', path);
  }
  return result;
}

int _safeMultiply(int value, int multiplier, String path) {
  if (value > OfficialStatCanonicalEncoding.maxSafeInteger ~/ multiplier) {
    _fail('arithmeticOverflow', path);
  }
  return value * multiplier;
}

Map<String, int> _zeroCounts() => {
  for (final field in playerCountFields) field: 0,
};

Map<String, int> _parseCounts(Object? value, String path) {
  final raw = _record(value, path, playerCountFields);
  return {
    for (final field in playerCountFields)
      field: _knownCount(raw[field], '$path.$field'),
  };
}

Map<String, int> _derivedTotals(Map<String, int> counts) {
  final fieldMade = _safeAdd(
    counts['twoMade']!,
    counts['threeMade']!,
    r'$.derived.fieldMade',
  );
  final fieldAttempted = _safeAdd(
    counts['twoAttempted']!,
    counts['threeAttempted']!,
    r'$.derived.fieldAttempted',
  );
  final totalRebounds = _safeAdd(
    counts['offensiveRebounds']!,
    counts['defensiveRebounds']!,
    r'$.derived.totalRebounds',
  );
  final points = _safeAdd(
    _safeAdd(
      _safeMultiply(counts['twoMade']!, 2, r'$.derived.points'),
      _safeMultiply(counts['threeMade']!, 3, r'$.derived.points'),
      r'$.derived.points',
    ),
    counts['freeMade']!,
    r'$.derived.points',
  );
  return {
    ...counts,
    'fieldMade': fieldMade,
    'fieldAttempted': fieldAttempted,
    'totalRebounds': totalRebounds,
    'points': points,
  };
}

Map<String, Object?> _shootingPercentages(Map<String, int> totals) {
  Map<String, Object?> ratio(int makes, int attempts) => attempts == 0
      ? {'state': 'unknown', 'value': null, 'reasonCode': 'zero_attempts'}
      : {
          'state': 'known',
          'value': {'attempts': attempts, 'makes': makes},
        };

  return {
    'field': ratio(totals['fieldMade']!, totals['fieldAttempted']!),
    'free': ratio(totals['freeMade']!, totals['freeAttempted']!),
    'three': ratio(totals['threeMade']!, totals['threeAttempted']!),
    'two': ratio(totals['twoMade']!, totals['twoAttempted']!),
  };
}

void _addCounts(Map<String, int> target, Map<String, int> source, String path) {
  for (final field in playerCountFields) {
    target[field] = _safeAdd(target[field]!, source[field]!, '$path.$field');
  }
}

bool _allCountsZero(Map<String, int> counts) =>
    playerCountFields.every((field) => counts[field] == 0);

bool _absentFact(Map<String, Object?> value, String reason) =>
    value['state'] == 'notApplicable' && value['reasonCode'] == reason;

Map<String, Object?> _validateRules(Object? value) {
  final raw = _record(value, r'$.rules', [
    'completedTiesAllowed',
    'exceptionalScoringProfile',
    'overtimePolicy',
    'penaltyAccumulationGroups',
    'playingTimeRoundingProfile',
    'regulationPeriodCount',
    'rulesProfileId',
    'teamTimeCapacityMultiplier',
  ]);
  final rulesProfileId = _enumeration(
    raw['rulesProfileId'],
    r'$.rules.rulesProfileId',
    ['generic-explicit-v2', 'fiba-2024-reference-v1'],
  );
  final regulationPeriodCount = _positiveInteger(
    raw['regulationPeriodCount'],
    r'$.rules.regulationPeriodCount',
  );
  final completedTiesAllowed = _boolean(
    raw['completedTiesAllowed'],
    r'$.rules.completedTiesAllowed',
  );
  final overtimeRaw = _record(
    raw['overtimePolicy'],
    r'$.rules.overtimePolicy',
    ['allowed', 'nominalDurationMs'],
  );
  final overtimePolicy = <String, Object?>{
    'allowed': _boolean(
      overtimeRaw['allowed'],
      r'$.rules.overtimePolicy.allowed',
    ),
    'nominalDurationMs': _countFact(
      overtimeRaw['nominalDurationMs'],
      r'$.rules.overtimePolicy.nominalDurationMs',
    ),
  };
  final overtimeDuration =
      overtimePolicy['nominalDurationMs']! as Map<String, Object?>;
  if (overtimePolicy['allowed'] == true) {
    if (overtimeDuration['state'] != 'known' ||
        overtimeDuration['value'] == 0) {
      _fail('invalidRulesProfile', r'$.rules.overtimePolicy.nominalDurationMs');
    }
  } else if (!_absentFact(overtimeDuration, 'overtime_not_allowed')) {
    _fail('invalidRulesProfile', r'$.rules.overtimePolicy.nominalDurationMs');
  }
  final teamTimeCapacityMultiplier = _countFact(
    raw['teamTimeCapacityMultiplier'],
    r'$.rules.teamTimeCapacityMultiplier',
  );
  if (teamTimeCapacityMultiplier['state'] == 'known' &&
      teamTimeCapacityMultiplier['value'] == 0) {
    _fail('invalidRulesProfile', r'$.rules.teamTimeCapacityMultiplier');
  }
  final playingTimeRoundingProfile = _enumeration(
    raw['playingTimeRoundingProfile'],
    r'$.rules.playingTimeRoundingProfile',
    ['nearest-half-up-v1', 'fiba-2024-reference-sheet-v1'],
  );
  final exceptionalScoringProfile = _enumeration(
    raw['exceptionalScoringProfile'],
    r'$.rules.exceptionalScoringProfile',
    ['fiba-2024-reference-attribution-v1'],
  );
  final groupValues = _list(
    raw['penaltyAccumulationGroups'],
    r'$.rules.penaltyAccumulationGroups',
  );
  if (groupValues.length > NormalizedBoxScoreLimits.maxPenaltyGroups) {
    _fail('resourceLimitExceeded', r'$.rules.penaltyAccumulationGroups');
  }
  final groupIds = <String>{};
  final groups = <Object?>[];
  for (var index = 0; index < groupValues.length; index += 1) {
    final path =
        r'$.rules.penaltyAccumulationGroups'
        '[$index]';
    final group = _record(groupValues[index], path, [
      'groupId',
      'penaltyStartsAtFoul',
      'periodNumbers',
    ]);
    final groupId = _identifier(group['groupId'], '$path.groupId');
    if (!groupIds.add(groupId)) _fail('invalidPenaltyPolicy', '$path.groupId');
    final periodValues = _list(group['periodNumbers'], '$path.periodNumbers');
    if (periodValues.isEmpty ||
        periodValues.length > NormalizedBoxScoreLimits.maxPeriods) {
      _fail('invalidPenaltyPolicy', '$path.periodNumbers');
    }
    final periodNumbers = <Object?>[];
    for (
      var numberIndex = 0;
      numberIndex < periodValues.length;
      numberIndex += 1
    ) {
      final number = _positiveInteger(
        periodValues[numberIndex],
        '$path.periodNumbers[$numberIndex]',
      );
      if (periodNumbers.isNotEmpty && number <= (periodNumbers.last! as int)) {
        _fail('invalidPenaltyPolicy', '$path.periodNumbers');
      }
      periodNumbers.add(number);
    }
    final penaltyStartsAtFoul = _countFact(
      group['penaltyStartsAtFoul'],
      '$path.penaltyStartsAtFoul',
    );
    if (penaltyStartsAtFoul['state'] == 'notApplicable' ||
        (penaltyStartsAtFoul['state'] == 'known' &&
            penaltyStartsAtFoul['value'] == 0)) {
      _fail('invalidPenaltyPolicy', '$path.penaltyStartsAtFoul');
    }
    groups.add({
      'groupId': groupId,
      'penaltyStartsAtFoul': penaltyStartsAtFoul,
      'periodNumbers': periodNumbers,
    });
  }
  if (rulesProfileId == 'fiba-2024-reference-v1' &&
      (regulationPeriodCount != 4 ||
          completedTiesAllowed ||
          overtimePolicy['allowed'] != true ||
          overtimeDuration['state'] != 'known' ||
          overtimeDuration['value'] != 300000 ||
          teamTimeCapacityMultiplier['state'] != 'known' ||
          teamTimeCapacityMultiplier['value'] != 5 ||
          playingTimeRoundingProfile != 'fiba-2024-reference-sheet-v1')) {
    _fail('invalidRulesProfile', r'$.rules');
  }
  return {
    'completedTiesAllowed': completedTiesAllowed,
    'exceptionalScoringProfile': exceptionalScoringProfile,
    'overtimePolicy': overtimePolicy,
    'penaltyAccumulationGroups': groups,
    'playingTimeRoundingProfile': playingTimeRoundingProfile,
    'regulationPeriodCount': regulationPeriodCount,
    'rulesProfileId': rulesProfileId,
    'teamTimeCapacityMultiplier': teamTimeCapacityMultiplier,
  };
}

Map<String, Object?> _validateTime(
  Object? value,
  String path,
  bool enteredPlay,
  String roundingProfile,
) {
  final raw = _record(value, path, [
    'playedTimeMs',
    'roundingMode',
    'timePrecisionMs',
    'timeSource',
  ]);
  final playedTimeMs = _countFact(raw['playedTimeMs'], '$path.playedTimeMs');
  final timePrecisionMs = _countFact(
    raw['timePrecisionMs'],
    '$path.timePrecisionMs',
  );
  final timeSource = _enumeration(raw['timeSource'], '$path.timeSource', [
    'liveClock',
    'officialSheetExact',
    'officialSheetRounded',
    'notRecorded',
    'notApplicable',
  ]);
  final roundingMode = _enumeration(raw['roundingMode'], '$path.roundingMode', [
    'nearestHalfUp',
    'fiba2024ReferenceSheet',
    'notApplicable',
  ]);
  if (!enteredPlay) {
    if (timeSource != 'notApplicable' ||
        roundingMode != 'notApplicable' ||
        !_absentFact(playedTimeMs, 'did_not_enter') ||
        !_absentFact(timePrecisionMs, 'did_not_enter')) {
      _fail('invalidTimeProvenance', path);
    }
    return {
      'playedTimeMs': playedTimeMs,
      'possibleIntervalMs': {
        'state': 'notApplicable',
        'value': null,
        'reasonCode': 'did_not_enter',
      },
      'roundingMode': roundingMode,
      'timePrecisionMs': timePrecisionMs,
      'timeSource': timeSource,
    };
  }
  if (timeSource == 'notRecorded') {
    if (playedTimeMs['state'] != 'unknown' ||
        roundingMode != 'notApplicable' ||
        !_absentFact(timePrecisionMs, 'no_time_source')) {
      _fail('invalidTimeProvenance', path);
    }
    return {
      'playedTimeMs': playedTimeMs,
      'possibleIntervalMs': {
        'state': 'unknown',
        'value': null,
        'reasonCode': 'no_time_source',
      },
      'roundingMode': roundingMode,
      'timePrecisionMs': timePrecisionMs,
      'timeSource': timeSource,
    };
  }
  if (timeSource == 'notApplicable' ||
      playedTimeMs['state'] != 'known' ||
      timePrecisionMs['state'] != 'known' ||
      timePrecisionMs['value'] == 0) {
    _fail('invalidTimeProvenance', path);
  }
  final played = playedTimeMs['value']! as int;
  final precision = timePrecisionMs['value']! as int;
  if (timeSource == 'officialSheetRounded') {
    final expectedMode = roundingProfile == 'nearest-half-up-v1'
        ? 'nearestHalfUp'
        : 'fiba2024ReferenceSheet';
    if (roundingMode != expectedMode || played % precision != 0) {
      _fail('invalidTimeProvenance', path);
    }
    if (roundingProfile == 'fiba-2024-reference-sheet-v1' &&
        precision != 60000) {
      _fail('invalidTimeProvenance', '$path.timePrecisionMs');
    }
    return {
      'playedTimeMs': playedTimeMs,
      'roundingMode': roundingMode,
      'timePrecisionMs': timePrecisionMs,
      'timeSource': timeSource,
    };
  }
  if (roundingMode != 'notApplicable') {
    _fail('invalidTimeProvenance', path);
  }
  return {
    'playedTimeMs': playedTimeMs,
    'possibleIntervalMs': {
      'state': 'known',
      'value': {
        'lowerInclusive': played,
        'upperExclusive': _safeAdd(played, precision, path),
      },
    },
    'roundingMode': roundingMode,
    'timePrecisionMs': timePrecisionMs,
    'timeSource': timeSource,
  };
}

Map<String, Object?> _validateDeparture(Object? value, String path) {
  final raw = _record(value, path, [
    'clockRemainingMs',
    'evidenceRefs',
    'kind',
    'periodNumber',
  ]);
  final kind = _enumeration(raw['kind'], '$path.kind', [
    'none',
    'fouledOut',
    'ejected',
    'injured',
    'other',
  ]);
  final periodNumber = _fact(
    raw['periodNumber'],
    '$path.periodNumber',
    _nonnegativeInteger,
  );
  final clockRemainingMs = _fact(
    raw['clockRemainingMs'],
    '$path.clockRemainingMs',
    _nonnegativeInteger,
  );
  final evidenceRefs = _fact(
    raw['evidenceRefs'],
    '$path.evidenceRefs',
    _stringList,
  );
  if (kind == 'none') {
    if (!_absentFact(periodNumber, 'no_departure') ||
        !_absentFact(clockRemainingMs, 'no_departure') ||
        !_absentFact(evidenceRefs, 'no_departure')) {
      _fail('invalidDeparture', path);
    }
  } else {
    if (periodNumber['state'] == 'notApplicable' ||
        clockRemainingMs['state'] == 'notApplicable' ||
        evidenceRefs['state'] != 'known') {
      _fail('invalidDeparture', path);
    }
    if (periodNumber['state'] == 'known' && periodNumber['value'] == 0) {
      _fail('invalidDeparture', path);
    }
    if (evidenceRefs['state'] == 'known' &&
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail('invalidDeparture', '$path.evidenceRefs');
    }
  }
  return {
    'clockRemainingMs': clockRemainingMs,
    'evidenceRefs': evidenceRefs,
    'kind': kind,
    'periodNumber': periodNumber,
  };
}

({Map<String, int> counts, Map<String, Object?> output}) _validatePlayer(
  Object? value,
  String path,
  String teamEntryId,
  String roundingProfile,
) {
  final raw = _record(value, path, [
    'counts',
    'departure',
    'enteredPlay',
    'participantId',
    'participationReasonCode',
    'participationStatus',
    'playerId',
    'rosterMembershipId',
    'rosterMembershipVersionId',
    'starter',
    'teamEntryId',
    'time',
  ]);
  final participantId = _identifier(
    raw['participantId'],
    '$path.participantId',
  );
  final playerId = _identifier(raw['playerId'], '$path.playerId');
  final rosterMembershipId = _identifier(
    raw['rosterMembershipId'],
    '$path.rosterMembershipId',
  );
  final rosterMembershipVersionId = _identifier(
    raw['rosterMembershipVersionId'],
    '$path.rosterMembershipVersionId',
  );
  final playerTeamEntryId = _identifier(
    raw['teamEntryId'],
    '$path.teamEntryId',
  );
  if (playerTeamEntryId != teamEntryId) {
    _fail('participantTeamMismatch', '$path.teamEntryId');
  }
  final participationStatus = _enumeration(
    raw['participationStatus'],
    '$path.participationStatus',
    ['active', 'dnp', 'inactive'],
  );
  final enteredPlay = _boolean(raw['enteredPlay'], '$path.enteredPlay');
  if ((participationStatus == 'active') != enteredPlay) {
    _fail('invalidParticipation', path);
  }
  final participationReasonCode = _fact(
    raw['participationReasonCode'],
    '$path.participationReasonCode',
    _identifier,
  );
  if (enteredPlay) {
    if (!_absentFact(participationReasonCode, 'entered_play')) {
      _fail('invalidParticipation', '$path.participationReasonCode');
    }
  } else if (participationReasonCode['state'] == 'notApplicable') {
    _fail('invalidParticipation', '$path.participationReasonCode');
  }
  final starter = _fact(raw['starter'], '$path.starter', _boolean);
  if (!enteredPlay && starter['state'] == 'known' && starter['value'] == true) {
    _fail('invalidParticipation', '$path.starter');
  }
  final counts = _parseCounts(raw['counts'], '$path.counts');
  if (!enteredPlay && !_allCountsZero(counts)) {
    _fail('dnpOrdinaryStat', '$path.counts');
  }
  if (counts['twoMade']! > counts['twoAttempted']!) {
    _fail('makesExceedAttempts', '$path.counts.twoMade');
  }
  if (counts['threeMade']! > counts['threeAttempted']!) {
    _fail('makesExceedAttempts', '$path.counts.threeMade');
  }
  if (counts['freeMade']! > counts['freeAttempted']!) {
    _fail('makesExceedAttempts', '$path.counts.freeMade');
  }
  final time = _validateTime(
    raw['time'],
    '$path.time',
    enteredPlay,
    roundingProfile,
  );
  final departure = _validateDeparture(raw['departure'], '$path.departure');
  if (!enteredPlay && departure['kind'] != 'none') {
    _fail('invalidDeparture', '$path.departure');
  }
  final totals = _derivedTotals(counts);
  return (
    counts: counts,
    output: {
      'departure': departure,
      'enteredPlay': enteredPlay,
      'gamesPlayed': enteredPlay ? 1 : 0,
      'participantId': participantId,
      'participationReasonCode': participationReasonCode,
      'participationStatus': participationStatus,
      'playerId': playerId,
      'rosterMembershipId': rosterMembershipId,
      'rosterMembershipVersionId': rosterMembershipVersionId,
      'shootingPercentages': _shootingPercentages(totals),
      'starter': starter,
      'teamEntryId': teamEntryId,
      'time': time,
      'totals': totals,
    },
  );
}

({Map<String, int> counts, Map<String, Object?> output}) _validateTeam(
  Object? value,
  String path,
  Set<String> seenParticipants,
  Set<String> seenPlayers,
  String roundingProfile,
) {
  final raw = _record(value, path, [
    'players',
    'reportedTotals',
    'side',
    'teamEntryId',
    'teamOnly',
  ]);
  final teamEntryId = _identifier(raw['teamEntryId'], '$path.teamEntryId');
  final side = _enumeration(raw['side'], '$path.side', ['home', 'away']);
  final playerValues = _list(raw['players'], '$path.players');
  if (playerValues.isEmpty) {
    _fail('invalidTeamStructure', '$path.players');
  }
  if (playerValues.length > NormalizedBoxScoreLimits.maxPlayersPerTeam) {
    _fail('resourceLimitExceeded', '$path.players');
  }
  final counts = _zeroCounts();
  final players = <Object?>[];
  for (var index = 0; index < playerValues.length; index += 1) {
    final parsed = _validatePlayer(
      playerValues[index],
      '$path.players[$index]',
      teamEntryId,
      roundingProfile,
    );
    final participantId = parsed.output['participantId']! as String;
    final playerId = parsed.output['playerId']! as String;
    if (seenParticipants.contains(participantId) ||
        seenPlayers.contains(playerId)) {
      _fail('duplicateParticipant', '$path.players[$index]');
    }
    seenParticipants.add(participantId);
    seenPlayers.add(playerId);
    _addCounts(counts, parsed.counts, '$path.players');
    players.add(parsed.output);
  }
  final teamOnlyRaw = _record(raw['teamOnly'], '$path.teamOnly', [
    'defensiveRebounds',
    'offensiveRebounds',
    'turnovers',
  ]);
  final teamOnly = <String, int>{
    'offensiveRebounds': _knownCount(
      teamOnlyRaw['offensiveRebounds'],
      '$path.teamOnly.offensiveRebounds',
    ),
    'defensiveRebounds': _knownCount(
      teamOnlyRaw['defensiveRebounds'],
      '$path.teamOnly.defensiveRebounds',
    ),
    'turnovers': _knownCount(
      teamOnlyRaw['turnovers'],
      '$path.teamOnly.turnovers',
    ),
  };
  for (final field in teamOnly.keys) {
    counts[field] = _safeAdd(
      counts[field]!,
      teamOnly[field]!,
      '$path.teamOnly.$field',
    );
  }
  final reportedTotals = _parseCounts(
    raw['reportedTotals'],
    '$path.reportedTotals',
  );
  for (final field in playerCountFields) {
    if (reportedTotals[field] != counts[field]) {
      _fail('reportedTeamTotalMismatch', '$path.reportedTotals.$field');
    }
  }
  final totals = _derivedTotals(counts);
  return (
    counts: counts,
    output: {
      'players': players,
      'side': side,
      'shootingPercentages': _shootingPercentages(totals),
      'teamEntryId': teamEntryId,
      'teamOnly': teamOnly,
      'totals': totals,
    },
  );
}

({
  Map<String, Object?> counterPoints,
  List<Object?> periods,
  Map<String, Object?> score,
  Map<String, Object?> totalElapsedMs,
})
_validatePeriods(
  Object? value,
  Map<String, Object?> rules,
  bool requiresCompletePlay,
) {
  final rawPeriods = _list(value, r'$.periods');
  if (rawPeriods.length > NormalizedBoxScoreLimits.maxPeriods) {
    _fail('resourceLimitExceeded', r'$.periods');
  }
  final regulationPeriodCount = rules['regulationPeriodCount']! as int;
  if (requiresCompletePlay && rawPeriods.length < regulationPeriodCount) {
    _fail('invalidPeriodSequence', r'$.periods');
  }
  final score = <String, Object?>{'home': 0, 'away': 0};
  final counterPoints = <String, Object?>{'home': 0, 'away': 0};
  final periods = <Object?>[];
  int? totalElapsed = 0;
  var cumulativeHome = 0;
  var cumulativeAway = 0;
  for (var index = 0; index < rawPeriods.length; index += 1) {
    final path =
        r'$.periods'
        '[$index]';
    final raw = _record(rawPeriods[index], path, [
      'awayScore',
      'completionState',
      'elapsedDurationMs',
      'exceptionalScoringPoints',
      'homeScore',
      'kind',
      'nominalDurationMs',
      'number',
      'overtimeIndex',
      'playerCounterPoints',
      'source',
    ]);
    final number = _positiveInteger(raw['number'], '$path.number');
    if (number != index + 1) _fail('invalidPeriodSequence', '$path.number');
    final kind = _enumeration(raw['kind'], '$path.kind', [
      'regulation',
      'overtime',
    ]);
    final overtimeIndex = _fact(
      raw['overtimeIndex'],
      '$path.overtimeIndex',
      _nonnegativeInteger,
    );
    if (number <= regulationPeriodCount) {
      if (kind != 'regulation' ||
          !_absentFact(overtimeIndex, 'regulation_period')) {
        _fail('invalidPeriodSequence', path);
      }
    } else {
      final expectedOvertime = number - regulationPeriodCount;
      final overtimePolicy = rules['overtimePolicy']! as Map<String, Object?>;
      if (overtimePolicy['allowed'] != true ||
          kind != 'overtime' ||
          overtimeIndex['state'] != 'known' ||
          overtimeIndex['value'] != expectedOvertime) {
        _fail('invalidOvertimeSequence', path);
      }
    }
    final nominalDurationMs = _countFact(
      raw['nominalDurationMs'],
      '$path.nominalDurationMs',
    );
    if (nominalDurationMs['state'] != 'known' ||
        nominalDurationMs['value'] == 0) {
      _fail('invalidPeriodState', '$path.nominalDurationMs');
    }
    if (kind == 'overtime') {
      final overtimePolicy = rules['overtimePolicy']! as Map<String, Object?>;
      final configured =
          overtimePolicy['nominalDurationMs']! as Map<String, Object?>;
      if (configured['state'] != 'known' ||
          nominalDurationMs['value'] != configured['value']) {
        _fail('invalidOvertimeSequence', '$path.nominalDurationMs');
      }
    }
    final elapsedDurationMs = _countFact(
      raw['elapsedDurationMs'],
      '$path.elapsedDurationMs',
    );
    final completionState = _enumeration(
      raw['completionState'],
      '$path.completionState',
      [
        'completed',
        'partial',
        'suspended',
        'resumedCompleted',
        'abandoned',
        'adjudicated',
      ],
    );
    if (completionState == 'completed' ||
        completionState == 'resumedCompleted') {
      if (elapsedDurationMs['state'] != 'known' ||
          elapsedDurationMs['value'] != nominalDurationMs['value']) {
        _fail('invalidPeriodState', '$path.elapsedDurationMs');
      }
    } else {
      if (elapsedDurationMs['state'] == 'notApplicable' ||
          (elapsedDurationMs['state'] == 'known' &&
              (elapsedDurationMs['value']! as int) >
                  (nominalDurationMs['value']! as int))) {
        _fail('invalidPeriodState', '$path.elapsedDurationMs');
      }
      if (index != rawPeriods.length - 1) {
        _fail('invalidPeriodState', '$path.completionState');
      }
    }
    if (requiresCompletePlay &&
        completionState != 'completed' &&
        completionState != 'resumedCompleted') {
      _fail('invalidPeriodState', '$path.completionState');
    }
    final homeScore = _nonnegativeInteger(raw['homeScore'], '$path.homeScore');
    final awayScore = _nonnegativeInteger(raw['awayScore'], '$path.awayScore');
    final playerCounterPoints = _scorePair(
      raw['playerCounterPoints'],
      '$path.playerCounterPoints',
    );
    final exceptionalScoringPoints = _scorePair(
      raw['exceptionalScoringPoints'],
      '$path.exceptionalScoringPoints',
    );
    if (playerCounterPoints['home'] != homeScore ||
        playerCounterPoints['away'] != awayScore ||
        (exceptionalScoringPoints['home']! as int) >
            (playerCounterPoints['home']! as int) ||
        (exceptionalScoringPoints['away']! as int) >
            (playerCounterPoints['away']! as int)) {
      _fail('playedScoreAttributionMismatch', path);
    }
    score['home'] = _safeAdd(
      score['home']! as int,
      homeScore,
      r'$.periods.homeScore',
    );
    score['away'] = _safeAdd(
      score['away']! as int,
      awayScore,
      r'$.periods.awayScore',
    );
    counterPoints['home'] = _safeAdd(
      counterPoints['home']! as int,
      playerCounterPoints['home']! as int,
      r'$.periods.playerCounterPoints.home',
    );
    counterPoints['away'] = _safeAdd(
      counterPoints['away']! as int,
      playerCounterPoints['away']! as int,
      r'$.periods.playerCounterPoints.away',
    );
    cumulativeHome = _safeAdd(
      cumulativeHome,
      homeScore,
      r'$.periods.homeScore',
    );
    cumulativeAway = _safeAdd(
      cumulativeAway,
      awayScore,
      r'$.periods.awayScore',
    );
    if (kind == 'overtime' &&
        index < rawPeriods.length - 1 &&
        cumulativeHome != cumulativeAway) {
      _fail('invalidOvertimeSequence', path);
    }
    if (number == regulationPeriodCount &&
        rawPeriods.length > number &&
        cumulativeHome != cumulativeAway) {
      _fail('invalidOvertimeSequence', path);
    }
    if (totalElapsed != null) {
      totalElapsed = elapsedDurationMs['state'] == 'known'
          ? _safeAdd(
              totalElapsed,
              elapsedDurationMs['value']! as int,
              r'$.periods.elapsedDurationMs',
            )
          : null;
    }
    final source = _enumeration(raw['source'], '$path.source', [
      'liveCounter',
      'officialSheet',
      'historicalEvidence',
    ]);
    periods.add({
      'awayScore': awayScore,
      'completionState': completionState,
      'elapsedDurationMs': elapsedDurationMs,
      'exceptionalScoringPoints': exceptionalScoringPoints,
      'homeScore': homeScore,
      'kind': kind,
      'nominalDurationMs': nominalDurationMs,
      'number': number,
      'overtimeIndex': overtimeIndex,
      'playerCounterPoints': playerCounterPoints,
      'source': source,
    });
  }
  return (
    counterPoints: counterPoints,
    periods: periods,
    score: score,
    totalElapsedMs: totalElapsed == null
        ? <String, Object?>{
            'reasonCode': 'elapsed_duration_unknown',
            'state': 'unknown',
            'value': null,
          }
        : <String, Object?>{'state': 'known', 'value': totalElapsed},
  );
}

({List<Object?> groups, Map<int, Map<String, Object?>> groupByPeriod})
_validatePenaltyGroups(Map<String, Object?> rules, List<Object?> periods) {
  final groups = rules['penaltyAccumulationGroups']! as List<Object?>;
  final groupByPeriod = <int, Map<String, Object?>>{};
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
    final group = groups[groupIndex]! as Map<String, Object?>;
    for (final periodNumberValue in group['periodNumbers']! as List<Object?>) {
      final periodNumber = periodNumberValue! as int;
      if (periodNumber > periods.length ||
          groupByPeriod.containsKey(periodNumber)) {
        _fail(
          'invalidPenaltyPolicy',
          r'$.rules.penaltyAccumulationGroups'
              '[$groupIndex].periodNumbers',
        );
      }
      groupByPeriod[periodNumber] = group;
    }
  }
  for (var number = 1; number <= periods.length; number += 1) {
    if (!groupByPeriod.containsKey(number)) {
      _fail('invalidPenaltyPolicy', r'$.rules.penaltyAccumulationGroups');
    }
  }
  if (periods.isEmpty && groups.isNotEmpty) {
    _fail('invalidPenaltyPolicy', r'$.rules.penaltyAccumulationGroups');
  }
  if (rules['rulesProfileId'] == 'fiba-2024-reference-v1') {
    final expected = <List<int>>[
      if (periods.isNotEmpty) [1],
      if (periods.length >= 2) [2],
      if (periods.length >= 3) [3],
      if (periods.length >= 4)
        [for (var number = 4; number <= periods.length; number += 1) number],
    ];
    if (groups.length != expected.length) {
      _fail('invalidPenaltyPolicy', r'$.rules.penaltyAccumulationGroups');
    }
    for (var index = 0; index < expected.length; index += 1) {
      final group = groups[index]! as Map<String, Object?>;
      final periodNumbers = group['periodNumbers']! as List<Object?>;
      final threshold = group['penaltyStartsAtFoul']! as Map<String, Object?>;
      if (periodNumbers.length != expected[index].length ||
          [for (final value in periodNumbers) value as int].join(',') !=
              expected[index].join(',') ||
          threshold['state'] != 'known' ||
          threshold['value'] != 5) {
        _fail(
          'invalidPenaltyPolicy',
          r'$.rules.penaltyAccumulationGroups'
              '[$index]',
        );
      }
    }
  }
  return (groups: groups, groupByPeriod: groupByPeriod);
}

Map<String, Object?> _roundedTimeInterval(
  Map<String, Object?> time,
  String profile,
  Map<String, Object?> totalElapsedMs,
  String path,
) {
  if (time.containsKey('possibleIntervalMs')) {
    return time['possibleIntervalMs']! as Map<String, Object?>;
  }
  final played =
      (time['playedTimeMs']! as Map<String, Object?>)['value']! as int;
  final precision =
      (time['timePrecisionMs']! as Map<String, Object?>)['value']! as int;
  if (time['timeSource'] != 'officialSheetRounded') {
    return {
      'state': 'known',
      'value': {
        'lowerInclusive': played,
        'upperExclusive': _safeAdd(played, precision, path),
      },
    };
  }
  if (profile == 'nearest-half-up-v1') {
    return {
      'state': 'known',
      'value': {
        'lowerInclusive': played - (precision ~/ 2) < 0
            ? 0
            : played - (precision ~/ 2),
        'upperExclusive': _safeAdd(played, (precision / 2).ceil(), path),
      },
    };
  }
  if (totalElapsedMs['state'] != 'known') {
    _fail('invalidTimeProvenance', path);
  }
  final maximum = totalElapsedMs['value']! as int;
  if (played == 0 || played > maximum || precision != 60000) {
    _fail('invalidTimeProvenance', path);
  }
  var lowerInclusive = played - 30000 < 1 ? 1 : played - 30000;
  var upperExclusive = _safeAdd(played, 30000, path);
  final maximumExclusive = _safeAdd(maximum, 1, path);
  if (upperExclusive > maximumExclusive) upperExclusive = maximumExclusive;
  if (played == 60000) lowerInclusive = 1;
  if (maximum % 60000 == 0 && played == maximum - 60000) {
    lowerInclusive = played - 30000 < 1 ? 1 : played - 30000;
    upperExclusive = maximum;
  }
  if (played == maximum) {
    lowerInclusive = maximum;
    upperExclusive = maximumExclusive;
  }
  if (lowerInclusive >= upperExclusive) {
    _fail('invalidTimeProvenance', path);
  }
  return {
    'state': 'known',
    'value': {
      'lowerInclusive': lowerInclusive,
      'upperExclusive': upperExclusive,
    },
  };
}

int? _knownElapsedBefore(List<Object?> periods, int periodNumber) {
  var elapsed = 0;
  for (var index = 0; index < periodNumber - 1; index += 1) {
    final period = periods[index]! as Map<String, Object?>;
    final value = period['elapsedDurationMs']! as Map<String, Object?>;
    if (value['state'] != 'known') return null;
    elapsed = _safeAdd(
      elapsed,
      value['value']! as int,
      r'$.periods.elapsedDurationMs',
    );
  }
  return elapsed;
}

int _nominalElapsedThrough(List<Object?> periods, int periodCount) {
  var elapsed = 0;
  for (var index = 0; index < periodCount; index += 1) {
    final period = periods[index]! as Map<String, Object?>;
    final nominal = period['nominalDurationMs']! as Map<String, Object?>;
    elapsed = _safeAdd(
      elapsed,
      nominal['value']! as int,
      r'$.periods.nominalDurationMs',
    );
  }
  return elapsed;
}

typedef _PermanentExitEvidence = ({
  Map<String, Object?> clockRemainingMs,
  int? incidentIndex,
  int periodNumber,
});

int _exitOpportunityUpperBound(
  List<Object?> periods,
  _PermanentExitEvidence exit,
  String path,
) {
  final period = periods[exit.periodNumber - 1]! as Map<String, Object?>;
  final nominal = period['nominalDurationMs']! as Map<String, Object?>;
  final elapsed = period['elapsedDurationMs']! as Map<String, Object?>;
  var opportunity = _nominalElapsedThrough(periods, exit.periodNumber - 1);
  if (exit.clockRemainingMs['state'] == 'known') {
    opportunity = _safeAdd(
      opportunity,
      (nominal['value']! as int) - (exit.clockRemainingMs['value']! as int),
      path,
    );
  } else {
    opportunity = _safeAdd(
      opportunity,
      elapsed['state'] == 'known'
          ? elapsed['value']! as int
          : nominal['value']! as int,
      path,
    );
  }
  return opportunity;
}

bool _eventOccursAfterExit(
  int eventPeriod,
  Map<String, Object?> eventClock,
  _PermanentExitEvidence exit,
) {
  if (eventPeriod != exit.periodNumber) return eventPeriod > exit.periodNumber;
  return eventClock['state'] == 'known' &&
      exit.clockRemainingMs['state'] == 'known' &&
      (eventClock['value']! as int) < (exit.clockRemainingMs['value']! as int);
}

void _validatePlayerTimeline(
  List<({Map<String, int> counts, Map<String, Object?> output})> teams,
  List<Object?> periods,
  Map<String, Object?> totalElapsedMs,
  Map<String, Object?> rules,
) {
  final durationUpperBound = totalElapsedMs['state'] == 'known'
      ? totalElapsedMs['value']! as int
      : _nominalElapsedThrough(periods, periods.length);
  for (final team in teams) {
    var knownTeamTimeLowerBound = 0;
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      final time = player['time']! as Map<String, Object?>;
      final path =
          r'$.participants.'
          '${player['participantId']}.time';
      final interval = _roundedTimeInterval(
        time,
        rules['playingTimeRoundingProfile']! as String,
        totalElapsedMs,
        path,
      );
      time['possibleIntervalMs'] = interval;
      if (interval['state'] == 'known') {
        final bounds = interval['value']! as Map<String, Object?>;
        if ((bounds['lowerInclusive']! as int) > durationUpperBound) {
          _fail('timeOutsideGameDuration', path);
        }
        knownTeamTimeLowerBound = _safeAdd(
          knownTeamTimeLowerBound,
          bounds['lowerInclusive']! as int,
          r'$.teams.'
          '${team.output['teamEntryId']}.players',
        );
      }
      final departure = player['departure']! as Map<String, Object?>;
      if (departure['kind'] == 'none') continue;
      final periodNumber = departure['periodNumber']! as Map<String, Object?>;
      final clock = departure['clockRemainingMs']! as Map<String, Object?>;
      if (clock['state'] == 'known' && periodNumber['state'] != 'known') {
        _fail(
          'eventClockOutsidePeriod',
          r'$.participants.'
              '${player['participantId']}.departure',
        );
      }
      if (periodNumber['state'] != 'known') continue;
      final number = periodNumber['value']! as int;
      if (number == 0 || number > periods.length) {
        _fail(
          'invalidDeparture',
          r'$.participants.'
              '${player['participantId']}.departure.periodNumber',
        );
      }
      final period = periods[number - 1]! as Map<String, Object?>;
      final nominal = period['nominalDurationMs']! as Map<String, Object?>;
      final elapsed = period['elapsedDurationMs']! as Map<String, Object?>;
      var opportunity = _nominalElapsedThrough(periods, number - 1);
      if (clock['state'] == 'known') {
        if (nominal['state'] != 'known' ||
            (clock['value']! as int) > (nominal['value']! as int)) {
          _fail(
            'eventClockOutsidePeriod',
            r'$.participants.'
                '${player['participantId']}.departure.clockRemainingMs',
          );
        }
        final elapsedAtDeparture =
            (nominal['value']! as int) - (clock['value']! as int);
        if (elapsed['state'] == 'known' &&
            elapsedAtDeparture > (elapsed['value']! as int)) {
          _fail(
            'eventClockOutsidePeriod',
            r'$.participants.'
                '${player['participantId']}.departure.clockRemainingMs',
          );
        }
        final knownBefore = _knownElapsedBefore(periods, number);
        opportunity = _safeAdd(
          knownBefore ?? opportunity,
          elapsedAtDeparture,
          r'$.participants.'
          '${player['participantId']}.departure',
        );
      } else {
        final currentPeriodUpper = elapsed['state'] == 'known'
            ? elapsed['value']! as int
            : nominal['value']! as int;
        opportunity = _safeAdd(
          opportunity,
          currentPeriodUpper,
          r'$.participants.'
          '${player['participantId']}.departure',
        );
      }
      if (interval['state'] == 'known') {
        final bounds = interval['value']! as Map<String, Object?>;
        if ((bounds['lowerInclusive']! as int) > opportunity) {
          _fail('departureTimeConflict', path);
        }
      }
    }
    final capacity =
        rules['teamTimeCapacityMultiplier']! as Map<String, Object?>;
    if (capacity['state'] == 'known' &&
        knownTeamTimeLowerBound >
            _safeMultiply(
              durationUpperBound,
              capacity['value']! as int,
              r'$.teams.'
              '${team.output['teamEntryId']}.players',
            )) {
      _fail(
        'timeOutsideGameDuration',
        r'$.teams.'
            '${team.output['teamEntryId']}.players',
      );
    }
  }
}

void _validatePermanentExitTimeConstraints(
  List<({Map<String, int> counts, Map<String, Object?> output})> teams,
  List<Object?> periods,
  Map<String, Object?> totalElapsedMs,
  Map<String, Object?> rules,
  Map<String, List<_PermanentExitEvidence>> disqualifications,
) {
  final durationUpperBound = totalElapsedMs['state'] == 'known'
      ? totalElapsedMs['value']! as int
      : _nominalElapsedThrough(periods, periods.length);
  for (final team in teams) {
    final playerDemands = <({int deadline, int minimum})>[];
    final exitDeadlines = <int>[];
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      final time = player['time']! as Map<String, Object?>;
      final interval = time['possibleIntervalMs']! as Map<String, Object?>;
      if (interval['state'] != 'known') continue;
      final exits = <_PermanentExitEvidence>[];
      final departure = player['departure']! as Map<String, Object?>;
      final departurePeriod =
          departure['periodNumber']! as Map<String, Object?>;
      if (departure['kind'] != 'none' && departurePeriod['state'] == 'known') {
        exits.add((
          clockRemainingMs:
              departure['clockRemainingMs']! as Map<String, Object?>,
          incidentIndex: null,
          periodNumber: departurePeriod['value']! as int,
        ));
      }
      exits.addAll(disqualifications[player['participantId']] ?? const []);
      final path =
          r'$.participants.'
          '${player['participantId']}.time';
      var earliestDeadline = durationUpperBound;
      for (final exit in exits) {
        final deadline = _exitOpportunityUpperBound(periods, exit, path);
        if (deadline < earliestDeadline) {
          earliestDeadline = deadline;
        }
      }
      final bounds = interval['value']! as Map<String, Object?>;
      final minimum = bounds['lowerInclusive']! as int;
      if (minimum > earliestDeadline) {
        _fail('departureTimeConflict', path);
      }
      playerDemands.add((deadline: earliestDeadline, minimum: minimum));
      if (exits.isNotEmpty) exitDeadlines.add(earliestDeadline);
    }
    final capacity =
        rules['teamTimeCapacityMultiplier']! as Map<String, Object?>;
    if (capacity['state'] != 'known') continue;
    final teamPath =
        r'$.teams.'
        '${team.output['teamEntryId']}.players';
    final checkpoints = exitDeadlines.toSet().toList()..sort();
    for (final checkpoint in checkpoints) {
      var requiredThroughCheckpoint = 0;
      for (final demand in playerDemands) {
        final availableAfterCheckpoint = demand.deadline > checkpoint
            ? demand.deadline - checkpoint
            : 0;
        final forcedBeforeOrAtCheckpoint =
            demand.minimum > availableAfterCheckpoint
            ? demand.minimum - availableAfterCheckpoint
            : 0;
        requiredThroughCheckpoint = _safeAdd(
          requiredThroughCheckpoint,
          forcedBeforeOrAtCheckpoint,
          teamPath,
        );
      }
      if (requiredThroughCheckpoint >
          _safeMultiply(checkpoint, capacity['value']! as int, teamPath)) {
        _fail('timeOutsideGameDuration', teamPath);
      }
    }
  }
}

Map<String, Object?> _evidenceFact(Object? value, String path) =>
    _fact(value, path, _stringList);

List<Object?> _validateScoreAdjustments(
  Object? value,
  List<Object?> periods,
  Set<String> teamIds,
  Map<String, Map<String, Object?>> participants,
) {
  final rawAdjustments = _list(value, r'$.playedScoreAdjustments');
  if (rawAdjustments.length >
      NormalizedBoxScoreLimits.maxPlayedScoreAdjustments) {
    _fail('resourceLimitExceeded', r'$.playedScoreAdjustments');
  }
  final adjustmentIds = <String>{};
  final requiredShots = <String, Map<String, int>>{};
  final adjustments = <Object?>[];
  for (var index = 0; index < rawAdjustments.length; index += 1) {
    final path =
        r'$.playedScoreAdjustments'
        '[$index]';
    final raw = _record(rawAdjustments[index], path, [
      'adjustmentId',
      'creditedParticipantId',
      'creditedShot',
      'evidenceRefs',
      'kind',
      'periodNumber',
      'points',
      'statisticalTreatment',
      'teamEntryId',
      'violatingTeamEntryId',
    ]);
    final adjustmentId = _identifier(raw['adjustmentId'], '$path.adjustmentId');
    if (!adjustmentIds.add(adjustmentId)) {
      _fail('invalidScoreAdjustment', '$path.adjustmentId');
    }
    final teamEntryId = _identifier(raw['teamEntryId'], '$path.teamEntryId');
    final violatingTeamEntryId = _identifier(
      raw['violatingTeamEntryId'],
      '$path.violatingTeamEntryId',
    );
    if (!teamIds.contains(teamEntryId) ||
        !teamIds.contains(violatingTeamEntryId) ||
        teamEntryId == violatingTeamEntryId) {
      _fail('invalidScoreAdjustment', '$path.violatingTeamEntryId');
    }
    final kind = _enumeration(raw['kind'], '$path.kind', [
      'accidentalOwnBasket',
      'defensiveGoaltending',
    ]);
    final points = _positiveInteger(raw['points'], '$path.points');
    final creditedShot = _enumeration(
      raw['creditedShot'],
      '$path.creditedShot',
      ['twoPointMade', 'threePointMade'],
    );
    if ((kind == 'accidentalOwnBasket' &&
            (points != 2 || creditedShot != 'twoPointMade')) ||
        (kind == 'defensiveGoaltending' &&
            ((points == 2 && creditedShot != 'twoPointMade') ||
                (points == 3 && creditedShot != 'threePointMade') ||
                (points != 2 && points != 3)))) {
      _fail('invalidScoreAdjustment', '$path.points');
    }
    final statisticalTreatment = _enumeration(
      raw['statisticalTreatment'],
      '$path.statisticalTreatment',
      ['includedInPlayerCounters', 'additiveToPlayerCounters'],
    );
    if (statisticalTreatment != 'includedInPlayerCounters') {
      _fail('invalidScoreAdjustment', '$path.statisticalTreatment');
    }
    final periodNumber = _fact(
      raw['periodNumber'],
      '$path.periodNumber',
      _nonnegativeInteger,
    );
    if (periodNumber['state'] != 'known' ||
        periodNumber['value'] == 0 ||
        (periodNumber['value']! as int) > periods.length) {
      _fail('invalidScoreAdjustment', '$path.periodNumber');
    }
    final creditedParticipantId = _fact(
      raw['creditedParticipantId'],
      '$path.creditedParticipantId',
      _identifier,
    );
    if (creditedParticipantId['state'] != 'known') {
      _fail('invalidScoreAdjustment', '$path.creditedParticipantId');
    }
    final participant = participants[creditedParticipantId['value']];
    if (participant == null ||
        participant['enteredPlay'] != true ||
        participant['teamEntryId'] != teamEntryId) {
      _fail('invalidScoreAdjustment', '$path.creditedParticipantId');
    }
    final output = participant['output']! as Map<String, Object?>;
    final departure = output['departure']! as Map<String, Object?>;
    final departurePeriod = departure['periodNumber']! as Map<String, Object?>;
    final number = periodNumber['value']! as int;
    if (departure['kind'] != 'none' &&
        departurePeriod['state'] == 'known' &&
        number > (departurePeriod['value']! as int)) {
      _fail('invalidScoreAdjustment', '$path.creditedParticipantId');
    }
    final evidenceRefs = _evidenceFact(
      raw['evidenceRefs'],
      '$path.evidenceRefs',
    );
    if (evidenceRefs['state'] != 'known' ||
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail('invalidScoreAdjustment', '$path.evidenceRefs');
    }
    final shotRequirement = requiredShots.putIfAbsent(
      creditedParticipantId['value']! as String,
      () => {'three': 0, 'two': 0},
    );
    final requirementKey = creditedShot == 'twoPointMade' ? 'two' : 'three';
    shotRequirement[requirementKey] = _safeAdd(
      shotRequirement[requirementKey]!,
      1,
      '$path.creditedShot',
    );
    adjustments.add({
      'adjustmentId': adjustmentId,
      'creditedParticipantId': creditedParticipantId,
      'creditedShot': creditedShot,
      'evidenceRefs': evidenceRefs,
      'kind': kind,
      'periodNumber': periodNumber,
      'points': points,
      'requiredCounterChanges': creditedShot == 'twoPointMade'
          ? {
              'threeAttempted': 0,
              'threeMade': 0,
              'twoAttempted': 1,
              'twoMade': 1,
            }
          : {
              'threeAttempted': 1,
              'threeMade': 1,
              'twoAttempted': 0,
              'twoMade': 0,
            },
      'statisticalTreatment': statisticalTreatment,
      'teamEntryId': teamEntryId,
      'violatingTeamEntryId': violatingTeamEntryId,
    });
  }
  for (final entry in requiredShots.entries) {
    final counts = participants[entry.key]!['counts']! as Map<String, int>;
    if (counts['twoMade']! < entry.value['two']! ||
        counts['twoAttempted']! < entry.value['two']! ||
        counts['threeMade']! < entry.value['three']! ||
        counts['threeAttempted']! < entry.value['three']!) {
      _fail('invalidScoreAdjustment', r'$.playedScoreAdjustments');
    }
  }
  return adjustments;
}

void _validateExceptionalPointsByPeriod(
  List<Object?> adjustments,
  List<Object?> periods,
  String homeTeamId,
  String awayTeamId,
) {
  final totals = <String, int>{};
  for (final adjustmentValue in adjustments) {
    final adjustment = adjustmentValue! as Map<String, Object?>;
    final periodNumber =
        (adjustment['periodNumber']! as Map<String, Object?>)['value']! as int;
    final teamEntryId = adjustment['teamEntryId']! as String;
    final key = '$periodNumber:$teamEntryId';
    totals[key] = _safeAdd(
      totals[key] ?? 0,
      adjustment['points']! as int,
      r'$.playedScoreAdjustments',
    );
  }
  for (final periodValue in periods) {
    final period = periodValue! as Map<String, Object?>;
    final number = period['number']! as int;
    final exceptional =
        period['exceptionalScoringPoints']! as Map<String, Object?>;
    if ((totals['$number:$homeTeamId'] ?? 0) != exceptional['home'] ||
        (totals['$number:$awayTeamId'] ?? 0) != exceptional['away']) {
      _fail(
        'invalidScoreAdjustment',
        r'$.periods'
            '[${number - 1}].exceptionalScoringPoints',
      );
    }
  }
}

void _validateAdjustmentDisqualificationEligibility(
  List<Object?> adjustments,
  Map<String, List<_PermanentExitEvidence>> disqualifications,
) {
  for (var index = 0; index < adjustments.length; index += 1) {
    final adjustment = adjustments[index]! as Map<String, Object?>;
    final participantId =
        (adjustment['creditedParticipantId']! as Map<String, Object?>)['value']!
            as String;
    final periodNumber =
        (adjustment['periodNumber']! as Map<String, Object?>)['value']! as int;
    if ((disqualifications[participantId] ?? const []).any(
      (exit) => periodNumber > exit.periodNumber,
    )) {
      _fail(
        'invalidScoreAdjustment',
        r'$.playedScoreAdjustments'
            '[$index].creditedParticipantId',
      );
    }
  }
}

({
  List<Object?> incidents,
  Map<String, Map<String, Object?>> byParticipant,
  Map<String, Map<String, Object?>> byTeam,
  Map<String, List<_PermanentExitEvidence>> disqualifications,
})
_validateDiscipline(
  Object? value,
  Set<String> teamIds,
  Map<String, Map<String, Object?>> participants,
  List<Object?> periods,
  ({List<Object?> groups, Map<int, Map<String, Object?>> groupByPeriod})
  penaltyPolicy,
) {
  final rawIncidents = _list(value, r'$.disciplineIncidents');
  if (rawIncidents.length > NormalizedBoxScoreLimits.maxIncidents) {
    _fail('resourceLimitExceeded', r'$.disciplineIncidents');
  }
  final incidentIds = <String>{};
  final disqualifications = <String, List<_PermanentExitEvidence>>{};
  final byParticipant = <String, Map<String, Object?>>{
    for (final participantId in participants.keys)
      participantId: {
        'byType': {
          'disqualifying': 0,
          'personal': 0,
          'technical': 0,
          'unsportsmanlike': 0,
        },
        'chargedFouls': 0,
        'playerDisqualificationCharges': 0,
        'relatedIncidentIds': <Object?>[],
      },
  };
  final byTeam = <String, Map<String, Object?>>{
    for (final teamId in teamIds)
      teamId: {
        'byParty': {'bench': 0, 'coach': 0, 'player': 0, 'team': 0},
        'byType': {
          'disqualifying': 0,
          'personal': 0,
          'technical': 0,
          'unsportsmanlike': 0,
        },
        'chargedFouls': 0,
        'playerDisqualificationCharges': 0,
        'teamFoulsByPeriod': <String, Object?>{
          for (final period in periods)
            '${(period! as Map<String, Object?>)['number']}': 0,
        },
      },
  };
  final incidents = <Object?>[];
  for (var index = 0; index < rawIncidents.length; index += 1) {
    final path =
        r'$.disciplineIncidents'
        '[$index]';
    final raw = _record(rawIncidents[index], path, [
      'chargedParticipantId',
      'chargedPartyKind',
      'clockRemainingMs',
      'context',
      'countsTowardPlayerDisqualification',
      'countsTowardTeamFoul',
      'evidenceRefs',
      'incidentId',
      'incidentType',
      'periodNumber',
      'relatedParticipantId',
      'scoresheetCode',
      'teamEntryId',
    ]);
    final incidentId = _identifier(raw['incidentId'], '$path.incidentId');
    if (!incidentIds.add(incidentId)) {
      _fail('invalidDisciplineIncident', '$path.incidentId');
    }
    final teamEntryId = _identifier(raw['teamEntryId'], '$path.teamEntryId');
    if (!teamIds.contains(teamEntryId)) {
      _fail('invalidDisciplineIncident', '$path.teamEntryId');
    }
    final context = _enumeration(raw['context'], '$path.context', [
      'onCourt',
      'bench',
      'preGame',
      'interval',
    ]);
    final chargedPartyKind = _enumeration(
      raw['chargedPartyKind'],
      '$path.chargedPartyKind',
      ['player', 'coach', 'bench', 'team'],
    );
    final chargedParticipantId = _fact(
      raw['chargedParticipantId'],
      '$path.chargedParticipantId',
      _identifier,
    );
    final relatedParticipantId = _fact(
      raw['relatedParticipantId'],
      '$path.relatedParticipantId',
      _identifier,
    );
    if (chargedPartyKind == 'player') {
      if (context != 'onCourt' || chargedParticipantId['state'] != 'known') {
        _fail('invalidDisciplineIncident', path);
      }
      final participant = participants[chargedParticipantId['value']];
      if (participant == null || participant['teamEntryId'] != teamEntryId) {
        _fail('invalidDisciplineIncident', '$path.chargedParticipantId');
      }
      if (participant['enteredPlay'] != true) {
        _fail('playerNotEnteredForIncident', '$path.chargedParticipantId');
      }
    } else {
      if (context == 'onCourt' ||
          !_absentFact(chargedParticipantId, 'not_player_charge')) {
        _fail('invalidDisciplineIncident', '$path.chargedParticipantId');
      }
    }
    if (relatedParticipantId['state'] == 'known') {
      final participant = participants[relatedParticipantId['value']];
      if (participant == null || participant['teamEntryId'] != teamEntryId) {
        _fail('invalidDisciplineIncident', '$path.relatedParticipantId');
      }
    }
    final incidentType = _enumeration(
      raw['incidentType'],
      '$path.incidentType',
      ['personal', 'technical', 'unsportsmanlike', 'disqualifying'],
    );
    if (chargedPartyKind != 'player' &&
        incidentType != 'technical' &&
        incidentType != 'disqualifying') {
      _fail('invalidDisciplineIncident', '$path.incidentType');
    }
    final scoresheetCode = _text(
      raw['scoresheetCode'],
      '$path.scoresheetCode',
      64,
    );
    final countsTowardTeamFoul = _boolean(
      raw['countsTowardTeamFoul'],
      '$path.countsTowardTeamFoul',
    );
    final countsTowardPlayerDisqualification = _boolean(
      raw['countsTowardPlayerDisqualification'],
      '$path.countsTowardPlayerDisqualification',
    );
    if ((countsTowardTeamFoul &&
            (chargedPartyKind != 'player' || context != 'onCourt')) ||
        (countsTowardPlayerDisqualification && chargedPartyKind != 'player')) {
      _fail('invalidDisciplineIncident', path);
    }
    final periodNumber = _fact(
      raw['periodNumber'],
      '$path.periodNumber',
      _nonnegativeInteger,
    );
    final clockRemainingMs = _fact(
      raw['clockRemainingMs'],
      '$path.clockRemainingMs',
      _nonnegativeInteger,
    );
    if (context == 'preGame') {
      if (!_absentFact(periodNumber, 'no_play_context') ||
          !_absentFact(clockRemainingMs, 'no_play_context')) {
        _fail('invalidDisciplineIncident', '$path.periodNumber');
      }
    } else {
      if (periodNumber['state'] != 'known' ||
          periodNumber['value'] == 0 ||
          (periodNumber['value']! as int) > periods.length) {
        _fail('invalidDisciplineIncident', '$path.periodNumber');
      }
      final number = periodNumber['value']! as int;
      final period = periods[number - 1]! as Map<String, Object?>;
      final nominal = period['nominalDurationMs']! as Map<String, Object?>;
      final elapsed = period['elapsedDurationMs']! as Map<String, Object?>;
      if (clockRemainingMs['state'] == 'known') {
        if (nominal['state'] != 'known' ||
            (clockRemainingMs['value']! as int) > (nominal['value']! as int)) {
          _fail('eventClockOutsidePeriod', '$path.clockRemainingMs');
        }
        if (elapsed['state'] == 'known' &&
            (nominal['value']! as int) - (clockRemainingMs['value']! as int) >
                (elapsed['value']! as int)) {
          _fail('eventClockOutsidePeriod', '$path.clockRemainingMs');
        }
      } else if (clockRemainingMs['state'] == 'notApplicable' &&
          !_absentFact(clockRemainingMs, 'interval_or_bench_context')) {
        _fail('invalidDisciplineIncident', '$path.clockRemainingMs');
      }
    }
    final evidenceRefs = _evidenceFact(
      raw['evidenceRefs'],
      '$path.evidenceRefs',
    );
    if (evidenceRefs['state'] != 'known' ||
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail('invalidDisciplineIncident', '$path.evidenceRefs');
    }
    final summary = byTeam[teamEntryId]!;
    final byParty = summary['byParty']! as Map<String, Object?>;
    final byType = summary['byType']! as Map<String, Object?>;
    byParty[chargedPartyKind] = _safeAdd(
      byParty[chargedPartyKind]! as int,
      1,
      path,
    );
    byType[incidentType] = _safeAdd(byType[incidentType]! as int, 1, path);
    summary['chargedFouls'] = _safeAdd(
      summary['chargedFouls']! as int,
      1,
      path,
    );
    if (countsTowardPlayerDisqualification) {
      summary['playerDisqualificationCharges'] = _safeAdd(
        summary['playerDisqualificationCharges']! as int,
        1,
        path,
      );
    }
    if (chargedPartyKind == 'player' &&
        chargedParticipantId['state'] == 'known') {
      final participantSummary = byParticipant[chargedParticipantId['value']]!;
      final participantByType =
          participantSummary['byType']! as Map<String, Object?>;
      participantByType[incidentType] = _safeAdd(
        participantByType[incidentType]! as int,
        1,
        path,
      );
      participantSummary['chargedFouls'] = _safeAdd(
        participantSummary['chargedFouls']! as int,
        1,
        path,
      );
      if (countsTowardPlayerDisqualification) {
        participantSummary['playerDisqualificationCharges'] = _safeAdd(
          participantSummary['playerDisqualificationCharges']! as int,
          1,
          path,
        );
      }
    }
    if (relatedParticipantId['state'] == 'known') {
      (byParticipant[relatedParticipantId['value']]!['relatedIncidentIds']!
              as List<Object?>)
          .add(incidentId);
    }
    if (countsTowardTeamFoul && periodNumber['state'] == 'known') {
      final teamFouls = summary['teamFoulsByPeriod']! as Map<String, Object?>;
      final key = '${periodNumber['value']}';
      teamFouls[key] = _safeAdd((teamFouls[key] ?? 0) as int, 1, path);
    }
    incidents.add({
      'chargedParticipantId': chargedParticipantId,
      'chargedPartyKind': chargedPartyKind,
      'clockRemainingMs': clockRemainingMs,
      'context': context,
      'countsTowardPlayerDisqualification': countsTowardPlayerDisqualification,
      'countsTowardTeamFoul': countsTowardTeamFoul,
      'evidenceRefs': evidenceRefs,
      'incidentId': incidentId,
      'incidentType': incidentType,
      'periodNumber': periodNumber,
      'relatedParticipantId': relatedParticipantId,
      'scoresheetCode': scoresheetCode,
      'teamEntryId': teamEntryId,
    });
  }
  for (var index = 0; index < incidents.length; index += 1) {
    final incident = incidents[index]! as Map<String, Object?>;
    final chargedParticipantId =
        incident['chargedParticipantId']! as Map<String, Object?>;
    final periodNumber = incident['periodNumber']! as Map<String, Object?>;
    if (incident['chargedPartyKind'] != 'player' ||
        chargedParticipantId['state'] != 'known' ||
        periodNumber['state'] != 'known' ||
        incident['incidentType'] != 'disqualifying') {
      continue;
    }
    final participantId = chargedParticipantId['value']! as String;
    disqualifications.putIfAbsent(participantId, () => []).add((
      clockRemainingMs: incident['clockRemainingMs']! as Map<String, Object?>,
      incidentIndex: index,
      periodNumber: periodNumber['value']! as int,
    ));
  }
  for (var index = 0; index < incidents.length; index += 1) {
    final incident = incidents[index]! as Map<String, Object?>;
    final chargedParticipantId =
        incident['chargedParticipantId']! as Map<String, Object?>;
    final periodNumber = incident['periodNumber']! as Map<String, Object?>;
    if (incident['chargedPartyKind'] != 'player' ||
        chargedParticipantId['state'] != 'known' ||
        periodNumber['state'] != 'known') {
      continue;
    }
    final participantId = chargedParticipantId['value']! as String;
    final clock = incident['clockRemainingMs']! as Map<String, Object?>;
    final participant = participants[participantId]!;
    final output = participant['output']! as Map<String, Object?>;
    final departure = output['departure']! as Map<String, Object?>;
    final departurePeriod = departure['periodNumber']! as Map<String, Object?>;
    if (departure['kind'] != 'none' &&
        departurePeriod['state'] == 'known' &&
        _eventOccursAfterExit(periodNumber['value']! as int, clock, (
          clockRemainingMs:
              departure['clockRemainingMs']! as Map<String, Object?>,
          incidentIndex: null,
          periodNumber: departurePeriod['value']! as int,
        ))) {
      _fail(
        'invalidDisciplineIncident',
        r'$.disciplineIncidents'
            '[$index].chargedParticipantId',
      );
    }
    for (final exit in disqualifications[participantId] ?? const []) {
      if (exit.incidentIndex != index &&
          _eventOccursAfterExit(periodNumber['value']! as int, clock, exit)) {
        _fail(
          'invalidDisciplineIncident',
          r'$.disciplineIncidents'
              '[$index].chargedParticipantId',
        );
      }
    }
  }
  for (final entry in disqualifications.entries) {
    final participantId = entry.key;
    final output =
        participants[participantId]!['output']! as Map<String, Object?>;
    final departure = output['departure']! as Map<String, Object?>;
    final departurePeriod = departure['periodNumber']! as Map<String, Object?>;
    final departureClock =
        departure['clockRemainingMs']! as Map<String, Object?>;
    if (departure['kind'] == 'none' || departurePeriod['state'] != 'known') {
      continue;
    }
    for (final exit in entry.value) {
      if ((departurePeriod['value']! as int) != exit.periodNumber ||
          (departureClock['state'] == 'known' &&
              exit.clockRemainingMs['state'] == 'known' &&
              departureClock['value'] != exit.clockRemainingMs['value'])) {
        _fail(
          'invalidDeparture',
          r'$.participants.'
              '$participantId.departure',
        );
      }
    }
  }
  for (final summary in byTeam.values) {
    final teamFouls = summary['teamFoulsByPeriod']! as Map<String, Object?>;
    final penaltyStateByPeriod = <String, Object?>{};
    final penaltyGroups = <Object?>[];
    for (final groupValue in penaltyPolicy.groups) {
      final group = groupValue! as Map<String, Object?>;
      var groupTeamFouls = 0;
      final threshold = group['penaltyStartsAtFoul']! as Map<String, Object?>;
      for (final numberValue in group['periodNumbers']! as List<Object?>) {
        final periodNumber = numberValue! as int;
        groupTeamFouls = _safeAdd(
          groupTeamFouls,
          (teamFouls['$periodNumber'] ?? 0) as int,
          r'$.disciplineIncidents',
        );
        penaltyStateByPeriod['$periodNumber'] = {
          'groupId': group['groupId'],
          'groupTeamFoulsThroughPeriod': groupTeamFouls,
          'inPenalty': threshold['state'] == 'known'
              ? {
                  'state': 'known',
                  'value': groupTeamFouls >= (threshold['value']! as int) - 1,
                }
              : threshold,
          'rawTeamFouls': (teamFouls['$periodNumber'] ?? 0) as int,
          'threshold': threshold,
        };
      }
      penaltyGroups.add({
        'groupId': group['groupId'],
        'inPenalty': threshold['state'] == 'known'
            ? {
                'state': 'known',
                'value': groupTeamFouls >= (threshold['value']! as int) - 1,
              }
            : threshold,
        'periodNumbers': group['periodNumbers'],
        'teamFouls': groupTeamFouls,
        'threshold': threshold,
      });
    }
    summary['penaltyGroups'] = penaltyGroups;
    summary['penaltyStateByPeriod'] = penaltyStateByPeriod;
  }
  return (
    incidents: incidents,
    byParticipant: byParticipant,
    byTeam: byTeam,
    disqualifications: disqualifications,
  );
}

Map<String, Object?> _validateAdministrativeResult(
  Object? value,
  String disposition,
  String statisticsDisposition,
  Set<String> teamIds,
  String homeTeamEntryId,
) {
  final raw = _record(value, r'$.administrativeResult', [
    'awardedScore',
    'evidenceRefs',
    'playerStatisticsTreatment',
    'standingsTreatment',
    'winnerTeamEntryId',
  ]);
  final awardedScore = _fact(
    raw['awardedScore'],
    r'$.administrativeResult.awardedScore',
    _scorePair,
  );
  final winnerTeamEntryId = _fact(
    raw['winnerTeamEntryId'],
    r'$.administrativeResult.winnerTeamEntryId',
    _identifier,
  );
  final evidenceRefs = _evidenceFact(
    raw['evidenceRefs'],
    r'$.administrativeResult.evidenceRefs',
  );
  final standingsTreatment = _enumeration(
    raw['standingsTreatment'],
    r'$.administrativeResult.standingsTreatment',
    ['playedResult', 'awardedResult', 'excluded', 'policyPending'],
  );
  final playerStatisticsTreatment = _enumeration(
    raw['playerStatisticsTreatment'],
    r'$.administrativeResult.playerStatisticsTreatment',
    ['includePlayedStatistics', 'exclude', 'policyPending'],
  );
  if (disposition == 'played') {
    if (statisticsDisposition != 'complete' ||
        !_absentFact(awardedScore, 'not_adjudicated') ||
        !_absentFact(winnerTeamEntryId, 'not_adjudicated') ||
        !_absentFact(evidenceRefs, 'not_adjudicated') ||
        standingsTreatment != 'playedResult' ||
        playerStatisticsTreatment != 'includePlayedStatistics') {
      _fail('invalidAdministrativeResult', r'$.administrativeResult');
    }
  } else {
    if (winnerTeamEntryId['state'] == 'known' &&
        !teamIds.contains(winnerTeamEntryId['value'])) {
      _fail(
        'invalidAdministrativeResult',
        r'$.administrativeResult.winnerTeamEntryId',
      );
    }
    if (evidenceRefs['state'] != 'known' ||
        (evidenceRefs['value']! as List<Object?>).isEmpty ||
        playerStatisticsTreatment == 'policyPending') {
      _fail('invalidAdministrativeResult', r'$.administrativeResult');
    }
    if (statisticsDisposition == 'complete' &&
        playerStatisticsTreatment != 'includePlayedStatistics') {
      _fail(
        'invalidAdministrativeResult',
        r'$.administrativeResult.playerStatisticsTreatment',
      );
    }
    if (statisticsDisposition != 'complete' &&
        playerStatisticsTreatment != 'exclude') {
      _fail(
        'invalidAdministrativeResult',
        r'$.administrativeResult.playerStatisticsTreatment',
      );
    }
    if ((disposition == 'forfeit' || disposition == 'default') &&
        (awardedScore['state'] != 'known' ||
            winnerTeamEntryId['state'] != 'known')) {
      _fail('invalidAdministrativeResult', r'$.administrativeResult');
    }
    if (standingsTreatment == 'awardedResult' &&
        (awardedScore['state'] != 'known' ||
            winnerTeamEntryId['state'] != 'known')) {
      _fail('invalidAdministrativeResult', r'$.administrativeResult');
    }
    if (awardedScore['state'] == 'known' &&
        winnerTeamEntryId['state'] == 'known') {
      final score = awardedScore['value']! as Map<String, Object?>;
      final winnerIsHome = winnerTeamEntryId['value'] == homeTeamEntryId;
      final winnerScore = score[winnerIsHome ? 'home' : 'away']! as int;
      final loserScore = score[winnerIsHome ? 'away' : 'home']! as int;
      if (winnerScore <= loserScore) {
        _fail(
          'invalidAdministrativeResult',
          r'$.administrativeResult.winnerTeamEntryId',
        );
      }
    }
  }
  return {
    'awardedScore': awardedScore,
    'evidenceRefs': evidenceRefs,
    'playerStatisticsTreatment': playerStatisticsTreatment,
    'standingsTreatment': standingsTreatment,
    'winnerTeamEntryId': winnerTeamEntryId,
  };
}

Map<String, Object?> _validateOfficialScore(
  Object? value,
  Map<String, Object?> playedScore,
) {
  final raw = _record(value, r'$.officialScore', [
    'evidenceRefs',
    'reconciliationStatus',
    'score',
  ]);
  final score = _fact(raw['score'], r'$.officialScore.score', _scorePair);
  final evidenceRefs = _evidenceFact(
    raw['evidenceRefs'],
    r'$.officialScore.evidenceRefs',
  );
  final reconciliationStatus = _enumeration(
    raw['reconciliationStatus'],
    r'$.officialScore.reconciliationStatus',
    ['reconciled', 'unreconciled', 'notAvailable'],
  );
  if (reconciliationStatus != 'reconciled' ||
      score['state'] != 'known' ||
      evidenceRefs['state'] != 'known' ||
      (evidenceRefs['value']! as List<Object?>).isEmpty) {
    _fail('officialScoreEvidenceRequired', r'$.officialScore');
  }
  final knownScore = score['value']! as Map<String, Object?>;
  if (knownScore['home'] != playedScore['home'] ||
      knownScore['away'] != playedScore['away']) {
    _fail('officialScoreMismatch', r'$.officialScore.score');
  }
  return {
    'evidenceRefs': evidenceRefs,
    'reconciliationStatus': reconciliationStatus,
    'score': score,
  };
}

Map<String, Object?> _validateRoot(Object? value) {
  final raw = _record(value, r'$', [
    'administrativeResult',
    'calculatorVersion',
    'canonicalEncodingVersion',
    'disciplineIncidents',
    'officialScore',
    'periods',
    'playedScore',
    'playedScoreAdjustments',
    'provenance',
    'resultDisposition',
    'rules',
    'schemaVersion',
    'scope',
    'statisticsDisposition',
    'teams',
    'unicodeNormalizationVersion',
  ]);
  final schemaVersion = _nonnegativeInteger(
    raw['schemaVersion'],
    r'$.schemaVersion',
  );
  if (schemaVersion != 2) {
    _fail('unsupportedSchemaVersion', r'$.schemaVersion');
  }
  if (raw['calculatorVersion'] != normalizedBoxScoreCalculatorVersion) {
    _fail('unsupportedCalculatorVersion', r'$.calculatorVersion');
  }
  if (raw['canonicalEncodingVersion'] !=
      OfficialStatContractVersions.canonicalEncoding) {
    _fail('unsupportedCanonicalEncodingVersion', r'$.canonicalEncodingVersion');
  }
  if (raw['unicodeNormalizationVersion'] != normalizedBoxScoreUnicodeVersion) {
    _fail(
      'unsupportedUnicodeNormalizationVersion',
      r'$.unicodeNormalizationVersion',
    );
  }
  final scope = _validateScope(raw['scope']);
  final resultDisposition = _enumeration(
    raw['resultDisposition'],
    r'$.resultDisposition',
    ['played', 'forfeit', 'default', 'annulled', 'otherAdjudicated'],
  );
  final statisticsDisposition = _enumeration(
    raw['statisticsDisposition'],
    r'$.statisticsDisposition',
    ['complete', 'resultOnly', 'excluded'],
  );
  final provenanceRaw = _record(raw['provenance'], r'$.provenance', [
    'captureMode',
    'rulesetVersion',
    'sourceId',
    'sourceLabel',
  ]);
  final provenance = <String, Object?>{
    'captureMode': _enumeration(
      provenanceRaw['captureMode'],
      r'$.provenance.captureMode',
      ['liveCapture', 'officialSheet', 'historicalImport'],
    ),
    'rulesetVersion': _identifier(
      provenanceRaw['rulesetVersion'],
      r'$.provenance.rulesetVersion',
    ),
    'sourceId': _identifier(
      provenanceRaw['sourceId'],
      r'$.provenance.sourceId',
    ),
    'sourceLabel': _text(
      provenanceRaw['sourceLabel'],
      r'$.provenance.sourceLabel',
    ),
  };
  final rules = _validateRules(raw['rules']);
  final teams = _list(raw['teams'], r'$.teams');
  if (teams.length != 2) _fail('invalidTeamStructure', r'$.teams');
  return {
    'administrativeResult': raw['administrativeResult'],
    'disciplineIncidents': raw['disciplineIncidents'],
    'officialScore': raw['officialScore'],
    'periods': raw['periods'],
    'playedScore': raw['playedScore'],
    'playedScoreAdjustments': raw['playedScoreAdjustments'],
    'provenance': provenance,
    'resultDisposition': resultDisposition,
    'rules': rules,
    'scope': scope,
    'statisticsDisposition': statisticsDisposition,
    'teams': teams,
  };
}

void _validateNoPlay(
  Map<String, Object?> root,
  List<({Map<String, int> counts, Map<String, Object?> output})> teams,
  List<Object?> periods,
  Map<String, Object?> playedScore,
  List<Object?> adjustments,
  List<Object?> incidents,
) {
  final representedPlay =
      periods.any((periodValue) {
        final period = periodValue! as Map<String, Object?>;
        final elapsed = period['elapsedDurationMs']! as Map<String, Object?>;
        return elapsed['state'] != 'known' || (elapsed['value']! as int) > 0;
      }) ||
      playedScore['home'] != 0 ||
      playedScore['away'] != 0 ||
      adjustments.isNotEmpty;
  if (root['statisticsDisposition'] != 'complete' &&
      (root['resultDisposition'] == 'played' || representedPlay)) {
    _fail('invalidNoPlayStatistics', r'$');
  }
  if (representedPlay) return;
  for (final team in teams) {
    if (!_allCountsZero(team.counts)) {
      _fail('invalidNoPlayStatistics', r'$.teams');
    }
    final teamOnly = team.output['teamOnly']! as Map<String, int>;
    if (teamOnly['offensiveRebounds'] != 0 ||
        teamOnly['defensiveRebounds'] != 0 ||
        teamOnly['turnovers'] != 0) {
      _fail('invalidNoPlayStatistics', r'$.teams');
    }
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      if (player['enteredPlay'] == true) {
        _fail(
          'invalidNoPlayStatistics',
          r'$.participants.'
              '${player['participantId']}.enteredPlay',
        );
      }
    }
  }
  for (final incidentValue in incidents) {
    final incident = incidentValue! as Map<String, Object?>;
    if (incident['context'] != 'preGame' ||
        incident['chargedPartyKind'] == 'player' ||
        incident['countsTowardTeamFoul'] == true ||
        incident['countsTowardPlayerDisqualification'] == true) {
      _fail('invalidNoPlayStatistics', r'$.disciplineIncidents');
    }
  }
}

Object? _deepUnmodifiable(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, Object?>({
      for (final entry in value.entries)
        entry.key as String: _deepUnmodifiable(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
  }
  return value;
}

Map<String, Object?> _calculateAccepted(Object? rawInput) {
  final root = _validateRoot(rawInput);
  final rules = root['rules']! as Map<String, Object?>;
  final requiresCompletePlay = root['resultDisposition'] == 'played';
  final periodResult = _validatePeriods(
    root['periods'],
    rules,
    requiresCompletePlay,
  );
  final penaltyPolicy = _validatePenaltyGroups(rules, periodResult.periods);
  final seenParticipants = <String>{};
  final seenPlayers = <String>{};
  final rawTeams = root['teams']! as List<Object?>;
  final teamResults =
      <({Map<String, int> counts, Map<String, Object?> output})>[
        for (var index = 0; index < rawTeams.length; index += 1)
          _validateTeam(
            rawTeams[index],
            r'$.teams'
            '[$index]',
            seenParticipants,
            seenPlayers,
            rules['playingTimeRoundingProfile']! as String,
          ),
      ];
  if (teamResults[0].output['side'] == teamResults[1].output['side'] ||
      teamResults[0].output['teamEntryId'] ==
          teamResults[1].output['teamEntryId']) {
    _fail('invalidTeamStructure', r'$.teams');
  }
  teamResults.sort((left, right) {
    if (left.output['side'] == 'home') return -1;
    if (right.output['side'] == 'home') return 1;
    return 0;
  });
  final homeTeam = teamResults[0];
  final awayTeam = teamResults[1];
  _validatePlayerTimeline(
    teamResults,
    periodResult.periods,
    periodResult.totalElapsedMs,
    rules,
  );
  final playedScore = _scorePair(root['playedScore'], r'$.playedScore');
  if (periodResult.score['home'] != playedScore['home'] ||
      periodResult.score['away'] != playedScore['away']) {
    _fail('playedScorePeriodMismatch', r'$.playedScore');
  }
  if (root['resultDisposition'] == 'played' &&
      rules['completedTiesAllowed'] == false &&
      playedScore['home'] == playedScore['away']) {
    _fail('invalidPeriodSequence', r'$.playedScore');
  }
  final homeTotals = homeTeam.output['totals']! as Map<String, int>;
  final awayTotals = awayTeam.output['totals']! as Map<String, int>;
  if (periodResult.counterPoints['home'] != homeTotals['points'] ||
      periodResult.counterPoints['away'] != awayTotals['points'] ||
      homeTotals['points'] != playedScore['home'] ||
      awayTotals['points'] != playedScore['away']) {
    _fail('playedScoreAttributionMismatch', r'$.playedScore');
  }
  final teamIds = <String>{
    homeTeam.output['teamEntryId']! as String,
    awayTeam.output['teamEntryId']! as String,
  };
  final participants = <String, Map<String, Object?>>{};
  for (final team in teamResults) {
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      participants[player['participantId']! as String] = {
        'counts': player['totals']! as Map<String, int>,
        'enteredPlay': player['enteredPlay'],
        'output': player,
        'teamEntryId': player['teamEntryId'],
      };
    }
  }
  final adjustments = _validateScoreAdjustments(
    root['playedScoreAdjustments'],
    periodResult.periods,
    teamIds,
    participants,
  );
  _validateExceptionalPointsByPeriod(
    adjustments,
    periodResult.periods,
    homeTeam.output['teamEntryId']! as String,
    awayTeam.output['teamEntryId']! as String,
  );
  final discipline = _validateDiscipline(
    root['disciplineIncidents'],
    teamIds,
    participants,
    periodResult.periods,
    penaltyPolicy,
  );
  _validateAdjustmentDisqualificationEligibility(
    adjustments,
    discipline.disqualifications,
  );
  _validatePermanentExitTimeConstraints(
    teamResults,
    periodResult.periods,
    periodResult.totalElapsedMs,
    rules,
    discipline.disqualifications,
  );
  for (final team in teamResults) {
    team.output['discipline'] = discipline.byTeam[team.output['teamEntryId']]!;
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      player['discipline'] = discipline.byParticipant[player['participantId']]!;
    }
  }
  final administrativeResult = _validateAdministrativeResult(
    root['administrativeResult'],
    root['resultDisposition']! as String,
    root['statisticsDisposition']! as String,
    teamIds,
    homeTeam.output['teamEntryId']! as String,
  );
  final officialScore = _validateOfficialScore(
    root['officialScore'],
    playedScore,
  );
  _validateNoPlay(
    root,
    teamResults,
    periodResult.periods,
    playedScore,
    adjustments,
    discipline.incidents,
  );
  final diagnostics = <Object?>[];
  if (homeTotals['steals']! > awayTotals['turnovers']!) {
    diagnostics.add({
      'code': 'crossTeamStealsVsTurnoversNeedsReview',
      'opponentTurnovers': awayTotals['turnovers'],
      'path':
          r'$.teams.'
          '${homeTeam.output['teamEntryId']}.totals.steals',
      'severity': 'evidenceReview',
      'steals': homeTotals['steals'],
    });
  }
  if (awayTotals['steals']! > homeTotals['turnovers']!) {
    diagnostics.add({
      'code': 'crossTeamStealsVsTurnoversNeedsReview',
      'opponentTurnovers': homeTotals['turnovers'],
      'path':
          r'$.teams.'
          '${awayTeam.output['teamEntryId']}.totals.steals',
      'severity': 'evidenceReview',
      'steals': awayTotals['steals'],
    });
  }
  diagnostics.sort(
    (left, right) => ((left! as Map<String, Object?>)['path']! as String)
        .compareTo((right! as Map<String, Object?>)['path']! as String),
  );
  final playedWinnerTeamEntryId = playedScore['home'] == playedScore['away']
      ? <String, Object?>{
          'reasonCode': 'tied_played_score',
          'state': 'unknown',
          'value': null,
        }
      : <String, Object?>{
          'state': 'known',
          'value': (playedScore['home']! as int) > (playedScore['away']! as int)
              ? homeTeam.output['teamEntryId']
              : awayTeam.output['teamEntryId'],
        };
  final multiplier =
      rules['teamTimeCapacityMultiplier']! as Map<String, Object?>;
  final totalElapsed = periodResult.totalElapsedMs;
  final teamPlayedTimeCapacityMs =
      totalElapsed['state'] == 'known' && multiplier['state'] == 'known'
      ? <String, Object?>{
          'state': 'known',
          'value': _safeMultiply(
            totalElapsed['value']! as int,
            multiplier['value']! as int,
            r'$.rules.teamTimeCapacityMultiplier',
          ),
        }
      : <String, Object?>{
          'reasonCode': 'capacity_input_unknown',
          'state': 'unknown',
          'value': null,
        };
  final result = <String, Object?>{
    'calculatorVersion': normalizedBoxScoreCalculatorVersion,
    'normalizedBoxScore': {
      'administrativeResult': administrativeResult,
      'canonicalEncodingVersion':
          OfficialStatContractVersions.canonicalEncoding,
      'diagnostics': diagnostics,
      'disciplineIncidents': discipline.incidents,
      'officialScore': officialScore,
      'periods': periodResult.periods,
      'playedScore': playedScore,
      'playedScoreAdjustments': adjustments,
      'playedWinnerTeamEntryId': playedWinnerTeamEntryId,
      'provenance': root['provenance'],
      'resultDisposition': root['resultDisposition'],
      'rules': {...rules, 'teamPlayedTimeCapacityMs': teamPlayedTimeCapacityMs},
      'schemaVersion': 2,
      'scope': root['scope'],
      'statisticsDisposition': root['statisticsDisposition'],
      'teams': [for (final team in teamResults) team.output],
      'totalElapsedPlayMs': totalElapsed,
      'unicodeNormalizationVersion': normalizedBoxScoreUnicodeVersion,
    },
    'status': 'accepted',
  };
  return _deepUnmodifiable(result)! as Map<String, Object?>;
}

Map<String, Object?> _rejected(String code, String path) {
  final result = <String, Object?>{
    'calculatorVersion': normalizedBoxScoreCalculatorVersion,
    'errors': [
      {'code': code, 'path': path},
    ],
    'status': 'rejected',
  };
  return _deepUnmodifiable(result)! as Map<String, Object?>;
}

/// Pure deterministic normalized box-score calculator.
///
/// It returns exactly the first error in the stable validation sequence. It
/// performs no I/O, imports no Firebase runtime, and never mutates [input].
Map<String, Object?> calculateNormalizedBoxScore(Object? input) {
  try {
    final boundedInput = _preflight(input);
    return _calculateAccepted(boundedInput);
  } on _ValidationFailure catch (error) {
    return _rejected(error.code, error.path);
  } on Object {
    return _rejected('invalidCanonicalValue', r'$');
  }
}

/// Raw JSON boundary for untrusted transports. The byte limit is enforced
/// before parsing and the decoded graph receives the independent preflight.
Map<String, Object?> calculateNormalizedBoxScoreFromJson(String rawJson) {
  if (_utf8Length(rawJson) > NormalizedBoxScoreLimits.maxRawTransportBytes) {
    return _rejected('resourceLimitExceeded', r'$');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } on Object {
    return _rejected('invalidCanonicalValue', r'$');
  }
  return calculateNormalizedBoxScore(decoded);
}
