#!/usr/bin/env node
'use strict';

const {execFileSync} = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT_ID = 'demo-hoopsconnect';
const SERVICES = 'auth,firestore,functions,storage';
const CREDENTIAL_ENV = [
  'GOOGLE_APPLICATION_CREDENTIALS',
  'FIREBASE_TOKEN',
  'GOOGLE_CLOUD_ACCESS_TOKEN',
  'CLOUDSDK_AUTH_ACCESS_TOKEN',
  'CLOUDSDK_CONFIG',
];

function validateSecurityEmulatorInvocation(argv = process.argv.slice(2), env = process.env) {
  if (argv.length !== 0) {
    throw new Error('The security emulator runner accepts no command-line arguments.');
  }
  for (const name of CREDENTIAL_ENV) {
    if (env[name]) throw new Error(`Credential environment variable ${name} is forbidden.`);
  }
  for (const name of [
    'FIRESTORE_EMULATOR_HOST',
    'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
  ]) {
    const value = env[name];
    if (value && !/^(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/.test(value)) {
      throw new Error(`${name} must be an uncredentialed loopback host and port.`);
    }
  }
  return {projectId: PROJECT_ID, services: SERVICES};
}

function main() {
  validateSecurityEmulatorInvocation();
  execFileSync('npm', ['--prefix', 'functions', 'run', 'build'], {stdio: 'inherit'});
  const isolatedCloudConfig = fs.mkdtempSync(path.join(os.tmpdir(), 'hoops-security-'));
  const disabledCredential = path.join(isolatedCloudConfig, 'disabled-credential.json');
  fs.writeFileSync(disabledCredential, '{}', {encoding: 'utf8', mode: 0o600});
  try {
    execFileSync(
      'firebase',
      [
        'emulators:exec',
        '--project', PROJECT_ID,
        '--only', SERVICES,
        'npm --prefix functions run test:security:no-build',
      ],
      {
        stdio: 'inherit',
        env: {
          ...process.env,
          CLOUDSDK_CONFIG: isolatedCloudConfig,
          // Force any accidental non-emulator Admin SDK call to fail while
          // loading a deliberately invalid local credential, before network.
          GOOGLE_APPLICATION_CREDENTIALS: disabledCredential,
          INVITE_TOKEN_HMAC_KEY_V1: 'local-emulator-only-key-with-at-least-32-bytes',
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
    process.exit(1);
  }
}

module.exports = {validateSecurityEmulatorInvocation};
