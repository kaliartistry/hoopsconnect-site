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
  const [usersSnap, membershipsSnap, postsSnap, ...knownInviteSnaps] =
    await Promise.all([
      db.collection('users')
        .select('role', 'associationId', 'authorizationSchemaVersion')
        .get(),
      db.collection('memberships')
        .select('role', 'associationId', 'status', 'authorizationSchemaVersion')
        .get(),
      db.collection('associations/jba/posts')
        .select('visibility', 'requiresAck')
        .get(),
      ...['NBL-ADMIN', 'ADMIN-2026'].map((code) =>
        db.doc(`inviteCodes/${code}`).get(),
      ),
    ]);

  const memberships = new Map(
    membershipsSnap.docs.map((doc) => [doc.id, doc.data()]),
  );
  let privilegedUsers = 0;
  let missingMemberships = 0;
  let conflictingAssociations = 0;
  for (const userDoc of usersSnap.docs) {
    const user = userDoc.data();
    if (!['fan', undefined].includes(user.role)) privilegedUsers += 1;
    const membership = memberships.get(userDoc.id);
    if (!membership) {
      missingMemberships += 1;
    } else if (membership.associationId !== user.associationId) {
      conflictingAssociations += 1;
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
    conflictingUserMembershipAssociations: conflictingAssociations,
    posts: postsSnap.size,
    postsMissingVisibility,
    postsMissingRequiresAck,
    publicPostsContainingAcknowledgments: publicAckPosts,
    knownStaticInvitesPresent: knownInviteSnaps
      .map((snap, index) => snap.exists ? ['NBL-ADMIN', 'ADMIN-2026'][index] : null)
      .filter(Boolean),
  };
  console.log(JSON.stringify(result, null, 2));
}

main()
  .then(() => admin.app().delete())
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
