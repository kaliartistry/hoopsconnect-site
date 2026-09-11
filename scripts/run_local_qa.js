#!/usr/bin/env node
'use strict';

const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PROJECT_ID = 'demo-hoopsconnect-stage0-platform';
const CONFIG = 'firebase.qa.json';
const REPOSITORY_ROOT = path.resolve(__dirname, '..');
const CREDENTIAL_ENV = [
  'FIREBASE_TOKEN',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'GOOGLE_CLOUD_ACCESS_TOKEN',
  'CLOUDSDK_AUTH_ACCESS_TOKEN',
];

function validateInvocation(argv = process.argv.slice(2), env = process.env) {
  if (argv.length !== 0) {
    throw new Error('The local QA runner accepts no command-line arguments.');
  }
  for (const name of CREDENTIAL_ENV) {
    if (env[name]) throw new Error(`${name} is forbidden in local QA.`);
  }
  const config = JSON.parse(
    fs.readFileSync(path.join(REPOSITORY_ROOT, CONFIG), 'utf8'),
  );
  const emulators = config.emulators || {};
  const expected = {
    auth: 19099,
    firestore: 18080,
    functions: 15001,
    storage: 19199,
  };
  for (const [service, port] of Object.entries(expected)) {
    const actual = emulators[service];
    if (actual?.host !== '127.0.0.1' || actual?.port !== port) {
      throw new Error(`${service} must use the recorded loopback QA endpoint.`);
    }
  }
  return {projectId: PROJECT_ID, config: CONFIG};
}

function run(file, args, options = {}) {
  execFileSync(file, args, {stdio: 'inherit', cwd: REPOSITORY_ROOT, ...options});
}

function main() {
  const target = validateInvocation();
  run('npm', ['--prefix', 'functions', 'run', 'build']);
  run('npm', ['--prefix', 'public_functions', 'run', 'build']);
  run('flutter', [
    'build', 'web', '--release', '--no-pub', '--target=lib/main_qa.dart',
    '--dart-define=HOOPSCONNECT_QA_MODE=true',
    `--dart-define=HOOPSCONNECT_QA_PROJECT_ID=${target.projectId}`,
    '--dart-define=HOOPSCONNECT_QA_EMULATOR_HOST=127.0.0.1',
    '--dart-define=HOOPSCONNECT_QA_AUTH_PORT=19099',
    '--dart-define=HOOPSCONNECT_QA_FIRESTORE_PORT=18080',
    '--dart-define=HOOPSCONNECT_QA_FUNCTIONS_PORT=15001',
    '--dart-define=HOOPSCONNECT_QA_STORAGE_PORT=19199',
  ]);

  const isolatedCloudConfig = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-qa-cloud-'));
  const disabledCredential = path.join(isolatedCloudConfig, 'disabled-credential.json');
  fs.writeFileSync(disabledCredential, '{}', {encoding: 'utf8', mode: 0o600});
  try {
    run(
      'firebase',
      [
        'emulators:exec',
        '--config', target.config,
        '--project', target.projectId,
        '--only', 'auth,firestore,functions,storage',
        'env -u GOOGLE_APPLICATION_CREDENTIALS FUNCTIONS_EMULATOR_HOST=127.0.0.1:15001 node scripts/qa/seed_local_qa.js && python3 scripts/qa/web_boot_smoke.py --timeout 45',
      ],
      {
        env: {
          ...process.env,
          CLOUDSDK_CONFIG: isolatedCloudConfig,
          GOOGLE_APPLICATION_CREDENTIALS: disabledCredential,
          HOOPSCONNECT_QA_DISABLE_EXTERNAL_DELIVERY: 'true',
        },
      },
    );
  } finally {
    fs.rmSync(isolatedCloudConfig, {recursive: true, force: true});
  }
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {validateInvocation};
