'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {validateInvocation} = require('../run_local_qa');
const {
  cleanupIsolation,
  createIsolation,
} = require('../qa/local_qa_runtime');

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
  assert.throws(
    () => validateInvocation([], {NODE_OPTIONS: '--require=/tmp/untrusted.cjs'}),
    /NODE_OPTIONS is forbidden/,
  );
});

test('delivery preload is copied to a space-safe isolated path', () => {
  const isolation = createIsolation({
    env: {},
    node: {path: process.execPath},
    python: {path: 'python3'},
  });
  try {
    const match = isolation.env.NODE_OPTIONS.match(/--require=([^\s]+)/);
    assert.ok(match);
    assert.equal(fs.existsSync(match[1]), true);
    assert.equal(match[1].startsWith(isolation.directory), true);
    assert.equal(isolation.env.NODE_OPTIONS, `--require=${match[1]}`);
  } finally {
    cleanupIsolation(isolation);
  }
});

test('browser QA exercises both isolated and production Hosting CSP profiles', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../qa/run_ephemeral_checks.js'),
    'utf8',
  );
  assert.match(source, /web_boot_smoke\.py', '--timeout', '60'/);
  assert.match(
    source,
    /web_boot_smoke\.py', '--config', 'firebase\.json', '--timeout', '60'/,
  );
});
