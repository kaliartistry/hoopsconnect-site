import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/services/repositories/invite_code_repository.dart';

void main() {
  test(
    'inspect metadata cannot replace the original bearer used to redeem',
    () async {
      const raw = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-ABCDE';
      final calls = <MapEntry<String, Map<String, dynamic>>>[];
      final repository = InviteCodeRepository(
        callable: (name, data) async {
          calls.add(MapEntry(name, data));
          if (name == 'inspectPrivilegedInvite') {
            return {
              'inviteId': 'v2_${'a' * 64}',
              'associationId': 'jba',
              'role': 'media',
              'teamId': null,
              'expiresAt': '2030-01-01T00:00:00.000Z',
            };
          }
          return {};
        },
      );

      final preview = await repository.validateCode(raw);
      expect(preview, isNotNull);
      expect(preview!.inviteId, startsWith('v2_'));
      await repository.redeemCode(
        code: raw,
        displayName: 'Invitee',
        operationId: 'client_operation_00000001',
      );

      expect(calls[0].value['code'], raw);
      expect(calls[1].value['code'], raw);
      expect(calls[1].value['operationId'], 'client_operation_00000001');
      expect(preview.toString(), isNot(contains(raw)));
    },
  );

  test(
    'ambiguous callable failures are distinguished from terminal rejection',
    () {
      final lostAfterCommit = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'lost after committed redemption',
      );
      expect(
        inviteFailureDisposition(lostAfterCommit),
        InviteFailureDisposition.ambiguous,
      );
      expect(
        shouldDeletePendingAuthIdentity(
          ownsPendingIdentity: true,
          error: lostAfterCommit,
        ),
        false,
      );
      final terminal = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'used',
      );
      expect(
        inviteFailureDisposition(terminal),
        InviteFailureDisposition.terminal,
      );
      expect(
        shouldDeletePendingAuthIdentity(
          ownsPendingIdentity: true,
          error: terminal,
        ),
        true,
      );
      final authTransport = FirebaseAuthException(
        code: 'network-request-failed',
        message: 'account creation response was not confirmed',
      );
      expect(
        inviteFailureDisposition(authTransport),
        InviteFailureDisposition.ambiguous,
      );
      expect(
        shouldDeletePendingAuthIdentity(
          ownsPendingIdentity: true,
          error: authTransport,
        ),
        false,
      );
      final authTerminal = FirebaseAuthException(
        code: 'weak-password',
        message: 'rejected before account creation',
      );
      expect(
        shouldDeletePendingAuthIdentity(
          ownsPendingIdentity: true,
          error: authTerminal,
        ),
        true,
      );
    },
  );
}
