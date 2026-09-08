'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  evaluateStorageMigrationBlockers,
  inspectStorageObject,
} = require('../audit_storage_migration');

function source(data) {
  return {exists: true, data: () => data};
}

test('storage audit accepts only canonical policy-complete objects', () => {
  const clean = inspectStorageObject({
    name: 'associations/jba/posts/post-1/image.png',
    size: '3',
    contentType: 'image/png',
    metadata: {
      associationId: 'jba',
      postId: 'post-1',
      ownerUid: 'author',
      visibility: 'internal',
    },
  }, source({authorId: 'author', visibility: 'internal', requiresAck: true}));
  assert.equal(clean.canonical, true);
  assert.deepEqual(evaluateStorageMigrationBlockers({
    legacyObjects: 0,
    invalidCanonicalPathObjects: 0,
    unclassifiedObjects: 0,
    objectsWithInvalidMetadata: Number(clean.invalidMetadata),
    objectsWithInvalidMime: Number(clean.invalidMime),
    objectsWithInvalidSize: Number(clean.invalidSize),
    objectsMissingSource: Number(clean.missingSource),
    objectsWithSourceMismatch: Number(clean.sourceMismatch),
    objectsWithDownloadTokens: Number(clean.hasDownloadToken),
    postUrlReferences: 0,
    teamUrlReferences: 0,
  }), []);
});

test('storage audit blocks missing metadata, missing sources, and retained tokens', () => {
  const unsafe = inspectStorageObject({
    name: 'associations/jba/posts/post-1/image.png',
    size: '3',
    contentType: 'image/png',
    metadata: {firebaseStorageDownloadTokens: 'still-live'},
  }, {exists: false});
  assert.equal(unsafe.invalidMetadata, true);
  assert.equal(unsafe.missingSource, true);
  assert.equal(unsafe.hasDownloadToken, true);
  assert.equal(evaluateStorageMigrationBlockers({
    legacyObjects: 0,
    invalidCanonicalPathObjects: 0,
    unclassifiedObjects: 0,
    objectsWithInvalidMetadata: 1,
    objectsWithInvalidMime: 0,
    objectsWithInvalidSize: 0,
    objectsMissingSource: 1,
    objectsWithSourceMismatch: 0,
    objectsWithDownloadTokens: 1,
    postUrlReferences: 0,
    teamUrlReferences: 0,
  }).length, 3);
});
