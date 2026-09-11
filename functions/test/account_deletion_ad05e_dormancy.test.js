'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad05_fcm_preferences_records.ts',
  'functions/src/account_deletion/ad05_fcm_preferences.ts',
];
const candidateRules =
  'functions/test/fixtures/account_deletion_ad05e/firestore.rules';
const fixturePath =
  'contracts/account_deletion/ad05e/fcm_preferences_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  'functions/src/index.ts': '04347ea48ff46cdc6564489b682c22c4495c2df4',
  'firebase.json': 'ce8dc404b218493d2cb1ee6fae159b36f408bab3',
  'firestore.rules': '263d865c407e3ac2f6da1b04b4968db2404975be',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'functions/src/account_deletion/ad05_records.ts':
    'dfc83138cf1a4e7cb306f7332417c46316eddf1e',
  'functions/src/account_deletion/ad05_inventory.ts':
    '414250fb21be1f1af7f23dba3ebd3705788c6339',
  'functions/src/account_deletion/ad05_account_shared_workflow.ts':
    '1812ca802a24f0d775b82c4e9a1c22fde1765007',
  'functions/src/account_deletion/ad05_storage_media.ts':
    'cba7b56f6e7433da2ada813d88199063ce739c41',
  'contracts/account_deletion/ad05/adapter_fixtures_v1.json':
    'acf87c1345bafbaf2387be54e55922e7f7257b40',
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
      /(?:import|export)\s+(?:[^'\";]+?\s+from\s+)?['\"]([^'\"]+)['\"]/g,
    )) {
      const resolved = resolveTsImport(current, match[1]);
      if (resolved) pending.push(resolved);
    }
  }
  return seen;
}

test('AD05-E preserves production and every frozen predecessor surface', () => {
  for (const [relativePath, hash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), hash, relativePath);
  }
});

test('AD05-E stays transitively unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const source of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, source)), false, source);
  }
});

test('candidate cannot export handlers, call providers, or mutate data', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from [\"']firebase-admin/, /from [\"']firebase-functions/,
    /firebase-admin\/messaging/, /getMessaging\s*\(/,
    /sendEachForMulticast\s*\(/, /onCall\s*\(/, /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /onSchedule\s*\(/, /\.delete\s*\(/, /\.set\s*\(/,
    /\.update\s*\(/, /fetch\s*\(/,
  ]) assert.doesNotMatch(source, forbidden);
  for (const flag of [
    'ACTIVATION_ALLOWED', 'PRODUCTION_EXPORT_ALLOWED',
    'TERMINAL_ADAPTER_ALLOWED', 'PROVIDER_REVOCATION_ALLOWED',
    'DELIVERY_RECALL_ALLOWED', 'LIVE_SUPPRESSION_ALLOWED',
    'DEVICE_CLEARING_ALLOWED',
  ]) assert.match(source, new RegExp(`AD05E_${flag}_V1\\s*=\\s*false`));
});

test('fixture and deny-all Rules remain dormant and unconfigured', () => {
  const fixture = JSON.parse(read(fixturePath));
  for (const key of [
    'activationAllowed', 'productionExportAllowed', 'terminalAdapterAllowed',
    'providerRevocationAllowed', 'deliveryRecallAllowed',
    'liveSuppressionAllowed', 'deviceClearingAllowed',
  ]) assert.equal(fixture[key], false, key);
  assert.equal(fixture.syntheticEvidenceOnly, true);
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  assert.doesNotMatch(read('firestore.rules'),
    /candidateAd05eFcmPreferencesV1/);
});

test('security scripts add AD05-E without replacing prior gates', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05e\.test\.js/);
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05e_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05e-v1:rules/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05d-v1:rules/);
});
