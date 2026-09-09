import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_v2.dart';

const _generationA =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _generationB =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

AuthIncarnationScopeV2 _scope(String uid) => AuthIncarnationScopeV2.fromMap({
  'authProjectIdV2': 'demo-hoopsconnect',
  'authTenantIdV2': null,
  'authUidV2': uid,
});

AuthIncarnationSessionAttemptV2 _issue(
  AuthIncarnationSessionGateV2 gate, {
  required String id,
  String uid = 'operator',
  String generation = _generationA,
  int epoch = 7,
}) => gate.issueAttempt(
  attemptId: id,
  scope: _scope(uid),
  accountGenerationV2: generation,
  accountLifecycleEpochV2: epoch,
);

ValidatedActiveAuthorityV2 _binding(
  AuthIncarnationSessionAttemptV2 attempt, {
  String? uid,
  String? generation,
  int? epoch,
}) {
  final bindingUid = uid ?? attempt.scope.authUidV2;
  final bindingGeneration = generation ?? attempt.accountGenerationV2;
  final bindingEpoch = epoch ?? attempt.accountLifecycleEpochV2;
  final scope = {
    'authProjectIdV2': attempt.scope.authProjectIdV2,
    'authTenantIdV2': attempt.scope.authTenantIdV2,
    'authUidV2': bindingUid,
  };
  final decision = evaluateAccountAuthorizationV2(
    sessionAttemptIdV2: attempt.attemptId,
    sessionAttemptEpochV2: attempt.sessionAttemptEpochV2,
    expectedScope: scope,
    tokenProof: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingEpoch,
      'authTimeSec': 1700000001,
    },
    lifecycle: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingEpoch,
      'lifecycleStateV2': 'active',
      'reauthAfterSecV2': 1700000000,
    },
    membership: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingEpoch,
      'membershipStatusV2': 'active',
      'associationId': 'jba',
      'capabilities': ['stats.enter'],
    },
    requiredCapability: 'stats.enter',
  );
  expect(decision.authorized, isTrue);
  return decision.binding!;
}

void _expectClosed(AuthIncarnationSessionGateV2 gate) {
  expect(gate.permitsProtectedListeners, isFalse);
  expect(gate.permitsCapabilities, isFalse);
  expect(gate.permitsFcmRegistration, isFalse);
}

void main() {
  test('current evaluator proof opens only the exact pending attempt', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attempt = _issue(gate, id: 'attempt-a');
    gate = gate.transition(AuthIncarnationSessionEventV2.authObserved(attempt));
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: _binding(attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
    expect(gate.permitsProtectedListeners, isTrue);
  });

  test('late account-A proof cannot open account B after switch', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attemptA = _issue(gate, id: 'attempt-a', uid: 'account-a');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.authObserved(attemptA),
    );
    final attemptB = _issue(gate, id: 'attempt-b', uid: 'account-b');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.accountSwitchStarted(attemptB),
    );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attemptA,
        binding: _binding(attemptA),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    _expectClosed(gate);
  });

  test('same UID new generation and attempt invalidate old completion', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final oldAttempt = _issue(gate, id: 'old');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.authObserved(oldAttempt),
    );
    final newAttempt = _issue(
      gate,
      id: 'new',
      generation: _generationB,
      epoch: 8,
    );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.accountSwitchStarted(newAttempt),
    );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: oldAttempt,
        binding: _binding(oldAttempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: newAttempt,
        binding: _binding(newAttempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('same exact identity cannot replay a binding across attempt IDs', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attemptA = _issue(gate, id: 'same-identity-a');
    final oldBinding = _binding(attemptA);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.authObserved(attemptA),
    );
    final attemptB = _issue(gate, id: 'same-identity-b');
    gate = gate
        .transition(
          AuthIncarnationSessionEventV2.accountSwitchStarted(attemptB),
        )
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptB,
            binding: oldBinding,
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('matching attempt cannot use a binding for another identity', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attempt = _issue(gate, id: 'attempt-a');
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attempt,
            binding: _binding(attempt, uid: 'other-user'),
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('repeated refresh remains closed until matching proof', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attempt = _issue(gate, id: 'refresh-0');
    gate = gate.transition(AuthIncarnationSessionEventV2.authObserved(attempt));
    final refresh1 = _issue(gate, id: 'refresh-1');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.refreshRequired(
        currentAttempt: attempt,
        refreshedAttempt: refresh1,
      ),
    );
    final refresh2 = _issue(gate, id: 'refresh-2');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.refreshRequired(
        currentAttempt: refresh1,
        refreshedAttempt: refresh2,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.refreshRequired);
    expect(gate.sessionAttemptHighWaterV2, 3);
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: refresh2,
        binding: _binding(refresh2),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('pre-refresh proof cannot reopen a refreshed attempt', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attempt = _issue(gate, id: 'pre-refresh');
    final oldBinding = _binding(attempt);
    gate = gate.transition(AuthIncarnationSessionEventV2.authObserved(attempt));
    final refreshed = _issue(gate, id: 'post-refresh');
    gate = gate
        .transition(
          AuthIncarnationSessionEventV2.refreshRequired(
            currentAttempt: attempt,
            refreshedAttempt: refreshed,
          ),
        )
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: refreshed,
            binding: oldBinding,
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('refresh cannot resurrect its retired attempt and binding', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attemptA = _issue(gate, id: 'attempt-a');
    final bindingA = _binding(attemptA);
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptA))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptA,
            binding: bindingA,
          ),
        );
    final attemptB = _issue(gate, id: 'attempt-b');
    gate = gate.transition(
      AuthIncarnationSessionEventV2.refreshRequired(
        currentAttempt: attemptA,
        refreshedAttempt: attemptB,
      ),
    );
    gate = gate
        .transition(
          AuthIncarnationSessionEventV2.accountSwitchStarted(attemptA),
        )
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptA,
            binding: bindingA,
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.refreshRequired);
    expect(gate.attempt!.sameAttempt(attemptB), isTrue);
    expect(gate.sessionAttemptHighWaterV2, 2);
    _expectClosed(gate);
  });

  test('sign-out cannot resurrect its retired attempt and binding', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attemptA = _issue(gate, id: 'attempt-a');
    final bindingA = _binding(attemptA);
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptA))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptA,
            binding: bindingA,
          ),
        )
        .transition(const AuthIncarnationSessionEventV2.signedOut())
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptA))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptA,
            binding: bindingA,
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.signedOut);
    expect(gate.sessionAttemptHighWaterV2, 1);
    _expectClosed(gate);
  });

  test('terminal states cannot resurrect retired attempts', () {
    for (final terminalKind in [
      AuthIncarnationSessionEventKindV2.lifecycleDeleting,
      AuthIncarnationSessionEventKindV2.lifecycleDeleted,
    ]) {
      var gate = const AuthIncarnationSessionGateV2.signedOut();
      final attemptA = _issue(gate, id: 'terminal');
      final bindingA = _binding(attemptA);
      gate = gate.transition(
        AuthIncarnationSessionEventV2.authObserved(attemptA),
      );
      gate = gate.transition(
        terminalKind == AuthIncarnationSessionEventKindV2.lifecycleDeleting
            ? AuthIncarnationSessionEventV2.lifecycleDeleting(attemptA)
            : AuthIncarnationSessionEventV2.lifecycleDeleted(attemptA),
      );
      gate = gate
          .transition(
            AuthIncarnationSessionEventV2.accountSwitchStarted(attemptA),
          )
          .transition(
            AuthIncarnationSessionEventV2.proofReady(
              attempt: attemptA,
              binding: bindingA,
            ),
          );
      expect(
        gate.state,
        terminalKind == AuthIncarnationSessionEventKindV2.lifecycleDeleting
            ? AuthIncarnationSessionStateV2.deleting
            : AuthIncarnationSessionStateV2.deleted,
      );
      expect(gate.sessionAttemptHighWaterV2, 1);
      _expectClosed(gate);
    }
  });

  test('a fresh gate-issued attempt can reuse an ID but not its old proof', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attemptA = _issue(gate, id: 'reused-id');
    final bindingA = _binding(attemptA);
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptA))
        .transition(const AuthIncarnationSessionEventV2.signedOut());
    final attemptB = _issue(gate, id: 'reused-id');
    expect(attemptB.sessionAttemptEpochV2, 2);
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptB))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptB,
            binding: bindingA,
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);

    gate = gate.transition(const AuthIncarnationSessionEventV2.signedOut());
    final attemptC = _issue(gate, id: 'reused-id');
    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptC))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attemptC,
            binding: _binding(attemptC),
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
    expect(gate.sessionAttemptHighWaterV2, 3);
  });

  test('out-of-order proof and stale starts stay closed', () {
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    final attempt = _issue(gate, id: 'stale');
    final binding = _binding(attempt);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: binding,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.signedOut);

    gate = gate
        .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
        .transition(const AuthIncarnationSessionEventV2.signedOut())
        .transition(
          AuthIncarnationSessionEventV2.accountSwitchStarted(attempt),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.signedOut);
    _expectClosed(gate);
  });
}
