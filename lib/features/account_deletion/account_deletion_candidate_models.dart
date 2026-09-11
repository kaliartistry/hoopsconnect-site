import '../../models/account_deletion/account_deletion_contract.dart';
import '../../models/account_deletion/account_lifecycle_ad02_v2.dart';
import '../../models/auth_incarnation/auth_incarnation_v2.dart';

/// The lifecycle surface is deliberately unreachable from production roots.
///
/// A later integration packet must replace this candidate boundary instead of
/// toggling the value in place.
const bool accountDeletionCandidateActivationAllowed = false;

enum AccountDeletionReauthenticationMethod { password, google, apple }

enum AccountDeletionReauthenticationOutcome { verified, cancelled }

enum AppleRevocationMaterialState {
  notApplicable,
  staged,
  unavailable,
  unknown,
}

enum AppleAccountRelationship { notLinked, linked, unknown }

enum AccountDeletionOwnershipResolution {
  ordinaryMember,
  transferVerified,
  custodySuspensionPrepared,
  operationalResolutionRequired,
}

enum AccountDeletionLocalWorkState {
  checking,
  clear,
  requiresReconciliation,
  readyWithDeviceConsent,
  unavailable,
}

enum AccountDeletionLocalWorkAction {
  reconcileOrExport,
  discardUnacceptedDrafts,
}

enum AccountDeletionJourneyPhase {
  bootstrapping,
  overview,
  reauthenticating,
  preparingImpact,
  impactReview,
  submitting,
  resolvingSubmittedStatus,
  acceptanceUnknown,
  processing,
  accountRemovedCleanupPending,
  attentionRequired,
  complete,
  retrySameOperation,
  requestRejected,
  unavailable,
}

enum AccountDeletionReceiptState {
  readyToSubmit,
  acceptanceUnknown,
  accepted,
  complete,
  definitiveNotAccepted,
}

final class AccountDeletionProviderProfile {
  AccountDeletionProviderProfile({
    required Iterable<AccountDeletionReauthenticationMethod> methods,
    required this.appleRelationship,
  }) : methods = Set.unmodifiable(methods) {
    if (this.methods.isEmpty) {
      throw const FormatException(
        'At least one reauthentication method is required.',
      );
    }
    if (appleRelationship == AppleAccountRelationship.notLinked &&
        this.methods.contains(AccountDeletionReauthenticationMethod.apple)) {
      throw const FormatException(
        'An Apple reauthentication method requires an Apple relationship.',
      );
    }
  }

  final Set<AccountDeletionReauthenticationMethod> methods;
  final AppleAccountRelationship appleRelationship;

  AccountDeletionReauthenticationMethod get recommendedMethod =>
      appleRelationship != AppleAccountRelationship.notLinked &&
          methods.contains(AccountDeletionReauthenticationMethod.apple)
      ? AccountDeletionReauthenticationMethod.apple
      : methods.first;
}

/// Exact local identity boundary for account-deletion recovery and teardown.
///
/// This is device-local binding material, not a client-selected deletion
/// target. Production adapters must derive it from the current authenticated
/// account generation and the device session that owns the local journal.
final class AccountDeletionDeviceBinding {
  AccountDeletionDeviceBinding({
    required this.authProjectIdV2,
    required this.authTenantIdV2,
    required this.accountId,
    required this.accountGeneration,
    required this.accountLifecycleEpochV2,
    required this.deviceSessionId,
  }) {
    AuthIncarnationScopeV2.fromMap({
      'authProjectIdV2': authProjectIdV2,
      'authTenantIdV2': authTenantIdV2,
      'authUidV2': accountId,
    });
    if (!AuthIncarnationV2.generationPattern.hasMatch(accountGeneration)) {
      throw const FormatException('Invalid account deletion generation.');
    }
    if (accountLifecycleEpochV2 < 0 ||
        accountLifecycleEpochV2 > AuthIncarnationV2.maxSafeInteger) {
      throw const FormatException('Invalid account deletion lifecycle epoch.');
    }
    AccountDeletionContract.requireOpaqueId('deviceSessionId', deviceSessionId);
  }

  final String authProjectIdV2;
  final String? authTenantIdV2;
  final String accountId;
  final String accountGeneration;
  final int accountLifecycleEpochV2;
  final String deviceSessionId;

  bool matches(AccountDeletionDeviceBinding other) =>
      authProjectIdV2 == other.authProjectIdV2 &&
      authTenantIdV2 == other.authTenantIdV2 &&
      accountId == other.accountId &&
      accountGeneration == other.accountGeneration &&
      accountLifecycleEpochV2 == other.accountLifecycleEpochV2 &&
      deviceSessionId == other.deviceSessionId;
}

/// Unforgeable live-session binding for every pre-acceptance async boundary.
final class AccountDeletionOperationBinding {
  AccountDeletionOperationBinding({
    required this.deviceBinding,
    required this.sessionAttemptIdV2,
    required this.sessionAttemptEpochV2,
    required this.sessionAttemptNonceV2,
  }) {
    AccountDeletionContract.requireOpaqueId(
      'sessionAttemptIdV2',
      sessionAttemptIdV2,
    );
    if (sessionAttemptEpochV2 <= 0 ||
        sessionAttemptEpochV2 > AuthIncarnationV2.maxSafeInteger) {
      throw const FormatException('Invalid deletion session-attempt epoch.');
    }
  }

  final AccountDeletionDeviceBinding deviceBinding;
  final String sessionAttemptIdV2;
  final int sessionAttemptEpochV2;
  final Object sessionAttemptNonceV2;

  bool matches(AccountDeletionOperationBinding other) =>
      deviceBinding.matches(other.deviceBinding) &&
      sessionAttemptIdV2 == other.sessionAttemptIdV2 &&
      sessionAttemptEpochV2 == other.sessionAttemptEpochV2 &&
      identical(sessionAttemptNonceV2, other.sessionAttemptNonceV2);
}

final class AccountDeletionReauthenticationResult {
  AccountDeletionReauthenticationResult({
    required this.operationBinding,
    required this.method,
    required this.outcome,
    required this.appleRevocationMaterialState,
    this.providerRevocationRef,
  }) {
    if (method != AccountDeletionReauthenticationMethod.apple &&
        (appleRevocationMaterialState !=
                AppleRevocationMaterialState.notApplicable ||
            providerRevocationRef != null)) {
      throw const FormatException(
        'Only Apple reauthentication can stage Apple revocation material.',
      );
    }
    if (outcome == AccountDeletionReauthenticationOutcome.cancelled &&
        providerRevocationRef != null) {
      throw const FormatException(
        'A cancelled provider flow cannot stage revocation material.',
      );
    }
    if (appleRevocationMaterialState == AppleRevocationMaterialState.staged &&
        providerRevocationRef == null) {
      throw const FormatException(
        'Staged Apple revocation material requires an opaque reference.',
      );
    }
    if (providerRevocationRef != null) {
      AccountDeletionContract.requireOpaqueId(
        'providerRevocationRef',
        providerRevocationRef!,
      );
    }
  }

  final AccountDeletionReauthenticationMethod method;
  final AccountDeletionOperationBinding operationBinding;
  final AccountDeletionReauthenticationOutcome outcome;
  final AppleRevocationMaterialState appleRevocationMaterialState;
  final String? providerRevocationRef;
}

final class AccountDeletionLocalWorkSummary {
  AccountDeletionLocalWorkSummary({
    required this.binding,
    required this.state,
    required this.workspaceCount,
    required this.unacceptedOperationCount,
    required this.receiptUnknownOperationCount,
    required this.acceptedOperationCount,
    this.manifestId,
    this.manifestChecksum,
    this.deviceConsentId,
    this.safeMessageCode,
  }) {
    for (final count in [
      workspaceCount,
      unacceptedOperationCount,
      receiptUnknownOperationCount,
      acceptedOperationCount,
    ]) {
      if (count < 0) {
        throw const FormatException('Local journal counts cannot be negative.');
      }
    }
    if (receiptUnknownOperationCount > unacceptedOperationCount) {
      throw const FormatException(
        'Receipt-unknown work must be a subset of unaccepted work.',
      );
    }
    final hasManifest =
        manifestId != null ||
        manifestChecksum != null ||
        deviceConsentId != null;
    if (state == AccountDeletionLocalWorkState.readyWithDeviceConsent) {
      if (manifestId == null ||
          manifestChecksum == null ||
          deviceConsentId == null) {
        throw const FormatException(
          'Resolved local work requires an exact manifest and device consent.',
        );
      }
      AccountDeletionContract.requireOpaqueId('manifestId', manifestId!);
      AccountDeletionContract.requireHash(
        'manifestChecksum',
        manifestChecksum!,
      );
      AccountDeletionContract.requireOpaqueId(
        'deviceConsentId',
        deviceConsentId!,
      );
      if (receiptUnknownOperationCount != 0) {
        throw const FormatException(
          'Resolved local work cannot retain receipt-unknown operations.',
        );
      }
    } else if (hasManifest) {
      throw const FormatException(
        'Unresolved local work cannot carry reusable consent material.',
      );
    }
    if (safeMessageCode != null) {
      AccountDeletionContract.requireOpaqueId(
        'safeMessageCode',
        safeMessageCode!,
      );
    }
  }

  factory AccountDeletionLocalWorkSummary.clear(
    AccountDeletionDeviceBinding binding,
  ) => AccountDeletionLocalWorkSummary(
    binding: binding,
    state: AccountDeletionLocalWorkState.clear,
    workspaceCount: 0,
    unacceptedOperationCount: 0,
    receiptUnknownOperationCount: 0,
    acceptedOperationCount: 0,
  );

  final AccountDeletionDeviceBinding binding;
  final AccountDeletionLocalWorkState state;
  final int workspaceCount;
  final int unacceptedOperationCount;
  final int receiptUnknownOperationCount;
  final int acceptedOperationCount;
  final String? manifestId;
  final String? manifestChecksum;
  final String? deviceConsentId;
  final String? safeMessageCode;

  bool get requiresAction =>
      state == AccountDeletionLocalWorkState.requiresReconciliation ||
      state == AccountDeletionLocalWorkState.unavailable ||
      state == AccountDeletionLocalWorkState.checking;

  bool get permitsDiscardWithoutReconciliation =>
      state == AccountDeletionLocalWorkState.requiresReconciliation &&
      receiptUnknownOperationCount == 0;

  bool get readyForRequest =>
      state == AccountDeletionLocalWorkState.clear ||
      state == AccountDeletionLocalWorkState.readyWithDeviceConsent;
}

final class CandidateAccountDeletionImpact {
  CandidateAccountDeletionImpact({
    required this.operationBinding,
    required this.intentId,
    required this.policyVersion,
    required this.impactVersion,
    required this.expiresAt,
    required this.custodyChoice,
    required this.ownershipResolution,
    required this.isLastRecoverableOwner,
    required this.associationId,
    required this.serverDeletionContinuesIndependently,
    required this.sportingHistoryIsNotAccountData,
  }) {
    for (final entry in {
      'intentId': intentId,
      'policyVersion': policyVersion,
      'impactVersion': impactVersion,
    }.entries) {
      AccountDeletionContract.requireOpaqueId(entry.key, entry.value);
    }
    if (!expiresAt.isUtc) {
      throw const FormatException('Deletion impact expiry must be UTC.');
    }
    if (associationId != null) {
      AccountDeletionContract.requireOpaqueId('associationId', associationId!);
    }
    if (!serverDeletionContinuesIndependently ||
        !sportingHistoryIsNotAccountData) {
      throw const FormatException(
        'The deletion impact cannot weaken lifecycle or sporting-history boundaries.',
      );
    }
    switch (ownershipResolution) {
      case AccountDeletionOwnershipResolution.ordinaryMember:
        if (isLastRecoverableOwner || custodyChoice != CustodyChoice.ordinary) {
          throw const FormatException(
            'Ordinary custody impact is inconsistent.',
          );
        }
      case AccountDeletionOwnershipResolution.transferVerified:
        if (!isLastRecoverableOwner ||
            custodyChoice != CustodyChoice.transferThenDelete) {
          throw const FormatException(
            'Transfer custody impact is inconsistent.',
          );
        }
      case AccountDeletionOwnershipResolution.custodySuspensionPrepared:
      case AccountDeletionOwnershipResolution.operationalResolutionRequired:
        if (!isLastRecoverableOwner ||
            custodyChoice != CustodyChoice.suspendToCustody) {
          throw const FormatException(
            'Custody-suspension impact is inconsistent.',
          );
        }
    }
  }

  final String intentId;
  final AccountDeletionOperationBinding operationBinding;
  final String policyVersion;
  final String impactVersion;
  final DateTime expiresAt;
  final CustodyChoice custodyChoice;
  final AccountDeletionOwnershipResolution ownershipResolution;
  final bool isLastRecoverableOwner;
  final String? associationId;
  final bool serverDeletionContinuesIndependently;
  final bool sportingHistoryIsNotAccountData;

  bool get needsOperationalCustodyResolution =>
      ownershipResolution ==
      AccountDeletionOwnershipResolution.operationalResolutionRequired;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);
}

final class AcceptedAccountDeletionRequest {
  AcceptedAccountDeletionRequest({
    required this.operationBinding,
    required this.requestId,
    required this.internalJobId,
    required this.acceptedAt,
    required this.nextPollAfter,
    required this.sameGenerationConvergence,
  }) {
    AccountDeletionContract.requireOpaqueId('requestId', requestId);
    AccountDeletionContract.requireOpaqueId('internalJobId', internalJobId);
    if (!acceptedAt.isUtc) {
      throw const FormatException('Deletion acceptance time must be UTC.');
    }
    if (nextPollAfter <= Duration.zero ||
        nextPollAfter > const Duration(hours: 1)) {
      throw const FormatException(
        'The next poll delay must be positive and bounded.',
      );
    }
  }

  final AccountDeletionOperationBinding operationBinding;
  final String requestId;
  final String internalJobId;
  final DateTime acceptedAt;
  final Duration nextPollAfter;
  final bool sameGenerationConvergence;
}

final class AccountDeletionStatusSnapshot {
  AccountDeletionStatusSnapshot({
    required this.requestId,
    required this.phase,
    required this.acceptedAt,
    required this.completedAt,
    required this.nextPollAfter,
    required this.providerOutcome,
    required this.messageCode,
    required Iterable<String> retainedCategoryCodes,
  }) : retainedCategoryCodes = List.unmodifiable(retainedCategoryCodes) {
    AccountDeletionContract.requireOpaqueId('requestId', requestId);
    AccountDeletionContract.requireOpaqueId('messageCode', messageCode);
    final expectedMessageCode = switch (phase) {
      DeletionStatusPhase.processing => 'AD_DELETION_REQUESTED',
      DeletionStatusPhase.accountRemovedCleanupPending =>
        'AD_ACCOUNT_REMOVED_CLEANUP_PENDING',
      DeletionStatusPhase.attentionRequired => 'AD_CLEANUP_ATTENTION_REQUIRED',
      DeletionStatusPhase.complete => 'AD_ACCOUNT_DELETION_COMPLETE',
    };
    if (messageCode != expectedMessageCode) {
      throw const FormatException(
        'Deletion phase and AD04 status message code must match.',
      );
    }
    if (!acceptedAt.isUtc || (completedAt != null && !completedAt!.isUtc)) {
      throw const FormatException('Deletion status times must be UTC.');
    }
    if (completedAt != null && completedAt!.isBefore(acceptedAt)) {
      throw const FormatException('Completion cannot precede acceptance.');
    }
    if (phase == DeletionStatusPhase.complete) {
      if (completedAt == null || nextPollAfter != null) {
        throw const FormatException(
          'Complete status requires completion time and no next poll.',
        );
      }
      if (providerOutcome != ProviderCheckpointState.complete &&
          providerOutcome != ProviderCheckpointState.notApplicable &&
          providerOutcome != ProviderCheckpointState.manualActionGuidance) {
        throw const FormatException(
          'Complete status requires a terminal provider outcome.',
        );
      }
    } else if (completedAt != null ||
        nextPollAfter == null ||
        nextPollAfter! <= Duration.zero) {
      throw const FormatException(
        'Nonterminal status requires a positive next poll and no completion time.',
      );
    }
    for (final code in this.retainedCategoryCodes) {
      AccountDeletionContract.requireOpaqueId('retainedCategoryCode', code);
    }
    if (this.retainedCategoryCodes.toSet().length !=
        this.retainedCategoryCodes.length) {
      throw const FormatException('Retained category codes must be unique.');
    }
  }

  final String requestId;
  final DeletionStatusPhase phase;
  final DateTime acceptedAt;
  final DateTime? completedAt;
  final Duration? nextPollAfter;
  final ProviderCheckpointState providerOutcome;
  final String messageCode;
  final List<String> retainedCategoryCodes;
}

final class AccountDeletionLocalCleanupResult {
  AccountDeletionLocalCleanupResult({
    required this.listenersStopped,
    required this.notificationRegistrationDetached,
    required this.ordinaryCachesCleared,
    required this.localNotificationsCancelled,
    required this.localOfficialWorkPreservedOrConsented,
    this.safeMessageCode,
  }) {
    if (safeMessageCode != null) {
      AccountDeletionContract.requireOpaqueId(
        'safeMessageCode',
        safeMessageCode!,
      );
    }
  }

  final bool listenersStopped;
  final bool notificationRegistrationDetached;
  final bool ordinaryCachesCleared;
  final bool localNotificationsCancelled;
  final bool localOfficialWorkPreservedOrConsented;
  final String? safeMessageCode;

  bool get completeOnThisDevice =>
      listenersStopped &&
      notificationRegistrationDetached &&
      ordinaryCachesCleared &&
      localNotificationsCancelled &&
      localOfficialWorkPreservedOrConsented;
}

final class CandidateAccountDeletionReceipt {
  CandidateAccountDeletionReceipt({
    required this.binding,
    required this.request,
    required this.statusSecret,
    required this.state,
    required this.recordedAt,
    required this.requiresCustodyAttention,
    this.custodyAttentionObserved = false,
    this.terminalErrorCode,
  }) {
    AccountDeletionContract.requireFirebaseUid(binding.accountId);
    AccountDeletionContract.decodeStatusSecret(statusSecret);
    if (AccountDeletionContract.statusSecretHash(statusSecret) !=
        request.statusSecretHash) {
      throw const FormatException(
        'The saved status secret does not match the deletion request.',
      );
    }
    if (!recordedAt.isUtc) {
      throw const FormatException('Deletion receipt time must be UTC.');
    }
    if (custodyAttentionObserved && !requiresCustodyAttention) {
      throw const FormatException(
        'Custody-attention evidence requires an unresolved-custody receipt.',
      );
    }
    final terminalPolicy = terminalErrorCode == null
        ? null
        : AccountDeletionContract.errorPolicies[terminalErrorCode];
    if (state == AccountDeletionReceiptState.definitiveNotAccepted) {
      if (terminalPolicy == null ||
          (terminalPolicy.retry != 'never' &&
              terminalPolicy.retry != 'operatorResolutionRequired')) {
        throw const FormatException(
          'A definitive rejection requires a frozen never or operator-resolution policy.',
        );
      }
    } else if (terminalErrorCode != null) {
      throw const FormatException(
        'Only a definitive rejection may retain a terminal error code.',
      );
    }
  }

  final AccountDeletionDeviceBinding binding;
  final RequestDeletionContract request;
  final String statusSecret;
  final AccountDeletionReceiptState state;
  final DateTime recordedAt;
  final bool requiresCustodyAttention;
  final bool custodyAttentionObserved;
  final String? terminalErrorCode;

  CandidateAccountDeletionReceipt copyWith({
    AccountDeletionReceiptState? state,
    DateTime? recordedAt,
    bool? custodyAttentionObserved,
    String? terminalErrorCode,
    bool clearTerminalErrorCode = false,
  }) => CandidateAccountDeletionReceipt(
    binding: binding,
    request: request,
    statusSecret: statusSecret,
    state: state ?? this.state,
    recordedAt: recordedAt ?? this.recordedAt,
    requiresCustodyAttention: requiresCustodyAttention,
    custodyAttentionObserved:
        custodyAttentionObserved ?? this.custodyAttentionObserved,
    terminalErrorCode: clearTerminalErrorCode
        ? null
        : terminalErrorCode ?? this.terminalErrorCode,
  );
}

/// One exact cleanup authorization envelope for the current device.
///
/// The server receipt proves the fence. The three matching device bindings
/// prove that the receipt and journal belong to the account data being cleared.
final class AccountDeletionLocalCleanupRequest {
  AccountDeletionLocalCleanupRequest({
    required this.currentBinding,
    required this.receipt,
    required this.localWork,
  }) {
    if (!receipt.binding.matches(currentBinding) ||
        !localWork.binding.matches(currentBinding)) {
      throw const FormatException(
        'Cleanup receipt, local work, and current device binding must match.',
      );
    }
    if (receipt.state != AccountDeletionReceiptState.accepted &&
        receipt.state != AccountDeletionReceiptState.complete) {
      throw const FormatException(
        'Only a server-accepted receipt can authorize local cleanup.',
      );
    }
  }

  final AccountDeletionDeviceBinding currentBinding;
  final CandidateAccountDeletionReceipt receipt;
  final AccountDeletionLocalWorkSummary localWork;
}

final class AccountDeletionCandidateFailure implements Exception {
  const AccountDeletionCandidateFailure(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'AccountDeletionCandidateFailure($code)';
}

final class AccountDeletionCandidateState {
  const AccountDeletionCandidateState({
    required this.phase,
    required this.providerProfile,
    required this.selectedMethod,
    required this.localWork,
    required this.impact,
    required this.receipt,
    required this.status,
    required this.localCleanup,
    required this.confirmedConsequences,
    required this.confirmationText,
    required this.noticeCode,
    required this.errorCode,
  });

  factory AccountDeletionCandidateState.initial(
    AccountDeletionProviderProfile providerProfile,
    AccountDeletionDeviceBinding binding,
  ) => AccountDeletionCandidateState(
    phase: AccountDeletionJourneyPhase.bootstrapping,
    providerProfile: providerProfile,
    selectedMethod: providerProfile.recommendedMethod,
    localWork: AccountDeletionLocalWorkSummary(
      binding: binding,
      state: AccountDeletionLocalWorkState.checking,
      workspaceCount: 0,
      unacceptedOperationCount: 0,
      receiptUnknownOperationCount: 0,
      acceptedOperationCount: 0,
    ),
    impact: null,
    receipt: null,
    status: null,
    localCleanup: null,
    confirmedConsequences: false,
    confirmationText: '',
    noticeCode: null,
    errorCode: null,
  );

  final AccountDeletionJourneyPhase phase;
  final AccountDeletionProviderProfile providerProfile;
  final AccountDeletionReauthenticationMethod selectedMethod;
  final AccountDeletionLocalWorkSummary localWork;
  final CandidateAccountDeletionImpact? impact;
  final CandidateAccountDeletionReceipt? receipt;
  final AccountDeletionStatusSnapshot? status;
  final AccountDeletionLocalCleanupResult? localCleanup;
  final bool confirmedConsequences;
  final String confirmationText;
  final String? noticeCode;
  final String? errorCode;

  bool get canPrepareImpact =>
      phase == AccountDeletionJourneyPhase.overview &&
      localWork.readyForRequest;

  bool get canSubmit =>
      phase == AccountDeletionJourneyPhase.impactReview &&
      impact != null &&
      confirmedConsequences &&
      confirmationText == 'DELETE';

  bool get canRetrySameOperation =>
      phase == AccountDeletionJourneyPhase.retrySameOperation &&
      receipt?.state == AccountDeletionReceiptState.acceptanceUnknown;

  /// Explicit handoff target for the production router owner.
  ///
  /// The candidate does not navigate or import GoRouter. It only reports the
  /// agreed stable destination after each lifecycle transition.
  String get routeHandoffPath {
    if (receipt?.state == AccountDeletionReceiptState.definitiveNotAccepted) {
      return AccountLifecycleCandidateRoutePathsV2.requestDeletion;
    }
    if (receipt != null &&
        receipt!.state != AccountDeletionReceiptState.readyToSubmit) {
      return AccountLifecycleCandidateRoutePathsV2.deletionStatus;
    }
    if (phase == AccountDeletionJourneyPhase.overview &&
        localWork.state ==
            AccountDeletionLocalWorkState.requiresReconciliation) {
      return AccountLifecycleCandidateRoutePathsV2.reconcileDeviceWork;
    }
    return AccountLifecycleCandidateRoutePathsV2.requestDeletion;
  }

  AccountDeletionCandidateState copyWith({
    AccountDeletionJourneyPhase? phase,
    AccountDeletionReauthenticationMethod? selectedMethod,
    AccountDeletionLocalWorkSummary? localWork,
    CandidateAccountDeletionImpact? impact,
    bool clearImpact = false,
    CandidateAccountDeletionReceipt? receipt,
    bool clearReceipt = false,
    AccountDeletionStatusSnapshot? status,
    bool clearStatus = false,
    AccountDeletionLocalCleanupResult? localCleanup,
    bool clearLocalCleanup = false,
    bool? confirmedConsequences,
    String? confirmationText,
    String? noticeCode,
    bool clearNotice = false,
    String? errorCode,
    bool clearError = false,
  }) => AccountDeletionCandidateState(
    phase: phase ?? this.phase,
    providerProfile: providerProfile,
    selectedMethod: selectedMethod ?? this.selectedMethod,
    localWork: localWork ?? this.localWork,
    impact: clearImpact ? null : impact ?? this.impact,
    receipt: clearReceipt ? null : receipt ?? this.receipt,
    status: clearStatus ? null : status ?? this.status,
    localCleanup: clearLocalCleanup ? null : localCleanup ?? this.localCleanup,
    confirmedConsequences: confirmedConsequences ?? this.confirmedConsequences,
    confirmationText: confirmationText ?? this.confirmationText,
    noticeCode: clearNotice ? null : noticeCode ?? this.noticeCode,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
  );
}
