import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_controller.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

void main() {
  group('candidate account deletion controller', () {
    test('persists status capability before one bound request', () async {
      final gateway = _Gateway(statuses: [_status()]);
      final reauth = _Reauthenticator(_passwordVerified());
      final cleanup = _DeviceCleanup(AccountDeletionLocalWorkSummary.clear());
      final receiptStore = _ReceiptStore();
      final controller = _controller(
        gateway: gateway,
        reauthenticator: reauth,
        cleanup: cleanup,
        receiptStore: receiptStore,
      );

      await controller.initialize();
      expect(controller.state.phase, AccountDeletionJourneyPhase.overview);
      await controller.continueToImpact(password: 'correct horse');
      expect(controller.state.phase, AccountDeletionJourneyPhase.impactReview);
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await controller.submitDeletion();

      expect(controller.state.phase, AccountDeletionJourneyPhase.processing);
      expect(gateway.requestCalls, 1);
      expect(gateway.lastRequest, isNotNull);
      expect(gateway.lastRequest!.operationId, 'operation_fixed');
      expect(gateway.lastRequest!.requestId, 'request_fixed');
      expect(
        gateway.lastRequest!.statusSecretHash,
        AccountDeletionContract.statusSecretHash(_statusSecret),
      );
      expect(gateway.lastRequest!.custodyChoice, CustodyChoice.ordinary);
      expect(receiptStore.writeStates, [
        AccountDeletionReceiptState.readyToSubmit,
        AccountDeletionReceiptState.acceptanceUnknown,
        AccountDeletionReceiptState.accepted,
        AccountDeletionReceiptState.accepted,
      ]);
      expect(cleanup.clearCalls, 1);
      expect(controller.state.localCleanup!.completeOnThisDevice, isTrue);
    });

    test(
      'provider cancellation sends no prepare or deletion request',
      () async {
        final gateway = _Gateway(statuses: [_status()]);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(
            AccountDeletionReauthenticationResult(
              method: AccountDeletionReauthenticationMethod.google,
              outcome: AccountDeletionReauthenticationOutcome.cancelled,
              appleRevocationMaterialState:
                  AppleRevocationMaterialState.notApplicable,
            ),
          ),
          cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
          receiptStore: _ReceiptStore(),
          profile: AccountDeletionProviderProfile(
            methods: const [AccountDeletionReauthenticationMethod.google],
            appleRelationship: AppleAccountRelationship.notLinked,
          ),
        );

        await controller.initialize();
        await controller.continueToImpact();

        expect(controller.state.phase, AccountDeletionJourneyPhase.overview);
        expect(controller.state.noticeCode, 'AD_PROVIDER_REAUTH_CANCELLED');
        expect(gateway.prepareCalls, 0);
        expect(gateway.requestCalls, 0);
      },
    );

    test('Apple seam forwards only the opaque revocation reference', () async {
      final gateway = _Gateway(
        statuses: [
          _status(
            phase: DeletionStatusPhase.complete,
            providerOutcome: ProviderCheckpointState.manualActionGuidance,
          ),
        ],
      );
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(
          AccountDeletionReauthenticationResult(
            method: AccountDeletionReauthenticationMethod.apple,
            outcome: AccountDeletionReauthenticationOutcome.verified,
            appleRevocationMaterialState: AppleRevocationMaterialState.staged,
            providerRevocationRef: 'apple_ref_1',
          ),
        ),
        cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
        receiptStore: _ReceiptStore(),
        profile: AccountDeletionProviderProfile(
          methods: const [AccountDeletionReauthenticationMethod.apple],
          appleRelationship: AppleAccountRelationship.linked,
        ),
      );

      await controller.initialize();
      await controller.continueToImpact();
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await controller.submitDeletion();

      expect(gateway.lastRequest!.providerRevocationRef, 'apple_ref_1');
      expect(controller.state.phase, AccountDeletionJourneyPhase.complete);
      expect(
        controller.state.status!.providerOutcome,
        ProviderCheckpointState.manualActionGuidance,
      );
    });

    test('receipt-unknown local work cannot be discarded', () async {
      final cleanup = _DeviceCleanup(
        AccountDeletionLocalWorkSummary(
          state: AccountDeletionLocalWorkState.requiresReconciliation,
          workspaceCount: 1,
          unacceptedOperationCount: 2,
          receiptUnknownOperationCount: 1,
          acceptedOperationCount: 3,
        ),
        resolved: _resolvedLocalWork(),
      );
      final controller = _controller(
        gateway: _Gateway(statuses: [_status()]),
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: cleanup,
        receiptStore: _ReceiptStore(),
      );

      await controller.initialize();
      await controller.resolveLocalWork(
        AccountDeletionLocalWorkAction.discardUnacceptedDrafts,
      );
      expect(cleanup.resolveCalls, 0);
      expect(
        controller.state.errorCode,
        'AD_LOCAL_RECEIPT_RECONCILIATION_REQUIRED',
      );

      await controller.resolveLocalWork(
        AccountDeletionLocalWorkAction.reconcileOrExport,
      );
      expect(cleanup.resolveCalls, 1);
      expect(controller.state.localWork.readyForRequest, isTrue);
      expect(
        controller.state.localWork.state,
        AccountDeletionLocalWorkState.readyWithDeviceConsent,
      );
    });

    test(
      'saved receipt recovers after Auth removal without reauth loop',
      () async {
        final store = _ReceiptStore(seed: _receipt());
        final reauth = _Reauthenticator(_passwordVerified());
        final controller = _controller(
          gateway: _Gateway(
            statuses: [
              _status(phase: DeletionStatusPhase.accountRemovedCleanupPending),
            ],
          ),
          reauthenticator: reauth,
          cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
          receiptStore: store,
        );

        await controller.initialize();

        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.accountRemovedCleanupPending,
        );
        expect(reauth.calls, 0);
        expect(
          controller.state.receipt!.state,
          AccountDeletionReceiptState.accepted,
        );
      },
    );

    test('lost response resolves saved status before any retry', () async {
      final gateway = _Gateway(
        requestError: const AccountDeletionCandidateFailure(
          'AD_TEMPORARILY_UNAVAILABLE',
        ),
        statuses: [
          const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
        ],
      );
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
        receiptStore: _ReceiptStore(),
      );

      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await controller.submitDeletion();

      expect(
        controller.state.phase,
        AccountDeletionJourneyPhase.acceptanceUnknown,
      );
      expect(controller.state.errorCode, 'AD_STATUS_UNAVAILABLE');
      expect(gateway.requestCalls, 1);
      expect(gateway.statusCalls, 1);

      gateway
        ..requestError = null
        ..statuses.add(_status());
      await controller.refreshStatus();

      expect(controller.state.phase, AccountDeletionJourneyPhase.processing);
      expect(
        gateway.requestCalls,
        1,
        reason: 'status recovery must not resubmit',
      );
      expect(gateway.statusCalls, 2);
    });

    for (final failingWrite in [1, 2]) {
      test(
        'receipt write $failingWrite failure sends no deletion request',
        () async {
          final gateway = _Gateway(statuses: [_status()]);
          final store = _ReceiptStore(failWriteAt: failingWrite);
          final controller = _controller(
            gateway: gateway,
            reauthenticator: _Reauthenticator(_passwordVerified()),
            cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
            receiptStore: store,
          );

          await controller.initialize();
          await controller.continueToImpact(password: 'correct horse');
          controller.setConsequencesConfirmed(true);
          controller.setConfirmationText('DELETE');
          await controller.submitDeletion();

          expect(
            controller.state.phase,
            AccountDeletionJourneyPhase.impactReview,
          );
          expect(controller.state.errorCode, 'AD_RECEIPT_STORAGE_UNAVAILABLE');
          expect(gateway.requestCalls, 0);
          expect(store.receipt, isNull);
        },
      );
    }

    test(
      'proved server rejection clears ambiguity only after status check',
      () async {
        final gateway = _Gateway(
          requestError: const AccountDeletionCandidateFailure(
            'AD_POLICY_NOT_READY',
          ),
          statuses: [
            const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
          ],
        );
        final store = _ReceiptStore();
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
          receiptStore: store,
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(gateway.requestCalls, 1);
        expect(gateway.statusCalls, 1);
        expect(store.clearCalls, 1);
        expect(store.receipt, isNull);
        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.impactReview,
        );
        expect(controller.state.errorCode, 'AD_POLICY_NOT_READY');
      },
    );

    test(
      'failed receipt clear stays conservative after proved rejection',
      () async {
        final gateway = _Gateway(
          requestError: const AccountDeletionCandidateFailure(
            'AD_POLICY_NOT_READY',
          ),
          statuses: [
            const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
          ],
        );
        final store = _ReceiptStore(failClear: true);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
          receiptStore: store,
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(store.receipt, isNotNull);
        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.acceptanceUnknown,
        );
        expect(controller.state.errorCode, 'AD_RECEIPT_CLEAR_FAILED');
        expect(gateway.requestCalls, 1);
      },
    );

    test('server completion still clears this device after restart', () async {
      final cleanup = _DeviceCleanup(AccountDeletionLocalWorkSummary.clear());
      final controller = _controller(
        gateway: _Gateway(
          statuses: [
            _status(
              phase: DeletionStatusPhase.complete,
              providerOutcome: ProviderCheckpointState.notApplicable,
            ),
          ],
        ),
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: cleanup,
        receiptStore: _ReceiptStore(seed: _receipt()),
      );

      await controller.initialize();

      expect(controller.state.phase, AccountDeletionJourneyPhase.complete);
      expect(cleanup.clearCalls, 1);
      expect(controller.state.localCleanup!.completeOnThisDevice, isTrue);
    });

    test('unresolved last-owner custody blocks submission', () async {
      final gateway = _Gateway(
        impact: CandidateAccountDeletionImpact(
          intentId: 'intent_1',
          policyVersion: 'policy_1',
          impactVersion: 'impact_1',
          expiresAt: _now.add(const Duration(minutes: 10)),
          custodyChoice: CustodyChoice.suspendToCustody,
          ownershipResolution:
              AccountDeletionOwnershipResolution.operationalResolutionRequired,
          isLastRecoverableOwner: true,
          associationId: 'jba',
          serverDeletionContinuesIndependently: true,
          sportingHistoryIsNotAccountData: true,
        ),
        statuses: [_status()],
      );
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(AccountDeletionLocalWorkSummary.clear()),
        receiptStore: _ReceiptStore(),
      );

      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await controller.submitDeletion();

      expect(controller.state.canSubmit, isFalse);
      expect(gateway.requestCalls, 0);
      expect(
        controller.state.errorCode,
        'AD_CUSTODY_OPERATIONAL_RESOLUTION_REQUIRED',
      );
    });

    test('non-synthetic dependencies cannot activate the candidate', () {
      expect(
        () => AccountDeletionCandidateController(
          providerProfile: _passwordProfile,
          gateway: _Gateway(statuses: [_status()], synthetic: false),
          reauthenticator: _Reauthenticator(_passwordVerified()),
          deviceCleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(),
          ),
          receiptStore: _ReceiptStore(),
        ),
        throwsStateError,
      );
      expect(accountDeletionCandidateActivationAllowed, isFalse);
    });
  });
}

final _now = DateTime.utc(2026, 9, 11, 16);
final _passwordProfile = AccountDeletionProviderProfile(
  methods: const [AccountDeletionReauthenticationMethod.password],
  appleRelationship: AppleAccountRelationship.notLinked,
);
final _statusSecret = base64Url
    .encode(Uint8List.fromList(List<int>.generate(32, (index) => index)))
    .replaceAll('=', '');

AccountDeletionCandidateController _controller({
  required _Gateway gateway,
  required _Reauthenticator reauthenticator,
  required _DeviceCleanup cleanup,
  required _ReceiptStore receiptStore,
  AccountDeletionProviderProfile? profile,
}) => AccountDeletionCandidateController(
  providerProfile: profile ?? _passwordProfile,
  gateway: gateway,
  reauthenticator: reauthenticator,
  deviceCleanup: cleanup,
  receiptStore: receiptStore,
  clock: _Clock(),
  operationFactory: const _OperationFactory(),
);

CandidateAccountDeletionImpact _impact() => CandidateAccountDeletionImpact(
  intentId: 'intent_1',
  policyVersion: 'policy_1',
  impactVersion: 'impact_1',
  expiresAt: _now.add(const Duration(minutes: 10)),
  custodyChoice: CustodyChoice.ordinary,
  ownershipResolution: AccountDeletionOwnershipResolution.ordinaryMember,
  isLastRecoverableOwner: false,
  associationId: 'jba',
  serverDeletionContinuesIndependently: true,
  sportingHistoryIsNotAccountData: true,
);

AccountDeletionStatusSnapshot _status({
  DeletionStatusPhase phase = DeletionStatusPhase.processing,
  ProviderCheckpointState providerOutcome = ProviderCheckpointState.pending,
}) => AccountDeletionStatusSnapshot(
  requestId: 'request_fixed',
  phase: phase,
  acceptedAt: _now,
  completedAt: phase == DeletionStatusPhase.complete
      ? _now.add(const Duration(minutes: 20))
      : null,
  nextPollAfter: phase == DeletionStatusPhase.complete
      ? null
      : const Duration(seconds: 15),
  providerOutcome: providerOutcome,
  messageCode: phase == DeletionStatusPhase.complete
      ? 'AD_ACCOUNT_DELETION_COMPLETE'
      : 'AD_DELETION_REQUESTED',
  retainedCategoryCodes: const [],
);

AccountDeletionReauthenticationResult _passwordVerified() =>
    AccountDeletionReauthenticationResult(
      method: AccountDeletionReauthenticationMethod.password,
      outcome: AccountDeletionReauthenticationOutcome.verified,
      appleRevocationMaterialState: AppleRevocationMaterialState.notApplicable,
    );

AccountDeletionLocalWorkSummary _resolvedLocalWork() =>
    AccountDeletionLocalWorkSummary(
      state: AccountDeletionLocalWorkState.readyWithDeviceConsent,
      workspaceCount: 1,
      unacceptedOperationCount: 2,
      receiptUnknownOperationCount: 0,
      acceptedOperationCount: 3,
      manifestId: 'manifest_1',
      manifestChecksum: List.filled(64, 'a').join(),
      deviceConsentId: 'consent_1',
    );

CandidateAccountDeletionReceipt _receipt() {
  final request = RequestDeletionContract(
    intentId: 'intent_1',
    policyVersion: 'policy_1',
    impactVersion: 'impact_1',
    operationId: 'operation_fixed',
    requestId: 'request_fixed',
    statusSecretHash: AccountDeletionContract.statusSecretHash(_statusSecret),
    custodyChoice: CustodyChoice.ordinary,
  );
  return CandidateAccountDeletionReceipt(
    request: request,
    statusSecret: _statusSecret,
    state: AccountDeletionReceiptState.acceptanceUnknown,
    recordedAt: _now,
  );
}

final class _Gateway implements CandidateAccountDeletionGateway {
  _Gateway({
    CandidateAccountDeletionImpact? impact,
    required List<Object> statuses,
    this.requestError,
    this.synthetic = true,
  }) : impact = impact ?? _impact(),
       statuses = [...statuses];

  final CandidateAccountDeletionImpact impact;
  final List<Object> statuses;
  Object? requestError;
  final bool synthetic;
  int prepareCalls = 0;
  int requestCalls = 0;
  int statusCalls = 0;
  RequestDeletionContract? lastRequest;

  @override
  bool get isSyntheticCandidate => synthetic;

  @override
  Future<CandidateAccountDeletionImpact> prepareDeletion() async {
    prepareCalls++;
    return impact;
  }

  @override
  Future<AcceptedAccountDeletionRequest> requestDeletion(
    RequestDeletionContract request,
  ) async {
    requestCalls++;
    lastRequest = request;
    if (requestError case final error?) throw error;
    return AcceptedAccountDeletionRequest(
      requestId: request.requestId,
      internalJobId: 'job_1',
      acceptedAt: _now,
      nextPollAfter: const Duration(seconds: 5),
      sameGenerationConvergence: false,
    );
  }

  @override
  Future<AccountDeletionStatusSnapshot> deletionStatus({
    required String requestId,
    required String statusSecret,
  }) async {
    statusCalls++;
    expect(requestId, 'request_fixed');
    expect(statusSecret, _statusSecret);
    final next = statuses.removeAt(0);
    if (next is AccountDeletionStatusSnapshot) return next;
    throw next;
  }
}

final class _Reauthenticator
    implements CandidateAccountDeletionReauthenticator {
  _Reauthenticator(this.result);

  final AccountDeletionReauthenticationResult result;
  int calls = 0;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionReauthenticationResult> reauthenticate({
    required AccountDeletionReauthenticationMethod method,
    String? password,
  }) async {
    calls++;
    return result;
  }
}

final class _DeviceCleanup implements CandidateAccountDeletionDeviceCleanup {
  _DeviceCleanup(this.initial, {AccountDeletionLocalWorkSummary? resolved})
    : resolved = resolved ?? initial;

  final AccountDeletionLocalWorkSummary initial;
  final AccountDeletionLocalWorkSummary resolved;
  int resolveCalls = 0;
  int clearCalls = 0;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionLocalWorkSummary> inspectLocalOfficialWork() async =>
      initial;

  @override
  Future<AccountDeletionLocalWorkSummary> resolveLocalOfficialWork(
    AccountDeletionLocalWorkAction action,
  ) async {
    resolveCalls++;
    return resolved;
  }

  @override
  Future<AccountDeletionLocalCleanupResult> clearAfterServerFence(
    AccountDeletionLocalWorkSummary localWork,
  ) async {
    clearCalls++;
    return AccountDeletionLocalCleanupResult(
      listenersStopped: true,
      notificationRegistrationDetached: true,
      ordinaryCachesCleared: true,
      localNotificationsCancelled: true,
      localOfficialWorkPreservedOrConsented: true,
    );
  }
}

final class _ReceiptStore implements CandidateAccountDeletionReceiptStore {
  _ReceiptStore({
    CandidateAccountDeletionReceipt? seed,
    this.failWriteAt,
    this.failClear = false,
  }) : receipt = seed;

  CandidateAccountDeletionReceipt? receipt;
  final int? failWriteAt;
  final bool failClear;
  final List<AccountDeletionReceiptState> writeStates = [];
  int writeAttempts = 0;
  int clearCalls = 0;

  @override
  Future<CandidateAccountDeletionReceipt?> read() async => receipt;

  @override
  Future<void> write(CandidateAccountDeletionReceipt receipt) async {
    writeAttempts++;
    if (writeAttempts == failWriteAt) {
      throw StateError('synthetic receipt write failure');
    }
    this.receipt = receipt;
    writeStates.add(receipt.state);
  }

  @override
  Future<void> clearProvenNotAccepted(
    CandidateAccountDeletionReceipt receipt,
  ) async {
    clearCalls++;
    if (failClear) throw StateError('synthetic receipt clear failure');
    this.receipt = null;
  }
}

final class _Clock implements AccountDeletionCandidateClock {
  @override
  DateTime nowUtc() => _now;
}

final class _OperationFactory implements CandidateDeletionOperationFactory {
  const _OperationFactory();

  @override
  CandidateDeletionOperationMaterial create() =>
      CandidateDeletionOperationMaterial(
        operationId: 'operation_fixed',
        requestId: 'request_fixed',
        statusSecret: _statusSecret,
      );
}
