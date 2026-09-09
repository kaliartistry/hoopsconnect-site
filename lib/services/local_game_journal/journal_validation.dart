import 'dart:convert';

import '../../models/official_stats/canonical_encoding.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../models/official_stats/fact.dart';
import 'journal_error.dart';
import 'journal_limits.dart';

abstract final class LocalJournalValidation {
  static final Set<String> _forbiddenContactKeys = {
    'address',
    'birthdate',
    'contact',
    'dob',
    'email',
    'guardian',
    'guardianemail',
    'guardianphone',
    'phone',
    'phonenumber',
  };

  static void exactKeys(
    Map<String, Object?> map,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    final missing = required.where((key) => !map.containsKey(key)).toList()
      ..sort();
    final allowed = {...required, ...optional};
    final unknown = map.keys.where((key) => !allowed.contains(key)).toList()
      ..sort();
    if (missing.isNotEmpty || unknown.isNotEmpty) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Wire keys do not match the local journal schema',
        {'missing': missing, 'unknown': unknown},
      );
    }
  }

  static String requireId(String field, Object? value) {
    if (value is! String || !OfficialStatIdentifiers.isValid(value)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        '$field must be an opaque 1-128 character ID',
        {'field': field},
      );
    }
    return value;
  }

  static String requireHash(String field, Object? value) {
    if (value is! String || !OfficialStatIdentifiers.isSha256(value)) {
      throw LocalJournalException(
        LocalJournalErrorCode.hashMismatch,
        '$field must be lowercase SHA-256 hex',
        {'field': field},
      );
    }
    return value;
  }

  static int requireSafeInteger(
    String field,
    Object? value, {
    int minimum = 0,
    int maximum = LocalGameJournalLimits.maxSafeInteger,
  }) {
    if (value is! int || value < minimum || value > maximum) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be an integer from $minimum through $maximum',
        {'field': field},
      );
    }
    return value;
  }

  static String? requireReasonCode(
    String field,
    Object? value, {
    bool required = false,
  }) {
    if (value == null && !required) return null;
    if (value is! String ||
        value.isEmpty ||
        value.length > 64 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(value)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be a 1-64 character stable reason code',
      );
    }
    return value;
  }

  static DateTime requireTimestamp(String field, Object? value) {
    if (value is! String) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be a normalized UTC timestamp',
        {'field': field},
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        !value.endsWith('Z') ||
        OfficialStatCanonicalEncoding.normalizeTimestamp(parsed) != value) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be canonical UTC millisecond precision',
        {'field': field},
      );
    }
    return parsed.toUtc();
  }

  static DateTime normalizeTimestamp(DateTime value) =>
      DateTime.parse(OfficialStatCanonicalEncoding.normalizeTimestamp(value));

  static Map<String, Object?> freezePayload(Map<String, Object?> payload) {
    var nodes = 0;
    Object? visit(Object? value, int depth, {String? key}) {
      nodes++;
      if (nodes > LocalGameJournalLimits.maxPayloadNodes) {
        throw LocalJournalException(
          LocalJournalErrorCode.resourceExhausted,
          'Payload contains too many values',
        );
      }
      if (depth > LocalGameJournalLimits.maxPayloadDepth) {
        throw LocalJournalException(
          LocalJournalErrorCode.resourceExhausted,
          'Payload nesting exceeds the supported depth',
        );
      }
      if (value == null || value is bool) return value;
      if (value is String) {
        if (value.length > LocalGameJournalLimits.maxStringLength) {
          throw LocalJournalException(
            LocalJournalErrorCode.resourceExhausted,
            'Payload string exceeds the supported length',
            key == null ? const {} : {'field': key},
          );
        }
        return value;
      }
      if (value is int) {
        requireSafeInteger(
          key ?? 'payloadInteger',
          value,
          minimum: -LocalGameJournalLimits.maxSafeInteger,
        );
        return value;
      }
      if (value is double) {
        if (!value.isFinite || value.truncateToDouble() != value) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            'Payload numbers must be finite safe integers',
            key == null ? const {} : {'field': key},
          );
        }
        return requireSafeInteger(
          key ?? 'payloadInteger',
          value.toInt(),
          minimum: -LocalGameJournalLimits.maxSafeInteger,
        );
      }
      if (value is DateTime) return normalizeTimestamp(value);
      if (value is List) {
        if (value.length > LocalGameJournalLimits.maxListElements) {
          throw LocalJournalException(
            LocalJournalErrorCode.resourceExhausted,
            'Payload list exceeds the supported element count',
          );
        }
        return List<Object?>.unmodifiable(
          value.map((item) => visit(item, depth + 1)),
        );
      }
      if (value is Map) {
        if (value.length > LocalGameJournalLimits.maxMapKeys) {
          throw LocalJournalException(
            LocalJournalErrorCode.resourceExhausted,
            'Payload object exceeds the supported key count',
          );
        }
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          final mapKey = entry.key;
          if (mapKey is! String ||
              !RegExp(r'^[\x21-\x7E]+$').hasMatch(mapKey)) {
            throw LocalJournalException(
              LocalJournalErrorCode.invalidArgument,
              'Payload keys must be nonempty printable ASCII',
            );
          }
          if (_forbiddenContactKeys.contains(mapKey.toLowerCase())) {
            throw LocalJournalException(
              LocalJournalErrorCode.invalidArgument,
              'Contact and guardian data are not permitted in the journal',
              {'field': mapKey},
            );
          }
          result[mapKey] = visit(entry.value, depth + 1, key: mapKey);
        }
        return Map<String, Object?>.unmodifiable(result);
      }
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Payload contains an unsupported value type',
        {'type': value.runtimeType.toString()},
      );
    }

    final frozen = visit(payload, 0) as Map<String, Object?>;
    final byteCount = utf8
        .encode(OfficialStatCanonicalEncoding.encode(frozen))
        .length;
    if (byteCount > LocalGameJournalLimits.maxPayloadBytes) {
      throw LocalJournalException(
        LocalJournalErrorCode.resourceExhausted,
        'Canonical payload exceeds ${LocalGameJournalLimits.maxPayloadBytes} bytes',
        {'actualBytes': byteCount},
      );
    }
    return frozen;
  }

  static void validateOperationPayload(
    JournalOperationType operationType,
    Map<String, Object?> payload,
  ) {
    const causality = {'amendsOperationId', 'reversesOperationId'};
    final required = switch (operationType) {
      JournalOperationType.setParticipantStatus => {'participantId', 'status'},
      JournalOperationType.setPlayerCounter => {
        'delta',
        'participantId',
        'stat',
      },
      JournalOperationType.setTeamOnlyCounter => {
        'delta',
        'stat',
        'teamEntryId',
      },
      JournalOperationType.setPeriodScore => {'score', 'teamEntryId'},
      JournalOperationType.setClock => {'clockState'},
      JournalOperationType.recordDiscipline => {
        'chargedPartyId',
        'chargedPartyType',
        'incidentId',
        'scoresheetCode',
      },
      JournalOperationType.setLineup => {'participantIds', 'teamEntryId'},
      JournalOperationType.attachEvidence => {'evidenceKind', 'evidenceRef'},
    };
    exactKeys(payload, required, causality);
    if (payload.containsKey('amendsOperationId') &&
        payload.containsKey('reversesOperationId')) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'An operation may amend or reverse one prior operation, not both',
      );
    }
    for (final key in causality) {
      if (payload.containsKey(key)) requireId(key, payload[key]);
    }
    switch (operationType) {
      case JournalOperationType.setParticipantStatus:
        requireId('participantId', payload['participantId']);
        if (!ParticipantStatus.values.any(
          (value) => value.name == payload['status'],
        )) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            'Participant status is unsupported',
          );
        }
      case JournalOperationType.setPlayerCounter:
        requireId('participantId', payload['participantId']);
        _requireCounterDelta(payload['delta']);
        _requireAllowedValue('stat', payload['stat'], const {
          'twoPointMade',
          'twoPointAttempted',
          'threePointMade',
          'threePointAttempted',
          'freeThrowMade',
          'freeThrowAttempted',
          'offensiveRebounds',
          'defensiveRebounds',
          'assists',
          'steals',
          'blocks',
          'turnovers',
        });
      case JournalOperationType.setTeamOnlyCounter:
        requireId('teamEntryId', payload['teamEntryId']);
        _requireCounterDelta(payload['delta']);
        _requireAllowedValue('stat', payload['stat'], const {
          'offensiveRebounds',
          'defensiveRebounds',
          'turnovers',
        });
      case JournalOperationType.setPeriodScore:
        requireId('teamEntryId', payload['teamEntryId']);
        requireSafeInteger('score', payload['score']);
      case JournalOperationType.setClock:
        _requireAllowedValue('clockState', payload['clockState'], const {
          'running',
          'stopped',
        });
      case JournalOperationType.recordDiscipline:
        requireId('incidentId', payload['incidentId']);
        requireId('chargedPartyId', payload['chargedPartyId']);
        _requireAllowedValue(
          'chargedPartyType',
          payload['chargedPartyType'],
          const {'player', 'coach', 'bench', 'team'},
        );
        _requireShortAsciiCode('scoresheetCode', payload['scoresheetCode']);
      case JournalOperationType.setLineup:
        requireId('teamEntryId', payload['teamEntryId']);
        final participants = payload['participantIds'];
        if (participants is! List ||
            participants.isEmpty ||
            participants.length > 20) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            'Lineup participantIds must contain 1-20 IDs',
          );
        }
        final ids = <String>{};
        for (final participant in participants) {
          ids.add(requireId('participantId', participant));
        }
        if (ids.length != participants.length) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            'Lineup participantIds must be unique',
          );
        }
      case JournalOperationType.attachEvidence:
        requireId('evidenceRef', payload['evidenceRef']);
        _requireAllowedValue('evidenceKind', payload['evidenceKind'], const {
          'officialSheet',
          'scoreboard',
          'clockAnchor',
          'rosterResolution',
          'otherReference',
        });
    }
  }

  static void _requireCounterDelta(Object? value) {
    requireSafeInteger('delta', value, minimum: -1000000, maximum: 1000000);
    if (value == 0) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Counter delta must not be zero',
      );
    }
  }

  static void _requireAllowedValue(
    String field,
    Object? value,
    Set<String> allowed,
  ) {
    if (value is! String || !allowed.contains(value)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field is unsupported',
        {'field': field},
      );
    }
  }

  static void _requireShortAsciiCode(String field, Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 64 ||
        !RegExp(r'^[\x21-\x7E]+$').hasMatch(value)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be 1-64 printable ASCII characters',
      );
    }
  }

  static Map<String, Object?> decodeMap(String value) {
    Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Persisted record is truncated or invalid JSON',
      );
    }
    if (decoded is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Persisted record is not an object',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  static GameScope decodeScope(Object? value) {
    if (value is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'scope must be an object',
      );
    }
    final map = Map<String, Object?>.from(value);
    exactKeys(map, const {
      'associationId',
      'competitionId',
      'seasonId',
      'divisionId',
      'phaseId',
      'gameId',
    });
    return GameScope(
      associationId: requireId('associationId', map['associationId']),
      competitionId: requireId('competitionId', map['competitionId']),
      seasonId: requireId('seasonId', map['seasonId']),
      divisionId: requireId('divisionId', map['divisionId']),
      phaseId: requireId('phaseId', map['phaseId']),
      gameId: requireId('gameId', map['gameId']),
    );
  }

  static Fact<int> decodeIntFact(
    String field,
    Object? value, {
    int minimum = 0,
    int maximum = LocalGameJournalLimits.maxSafeInteger,
  }) {
    if (value is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be an explicit fact',
      );
    }
    final map = Map<String, Object?>.from(value);
    return switch (map['state']) {
      'known' => (() {
        exactKeys(map, const {'state', 'value'});
        return Fact<int>.known(
          requireSafeInteger(
            field,
            map['value'],
            minimum: minimum,
            maximum: maximum,
          ),
        );
      })(),
      'unknown' => (() {
        exactKeys(map, const {'state', 'value', 'reasonCode'});
        if (map['value'] != null) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            '$field unknown fact must have a null value',
          );
        }
        return Fact<int>.unknown(
          reasonCode: requireReasonCode('$field.reasonCode', map['reasonCode']),
        );
      })(),
      'notApplicable' => (() {
        exactKeys(map, const {'state', 'value', 'reasonCode'});
        if (map['value'] != null) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            '$field notApplicable fact requires a reason and null value',
          );
        }
        return Fact<int>.notApplicable(
          reasonCode: requireReasonCode(
            '$field.reasonCode',
            map['reasonCode'],
            required: true,
          )!,
        );
      })(),
      _ => throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field has an unknown fact state',
      ),
    };
  }

  static Fact<String> decodeStringFact(
    String field,
    Object? value, {
    bool requireHash = false,
    bool requireIdentifier = false,
  }) {
    if (value is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field must be an explicit fact',
      );
    }
    final map = Map<String, Object?>.from(value);
    switch (map['state']) {
      case 'known':
        exactKeys(map, const {'state', 'value'});
        final raw = map['value'];
        if (raw is! String) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            '$field known fact requires a string',
          );
        }
        if (requireHash) LocalJournalValidation.requireHash(field, raw);
        if (requireIdentifier) requireId(field, raw);
        return Fact<String>.known(raw);
      case 'unknown':
        exactKeys(map, const {'state', 'value', 'reasonCode'});
        if (map['value'] != null) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            '$field unknown fact must have a null value',
          );
        }
        return Fact<String>.unknown(
          reasonCode: requireReasonCode('$field.reasonCode', map['reasonCode']),
        );
      case 'notApplicable':
        exactKeys(map, const {'state', 'value', 'reasonCode'});
        if (map['value'] != null) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidArgument,
            '$field notApplicable fact requires a reason and null value',
          );
        }
        return Fact<String>.notApplicable(
          reasonCode: requireReasonCode(
            '$field.reasonCode',
            map['reasonCode'],
            required: true,
          )!,
        );
      default:
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          '$field has an unknown fact state',
        );
    }
  }
}
