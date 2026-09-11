import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_wire.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

void main() {
  Map<String, Object?> impact() => {
    'schemaVersion': 1,
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
    final parsed = AccountDeletionCandidateWire.parseImpact(impact());

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
        () => AccountDeletionCandidateWire.parseImpact(changed),
        throwsFormatException,
      );
    }
  });

  test('accepted response binds one request and a positive poll interval', () {
    final parsed = AccountDeletionCandidateWire.parseAccepted(accepted());

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
        () => AccountDeletionCandidateWire.parseAccepted(changed),
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

  test('complete status requires completion evidence and no next poll', () {
    final complete = AccountDeletionCandidateWire.parseStatus(
      {
        ...status(),
        'phase': 'complete',
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
        'completedAt': '2026-09-11T16:20:00.000Z',
      }..remove('nextPollAfterSeconds'),
      {...status(), 'adapterResults': <Object?>[]},
    ]) {
      expect(
        () => AccountDeletionCandidateWire.parseStatus(changed),
        throwsFormatException,
      );
    }
  });
}
