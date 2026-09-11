'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad05_identity_suppression_records.ts',
  'functions/src/account_deletion/ad05_identity_suppression.ts',
];
const candidateRules =
  'functions/test/fixtures/account_deletion_ad05b_v1/firestore.rules';
const fixturePath =
  'contracts/account_deletion/ad05/identity_suppression_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  // Reviewed callable-only season lifecycle transition; AD05-B stays absent.
  'functions/src/index.ts': '32cb4ad58c2fd3409c480d67fefffd13c71cb372',
  'firebase.json': '200cb8847e8897c13e2f747a8fca44a22e994b9c',
  'firestore.rules': '74e7c8dc7530ca45e22c2757d7a8dfa5b35da123',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'functions/src/domain/official_stats_contract.ts':
    'c6879439091b72088bcef2659490eaff72ddd5f0',
  'contracts/official_stats/v2/contract_fixtures.json':
    '31eb905b49fbb645f4df0b65ce11251e829ed83f',
  'docs/planning/official-stat-contract.md':
    '5f0322fb0aa601d59ac34b9575314777e792c00e',
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
  'functions/src/account_deletion/ad05_records.ts':
    'dfc83138cf1a4e7cb306f7332417c46316eddf1e',
  'functions/src/account_deletion/ad05_inventory.ts':
    '414250fb21be1f1af7f23dba3ebd3705788c6339',
  'functions/src/account_deletion/ad05_effects.ts':
    '56a9b4d8d53ba51277635acc6f7fa504129fba91',
  'functions/src/account_deletion/ad05_adapters.ts':
    '920d7d2cd1397cbe25eb3a5cccdacccfffc019f0',
  'contracts/account_deletion/ad05/adapter_fixtures_v1.json':
    'acf87c1345bafbaf2387be54e55922e7f7257b40',
  'contracts/account_deletion/v1/retention_policy_registry.json':
    'e23a115d3788710b1473cb5f4a9d1bd5a86a8229',
  'docs/account-deletion-contract.md':
    'a8652ac77dfdecb30dcab468b6b77b1a2104809b',
  'docs/account-deletion-retention-policy.md':
    'ef61b8eadce958894fa1e342c6d3912f6c7b4d3d',
  'docs/account-deletion-release-gates.md':
    '1549e48922d1e43dc7281496c810a8c603be5a46',
  'docs/account-deletion-ad02-v2-boundary-matrix.md':
    '2b63223ba9d453e28ef1a99ca55422bcd11f224a',
  'docs/account-deletion-ad03-v2-custody-control.md':
    'b4bdbd05372ad8f0e850069b3f2e434b1df238a1',
  'docs/account-deletion-ad04-v1-lifecycle-cleanup.md':
    '4b6a64196eaaaba3aa5deafc4e5c5e7b62e5d9a4',
  'docs/account-deletion-ad05-v1-adapters.md':
    '6d932610b7819ba7a8c86c1c38668f7023934fb6',
  'docs/planning/official-stat-account-deletion-addendum.md':
    '214910b936b9a876eff6dd72143ef982e2d15fb8',
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

test('AD05-B preserves exact production, official-stat, AD01-AD05-A blobs', () => {
  for (const [relativePath, hash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), hash, relativePath);
  }
});

test('AD05-B remains transitively unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const relativePath of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, relativePath)), false,
      relativePath);
  }
  const reachable = [...graph].map((file) => read(path.relative(repositoryRoot,
    file))).join('\n');
  assert.doesNotMatch(reachable, /ad05_identity_suppression/);
});

test('candidate has no handlers, Firebase/provider/network mutation, epoch or release writer', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from ["']firebase-admin/, /from ["']firebase-functions/, /onCall\s*\(/,
    /onRequest\s*\(/, /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /onSchedule\s*\(/, /\.deleteUser\s*\(/, /setCustomUserClaims\s*\(/,
    /https?\.request\s*\(/, /fetch\s*\(/, /privacyEpoch\s*\+\+/, /releaseHead\s*=/,
  ]) assert.doesNotMatch(source, forbidden);
  assert.match(source,
    /ACCOUNT_DELETION_AD05B_ACTIVATION_ALLOWED_V1\s*=\s*false/);
  assert.match(source,
    /ACCOUNT_DELETION_AD05B_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/);
});

test('AD05-A family registry remains T/R-only and normative AD01 policy stays null', () => {
  const ad05 = JSON.parse(read(
    'contracts/account_deletion/ad05/adapter_fixtures_v1.json'));
  for (const row of ad05.adapterRows) {
    assert.equal(row.mechanicalSupportV1,
      row.protectionFamilyV1 === 'T' ? 'transactionalDocument' :
        row.protectionFamilyV1 === 'R' ? 'evidenceOnly' : 'unsupported');
  }
  const policy = JSON.parse(read(
    'contracts/account_deletion/v1/retention_policy_registry.json'));
  assert.equal(policy.policyVersion, null);
  assert.equal(policy.activationApproved, false);
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.normativePolicy.policyVersion, null);
  assert.equal(fixture.normativePolicy.mutationsAllowed, false);
  assert.equal(fixture.mechanicalSupportV1.person_identity_evidence,
    'unsupportedVersionedMaterial');
  assert.equal(fixture.mechanicalSupportV1.public_projections_exports,
    'suppressionPrerequisiteOnlyExternalStillUnsupported');
});

test('AD05-B Rules are deny-all, enumerate private records, and remain unconfigured', () => {
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  const rules = read(candidateRules);
  assert.match(rules,
    /ACCOUNT_DELETION_AD05B_V1_TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const collection of [
    'ad05IdentityReferenceManifestsV1', 'ad05IdentitySuppressionsV1',
  ]) assert.match(rules, new RegExp(collection));
  assert.doesNotMatch(read('firestore.rules'),
    /ad05IdentityReferenceManifestsV1|ad05IdentitySuppressionsV1/);
});

test('security scripts add AD05-B without replacing earlier account-deletion gates', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05b_identity_suppression_v1\.test\.js/);
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05b_identity_suppression_v1_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05b-v1:rules/);
  for (const prior of [
    'test:association-custody-ad03-v2:rules',
    'test:account-deletion-ad04-v1:rules',
    'test:account-deletion-ad05-v1:rules',
  ]) assert.match(scripts['test:security:no-build'],
    new RegExp(prior.replaceAll(':', '\\:')));
});
