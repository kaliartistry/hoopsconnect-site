import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/account_deletion/account_lifecycle_ad02_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_v2.dart';
import 'package:hoops_connect/services/account_lifecycle_candidate_adapter_v2.dart';

const _generationA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _generationB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

AuthIncarnationScopeV2 _scope({String uid = 'operator', String? tenant}) =>
    AuthIncarnationScopeV2.fromMap({
      'authProjectIdV2': 'demo-hoopsconnect',
      'authTenantIdV2': tenant,
      'authUidV2': uid,
    });

ValidatedActiveAuthorityV2 _binding(AuthIncarnationSessionAttemptV2 attempt) {
  final scope = attempt.scope.toMap();
  final decision = evaluateAccountAuthorizationV2(
    sessionAttemptIdV2: attempt.attemptId,
    sessionAttemptEpochV2: attempt.sessionAttemptEpochV2,
    sessionAttemptNonceV2: attempt.sessionAttemptNonceV2,
    expectedScope: scope,
    tokenProof: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': attempt.accountGenerationV2,
      'accountLifecycleEpochV2': attempt.accountLifecycleEpochV2,
      'authTimeSec': 1700000001,
    },
    lifecycle: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': attempt.accountGenerationV2,
      'accountLifecycleEpochV2': attempt.accountLifecycleEpochV2,
      'lifecycleStateV2': 'active',
      'reauthAfterSecV2': 1700000000,
    },
    membership: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': attempt.accountGenerationV2,
      'accountLifecycleEpochV2': attempt.accountLifecycleEpochV2,
      'membershipStatusV2': 'active',
      'associationId': 'jba',
      'capabilities': ['association.read'],
    },
    requiredCapability: 'association.read',
  );
  expect(decision.authorized, isTrue);
  return decision.binding!;
}

AuthIncarnationSessionAttemptV2 _makeReady(
  AccountLifecycleCandidateClientAdapterV2 adapter, {
  String id = 'attempt-a',
  String uid = 'operator',
  String generation = _generationA,
  int epoch = 7,
  String? tenant,
}) {
  final attempt = adapter.observeAuth(
    attemptId: id,
    scope: _scope(uid: uid, tenant: tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: epoch,
  );
  adapter.acceptProof(attempt: attempt, binding: _binding(attempt));
  expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
  return attempt;
}

void main() {
  test(
    'shared directory fixture parses exactly and contains no private fields',
    () {
      final fixture =
          jsonDecode(
                File(
                  'contracts/account_deletion/ad02/lifecycle_fixtures_v2.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(accountLifecycleAd02ActivationAllowedV2, isFalse);
      expect(fixture['activationAllowed'], isFalse);
      expect(fixture['v1Interoperability'], 'none');

      final directory = ActiveMemberDirectoryV2.fromMap({
        'accountDirectorySchemaVersionV2': 2,
        'users': [fixture['directoryExpected'] ?? fixture['directoryEntry']],
        'truncated': false,
      });
      expect(directory.users.single.uid, fixture['rootScope']['authUidV2']);
      expect(
        directory.users.single.displayName,
        fixture['directoryEntry']['displayName'],
      );
      final serialized = jsonEncode(directory.toMap());
      for (final forbidden in [
        'email',
        'role',
        'capabilities',
        'fcmTokens',
        'notificationPrefs',
        'accountGenerationV2',
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
      expect(
        () => ActiveMemberDirectoryV2.fromMap({
          ...directory.toMap(),
          'unexpected': true,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'route adapter uses only synthetic gate state and preserves deletion intent',
    () {
      final fixture =
          jsonDecode(
                File(
                  'contracts/account_deletion/ad02/lifecycle_fixtures_v2.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final expected = fixture['routeExpectations'] as Map<String, dynamic>;
      expect(
        candidateRouteForAccountLifecycleV2(
          state: AuthIncarnationSessionStateV2.signedOut,
          requestedLocation: '/board',
        ),
        expected['signedOutOrdinary'],
      );
      expect(
        candidateRouteForAccountLifecycleV2(
          state: AuthIncarnationSessionStateV2.signedOut,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.requestDeletion,
          intent: AccountLifecycleRouteIntentV2.accountDeletion,
        ),
        expected['signedOutDeletion'],
      );
      final mapping = {
        AuthIncarnationSessionStateV2.establishing: expected['establishing'],
        AuthIncarnationSessionStateV2.refreshRequired:
            expected['refreshRequired'],
        AuthIncarnationSessionStateV2.ready: expected['ready'],
        AuthIncarnationSessionStateV2.blocked: expected['blocked'],
        AuthIncarnationSessionStateV2.deleting: expected['deleting'],
        AuthIncarnationSessionStateV2.deleted: expected['deleted'],
      };
      for (final entry in mapping.entries) {
        expect(
          candidateRouteForAccountLifecycleV2(
            state: entry.key,
            requestedLocation: '/board',
          ),
          entry.value,
        );
      }
      expect(
        candidateRouteForAccountLifecycleV2(
          state: AuthIncarnationSessionStateV2.deleting,
          requestedLocation: '/board',
          intent: AccountLifecycleRouteIntentV2.accountDeletion,
          hasBoundStatusReceipt: true,
        ),
        expected['deletingWithReceipt'],
      );
      expect(
        candidateRouteForAccountLifecycleV2(
          state: AuthIncarnationSessionStateV2.ready,
          requestedLocation:
              AccountLifecycleCandidateRoutePathsV2.requestDeletion,
          requiresDeviceReconciliation: true,
        ),
        expected['authenticatedDeviceReconciliation'],
      );
    },
  );

  test(
    'only exact ready attempt permits listeners, capability, and FCM',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = adapter.observeAuth(
        attemptId: 'attempt-a',
        scope: _scope(),
        accountGenerationV2: _generationA,
        accountLifecycleEpochV2: 7,
      );
      expect(adapter.permitsProtectedListeners, isFalse);
      expect(adapter.permitsCapabilities, isFalse);
      expect(adapter.permitsFcmRegistration, isFalse);
      expect(
        adapter.attachProtectedListener(attempt: attempt, start: () => () {}),
        isFalse,
      );

      adapter.acceptProof(attempt: attempt, binding: _binding(attempt));
      var disposed = 0;
      expect(
        adapter.attachProtectedListener(
          attempt: attempt,
          start: () =>
              () => disposed += 1,
        ),
        isTrue,
      );
      var writes = 0;
      expect(
        await adapter.registerFcmToken(
          attempt: attempt,
          token: 'token-a',
          writeRegistration: () async => writes += 1,
          removeStaleRegistration: () async {},
        ),
        isTrue,
      );
      expect(writes, 1);
      expect(adapter.fcmOwner?.attempt.sameAttempt(attempt), isTrue);
      expect(adapter.protectedListenerCount, 1);
      expect(disposed, 0);
    },
  );

  test(
    'same UID new generation retires stale async registration and listener',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final oldAttempt = _makeReady(adapter);
      var disposed = 0;
      adapter.attachProtectedListener(
        attempt: oldAttempt,
        start: () =>
            () => disposed += 1,
      );

      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      var staleRemoved = 0;
      final registration = adapter.registerFcmToken(
        attempt: oldAttempt,
        token: 'old-token',
        writeRegistration: () async {
          writeStarted.complete();
          await releaseWrite.future;
        },
        removeStaleRegistration: () async => staleRemoved += 1,
      );
      await writeStarted.future;
      final switchFuture = adapter.startAccountSwitch(
        attemptId: 'attempt-b',
        scope: _scope(),
        accountGenerationV2: _generationB,
        accountLifecycleEpochV2: 8,
        removeOwnerBinding: () async {},
        rotateInstallationToken: () async {},
      );
      releaseWrite.complete();
      expect(await registration, isFalse);
      final newAttempt = await switchFuture;
      expect(staleRemoved, 1);
      expect(disposed, 1);
      expect(adapter.fcmOwner, isNull);
      expect(adapter.gate.attempt!.sameAttempt(newAttempt), isTrue);
      expect(adapter.permitsFcmRegistration, isFalse);
    },
  );

  test('nonce mismatch and retired-attempt proof cannot reopen adapter', () {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    final current = adapter.observeAuth(
      attemptId: 'same-id',
      scope: _scope(),
      accountGenerationV2: _generationA,
      accountLifecycleEpochV2: 7,
    );
    final other = AccountLifecycleCandidateClientAdapterV2().observeAuth(
      attemptId: 'same-id',
      scope: _scope(),
      accountGenerationV2: _generationA,
      accountLifecycleEpochV2: 7,
    );
    adapter.acceptProof(attempt: current, binding: _binding(other));
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.blocked);
    expect(adapter.permitsCapabilities, isFalse);
  });

  test('refresh and deletion dispose consumers and reject resurrection', () {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    final attempt = _makeReady(adapter);
    var disposed = 0;
    adapter.attachProtectedListener(
      attempt: attempt,
      start: () =>
          () => disposed += 1,
    );
    final refresh = adapter.requireRefresh(attemptId: 'refresh');
    expect(disposed, 1);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.refreshRequired);
    expect(adapter.gate.sessionAttemptHighWaterV2, 2);
    adapter.acceptProof(attempt: attempt, binding: _binding(attempt));
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.refreshRequired);

    adapter.acceptProof(attempt: refresh, binding: _binding(refresh));
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
    adapter.markDeleting(refresh);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.deleting);
    adapter.acceptProof(attempt: refresh, binding: _binding(refresh));
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.deleting);
    adapter.markDeleted(refresh);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.deleted);
    adapter.acceptProof(attempt: refresh, binding: _binding(refresh));
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.deleted);
  });

  test('stale branch events cannot tear down a newer ready attempt', () async {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    final oldAttempt = _makeReady(adapter);
    final nextAttempt = await adapter.startAccountSwitch(
      attemptId: 'next-attempt',
      scope: _scope(),
      accountGenerationV2: _generationB,
      accountLifecycleEpochV2: 8,
      removeOwnerBinding: () async {},
      rotateInstallationToken: () async {},
    );
    adapter.acceptProof(attempt: nextAttempt, binding: _binding(nextAttempt));
    var disposed = 0;
    adapter.attachProtectedListener(
      attempt: nextAttempt,
      start: () =>
          () => disposed += 1,
    );
    adapter.loseProof(oldAttempt);
    adapter.markDeleting(oldAttempt);
    adapter.markDeleted(oldAttempt);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
    expect(adapter.gate.attempt!.sameAttempt(nextAttempt), isTrue);
    expect(adapter.protectedListenerCount, 1);
    expect(disposed, 0);
  });

  test(
    'a faulty listener disposer cannot keep the old ready gate open',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final oldAttempt = _makeReady(adapter);
      var secondDisposed = 0;
      adapter.attachProtectedListener(
        attempt: oldAttempt,
        start: () =>
            () => throw StateError('dispose failed'),
      );
      adapter.attachProtectedListener(
        attempt: oldAttempt,
        start: () =>
            () => secondDisposed += 1,
      );

      final nextAttempt = await adapter.startAccountSwitch(
        attemptId: 'next-attempt',
        scope: _scope(uid: 'next-user'),
        accountGenerationV2: _generationB,
        accountLifecycleEpochV2: 8,
        removeOwnerBinding: () async {},
        rotateInstallationToken: () async {},
      );
      expect(secondDisposed, 1);
      expect(adapter.protectedListenerCount, 0);
      expect(adapter.gate.attempt!.sameAttempt(nextAttempt), isTrue);
      expect(adapter.permitsCapabilities, isFalse);
    },
  );

  test(
    'both detach controls failing blocks Auth sign-out and restores ready gate',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      _makeReady(adapter);
      var signOutCalls = 0;
      await expectLater(
        adapter.detachAndSignOut(
          removeOwnerBinding: () async => throw StateError('remove failed'),
          rotateInstallationToken: () async =>
              throw StateError('rotate failed'),
          signOutExactCurrent: (_) async => signOutCalls += 1,
          restoreRegistration: () async {},
          verifyAuthStillCurrent: (_) async => true,
        ),
        throwsStateError,
      );
      expect(signOutCalls, 0);
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
      expect(adapter.permitsFcmRegistration, isTrue);
    },
  );

  test(
    'either detach control permits sign-out and high-water survives',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      _makeReady(adapter);
      final result = await adapter.detachAndSignOut(
        removeOwnerBinding: () async => throw StateError('remove failed'),
        rotateInstallationToken: () async {},
        signOutExactCurrent: (_) async {},
        restoreRegistration: () async {},
        verifyAuthStillCurrent: (_) async => true,
      );
      expect(result.ownerBindingRemoved, isFalse);
      expect(result.installationTokenRotated, isTrue);
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
      expect(adapter.gate.sessionAttemptHighWaterV2, 1);
      final next = adapter.observeAuth(
        attemptId: 'next',
        scope: _scope(uid: 'next-user'),
        accountGenerationV2: _generationB,
        accountLifecycleEpochV2: 0,
      );
      expect(next.sessionAttemptEpochV2, 2);
    },
  );

  test(
    'Auth sign-out failure restores exact ready attempt and registration',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      await adapter.registerFcmToken(
        attempt: attempt,
        token: 'token-a',
        writeRegistration: () async {},
        removeStaleRegistration: () async {},
      );
      var restored = 0;
      await expectLater(
        adapter.detachAndSignOut(
          removeOwnerBinding: () async {},
          rotateInstallationToken: () async =>
              throw StateError('rotate failed'),
          signOutExactCurrent: (_) async => throw StateError('sign-out failed'),
          restoreRegistration: () async => restored += 1,
          verifyAuthStillCurrent: (_) async => true,
        ),
        throwsStateError,
      );
      expect(restored, 1);
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
      expect(adapter.gate.attempt!.sameAttempt(attempt), isTrue);
      expect(adapter.fcmOwner?.attempt.sameAttempt(attempt), isTrue);
      expect(adapter.permitsFcmRegistration, isTrue);
    },
  );

  test(
    'failed sign-out restoration keeps every client-side grant latched closed',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      await adapter.registerFcmToken(
        attempt: attempt,
        token: 'token-a',
        writeRegistration: () async {},
        removeStaleRegistration: () async {},
      );
      await expectLater(
        adapter.detachAndSignOut(
          removeOwnerBinding: () async {},
          rotateInstallationToken: () async =>
              throw StateError('rotate failed'),
          signOutExactCurrent: (_) async => throw StateError('sign-out failed'),
          restoreRegistration: () async => throw StateError('restore failed'),
          verifyAuthStillCurrent: (_) async => true,
        ),
        throwsStateError,
      );
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
      expect(adapter.gate.sessionAttemptHighWaterV2, 1);
      expect(adapter.fcmOwner, isNull);
      expect(adapter.permitsProtectedListeners, isFalse);
      expect(adapter.permitsCapabilities, isFalse);
      expect(adapter.permitsFcmRegistration, isFalse);
    },
  );

  test(
    'detach serialization cannot clobber a concurrent auth observation',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      final detachStarted = Completer<void>();
      final releaseDetach = Completer<void>();
      final pending = adapter.detachAndSignOut(
        removeOwnerBinding: () async {
          detachStarted.complete();
          await releaseDetach.future;
        },
        rotateInstallationToken: () async => throw StateError('rotate failed'),
        signOutExactCurrent: (_) async => throw StateError('sign-out failed'),
        restoreRegistration: () async {},
        verifyAuthStillCurrent: (_) async => true,
      );
      await detachStarted.future;

      expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
      await expectLater(
        adapter.startAccountSwitch(
          attemptId: 'concurrent-attempt',
          scope: _scope(uid: 'next-user'),
          accountGenerationV2: _generationB,
          accountLifecycleEpochV2: 0,
          removeOwnerBinding: () async {},
          rotateInstallationToken: () async {},
        ),
        throwsStateError,
      );
      expect(adapter.permitsCapabilities, isFalse);
      releaseDetach.complete();
      await expectLater(pending, throwsStateError);
      expect(adapter.gate.attempt!.sameAttempt(attempt), isTrue);
      expect(adapter.permitsCapabilities, isTrue);
    },
  );

  test(
    'deletion observed during detach cannot be rolled back to ready',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      final detachStarted = Completer<void>();
      final releaseDetach = Completer<void>();
      var restoreCalls = 0;
      final pending = adapter.detachAndSignOut(
        removeOwnerBinding: () async {
          detachStarted.complete();
          await releaseDetach.future;
        },
        rotateInstallationToken: () async => throw StateError('rotate failed'),
        signOutExactCurrent: (_) async => throw StateError('sign-out failed'),
        restoreRegistration: () async => restoreCalls += 1,
        verifyAuthStillCurrent: (_) async => true,
      );
      await detachStarted.future;
      adapter.markDeleting(attempt);
      releaseDetach.complete();
      await expectLater(pending, throwsStateError);
      expect(restoreCalls, 0);
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.deleting);
      expect(adapter.permitsCapabilities, isFalse);
    },
  );

  test('queued detach cannot clear an uncertain restoration latch', () async {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    _makeReady(adapter);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final first = adapter.detachAndSignOut(
      removeOwnerBinding: () async {
        firstStarted.complete();
        await releaseFirst.future;
      },
      rotateInstallationToken: () async => throw StateError('rotate failed'),
      signOutExactCurrent: (_) async => throw StateError('sign-out failed'),
      restoreRegistration: () async => throw StateError('restore failed'),
      verifyAuthStillCurrent: (_) async => true,
    );
    await firstStarted.future;

    var secondControlCalls = 0;
    final second = adapter.detachAndSignOut(
      removeOwnerBinding: () async {
        secondControlCalls += 1;
      },
      rotateInstallationToken: () async {
        secondControlCalls += 1;
      },
      signOutExactCurrent: (_) async {
        secondControlCalls += 1;
      },
      restoreRegistration: () async {
        secondControlCalls += 1;
      },
      verifyAuthStillCurrent: (_) async {
        secondControlCalls += 1;
        return true;
      },
    );
    final secondExpectation = expectLater(second, throwsStateError);
    releaseFirst.complete();
    await expectLater(first, throwsStateError);
    await secondExpectation;
    expect(secondControlCalls, 0);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
    expect(adapter.permitsProtectedListeners, isFalse);
    expect(adapter.permitsCapabilities, isFalse);
    expect(adapter.permitsFcmRegistration, isFalse);
  });

  test(
    'account switch removes or rotates the prior remote FCM owner',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      var remoteRegistration = true;
      await adapter.registerFcmToken(
        attempt: attempt,
        token: 'token-a',
        writeRegistration: () async => remoteRegistration = true,
        removeStaleRegistration: () async => remoteRegistration = false,
      );

      final next = await adapter.startAccountSwitch(
        attemptId: 'attempt-b',
        scope: _scope(uid: 'next-user'),
        accountGenerationV2: _generationB,
        accountLifecycleEpochV2: 0,
        removeOwnerBinding: () async => remoteRegistration = false,
        rotateInstallationToken: () async =>
            throw StateError('rotation unavailable'),
      );
      expect(remoteRegistration, isFalse);
      expect(adapter.fcmOwner, isNull);
      expect(adapter.gate.attempt!.sameAttempt(next), isTrue);
      expect(adapter.permitsFcmRegistration, isFalse);
    },
  );

  test(
    'account switch is blocked when both remote detach controls fail',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      await adapter.registerFcmToken(
        attempt: attempt,
        token: 'token-a',
        writeRegistration: () async {},
        removeStaleRegistration: () async {},
      );
      await expectLater(
        adapter.startAccountSwitch(
          attemptId: 'attempt-b',
          scope: _scope(uid: 'next-user'),
          accountGenerationV2: _generationB,
          accountLifecycleEpochV2: 0,
          removeOwnerBinding: () async => throw StateError('remove failed'),
          rotateInstallationToken: () async =>
              throw StateError('rotation failed'),
        ),
        throwsStateError,
      );
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.ready);
      expect(adapter.gate.attempt!.sameAttempt(attempt), isTrue);
      expect(adapter.fcmOwner?.attempt.sameAttempt(attempt), isTrue);
      expect(adapter.permitsCapabilities, isTrue);
    },
  );

  test('detach latches synchronously before a queued token mutation', () async {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    final attempt = _makeReady(adapter);
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final registration = adapter.registerFcmToken(
      attempt: attempt,
      token: 'token-a',
      writeRegistration: () async {
        writeStarted.complete();
        await releaseWrite.future;
      },
      removeStaleRegistration: () async {},
    );
    await writeStarted.future;
    final detach = adapter.detachAndSignOut(
      removeOwnerBinding: () async {},
      rotateInstallationToken: () async {},
      signOutExactCurrent: (_) async {},
      restoreRegistration: () async {},
      verifyAuthStillCurrent: (_) async => true,
    );

    await expectLater(
      adapter.startAccountSwitch(
        attemptId: 'attempt-b',
        scope: _scope(uid: 'next-user'),
        accountGenerationV2: _generationB,
        accountLifecycleEpochV2: 0,
        removeOwnerBinding: () async {},
        rotateInstallationToken: () async {},
      ),
      throwsStateError,
    );
    releaseWrite.complete();
    expect(await registration, isFalse);
    await detach;
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
  });

  test(
    'queued provider change is rejected before attempt-scoped sign-out',
    () async {
      final adapter = AccountLifecycleCandidateClientAdapterV2();
      final attempt = _makeReady(adapter);
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      final registration = adapter.registerFcmToken(
        attempt: attempt,
        token: 'token-a',
        writeRegistration: () async {
          writeStarted.complete();
          await releaseWrite.future;
        },
        removeStaleRegistration: () async {},
      );
      await writeStarted.future;

      var providerStillMatches = true;
      var signOutCalls = 0;
      final detach = adapter.detachAndSignOut(
        removeOwnerBinding: () async {},
        rotateInstallationToken: () async {},
        signOutExactCurrent: (captured) async {
          expect(captured.sameAttempt(attempt), isTrue);
          signOutCalls += 1;
        },
        restoreRegistration: () async {},
        verifyAuthStillCurrent: (captured) async {
          expect(captured.sameAttempt(attempt), isTrue);
          return providerStillMatches;
        },
      );
      providerStillMatches = false;
      releaseWrite.complete();

      expect(await registration, isFalse);
      await expectLater(detach, throwsStateError);
      expect(signOutCalls, 0);
      expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
      expect(adapter.fcmOwner, isNull);
      expect(adapter.permitsCapabilities, isFalse);
    },
  );

  test('throwing sign-out cannot reopen a provider-changed session', () async {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    _makeReady(adapter);
    var providerStillMatches = true;
    var restoreCalls = 0;
    await expectLater(
      adapter.detachAndSignOut(
        removeOwnerBinding: () async {},
        rotateInstallationToken: () async =>
            throw StateError('rotation unavailable'),
        signOutExactCurrent: (_) async {
          providerStillMatches = false;
          throw StateError('sign-out observer failed');
        },
        restoreRegistration: () async => restoreCalls += 1,
        verifyAuthStillCurrent: (_) async => providerStillMatches,
      ),
      throwsStateError,
    );
    expect(restoreCalls, 0);
    expect(adapter.gate.state, AuthIncarnationSessionStateV2.signedOut);
    expect(adapter.permitsCapabilities, isFalse);
  });

  test('cached gate views cannot preserve a retired ready grant', () {
    final adapter = AccountLifecycleCandidateClientAdapterV2();
    final attempt = _makeReady(adapter);
    final cached = adapter.gate;
    expect(cached.permitsCapabilities, isTrue);
    adapter.markDeleting(attempt);
    expect(cached.state, AuthIncarnationSessionStateV2.deleting);
    expect(cached.permitsProtectedListeners, isFalse);
    expect(cached.permitsCapabilities, isFalse);
    expect(cached.permitsFcmRegistration, isFalse);
  });
}
