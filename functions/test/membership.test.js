'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');

if (admin.apps.length === 0) {
  admin.initializeApp({projectId: 'demo-hoopsconnect'});
}

const {
  createPrivilegedInviteHandler,
  inspectPrivilegedInviteHandler,
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
  await db.doc('associations/' + id).set({
    name: id,
    currentSeasonId: 'season-1',
  });
}

test.beforeEach(async () => {
  await clearFirestore();
  await seedAssociation();
});

test.after(async () => {
  await clearFirestore();
  await admin.app().delete();
});

test('fan provisioning ignores forged authority fields and binds auth email', async () => {
  const result = await provisionFanProfileHandler(
    request('fan-1', 'Fan@Example.com', {
      displayName: 'Fan One',
      role: 'superAdmin',
      associationId: 'victim',
      capabilities: ['members.manage'],
    }),
  );
  assert.equal(result.created, true);

  const user = (await db.doc('users/fan-1').get()).data();
  const membership = (await db.doc('memberships/fan-1').get()).data();
  assert.equal(user.role, 'fan');
  assert.equal(user.associationId, 'jba');
  assert.equal(user.email, 'fan@example.com');
  assert.equal(membership.role, 'fan');
  assert.deepEqual(membership.capabilities, capabilitiesForRole('fan'));
  assert.equal(membership.seasonId, 'season-1');
});

test('fan provisioning rejects old authorization schema and missing auth', async () => {
  await assert.rejects(
    provisionFanProfileHandler({
      auth: {uid: 'fan-1', token: {email: 'fan@example.com'}},
      data: {displayName: 'Fan', authorizationSchemaVersion: 0},
      rawRequest: {},
    }),
    (error) => error.code === 'failed-precondition',
  );
  await assert.rejects(
    provisionFanProfileHandler(request(null, null, {displayName: 'Fan'})),
    (error) => error.code === 'unauthenticated',
  );
});

test('concurrent redemption consumes a single-use invite exactly once', async () => {
  await db.doc('associations/jba/teams/team-1').set({name: 'Team One'});
  await db.doc('inviteCodes/REP123').set({
    associationId: 'jba',
    teamId: 'team-1',
    role: 'rep',
    status: 'active',
    usesRemaining: 1,
    authorizationSchemaVersion: 1,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  });

  const results = await Promise.allSettled([
    redeemPrivilegedInviteHandler(
      request('rep-a', 'a@example.com', {
        code: ' rep123 ',
        displayName: 'Rep A',
      }),
    ),
    redeemPrivilegedInviteHandler(
      request('rep-b', 'b@example.com', {
        code: 'REP123',
        displayName: 'Rep B',
      }),
    ),
  ]);

  const resultSummary = results.map((result) =>
    result.status === 'fulfilled'
      ? 'fulfilled'
      : String(result.reason?.code) + ': ' + String(result.reason?.message),
  ).join(' | ');
  assert.equal(
    results.filter((result) => result.status === 'fulfilled').length,
    1,
    resultSummary,
  );
  assert.equal(results.filter((result) => result.status === 'rejected').length, 1);
  const invite = (await db.doc('inviteCodes/REP123').get()).data();
  assert.equal(invite.status, 'redeemed');
  assert.equal(invite.usesRemaining, 0);
  const memberships = await db.collection('memberships').get();
  assert.equal(memberships.size, 1);
  const audits = await db
    .collection('authorizationAudit')
    .where('action', '==', 'invite.redeemed')
    .get();
  assert.equal(audits.size, 1);
});

test('expired, revoked, replayed, and super-admin invites fail closed', async () => {
  const base = {
    associationId: 'jba',
    teamId: null,
    role: 'media',
    usesRemaining: 1,
    authorizationSchemaVersion: 1,
  };
  await db.doc('inviteCodes/EXPIRED').set(Object.assign({}, base, {
    status: 'active',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  }));
  await db.doc('inviteCodes/REVOKED').set(Object.assign({}, base, {
    status: 'revoked',
    revokedAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  }));
  await db.doc('inviteCodes/ROOT123').set(Object.assign({}, base, {
    role: 'superAdmin',
    status: 'active',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  }));

  for (const code of ['EXPIRED', 'REVOKED', 'ROOT123']) {
    await assert.rejects(
      redeemPrivilegedInviteHandler(
        request('user-' + code, code.toLowerCase() + '@example.com', {
          code,
          displayName: code,
        }),
      ),
    );
  }

  await db.doc('inviteCodes/MEDIA1').set(Object.assign({}, base, {
    status: 'active',
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000),
  }));
  await redeemPrivilegedInviteHandler(
    request('media-1', 'media@example.com', {
      code: 'MEDIA1',
      displayName: 'Media',
    }),
  );
  await assert.rejects(
    redeemPrivilegedInviteHandler(
      request('media-2', 'media2@example.com', {
        code: 'MEDIA1',
        displayName: 'Media Two',
      }),
    ),
    (error) => error.code === 'failed-precondition',
  );
});

test('known static legacy invites and legacy user roles have no authority', async () => {
  await db.doc('inviteCodes/NBL-ADMIN').set({
    associationId: 'jba',
    teamId: null,
    role: 'admin',
    usesRemaining: 5,
    expiresAt: admin.firestore.Timestamp.fromDate(new Date('2026-12-31T23:59:59Z')),
  });
  await assert.rejects(
    inspectPrivilegedInviteHandler(request(null, null, {code: 'NBL-ADMIN'})),
    (error) => error.code === 'not-found',
  );
  await assert.rejects(
    redeemPrivilegedInviteHandler(
      request('legacy-admin', 'legacy@example.com', {
        code: 'NBL-ADMIN',
        displayName: 'Legacy Admin',
      }),
    ),
    (error) => error.code === 'failed-precondition',
  );

  await db.doc('users/legacy-root').set({
    email: 'root@example.com',
    displayName: 'Legacy Root',
    associationId: 'jba',
    role: 'superAdmin',
  });
  await assert.rejects(
    createPrivilegedInviteHandler(
      request('legacy-root', 'root@example.com', {
        role: 'media',
        daysValid: 7,
      }),
    ),
    (error) => error.code === 'permission-denied',
  );
});

test('fan cannot create an invite and super admin cannot delegate super admin', async () => {
  await db.doc('users/fan-1').set({
    email: 'fan@example.com',
    displayName: 'Fan',
    associationId: 'jba',
    role: 'fan',
  });
  await db.doc('memberships/fan-1').set({
    associationId: 'jba',
    role: 'fan',
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole('fan'),
  });
  await assert.rejects(
    createPrivilegedInviteHandler(
      request('fan-1', 'fan@example.com', {
        role: 'media',
        daysValid: 7,
      }),
    ),
    (error) => error.code === 'permission-denied',
  );

  await db.doc('users/root-1').set({
    email: 'root@example.com',
    displayName: 'Root',
    associationId: 'jba',
    role: 'superAdmin',
  });
  await db.doc('memberships/root-1').set({
    associationId: 'jba',
    role: 'superAdmin',
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole('superAdmin'),
  });
  await assert.rejects(
    createPrivilegedInviteHandler(
      request('root-1', 'root@example.com', {
        role: 'superAdmin',
        daysValid: 7,
      }),
    ),
    (error) => error.code === 'permission-denied',
  );
  await assert.rejects(
    createPrivilegedInviteHandler(
      request('root-1', 'root@example.com', {
        role: 'rep',
        daysValid: 7,
      }),
    ),
    (error) => error.code === 'invalid-argument',
  );
});

test('authorized invite creation is single-use, scoped, and audited', async () => {
  await db.doc('associations/jba/teams/team-1').set({
    name: 'Team One',
    divisionId: 'division-1',
  });
  await db.doc('users/root-1').set({
    email: 'root@example.com',
    displayName: 'Root',
    associationId: 'jba',
    role: 'superAdmin',
  });
  await db.doc('memberships/root-1').set({
    associationId: 'jba',
    role: 'superAdmin',
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole('superAdmin'),
  });

  const created = await createPrivilegedInviteHandler(
    request('root-1', 'root@example.com', {
      role: 'rep',
      teamId: 'team-1',
      daysValid: 7,
    }),
  );
  const invite = (await db.doc('inviteCodes/' + created.code).get()).data();
  assert.equal(invite.associationId, 'jba');
  assert.equal(invite.teamId, 'team-1');
  assert.equal(invite.divisionId, 'division-1');
  assert.equal(invite.usesRemaining, 1);
  assert.equal(invite.status, 'active');
  const audit = await db
    .collection('authorizationAudit')
    .where('inviteCode', '==', created.code)
    .get();
  assert.equal(audit.size, 1);

  await revokePrivilegedInviteHandler(
    request('root-1', 'root@example.com', {code: created.code}),
  );
  const revoked = (await db.doc('inviteCodes/' + created.code).get()).data();
  assert.equal(revoked.status, 'revoked');
  await assert.rejects(
    redeemPrivilegedInviteHandler(
      request('rep-after-revoke', 'rep@example.com', {
        code: created.code,
        displayName: 'Rep',
      }),
    ),
    (error) => error.code === 'failed-precondition',
  );
});

test('role management cannot reach across associations', async () => {
  await seedAssociation('other');
  await db.doc('users/root-1').set({
    email: 'root@example.com',
    displayName: 'Root',
    associationId: 'jba',
    role: 'superAdmin',
  });
  await db.doc('memberships/root-1').set({
    associationId: 'jba',
    role: 'superAdmin',
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole('superAdmin'),
  });
  await db.doc('users/other-user').set({
    email: 'other@example.com',
    displayName: 'Other',
    associationId: 'other',
    role: 'fan',
  });
  await assert.rejects(
    setMemberRoleHandler(
      request('root-1', 'root@example.com', {
        userId: 'other-user',
        role: 'media',
      }),
    ),
    (error) => error.code === 'not-found',
  );
  await assert.rejects(
    setMemberRoleHandler(
      request('root-1', 'root@example.com', {
        userId: 'root-1',
        role: 'admin',
      }),
    ),
    (error) => error.code === 'failed-precondition',
  );

  await db.doc('users/split-user').set({
    email: 'split@example.com',
    displayName: 'Split',
    associationId: 'jba',
    role: 'fan',
  });
  await db.doc('memberships/split-user').set({
    associationId: 'other',
    role: 'fan',
    status: 'active',
    authorizationSchemaVersion: 1,
    capabilities: capabilitiesForRole('fan'),
  });
  await assert.rejects(
    setMemberRoleHandler(
      request('root-1', 'root@example.com', {
        userId: 'split-user',
        role: 'media',
      }),
    ),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal(
    (await db.doc('memberships/split-user').get()).get('associationId'),
    'other',
  );
});
