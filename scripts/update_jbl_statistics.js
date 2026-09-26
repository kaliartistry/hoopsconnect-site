#!/usr/bin/env node
'use strict';
// Narrow, backed-up enrichment. Does not delete records, create game results,
// infer wins/losses, change sponsors or reuse the destructive NBL migration.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const {encode} = require('./jbl_live_inventory');
const {decode, projectionData, COLLECTIONS} = require('./lib/jbl_live_runtime');
const {digest, DIVISION} = require('./lib/jbl_live_plan');
const {buildApprovedLegacySnapshot} = require('../public_functions/lib/legacy_live');

// Published April 15, 2025. Keep this date separate from April 10 player totals.
// These are competition points, not scored baskets, wins or official tie-breaks.
const REPORTED_POINTS = {
  'st-georges-slayers': 16, 'upper-room-eagles': 16, 'urban-knights': 15,
  'portmore-flames': 15, 'uwi-running-rebels': 15, 'mbbgc-warriors': 14,
  'rae-town-raptors': 14, 'spanish-town-spartans': 11, 'central-celtics': 10,
  'tivoli-wizards': 9,
};
const SOURCE_URL = 'https://jamaica-gleaner.com/article/sports/20250415/slayers-eagles-fight-mid-season-title';

function buildEnrichment(backup, source) {
  const original = new Map(backup.records.map(row => [row.path, row]));
  const association = structuredClone(original.get('associations/jba').data);
  const league = association.leagueCatalogV1.leagues.find(row => row.leagueId === 'jbl');
  assert.ok(league?.historicalStatistics);
  assert.deepEqual([...source.teams.map(t => t.teamId)].sort(), Object.keys(REPORTED_POINTS).sort());
  assert.equal(source.players.length, 188);
  assert.equal(source.totals.points, 5555);
  const byPlayer = new Map(source.players.map(player => [player.playerId, player]));
  const operations = [];
  const put = (record, data) => {
    if (digest(data) !== digest(record.data)) operations.push({path: record.path, before: record, data});
  };
  league.seasonLabel = '2025 Season';
  league.description = `Player statistics as of ${source.asOf}`;
  league.reportedStandings = Object.entries(REPORTED_POINTS).map(([teamId, leaguePoints]) => ({teamId, leaguePoints}));
  league.standingsAsOf = '2025-04-15';
  league.standingsSourceUrl = SOURCE_URL;
  put(original.get('associations/jba'), association);
  for (const record of backup.records) {
    if (!record.path.startsWith('associations/jba/')) continue;
    const data = structuredClone(record.data);
    if (data.divisionId !== DIVISION && record.path !== `associations/jba/divisions/${DIVISION}`) continue;
    if (record.path === `associations/jba/divisions/${DIVISION}`) data.name = '2025 Season';
    if (data.statisticsPeriod) data.statisticsPeriod = '2025 Season';
    if (data.qualificationLabel) data.qualificationLabel = '2025 Season · Per game · All recorded players';
    if (record.path.includes('/leaderboard/') && data.category === 'ppg') {
      data.rankings = data.rankings.map(row => {
        const player = byPlayer.get(row.playerId);
        assert.ok(player, 'Unexpected JBL leaderboard player');
        return {...row, shootingMade: {twoMade: player.twoMade, threeMade: player.threeMade, ftMade: player.ftMade}};
      });
    }
    put(record, data);
  }
  return {projectId: backup.projectId, sourceSha256: source.source.sha256, operations};
}

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Live project required');
  const [backupPath, applyDigest] = process.argv.slice(2);
  const backup = JSON.parse(fs.readFileSync(backupPath));
  assert.ok(['hoops-connect-jm', 'hoopsconnect-jba-staging'].includes(backup.projectId));
  const source = JSON.parse(cp.execFileSync('.local/jbl-import-20260917/venv/bin/python', [
    'scripts/extract_jbl_first_round.py', '.local/jbl-import-20260917/source/NBL total stats1ist round (1).xls'], {encoding: 'utf8'}));
  const plan = buildEnrichment(backup, source);
  const planDigest = digest(plan);
  const after = new Map(backup.records.map(row => [row.path, row.data]));
  for (const op of plan.operations) after.set(op.path, op.data);
  const sources = Object.fromEntries(COLLECTIONS.map(name => [name, [...after]
    .filter(([p]) => p.startsWith(`associations/jba/${name}/`) && p.split('/').length === 4)
    .map(([p, data]) => ({id: p.split('/').pop(), data: projectionData(data)}))]));
  const snapshot = buildApprovedLegacySnapshot(projectionData(after.get('associations/jba')), sources);
  const publicLeague = snapshot.leagues.find(row => row.leagueId === 'jbl');
  assert.equal(publicLeague.reportedStandings.length, 10);
  assert.equal(snapshot.leaderboards.find(b => b.divisionId === DIVISION && b.category === 'ppg').rankings
    .reduce((sum, p) => sum + p.shootingMade.twoMade, 0), 1805);
  assert.ok(JSON.stringify(snapshot).length < 850000);
  console.log(JSON.stringify({projectId: backup.projectId, planDigest, writes: plan.operations.length + 1,
    standings: publicLeague.reportedStandings, seasonLabel: publicLeague.seasonLabel}));
  if (!applyDigest) return;
  assert.equal(applyDigest, planDigest, 'Plan changed since review');
  const receiptPath = path.join(path.dirname(backupPath), `${backup.projectId}-statistics-applied.json`);
  assert.ok(!fs.existsSync(receiptPath), 'Already applied');
  fs.writeFileSync(receiptPath.replace('-applied', '-plan'), JSON.stringify(plan, null, 2), {mode: 0o600, flag: 'wx'});
  const app = admin.initializeApp({projectId: backup.projectId, credential: admin.credential.applicationDefault()});
  const db = app.firestore();
  await db.runTransaction(async tx => {
    // Validate every source used in the public projection, not only changed rows.
    const refs = COLLECTIONS.map(name => db.collection(`associations/jba/${name}`));
    const reads = await Promise.all(refs.map(ref => tx.get(ref)));
    for (let i = 0; i < refs.length; i++) {
      const expected = backup.records.filter(r => r.path.startsWith(refs[i].path + '/') && r.path.split('/').length === 4);
      assert.equal(reads[i].size, expected.length, 'Source collection changed');
      for (const doc of reads[i].docs) assert.equal(digest(encode(doc.data())), digest(after.has(doc.ref.path) ?
        backup.records.find(r => r.path === doc.ref.path).data : null), 'Source data changed');
    }
    const originals = await Promise.all(plan.operations.map(op => tx.get(db.doc(op.path))));
    originals.forEach((doc, i) => assert.equal(digest(encode(doc.data())), digest(plan.operations[i].before.data), 'Write target changed'));
    for (const op of plan.operations) tx.set(db.doc(op.path), decode(op.data, db));
    tx.set(db.doc('publicData/jba/snapshots/current'), snapshot);
  });
  const current = (await db.doc('publicData/jba/snapshots/current').get()).data();
  assert.equal(current.leagues.find(l => l.leagueId === 'jbl').reportedStandings.length, 10);
  fs.writeFileSync(receiptPath, JSON.stringify({planDigest, appliedAt: new Date().toISOString(), snapshotVersion: current.snapshotVersion}, null, 2), {mode: 0o600, flag: 'wx'});
  console.log('Applied and verified ' + backup.projectId);
  await app.delete();
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {buildEnrichment, REPORTED_POINTS};
