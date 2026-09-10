#!/usr/bin/env node
'use strict';

const admin = require('../functions/node_modules/firebase-admin');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const authorizationSchema = require('../functions/src/authorization_schema_v1.json');
const {guardFirestoreTarget, readFlag} = require('./lib/firebase_target_guard');

const allowedFlags = new Set([
  '--project',
  '--allow-production-read',
  '--association',
  '--commit',
  '--confirm-production',
  '--confirm-source-sha',
]);

function parseArgs(argv) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) throw new Error('Positional arguments are not allowed.');
    const name = arg.split('=', 1)[0];
    if (!allowedFlags.has(name)) throw new Error(`Unsupported flag ${name}.`);
    if (!arg.includes('=') && name !== '--commit') index += 1;
  }
  const projectId = readFlag(argv, '--project');
  const associationId = readFlag(argv, '--association');
  if (!projectId || !associationId || !/^[A-Za-z0-9_-]+$/.test(associationId)) {
    throw new Error('--project and an exact --association document ID are required.');
  }
  const commit = argv.includes('--commit');
  if (commit && readFlag(argv, '--confirm-production') !== projectId) {
    throw new Error(`Commit requires --confirm-production=${projectId}.`);
  }
  return {
    projectId,
    associationId,
    commit,
    confirmSourceSha: readFlag(argv, '--confirm-source-sha'),
  };
}

function normalize(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return {__timestamp: value.toDate().toISOString()};
  }
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, normalize(value[key])]),
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(normalize(value), null, 2) + '\n';
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function records(snapshot) {
  return snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
}

async function readSource(db, auth, associationId) {
  const [authPage, usersSnap, membershipsSnap, postsSnap, invitesSnap] = await Promise.all([
    auth.listUsers(1000),
    db.collection('users').get(),
    db.collection('memberships').get(),
    db.collection(`associations/${associationId}/posts`).get(),
    db.collection('inviteCodes').get(),
  ]);
  if (authPage.pageToken) throw new Error('More than 1,000 Auth users requires a paginated executor.');
  return {
    authUsers: authPage.users.map((user) => ({uid: user.uid, email: user.email || null})),
    users: records(usersSnap),
    memberships: records(membershipsSnap),
    posts: records(postsSnap),
    invites: records(invitesSnap),
  };
}

function planMigration(source, associationId) {
  const authById = new Map(source.authUsers.map((user) => [user.uid, user]));
  const membershipsById = new Map(source.memberships.map((entry) => [entry.id, entry.data]));
  const membershipActions = [];
  for (const entry of source.users) {
    const user = entry.data;
    const authUser = authById.get(entry.id);
    if (!authUser || !authUser.email || typeof user.email !== 'string' ||
        authUser.email.toLowerCase() !== user.email.toLowerCase()) {
      throw new Error(`Profile ${entry.id} does not have a matching Auth identity and email.`);
    }
    if (user.associationId !== associationId) {
      throw new Error(`Profile ${entry.id} is outside association ${associationId}.`);
    }
    if (!Object.prototype.hasOwnProperty.call(authorizationSchema.roles, user.role)) {
      throw new Error(`Profile ${entry.id} has unsupported role ${user.role}.`);
    }
    const expected = {
      associationId,
      role: user.role,
      capabilities: [...authorizationSchema.roles[user.role]],
      status: 'active',
      teamId: user.teamId ?? null,
      divisionId: user.divisionId ?? null,
      seasonId: user.seasonId ?? null,
      competitionId: null,
      authorizationSchemaVersion: authorizationSchema.schemaVersion,
    };
    const membership = membershipsById.get(entry.id);
    if (membership && canonicalJson({...membership, createdAt: undefined, updatedAt: undefined}) !==
        canonicalJson(expected)) {
      throw new Error(`Existing membership ${entry.id} requires manual conflict review.`);
    }
    membershipActions.push({id: entry.id, expected, create: !membership});
  }
  const postActions = source.posts
    .filter((entry) => !['public', 'internal'].includes(entry.data.visibility))
    .map((entry) => ({id: entry.id, visibility: 'internal'}));
  const legacyInvites = source.invites.filter((entry) =>
    entry.data.credentialVersion !== 2 ||
    entry.data.authorizationSchemaVersion !== authorizationSchema.schemaVersion,
  );
  return {membershipActions, postActions, legacyInvites};
}

function writeBackup(projectId, source, sourceSha) {
  const directory = path.resolve('.local/authorization-migration');
  fs.mkdirSync(directory, {recursive: true, mode: 0o700});
  fs.chmodSync(directory, 0o700);
  const filePath = path.join(directory, `${projectId}-${sourceSha}.json`);
  const descriptor = fs.openSync(filePath, 'wx', 0o600);
  try {
    fs.writeFileSync(descriptor, canonicalJson({projectId, sourceSha, source}));
  } finally {
    fs.closeSync(descriptor);
  }
  fs.chmodSync(filePath, 0o600);
  return filePath;
}

async function applyMigration(db, associationId, plan) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  for (const action of plan.membershipActions) {
    const userRef = db.doc(`users/${action.id}`);
    const membershipRef = db.doc(`memberships/${action.id}`);
    batch.set(membershipRef, {...action.expected, createdAt: now, updatedAt: now}, {merge: false});
    batch.update(userRef, {
      authorizationSchemaVersion: authorizationSchema.schemaVersion,
      updatedAt: now,
    });
  }
  for (const action of plan.postActions) {
    batch.update(db.doc(`associations/${associationId}/posts/${action.id}`), {
      visibility: action.visibility,
    });
  }
  for (const entry of plan.legacyInvites) {
    batch.update(db.doc(`inviteCodes/${entry.id}`), {
      status: 'revoked',
      usesRemaining: 0,
      revokedAt: now,
      revokedReason: 'authorization_schema_v1_migration',
    });
  }
  await batch.commit();
}

async function main() {
  const argv = process.argv.slice(2);
  const options = parseArgs(argv);
  const target = guardFirestoreTarget({argv, mode: 'read'});
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: target.projectId,
  });
  const db = admin.firestore();
  const source = await readSource(db, admin.auth(), options.associationId);
  const sourceSha = sha256(canonicalJson(source));
  const plan = planMigration(source, options.associationId);
  const summary = {
    projectId: target.projectId,
    associationId: options.associationId,
    commit: options.commit,
    sourceSha,
    profilesToMigrate: plan.membershipActions.length,
    membershipsToCreate: plan.membershipActions.filter((action) => action.create).length,
    postsDefaultedInternal: plan.postActions.length,
    legacyInvitesRevoked: plan.legacyInvites.length,
  };
  console.log(JSON.stringify(summary, null, 2));
  if (!options.commit) return;
  if (!options.confirmSourceSha || options.confirmSourceSha !== sourceSha) {
    throw new Error(`Commit requires --confirm-source-sha=${sourceSha}.`);
  }
  const backupPath = writeBackup(target.projectId, source, sourceSha);
  await applyMigration(db, options.associationId, plan);
  console.log(JSON.stringify({committed: true, backupPath, ...summary}, null, 2));
}

if (require.main === module) {
  main()
    .then(async () => admin.app().delete())
    .catch(async (error) => {
      console.error(error.message);
      process.exitCode = 1;
      if (admin.apps.length > 0) await admin.app().delete();
    });
}

module.exports = {canonicalJson, parseArgs, planMigration};
