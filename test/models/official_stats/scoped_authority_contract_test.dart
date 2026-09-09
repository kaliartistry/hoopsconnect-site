import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/scoped_authority_contract.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'contracts/official_stats/v2/authority_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  Map<String, Object?> scope(String kind) => Map<String, Object?>.from(
    (fixture['scopes'] as Map<String, dynamic>)[kind] as Map<String, dynamic>,
  );

  Map<String, Object?> materializeGrant(
    Map<String, dynamic> vector, {
    bool? hydrate,
  }) {
    final data = <String, Object?>{
      ...Map<String, Object?>.from(
        fixture['grantBase'] as Map<String, dynamic>,
      ),
      ...Map<String, Object?>.from(
        vector['patch'] as Map<String, dynamic>? ?? const {},
      ),
    };
    final shouldHydrate = hydrate ?? vector['doNotHydrateTime'] != true;
    if (shouldHydrate) {
      data['effectiveFrom'] = Timestamp.fromDate(
        DateTime.parse(data['effectiveFrom']! as String),
      );
      data['effectiveTo'] = data['effectiveTo'] == null
          ? null
          : Timestamp.fromDate(DateTime.parse(data['effectiveTo']! as String));
    }
    return data;
  }

  AuthorityControlContract controlFrom(String key, List<Object?> accepted) =>
      AuthorityControlContract.fromMap({
        ...Map<String, Object?>.from(fixture[key] as Map<String, dynamic>),
        'acceptedCalculatorVersions': accepted,
      });

  Map<String, Object?> materializeControlVector(Map<String, dynamic> vector) {
    final origin = vector['origin'] as String;
    final data = <String, Object?>{
      ...Map<String, Object?>.from(
        fixture[origin == 'association'
                ? 'associationControlBase'
                : 'seasonControlBase']
            as Map<String, dynamic>,
      ),
      ...Map<String, Object?>.from(
        vector['patch'] as Map<String, dynamic>? ?? const {},
      ),
    };
    for (final key in vector['removeKeys'] as List? ?? const []) {
      data.remove(key);
    }
    return data;
  }

  test('shared fixture drives exact grant shapes, keys, and containment', () {
    expect(fixture['fixtureVersion'], 4);
    expect(fixture['safeIntegerMax'], maxJavaScriptSafeInteger);
    for (final raw in fixture['grantVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      final contract = ScopedGrantContract.fromMap(materializeGrant(vector));
      expect(
        contract.isDescriptivelyValid,
        vector['expectedShape'],
        reason: '${vector['name']} shape',
      );
      expect(
        contract.deterministicKey,
        vector['expectedKey'],
        reason: '${vector['name']} key',
      );
      expect(
        contract.matchesScopeDescription(scope(vector['target'] as String)),
        vector['expectedMatchesTarget'],
        reason: '${vector['name']} target',
      );
    }
  });

  test(
    'shared malformed-control vectors preserve raw key presence and type',
    () {
      for (final raw in fixture['controlShapeVectors'] as List) {
        final vector = raw as Map<String, dynamic>;
        final origin = vector['origin'] == 'association'
            ? AuthorityAccessOrigin.association
            : AuthorityAccessOrigin.season;
        final control = AuthorityControlContract.fromMap(
          materializeControlVector(vector),
        );
        expect(
          control.validFor(
            origin: origin,
            scope: scope(vector['origin'] as String),
          ),
          vector['expectedValid'],
          reason: vector['name'] as String,
        );
      }
    },
  );

  test('shared fixture drives one exact envelope map representation', () {
    for (final raw in fixture['envelopeVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      final origin = vector['origin'] == 'association'
          ? AuthorityAccessOrigin.association
          : AuthorityAccessOrigin.season;
      final baseKey = origin == AuthorityAccessOrigin.association
          ? 'associationEnvelopeBase'
          : 'seasonEnvelopeBase';
      final data = <String, Object?>{
        ...Map<String, Object?>.from(fixture[baseKey] as Map<String, dynamic>),
        ...Map<String, Object?>.from(
          vector['patch'] as Map<String, dynamic>? ?? const {},
        ),
      };
      final contract = AccessEnvelopeContract.fromMap(
        data,
        origin: origin,
        uid: 'operator',
        scope: scope(vector['origin'] as String),
      );
      expect(
        contract.isDescriptivelyValid,
        vector['expectedValid'],
        reason: vector['name'] as String,
      );
    }
  });

  test('shared numeric and ID counterexamples align with TypeScript', () {
    for (final raw in fixture['counterVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      expect(
        validPositiveAuthorityCounter(vector['value']),
        vector['expectedValid'],
        reason: vector['name'] as String,
      );
      final direct = ScopedGrantContract(
        grantId: 'grant-direct',
        capability: 'players.manage',
        scopeKind: AuthorityScopeKind.association,
        associationId: 'jba',
        status: 'active',
        membershipVersion: vector['value'] as int,
        effectiveFrom: DateTime.utc(2026),
        effectiveTo: null,
      );
      expect(
        direct.isDescriptivelyValid,
        vector['expectedValid'],
        reason: '${vector['name']} direct grant',
      );
    }
    for (final raw in fixture['calculatorIdVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      expect(
        validAuthorityId(vector['value']),
        vector['expectedValid'],
        reason: vector['name'] as String,
      );
    }
    for (final raw in fixture['teamEntrySetVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      expect(
        validAuthorityTeamEntryIds(vector['value']),
        vector['expectedValid'],
        reason: vector['name'] as String,
      );
    }
  });

  test('shared action table requires exact missing-null-extra-free scopes', () {
    expect(
      authorityActionScopes.length,
      (fixture['actionContracts'] as List).length,
    );
    for (final raw in fixture['actionContracts'] as List) {
      final contract = raw as Map<String, dynamic>;
      final capability = contract['capability'] as String;
      final validScope = scope(contract['scope'] as String);
      expect(
        validActionScope(capability, validScope),
        isTrue,
        reason: capability,
      );
      for (final key in validScope.keys) {
        final missing = {...validScope}..remove(key);
        expect(validActionScope(capability, missing), isFalse);
        expect(
          validActionScope(capability, {...validScope, key: null}),
          isFalse,
        );
      }
      expect(
        validActionScope(capability, {...validScope, 'extra': 'x'}),
        isFalse,
      );
    }
  });

  test('shared calculator vectors align map and direct control paths', () {
    for (final raw in fixture['compatibilityVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      final associationAccepted = List<Object?>.from(
        vector['associationAccepted'] as List,
      );
      final seasonAccepted = List<Object?>.from(
        vector['seasonAccepted'] as List,
      );
      final association = controlFrom(
        'associationControlBase',
        associationAccepted,
      );
      final season = controlFrom('seasonControlBase', seasonAccepted);
      final versions = <String, Object?>{
        ...Map<String, Object?>.from(
          fixture['versionsWithoutCalculator'] as Map<String, dynamic>,
        ),
        if (vector['omitCalculator'] != true)
          'calculatorVersion': vector['calculatorVersion'],
      };
      final gate = CompatibilityGateContract(
        associationControl: association,
        seasonControl: season,
      );
      expect(
        gate.accepts(
          scope: scope('season'),
          lowerThanAssociation: true,
          calculatorRequired: vector['required'] as bool,
          versions: versions,
        ),
        vector['expectedAccepts'],
        reason: vector['name'] as String,
      );

      final directAssociation = AuthorityControlContract(
        authorityMode: AuthorityMode.v2,
        dataSchemaVersion: 2,
        associationId: 'jba',
        minimumAuthorizationSchemaVersion: 2,
        minimumDomainSchemaVersion: 2,
        minimumCommandSchemaVersion: 2,
        acceptedCalculatorVersions: associationAccepted,
        controlVersion: 2,
      );
      final directSeason = AuthorityControlContract(
        authorityMode: AuthorityMode.v2,
        dataSchemaVersion: 2,
        associationId: 'jba',
        competitionId: 'nbl',
        seasonId: 's2026',
        minimumAuthorizationSchemaVersion: 2,
        minimumDomainSchemaVersion: 2,
        minimumCommandSchemaVersion: 2,
        acceptedCalculatorVersions: seasonAccepted,
        controlVersion: 7,
      );
      expect(
        CompatibilityGateContract(
          associationControl: directAssociation,
          seasonControl: directSeason,
        ).accepts(
          scope: scope('season'),
          lowerThanAssociation: true,
          calculatorRequired: vector['required'] as bool,
          versions: versions,
        ),
        vector['expectedAccepts'],
        reason: '${vector['name']} direct controls',
      );
    }
  });

  test(
    'direct controls cannot bypass semantic shape or counter validation',
    () {
      for (final invalid in [
        AuthorityControlContract(
          authorityMode: AuthorityMode.v2,
          dataSchemaVersion: 2,
          associationId: 'jba',
          minimumAuthorizationSchemaVersion: 2,
          minimumDomainSchemaVersion: 2,
          minimumCommandSchemaVersion: 2,
          acceptedCalculatorVersions: const ['calc-v1', 'calc-v1'],
          controlVersion: maxJavaScriptSafeInteger + 1,
        ),
        const AuthorityControlContract(
          authorityMode: AuthorityMode.v2,
          dataSchemaVersion: 2,
          associationId: 'jba',
          competitionId: 'nbl',
          minimumAuthorizationSchemaVersion: 2,
          minimumDomainSchemaVersion: 2,
          minimumCommandSchemaVersion: 2,
          acceptedCalculatorVersions: ['calc-v1'],
          controlVersion: 2,
        ),
        const AuthorityControlContract(
          authorityMode: AuthorityMode.v2,
          dataSchemaVersion: 2,
          associationId: 'jba',
          minimumAuthorizationSchemaVersion: 2,
          minimumDomainSchemaVersion: 2,
          minimumCommandSchemaVersion: 2,
          acceptedCalculatorVersions: [null],
          controlVersion: 2,
        ),
      ]) {
        expect(
          invalid.validFor(
            origin: AuthorityAccessOrigin.association,
            scope: scope('association'),
          ),
          isFalse,
        );
      }
    },
  );

  test('shared calculator allowlist bound is exact from zero through four', () {
    for (final raw in fixture['calculatorAllowlistVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      final control = controlFrom(
        'associationControlBase',
        List<Object?>.from(vector['value'] as List),
      );
      expect(
        control.validFor(
          origin: AuthorityAccessOrigin.association,
          scope: scope('association'),
        ),
        vector['expectedValid'],
        reason: vector['name'] as String,
      );
    }
  });

  test('parsed envelope grants are a detached immutable snapshot', () {
    final original = <String, Object?>{
      'slot': {'grantId': 'one'},
    };
    final data = <String, Object?>{
      ...Map<String, Object?>.from(
        fixture['associationEnvelopeBase'] as Map<String, dynamic>,
      ),
      'grants': original,
    };
    final contract = AccessEnvelopeContract.fromMap(
      data,
      origin: AuthorityAccessOrigin.association,
      uid: 'operator',
      scope: scope('association'),
    );
    original['later'] = {};
    expect(contract.grants.keys, ['slot']);
    expect(() => contract.grants['new'] = {}, throwsUnsupportedError);
  });
}
