'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const candidateSource = 'functions/src/domain/association_ownership_ad03_v2.ts';
const candidateRules =
  'functions/test/fixtures/association_ownership_ad03_v2/firestore.rules';
const fixturePath = 'contracts/account_deletion/ad03/ownership_fixtures_v2.json';

const pinnedMergedMainBlobs = Object.freeze({
  // Reviewed callable-only season lifecycle transition; AD03 stays absent.
  'functions/src/index.ts': '32cb4ad58c2fd3409c480d67fefffd13c71cb372',
  'firestore.rules': '74e7c8dc7530ca45e22c2757d7a8dfa5b35da123',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'firebase.json': '200cb8847e8897c13e2f747a8fca44a22e994b9c',
  'functions/src/domain/account_deletion_contract.ts':
    '39a76af7b7fc2b76389cbf31defa0aab60c6e5fe',
  'functions/src/domain/account_lifecycle_ad02_v2.ts':
    '642c86e4cfe3d9b4177918b537b2f614b375f9e8',
  'functions/src/domain/notification_delivery_ad02_v2.ts':
    '03c860037212bef791c0daf222af80f6977bee58',
  'functions/src/domain/official_stats_contract.ts':
    'c6879439091b72088bcef2659490eaff72ddd5f0',
  'functions/src/domain/scoped_authority.ts':
    '4b91340f8932e4998685f854e46e304d9d0375ab',
  'docs/planning/official-stat-account-deletion-addendum.md':
    '214910b936b9a876eff6dd72143ef982e2d15fb8',
  // Reviewed dormant courtside-recovery contract; AD03 stays absent.
  'docs/planning/local-game-journal-v1.md':
    'd63191edfe1de6ec26da2e2029c6260d255e9bcf',
  // Reviewed public deep-link transition: URL strategy only; AD03 stays absent.
  'lib/main.dart': '087bf8e6fa37f3c005d5000821e406018f0cdade',
  'lib/providers/auth_providers.dart': 'db5ea8af4f341f8b5736b8f0814829b0dafbfb73',
  // Reviewed public detail-route mount; AD03 candidate imports stay excluded.
  'lib/app/router/app_router.dart': '8fd2f939210a7ce488747276e179e76d74ea2edb',
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
    const source = fs.readFileSync(current, 'utf8');
    const imports = source.matchAll(
      /(?:import|export)\s+(?:[^'";]+?\s+from\s+)?['"]([^'"]+)['"]/g,
    );
    for (const match of imports) {
      const resolved = resolveTsImport(current, match[1]);
      if (resolved) pending.push(resolved);
    }
  }
  return seen;
}

test('AD03 preserves every pinned production and AD01/AD02/official-stat boundary', () => {
  for (const [relativePath, expected] of Object.entries(pinnedMergedMainBlobs)) {
    assert.equal(gitBlobHash(relativePath), expected, relativePath);
  }
});

test('AD03 source remains absent from the production Functions graph', () => {
  const graph = transitiveTsDependencies('functions/src/index.ts');
  assert.equal(graph.has(path.join(repositoryRoot, candidateSource)), false);
  const reachable = [...graph].map((file) => fs.readFileSync(file, 'utf8')).join('\n');
  assert.doesNotMatch(reachable, /association_ownership_ad03_v2/);
});

test('candidate contains no live handler, provider mutation, owner bootstrap, IAM, or V1 bridge', () => {
  const source = read(candidateSource);
  for (const forbidden of [
    /from ["']firebase-admin/,
    /from ["']firebase-functions/,
    /onCall\s*\(/,
    /onRequest\s*\(/,
    /onDocument(?:Created|Updated|Written|Deleted)\s*\(/,
    /beforeUser(?:Created|SignedIn)\s*\(/,
    /\.deleteUser\s*\(/,
    /\.updateUser\s*\(/,
    /setCustomUserClaims\s*\(/,
    /setIamPolicy\s*\(/i,
    /deleteProject\s*\(/i,
    /export (?:async )?function [^{\n]*bootstrap/i,
    /accountGenerationHashV1/,
    /authCreatedAt/,
    /metadata\.creationTime/,
  ]) {
    assert.doesNotMatch(source, forbidden);
  }
  assert.match(source, /ASSOCIATION_OWNERSHIP_AD03_ACTIVATION_ALLOWED_V2\s*=\s*false/);
  assert.match(source, /productionCustodyActivationReadyV2[\s\S]*return false/);
});

test('candidate Rules are emulator-only and every raw ownership surface is denied', () => {
  const firebase = JSON.parse(read('firebase.json'));
  assert.notEqual(firebase.firestore.rules, candidateRules);
  const rules = read(candidateRules);
  assert.match(rules, /TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const collection of [
    'associationOwnershipV2Root',
    'associationOwnershipV2Tenants',
    'recipientEligibilityV2Root',
    'recipientEligibilityV2Tenants',
  ]) {
    assert.match(rules, new RegExp(collection));
  }
  assert.doesNotMatch(read('firestore.rules'), /associationOwnershipV2/);
});

test('fixture keeps production custody, activation, bootstrap, IAM, and closure closed', () => {
  const fixture = JSON.parse(read(fixturePath));
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.productionCustodyConfigured, false);
  assert.equal(fixture.productionOwnerBootstrapImplemented, false);
  assert.equal(fixture.firebaseIamMutationAllowed, false);
  assert.equal(fixture.associationClosureOwnedByAd03, false);
  assert.equal(fixture.activationGates.G3, false);
  assert.equal(fixture.activationGates.G4, false);
  assert.equal(fixture.deferredOwners.privacyEpochAndPublicProjectionCustody, 'AD06');
  assert.equal(fixture.deferredOwners.encryptedLocalJournalQuarantine, 'AD07');
  assert.equal(fixture.testCustodyPolicy.configurationClassV2, 'testFixture');
  assert.equal(fixture.testCustodyPolicy.decisionStateV2, 'testOnly');
  assert.equal(fixture.unresolvedProductionCustodyPolicy.decisionStateV2, 'unresolved');
  assert.equal(fixture.unresolvedProductionCustodyPolicy.namedOperatorRefV2, null);
});

test('security scripts add AD03 without replacing earlier coverage', () => {
  const scripts = JSON.parse(read('functions/package.json')).scripts;
  assert.match(scripts['test:contracts:no-build'], /association_ownership_ad03_v2\.test\.js/);
  assert.match(
    scripts['test:contracts:no-build'],
    /association_ownership_ad03_v2_dormancy\.test\.js/,
  );
  assert.match(
    scripts['test:security:no-build'],
    /test:association-custody-ad03-v2:rules/,
  );
  for (const prior of [
    'test:auth-incarnation-v2:rules',
    'test:account-lifecycle-ad02-v2:no-build',
    'test:account-lifecycle-ad02-v2:rules',
  ]) {
    assert.match(scripts['test:security:no-build'], new RegExp(prior.replaceAll(':', '\\:')));
  }
});
