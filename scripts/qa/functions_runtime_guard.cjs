'use strict';

const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');

const PROJECT_ID = 'demo-hoopsconnect-stage0-platform';
const LOOPBACK_HOSTS = new Set(['127.0.0.1', '::1', 'localhost']);
const active = process.env.FUNCTIONS_EMULATOR === 'true' &&
  process.env.HOOPSCONNECT_QA_DISABLE_EXTERNAL_DELIVERY === 'true';

function assertAllowedUrl(value) {
  const parsed = value instanceof URL ? value : new URL(String(value));
  const hostname = parsed.hostname.replace(/^\[|\]$/g, '');
  if (!LOOPBACK_HOSTS.has(hostname)) {
    throw new Error(
      `HOOPSCONNECT_QA_EXTERNAL_DELIVERY_BLOCKED ${parsed.protocol}//${parsed.host}`,
    );
  }
  return parsed;
}

function requestUrl(args, fallbackProtocol) {
  const first = args[0];
  if (first instanceof URL || typeof first === 'string') return first;
  const options = first || {};
  const protocol = options.protocol || fallbackProtocol;
  const hostname = options.hostname || options.host || 'localhost';
  const port = options.port ? `:${options.port}` : '';
  return `${protocol}//${hostname}${port}${options.path || '/'}`;
}

function installRequestGuard(module, protocol) {
  const original = module.request.bind(module);
  module.request = (...args) => {
    assertAllowedUrl(requestUrl(args, protocol));
    return original(...args);
  };
  module.get = (...args) => {
    const request = module.request(...args);
    request.end();
    return request;
  };
}

if (active) {
  if (process.env.GCLOUD_PROJECT !== PROJECT_ID) {
    throw new Error(`QA delivery guard refuses project ${process.env.GCLOUD_PROJECT || '<unset>'}.`);
  }
  for (const name of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    const value = process.env[name] || '';
    let hostname = '';
    try {
      hostname = new URL(`http://${value}`).hostname.replace(/^\[|\]$/g, '');
    } catch (_error) {
      // The closed-path error below intentionally handles malformed endpoints.
    }
    if (!LOOPBACK_HOSTS.has(hostname)) {
      throw new Error(`QA delivery guard requires loopback ${name}.`);
    }
  }
  installRequestGuard(http, 'http:');
  installRequestGuard(https, 'https:');
  if (typeof globalThis.fetch === 'function') {
    const originalFetch = globalThis.fetch.bind(globalThis);
    globalThis.fetch = (input, init) => {
      assertAllowedUrl(input instanceof Request ? input.url : input);
      return originalFetch(input, init);
    };
  }
  const logPath = process.env.HOOPSCONNECT_QA_DELIVERY_GUARD_LOG;
  if (!logPath) throw new Error('QA delivery guard log path is required.');
  fs.appendFileSync(logPath, `${JSON.stringify({pid: process.pid, cwd: process.cwd()})}\n`);
}

module.exports = {active, assertAllowedUrl};
