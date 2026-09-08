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
const connectSources = csp
  .split(';')
  .map((directive) => directive.trim().split(/\s+/))
  .find(([name]) => name === 'connect-src')
  .slice(1);

function allows(urlString, selfOrigin = 'https://hoops-connect-jm.web.app') {
  const url = new URL(urlString);
  return connectSources.some((source) => {
    if (source === "'self'") return url.origin === selfOrigin;
    if (source.startsWith('wss://*.')) {
      return url.protocol === 'wss:' && url.hostname.endsWith(source.slice('wss://*'.length));
    }
    if (source.startsWith('https://*.')) {
      return url.protocol === 'https:' && url.hostname.endsWith(source.slice('https://*'.length));
    }
    return url.origin === source;
  });
}

test('deployed Hosting CSP permits exact Firebase client endpoints and blocks unrelated origins', () => {
  assert.equal(allows('https://us-central1-hoops-connect-jm.cloudfunctions.net/provisionFanProfile'), true);
  assert.equal(allows('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword'), true);
  assert.equal(allows('https://firestore.googleapis.com/google.firestore.v1.Firestore/Listen/channel'), true);
  assert.equal(allows('https://firebasestorage.googleapis.com/v0/b/hoops-connect-jm/o'), true);
  assert.equal(allows('https://hoops-connect-jm.web.app/assets/app.js'), true);
  assert.equal(allows('https://evil.example/collect'), false);
  assert.equal(connectSources.some((source) => source === '*' || source === 'https://*'), false);
});
