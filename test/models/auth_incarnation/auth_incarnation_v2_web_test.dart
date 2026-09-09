import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_v2.dart';

const generation =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> scope() => {
  'authProjectIdV2': 'demo-hoopsconnect',
  'authTenantIdV2': null,
  'authUidV2': 'operator',
};

Map<String, Object?> token() => {
  'authIncarnationSchemaVersionV2': 2,
  ...scope(),
  'accountGenerationV2': generation,
  'accountLifecycleEpochV2': 7,
  'authTimeSec': 1700000001,
};

Map<String, Object?> lifecycle() => {
  'authIncarnationSchemaVersionV2': 2,
  ...scope(),
  'accountGenerationV2': generation,
  'accountLifecycleEpochV2': 7,
  'lifecycleStateV2': 'active',
  'reauthAfterSecV2': 1700000000,
};

Map<String, Object?> membership() => {
  'authIncarnationSchemaVersionV2': 2,
  ...scope(),
  'accountGenerationV2': generation,
  'accountLifecycleEpochV2': 7,
  'membershipStatusV2': 'active',
  'associationId': 'jba',
  'capabilities': ['stats.enter'],
};

void main() {
  test('Chrome accepts only the all-exact V2 tuple', () {
    final allowed = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: 'web-evaluation',
      sessionAttemptEpochV2: 1,
      sessionAttemptNonceV2: Object(),
      expectedScope: scope(),
      tokenProof: token(),
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    expect(allowed.authorized, isTrue);

    final stale = token()
      ..['accountGenerationV2'] = List.filled(64, 'f').join();
    final denied = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: 'web-evaluation',
      sessionAttemptEpochV2: 1,
      sessionAttemptNonceV2: Object(),
      expectedScope: scope(),
      tokenProof: stale,
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    expect(denied.authorized, isFalse);
    expect(denied.code, AuthIncarnationDenialCodeV2.generationMismatch);
  });

  test('Chrome rejects unsafe JSON integers and freshness equality', () {
    final integralDouble = token()..['accountLifecycleEpochV2'] = 7.0;
    expect(
      AuthIncarnationTokenProofV2.fromMap(
        integralDouble,
      ).accountLifecycleEpochV2,
      7,
    );
    final unsafeToken = Map<String, Object?>.from(
      jsonDecode(
            '{"authIncarnationSchemaVersionV2":2,'
            '"authProjectIdV2":"demo-hoopsconnect",'
            '"authTenantIdV2":null,"authUidV2":"operator",'
            '"accountGenerationV2":"$generation",'
            '"accountLifecycleEpochV2":9007199254740992,'
            '"authTimeSec":1700000001}',
          )
          as Map,
    );
    expect(
      () => AuthIncarnationTokenProofV2.fromMap(unsafeToken),
      throwsFormatException,
    );

    final equalBoundary = token()..['authTimeSec'] = 1700000000;
    final decision = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: 'web-evaluation',
      sessionAttemptEpochV2: 1,
      sessionAttemptNonceV2: Object(),
      expectedScope: scope(),
      tokenProof: equalBoundary,
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    expect(decision.code, AuthIncarnationDenialCodeV2.reauthenticationRequired);
  });

  test('Chrome session gate opens only after proofReady', () {
    final observed = const AuthIncarnationSessionGateV2.signedOut().observeAuth(
      attemptId: 'web-attempt',
      scope: AuthIncarnationScopeV2.fromMap(scope()),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
    );
    final attempt = observed.attempt;
    final decision = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: 'web-attempt',
      sessionAttemptEpochV2: attempt.sessionAttemptEpochV2,
      sessionAttemptNonceV2: attempt.sessionAttemptNonceV2,
      expectedScope: scope(),
      tokenProof: token(),
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    var gate = observed.gate;
    expect(gate.permitsProtectedListeners, isFalse);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: decision.binding!,
      ),
    );
    expect(gate.permitsProtectedListeners, isTrue);
    final switched = gate.startAccountSwitch(
      attemptId: 'next-web-attempt',
      scope: AuthIncarnationScopeV2.fromMap(scope()),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
    );
    gate = switched.gate;
    expect(gate.permitsProtectedListeners, isFalse);
  });

  test('Chrome stale atomic branches cannot share proof', () {
    final observed = const AuthIncarnationSessionGateV2.signedOut().observeAuth(
      attemptId: 'web-initial',
      scope: AuthIncarnationScopeV2.fromMap(scope()),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
    );
    final initialDecision = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: observed.attempt.attemptId,
      sessionAttemptEpochV2: observed.attempt.sessionAttemptEpochV2,
      sessionAttemptNonceV2: observed.attempt.sessionAttemptNonceV2,
      expectedScope: scope(),
      tokenProof: token(),
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    final ready = observed.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: observed.attempt,
        binding: initialDecision.binding!,
      ),
    );
    final branch1 = ready.requireRefresh(attemptId: 'same-branch');
    final branch2 = ready.requireRefresh(attemptId: 'same-branch');
    expect(
      identical(
        branch1.attempt.sessionAttemptNonceV2,
        branch2.attempt.sessionAttemptNonceV2,
      ),
      isFalse,
    );
    final branch1Decision = evaluateAccountAuthorizationV2(
      sessionAttemptIdV2: branch1.attempt.attemptId,
      sessionAttemptEpochV2: branch1.attempt.sessionAttemptEpochV2,
      sessionAttemptNonceV2: branch1.attempt.sessionAttemptNonceV2,
      expectedScope: scope(),
      tokenProof: token(),
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    final staleCompletion = branch2.gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch1.attempt,
        binding: branch1Decision.binding!,
      ),
    );
    expect(
      staleCompletion.state,
      AuthIncarnationSessionStateV2.refreshRequired,
    );
    final gate = staleCompletion.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: branch2.attempt,
        binding: branch1Decision.binding!,
      ),
    );
    expect(gate.state, AuthIncarnationSessionStateV2.blocked);
    expect(gate.permitsProtectedListeners, isFalse);
  });
}
