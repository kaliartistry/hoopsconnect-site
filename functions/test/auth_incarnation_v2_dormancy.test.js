'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const baselineGitBlobHashes = Object.freeze({
  'functions/src/index.ts': '04347ea48ff46cdc6564489b682c22c4495c2df4',
  'firestore.rules': '263d865c407e3ac2f6da1b04b4968db2404975be',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  // Reviewed public deep-link transition: URL strategy only; V2 stays absent.
  'lib/main.dart': '087bf8e6fa37f3c005d5000821e406018f0cdade',
  'lib/providers/auth_providers.dart': 'db5ea8af4f341f8b5736b8f0814829b0dafbfb73',
  // Reviewed public detail-route mount; V2 candidate imports stay excluded.
  'lib/app/router/app_router.dart': '32e9c991342d9da2d40185b634e3db0285b5200e',
  'firebase.json': 'ce8dc404b218493d2cb1ee6fae159b36f408bab3',
});

function read(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath));
}

function gitBlobHash(content) {
  const prefix = Buffer.from(`blob ${content.byteLength}\0`, 'utf8');
  return createHash('sha1').update(prefix).update(content).digest('hex');
}

test('production exports, live Rules, and client roots match the green-base blobs', () => {
  for (const [relativePath, expectedHash] of Object.entries(baselineGitBlobHashes)) {
    assert.equal(gitBlobHash(read(relativePath)), expectedHash, relativePath);
  }
});

test('firebase deploy configuration references only the unchanged live Rules', () => {
  const firebase = JSON.parse(read('firebase.json').toString('utf8'));
  assert.equal(firebase.firestore.rules, 'firestore.rules');
  assert.equal(firebase.storage.rules, 'storage.rules');
  assert.doesNotMatch(JSON.stringify(firebase), /auth_incarnation_v2/);
});

test('V2 modules are absent from production exports and client roots', () => {
  const roots = [
    'functions/src/index.ts',
    'lib/main.dart',
    'lib/providers/auth_providers.dart',
    'lib/app/router/app_router.dart',
    'lib/services/notification_service.dart',
  ];
  for (const relativePath of roots) {
    assert.doesNotMatch(read(relativePath).toString('utf8'), /auth[_-]incarnation|accountGenerationV2/i);
  }
});

test('dormant server modules contain no issuance transport, Auth hook, claim write, or live writer', () => {
  const source = [
    'functions/src/domain/auth_incarnation_v2.ts',
    'functions/src/domain/auth_incarnation_v2_issuer.ts',
  ].map((relativePath) => read(relativePath).toString('utf8')).join('\n');
  for (const forbidden of [
    /setCustomUserClaims\s*\(/,
    /onCall\s*\(/,
    /onRequest\s*\(/,
    /beforeUserCreated\s*\(/,
    /beforeUserSignedIn\s*\(/,
    /\.create\s*\(/,
    /\.set\s*\(/,
    /\.update\s*\(/,
    /\.delete\s*\(/,
  ]) {
    assert.doesNotMatch(source, forbidden);
  }
});

test('shared fixture and documentation keep activation explicitly closed', () => {
  const fixture = JSON.parse(read(
    'contracts/auth_incarnation/v2/contract_fixtures.json',
  ).toString('utf8'));
  const documentation = read(
    'docs/planning/auth-incarnation-v2-prerequisite.md',
  ).toString('utf8');
  assert.equal(fixture.activationAllowed, false);
  assert.match(documentation, /activationAllowed:\s*false/);
  assert.match(documentation, /Production UID reuse is prohibited/);
  assert.match(documentation, /fence-before-Auth-mutation/);
  assert.match(documentation, /AUTH_INCARNATION_V2_TEST_ONLY_PROJECT=demo-hoopsconnect/);
  for (const candidate of [
    'functions/test/fixtures/auth_incarnation_v2/firestore.rules',
    'functions/test/fixtures/auth_incarnation_v2/storage.rules',
  ]) {
    assert.match(
      read(candidate).toString('utf8'),
      /AUTH_INCARNATION_V2_TEST_ONLY_PROJECT=demo-hoopsconnect/,
    );
  }
  for (const production of ['firestore.rules', 'storage.rules', 'firebase.json']) {
    assert.doesNotMatch(read(production).toString('utf8'), /demo-hoopsconnect/);
  }
});
