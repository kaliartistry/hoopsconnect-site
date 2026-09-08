'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');
const {initializeApp, deleteApp} = require('firebase/app');
const {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  signOut,
} = require('firebase/auth');
const {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} = require('firebase/functions');

if (admin.apps.length === 0) {
  admin.initializeApp({projectId: 'demo-hoopsconnect'});
}
const adminDb = admin.firestore();
const {capabilitiesForRole} = require('../lib/authorization');
const clientApp = initializeApp({
  projectId: 'demo-hoopsconnect',
  apiKey: 'demo-key',
  appId: 'demo-app',
});
const auth = getAuth(clientApp);
connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
const functions = getFunctions(clientApp);
connectFunctionsEmulator(functions, '127.0.0.1', 5001);

test.before(async () => {
  await adminDb.doc('associations/jba').set({
    name: 'JBA',
    currentSeasonId: 'season-1',
  });
});

test.after(async () => {
  const collections = await adminDb.listCollections();
  await Promise.all(
    collections.map((collection) => adminDb.recursiveDelete(collection)),
  );
  await deleteApp(clientApp);
  await admin.app().delete();
});

test('authenticated callable provisions fan and ignores forged authority', async () => {
  const credential = await createUserWithEmailAndPassword(
    auth,
    'callable-fan@example.com',
    'correct-horse-battery-staple',
  );
  const provision = httpsCallable(functions, 'provisionFanProfile');
  const result = await provision({
    displayName: 'Callable Fan',
    role: 'superAdmin',
    associationId: 'victim',
    capabilities: ['members.manage'],
    authorizationSchemaVersion: 1,
  });
  assert.equal(result.data.role, 'fan');
  assert.equal(result.data.associationId, 'jba');

  const user = (
    await adminDb.doc('users/' + credential.user.uid).get()
  ).data();
  assert.equal(user.role, 'fan');
  assert.equal(user.associationId, 'jba');
  assert.equal(user.email, 'callable-fan@example.com');
});

test('callable inspect omits the bearer and redeem accepts the original client entry on retry', async () => {
  await signOut(auth);
  const rootCredential = await createUserWithEmailAndPassword(
    auth,
    'callable-root@example.com',
    'correct-horse-battery-staple',
  );
  await adminDb.doc('users/' + rootCredential.user.uid).set({
    email: 'callable-root@example.com',
    displayName: 'Root',
    associationId: 'jba',
    role: 'superAdmin',
    authorizationSchemaVersion: 1,
  });
  await adminDb.doc('memberships/' + rootCredential.user.uid).set({
    associationId: 'jba',
    role: 'superAdmin',
    status: 'active',
    capabilities: capabilitiesForRole('superAdmin'),
    authorizationSchemaVersion: 1,
  });

  const createInvite = httpsCallable(functions, 'createPrivilegedInvite');
  const issued = await createInvite({
    role: 'media',
    daysValid: 7,
    operationId: 'callable_create_operation_001',
    authorizationSchemaVersion: 1,
  });
  const rawCode = issued.data.code;
  assert.match(rawCode, /^[A-Za-z0-9_-]{43}$/);

  await signOut(auth);
  const inspect = httpsCallable(functions, 'inspectPrivilegedInvite');
  const inspected = await inspect({code: rawCode, authorizationSchemaVersion: 1});
  assert.equal(inspected.data.inviteId, issued.data.inviteId);
  assert.equal(JSON.stringify(inspected.data).includes(rawCode), false);

  const invitee = await createUserWithEmailAndPassword(
    auth,
    'callable-media@example.com',
    'correct-horse-battery-staple',
  );
  const redeem = httpsCallable(functions, 'redeemPrivilegedInvite');
  const requestData = {
    code: rawCode,
    displayName: 'Callable Media',
    operationId: 'callable_redeem_operation_001',
    authorizationSchemaVersion: 1,
  };
  const first = await redeem(requestData);
  const retry = await redeem(requestData);
  assert.deepEqual(retry.data, first.data);
  assert.equal(
    (await adminDb.doc('memberships/' + invitee.user.uid).get()).get('role'),
    'media',
  );

  for (const collectionName of [
    'inviteCodes',
    'authorizationAudit',
    'authorizationOperationReceipts',
  ]) {
    const snapshot = await adminDb.collection(collectionName).get();
    assert.equal(JSON.stringify(snapshot.docs.map((doc) => doc.data())).includes(rawCode), false);
  }
});
