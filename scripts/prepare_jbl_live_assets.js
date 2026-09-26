#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const ROOT = path.resolve(__dirname, '..');
const FILES = ['full', 'sub', 'foska', 'tivoli', 'slayers', 'warriors', 'raptors',
  'flames', 'eagles', 'knights', 'celtics', 'rebels', 'spartans'].map(id => `jbl_${id}.png`);
async function main() {
  assert.ok(process.argv.includes('--publish-approved-logos'));
  assert.ok(!process.env.FIREBASE_STORAGE_EMULATOR_HOST);
  const app = admin.initializeApp({projectId: 'hoops-connect-jm', credential: admin.credential.applicationDefault()});
  const bucket = app.storage().bucket('hoops-connect-jm.firebasestorage.app');
  const logos = {};
  try {
    for (const name of FILES) {
      const buffer = fs.readFileSync(path.join(ROOT, 'assets/images', name));
      assert.equal(buffer.subarray(1, 4).toString(), 'PNG');
      const sha = crypto.createHash('sha256').update(buffer).digest('hex');
      const objectPath = `public/jbl/2025-first-round/${sha.slice(0, 16)}/${name}`;
      const file = bucket.file(objectPath);
      if (!(await file.exists())[0]) await file.save(buffer, {resumable: false,
        preconditionOpts: {ifGenerationMatch: 0}, metadata: {contentType: 'image/png',
          cacheControl: 'public,max-age=31536000,immutable',
          metadata: {firebaseStorageDownloadTokens: crypto.randomUUID(), sourceSha256: sha}}});
      const [metadata] = await file.getMetadata();
      assert.equal(metadata.metadata.sourceSha256, sha);
      const token = metadata.metadata.firebaseStorageDownloadTokens;
      assert.ok(token);
      const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
      const response = await fetch(url);
      assert.equal(response.status, 200);
      assert.ok(Buffer.from(await response.arrayBuffer()).equals(buffer), 'Public artwork read-back mismatch');
      logos[name] = url;
    }
    const destination = path.join(ROOT, '.local/jbl-live-migration/logo-urls.json');
    fs.writeFileSync(destination, JSON.stringify(logos, null, 2) + '\n', {mode: 0o600});
    console.log(JSON.stringify({publishedExactSourceLogos: FILES.length, destination}));
  } finally {await app.delete();}
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
