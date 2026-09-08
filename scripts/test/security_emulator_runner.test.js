'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {validateSecurityEmulatorInvocation} = require('../run_security_emulators');

test('security runner is pinned to the demo project and complete emulator set', () => {
  assert.deepEqual(validateSecurityEmulatorInvocation([], {}), {
    projectId: 'demo-hoopsconnect',
    services: 'auth,firestore,functions,storage',
  });
});

test('security runner rejects extra args, credentials, remote hosts, and URL userinfo', () => {
  assert.throws(
    () => validateSecurityEmulatorInvocation(['--project=production'], {}),
    /accepts no command-line arguments/,
  );
  assert.throws(
    () => validateSecurityEmulatorInvocation([], {FIREBASE_TOKEN: 'secret'}),
    /FIREBASE_TOKEN is forbidden/,
  );
  assert.throws(
    () => validateSecurityEmulatorInvocation([], {CLOUDSDK_CONFIG: '/real/credentials'}),
    /CLOUDSDK_CONFIG is forbidden/,
  );
  assert.throws(
    () => validateSecurityEmulatorInvocation([], {FIRESTORE_EMULATOR_HOST: 'example.com:8080'}),
    /loopback host and port/,
  );
  assert.throws(
    () => validateSecurityEmulatorInvocation([], {FIRESTORE_EMULATOR_HOST: 'localhost:8080@evil.example:80'}),
    /loopback host and port/,
  );
});
