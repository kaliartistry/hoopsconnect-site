'use strict';
const assert = require('node:assert/strict');
const admin = require('../../functions/node_modules/firebase-admin');
const {buildApprovedLegacySnapshot} = require('../../public_functions/lib/legacy_live');
const {DIVISION} = require('./jbl_live_plan');
const COLLECTIONS = ['seasons', 'divisions', 'events', 'gameStats', 'standings', 'leaderboard', 'teams', 'posts'];

// Feed the pure projection JSON/ISO dates. Separate installed Admin SDK copies
// have different Timestamp constructors even though their data is identical.
function projectionData(value) {
  if (Array.isArray(value)) return value.map(projectionData);
  if (value && typeof value === 'object') {
    if (value.$type === 'timestamp') return new Date(value.seconds * 1000 + value.nanoseconds / 1e6).toISOString();
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, projectionData(item)]));
  }
  return value;
}

function decode(value, db) {
  if (Array.isArray(value)) return value.map(item => decode(item, db));
  if (value && typeof value === 'object') {
    if (value.$type === 'timestamp') return new admin.firestore.Timestamp(value.seconds, value.nanoseconds);
    if (value.$type === 'geoPoint') return new admin.firestore.GeoPoint(value.latitude, value.longitude);
    if (value.$type === 'reference') return db.doc(value.path);
    if (value.$type === 'bytes') return Buffer.from(value.value, 'base64');
    if (value.$type === 'number') return Number(value.value);
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, decode(item, db)]));
  }
  return value;
}

function projectPlan(backup, plan, db) {
  const after = new Map(backup.records.map(row => [row.path, row.data]));
  for (const op of plan.operations) op.action === 'delete' ? after.delete(op.path) : after.set(op.path, op.data);
  const sources = Object.fromEntries(COLLECTIONS.map(name => [name, [...after]
    .filter(([path]) => path.startsWith(`associations/jba/${name}/`) && path.split('/').length === 4)
    .map(([path, data]) => ({id: path.split('/').pop(), data: projectionData(data)}))]));
  const snapshot = buildApprovedLegacySnapshot(projectionData(after.get('associations/jba')), sources);
  assert.equal(snapshot.published, true);
  assert.equal(snapshot.leagues.filter(row => row.leagueId === 'jbl').length, 1);
  assert.equal(snapshot.leagues.some(row => row.leagueId === 'nbl'), false);
  assert.equal(snapshot.teams.filter(row => row.divisionId === DIVISION).length, 10);
  assert.equal(snapshot.schedule.some(row => plan.oldGames.includes(row.gameId)), false);
  assert.equal(snapshot.standings.some(row => plan.oldDivisions.includes(row.divisionId)), false);
  const boards = snapshot.leaderboards.filter(row => row.divisionId === DIVISION);
  assert.equal(boards.length, 5);
  for (const board of boards) assert.equal(board.rankings.length, 188);
  assert.equal(boards.find(row => row.category === 'ppg').rankings.reduce((sum, row) => sum + row.cumulativeTotal, 0), 5555);
  assert.equal(boards.flatMap(row => row.rankings).some(row => !Number.isFinite(row.value)), false);
  assert.ok(plan.operations.length + 2 <= 500, 'Require one atomic write, never partial deletion');
  return {after, snapshot};
}
module.exports = {decode, projectPlan, projectionData, COLLECTIONS};
