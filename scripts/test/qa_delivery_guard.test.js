'use strict';

const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const guardPath = path.resolve(__dirname, '../qa/functions_runtime_guard.cjs');

test('Functions emulator guard fails closed for external delivery and permits loopback', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-guard-test-'));
  const guardLog = path.join(directory, 'guard.jsonl');
  try {
    const script = [
      `const guard = require(${JSON.stringify(guardPath)});`,
      `if (!guard.active) throw new Error('guard inactive');`,
      `guard.assertAllowedUrl('http://127.0.0.1:8080/local');`,
      `guard.assertAllowedUrl('http://[::1]:8080/local');`,
      `try { guard.assertAllowedUrl('https://fcm.googleapis.com/v1/projects/demo/messages:send'); }`,
      `catch (error) { if (/EXTERNAL_DELIVERY_BLOCKED/.test(error.message)) process.exit(0); throw error; }`,
      `throw new Error('external delivery was not blocked');`,
    ].join('');
    const result = spawnSync(process.execPath, ['-e', script], {
      encoding: 'utf8',
      env: {
        ...process.env,
        FUNCTIONS_EMULATOR: 'true',
        GCLOUD_PROJECT: 'demo-hoopsconnect-stage0-platform',
        FIRESTORE_EMULATOR_HOST: '127.0.0.1:18080',
        FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19099',
        HOOPSCONNECT_QA_DISABLE_EXTERNAL_DELIVERY: 'true',
        HOOPSCONNECT_QA_DELIVERY_GUARD_LOG: guardLog,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    const record = JSON.parse(fs.readFileSync(guardLog, 'utf8').trim());
    assert.equal(record.pid > 0, true);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});

test('delivery guard cannot activate outside the synthetic project', () => {
  const result = spawnSync(process.execPath, ['-e', `require(${JSON.stringify(guardPath)})`], {
    encoding: 'utf8',
    env: {
      ...process.env,
      FUNCTIONS_EMULATOR: 'true',
      GCLOUD_PROJECT: 'hoops-connect-jm',
      HOOPSCONNECT_QA_DISABLE_EXTERNAL_DELIVERY: 'true',
    },
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /refuses project hoops-connect-jm/);
});
