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

function claims(patch = {}, removeKeys = [], providerTenant = null) {
  const token = fixture.tokenProof;
  const firebase = {sign_in_provider: 'custom', identities: {}};
  if (providerTenant !== null) firebase.tenant = providerTenant;
  const result = {
    authIncarnationSchemaVersionV2: token.authIncarnationSchemaVersionV2,
    authProjectIdV2: token.authProjectIdV2,
    authTenantIdV2: token.authTenantIdV2,
    authUidV2: token.authUidV2,
    accountGenerationV2: token.accountGenerationV2,
    accountLifecycleEpochV2: token.accountLifecycleEpochV2,
    auth_time: token.authTimeSec,
    firebase,
    ...patch,
  };
  for (const key of removeKeys) delete result[key];
  return result;
}

function authedFirestore(tokenClaims = claims(), uid = 'operator') {
  return testEnv.authenticatedContext(uid, tokenClaims).firestore();
}

function authedStorage(tokenClaims = claims(), uid = 'operator') {
  return testEnv.authenticatedContext(uid, tokenClaims).storage();
}

function authorityPaths(tenant, uid = 'operator') {
  if (tenant === null) {
    return {
      lifecycle: `accountLifecycleV2Root/${uid}`,
      membership: `membershipsV2Root/${uid}`,
      projection: `storageAuthorizationsV2Root/${uid}`,
    };
  }
  return {
    lifecycle: `accountLifecycleV2Tenants/${tenant}/users/${uid}`,
    membership: `membershipsV2Tenants/${tenant}/users/${uid}`,
    projection: `storageAuthorizationsV2Tenants/${tenant}/users/${uid}`,
  };
}

async function seedAuthority({
  tenant = null,
  uid = 'operator',
  lifecycle = {},
  membership = {},
  projection = {},
} = {}) {
  const paths = authorityPaths(tenant, uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const scope = {authTenantIdV2: tenant, authUidV2: uid};
    await setDoc(doc(db, paths.lifecycle), {...fixture.lifecycle, ...scope, ...lifecycle});
    await setDoc(doc(db, paths.membership), {...fixture.membership, ...scope, ...membership});
    await setDoc(doc(db, paths.projection), {...fixture.projection, ...scope, ...projection});
  });
}

async function seedProtectedRecords() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'protectedRecordsV2/record-1'), {
      ownerUid: 'operator', associationId: 'jba',
      requiredCapability: 'stats.enter', value: 'protected',
    });
    await setDoc(doc(db, 'protectedRecordsV2/other-record'), {
      ownerUid: 'other-user', associationId: 'jba',
      requiredCapability: 'stats.enter', value: 'other protected',
    });
    await setDoc(doc(db, 'protectedRecordsV2/other-association'), {
      ownerUid: 'operator', associationId: 'other-association',
      requiredCapability: 'stats.enter', value: 'other association',
    });
  });
}

async function seedStorageObject(contents = bytes) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(storageRef(
      context.storage(),
      'protectedV2/jba/object.bin',
    ), contents);
  });
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
  await seedProtectedRecords();
});

test.after(async () => testEnv.cleanup());

test('candidate Firestore grants only owner-and-association-bound operations', async () => {
  const db = authedFirestore();
  await assertSucceeds(getDoc(doc(db, 'protectedRecordsV2/record-1')));
  await assertFails(getDoc(doc(db, 'protectedRecordsV2/other-record')));
  await assertFails(getDoc(doc(db, 'protectedRecordsV2/other-association')));
  await assertSucceeds(setDoc(doc(db, 'protectedRecordsV2/owned'), {
    ownerUid: 'operator', associationId: 'jba',
    requiredCapability: 'stats.enter', value: 'created',
  }));
  await assertFails(setDoc(doc(db, 'protectedRecordsV2/owned-cross-association'), {
    ownerUid: 'operator', associationId: 'other-association',
    requiredCapability: 'stats.enter', value: 'created',
  }));
  await assertSucceeds(setDoc(doc(db, 'protectedRecordsV2/record-1'), {
    ownerUid: 'operator', associationId: 'jba',
    requiredCapability: 'stats.enter', value: 'updated',
  }));
  await assertSucceeds(deleteDoc(doc(db, 'protectedRecordsV2/record-1')));
});

test('candidate Firestore keeps owner, association, and capability immutable', async () => {
  const db = authedFirestore();
  for (const patch of [
    {ownerUid: 'other-user'},
    {associationId: 'other-association'},
    {requiredCapability: 'association.read'},
  ]) {
    await assertFails(setDoc(doc(db, 'protectedRecordsV2/record-1'), {
      ownerUid: 'operator', associationId: 'jba',
      requiredCapability: 'stats.enter', value: 'downgrade', ...patch,
    }));
  }
});

test('provider and custom tenant must match exactly in both candidate Rules', async () => {
  await seedStorageObject();
  const mismatches = [
    claims({}, [], 'tenant-a'),
    claims({authTenantIdV2: 'tenant-a'}),
    claims({authTenantIdV2: 'tenant-b'}, [], 'tenant-a'),
  ];
  for (const tokenClaims of mismatches) {
    await assertFails(getDoc(doc(
      authedFirestore(tokenClaims),
      'protectedRecordsV2/record-1',
    )));
    await assertFails(getBytes(storageRef(
      authedStorage(tokenClaims),
      'protectedV2/jba/object.bin',
    )));
  }

  await seedAuthority({tenant: 'tenant-a'});
  const tenantClaims = claims({authTenantIdV2: 'tenant-a'}, [], 'tenant-a');
  await assertSucceeds(getDoc(doc(
    authedFirestore(tenantClaims),
    'protectedRecordsV2/record-1',
  )));
  await assertSucceeds(getBytes(storageRef(
    authedStorage(tenantClaims),
    'protectedV2/jba/object.bin',
  )));
});

test('same UID in root and tenant lanes cannot collide', async () => {
  await seedAuthority({lifecycle: {lifecycleStateV2: 'deleted'}});
  await seedAuthority({tenant: 'tenant-a'});
  const tenantClaims = claims({authTenantIdV2: 'tenant-a'}, [], 'tenant-a');
  await assertFails(getDoc(doc(
    authedFirestore(),
    'protectedRecordsV2/record-1',
  )));
  await assertSucceeds(getDoc(doc(
    authedFirestore(tenantClaims),
    'protectedRecordsV2/record-1',
  )));
});

test('malformed token, freshness, and control-character identifiers fail closed', async () => {
  const cases = [
    claims({}, [
      'authIncarnationSchemaVersionV2', 'authProjectIdV2', 'authTenantIdV2',
      'authUidV2', 'accountGenerationV2', 'accountLifecycleEpochV2',
    ]),
    claims({accountGenerationV2: 'BAD'}),
    claims({accountGenerationV2: 'f'.repeat(64)}),
    claims({accountLifecycleEpochV2: 7.5}),
    claims({accountLifecycleEpochV2: -1}),
    claims({accountLifecycleEpochV2: 9007199254740992}),
    claims({authProjectIdV2: 'demo-hoopsconnect\u0000'}),
    claims({authUidV2: 'operator\u001f'}),
    claims({authUidV2: 'operator\u007f'}),
    claims({auth_time: fixture.lifecycle.reauthAfterSecV2}),
  ];
  for (const tokenClaims of cases) {
    await assertFails(getDoc(doc(
      authedFirestore(tokenClaims),
      'protectedRecordsV2/record-1',
    )));
  }

  for (const associationId of ['jba\u0000', 'jba\u001f', 'jba\u007f']) {
    await seedAuthority({membership: {associationId}});
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'protectedRecordsV2/record-1'), {
        ownerUid: 'operator', associationId,
        requiredCapability: 'stats.enter', value: 'control vector',
      });
    });
    await assertFails(getDoc(doc(authedFirestore(), 'protectedRecordsV2/record-1')));
  }
  await seedAuthority();
  await seedProtectedRecords();
  await assertSucceeds(getDoc(doc(
    authedFirestore(claims({accountLifecycleEpochV2: 7.0})),
    'protectedRecordsV2/record-1',
  )));
});

test('candidate authority documents are never directly client accessible', async () => {
  const db = authedFirestore();
  for (const target of Object.values(authorityPaths(null))) {
    await assertFails(getDoc(doc(db, target)));
    await assertFails(setDoc(doc(db, target), {owned: true}));
  }
});

test('candidate Storage is readable only with exact V2 projection binding', async () => {
  await seedStorageObject();
  await assertSucceeds(getBytes(storageRef(
    authedStorage(),
    'protectedV2/jba/object.bin',
  )));
  for (const tokenClaims of [
    claims({}, ['accountGenerationV2']),
    claims({accountGenerationV2: 'f'.repeat(64)}),
    claims({accountLifecycleEpochV2: 8}),
    claims({auth_time: fixture.projection.reauthAfterSecV2}),
  ]) {
    await assertFails(getBytes(storageRef(
      authedStorage(tokenClaims),
      'protectedV2/jba/object.bin',
    )));
  }
});

test('generic candidate Storage denies upload, overwrite, and delete', async () => {
  await seedStorageObject();
  const storage = authedStorage();
  await assertFails(uploadBytes(
    storageRef(storage, 'protectedV2/jba/new.bin'),
    bytes,
  ));
  await assertFails(uploadBytes(
    storageRef(storage, 'protectedV2/jba/object.bin'),
    new Uint8Array([9]),
  ));
  await assertFails(deleteObject(storageRef(storage, 'protectedV2/jba/object.bin')));
});

test('candidate rule read budgets remain fixed and selectors remain test-only', () => {
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
  assert.match(firestoreRules, /AUTH_INCARNATION_V2_TEST_ONLY_PROJECT=demo-hoopsconnect/);
  assert.match(storageRules, /AUTH_INCARNATION_V2_TEST_ONLY_PROJECT=demo-hoopsconnect/);
});
