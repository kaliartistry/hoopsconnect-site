'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad05_records.ts',
  'functions/src/account_deletion/ad05_inventory.ts',
  'functions/src/account_deletion/ad05_effects.ts',
  'functions/src/account_deletion/ad05_adapters.ts',
];
const candidateRules =
  'functions/test/fixtures/account_deletion_ad05_v1/firestore.rules';
const fixturePath = 'contracts/account_deletion/ad05/adapter_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  'functions/src/index.ts': '78ebe0c51a1550132da8201b0f2e7b783260cb38',
  'firebase.json': 'bffa6ccd0f69f3f39d9be8cdc49941adab02f3dc',
  'firestore.rules': '9dc99cf1f7c597dd556898424b2911154abe3fc3',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'functions/src/domain/account_deletion_contract.ts':
    '39a76af7b7fc2b76389cbf31defa0aab60c6e5fe',
  'functions/src/domain/auth_incarnation_v2.ts':
    '497923d51d8f8c49533ec5a5c2b1e12607acbbbc',
  'functions/src/domain/account_lifecycle_ad02_v2.ts':
    '642c86e4cfe3d9b4177918b537b2f614b375f9e8',
  'functions/src/domain/association_ownership_ad03_v2.ts':
    '97bc474e3b7b283e9e36d3b7eefe7b76eda9e454',
  'functions/src/account_deletion/ad04_records.ts':
    '1c21e888e8934d014921346a9cdef81fb379c5f1',
  'functions/src/account_deletion/ad04_coordinator.ts':
    'fe7aa2d2460db2dcdecc8ce87a58d9c19c76b700',
  'functions/src/account_deletion/ad04_worker.ts':
    'abd57f57ae7b6953f67a8899a53e9ce91180e84c',
  'functions/src/account_deletion/ad04_reconciliation.ts':
    '33bd57a06ce8ed58bc097cd54d49dff54d0cca0e',
  'contracts/account_deletion/v1/retention_policy_registry.json':
    'e23a115d3788710b1473cb5f4a9d1bd5a86a8229',
});

function read(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath), 'utf8');
}

function gitBlobHash(relativePath) {
  const content = fs.readFileSync(path.join(repositoryRoot, relativePath));
  return createHash('sha1')
    .update(Buffer.from(`blob ${content.byteLength}\0`, 'utf8'))
    .update(content)
    .digest('hex');
}

function resolveTsImport(importer, specifier) {
  if (!specifier.startsWith('.')) return null;
  const base = path.resolve(path.dirname(importer), specifier);
  for (const candidate of [`${base}.ts`, path.join(base, 'index.ts')]) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function transitiveTsDependencies(relativeRoot) {
  const pending = [path.join(repositoryRoot, relativeRoot)];
  const seen = new Set();
  while (pending.length > 0) {
    const current = pending.pop();
    if (seen.has(current)) continue;
    seen.add(current);
    for (const match of fs.readFileSync(current, 'utf8').matchAll(
      /(?:import|export)\s+(?:[^'";]+?\s+from\s+)?['"]([^'"]+)['"]/g,
    )) {
      const resolved = resolveTsImport(current, match[1]);
      if (resolved) pending.push(resolved);
    }
  }
  return seen;
}

test('AD05 preserves exact production, configuration, Rules, AD01, AD02, AD03, and AD04 blobs', () => {
  for (const [relativePath, hash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), hash, relativePath);
  }
});

test('complete AD05 graph remains unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const relativePath of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, relativePath)), false, relativePath);
  }
  const reachable = [...graph].map((file) => fs.readFileSync(file, 'utf8')).join('\n');
  assert.doesNotMatch(reachable, /account_deletion\/ad05_/);
});

test('candidate sources have no live handlers, Firebase SDK, network, provider mutation, or activation flag', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from ["']firebase-admin/, /from ["']firebase-functions/, /onCall\s*\(/,
    /onRequest\s*\(/, /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /onSchedule\s*\(/, /\.deleteUser\s*\(/, /\.updateUser\s*\(/,
    /revokeRefreshTokens\s*\(/, /setCustomUserClaims\s*\(/,
    /https?\.request\s*\(/, /fetch\s*\(/,
  ]) assert.doesNotMatch(source, forbidden);
  assert.match(source, /ACCOUNT_DELETION_AD05_ACTIVATION_ALLOWED_V1\s*=\s*false/);
  assert.match(source, /ACCOUNT_DELETION_AD05_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/);
});

test('AD01 through AD05 flags and the checked-in normative policy all remain closed', () => {
  const source = [
    read('functions/src/domain/account_lifecycle_ad02_v2.ts'),
    read('functions/src/domain/association_ownership_ad03_v2.ts'),
    read('functions/src/account_deletion/ad04_records.ts'),
    read('functions/src/account_deletion/ad04_reconciliation.ts'),
    ...candidateSources.map(read),
  ].join('\n');
  for (const pattern of [
    /ACCOUNT_LIFECYCLE_AD02_ACTIVATION_ALLOWED_V2\s*=\s*false/,
    /ASSOCIATION_OWNERSHIP_AD03_ACTIVATION_ALLOWED_V2\s*=\s*false/,
    /ACCOUNT_DELETION_AD04_ACTIVATION_ALLOWED_V1\s*=\s*false/,
    /ACCOUNT_DELETION_AD04_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/,
    /ACCOUNT_DELETION_AD04_AUTH_ON_DELETE_EXPORT_ALLOWED_V1\s*=\s*false/,
    /ACCOUNT_DELETION_AD04_SCHEDULED_SWEEPER_EXPORT_ALLOWED_V1\s*=\s*false/,
    /ACCOUNT_DELETION_AD05_ACTIVATION_ALLOWED_V1\s*=\s*false/,
    /ACCOUNT_DELETION_AD05_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/,
  ]) assert.match(source, pattern);
  const policy = JSON.parse(read('contracts/account_deletion/v1/retention_policy_registry.json'));
  assert.equal(policy.policyVersion, null);
  assert.equal(policy.activationApproved, false);
  assert.equal(policy.decisions.length, 27);
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.deepEqual(fixture.receiptOutcomesV1,
    ['mutated', 'notApplicableVerified']);
  assert.deepEqual(fixture.completionEvidenceV1, {
    manifestExactBound: true, canonicalManifestCreateOnceRequired: true,
    receiptManifestBound: true, receiptSetBound: true,
    independentSourceRequired: true, postCommitFreshnessRequired: true,
  });
  assert.deepEqual(fixture.activationObligationsV1, {
    concreteSchemaClassifiersApproved: false,
    registeredIndependentVerifiersApproved: false,
    authoritativeCommitVersionEvidenceApproved: false,
    postCommitScanCausalityApproved: false,
  });
  assert.equal(fixture.testOnlySyntheticApprovedPolicy.testOnlySyntheticV1, true);
});

test('test-only deny-all Rules are not production Rules and enumerate all AD05 private record types', () => {
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  const rules = read(candidateRules);
  assert.match(rules, /ACCOUNT_DELETION_AD05_V1_TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const collection of [
    'ad05ManifestsV1', 'ad05ItemReceiptsV1', 'ad05ContinuationsV1',
  ]) assert.match(rules, new RegExp(collection));
  assert.doesNotMatch(read('firestore.rules'),
    /ad05ManifestsV1|ad05ItemReceiptsV1|ad05ContinuationsV1/);
});

test('security scripts add AD05 without replacing earlier gates', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'], /account_deletion_ad05_v1\.test\.js/);
  assert.match(scripts['test:contracts:no-build'], /account_deletion_ad05_v1_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'], /test:account-deletion-ad05-v1:rules/);
  for (const prior of [
    'test:auth-incarnation-v2:rules', 'test:account-lifecycle-ad02-v2:no-build',
    'test:account-lifecycle-ad02-v2:rules', 'test:association-custody-ad03-v2:rules',
    'test:account-deletion-ad04-v1:rules',
  ]) assert.match(scripts['test:security:no-build'],
    new RegExp(prior.replaceAll(':', '\\:')));
});
