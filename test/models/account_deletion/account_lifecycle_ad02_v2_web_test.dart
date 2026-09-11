import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/account_deletion/account_lifecycle_ad02_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';

void main() {
  test(
    'AD02 candidate directory wire contract is browser-safe and minimized',
    () {
      final directory = ActiveMemberDirectoryV2.fromMap({
        'accountDirectorySchemaVersionV2': 2,
        'users': [
          {
            'accountDirectorySchemaVersionV2': 2,
            'uid': 'browser_user',
            'displayName': 'Browser User',
            'teamId': null,
            'divisionId': 'division_a',
          },
        ],
        'truncated': false,
      });
      expect(directory.users.single.uid, 'browser_user');
      expect(directory.toMap()['users'], [
        {
          'accountDirectorySchemaVersionV2': 2,
          'uid': 'browser_user',
          'displayName': 'Browser User',
          'teamId': null,
          'divisionId': 'division_a',
        },
      ]);
    },
  );

  test('AD02 candidate browser routing remains dormant and fail closed', () {
    expect(accountLifecycleAd02ActivationAllowedV2, isFalse);
    expect(
      candidateRouteForAccountLifecycleV2(
        state: AuthIncarnationSessionStateV2.refreshRequired,
        requestedLocation: '/board',
      ),
      '/loading',
    );
    expect(
      candidateRouteForAccountLifecycleV2(
        state: AuthIncarnationSessionStateV2.deleted,
        requestedLocation: '/board',
        statusReceiptState: AccountLifecycleStatusReceiptStateV2.exactAccepted,
      ),
      AccountLifecycleCandidateRoutePathsV2.deletionStatus,
    );
  });

  test('AD02 split lifecycle route matrix avoids Auth-loss loops', () {
    for (final state in [
      AuthIncarnationSessionStateV2.ready,
      AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionStateV2.deleting,
    ]) {
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.requestDeletion,
        ),
        AccountLifecycleCandidateRoutePathsV2.requestDeletion,
        reason: state.name,
      );
    }
    for (final state in [
      AuthIncarnationSessionStateV2.establishing,
      AuthIncarnationSessionStateV2.refreshRequired,
    ]) {
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.requestDeletion,
        ),
        '/loading',
        reason: state.name,
      );
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.reconcileDeviceWork,
        ),
        '/loading',
        reason: 'authenticated transition for ${state.name}',
      );
    }
    expect(
      candidateRouteForAccountLifecycleV2(
        state: AuthIncarnationSessionStateV2.ready,
        requestedLocation:
            AccountLifecycleCandidateRoutePathsV2.requestDeletion,
        requiresDeviceReconciliation: true,
      ),
      AccountLifecycleCandidateRoutePathsV2.reconcileDeviceWork,
    );
    for (final state in AuthIncarnationSessionStateV2.values) {
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.deletionStatus,
        ),
        AccountLifecycleCandidateRoutePathsV2.deletionStatus,
        reason: state.name,
      );
    }
    for (final state in [
      AuthIncarnationSessionStateV2.signedOut,
      AuthIncarnationSessionStateV2.deleted,
    ]) {
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.requestDeletion,
        ),
        '/login',
        reason: state.name,
      );
      expect(
        candidateRouteForAccountLifecycleV2(
          state: state,
          requestedLocation: '/board',
          statusReceiptState:
              AccountLifecycleStatusReceiptStateV2.exactAcceptanceUnknown,
        ),
        AccountLifecycleCandidateRoutePathsV2.deletionStatus,
        reason: 'bound receipt after ${state.name}',
      );
    }

    for (final receiptState in [
      AccountLifecycleStatusReceiptStateV2.exactAcceptanceUnknown,
      AccountLifecycleStatusReceiptStateV2.exactAccepted,
    ]) {
      expect(
        candidateRouteForAccountLifecycleV2(
          state: AuthIncarnationSessionStateV2.signedOut,
          requestedLocation: '/board',
          statusReceiptState: receiptState,
        ),
        AccountLifecycleCandidateRoutePathsV2.deletionStatus,
        reason: 'ordinary cold start with ${receiptState.name}',
      );
    }
    expect(
      candidateRouteForAccountLifecycleV2(
        state: AuthIncarnationSessionStateV2.signedOut,
        requestedLocation: '/board',
        statusReceiptState:
            AccountLifecycleStatusReceiptStateV2.staleOrMismatched,
      ),
      '/login',
      reason: 'a stale or cross-account receipt is never recovery authority',
    );
  });
}
