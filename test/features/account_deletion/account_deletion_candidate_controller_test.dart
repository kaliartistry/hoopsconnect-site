import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_controller.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';
import 'package:hoops_connect/models/account_deletion/account_lifecycle_ad02_v2.dart';

void main() {
  group('candidate account deletion controller', () {
    test('persists status capability before one bound request', () async {
      final gateway = _Gateway(statuses: [_status()]);
      final reauth = _Reauthenticator(_passwordVerified());
      final cleanup = _DeviceCleanup(
        AccountDeletionLocalWorkSummary.clear(_deviceBinding),
      );
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
      expect(
        controller.state.routeHandoffPath,
        AccountLifecycleCandidateRoutePathsV2.deletionStatus,
      );
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
      expect(
        cleanup.lastCleanupRequest!.receipt.binding.matches(_deviceBinding),
        isTrue,
      );
      expect(
        cleanup.lastCleanupRequest!.localWork.binding.matches(_deviceBinding),
        isTrue,
      );
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
              operationBinding: _operationBinding,
              method: AccountDeletionReauthenticationMethod.google,
              outcome: AccountDeletionReauthenticationOutcome.cancelled,
              appleRevocationMaterialState:
                  AppleRevocationMaterialState.notApplicable,
            ),
          ),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
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

    test(
      'Google success prepares the impact without provider material',
      () async {
        final gateway = _Gateway(statuses: [_status()]);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(
            AccountDeletionReauthenticationResult(
              operationBinding: _operationBinding,
              method: AccountDeletionReauthenticationMethod.google,
              outcome: AccountDeletionReauthenticationOutcome.verified,
              appleRevocationMaterialState:
                  AppleRevocationMaterialState.notApplicable,
            ),
          ),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
          profile: AccountDeletionProviderProfile(
            methods: const [AccountDeletionReauthenticationMethod.google],
            appleRelationship: AppleAccountRelationship.notLinked,
          ),
        );

        await controller.initialize();
        await controller.continueToImpact();

        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.impactReview,
        );
        expect(gateway.prepareCalls, 1);
        expect(gateway.requestCalls, 0);
      },
    );

    test('Apple cancellation stays reachable and sends no request', () async {
      final gateway = _Gateway(statuses: [_status()]);
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(
          AccountDeletionReauthenticationResult(
            operationBinding: _operationBinding,
            method: AccountDeletionReauthenticationMethod.apple,
            outcome: AccountDeletionReauthenticationOutcome.cancelled,
            appleRevocationMaterialState: AppleRevocationMaterialState.unknown,
          ),
        ),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: _ReceiptStore(),
        profile: AccountDeletionProviderProfile(
          methods: const [AccountDeletionReauthenticationMethod.apple],
          appleRelationship: AppleAccountRelationship.unknown,
        ),
      );

      await controller.initialize();
      await controller.continueToImpact();

      expect(controller.state.phase, AccountDeletionJourneyPhase.overview);
      expect(controller.state.noticeCode, 'AD_PROVIDER_REAUTH_CANCELLED');
      expect(gateway.prepareCalls, 0);
      expect(gateway.requestCalls, 0);
    });

    for (final appleCase in [
      (
        state: AppleRevocationMaterialState.unavailable,
        notice: 'AD_APPLE_REVOCATION_MATERIAL_UNAVAILABLE',
      ),
      (
        state: AppleRevocationMaterialState.unknown,
        notice: 'AD_APPLE_REVOCATION_MATERIAL_UNKNOWN',
      ),
    ]) {
      test(
        'Apple ${appleCase.state.name} remains explicit and unverified',
        () async {
          final gateway = _Gateway(statuses: [_status()]);
          final controller = _controller(
            gateway: gateway,
            reauthenticator: _Reauthenticator(
              AccountDeletionReauthenticationResult(
                operationBinding: _operationBinding,
                method: AccountDeletionReauthenticationMethod.apple,
                outcome: AccountDeletionReauthenticationOutcome.verified,
                appleRevocationMaterialState: appleCase.state,
              ),
            ),
            cleanup: _DeviceCleanup(
              AccountDeletionLocalWorkSummary.clear(_deviceBinding),
            ),
            receiptStore: _ReceiptStore(),
            profile: AccountDeletionProviderProfile(
              methods: const [AccountDeletionReauthenticationMethod.apple],
              appleRelationship: AppleAccountRelationship.unknown,
            ),
          );

          await controller.initialize();
          await controller.continueToImpact();

          expect(
            controller.state.phase,
            AccountDeletionJourneyPhase.impactReview,
          );
          expect(controller.state.noticeCode, appleCase.notice);
          controller.setConsequencesConfirmed(true);
          controller.setConfirmationText('DELETE');
          await controller.submitDeletion();
          expect(gateway.lastRequest!.providerRevocationRef, isNull);
        },
      );
    }

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
            operationBinding: _operationBinding,
            method: AccountDeletionReauthenticationMethod.apple,
            outcome: AccountDeletionReauthenticationOutcome.verified,
            appleRevocationMaterialState: AppleRevocationMaterialState.staged,
            providerRevocationRef: 'apple_ref_1',
          ),
        ),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
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
          binding: _deviceBinding,
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
      expect(
        controller.state.routeHandoffPath,
        AccountLifecycleCandidateRoutePathsV2.reconcileDeviceWork,
      );
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
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: store,
        );

        await controller.initialize();

        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.accountRemovedCleanupPending,
        );
        expect(
          controller.state.routeHandoffPath,
          AccountLifecycleCandidateRoutePathsV2.deletionStatus,
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
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: _ReceiptStore(),
      );

      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await controller.submitDeletion();

      expect(
        controller.state.phase,
        AccountDeletionJourneyPhase.retrySameOperation,
      );
      expect(controller.state.errorCode, 'AD_TEMPORARILY_UNAVAILABLE');
      expect(gateway.requestCalls, 1);
      expect(gateway.statusCalls, 1);

      gateway
        ..requestError = null
        ..statuses.add(_status());
      await controller.retrySameOperation();

      expect(controller.state.phase, AccountDeletionJourneyPhase.processing);
      expect(
        gateway.requestCalls,
        2,
        reason: 'retry must reuse the exact persisted operation',
      );
      expect(gateway.statusCalls, 2);
      expect(gateway.lastRequest!.operationId, 'operation_fixed');
      expect(gateway.lastRequest!.requestId, 'request_fixed');
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
            cleanup: _DeviceCleanup(
              AccountDeletionLocalWorkSummary.clear(_deviceBinding),
            ),
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
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: store,
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(gateway.requestCalls, 1);
        expect(gateway.statusCalls, 1);
        expect(store.clearCalls, 0);
        expect(
          store.receipt!.state,
          AccountDeletionReceiptState.definitiveNotAccepted,
        );
        expect(store.receipt!.terminalErrorCode, 'AD_POLICY_NOT_READY');
        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.requestRejected,
        );
        expect(controller.state.errorCode, 'AD_POLICY_NOT_READY');
      },
    );

    test(
      'failed receipt clear stays conservative after proved rejection',
      () async {
        final gateway = _Gateway(
          requestError: const AccountDeletionCandidateFailure(
            'AD_INTENT_EXPIRED',
          ),
          statuses: [
            const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
          ],
        );
        final store = _ReceiptStore(failClear: true);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
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

    test(
      'failed terminal rejection write retains the same unknown receipt',
      () async {
        final gateway = _Gateway(
          requestError: const AccountDeletionCandidateFailure(
            'AD_POLICY_NOT_READY',
          ),
          statuses: [
            const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
          ],
        );
        final store = _ReceiptStore(failWriteAt: 3);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: store,
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
        expect(controller.state.errorCode, 'AD_RECEIPT_STORAGE_UNAVAILABLE');
        expect(
          store.receipt!.state,
          AccountDeletionReceiptState.acceptanceUnknown,
        );
        expect(store.receipt!.request.operationId, 'operation_fixed');
        expect(gateway.requestCalls, 1);
      },
    );

    test('server completion still clears this device after restart', () async {
      final cleanup = _DeviceCleanup(
        AccountDeletionLocalWorkSummary.clear(_deviceBinding),
      );
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

    test(
      'unresolved last-owner custody accepts and enters attention',
      () async {
        final gateway = _Gateway(
          impact: CandidateAccountDeletionImpact(
            operationBinding: _operationBinding,
            intentId: 'intent_1',
            policyVersion: 'policy_1',
            impactVersion: 'impact_1',
            expiresAt: _now.add(const Duration(minutes: 10)),
            custodyChoice: CustodyChoice.suspendToCustody,
            ownershipResolution: AccountDeletionOwnershipResolution
                .operationalResolutionRequired,
            isLastRecoverableOwner: true,
            associationId: 'jba',
            serverDeletionContinuesIndependently: true,
            sportingHistoryIsNotAccountData: true,
          ),
          statuses: [
            _status(),
            _status(phase: DeletionStatusPhase.accountRemovedCleanupPending),
            _status(phase: DeletionStatusPhase.attentionRequired),
          ],
        );
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(controller.state.canSubmit, isFalse);
        expect(gateway.requestCalls, 1);
        expect(controller.state.phase, AccountDeletionJourneyPhase.processing);
        expect(controller.state.status!.messageCode, 'AD_DELETION_REQUESTED');
        await controller.refreshStatus();
        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.accountRemovedCleanupPending,
        );
        await controller.refreshStatus();
        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.attentionRequired,
        );
        expect(
          controller.state.status!.messageCode,
          'AD_CLEANUP_ATTENTION_REQUIRED',
        );
        expect(controller.state.receipt!.custodyAttentionObserved, isTrue);
        expect(
          gateway.lastRequest!.custodyChoice,
          CustodyChoice.suspendToCustody,
        );
      },
    );

    test(
      'unresolved custody rejects impossible completion without attention',
      () async {
        final gateway = _Gateway(
          impact: CandidateAccountDeletionImpact(
            operationBinding: _operationBinding,
            intentId: 'intent_1',
            policyVersion: 'policy_1',
            impactVersion: 'impact_1',
            expiresAt: _now.add(const Duration(minutes: 10)),
            custodyChoice: CustodyChoice.suspendToCustody,
            ownershipResolution: AccountDeletionOwnershipResolution
                .operationalResolutionRequired,
            isLastRecoverableOwner: true,
            associationId: 'jba',
            serverDeletionContinuesIndependently: true,
            sportingHistoryIsNotAccountData: true,
          ),
          statuses: [
            _status(
              phase: DeletionStatusPhase.complete,
              providerOutcome: ProviderCheckpointState.notApplicable,
            ),
          ],
        );
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.attentionRequired,
        );
        expect(controller.state.errorCode, 'AD_CUSTODY_STATUS_MISMATCH');
        expect(controller.state.receipt, isNotNull);
        expect(controller.state.receipt!.custodyAttentionObserved, isFalse);
      },
    );

    for (final code in [
      'AD_IDENTITY_MISMATCH',
      'AD_INVALID_REQUEST',
      'AD_OPERATION_CONFLICT',
      'AD_TRANSFER_NOT_READY',
      'AD_POLICY_NOT_READY',
    ]) {
      test('$code cannot create a replacement operation', () async {
        final gateway = _Gateway(
          requestError: AccountDeletionCandidateFailure(code),
          statuses: [
            const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
          ],
        );
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();
        await controller.submitDeletion();
        await controller.retrySameOperation();

        expect(
          controller.state.phase,
          AccountDeletionJourneyPhase.requestRejected,
        );
        expect(
          controller.state.receipt!.state,
          AccountDeletionReceiptState.definitiveNotAccepted,
        );
        expect(controller.state.receipt!.terminalErrorCode, code);
        expect(gateway.requestCalls, 1);
      });
    }

    test('terminal rejection survives restart without new IDs', () async {
      final store = _ReceiptStore();
      final firstGateway = _Gateway(
        requestError: const AccountDeletionCandidateFailure(
          'AD_TRANSFER_NOT_READY',
        ),
        statuses: [
          const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE'),
        ],
      );
      final first = _controller(
        gateway: firstGateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: store,
      );
      await first.initialize();
      await first.continueToImpact(password: 'correct horse');
      first.setConsequencesConfirmed(true);
      first.setConfirmationText('DELETE');
      await first.submitDeletion();
      first.dispose();

      final restartedGateway = _Gateway(statuses: [_status()]);
      final restarted = _controller(
        gateway: restartedGateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: store,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      await restarted.submitDeletion();
      await restarted.retrySameOperation();

      expect(
        restarted.state.phase,
        AccountDeletionJourneyPhase.requestRejected,
      );
      expect(
        restarted.state.routeHandoffPath,
        AccountLifecycleCandidateRoutePathsV2.requestDeletion,
      );
      expect(restartedGateway.requestCalls, 0);
      expect(restartedGateway.statusCalls, 0);
      expect(store.receipt!.request.operationId, 'operation_fixed');
    });

    test('two concurrent submit actions issue one request', () async {
      final gateway = _Gateway(statuses: [_status()]);
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: _ReceiptStore(),
      );

      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');
      await Future.wait([
        controller.submitDeletion(),
        controller.submitDeletion(),
      ]);

      expect(gateway.requestCalls, 1);
      expect(gateway.lastRequest!.operationId, 'operation_fixed');
    });

    test(
      'device cleanup failure stays visible and a status retry recovers',
      () async {
        final cleanup = _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          failClearAttempts: 2,
        );
        final controller = _controller(
          gateway: _Gateway(statuses: [_status(), _status()]),
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: cleanup,
          receiptStore: _ReceiptStore(),
        );

        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');
        await controller.submitDeletion();

        expect(cleanup.clearCalls, 2);
        expect(controller.state.localCleanup!.completeOnThisDevice, isFalse);
        expect(controller.state.errorCode, 'AD_DEVICE_CLEANUP_INCOMPLETE');

        await controller.refreshStatus();
        expect(cleanup.clearCalls, 3);
        expect(controller.state.localCleanup!.completeOnThisDevice, isTrue);
        expect(controller.state.errorCode, isNull);
      },
    );

    for (final mismatch in [
      AccountDeletionDeviceBinding(
        authProjectIdV2: 'demo-hoopsconnect',
        authTenantIdV2: null,
        accountId: 'other_account',
        accountGeneration: _generationA,
        accountLifecycleEpochV2: 7,
        deviceSessionId: 'device_session_1',
      ),
      AccountDeletionDeviceBinding(
        authProjectIdV2: 'demo-hoopsconnect',
        authTenantIdV2: null,
        accountId: 'account_1',
        accountGeneration: _generationB,
        accountLifecycleEpochV2: 7,
        deviceSessionId: 'device_session_1',
      ),
      AccountDeletionDeviceBinding(
        authProjectIdV2: 'demo-hoopsconnect',
        authTenantIdV2: null,
        accountId: 'account_1',
        accountGeneration: _generationA,
        accountLifecycleEpochV2: 7,
        deviceSessionId: 'other_device',
      ),
    ]) {
      test(
        'mismatched receipt cannot read status or clear current data',
        () async {
          final cleanup = _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          );
          final gateway = _Gateway(statuses: [_status()]);
          final controller = _controller(
            gateway: gateway,
            reauthenticator: _Reauthenticator(_passwordVerified()),
            cleanup: cleanup,
            receiptStore: _ReceiptStore(seed: _receipt(binding: mismatch)),
          );

          await controller.initialize();

          expect(
            controller.state.phase,
            AccountDeletionJourneyPhase.unavailable,
          );
          expect(
            controller.state.errorCode,
            'AD_RECEIPT_DEVICE_BINDING_MISMATCH',
          );
          expect(gateway.statusCalls, 0);
          expect(cleanup.clearCalls, 0);
        },
      );
    }

    test('cleanup envelope rejects a cross-device local manifest', () {
      final otherDevice = AccountDeletionDeviceBinding(
        authProjectIdV2: 'demo-hoopsconnect',
        authTenantIdV2: null,
        accountId: 'account_1',
        accountGeneration: _generationA,
        accountLifecycleEpochV2: 7,
        deviceSessionId: 'other_device',
      );
      expect(
        () => AccountDeletionLocalCleanupRequest(
          currentBinding: _deviceBinding,
          receipt: _receipt(state: AccountDeletionReceiptState.accepted),
          localWork: AccountDeletionLocalWorkSummary.clear(otherDevice),
        ),
        throwsFormatException,
      );
    });

    test(
      'receipt store cannot clear the same IDs under another binding',
      () async {
        final store = InMemoryCandidateAccountDeletionReceiptStore();
        final receipt = _receipt();
        await store.write(receipt);
        final otherBinding = AccountDeletionDeviceBinding(
          authProjectIdV2: 'demo-hoopsconnect',
          authTenantIdV2: null,
          accountId: 'account_1',
          accountGeneration: _generationA,
          accountLifecycleEpochV2: 7,
          deviceSessionId: 'other_device',
        );

        await expectLater(
          store.clearProvenNotAccepted(_receipt(binding: otherBinding)),
          throwsStateError,
        );
        expect(await store.read(), same(receipt));
      },
    );

    test(
      'account switch during reauthentication aborts before prepare',
      () async {
        final reauthCompleter =
            Completer<AccountDeletionReauthenticationResult>();
        final reauth = _Reauthenticator(
          _passwordVerified(),
          completer: reauthCompleter,
        );
        final gateway = _Gateway(statuses: [_status()]);
        final guard = _SessionGuard(_operationBinding);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: reauth,
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
          sessionGuard: guard,
        );
        await controller.initialize();

        final continuing = controller.continueToImpact(
          password: 'correct horse',
        );
        await _waitUntil(() => reauth.calls == 1);
        guard.currentOperationBinding = _otherOperationBinding;
        reauthCompleter.complete(_passwordVerified());
        await continuing;

        expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
        expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
        expect(gateway.prepareCalls, 0);
        expect(gateway.requestCalls, 0);
      },
    );

    test(
      'reauthentication result with mixed identity binding is rejected',
      () async {
        final gateway = _Gateway(statuses: [_status()]);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(
            _passwordVerified(operationBinding: _otherOperationBinding),
          ),
          cleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          ),
          receiptStore: _ReceiptStore(),
        );
        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');

        expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
        expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
        expect(gateway.prepareCalls, 0);
        expect(gateway.requestCalls, 0);
      },
    );

    test('account switch during prepare aborts before submission', () async {
      final prepareCompleter = Completer<CandidateAccountDeletionImpact>();
      final gateway = _Gateway(
        statuses: [_status()],
        prepareCompleter: prepareCompleter,
      );
      final guard = _SessionGuard(_operationBinding);
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: _ReceiptStore(),
        sessionGuard: guard,
      );
      await controller.initialize();

      final continuing = controller.continueToImpact(password: 'correct horse');
      await _waitUntil(() => gateway.prepareCalls == 1);
      guard.currentOperationBinding = _otherOperationBinding;
      prepareCompleter.complete(_impact());
      await continuing;

      expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
      expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
      expect(gateway.requestCalls, 0);
    });

    test('prepared impact with mixed identity binding is rejected', () async {
      final gateway = _Gateway(
        statuses: [_status()],
        impact: _impact(operationBinding: _otherOperationBinding),
      );
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        ),
        receiptStore: _ReceiptStore(),
      );
      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');

      expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
      expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
      expect(gateway.prepareCalls, 1);
      expect(gateway.requestCalls, 0);
    });

    test(
      'account switch while submit is in flight preserves unknown receipt and never cleans',
      () async {
        final requestCompleter = Completer<AcceptedAccountDeletionRequest>();
        final gateway = _Gateway(
          statuses: [_status()],
          requestCompleter: requestCompleter,
        );
        final cleanup = _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
        );
        final store = _ReceiptStore();
        final guard = _SessionGuard(_operationBinding);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: cleanup,
          receiptStore: store,
          sessionGuard: guard,
        );
        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');

        final submitting = controller.submitDeletion();
        await _waitUntil(() => gateway.requestCalls == 1);
        guard.currentOperationBinding = _otherOperationBinding;
        requestCompleter.complete(_accepted());
        await submitting;

        expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
        expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
        expect(
          store.receipt!.state,
          AccountDeletionReceiptState.acceptanceUnknown,
        );
        expect(cleanup.clearCalls, 0);
        expect(gateway.statusCalls, 0);
      },
    );

    test('submit response with mixed identity binding never cleans', () async {
      final requestCompleter = Completer<AcceptedAccountDeletionRequest>();
      final gateway = _Gateway(
        statuses: [_status()],
        requestCompleter: requestCompleter,
      );
      final cleanup = _DeviceCleanup(
        AccountDeletionLocalWorkSummary.clear(_deviceBinding),
      );
      final store = _ReceiptStore();
      final controller = _controller(
        gateway: gateway,
        reauthenticator: _Reauthenticator(_passwordVerified()),
        cleanup: cleanup,
        receiptStore: store,
      );
      await controller.initialize();
      await controller.continueToImpact(password: 'correct horse');
      controller.setConsequencesConfirmed(true);
      controller.setConfirmationText('DELETE');

      final submitting = controller.submitDeletion();
      await _waitUntil(() => gateway.requestCalls == 1);
      requestCompleter.complete(
        _accepted(operationBinding: _otherOperationBinding),
      );
      await submitting;

      expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
      expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
      expect(
        store.receipt!.state,
        AccountDeletionReceiptState.acceptanceUnknown,
      );
      expect(cleanup.clearCalls, 0);
      expect(gateway.statusCalls, 0);
    });

    test(
      'account switch during local cleanup cannot continue into status',
      () async {
        final clearCompleter = Completer<AccountDeletionLocalCleanupResult>();
        final cleanup = _DeviceCleanup(
          AccountDeletionLocalWorkSummary.clear(_deviceBinding),
          clearCompleter: clearCompleter,
        );
        final gateway = _Gateway(statuses: [_status()]);
        final guard = _SessionGuard(_operationBinding);
        final controller = _controller(
          gateway: gateway,
          reauthenticator: _Reauthenticator(_passwordVerified()),
          cleanup: cleanup,
          receiptStore: _ReceiptStore(),
          sessionGuard: guard,
        );
        await controller.initialize();
        await controller.continueToImpact(password: 'correct horse');
        controller.setConsequencesConfirmed(true);
        controller.setConfirmationText('DELETE');

        final submitting = controller.submitDeletion();
        await _waitUntil(() => cleanup.clearCalls == 1);
        guard.currentOperationBinding = _otherOperationBinding;
        clearCompleter.complete(_cleanupComplete());
        await submitting;

        expect(controller.state.phase, AccountDeletionJourneyPhase.unavailable);
        expect(controller.state.errorCode, 'AD_ACCOUNT_SESSION_CHANGED');
        expect(gateway.requestCalls, 1);
        expect(gateway.statusCalls, 0);
        expect(
          cleanup.lastCleanupRequest!.currentBinding.matches(_deviceBinding),
          isTrue,
        );
      },
    );

    test('non-synthetic dependencies cannot activate the candidate', () {
      expect(
        () => AccountDeletionCandidateController(
          providerProfile: _passwordProfile,
          operationBinding: _operationBinding,
          sessionGuard: _SessionGuard(_operationBinding),
          gateway: _Gateway(statuses: [_status()], synthetic: false),
          reauthenticator: _Reauthenticator(_passwordVerified()),
          deviceCleanup: _DeviceCleanup(
            AccountDeletionLocalWorkSummary.clear(_deviceBinding),
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
final _generationA = List.filled(64, 'a').join();
final _generationB = List.filled(64, 'b').join();
final _deviceBinding = AccountDeletionDeviceBinding(
  authProjectIdV2: 'demo-hoopsconnect',
  authTenantIdV2: null,
  accountId: 'account_1',
  accountGeneration: _generationA,
  accountLifecycleEpochV2: 7,
  deviceSessionId: 'device_session_1',
);
final _sessionNonce = Object();
final _operationBinding = AccountDeletionOperationBinding(
  deviceBinding: _deviceBinding,
  sessionAttemptIdV2: 'deletion_session_1',
  sessionAttemptEpochV2: 1,
  sessionAttemptNonceV2: _sessionNonce,
);
final _otherDeviceBinding = AccountDeletionDeviceBinding(
  authProjectIdV2: 'other-project',
  authTenantIdV2: 'tenant_b',
  accountId: 'account_2',
  accountGeneration: _generationB,
  accountLifecycleEpochV2: 8,
  deviceSessionId: 'device_session_2',
);
final _otherOperationBinding = AccountDeletionOperationBinding(
  deviceBinding: _otherDeviceBinding,
  sessionAttemptIdV2: 'deletion_session_2',
  sessionAttemptEpochV2: 2,
  sessionAttemptNonceV2: Object(),
);
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
  _SessionGuard? sessionGuard,
  AccountDeletionOperationBinding? operationBinding,
}) => AccountDeletionCandidateController(
  providerProfile: profile ?? _passwordProfile,
  operationBinding: operationBinding ?? _operationBinding,
  sessionGuard:
      sessionGuard ?? _SessionGuard(operationBinding ?? _operationBinding),
  gateway: gateway,
  reauthenticator: reauthenticator,
  deviceCleanup: cleanup,
  receiptStore: receiptStore,
  clock: _Clock(),
  operationFactory: const _OperationFactory(),
);

CandidateAccountDeletionImpact _impact({
  AccountDeletionOperationBinding? operationBinding,
}) => CandidateAccountDeletionImpact(
  operationBinding: operationBinding ?? _operationBinding,
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
  String? messageCode,
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
  messageCode:
      messageCode ??
      switch (phase) {
        DeletionStatusPhase.processing => 'AD_DELETION_REQUESTED',
        DeletionStatusPhase.accountRemovedCleanupPending =>
          'AD_ACCOUNT_REMOVED_CLEANUP_PENDING',
        DeletionStatusPhase.attentionRequired =>
          'AD_CLEANUP_ATTENTION_REQUIRED',
        DeletionStatusPhase.complete => 'AD_ACCOUNT_DELETION_COMPLETE',
      },
  retainedCategoryCodes: const [],
);

AccountDeletionReauthenticationResult _passwordVerified({
  AccountDeletionOperationBinding? operationBinding,
}) => AccountDeletionReauthenticationResult(
  operationBinding: operationBinding ?? _operationBinding,
  method: AccountDeletionReauthenticationMethod.password,
  outcome: AccountDeletionReauthenticationOutcome.verified,
  appleRevocationMaterialState: AppleRevocationMaterialState.notApplicable,
);

AcceptedAccountDeletionRequest _accepted({
  AccountDeletionOperationBinding? operationBinding,
}) => AcceptedAccountDeletionRequest(
  operationBinding: operationBinding ?? _operationBinding,
  requestId: 'request_fixed',
  internalJobId: 'job_1',
  acceptedAt: _now,
  nextPollAfter: const Duration(seconds: 5),
  sameGenerationConvergence: false,
);

AccountDeletionLocalCleanupResult _cleanupComplete() =>
    AccountDeletionLocalCleanupResult(
      listenersStopped: true,
      notificationRegistrationDetached: true,
      ordinaryCachesCleared: true,
      localNotificationsCancelled: true,
      localOfficialWorkPreservedOrConsented: true,
    );

Future<void> _waitUntil(bool Function() predicate) async {
  for (var index = 0; index < 50 && !predicate(); index++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue, reason: 'async test boundary was not reached');
}

AccountDeletionLocalWorkSummary _resolvedLocalWork() =>
    AccountDeletionLocalWorkSummary(
      binding: _deviceBinding,
      state: AccountDeletionLocalWorkState.readyWithDeviceConsent,
      workspaceCount: 1,
      unacceptedOperationCount: 2,
      receiptUnknownOperationCount: 0,
      acceptedOperationCount: 3,
      manifestId: 'manifest_1',
      manifestChecksum: List.filled(64, 'a').join(),
      deviceConsentId: 'consent_1',
    );

CandidateAccountDeletionReceipt _receipt({
  AccountDeletionDeviceBinding? binding,
  AccountDeletionReceiptState state =
      AccountDeletionReceiptState.acceptanceUnknown,
}) {
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
    binding: binding ?? _deviceBinding,
    request: request,
    statusSecret: _statusSecret,
    state: state,
    recordedAt: _now,
    requiresCustodyAttention: false,
  );
}

final class _SessionGuard implements CandidateAccountDeletionSessionGuard {
  _SessionGuard(this.currentOperationBinding);

  @override
  bool get isSyntheticCandidate => true;

  @override
  AccountDeletionOperationBinding? currentOperationBinding;
}

final class _Gateway implements CandidateAccountDeletionGateway {
  _Gateway({
    CandidateAccountDeletionImpact? impact,
    required List<Object> statuses,
    this.requestError,
    this.prepareCompleter,
    this.requestCompleter,
    this.synthetic = true,
  }) : impact = impact ?? _impact(),
       statuses = [...statuses];

  final CandidateAccountDeletionImpact impact;
  final List<Object> statuses;
  Object? requestError;
  final Completer<CandidateAccountDeletionImpact>? prepareCompleter;
  final Completer<AcceptedAccountDeletionRequest>? requestCompleter;
  final bool synthetic;
  int prepareCalls = 0;
  int requestCalls = 0;
  int statusCalls = 0;
  RequestDeletionContract? lastRequest;

  @override
  bool get isSyntheticCandidate => synthetic;

  @override
  Future<CandidateAccountDeletionImpact> prepareDeletion(
    AccountDeletionOperationBinding operationBinding,
  ) async {
    expect(operationBinding.matches(_operationBinding), isTrue);
    prepareCalls++;
    return prepareCompleter == null ? impact : await prepareCompleter!.future;
  }

  @override
  Future<AcceptedAccountDeletionRequest> requestDeletion(
    RequestDeletionContract request,
    AccountDeletionOperationBinding operationBinding,
  ) async {
    expect(operationBinding.matches(_operationBinding), isTrue);
    requestCalls++;
    lastRequest = request;
    if (requestError case final error?) throw error;
    return requestCompleter == null
        ? _accepted(operationBinding: operationBinding)
        : await requestCompleter!.future;
  }

  @override
  Future<AccountDeletionStatusSnapshot> deletionStatus({
    required String requestId,
    required String statusSecret,
    required AccountDeletionOperationBinding operationBinding,
  }) async {
    expect(operationBinding.matches(_operationBinding), isTrue);
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
  _Reauthenticator(this.result, {this.completer});

  final AccountDeletionReauthenticationResult result;
  final Completer<AccountDeletionReauthenticationResult>? completer;
  int calls = 0;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionReauthenticationResult> reauthenticate({
    required AccountDeletionOperationBinding operationBinding,
    required AccountDeletionReauthenticationMethod method,
    String? password,
  }) async {
    expect(operationBinding.matches(_operationBinding), isTrue);
    calls++;
    return completer == null ? result : await completer!.future;
  }
}

final class _DeviceCleanup implements CandidateAccountDeletionDeviceCleanup {
  _DeviceCleanup(
    this.initial, {
    AccountDeletionLocalWorkSummary? resolved,
    this.failClearAttempts = 0,
    this.clearCompleter,
  }) : resolved = resolved ?? initial;

  final AccountDeletionLocalWorkSummary initial;
  final AccountDeletionLocalWorkSummary resolved;
  final int failClearAttempts;
  final Completer<AccountDeletionLocalCleanupResult>? clearCompleter;
  int resolveCalls = 0;
  int clearCalls = 0;
  AccountDeletionLocalCleanupRequest? lastCleanupRequest;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionLocalWorkSummary> inspectLocalOfficialWork(
    AccountDeletionDeviceBinding binding,
  ) async => initial;

  @override
  Future<AccountDeletionLocalWorkSummary> resolveLocalOfficialWork(
    AccountDeletionLocalWorkAction action,
    AccountDeletionDeviceBinding binding,
  ) async {
    resolveCalls++;
    return resolved;
  }

  @override
  Future<AccountDeletionLocalCleanupResult> clearAfterServerFence(
    AccountDeletionLocalCleanupRequest request,
  ) async {
    clearCalls++;
    lastCleanupRequest = request;
    if (clearCalls <= failClearAttempts) {
      throw const AccountDeletionCandidateFailure(
        'AD_DEVICE_CLEANUP_INCOMPLETE',
      );
    }
    return clearCompleter == null
        ? _cleanupComplete()
        : await clearCompleter!.future;
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
