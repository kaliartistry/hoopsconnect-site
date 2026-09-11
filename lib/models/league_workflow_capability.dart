class LeagueWorkflowCapability {
  static const schemaVersion = 1;
  static const timezone = 'America/Jamaica';

  final String associationId;
  final String competitionId;
  final String activeSeasonId;
  final String defaultPhaseId;
  final String authorityMode;
  final bool callablesReady;
  final bool directWritesDenied;
  final bool lifecycleAuthorityReady;
  final bool custodyAuthorityReady;
  final bool actorAuthorityReady;
  final bool identityAuthorityReady;
  final bool privacyAuthorityReady;
  final int custodyPolicyVersionV2;
  final int privacyEpochV2;
  final int clientAuthorizationSchemaVersion;
  final bool rosters;
  final bool divisionDeletion;
  final bool scheduling;
  final bool seasonLifecycle;

  const LeagueWorkflowCapability({
    required this.associationId,
    required this.competitionId,
    required this.activeSeasonId,
    required this.defaultPhaseId,
    required this.authorityMode,
    required this.callablesReady,
    required this.directWritesDenied,
    required this.lifecycleAuthorityReady,
    required this.custodyAuthorityReady,
    required this.actorAuthorityReady,
    required this.identityAuthorityReady,
    required this.privacyAuthorityReady,
    required this.custodyPolicyVersionV2,
    required this.privacyEpochV2,
    required this.clientAuthorizationSchemaVersion,
    required this.rosters,
    required this.divisionDeletion,
    required this.scheduling,
    required this.seasonLifecycle,
  });

  factory LeagueWorkflowCapability.fromMap(
    Map<String, dynamic> map, {
    required String expectedAssociationId,
    required int clientAuthorizationSchemaVersion,
  }) {
    String requiredId(String key) {
      final value = map[key];
      if (value is! String || !_idPattern.hasMatch(value)) {
        throw FormatException('Invalid league workflow $key');
      }
      return value;
    }

    if (map['schemaVersion'] != schemaVersion ||
        map['associationId'] != expectedAssociationId ||
        map['timezone'] != timezone ||
        map['custodyPolicyVersionV2'] is! int ||
        (map['custodyPolicyVersionV2'] as int) < 1 ||
        map['privacyEpochV2'] is! int ||
        (map['privacyEpochV2'] as int) < 1 ||
        !{'legacyV1', 'v2'}.contains(map['authorityMode'])) {
      throw const FormatException('Invalid league workflow capability');
    }
    return LeagueWorkflowCapability(
      associationId: expectedAssociationId,
      competitionId: requiredId('competitionId'),
      activeSeasonId: requiredId('activeSeasonId'),
      defaultPhaseId: requiredId('defaultPhaseId'),
      authorityMode: map['authorityMode'] as String,
      callablesReady: map['callablesReady'] == true,
      directWritesDenied: map['directWritesDenied'] == true,
      lifecycleAuthorityReady: map['lifecycleAuthorityReady'] == true,
      custodyAuthorityReady: map['custodyAuthorityReady'] == true,
      actorAuthorityReady: map['actorAuthorityReady'] == true,
      identityAuthorityReady: map['identityAuthorityReady'] == true,
      privacyAuthorityReady: map['privacyAuthorityReady'] == true,
      custodyPolicyVersionV2: map['custodyPolicyVersionV2'] as int,
      privacyEpochV2: map['privacyEpochV2'] as int,
      clientAuthorizationSchemaVersion: clientAuthorizationSchemaVersion,
      rosters: map['rosters'] == true,
      divisionDeletion: map['divisionDeletion'] == true,
      scheduling: map['scheduling'] == true,
      seasonLifecycle: map['seasonLifecycle'] == true,
    );
  }

  bool get commonReady =>
      callablesReady &&
      directWritesDenied &&
      lifecycleAuthorityReady &&
      custodyAuthorityReady &&
      actorAuthorityReady &&
      identityAuthorityReady &&
      privacyAuthorityReady &&
      ((authorityMode == 'legacyV1' && clientAuthorizationSchemaVersion == 1) ||
          (authorityMode == 'v2' && clientAuthorizationSchemaVersion == 2));

  bool get rosterEnabled => commonReady && rosters;
  bool get divisionDeletionEnabled => commonReady && divisionDeletion;
  bool get schedulingEnabled => commonReady && scheduling;
  // Season callables intentionally support only the legacy association.manage
  // authority until a scoped V2 seasons.manage capability is adopted. Keep the
  // client gate identical to the server gate so V2 operators are never shown
  // actions that the server must reject.
  bool get seasonLifecycleEnabled =>
      commonReady &&
      seasonLifecycle &&
      authorityMode == 'legacyV1' &&
      clientAuthorizationSchemaVersion == 1;
}

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
