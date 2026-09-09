import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../official_stats/canonical_encoding.dart';

/// Disabled AD01 contract only. Nothing in this library calls Firebase or is
/// imported by a live application path.
abstract final class AccountDeletionVersions {
  static const int schema = 1;
  static const String domain = 'account-deletion-domain-v1';
  static const String policyRegistry = 'unapproved';
  static const String inventory = 'account-deletion-adapter-inventory-v1';
  static const String canonicalEncoding = 'official-stat-canonical-json-v1';
  static const String fingerprint = 'account-deletion-fingerprint-v1';
  static const String statusCapability =
      'account-deletion-status-capability-v1';
}

enum AccountLifecycleState { active, deleting, deleted }

enum DeletionJobState {
  accepted,
  fencingExternalAccess,
  inventory,
  disposition,
  verify,
  retryWait,
  needsAttention,
  complete,
}

enum ResumeStage { fencingExternalAccess, inventory, disposition, verify }

enum CustodyChoice { ordinary, transferThenDelete, suspendToCustody }

enum CustodyOutcome {
  ordinary,
  transferThenDelete,
  suspendToCustody,
  policyBlockedButDeletionMustReceiveOperationalResolution,
}

enum AssociationCustodyState {
  operating,
  transferPending,
  custodyRequired,
  suspendedToCustody,
  recoveryReview,
}

enum HoldState { none, activeApproved, releasePending, unknown }

enum AdapterApplicability { applicable, notApplicable, unknown }

enum AdapterResultState {
  pending,
  blocked,
  complete,
  notApplicable,
  unsupported,
}

enum DispositionAction {
  erase,
  detach,
  pseudonymize,
  restrictedRetention,
  accessRevokedAwaitingExpiry,
  notApplicable,
  unresolved,
}

enum ProviderName { firebaseAuth, appleCredential }

enum StatusAliasBindingKind { winningOperation, sameGenerationConvergence }

enum AuthDeletionCheckpointState {
  notScheduled,
  scheduled,
  retryRequired,
  needsAttention,
  complete,
}

enum ProviderCheckpointState {
  pending,
  complete,
  retryRequired,
  manualActionGuidance,
  notApplicable,
  unknown,
}

enum DeletionStatusPhase {
  processing,
  accountRemovedCleanupPending,
  attentionRequired,
  complete,
}

enum IdempotencyDecision {
  acceptNew,
  exactReplay,
  attachStatusAlias,
  conflict,
  denyFenced,
}

enum PolicyDecisionState {
  pendingAuthoritativeDecision,
  pendingOperationalProof,
  approved,
  rejected,
  superseded,
}

enum SubmittedOperationStatusResolution {
  notAttempted,
  accepted,
  notAccepted,
  unresolved,
}

class AccountGeneration {
  final String authNamespace;
  final String accountId;
  final DateTime authCreatedAt;

  AccountGeneration({
    required this.authNamespace,
    required this.accountId,
    required this.authCreatedAt,
  }) {
    if (!AccountDeletionContract.namespaceId.hasMatch(authNamespace)) {
      throw FormatException('Invalid auth namespace');
    }
    AccountDeletionContract.requireFirebaseUid(accountId);
  }

  Map<String, Object?> toContractMap() => {
    'accountIdUtf16LeBase64Url': accountIdUtf16LeBase64Url,
    'authCreatedAt': authCreatedAt,
    'authNamespace': authNamespace,
  };

  String get accountIdUtf16LeBase64Url {
    final bytes = Uint8List(accountId.length * 2);
    final data = ByteData.view(bytes.buffer);
    for (var index = 0; index < accountId.codeUnits.length; index += 1) {
      data.setUint16(index * 2, accountId.codeUnits[index], Endian.little);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String get generationHash =>
      OfficialStatCanonicalEncoding.sha256Hex(toContractMap());
}

class RequestDeletionContract {
  final int schemaVersion;
  final String intentId;
  final String policyVersion;
  final String impactVersion;
  final String operationId;
  final String requestId;
  final String statusSecretHash;
  final String confirmation;
  final CustodyChoice custodyChoice;
  final String? providerRevocationRef;

  RequestDeletionContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.intentId,
    required this.policyVersion,
    required this.impactVersion,
    required this.operationId,
    required this.requestId,
    required this.statusSecretHash,
    this.confirmation = 'deleteAccount',
    required this.custodyChoice,
    this.providerRevocationRef,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
    for (final entry in {
      'intentId': intentId,
      'policyVersion': policyVersion,
      'impactVersion': impactVersion,
      'operationId': operationId,
      'requestId': requestId,
    }.entries) {
      AccountDeletionContract.requireOpaqueId(entry.key, entry.value);
    }
    AccountDeletionContract.requireHash('statusSecretHash', statusSecretHash);
    if (confirmation != 'deleteAccount') {
      throw FormatException('Irreversible confirmation is required');
    }
    if (providerRevocationRef != null) {
      AccountDeletionContract.requireOpaqueId(
        'providerRevocationRef',
        providerRevocationRef!,
      );
    }
  }

  factory RequestDeletionContract.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(
      map,
      const {
        'schemaVersion',
        'intentId',
        'policyVersion',
        'impactVersion',
        'operationId',
        'requestId',
        'statusSecretHash',
        'confirmation',
        'custodyChoice',
      },
      const {'providerRevocationRef'},
    );
    if (map.containsKey('providerRevocationRef') &&
        map['providerRevocationRef'] == null) {
      throw FormatException(
        'providerRevocationRef must be omitted or a string',
      );
    }
    return RequestDeletionContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      intentId: map['intentId'] as String,
      policyVersion: map['policyVersion'] as String,
      impactVersion: map['impactVersion'] as String,
      operationId: map['operationId'] as String,
      requestId: map['requestId'] as String,
      statusSecretHash: map['statusSecretHash'] as String,
      confirmation: map['confirmation'] as String,
      custodyChoice: CustodyChoice.values.byName(
        map['custodyChoice'] as String,
      ),
      providerRevocationRef: map['providerRevocationRef'] as String?,
    );
  }

  Map<String, Object?> toContractMap() => {
    'confirmation': confirmation,
    'custodyChoice': custodyChoice.name,
    'impactVersion': impactVersion,
    'intentId': intentId,
    'operationId': operationId,
    'policyVersion': policyVersion,
    if (providerRevocationRef != null)
      'providerRevocationRef': providerRevocationRef,
    'requestId': requestId,
    'schemaVersion': schemaVersion,
    'statusSecretHash': statusSecretHash,
  };
}

class AccountLifecycleContract {
  final int schemaVersion;
  final AccountLifecycleState state;
  final int epoch;
  final String generationHash;
  final String? internalJobId;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  AccountLifecycleContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.state,
    required this.epoch,
    required this.generationHash,
    this.internalJobId,
    this.acceptedAt,
    this.completedAt,
  }) {
    if (schemaVersion != 1 ||
        epoch < 0 ||
        epoch > OfficialStatCanonicalEncoding.maxSafeInteger) {
      throw FormatException('Invalid lifecycle version or epoch');
    }
    AccountDeletionContract.requireHash('generationHash', generationHash);
    if (internalJobId != null) {
      AccountDeletionContract.requireOpaqueId('internalJobId', internalJobId!);
    }
    if (state == AccountLifecycleState.active &&
        (internalJobId != null || acceptedAt != null || completedAt != null)) {
      throw FormatException('Active lifecycle cannot carry deletion state');
    }
    if (state == AccountLifecycleState.deleting &&
        (internalJobId == null || acceptedAt == null || completedAt != null)) {
      throw FormatException('Deleting lifecycle requires job and acceptance');
    }
    if (state == AccountLifecycleState.deleted &&
        (internalJobId == null || acceptedAt == null || completedAt == null)) {
      throw FormatException('Deleted lifecycle requires terminal evidence');
    }
    if (acceptedAt != null &&
        completedAt != null &&
        completedAt!.isBefore(acceptedAt!)) {
      throw FormatException('completedAt cannot precede acceptedAt');
    }
  }

  factory AccountLifecycleContract.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'state',
      'epoch',
      'generationHash',
      'internalJobId',
      'acceptedAt',
      'completedAt',
    });
    return AccountLifecycleContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      state: AccountLifecycleState.values.byName(map['state'] as String),
      epoch: AccountDeletionContract.decodeWireSafeInteger(
        'epoch',
        map['epoch'],
        nonNegative: true,
      ),
      generationHash: map['generationHash'] as String,
      internalJobId: map['internalJobId'] as String?,
      acceptedAt: map['acceptedAt'] as DateTime?,
      completedAt: map['completedAt'] as DateTime?,
    );
  }
}

class AccountDeletionJobContract {
  final int schemaVersion;
  final String internalJobId;
  final String generationHash;
  final DeletionJobState state;
  final ResumeStage? resumeStage;
  final String policyVersion;
  final String inventoryVersion;
  final int attempt;
  final int leaseGeneration;
  final bool authorityFenceDurable;
  final bool minimumCleanupReferencesCaptured;
  final AuthDeletionCheckpointState authDeletionCheckpointState;
  final bool authAbsent;
  final bool dataDispositionVerified;
  final bool publicPrivacyVerified;
  final bool custodyRecorded;
  final bool providerDispositionRecorded;
  final bool restoreSuppressionDurable;
  final String? safeErrorCode;

  AccountDeletionJobContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.internalJobId,
    required this.generationHash,
    required this.state,
    required this.resumeStage,
    required this.policyVersion,
    required this.inventoryVersion,
    required this.attempt,
    required this.leaseGeneration,
    required this.authorityFenceDurable,
    required this.minimumCleanupReferencesCaptured,
    required this.authDeletionCheckpointState,
    required this.authAbsent,
    required this.dataDispositionVerified,
    required this.publicPrivacyVerified,
    required this.custodyRecorded,
    required this.providerDispositionRecorded,
    required this.restoreSuppressionDurable,
    required this.safeErrorCode,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
    AccountDeletionContract.requireOpaqueId('internalJobId', internalJobId);
    AccountDeletionContract.requireHash('generationHash', generationHash);
    AccountDeletionContract.requireOpaqueId('policyVersion', policyVersion);
    if (inventoryVersion != AccountDeletionVersions.inventory) {
      throw FormatException('Unknown inventory version');
    }
    if (attempt < 0 ||
        attempt > OfficialStatCanonicalEncoding.maxSafeInteger ||
        leaseGeneration < 0 ||
        leaseGeneration > OfficialStatCanonicalEncoding.maxSafeInteger) {
      throw FormatException('Job counters must be nonnegative safe integers');
    }
    final needsResume =
        state == DeletionJobState.retryWait ||
        state == DeletionJobState.needsAttention;
    if ((needsResume && resumeStage == null) ||
        (!needsResume && resumeStage != null)) {
      throw FormatException(
        'retryWait/needsAttention require a resumeStage and other states forbid it',
      );
    }
    if (safeErrorCode != null &&
        !AccountDeletionContract.errorPolicies.containsKey(safeErrorCode)) {
      throw FormatException(
        'safeErrorCode must be a stable external deletion error or null',
      );
    }
    if (authorityFenceDurable &&
        minimumCleanupReferencesCaptured &&
        !authAbsent &&
        authDeletionCheckpointState ==
            AuthDeletionCheckpointState.notScheduled) {
      throw FormatException(
        'Auth deletion must be scheduled independently after its durable preconditions',
      );
    }
    if (authAbsent &&
        authDeletionCheckpointState != AuthDeletionCheckpointState.complete) {
      throw FormatException(
        'Verified Auth absence requires a complete Auth checkpoint',
      );
    }
    if (authDeletionCheckpointState == AuthDeletionCheckpointState.complete &&
        !authAbsent) {
      throw FormatException(
        'A complete Auth checkpoint requires verified Auth absence',
      );
    }
    if (state == DeletionJobState.complete &&
        (!authorityFenceDurable ||
            !minimumCleanupReferencesCaptured ||
            authDeletionCheckpointState !=
                AuthDeletionCheckpointState.complete ||
            !authAbsent ||
            !dataDispositionVerified ||
            !publicPrivacyVerified ||
            !custodyRecorded ||
            !providerDispositionRecorded ||
            !restoreSuppressionDurable ||
            safeErrorCode != null)) {
      throw FormatException(
        'Complete jobs require every summary checkpoint and no error',
      );
    }
  }

  factory AccountDeletionJobContract.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'internalJobId',
      'generationHash',
      'state',
      'resumeStage',
      'policyVersion',
      'inventoryVersion',
      'attempt',
      'leaseGeneration',
      'authorityFenceDurable',
      'minimumCleanupReferencesCaptured',
      'authDeletionCheckpointState',
      'authAbsent',
      'dataDispositionVerified',
      'publicPrivacyVerified',
      'custodyRecorded',
      'providerDispositionRecorded',
      'restoreSuppressionDurable',
      'safeErrorCode',
    });
    return AccountDeletionJobContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      internalJobId: map['internalJobId'] as String,
      generationHash: map['generationHash'] as String,
      state: DeletionJobState.values.byName(map['state'] as String),
      resumeStage: map['resumeStage'] == null
          ? null
          : ResumeStage.values.byName(map['resumeStage'] as String),
      policyVersion: map['policyVersion'] as String,
      inventoryVersion: map['inventoryVersion'] as String,
      attempt: AccountDeletionContract.decodeWireSafeInteger(
        'attempt',
        map['attempt'],
        nonNegative: true,
      ),
      leaseGeneration: AccountDeletionContract.decodeWireSafeInteger(
        'leaseGeneration',
        map['leaseGeneration'],
        nonNegative: true,
      ),
      authorityFenceDurable: map['authorityFenceDurable'] as bool,
      minimumCleanupReferencesCaptured:
          map['minimumCleanupReferencesCaptured'] as bool,
      authDeletionCheckpointState: AuthDeletionCheckpointState.values.byName(
        map['authDeletionCheckpointState'] as String,
      ),
      authAbsent: map['authAbsent'] as bool,
      dataDispositionVerified: map['dataDispositionVerified'] as bool,
      publicPrivacyVerified: map['publicPrivacyVerified'] as bool,
      custodyRecorded: map['custodyRecorded'] as bool,
      providerDispositionRecorded: map['providerDispositionRecorded'] as bool,
      restoreSuppressionDurable: map['restoreSuppressionDurable'] as bool,
      safeErrorCode: map['safeErrorCode'] as String?,
    );
  }
}

class AccountDeletionStatusAliasContract {
  final int schemaVersion;
  final String requestId;
  final String internalJobId;
  final String generationHash;
  final String acceptedSemanticFingerprint;
  final StatusAliasBindingKind bindingKind;
  final String purpose;
  final String statusSecretHash;
  final DateTime createdAt;
  final String expiryPolicyDecisionId;

  AccountDeletionStatusAliasContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.requestId,
    required this.internalJobId,
    required this.generationHash,
    required this.acceptedSemanticFingerprint,
    required this.bindingKind,
    this.purpose = 'readOnlyDeletionStatus',
    required this.statusSecretHash,
    required this.createdAt,
    required this.expiryPolicyDecisionId,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
    AccountDeletionContract.requireOpaqueId('requestId', requestId);
    AccountDeletionContract.requireOpaqueId('internalJobId', internalJobId);
    AccountDeletionContract.requireHash('generationHash', generationHash);
    AccountDeletionContract.requireHash(
      'acceptedSemanticFingerprint',
      acceptedSemanticFingerprint,
    );
    if (purpose != 'readOnlyDeletionStatus') {
      throw FormatException(
        'Status aliases are read-only deletion status capabilities',
      );
    }
    AccountDeletionContract.requireHash('statusSecretHash', statusSecretHash);
    if (!AccountDeletionContract.namespaceId.hasMatch(expiryPolicyDecisionId)) {
      throw FormatException(
        'expiryPolicyDecisionId must be a versioned policy reference',
      );
    }
  }

  factory AccountDeletionStatusAliasContract.fromContractMap(
    Map<String, Object?> map,
  ) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'requestId',
      'internalJobId',
      'generationHash',
      'acceptedSemanticFingerprint',
      'bindingKind',
      'purpose',
      'statusSecretHash',
      'createdAt',
      'expiryPolicyDecisionId',
    });
    return AccountDeletionStatusAliasContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      requestId: map['requestId'] as String,
      internalJobId: map['internalJobId'] as String,
      generationHash: map['generationHash'] as String,
      acceptedSemanticFingerprint: map['acceptedSemanticFingerprint'] as String,
      bindingKind: StatusAliasBindingKind.values.byName(
        map['bindingKind'] as String,
      ),
      purpose: map['purpose'] as String,
      statusSecretHash: map['statusSecretHash'] as String,
      createdAt: map['createdAt'] as DateTime,
      expiryPolicyDecisionId: map['expiryPolicyDecisionId'] as String,
    );
  }
}

class MinimalDeletionTombstoneContract {
  final int schemaVersion;
  final String generationHmac;
  final int deletionEpoch;
  final String policyVersion;
  final String suppressionKeyVersion;
  final DateTime acceptedAt;
  final DateTime? completedAt;
  final DateTime minimumReplayCutoff;

  MinimalDeletionTombstoneContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.generationHmac,
    required this.deletionEpoch,
    required this.policyVersion,
    required this.suppressionKeyVersion,
    required this.acceptedAt,
    required this.completedAt,
    required this.minimumReplayCutoff,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema ||
        deletionEpoch < 0 ||
        deletionEpoch > OfficialStatCanonicalEncoding.maxSafeInteger) {
      throw FormatException('Invalid tombstone version or deletion epoch');
    }
    AccountDeletionContract.requireHash('generationHmac', generationHmac);
    AccountDeletionContract.requireOpaqueId('policyVersion', policyVersion);
    AccountDeletionContract.requireOpaqueId(
      'suppressionKeyVersion',
      suppressionKeyVersion,
    );
    if (completedAt != null && completedAt!.isBefore(acceptedAt) ||
        minimumReplayCutoff.isBefore(acceptedAt)) {
      throw FormatException(
        'Tombstone timestamps violate lifecycle chronology',
      );
    }
  }

  factory MinimalDeletionTombstoneContract.fromContractMap(
    Map<String, Object?> map,
  ) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'generationHmac',
      'deletionEpoch',
      'policyVersion',
      'suppressionKeyVersion',
      'acceptedAt',
      'completedAt',
      'minimumReplayCutoff',
    });
    return MinimalDeletionTombstoneContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      generationHmac: map['generationHmac'] as String,
      deletionEpoch: AccountDeletionContract.decodeWireSafeInteger(
        'deletionEpoch',
        map['deletionEpoch'],
        nonNegative: true,
      ),
      policyVersion: map['policyVersion'] as String,
      suppressionKeyVersion: map['suppressionKeyVersion'] as String,
      acceptedAt: map['acceptedAt'] as DateTime,
      completedAt: map['completedAt'] as DateTime?,
      minimumReplayCutoff: map['minimumReplayCutoff'] as DateTime,
    );
  }
}

class AdapterResultContract {
  final int schemaVersion;
  final String adapterId;
  final AdapterApplicability applicability;
  final AdapterResultState state;
  final DispositionAction disposition;
  final PolicyDecisionState policyDecisionState;
  final String policyDecisionId;
  final String policyVersion;
  final HoldState holdState;
  final String? evidenceCode;
  final String evidenceRef;
  final DateTime? holdBoundaryAt;

  AdapterResultContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.adapterId,
    required this.applicability,
    required this.state,
    required this.disposition,
    required this.policyDecisionState,
    required this.policyDecisionId,
    required this.policyVersion,
    required this.holdState,
    this.evidenceCode,
    required this.evidenceRef,
    required this.holdBoundaryAt,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
  }

  factory AdapterResultContract.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'adapterId',
      'applicability',
      'state',
      'disposition',
      'policyDecisionState',
      'policyDecisionId',
      'policyVersion',
      'holdState',
      'evidenceCode',
      'evidenceRef',
      'holdBoundaryAt',
    });
    return AdapterResultContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      adapterId: map['adapterId'] as String,
      applicability: AdapterApplicability.values.byName(
        map['applicability'] as String,
      ),
      state: AdapterResultState.values.byName(map['state'] as String),
      disposition: DispositionAction.values.byName(
        map['disposition'] as String,
      ),
      policyDecisionState: PolicyDecisionState.values.byName(
        map['policyDecisionState'] as String,
      ),
      policyDecisionId: map['policyDecisionId'] as String,
      policyVersion: map['policyVersion'] as String,
      holdState: HoldState.values.byName(map['holdState'] as String),
      evidenceCode: map['evidenceCode'] as String?,
      evidenceRef: map['evidenceRef'] as String,
      holdBoundaryAt: map['holdBoundaryAt'] as DateTime?,
    );
  }

  Map<String, Object?> toContractMap() => {
    'schemaVersion': schemaVersion,
    'adapterId': adapterId,
    'applicability': applicability.name,
    'state': state.name,
    'disposition': disposition.name,
    'policyDecisionState': policyDecisionState.name,
    'policyDecisionId': policyDecisionId,
    'policyVersion': policyVersion,
    'holdState': holdState.name,
    'evidenceCode': evidenceCode,
    'evidenceRef': evidenceRef,
    'holdBoundaryAt': holdBoundaryAt,
  };
}

class ProviderCheckpointContract {
  final int schemaVersion;
  final ProviderName provider;
  final ProviderCheckpointState state;
  final String evidenceCode;
  final DateTime checkedAt;

  ProviderCheckpointContract({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.provider,
    required this.state,
    required this.evidenceCode,
    required this.checkedAt,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
  }

  factory ProviderCheckpointContract.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'provider',
      'state',
      'evidenceCode',
      'checkedAt',
    });
    return ProviderCheckpointContract(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      provider: ProviderName.values.byName(map['provider'] as String),
      state: ProviderCheckpointState.values.byName(map['state'] as String),
      evidenceCode: map['evidenceCode'] as String,
      checkedAt: map['checkedAt'] as DateTime,
    );
  }

  Map<String, Object?> toContractMap() => {
    'schemaVersion': schemaVersion,
    'provider': provider.name,
    'state': state.name,
    'evidenceCode': evidenceCode,
    'checkedAt': checkedAt,
  };
}

class DeletionCompletionInput {
  final int schemaVersion;
  final bool authAbsent;
  final bool dataDispositionVerified;
  final bool publicPrivacyVerified;
  final bool custodyRecorded;
  final bool providerDispositionRecorded;
  final bool restoreSuppressionDurable;
  final List<String> requiredAdapterIds;
  final List<AdapterResultContract> adapterResults;
  final List<ProviderCheckpointContract> providerCheckpoints;
  final bool unknownRequiredState;

  DeletionCompletionInput({
    this.schemaVersion = AccountDeletionVersions.schema,
    required this.authAbsent,
    required this.dataDispositionVerified,
    required this.publicPrivacyVerified,
    required this.custodyRecorded,
    required this.providerDispositionRecorded,
    required this.restoreSuppressionDurable,
    required this.requiredAdapterIds,
    required this.adapterResults,
    required this.providerCheckpoints,
    required this.unknownRequiredState,
  }) {
    if (schemaVersion != AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
  }

  factory DeletionCompletionInput.fromContractMap(Map<String, Object?> map) {
    AccountDeletionContract.requireExactKeys(map, const {
      'schemaVersion',
      'authAbsent',
      'checkpoints',
      'requiredAdapterIds',
      'adapterResults',
      'providerCheckpoints',
      'unknownRequiredState',
    });
    final checkpoints = Map<String, Object?>.from(map['checkpoints'] as Map);
    AccountDeletionContract.requireExactKeys(
      checkpoints,
      AccountDeletionContract.completionCheckpointNames.toSet(),
    );
    final adapterMaps = map['adapterResults'] as List<dynamic>;
    final providerMaps = map['providerCheckpoints'] as List<dynamic>;
    return DeletionCompletionInput(
      schemaVersion: AccountDeletionContract.decodeWireSafeInteger(
        'schemaVersion',
        map['schemaVersion'],
        nonNegative: true,
      ),
      authAbsent: map['authAbsent'] as bool,
      dataDispositionVerified: checkpoints['dataDispositionVerified'] as bool,
      publicPrivacyVerified: checkpoints['publicPrivacyVerified'] as bool,
      custodyRecorded: checkpoints['custodyRecorded'] as bool,
      providerDispositionRecorded:
          checkpoints['providerDispositionRecorded'] as bool,
      restoreSuppressionDurable:
          checkpoints['restoreSuppressionDurable'] as bool,
      requiredAdapterIds: (map['requiredAdapterIds'] as List<dynamic>)
          .cast<String>(),
      adapterResults: [
        for (final raw in adapterMaps)
          AdapterResultContract.fromContractMap(
            Map<String, Object?>.from(raw as Map),
          ),
      ],
      providerCheckpoints: [
        for (final raw in providerMaps)
          ProviderCheckpointContract.fromContractMap(
            Map<String, Object?>.from(raw as Map),
          ),
      ],
      unknownRequiredState: map['unknownRequiredState'] as bool,
    );
  }
}

class IdempotencyEvaluationInput {
  final bool hasJob;
  final bool sameOperation;
  final bool sameSemantic;
  final bool sameEnvelope;
  final bool authenticatedSameGeneration;
  final AccountLifecycleState lifecycle;

  const IdempotencyEvaluationInput({
    required this.hasJob,
    required this.sameOperation,
    required this.sameSemantic,
    required this.sameEnvelope,
    required this.authenticatedSameGeneration,
    required this.lifecycle,
  });
}

class AccountDeletionErrorPolicy {
  final String transport;
  final String retry;
  final String idempotency;

  const AccountDeletionErrorPolicy({
    required this.transport,
    required this.retry,
    required this.idempotency,
  });
}

abstract final class AccountDeletionContract {
  static final RegExp opaqueId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
  static final RegExp namespaceId = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
  );
  static final RegExp hashPattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp statusSecretPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static const List<String> completionCheckpointNames = [
    'dataDispositionVerified',
    'publicPrivacyVerified',
    'custodyRecorded',
    'providerDispositionRecorded',
    'restoreSuppressionDurable',
  ];

  static const Set<String> accountLifecycleTransitions = {
    'active->deleting',
    'deleting->deleted',
  };

  static const Set<String> deletionJobTransitions = {
    'accepted->fencingExternalAccess',
    'accepted->retryWait',
    'accepted->needsAttention',
    'fencingExternalAccess->inventory',
    'fencingExternalAccess->retryWait',
    'fencingExternalAccess->needsAttention',
    'inventory->disposition',
    'inventory->retryWait',
    'inventory->needsAttention',
    'disposition->verify',
    'disposition->retryWait',
    'disposition->needsAttention',
    'verify->complete',
    'verify->retryWait',
    'verify->needsAttention',
    'retryWait->fencingExternalAccess',
    'retryWait->inventory',
    'retryWait->disposition',
    'retryWait->verify',
    'retryWait->needsAttention',
    'needsAttention->fencingExternalAccess',
    'needsAttention->inventory',
    'needsAttention->disposition',
    'needsAttention->verify',
    'needsAttention->retryWait',
  };

  static bool canTransitionAccountLifecycle(
    AccountLifecycleState from,
    AccountLifecycleState to,
  ) => accountLifecycleTransitions.contains('${from.name}->${to.name}');

  static bool canTransitionDeletionJob(
    DeletionJobState from,
    DeletionJobState to,
  ) => deletionJobTransitions.contains('${from.name}->${to.name}');

  static void validatePrepareDeletionRequest(Map<String, Object?> value) {
    requireExactKeys(value, const {'schemaVersion'});
    if (decodeWireSafeInteger(
          'schemaVersion',
          value['schemaVersion'],
          nonNegative: true,
        ) !=
        AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
  }

  static void validateDeletionStatusRequest(Map<String, Object?> value) {
    requireExactKeys(value, const {
      'schemaVersion',
      'requestId',
      'statusSecret',
    });
    if (decodeWireSafeInteger(
          'schemaVersion',
          value['schemaVersion'],
          nonNegative: true,
        ) !=
        AccountDeletionVersions.schema) {
      throw FormatException('Unsupported schemaVersion');
    }
    requireOpaqueId('requestId', value['requestId'] as String);
    decodeStatusSecret(value['statusSecret'] as String);
  }

  static void requireExactKeys(
    Map<String, Object?> value,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    if (!value.keys.toSet().containsAll(required)) {
      throw FormatException('Missing required field');
    }
    final allowed = {...required, ...optional};
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw FormatException('Unknown field');
    }
  }

  static int decodeWireSafeInteger(
    String field,
    Object? value, {
    bool nonNegative = false,
  }) {
    if (value is! num || !value.isFinite) {
      throw FormatException('$field must be a finite safe integer');
    }
    final asDouble = value.toDouble();
    if (asDouble.truncateToDouble() != asDouble ||
        asDouble.abs() > OfficialStatCanonicalEncoding.maxSafeInteger ||
        (nonNegative && asDouble < 0)) {
      throw FormatException(
        '$field must be a${nonNegative ? ' nonnegative' : ''} finite safe integer',
      );
    }
    return asDouble == 0 ? 0 : asDouble.toInt();
  }

  static void requireOpaqueId(String field, String value) {
    if (!opaqueId.hasMatch(value)) {
      throw FormatException('$field must be an opaque 1-128 character ID');
    }
  }

  static void requireFirebaseUid(String value) {
    // Firebase Admin defines UID validity as non-empty and at most 128 UTF-16
    // code units. Preserve the provider value exactly; never normalize it.
    if (value.isEmpty || value.length > 128) {
      throw FormatException('accountId must be a valid Firebase UID');
    }
  }

  static void requireHash(String field, String value) {
    if (!hashPattern.hasMatch(value)) {
      throw FormatException('$field must be lowercase SHA-256 hex');
    }
  }

  static Map<String, Object?> semanticFingerprintInput(
    RequestDeletionContract request,
    AccountGeneration generation,
  ) => {
    'accountGeneration': generation.generationHash,
    'accountIdUtf16LeBase64Url': generation.accountIdUtf16LeBase64Url,
    'authNamespace': generation.authNamespace,
    'confirmation': request.confirmation,
    'custodyChoice': request.custodyChoice.name,
    'impactVersion': request.impactVersion,
    'policyVersion': request.policyVersion,
    'schemaVersion': request.schemaVersion,
  };

  static String semanticFingerprint(
    RequestDeletionContract request,
    AccountGeneration generation,
  ) => OfficialStatCanonicalEncoding.sha256Hex(
    semanticFingerprintInput(request, generation),
  );

  static Map<String, Object?> operationEnvelopeInput(
    RequestDeletionContract request,
    String semanticFingerprint,
  ) {
    requireHash('semanticFingerprint', semanticFingerprint);
    return {
      'operationId': request.operationId,
      'requestId': request.requestId,
      'semanticFingerprint': semanticFingerprint,
      'statusSecretHash': request.statusSecretHash,
    };
  }

  static String operationEnvelopeFingerprint(
    RequestDeletionContract request,
    String semanticFingerprint,
  ) => OfficialStatCanonicalEncoding.sha256Hex(
    operationEnvelopeInput(request, semanticFingerprint),
  );

  static Uint8List decodeStatusSecret(String value) {
    if (!statusSecretPattern.hasMatch(value)) {
      throw FormatException(
        'statusSecret must be canonical unpadded base64url for 32 bytes',
      );
    }
    late Uint8List decoded;
    try {
      decoded = Uint8List.fromList(base64Url.decode('$value='));
    } on FormatException {
      throw FormatException('Invalid statusSecret');
    }
    final encoded = base64Url.encode(decoded).replaceAll('=', '');
    if (decoded.length != 32 || encoded != value) {
      throw FormatException('statusSecret must decode to exactly 32 bytes');
    }
    return decoded;
  }

  static String statusSecretHash(String value) =>
      sha256.convert(decodeStatusSecret(value)).toString();

  static bool statusSecretMatches(String value, String expectedHash) {
    requireHash('expectedHash', expectedHash);
    final actual = hexToBytes(statusSecretHash(value));
    final expected = hexToBytes(expectedHash);
    var difference = 0;
    for (var index = 0; index < actual.length; index += 1) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }

  static Uint8List hexToBytes(String value) => Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);

  static IdempotencyDecision evaluateIdempotency(
    IdempotencyEvaluationInput input,
  ) {
    if (!input.authenticatedSameGeneration) {
      return input.lifecycle == AccountLifecycleState.active
          ? IdempotencyDecision.conflict
          : IdempotencyDecision.denyFenced;
    }
    if (!input.hasJob) {
      return input.lifecycle == AccountLifecycleState.active
          ? IdempotencyDecision.acceptNew
          : IdempotencyDecision.denyFenced;
    }
    if (input.sameOperation) {
      return input.sameSemantic && input.sameEnvelope
          ? IdempotencyDecision.exactReplay
          : IdempotencyDecision.conflict;
    }
    return IdempotencyDecision.attachStatusAlias;
  }

  static String resolveSubmittedOperationFailure({
    required String errorCode,
    required bool hasPersistedRequestMaterial,
    required SubmittedOperationStatusResolution statusResolution,
  }) {
    const statusFirstCodes = {
      'AD_UNAUTHENTICATED',
      'AD_REAUTH_REQUIRED',
      'AD_APP_ATTESTATION_REQUIRED',
    };
    if (!statusFirstCodes.contains(errorCode) || !hasPersistedRequestMaterial) {
      return errorCode;
    }
    return switch (statusResolution) {
      SubmittedOperationStatusResolution.accepted => 'AD_ALREADY_ACCEPTED',
      SubmittedOperationStatusResolution.notAccepted => errorCode,
      SubmittedOperationStatusResolution.unresolved => 'AD_STATUS_UNAVAILABLE',
      SubmittedOperationStatusResolution.notAttempted =>
        'AD_ACCEPTANCE_UNKNOWN',
    };
  }

  static bool authDeletionScheduleRequired({
    required bool authorityFenceDurable,
    required bool minimumCleanupReferencesCaptured,
    required bool authAbsent,
    required bool hasUnknownAdapter,
    required bool retentionClassificationResolved,
    required bool custodyResolved,
  }) {
    final _ = (
      hasUnknownAdapter,
      retentionClassificationResolved,
      custodyResolved,
    );
    return authorityFenceDurable &&
        minimumCleanupReferencesCaptured &&
        !authAbsent;
  }

  static bool canReplayGrant({
    required AccountLifecycleState lifecycle,
    required bool generationMatches,
    required bool epochMatches,
    required bool capabilityPresent,
  }) =>
      lifecycle == AccountLifecycleState.active &&
      generationMatches &&
      epochMatches &&
      capabilityPresent;

  static bool _adapterComplete(AdapterResultContract result) {
    if (result.schemaVersion != AccountDeletionVersions.schema ||
        !adapterIds.contains(result.adapterId) ||
        result.evidenceCode == null ||
        !opaqueId.hasMatch(result.evidenceCode!) ||
        result.policyDecisionId != 'retention.${result.adapterId}' ||
        !namespaceId.hasMatch(result.policyDecisionId) ||
        !opaqueId.hasMatch(result.policyVersion) ||
        !opaqueId.hasMatch(result.evidenceRef) ||
        (result.holdBoundaryAt != null &&
            result.holdBoundaryAt!.millisecondsSinceEpoch.abs() >
                OfficialStatCanonicalEncoding.maxSafeInteger) ||
        result.applicability == AdapterApplicability.unknown ||
        result.holdState == HoldState.unknown ||
        result.policyDecisionState != PolicyDecisionState.approved) {
      return false;
    }
    if (result.state == AdapterResultState.notApplicable) {
      return result.applicability == AdapterApplicability.notApplicable &&
          result.disposition == DispositionAction.notApplicable &&
          result.holdState == HoldState.none &&
          result.holdBoundaryAt == null;
    }
    if (result.applicability != AdapterApplicability.applicable ||
        result.state != AdapterResultState.complete ||
        result.disposition == DispositionAction.unresolved ||
        result.disposition == DispositionAction.notApplicable) {
      return false;
    }
    if (result.disposition == DispositionAction.restrictedRetention) {
      return result.holdState == HoldState.activeApproved &&
          result.holdBoundaryAt != null;
    }
    return result.holdState == HoldState.none && result.holdBoundaryAt == null;
  }

  static bool providerCheckpointTerminal(ProviderCheckpointContract value) {
    if (value.schemaVersion != AccountDeletionVersions.schema ||
        !opaqueId.hasMatch(value.evidenceCode) ||
        value.checkedAt.millisecondsSinceEpoch.abs() >
            OfficialStatCanonicalEncoding.maxSafeInteger) {
      return false;
    }
    if (value.provider == ProviderName.firebaseAuth) {
      return value.state == ProviderCheckpointState.complete;
    }
    return value.state == ProviderCheckpointState.complete ||
        value.state == ProviderCheckpointState.notApplicable ||
        value.state == ProviderCheckpointState.manualActionGuidance;
  }

  static bool isDeletionComplete(DeletionCompletionInput input) {
    if (input.schemaVersion != AccountDeletionVersions.schema ||
        !input.authAbsent ||
        input.unknownRequiredState) {
      return false;
    }
    if (!input.dataDispositionVerified ||
        !input.publicPrivacyVerified ||
        !input.custodyRecorded ||
        !input.providerDispositionRecorded ||
        !input.restoreSuppressionDurable ||
        input.providerCheckpoints.length != ProviderName.values.length) {
      return false;
    }
    if (input.requiredAdapterIds.length != adapterIds.length ||
        input.adapterResults.length != adapterIds.length) {
      return false;
    }
    for (var index = 0; index < adapterIds.length; index += 1) {
      if (input.requiredAdapterIds[index] != adapterIds[index]) return false;
    }
    final providers = <ProviderName>{};
    for (final checkpoint in input.providerCheckpoints) {
      if (!providers.add(checkpoint.provider) ||
          !providerCheckpointTerminal(checkpoint)) {
        return false;
      }
    }
    if (!providers.containsAll(ProviderName.values)) return false;
    final byId = <String, AdapterResultContract>{};
    for (final result in input.adapterResults) {
      if (byId.containsKey(result.adapterId)) return false;
      byId[result.adapterId] = result;
    }
    return adapterIds.every(
      (id) => byId[id] != null && _adapterComplete(byId[id]!),
    );
  }

  static bool selfDeletionEligible({
    required bool authenticatedSameGeneration,
    required bool hasProfile,
    required bool hasMembership,
    required String? legacyRole,
  }) {
    // These are deliberately non-authoritative compatibility observations.
    final _ = (hasProfile, hasMembership, legacyRole);
    return authenticatedSameGeneration;
  }

  static CustodyOutcome resolveCustodyOutcome({
    required bool isLastRecoverableOwner,
    required bool transferVerified,
    required bool namedCustodyAvailable,
  }) {
    if (!isLastRecoverableOwner) return CustodyOutcome.ordinary;
    if (transferVerified) return CustodyOutcome.transferThenDelete;
    if (namedCustodyAvailable) return CustodyOutcome.suspendToCustody;
    return CustodyOutcome
        .policyBlockedButDeletionMustReceiveOperationalResolution;
  }

  static const List<String> adapterIds = [
    'firebase_auth_identity',
    'user_profile',
    'memberships_capabilities',
    'device_fcm_preferences',
    'notification_inbox',
    'team_assignments',
    'pending_invites',
    'historical_invites',
    'authorization_evidence',
    'personal_ugc',
    'official_notices',
    'acknowledgements',
    'event_attribution',
    'account_person_claims',
    'person_identity_evidence',
    'legacy_player_identity',
    'legacy_game_evidence',
    'v2_journal_operations',
    'local_offline_journal',
    'v2_certified_evidence',
    'public_projections_exports',
    'personal_storage_media',
    'shared_association_media',
    'device_local_state',
    'diagnostics_processors',
    'backups_restores',
    'deletion_operational_residue',
  ];

  static const Map<String, AccountDeletionErrorPolicy> errorPolicies = {
    'AD_UNAUTHENTICATED': AccountDeletionErrorPolicy(
      transport: 'unauthenticated',
      retry: 'resolveSavedStatusBeforeNewAuthentication',
      idempotency: 'acceptanceUnknownUnlessStatusResolved',
    ),
    'AD_REAUTH_REQUIRED': AccountDeletionErrorPolicy(
      transport: 'unauthenticated',
      retry: 'resolveSavedStatusBeforeNewAuthentication',
      idempotency: 'acceptanceUnknownUnlessStatusResolved',
    ),
    'AD_IDENTITY_MISMATCH': AccountDeletionErrorPolicy(
      transport: 'permission-denied',
      retry: 'never',
      idempotency: 'notAccepted',
    ),
    'AD_APP_ATTESTATION_REQUIRED': AccountDeletionErrorPolicy(
      transport: 'failed-precondition',
      retry: 'resolveSavedStatusBeforeNewAuthentication',
      idempotency: 'acceptanceUnknownUnlessStatusResolved',
    ),
    'AD_INVALID_REQUEST': AccountDeletionErrorPolicy(
      transport: 'invalid-argument',
      retry: 'never',
      idempotency: 'notAccepted',
    ),
    'AD_INTENT_EXPIRED': AccountDeletionErrorPolicy(
      transport: 'failed-precondition',
      retry: 'refreshImpactThenCreateNewOperation',
      idempotency: 'notAccepted',
    ),
    'AD_IMPACT_CHANGED': AccountDeletionErrorPolicy(
      transport: 'failed-precondition',
      retry: 'refreshImpactThenCreateNewOperation',
      idempotency: 'notAccepted',
    ),
    'AD_OPERATION_CONFLICT': AccountDeletionErrorPolicy(
      transport: 'already-exists',
      retry: 'never',
      idempotency: 'sameKeyDifferentPayloadRejected',
    ),
    'AD_ALREADY_ACCEPTED': AccountDeletionErrorPolicy(
      transport: 'success',
      retry: 'returnBoundStatusAlias',
      idempotency: 'safeReplayReturnsOriginalAcceptance',
    ),
    'AD_ACCEPTANCE_UNKNOWN': AccountDeletionErrorPolicy(
      transport: 'acceptance-unknown',
      retry: 'resolveSavedStatusBeforeNewAuthentication',
      idempotency: 'mayAlreadyBeAccepted',
    ),
    'AD_TRANSFER_NOT_READY': AccountDeletionErrorPolicy(
      transport: 'failed-precondition',
      retry: 'operatorResolutionRequired',
      idempotency: 'notAccepted',
    ),
    'AD_POLICY_NOT_READY': AccountDeletionErrorPolicy(
      transport: 'failed-precondition',
      retry: 'operatorResolutionRequired',
      idempotency: 'notAccepted',
    ),
    'AD_RATE_LIMITED': AccountDeletionErrorPolicy(
      transport: 'resource-exhausted',
      retry: 'retrySameOperation',
      idempotency: 'notAcceptedUnlessReceiptExists',
    ),
    'AD_TEMPORARILY_UNAVAILABLE': AccountDeletionErrorPolicy(
      transport: 'unavailable',
      retry: 'resolveStatusThenRetrySameOperation',
      idempotency: 'mayAlreadyBeAccepted',
    ),
    'AD_STATUS_UNAVAILABLE': AccountDeletionErrorPolicy(
      transport: 'uniform-status-error',
      retry: 'useExistingReceiptOrVerifiedRecovery',
      idempotency: 'noMutation',
    ),
    'AD_REVIEW_REQUIRED': AccountDeletionErrorPolicy(
      transport: 'accepted-status',
      retry: 'operatorResolutionRequired',
      idempotency: 'acceptedJobRemainsFenced',
    ),
  };

  static const List<String> internalErrorCodes = [
    'AUTH_DELETE_RETRY',
    'MEDIA_VERSION_CONFLICT',
    'RETENTION_CLASS_UNKNOWN',
    'REFERENCE_REMAINS',
    'CUSTODY_CONFLICT',
    'UNSUPPORTED_REQUIRED_ADAPTER',
  ];
}
