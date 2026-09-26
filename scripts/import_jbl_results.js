#!/usr/bin/env node
'use strict';
// Append-only historical results. No inferred player totals or standings writes.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const {encode} = require('./jbl_live_inventory');
const {decode, projectionData, COLLECTIONS} = require('./lib/jbl_live_runtime');
const {digest, DIVISION} = require('./lib/jbl_live_plan');
const {buildApprovedLegacySnapshot} = require('../public_functions/lib/legacy_live');

function buildPlan(backup, input) {
  const original = new Map(backup.records.map(r => [r.path, r.data]));
  const association = original.get('associations/jba');
  assert.ok(association.leagueCatalogV1.leagues.some(l => l.leagueId === 'jbl' && l.historicalStatistics));
  const names = new Map(backup.records.filter(r => r.path.startsWith('associations/jba/teams/'))
    .map(r => [r.path.split('/').pop(), r.data.name]));
  const operations = [];
  for (const game of input.games) {
    const [home, away] = game.sides;
    assert.ok(names.has(home.teamId) && names.has(away.teamId));
    assert.notEqual(home.teamId, away.teamId);
    const timestamp = {$type: 'timestamp', seconds: Date.parse(game.date + 'T17:00:00Z') / 1000, nanoseconds: 0};
    const common = {seasonId: association.currentSeasonId, divisionId: DIVISION,
      historicalImport: 'kurt-results-20260917', sourceReports: game.sources,
      dateOnly: true, reportingDate: game.date};
    const recap = ['Recorded final result. Game time was not supplied.',
      'Selected performers from the supplied report (not a complete box score):',
      ...game.sides.flatMap(side => [names.get(side.teamId), ...side.players.map(p =>
        p.name + ': ' + [['points', 'PTS'], ['rebounds', 'REB'], ['assists', 'AST'], ['steals', 'STL'], ['blocks', 'BLK']]
          .filter(([key]) => p[key] !== null).map(([key, label]) => `${p[key]} ${label}`).join(' · '))]),
      'Whole-team rebounds, assists, steals and blocks were not supplied. Player season totals are maintained separately.',
      ...(game.periodsVerified ? [] : ['The supplied quarter totals do not reconcile; the breakdown is withheld.'])].join('\n');
    const quarterScores = side => game.periodsVerified ? Object.fromEntries([
      ...side.quarters.map((v, i) => [String(i + 1), v]),
      ...(game.sides.some(s => s.overtime !== null) ? [['5', side.overtime || 0]] : []),
    ]) : {};
    const event = {...common, title: `${names.get(home.teamId)} vs ${names.get(away.teamId)}`,
      type: 'game', startTime: timestamp, endTime: null, location: null,
      teamIds: [home.teamId, away.teamId], createdBy: 'historical-import',
      statsStatus: 'approved', status: 'scheduled', description: recap};
    const stats = {...common, eventId: game.gameId, status: 'approved',
      homeTeamId: home.teamId, awayTeamId: away.teamId,
      homeTeamName: names.get(home.teamId), awayTeamName: names.get(away.teamId),
      homeScore: home.score, awayScore: away.score, entryMode: 'postGame',
      playerLines: {}, publicPlayerLines: [], publicRecap: recap,
      homeQuarterScores: quarterScores(home), awayQuarterScores: quarterScores(away)};
    for (const [collection, data] of [['events', event], ['gameStats', stats]]) {
      const target = `associations/jba/${collection}/${game.gameId}`;
      assert.ok(!original.has(target), `Refusing to overwrite ${target}`);
      operations.push({path: target, data});
    }
  }
  assert.ok(operations.length > 0 && operations.length < 400);
  const after = new Map(original);
  for (const op of operations) after.set(op.path, op.data);
  const sources = Object.fromEntries(COLLECTIONS.map(name => [name, [...after]
    .filter(([p]) => p.startsWith(`associations/jba/${name}/`) && p.split('/').length === 4)
    .map(([p, data]) => ({id: p.split('/').pop(), data: projectionData(data)}))]));
  const snapshot = buildApprovedLegacySnapshot(projectionData(association), sources);
  assert.equal(snapshot.schedule.filter(g => input.games.some(s => s.gameId === g.gameId)).length, input.games.length);
  const beforeSnapshot = original.get('publicData/jba/snapshots/current');
  assert.deepEqual(snapshot.standings, beforeSnapshot.standings);
  assert.deepEqual(snapshot.leaderboards, beforeSnapshot.leaderboards);
  return {projectId: backup.projectId, operations, snapshot, sourceDigest: digest(input)};
}

async function main() {
  const [backupPath, inputPath, approvedDigest] = process.argv.slice(2);
  const backup = JSON.parse(fs.readFileSync(backupPath));
  assert.ok(['hoops-connect-jm', 'hoopsconnect-jba-staging'].includes(backup.projectId));
  assert.ok(!process.env.FIRESTORE_EMULATOR_HOST);
  const input = JSON.parse(fs.readFileSync(inputPath));
  const plan = buildPlan(backup, input);
  // Generated-at changes must not change approval for otherwise identical source writes.
  const hash = digest({projectId: plan.projectId, operations: plan.operations, sourceDigest: plan.sourceDigest});
  console.log(JSON.stringify({projectId: plan.projectId, digest: hash, newGames: input.games.length,
    writes: plan.operations.length + 1, snapshotBytes: Buffer.byteLength(JSON.stringify(plan.snapshot))}));
  if (!approvedDigest) return;
  assert.equal(hash, approvedDigest);
  const receipt = path.join(path.dirname(backupPath), `${backup.projectId}-game-results-applied.json`);
  assert.ok(!fs.existsSync(receipt));
  fs.writeFileSync(receipt.replace('-applied', '-plan'), JSON.stringify(plan, null, 2), {mode: 0o600, flag: 'wx'});
  const app = admin.initializeApp({projectId: plan.projectId, credential: admin.credential.applicationDefault()});
  const db = app.firestore();
  await db.runTransaction(async tx => {
    const association = await tx.get(db.doc('associations/jba'));
    assert.equal(digest(encode(association.data())), digest(backup.records.find(r => r.path === 'associations/jba').data));
    for (const collection of COLLECTIONS) {
      const target = `associations/jba/${collection}`;
      const live = await tx.get(db.collection(target));
      const expected = backup.records.filter(r => r.path.startsWith(target + '/') && r.path.split('/').length === 4);
      assert.equal(live.size, expected.length, `Concurrent ${collection} change`);
      const expectedMap = new Map(expected.map(r => [r.path, r.data]));
      for (const doc of live.docs) assert.equal(digest(encode(doc.data())), digest(expectedMap.get(doc.ref.path)));
    }
    for (const op of plan.operations) tx.create(db.doc(op.path), decode(op.data, db));
    tx.set(db.doc('publicData/jba/snapshots/current'), plan.snapshot);
  });
  const current = (await db.doc('publicData/jba/snapshots/current').get()).data();
  assert.equal(current.schedule.filter(g => input.games.some(s => s.gameId === g.gameId)).length, input.games.length);
  fs.writeFileSync(receipt, JSON.stringify({digest: hash, newGames: input.games.length, appliedAt: new Date().toISOString(),
    snapshotVersion: current.snapshotVersion}, null, 2), {mode: 0o600, flag: 'wx'});
  console.log('Created and verified recorded results; no standings or player totals changed.');
  await app.delete();
}
if (require.main === module) main().catch(e => {console.error(e); process.exitCode = 1;});
module.exports = {buildPlan};
