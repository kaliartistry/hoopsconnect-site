import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthorityMode { disabled, shadow, v2 }

AuthorityMode parseAuthorityMode(Object? value) => switch (value) {
  'shadow' => AuthorityMode.shadow,
  'v2' => AuthorityMode.v2,
  _ => AuthorityMode.disabled,
};

enum AuthorityScopeKind { association, season, division, teamEntry }

enum AuthorityAccessOrigin { association, season }

enum AuthorityActionScope { association, season, division, teamEntry, game }

final RegExp _authorityIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
const int maxJavaScriptSafeInteger = 9007199254740991;

bool validAuthorityId(Object? value) =>
    value is String && _authorityIdPattern.hasMatch(value);

bool validPositiveAuthorityCounter(Object? value) =>
    value is int && value > 0 && value <= maxJavaScriptSafeInteger;

bool validAuthorityTeamEntryIds(Object? value) =>
    value is List &&
    value.length == 2 &&
    value.every(validAuthorityId) &&
    value.toSet().length == 2;

bool _exactKeys(Map<String, Object?> data, Set<String> expected) =>
    data.keys.toSet().containsAll(expected) && expected.containsAll(data.keys);

bool _validUniqueStringList(
  Object? value,
  bool Function(Object?) predicate, {
  required int maximum,
}) =>
    value is List &&
    value.length <= maximum &&
    value.every(predicate) &&
    value.toSet().length == value.length;

abstract final class ScopedAuthorityVersions {
  static const authorizationSchema = 2;
  static const domainSchema = 2;
  static const commandSchema = 2;
}

abstract final class OfficialStatCapabilities {
  static const values = <String>{
    'association.read',
    'players.manage',
    'players.private.read',
    'rosters.assert',
    'rosters.manage',
    'games.schedule',
    'stats.enter',
    'stats.submit',
    'stats.review',
    'stats.correct',
    'stats.certify',
    'results.publish',
    'results.retract',
    'official.override',
  };
}

class ScopedGrantContract {
  final String grantId;
  final String capability;
  final AuthorityScopeKind scopeKind;
  final String associationId;
  final String? competitionId;
  final String? seasonId;
  final String? divisionId;
  final String? teamEntryId;
  final String status;
  final int membershipVersion;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final bool _wireShapeValid;

  const ScopedGrantContract({
    required this.grantId,
    required this.capability,
    required this.scopeKind,
    required this.associationId,
    required this.status,
    required this.membershipVersion,
    required this.effectiveFrom,
    required this.effectiveTo,
    this.competitionId,
    this.seasonId,
    this.divisionId,
    this.teamEntryId,
  }) : _wireShapeValid = true;

  const ScopedGrantContract._({
    required this.grantId,
    required this.capability,
    required this.scopeKind,
    required this.associationId,
    required this.status,
    required this.membershipVersion,
    required this.effectiveFrom,
    required this.effectiveTo,
    required bool wireShapeValid,
    this.competitionId,
    this.seasonId,
    this.divisionId,
    this.teamEntryId,
  }) : _wireShapeValid = wireShapeValid;

  factory ScopedGrantContract.fromMap(Map<String, Object?> data) {
    const commonKeys = {
      'grantId',
      'capability',
      'scopeKind',
      'associationId',
      'status',
      'membershipVersion',
      'effectiveFrom',
      'effectiveTo',
    };
    final parsedKind = switch (data['scopeKind']) {
      'association' => AuthorityScopeKind.association,
      'season' => AuthorityScopeKind.season,
      'division' => AuthorityScopeKind.division,
      'teamEntry' => AuthorityScopeKind.teamEntry,
      _ => null,
    };
    final expectedKeys = {
      ...commonKeys,
      if (parsedKind != null && parsedKind != AuthorityScopeKind.association)
        'competitionId',
      if (parsedKind != null && parsedKind != AuthorityScopeKind.association)
        'seasonId',
      if (parsedKind == AuthorityScopeKind.division ||
          parsedKind == AuthorityScopeKind.teamEntry)
        'divisionId',
      if (parsedKind == AuthorityScopeKind.teamEntry) 'teamEntryId',
    };
    final from = data['effectiveFrom'];
    final to = data['effectiveTo'];
    final fromDate = from is Timestamp ? from.toDate() : null;
    final toDate = to is Timestamp ? to.toDate() : null;
    return ScopedGrantContract._(
      grantId: data['grantId'] is String ? data['grantId']! as String : '',
      capability: data['capability'] is String
          ? data['capability']! as String
          : '',
      scopeKind: parsedKind ?? AuthorityScopeKind.association,
      associationId: data['associationId'] is String
          ? data['associationId']! as String
          : '',
      competitionId: data['competitionId'] is String
          ? data['competitionId']! as String
          : null,
      seasonId: data['seasonId'] is String ? data['seasonId']! as String : null,
      divisionId: data['divisionId'] is String
          ? data['divisionId']! as String
          : null,
      teamEntryId: data['teamEntryId'] is String
          ? data['teamEntryId']! as String
          : null,
      status: data['status'] is String ? data['status']! as String : '',
      membershipVersion: data['membershipVersion'] is int
          ? data['membershipVersion']! as int
          : 0,
      effectiveFrom:
          fromDate ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      effectiveTo: to == null ? null : toDate,
      wireShapeValid:
          parsedKind != null &&
          _exactKeys(data, expectedKeys) &&
          from is Timestamp &&
          (to == null || to is Timestamp),
    );
  }

  bool get isDescriptivelyValid =>
      _wireShapeValid &&
      validAuthorityId(grantId) &&
      OfficialStatCapabilities.values.contains(capability) &&
      validAuthorityId(associationId) &&
      const {'active', 'suspended', 'revoked'}.contains(status) &&
      validPositiveAuthorityCounter(membershipVersion) &&
      (effectiveTo == null || effectiveFrom.isBefore(effectiveTo!)) &&
      switch (scopeKind) {
        AuthorityScopeKind.association =>
          competitionId == null &&
              seasonId == null &&
              divisionId == null &&
              teamEntryId == null,
        AuthorityScopeKind.season =>
          validAuthorityId(competitionId) &&
              validAuthorityId(seasonId) &&
              divisionId == null &&
              teamEntryId == null,
        AuthorityScopeKind.division =>
          validAuthorityId(competitionId) &&
              validAuthorityId(seasonId) &&
              validAuthorityId(divisionId) &&
              teamEntryId == null,
        AuthorityScopeKind.teamEntry =>
          validAuthorityId(competitionId) &&
              validAuthorityId(seasonId) &&
              validAuthorityId(divisionId) &&
              validAuthorityId(teamEntryId),
      };

  String? get deterministicKey {
    if (!isDescriptivelyValid) return null;
    return switch (scopeKind) {
      AuthorityScopeKind.association => '$capability|association',
      AuthorityScopeKind.season => '$capability|season',
      AuthorityScopeKind.division => '$capability|division|$divisionId',
      AuthorityScopeKind.teamEntry =>
        '$capability|teamEntry|$divisionId|$teamEntryId',
    };
  }

  /// Describes containment only. Server controls, membership, provenance,
  /// trusted time, canonical game, and transaction checks remain authoritative.
  bool matchesScopeDescription(Map<String, Object?> scope) {
    if (!isDescriptivelyValid || scope['associationId'] != associationId) {
      return false;
    }
    if (scopeKind == AuthorityScopeKind.association) return true;
    if (scope['competitionId'] != competitionId ||
        scope['seasonId'] != seasonId) {
      return false;
    }
    if (scopeKind == AuthorityScopeKind.season) return true;
    if (scope['divisionId'] != divisionId) return false;
    return scopeKind == AuthorityScopeKind.division ||
        scope['teamEntryId'] == teamEntryId;
  }
}

class AccessEnvelopeContract {
  final AuthorityAccessOrigin origin;
  final bool isDescriptivelyValid;
  final int accessVersion;
  final int membershipVersion;
  final Map<String, Object?> grants;

  const AccessEnvelopeContract._({
    required this.origin,
    required this.isDescriptivelyValid,
    required this.accessVersion,
    required this.membershipVersion,
    required this.grants,
  });

  factory AccessEnvelopeContract.fromMap(
    Map<String, Object?> data, {
    required AuthorityAccessOrigin origin,
    required String uid,
    required Map<String, Object?> scope,
  }) {
    const associationKeys = {
      'dataSchemaVersion',
      'authorizationSchemaVersion',
      'uid',
      'associationId',
      'scopeKind',
      'status',
      'membershipVersion',
      'accessVersion',
      'grants',
    };
    final expected = {
      ...associationKeys,
      if (origin == AuthorityAccessOrigin.season) 'competitionId',
      if (origin == AuthorityAccessOrigin.season) 'seasonId',
    };
    final rawGrants = data['grants'];
    final grants = rawGrants is Map
        ? Map<String, Object?>.from(rawGrants)
        : const <String, Object?>{};
    final valid =
        _exactKeys(data, expected) &&
        data['dataSchemaVersion'] == 2 &&
        data['authorizationSchemaVersion'] == 2 &&
        data['uid'] == uid &&
        data['associationId'] == scope['associationId'] &&
        data['scopeKind'] == origin.name &&
        const {'active', 'suspended', 'revoked'}.contains(data['status']) &&
        validPositiveAuthorityCounter(data['membershipVersion']) &&
        validPositiveAuthorityCounter(data['accessVersion']) &&
        rawGrants is Map &&
        (origin == AuthorityAccessOrigin.association ||
            (data['competitionId'] == scope['competitionId'] &&
                data['seasonId'] == scope['seasonId']));
    return AccessEnvelopeContract._(
      origin: origin,
      isDescriptivelyValid: valid,
      accessVersion: data['accessVersion'] is int
          ? data['accessVersion']! as int
          : 0,
      membershipVersion: data['membershipVersion'] is int
          ? data['membershipVersion']! as int
          : 0,
      grants: Map.unmodifiable(grants),
    );
  }
}

class AuthorityControlContract {
  final AuthorityMode authorityMode;
  final int dataSchemaVersion;
  final String associationId;
  final String? competitionId;
  final String? seasonId;
  final int minimumAuthorizationSchemaVersion;
  final int minimumDomainSchemaVersion;
  final int minimumCommandSchemaVersion;
  final List<Object?> acceptedCalculatorVersions;
  final int controlVersion;
  final bool _acceptedCalculatorVersionsWireValid;
  final bool _competitionIdWasPresent;
  final bool _competitionIdWireValid;
  final bool _seasonIdWasPresent;
  final bool _seasonIdWireValid;

  const AuthorityControlContract({
    this.authorityMode = AuthorityMode.disabled,
    required this.dataSchemaVersion,
    required this.associationId,
    this.competitionId,
    this.seasonId,
    required this.minimumAuthorizationSchemaVersion,
    required this.minimumDomainSchemaVersion,
    required this.minimumCommandSchemaVersion,
    required this.acceptedCalculatorVersions,
    required this.controlVersion,
  }) : _acceptedCalculatorVersionsWireValid = true,
       _competitionIdWasPresent = competitionId != null,
       _competitionIdWireValid = true,
       _seasonIdWasPresent = seasonId != null,
       _seasonIdWireValid = true;

  const AuthorityControlContract._({
    required this.authorityMode,
    required this.dataSchemaVersion,
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.minimumAuthorizationSchemaVersion,
    required this.minimumDomainSchemaVersion,
    required this.minimumCommandSchemaVersion,
    required this.acceptedCalculatorVersions,
    required this.controlVersion,
    required bool acceptedCalculatorVersionsWireValid,
    required bool competitionIdWasPresent,
    required bool competitionIdWireValid,
    required bool seasonIdWasPresent,
    required bool seasonIdWireValid,
  }) : _acceptedCalculatorVersionsWireValid =
           acceptedCalculatorVersionsWireValid,
       _competitionIdWasPresent = competitionIdWasPresent,
       _competitionIdWireValid = competitionIdWireValid,
       _seasonIdWasPresent = seasonIdWasPresent,
       _seasonIdWireValid = seasonIdWireValid;

  factory AuthorityControlContract.fromMap(Map<String, Object?>? data) {
    final accepted = data?['acceptedCalculatorVersions'];
    final competitionIdWasPresent = data?.containsKey('competitionId') ?? false;
    final seasonIdWasPresent = data?.containsKey('seasonId') ?? false;
    final competitionId = data?['competitionId'];
    final seasonId = data?['seasonId'];
    return AuthorityControlContract._(
      authorityMode: parseAuthorityMode(data?['authorityMode']),
      dataSchemaVersion: data?['dataSchemaVersion'] is int
          ? data!['dataSchemaVersion']! as int
          : 0,
      associationId: data?['associationId'] is String
          ? data!['associationId']! as String
          : '',
      competitionId: competitionId is String ? competitionId : null,
      seasonId: seasonId is String ? seasonId : null,
      minimumAuthorizationSchemaVersion:
          data?['minimumAuthorizationSchemaVersion'] is int
          ? data!['minimumAuthorizationSchemaVersion']! as int
          : 0,
      minimumDomainSchemaVersion: data?['minimumDomainSchemaVersion'] is int
          ? data!['minimumDomainSchemaVersion']! as int
          : 0,
      minimumCommandSchemaVersion: data?['minimumCommandSchemaVersion'] is int
          ? data!['minimumCommandSchemaVersion']! as int
          : 0,
      acceptedCalculatorVersions: accepted is List
          ? List<Object?>.unmodifiable(accepted)
          : const [],
      controlVersion: data?['controlVersion'] is int
          ? data!['controlVersion']! as int
          : 0,
      acceptedCalculatorVersionsWireValid:
          data?.containsKey('acceptedCalculatorVersions') == true &&
          accepted is List,
      competitionIdWasPresent: competitionIdWasPresent,
      competitionIdWireValid:
          !competitionIdWasPresent || competitionId is String,
      seasonIdWasPresent: seasonIdWasPresent,
      seasonIdWireValid: !seasonIdWasPresent || seasonId is String,
    );
  }

  bool validFor({
    required AuthorityAccessOrigin origin,
    required Map<String, Object?> scope,
  }) =>
      authorityMode == AuthorityMode.v2 &&
      dataSchemaVersion == 2 &&
      associationId == scope['associationId'] &&
      minimumAuthorizationSchemaVersion == 2 &&
      minimumDomainSchemaVersion == 2 &&
      minimumCommandSchemaVersion == 2 &&
      validPositiveAuthorityCounter(controlVersion) &&
      _acceptedCalculatorVersionsWireValid &&
      _validUniqueStringList(
        acceptedCalculatorVersions,
        validAuthorityId,
        maximum: 4,
      ) &&
      switch (origin) {
        AuthorityAccessOrigin.association =>
          !_competitionIdWasPresent && !_seasonIdWasPresent,
        AuthorityAccessOrigin.season =>
          _competitionIdWasPresent &&
              _competitionIdWireValid &&
              _seasonIdWasPresent &&
              _seasonIdWireValid &&
              competitionId == scope['competitionId'] &&
              seasonId == scope['seasonId'],
      };
}

class CompatibilityGateContract {
  final AuthorityControlContract associationControl;
  final AuthorityControlContract? seasonControl;

  const CompatibilityGateContract({
    required this.associationControl,
    this.seasonControl,
  });

  bool accepts({
    required Map<String, Object?> scope,
    required bool lowerThanAssociation,
    required bool calculatorRequired,
    required Map<String, Object?> versions,
  }) {
    if (!associationControl.validFor(
      origin: AuthorityAccessOrigin.association,
      scope: scope,
    )) {
      return false;
    }
    if (lowerThanAssociation &&
        !(seasonControl?.validFor(
              origin: AuthorityAccessOrigin.season,
              scope: scope,
            ) ??
            false)) {
      return false;
    }
    final expectedKeys = {
      'authorizationSchemaVersion',
      'domainSchemaVersion',
      'commandSchemaVersion',
      if (calculatorRequired) 'calculatorVersion',
    };
    if (!_exactKeys(versions, expectedKeys) ||
        versions['authorizationSchemaVersion'] != 2 ||
        versions['domainSchemaVersion'] != 2 ||
        versions['commandSchemaVersion'] != 2) {
      return false;
    }
    if (!calculatorRequired) return true;
    final calculator = versions['calculatorVersion'];
    return validAuthorityId(calculator) &&
        associationControl.acceptedCalculatorVersions.contains(calculator) &&
        (seasonControl?.acceptedCalculatorVersions.contains(calculator) ??
            false);
  }
}

const Map<String, AuthorityActionScope> authorityActionScopes = {
  'association.read': AuthorityActionScope.association,
  'players.manage': AuthorityActionScope.association,
  'players.private.read': AuthorityActionScope.association,
  'rosters.assert': AuthorityActionScope.teamEntry,
  'rosters.manage': AuthorityActionScope.season,
  'games.schedule': AuthorityActionScope.division,
  'stats.enter': AuthorityActionScope.game,
  'stats.submit': AuthorityActionScope.game,
  'stats.review': AuthorityActionScope.game,
  'stats.correct': AuthorityActionScope.game,
  'stats.certify': AuthorityActionScope.game,
  'results.publish': AuthorityActionScope.season,
  'results.retract': AuthorityActionScope.season,
  'official.override': AuthorityActionScope.association,
};

bool validActionScope(String capability, Map<String, Object?> scope) {
  final kind = authorityActionScopes[capability];
  if (kind == null) return false;
  final expected = switch (kind) {
    AuthorityActionScope.association => {'associationId'},
    AuthorityActionScope.season => {
      'associationId',
      'competitionId',
      'seasonId',
    },
    AuthorityActionScope.division => {
      'associationId',
      'competitionId',
      'seasonId',
      'divisionId',
    },
    AuthorityActionScope.teamEntry => {
      'associationId',
      'competitionId',
      'seasonId',
      'divisionId',
      'teamEntryId',
    },
    AuthorityActionScope.game => {
      'associationId',
      'competitionId',
      'seasonId',
      'divisionId',
      'phaseId',
      'gameId',
    },
  };
  return _exactKeys(scope, expected) && scope.values.every(validAuthorityId);
}
