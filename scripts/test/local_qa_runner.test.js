'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {validateInvocation} = require('../run_local_qa');

test('local QA runner pins a dedicated demo target and config', () => {
  assert.deepEqual(validateInvocation([], {}), {
    projectId: 'demo-hoopsconnect-stage0-platform',
    config: 'firebase.qa.json',
  });
});

test('local QA runner rejects arguments and ambient credentials', () => {
  assert.throws(() => validateInvocation(['--project=hoops-connect-jm'], {}), /no command-line/);
  assert.throws(() => validateInvocation([], {FIREBASE_TOKEN: 'secret'}), /forbidden/);
  assert.throws(
    () => validateInvocation([], {GOOGLE_APPLICATION_CREDENTIALS: '/tmp/key.json'}),
    /forbidden/,
  );
});
