'use strict';

const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {randomBytes} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const contract = require('../lib/domain/auth_incarnation_v2');
const issuerContract = require('../lib/domain/auth_incarnation_v2_issuer');

const fixture = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, '../../contracts/auth_incarnation/v2/contract_fixtures.json'),
  'utf8',
));

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function applyVector(vector, includeProjection = false) {
  const material = {
    sessionAttemptIdV2: fixture.sessionAttemptIdV2,
    sessionAttemptEpochV2: fixture.sessionAttemptEpochV2,
    expectedScope: clone(fixture.scope),
    tokenProof: clone(fixture.tokenProof),
    lifecycle: clone(fixture.lifecycle),
    membership: clone(fixture.membership),
    projection: clone(fixture.projection),
    requiredCapability: vector.requiredCapability || 'stats.enter',
  };
  if (vector.target) {
    if (vector.omitTarget) {
      material[vector.target] = null;
    } else {
      for (const key of vector.removeKeys || []) delete material[vector.target][key];
      Object.assign(material[vector.target], vector.patch || {});
    }
  }
  return includeProjection ? {
    sessionAttemptIdV2: material.sessionAttemptIdV2,
    sessionAttemptEpochV2: material.sessionAttemptEpochV2,
    expectedScope: material.expectedScope,
    tokenProof: material.tokenProof,
    projection: material.projection,
    requiredCapability: material.requiredCapability,
  } : {
    sessionAttemptIdV2: material.sessionAttemptIdV2,
    sessionAttemptEpochV2: material.sessionAttemptEpochV2,
    expectedScope: material.expectedScope,
    tokenProof: material.tokenProof,
    lifecycle: material.lifecycle,
    membership: material.membership,
    requiredCapability: material.requiredCapability,
  };
}

test('shared fixture is dormant V2 and preserves the JavaScript-safe counter boundary', () => {
  assert.equal(fixture.fixtureVersion, 1);
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.schemaVersion, contract.AUTH_INCARNATION_SCHEMA_VERSION_V2);
  assert.equal(fixture.maxSafeInteger, contract.MAX_SAFE_AUTHORITY_INTEGER_V2);
  assert.equal(contract.ACCOUNT_GENERATION_CLAIM_V2, 'accountGenerationV2');
  assert.equal(contract.ACCOUNT_LIFECYCLE_EPOCH_CLAIM_V2, 'accountLifecycleEpochV2');
});

test('account evaluator follows every shared fail-closed vector without mutation', () => {
  for (const vector of fixture.accountAuthorizationVectors) {
    const input = applyVector(vector);
    const before = clone(input);
    const decision = contract.evaluateAccountAuthorizationV2(input);
    assert.equal(decision.authorized, vector.expectedAuthorized, vector.name);
    if (!decision.authorized) assert.equal(decision.code, vector.expectedCode, vector.name);
    assert.deepEqual(input, before, `${vector.name} mutated its input`);
  }
});

test('Storage evaluator follows every shared fail-closed vector without mutation', () => {
  for (const vector of fixture.storageAuthorizationVectors) {
    const input = applyVector(vector, true);
    const before = clone(input);
    const decision = contract.evaluateStorageAuthorizationV2(input);
    assert.equal(decision.authorized, vector.expectedAuthorized, vector.name);
    if (!decision.authorized) assert.equal(decision.code, vector.expectedCode, vector.name);
    assert.deepEqual(input, before, `${vector.name} mutated its input`);
  }
});

test('generation parser accepts only 32-byte lowercase hexadecimal values', () => {
  assert.doesNotThrow(() => contract.parseAuthIncarnationTokenProofV2(fixture.tokenProof));
  for (const invalidGeneration of fixture.invalidGenerations) {
    assert.throws(() => contract.parseAuthIncarnationTokenProofV2({
      ...fixture.tokenProof,
      accountGenerationV2: invalidGeneration,
    }));
    assert.throws(() => contract.parsePendingAuthIncarnationBindingV2({
      ...fixture.pendingBinding,
      accountGenerationV2: invalidGeneration,
    }));
  }
});

test('all runtimes use finite mathematically integral safe counters', () => {
  for (const accepted of fixture.numericSemantics.accepted) {
    assert.doesNotThrow(() => contract.parseAuthIncarnationTokenProofV2({
      ...fixture.tokenProof,
      accountLifecycleEpochV2: accepted,
    }));
  }
  const invalidCounters = [
    ...fixture.numericSemantics.rejected,
    '7', Number.NaN, Number.POSITIVE_INFINITY,
  ];
  for (const invalidCounter of invalidCounters) {
    assert.throws(() => contract.parseAuthIncarnationTokenProofV2({
      ...fixture.tokenProof,
      accountLifecycleEpochV2: invalidCounter,
    }));
    assert.throws(() => contract.parseAuthIncarnationTokenProofV2({
      ...fixture.tokenProof,
      authTimeSec: invalidCounter,
    }));
    assert.throws(() => contract.parseAccountLifecycleAuthorityV2({
      ...fixture.lifecycle,
      reauthAfterSecV2: invalidCounter,
    }));
  }
  assert.doesNotThrow(() => contract.parseAuthIncarnationTokenProofV2({
    ...fixture.tokenProof,
    accountLifecycleEpochV2: contract.MAX_SAFE_AUTHORITY_INTEGER_V2,
  }));
});

test('validated binding is the only input accepted by the projection builder', () => {
  assert.throws(() => contract.buildStorageAuthorizationProjectionV2({
    scope: fixture.scope,
    accountGenerationV2: fixture.tokenProof.accountGenerationV2,
    accountLifecycleEpochV2: 7,
    reauthAfterSecV2: 1700000000,
    associationId: 'jba',
    capabilities: ['stats.enter'],
  }));
  const decision = contract.evaluateAccountAuthorizationV2(applyVector(
    fixture.accountAuthorizationVectors[0],
  ));
  assert.equal(decision.authorized, true);
  const projection = contract.buildStorageAuthorizationProjectionV2(decision.binding);
  assert.deepEqual(projection, fixture.projection);
  assert.equal(Object.isFrozen(projection), true);
});

test('validated bindings are scoped to one exact session attempt', () => {
  const input = applyVector(fixture.accountAuthorizationVectors[0]);
  input.sessionAttemptIdV2 = 'attempt-exact-a';
  input.sessionAttemptEpochV2 = 17;
  const decision = contract.evaluateAccountAuthorizationV2(input);
  assert.equal(decision.authorized, true);
  assert.equal(decision.binding.sessionAttemptIdV2, 'attempt-exact-a');
  assert.equal(decision.binding.sessionAttemptEpochV2, 17);

  for (const sessionAttemptIdV2 of ['', 'bad\u0000attempt', 'x'.repeat(129)]) {
    const denied = contract.evaluateAccountAuthorizationV2({
      ...applyVector(fixture.accountAuthorizationVectors[0]),
      sessionAttemptIdV2,
    });
    assert.deepEqual(denied, {authorized: false, code: 'invalid_token_proof'});
  }

  for (const sessionAttemptEpochV2 of [0, -1, 1.5, Number.NaN, 9007199254740992]) {
    const denied = contract.evaluateAccountAuthorizationV2({
      ...applyVector(fixture.accountAuthorizationVectors[0]),
      sessionAttemptEpochV2,
    });
    assert.deepEqual(denied, {authorized: false, code: 'invalid_token_proof'});
  }
});

test('Dart external libraries cannot forge bindings or construct allowed decisions', {
  timeout: 120000,
}, () => {
  const repositoryRoot = path.resolve(__dirname, '../..');
  const buildRoot = path.join(repositoryRoot, 'build');
  fs.mkdirSync(buildRoot, {recursive: true});
  const temporary = fs.mkdtempSync(path.join(buildRoot, 'auth-v2-provenance-'));
  try {
    const sourcePath = path.join(temporary, 'forgery.dart');
    fs.writeFileSync(sourcePath, `
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_v2.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';
final class Forged implements ValidatedActiveAuthorityV2 {
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
final class ForgedDecision extends AuthIncarnationAuthorizationDecisionV2 {
  ForgedDecision() : super.denied(AuthIncarnationDenialCodeV2.invalidTokenProof);
  @override
  bool get authorized => true;
}
final class ForgedAttempt implements AuthIncarnationSessionAttemptV2 {
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  StorageAuthorizationProjectionV2.fromValidated(Forged());
  AuthIncarnationAuthorizationDecisionV2.allowed(null as dynamic);
  ForgedDecision();
  AuthIncarnationSessionAttemptV2();
  ForgedAttempt();
}
`);
    const result = spawnSync('dart', ['analyze', sourcePath], {
      cwd: repositoryRoot,
      encoding: 'utf8',
      timeout: 110000,
    });
    const output = `${result.stdout || ''}\n${result.stderr || ''}`;
    assert.equal(result.error, undefined, output);
    assert.notEqual(result.status, 0, 'forged external library unexpectedly analyzed');
    assert.match(output, /ValidatedActiveAuthorityV2/);
    assert.match(output, /AuthIncarnationAuthorizationDecisionV2/);
    assert.match(output, /AuthIncarnationSessionAttemptV2/);
    assert.match(output, /allowed/);
  } finally {
    fs.rmSync(temporary, {recursive: true, force: true});
  }
});

test('default trusted issuer is closed and an injected test fake uses 32 CSPRNG bytes', async () => {
  await assert.rejects(
    issuerContract.unavailableTrustedAccountGenerationIssuerV2.issuePendingBinding({
      scope: fixture.scope,
      reauthAfterSecV2: 1700000000,
    }),
    {name: 'TrustedIssuerUnavailableErrorV2'},
  );

  const fake = {
    async issuePendingBinding(request) {
      const entropy = randomBytes(32);
      assert.equal(entropy.byteLength, 32);
      return issuerContract.validatePendingIssuerResultV2({
        authIncarnationSchemaVersionV2: 2,
        ...request.scope,
        accountGenerationV2: entropy.toString('hex'),
        accountLifecycleEpochV2: 0,
        bindingStateV2: 'pending',
        reauthAfterSecV2: request.reauthAfterSecV2,
      });
    },
  };
  const values = new Set();
  for (let index = 0; index < 32; index += 1) {
    const pending = await fake.issuePendingBinding({
      scope: fixture.scope,
      reauthAfterSecV2: 1700000000,
    });
    assert.match(pending.accountGenerationV2, /^[a-f0-9]{64}$/);
    values.add(pending.accountGenerationV2);
  }
  assert.equal(values.size, 32, 'same UID and timestamp must still receive independent generations');
});

test('scope is exact and null tenant is distinct from a concrete tenant', () => {
  const valid = applyVector(fixture.accountAuthorizationVectors[0]);
  assert.equal(contract.evaluateAccountAuthorizationV2(valid).authorized, true);
  for (const [field, value] of [
    ['authProjectIdV2', 'other-project'],
    ['authTenantIdV2', 'tenant-a'],
    ['authUidV2', 'other-user'],
  ]) {
    const changedExpected = applyVector(fixture.accountAuthorizationVectors[0]);
    changedExpected.expectedScope[field] = value;
    const decision = contract.evaluateAccountAuthorizationV2(changedExpected);
    assert.deepEqual(decision, {authorized: false, code: 'scope_mismatch'});
  }
});

test('scope identifiers are lossless and share the Dart UTF-16 boundary', () => {
  const composed = 'é';
  const decomposed = 'e\u0301';
  assert.notEqual(composed, decomposed);
  assert.doesNotThrow(() => contract.parseAuthIncarnationScopeV2({
    ...fixture.scope,
    authUidV2: composed,
  }));
  assert.doesNotThrow(() => contract.parseAuthIncarnationScopeV2({
    ...fixture.scope,
    authUidV2: decomposed,
  }));
  assert.doesNotThrow(() => contract.parseAuthIncarnationScopeV2({
    ...fixture.scope,
    authUidV2: '😀'.repeat(64),
  }));
  for (const invalidUid of ['', 'bad\u0000uid', '😀'.repeat(65), 'x'.repeat(129)]) {
    assert.throws(() => contract.parseAuthIncarnationScopeV2({
      ...fixture.scope,
      authUidV2: invalidUid,
    }));
  }
});
