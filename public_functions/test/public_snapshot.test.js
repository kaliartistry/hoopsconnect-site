'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {Timestamp} = require('firebase-admin/firestore');
const {buildPublicSnapshot} = require('../lib/index');

test('public snapshot exposes approved scores and strips private source fields', () => {
  const snapshot = buildPublicSnapshot({
    associationId: 'jba',
    association: {
      name: 'Jamaica Basketball Association', currentSeasonId: 'season-1',
      privateNotes: 'never public',
    },
    teams: [
      {id: 'home', data: {name: 'Home Team', repIds: ['private-user']}},
      {id: 'away', data: {name: 'Away Team'}},
    ],
    events: [{id: 'game-1', data: {
      type: 'game', seasonId: 'season-1', title: 'Home vs Away',
      startTime: Timestamp.fromDate(new Date('2026-09-10T20:00:00Z')),
      teamIds: ['home', 'away'], createdBy: 'private-user', description: 'private note',
    }}],
    gameStats: [{id: 'game-1', data: {
      status: 'approved', seasonId: 'season-1', homeTeamId: 'home', awayTeamId: 'away',
      homeTeamName: 'Home Team', awayTeamName: 'Away Team', homeScore: 82, awayScore: 79,
      submittedBy: 'private-user', approvedBy: 'private-admin', playerLines: {private: true},
    }}],
    standings: [{id: 'season-1_all', data: {
      seasonId: 'season-1', divisionId: null,
      standings: [{teamId: 'home', teamName: 'Home Team', wins: 1, losses: 0, pct: 1}],
      processedEvents: ['private-event'],
    }}],
    leaderboards: [{id: 'season-1_all_ppg', data: {
      seasonId: 'season-1', divisionId: null, category: 'ppg',
      rankings: [{playerId: 'player-1', name: 'Player One', teamName: 'Home Team', value: 20, gp: 1}],
    }}],
    generatedAt: '2026-09-10T21:00:00.000Z',
  });

  assert.equal(snapshot.schedule[0].status, 'final');
  assert.equal(snapshot.schedule[0].homeScore, 82);
  assert.equal(snapshot.standings[0].wins, 1);
  assert.equal(snapshot.leaderboards[0].rankings[0].displayName, 'Player One');
  const serialized = JSON.stringify(snapshot);
  for (const forbidden of ['privateNotes', 'repIds', 'createdBy', 'description', 'submittedBy', 'approvedBy', 'playerLines', 'processedEvents']) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('unapproved scores are never returned to guests', () => {
  const snapshot = buildPublicSnapshot({
    associationId: 'jba',
    association: {name: 'JBA', currentSeasonId: 'season-1'},
    teams: [],
    events: [{id: 'game-1', data: {
      type: 'game', seasonId: 'season-1', title: 'Game',
      startTime: Timestamp.fromDate(new Date('2026-09-10T20:00:00Z')),
    }}],
    gameStats: [{id: 'game-1', data: {
      status: 'submitted', seasonId: 'season-1', homeScore: 99, awayScore: 98,
    }}],
    standings: [],
    leaderboards: [],
  });
  assert.equal(snapshot.schedule[0].status, 'scheduled');
  assert.equal(snapshot.schedule[0].homeScore, null);
  assert.equal(snapshot.schedule[0].awayScore, null);
});
