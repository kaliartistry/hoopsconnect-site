import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_v2.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'contracts/auth_incarnation/v2/contract_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  dynamic clone(dynamic value) => jsonDecode(jsonEncode(value));

  Map<String, Object?> applyVector(
    Map<String, dynamic> vector, {
    bool storage = false,
  }) {
    final material = <String, Object?>{
      'expectedScope': clone(fixture['scope']),
      'tokenProof': clone(fixture['tokenProof']),
      'lifecycle': clone(fixture['lifecycle']),
      'membership': clone(fixture['membership']),
      'projection': clone(fixture['projection']),
      'requiredCapability':
          vector['requiredCapability'] as String? ?? 'stats.enter',
    };
    final target = vector['target'] as String?;
    if (target != null) {
      if (vector['omitTarget'] == true) {
        material[target] = null;
      } else {
        final targetMap = Map<String, Object?>.from(material[target]! as Map);
        for (final key in vector['removeKeys'] as List? ?? const []) {
          targetMap.remove(key);
        }
        targetMap.addAll(
          Map<String, Object?>.from(vector['patch'] as Map? ?? const {}),
        );
        material[target] = targetMap;
      }
    }
    return storage
        ? {
            'expectedScope': material['expectedScope'],
            'tokenProof': material['tokenProof'],
            'projection': material['projection'],
            'requiredCapability': material['requiredCapability'],
          }
        : {
            'expectedScope': material['expectedScope'],
            'tokenProof': material['tokenProof'],
            'lifecycle': material['lifecycle'],
            'membership': material['membership'],
            'requiredCapability': material['requiredCapability'],
          };
  }

  String wireCode(AuthIncarnationDenialCodeV2 code) => switch (code) {
    AuthIncarnationDenialCodeV2.missingTokenProof => 'missing_token_proof',
    AuthIncarnationDenialCodeV2.invalidTokenProof => 'invalid_token_proof',
    AuthIncarnationDenialCodeV2.invalidLifecycle => 'invalid_lifecycle',
    AuthIncarnationDenialCodeV2.lifecycleInactive => 'lifecycle_inactive',
    AuthIncarnationDenialCodeV2.invalidMembership => 'invalid_membership',
    AuthIncarnationDenialCodeV2.membershipInactive => 'membership_inactive',
    AuthIncarnationDenialCodeV2.invalidProjection => 'invalid_projection',
    AuthIncarnationDenialCodeV2.scopeMismatch => 'scope_mismatch',
    AuthIncarnationDenialCodeV2.generationMismatch => 'generation_mismatch',
    AuthIncarnationDenialCodeV2.epochMismatch => 'epoch_mismatch',
    AuthIncarnationDenialCodeV2.reauthenticationRequired =>
      'reauthentication_required',
    AuthIncarnationDenialCodeV2.capabilityDenied => 'capability_denied',
  };

  test('shared fixture is dormant V2 with exact constants', () {
    expect(fixture['fixtureVersion'], 1);
    expect(fixture['activationAllowed'], isFalse);
    expect(fixture['schemaVersion'], AuthIncarnationV2.schemaVersion);
    expect(fixture['maxSafeInteger'], AuthIncarnationV2.maxSafeInteger);
    expect(AuthIncarnationV2.generationClaim, 'accountGenerationV2');
    expect(AuthIncarnationV2.lifecycleEpochClaim, 'accountLifecycleEpochV2');
  });

  test('Dart account evaluator matches every shared fail-closed vector', () {
    for (final raw in fixture['accountAuthorizationVectors'] as List) {
      final vector = Map<String, dynamic>.from(raw as Map);
      final input = applyVector(vector);
      final decision = evaluateAccountAuthorizationV2(
        expectedScope: input['expectedScope'],
        tokenProof: input['tokenProof'],
        lifecycle: input['lifecycle'],
        membership: input['membership'],
        requiredCapability: input['requiredCapability']! as String,
      );
      expect(
        decision.authorized,
        vector['expectedAuthorized'],
        reason: vector['name'] as String,
      );
      if (!decision.authorized) {
        expect(
          wireCode(decision.code!),
          vector['expectedCode'],
          reason: vector['name'] as String,
        );
      }
    }
  });

  test('Dart Storage evaluator matches every shared fail-closed vector', () {
    for (final raw in fixture['storageAuthorizationVectors'] as List) {
      final vector = Map<String, dynamic>.from(raw as Map);
      final input = applyVector(vector, storage: true);
      final decision = evaluateStorageAuthorizationV2(
        expectedScope: input['expectedScope'],
        tokenProof: input['tokenProof'],
        projection: input['projection'],
        requiredCapability: input['requiredCapability']! as String,
      );
      expect(
        decision.authorized,
        vector['expectedAuthorized'],
        reason: vector['name'] as String,
      );
      if (!decision.authorized) {
        expect(
          wireCode(decision.code!),
          vector['expectedCode'],
          reason: vector['name'] as String,
        );
      }
    }
  });

  test(
    'generation and pending-binding parsers require lowercase 32-byte hex',
    () {
      final token = Map<String, Object?>.from(fixture['tokenProof'] as Map);
      final pending = Map<String, Object?>.from(
        fixture['pendingBinding'] as Map,
      );
      expect(AuthIncarnationTokenProofV2.fromMap(token).toMap(), token);
      expect(PendingAuthIncarnationBindingV2.fromMap(pending).toMap(), pending);
      for (final invalid in fixture['invalidGenerations'] as List) {
        expect(
          () => AuthIncarnationTokenProofV2.fromMap({
            ...token,
            'accountGenerationV2': invalid,
          }),
          throwsFormatException,
        );
        expect(
          () => PendingAuthIncarnationBindingV2.fromMap({
            ...pending,
            'accountGenerationV2': invalid,
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('all runtimes use finite mathematically integral safe counters', () {
    final token = Map<String, Object?>.from(fixture['tokenProof'] as Map);
    final lifecycle = Map<String, Object?>.from(fixture['lifecycle'] as Map);
    for (final accepted
        in Map<String, dynamic>.from(
              fixture['numericSemantics'] as Map,
            )['accepted']
            as List) {
      final parsed = AuthIncarnationTokenProofV2.fromMap({
        ...token,
        'accountLifecycleEpochV2': accepted,
      });
      expect(parsed.accountLifecycleEpochV2, accepted == 0 ? 0 : accepted);
      expect(parsed.accountLifecycleEpochV2, isA<int>());
    }
    final invalidCounters = <Object?>[
      ...Map<String, dynamic>.from(
            fixture['numericSemantics'] as Map,
          )['rejected']
          as List,
      '7',
      double.nan,
      double.infinity,
    ];
    for (final invalid in invalidCounters) {
      expect(
        () => AuthIncarnationTokenProofV2.fromMap({
          ...token,
          'accountLifecycleEpochV2': invalid,
        }),
        throwsFormatException,
      );
      expect(
        () => AuthIncarnationTokenProofV2.fromMap({
          ...token,
          'authTimeSec': invalid,
        }),
        throwsFormatException,
      );
      expect(
        () => AccountLifecycleAuthorityV2.fromMap({
          ...lifecycle,
          'reauthAfterSecV2': invalid,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => AuthIncarnationTokenProofV2.fromMap({
        ...token,
        'accountLifecycleEpochV2': AuthIncarnationV2.maxSafeInteger,
      }),
      returnsNormally,
    );
  });

  test('projection builder accepts only an evaluator-produced binding', () {
    final input = applyVector(
      Map<String, dynamic>.from(
        (fixture['accountAuthorizationVectors'] as List).first as Map,
      ),
    );
    final decision = evaluateAccountAuthorizationV2(
      expectedScope: input['expectedScope'],
      tokenProof: input['tokenProof'],
      lifecycle: input['lifecycle'],
      membership: input['membership'],
      requiredCapability: input['requiredCapability']! as String,
    );
    expect(decision.authorized, isTrue);
    expect(
      StorageAuthorizationProjectionV2.fromValidated(decision.binding!).toMap(),
      fixture['projection'],
    );
  });

  test('scope identifiers are lossless and use a UTF-16 boundary', () {
    const composed = 'é';
    const decomposed = 'e\u0301';
    expect(composed, isNot(decomposed));
    final emoji64 = List.filled(64, '😀').join();
    final emoji65 = List.filled(65, '😀').join();
    for (final validUid in [composed, decomposed, emoji64]) {
      expect(
        () => AuthIncarnationScopeV2.fromMap({
          ...Map<String, Object?>.from(fixture['scope'] as Map),
          'authUidV2': validUid,
        }),
        returnsNormally,
      );
    }
    for (final invalidUid in ['', 'bad\u0000uid', emoji65, 'x' * 129]) {
      expect(
        () => AuthIncarnationScopeV2.fromMap({
          ...Map<String, Object?>.from(fixture['scope'] as Map),
          'authUidV2': invalidUid,
        }),
        throwsFormatException,
      );
    }
  });
}
