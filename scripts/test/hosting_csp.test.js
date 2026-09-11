'use strict';

const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const test = require('node:test');

const firebase = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../../firebase.json'), 'utf8'),
);
const csp = firebase.hosting.headers
  .find((entry) => entry.source === '**')
  .headers.find((header) => header.key === 'Content-Security-Policy').value;
const directives = Object.fromEntries(
  csp
    .split(';')
    .map((directive) => directive.trim())
    .filter(Boolean)
    .map((directive) => {
      const [name, ...sources] = directive.split(/\s+/);
      return [name, sources];
    }),
);

test('production and QA web entrypoints use clean-path routing', () => {
  for (const entrypoint of ['lib/main.dart', 'lib/main_qa.dart']) {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../..', entrypoint),
      'utf8',
    );
    assert.match(
      source,
      /package:flutter_web_plugins\/url_strategy\.dart/,
      `${entrypoint} must import Flutter's reviewed URL strategy`,
    );
    assert.match(
      source,
      /WidgetsFlutterBinding\.ensureInitialized\(\);\s*usePathUrlStrategy\(\);/,
      `${entrypoint} must select clean paths before app initialization`,
    );
  }
  assert.deepEqual(firebase.hosting.rewrites, [
    {source: '**', destination: '/index.html'},
  ]);
});

function sourceAllows(source, urlString, selfOrigin) {
  if (source === "'self'") {
    return new URL(urlString, selfOrigin).origin === selfOrigin;
  }
  if (source === 'blob:') return urlString.startsWith('blob:');

  const url = new URL(urlString, selfOrigin);
  if (source.startsWith('wss://*.')) {
    return (
      url.protocol === 'wss:' &&
      url.hostname.endsWith(source.slice('wss://*'.length))
    );
  }
  if (source.startsWith('https://*.')) {
    return (
      url.protocol === 'https:' &&
      url.hostname.endsWith(source.slice('https://*'.length))
    );
  }
  if (!source.startsWith('https://')) return false;

  const allowed = new URL(source);
  const pathMatches = allowed.pathname.endsWith('/')
    ? url.pathname.startsWith(allowed.pathname)
    : url.pathname === allowed.pathname;
  return (
    url.origin === allowed.origin &&
    (allowed.pathname === '/' || pathMatches)
  );
}

function allows(
  directive,
  urlString,
  selfOrigin = 'https://hoops-connect-jm.web.app',
) {
  return (directives[directive] || []).some((source) =>
    sourceAllows(source, urlString, selfOrigin),
  );
}

function assertNoBroadNetworkSource(directive) {
  const sources = directives[directive] || [];
  assert.equal(
    sources.some((source) => source === '*' || source === 'https://*'),
    false,
  );
}

test('Hosting CSP permits exact Firebase client endpoints only', () => {
  assert.equal(
    allows(
      'connect-src',
      'https://us-central1-hoops-connect-jm.cloudfunctions.net/provisionFanProfile',
    ),
    true,
  );
  assert.equal(
    allows('connect-src', 'https://identitytoolkit.googleapis.com/v1/accounts'),
    true,
  );
  assert.equal(
    allows('connect-src', 'https://firestore.googleapis.com/listen'),
    true,
  );
  assert.equal(
    allows('connect-src', 'https://firebasestorage.googleapis.com/v0/b/app/o'),
    true,
  );
  assert.equal(allows('connect-src', 'https://evil.example/collect'), false);
  assertNoBroadNetworkSource('connect-src');
});

test('Hosting CSP path-scopes FlutterFire and Google provider scripts', () => {
  assert.equal(
    allows(
      'script-src',
      'https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js',
    ),
    true,
  );
  assert.equal(
    allows('script-src', 'https://www.gstatic.com/unrelated/library.js'),
    false,
  );
  assert.equal(
    allows('script-src', 'https://accounts.google.com/gsi/client'),
    true,
  );
  assert.equal(
    allows('script-src', 'https://accounts.google.com/unrelated.js'),
    false,
  );
  assert.equal(
    allows('script-src', 'https://www.google.com/recaptcha/api.js'),
    true,
  );
  assert.equal(
    allows('script-src', 'https://www.gstatic.com/recaptcha/releases/pinned.js'),
    true,
  );
  assertNoBroadNetworkSource('script-src');
});

test('Hosting CSP permits only required provider frames, styles, and workers', () => {
  assert.equal(
    allows('frame-src', 'https://accounts.google.com/gsi/button'),
    true,
  );
  assert.equal(
    allows(
      'frame-src',
      'https://hoops-connect-jm.firebaseapp.com/__/auth/iframe',
    ),
    true,
  );
  assert.equal(
    allows('frame-src', 'https://www.google.com/recaptcha/api2/anchor'),
    true,
  );
  assert.equal(
    allows('frame-src', 'https://recaptcha.google.com/recaptcha/api2/bframe'),
    true,
  );
  assert.equal(allows('frame-src', 'https://evil.example/frame'), false);
  assert.equal(
    allows('style-src', 'https://accounts.google.com/gsi/style'),
    true,
  );
  assert.equal(
    allows('worker-src', 'https://hoops-connect-jm.web.app/firebase-worker.js'),
    true,
  );
  assert.equal(
    allows('worker-src', 'blob:https://hoops-connect-jm.web.app/id'),
    true,
  );
  assert.equal(allows('worker-src', 'https://evil.example/worker.js'), false);
  for (const directive of ['frame-src', 'style-src', 'worker-src']) {
    assertNoBroadNetworkSource(directive);
  }
});
