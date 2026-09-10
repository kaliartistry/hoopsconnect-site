'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {assertFails, initializeTestEnvironment} =
  require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {deleteObject, getBytes, ref: storageRef, uploadBytes} =
  require('firebase/storage');

const firestoreRules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05d/firestore.rules'), 'utf8');
const storageRules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05d/storage.rules'), 'utf8');

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {rules: firestoreRules},
    storage: {rules: storageRules},
  });
});
test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});
test.after(async () => testEnv.cleanup());

test('all AD05-D Firestore candidate evidence denies every client', async () => {
  for (const context of [
    testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'}),
  ]) {
    const db = context.firestore();
    for (const pathValue of [
      'accountDeletionJobsV1/job-a/ad05ManifestsV1/manifest-a',
      'candidateAd05dMediaEvidenceV1/evidence-a',
    ]) {
      await assertFails(getDoc(doc(db, pathValue)));
      await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
    }
  }
});

test('all AD05-D Storage candidate objects deny every client', async () => {
  const bytes = new Uint8Array([1, 2, 3]);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(storageRef(context.storage(),
      'candidate-ad05d/tenant-a/account-a/file.png'), bytes);
  });
  for (const context of [
    testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'}),
  ]) {
    const object = storageRef(context.storage(),
      'candidate-ad05d/tenant-a/account-a/file.png');
    await assertFails(getBytes(object));
    await assertFails(uploadBytes(object, bytes));
    await assertFails(deleteObject(object));
  }
});

test('candidate Rules carry no production activation path', () => {
  assert.doesNotMatch(firestoreRules,
    /allow\s+(read|write)[^;]*:\s*if\s+true/);
  assert.doesNotMatch(storageRules,
    /allow\s+(read|write)[^;]*:\s*if\s+true/);
  assert.equal(JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../package.json'), 'utf8')).scripts.deploy,
  'firebase deploy --only functions');
});
