'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {assertFails, initializeTestEnvironment} =
  require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');

const rules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05e/firestore.rules'), 'utf8');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {rules},
  });
});
test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all AD05-E private records deny every client', async () => {
  for (const context of [
    testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'}),
  ]) {
    const db = context.firestore();
    for (const pathValue of [
      'accountDeletionJobsV1/job-a/ad05ManifestsV1/manifest-a',
      'candidateAd05eFcmEvidenceV1/evidence-a',
      'candidateAd05eFcmPreferencesV1/job-a/authoritiesV1/source-a',
      'candidateAd05eFcmPreferencesV1/job-a/recordsV1/suppression-a',
      'candidateAd05eFcmPreferencesV1/job-a/receiptsV1/receipt-a',
    ]) {
      await assertFails(getDoc(doc(db, pathValue)));
      await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
    }
  }
});

test('candidate Rules carry no production activation path', () => {
  assert.doesNotMatch(rules, /allow\s+(read|write)[^;]*:\s*if\s+true/);
  assert.equal(JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../package.json'), 'utf8')).scripts.deploy,
  'firebase deploy --only functions');
});
