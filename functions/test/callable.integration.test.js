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
