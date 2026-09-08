'use strict';

const PRODUCTION_PROJECTS = new Set(['hoops-connect-jm']);
const DEFAULT_EMULATOR_PROJECT = 'demo-hoopsconnect';

function readFlag(argv, name) {
  const exact = argv.find((arg) => arg.startsWith(`${name}=`));
  if (exact) return exact.slice(name.length + 1);
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : undefined;
}

function localEmulatorHost(value) {
  if (!value) return null;
  if (value.includes('://')) {
    throw new Error('FIRESTORE_EMULATOR_HOST must use host:port syntax.');
  }
  let parsed;
  try {
    parsed = new URL(`http://${value}`);
  } catch {
    throw new Error('FIRESTORE_EMULATOR_HOST must be a valid local host and port.');
  }
  if (
    parsed.username
    || parsed.password
    || parsed.pathname !== '/'
    || parsed.search
    || parsed.hash
    || !parsed.port
    || !['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname)
  ) {
    throw new Error('FIRESTORE_EMULATOR_HOST must point to localhost.');
  }
  return parsed.host;
}

function guardFirestoreTarget({
  argv = process.argv.slice(2),
  env = process.env,
  mode = 'write',
  destructiveScope = null,
} = {}) {
  const emulatorHost = localEmulatorHost(env.FIRESTORE_EMULATOR_HOST);
  const projectId =
    readFlag(argv, '--project') ||
    env.GCLOUD_PROJECT ||
    env.GOOGLE_CLOUD_PROJECT ||
    (emulatorHost ? DEFAULT_EMULATOR_PROJECT : null);

  if (!projectId) {
    throw new Error(
      'No Firebase project selected. Start the local emulator or pass --project for an explicitly allowlisted non-production project.',
    );
  }
  if (PRODUCTION_PROJECTS.has(projectId)) {
    if (mode !== 'read') {
      throw new Error(`Refusing to ${mode} protected production project ${projectId}.`);
    }
    if (readFlag(argv, '--allow-production-read') !== projectId) {
      throw new Error(
        `Production reads require --allow-production-read=${projectId}; writes remain prohibited.`,
      );
    }
  }

  if (!emulatorHost && !PRODUCTION_PROJECTS.has(projectId)) {
    const allowlist = new Set(
      (env.HOOPSCONNECT_NONPROD_PROJECT_ALLOWLIST || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean),
    );
    if (!allowlist.has(projectId)) {
      throw new Error(
        `Remote project ${projectId} is not in HOOPSCONNECT_NONPROD_PROJECT_ALLOWLIST.`,
      );
    }
    if (readFlag(argv, '--allow-remote-nonprod') !== projectId) {
      throw new Error(
        `Remote non-production access requires --allow-remote-nonprod=${projectId}.`,
      );
    }
  }

  if (destructiveScope) {
    const expected = `${projectId}:${destructiveScope}`;
    if (readFlag(argv, '--confirm-delete') !== expected) {
      throw new Error(`Destructive seed requires --confirm-delete=${expected}.`);
    }
  }

  const baseUrl = emulatorHost
    ? `http://${emulatorHost}/v1/projects/${projectId}/databases/(default)/documents`
    : `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

  return {
    projectId,
    emulatorHost,
    isEmulator: Boolean(emulatorHost),
    baseUrl,
  };
}

module.exports = {
  DEFAULT_EMULATOR_PROJECT,
  PRODUCTION_PROJECTS,
  guardFirestoreTarget,
  readFlag,
};
