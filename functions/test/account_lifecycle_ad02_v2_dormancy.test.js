'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const baselineGitBlobHashes = Object.freeze({
  // Reviewed callable-only season lifecycle transition; AD02 stays absent.
  'functions/src/index.ts': '32cb4ad58c2fd3409c480d67fefffd13c71cb372',
  'firestore.rules': '74e7c8dc7530ca45e22c2757d7a8dfa5b35da123',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'firebase.json': '200cb8847e8897c13e2f747a8fca44a22e994b9c',
  // Reviewed public deep-link transition: URL strategy only; AD02 stays absent.
  'lib/main.dart': '087bf8e6fa37f3c005d5000821e406018f0cdade',
  'lib/providers/auth_providers.dart': 'db5ea8af4f341f8b5736b8f0814829b0dafbfb73',
  // Reviewed public detail-route mount; AD02 candidate imports stay excluded.
  'lib/app/router/app_router.dart': '8fd2f939210a7ce488747276e179e76d74ea2edb',
  'lib/services/notification_service.dart': 'd17c7c10ca2620d97adf56fae0408cec0647fba8',
  'lib/services/repositories/auth_repository.dart': '533f850d12b4b7d50428149f5c2af0c816717c0f',
  'lib/core/constants/firestore_paths.dart': '59571aec275caa239e4fc3bb6ffa259c1c12dcb7',
});
const candidateSources = [
  'functions/src/domain/account_lifecycle_ad02_v2.ts',
  'functions/src/domain/notification_delivery_ad02_v2.ts',
  'lib/models/account_deletion/account_lifecycle_ad02_v2.dart',
  'lib/services/account_lifecycle_candidate_adapter_v2.dart',
];

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

function tsDependencies(file) {
  const source = fs.readFileSync(file, 'utf8');
  const dependencies = [];
  const pattern = /(?:import|export)\s+(?:[^'";]+?\s+from\s+)?['"]([^'"]+)['"]/g;
  for (const match of source.matchAll(pattern)) {
    const resolved = resolveTsImport(file, match[1]);
    if (resolved) dependencies.push(resolved);
  }
  return dependencies;
}

function resolveDartImport(importer, specifier) {
  if (specifier.startsWith('package:hoops_connect/')) {
    return path.join(repositoryRoot, 'lib', specifier.slice('package:hoops_connect/'.length));
  }
  if (specifier.startsWith('.')) return path.resolve(path.dirname(importer), specifier);
  return null;
}

function dartDependencies(file) {
  const source = fs.readFileSync(file, 'utf8');
  const dependencies = [];
  for (const match of source.matchAll(/(?:import|export|part)\s+['"]([^'"]+)['"]/g)) {
    const resolved = resolveDartImport(file, match[1]);
    if (resolved && fs.existsSync(resolved)) dependencies.push(resolved);
  }
  return dependencies;
}

function transitiveDependencies(roots, dependencies) {
  const seen = new Set();
  const pending = roots.map((root) => path.join(repositoryRoot, root));
  while (pending.length > 0) {
    const current = pending.pop();
    if (seen.has(current)) continue;
    seen.add(current);
    pending.push(...dependencies(current));
  }
  return seen;
}

test('all pinned production surfaces remain byte-identical to exact merged main', () => {
  for (const [relativePath, expected] of Object.entries(baselineGitBlobHashes)) {
    assert.equal(gitBlobHash(relativePath), expected, relativePath);
  }
});

test('candidate modules are absent from the transitive production import graphs', () => {
  const functionsGraph = transitiveDependencies(
    ['functions/src/index.ts'],
    tsDependencies,
  );
  const clientGraph = transitiveDependencies([
    'lib/main.dart',
    'lib/providers/auth_providers.dart',
    'lib/app/router/app_router.dart',
    'lib/services/notification_service.dart',
  ], dartDependencies);
  for (const relativePath of candidateSources) {
    const absolute = path.join(repositoryRoot, relativePath);
    assert.equal(functionsGraph.has(absolute), false, relativePath);
    assert.equal(clientGraph.has(absolute), false, relativePath);
  }
  const reachableSource = [...functionsGraph, ...clientGraph]
    .map((file) => fs.readFileSync(file, 'utf8'))
    .join('\n');
  assert.doesNotMatch(
    reachableSource,
    /account_lifecycle_ad02_v2|notification_delivery_ad02_v2|account_lifecycle_candidate_adapter_v2/,
  );
});

test('security scripts retain merged V2 coverage and add AD02 without replacement', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  for (const required of [
    'test:contracts:no-build',
    'test:functions:no-build',
    'test:notifications',
    'test:callable',
    'test:rules',
    'test:storage',
    'test:auth-incarnation-v2:rules',
    'test:account-lifecycle-ad02-v2:no-build',
    'test:account-lifecycle-ad02-v2:rules',
  ]) {
    assert.match(scripts['test:security:no-build'], new RegExp(required.replaceAll(':', '\\:')));
  }
  assert.match(
    scripts['test:contracts:no-build'],
    /auth_incarnation_v2\.test\.js.*auth_incarnation_v2_dormancy\.test\.js/,
  );
});

test('candidate code contains no issuer, production handler, V1 bridge, or Auth mutation', () => {
  const source = candidateSources.map(read).join('\n');
  for (const forbidden of [
    /setCustomUserClaims\s*\(/,
    /\.deleteUser\s*\(/,
    /beforeUserCreated\s*\(/,
    /beforeUserSignedIn\s*\(/,
    /onCall\s*\(/,
    /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /accountGenerationHashV1/,
    /authCreatedAt/,
    /metadata\.creationTime/,
    /\bgenerationHash\b/,
    /['"]memberships\//,
    /['"]accountLifecycle\//,
  ]) {
    assert.doesNotMatch(source, forbidden);
  }
});

test('candidate Rules are emulator-only and live deploy config remains unchanged', () => {
  const firebase = JSON.parse(read('firebase.json'));
  const firestoreCandidate =
    'functions/test/fixtures/account_lifecycle_ad02_v2/firestore.rules';
  const storageCandidate =
    'functions/test/fixtures/account_lifecycle_ad02_v2/storage.rules';
  assert.notEqual(firebase.firestore.rules, firestoreCandidate);
  assert.notEqual(firebase.storage.rules, storageCandidate);
  assert.match(read(firestoreCandidate), /TEST_ONLY_PROJECT=demo-hoopsconnect/);
  assert.match(read(storageCandidate), /TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const production of ['firestore.rules', 'storage.rules', 'firebase.json']) {
    assert.doesNotMatch(read(production), /account_lifecycle_ad02|accountGenerationV2/i);
  }
});

test('every activation declaration remains false and AD01 fingerprints are untouched', () => {
  const fixture = JSON.parse(read(
    'contracts/account_deletion/ad02/lifecycle_fixtures_v2.json',
  ));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.v1Interoperability, 'none');
  assert.match(
    read('functions/src/domain/account_lifecycle_ad02_v2.ts'),
    /ACCOUNT_LIFECYCLE_AD02_ACTIVATION_ALLOWED_V2\s*=\s*false/,
  );
  assert.match(
    read('lib/models/account_deletion/account_lifecycle_ad02_v2.dart'),
    /accountLifecycleAd02ActivationAllowedV2\s*=\s*false/,
  );
  assert.equal(
    gitBlobHash('functions/src/domain/account_deletion_contract.ts'),
    '39a76af7b7fc2b76389cbf31defa0aab60c6e5fe',
  );
  assert.equal(
    gitBlobHash('contracts/account_deletion/v1/contract_fixtures.json'),
    '8c27142d55b68b115e422d3f60cd1da6a701e5c8',
  );
});
