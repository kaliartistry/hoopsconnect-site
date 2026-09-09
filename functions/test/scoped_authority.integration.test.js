'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp({projectId: 'demo-hoopsconnect'});

const {requireScopedAuthorityInTransaction, ScopedAuthorityError} = require('../lib/domain/scoped_authority');
const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/authority_fixtures.json'),
  'utf8',
));
const db = admin.firestore();
const seasonPath = 'associations/jba/competitions/nbl/seasons/s2026';
const timestamp = (value) => admin.firestore.Timestamp.fromDate(new Date(value));

function persistedGrant(capability = 'stats.enter', scopeKind = 'division', changes = {}) {
  const grant = {
    grantId: `grant-${capability.replaceAll('.', '-')}`,
    capability,
    scopeKind,
    associationId: 'jba',
    status: 'active',
    membershipVersion: 7,
    effectiveFrom: timestamp('2020-01-01T00:00:00.000Z'),
    effectiveTo: null,
  };
  if (scopeKind !== 'association') Object.assign(grant, {competitionId: 'nbl', seasonId: 's2026'});
  if (scopeKind === 'division' || scopeKind === 'teamEntry') grant.divisionId = 'premier';
  if (scopeKind === 'teamEntry') grant.teamEntryId = 'team-a';
  return Object.assign(grant, changes);
}

function grantKey(grant) {
  if (grant.scopeKind === 'association' || grant.scopeKind === 'season') return `${grant.capability}|${grant.scopeKind}`;
  if (grant.scopeKind === 'division') return `${grant.capability}|division|${grant.divisionId}`;
  return `${grant.capability}|teamEntry|${grant.divisionId}|${grant.teamEntryId}`;
}

async function clear() {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
}

async function seedStats(mode = 'v2') {
  const statsGrant = persistedGrant();
  await db.doc('memberships/operator').set({...fixture.membershipBase, capabilities: ['stats.enter']});
  await db.doc('associations/jba/domainControl/current').set({...fixture.associationControlBase, authorityMode: mode});
  await db.doc('associations/jba/access/operator').set({...fixture.associationEnvelopeBase, grants: {}});
  await db.doc(`${seasonPath}/control/current`).set({...fixture.seasonControlBase});
  await db.doc(`${seasonPath}/access/operator`).set({...fixture.seasonEnvelopeBase, grants: {[grantKey(statsGrant)]: statsGrant}});
  await db.doc(`${seasonPath}/games/game-1`).set({...fixture.gameBase});
  await db.doc(`${seasonPath}/games/game-1/assignments/operator`).set({...fixture.assignmentBase});
}

const statsRequest = {
  uid: 'operator',
  scope: {...fixture.scopes.game},
  capability: 'stats.enter',
  versions: {...fixture.versionsWithCalculator},
  writerEpoch: fixture.assignmentBase.writerEpoch,
  expectedAssignmentVersion: fixture.assignmentBase.assignmentVersion,
  expectedGameControlVersion: fixture.gameBase.controlVersion,
};

test.beforeEach(clear);

test('transaction wrapper reads the shared persisted schema once and returns complete bindings', async () => {
  await seedStats();
  const result = await db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, statsRequest));
  assert.equal(result.authorized, true);
  assert.equal(result.grant.grantKey, 'stats.enter|division|premier');
  assert.equal(result.associationControlVersion, 2);
  assert.equal(result.seasonControlVersion, 7);
  assert.equal(result.game.controlVersion, 11);
  assert.equal(result.assignment.assignmentVersion, 4);
});

test('association-only action constructs no season, game, or assignment reads', async () => {
  const associationGrant = persistedGrant('players.manage', 'association');
  const documents = new Map([
    ['memberships/operator', {...fixture.membershipBase, capabilities: ['players.manage']}],
    ['associations/jba/domainControl/current', {...fixture.associationControlBase}],
    ['associations/jba/access/operator', {...fixture.associationEnvelopeBase, grants: {[grantKey(associationGrant)]: associationGrant}}],
  ]);
  const observedPaths = [];
  const fakeDb = {doc: (documentPath) => ({path: documentPath})};
  const fakeTransaction = {
    getAll: async (...refs) => {
      observedPaths.push(...refs.map((ref) => ref.path));
      return refs.map((ref) => ({exists: documents.has(ref.path), data: () => documents.get(ref.path)}));
    },
  };
  const result = await requireScopedAuthorityInTransaction(fakeTransaction, fakeDb, {
    uid: 'operator', capability: 'players.manage', scope: {...fixture.scopes.association},
    versions: {...fixture.versionsWithoutCalculator},
  });
  assert.equal(result.authorized, true);
  assert.deepEqual(observedPaths, [
    'memberships/operator',
    'associations/jba/domainControl/current',
    'associations/jba/access/operator',
  ]);
});

test('transaction re-read denies association shadow, revoked membership, and stale independent optimistic versions', async () => {
  await seedStats('shadow');
  await assert.rejects(
    db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, statsRequest)),
    (error) => error instanceof ScopedAuthorityError && error.code === 'authority_shadow_only',
  );
  await db.doc('associations/jba/domainControl/current').update({authorityMode: 'v2'});
  await db.doc('memberships/operator').update({status: 'revoked'});
  await assert.rejects(
    db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, statsRequest)),
    (error) => error.code === 'membership_denied',
  );
  await seedStats();
  await assert.rejects(
    db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, {...statsRequest, expectedGameControlVersion: 7})),
    (error) => error.code === 'stale_control_version',
  );
  await assert.rejects(
    db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, {...statsRequest, expectedAssignmentVersion: 3})),
    (error) => error.code === 'stale_assignment_version',
  );
});

test('transaction wrapper rejects omitted division grants, wrong slots, and old array access forms', async () => {
  await seedStats();
  const malformed = persistedGrant('games.schedule', 'division');
  delete malformed.divisionId;
  await db.doc('memberships/operator').update({capabilities: ['games.schedule']});
  const request = {
    uid: 'operator', capability: 'games.schedule', scope: {...fixture.scopes.division},
    versions: {...fixture.versionsWithoutCalculator},
  };
  for (const grants of [
    {'games.schedule|division|premier': malformed},
    {'games.schedule|division|wrong': persistedGrant('games.schedule', 'division')},
    [persistedGrant('games.schedule', 'division')],
  ]) {
    await db.doc(`${seasonPath}/access/operator`).set({...fixture.seasonEnvelopeBase, grants});
    await assert.rejects(
      db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, request)),
      (error) => error instanceof ScopedAuthorityError && error.code === 'scope_denied',
    );
  }
});

test('calculator-required wrapper rejects omission and either control allowlist gap', async () => {
  await seedStats();
  for (const request of [
    {...statsRequest, versions: {...fixture.versionsWithoutCalculator}},
    statsRequest,
    statsRequest,
  ]) {
    if (request === statsRequest && (await db.doc('associations/jba/domainControl/current').get()).data().acceptedCalculatorVersions.length) {
      await db.doc('associations/jba/domainControl/current').update({acceptedCalculatorVersions: []});
    } else if (request === statsRequest) {
      await db.doc('associations/jba/domainControl/current').update({acceptedCalculatorVersions: ['calc-v1']});
      await db.doc(`${seasonPath}/control/current`).update({acceptedCalculatorVersions: []});
    }
    await assert.rejects(
      db.runTransaction((transaction) => requireScopedAuthorityInTransaction(transaction, db, request)),
      (error) => error.code === 'unsupported_calculator',
    );
  }
});
