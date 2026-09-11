import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_wire.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

void main() {
  final generation = List.filled(64, 'a').join();
  final deviceBinding = AccountDeletionDeviceBinding(
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant_a',
    accountId: 'account_1',
    accountGeneration: generation,
    accountLifecycleEpochV2: 7,
    deviceSessionId: 'device_session_1',
  );
  final operationBinding = AccountDeletionOperationBinding(
    deviceBinding: deviceBinding,
    sessionAttemptIdV2: 'deletion_session_1',
    sessionAttemptEpochV2: 3,
    sessionAttemptNonceV2: Object(),
  );

  Map<String, Object?> impact() => {
    'schemaVersion': 1,
    'authProjectIdV2': 'demo-hoopsconnect',
    'authTenantIdV2': 'tenant_a',
    'authUidV2': 'account_1',
    'generationHash': generation,
    'expectedLifecycleEpochV2': 7,
    'sessionAttemptIdV2': 'deletion_session_1',
    'sessionAttemptEpochV2': 3,
    'intentId': 'intent_1',
    'policyVersion': 'policy_1',
    'impactVersion': 'impact_1',
    'expiresAt': '2026-09-11T16:10:00.000Z',
    'custodyChoice': 'ordinary',
    'ownershipResolution': 'ordinaryMember',
    'isLastRecoverableOwner': false,
    'associationId': 'jba',
    'serverDeletionContinuesIndependently': true,
    'sportingHistoryIsNotAccountData': true,
  };

  Map<String, Object?> accepted() => {
    'requestId': 'request_1',
    'internalJobId': 'job_1',
    'acceptedAt': '2026-09-11T16:00:00.000Z',
    'state': 'deleting',
    'completionTargetText':
        'Account removal is processing; cleanup completion is separately verified.',
    'nextPollAfterSeconds': 5,
    'bindingKind': 'winningOperation',
  };

  Map<String, Object?> status() => {
    'requestId': 'request_1',
    'phase': 'accountRemovedCleanupPending',
    'acceptedAt': '2026-09-11T16:00:00.000Z',
    'nextPollAfterSeconds': 15,
    'retainedCategoryCodes': <Object?>[],
    'providerOutcome': 'pending',
    'messageCode': 'AD_ACCOUNT_REMOVED_CLEANUP_PENDING',
  };

  test('impact preserves custody and sporting-history boundaries', () {
    final parsed = AccountDeletionCandidateWire.parseImpact(
      impact(),
      operationBinding,
    );

    expect(parsed.operationBinding, same(operationBinding));
    expect(parsed.custodyChoice, CustodyChoice.ordinary);
    expect(
      parsed.ownershipResolution,
      AccountDeletionOwnershipResolution.ordinaryMember,
    );
    expect(parsed.isLastRecoverableOwner, isFalse);
    expect(parsed.serverDeletionContinuesIndependently, isTrue);
    expect(parsed.sportingHistoryIsNotAccountData, isTrue);
  });

  test('impact rejects inconsistent custody and weakened boundaries', () {
    for (final changed in [
      {...impact(), 'isLastRecoverableOwner': true},
      {...impact(), 'sportingHistoryIsNotAccountData': false},
      {...impact(), 'serverDeletionContinuesIndependently': false},
      {...impact(), 'extra': true},
    ]) {
      expect(
        () =>
            AccountDeletionCandidateWire.parseImpact(changed, operationBinding),
        throwsFormatException,
      );
    }
  });

  test('impact wire adapter rejects every mixed account-session field', () {
    for (final changed in [
      {...impact(), 'authProjectIdV2': 'other-project'},
      {...impact(), 'authTenantIdV2': 'tenant_b'},
      {...impact(), 'authUidV2': 'account_2'},
      {...impact(), 'generationHash': List.filled(64, 'b').join()},
      {...impact(), 'expectedLifecycleEpochV2': 8},
      {...impact(), 'sessionAttemptIdV2': 'deletion_session_2'},
      {...impact(), 'sessionAttemptEpochV2': 4},
    ]) {
      expect(
        () =>
            AccountDeletionCandidateWire.parseImpact(changed, operationBinding),
        throwsFormatException,
      );
    }
  });

  test('accepted response binds one request and a positive poll interval', () {
    final parsed = AccountDeletionCandidateWire.parseAccepted(
      accepted(),
      operationBinding,
    );

    expect(parsed.operationBinding, same(operationBinding));
    expect(parsed.requestId, 'request_1');
    expect(parsed.internalJobId, 'job_1');
    expect(parsed.nextPollAfter, const Duration(seconds: 5));
    expect(parsed.sameGenerationConvergence, isFalse);
  });

  test('accepted response rejects false completion and changed shape', () {
    for (final changed in [
      {...accepted(), 'state': 'complete'},
      {...accepted(), 'nextPollAfterSeconds': 0},
      {...accepted(), 'bindingKind': 'replacement'},
      {...accepted(), 'targetUid': 'someone_else'},
    ]) {
      expect(
        () => AccountDeletionCandidateWire.parseAccepted(
          changed,
          operationBinding,
        ),
        throwsFormatException,
      );
    }
  });

  test('status keeps Auth removal separate from cleanup completion', () {
    final parsed = AccountDeletionCandidateWire.parseStatus(status());

    expect(parsed.phase, DeletionStatusPhase.accountRemovedCleanupPending);
    expect(parsed.completedAt, isNull);
    expect(parsed.nextPollAfter, const Duration(seconds: 15));
    expect(parsed.providerOutcome, ProviderCheckpointState.pending);
  });

  test('status accepts only the exact observable AD04 progression', () {
    for (final entry in <(String, String)>[
      ('processing', 'AD_DELETION_REQUESTED'),
      ('accountRemovedCleanupPending', 'AD_ACCOUNT_REMOVED_CLEANUP_PENDING'),
      ('attentionRequired', 'AD_CLEANUP_ATTENTION_REQUIRED'),
    ]) {
      final parsed = AccountDeletionCandidateWire.parseStatus({
        ...status(),
        'phase': entry.$1,
        'messageCode': entry.$2,
      });
      expect(parsed.messageCode, entry.$2);
    }
  });

  test('complete status requires completion evidence and no next poll', () {
    final complete = AccountDeletionCandidateWire.parseStatus(
      {
        ...status(),
        'phase': 'complete',
        'messageCode': 'AD_ACCOUNT_DELETION_COMPLETE',
        'completedAt': '2026-09-11T16:20:00.000Z',
        'providerOutcome': 'manual_action_guidance',
      }..remove('nextPollAfterSeconds'),
    );

    expect(complete.phase, DeletionStatusPhase.complete);
    expect(complete.completedAt, isNotNull);
    expect(
      complete.providerOutcome,
      ProviderCheckpointState.manualActionGuidance,
    );
  });

  test('status rejects duplicate codes, false terminality and extras', () {
    for (final changed in [
      {
        ...status(),
        'retainedCategoryCodes': ['official', 'official'],
      },
      {...status(), 'completedAt': '2026-09-11T16:20:00.000Z'},
      {...status(), 'providerOutcome': 'probably_revoked'},
      {
        ...status(),
        'phase': 'complete',
        'messageCode': 'AD_ACCOUNT_DELETION_COMPLETE',
        'completedAt': '2026-09-11T16:20:00.000Z',
      }..remove('nextPollAfterSeconds'),
      {...status(), 'messageCode': 'CUSTODY_CONFLICT'},
      {
        ...status(),
        'phase': 'attentionRequired',
        'messageCode': 'AD_ACCOUNT_REMOVED_CLEANUP_PENDING',
      },
      {...status(), 'adapterResults': <Object?>[]},
    ]) {
      expect(
        () => AccountDeletionCandidateWire.parseStatus(changed),
        throwsFormatException,
      );
    }
  });
}
