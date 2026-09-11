'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {validateInvocation} = require('../run_local_qa');
const {
  cleanupIsolation,
  createIsolation,
  seedEnvironment,
  verifyDeliveryGuard,
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

test('synthetic seed process activates the same network guard as workers', () => {
  const env = seedEnvironment({NODE_OPTIONS: '--require=/tmp/qa-guard.cjs'});
  assert.equal(env.FUNCTIONS_EMULATOR, 'true');
  assert.equal(env.NODE_OPTIONS, '--require=/tmp/qa-guard.cjs');
  assert.equal(env.GCLOUD_PROJECT, 'demo-hoopsconnect-stage0-platform');
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

test('triggerless public projection stays inside the guarded QA harness', () => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'hoops-guard-log-'),
  );
  const log = path.join(directory, 'guard.jsonl');
  try {
    fs.writeFileSync(log, [
      JSON.stringify({pid: 1, cwd: path.resolve(__dirname, '../..')}),
      JSON.stringify({pid: 2, cwd: path.resolve(__dirname, '../../functions')}),
    ].join('\n'));
    assert.deepEqual(verifyDeliveryGuard(log).codebases, ['default', 'public']);

    fs.writeFileSync(
      log,
      `${JSON.stringify({pid: 2, cwd: path.resolve(__dirname, '../../functions')})}\n`,
    );
    assert.throws(
      () => verifyDeliveryGuard(log),
      /neither loaded the QA delivery guard nor proved/,
    );
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
