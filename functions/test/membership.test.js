'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});
process.env.INVITE_TOKEN_HMAC_KEY_V1 = 'local-emulator-only-key-with-at-least-32-bytes';

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');

if (admin.apps.length === 0) admin.initializeApp({projectId: 'demo-hoopsconnect'});

const {
  createPrivilegedInviteHandler,
  inspectPrivilegedInviteHandler,
  inviteIdForToken,
  provisionFanProfileHandler,
  redeemPrivilegedInviteHandler,
  revokePrivilegedInviteHandler,
  setMemberRoleHandler,
} = require('../lib/membership');
const {capabilitiesForRole} = require('../lib/authorization');

const db = admin.firestore();
const schema = {authorizationSchemaVersion: 1};

function request(uid, email, data) {
  return {
    auth: uid ? {uid, token: {email}} : undefined,
    data: Object.assign({}, data, schema),
    rawRequest: {},
  };
}

async function clearFirestore() {
  const collections = await db.listCollections();
  await Promise.all(collections.map((collection) => db.recursiveDelete(collection)));
}

async function seedAssociation(id = 'jba') {
  await db.doc('associations/' + id).set({name: id, currentSeasonId: 'season-1'});
}

async function seedMember(uid, role, associationId = 'jba', overrides = {}) {
  await db.doc('users/' + uid).set({
    email: uid + '@example.com',
    displayName: uid,
    associationId,
    role,
    authorizationSchemaVersion: 1,
  });
  await db.doc('memberships/' + uid).set(Object.assign({
    associationId,
    role,
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole(role),
  }, overrides));
}

async function allSecurityDocuments() {
  const result = [];
  for (const collectionName of [
    'inviteCodes',
    'authorizationAudit',
    'authorizationOperationReceipts',
  ]) {
    const snapshot = await db.collection(collectionName).get();
    for (const doc of snapshot.docs) result.push({path: doc.ref.path, data: doc.data()});
  }
  return result;
}

function assertRawAbsent(rawToken, value) {
  assert.equal(JSON.stringify(value).includes(rawToken), false);
}

function assertNoSecretFields(value) {
  if (Array.isArray(value)) {
    value.forEach(assertNoSecretFields);
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    assert.equal(['code', 'inviteCode', 'rawToken', 'secret'].includes(key), false);
    assertNoSecretFields(child);
  }
}

test.beforeEach(async () => {
  await clearFirestore();
  await seedAssociation();
});

test.after(async () => {
  await clearFirestore();
  await admin.app().delete();
});

test('fan provisioning creates a consistent pair, repairs membership-only, and fails closed on conflicts', async () => {
  const created = await provisionFanProfileHandler(request('fan-1', 'Fan@Example.com', {
    displayName: 'Fan One',
    role: 'superAdmin',
    associationId: 'victim',
  }));
  assert.equal(created.created, true);
  assert.equal((await db.doc('users/fan-1').get()).get('email'), 'fan@example.com');
  assert.deepEqual(
    (await db.doc('memberships/fan-1').get()).get('capabilities'),
    capabilitiesForRole('fan'),
  );

  const repeated = await provisionFanProfileHandler(request('fan-1', 'fan@example.com', {
    displayName: 'Ignored Rename',
  }));
  assert.deepEqual(
    {created: repeated.created, repaired: repeated.repaired},
    {created: false, repaired: false},
  );

  await db.doc('users/fan-1').update({teamId: 'conflicting-team'});
  await assert.rejects(
    provisionFanProfileHandler(request('fan-1', 'fan@example.com', {displayName: 'Fan One'})),
    (error) => error.code === 'failed-precondition',
  );
  await db.doc('users/fan-1').update({teamId: null});

  await db.doc('memberships/member-only').set({
    associationId: 'jba', role: 'fan', status: 'active',
    capabilities: capabilitiesForRole('fan'), authorizationSchemaVersion: 1,
  });
  const repaired = await provisionFanProfileHandler(request('member-only', 'repair@example.com', {
    displayName: 'Repair',
  }));
  assert.equal(repaired.repaired, true);
  assert.equal((await db.doc('users/member-only').get()).get('email'), 'repair@example.com');

  await db.doc('memberships/media-only').set({
    associationId: 'jba', role: 'media', status: 'active',
    capabilities: capabilitiesForRole('media'), authorizationSchemaVersion: 1,
  });
  const privilegedRepair = await provisionFanProfileHandler(
    request('media-only', 'media-only@example.com', {displayName: 'Media Repair'}),
  );
  assert.equal(privilegedRepair.role, 'media');
  assert.equal((await db.doc('users/media-only').get()).get('role'), 'media');

  await db.doc('users/user-only').set({
    email: 'user-only@example.com', displayName: 'Legacy', associationId: 'jba', role: 'fan',
  });
  await assert.rejects(
    provisionFanProfileHandler(request('user-only', 'user-only@example.com', {displayName: 'Legacy'})),
    (error) => error.code === 'failed-precondition',
  );

  await db.doc('memberships/conflict').set({
    associationId: 'other', role: 'fan', status: 'active',
    capabilities: capabilitiesForRole('fan'), authorizationSchemaVersion: 1,
  });
  await assert.rejects(
    provisionFanProfileHandler(request('conflict', 'conflict@example.com', {displayName: 'Conflict'})),
    (error) => error.code === 'failed-precondition',
  );
});

test('invite issuance is high-entropy, hash-addressed, idempotent, and never persists the bearer', async () => {
  await seedMember('root', 'superAdmin');
  await db.doc('associations/jba/divisions/division-1').set({
    name: 'Division 1', status: 'active', version: 1,
  });
  await db.doc('associations/jba/teams/team-1').set({
    name: 'Team', divisionId: 'division-1', seasonId: 'season-1', status: 'active',
  });
  const payload = {
    role: 'rep', teamId: 'team-1', daysValid: 7,
    operationId: 'create_operation_00000001',
  };
  const [first, replay] = await Promise.all([
    createPrivilegedInviteHandler(request('root', 'root@example.com', payload)),
    createPrivilegedInviteHandler(request('root', 'root@example.com', payload)),
  ]);
  assert.equal(first.code, replay.code);
  assert.match(first.code, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(first.inviteId, inviteIdForToken(first.code));
  assert.match(first.inviteId, /^v2_[a-f0-9]{64}$/);
  assert.equal((await db.collection('inviteCodes').get()).size, 1);
  assert.equal((await db.collection('authorizationOperationReceipts').get()).size, 1);
  assert.equal((await db.collection('authorizationAudit').get()).size, 1);
  assert.equal((await db.doc('inviteCodes/' + first.inviteId).get()).get('divisionId'), 'division-1');
  const securityDocuments = await allSecurityDocuments();
  assertRawAbsent(first.code, securityDocuments);
  assertNoSecretFields(securityDocuments);

  await db.doc('memberships/root').update({status: 'suspended'});
  await assert.rejects(
    createPrivilegedInviteHandler(request('root', 'root@example.com', payload)),
    (error) => error.code === 'permission-denied',
  );
  await db.doc('memberships/root').update({status: 'active'});

  await assert.rejects(
    createPrivilegedInviteHandler(request('root', 'root@example.com', {
      ...payload, role: 'media',
    })),
    (error) => error.code === 'failed-precondition',
  );
});

test('representative invite team must remain active in the association current season', async () => {
  await seedMember('root', 'superAdmin');
  await db.doc('associations/jba/divisions/division-1').set({
    name: 'Division 1', status: 'active', version: 1,
  });
  const createForTeam = (operationId) => createPrivilegedInviteHandler(request('root', 'root@example.com', {
    role: 'rep', teamId: 'team-hostile', daysValid: 7, operationId,
  }));
  await db.doc('associations/jba/teams/team-hostile').set({
    name: 'Old Team', divisionId: 'division-1', seasonId: 'season-old', status: 'active',
  });
  await assert.rejects(
    createForTeam('create_wrong_season_000001'),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal((await db.collection('inviteCodes').get()).empty, true);

  await db.doc('associations/jba/teams/team-hostile').set({
    name: 'Archived Team', divisionId: 'division-1', seasonId: 'season-1', status: 'archived',
  });
  await assert.rejects(
    createForTeam('create_archived_team_00001'),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal((await db.collection('inviteCodes').get()).empty, true);

  await db.doc('associations/jba/teams/team-hostile').set({
    name: 'Current Team', divisionId: 'division-1', seasonId: 'season-1', status: 'active',
  });
  const issued = await createForTeam('create_current_team_000001');
  const invite = await db.doc(`inviteCodes/${issued.inviteId}`).get();
  assert.equal(invite.get('seasonId'), 'season-1');
  assert.equal(invite.get('teamId'), 'team-hostile');
});

test('inspection never echoes a bearer and redemption retries return the original success', async () => {
  await seedMember('root', 'superAdmin');
  const issued = await createPrivilegedInviteHandler(request('root', 'root@example.com', {
    role: 'media', daysValid: 7, operationId: 'create_operation_00000002',
  }));
  const inspected = await inspectPrivilegedInviteHandler(request(null, null, {code: issued.code}));
  assert.equal(inspected.inviteId, issued.inviteId);
  assertRawAbsent(issued.code, inspected);

  const redemption = {
    code: issued.code,
    displayName: 'Media One',
    operationId: 'redeem_operation_00000001',
  };
  const first = await redeemPrivilegedInviteHandler(
    request('media-1', 'media@example.com', redemption),
  );
  // Simulates a response lost after commit: the same logical request is safe.
  const retry = await redeemPrivilegedInviteHandler(
    request('media-1', 'media@example.com', redemption),
  );
  assert.deepEqual(retry, first);
  assert.equal((await db.doc('memberships/media-1').get()).get('role'), 'media');
  assert.equal((await db.collection('memberships').get()).size, 2);
  assert.equal((await db.collection('authorizationAudit').where('action', '==', 'invite.redeemed').get()).size, 1);
  const securityDocuments = await allSecurityDocuments();
  assertRawAbsent(issued.code, securityDocuments);
  assertNoSecretFields(securityDocuments);

  await assert.rejects(
    redeemPrivilegedInviteHandler(request('media-2', 'media2@example.com', {
      ...redemption, operationId: 'redeem_operation_00000002',
    })),
    (error) => error.code === 'failed-precondition',
  );
});

test('different actors racing a single-use invite produce one membership', async () => {
  await seedMember('root', 'superAdmin');
  const issued = await createPrivilegedInviteHandler(request('root', 'root@example.com', {
    role: 'media', daysValid: 7, operationId: 'create_operation_00000003',
  }));
  const results = await Promise.allSettled([
    redeemPrivilegedInviteHandler(request('a', 'a@example.com', {
      code: issued.code, displayName: 'A', operationId: 'redeem_operation_actor_a',
    })),
    redeemPrivilegedInviteHandler(request('b', 'b@example.com', {
      code: issued.code, displayName: 'B', operationId: 'redeem_operation_actor_b',
    })),
  ]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter((result) => result.status === 'rejected').length, 1);
  assert.equal((await db.collection('memberships').get()).size, 2);
});

test('legacy/static credentials and role-only profiles fail closed', async () => {
  await db.doc('inviteCodes/LEGACY-FIXTURE').set({
    associationId: 'jba', role: 'admin', status: 'active', usesRemaining: 1,
    authorizationSchemaVersion: 1,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  });
  await assert.rejects(
    inspectPrivilegedInviteHandler(request(null, null, {code: 'LEGACY-FIXTURE'})),
    (error) => error.code === 'invalid-argument',
  );
  await db.doc('users/legacy-root').set({
    email: 'root@example.com', displayName: 'Root', associationId: 'jba', role: 'superAdmin',
  });
  await assert.rejects(
    createPrivilegedInviteHandler(request('legacy-root', 'root@example.com', {
      role: 'media', daysValid: 7, operationId: 'create_operation_legacy_001',
    })),
    (error) => error.code === 'permission-denied',
  );
});

test('revocation and role changes re-check active capability authority transactionally', async () => {
  await seedMember('root', 'superAdmin');
  const issued = await createPrivilegedInviteHandler(request('root', 'root@example.com', {
    role: 'media', daysValid: 7, operationId: 'create_operation_00000004',
  }));
  await db.doc('memberships/root').update({status: 'suspended'});
  await assert.rejects(
    revokePrivilegedInviteHandler(request('root', 'root@example.com', {inviteId: issued.inviteId})),
    (error) => error.code === 'permission-denied',
  );
  assert.equal((await db.doc('inviteCodes/' + issued.inviteId).get()).get('status'), 'active');

  await db.doc('memberships/root').update({status: 'active'});
  await revokePrivilegedInviteHandler(request('root', 'root@example.com', {inviteId: issued.inviteId}));
  assert.equal((await db.doc('inviteCodes/' + issued.inviteId).get()).get('status'), 'revoked');

  await seedMember('target', 'media');
  await db.doc('users/target').update({role: 'admin'});
  await assert.rejects(
    setMemberRoleHandler(request('root', 'root@example.com', {userId: 'target', role: 'statistician'})),
    (error) => error.code === 'failed-precondition',
  );
  await db.doc('users/target').update({role: 'media'});
  await db.doc('memberships/root').update({capabilities: []});
  await assert.rejects(
    setMemberRoleHandler(request('root', 'root@example.com', {userId: 'target', role: 'admin'})),
    (error) => error.code === 'permission-denied',
  );
  assert.equal((await db.doc('memberships/target').get()).get('role'), 'media');
});
