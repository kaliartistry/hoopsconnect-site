import 'canonical_encoding.dart';
import 'contract_versions.dart';
import 'domain_enums.dart';
import 'fact.dart';

void _requireNonnegativeSafeInteger(String field, int value) {
  if (value < 0 || value > OfficialStatCanonicalEncoding.maxSafeInteger) {
    throw ArgumentError.value(
      value,
      field,
      'must be a nonnegative safe integer',
    );
  }
}

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
    if (effectiveTo case NotApplicableFact<DateTime>(:final reasonCode)) {
      if (reasonCode != 'open_ended') {
        throw ArgumentError.value(
          reasonCode,
          'effectiveTo.reasonCode',
          'must be open_ended when effectiveTo is notApplicable',
        );
      }
    }
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
  final JournalOperationType operationType;
  final Fact<int> periodNumber;
  final Fact<int> clockRemainingMs;
  final int logicalPlayOrder;
  final Map<String, Object?> payload;
  final String semanticHash;
  final String requestHash;
  final DateTime clientObservedAt;

  JournalOperationContract({
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
    required this.periodNumber,
    required this.clockRemainingMs,
    required this.logicalPlayOrder,
    required this.payload,
    required this.semanticHash,
    required this.requestHash,
    required this.clientObservedAt,
  }) {
    for (final entry in {
      'workspaceId': workspaceId,
      'operationId': operationId,
      'commandId': commandId,
      'actorAccountId': actorAccountId,
      'deviceSessionId': deviceSessionId,
    }.entries) {
      OfficialStatIdentifiers.requireValid(entry.key, entry.value);
    }
    _requireNonnegativeSafeInteger('writerEpoch', writerEpoch);
    _requireNonnegativeSafeInteger('localSequence', localSequence);
    _requireNonnegativeSafeInteger(
      'operationSchemaVersion',
      operationSchemaVersion,
    );
    if (operationSchemaVersion == 0) {
      throw ArgumentError.value(
        operationSchemaVersion,
        'operationSchemaVersion',
        'must be at least one',
      );
    }
    _requireNonnegativeSafeInteger('logicalPlayOrder', logicalPlayOrder);
    OfficialStatIdentifiers.requireValid(
      'expectedServerHead',
      expectedServerHead,
    );
    OfficialStatIdentifiers.requireValid('reducerVersion', reducerVersion);
    OfficialStatIdentifiers.requireValid('rulesetVersion', rulesetVersion);
    _validatePreviousOperationHash();
    _validateOrderingFact('periodNumber', periodNumber, minimum: 1);
    _validateOrderingFact('clockRemainingMs', clockRemainingMs);
    OfficialStatIdentifiers.requireSha256('semanticHash', semanticHash);
    OfficialStatIdentifiers.requireSha256('requestHash', requestHash);
    final calculatedSemanticHash = OfficialStatCanonicalEncoding.sha256Hex(
      semanticHashInput(),
    );
    if (calculatedSemanticHash != semanticHash) {
      throw ArgumentError('semanticHash does not match semantic fields');
    }
    final calculatedRequestHash = OfficialStatCanonicalEncoding.sha256Hex(
      requestHashInput(),
    );
    if (calculatedRequestHash != requestHash) {
      throw ArgumentError(
        'requestHash does not match immutable request fields',
      );
    }
  }

  /// Immutable basketball meaning. IDs, actor/device authority, writer
  /// fencing, observation time, and local delivery metadata are excluded.
  Map<String, Object?> semanticHashInput() => {
    'clockRemainingMs': clockRemainingMs.toContractMap((value) => value),
    'logicalPlayOrder': logicalPlayOrder,
    'operationSchemaVersion': operationSchemaVersion,
    'operationType': operationType.name,
    'payload': payload,
    'periodNumber': periodNumber.toContractMap((value) => value),
    'reducerVersion': reducerVersion,
    'rulesetVersion': rulesetVersion,
    'scope': scope.toContractMap(),
    'workspaceId': workspaceId,
  };

  /// Immutable authority/fencing identity. [commandId] is the idempotency key
  /// and is excluded from the value it keys. Client observation time and all
  /// [JournalDeliveryContract] fields are transport metadata and excluded.
  Map<String, Object?> requestHashInput() => {
    'actorAccountId': actorAccountId,
    'deviceSessionId': deviceSessionId,
    'expectedServerHead': expectedServerHead,
    'localSequence': localSequence,
    'operationId': operationId,
    'previousOperationHash': previousOperationHash.toContractMap(
      (value) => value,
    ),
    'semanticHash': semanticHash,
    'writerEpoch': writerEpoch,
  };

  static void _validateOrderingFact(
    String field,
    Fact<int> fact, {
    int minimum = 0,
  }) {
    if (fact case NotApplicableFact<int>(:final reasonCode)) {
      if (reasonCode.isEmpty) {
        throw ArgumentError.value(
          reasonCode,
          '$field.reasonCode',
          'must be nonempty when notApplicable',
        );
      }
    }
    final value = fact.valueOrNull;
    if (value == null) return;
    _requireNonnegativeSafeInteger(field, value);
    if (value < minimum) {
      throw ArgumentError.value(value, field, 'must be at least $minimum');
    }
  }

  void _validatePreviousOperationHash() {
    if (localSequence == 0) {
      if (previousOperationHash case NotApplicableFact<String>(
        reasonCode: 'genesis',
      )) {
        return;
      }
      throw ArgumentError(
        'Sequence zero requires previousOperationHash '
        'notApplicable(genesis)',
      );
    }
    final previousHash = previousOperationHash.valueOrNull;
    if (previousHash == null) {
      throw ArgumentError(
        'Non-genesis operations require a known previousOperationHash',
      );
    }
    OfficialStatIdentifiers.requireSha256(
      'previousOperationHash',
      previousHash,
    );
  }
}

/// Server proof that one immutable request was accepted at a precise journal
/// position. Every identity needed to reject a mismatched replay is bound here.
class OperationReceiptContract {
  final String receiptId;
  final GameScope scope;
  final String workspaceId;
  final String operationId;
  final String commandId;
  final String actorAccountId;
  final JournalOperationType commandKind;
  final String requestHash;
  final int serverSequence;
  final String acceptedJournalHead;
  final String acceptedJournalHash;
  final int writerEpoch;
  final DateTime acceptedAt;

  OperationReceiptContract({
    required this.receiptId,
    required this.scope,
    required this.workspaceId,
    required this.operationId,
    required this.commandId,
    required this.actorAccountId,
    required this.commandKind,
    required this.requestHash,
    required this.serverSequence,
    required this.acceptedJournalHead,
    required this.acceptedJournalHash,
    required this.writerEpoch,
    required this.acceptedAt,
  }) {
    for (final entry in {
      'receiptId': receiptId,
      'workspaceId': workspaceId,
      'operationId': operationId,
      'commandId': commandId,
      'actorAccountId': actorAccountId,
      'acceptedJournalHead': acceptedJournalHead,
    }.entries) {
      OfficialStatIdentifiers.requireValid(entry.key, entry.value);
    }
    OfficialStatIdentifiers.requireSha256('requestHash', requestHash);
    OfficialStatIdentifiers.requireSha256(
      'acceptedJournalHash',
      acceptedJournalHash,
    );
    _requireNonnegativeSafeInteger('serverSequence', serverSequence);
    _requireNonnegativeSafeInteger('writerEpoch', writerEpoch);
  }
}

/// Mutable device-local transport state. It is intentionally separate from
/// [JournalOperationContract] and excluded from semantic/idempotency hashes.
class JournalDeliveryContract {
  final String operationId;
  final JournalDeliveryState state;
  final int retryCount;
  final Fact<DateTime> nextAttemptAt;
  final Fact<String> lastErrorCode;
  final Fact<OperationReceiptContract> receipt;

  JournalDeliveryContract({
    required this.operationId,
    required this.state,
    required this.retryCount,
    required this.nextAttemptAt,
    required this.lastErrorCode,
    required this.receipt,
  }) {
    OfficialStatIdentifiers.requireValid('operationId', operationId);
    _requireNonnegativeSafeInteger('retryCount', retryCount);
    if (state == JournalDeliveryState.accepted &&
        receipt is! KnownFact<OperationReceiptContract>) {
      throw ArgumentError('Accepted delivery requires a known receipt');
    }
    if (receipt.valueOrNull case final knownReceipt?) {
      if (knownReceipt.operationId != operationId) {
        throw ArgumentError(
          'Delivery receipt operationId must match delivery operationId',
        );
      }
    }
  }
}

class BoxScoreInputPartDescriptor {
  final String partId;
  final BoxScorePartKind kind;
  final int count;
  final String sha256;

  BoxScoreInputPartDescriptor({
    required this.partId,
    required this.kind,
    required this.count,
    required this.sha256,
  }) {
    OfficialStatIdentifiers.requireValid('partId', partId);
    _requireNonnegativeSafeInteger('count', count);
    if (count == 0) {
      throw ArgumentError.value(count, 'count', 'must be at least one');
    }
    OfficialStatIdentifiers.requireSha256('sha256', sha256);
  }

  Map<String, Object?> toContractMap() => {
    'count': count,
    'kind': kind.name,
    'partId': partId,
    'sha256': sha256,
  };
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
  final List<BoxScoreInputPartDescriptor> inputParts;
  final String inputHash;
  final String derivedHash;
  final String validationReportHash;
  final String createdBy;
  final DateTime createdAt;

  BoxScoreRevisionContract({
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
    required this.inputParts,
    required this.inputHash,
    required this.derivedHash,
    required this.validationReportHash,
    required this.createdBy,
    required this.createdAt,
  }) {
    validateInputParts(inputParts, statisticsDisposition);
    OfficialStatIdentifiers.requireSha256('inputHash', inputHash);
    final calculatedInputHash = OfficialStatCanonicalEncoding.sha256Hex(
      inputParts.map((part) => part.toContractMap()).toList(),
    );
    if (calculatedInputHash != inputHash) {
      throw ArgumentError('inputHash does not match inputParts descriptors');
    }
  }

  static void validateInputParts(
    List<BoxScoreInputPartDescriptor> parts,
    StatisticsDisposition disposition,
  ) {
    final seenIds = <String>{};
    BoxScoreInputPartDescriptor? previous;
    final kinds = <BoxScorePartKind>{};
    for (final part in parts) {
      if (!seenIds.add(part.partId)) {
        throw ArgumentError('inputParts partId values must be unique');
      }
      kinds.add(part.kind);
      if (previous != null) {
        final kindComparison = previous.kind.index.compareTo(part.kind.index);
        if (kindComparison > 0 ||
            (kindComparison == 0 &&
                previous.partId.compareTo(part.partId) >= 0)) {
          throw ArgumentError(
            'inputParts must be sorted by kind then ASCII partId',
          );
        }
      }
      previous = part;
    }
    if (!kinds.contains(BoxScorePartKind.teamOnlyInputs)) {
      throw ArgumentError(
        'Every revision requires teamOnlyInputs for outcome facts',
      );
    }
    if (disposition == StatisticsDisposition.complete) {
      const completeRequired = {
        BoxScorePartKind.playerInputs,
        BoxScorePartKind.periods,
        BoxScorePartKind.discipline,
      };
      final missing = completeRequired.difference(kinds);
      if (missing.isNotEmpty) {
        throw ArgumentError('Complete revision inputParts missing $missing');
      }
    }
  }
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
  final Fact<String> activeReleaseId;
  final int certificateEpoch;
  final int publicationEpoch;
  final int privacyEpoch;

  PublicationReleaseHeadContract({
    required this.associationId,
    required this.competitionId,
    required this.seasonId,
    required this.state,
    required this.activeReleaseId,
    required this.certificateEpoch,
    required this.publicationEpoch,
    required this.privacyEpoch,
  }) {
    final activeRelease = activeReleaseId.valueOrNull;
    if (state == ReleaseHeadState.active) {
      if (activeRelease == null) {
        throw ArgumentError('Active release head requires activeReleaseId');
      }
      OfficialStatIdentifiers.requireSha256('activeReleaseId', activeRelease);
    } else {
      final expectedReason = state == ReleaseHeadState.absent
          ? 'not_activated'
          : 'retracted';
      if (activeReleaseId case NotApplicableFact<String>(:final reasonCode)) {
        if (reasonCode != expectedReason) {
          throw ArgumentError(
            '${state.name} release head requires notApplicable($expectedReason)',
          );
        }
      } else {
        throw ArgumentError(
          '${state.name} release head requires notApplicable($expectedReason)',
        );
      }
    }
    _requireNonnegativeSafeInteger('certificateEpoch', certificateEpoch);
    _requireNonnegativeSafeInteger('publicationEpoch', publicationEpoch);
    _requireNonnegativeSafeInteger('privacyEpoch', privacyEpoch);
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
