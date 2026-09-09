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
      ),
      '/delete-account',
    );
  });
}
