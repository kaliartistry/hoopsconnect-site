'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const config = JSON.parse(fs.readFileSync(path.join(root, 'firebase.qa.json'), 'utf8'));
const csp = config.hosting.headers
  .find((entry) => entry.source === '**').headers
  .find((header) => header.key === 'Content-Security-Policy').value;
const bootstrap = fs.readFileSync(path.join(root, 'web/flutter_bootstrap.js'), 'utf8');

test('QA config isolates both Functions codebases and all data emulators', () => {
  assert.deepEqual(
    config.functions.map(({source, codebase}) => ({source, codebase})),
    [
      {source: 'functions', codebase: 'default'},
      {source: 'public_functions', codebase: 'public'},
    ],
  );
  assert.deepEqual(
    Object.fromEntries(
      ['auth', 'firestore', 'functions', 'storage'].map((service) => [
        service,
        [config.emulators[service].host, config.emulators[service].port],
      ]),
    ),
    {
      auth: ['127.0.0.1', 19099],
      firestore: ['127.0.0.1', 18080],
      functions: ['127.0.0.1', 15001],
      storage: ['127.0.0.1', 19199],
    },
  );
});

test('QA Hosting CSP permits exact startup dependencies without broad origins', () => {
  assert.match(csp, /script-src[^;]*https:\/\/www\.gstatic\.com\/firebasejs\//);
  assert.match(csp, /script-src[^;]*https:\/\/accounts\.google\.com\/gsi\/client/);
  assert.match(csp, /connect-src[^;]*http:\/\/127\.0\.0\.1:18080/);
  assert.match(csp, /connect-src[^;]*http:\/\/127\.0\.0\.1:15001/);
  assert.match(csp, /font-src[^;]*https:\/\/fonts\.gstatic\.com/);
  assert.match(csp, /connect-src[^;]*https:\/\/fonts\.gstatic\.com/);
  assert.doesNotMatch(csp, /(?:script-src|connect-src)[^;]*(?:\s\*|https:\/\/\*)/);
  assert.doesNotMatch(csp, /flutter-canvaskit/);
});

test('web bootstrap selects the engine-matched local renderer', () => {
  assert.match(bootstrap, /canvasKitBaseUrl:\s*'canvaskit\/'/);
  assert.doesNotMatch(bootstrap, /serviceWorkerVersion/);
  assert.doesNotMatch(bootstrap, /www\.gstatic\.com/);
  assert.match(bootstrap, /navigator\.serviceWorker\.getRegistrations\(\)/);
  assert.match(bootstrap, /navigator\.serviceWorker\.register\('flutter_service_worker\.js'/);
  assert.match(bootstrap, /pathname\.endsWith\('\/flutter_service_worker\.js'/);
  assert.doesNotMatch(bootstrap, /if \(registrations\.length > 0\)/);
});
