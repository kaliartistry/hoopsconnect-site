'use strict';

process.env.GCLOUD_PROJECT = 'demo-hoopsconnect';
process.env.FIREBASE_CONFIG = JSON.stringify({projectId: 'demo-hoopsconnect'});

const assert = require('node:assert/strict');
const test = require('node:test');
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp({projectId: 'demo-hoopsconnect'});

const {loadAuthorizedRecipients} = require('../lib/notification_authorization');
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
} = {}) {
  await db.doc('users/' + uid).set({
    displayName: uid,
    associationId: userAssociationId,
    role: 'rep',
    fcmTokens: ['token-' + uid],
    notificationPrefs: prefs,
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
      teamId: 't1',
    });
  }
}

test.beforeEach(clearFirestore);
test.after(async () => {
  await clearFirestore();
  await admin.app().delete();
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
