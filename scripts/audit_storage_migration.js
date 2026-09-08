#!/usr/bin/env node
'use strict';

const admin = require('../functions/node_modules/firebase-admin');
const {guardFirestoreTarget, readFlag} = require('./lib/firebase_target_guard');

async function main() {
  const target = guardFirestoreTarget({mode: 'read'});
  const bucketName = readFlag(process.argv.slice(2), '--bucket');
  const allowedBuckets = new Set([
    `${target.projectId}.appspot.com`,
    `${target.projectId}.firebasestorage.app`,
  ]);
  if (!allowedBuckets.has(bucketName)) {
    throw new Error('--bucket must exactly match the selected Firebase project.');
  }
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: target.projectId,
    storageBucket: bucketName,
  });
  const [files] = await admin.storage().bucket().getFiles();
  const db = admin.firestore();
  const [posts, teams] = await Promise.all([
    db.collectionGroup('posts').select('imageUrl').get(),
    db.collectionGroup('teams').select('logoUrl').get(),
  ]);
  const counts = {
    projectId: target.projectId,
    bucket: bucketName,
    readOnly: true,
    objects: files.length,
    legacyObjects: files.filter((file) => /^(posts|teams|documents)\//.test(file.name)).length,
    associationScopedObjects: files.filter((file) => /^associations\/[^/]+\/(posts|teams|documents)\//.test(file.name)).length,
    unclassifiedObjects: files.filter((file) => !/^(posts|teams|documents)\//.test(file.name)
      && !/^associations\/[^/]+\/(posts|teams|documents)\//.test(file.name)).length,
    postUrlReferences: posts.docs.filter((doc) => typeof doc.get('imageUrl') === 'string').length,
    teamUrlReferences: teams.docs.filter((doc) => typeof doc.get('logoUrl') === 'string').length,
  };
  console.log(JSON.stringify(counts, null, 2));
  if (counts.legacyObjects || counts.unclassifiedObjects || counts.postUrlReferences || counts.teamUrlReferences) {
    process.exitCode = 1;
  }
}

main()
  .then(() => admin.app().delete())
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
