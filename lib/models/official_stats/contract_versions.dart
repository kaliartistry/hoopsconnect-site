/// Version constants and immutable references for the v2 official-stat domain.
///
/// These constants describe a disabled contract. They do not activate v2
/// authority or change the legacy data model.
abstract final class OfficialStatContractVersions {
  static const int dataSchema = 2;
  static const int domainSchema = 2;
  static const int commandSchema = 2;
  static const int authorizationSchema = 2;
  static const int projectionSchema = 2;
  static const String canonicalEncoding = 'official-stat-canonical-json-v1';
}

/// A pinned, immutable version of policy, rules, calculation, or projection
/// logic. IDs are meaningful only inside [associationId].
class VersionReference {
  final String associationId;
  final String versionId;
  final String sha256;

  VersionReference({
    required this.associationId,
    required this.versionId,
    required this.sha256,
  }) {
    final id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
    final hash = RegExp(r'^[0-9a-f]{64}$');
    if (!id.hasMatch(associationId) || !id.hasMatch(versionId)) {
      throw FormatException('Version scope and ID must use opaque ID syntax');
    }
    if (!hash.hasMatch(sha256)) {
      throw FormatException('Version references require lowercase SHA-256 hex');
    }
  }

  Map<String, Object?> toContractMap() => {
    'associationId': associationId,
    'sha256': sha256,
    'versionId': versionId,
  };
}

/// Every official revision pins all interpretation inputs. A later policy
/// change therefore cannot reinterpret an already certified box score.
class OfficialStatVersionSet {
  final int dataSchemaVersion;
  final int domainSchemaVersion;
  final int commandSchemaVersion;
  final int authorizationSchemaVersion;
  final VersionReference rulesetVersion;
  final VersionReference policyVersion;
  final VersionReference calculatorVersion;
  final VersionReference projectionVersion;
  final VersionReference identityResolutionVersion;
  final VersionReference privacyPolicyVersion;
  final VersionReference brandingVersion;

  OfficialStatVersionSet({
    this.dataSchemaVersion = OfficialStatContractVersions.dataSchema,
    this.domainSchemaVersion = OfficialStatContractVersions.domainSchema,
    this.commandSchemaVersion = OfficialStatContractVersions.commandSchema,
    this.authorizationSchemaVersion =
        OfficialStatContractVersions.authorizationSchema,
    required this.rulesetVersion,
    required this.policyVersion,
    required this.calculatorVersion,
    required this.projectionVersion,
    required this.identityResolutionVersion,
    required this.privacyPolicyVersion,
    required this.brandingVersion,
  }) {
    final references = [
      rulesetVersion,
      policyVersion,
      calculatorVersion,
      projectionVersion,
      identityResolutionVersion,
      privacyPolicyVersion,
      brandingVersion,
    ];
    if (references.any(
      (reference) => reference.associationId != rulesetVersion.associationId,
    )) {
      throw ArgumentError('All pinned versions must share one association');
    }
  }

  Map<String, Object?> toContractMap() => {
    'authorizationSchemaVersion': authorizationSchemaVersion,
    'brandingVersion': brandingVersion.toContractMap(),
    'calculatorVersion': calculatorVersion.toContractMap(),
    'commandSchemaVersion': commandSchemaVersion,
    'dataSchemaVersion': dataSchemaVersion,
    'domainSchemaVersion': domainSchemaVersion,
    'identityResolutionVersion': identityResolutionVersion.toContractMap(),
    'policyVersion': policyVersion.toContractMap(),
    'privacyPolicyVersion': privacyPolicyVersion.toContractMap(),
    'projectionVersion': projectionVersion.toContractMap(),
    'rulesetVersion': rulesetVersion.toContractMap(),
  };
}

/// Version identity for one sealed publication release. Activation metadata
/// such as timestamps is deliberately excluded from content identity.
class PublicationReleaseVersion {
  final String releaseId;
  final String sourceSetHash;
  final String projectionHash;
  final int publicationEpoch;
  final int privacyEpoch;
  final OfficialStatVersionSet versions;

  PublicationReleaseVersion({
    required this.releaseId,
    required this.sourceSetHash,
    required this.projectionHash,
    required this.publicationEpoch,
    required this.privacyEpoch,
    required this.versions,
  }) {
    final hash = RegExp(r'^[0-9a-f]{64}$');
    if (!hash.hasMatch(releaseId) ||
        !hash.hasMatch(sourceSetHash) ||
        !hash.hasMatch(projectionHash)) {
      throw FormatException('Release content identities must be SHA-256 hex');
    }
    if (publicationEpoch < 0 || privacyEpoch < 0) {
      throw ArgumentError('Release epochs must be nonnegative');
    }
  }

  Map<String, Object?> toContractMap() => {
    'privacyEpoch': privacyEpoch,
    'projectionHash': projectionHash,
    'publicationEpoch': publicationEpoch,
    'releaseId': releaseId,
    'sourceSetHash': sourceSetHash,
    'versions': versions.toContractMap(),
  };
}
