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
const {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  ref: storageRef,
  uploadBytes,
} = require('firebase/storage');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad02/lifecycle_fixtures_v2.json',
), 'utf8'));
const firestoreRulesPath = path.resolve(
  __dirname,
  'fixtures/account_lifecycle_ad02_v2/firestore.rules',
);
const storageRulesPath = path.resolve(
  __dirname,
  'fixtures/account_lifecycle_ad02_v2/storage.rules',
);

const generationA = 'a'.repeat(64);
const generationB = 'b'.repeat(64);
const bytes = new Uint8Array([2, 0, 2, 6]);
let testEnv;

function scope(tenant = null, uid = fixture.rootScope.authUidV2) {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    authUidV2: uid,
  };
}

function claims(patch = {}, removeKeys = [], tenant = null, uid = fixture.rootScope.authUidV2) {
  const firebase = {sign_in_provider: 'custom', identities: {}};
  if (tenant !== null) firebase.tenant = tenant;
  const result = {
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    auth_time: 1700000001,
    firebase,
    ...patch,
  };
  for (const key of removeKeys) delete result[key];
  return result;
}

function paths(tenant = null, uid = fixture.rootScope.authUidV2) {
  return tenant === null ? {
    lifecycle: `accountLifecycleV2Root/${uid}`,
    membership: `membershipsV2Root/${uid}`,
    projection: `storageAuthorizationsV2Root/${uid}`,
    profile: `accountProfilesV2Root/${uid}`,
    registration: `accountFcmRegistrationsV2Root/${uid}/installations/device_a`,
  } : {
    lifecycle: `accountLifecycleV2Tenants/${tenant}/users/${uid}`,
    membership: `membershipsV2Tenants/${tenant}/users/${uid}`,
    projection: `storageAuthorizationsV2Tenants/${tenant}/users/${uid}`,
    profile: `accountProfilesV2Tenants/${tenant}/users/${uid}`,
    registration:
      `accountFcmRegistrationsV2Tenants/${tenant}/users/${uid}/installations/device_a`,
  };
}

function lifecycle(tenant = null, uid = fixture.rootScope.authUidV2, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    lifecycleStateV2: 'active',
    reauthAfterSecV2: 1700000000,
    ...patch,
  };
}

function membership(tenant = null, uid = fixture.rootScope.authUidV2, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    membershipStatusV2: 'active',
    associationId: 'jba',
    capabilities: ['association.read', 'stats.enter', 'stats.approve'],
    ...patch,
  };
}

function projection(tenant = null, uid = fixture.rootScope.authUidV2, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    lifecycleStateV2: 'active',
    membershipStatusV2: 'active',
    reauthAfterSecV2: 1700000000,
    associationId: 'jba',
    capabilities: ['association.read', 'stats.enter', 'stats.approve'],
    ...patch,
  };
}

function profile(tenant = null, uid = fixture.rootScope.authUidV2, patch = {}) {
  return {
    accountProfileSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    associationId: 'jba',
    displayName: 'Operator',
    teamId: null,
    divisionId: null,
    notificationPrefs: {newPosts: true},
    ...patch,
  };
}

function registration(tenant = null, uid = fixture.rootScope.authUidV2, patch = {}) {
  return {
    fcmRegistrationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    associationId: 'jba',
    installationId: 'device_a',
    fcmToken: 'installation-token',
    updatedAt: serverTimestamp(),
    ...patch,
  };
}

function authorityStamp(
  tenant = null,
  uid = fixture.rootScope.authUidV2,
  generation = generationA,
  epoch = 7,
) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant, uid),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: epoch,
  };
}

function protectedRecord(
  tenant = null,
  uid = fixture.rootScope.authUidV2,
  generation = generationA,
  epoch = 7,
) {
  return {
    owner: authorityStamp(tenant, uid, generation, epoch),
    associationId: 'jba',
    requiredCapability: 'stats.enter',
    value: 'candidate',
  };
}

function protectedStoragePath(
  tenant = null,
  uid = fixture.rootScope.authUidV2,
  generation = generationA,
) {
  return tenant === null
    ? `candidateProtectedV2Root/${uid}/${generation}/jba/object.bin`
    : `candidateProtectedV2Tenants/${tenant}/users/${uid}/${generation}/jba/object.bin`;
}

async function seedAuthority({
  tenant = null,
  uid = fixture.rootScope.authUidV2,
  lifecyclePatch = {},
  membershipPatch = {},
  projectionPatch = {},
  profilePatch = {},
} = {}) {
  const target = paths(tenant, uid);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, target.lifecycle), lifecycle(tenant, uid, lifecyclePatch));
    await setDoc(doc(db, target.membership), membership(tenant, uid, membershipPatch));
    await setDoc(doc(db, target.projection), projection(tenant, uid, projectionPatch));
    await setDoc(doc(db, target.profile), profile(tenant, uid, profilePatch));
  });
}

async function seedProtected({
  tenant = null,
  uid = fixture.rootScope.authUidV2,
  generation = generationA,
  epoch = 7,
  recordId = 'owned',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `protectedRecordsV2/${recordId}`),
      protectedRecord(tenant, uid, generation, epoch),
    );
    await uploadBytes(
      storageRef(context.storage(), protectedStoragePath(tenant, uid, generation)),
      bytes,
    );
  });
}

function firestore(tokenClaims = claims(), uid = fixture.rootScope.authUidV2) {
  return testEnv.authenticatedContext(uid, tokenClaims).firestore();
}

function storage(tokenClaims = claims(), uid = fixture.rootScope.authUidV2) {
  return testEnv.authenticatedContext(uid, tokenClaims).storage();
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: fixture.projectId,
    firestore: {rules: fs.readFileSync(firestoreRulesPath, 'utf8')},
    storage: {rules: fs.readFileSync(storageRulesPath, 'utf8')},
  });
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedAuthority();
  await seedProtected();
});

test.after(async () => testEnv.cleanup());

test('candidate Firestore and Storage require exact active V2 authority', async () => {
  const db = firestore();
  await assertSucceeds(getDoc(doc(db, 'protectedRecordsV2/owned')));
  await assertSucceeds(setDoc(
    doc(db, 'protectedRecordsV2/new'),
    protectedRecord(),
  ));
  await assertSucceeds(getBytes(storageRef(
    storage(),
    protectedStoragePath(),
  )));
});

test('old-G tokens cannot attach to a recreated same UID with new G/E', async () => {
  await seedAuthority({
    lifecyclePatch: {accountGenerationV2: generationB, accountLifecycleEpochV2: 0},
    membershipPatch: {accountGenerationV2: generationB, accountLifecycleEpochV2: 0},
    projectionPatch: {accountGenerationV2: generationB, accountLifecycleEpochV2: 0},
    profilePatch: {accountGenerationV2: generationB, accountLifecycleEpochV2: 0},
  });
  const oldToken = claims();
  await assertFails(getDoc(doc(firestore(oldToken), 'protectedRecordsV2/owned')));
  await assertFails(getBytes(storageRef(
    storage(oldToken),
    protectedStoragePath(),
  )));

  const newToken = claims({accountGenerationV2: generationB, accountLifecycleEpochV2: 0});
  await assertFails(getDoc(doc(firestore(newToken), 'protectedRecordsV2/owned')));
  await assertFails(getBytes(storageRef(
    storage(newToken),
    protectedStoragePath(),
  )));
  await seedProtected({generation: generationB, epoch: 0, recordId: 'owned_new'});
  await assertSucceeds(getDoc(doc(firestore(newToken), 'protectedRecordsV2/owned_new')));
  await assertSucceeds(getBytes(storageRef(
    storage(newToken),
    protectedStoragePath(null, fixture.rootScope.authUidV2, generationB),
  )));
});

test('root and tenant same UID remain isolated across every candidate sink', async () => {
  await seedAuthority({
    lifecyclePatch: {lifecycleStateV2: 'deleted', accountLifecycleEpochV2: 8},
    membershipPatch: {membershipStatusV2: 'revoked', accountLifecycleEpochV2: 8},
    projectionPatch: {
      lifecycleStateV2: 'deleted', membershipStatusV2: 'revoked',
      accountLifecycleEpochV2: 8,
    },
  });
  await seedAuthority({tenant: 'tenant-a'});
  await seedProtected({tenant: 'tenant-a', recordId: 'tenant_owned'});
  const tenantClaims = claims({}, [], 'tenant-a');
  await assertFails(getDoc(doc(firestore(), 'protectedRecordsV2/owned')));
  await assertFails(getBytes(storageRef(
    storage(),
    protectedStoragePath(),
  )));
  await assertFails(getDoc(doc(firestore(tenantClaims), 'protectedRecordsV2/owned')));
  await assertFails(getBytes(storageRef(
    storage(tenantClaims),
    protectedStoragePath(),
  )));
  await assertSucceeds(getDoc(doc(firestore(tenantClaims), 'protectedRecordsV2/tenant_owned')));
  await assertSucceeds(getBytes(storageRef(
    storage(tenantClaims),
    protectedStoragePath('tenant-a'),
  )));
  await assertFails(getDoc(doc(firestore(tenantClaims), paths().profile)));
  await assertSucceeds(getDoc(doc(firestore(tenantClaims), paths('tenant-a').profile)));
});

test('missing/malformed/V1 proof, strict freshness equality, and inactive rows deny', async () => {
  const denialClaims = [
    claims({}, ['accountGenerationV2']),
    claims({accountGenerationV2: 'f'.repeat(64)}),
    claims({accountLifecycleEpochV2: 8}),
    claims({auth_time: 1700000000}),
    claims({authProjectIdV2: 'other-project'}),
    claims({authTenantIdV2: 'tenant-a'}),
    {
      accountGenerationHashV1: 'c'.repeat(64),
      accountLifecycleEpoch: 7,
      firebase: {sign_in_provider: 'custom', identities: {}},
    },
  ];
  for (const token of denialClaims) {
    await assertFails(getDoc(doc(firestore(token), 'protectedRecordsV2/owned')));
    await assertFails(getBytes(storageRef(
      storage(token),
      protectedStoragePath(),
    )));
  }

  await seedAuthority({
    lifecyclePatch: {lifecycleStateV2: 'deleting', accountLifecycleEpochV2: 8},
    membershipPatch: {membershipStatusV2: 'revoked', accountLifecycleEpochV2: 8},
    projectionPatch: {
      lifecycleStateV2: 'deleting', membershipStatusV2: 'revoked',
      accountLifecycleEpochV2: 8,
    },
  });
  await assertFails(getDoc(doc(firestore(), 'protectedRecordsV2/owned')));
  await assertFails(getBytes(storageRef(
    storage(),
    protectedStoragePath(),
  )));
});

test('FCM registration is own-lane, ready-authority bound, and lifecycle fenced', async () => {
  const db = firestore();
  const target = paths().registration;
  await assertSucceeds(setDoc(doc(db, target), registration()));
  await assertFails(getDoc(doc(db, target)));
  await assertSucceeds(updateDoc(doc(db, target), {
    fcmToken: 'rotated-token',
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(deleteDoc(doc(db, target)));

  const otherPath = paths(null, 'other-user').registration;
  await assertFails(setDoc(doc(db, otherPath), registration(null, 'other-user')));

  await seedAuthority({
    lifecyclePatch: {lifecycleStateV2: 'deleting', accountLifecycleEpochV2: 8},
    membershipPatch: {membershipStatusV2: 'revoked', accountLifecycleEpochV2: 8},
  });
  await assertFails(setDoc(doc(db, target), registration()));
});

test('legacy approval source must carry the presented original scope/G/E', async () => {
  const db = firestore();
  const base = {
    associationId: 'jba',
    actor: {
      authIncarnationSchemaVersionV2: 2,
      ...scope(),
      accountGenerationV2: generationA,
      accountLifecycleEpochV2: 7,
    },
    approvedValue: 42,
  };
  await assertSucceeds(setDoc(doc(db, 'candidateLegacyApprovalsV2/good'), base));
  for (const actorPatch of [
    {accountGenerationV2: generationB},
    {accountLifecycleEpochV2: 8},
    {authTenantIdV2: 'tenant-a'},
    {authProjectIdV2: 'other-project'},
  ]) {
    await assertFails(setDoc(doc(db, `candidateLegacyApprovalsV2/bad_${Object.keys(actorPatch)[0]}`), {
      ...base,
      actor: {...base.actor, ...actorPatch},
    }));
  }
  await assertFails(getDoc(doc(db, 'candidateLegacyApprovalsV2/good')));
});

test('raw authority, suppression, notification, deletion, and derived records stay private', async () => {
  const db = firestore();
  const targets = [
    paths().lifecycle,
    paths().membership,
    'accountGenerationSuppressionsV2Root/operator',
    'notificationDeliveryEffectsV2/effect',
    'notificationDeliveryAttemptsV2/attempt',
    'notificationDispatchBarriersV2/jba',
    'accountDeletionV2/job',
    'candidateDerivedOutputsV2/output',
  ];
  for (const target of targets) {
    await assertFails(getDoc(doc(db, target)));
    await assertFails(setDoc(doc(db, target), {owned: true}));
  }
});

test('generic candidate Storage mutation remains denied', async () => {
  const object = storageRef(storage(), protectedStoragePath());
  await assertFails(uploadBytes(object, new Uint8Array([9])));
  await assertFails(uploadBytes(
    storageRef(storage(), protectedStoragePath().replace('object.bin', 'new.bin')),
    bytes,
  ));
  await assertFails(deleteObject(object));
});

test('candidate rule read budgets are fixed and selectors are test-only', () => {
  const firestoreRules = fs.readFileSync(firestoreRulesPath, 'utf8');
  const storageRules = fs.readFileSync(storageRulesPath, 'utf8');
  const firestoreToken = firestoreRules.match(
    /AD02_TOKEN_V2_BEGIN([\s\S]*?)AD02_TOKEN_V2_END/,
  )[1];
  const firestoreActive = firestoreRules.match(
    /AD02_ACTIVE_V2_BEGIN([\s\S]*?)AD02_ACTIVE_V2_END/,
  )[1];
  const storageToken = storageRules.match(
    /AD02_TOKEN_V2_BEGIN([\s\S]*?)AD02_TOKEN_V2_END/,
  )[1];
  const storageActive = storageRules.match(
    /AD02_ACTIVE_V2_BEGIN([\s\S]*?)AD02_ACTIVE_V2_END/,
  )[1];
  assert.doesNotMatch(firestoreToken, /\b(?:get|exists)\s*\(/);
  assert.doesNotMatch(storageToken, /\b(?:get|exists)\s*\(/);
  assert.equal((firestoreActive.match(/\bget\s*\(/g) || []).length, 2);
  assert.equal((storageActive.match(/\bfirestore\.get\s*\(/g) || []).length, 1);
  assert.match(firestoreRules, /ACCOUNT_LIFECYCLE_AD02_V2_TEST_ONLY_PROJECT/);
  assert.match(storageRules, /ACCOUNT_LIFECYCLE_AD02_V2_TEST_ONLY_PROJECT/);
  const firebase = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, '../../firebase.json'),
    'utf8',
  ));
  assert.notEqual(firebase.firestore.rules, path.relative(process.cwd(), firestoreRulesPath));
  assert.notEqual(firebase.storage.rules, path.relative(process.cwd(), storageRulesPath));
});
