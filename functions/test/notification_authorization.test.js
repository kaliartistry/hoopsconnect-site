'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp({projectId: 'demo-hoopsconnect'});

const {
  loadAuthorizedRecipients,
  loadFavoriteTeamRecipients,
  loadFavoriteTeamAudience,
  loadTeamAcknowledgmentRecipients,
} = require('../lib/notification_authorization');
const {
  notifyFavoriteTeamFans,
  notifyFavoriteTeamScheduleFans,
  notifyFavoriteTeamScheduleDigestFans,
  publicTeamUpdateCandidates,
} = require('../lib/notifications');
const db = admin.firestore();

async function clearFirestore() {
  const collections = await db.listCollections();
  await Promise.all(collections.map((collection) => db.recursiveDelete(collection)));
}

async function seed(uid, {
  membership = true,
  status = 'active',
  schema = 1,
  associationId = 'jba',
  userAssociationId = associationId,
  capabilities = ['posts.acknowledge'],
  prefs = {},
  teamId = 't1',
  favoriteTeamIds = [],
  favoriteLeagueIds = [],
} = {}) {
  await db.doc('users/' + uid).set({
    displayName: uid,
    associationId: userAssociationId,
    role: 'rep',
    fcmTokens: ['token-' + uid],
    notificationPrefs: prefs,
    favoriteTeamIds,
    favoriteLeagueIds,
    authorizationSchemaVersion: 1,
  });
  if (membership) {
    await db.doc('memberships/' + uid).set({
      associationId,
      role: 'rep',
      status,
      capabilities,
      authorizationSchemaVersion: schema,
      divisionId: 'd1',
      teamId,
    });
  }
}

test.beforeEach(clearFirestore);
test.after(async () => {
  await clearFirestore();
  await admin.app().delete();
});

test('favorite-team inbox includes followers with push off and excludes inactive or cross-association accounts', async () => {
  await seed('follows-home', {favoriteTeamIds: ['home']});
  await seed('follows-away', {favoriteTeamIds: ['away']});
  await seed('unrelated', {favoriteTeamIds: ['other']});
  await seed('follows-league', {favoriteLeagueIds: ['nbl']});
  await seed('opted-out-fan', {
    favoriteTeamIds: ['home'],
    prefs: {favoriteTeamUpdates: false},
  });
  await seed('suspended-fan', {favoriteTeamIds: ['home'], status: 'suspended'});
  await seed('cross-tenant-fan', {
    favoriteTeamIds: ['home'],
    userAssociationId: 'other',
  });

  const recipients = await loadFavoriteTeamRecipients(db, 'jba', ['home', 'away'], ['nbl']);
  assert.deepEqual(
    recipients.map((recipient) => recipient.uid),
    ['follows-away', 'follows-home', 'follows-league', 'opted-out-fan'],
  );
  assert.equal(
    recipients.find((recipient) => recipient.uid === 'opted-out-fan')
      .notificationPrefs.favoriteTeamUpdates,
    false,
  );
});

test('final score creates one durable inbox item and retry preserves read state', async () => {
  await seed('following-fan', {
    favoriteTeamIds: ['home'],
    prefs: {favoriteTeamUpdates: false},
  });
  await seed('not-following-fan', {
    favoriteTeamIds: ['other'],
    prefs: {favoriteTeamUpdates: false},
  });
  await db.doc('publicData/jba/snapshots/current').set({
    leagues: [{leagueId: 'nbl', divisionIds: ['premier']}],
  });
  const input = {
    db,
    associationId: 'jba',
    gameId: 'game-1',
    divisionId: 'premier',
    homeTeamId: 'home',
    awayTeamId: 'away',
    homeTeamName: 'Home',
    awayTeamName: 'Away',
    homeScore: 81,
    awayScore: 74,
  };
  assert.equal(await notifyFavoriteTeamFans(input), 1);
  const inbox = await db.collection('users/following-fan/notifications').get();
  assert.equal(inbox.size, 1);
  const ref = inbox.docs[0].ref;
  const first = await ref.get();
  assert.equal(first.data().type, 'favorite_team_final');
  assert.equal(first.data().readAt, null);
  assert.equal((await db.collection('users/not-following-fan/notifications').get()).empty, true);
  await ref.update({readAt: admin.firestore.Timestamp.now()});
  assert.equal(await notifyFavoriteTeamFans(input), 1);
  const second = await ref.get();
  assert.deepEqual(second.data().createdAt, first.data().createdAt);
  assert.notEqual(second.data().readAt, null);
});

test('schedule update creates one inbox item for a league follower with push off', async () => {
  await seed('league-fan', {
    favoriteLeagueIds: ['nbl'],
    prefs: {favoriteTeamUpdates: false},
  });
  const input = {
    db, associationId: 'jba', gameId: 'game-2', divisionId: 'premier',
    homeTeamId: 'home', awayTeamId: 'away', title: 'Schedule: Home vs Away',
    body: 'Game schedule updated.', scheduleRevision: 'revision-1',
    leagueIds: ['nbl'],
  };
  assert.equal(await notifyFavoriteTeamScheduleFans(input), 1);
  assert.equal(await notifyFavoriteTeamScheduleFans(input), 1);
  const inbox = await db.collection('users/league-fan/notifications').get();
  assert.equal(inbox.size, 1);
  assert.equal(inbox.docs[0].data().type, 'favorite_team_schedule');
});

test('bulk schedule release creates one digest for a follower, not one item per game', async () => {
  await seed('league-fan', {
    favoriteLeagueIds: ['nbl'], prefs: {favoriteTeamUpdates: false},
  });
  await seed('other-fan', {
    favoriteLeagueIds: ['school'], prefs: {favoriteTeamUpdates: false},
  });
  const changes = Array.from({length: 6}, (_, index) => ({
    type: 'favorite_team_schedule', gameId: `g${index}`,
    divisionId: 'premier', homeTeamId: 'home', awayTeamId: 'away',
    scheduleRevision: `r${index}`,
  }));
  const input = {
    db, associationId: 'jba', changes,
    leagues: [{leagueId: 'nbl', divisionIds: ['premier']}],
    audience: await loadFavoriteTeamAudience(db, 'jba'),
  };
  assert.equal(await notifyFavoriteTeamScheduleDigestFans(input), 1);
  assert.equal(await notifyFavoriteTeamScheduleDigestFans(input), 1);
  const inbox = await db.collection('users/league-fan/notifications').get();
  assert.equal(inbox.size, 1);
  assert.equal(inbox.docs[0].data().gameId, undefined);
  assert.equal((await db.collection('users/other-fan/notifications').get()).empty, true);
});

test('public release diff alerts only certified new results and meaningful schedule changes', () => {
  const game = {
    gameId: 'g1', divisionId: 'premier', homeTeamId: 'home', awayTeamId: 'away',
    homeTeamName: 'Home', awayTeamName: 'Away', status: 'scheduled',
    startTime: '2027-01-01T20:00:00.000Z', venue: 'Arena',
  };
  const release = {schemaVersion: 1, associationId: 'jba', published: true,
    certificationStatus: 'certified', schedule: [game]};
  assert.deepEqual(publicTeamUpdateCandidates(undefined, release), []);
  assert.deepEqual(publicTeamUpdateCandidates(release, {...release, seasonName: 'New'}), []);
  const changed = {...game, startTime: '2027-01-02T20:00:00.000Z'};
  assert.deepEqual(
    publicTeamUpdateCandidates(release, {...release, schedule: [changed]}).map((x) => x.type),
    ['favorite_team_schedule'],
  );
  const final = {...game, status: 'final', homeScore: 81, awayScore: 74,
    resultVersion: 'a'.repeat(64)};
  assert.deepEqual(
    publicTeamUpdateCandidates(release, {...release, schedule: [final]}).map((x) => x.type),
    ['favorite_team_final'],
  );
  assert.deepEqual(publicTeamUpdateCandidates({...release, schedule: [final]}, {
    ...release, schedule: [{...final, resultVersion: 'b'.repeat(64)}],
  }), []);
  assert.deepEqual(publicTeamUpdateCandidates(release, {
    ...release, certificationStatus: 'pending', schedule: [final],
  }), []);
});

test('acknowledgment audiences contain only team-assigned reps with team names', async () => {
  await db.doc('associations/jba/teams/t1').set({name: 'Kingston Lions'});
  await seed('team-rep');
  await seed('capable-admin-without-team', {teamId: null});
  await seed('rep-with-missing-team', {teamId: 'missing'});

  const recipients = await loadTeamAcknowledgmentRecipients(db, 'jba', {
    divisionId: 'd1',
  });

  assert.deepEqual(
    recipients.map(({uid, teamId, teamName}) => ({uid, teamId, teamName})),
    [{uid: 'team-rep', teamId: 't1', teamName: 'Kingston Lions'}],
  );
});

test('private ack targeting excludes legacy, suspended, revoked, demoted, and cross-tenant profiles', async () => {
  await seed('allowed');
  await seed('legacy-role-only', {membership: false});
  await seed('suspended', {status: 'suspended'});
  await seed('revoked', {status: 'revoked'});
  await seed('old-schema', {schema: 0});
  await seed('demoted-after-post', {capabilities: ['association.read']});
  await seed('cross-tenant-profile', {userAssociationId: 'other'});
  await seed('other-association', {associationId: 'other'});
  await seed('opted-out', {prefs: {ackReminders: false}});
  await seed('new-post-opted-out', {prefs: {newPosts: false}});

  const recipients = await loadAuthorizedRecipients(
    db,
    'jba',
    'posts.acknowledge',
    {divisionId: 'd1'},
  );
  assert.deepEqual(
    recipients.map((recipient) => recipient.uid),
    ['allowed', 'new-post-opted-out', 'opted-out'],
  );
  assert.equal(
    recipients.filter((recipient) => recipient.notificationPrefs.newPosts !== false).length,
    2,
  );

  const overdue = await loadAuthorizedRecipients(
    db,
    'jba',
    'posts.acknowledge',
    {
      userIds: ['allowed', 'demoted-after-post', 'suspended', 'legacy-role-only', 'opted-out'],
      preference: 'ackReminders',
    },
  );
  assert.deepEqual(overdue.map((recipient) => recipient.uid), ['allowed']);
});

test('ack completion author and stats reminders require current capabilities, not old role labels', async () => {
  await seed('active-author', {capabilities: ['posts.manage']});
  await seed('demoted-author', {capabilities: ['association.read']});
  await seed('legacy-admin', {membership: false});
  await seed('suspended-admin', {status: 'suspended', capabilities: ['stats.enter']});
  await seed('active-statistician', {capabilities: ['stats.enter']});

  const authors = await loadAuthorizedRecipients(
    db,
    'jba',
    'posts.manage',
    {userIds: ['active-author', 'demoted-author']},
  );
  assert.deepEqual(authors.map((recipient) => recipient.uid), ['active-author']);

  const stats = await loadAuthorizedRecipients(db, 'jba', 'stats.enter');
  assert.deepEqual(stats.map((recipient) => recipient.uid), ['active-statistician']);
});
