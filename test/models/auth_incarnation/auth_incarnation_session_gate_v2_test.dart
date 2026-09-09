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

AuthIncarnationSessionAdvanceV2 _observe(
  AuthIncarnationSessionGateV2 gate, {
  required String id,
  String uid = 'operator',
  String generation = _generationA,
  int lifecycleEpoch = 7,
}) => gate.observeAuth(
  attemptId: id,
  scope: _scope(uid),
  accountGenerationV2: generation,
  accountLifecycleEpochV2: lifecycleEpoch,
);

AuthIncarnationSessionAdvanceV2 _switch(
  AuthIncarnationSessionGateV2 gate, {
  required String id,
  String uid = 'operator',
  String generation = _generationA,
  int lifecycleEpoch = 7,
}) => gate.startAccountSwitch(
  attemptId: id,
  scope: _scope(uid),
  accountGenerationV2: generation,
  accountLifecycleEpochV2: lifecycleEpoch,
);

ValidatedActiveAuthorityV2 _binding(
  AuthIncarnationSessionAttemptV2 attempt, {
  String? uid,
  String? generation,
  int? lifecycleEpoch,
}) {
  final bindingUid = uid ?? attempt.scope.authUidV2;
  final bindingGeneration = generation ?? attempt.accountGenerationV2;
  final bindingLifecycleEpoch =
      lifecycleEpoch ?? attempt.accountLifecycleEpochV2;
  final scope = {
    'authProjectIdV2': attempt.scope.authProjectIdV2,
    'authTenantIdV2': attempt.scope.authTenantIdV2,
    'authUidV2': bindingUid,
  };
  final decision = evaluateAccountAuthorizationV2(
    sessionAttemptIdV2: attempt.attemptId,
    sessionAttemptEpochV2: attempt.sessionAttemptEpochV2,
    sessionAttemptNonceV2: attempt.sessionAttemptNonceV2,
    expectedScope: scope,
    tokenProof: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingLifecycleEpoch,
      'authTimeSec': 1700000001,
    },
    lifecycle: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingLifecycleEpoch,
      'lifecycleStateV2': 'active',
      'reauthAfterSecV2': 1700000000,
    },
    membership: {
      'authIncarnationSchemaVersionV2': 2,
      ...scope,
      'accountGenerationV2': bindingGeneration,
      'accountLifecycleEpochV2': bindingLifecycleEpoch,
      'membershipStatusV2': 'active',
      'associationId': 'jba',
      'capabilities': ['stats.enter'],
    },
    requiredCapability: 'stats.enter',
  );
  expect(decision.authorized, isTrue);
  return decision.binding!;
}

AuthIncarnationSessionGateV2 _ready(AuthIncarnationSessionAdvanceV2 advance) =>
    advance.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: advance.attempt,
        binding: _binding(advance.attempt),
      ),
    );

void _expectClosed(AuthIncarnationSessionGateV2 gate) {
  expect(gate.permitsProtectedListeners, isFalse);
  expect(gate.permitsCapabilities, isFalse);
  expect(gate.permitsFcmRegistration, isFalse);
}

void main() {
  test('atomic auth observation opens only after exact current proof', () {
    final advance = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    expect(advance.gate.state, AuthIncarnationSessionStateV2.establishing);
    expect(advance.gate.sessionAttemptHighWaterV2, 1);
    _expectClosed(advance.gate);
    final gate = _ready(advance);
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
    expect(gate.permitsProtectedListeners, isTrue);
  });

  test('late account-A proof cannot open account B after atomic switch', () {
    final advanceA = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
      uid: 'account-a',
    );
    final advanceB = _switch(advanceA.gate, id: 'attempt-b', uid: 'account-b');
    final gate = advanceB.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: advanceA.attempt,
        binding: _binding(advanceA.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    expect(gate.attempt!.sameAttempt(advanceB.attempt), isTrue);
    _expectClosed(gate);
  });

  test('same UID new generation and attempt invalidate old completion', () {
    final advanceA = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'old',
    );
    final advanceB = _switch(
      advanceA.gate,
      id: 'new',
      generation: _generationB,
      lifecycleEpoch: 8,
    );
    var gate = advanceB.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: advanceA.attempt,
        binding: _binding(advanceA.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.establishing);
    _expectClosed(gate);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: advanceB.attempt,
        binding: _binding(advanceB.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('refresh advances atomically before its proof can be evaluated', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'refresh-0',
    );
    final refresh1 = initial.gate.requireRefresh(attemptId: 'refresh-1');
    expect(refresh1.gate.state, AuthIncarnationSessionStateV2.refreshRequired);
    expect(refresh1.gate.sessionAttemptHighWaterV2, 2);
    _expectClosed(refresh1.gate);
    final refresh2 = refresh1.gate.requireRefresh(attemptId: 'refresh-2');
    expect(refresh2.gate.sessionAttemptHighWaterV2, 3);
    final gate = refresh2.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: refresh2.attempt,
        binding: _binding(refresh2.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
  });

  test('pre-refresh attempt proof cannot reopen the refreshed gate', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'pre-refresh',
    );
    final oldBinding = _binding(initial.attempt);
    final refreshed = initial.gate.requireRefresh(attemptId: 'post-refresh');
    final gate = refreshed.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: refreshed.attempt,
        binding: oldBinding,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('stale immutable gate branches cannot share proof', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    final readyA = _ready(initial);
    final branch1 = _switch(readyA, id: 'same-id');
    final branch2 = _switch(readyA, id: 'same-id');
    expect(branch1.attempt.sessionAttemptEpochV2, 2);
    expect(branch2.attempt.sessionAttemptEpochV2, 2);
    expect(
      identical(
        branch1.attempt.sessionAttemptNonceV2,
        branch2.attempt.sessionAttemptNonceV2,
      ),
      isFalse,
    );
    final staleCompletion = branch2.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch1.attempt,
        binding: _binding(branch1.attempt),
      ),
    );
    expect(staleCompletion.state, AuthIncarnationSessionStateV2.establishing);
    expect(staleCompletion.attempt!.sameAttempt(branch2.attempt), isTrue);
    final gate = staleCompletion.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch2.attempt,
        binding: _binding(branch1.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('stale refresh branches cannot share proof', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    final readyA = _ready(initial);
    final branch1 = readyA.requireRefresh(attemptId: 'same-refresh-id');
    final branch2 = readyA.requireRefresh(attemptId: 'same-refresh-id');
    final staleCompletion = branch2.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch1.attempt,
        binding: _binding(branch1.attempt),
      ),
    );
    expect(
      staleCompletion.state,
      AuthIncarnationSessionStateV2.refreshRequired,
    );
    expect(staleCompletion.attempt!.sameAttempt(branch2.attempt), isTrue);
    final gate = staleCompletion.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch2.attempt,
        binding: _binding(branch1.attempt),
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('precomputed account switch cannot survive sign-out', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    final readyA = _ready(initial);
    final staleBranch = _switch(readyA, id: 'attempt-b');
    final bindingB = _binding(staleBranch.attempt);
    var gate = readyA.transition(
      const AuthIncarnationSessionEventV2.signedOut(),
    );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: staleBranch.attempt,
        binding: bindingB,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.signedOut);

    final fresh = _observe(gate, id: 'attempt-b');
    expect(fresh.attempt.sessionAttemptEpochV2, 2);
    gate = fresh.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: fresh.attempt,
        binding: bindingB,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('precomputed account switch cannot survive deletion', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    final readyA = _ready(initial);
    final staleBranch = _switch(readyA, id: 'attempt-b');
    final bindingB = _binding(staleBranch.attempt);
    var gate = readyA.transition(
      AuthIncarnationSessionEventV2.lifecycleDeleted(initial.attempt),
    );
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: staleBranch.attempt,
        binding: bindingB,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.deleted);

    final fresh = _switch(gate, id: 'attempt-b');
    gate = fresh.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: fresh.attempt,
        binding: bindingB,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);
  });

  test('same ID can be reused only by a fresh atomic attempt and proof', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'reused-id',
    );
    final bindingA = _binding(initial.attempt);
    final signedOut = initial.gate.transition(
      const AuthIncarnationSessionEventV2.signedOut(),
    );
    final fresh = _observe(signedOut, id: 'reused-id');
    expect(fresh.attempt.sessionAttemptEpochV2, 2);
    var gate = fresh.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: fresh.attempt,
        binding: bindingA,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    _expectClosed(gate);

    gate = gate.transition(const AuthIncarnationSessionEventV2.signedOut());
    final finalAttempt = _observe(gate, id: 'reused-id');
    gate = _ready(finalAttempt);
    expect(gate.state, AuthIncarnationSessionStateV2.ready);
    expect(gate.sessionAttemptHighWaterV2, 3);
  });

  test('terminal and stale current-attempt events remain closed', () {
    for (final terminalKind in [
      AuthIncarnationSessionEventKindV2.lifecycleDeleting,
      AuthIncarnationSessionEventKindV2.lifecycleDeleted,
    ]) {
      final initial = _observe(
        const AuthIncarnationSessionGateV2.signedOut(),
        id: 'terminal',
      );
      final binding = _binding(initial.attempt);
      var gate = initial.gate.transition(
        terminalKind == AuthIncarnationSessionEventKindV2.lifecycleDeleting
            ? AuthIncarnationSessionEventV2.lifecycleDeleting(initial.attempt)
            : AuthIncarnationSessionEventV2.lifecycleDeleted(initial.attempt),
      );
      gate = gate.transition(
        AuthIncarnationSessionEventV2.proofReady(
          attempt: initial.attempt,
          binding: binding,
        ),
      );
      expect(
        gate.state,
        terminalKind == AuthIncarnationSessionEventKindV2.lifecycleDeleting
            ? AuthIncarnationSessionStateV2.deleting
            : AuthIncarnationSessionStateV2.deleted,
      );
      _expectClosed(gate);
    }
  });

  test('deleting can advance to deleted without reopening authority', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'deletion-progress',
    );
    var gate = initial.gate.transition(
      AuthIncarnationSessionEventV2.lifecycleDeleting(initial.attempt),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.deleting);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.lifecycleDeleted(initial.attempt),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.deleted);
    expect(gate.sessionAttemptHighWaterV2, 1);
    _expectClosed(gate);
  });

  test('invalid atomic transitions fail without granting state', () {
    final initial = _observe(
      const AuthIncarnationSessionGateV2.signedOut(),
      id: 'attempt-a',
    );
    expect(
      () => _observe(initial.gate, id: 'invalid-second-observation'),
      throwsStateError,
    );
    final blocked = initial.gate.transition(
      AuthIncarnationSessionEventV2.proofLost(initial.attempt),
    );
    expect(
      () => blocked.requireRefresh(attemptId: 'invalid-refresh'),
      throwsStateError,
    );
    _expectClosed(blocked);
  });

  test('out-of-order proof cannot install an atomic branch attempt', () {
    final initialGate = const AuthIncarnationSessionGateV2.signedOut();
    final staleBranch = _observe(initialGate, id: 'stale');
    final binding = _binding(staleBranch.attempt);
    final gate = initialGate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: staleBranch.attempt,
        binding: binding,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.signedOut);
    expect(gate.sessionAttemptHighWaterV2, 0);
    _expectClosed(gate);
  });
}
