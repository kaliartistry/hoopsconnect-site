import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/account_deletion/account_deletion_contract.dart';
import 'account_deletion_candidate_models.dart';

abstract interface class CandidateAccountDeletionGateway {
  /// Candidate gateways must be isolated fakes or emulator adapters. A live
  /// transport is rejected while this packet remains dormant.
  bool get isSyntheticCandidate;

  Future<CandidateAccountDeletionImpact> prepareDeletion();

  Future<AcceptedAccountDeletionRequest> requestDeletion(
    RequestDeletionContract request,
  );

  Future<AccountDeletionStatusSnapshot> deletionStatus({
    required String requestId,
    required String statusSecret,
  });
}

abstract interface class CandidateAccountDeletionReauthenticator {
  bool get isSyntheticCandidate;

  Future<AccountDeletionReauthenticationResult> reauthenticate({
    required AccountDeletionReauthenticationMethod method,
    String? password,
  });
}

abstract interface class CandidateAccountDeletionDeviceCleanup {
  bool get isSyntheticCandidate;

  Future<AccountDeletionLocalWorkSummary> inspectLocalOfficialWork();

  /// The concrete adapter must bind any choice to an exact per-device
  /// manifest. Consent from another device is never accepted here.
  Future<AccountDeletionLocalWorkSummary> resolveLocalOfficialWork(
    AccountDeletionLocalWorkAction action,
  );

  /// Runs only after server acceptance. Failure is reported separately and
  /// never changes an accepted server request into a rejected one.
  Future<AccountDeletionLocalCleanupResult> clearAfterServerFence(
    AccountDeletionLocalWorkSummary localWork,
  );
}

abstract interface class CandidateAccountDeletionReceiptStore {
  Future<CandidateAccountDeletionReceipt?> read();

  Future<void> write(CandidateAccountDeletionReceipt receipt);

  /// Only an operation proven not accepted may be cleared through this
  /// candidate API. Accepted or still-ambiguous receipts remain recoverable.
  Future<void> clearProvenNotAccepted(CandidateAccountDeletionReceipt receipt);
}

abstract interface class AccountDeletionCandidateClock {
  DateTime nowUtc();
}

final class SystemAccountDeletionCandidateClock
    implements AccountDeletionCandidateClock {
  const SystemAccountDeletionCandidateClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class CandidateDeletionOperationMaterial {
  const CandidateDeletionOperationMaterial({
    required this.operationId,
    required this.requestId,
    required this.statusSecret,
  });

  final String operationId;
  final String requestId;
  final String statusSecret;
}

abstract interface class CandidateDeletionOperationFactory {
  CandidateDeletionOperationMaterial create();
}

final class SecureCandidateDeletionOperationFactory
    implements CandidateDeletionOperationFactory {
  SecureCandidateDeletionOperationFactory({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  CandidateDeletionOperationMaterial create() =>
      CandidateDeletionOperationMaterial(
        operationId: _base64Url(18),
        requestId: _base64Url(18),
        statusSecret: _base64Url(32),
      );

  String _base64Url(int length) {
    final bytes = Uint8List.fromList([
      for (var index = 0; index < length; index++) _random.nextInt(256),
    ]);
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Dormant orchestration for the reviewable deletion surface.
///
/// It accepts only synthetic dependencies. It intentionally has no Firebase,
/// GoRouter, auth-provider, notification-service, or production repository
/// imports. The integration owner must provide those roots in a later packet.
final class AccountDeletionCandidateController extends ChangeNotifier {
  AccountDeletionCandidateController({
    required AccountDeletionProviderProfile providerProfile,
    required CandidateAccountDeletionGateway gateway,
    required CandidateAccountDeletionReauthenticator reauthenticator,
    required CandidateAccountDeletionDeviceCleanup deviceCleanup,
    required CandidateAccountDeletionReceiptStore receiptStore,
    AccountDeletionCandidateClock clock =
        const SystemAccountDeletionCandidateClock(),
    CandidateDeletionOperationFactory? operationFactory,
  }) : _gateway = gateway,
       _reauthenticator = reauthenticator,
       _deviceCleanup = deviceCleanup,
       _receiptStore = receiptStore,
       _clock = clock,
       _operationFactory =
           operationFactory ?? SecureCandidateDeletionOperationFactory(),
       _state = AccountDeletionCandidateState.initial(providerProfile) {
    if (accountDeletionCandidateActivationAllowed ||
        !_gateway.isSyntheticCandidate ||
        !_reauthenticator.isSyntheticCandidate ||
        !_deviceCleanup.isSyntheticCandidate) {
      throw StateError(
        'The dormant deletion controller accepts synthetic dependencies only.',
      );
    }
  }

  final CandidateAccountDeletionGateway _gateway;
  final CandidateAccountDeletionReauthenticator _reauthenticator;
  final CandidateAccountDeletionDeviceCleanup _deviceCleanup;
  final CandidateAccountDeletionReceiptStore _receiptStore;
  final AccountDeletionCandidateClock _clock;
  final CandidateDeletionOperationFactory _operationFactory;

  AccountDeletionCandidateState _state;
  int _operationEpoch = 0;
  bool _disposed = false;
  String? _providerRevocationRef;

  AccountDeletionCandidateState get state => _state;

  Future<void> initialize() async {
    final epoch = _beginOperation();
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.bootstrapping,
        clearError: true,
        clearNotice: true,
      ),
    );
    try {
      final receipt = await _receiptStore.read();
      if (!_isCurrent(epoch)) return;
      if (receipt != null &&
          receipt.state != AccountDeletionReceiptState.readyToSubmit) {
        final localWork = await _inspectLocalWorkSafely();
        if (!_isCurrent(epoch)) return;
        _emit(
          _state.copyWith(
            receipt: receipt,
            localWork: localWork,
            phase: AccountDeletionJourneyPhase.resolvingSubmittedStatus,
          ),
        );
        await _refreshStatusForEpoch(epoch);
        return;
      }
      if (receipt != null) {
        await _receiptStore.clearProvenNotAccepted(receipt);
        if (!_isCurrent(epoch)) return;
      }
      final localWork = await _inspectLocalWorkSafely();
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.overview,
          localWork: localWork,
          clearReceipt: true,
          clearStatus: true,
          clearLocalCleanup: true,
        ),
      );
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.unavailable,
          errorCode: _safeCode(error, fallback: 'AD_CANDIDATE_UNAVAILABLE'),
        ),
      );
    }
  }

  void selectReauthenticationMethod(
    AccountDeletionReauthenticationMethod method,
  ) {
    if (_state.phase != AccountDeletionJourneyPhase.overview ||
        !_state.providerProfile.methods.contains(method)) {
      return;
    }
    _providerRevocationRef = null;
    _emit(
      _state.copyWith(
        selectedMethod: method,
        clearError: true,
        clearNotice: true,
      ),
    );
  }

  Future<void> resolveLocalWork(AccountDeletionLocalWorkAction action) async {
    if (_state.phase != AccountDeletionJourneyPhase.overview ||
        _state.localWork.state !=
            AccountDeletionLocalWorkState.requiresReconciliation) {
      return;
    }
    if (action == AccountDeletionLocalWorkAction.discardUnacceptedDrafts &&
        !_state.localWork.permitsDiscardWithoutReconciliation) {
      _emit(
        _state.copyWith(
          errorCode: 'AD_LOCAL_RECEIPT_RECONCILIATION_REQUIRED',
          clearNotice: true,
        ),
      );
      return;
    }
    final epoch = _beginOperation();
    _emit(
      _state.copyWith(
        localWork: AccountDeletionLocalWorkSummary(
          state: AccountDeletionLocalWorkState.checking,
          workspaceCount: _state.localWork.workspaceCount,
          unacceptedOperationCount: _state.localWork.unacceptedOperationCount,
          receiptUnknownOperationCount:
              _state.localWork.receiptUnknownOperationCount,
          acceptedOperationCount: _state.localWork.acceptedOperationCount,
        ),
        clearError: true,
        clearNotice: true,
      ),
    );
    try {
      final resolved = await _deviceCleanup.resolveLocalOfficialWork(action);
      if (!_isCurrent(epoch)) return;
      if (!resolved.readyForRequest) {
        throw const AccountDeletionCandidateFailure(
          'AD_LOCAL_WORK_NOT_RESOLVED',
        );
      }
      _emit(
        _state.copyWith(
          localWork: resolved,
          noticeCode: 'AD_LOCAL_DEVICE_CONSENT_RECORDED',
        ),
      );
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          localWork: AccountDeletionLocalWorkSummary(
            state: AccountDeletionLocalWorkState.unavailable,
            workspaceCount: _state.localWork.workspaceCount,
            unacceptedOperationCount: _state.localWork.unacceptedOperationCount,
            receiptUnknownOperationCount:
                _state.localWork.receiptUnknownOperationCount,
            acceptedOperationCount: _state.localWork.acceptedOperationCount,
            safeMessageCode: _safeCode(
              error,
              fallback: 'AD_LOCAL_WORK_UNAVAILABLE',
            ),
          ),
          errorCode: _safeCode(error, fallback: 'AD_LOCAL_WORK_UNAVAILABLE'),
        ),
      );
    }
  }

  Future<void> continueToImpact({String? password}) async {
    if (!_state.canPrepareImpact) return;
    final method = _state.selectedMethod;
    if (method == AccountDeletionReauthenticationMethod.password &&
        (password == null || password.isEmpty)) {
      _emit(
        _state.copyWith(errorCode: 'AD_PASSWORD_REQUIRED', clearNotice: true),
      );
      return;
    }
    final epoch = _beginOperation();
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.reauthenticating,
        clearError: true,
        clearNotice: true,
      ),
    );
    try {
      final reauthentication = await _reauthenticator.reauthenticate(
        method: method,
        password: method == AccountDeletionReauthenticationMethod.password
            ? password
            : null,
      );
      if (!_isCurrent(epoch)) return;
      if (reauthentication.method != method) {
        throw const AccountDeletionCandidateFailure(
          'AD_REAUTH_METHOD_MISMATCH',
        );
      }
      if (reauthentication.outcome ==
          AccountDeletionReauthenticationOutcome.cancelled) {
        _providerRevocationRef = null;
        _emit(
          _state.copyWith(
            phase: AccountDeletionJourneyPhase.overview,
            noticeCode: 'AD_PROVIDER_REAUTH_CANCELLED',
            clearError: true,
          ),
        );
        return;
      }
      _providerRevocationRef = reauthentication.providerRevocationRef;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.preparingImpact,
          noticeCode:
              reauthentication.appleRevocationMaterialState ==
                  AppleRevocationMaterialState.unavailable
              ? 'AD_APPLE_REVOCATION_MATERIAL_UNAVAILABLE'
              : null,
          clearNotice:
              reauthentication.appleRevocationMaterialState !=
              AppleRevocationMaterialState.unavailable,
        ),
      );
      final impact = await _gateway.prepareDeletion();
      if (!_isCurrent(epoch)) return;
      if (impact.isExpiredAt(_clock.nowUtc())) {
        throw const AccountDeletionCandidateFailure('AD_INTENT_EXPIRED');
      }
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.impactReview,
          impact: impact,
          confirmedConsequences: false,
          confirmationText: '',
          errorCode: impact.needsOperationalCustodyResolution
              ? 'AD_CUSTODY_OPERATIONAL_RESOLUTION_REQUIRED'
              : null,
          clearError: !impact.needsOperationalCustodyResolution,
        ),
      );
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      _providerRevocationRef = null;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.overview,
          clearImpact: true,
          errorCode: _safeCode(error, fallback: 'AD_PREPARE_FAILED'),
        ),
      );
    }
  }

  void setConsequencesConfirmed(bool value) {
    if (_state.phase != AccountDeletionJourneyPhase.impactReview) return;
    _emit(_state.copyWith(confirmedConsequences: value, clearError: true));
  }

  void setConfirmationText(String value) {
    if (_state.phase != AccountDeletionJourneyPhase.impactReview) return;
    _emit(
      _state.copyWith(
        confirmationText: value.length > 16 ? value.substring(0, 16) : value,
        clearError: true,
      ),
    );
  }

  Future<void> submitDeletion() async {
    final impact = _state.impact;
    if (_state.phase != AccountDeletionJourneyPhase.impactReview ||
        impact == null ||
        !_state.localWork.readyForRequest ||
        !(_state.confirmedConsequences &&
            _state.confirmationText == 'DELETE')) {
      return;
    }
    if (impact.needsOperationalCustodyResolution) {
      _emit(
        _state.copyWith(
          errorCode: 'AD_CUSTODY_OPERATIONAL_RESOLUTION_REQUIRED',
        ),
      );
      return;
    }
    if (impact.isExpiredAt(_clock.nowUtc())) {
      _providerRevocationRef = null;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.overview,
          clearImpact: true,
          errorCode: 'AD_INTENT_EXPIRED',
          confirmedConsequences: false,
          confirmationText: '',
        ),
      );
      return;
    }

    final material = _operationFactory.create();
    final request = RequestDeletionContract(
      intentId: impact.intentId,
      policyVersion: impact.policyVersion,
      impactVersion: impact.impactVersion,
      operationId: material.operationId,
      requestId: material.requestId,
      statusSecretHash: AccountDeletionContract.statusSecretHash(
        material.statusSecret,
      ),
      custodyChoice: impact.custodyChoice,
      providerRevocationRef: _providerRevocationRef,
    );
    var receipt = CandidateAccountDeletionReceipt(
      request: request,
      statusSecret: material.statusSecret,
      state: AccountDeletionReceiptState.readyToSubmit,
      recordedAt: _clock.nowUtc(),
    );
    final epoch = _beginOperation();
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.submitting,
        receipt: receipt,
        clearError: true,
        clearNotice: true,
      ),
    );
    CandidateAccountDeletionReceipt? persistedBeforeTransport;
    try {
      await _receiptStore.write(receipt);
      persistedBeforeTransport = receipt;
      if (!_isCurrent(epoch)) return;
      receipt = receipt.copyWith(
        state: AccountDeletionReceiptState.acceptanceUnknown,
        recordedAt: _clock.nowUtc(),
      );
      await _receiptStore.write(receipt);
      persistedBeforeTransport = receipt;
      if (!_isCurrent(epoch)) return;
      _emit(_state.copyWith(receipt: receipt));
    } catch (_) {
      if (!_isCurrent(epoch)) return;
      if (persistedBeforeTransport != null) {
        try {
          await _receiptStore.clearProvenNotAccepted(persistedBeforeTransport);
        } catch (_) {
          // No transport ran. A conservative leftover receipt remains safe and
          // can only attempt read-only status recovery after restart.
        }
      }
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.impactReview,
          clearReceipt: true,
          errorCode: 'AD_RECEIPT_STORAGE_UNAVAILABLE',
        ),
      );
      return;
    }
    try {
      final accepted = await _gateway.requestDeletion(request);
      if (!_isCurrent(epoch)) return;
      if (accepted.requestId != request.requestId) {
        throw const AccountDeletionCandidateFailure(
          'AD_ACCEPTANCE_BINDING_MISMATCH',
        );
      }
      receipt = receipt.copyWith(
        state: AccountDeletionReceiptState.accepted,
        recordedAt: accepted.acceptedAt,
      );
      await _receiptStore.write(receipt);
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.processing,
          receipt: receipt,
          noticeCode: accepted.sameGenerationConvergence
              ? 'AD_ALREADY_ACCEPTED'
              : 'AD_DELETION_REQUESTED',
          clearError: true,
        ),
      );
      await _clearThisDeviceAfterFence(epoch);
      await _refreshStatusForEpoch(epoch, preserveAcceptedOnFailure: true);
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      await _resolveSubmittedFailure(epoch, error);
    }
  }

  Future<void> refreshStatus() async {
    final receipt = _state.receipt;
    if (receipt == null ||
        receipt.state == AccountDeletionReceiptState.readyToSubmit) {
      return;
    }
    final epoch = _beginOperation();
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.resolvingSubmittedStatus,
        clearError: true,
      ),
    );
    await _refreshStatusForEpoch(epoch, preserveAcceptedOnFailure: true);
  }

  void restartImpactReview() {
    if (_state.phase != AccountDeletionJourneyPhase.impactReview) return;
    _providerRevocationRef = null;
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.overview,
        clearImpact: true,
        confirmedConsequences: false,
        confirmationText: '',
        clearError: true,
        clearNotice: true,
      ),
    );
  }

  Future<AccountDeletionLocalWorkSummary> _inspectLocalWorkSafely() async {
    try {
      return await _deviceCleanup.inspectLocalOfficialWork();
    } catch (error) {
      return AccountDeletionLocalWorkSummary(
        state: AccountDeletionLocalWorkState.unavailable,
        workspaceCount: 0,
        unacceptedOperationCount: 0,
        receiptUnknownOperationCount: 0,
        acceptedOperationCount: 0,
        safeMessageCode: _safeCode(
          error,
          fallback: 'AD_LOCAL_WORK_UNAVAILABLE',
        ),
      );
    }
  }

  Future<void> _resolveSubmittedFailure(int epoch, Object error) async {
    final receipt = _state.receipt;
    if (receipt == null) {
      _emit(
        _state.copyWith(
          phase: AccountDeletionJourneyPhase.impactReview,
          errorCode: _safeCode(error, fallback: 'AD_REQUEST_FAILED'),
        ),
      );
      return;
    }
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.resolvingSubmittedStatus,
        noticeCode: 'AD_ACCEPTANCE_UNKNOWN',
        clearError: true,
      ),
    );
    try {
      await _refreshStatusForEpoch(epoch);
    } catch (_) {
      // _refreshStatusForEpoch normally owns presentation of status failures.
    }
    final code = _safeCode(error, fallback: 'AD_ACCEPTANCE_UNKNOWN');
    if (!_isCurrent(epoch)) return;
    if (_provesNotAccepted(code) &&
        (_state.phase == AccountDeletionJourneyPhase.resolvingSubmittedStatus ||
            _state.phase == AccountDeletionJourneyPhase.acceptanceUnknown)) {
      try {
        await _receiptStore.clearProvenNotAccepted(receipt);
      } catch (_) {
        if (!_isCurrent(epoch)) return;
        _emit(
          _state.copyWith(
            phase: AccountDeletionJourneyPhase.acceptanceUnknown,
            errorCode: 'AD_RECEIPT_CLEAR_FAILED',
            noticeCode: code,
          ),
        );
        return;
      }
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: code == 'AD_INTENT_EXPIRED' || code == 'AD_IMPACT_CHANGED'
              ? AccountDeletionJourneyPhase.overview
              : AccountDeletionJourneyPhase.impactReview,
          clearReceipt: true,
          clearImpact:
              code == 'AD_INTENT_EXPIRED' || code == 'AD_IMPACT_CHANGED',
          errorCode: code,
          clearNotice: true,
        ),
      );
      return;
    }
    if (_state.phase != AccountDeletionJourneyPhase.resolvingSubmittedStatus) {
      return;
    }
    _emit(
      _state.copyWith(
        phase: AccountDeletionJourneyPhase.acceptanceUnknown,
        receipt: receipt.copyWith(
          state: AccountDeletionReceiptState.acceptanceUnknown,
          recordedAt: _clock.nowUtc(),
        ),
        errorCode: 'AD_ACCEPTANCE_UNKNOWN',
        noticeCode: code,
      ),
    );
  }

  Future<void> _refreshStatusForEpoch(
    int epoch, {
    bool preserveAcceptedOnFailure = false,
  }) async {
    final receipt = _state.receipt;
    if (receipt == null) return;
    try {
      final status = await _gateway.deletionStatus(
        requestId: receipt.request.requestId,
        statusSecret: receipt.statusSecret,
      );
      if (!_isCurrent(epoch)) return;
      if (status.requestId != receipt.request.requestId) {
        throw const AccountDeletionCandidateFailure(
          'AD_STATUS_BINDING_MISMATCH',
        );
      }
      final nextReceipt = receipt.copyWith(
        state: status.phase == DeletionStatusPhase.complete
            ? AccountDeletionReceiptState.complete
            : AccountDeletionReceiptState.accepted,
        recordedAt: _clock.nowUtc(),
      );
      await _receiptStore.write(nextReceipt);
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          phase: _journeyPhase(status.phase),
          receipt: nextReceipt,
          status: status,
          clearError: true,
          clearNotice: true,
        ),
      );
      if (_state.localCleanup == null ||
          !_state.localCleanup!.completeOnThisDevice) {
        await _clearThisDeviceAfterFence(epoch);
      }
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      if (receipt.state == AccountDeletionReceiptState.acceptanceUnknown) {
        _emit(
          _state.copyWith(
            phase: AccountDeletionJourneyPhase.acceptanceUnknown,
            errorCode: 'AD_STATUS_UNAVAILABLE',
          ),
        );
      } else if (preserveAcceptedOnFailure ||
          receipt.state == AccountDeletionReceiptState.accepted ||
          receipt.state == AccountDeletionReceiptState.complete) {
        _emit(
          _state.copyWith(
            phase: _state.status == null
                ? AccountDeletionJourneyPhase.processing
                : _journeyPhase(_state.status!.phase),
            errorCode: 'AD_STATUS_UNAVAILABLE',
          ),
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> _clearThisDeviceAfterFence(int epoch) async {
    try {
      final result = await _deviceCleanup.clearAfterServerFence(
        _state.localWork,
      );
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          localCleanup: result,
          errorCode: result.completeOnThisDevice
              ? _state.errorCode
              : result.safeMessageCode ?? 'AD_DEVICE_CLEANUP_INCOMPLETE',
        ),
      );
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      _emit(
        _state.copyWith(
          localCleanup: AccountDeletionLocalCleanupResult(
            listenersStopped: false,
            notificationRegistrationDetached: false,
            ordinaryCachesCleared: false,
            localNotificationsCancelled: false,
            localOfficialWorkPreservedOrConsented:
                _state.localWork.readyForRequest,
            safeMessageCode: _safeCode(
              error,
              fallback: 'AD_DEVICE_CLEANUP_INCOMPLETE',
            ),
          ),
          errorCode: _safeCode(error, fallback: 'AD_DEVICE_CLEANUP_INCOMPLETE'),
        ),
      );
    }
  }

  static AccountDeletionJourneyPhase _journeyPhase(DeletionStatusPhase phase) =>
      switch (phase) {
        DeletionStatusPhase.processing =>
          AccountDeletionJourneyPhase.processing,
        DeletionStatusPhase.accountRemovedCleanupPending =>
          AccountDeletionJourneyPhase.accountRemovedCleanupPending,
        DeletionStatusPhase.attentionRequired =>
          AccountDeletionJourneyPhase.attentionRequired,
        DeletionStatusPhase.complete => AccountDeletionJourneyPhase.complete,
      };

  static bool _provesNotAccepted(String code) => const {
    'AD_INVALID_REQUEST',
    'AD_INTENT_EXPIRED',
    'AD_IMPACT_CHANGED',
    'AD_OPERATION_CONFLICT',
    'AD_TRANSFER_NOT_READY',
    'AD_POLICY_NOT_READY',
  }.contains(code);

  static String _safeCode(Object error, {required String fallback}) {
    if (error is AccountDeletionCandidateFailure) return error.code;
    return fallback;
  }

  int _beginOperation() => ++_operationEpoch;

  bool _isCurrent(int epoch) => !_disposed && _operationEpoch == epoch;

  void _emit(AccountDeletionCandidateState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationEpoch++;
    super.dispose();
  }
}

/// Candidate-only in-memory receipt store used by previews and tests.
/// Production integration requires encrypted, durable, account-scoped storage.
final class InMemoryCandidateAccountDeletionReceiptStore
    implements CandidateAccountDeletionReceiptStore {
  CandidateAccountDeletionReceipt? _receipt;

  @override
  Future<CandidateAccountDeletionReceipt?> read() async => _receipt;

  @override
  Future<void> write(CandidateAccountDeletionReceipt receipt) async {
    _receipt = receipt;
  }

  @override
  Future<void> clearProvenNotAccepted(
    CandidateAccountDeletionReceipt receipt,
  ) async {
    final stored = _receipt;
    if (stored == null ||
        stored.state == AccountDeletionReceiptState.accepted ||
        stored.state == AccountDeletionReceiptState.complete ||
        receipt.state == AccountDeletionReceiptState.accepted ||
        receipt.state == AccountDeletionReceiptState.complete ||
        stored.request.requestId != receipt.request.requestId ||
        stored.request.operationId != receipt.request.operationId ||
        stored.request.statusSecretHash != receipt.request.statusSecretHash ||
        stored.statusSecret != receipt.statusSecret) {
      throw StateError(
        'Only the exact receipt proven not accepted may be cleared.',
      );
    }
    _receipt = null;
  }
}
