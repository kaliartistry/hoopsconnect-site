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

AuthIncarnationSessionAttemptV2 _attempt({
  required String id,
  String uid = 'operator',
  String generation = _generationA,
  int epoch = 7,
}) => AuthIncarnationSessionAttemptV2(
  attemptId: id,
  scope: _scope(uid),
  accountGenerationV2: generation,
  accountLifecycleEpochV2: epoch,
);

ValidatedActiveAuthorityV2 _binding({
  String uid = 'operator',
  String generation = _generationA,
  int epoch = 7,
}) {
  final scope = {
    'authProjectIdV2': 'demo-hoopsconnect',
    'authTenantIdV2': null,
    'authUidV2': uid,
  };
  final decision = evaluateAccountAuthorizationV2(
    expectedScope: scope,
    tokenProof: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': generation,
      'accountLifecycleEpochV2': epoch,
      'authTimeSec': 1700000001,
    },
    lifecycle: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': generation,
      'accountLifecycleEpochV2': epoch,
      'lifecycleStateV2': 'active',
      'reauthAfterSecV2': 1700000000,
    },
    membership: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': generation,
      'accountLifecycleEpochV2': epoch,
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
    final attempt = _attempt(id: 'attempt-a');
    var gate = const AuthIncarnationSessionGateV2.signedOut().transition(
      AuthIncarnationSessionEventV2.authObserved(attempt),
    );
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: _binding(),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
    expect(gate.permitsProtectedListeners, isTrue);
  });

  test('late account-A proof cannot open account B after switch', () {
    final attemptA = _attempt(id: 'attempt-a', uid: 'account-a');
    final attemptB = _attempt(id: 'attempt-b', uid: 'account-b');
    var gate = const AuthIncarnationSessionGateV2.signedOut()
        .transition(AuthIncarnationSessionEventV2.authObserved(attemptA))
        .transition(
          AuthIncarnationSessionEventV2.accountSwitchStarted(attemptB),
        );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attemptA,
        binding: _binding(uid: 'account-a'),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    _expectClosed(gate);
  });

  test('same UID new generation and attempt invalidate old completion', () {
    final oldAttempt = _attempt(id: 'old');
    final newAttempt = _attempt(id: 'new', generation: _generationB, epoch: 8);
    var gate = const AuthIncarnationSessionGateV2.signedOut()
        .transition(AuthIncarnationSessionEventV2.authObserved(oldAttempt))
        .transition(
          AuthIncarnationSessionEventV2.accountSwitchStarted(newAttempt),
        );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: oldAttempt,
        binding: _binding(),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: newAttempt,
        binding: _binding(generation: _generationB, epoch: 8),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('matching attempt cannot use a binding for another identity', () {
    final attempt = _attempt(id: 'attempt-a');
    final gate = const AuthIncarnationSessionGateV2.signedOut()
        .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attempt,
            binding: _binding(uid: 'other-user'),
          ),
        );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('repeated refresh remains closed until matching proof', () {
    final attempt = _attempt(id: 'refresh');
    var gate = const AuthIncarnationSessionGateV2.signedOut()
        .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
        .transition(AuthIncarnationSessionEventV2.refreshRequired(attempt))
        .transition(AuthIncarnationSessionEventV2.refreshRequired(attempt));
    expect(gate.state, AuthIncarnationSessionStateV2.refreshRequired);
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: _binding(),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('sign-out, deleting, deleted, and out-of-order proof stay closed', () {
    final attempt = _attempt(id: 'terminal');
    final binding = _binding();
    final signedOut = const AuthIncarnationSessionGateV2.signedOut().transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: binding,
      ),
    );
    expect(signedOut.state, AuthIncarnationSessionStateV2.signedOut);
    _expectClosed(signedOut);

    for (final terminalEvent in [
      AuthIncarnationSessionEventV2.lifecycleDeleting(attempt),
      AuthIncarnationSessionEventV2.lifecycleDeleted(attempt),
    ]) {
      var gate = const AuthIncarnationSessionGateV2.signedOut()
          .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
          .transition(terminalEvent);
      gate = gate.transition(
        AuthIncarnationSessionEventV2.proofReady(
          attempt: attempt,
          binding: binding,
        ),
      );
      expect(
        gate.state,
        terminalEvent.kind ==
                AuthIncarnationSessionEventKindV2.lifecycleDeleting
            ? AuthIncarnationSessionStateV2.deleting
            : AuthIncarnationSessionStateV2.deleted,
      );
      gate = gate.transition(
        AuthIncarnationSessionEventV2.authObserved(attempt),
      );
      _expectClosed(gate);
    }

    final afterSignOut = const AuthIncarnationSessionGateV2.signedOut()
        .transition(AuthIncarnationSessionEventV2.authObserved(attempt))
        .transition(const AuthIncarnationSessionEventV2.signedOut())
        .transition(
          AuthIncarnationSessionEventV2.proofReady(
            attempt: attempt,
            binding: binding,
          ),
        );
    expect(afterSignOut.state, AuthIncarnationSessionStateV2.signedOut);
    _expectClosed(afterSignOut);
  });
}
