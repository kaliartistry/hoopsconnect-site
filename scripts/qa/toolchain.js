#!/usr/bin/env node
'use strict';

const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const PINS = require('./toolchain.json');

function executableCandidates(name, env, fallbacks = []) {
  const override = env[`HOOPSCONNECT_QA_${name.toUpperCase()}`];
  const extension = process.platform === 'win32' && ['npm', 'firebase'].includes(name)
    ? '.cmd'
    : '';
  const fromPath = (env.PATH || '').split(path.delimiter)
    .filter(Boolean)
    .map((directory) => path.join(directory, `${name}${extension}`));
  return [override, ...fallbacks, ...fromPath].filter(Boolean);
}

function runnable(candidate, args, env) {
  if (!fs.existsSync(candidate)) return null;
  const result = spawnSync(candidate, args, {encoding: 'utf8', env});
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim();
  if (result.status === 0) return output;
  return {error: output || result.error?.message || `exit ${result.status}`};
}

function nodeEnvironment(candidate, env) {
  const result = {...env};
  if (process.platform === 'darwin' && candidate.includes('/node@22/')) {
    const cellar = '/opt/homebrew/Cellar/simdutf';
    const simdutfFallback = fs.existsSync(cellar)
      ? fs.readdirSync(cellar)
        .map((version) => path.join(cellar, version, 'lib'))
        .find((directory) => fs.existsSync(path.join(directory, 'libsimdutf.33.dylib')))
      : null;
    if (simdutfFallback) {
      result.DYLD_LIBRARY_PATH = [
        simdutfFallback,
        result.DYLD_LIBRARY_PATH,
      ].filter(Boolean).join(path.delimiter);
    }
  }
  return result;
}

function selectExecutable(name, args, env, fallbacks = []) {
  const failures = [];
  for (const candidate of executableCandidates(name, env, fallbacks)) {
    const candidateEnv = name === 'node' ? nodeEnvironment(candidate, env) : env;
    const result = runnable(candidate, args, candidateEnv);
    if (typeof result === 'string') return {path: candidate, output: result, env: candidateEnv};
    if (result) failures.push(`${candidate}: ${result.error}`);
  }
  throw new Error(
    `Unable to run ${name}. Set HOOPSCONNECT_QA_${name.toUpperCase()} to the pinned executable.` +
    (failures.length ? ` Attempts: ${failures.join(' | ')}` : ''),
  );
}

function parseMajor(output, label) {
  const match = output.match(/(?:version\s+\")?v?(\d+)(?:\.|\")/i);
  if (!match) throw new Error(`Could not parse ${label} version from ${JSON.stringify(output)}.`);
  return Number(match[1]);
}

function discoverToolchain(env = process.env) {
  const nodeFallbacks = process.platform === 'darwin'
    ? ['/opt/homebrew/opt/node@22/bin/node', '/usr/local/opt/node@22/bin/node']
    : [];
  const node = selectExecutable('node', ['--version'], env, nodeFallbacks);
  if (parseMajor(node.output, 'Node') !== PINS.nodeMajor) {
    throw new Error(`Node ${PINS.nodeMajor} is required; found ${node.output} at ${node.path}.`);
  }

  const javaFallbacks = [];
  if (env.JAVA_HOME) javaFallbacks.push(path.join(env.JAVA_HOME, 'bin', 'java'));
  if (process.platform === 'darwin') {
    javaFallbacks.push('/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java');
  }
  const java = selectExecutable('java', ['-version'], env, javaFallbacks);
  if (parseMajor(java.output, 'Java') !== PINS.javaMajor) {
    throw new Error(`Java ${PINS.javaMajor} is required; found ${java.output.split('\n')[0]} at ${java.path}.`);
  }

  const flutter = selectExecutable('flutter', ['--version', '--machine'], env);
  let flutterDetails;
  try {
    flutterDetails = JSON.parse(flutter.output);
  } catch (_error) {
    throw new Error(`Flutter --version --machine returned invalid JSON from ${flutter.path}.`);
  }
  if (flutterDetails.flutterVersion !== PINS.flutter || flutterDetails.dartSdkVersion !== PINS.dart) {
    throw new Error(
      `Flutter ${PINS.flutter} / Dart ${PINS.dart} required; found ` +
      `${flutterDetails.flutterVersion} / ${flutterDetails.dartSdkVersion}.`,
    );
  }

  const firebase = selectExecutable('firebase', ['--version'], env);
  if (firebase.output !== PINS.firebaseCli) {
    throw new Error(`Firebase CLI ${PINS.firebaseCli} is required; found ${firebase.output}.`);
  }

  const python = selectExecutable(
    'python3',
    ['--version'],
    env,
    process.platform === 'win32' ? [] : ['/usr/bin/python3'],
  );
  const npm = selectExecutable('npm', ['--version'], env);
  const runtimeEnv = {
    ...node.env,
    JAVA_HOME: path.dirname(path.dirname(java.path)),
  };
  firebase.entrypoint = fs.realpathSync(firebase.path);
  npm.entrypoint = fs.realpathSync(npm.path);
  return {node, java, flutter, firebase, npm, python, env: runtimeEnv};
}

function describeToolchain(tools) {
  return [
    `node=${tools.node.output}`,
    `java=${tools.java.output.split('\n')[0]}`,
    `flutter=${PINS.flutter}`,
    `dart=${PINS.dart}`,
    `firebase=${tools.firebase.output}`,
  ].join(' ');
}

module.exports = {PINS, describeToolchain, discoverToolchain, parseMajor};
