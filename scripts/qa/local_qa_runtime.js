'use strict';

const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {describeToolchain, discoverToolchain} = require('./toolchain');

const PROJECT_ID = 'demo-hoopsconnect-stage0-platform';
const CONFIG = 'firebase.qa.json';
const REPOSITORY_ROOT = path.resolve(__dirname, '../..');
const CREDENTIAL_ENV = [
  'FIREBASE_TOKEN',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'GOOGLE_CLOUD_ACCESS_TOKEN',
  'CLOUDSDK_AUTH_ACCESS_TOKEN',
];
const EMULATORS = Object.freeze({
  auth: 19099,
  firestore: 18080,
  functions: 15001,
  storage: 19199,
  hosting: 15500,
});

function validateInvocation(argv = process.argv.slice(2), env = process.env) {
  if (argv.length !== 0) {
    throw new Error('The local QA runner accepts no command-line arguments.');
  }
  for (const name of CREDENTIAL_ENV) {
    if (env[name]) throw new Error(`${name} is forbidden in local QA.`);
  }
  const config = JSON.parse(fs.readFileSync(path.join(REPOSITORY_ROOT, CONFIG), 'utf8'));
  for (const [service, port] of Object.entries(EMULATORS)) {
    const actual = config.emulators?.[service];
    if (actual?.host !== '127.0.0.1' || actual?.port !== port) {
      throw new Error(`${service} must use the recorded loopback QA endpoint.`);
    }
  }
  return {projectId: PROJECT_ID, config: CONFIG};
}

function run(file, args, options = {}) {
  execFileSync(file, args, {
    stdio: 'inherit',
    cwd: REPOSITORY_ROOT,
    ...options,
  });
}

function buildCandidate(tools) {
  run(tools.node.path, [tools.npm.entrypoint, '--prefix', 'functions', 'run', 'build'], {env: tools.env});
  run(tools.node.path, [tools.npm.entrypoint, '--prefix', 'public_functions', 'run', 'build'], {env: tools.env});
  run(tools.flutter.path, [
    'build', 'web', '--release', '--no-pub', '--target=lib/main_qa.dart',
    '--dart-define=HOOPSCONNECT_QA_MODE=true',
    `--dart-define=HOOPSCONNECT_QA_PROJECT_ID=${PROJECT_ID}`,
    '--dart-define=HOOPSCONNECT_QA_EMULATOR_HOST=127.0.0.1',
    `--dart-define=HOOPSCONNECT_QA_AUTH_PORT=${EMULATORS.auth}`,
    `--dart-define=HOOPSCONNECT_QA_FIRESTORE_PORT=${EMULATORS.firestore}`,
    `--dart-define=HOOPSCONNECT_QA_FUNCTIONS_PORT=${EMULATORS.functions}`,
    `--dart-define=HOOPSCONNECT_QA_STORAGE_PORT=${EMULATORS.storage}`,
  ], {env: tools.env});
}

function createIsolation(tools) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-qa-cloud-'));
  const disabledCredential = path.join(directory, 'disabled-credential.json');
  const guardLog = path.join(directory, 'delivery-guard.jsonl');
  fs.writeFileSync(disabledCredential, '{}', {encoding: 'utf8', mode: 0o600});
  const preload = path.join(REPOSITORY_ROOT, 'scripts/qa/functions_runtime_guard.cjs');
  const nodeOptions = [tools.env.NODE_OPTIONS, `--require=${preload}`].filter(Boolean).join(' ');
  return {
    directory,
    guardLog,
    env: {
      ...tools.env,
      CLOUDSDK_CONFIG: directory,
      GOOGLE_APPLICATION_CREDENTIALS: disabledCredential,
      HOOPSCONNECT_QA_DISABLE_EXTERNAL_DELIVERY: 'true',
      HOOPSCONNECT_QA_DELIVERY_GUARD_LOG: guardLog,
      HOOPSCONNECT_QA_NODE: tools.node.path,
      HOOPSCONNECT_QA_PYTHON: tools.python.path,
      NODE_OPTIONS: nodeOptions,
    },
  };
}

function seedEnvironment(baseEnv) {
  const env = {
    ...baseEnv,
    GCLOUD_PROJECT: PROJECT_ID,
    FIREBASE_AUTH_EMULATOR_HOST: `127.0.0.1:${EMULATORS.auth}`,
    FIRESTORE_EMULATOR_HOST: `127.0.0.1:${EMULATORS.firestore}`,
    FUNCTIONS_EMULATOR_HOST: `127.0.0.1:${EMULATORS.functions}`,
    FIREBASE_STORAGE_EMULATOR_HOST: `127.0.0.1:${EMULATORS.storage}`,
  };
  for (const name of CREDENTIAL_ENV) delete env[name];
  return env;
}

function verifyDeliveryGuard(logPath) {
  if (!fs.existsSync(logPath)) {
    throw new Error('Both Functions codebases must load the QA delivery guard; no guard log exists.');
  }
  const records = fs.readFileSync(logPath, 'utf8').trim().split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  const codebases = new Set(records.map((record) => {
    if (record.cwd.endsWith(`${path.sep}public_functions`)) return 'public';
    if (record.cwd.endsWith(`${path.sep}functions`)) return 'default';
    return null;
  }).filter(Boolean));
  for (const expected of ['default', 'public']) {
    if (!codebases.has(expected)) {
      throw new Error(`QA delivery guard was not observed in the ${expected} Functions codebase.`);
    }
  }
  return {records: records.length, codebases: [...codebases].sort()};
}

function cleanupIsolation(isolation) {
  fs.rmSync(isolation.directory, {recursive: true, force: true});
}

function shellCommand(file, args, env) {
  const quote = (value) => JSON.stringify(String(value));
  const prefix = process.platform === 'darwin' && env.DYLD_LIBRARY_PATH
    ? `DYLD_LIBRARY_PATH=${quote(env.DYLD_LIBRARY_PATH)} `
    : '';
  return `${prefix}${[file, ...args].map(quote).join(' ')}`;
}

function prepare(argv = process.argv.slice(2), env = process.env) {
  const target = validateInvocation(argv, env);
  const tools = discoverToolchain(env);
  console.log(`HOOPSCONNECT_QA_TOOLCHAIN_OK ${describeToolchain(tools)}`);
  return {target, tools};
}

module.exports = {
  CONFIG,
  CREDENTIAL_ENV,
  EMULATORS,
  PROJECT_ID,
  REPOSITORY_ROOT,
  buildCandidate,
  cleanupIsolation,
  createIsolation,
  prepare,
  run,
  seedEnvironment,
  shellCommand,
  validateInvocation,
  verifyDeliveryGuard,
};
