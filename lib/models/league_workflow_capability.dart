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
  final bool rosters;
  final bool divisionDeletion;
  final bool scheduling;

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
    required this.rosters,
    required this.divisionDeletion,
    required this.scheduling,
  });

  factory LeagueWorkflowCapability.fromMap(
    Map<String, dynamic> map, {
    required String expectedAssociationId,
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
      rosters: map['rosters'] == true,
      divisionDeletion: map['divisionDeletion'] == true,
      scheduling: map['scheduling'] == true,
    );
  }

  bool get commonReady =>
      callablesReady &&
      directWritesDenied &&
      lifecycleAuthorityReady &&
      custodyAuthorityReady;

  bool get rosterEnabled => commonReady && rosters;
  bool get divisionDeletionEnabled => commonReady && divisionDeletion;
  bool get schedulingEnabled => commonReady && scheduling;
}

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
