#!/usr/bin/env node
'use strict';

const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

const {
  CREDENTIAL_ENV,
  EMULATORS,
  PROJECT_ID,
  REPOSITORY_ROOT,
} = require('./qa/local_qa_runtime');
const {discoverToolchain} = require('./qa/toolchain');

function portReady(port) {
  return new Promise((resolve) => {
    const socket = net.createConnection({host: '127.0.0.1', port});
    socket.once('connect', () => {
      socket.destroy();
      resolve(true);
    });
    socket.once('error', () => resolve(false));
    socket.setTimeout(500, () => {
      socket.destroy();
      resolve(false);
    });
  });
}

async function requireRunningEmulators() {
  const services = ['auth', 'firestore', 'functions', 'storage'];
  const readiness = await Promise.all(
    services.map(async (service) => [service, await portReady(EMULATORS[service])]),
  );
  const missing = readiness.filter(([, ready]) => !ready).map(([name]) => name);
  if (missing.length > 0) {
    throw new Error(
      `Local QA emulators are not running (${missing.join(', ')}). ` +
      'Start node scripts/start_local_qa.js in another terminal first.',
    );
  }
}

function bootedIphone() {
  const output = execFileSync(
    '/usr/bin/xcrun',
    ['simctl', 'list', 'devices', 'booted', '--json'],
    {encoding: 'utf8'},
  );
  const runtimes = Object.values(JSON.parse(output).devices || {});
  const booted = runtimes.flat().filter((device) => device.state === 'Booted');
  return booted.find((device) => device.name.includes('HoopsConnect')) ??
    booted.find((device) => device.name.includes('iPhone')) ??
    booted[0];
}

function makeSafeScratchCopy() {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-ios-qa-'));
  execFileSync(
    '/usr/bin/rsync',
    [
      '-a',
      '--exclude=.git',
      '--exclude=.dart_tool',
      '--exclude=build',
      '--exclude=node_modules',
      '--exclude=functions/node_modules',
      '--exclude=public_functions/node_modules',
      '--exclude=.env',
      '--exclude=.env.*',
      `${REPOSITORY_ROOT}/`,
      `${scratch}/`,
    ],
    {stdio: 'inherit'},
  );

  const projectPath = path.join(
    scratch,
    'ios/Runner.xcodeproj/project.pbxproj',
  );
  const project = fs.readFileSync(projectPath, 'utf8');
  const sanitized = project
    .split('\n')
    .filter((line) => !line.includes('GoogleService-Info.plist'))
    .join('\n');
  if (sanitized === project) {
    throw new Error('The iOS production Firebase resource was not found.');
  }
  fs.writeFileSync(projectPath, sanitized, 'utf8');
  fs.rmSync(path.join(scratch, 'ios/Runner/GoogleService-Info.plist'), {
    force: true,
  });
  return scratch;
}

async function main() {
  if (process.argv.length !== 2) {
    throw new Error('The iOS simulator QA runner accepts no arguments.');
  }
  await requireRunningEmulators();
  const device = bootedIphone();
  if (!device) {
    throw new Error(
      'Boot an iPhone simulator in Xcode, then run this command again.',
    );
  }

  const tools = discoverToolchain(process.env);
  const scratch = makeSafeScratchCopy();
  const env = {...tools.env};
  for (const name of CREDENTIAL_ENV) delete env[name];
  try {
    execFileSync(tools.flutter.path, ['pub', 'get'], {
      cwd: scratch,
      env,
      stdio: 'inherit',
    });
    console.log(
      `HOOPSCONNECT_IOS_QA_SAFE device=${device.name} project=${PROJECT_ID} ` +
      'productionPlistBundled=false stop=Ctrl-C',
    );
    execFileSync(
      tools.flutter.path,
      [
        'run',
        '-d',
        device.udid,
        '--target=lib/main_qa.dart',
        '--dart-define=HOOPSCONNECT_QA_MODE=true',
        `--dart-define=HOOPSCONNECT_QA_PROJECT_ID=${PROJECT_ID}`,
        '--dart-define=HOOPSCONNECT_QA_EMULATOR_HOST=127.0.0.1',
        `--dart-define=HOOPSCONNECT_QA_AUTH_PORT=${EMULATORS.auth}`,
        `--dart-define=HOOPSCONNECT_QA_FIRESTORE_PORT=${EMULATORS.firestore}`,
        `--dart-define=HOOPSCONNECT_QA_FUNCTIONS_PORT=${EMULATORS.functions}`,
        `--dart-define=HOOPSCONNECT_QA_STORAGE_PORT=${EMULATORS.storage}`,
      ],
      {cwd: scratch, env, stdio: 'inherit'},
    );
  } finally {
    fs.rmSync(scratch, {recursive: true, force: true});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  bootedIphone,
  makeSafeScratchCopy,
  portReady,
  requireRunningEmulators,
};
