#!/usr/bin/env node
'use strict';

const {execFileSync} = require('node:child_process');

const {REPOSITORY_ROOT, seedEnvironment} = require('./local_qa_runtime');

const env = seedEnvironment(process.env);
execFileSync(process.execPath, ['scripts/qa/seed_local_qa.js'], {
  cwd: REPOSITORY_ROOT,
  env,
  stdio: 'inherit',
});
execFileSync(process.env.HOOPSCONNECT_QA_PYTHON || 'python3', [
  'scripts/qa/web_boot_smoke.py', '--timeout', '60',
], {
  cwd: REPOSITORY_ROOT,
  env,
  stdio: 'inherit',
});
execFileSync(process.env.HOOPSCONNECT_QA_PYTHON || 'python3', [
  'scripts/qa/web_boot_smoke.py', '--config', 'firebase.json', '--timeout', '60',
], {
  cwd: REPOSITORY_ROOT,
  env,
  stdio: 'inherit',
});
