'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {assertFails, initializeTestEnvironment} =
  require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');

const rules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05c_v1/firestore.rules',
), 'utf8');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect', firestore: {rules},
  });
});
test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all AD05-C manifests, effects, and candidate sources deny every client', async () => {
  for (const context of [
    testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'}),
  ]) {
    const db = context.firestore();
    for (const pathValue of [
      'accountDeletionJobsV1/job-a/ad05ManifestsV1/manifest-a',
      'accountDeletionJobsV1/job-a/ad05EffectsV1/effect-a',
      'candidateAd05cSources/user_profile',
      'candidateAd05cSources/acknowledgements',
    ]) {
      await assertFails(getDoc(doc(db, pathValue)));
      await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
    }
  }
});

test('fixture is deny-all and carries no production activation path', () => {
  assert.match(rules, /candidateAd05cSources/);
  assert.doesNotMatch(rules, /allow\s+(read|write)[^;]*:\s*if\s+true/);
  assert.equal(JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../package.json'), 'utf8')).scripts.deploy,
  'firebase deploy --only functions');
});
