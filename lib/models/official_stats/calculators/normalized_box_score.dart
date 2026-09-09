import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../canonical_encoding.dart';
import '../contract_versions.dart';

const normalizedBoxScoreCalculatorVersion =
    'hoopsconnect-normalized-box-score-v1';
const normalizedBoxScoreUnicodeVersion = 'official-stat-unicode-nfc-v1';

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
  'eventClockOutsidePeriod',
  'makesExceedAttempts',
  'reportedTeamTotalMismatch',
  'invalidPeriodSequence',
  'invalidOvertimeSequence',
  'playedScorePeriodMismatch',
  'playedScoreAttributionMismatch',
  'invalidScoreAdjustment',
  'invalidDisciplineIncident',
  'invalidAdministrativeResult',
  'officialScoreEvidenceRequired',
  'officialScoreMismatch',
];

abstract final class NormalizedBoxScoreLimits {
  static const maxCanonicalPayloadBytes = 128 * 1024;
  static const maxDepth = 16;
  static const maxEvidenceRefsPerFact = 64;
  static const maxIncidents = 512;
  static const maxNodes = 20000;
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

List<String> _sortedKeys(Map<Object?, Object?> value) {
  final keys = <String>[];
  for (final key in value.keys) {
    if (key is! String) _fail('invalidCanonicalValue', r'$');
    keys.add(key);
  }
  return keys..sort();
}

void _preflight(Object? value) {
  var nodes = 0;

  void visit(Object? current, String path, int depth) {
    nodes += 1;
    if (nodes > NormalizedBoxScoreLimits.maxNodes ||
        depth > NormalizedBoxScoreLimits.maxDepth) {
      _fail('resourceLimitExceeded', path);
    }
    if (current == null || current is bool) return;
    if (current is String) {
      if (_utf8Length(current) > NormalizedBoxScoreLimits.maxStringBytes) {
        _fail('resourceLimitExceeded', path);
      }
      return;
    }
    if (current is num) {
      if (!current.isFinite ||
          current < 0 ||
          current > OfficialStatCanonicalEncoding.maxSafeInteger ||
          current != current.truncateToDouble()) {
        _fail('invalidNonnegativeSafeInteger', path);
      }
      return;
    }
    if (current is List<Object?>) {
      for (var index = 0; index < current.length; index += 1) {
        visit(current[index], '$path[$index]', depth + 1);
      }
      return;
    }
    if (current is Map<Object?, Object?>) {
      final keys = _sortedKeys(current);
      for (final key in keys) {
        if (!_asciiKey.hasMatch(key)) _fail('invalidCanonicalValue', path);
        if (_utf8Length(key) > NormalizedBoxScoreLimits.maxStringBytes) {
          _fail('resourceLimitExceeded', path);
        }
        visit(current[key], '$path.$key', depth + 1);
      }
      return;
    }
    _fail('invalidCanonicalValue', path);
  }

  visit(value, r'$', 0);
  String encoded;
  try {
    encoded = OfficialStatCanonicalEncoding.encode(value);
  } on Object {
    _fail('invalidCanonicalValue', r'$');
  }
  if (_utf8Length(encoded) >
      NormalizedBoxScoreLimits.maxCanonicalPayloadBytes) {
    _fail('resourceLimitExceeded', r'$');
  }
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
  final normalized = unicode.nfc(value);
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

Map<String, Object?> _validateTime(
  Object? value,
  String path,
  bool enteredPlay,
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
    if (roundingMode != 'nearestHalfUp' || played % precision != 0) {
      _fail('invalidTimeProvenance', path);
    }
    final candidateLower = played - (precision ~/ 2);
    final lowerInclusive = candidateLower < 0 ? 0 : candidateLower;
    final upperExclusive = _safeAdd(played, (precision / 2).ceil(), path);
    return {
      'playedTimeMs': playedTimeMs,
      'possibleIntervalMs': {
        'state': 'known',
        'value': {
          'lowerInclusive': lowerInclusive,
          'upperExclusive': upperExclusive,
        },
      },
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
  final time = _validateTime(raw['time'], '$path.time', enteredPlay);
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

({List<Object?> periods, Map<String, Object?> score}) _validatePeriods(
  Object? value,
  int regulationPeriodCount,
  bool requiresCompleteRegulation,
) {
  final rawPeriods = _list(value, r'$.periods');
  if (rawPeriods.length > NormalizedBoxScoreLimits.maxPeriods) {
    _fail('resourceLimitExceeded', r'$.periods');
  }
  if (requiresCompleteRegulation && rawPeriods.length < regulationPeriodCount) {
    _fail('invalidPeriodSequence', r'$.periods');
  }
  final score = <String, Object?>{'home': 0, 'away': 0};
  final periods = <Object?>[];
  for (var index = 0; index < rawPeriods.length; index += 1) {
    final path =
        r'$.periods'
        '[$index]';
    final raw = _record(rawPeriods[index], path, [
      'awayScore',
      'durationMs',
      'homeScore',
      'kind',
      'number',
      'overtimeIndex',
      'source',
    ]);
    final number = _nonnegativeInteger(raw['number'], '$path.number');
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
      if (kind != 'overtime' ||
          overtimeIndex['state'] != 'known' ||
          overtimeIndex['value'] != expectedOvertime) {
        _fail('invalidOvertimeSequence', path);
      }
    }
    final durationMs = _countFact(raw['durationMs'], '$path.durationMs');
    if (durationMs['state'] == 'known' && durationMs['value'] == 0) {
      _fail('invalidPeriodSequence', '$path.durationMs');
    }
    final homeScore = _nonnegativeInteger(raw['homeScore'], '$path.homeScore');
    final awayScore = _nonnegativeInteger(raw['awayScore'], '$path.awayScore');
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
    final source = _enumeration(raw['source'], '$path.source', [
      'liveCounter',
      'officialSheet',
      'historicalEvidence',
    ]);
    periods.add({
      'awayScore': awayScore,
      'durationMs': durationMs,
      'homeScore': homeScore,
      'kind': kind,
      'number': number,
      'overtimeIndex': overtimeIndex,
      'source': source,
    });
  }
  return (periods: periods, score: score);
}

void _validatePlayerTimeline(
  List<({Map<String, int> counts, Map<String, Object?> output})> teams,
  List<Object?> periods,
) {
  int? elapsedMs = 0;
  for (final periodValue in periods) {
    final period = periodValue! as Map<String, Object?>;
    final duration = period['durationMs']! as Map<String, Object?>;
    if (duration['state'] != 'known') {
      elapsedMs = null;
      break;
    }
    elapsedMs = _safeAdd(
      elapsedMs!,
      duration['value']! as int,
      r'$.periods.durationMs',
    );
  }
  for (final team in teams) {
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      final time = player['time']! as Map<String, Object?>;
      final interval = time['possibleIntervalMs']! as Map<String, Object?>;
      if (elapsedMs != null && interval['state'] == 'known') {
        final bounds = interval['value']! as Map<String, Object?>;
        if ((bounds['lowerInclusive']! as int) > elapsedMs) {
          _fail(
            'timeOutsideGameDuration',
            r'$.participants.'
                '${player['participantId']}.time',
          );
        }
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
      if (periodNumber['state'] == 'known') {
        final number = periodNumber['value']! as int;
        if (number == 0 || number > periods.length) {
          _fail(
            'invalidDeparture',
            r'$.participants.'
                '${player['participantId']}.departure.periodNumber',
          );
        }
        final period = periods[number - 1]! as Map<String, Object?>;
        final duration = period['durationMs']! as Map<String, Object?>;
        if (clock['state'] == 'known' &&
            duration['state'] == 'known' &&
            (clock['value']! as int) > (duration['value']! as int)) {
          _fail(
            'eventClockOutsidePeriod',
            r'$.participants.'
                '${player['participantId']}.departure.clockRemainingMs',
          );
        }
      }
    }
  }
}

Map<String, Object?> _evidenceFact(Object? value, String path) =>
    _fact(value, path, _stringList);

({
  List<Object?> incidents,
  Map<String, Map<String, Object?>> byParticipant,
  Map<String, Map<String, Object?>> byTeam,
})
_validateDiscipline(
  Object? value,
  Set<String> teamIds,
  Map<String, ({bool enteredPlay, String teamEntryId})> participants,
  List<Object?> periods,
  ({Map<String, Object?> overtime, Map<String, Object?> regulation})
  penaltyThresholds,
) {
  final rawIncidents = _list(value, r'$.disciplineIncidents');
  if (rawIncidents.length > NormalizedBoxScoreLimits.maxIncidents) {
    _fail('resourceLimitExceeded', r'$.disciplineIncidents');
  }
  final incidentIds = <String>{};
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
        'teamFoulsByPeriod': <String, Object?>{},
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
      if (chargedParticipantId['state'] != 'known') {
        _fail('invalidDisciplineIncident', path);
      }
      final participant = participants[chargedParticipantId['value']];
      if (participant == null || participant.teamEntryId != teamEntryId) {
        _fail('invalidDisciplineIncident', '$path.chargedParticipantId');
      }
    } else if (!_absentFact(chargedParticipantId, 'not_player_charge')) {
      _fail('invalidDisciplineIncident', '$path.chargedParticipantId');
    }
    if (relatedParticipantId['state'] == 'known') {
      final participant = participants[relatedParticipantId['value']];
      if (participant == null || participant.teamEntryId != teamEntryId) {
        _fail('invalidDisciplineIncident', '$path.relatedParticipantId');
      }
    }
    final incidentType = _enumeration(
      raw['incidentType'],
      '$path.incidentType',
      ['personal', 'technical', 'unsportsmanlike', 'disqualifying'],
    );
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
    if (countsTowardPlayerDisqualification && chargedPartyKind != 'player') {
      _fail(
        'invalidDisciplineIncident',
        '$path.countsTowardPlayerDisqualification',
      );
    }
    final periodNumber = _fact(
      raw['periodNumber'],
      '$path.periodNumber',
      _nonnegativeInteger,
    );
    if (periodNumber['state'] == 'known' && periodNumber['value'] == 0) {
      _fail('invalidDisciplineIncident', '$path.periodNumber');
    }
    if (countsTowardTeamFoul && periodNumber['state'] != 'known') {
      _fail('invalidDisciplineIncident', '$path.periodNumber');
    }
    final clockRemainingMs = _fact(
      raw['clockRemainingMs'],
      '$path.clockRemainingMs',
      _nonnegativeInteger,
    );
    if (clockRemainingMs['state'] == 'known' &&
        periodNumber['state'] != 'known') {
      _fail('eventClockOutsidePeriod', '$path.clockRemainingMs');
    }
    if (periodNumber['state'] == 'known') {
      final number = periodNumber['value']! as int;
      if (number > periods.length) {
        _fail('invalidDisciplineIncident', '$path.periodNumber');
      }
      final period = periods[number - 1]! as Map<String, Object?>;
      final duration = period['durationMs']! as Map<String, Object?>;
      if (clockRemainingMs['state'] == 'known' &&
          duration['state'] == 'known' &&
          (clockRemainingMs['value']! as int) > (duration['value']! as int)) {
        _fail('eventClockOutsidePeriod', '$path.clockRemainingMs');
      }
    }
    final evidenceRefs = _evidenceFact(
      raw['evidenceRefs'],
      '$path.evidenceRefs',
    );
    if (evidenceRefs['state'] == 'known' &&
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
  for (final summary in byTeam.values) {
    final teamFouls = summary['teamFoulsByPeriod']! as Map<String, Object?>;
    final penaltyStateByPeriod = <String, Object?>{};
    for (final periodValue in periods) {
      final period = periodValue! as Map<String, Object?>;
      final periodNumber = period['number']! as int;
      final threshold = period['kind'] == 'regulation'
          ? penaltyThresholds.regulation
          : penaltyThresholds.overtime;
      penaltyStateByPeriod['$periodNumber'] = threshold['state'] == 'known'
          ? {
              'state': 'known',
              'value': {
                'inPenalty':
                    ((teamFouls['$periodNumber'] ?? 0) as int) >=
                    (threshold['value']! as int),
                'teamFouls': (teamFouls['$periodNumber'] ?? 0) as int,
                'threshold': threshold['value'],
              },
            }
          : threshold;
    }
    summary['penaltyStateByPeriod'] = penaltyStateByPeriod;
  }
  return (incidents: incidents, byParticipant: byParticipant, byTeam: byTeam);
}

Map<String, Object?> _validateAdministrativeResult(
  Object? value,
  String disposition,
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
    if (!_absentFact(awardedScore, 'not_adjudicated') ||
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
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail(
        'invalidAdministrativeResult',
        r'$.administrativeResult.evidenceRefs',
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
  if (reconciliationStatus != 'reconciled') {
    _fail(
      'officialScoreEvidenceRequired',
      r'$.officialScore.reconciliationStatus',
    );
  }
  if (reconciliationStatus == 'reconciled') {
    if (score['state'] != 'known' ||
        evidenceRefs['state'] != 'known' ||
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail('officialScoreEvidenceRequired', r'$.officialScore');
    }
    final knownScore = score['value']! as Map<String, Object?>;
    if (knownScore['home'] != playedScore['home'] ||
        knownScore['away'] != playedScore['away']) {
      _fail('officialScoreMismatch', r'$.officialScore.score');
    }
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
  if (raw['schemaVersion'] != 1) {
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
  _validateScope(raw['scope']);
  _enumeration(raw['resultDisposition'], r'$.resultDisposition', [
    'played',
    'forfeit',
    'default',
    'annulled',
    'otherAdjudicated',
  ]);
  if (raw['statisticsDisposition'] != 'complete') {
    _fail('invalidShape', r'$.statisticsDisposition');
  }
  final provenance = _record(raw['provenance'], r'$.provenance', [
    'captureMode',
    'rulesetVersion',
    'sourceId',
    'sourceLabel',
  ]);
  _enumeration(provenance['captureMode'], r'$.provenance.captureMode', [
    'liveCapture',
    'officialSheet',
    'historicalImport',
  ]);
  _identifier(provenance['sourceId'], r'$.provenance.sourceId');
  _text(provenance['sourceLabel'], r'$.provenance.sourceLabel');
  _identifier(provenance['rulesetVersion'], r'$.provenance.rulesetVersion');
  final rules = _record(raw['rules'], r'$.rules', [
    'completedTiesAllowed',
    'regulationPeriodCount',
    'teamFoulPenaltyThresholds',
  ]);
  final regulationPeriodCount = _nonnegativeInteger(
    rules['regulationPeriodCount'],
    r'$.rules.regulationPeriodCount',
  );
  if (regulationPeriodCount == 0) {
    _fail('invalidPeriodSequence', r'$.rules.regulationPeriodCount');
  }
  _boolean(rules['completedTiesAllowed'], r'$.rules.completedTiesAllowed');
  final penaltyThresholds = _record(
    rules['teamFoulPenaltyThresholds'],
    r'$.rules.teamFoulPenaltyThresholds',
    ['overtime', 'regulation'],
  );
  for (final kind in ['regulation', 'overtime']) {
    final threshold = _countFact(
      penaltyThresholds[kind],
      r'$.rules.teamFoulPenaltyThresholds.'
      '$kind',
    );
    if (threshold['state'] == 'known' && threshold['value'] == 0) {
      _fail(
        'invalidDisciplineIncident',
        r'$.rules.teamFoulPenaltyThresholds.'
            '$kind',
      );
    }
  }
  final teams = _list(raw['teams'], r'$.teams');
  if (teams.length != 2) _fail('invalidTeamStructure', r'$.teams');
  return raw;
}

Map<String, Object?> _calculateAccepted(Object? rawInput) {
  final input = _validateRoot(rawInput);
  final scope = _validateScope(input['scope']);
  final seenParticipants = <String>{};
  final seenPlayers = <String>{};
  final rawTeams = _list(input['teams'], r'$.teams');
  final teamResults =
      <({Map<String, int> counts, Map<String, Object?> output})>[
        for (var index = 0; index < rawTeams.length; index += 1)
          _validateTeam(
            rawTeams[index],
            r'$.teams'
            '[$index]',
            seenParticipants,
            seenPlayers,
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
  final rules = _record(input['rules'], r'$.rules');
  final penaltyThresholdRaw = _record(
    rules['teamFoulPenaltyThresholds'],
    r'$.rules.teamFoulPenaltyThresholds',
  );
  final penaltyThresholds = (
    overtime: _countFact(
      penaltyThresholdRaw['overtime'],
      r'$.rules.teamFoulPenaltyThresholds.overtime',
    ),
    regulation: _countFact(
      penaltyThresholdRaw['regulation'],
      r'$.rules.teamFoulPenaltyThresholds.regulation',
    ),
  );
  final periodResult = _validatePeriods(
    input['periods'],
    rules['regulationPeriodCount']! as int,
    input['resultDisposition'] == 'played',
  );
  _validatePlayerTimeline(teamResults, periodResult.periods);
  final playedScore = _scorePair(input['playedScore'], r'$.playedScore');
  if (periodResult.score['home'] != playedScore['home'] ||
      periodResult.score['away'] != playedScore['away']) {
    _fail('playedScorePeriodMismatch', r'$.playedScore');
  }
  if (input['resultDisposition'] == 'played' &&
      rules['completedTiesAllowed'] == false &&
      playedScore['home'] == playedScore['away']) {
    _fail('invalidPeriodSequence', r'$.playedScore');
  }

  final adjustmentValues = _list(
    input['playedScoreAdjustments'],
    r'$.playedScoreAdjustments',
  );
  if (adjustmentValues.length >
      NormalizedBoxScoreLimits.maxPlayedScoreAdjustments) {
    _fail('resourceLimitExceeded', r'$.playedScoreAdjustments');
  }
  final adjustmentIds = <String>{};
  final adjustmentPoints = <String, int>{
    homeTeam.output['teamEntryId']! as String: 0,
    awayTeam.output['teamEntryId']! as String: 0,
  };
  final adjustments = <Object?>[];
  for (var index = 0; index < adjustmentValues.length; index += 1) {
    final path =
        r'$.playedScoreAdjustments'
        '[$index]';
    final raw = _record(adjustmentValues[index], path, [
      'adjustmentId',
      'evidenceRefs',
      'kind',
      'periodNumber',
      'points',
      'teamEntryId',
    ]);
    final adjustmentId = _identifier(raw['adjustmentId'], '$path.adjustmentId');
    if (!adjustmentIds.add(adjustmentId)) {
      _fail('invalidScoreAdjustment', '$path.adjustmentId');
    }
    final teamEntryId = _identifier(raw['teamEntryId'], '$path.teamEntryId');
    if (!adjustmentPoints.containsKey(teamEntryId)) {
      _fail('invalidScoreAdjustment', '$path.teamEntryId');
    }
    final kind = _enumeration(raw['kind'], '$path.kind', [
      'ownBasket',
      'goaltending',
    ]);
    final points = _nonnegativeInteger(raw['points'], '$path.points');
    if (points == 0 || points > 3 || (kind == 'ownBasket' && points != 2)) {
      _fail('invalidScoreAdjustment', '$path.points');
    }
    final periodNumber = _fact(
      raw['periodNumber'],
      '$path.periodNumber',
      _nonnegativeInteger,
    );
    if (periodNumber['state'] != 'known' ||
        periodNumber['value'] == 0 ||
        (periodNumber['value']! as int) > periodResult.periods.length) {
      _fail('invalidScoreAdjustment', '$path.periodNumber');
    }
    final evidenceRefs = _evidenceFact(
      raw['evidenceRefs'],
      '$path.evidenceRefs',
    );
    if (evidenceRefs['state'] != 'known' ||
        (evidenceRefs['value']! as List<Object?>).isEmpty) {
      _fail('invalidScoreAdjustment', '$path.evidenceRefs');
    }
    adjustmentPoints[teamEntryId] = _safeAdd(
      adjustmentPoints[teamEntryId]!,
      points,
      '$path.points',
    );
    adjustments.add({
      'adjustmentId': adjustmentId,
      'evidenceRefs': evidenceRefs,
      'kind': kind,
      'periodNumber': periodNumber,
      'points': points,
      'teamEntryId': teamEntryId,
    });
  }
  final homeTotals = homeTeam.output['totals']! as Map<String, int>;
  final awayTotals = awayTeam.output['totals']! as Map<String, int>;
  final attributedHome = _safeAdd(
    homeTotals['points']!,
    adjustmentPoints[homeTeam.output['teamEntryId']]!,
    r'$.playedScore.home',
  );
  final attributedAway = _safeAdd(
    awayTotals['points']!,
    adjustmentPoints[awayTeam.output['teamEntryId']]!,
    r'$.playedScore.away',
  );
  if (attributedHome != playedScore['home'] ||
      attributedAway != playedScore['away']) {
    _fail('playedScoreAttributionMismatch', r'$.playedScore');
  }

  final teamIds = <String>{
    homeTeam.output['teamEntryId']! as String,
    awayTeam.output['teamEntryId']! as String,
  };
  final participants = <String, ({bool enteredPlay, String teamEntryId})>{};
  for (final team in teamResults) {
    for (final player in team.output['players']! as List<Object?>) {
      final playerMap = player! as Map<String, Object?>;
      participants[playerMap['participantId']! as String] = (
        enteredPlay: playerMap['enteredPlay']! as bool,
        teamEntryId: playerMap['teamEntryId']! as String,
      );
    }
  }
  final discipline = _validateDiscipline(
    input['disciplineIncidents'],
    teamIds,
    participants,
    periodResult.periods,
    penaltyThresholds,
  );
  for (final team in teamResults) {
    team.output['discipline'] = discipline.byTeam[team.output['teamEntryId']]!;
    for (final playerValue in team.output['players']! as List<Object?>) {
      final player = playerValue! as Map<String, Object?>;
      player['discipline'] = discipline.byParticipant[player['participantId']]!;
    }
  }
  final administrativeResult = _validateAdministrativeResult(
    input['administrativeResult'],
    input['resultDisposition']! as String,
    teamIds,
    homeTeam.output['teamEntryId']! as String,
  );
  final officialScore = _validateOfficialScore(
    input['officialScore'],
    playedScore,
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
          'state': 'unknown',
          'value': null,
          'reasonCode': 'tied_played_score',
        }
      : <String, Object?>{
          'state': 'known',
          'value': (playedScore['home']! as int) > (playedScore['away']! as int)
              ? homeTeam.output['teamEntryId']
              : awayTeam.output['teamEntryId'],
        };
  final provenance = _record(input['provenance'], r'$.provenance');
  return {
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
      'provenance': {
        'captureMode': provenance['captureMode'],
        'rulesetVersion': provenance['rulesetVersion'],
        'sourceId': provenance['sourceId'],
        'sourceLabel': unicode.nfc(provenance['sourceLabel']! as String),
      },
      'resultDisposition': input['resultDisposition'],
      'rules': {
        'completedTiesAllowed': rules['completedTiesAllowed'],
        'regulationPeriodCount': rules['regulationPeriodCount'],
        'teamFoulPenaltyThresholds': {
          'overtime': penaltyThresholds.overtime,
          'regulation': penaltyThresholds.regulation,
        },
      },
      'schemaVersion': 1,
      'scope': scope,
      'statisticsDisposition': input['statisticsDisposition'],
      'teams': [for (final team in teamResults) team.output],
      'unicodeNormalizationVersion': normalizedBoxScoreUnicodeVersion,
    },
    'status': 'accepted',
  };
}

/// Pure deterministic normalized box-score calculator.
///
/// It returns exactly the first error in the stable validation sequence. It
/// performs no I/O, imports no Firebase runtime, and never mutates [input].
Map<String, Object?> calculateNormalizedBoxScore(Object? input) {
  try {
    _preflight(input);
    return _calculateAccepted(input);
  } on _ValidationFailure catch (error) {
    return {
      'calculatorVersion': normalizedBoxScoreCalculatorVersion,
      'errors': [
        {'code': error.code, 'path': error.path},
      ],
      'status': 'rejected',
    };
  } on Object {
    return {
      'calculatorVersion': normalizedBoxScoreCalculatorVersion,
      'errors': [
        {'code': 'invalidCanonicalValue', 'path': r'$'},
      ],
      'status': 'rejected',
    };
  }
}
