'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSources = [
  'functions/src/account_deletion/ad05_storage_media_records.ts',
  'functions/src/account_deletion/ad05_storage_media.ts',
];
const candidateFirestoreRules =
  'functions/test/fixtures/account_deletion_ad05d/firestore.rules';
const candidateStorageRules =
  'functions/test/fixtures/account_deletion_ad05d/storage.rules';
const fixturePath =
  'contracts/account_deletion/ad05d/storage_media_fixtures_v1.json';

const pinnedBaseBlobs = Object.freeze({
  'functions/src/index.ts': '78ebe0c51a1550132da8201b0f2e7b783260cb38',
  'firebase.json': 'bffa6ccd0f69f3f39d9be8cdc49941adab02f3dc',
  'firestore.rules': '9dc99cf1f7c597dd556898424b2911154abe3fc3',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'functions/src/account_deletion/ad05_records.ts':
    'dfc83138cf1a4e7cb306f7332417c46316eddf1e',
  'functions/src/account_deletion/ad05_inventory.ts':
    '414250fb21be1f1af7f23dba3ebd3705788c6339',
  'functions/src/account_deletion/ad05_identity_suppression.ts':
    'c888923ac22c9a985e5c8b380a87d1dc53899f77',
  'functions/src/account_deletion/ad05_account_shared_workflow.ts':
    '1812ca802a24f0d775b82c4e9a1c22fde1765007',
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

test('AD05-D preserves production and every frozen predecessor surface', () => {
  for (const [relativePath, hash] of Object.entries(pinnedBaseBlobs)) {
    assert.equal(gitBlobHash(relativePath), hash, relativePath);
  }
});

test('AD05-D remains transitively unreachable from production Functions', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  for (const relativePath of candidateSources) {
    assert.equal(graph.has(path.join(repositoryRoot, relativePath)), false,
      relativePath);
  }
});

test('candidate cannot export handlers or perform provider and network calls', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /from [\"']firebase-admin/, /from [\"']firebase-functions/,
    /@google-cloud\/storage/, /onCall\s*\(/, /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /onSchedule\s*\(/, /\.delete\s*\(/, /\.save\s*\(/,
    /https?\.request\s*\(/, /fetch\s*\(/,
  ]) assert.doesNotMatch(source, forbidden);
  assert.match(source,
    /ACCOUNT_DELETION_AD05D_ACTIVATION_ALLOWED_V1\s*=\s*false/);
  assert.match(source,
    /ACCOUNT_DELETION_AD05D_PRODUCTION_EXPORT_ALLOWED_V1\s*=\s*false/);
  assert.match(source,
    /ACCOUNT_DELETION_AD05D_PROVIDER_MUTATION_ALLOWED_V1\s*=\s*false/);
});

test('fixture and deny-all Rules remain dormant and unconfigured', () => {
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.providerMutationAllowed, false);
  assert.equal(fixture.syntheticEvidenceOnly, true);
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateFirestoreRules);
  assert.notEqual(firebase.storage.rules, candidateStorageRules);
  assert.doesNotMatch(read('firestore.rules'), /candidateAd05dMediaEvidenceV1/);
  assert.doesNotMatch(read('storage.rules'), /candidate-ad05d/);
});

test('security scripts include AD05-D without replacing prior gates', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05d\.test\.js/);
  assert.match(scripts['test:contracts:no-build'],
    /account_deletion_ad05d_dormancy\.test\.js/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05d-v1:rules/);
  assert.match(scripts['test:security:no-build'],
    /test:account-deletion-ad05c-v1:rules/);
});
