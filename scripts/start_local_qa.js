#!/usr/bin/env node
'use strict';

const {execFileSync, spawn} = require('node:child_process');
const net = require('node:net');

const {
  EMULATORS,
  REPOSITORY_ROOT,
  buildCandidate,
  cleanupIsolation,
  createIsolation,
  prepare,
  seedEnvironment,
  verifyDeliveryGuard,
} = require('./qa/local_qa_runtime');

function portReady(port) {
  return new Promise((resolve) => {
    const socket = net.createConnection({host: '127.0.0.1', port});
    socket.once('connect', () => { socket.destroy(); resolve(true); });
    socket.once('error', () => resolve(false));
    socket.setTimeout(500, () => { socket.destroy(); resolve(false); });
  });
}

async function waitForEmulators(child, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Firebase emulators exited ${child.exitCode}.`);
    const readiness = await Promise.all(Object.values(EMULATORS).map(portReady));
    if (readiness.every(Boolean)) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error('Timed out waiting for the complete local QA emulator suite.');
}

async function waitForGuard(logPath) {
  const deadline = Date.now() + 15000;
  let lastError;
  while (Date.now() < deadline) {
    try {
      return verifyDeliveryGuard(logPath);
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  throw lastError;
}

async function main() {
  const {target, tools} = prepare();
  buildCandidate(tools);
  const isolation = createIsolation(tools);
  const child = spawn(tools.node.path, [
    tools.firebase.entrypoint,
    'emulators:start',
    '--config', target.config,
    '--project', target.projectId,
    '--only', 'auth,firestore,functions,storage,hosting',
  ], {
    cwd: REPOSITORY_ROOT,
    env: isolation.env,
    stdio: 'inherit',
  });
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    child.kill('SIGINT');
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  try {
    await waitForEmulators(child);
    execFileSync(tools.node.path, ['scripts/qa/seed_local_qa.js'], {
      cwd: REPOSITORY_ROOT,
      env: seedEnvironment(isolation.env),
      stdio: 'inherit',
    });
    const guard = await waitForGuard(isolation.guardLog);
    console.log(
      `HOOPSCONNECT_QA_INTERACTIVE_READY url=http://127.0.0.1:${EMULATORS.hosting}/ ` +
      `guardedCodebases=${guard.codebases.join(',')} stop=Ctrl-C`,
    );
    await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', (code, signal) => {
        if (stopping || signal === 'SIGINT' || code === 0) resolve();
        else reject(new Error(`Firebase emulators exited ${code || signal}.`));
      });
    });
  } finally {
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
    if (child.exitCode === null && !child.killed) child.kill('SIGINT');
    cleanupIsolation(isolation);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = {portReady, waitForEmulators};
