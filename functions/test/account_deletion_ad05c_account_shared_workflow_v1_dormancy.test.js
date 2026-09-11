'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad05_account_shared_workflow_records.ts',
  'functions/src/account_deletion/ad05_account_shared_workflow.ts',
];
const candidateRules =
  'functions/test/fixtures/account_deletion_ad05c_v1/firestore.rules';
const fixturePath =
  'contracts/account_deletion/ad05/account_shared_workflow_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  'functions/src/index.ts': '04347ea48ff46cdc6564489b682c22c4495c2df4',
  'firebase.json': 'ce8dc404b218493d2cb1ee6fae159b36f408bab3',
  'firestore.rules': 'fae96dfa751599739cdf45cf865a9e84c42f3098',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'functions/src/account_deletion/ad05_identity_suppression_records.ts':
    '6624d768d8910060c792605b1330ca757f05fcf8',
  'functions/src/account_deletion/ad05_identity_suppression.ts':
    'c888923ac22c9a985e5c8b380a87d1dc53899f77',
  'contracts/account_deletion/ad05/identity_suppression_fixtures_v1.json':
    'bc4db27c978f00babc1692376975a5eb1f0ef71b',
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

test('AD05-C preserves production and the frozen AD05-B base', () => {
  for (const [relativePath, hash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), hash, relativePath);
  }
});

test('AD05-C remains transitively unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const relativePath of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, relativePath)), false,
      relativePath);
  }
});

test('candidate cannot export handlers or perform provider and network writes', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from [\"']firebase-admin/, /from [\"']firebase-functions/,
    /onCall\s*\(/, /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /onSchedule\s*\(/, /\.deleteUser\s*\(/,
    /setCustomUserClaims\s*\(/, /https?\.request\s*\(/, /fetch\s*\(/,
  ]) assert.doesNotMatch(source, forbidden);
  assert.match(source,
    /ACCOUNT_DELETION_AD05C_ACTIVATION_ALLOWED_V1\s*=\s*false/);
  assert.match(source,
    /ACCOUNT_DELETION_AD05C_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/);
});

test('fixture and candidate Rules remain dormant and unconfigured', () => {
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.normativePolicy.policyVersion, null);
  assert.equal(fixture.normativePolicy.mutationsAllowed, false);
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  assert.doesNotMatch(read('firestore.rules'), /candidateAd05cSources/);
});

test('security scripts include AD05-C without replacing prior gates', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05c_account_shared_workflow_v1\.test\.js/);
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05c_account_shared_workflow_v1_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05c-v1:rules/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05b-v1:rules/);
});
