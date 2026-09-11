#!/usr/bin/env node
'use strict';

const path = require('node:path');

const PROJECT_ID = 'demo-hoopsconnect-stage0-platform';
const ASSOCIATION_ID = 'jba';
const EMPTY_ASSOCIATION_ID = 'jba-empty';
const PASSWORD = 'LocalQa-Only-42!';
const LOOPBACK = /^(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/;

const roles = [
  ['fan', []],
  ['rep', ['posts.internal.read']],
  ['statistician', ['posts.internal.read', 'stats.enter']],
  ['media', ['press.read', 'stats.export']],
  ['press', ['press.read', 'stats.export']],
  ['admin', [
    'invites.manage', 'members.manage', 'posts.create',
    'posts.internal.read', 'schedule.manage', 'stats.approve', 'teams.manage',
  ]],
  ['superAdmin', [
    'association.manage', 'invites.manage', 'members.manage', 'posts.create',
    'posts.internal.read', 'posts.manage', 'press.read', 'schedule.manage',
    'stats.approve', 'stats.enter', 'stats.export', 'teams.manage',
  ]],
];

function requireSafeEnvironment(env = process.env) {
  if (env.GCLOUD_PROJECT !== PROJECT_ID) {
    throw new Error(`GCLOUD_PROJECT must be ${PROJECT_ID}.`);
  }
  for (const name of [
    'FIREBASE_AUTH_EMULATOR_HOST',
    'FIRESTORE_EMULATOR_HOST',
    'FUNCTIONS_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
  ]) {
    if (!LOOPBACK.test(env[name] || '')) {
      throw new Error(`${name} must be an explicit loopback emulator endpoint.`);
    }
  }
  for (const name of [
    'FIREBASE_TOKEN',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'GOOGLE_CLOUD_ACCESS_TOKEN',
    'CLOUDSDK_AUTH_ACCESS_TOKEN',
  ]) {
    if (env[name]) throw new Error(`${name} is forbidden in local QA.`);
  }
}

async function probeCallable(env = process.env) {
  const endpoint =
    `http://${env.FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/us-central1/` +
    'inspectPrivilegedInvite';
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      data: {
        code: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        authorizationSchemaVersion: 1,
      },
    }),
  });
  const body = await response.json();
  if (response.ok || body?.error?.status !== 'NOT_FOUND') {
    throw new Error(
      `Functions emulator callable probe returned ${response.status} ` +
      `${JSON.stringify(body)}`,
    );
  }
}

function firebaseAdmin() {
  return require(path.resolve(__dirname, '../../functions/node_modules/firebase-admin'));
}

function identity(role, dataset) {
  const suffix = dataset === 'empty' ? '-empty' : '';
  return {
    uid: `qa-${role.toLowerCase()}${suffix}`,
    email: `${role.toLowerCase()}${suffix}@hoopsconnect.test`,
    displayName: `QA ${role}${dataset === 'empty' ? ' Empty' : ''}`,
  };
}

async function upsertIdentity(auth, user) {
  try {
    await auth.updateUser(user.uid, {
      email: user.email,
      password: PASSWORD,
      displayName: user.displayName,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    await auth.createUser({...user, password: PASSWORD, emailVerified: true});
  }
}

function profile(user, role, associationId, teamId) {
  return {
    email: user.email,
    displayName: user.displayName,
    associationId,
    role,
    teamId: teamId || null,
    divisionId: teamId ? 'premier' : null,
    fcmTokens: [],
    notificationPrefs: {
      ackReminders: false,
      statReminders: false,
      newPosts: false,
    },
    qaFixtureVersion: 1,
  };
}

function membership(user, role, capabilities, associationId, teamId) {
  return {
    associationId,
    role,
    capabilities,
    status: 'active',
    authorizationSchemaVersion: 1,
    teamId: teamId || null,
    divisionId: teamId ? 'premier' : null,
    qaFixtureVersion: 1,
  };
}

async function seedIdentities(auth, db) {
  const writes = [];
  for (const [role, capabilities] of roles) {
    for (const dataset of ['full', 'empty']) {
      const user = identity(role, dataset);
      const associationId = dataset === 'full' ? ASSOCIATION_ID : EMPTY_ASSOCIATION_ID;
      const teamId = role === 'rep' ? 'kingston-lions' : null;
      await upsertIdentity(auth, user);
      writes.push(
        db.doc(`users/${user.uid}`).set(profile(user, role, associationId, teamId)),
        db.doc(`memberships/${user.uid}`).set(
          membership(user, role, capabilities, associationId, teamId),
        ),
      );
    }
  }
  await Promise.all(writes);
}

async function seedLeague(db, admin) {
  const timestamp = admin.firestore.Timestamp;
  const seasonId = 'qa-2026';
  const batch = db.batch();
  const set = (documentPath, value) => batch.set(db.doc(documentPath), value);

  set(`associations/${ASSOCIATION_ID}`, {
    name: 'Jamaica Basketball Association QA',
    shortName: 'JBA QA',
    currentSeasonId: seasonId,
    primaryColor: '#2E7D32',
    qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/seasons/${seasonId}`, {
    name: 'Synthetic 2026 Season',
    status: 'active',
    startDate: timestamp.fromDate(new Date('2026-01-01T05:00:00.000Z')),
    endDate: timestamp.fromDate(new Date('2026-12-31T05:00:00.000Z')),
    qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/divisions/premier`, {
    name: 'Premier Division',
    seasonId,
    qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/teams/kingston-lions`, {
    name: 'Kingston Lions', divisionId: 'premier', seasonId,
    repIds: ['qa-rep'], qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/teams/montego-bay-waves`, {
    name: 'Montego Bay Waves', divisionId: 'premier', seasonId,
    repIds: [], qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/events/qa-final-game`, {
    title: 'Kingston Lions vs Montego Bay Waves',
    type: 'game', seasonId, divisionId: 'premier',
    startTime: timestamp.fromDate(new Date('2026-08-20T00:00:00.000Z')),
    endTime: timestamp.fromDate(new Date('2026-08-20T02:00:00.000Z')),
    location: 'National Indoor Sports Centre',
    teamIds: ['kingston-lions', 'montego-bay-waves'],
    createdBy: 'qa-superadmin', statsStatus: 'approved', qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/events/qa-upcoming-game`, {
    title: 'Montego Bay Waves vs Kingston Lions',
    type: 'game', seasonId, divisionId: 'premier',
    startTime: timestamp.fromDate(new Date('2026-10-15T23:00:00.000Z')),
    endTime: timestamp.fromDate(new Date('2026-10-16T01:00:00.000Z')),
    location: 'Montego Bay Community Centre',
    teamIds: ['montego-bay-waves', 'kingston-lions'],
    createdBy: 'qa-superadmin', statsStatus: 'pending', qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/gameStats/qa-final-game`, {
    seasonId, divisionId: 'premier', status: 'approved',
    homeTeamId: 'kingston-lions', homeTeamName: 'Kingston Lions', homeScore: 82,
    awayTeamId: 'montego-bay-waves', awayTeamName: 'Montego Bay Waves', awayScore: 76,
    playerStats: [], teamStats: {}, qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/standings/${seasonId}`, {
    seasonId,
    standings: [
      {teamId: 'kingston-lions', teamName: 'Kingston Lions', divisionId: 'premier', wins: 1, losses: 0, pct: 1, gb: 0, streak: 'W1', lastTen: '1-0', pointsFor: 82, pointsAgainst: 76},
      {teamId: 'montego-bay-waves', teamName: 'Montego Bay Waves', divisionId: 'premier', wins: 0, losses: 1, pct: 0, gb: 1, streak: 'L1', lastTen: '0-1', pointsFor: 76, pointsAgainst: 82},
    ],
    qaFixtureVersion: 1,
  });
  set(`associations/${ASSOCIATION_ID}/leaderboard/${seasonId}-pts`, {
    seasonId, category: 'PTS', rankings: [], qaFixtureVersion: 1,
  });
  set(`associations/${EMPTY_ASSOCIATION_ID}`, {
    name: 'JBA Empty Fixture', shortName: 'JBA Empty',
    currentSeasonId: 'qa-empty-2026', qaFixtureVersion: 1,
  });
  set(`associations/${EMPTY_ASSOCIATION_ID}/seasons/qa-empty-2026`, {
    name: 'Empty Synthetic Season', status: 'active', qaFixtureVersion: 1,
  });
  await batch.commit();

  // The final source write deterministically exercises the public codebase.
  await db.doc(`associations/${ASSOCIATION_ID}/teams/kingston-lions`).set(
    {qaPublicProjectionProbe: true},
    {merge: true},
  );
}

async function waitForPublicSnapshot(db) {
  const ref = db.doc(`publicData/${ASSOCIATION_ID}/snapshots/current`);
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const snapshot = await ref.get();
    if (snapshot.exists && snapshot.get('published') === true) return snapshot.data();
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('Public Functions emulator did not publish the QA snapshot.');
}

async function main() {
  requireSafeEnvironment();
  const admin = firebaseAdmin();
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: PROJECT_ID,
      storageBucket: `${PROJECT_ID}.appspot.com`,
    });
  }
  const db = admin.firestore();
  await seedIdentities(admin.auth(), db);
  await seedLeague(db, admin);
  await probeCallable();
  await admin.storage().bucket().file('qa/public/fixture-health.txt').save(
    Buffer.from('HOOPSCONNECT_QA_STORAGE_OK\n', 'utf8'),
    {contentType: 'text/plain', resumable: false},
  );
  const publicSnapshot = await waitForPublicSnapshot(db);
  if (publicSnapshot.schedule.length !== 2) {
    throw new Error('Public QA snapshot did not contain both synthetic games.');
  }
  console.log(
    `HOOPSCONNECT_QA_FIXTURES_OK users=${roles.length * 2} ` +
    `publicGames=${publicSnapshot.schedule.length} callable=true storage=true ` +
    `password=${PASSWORD}`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = {identity, probeCallable, requireSafeEnvironment, roles};
