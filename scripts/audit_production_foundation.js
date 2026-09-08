#!/usr/bin/env node
'use strict';

const admin = require('../functions/node_modules/firebase-admin');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

async function main() {
  const target = guardFirestoreTarget({mode: 'read'});
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: target.projectId,
    });
  }
  const db = admin.firestore();
  const [usersSnap, membershipsSnap, postsSnap, invitesSnap] =
    await Promise.all([
      db.collection('users')
        .select(
          'role',
          'associationId',
          'teamId',
          'divisionId',
          'authorizationSchemaVersion',
        )
        .get(),
      db.collection('memberships')
        .select(
          'role',
          'associationId',
          'teamId',
          'divisionId',
          'status',
          'authorizationSchemaVersion',
        )
        .get(),
      db.collection('associations/jba/posts')
        .select('visibility', 'requiresAck')
        .get(),
      db.collection('inviteCodes')
        .select('credentialVersion', 'authorizationSchemaVersion')
        .get(),
    ]);

  const memberships = new Map(
    membershipsSnap.docs.map((doc) => [doc.id, doc.data()]),
  );
  let privilegedUsers = 0;
  let missingMemberships = 0;
  let invalidUserSchemas = 0;
  let conflictingScopes = 0;
  for (const userDoc of usersSnap.docs) {
    const user = userDoc.data();
    if (!['fan', undefined].includes(user.role)) privilegedUsers += 1;
    if (user.authorizationSchemaVersion !== 1) invalidUserSchemas += 1;
    const membership = memberships.get(userDoc.id);
    if (!membership) {
      missingMemberships += 1;
    } else if (
      membership.associationId !== user.associationId
      || membership.role !== user.role
      || (membership.teamId || null) !== (user.teamId || null)
      || (membership.divisionId || null) !== (user.divisionId || null)
    ) {
      conflictingScopes += 1;
    }
  }

  let membershipsMissingUsers = 0;
  let inactiveMemberships = 0;
  let invalidMembershipSchemas = 0;
  for (const membershipDoc of membershipsSnap.docs) {
    const membership = membershipDoc.data();
    if (!usersSnap.docs.some((userDoc) => userDoc.id === membershipDoc.id)) {
      membershipsMissingUsers += 1;
    }
    if (membership.status !== 'active') inactiveMemberships += 1;
    if (membership.authorizationSchemaVersion !== 1) {
      invalidMembershipSchemas += 1;
    }
  }

  let postsMissingVisibility = 0;
  let postsMissingRequiresAck = 0;
  let publicAckPosts = 0;
  for (const postDoc of postsSnap.docs) {
    const post = postDoc.data();
    if (typeof post.visibility !== 'string') postsMissingVisibility += 1;
    if (typeof post.requiresAck !== 'boolean') postsMissingRequiresAck += 1;
    if (post.visibility === 'public' && post.requiresAck === true) {
      publicAckPosts += 1;
    }
  }

  const result = {
    projectId: target.projectId,
    readOnly: true,
    users: usersSnap.size,
    privilegedUsers,
    memberships: membershipsSnap.size,
    usersMissingMemberships: missingMemberships,
    membershipsMissingUsers,
    invalidUserAuthorizationSchemas: invalidUserSchemas,
    inactiveMemberships,
    invalidMembershipAuthorizationSchemas: invalidMembershipSchemas,
    conflictingUserMembershipScopes: conflictingScopes,
    posts: postsSnap.size,
    postsMissingVisibility,
    postsMissingRequiresAck,
    publicPostsContainingAcknowledgments: publicAckPosts,
    inviteDocuments: invitesSnap.size,
    legacyInviteDocuments: invitesSnap.docs.filter((doc) => {
      const invite = doc.data();
      return invite.credentialVersion !== 2
        || invite.authorizationSchemaVersion !== 1;
    }).length,
  };
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function evaluateProductionFoundationBlockers(result) {
  const blockers = [];
  for (const field of [
    'usersMissingMemberships',
    'membershipsMissingUsers',
    'invalidUserAuthorizationSchemas',
    'invalidMembershipAuthorizationSchemas',
    'conflictingUserMembershipScopes',
    'postsMissingVisibility',
    'postsMissingRequiresAck',
    'publicPostsContainingAcknowledgments',
  ]) {
    if (result[field] > 0) blockers.push(`${field}=${result[field]}`);
  }
  if (result.legacyInviteDocuments > 0) {
    blockers.push(`legacyInviteDocuments=${result.legacyInviteDocuments}`);
  }
  return blockers;
}

if (require.main === module) {
  main()
    .then(async (result) => {
      const blockers = evaluateProductionFoundationBlockers(result);
      if (blockers.length > 0) {
        console.error('Production foundation blockers: ' + blockers.join(', '));
        process.exitCode = 1;
      }
      await admin.app().delete();
    })
    .catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
}

module.exports = {evaluateProductionFoundationBlockers};
