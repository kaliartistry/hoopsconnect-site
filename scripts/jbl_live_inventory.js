#!/usr/bin/env node
'use strict';

// Read-only inventory and lossless backup. No live mutations are implemented.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const admin = require('../functions/node_modules/firebase-admin');
const projects = ['hoops-connect-jm', 'hoopsconnect-jba-staging'];

function encode(value) {
  if (value instanceof admin.firestore.Timestamp) {
    return {$type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds};
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {$type: 'geoPoint', latitude: value.latitude, longitude: value.longitude};
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return {$type: 'reference', path: value.path};
  }
  if (Buffer.isBuffer(value)) return {$type: 'bytes', value: value.toString('base64')};
  if (Array.isArray(value)) return value.map(encode);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)]));
  }
  if (typeof value === 'number' && !Number.isFinite(value)) {
    return {$type: 'number', value: String(value)};
  }
  return value;
}

async function inventory(projectId, outputRoot) {
  const app = admin.initializeApp({projectId, credential: admin.credential.applicationDefault()}, projectId);
  const db = app.firestore();
  const records = [];
  async function visit(ref) {
    const document = await ref.get();
    if (document.exists) records.push({path: ref.path, data: encode(document.data()),
      updateTime: encode(document.updateTime)});
    if (records.length > 10000) throw new Error('Inventory size exceeded safety bound.');
    for (const collection of await ref.listCollections()) {
      for (const child of await collection.listDocuments()) await visit(child);
    }
  }
  // Only the named association and its public read models. Auth/users and other
  // associations are not enumerated, changed, or copied.
  await visit(db.doc('associations/jba'));
  await visit(db.doc('publicData/jba'));
  records.sort((a, b) => a.path.localeCompare(b.path));
  const encoded = JSON.stringify({schemaVersion: 1, projectId,
    capturedAt: new Date().toISOString(), records}, null, 2) + '\n';
  const destination = path.join(outputRoot, `${projectId}.json`);
  fs.writeFileSync(destination, encoded, {mode: 0o600, flag: 'wx'});
  const saved = fs.readFileSync(destination, 'utf8');
  if (saved !== encoded) throw new Error('Backup read-back mismatch.');
  const counts = {};
  for (const row of records) {
    const collection = row.path.split('/').slice(0, -1).join('/');
    counts[collection] = (counts[collection] || 0) + 1;
  }
  console.log(JSON.stringify({projectId, backup: destination, records: records.length,
    sha256: crypto.createHash('sha256').update(saved).digest('hex'), counts}));
  await app.delete();
}

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Unset emulator routing before live inventory.');
  const root = path.resolve(__dirname, '../.local/jbl-live-migration');
  fs.mkdirSync(root, {recursive: true, mode: 0o700});
  const output = fs.mkdtempSync(path.join(root, 'backup-'));
  for (const project of projects) await inventory(project, output);
}

if (require.main === module) main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
module.exports = {encode};
