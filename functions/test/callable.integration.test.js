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

async function createLeagueOperator(email, role, capabilities, teamId = null) {
  await signOut(auth);
  const credential = await createUserWithEmailAndPassword(
    auth,
    email,
    'correct-horse-battery-staple',
  );
  await adminDb.doc('users/' + credential.user.uid).set({
    email,
    displayName: role === 'rep' ? 'Team Representative' : 'League Operator',
    associationId: 'jba',
    role,
    teamId,
    authorizationSchemaVersion: 1,
  });
  await adminDb.doc('memberships/' + credential.user.uid).set({
    associationId: 'jba',
    role,
    teamId,
    status: 'active',
    capabilities,
    authorizationSchemaVersion: 1,
  });
  return credential.user.uid;
}

async function seedLeagueOperations() {
  await adminDb.doc('associations/jba').set({
    name: 'JBA',
    currentSeasonId: 's2026',
  }, {merge: true});
  await adminDb.doc('associations/jba/leagueWorkflowControl/current').set({
    schemaVersion: 1,
    associationId: 'jba',
    competitionId: 'nbl',
    activeSeasonId: 's2026',
    defaultPhaseId: 'regular',
    timezone: 'America/Jamaica',
    authorityMode: 'legacyV1',
    callablesReady: true,
    directWritesDenied: true,
    lifecycleAuthorityReady: true,
    custodyAuthorityReady: true,
    rosters: true,
    divisionDeletion: true,
    scheduling: true,
  });
  await adminDb.doc('associations/jba/seasons/s2026').set({name: '2026', status: 'active'});
  await adminDb.doc('associations/jba/divisions/premier').set({name: 'Premier', status: 'active', version: 7});
  await adminDb.doc('associations/jba/teams/team-a').set({
    name: 'Team A', seasonId: 's2026', divisionId: 'premier', status: 'active', teamEntryId: 'entry-a',
  });
  await adminDb.doc('associations/jba/teams/team-b').set({
    name: 'Team B', seasonId: 's2026', divisionId: 'premier', status: 'active', teamEntryId: 'entry-b',
  });
  await adminDb.doc('associations/jba/teams/team-c').set({
    name: 'Team C', seasonId: 's2026', divisionId: 'premier', status: 'active', teamEntryId: 'entry-c',
  });
  for (const [teamId, teamEntryId] of [['team-a', 'entry-a'], ['team-b', 'entry-b'], ['team-c', 'entry-c']]) {
    await adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/teamEntries/${teamEntryId}`).set({
      dataSchemaVersion: 2,
      associationId: 'jba',
      competitionId: 'nbl',
      seasonId: 's2026',
      divisionId: 'premier',
      teamEntryId,
      teamId,
      seasonalIdentityVersionId: `identity-${teamEntryId}`,
      registrationStatus: 'active',
    });
  }
}

test('league operation callables stay closed until every server readiness fact is true', async () => {
  await seedLeagueOperations();
  await adminDb.doc('associations/jba/leagueWorkflowControl/current').update({
    lifecycleAuthorityReady: false,
  });
  await createLeagueOperator('closed-scheduler@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = httpsCallable(functions, 'scheduleGame');
  await assert.rejects(
    schedule({
      schemaVersion: 1,
      operationId: 'schedule_closed_gate_01',
      seasonId: 's2026',
      divisionId: 'premier',
      homeTeamId: 'team-a',
      awayTeamId: 'team-b',
      startTimeUtc: '2026-09-12T01:00:00.000Z',
      endTimeUtc: '2026-09-12T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  assert.equal((await adminDb.collection('associations/jba/events').get()).empty, true);
});

test('roster callables preserve exact jersey strings and representative proposals', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('roster-admin@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const submit = httpsCallable(functions, 'submitRosterChange');
  const workspace = httpsCallable(functions, 'getRosterWorkspace');
  const firstRequest = {
    schemaVersion: 1,
    operationId: 'roster_admin_add_0001',
    teamId: 'team-a',
    seasonId: 's2026',
    expectedRosterVersion: 0,
    kind: 'addPlayer',
    requestedOutcome: 'propose',
    displayName: 'Aaliyah Brown',
    jerseyNumber: '00',
    reason: 'New registration',
  };
  const first = await submit(firstRequest);
  const retry = await submit(firstRequest);
  assert.deepEqual(retry.data, first.data);
  assert.equal(first.data.status, 'approved');
  assert.equal(first.data.rosterVersion, 1);
  assert.ok(first.data.playerId);
  assert.ok(first.data.registrationId);
  assert.equal((await adminDb.collection('associations/jba/playerSeasonStats').get()).empty, true);
  const loaded = await workspace({schemaVersion: 1, teamId: 'team-a', seasonId: 's2026'});
  assert.equal(loaded.data.registrations[0].jerseyNumber, '00');
  assert.equal(Object.hasOwn(loaded.data.registrations[0], 'position'), false);

  await assert.rejects(
    submit({...firstRequest, displayName: 'Changed semantics'}),
    (error) => error.code === 'functions/already-exists',
  );

  await createLeagueOperator('roster-rep@example.com', 'rep', [
    'association.read', 'teams.represent',
  ], 'team-a');
  const proposal = await submit({
    schemaVersion: 1,
    operationId: 'roster_rep_add_000001',
    teamId: 'team-a',
    seasonId: 's2026',
    expectedRosterVersion: 1,
    kind: 'addPlayer',
    requestedOutcome: 'apply',
    displayName: 'Jordan Smith',
    jerseyNumber: '0',
    reason: 'Team request',
  });
  assert.equal(proposal.data.status, 'pending');
  assert.equal(proposal.data.rosterVersion, 1);
  await assert.rejects(
    submit({
      schemaVersion: 1,
      operationId: 'roster_rep_wrong_0001',
      teamId: 'team-b',
      seasonId: 's2026',
      expectedRosterVersion: 0,
      kind: 'addPlayer',
      requestedOutcome: 'propose',
      displayName: 'Wrong Team',
      jerseyNumber: '1',
      reason: 'Should be denied',
    }),
    (error) => error.code === 'functions/permission-denied',
  );

  await createLeagueOperator('roster-reviewer@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const review = httpsCallable(functions, 'reviewRosterProposal');
  const reviewRequest = {
    schemaVersion: 1,
    operationId: 'roster_review_000001',
    proposalId: proposal.data.proposalId,
    teamId: 'team-a',
    seasonId: 's2026',
    expectedRosterVersion: 1,
    decision: 'approve',
  };
  const approved = await review(reviewRequest);
  const approvedRetry = await review(reviewRequest);
  assert.deepEqual(approvedRetry.data, approved.data);
  assert.equal(approved.data.rosterVersion, 2);
  const finalWorkspace = await workspace({schemaVersion: 1, teamId: 'team-a', seasonId: 's2026'});
  assert.deepEqual(finalWorkspace.data.registrations.map((entry) => entry.jerseyNumber).sort(), ['0', '00']);

  await adminDb.doc('associations/jba/divisions/premier').update({
    deletionPending: {schemaVersion: 1, operationId: 'delete_in_progress_01'},
  });
  await assert.rejects(
    submit({
      ...firstRequest,
      operationId: 'roster_while_delete_01',
      expectedRosterVersion: 2,
      displayName: 'Blocked Player',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
});

test('schedule callables serialize conflicts, replay exactly, and preserve cancellation history', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('scheduler@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = httpsCallable(functions, 'scheduleGame');
  const mutate = httpsCallable(functions, 'mutateScheduledGame');
  const requestData = {
    schemaVersion: 1,
    operationId: 'schedule_create_00001',
    seasonId: 's2026',
    divisionId: 'premier',
    homeTeamId: 'team-a',
    awayTeamId: 'team-b',
    startTimeUtc: '2026-09-13T01:00:00.000Z',
    endTimeUtc: '2026-09-13T03:00:00.000Z',
    location: 'National Arena',
  };
  const created = await schedule(requestData);
  assert.deepEqual((await schedule(requestData)).data, created.data);
  await assert.rejects(
    schedule({...requestData, location: 'Changed venue'}),
    (error) => error.code === 'functions/already-exists',
  );
  await assert.rejects(
    schedule({
      ...requestData,
      operationId: 'schedule_overlap_0001',
      homeTeamId: 'team-a',
      awayTeamId: 'team-c',
      startTimeUtc: '2026-09-13T02:30:00.000Z',
      endTimeUtc: '2026-09-13T04:30:00.000Z',
    }),
    (error) => error.code === 'functions/already-exists',
  );
  const cancelled = await mutate({
    schemaVersion: 1,
    operationId: 'schedule_cancel_0001',
    eventId: created.data.eventId,
    expectedScheduleVersion: 1,
    action: 'cancel',
    reason: 'Venue unavailable',
  });
  assert.equal(cancelled.data.status, 'cancelled');
  const event = await adminDb.doc(`associations/jba/events/${created.data.eventId}`).get();
  assert.equal(event.get('status'), 'cancelled');
  assert.equal(event.get('scheduleVersion'), 2);
  const revisions = await adminDb.collection(
    `associations/jba/competitions/nbl/seasons/s2026/games/${created.data.eventId}/scheduleRevisions`,
  ).get();
  assert.equal(revisions.size, 2);
});

test('division deletion returns malformed references as blockers and replays the receipt', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('division-ordinary@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const remove = httpsCallable(functions, 'deleteDivisionIfUnreferenced');
  await assert.rejects(
    remove({
      schemaVersion: 1,
      operationId: 'division_admin_denied_1',
      divisionId: 'premier',
      expectedDivisionVersion: 7,
    }),
    (error) => error.code === 'functions/permission-denied',
  );
  await createLeagueOperator('division-admin@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  await adminDb.doc('associations/jba/divisions/empty').set({name: 'Empty', status: 'active', version: 1});
  await adminDb.doc('associations/jba/events/malformed-event').set({divisionId: 'premier', type: 'game'});
  const blockedRequest = {
    schemaVersion: 1,
    operationId: 'division_delete_0001',
    divisionId: 'premier',
    expectedDivisionVersion: 7,
  };
  const blocked = await remove(blockedRequest);
  assert.equal(blocked.data.status, 'blocked');
  assert.ok(blocked.data.references.some((entry) => entry.id === 'malformed-event' && entry.displayName === null));
  const retainedDivision = await adminDb.doc('associations/jba/divisions/premier').get();
  assert.equal(retainedDivision.exists, true);
  assert.equal(retainedDivision.get('deletionPending'), undefined);
  assert.deepEqual((await remove(blockedRequest)).data, blocked.data);
  const deleted = await remove({
    schemaVersion: 1,
    operationId: 'division_delete_0002',
    divisionId: 'empty',
    expectedDivisionVersion: 1,
  });
  assert.equal(deleted.data.status, 'deleted');
  assert.equal((await adminDb.doc('associations/jba/divisions/empty').get()).exists, false);
});

test('v2 scheduling requires the exact scoped grant and never falls back to legacy capability strings', async () => {
  await seedLeagueOperations();
  await adminDb.doc('associations/jba/leagueWorkflowControl/current').update({authorityMode: 'v2'});
  await signOut(auth);
  const credential = await createUserWithEmailAndPassword(
    auth,
    'scheduler-v2@example.com',
    'correct-horse-battery-staple',
  );
  const uid = credential.user.uid;
  await adminDb.doc(`memberships/${uid}`).set({
    authorizationSchemaVersion: 2,
    associationId: 'jba',
    status: 'active',
    membershipVersion: 7,
    capabilities: ['games.schedule'],
  });
  const associationControl = {
    dataSchemaVersion: 2,
    associationId: 'jba',
    authorityMode: 'v2',
    minimumAuthorizationSchemaVersion: 2,
    minimumDomainSchemaVersion: 2,
    minimumCommandSchemaVersion: 2,
    acceptedCalculatorVersions: ['calc-v1'],
    controlVersion: 2,
  };
  const seasonControl = {
    ...associationControl,
    competitionId: 'nbl',
    seasonId: 's2026',
    controlVersion: 7,
  };
  const grant = {
    grantId: 'grant-games-schedule',
    capability: 'games.schedule',
    scopeKind: 'division',
    associationId: 'jba',
    competitionId: 'nbl',
    seasonId: 's2026',
    divisionId: 'premier',
    status: 'active',
    membershipVersion: 7,
    effectiveFrom: admin.firestore.Timestamp.fromDate(new Date('2026-01-01T00:00:00.000Z')),
    effectiveTo: null,
  };
  await adminDb.doc('associations/jba/domainControl/current').set(associationControl);
  await adminDb.doc('associations/jba/competitions/nbl/seasons/s2026/control/current').set(seasonControl);
  await adminDb.doc(`associations/jba/access/${uid}`).set({
    dataSchemaVersion: 2,
    authorizationSchemaVersion: 2,
    uid,
    associationId: 'jba',
    scopeKind: 'association',
    status: 'active',
    membershipVersion: 7,
    accessVersion: 1,
    grants: {},
  });
  await adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/access/${uid}`).set({
    dataSchemaVersion: 2,
    authorizationSchemaVersion: 2,
    uid,
    associationId: 'jba',
    competitionId: 'nbl',
    seasonId: 's2026',
    scopeKind: 'season',
    status: 'active',
    membershipVersion: 7,
    accessVersion: 1,
    grants: {'games.schedule|division|premier': grant},
  });
  const schedule = httpsCallable(functions, 'scheduleGame');
  const created = await schedule({
    schemaVersion: 1,
    operationId: 'schedule_v2_create_01',
    seasonId: 's2026',
    divisionId: 'premier',
    homeTeamId: 'team-b',
    awayTeamId: 'team-c',
    startTimeUtc: '2026-10-01T01:00:00.000Z',
    endTimeUtc: '2026-10-01T03:00:00.000Z',
  });
  assert.equal(created.data.status, 'created');

  await adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/access/${uid}`).update({grants: {}});
  await assert.rejects(
    schedule({
      schemaVersion: 1,
      operationId: 'schedule_v2_denied_01',
      seasonId: 's2026',
      divisionId: 'premier',
      homeTeamId: 'team-a',
      awayTeamId: 'team-c',
      startTimeUtc: '2026-10-02T01:00:00.000Z',
      endTimeUtc: '2026-10-02T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/permission-denied',
  );

  const rosterGrant = {
    ...grant,
    grantId: 'grant-rosters-assert',
    capability: 'rosters.assert',
    scopeKind: 'teamEntry',
    teamEntryId: 'entry-a',
  };
  await adminDb.doc(`memberships/${uid}`).update({
    capabilities: ['rosters.assert'],
  });
  await adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/access/${uid}`).update({
    grants: {'rosters.assert|teamEntry|premier|entry-a': rosterGrant},
  });
  const submitRoster = httpsCallable(functions, 'submitRosterChange');
  const rosterHead = await adminDb.doc(
    'associations/jba/competitions/nbl/seasons/s2026/rosterHeads/entry-a',
  ).get();
  const currentRosterVersion = rosterHead.get('rosterVersion') ?? 0;
  await assert.rejects(
    submitRoster({
      schemaVersion: 1,
      operationId: 'roster_v2_wrong_team_1',
      teamId: 'team-b',
      seasonId: 's2026',
      expectedRosterVersion: 0,
      kind: 'addPlayer',
      requestedOutcome: 'propose',
      displayName: 'Wrong Team',
      jerseyNumber: '8',
      reason: 'Must be exact scoped',
    }),
    (error) => error.code === 'functions/permission-denied',
  );
  const v2Proposal = await submitRoster({
    schemaVersion: 1,
    operationId: 'roster_v2_exact_team_1',
    teamId: 'team-a',
    seasonId: 's2026',
    expectedRosterVersion: currentRosterVersion,
    kind: 'addPlayer',
    requestedOutcome: 'apply',
    displayName: 'Exact Team',
    jerseyNumber: '08',
    reason: 'Scoped representative proposal',
  });
  assert.equal(v2Proposal.data.status, 'pending');
  await adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/access/${uid}`).update({grants: {}});
  await assert.rejects(
    submitRoster({
      schemaVersion: 1,
      operationId: 'roster_v2_no_fallback_1',
      teamId: 'team-a',
      seasonId: 's2026',
      expectedRosterVersion: currentRosterVersion,
      kind: 'addPlayer',
      requestedOutcome: 'apply',
      displayName: 'No Fallback',
      jerseyNumber: '9',
      reason: 'Legacy capability must not apply',
    }),
    (error) => error.code === 'functions/permission-denied',
  );
});

test('batch, concurrent, cross-midnight, stale, and approved-game schedule guards hold', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('scheduler-guards@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = httpsCallable(functions, 'scheduleGame');
  const batch = httpsCallable(functions, 'createScheduleBatch');
  const mutate = httpsCallable(functions, 'mutateScheduledGame');

  const batchRequest = {
    schemaVersion: 1,
    operationId: 'schedule_batch_000001',
    games: [
      {
        itemKey: 'round_001', seasonId: 's2026', divisionId: 'premier',
        homeTeamId: 'team-a', awayTeamId: 'team-b',
        startTimeUtc: '2026-11-01T01:00:00.000Z', endTimeUtc: '2026-11-01T03:00:00.000Z',
      },
      {
        itemKey: 'round_002', seasonId: 's2026', divisionId: 'premier',
        homeTeamId: 'team-a', awayTeamId: 'team-c',
        startTimeUtc: '2026-11-02T01:00:00.000Z', endTimeUtc: '2026-11-02T03:00:00.000Z',
      },
    ],
  };
  const batchResult = await batch(batchRequest);
  assert.equal(batchResult.data.results.length, 2);
  assert.deepEqual((await batch(batchRequest)).data, batchResult.data);

  const racingBase = {
    schemaVersion: 1, seasonId: 's2026', divisionId: 'premier',
    homeTeamId: 'team-b', awayTeamId: 'team-c',
    startTimeUtc: '2026-11-03T01:00:00.000Z', endTimeUtc: '2026-11-03T03:00:00.000Z',
  };
  const racing = await Promise.allSettled([
    schedule({...racingBase, operationId: 'schedule_race_left_001'}),
    schedule({...racingBase, operationId: 'schedule_race_right_01'}),
  ]);
  assert.equal(racing.filter((entry) => entry.status === 'fulfilled').length, 1);
  assert.equal(racing.filter((entry) => entry.status === 'rejected').length, 1);

  await schedule({
    schemaVersion: 1, operationId: 'schedule_midnight_0001',
    seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-a', awayTeamId: 'team-b',
    startTimeUtc: '2026-11-04T23:30:00.000Z', endTimeUtc: '2026-11-05T01:30:00.000Z',
  });
  await assert.rejects(
    schedule({
      schemaVersion: 1, operationId: 'schedule_midnight_0002',
      seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-a', awayTeamId: 'team-c',
      startTimeUtc: '2026-11-05T01:00:00.000Z', endTimeUtc: '2026-11-05T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/already-exists',
  );

  const immutable = await schedule({
    schemaVersion: 1, operationId: 'schedule_immutable_001',
    seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-b', awayTeamId: 'team-c',
    startTimeUtc: '2026-11-06T01:00:00.000Z', endTimeUtc: '2026-11-06T03:00:00.000Z',
  });
  await adminDb.doc(`associations/jba/gameStats/${immutable.data.eventId}`).set({status: 'approved'});
  await assert.rejects(
    mutate({
      schemaVersion: 1,
      operationId: 'schedule_edit_denied_01',
      eventId: immutable.data.eventId,
      expectedScheduleVersion: 1,
      action: 'edit',
      location: 'Must remain immutable',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  await assert.rejects(
    mutate({
      schemaVersion: 1,
      operationId: 'schedule_cancel_denied_1',
      eventId: immutable.data.eventId,
      expectedScheduleVersion: 1,
      action: 'cancel',
      reason: 'Should not erase approved history',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  await assert.rejects(
    mutate({
      schemaVersion: 1,
      operationId: 'schedule_stale_edit_01',
      eventId: immutable.data.eventId,
      expectedScheduleVersion: 99,
      action: 'edit',
      location: 'Changed',
    }),
    (error) => error.code === 'functions/aborted',
  );

  await adminDb.doc('associations/jba/teams/team-c').update({status: 'archived'});
  await assert.rejects(
    schedule({
      schemaVersion: 1, operationId: 'schedule_archived_team_1',
      seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-a', awayTeamId: 'team-c',
      startTimeUtc: '2026-11-08T01:00:00.000Z', endTimeUtc: '2026-11-08T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  await adminDb.doc('associations/jba/teams/team-c').update({status: 'active'});
  await adminDb.doc('associations/jba/divisions/premier').update({status: 'archived'});
  await assert.rejects(
    schedule({
      schemaVersion: 1, operationId: 'schedule_archived_div_01',
      seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-a', awayTeamId: 'team-c',
      startTimeUtc: '2026-11-09T01:00:00.000Z', endTimeUtc: '2026-11-09T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
});
