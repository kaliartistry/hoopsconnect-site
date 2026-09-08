import 'canonical_encoding.dart';
import 'contract_versions.dart';
import 'domain_enums.dart';
import 'fact.dart';

/// Full tenant and game boundary. Association/operator is always the tenant;
/// no nullable scope component means "all".
class GameScope {
  final String associationId;
  final String competitionId;
  final String seasonId;
  final String divisionId;
  final String phaseId;
  final String gameId;

  GameScope({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.divisionId,
    required this.phaseId,
    required this.gameId,
  }) {
    for (final entry in toContractMap().entries) {
      OfficialStatIdentifiers.requireValid(entry.key, entry.value as String);
    }
  }

  String get key =>
      '$associationId/$competitionId/$seasonId/$divisionId/$phaseId/$gameId';

  Map<String, Object?> toContractMap() => {
    'associationId': associationId,
    'competitionId': competitionId,
    'divisionId': divisionId,
    'gameId': gameId,
    'phaseId': phaseId,
    'seasonId': seasonId,
  };
}

/// Effective facts use half-open intervals [effectiveFrom, effectiveTo).
/// [recordedAt] remains separate so retroactive facts retain bitemporal meaning.
class TemporalInterval {
  final DateTime effectiveFrom;
  final Fact<DateTime> effectiveTo;
  final DateTime recordedAt;

  TemporalInterval({
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.recordedAt,
  }) {
    final knownEnd = effectiveTo.valueOrNull;
    if (knownEnd != null && !knownEnd.isAfter(effectiveFrom)) {
      throw ArgumentError.value(
        knownEnd,
        'effectiveTo',
        'must be after effectiveFrom for a half-open interval',
      );
    }
  }

  /// Returns null when the end is unknown and membership at [instant] cannot
  /// be determined. `notApplicable(open_ended)` is the explicit unbounded case.
  bool? contains(DateTime instant) {
    if (instant.isBefore(effectiveFrom)) return false;
    return switch (effectiveTo) {
      KnownFact<DateTime>(:final value) => instant.isBefore(value),
      NotApplicableFact<DateTime>() => true,
      UnknownFact<DateTime>() => null,
    };
  }

  Map<String, Object?> toContractMap() => {
    'effectiveFrom': effectiveFrom,
    'effectiveTo': effectiveTo.toContractMap((value) => value),
    'recordedAt': recordedAt,
  };
}

class PersonIdentityContract {
  final String associationId;
  final String personId;
  final PersonIdentityStatus status;
  final String identityVersionId;
  final List<String> restrictedEvidenceRefs;

  const PersonIdentityContract({
    required this.associationId,
    required this.personId,
    required this.status,
    required this.identityVersionId,
    this.restrictedEvidenceRefs = const [],
  });
}

class PlayerIdentityContract {
  final String associationId;
  final String playerId;
  final String personId;
  final String displayNameVersionId;
  final PlayerIdentityStatus status;

  const PlayerIdentityContract({
    required this.associationId,
    required this.playerId,
    required this.personId,
    required this.displayNameVersionId,
    required this.status,
  });
}

class TeamIdentityContract {
  final String associationId;
  final String teamId;
  final String identityVersionId;
  final TeamIdentityStatus status;

  const TeamIdentityContract({
    required this.associationId,
    required this.teamId,
    required this.identityVersionId,
    required this.status,
  });
}

class SeasonTeamEntryContract {
  final String associationId;
  final String competitionId;
  final String seasonId;
  final String divisionId;
  final String teamEntryId;
  final String teamId;
  final String seasonalIdentityVersionId;
  final TeamEntryRegistrationStatus registrationStatus;

  const SeasonTeamEntryContract({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.divisionId,
    required this.teamEntryId,
    required this.teamId,
    required this.seasonalIdentityVersionId,
    required this.registrationStatus,
  });
}

class RosterMembershipContract {
  final String associationId;
  final String competitionId;
  final String seasonId;
  final String membershipId;
  final String membershipVersionId;
  final String playerId;
  final String teamEntryId;
  final EligibilityStatus eligibilityStatus;
  final TemporalInterval interval;

  const RosterMembershipContract({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.membershipId,
    required this.membershipVersionId,
    required this.playerId,
    required this.teamEntryId,
    required this.eligibilityStatus,
    required this.interval,
  });
}

/// Participant facts are copied into the game-owned snapshot. Later identity,
/// roster, jersey, or team changes cannot rewrite this historical input.
class GameParticipantSnapshotContract {
  final GameScope scope;
  final String snapshotId;
  final String snapshotHash;
  final String participantId;
  final String playerId;
  final String rosterMembershipId;
  final String rosterMembershipVersionId;
  final String teamEntryId;
  final String jersey;
  final String displayNameVersionId;
  final EligibilityStatus eligibilityStatus;
  final List<String> eligibilityEvidenceRefs;

  GameParticipantSnapshotContract({
    required this.scope,
    required this.snapshotId,
    required this.snapshotHash,
    required this.participantId,
    required this.playerId,
    required this.rosterMembershipId,
    required this.rosterMembershipVersionId,
    required this.teamEntryId,
    required this.jersey,
    required this.displayNameVersionId,
    required this.eligibilityStatus,
    this.eligibilityEvidenceRefs = const [],
  }) {
    if (jersey.isEmpty) {
      throw ArgumentError.value(jersey, 'jersey', 'must remain a string');
    }
    OfficialStatIdentifiers.requireSha256('snapshotHash', snapshotHash);
  }
}

class JournalOperationContract {
  final GameScope scope;
  final String workspaceId;
  final String operationId;
  final String commandId;
  final String actorAccountId;
  final String deviceSessionId;
  final int writerEpoch;
  final int localSequence;
  final Fact<String> previousOperationHash;
  final String expectedServerHead;
  final int operationSchemaVersion;
  final String reducerVersion;
  final String rulesetVersion;
  final String operationType;
  final Map<String, Object?> payload;
  final String payloadHash;
  final DateTime clientObservedAt;

  const JournalOperationContract({
    required this.scope,
    required this.workspaceId,
    required this.operationId,
    required this.commandId,
    required this.actorAccountId,
    required this.deviceSessionId,
    required this.writerEpoch,
    required this.localSequence,
    required this.previousOperationHash,
    required this.expectedServerHead,
    required this.operationSchemaVersion,
    required this.reducerVersion,
    required this.rulesetVersion,
    required this.operationType,
    required this.payload,
    required this.payloadHash,
    required this.clientObservedAt,
  });
}

class BoxScoreRevisionContract {
  final GameScope scope;
  final String revisionId;
  final int revisionNumber;
  final Fact<String> supersedesRevisionId;
  final CaptureMode captureMode;
  final ResultDisposition resultDisposition;
  final StatisticsDisposition statisticsDisposition;
  final OfficialStatVersionSet versions;
  final String scheduleRevisionId;
  final String rosterSnapshotId;
  final String rosterSnapshotHash;
  final String sourceWorkspaceId;
  final int acceptedThroughSequence;
  final String journalHash;
  final Fact<List<String>> officialScoreEvidenceRefs;
  final String inputHash;
  final String derivedHash;
  final String validationReportHash;
  final String createdBy;
  final DateTime createdAt;

  const BoxScoreRevisionContract({
    required this.scope,
    required this.revisionId,
    required this.revisionNumber,
    required this.supersedesRevisionId,
    required this.captureMode,
    required this.resultDisposition,
    required this.statisticsDisposition,
    required this.versions,
    required this.scheduleRevisionId,
    required this.rosterSnapshotId,
    required this.rosterSnapshotHash,
    required this.sourceWorkspaceId,
    required this.acceptedThroughSequence,
    required this.journalHash,
    required this.officialScoreEvidenceRefs,
    required this.inputHash,
    required this.derivedHash,
    required this.validationReportHash,
    required this.createdBy,
    required this.createdAt,
  });
}

class CertificationContract {
  final GameScope scope;
  final String certificateId;
  final String revisionId;
  final String revisionHash;
  final String certifierAccountId;
  final Fact<String> predecessorCertificateId;
  final String certificationPolicyVersion;
  final DateTime certifiedAt;

  const CertificationContract({
    required this.scope,
    required this.certificateId,
    required this.revisionId,
    required this.revisionHash,
    required this.certifierAccountId,
    required this.predecessorCertificateId,
    required this.certificationPolicyVersion,
    required this.certifiedAt,
  });
}

class CorrectionContract {
  final GameScope scope;
  final String correctionId;
  final String targetCertificateId;
  final String reasonCode;
  final List<String> evidenceRefs;
  final List<Map<String, Object?>> fieldDiff;
  final String successorWorkspaceId;

  const CorrectionContract({
    required this.scope,
    required this.correctionId,
    required this.targetCertificateId,
    required this.reasonCode,
    required this.evidenceRefs,
    required this.fieldDiff,
    required this.successorWorkspaceId,
  });
}

class ProjectionBuildContract {
  final String associationId;
  final String competitionId;
  final String seasonId;
  final String buildId;
  final ProjectionBuildState state;
  final String selectionId;
  final String sourceSetHash;
  final int expectedCertificateEpoch;
  final int expectedPublicationEpoch;
  final int expectedPrivacyEpoch;
  final Fact<String> sealedManifestHash;

  ProjectionBuildContract({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.buildId,
    required this.state,
    required this.selectionId,
    required this.sourceSetHash,
    required this.expectedCertificateEpoch,
    required this.expectedPublicationEpoch,
    required this.expectedPrivacyEpoch,
    required this.sealedManifestHash,
  }) {
    if (state == ProjectionBuildState.sealed &&
        sealedManifestHash is! KnownFact<String>) {
      throw ArgumentError('A sealed projection requires a known manifest hash');
    }
    if (state != ProjectionBuildState.sealed &&
        sealedManifestHash is KnownFact<String>) {
      throw ArgumentError(
        'An unsealed projection cannot claim a manifest hash',
      );
    }
  }
}

/// The only mutable public authority pointer for a season. It points to one
/// complete sealed release or to no release at all.
class PublicationReleaseHeadContract {
  final String associationId;
  final String competitionId;
  final String seasonId;
  final ReleaseHeadState state;
  final Fact<PublicationReleaseVersion> activeRelease;
  final int publicationEpoch;
  final int privacyEpoch;

  PublicationReleaseHeadContract({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.state,
    required this.activeRelease,
    required this.publicationEpoch,
    required this.privacyEpoch,
  }) {
    final hasRelease = activeRelease is KnownFact<PublicationReleaseVersion>;
    if ((state == ReleaseHeadState.active) != hasRelease) {
      throw ArgumentError('Only an active release head may name a release');
    }
    if (publicationEpoch < 0 || privacyEpoch < 0) {
      throw ArgumentError('Release-head epochs must be nonnegative');
    }
  }
}

/// Field-specific public permission. Name permission never grants photo, bio,
/// birthday, school, guardian, contact, or any other field by implication.
class PrivacyReleaseContract {
  final String associationId;
  final String playerId;
  final String privacyPolicyVersion;
  final int privacyEpoch;
  final bool isMinor;
  final Map<String, PrivacyPermissionState> fieldPermissions;
  final List<String> authorityEvidenceRefs;

  const PrivacyReleaseContract({
    required this.associationId,
    required this.playerId,
    required this.privacyPolicyVersion,
    required this.privacyEpoch,
    required this.isMinor,
    required this.fieldPermissions,
    required this.authorityEvidenceRefs,
  });

  bool permits(String field) =>
      fieldPermissions[field] == PrivacyPermissionState.permitted;
}
