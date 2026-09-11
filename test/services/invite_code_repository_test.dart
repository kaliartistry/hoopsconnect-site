import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/invite_code_model.dart';
import 'package:hoops_connect/services/repositories/invite_code_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
    'creation attempt reuses one operation ID after a lost response',
    () async {
      final operationIds = <String>[];
      final logicalIssuances = <String>{};
      var calls = 0;
      final repository = InviteCodeRepository(
        callable: (name, data) async {
          expect(name, 'createPrivilegedInvite');
          expect(data['authorizationSchemaVersion'], 1);
          calls += 1;
          final operationId = data['operationId'] as String;
          operationIds.add(operationId);
          logicalIssuances.add(operationId);
          if (calls == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'response lost after commit',
            );
          }
          final code = 'C' * 43;
          return {
            'inviteId': _inviteId(code),
            'associationId': 'jba',
            'role': data['role'],
            'teamId': data['teamId'],
            'usesRemaining': 1,
            'status': 'active',
            'expiresAt': '2030-01-01T00:00:00.000Z',
            'code': code,
          };
        },
      );
      const attempt = InviteCreationAttempt(
        role: 'rep',
        teamId: 'team-1',
        daysValid: 7,
        operationId: 'create_operation_client_0001',
      );

      await expectLater(
        attempt.submit(repository, expectedAssociationId: 'jba'),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
      final recovered = await attempt.submit(
        repository,
        expectedAssociationId: 'jba',
      );

      expect(recovered.invite.teamId, 'team-1');
      expect(recovered.code, 'C' * 43);
      expect(operationIds, [
        'create_operation_client_0001',
        'create_operation_client_0001',
      ]);
      expect(logicalIssuances, hasLength(1));
    },
  );

  test(
    'truncated creation response remains receipt-unknown for exact replay',
    () async {
      final operationIds = <String>[];
      var calls = 0;
      final repository = InviteCodeRepository(
        callable: (name, data) async {
          expect(name, 'createPrivilegedInvite');
          operationIds.add(data['operationId'] as String);
          calls += 1;
          final code = calls == 1 ? 'truncated' : 'M' * 43;
          final response = <Object?, Object?>{
            'inviteId': calls == 1 ? 'v2_${'c' * 64}' : _inviteId(code),
            'associationId': 'jba',
            'role': 'media',
            'teamId': null,
            'expiresAt': '2030-01-01T00:00:00.000Z',
            'code': code,
          };
          return response;
        },
      );
      const attempt = InviteCreationAttempt(
        role: 'media',
        teamId: null,
        daysValid: 7,
        operationId: 'create_operation_malformed_001',
      );

      final firstError = await attempt
          .submit(repository, expectedAssociationId: 'jba')
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(firstError, isA<InviteReceiptUnknownException>());
      expect(
        inviteFailureDisposition(firstError!),
        InviteFailureDisposition.ambiguous,
      );
      final recovered = await attempt.submit(
        repository,
        expectedAssociationId: 'jba',
      );

      expect(recovered.code, 'M' * 43);
      expect(operationIds, [
        'create_operation_malformed_001',
        'create_operation_malformed_001',
      ]);
    },
  );

  test(
    'authoritative usability check rejects a stale issued receipt',
    () async {
      final repository = InviteCodeRepository(
        callable: (name, data) async {
          expect(name, 'inspectPrivilegedInvite');
          expect(data['code'], 'U' * 43);
          throw FirebaseFunctionsException(
            code: 'not-found',
            message: 'revoked, redeemed, or expired',
          );
        },
      );
      final issued = IssuedInviteCode(
        invite: InviteCodeModel(
          inviteId: 'v2_${'a' * 64}',
          teamId: null,
          role: 'media',
          usesRemaining: 1,
          status: 'active',
          expiresAt: DateTime.utc(2030),
          associationId: 'jba',
        ),
        code: 'U' * 43,
      );

      expect(
        await repository.verifyIssuedCode(issued),
        IssuedInviteUsability.inactive,
      );
    },
  );

  test(
    'usability check fails closed on explicitly inactive metadata',
    () async {
      final code = 'V' * 43;
      final repository = InviteCodeRepository(
        callable: (name, data) async => {
          'inviteId': _inviteId(code),
          'associationId': 'jba',
          'role': 'media',
          'teamId': null,
          'usesRemaining': 0,
          'status': 'redeemed',
          'expiresAt': '2030-01-01T00:00:00.000Z',
        },
      );
      final issued = IssuedInviteCode(
        invite: InviteCodeModel(
          inviteId: _inviteId(code),
          teamId: null,
          role: 'media',
          usesRemaining: 1,
          status: 'active',
          expiresAt: DateTime.utc(2030),
          associationId: 'jba',
        ),
        code: code,
      );

      expect(
        await repository.verifyIssuedCode(issued),
        IssuedInviteUsability.inactive,
      );
    },
  );

  test('persisted creation attempts are account and association bound', () {
    const attempt = InviteCreationAttempt(
      role: 'rep',
      teamId: 'team-1',
      daysValid: 7,
      operationId: 'create_operation_client_0002',
    );
    final encoded = attempt.toJson(actorId: 'admin-1', associationId: 'jba');

    expect(
      InviteCreationAttempt.fromJson(
        encoded,
        actorId: 'admin-1',
        associationId: 'jba',
      )?.operationId,
      attempt.operationId,
    );
    expect(
      InviteCreationAttempt.fromJson(
        encoded,
        actorId: 'admin-2',
        associationId: 'jba',
      ),
      isNull,
    );
    expect(
      InviteCreationAttempt.fromJson(
        encoded,
        actorId: 'admin-1',
        associationId: 'other',
      ),
      isNull,
    );
  });

  test('shared preferences store persists only the logical request', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesInviteCreationAttemptStore();
    const attempt = InviteCreationAttempt(
      role: 'media',
      teamId: null,
      daysValid: 14,
      operationId: 'create_operation_client_0003',
    );

    await store.save(
      actorId: 'admin-1',
      associationId: 'jba',
      attempt: attempt,
    );
    final recovered = await store.load(
      actorId: 'admin-1',
      associationId: 'jba',
    );
    final preferences = await SharedPreferences.getInstance();
    final persisted = preferences
        .getKeys()
        .map(preferences.getString)
        .whereType<String>()
        .single;

    expect(recovered?.operationId, attempt.operationId);
    expect(persisted, contains(attempt.operationId));
    expect(persisted, isNot(contains('"code"')));
    await store.clear(actorId: 'admin-1', associationId: 'jba');
    expect(preferences.getKeys(), isEmpty);
  });
}

String _inviteId(String code) =>
    'v2_${sha256.convert(code.codeUnits).toString()}';
