import 'dart:convert';

import 'scoped_authority_contract.dart';

const int assignedGameBootstrapResponseByteLimit = 16 * 1024;

bool _exactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.keys.toSet().containsAll(expected) && expected.containsAll(value.keys);

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    return null;
  }
}

final RegExp _utcMilliseconds = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);

class AssignedGameBootstrap {
  final String actorAccountId;
  final Map<String, String> scope;
  final String homeTeamEntryId;
  final String awayTeamEntryId;
  final int gameControlVersion;
  final int assignmentVersion;
  final int writerEpoch;
  final List<String> duties;
  final int associationControlVersion;
  final int seasonControlVersion;
  final List<String> acceptedCalculatorVersions;
  final String evaluatedAt;

  const AssignedGameBootstrap._({
    required this.actorAccountId,
    required this.scope,
    required this.homeTeamEntryId,
    required this.awayTeamEntryId,
    required this.gameControlVersion,
    required this.assignmentVersion,
    required this.writerEpoch,
    required this.duties,
    required this.associationControlVersion,
    required this.seasonControlVersion,
    required this.acceptedCalculatorVersions,
    required this.evaluatedAt,
  });

  static AssignedGameBootstrap? tryParse(Map<String, Object?> data) {
    if (utf8.encode(jsonEncode(data)).length >
            assignedGameBootstrapResponseByteLimit ||
        !_exactKeys(data, const {
          'readSchemaVersion',
          'kind',
          'actorAccountId',
          'scope',
          'homeTeamEntryId',
          'awayTeamEntryId',
          'gameControlVersion',
          'assignment',
          'controlVersions',
          'compatibility',
          'evaluatedAt',
        }) ||
        data['readSchemaVersion'] != 2 ||
        data['kind'] != 'assignedGameBootstrap' ||
        !validAuthorityId(data['actorAccountId']) ||
        !validAuthorityId(data['homeTeamEntryId']) ||
        !validAuthorityId(data['awayTeamEntryId']) ||
        data['homeTeamEntryId'] == data['awayTeamEntryId'] ||
        !validPositiveAuthorityCounter(data['gameControlVersion'])) {
      return null;
    }

    final scope = _stringMap(data['scope']);
    final assignment = _stringMap(data['assignment']);
    final controls = _stringMap(data['controlVersions']);
    final compatibility = _stringMap(data['compatibility']);
    if (scope == null ||
        assignment == null ||
        controls == null ||
        compatibility == null ||
        !_exactKeys(scope, const {
          'associationId',
          'competitionId',
          'seasonId',
          'divisionId',
          'phaseId',
          'gameId',
        }) ||
        !scope.values.every(validAuthorityId) ||
        !_exactKeys(assignment, const {
          'assignmentVersion',
          'writerEpoch',
          'duties',
        }) ||
        !validPositiveAuthorityCounter(assignment['assignmentVersion']) ||
        !validPositiveAuthorityCounter(assignment['writerEpoch']) ||
        !_exactKeys(controls, const {'association', 'season'}) ||
        !validPositiveAuthorityCounter(controls['association']) ||
        !validPositiveAuthorityCounter(controls['season']) ||
        !_exactKeys(compatibility, const {
          'authorizationSchemaVersion',
          'domainSchemaVersion',
          'commandSchemaVersion',
          'acceptedCalculatorVersions',
        }) ||
        compatibility['authorizationSchemaVersion'] != 2 ||
        compatibility['domainSchemaVersion'] != 2 ||
        compatibility['commandSchemaVersion'] != 2) {
      return null;
    }

    final rawDuties = assignment['duties'];
    final rawCalculators = compatibility['acceptedCalculatorVersions'];
    if (rawDuties is! List ||
        rawDuties.length > 2 ||
        rawDuties.toSet().length != rawDuties.length ||
        !rawDuties.every((value) => value == 'enter' || value == 'submit') ||
        !rawDuties.contains('enter') ||
        rawCalculators is! List ||
        rawCalculators.length > 4 ||
        rawCalculators.toSet().length != rawCalculators.length ||
        !rawCalculators.every(validAuthorityId)) {
      return null;
    }
    final calculators = rawCalculators.cast<String>();
    final sortedCalculators = [...calculators]..sort();
    if (jsonEncode(calculators) != jsonEncode(sortedCalculators)) return null;

    final evaluatedAt = data['evaluatedAt'];
    if (evaluatedAt is! String ||
        !_utcMilliseconds.hasMatch(evaluatedAt) ||
        DateTime.tryParse(evaluatedAt)?.toUtc().toIso8601String() != evaluatedAt) {
      return null;
    }
    return AssignedGameBootstrap._(
      actorAccountId: data['actorAccountId']! as String,
      scope: Map<String, String>.unmodifiable(scope.cast<String, String>()),
      homeTeamEntryId: data['homeTeamEntryId']! as String,
      awayTeamEntryId: data['awayTeamEntryId']! as String,
      gameControlVersion: data['gameControlVersion']! as int,
      assignmentVersion: assignment['assignmentVersion']! as int,
      writerEpoch: assignment['writerEpoch']! as int,
      duties: List<String>.unmodifiable(rawDuties.cast<String>()),
      associationControlVersion: controls['association']! as int,
      seasonControlVersion: controls['season']! as int,
      acceptedCalculatorVersions: List<String>.unmodifiable(calculators),
      evaluatedAt: evaluatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'readSchemaVersion': 2,
    'kind': 'assignedGameBootstrap',
    'actorAccountId': actorAccountId,
    'scope': Map<String, String>.from(scope),
    'homeTeamEntryId': homeTeamEntryId,
    'awayTeamEntryId': awayTeamEntryId,
    'gameControlVersion': gameControlVersion,
    'assignment': <String, Object?>{
      'assignmentVersion': assignmentVersion,
      'writerEpoch': writerEpoch,
      'duties': [...duties],
    },
    'controlVersions': <String, Object?>{
      'association': associationControlVersion,
      'season': seasonControlVersion,
    },
    'compatibility': <String, Object?>{
      'authorizationSchemaVersion': 2,
      'domainSchemaVersion': 2,
      'commandSchemaVersion': 2,
      'acceptedCalculatorVersions': [...acceptedCalculatorVersions],
    },
    'evaluatedAt': evaluatedAt,
  };
}
