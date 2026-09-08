'use strict';

const fs = require('fs');
const path = require('path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {doc, setDoc} = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  ref: storageRef,
  uploadBytes,
} = require('firebase/storage');

let testEnv;
const bytes = new Uint8Array([1, 2, 3]);

function storage(uid) {
  return testEnv.authenticatedContext(uid, {email: uid + '@example.com'}).storage();
}

async function seedFirestore() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const users = [
      ['fan', 'jba', ['association.read']],
      ['author', 'jba', ['association.read', 'posts.create', 'posts.internal.read']],
      ['manager', 'jba', [
        'association.read', 'association.manage', 'teams.manage', 'posts.manage',
        'posts.internal.read', 'press.read',
      ]],
      ['press', 'jba', ['association.read', 'press.read']],
      ['other', 'other', ['association.read', 'posts.internal.read', 'posts.create']],
      ['suspended', 'jba', ['association.read', 'posts.internal.read']],
    ];
    for (const [uid, associationId, capabilities] of users) {
      await setDoc(doc(db, 'memberships/' + uid), {
        associationId,
        role: 'fan',
        status: uid === 'suspended' ? 'suspended' : 'active',
        authorizationSchemaVersion: 1,
        capabilities,
      });
    }
    await setDoc(doc(db, 'associations/jba/posts/public-post'), {
      authorId: 'author', visibility: 'public', requiresAck: false,
    });
    await setDoc(doc(db, 'associations/jba/posts/internal-post'), {
      authorId: 'author', visibility: 'internal', requiresAck: true,
    });
    await setDoc(doc(db, 'associations/other/posts/other-post'), {
      authorId: 'other', visibility: 'internal', requiresAck: false,
    });
    await setDoc(doc(db, 'associations/jba/teams/team-1'), {name: 'Team One'});
    await setDoc(doc(db, 'associations/jba/documents/rules'), {
      visibility: 'internal',
    });
  });
}

function postMetadata(postId, visibility, ownerUid = 'author', associationId = 'jba') {
  return {
    contentType: 'image/png',
    customMetadata: {associationId, postId, ownerUid, visibility},
  };
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
    storage: {
      rules: fs.readFileSync(path.resolve(__dirname, '../../storage.rules'), 'utf8'),
    },
  });
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedFirestore();
});

test.after(async () => testEnv.cleanup());

test('fan reads public media while internal, cross-tenant, suspended, and unauthenticated reads fail', async () => {
  const authorStorage = storage('author');
  await assertSucceeds(uploadBytes(
    storageRef(authorStorage, 'associations/jba/posts/public-post/image.png'),
    bytes,
    postMetadata('public-post', 'public'),
  ));
  await assertSucceeds(uploadBytes(
    storageRef(authorStorage, 'associations/jba/posts/internal-post/image.png'),
    bytes,
    postMetadata('internal-post', 'internal'),
  ));

  await assertSucceeds(getBytes(storageRef(storage('fan'), 'associations/jba/posts/public-post/image.png')));
  await assertFails(getBytes(storageRef(storage('fan'), 'associations/jba/posts/internal-post/image.png')));
  await assertSucceeds(getBytes(storageRef(storage('author'), 'associations/jba/posts/internal-post/image.png')));
  await assertFails(getBytes(storageRef(storage('other'), 'associations/jba/posts/internal-post/image.png')));
  await assertFails(getBytes(storageRef(storage('suspended'), 'associations/jba/posts/public-post/image.png')));
  await assertFails(getBytes(storageRef(testEnv.unauthenticatedContext().storage(), 'associations/jba/posts/public-post/image.png')));
});

test('post author and manager CRUD is tenant-bound and rejects metadata, owner, MIME, and size forgery', async () => {
  const object = storageRef(storage('author'), 'associations/jba/posts/public-post/image.png');
  await assertSucceeds(uploadBytes(object, bytes, postMetadata('public-post', 'public')));
  await assertSucceeds(uploadBytes(object, new Uint8Array([4]), postMetadata('public-post', 'public')));
  await assertFails(uploadBytes(
    object,
    bytes,
    postMetadata('public-post', 'public', 'attacker'),
  ));
  await assertFails(uploadBytes(
    storageRef(storage('author'), 'associations/jba/posts/public-post/forged.png'),
    bytes,
    postMetadata('public-post', 'public', 'author', 'other'),
  ));
  await assertFails(uploadBytes(
    storageRef(storage('other'), 'associations/jba/posts/public-post/cross.png'),
    bytes,
    postMetadata('public-post', 'public'),
  ));
  await assertFails(uploadBytes(
    storageRef(storage('author'), 'associations/jba/posts/public-post/vector.svg'),
    bytes,
    {...postMetadata('public-post', 'public'), contentType: 'image/svg+xml'},
  ));
  await assertFails(uploadBytes(
    storageRef(storage('author'), 'associations/jba/posts/public-post/oversize.png'),
    new Uint8Array(5 * 1024 * 1024 + 1),
    postMetadata('public-post', 'public'),
  ));
  await assertSucceeds(deleteObject(object));

  const managed = storageRef(storage('manager'), 'associations/jba/posts/public-post/managed.png');
  await assertSucceeds(uploadBytes(managed, bytes, postMetadata('public-post', 'public')));
  await assertSucceeds(deleteObject(managed));
});

test('team and internal-document media enforce capability, metadata, and CRUD boundaries', async () => {
  const teamPath = 'associations/jba/teams/team-1/logo.png';
  const teamMeta = {
    contentType: 'image/webp',
    customMetadata: {associationId: 'jba', teamId: 'team-1'},
  };
  const teamObject = storageRef(storage('manager'), teamPath);
  await assertSucceeds(uploadBytes(teamObject, bytes, teamMeta));
  await assertSucceeds(getBytes(storageRef(storage('fan'), teamPath)));
  await assertFails(uploadBytes(
    storageRef(storage('fan'), 'associations/jba/teams/team-1/forged.png'),
    bytes,
    {...teamMeta, contentType: 'image/png'},
  ));
  await assertFails(uploadBytes(
    storageRef(storage('manager'), 'associations/jba/teams/missing/logo.png'),
    bytes,
    {contentType: 'image/png', customMetadata: {associationId: 'jba', teamId: 'missing'}},
  ));
  await assertFails(uploadBytes(
    teamObject,
    bytes,
    {contentType: 'image/webp', customMetadata: {associationId: 'other', teamId: 'team-1'}},
  ));
  await assertSucceeds(deleteObject(teamObject));

  const documentPath = 'associations/jba/documents/rules/rules.pdf';
  const documentMeta = {
    contentType: 'application/pdf',
    customMetadata: {associationId: 'jba', documentId: 'rules', visibility: 'internal'},
  };
  const documentObject = storageRef(storage('manager'), documentPath);
  await assertSucceeds(uploadBytes(documentObject, bytes, documentMeta));
  await assertSucceeds(getBytes(storageRef(storage('press'), documentPath)));
  await assertFails(getBytes(storageRef(storage('fan'), documentPath)));
  await assertFails(uploadBytes(
    storageRef(storage('manager'), 'associations/jba/documents/rules/forged.pdf'),
    bytes,
    {...documentMeta, customMetadata: {...documentMeta.customMetadata, associationId: 'other'}},
  ));
  await assertFails(uploadBytes(
    storageRef(storage('manager'), 'associations/jba/documents/missing/file.pdf'),
    bytes,
    {
      contentType: 'application/pdf',
      customMetadata: {associationId: 'jba', documentId: 'missing', visibility: 'internal'},
    },
  ));
  await assertSucceeds(deleteObject(documentObject));
});

test('legacy global roots remain unreadable and unwritable', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await uploadBytes(storageRef(context.storage(), 'posts/legacy/image.png'), bytes, {
      contentType: 'image/png',
    });
    await uploadBytes(
      storageRef(context.storage(), 'associations/jba/posts/public-post/missing-metadata.png'),
      bytes,
      {contentType: 'image/png'},
    );
  });
  await assertFails(getBytes(storageRef(storage('manager'), 'posts/legacy/image.png')));
  await assertFails(getBytes(
    storageRef(storage('fan'), 'associations/jba/posts/public-post/missing-metadata.png'),
  ));
  await assertFails(uploadBytes(
    storageRef(storage('manager'), 'teams/legacy/logo.png'),
    bytes,
    {contentType: 'image/png'},
  ));
  await assertFails(uploadBytes(
    storageRef(storage('manager'), 'documents/legacy/file.pdf'),
    bytes,
    {contentType: 'application/pdf'},
  ));
});
