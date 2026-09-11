'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';

const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
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
const leagueOperations = require('../lib/league_operations');
const seasonOperations = require('../lib/season_operations');
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
  await activateLeagueActor(credential.user, 1);
  return credential.user.uid;
}

async function activateLeagueActor(user, authorizationSchemaVersion) {
  const accountGenerationV2 = createHash('sha256')
    .update(`test-generation:${user.uid}`)
    .digest('hex');
  await admin.auth().setCustomUserClaims(user.uid, {
    authIncarnationSchemaVersionV2: 2,
    accountGenerationV2,
    accountLifecycleEpochV2: 1,
  });
  await adminDb.doc(`memberships/${user.uid}`).update({
    authIncarnationSchemaVersionV2: 2,
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: null,
    authUidV2: user.uid,
    accountGenerationV2,
    accountLifecycleEpochV2: 1,
    membershipStatusV2: 'active',
  });
  await adminDb.doc(`associations/jba/leagueActorAuthorities/${user.uid}`).set({
    schemaVersion: 1,
    authIncarnationSchemaVersionV2: 2,
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: null,
    authUidV2: user.uid,
    accountGenerationV2,
    accountLifecycleEpochV2: 1,
    lifecycleStateV2: 'active',
    membershipStatusV2: 'active',
    reauthAfterSecV2: 0,
    associationId: 'jba',
    authorizationSchemaVersion,
    operationalStateV2: 'operating',
    custodyStateV2: 'operating',
    custodyPolicyVersionV2: 1,
    identitySuppressedV2: false,
    privacyStateV2: 'internal',
    privacyEpochV2: 1,
  });
  await user.getIdToken(true);
}

function leagueCallable(name) {
  return async (data) => {
    try {
      const handler = leagueOperations[`${name}Handler`] || seasonOperations[`${name}Handler`];
      return {data: await handler(await leagueRequest(data))};
    } catch (error) {
      if (typeof error?.code === 'string' && !error.code.startsWith('functions/')) {
        error.code = `functions/${error.code}`;
      }
      throw error;
    }
  };
}

async function leagueRequest(data) {
  const user = auth.currentUser;
  assert.ok(user, 'league callable test requires an authenticated user');
  const token = (await user.getIdTokenResult()).claims;
  return {
    auth: {uid: user.uid, token},
    app: {appId: 'test-app'},
    data,
  };
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
    actorAuthorityReady: true,
    identityAuthorityReady: true,
    privacyAuthorityReady: true,
    custodyPolicyVersionV2: 1,
    privacyEpochV2: 1,
    rosters: true,
    divisionDeletion: true,
    scheduling: true,
    seasonLifecycle: true,
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
  const schedule = leagueCallable('scheduleGame');
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
  const submit = leagueCallable('submitRosterChange');
  const workspace = leagueCallable('getRosterWorkspace');
  const firstRequest = {
    schemaVersion: 1,
    operationId: 'roster_admin_add_0001',
    teamId: 'team-a',
    seasonId: 's2026',
    expectedRosterVersion: 0,
    kind: 'addPlayer',
    requestedOutcome: 'propose',
    displayName: '  Aaliyah Brown  ',
    jerseyNumber: '00',
    reason: '  New registration  ',
  };
  const first = await submit(firstRequest);
  const retry = await submit({...firstRequest, displayName: 'Aaliyah Brown', reason: 'New registration'});
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
    jerseyNumber: 'GK-01',
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
  const review = leagueCallable('reviewRosterProposal');
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
  assert.deepEqual(finalWorkspace.data.registrations.map((entry) => entry.jerseyNumber).sort(), ['00', 'GK-01']);

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

test('roster proposal queue rejects a hostile 101st request while managers retain bounded recovery access', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('roster-flood-rep@example.com', 'rep', [
    'association.read', 'teams.represent',
  ], 'team-c');
  const root = 'associations/jba/competitions/nbl/seasons/s2026';
  const batch = adminDb.batch();
  const now = admin.firestore.Timestamp.now();
  const proposalFacts = {
    playerId: null,
    registrationId: null,
    displayName: 'Queued Player',
    jerseyNumber: '1',
    position: null,
  };
  for (let index = 0; index < 101; index += 1) {
    const proposalId = `historical-proposal-${index}`;
    batch.set(adminDb.doc(`${root}/rosterAssertions/${proposalId}`), {
      schemaVersion: 1, proposalId, associationId: 'jba', competitionId: 'nbl',
      teamId: 'team-c', teamEntryId: 'entry-c', divisionId: 'premier', seasonId: 's2026',
      kind: 'addPlayer', status: 'pending', before: null, after: proposalFacts,
      reason: 'Historical request', requestedBy: 'historical-rep', requestedByName: 'Historical Rep',
      requestedAt: now, expectedRosterVersion: 0, reviewNote: null,
    });
    batch.set(adminDb.doc(`${root}/rosterAssertionDecisions/${proposalId}`), {
      schemaVersion: 1, proposalId, associationId: 'jba', competitionId: 'nbl',
      teamId: 'team-c', teamEntryId: 'entry-c', divisionId: 'premier', seasonId: 's2026',
      decision: 'reject', actorId: 'historical-manager', createdAt: now,
    });
  }
  for (let index = 0; index < 100; index += 1) {
    const proposalId = `outstanding-proposal-${index}`;
    batch.set(adminDb.doc(`${root}/rosterAssertions/${proposalId}`), {
      schemaVersion: 1, proposalId, associationId: 'jba', competitionId: 'nbl',
      teamId: 'team-c', teamEntryId: 'entry-c', divisionId: 'premier', seasonId: 's2026',
      kind: 'addPlayer', status: 'pending', before: null, after: proposalFacts,
      reason: 'Outstanding request', requestedBy: 'queue-rep', requestedByName: 'Queue Rep',
      requestedAt: now, expectedRosterVersion: 0, reviewNote: null,
    });
    batch.set(adminDb.doc(`${root}/rosterOutstandingProposals/${proposalId}`), {
      schemaVersion: 1, proposalId, associationId: 'jba', competitionId: 'nbl',
      teamId: 'team-c', teamEntryId: 'entry-c', divisionId: 'premier', seasonId: 's2026',
      requestedBy: 'queue-rep', createdAt: now,
    });
  }
  batch.set(adminDb.doc(`${root}/rosterProposalQueues/entry-c`), {
    schemaVersion: 1, associationId: 'jba', competitionId: 'nbl', teamId: 'team-c',
    teamEntryId: 'entry-c', divisionId: 'premier', seasonId: 's2026',
    outstandingCount: 100, updatedAt: now,
  });
  await batch.commit();

  const submit = leagueCallable('submitRosterChange');
  await assert.rejects(submit({
    schemaVersion: 1, operationId: 'roster_hostile_101st_1', teamId: 'team-c', seasonId: 's2026',
    expectedRosterVersion: 0, kind: 'addPlayer', requestedOutcome: 'propose',
    displayName: 'Blocked Flood', jerseyNumber: '101', reason: 'Must remain bounded',
  }), (error) => error.code === 'functions/resource-exhausted');
  assert.equal((await adminDb.collection(`${root}/rosterOutstandingProposals`).get()).size, 100);

  await createLeagueOperator('roster-flood-manager@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const workspace = leagueCallable('getRosterWorkspace');
  const loaded = await workspace({schemaVersion: 1, teamId: 'team-c', seasonId: 's2026'});
  assert.equal(loaded.data.proposals.length, 100);
  assert.ok(loaded.data.proposals.every((entry) => entry.status === 'pending'));
  const review = leagueCallable('reviewRosterProposal');
  const approved = await review({
    schemaVersion: 1, operationId: 'roster_queue_recovery_1', proposalId: 'outstanding-proposal-0',
    teamId: 'team-c', seasonId: 's2026', expectedRosterVersion: 0,
    decision: 'approve',
  });
  assert.equal(approved.data.rosterVersion, 1);
  await review({
    schemaVersion: 1, operationId: 'roster_queue_recovery_2', proposalId: 'outstanding-proposal-1',
    teamId: 'team-c', seasonId: 's2026', expectedRosterVersion: 1,
    decision: 'reject', note: 'A stale proposal can still leave the active queue',
  });
  const recovered = await workspace({schemaVersion: 1, teamId: 'team-c', seasonId: 's2026'});
  assert.equal(recovered.data.proposals.length, 98);
  assert.equal((await adminDb.doc(`${root}/rosterProposalQueues/entry-c`).get()).get('outstandingCount'), 98);

  await createLeagueOperator('roster-queue-race-rep@example.com', 'rep', [
    'association.read', 'teams.represent',
  ], 'team-c');
  const raced = await Promise.allSettled([0, 1, 2].map((index) => submit({
    schemaVersion: 1, operationId: `roster_queue_race_${index}`, teamId: 'team-c', seasonId: 's2026',
    expectedRosterVersion: 1, kind: 'addPlayer', requestedOutcome: 'propose',
    displayName: `Race Player ${index}`, jerseyNumber: `R${index}`, reason: 'Concurrent bound test',
  })));
  assert.equal(raced.filter((entry) => entry.status === 'fulfilled').length, 2);
  assert.equal(raced.filter((entry) => entry.status === 'rejected' &&
    entry.reason.code === 'functions/resource-exhausted').length, 1);
  assert.equal((await adminDb.doc(`${root}/rosterProposalQueues/entry-c`).get()).get('outstandingCount'), 100);
});

test('schedule callables serialize conflicts, replay exactly, and preserve cancellation history', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('scheduler@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = leagueCallable('scheduleGame');
  const mutate = leagueCallable('mutateScheduledGame');
  const requestData = {
    schemaVersion: 1,
    operationId: 'schedule_create_00001',
    seasonId: 's2026',
    divisionId: 'premier',
    homeTeamId: 'team-a',
    awayTeamId: 'team-b',
    startTimeUtc: '2026-09-13T01:00:00.000Z',
    endTimeUtc: '2026-09-13T03:00:00.000Z',
    location: '  National Arena  ',
  };
  const created = await schedule(requestData);
  assert.deepEqual((await schedule({...requestData, location: 'National Arena'})).data, created.data);
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
  const cancellationRevision = revisions.docs.find((entry) => entry.id === 'schedule_2');
  assert.equal(cancellationRevision.get('actorId'), auth.currentUser.uid);
  assert.equal(cancellationRevision.get('title'), 'Team A vs Team B');
  assert.equal(cancellationRevision.get('description'), null);
  assert.equal(cancellationRevision.get('location'), 'National Arena');
  assert.equal(cancellationRevision.get('status'), 'cancelled');
  assert.equal(cancellationRevision.get('cancellationReason'), 'Venue unavailable');
});

test('division deletion returns malformed references as blockers and replays the receipt', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('division-ordinary@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const remove = leagueCallable('deleteDivisionIfUnreferenced');
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
  await adminDb.doc('associations/jba/divisions/legacy-zero').set({
    name: 'Legacy Zero', status: 'active',
  });
  const legacyDeleted = await remove({
    schemaVersion: 1,
    operationId: 'division_delete_zero_1',
    divisionId: 'legacy-zero',
    expectedDivisionVersion: 0,
  });
  assert.equal(legacyDeleted.data.status, 'deleted');
  assert.equal(legacyDeleted.data.divisionVersion, 0);
  assert.equal((await adminDb.doc('associations/jba/divisions/legacy-zero').get()).exists, false);
  await adminDb.doc('associations/jba/divisions/stale-delete').set({
    name: 'Stale Delete', status: 'active', version: 2,
  });
  await assert.rejects(remove({
    schemaVersion: 1,
    operationId: 'division_delete_stale_1',
    divisionId: 'stale-delete',
    expectedDivisionVersion: 1,
  }), (error) => {
    assert.equal(error.code, 'functions/aborted');
    assert.deepEqual(error.details, {
      schemaVersion: 1,
      reason: 'division-version-mismatch',
      actorId: auth.currentUser.uid,
      associationId: 'jba',
      operationId: 'division_delete_stale_1',
      divisionId: 'stale-delete',
      expectedDivisionVersion: 1,
      currentDivisionVersion: 2,
    });
    return true;
  });
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
  await activateLeagueActor(credential.user, 2);
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
  const schedule = leagueCallable('scheduleGame');
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
  const submitRoster = leagueCallable('submitRosterChange');
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
  const schedule = leagueCallable('scheduleGame');
  const batch = leagueCallable('createScheduleBatch');
  const mutate = leagueCallable('mutateScheduledGame');

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

test('league exports require App Check and a retry reauthorizes account lifecycle, custody, and freshness', async () => {
  assert.equal(leagueOperations.LEAGUE_CALLABLE_OPTIONS.enforceAppCheck, true);
  await seedLeagueOperations();
  const uid = await createLeagueOperator('reauth-replay@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = leagueCallable('scheduleGame');
  const requestData = {
    schemaVersion: 1, operationId: 'schedule_reauth_replay_1',
    seasonId: 's2026', divisionId: 'premier', homeTeamId: 'team-a', awayTeamId: 'team-b',
    startTimeUtc: '2026-12-01T01:00:00.000Z', endTimeUtc: '2026-12-01T03:00:00.000Z',
  };
  const first = await schedule(requestData);
  assert.equal(first.data.status, 'created');
  const projectionRef = adminDb.doc(`associations/jba/leagueActorAuthorities/${uid}`);
  await projectionRef.update({lifecycleStateV2: 'deleting'});
  await assert.rejects(schedule(requestData), (error) => error.code === 'functions/permission-denied');
  await projectionRef.update({lifecycleStateV2: 'active', custodyStateV2: 'suspendedToCustody'});
  await assert.rejects(schedule(requestData), (error) => error.code === 'functions/permission-denied');
  const token = (await auth.currentUser.getIdTokenResult()).claims;
  await projectionRef.update({custodyStateV2: 'operating', reauthAfterSecV2: token.auth_time});
  await assert.rejects(schedule(requestData), (error) => error.code === 'functions/permission-denied');
  await projectionRef.update({reauthAfterSecV2: 0});
  await adminDb.doc(`memberships/${uid}`).update({accountGenerationV2: 'f'.repeat(64)});
  await assert.rejects(schedule(requestData), (error) => error.code === 'functions/permission-denied');

  const networkSchedule = httpsCallable(functions, 'scheduleGame');
  await assert.rejects(
    networkSchedule({...requestData, operationId: 'schedule_missing_appcheck_1'}),
    (error) => error.code === 'functions/unauthenticated',
  );
});

test('roster reads and mutations require unsuppressed current identity chains and prohibit unguided renames', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('identity-roster@example.com', 'admin', [
    'association.read', 'teams.manage',
  ]);
  const submit = leagueCallable('submitRosterChange');
  const workspace = leagueCallable('getRosterWorkspace');
  const startingVersion = (await adminDb.doc(
    'associations/jba/competitions/nbl/seasons/s2026/rosterHeads/entry-a',
  ).get()).get('rosterVersion') ?? 0;
  const added = await submit({
    schemaVersion: 1, operationId: 'roster_identity_add_01', teamId: 'team-a', seasonId: 's2026',
    expectedRosterVersion: startingVersion, kind: 'addPlayer', requestedOutcome: 'apply',
    displayName: 'Current Identity', jerseyNumber: 'A1', reason: 'Identity test',
  });
  const registration = (await workspace({schemaVersion: 1, teamId: 'team-a', seasonId: 's2026'})).data.registrations
    .find((entry) => entry.playerId === added.data.playerId);
  assert.ok(registration);
  await assert.rejects(submit({
    schemaVersion: 1, operationId: 'roster_identity_rename_1', teamId: 'team-a', seasonId: 's2026',
    expectedRosterVersion: startingVersion + 1, kind: 'updatePlayer', requestedOutcome: 'apply',
    playerId: added.data.playerId, registrationId: added.data.registrationId,
    displayName: 'Ungoverned Rename', jerseyNumber: 'A1', reason: 'Should remain closed',
  }), (error) => error.code === 'functions/failed-precondition');

  const guardRef = adminDb.doc(`associations/jba/leagueIdentityAuthorities/${added.data.playerId}`);
  await guardRef.update({identitySuppressedV2: true});
  await assert.rejects(
    workspace({schemaVersion: 1, teamId: 'team-a', seasonId: 's2026'}),
    (error) => error.code === 'functions/failed-precondition',
  );
  await guardRef.update({identitySuppressedV2: false, currentPlayerDisplayNameVersionId: 'stale-version'});
  await assert.rejects(submit({
    schemaVersion: 1, operationId: 'roster_identity_stale_01', teamId: 'team-a', seasonId: 's2026',
    expectedRosterVersion: startingVersion + 1, kind: 'updatePlayer', requestedOutcome: 'apply',
    playerId: registration.playerId, registrationId: registration.registrationId,
    displayName: registration.displayName, jerseyNumber: 'A2', reason: 'Stale chain must fail',
  }), (error) => error.code === 'functions/failed-precondition');
});

test('schedule mutation rejects every started, submitted, rejected, final, or snapshotted state', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('lifecycle-scheduler@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const schedule = leagueCallable('scheduleGame');
  const mutate = leagueCallable('mutateScheduledGame');
  const created = await schedule({
    schemaVersion: 1, operationId: 'schedule_states_create_1', seasonId: 's2026', divisionId: 'premier',
    homeTeamId: 'team-a', awayTeamId: 'team-b',
    startTimeUtc: '2026-12-03T01:00:00.000Z', endTimeUtc: '2026-12-03T03:00:00.000Z',
  });
  const eventRef = adminDb.doc(`associations/jba/events/${created.data.eventId}`);
  const gameRef = adminDb.doc(`associations/jba/competitions/nbl/seasons/s2026/games/${created.data.eventId}`);
  const cases = [
    ['event-status-started', eventRef, {status: 'started'}],
    ['play-in-progress', gameRef, {playState: 'inProgress'}],
    ['stats-submitted', eventRef, {statsStatus: 'submitted'}],
    ['review-rejected', gameRef, {reviewState: 'rejected'}],
    ['stats-final', eventRef, {statsStatus: 'approved'}],
  ];
  for (const [label, reference, update] of cases) {
    await eventRef.update({status: 'scheduled', statsStatus: 'pending'});
    await gameRef.update({playState: 'scheduled', reviewState: 'none'});
    await reference.update(update);
    await assert.rejects(mutate({
      schemaVersion: 1, operationId: `schedule_state_${label}`, eventId: created.data.eventId,
      expectedScheduleVersion: 1, action: 'edit', location: `Blocked ${label}`,
    }), (error) => error.code === 'functions/failed-precondition', label);
  }
  await eventRef.update({status: 'scheduled', statsStatus: 'pending'});
  await gameRef.update({playState: 'scheduled', reviewState: 'none'});
  await gameRef.collection('participantSnapshots').doc('locked').set({divisionId: 'premier'});
  await assert.rejects(mutate({
    schemaVersion: 1, operationId: 'schedule_state_snapshot_1', eventId: created.data.eventId,
    expectedScheduleVersion: 1, action: 'cancel', reason: 'Must keep participant history',
  }), (error) => error.code === 'functions/failed-precondition');
});

test('division deletion resumes persisted operations and inventories canonical journal references', async () => {
  await seedLeagueOperations();
  const uid = await createLeagueOperator('division-recovery@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  const remove = leagueCallable('deleteDivisionIfUnreferenced');
  await adminDb.doc('associations/jba/divisions/recoverable').set({name: 'Recoverable', status: 'active', version: 1});
  const operationId = 'division_recovery_0001';
  const canonical = (value) => Array.isArray(value) ? value.map(canonical) :
    value && typeof value === 'object' ? Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonical(value[key]);
      return result;
    }, {}) : value;
  const digest = (value) => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
  const fingerprint = digest({schemaVersion: 1, operationId, divisionId: 'recoverable', expectedDivisionVersion: 1});
  const operationRef = adminDb.doc(
    `associations/jba/divisionDeletionOperations/${digest({actorId: uid, operationId})}`,
  );
  await operationRef.set({
    schemaVersion: 1, associationId: 'jba', actorId: uid, operationId,
    divisionId: 'recoverable', expectedDivisionVersion: 1, requestFingerprint: fingerprint,
    status: 'inventoryFailed', attempt: 1,
  });
  const recovered = await remove({
    schemaVersion: 1, operationId, divisionId: 'recoverable', expectedDivisionVersion: 1,
  });
  assert.equal(recovered.data.status, 'deleted');
  assert.equal((await operationRef.get()).get('status'), 'deleted');

  await adminDb.doc('associations/jba/divisions/inventory').set({name: 'Inventory', status: 'active', version: 1});
  await adminDb.doc(
    'associations/jba/competitions/nbl/seasons/s2026/games/inventory-game/workspaces/w1/operations/op1',
  ).set({associationId: 'jba', divisionId: 'inventory', displayName: 'Journal evidence'});
  const blocked = await remove({
    schemaVersion: 1, operationId: 'division_inventory_0001', divisionId: 'inventory', expectedDivisionVersion: 1,
  });
  assert.equal(blocked.data.status, 'blocked');
  assert.ok(blocked.data.references.some((entry) => entry.kind === 'journalOperation'));

  await adminDb.doc('associations/jba/divisions/inventory-limit').set({
    name: 'Inventory Limit', status: 'active', version: 1,
  });
  let batch = adminDb.batch();
  for (let index = 0; index < 501; index += 1) {
    batch.set(adminDb.doc(`associations/jba/leaderboard/inventory-limit-${index}`), {
      divisionId: 'inventory-limit',
      displayName: `Reference ${index}`,
    });
    if (index === 499) {
      await batch.commit();
      batch = adminDb.batch();
    }
  }
  await batch.commit();
  const limitedOperationId = 'division_inventory_limit_1';
  await assert.rejects(remove({
    schemaVersion: 1,
    operationId: limitedOperationId,
    divisionId: 'inventory-limit',
    expectedDivisionVersion: 1,
  }), (error) => error.code === 'functions/resource-exhausted');
  const limitedDivision = await adminDb.doc(
    'associations/jba/divisions/inventory-limit',
  ).get();
  assert.equal(limitedDivision.exists, true);
  assert.equal(limitedDivision.get('deletionPending'), undefined);
  const limitedOperation = await adminDb.doc(
    `associations/jba/divisionDeletionOperations/${digest({actorId: uid, operationId: limitedOperationId})}`,
  ).get();
  assert.equal(limitedOperation.get('status'), 'inventoryFailed');
  assert.equal(limitedOperation.get('failureCode'), 'inventory-too-large');
});

test('division deletion inventories board posts and rejects authority reassignment during inventory', async () => {
  await seedLeagueOperations();
  const uid = await createLeagueOperator('division-scope-race@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  const remove = leagueCallable('deleteDivisionIfUnreferenced');
  await adminDb.doc('associations/jba/divisions/board-scope').set({
    name: 'Board Scope', status: 'active', version: 1,
  });
  await adminDb.doc('associations/jba/posts/division-announcement').set({
    title: 'Division announcement', divisionFilter: 'board-scope',
  });
  await adminDb.doc('associations/jba/posts/legacy-division-announcement').set({
    title: 'Legacy division announcement', divisionFilter: 'Board Scope',
  });
  const blocked = await remove({
    schemaVersion: 1,
    operationId: 'division_board_inventory_1',
    divisionId: 'board-scope',
    expectedDivisionVersion: 1,
  });
  assert.equal(blocked.data.status, 'blocked');
  assert.ok(blocked.data.references.some((entry) =>
    entry.kind === 'boardPost' && entry.id === 'division-announcement'));
  assert.ok(blocked.data.references.some((entry) =>
    entry.kind === 'boardPostLegacyName' && entry.id === 'legacy-division-announcement'));

  await adminDb.doc('associations/jba/divisions/scope-race').set({
    name: 'Scope Race', status: 'active', version: 1,
  });
  const jbaControl = (await adminDb.doc(
    'associations/jba/leagueWorkflowControl/current',
  ).get()).data();
  const jbaProjection = (await adminDb.doc(
    `associations/jba/leagueActorAuthorities/${uid}`,
  ).get()).data();
  await adminDb.doc('associations/other').set({name: 'Other'});
  await adminDb.doc('associations/other/leagueWorkflowControl/current').set({
    ...jbaControl, associationId: 'other',
  });
  await adminDb.doc(`associations/other/leagueActorAuthorities/${uid}`).set({
    ...jbaProjection, associationId: 'other',
  });

  await assert.rejects(
    leagueOperations.deleteDivisionIfUnreferencedHandlerForTest(
      await leagueRequest({
        schemaVersion: 1,
        operationId: 'division_scope_race_001',
        divisionId: 'scope-race',
        expectedDivisionVersion: 1,
      }),
      {
        afterInventory: async () => {
          await adminDb.doc(`memberships/${uid}`).update({associationId: 'other'});
        },
      },
    ),
    (error) => error.code === 'permission-denied',
  );
  assert.equal((await adminDb.doc(
    'associations/jba/divisions/scope-race',
  ).get()).exists, true);
});

test('invite creation and redemption cannot add membership references while a division deletion guard is active', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('invite-guard-admin@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'invites.manage',
  ]);
  const createInvite = httpsCallable(functions, 'createPrivilegedInvite');
  const issued = await createInvite({
    role: 'rep',
    teamId: 'team-a',
    daysValid: 7,
    operationId: 'invite_before_guard_001',
    authorizationSchemaVersion: 1,
  });
  await adminDb.doc('associations/jba/divisions/premier').update({
    deletionPending: {
      schemaVersion: 1,
      operationId: 'division_invite_guard_1',
      actorId: 'server-test',
      expectedDivisionVersion: 7,
      leaseExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60_000),
    },
  });
  await assert.rejects(
    createInvite({
      role: 'rep',
      teamId: 'team-a',
      daysValid: 7,
      operationId: 'invite_during_guard_001',
      authorizationSchemaVersion: 1,
    }),
    (error) => error.code === 'functions/failed-precondition',
  );

  await signOut(auth);
  const invitee = await createUserWithEmailAndPassword(
    auth,
    'invite-guard-rep@example.com',
    'correct-horse-battery-staple',
  );
  const redeem = httpsCallable(functions, 'redeemPrivilegedInvite');
  await assert.rejects(
    redeem({
      code: issued.data.code,
      displayName: 'Guarded Representative',
      operationId: 'redeem_during_guard_01',
      authorizationSchemaVersion: 1,
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  assert.equal((await adminDb.doc(`memberships/${invitee.user.uid}`).get()).exists, false);
});

test('token bucket has no boundary reset and exact lost-response replay consumes no quota', async () => {
  await seedLeagueOperations();
  const uid = await createLeagueOperator('quota-operator@example.com', 'superAdmin', [
    'association.read', 'association.manage', 'schedule.manage',
  ]);
  const quotaRef = adminDb.doc(
    `associations/jba/leagueActorQuotas/${createHash('sha256').update(JSON.stringify({uid})).digest('hex')}`,
  );
  const now = admin.firestore.Timestamp.now();
  await quotaRef.set({
    schemaVersion: 2,
    associationId: 'jba',
    actorId: uid,
    minuteTokens: 1_000,
    minuteRefilledAt: now,
    dayTokens: 1_000,
    dayRefilledAt: now,
  });
  const schedule = leagueCallable('scheduleGame');
  const request = {
    schemaVersion: 1,
    operationId: 'schedule_quota_boundary_1',
    seasonId: 's2026',
    divisionId: 'premier',
    homeTeamId: 'team-a',
    awayTeamId: 'team-b',
    startTimeUtc: '2027-01-02T01:00:00.000Z',
    endTimeUtc: '2027-01-02T03:00:00.000Z',
  };
  const first = await schedule(request);
  const afterFirst = (await quotaRef.get()).data();
  assert.ok(afterFirst.minuteTokens < 1_000);
  assert.ok(afterFirst.dayTokens < 1_000);

  const replay = await schedule(request);
  assert.deepEqual(replay.data, first.data);
  assert.deepEqual((await quotaRef.get()).data(), afterFirst);
  await assert.rejects(
    schedule({...request, startTimeUtc: '2027-01-02T02:00:00.000Z'}),
    (error) => error.code === 'functions/already-exists',
  );
  await assert.rejects(
    schedule({
      ...request,
      operationId: 'schedule_quota_boundary_2',
      startTimeUtc: '2027-01-03T01:00:00.000Z',
      endTimeUtc: '2027-01-03T03:00:00.000Z',
    }),
    (error) => error.code === 'functions/resource-exhausted',
  );
});

test('season preparation is gated, date-only, stable-ID bound, and never changes current season', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('season-prepare@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  const prepare = leagueCallable('seasonPrepare');
  const request = {
    schemaVersion: 1,
    operationId: 'season_prepare_2027_01',
    seasonId: 'nbl-2027',
    name: 'NBL 2027',
    startDate: '2027-01-03',
    endDate: '2027-09-30',
  };

  await adminDb.doc('associations/jba/leagueWorkflowControl/current').update({seasonLifecycle: false});
  await assert.rejects(prepare(request), (error) => error.code === 'functions/failed-precondition');
  assert.equal((await adminDb.doc('associations/jba/seasons/nbl-2027').get()).exists, false);
  await adminDb.doc('associations/jba/leagueWorkflowControl/current').update({seasonLifecycle: true});

  await assert.rejects(
    prepare({...request, operationId: 'season_prepare_bad_date', startDate: '2027-02-30'}),
    (error) => error.code === 'functions/invalid-argument',
  );
  await assert.rejects(
    prepare({...request, operationId: 'season_prepare_bad_range', startDate: '2027-10-01'}),
    (error) => error.code === 'functions/invalid-argument',
  );
  await assert.rejects(
    prepare({...request, operationId: 'season_prepare_bad_slug', seasonId: 'chosen-id'}),
    (error) => error.code === 'functions/invalid-argument',
  );
  await assert.rejects(
    prepare({...request, operationId: 'season_prepare_scope_injection', associationId: 'other'}),
    (error) => error.code === 'functions/invalid-argument',
  );

  const first = await prepare(request);
  assert.deepEqual(first.data, {
    operationId: request.operationId,
    status: 'prepared',
    seasonId: 'nbl-2027',
    seasonVersion: 1,
    currentSeasonId: 's2026',
  });
  const prepared = (await adminDb.doc('associations/jba/seasons/nbl-2027').get()).data();
  assert.equal(prepared.status, 'prepared');
  assert.equal(prepared.isActive, false);
  assert.equal(prepared.startDate, '2027-01-03');
  assert.equal((await adminDb.doc('associations/jba').get()).get('currentSeasonId'), 's2026');
  assert.equal(
    (await adminDb.doc('associations/jba/leagueWorkflowControl/current').get()).get('activeSeasonId'),
    's2026',
  );

  const replay = await prepare(request);
  assert.deepEqual(replay.data, first.data);
  await assert.rejects(
    prepare({...request, endDate: '2027-10-01'}),
    (error) => error.code === 'functions/already-exists',
  );
  await assert.rejects(
    prepare({...request, operationId: 'season_prepare_duplicate_id'}),
    (error) => error.code === 'functions/already-exists',
  );
  assert.equal((await adminDb.doc('associations/jba/seasons/nbl-2027').get()).get('endDate'), '2027-09-30');
});

test('season activation atomically switches both pointers and active flags with exact replay', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('season-activate@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  const prepare = leagueCallable('seasonPrepare');
  const activate = leagueCallable('seasonActivate');
  await prepare({
    schemaVersion: 1,
    operationId: 'season_prepare_activation',
    seasonId: 'nbl-2028',
    name: 'NBL 2028',
    startDate: '2028-01-01',
    endDate: '2028-09-30',
  });
  const request = {
    schemaVersion: 1,
    operationId: 'season_activate_2027_01',
    seasonId: 'nbl-2028',
    expectedSeasonVersion: 1,
    expectedCurrentSeasonId: 's2026',
  };
  await assert.rejects(
    activate({...request, operationId: 'season_activate_stale_01', expectedCurrentSeasonId: 'stale'}),
    (error) => error.code === 'functions/aborted',
  );
  const first = await activate(request);
  assert.equal(first.data.previousSeasonId, 's2026');
  assert.equal(first.data.currentSeasonId, 'nbl-2028');
  const [association, control, oldSeason, newSeason] = await Promise.all([
    adminDb.doc('associations/jba').get(),
    adminDb.doc('associations/jba/leagueWorkflowControl/current').get(),
    adminDb.doc('associations/jba/seasons/s2026').get(),
    adminDb.doc('associations/jba/seasons/nbl-2028').get(),
  ]);
  assert.equal(association.get('currentSeasonId'), 'nbl-2028');
  assert.equal(control.get('activeSeasonId'), 'nbl-2028');
  assert.equal(oldSeason.get('status'), 'inactive');
  assert.equal(oldSeason.get('isActive'), false);
  assert.equal(newSeason.get('status'), 'active');
  assert.equal(newSeason.get('isActive'), true);
  assert.deepEqual((await activate(request)).data, first.data);
});

test('season archive refuses current, preserves history, and restore is reversible', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('season-archive@example.com', 'superAdmin', [
    'association.read', 'association.manage',
  ]);
  const prepare = leagueCallable('seasonPrepare');
  const archive = leagueCallable('seasonArchive');
  const restore = leagueCallable('seasonRestore');
  await prepare({
    schemaVersion: 1,
    operationId: 'season_prepare_archive',
    seasonId: 'nbl-2029',
    name: 'NBL 2029',
    startDate: '2029-01-01',
    endDate: '2029-09-30',
  });
  await adminDb.doc('associations/jba/seasons/nbl-2029/games/historical').set({result: 'preserved'});

  await assert.rejects(
    archive({
      schemaVersion: 1,
      operationId: 'season_archive_current',
      seasonId: 's2026',
      expectedSeasonVersion: 1,
      expectedCurrentSeasonId: 's2026',
    }),
    (error) => error.code === 'functions/failed-precondition',
  );
  const archived = await archive({
    schemaVersion: 1,
    operationId: 'season_archive_2027_01',
    seasonId: 'nbl-2029',
    expectedSeasonVersion: 1,
    expectedCurrentSeasonId: 's2026',
  });
  assert.equal(archived.data.status, 'archived');
  assert.equal((await adminDb.doc('associations/jba/seasons/nbl-2029').get()).get('status'), 'archived');
  assert.equal((await adminDb.doc('associations/jba/seasons/nbl-2029/games/historical').get()).exists, true);
  const restored = await restore({
    schemaVersion: 1,
    operationId: 'season_restore_2027_01',
    seasonId: 'nbl-2029',
    expectedSeasonVersion: 2,
    expectedCurrentSeasonId: 's2026',
  });
  assert.equal(restored.data.status, 'restored');
  const restoredSeason = await adminDb.doc('associations/jba/seasons/nbl-2029').get();
  assert.equal(restoredSeason.get('status'), 'prepared');
  assert.equal(restoredSeason.get('isActive'), false);
  assert.equal((await adminDb.doc('associations/jba').get()).get('currentSeasonId'), 's2026');
});

test('season callables require authoritative association management capability', async () => {
  await seedLeagueOperations();
  await createLeagueOperator('season-reader@example.com', 'fan', ['association.read']);
  const prepare = leagueCallable('seasonPrepare');
  await assert.rejects(
    prepare({
      schemaVersion: 1,
      operationId: 'season_prepare_denied_01',
      seasonId: 'nbl-2030',
      name: 'NBL 2030',
      startDate: '2030-01-01',
      endDate: '2030-09-30',
    }),
    (error) => error.code === 'functions/permission-denied',
  );
  assert.equal((await adminDb.doc('associations/jba/seasons/nbl-2030').get()).exists, false);
});
