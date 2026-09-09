'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp({projectId: 'demo-hoopsconnect'});

const {
  AssignedGameBootstrapError,
  requireAssignedGameBootstrapReadInTransaction,
} = require('../lib/domain/assigned_game_bootstrap');

const authorityFixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/authority_fixtures.json'),
  'utf8',
));
const bootstrapFixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '../../contracts/official_stats/v2/assigned_game_bootstrap_fixtures.json'),
  'utf8',
));
const db = admin.firestore();
const seasonPath = 'associations/jba/competitions/nbl/seasons/s2026';
const gamePath = `${seasonPath}/games/game-1`;

function timestamp(value) {
  return admin.firestore.Timestamp.fromDate(new Date(value));
}

function divisionGrant(changes = {}) {
  return {
    grantId: 'grant-stats-enter', capability: 'stats.enter', scopeKind: 'division',
    associationId: 'jba', competitionId: 'nbl', seasonId: 's2026', divisionId: 'premier',
    status: 'active', membershipVersion: 7,
    effectiveFrom: timestamp('2020-01-01T00:00:00.000Z'), effectiveTo: null,
    ...changes,
  };
}

function associationGrant() {
  return {
    grantId: 'grant-stats-enter-association', capability: 'stats.enter', scopeKind: 'association',
    associationId: 'jba', status: 'active', membershipVersion: 7,
    effectiveFrom: timestamp('2020-01-01T00:00:00.000Z'), effectiveTo: null,
  };
}

async function clear() {
  for (const collection of await db.listCollections()) await db.recursiveDelete(collection);
}

async function seed(options = {}) {
  const grant = divisionGrant();
  await db.doc('memberships/operator').set({...authorityFixture.membershipBase, capabilities: ['stats.enter']});
  await db.doc('associations/jba/domainControl/current').set({...authorityFixture.associationControlBase});
  if (!options.omitAssociationAccess) {
    await db.doc('associations/jba/access/operator').set({...authorityFixture.associationEnvelopeBase, grants: {}});
  }
  await db.doc(`${seasonPath}/control/current`).set({...authorityFixture.seasonControlBase});
  if (!options.omitSeasonAccess) {
    await db.doc(`${seasonPath}/access/operator`).set({
      ...authorityFixture.seasonEnvelopeBase,
      grants: {'stats.enter|division|premier': grant},
    });
  }
  await db.doc(gamePath).set({...authorityFixture.gameBase});
  await db.doc(`${gamePath}/assignments/operator`).set({...authorityFixture.assignmentBase});
}

async function read(request = bootstrapFixture.requestBase) {
  return db.runTransaction((transaction) =>
    requireAssignedGameBootstrapReadInTransaction(transaction, db, 'operator', request));
}

test.beforeEach(clear);

test('transaction reads one coherent seven-path snapshot and returns only frozen authority plus DTO', async () => {
  await seed();
  const result = await read();
  assert.equal(result.authority.kind, 'assignedGameBootstrapReadAllowed');
  assert.equal(result.authority.grant.origin, 'season');
  assert.equal(result.dto.kind, 'assignedGameBootstrap');
  assert.equal(result.dto.gameControlVersion, 11);
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.dto.assignment.duties), true);
});

test('transaction constructs exactly seven paths from trusted uid and the exact locator', async () => {
  const documents = new Map();
  const grant = divisionGrant();
  documents.set('memberships/operator', {...authorityFixture.membershipBase, capabilities: ['stats.enter']});
  documents.set('associations/jba/domainControl/current', {...authorityFixture.associationControlBase});
  documents.set('associations/jba/access/operator', {...authorityFixture.associationEnvelopeBase, grants: {}});
  documents.set(`${seasonPath}/control/current`, {...authorityFixture.seasonControlBase});
  documents.set(`${seasonPath}/access/operator`, {...authorityFixture.seasonEnvelopeBase, grants: {'stats.enter|division|premier': grant}});
  documents.set(gamePath, {...authorityFixture.gameBase});
  documents.set(`${gamePath}/assignments/operator`, {...authorityFixture.assignmentBase});
  const observed = [];
  const fakeDb = {doc: (documentPath) => ({path: documentPath})};
  const fakeTransaction = {getAll: async (...refs) => {
    observed.push(...refs.map((ref) => ref.path));
    return refs.map((ref) => ({exists: documents.has(ref.path), data: () => documents.get(ref.path)}));
  }};
  const result = await requireAssignedGameBootstrapReadInTransaction(
    fakeTransaction, fakeDb, 'operator', bootstrapFixture.requestBase,
  );
  assert.equal(result.authority.uid, 'operator');
  assert.deepEqual(observed, [
    'memberships/operator',
    'associations/jba/domainControl/current',
    'associations/jba/access/operator',
    `${seasonPath}/control/current`,
    `${seasonPath}/access/operator`,
    gamePath,
    `${gamePath}/assignments/operator`,
  ]);
});

test('transaction rejects forged request fields before reading any document', async () => {
  let readCalled = false;
  const fakeDb = {doc: (documentPath) => ({path: documentPath})};
  const fakeTransaction = {getAll: async () => {
    readCalled = true;
    return [];
  }};
  await assert.rejects(
    requireAssignedGameBootstrapReadInTransaction(
      fakeTransaction,
      fakeDb,
      'operator',
      {...bootstrapFixture.requestBase, capability: 'stats.submit'},
    ),
    (error) => error instanceof AssignedGameBootstrapError && error.code === 'invalid_request',
  );
  assert.equal(readCalled, false);
});

test('fresh transaction re-reads every revocation and stale-state fence', async () => {
  const mutations = [
    async () => db.doc('memberships/operator').update({status: 'revoked'}),
    async () => db.doc('associations/jba/domainControl/current').update({authorityMode: 'shadow'}),
    async () => db.doc(`${seasonPath}/control/current`).update({authorityMode: 'disabled'}),
    async () => db.doc('associations/jba/access/operator').update({extra: true}),
    async () => db.doc(`${seasonPath}/access/operator`).update({membershipVersion: 6}),
    async () => db.doc(gamePath).update({awayTeamEntryId: 'team-a'}),
    async () => db.doc(`${gamePath}/assignments/operator`).update({extra: true}),
  ];
  for (const mutate of mutations) {
    await clear();
    await seed();
    await mutate();
    await assert.rejects(read(), (error) => error instanceof AssignedGameBootstrapError);
  }
});

test('transaction selected-origin behavior supports either absent unused access source', async () => {
  await seed({omitAssociationAccess: true});
  assert.equal((await read()).authority.grant.origin, 'season');

  await clear();
  await seed({omitSeasonAccess: true});
  const grant = associationGrant();
  await db.doc('associations/jba/access/operator').set({
    ...authorityFixture.associationEnvelopeBase,
    grants: {'stats.enter|association': grant},
  });
  assert.equal((await read()).authority.grant.origin, 'association');
});

test('compiled deployed Function surface does not export the bootstrap service', () => {
  const compiledIndex = fs.readFileSync(path.join(__dirname, '../lib/index.js'), 'utf8');
  assert.doesNotMatch(compiledIndex, /assigned_game_bootstrap/);
  assert.doesNotMatch(compiledIndex, /getAssignedGameBootstrapV2/);
});
