#!/usr/bin/env node
'use strict';
// Default is a local dry run. Live application requires both a reviewed plan
// digest and the deployed, fail-closed compatibility publisher. No Auth writes.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const {buildPlan, digest} = require('./lib/jbl_live_plan');
const {decode, projectPlan} = require('./lib/jbl_live_runtime');
const {encode} = require('./jbl_live_inventory');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const arg = name => args[args.indexOf(name) + 1];

async function main() {
  assert.ok(args.includes('--backup') && args.includes('--logos'));
  assert.ok(!process.env.FIRESTORE_EMULATOR_HOST, 'Live migration must not use emulator routing');
  const backupPath = path.resolve(arg('--backup'));
  assert.ok(backupPath.startsWith(path.join(root, '.local/jbl-live-migration/')));
  const backup = JSON.parse(fs.readFileSync(backupPath));
  const source = JSON.parse(cp.execFileSync(path.join(root, '.local/jbl-import-20260917/venv/bin/python'), [
    path.join(root, 'scripts/extract_jbl_first_round.py'),
    path.join(root, '.local/jbl-import-20260917/source/NBL total stats1ist round (1).xls'),
  ], {encoding: 'utf8', maxBuffer: 4e6}));
  const logos = JSON.parse(fs.readFileSync(arg('--logos')));
  const plan = buildPlan(backup, source, logos);
  const planDigest = digest(plan);
  const projected = projectPlan(backup, plan);
  const summary = {projectId: plan.projectId, planDigest, writes: plan.operations.length + 2,
    counts: plan.counts, snapshotBytes: Buffer.byteLength(JSON.stringify(projected.snapshot)),
    teams: 10, playerRows: 188, sourcePoints: 5555, sourceSha256: source.source.sha256};
  console.log(JSON.stringify(summary));
  if (!args.includes('--apply-plan')) return;
  assert.equal(arg('--apply-plan'), planDigest, 'Plan changed since review');
  // Inspect the actual deployed entrypoint and require our exact source marker.
  const fn = JSON.parse(cp.execFileSync('gcloud', ['functions', 'describe', 'onPublicLeagueSourceWritten',
    '--gen2', '--region=us-central1', `--project=${plan.projectId}`, '--format=json'], {encoding: 'utf8'}));
  assert.equal(fn.state, 'ACTIVE');
  assert.equal(fn.labels?.['jbl-compatibility'], 'v1-20260917');
  const app = admin.initializeApp({projectId: plan.projectId, credential: admin.credential.applicationDefault()}, 'jbl-migration');
  const db = app.firestore();
  try {
    const {snapshot} = projectPlan(backup, plan, db);
    const controlRef = db.doc('publicSnapshotControls/jba');
    const publicRef = db.doc('publicData/jba/snapshots/current');
    const original = new Map(backup.records.map(row => [row.path, row]));
    const paths = new Set([...original.keys(), ...plan.operations.map(row => row.path)]);
    // Query every existing collection as well as the association's direct
    // collections, so concurrent additions cannot fall outside the backup.
    const collectionPaths = new Set(backup.records.filter(row => row.path.startsWith('associations/jba/'))
      .map(row => row.path.split('/').slice(0, -1).join('/')));
    for (const collection of await db.doc('associations/jba').listCollections()) collectionPaths.add(collection.path);
    const evidencePath = path.join(path.dirname(backupPath), `${plan.projectId}-applied.json`);
    assert.ok(!fs.existsSync(evidencePath), 'Application already recorded; inspect instead of replaying');
    await db.runTransaction(async tx => {
      const control = await tx.get(controlRef);
      assert.equal(control.exists, false, 'Unexpected existing control; stop for reconciliation');
      for (const collectionPath of collectionPaths) {
        const live = await tx.get(db.collection(collectionPath).limit(1001));
        assert.ok(live.size <= 1000);
        const expected = [...original.values()].filter(row => row.path.split('/').slice(0, -1).join('/') === collectionPath);
        assert.equal(live.size, expected.length, `Collection changed since backup: ${collectionPath}`);
        for (const doc of live.docs) {
          assert.deepEqual(encode(doc.data()), original.get(doc.ref.path)?.data, `Source changed: ${doc.ref.path}`);
        }
      }
      // Explicit reads also prove every newly allocated ID is still absent.
      const documents = await tx.getAll(...[...paths].map(p => db.doc(p)));
      for (const doc of documents) {
        const saved = original.get(doc.ref.path);
        assert.equal(doc.exists, Boolean(saved), `Existence changed: ${doc.ref.path}`);
        if (saved) assert.deepEqual(encode(doc.data()), saved.data, `Source changed: ${doc.ref.path}`);
      }
      for (const operation of plan.operations) {
        const ref = db.doc(operation.path);
        operation.action === 'delete' ? tx.delete(ref) : tx.set(ref, decode(operation.data, db));
      }
      tx.set(publicRef, snapshot);
      tx.create(controlRef, {schemaVersion: 1, associationId: 'jba', enabled: true,
        maintenance: false, contractVersion: 'legacy-public-snapshot-v1.1',
        migrationPlanDigest: planDigest, sourceWorkbookSha256: source.source.sha256,
        ignoreEventsThrough: admin.firestore.FieldValue.serverTimestamp()});
    }, {maxAttempts: 2});
    const result = await publicRef.get();
    assert.equal(result.data().snapshotVersion, snapshot.snapshotVersion);
    fs.writeFileSync(evidencePath, JSON.stringify({...summary, appliedAt: new Date().toISOString(),
      snapshotVersion: snapshot.snapshotVersion, plan}, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
    console.log(JSON.stringify({applied: true, projectId: plan.projectId, snapshotVersion: snapshot.snapshotVersion,
      evidencePath, backupPath}));
  } finally { await app.delete(); }
}
main().catch(error => {console.error(error.stack); process.exitCode = 1;});
