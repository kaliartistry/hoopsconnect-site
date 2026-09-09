'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {deleteDoc, doc, getDoc, setDoc} = require('firebase/firestore');
const {deleteObject, getBytes, ref: storageRef, uploadBytes} = require('firebase/storage');

const fixture = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, '../../contracts/auth_incarnation/v2/contract_fixtures.json'),
  'utf8',
));
const firestoreRulesPath = path.resolve(
  __dirname,
  'fixtures/auth_incarnation_v2/firestore.rules',
);
const storageRulesPath = path.resolve(
  __dirname,
  'fixtures/auth_incarnation_v2/storage.rules',
);

let testEnv;
const bytes = new Uint8Array([2, 7, 2, 7]);

function claims(patch = {}, removeKeys = []) {
  const token = fixture.tokenProof;
  const result = {
    authIncarnationSchemaVersionV2: token.authIncarnationSchemaVersionV2,
    authProjectIdV2: token.authProjectIdV2,
    authTenantIdV2: token.authTenantIdV2,
    authUidV2: token.authUidV2,
    accountGenerationV2: token.accountGenerationV2,
    accountLifecycleEpochV2: token.accountLifecycleEpochV2,
    auth_time: token.authTimeSec,
    ...patch,
  };
  for (const key of removeKeys) delete result[key];
  return result;
}

function authedFirestore(patch, removeKeys) {
  return testEnv.authenticatedContext('operator', claims(patch, removeKeys)).firestore();
}

function authedStorage(patch, removeKeys) {
  return testEnv.authenticatedContext('operator', claims(patch, removeKeys)).storage();
}

async function seedAuthority(changes = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'accountLifecycleV2/operator'), {
      ...fixture.lifecycle,
      ...(changes.lifecycle || {}),
    });
    await setDoc(doc(db, 'membershipsV2/operator'), changes.replaceMembership || {
      ...fixture.membership,
      ...(changes.membership || {}),
    });
    await setDoc(doc(db, 'storageAuthorizationsV2/operator'), {
      ...fixture.projection,
      ...(changes.projection || {}),
    });
    await setDoc(doc(db, 'protectedRecordsV2/record-1'), {
      ownerUid: 'operator',
      requiredCapability: 'stats.enter',
      value: 'protected',
    });
    await setDoc(doc(db, 'protectedRecordsV2/other-record'), {
      ownerUid: 'other-user',
      requiredCapability: 'stats.enter',
      value: 'other protected',
    });
  });
}

async function seedStorageObject() {
  await assertSucceeds(uploadBytes(
    storageRef(authedStorage(), 'protectedV2/jba/object.bin'),
    bytes,
  ));
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {rules: fs.readFileSync(firestoreRulesPath, 'utf8')},
    storage: {rules: fs.readFileSync(storageRulesPath, 'utf8')},
  });
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedAuthority();
});

test.after(async () => testEnv.cleanup());

test('candidate Firestore grants only an all-exact active V2 tuple', async () => {
  const db = authedFirestore();
  await assertSucceeds(getDoc(doc(db, 'protectedRecordsV2/record-1')));
  await assertSucceeds(setDoc(doc(db, 'protectedRecordsV2/owned'), {
    ownerUid: 'operator',
    requiredCapability: 'stats.enter',
    value: 'created',
  }));
  await assertSucceeds(setDoc(doc(db, 'protectedRecordsV2/record-1'), {
    ownerUid: 'operator',
    requiredCapability: 'stats.enter',
    value: 'updated',
  }));
  await assertFails(setDoc(doc(db, 'protectedRecordsV2/other-record'), {
    ownerUid: 'operator',
    requiredCapability: 'stats.enter',
    value: 'stolen',
  }));
  await assertSucceeds(deleteDoc(doc(db, 'protectedRecordsV2/record-1')));
});

test('candidate Firestore denies missing, malformed, V1-only, and mismatched token proof', async () => {
  const cases = [
    [claims({}, [
      'authIncarnationSchemaVersionV2', 'authProjectIdV2', 'authTenantIdV2',
      'authUidV2', 'accountGenerationV2', 'accountLifecycleEpochV2',
    ])],
    [{...claims(), accountGenerationV2: 'BAD'}],
    [{...claims(), accountGenerationV2: 'f'.repeat(64)}],
    [{...claims(), accountLifecycleEpochV2: 8}],
    [{...claims(), accountLifecycleEpochV2: -1}],
    [{...claims(), accountLifecycleEpochV2: 7.5}],
    [{...claims(), accountLifecycleEpochV2: '7'}],
    [{...claims(), accountLifecycleEpochV2: 9007199254740992}],
    [{...claims(), authProjectIdV2: 'other-project'}],
    [{...claims(), authTenantIdV2: 'tenant-a'}],
    [{...claims(), authUidV2: 'other-user'}],
  ];
  for (const [tokenClaims] of cases) {
    const db = testEnv.authenticatedContext('operator', tokenClaims).firestore();
    await assertFails(getDoc(doc(db, 'protectedRecordsV2/record-1')));
  }
});

test('candidate Firestore denies lifecycle, membership, freshness, and legacy-adoption attacks', async () => {
  const variants = [
    {lifecycle: {lifecycleStateV2: 'pending'}},
    {lifecycle: {lifecycleStateV2: 'deleting'}},
    {lifecycle: {accountGenerationV2: 'f'.repeat(64)}},
    {lifecycle: {accountLifecycleEpochV2: 8}},
    {membership: {membershipStatusV2: 'suspended'}},
    {membership: {accountGenerationV2: 'f'.repeat(64)}},
    {membership: {accountLifecycleEpochV2: 8}},
    {membership: {authTenantIdV2: 'tenant-a'}},
    {membership: {capabilities: ['stats.enter', 'stats.enter']}},
    {membership: {capabilities: ['stats.enter', 7]}},
    {membership: {capabilities: ['stats.enter', 'unknown.grant']}},
    {replaceMembership: {
      authorizationSchemaVersion: 1,
      role: 'superAdmin',
      status: 'active',
      associationId: 'jba',
      capabilities: ['stats.enter'],
    }},
  ];
  for (const variant of variants) {
    await seedAuthority(variant);
    await assertFails(getDoc(doc(authedFirestore(), 'protectedRecordsV2/record-1')));
  }
  await seedAuthority();
  await assertFails(getDoc(doc(
    authedFirestore({auth_time: fixture.lifecycle.reauthAfterSecV2}),
    'protectedRecordsV2/record-1',
  )));
});

test('candidate authority documents are never client writable or directly readable', async () => {
  const db = authedFirestore();
  for (const target of [
    'accountLifecycleV2/operator',
    'membershipsV2/operator',
    'storageAuthorizationsV2/operator',
  ]) {
    await assertFails(getDoc(doc(db, target)));
    await assertFails(setDoc(doc(db, target), {owned: true}));
  }
});

test('candidate Storage grants only exact V2 token/projection binding', async () => {
  await seedStorageObject();
  await assertSucceeds(getBytes(storageRef(
    authedStorage(),
    'protectedV2/jba/object.bin',
  )));
  await assertSucceeds(deleteObject(storageRef(
    authedStorage(),
    'protectedV2/jba/object.bin',
  )));
});

test('candidate Storage denies missing, stale, mismatched, inactive, and equality-bound proof', async () => {
  await seedStorageObject();
  const tokenCases = [
    claims({}, ['accountGenerationV2']),
    {...claims(), accountGenerationV2: 'f'.repeat(64)},
    {...claims(), accountLifecycleEpochV2: 8},
    {...claims(), authTenantIdV2: 'tenant-a'},
    {...claims(), auth_time: fixture.projection.reauthAfterSecV2},
  ];
  for (const tokenClaims of tokenCases) {
    const storage = testEnv.authenticatedContext('operator', tokenClaims).storage();
    await assertFails(getBytes(storageRef(storage, 'protectedV2/jba/object.bin')));
  }
  for (const projection of [
    {accountGenerationV2: 'f'.repeat(64)},
    {accountLifecycleEpochV2: 6},
    {lifecycleStateV2: 'deleted'},
    {membershipStatusV2: 'revoked'},
    {authProjectIdV2: 'other-project'},
    {capabilities: ['members.manage']},
    {capabilities: ['association.read', 'unknown.grant']},
  ]) {
    await seedAuthority({projection});
    await assertFails(getBytes(storageRef(
      authedStorage(),
      'protectedV2/jba/object.bin',
    )));
  }
});

test('candidate rule read budgets keep token checks read-free and authority reads fixed', () => {
  const firestoreRules = fs.readFileSync(firestoreRulesPath, 'utf8');
  const storageRules = fs.readFileSync(storageRulesPath, 'utf8');
  const firestoreToken = firestoreRules.match(/TOKEN_V2_BEGIN([\s\S]*?)TOKEN_V2_END/)[1];
  const firestoreActive = firestoreRules.match(/ACTIVE_V2_BEGIN([\s\S]*?)ACTIVE_V2_END/)[1];
  const storageToken = storageRules.match(/TOKEN_V2_BEGIN([\s\S]*?)TOKEN_V2_END/)[1];
  const storageActive = storageRules.match(/ACTIVE_V2_BEGIN([\s\S]*?)ACTIVE_V2_END/)[1];
  assert.doesNotMatch(firestoreToken, /\b(?:get|exists)\s*\(/);
  assert.doesNotMatch(storageToken, /\b(?:get|exists)\s*\(/);
  assert.equal((firestoreActive.match(/\bget\s*\(/g) || []).length, 2);
  assert.equal((storageActive.match(/\bfirestore\.get\s*\(/g) || []).length, 1);
});
