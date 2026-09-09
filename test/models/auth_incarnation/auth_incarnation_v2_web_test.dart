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
      expectedScope: scope(),
      tokenProof: equalBoundary,
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    expect(decision.code, AuthIncarnationDenialCodeV2.reauthenticationRequired);
  });

  test('Chrome session gate opens only after proofReady', () {
    final attempt = AuthIncarnationSessionAttemptV2(
      attemptId: 'web-attempt',
      scope: AuthIncarnationScopeV2.fromMap(scope()),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
    );
    final decision = evaluateAccountAuthorizationV2(
      expectedScope: scope(),
      tokenProof: token(),
      lifecycle: lifecycle(),
      membership: membership(),
      requiredCapability: 'stats.enter',
    );
    var gate = const AuthIncarnationSessionGateV2.signedOut();
    gate = gate.transition(AuthIncarnationSessionEventV2.authObserved(attempt));
    expect(gate.permitsProtectedListeners, isFalse);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: decision.binding!,
      ),
    );
    expect(gate.permitsProtectedListeners, isTrue);
    gate = gate.transition(
      AuthIncarnationSessionEventV2.accountSwitchStarted(
        AuthIncarnationSessionAttemptV2(
          attemptId: 'next-web-attempt',
          scope: AuthIncarnationScopeV2.fromMap(scope()),
          accountGenerationV2: generation,
          accountLifecycleEpochV2: 7,
        ),
      ),
    );
    expect(gate.permitsProtectedListeners, isFalse);
  });
}
