'use strict';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');
const baselineGitBlobHashes = Object.freeze({
  'functions/src/index.ts': '78ebe0c51a1550132da8201b0f2e7b783260cb38',
  'firestore.rules': '9dc99cf1f7c597dd556898424b2911154abe3fc3',
  'storage.rules': '54d7ba69c6ae42dd1e7556b1e2ca2164a3c18d53',
  'lib/main.dart': 'e362527e198c63d829fd81be72792239625619d5',
  'lib/providers/auth_providers.dart': 'b7513cb1767b0943949ca40976bbd05f4a0effba',
  'lib/app/router/app_router.dart': 'f4e0417b6a0a7d25f1edb4d27be4d0463c3467a4',
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
});
