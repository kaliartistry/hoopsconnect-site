#!/usr/bin/env node
'use strict';

const admin = require('../functions/node_modules/firebase-admin');
const {guardFirestoreTarget, readFlag} = require('./lib/firebase_target_guard');

const imageTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
]);

function canonicalObject(name) {
  const match = /^associations\/([^/]+)\/(posts|teams|documents)\/([^/]+)\/([^/]+)$/.exec(name);
  if (!match) return null;
  const [, associationId, kind, entityId] = match;
  return {
    associationId,
    kind,
    entityId,
    sourcePath: `associations/${associationId}/${kind}/${entityId}`,
  };
}

function inspectStorageObject(record, source) {
  const canonical = canonicalObject(record.name);
  const legacy = /^(posts|teams|documents)\//.test(record.name);
  const invalidCanonicalPath = !canonical && record.name.startsWith('associations/');
  const unclassified = !canonical && !legacy && !invalidCanonicalPath;
  const custom = record.metadata && typeof record.metadata === 'object'
    ? record.metadata
    : {};
  const hasDownloadToken = typeof custom.firebaseStorageDownloadTokens === 'string'
    && custom.firebaseStorageDownloadTokens.trim().length > 0;
  if (!canonical) {
    return {
      canonical: false,
      legacy,
      invalidCanonicalPath,
      unclassified,
      invalidMetadata: false,
      invalidMime: false,
      invalidSize: false,
      missingSource: false,
      sourceMismatch: false,
      hasDownloadToken,
    };
  }

  const sourceData = source?.exists ? source.data() : null;
  const size = Number(record.size);
  let invalidMetadata = custom.associationId !== canonical.associationId;
  let invalidMime = false;
  let invalidSize = !Number.isFinite(size) || size <= 0;
  let sourceMismatch = false;

  if (canonical.kind === 'posts') {
    invalidMetadata ||= custom.postId !== canonical.entityId
      || typeof custom.ownerUid !== 'string'
      || !['public', 'internal'].includes(custom.visibility);
    invalidMime = !imageTypes.has(record.contentType);
    invalidSize ||= size > 5 * 1024 * 1024;
    if (sourceData) {
      sourceMismatch = typeof sourceData.authorId !== 'string'
        || !['public', 'internal'].includes(sourceData.visibility)
        || typeof sourceData.requiresAck !== 'boolean'
        || custom.ownerUid !== sourceData.authorId
        || custom.visibility !== sourceData.visibility;
    }
  } else if (canonical.kind === 'teams') {
    invalidMetadata ||= custom.teamId !== canonical.entityId;
    invalidMime = !imageTypes.has(record.contentType);
    invalidSize ||= size > 2 * 1024 * 1024;
  } else {
    invalidMetadata ||= custom.documentId !== canonical.entityId
      || custom.visibility !== 'internal';
    invalidMime = !imageTypes.has(record.contentType)
      && record.contentType !== 'application/pdf';
    invalidSize ||= size > 10 * 1024 * 1024;
    if (sourceData) {
      sourceMismatch = sourceData.visibility !== 'internal';
    }
  }

  return {
    canonical: true,
    legacy: false,
    invalidCanonicalPath: false,
    unclassified: false,
    invalidMetadata,
    invalidMime,
    invalidSize,
    missingSource: !source?.exists,
    sourceMismatch,
    hasDownloadToken,
  };
}

function evaluateStorageMigrationBlockers(counts) {
  const fields = [
    'legacyObjects',
    'invalidCanonicalPathObjects',
    'unclassifiedObjects',
    'objectsWithInvalidMetadata',
    'objectsWithInvalidMime',
    'objectsWithInvalidSize',
    'objectsMissingSource',
    'objectsWithSourceMismatch',
    'objectsWithDownloadTokens',
    'postUrlReferences',
    'teamUrlReferences',
  ];
  return fields
    .filter((field) => counts[field] > 0)
    .map((field) => `${field}=${counts[field]}`);
}

async function loadSources(db, paths) {
  const result = new Map();
  const uniquePaths = [...new Set(paths)];
  for (let offset = 0; offset < uniquePaths.length; offset += 100) {
    const chunk = uniquePaths.slice(offset, offset + 100);
    const snapshots = await db.getAll(...chunk.map((sourcePath) => db.doc(sourcePath)));
    snapshots.forEach((snapshot) => result.set(snapshot.ref.path, snapshot));
  }
  return result;
}

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
  const records = await Promise.all(files.map(async (file) => {
    const [metadata] = await file.getMetadata();
    return {
      name: file.name,
      size: metadata.size,
      contentType: metadata.contentType,
      metadata: metadata.metadata,
    };
  }));
  const db = admin.firestore();
  const canonical = records.map((record) => canonicalObject(record.name));
  const sources = await loadSources(
    db,
    canonical.filter(Boolean).map((entry) => entry.sourcePath),
  );
  const inspections = records.map((record, index) => inspectStorageObject(
    record,
    canonical[index] ? sources.get(canonical[index].sourcePath) : null,
  ));
  const [posts, teams] = await Promise.all([
    db.collectionGroup('posts').select('imageUrl').get(),
    db.collectionGroup('teams').select('logoUrl').get(),
  ]);
  const count = (field) => inspections.filter((entry) => entry[field]).length;
  const counts = {
    projectId: target.projectId,
    bucket: bucketName,
    readOnly: true,
    objects: files.length,
    legacyObjects: count('legacy'),
    associationScopedObjects: count('canonical'),
    invalidCanonicalPathObjects: count('invalidCanonicalPath'),
    unclassifiedObjects: count('unclassified'),
    objectsWithInvalidMetadata: count('invalidMetadata'),
    objectsWithInvalidMime: count('invalidMime'),
    objectsWithInvalidSize: count('invalidSize'),
    objectsMissingSource: count('missingSource'),
    objectsWithSourceMismatch: count('sourceMismatch'),
    objectsWithDownloadTokens: count('hasDownloadToken'),
    postUrlReferences: posts.docs.filter((doc) => typeof doc.get('imageUrl') === 'string').length,
    teamUrlReferences: teams.docs.filter((doc) => typeof doc.get('logoUrl') === 'string').length,
  };
  console.log(JSON.stringify(counts, null, 2));
  const blockers = evaluateStorageMigrationBlockers(counts);
  if (blockers.length > 0) {
    console.error('Storage migration blockers: ' + blockers.join(', '));
    process.exitCode = 1;
  }
  return counts;
}

if (require.main === module) {
  main()
    .then(() => admin.app().delete())
    .catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
}

module.exports = {
  canonicalObject,
  evaluateStorageMigrationBlockers,
  inspectStorageObject,
};
