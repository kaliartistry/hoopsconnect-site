'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {guardFirestoreTarget} = require('../lib/firebase_target_guard');

test('defaults to a demo project only when a local emulator is active', () => {
  const target = guardFirestoreTarget({
    argv: [],
    env: {FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080'},
    mode: 'write',
  });
  assert.equal(target.projectId, 'demo-hoopsconnect');
  assert.equal(target.isEmulator, true);
  assert.match(target.baseUrl, /^http:\/\/127\.0\.0\.1:8080\//);
});

test('refuses production writes even with explicit remote flags', () => {
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: [
          '--project=hoops-connect-jm',
          '--allow-remote-nonprod=hoops-connect-jm',
        ],
        env: {HOOPSCONNECT_NONPROD_PROJECT_ALLOWLIST: 'hoops-connect-jm'},
        mode: 'write',
      }),
    /Refusing to write protected production project/,
  );
});

test('requires an exact explicit flag for a production read', () => {
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: ['--project=hoops-connect-jm'],
        env: {},
        mode: 'read',
      }),
    /Production reads require/,
  );
  assert.equal(
    guardFirestoreTarget({
      argv: [
        '--project=hoops-connect-jm',
        '--allow-production-read=hoops-connect-jm',
      ],
      env: {},
      mode: 'read',
    }).projectId,
    'hoops-connect-jm',
  );
});

test('requires both the allowlist and matching remote opt-in', () => {
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: ['--project=hoops-staging'],
        env: {},
        mode: 'write',
      }),
    /not in HOOPSCONNECT_NONPROD_PROJECT_ALLOWLIST/,
  );
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: ['--project=hoops-staging'],
        env: {HOOPSCONNECT_NONPROD_PROJECT_ALLOWLIST: 'hoops-staging'},
        mode: 'write',
      }),
    /requires --allow-remote-nonprod/,
  );
});

test('destructive operation requires project and scope bound confirmation', () => {
  const options = {
    env: {FIRESTORE_EMULATOR_HOST: 'localhost:8080'},
    mode: 'destructive',
    destructiveScope: 'associations/jba',
  };
  assert.throws(
    () => guardFirestoreTarget({...options, argv: []}),
    /--confirm-delete=demo-hoopsconnect:associations\/jba/,
  );
  const target = guardFirestoreTarget({
    ...options,
    argv: ['--confirm-delete=demo-hoopsconnect:associations/jba'],
  });
  assert.equal(target.isEmulator, true);
});

test('refuses a non-local emulator host', () => {
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: [],
        env: {FIRESTORE_EMULATOR_HOST: 'example.com:8080'},
      }),
    /must point to localhost/,
  );
  assert.throws(
    () =>
      guardFirestoreTarget({
        argv: ['--confirm-delete=demo-hoopsconnect:associations/jba'],
        env: {
          FIRESTORE_EMULATOR_HOST: 'localhost:8080@evil.example:80',
        },
        mode: 'destructive',
        destructiveScope: 'associations/jba',
      }),
    /must point to localhost/,
  );
});
