'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad04_records.ts',
  'functions/src/account_deletion/ad04_coordinator.ts',
  'functions/src/account_deletion/ad04_worker.ts',
  'functions/src/account_deletion/ad04_reconciliation.ts',
];
const candidateRules =
  'functions/test/fixtures/account_deletion_ad04_v1/firestore.rules';
const fixturePath =
  'contracts/account_deletion/ad04/lifecycle_cleanup_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  'functions/src/index.ts': '04347ea48ff46cdc6564489b682c22c4495c2df4',
  'firestore.rules': 'fae96dfa751599739cdf45cf865a9e84c42f3098',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'firebase.json': 'ce8dc404b218493d2cb1ee6fae159b36f408bab3',
  'functions/src/domain/account_deletion_contract.ts':
    '39a76af7b7fc2b76389cbf31defa0aab60c6e5fe',
  'functions/src/domain/account_lifecycle_ad02_v2.ts':
    '642c86e4cfe3d9b4177918b537b2f614b375f9e8',
  'functions/src/domain/notification_delivery_ad02_v2.ts':
    '03c860037212bef791c0daf222af80f6977bee58',
  'functions/src/domain/association_ownership_ad03_v2.ts':
    '97bc474e3b7b283e9e36d3b7eefe7b76eda9e454',
  'functions/src/domain/official_stats_contract.ts':
    'c6879439091b72088bcef2659490eaff72ddd5f0',
  'contracts/account_deletion/v1/contract_fixtures.json':
    '8c27142d55b68b115e422d3f60cd1da6a701e5c8',
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
    const imports = fs.readFileSync(current, 'utf8').matchAll(
      /(?:import|export)\s+(?:[^'";]+?\s+from\s+)?['"]([^'"]+)['"]/g,
    );
    for (const match of imports) {
      const resolved = resolveTsImport(current, match[1]);
      if (resolved) pending.push(resolved);
    }
  }
  return seen;
}

test('AD04 preserves the exact base production, AD01, AD02, and AD03 blobs', () => {
  for (const [relativePath, expectedHash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), expectedHash, relativePath);
  }
});

test('the complete AD04 module graph remains unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const relativePath of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, relativePath)), false, relativePath);
  }
  const reachable = [...graph].map((file) => fs.readFileSync(file, 'utf8')).join('\n');
  assert.doesNotMatch(reachable, /account_deletion\/ad04_/);
});

test('candidate source has no Firebase SDK, live handler, network, or direct provider mutation', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from ["']firebase-admin/,
    /from ["']firebase-functions/,
    /onCall\s*\(/,
    /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /beforeUser(?:Created|SignedIn)\s*\(/,
    /onSchedule\s*\(/,
    /\.deleteUser\s*\(/,
    /\.updateUser\s*\(/,
    /setCustomUserClaims\s*\(/,
    /https?\.request\s*\(/,
    /fetch\s*\(/,
  ]) assert.doesNotMatch(source, forbidden);
  assert.match(source, /ACCOUNT_DELETION_AD04_ACTIVATION_ALLOWED_V1\s*=\s*false/);
  assert.match(source, /ACCOUNT_DELETION_AD04_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/);
  assert.match(source,
    /ACCOUNT_DELETION_AD04_SHARED_AD02_UID_PATH_CODEC_PROVEN_V1\s*=\s*false/);
  assert.match(source, /ACCOUNT_DELETION_AD04_AUTH_ON_DELETE_EXPORT_ALLOWED_V1\s*=\s*false/);
  assert.match(source, /ACCOUNT_DELETION_AD04_SCHEDULED_SWEEPER_EXPORT_ALLOWED_V1\s*=\s*false/);
});

test('candidate Rules are emulator-only and deny every raw AD04 collection', () => {
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  const rules = read(candidateRules);
  assert.match(rules, /ACCOUNT_DELETION_AD04_V1_TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const collectionName of [
    'accountDeletionIntentsV1',
    'accountDeletionJobsV1',
    'accountDeletionStatusV1',
    'accountDeletionStatusControlsV1',
    'accountDeletionReceiptsV1',
    'accountDeletionRevocationMaterialV1',
    'accountDeletionProviderEventsV1',
    'accountDeletionAlertsV1',
  ]) assert.match(rules, new RegExp(collectionName));
  assert.doesNotMatch(read('firestore.rules'), /accountDeletionJobsV1|accountDeletionIntentsV1/);
});

test('fixture keeps activation, exports, TTL deletion, and production provider use closed', () => {
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.schemaVersion, 1);
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.authGenerationConditionalMutationProven, false);
  assert.equal(fixture.sharedAd02UidPathCodecIntegrationProven, false);
  assert.equal(fixture.authOnDeleteExportAllowed, false);
  assert.equal(fixture.scheduledSweeperExportAllowed, false);
  assert.equal(fixture.completionRule.authDeletionDependsOnAdapterCompletion, false);
  assert.equal(fixture.completionRule.unfinishedWorkHasTtl, false);
  assert.equal(fixture.architectureSha256,
    '9a9d0150244fc124bbc8ab1697fba177a3c862de8b7099c5c684d02ed8537832');
  assert.equal(fixture.exactBaseCommit, 'fc46cecb4243acc248606cc2d83081843befa030');
});

test('security scripts add AD04 without replacing any earlier gate', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'], /account_deletion_ad04_v1\.test\.js/);
  assert.match(scripts['test:contracts:no-build'], /account_deletion_ad04_v1_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'], /test:account-deletion-ad04-v1:rules/);
  for (const prior of [
    'test:auth-incarnation-v2:rules',
    'test:account-lifecycle-ad02-v2:no-build',
    'test:account-lifecycle-ad02-v2:rules',
    'test:association-custody-ad03-v2:rules',
  ]) assert.match(scripts['test:security:no-build'],
    new RegExp(prior.replaceAll(':', '\\:')));
});
