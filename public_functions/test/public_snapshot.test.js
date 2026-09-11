'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {Timestamp} = require('firebase-admin/firestore');
const {buildPublicSnapshot} = require('../lib/index');

function fixture(overrides = {}) {
  return {
    associationId: 'jba',
    association: {
      name: 'Jamaica Basketball Association', shortName: 'JBA',
      currentSeasonId: 'season-1', publicLeagueState: 'published', publicPrivacyEpoch: 7,
      standingsPolicyLabel: 'Winning percentage; unresolved ties remain tied',
      privateNotes: 'never public',
    },
    season: {id: 'season-1', data: {name: '2026 NBL'}},
    divisions: [{id: 'premier', data: {name: 'Premier', seasonId: 'season-1', managerUid: 'private'}}],
    teams: [
      {id: 'home', data: {name: 'Home Team', divisionId: 'premier', repIds: ['private-user']}},
      {id: 'away', data: {name: 'Away Team', divisionId: 'premier'}},
    ],
    events: [{id: 'game-1', data: {
      type: 'game', seasonId: 'season-1', divisionId: 'premier', title: 'Private Admin Title',
      startTime: Timestamp.fromDate(new Date('2026-09-10T20:00:00Z')),
      teamIds: ['home', 'away'], createdBy: 'private-user', description: 'private note',
    }}],
    gameStats: [{id: 'game-1', data: {
      status: 'approved', seasonId: 'season-1', homeTeamId: 'home', awayTeamId: 'away',
      homeTeamName: 'Private Home Alias', awayTeamName: 'Private Away Alias', homeScore: 82, awayScore: 79,
      homeQuarterScores: {'1': 20, '2': 22}, awayQuarterScores: {'1': 18, '2': 21},
      submittedBy: 'private-user', approvedBy: 'private-admin',
      playerLines: {privatePlayerId: {name: 'Private Player'}},
      publicPlayerLines: [{
        playerId: 'player-1', publicDisplayName: 'Player One', teamId: 'home',
        points: 20, twoPointMade: 6, twoPointAttempted: 10, turnovers: 2,
        email: 'never@example.com', school: 'Never Public School',
      }],
      publicRecap: 'Home Team won a close game.', internalRecap: 'private recap',
    }}],
    standings: [{id: 'season-1_premier', data: {
      seasonId: 'season-1', divisionId: 'premier',
      standings: [{
        teamId: 'home', teamName: 'Private Standings Alias', wins: 1, losses: 0, pct: 1,
        rank: 1, rankStatus: 'ranked',
      }],
      processedEvents: ['private-event'],
    }}],
    leaderboards: [
      {id: 'season-1_premier_apg', data: {
        seasonId: 'season-1', divisionId: 'premier', category: 'apg',
        rankings: [{
          playerId: 'player-1', name: 'Private Alias', publicDisplayName: 'Player One',
          teamId: 'home', teamName: 'Private Rankings Alias', value: 4, gp: 1,
        }],
      }},
      {id: 'season-1_premier_ppg', data: {
        seasonId: 'season-1', divisionId: 'premier', category: 'ppg',
        rankings: [{
          playerId: 'player-1', name: 'Private Alias', publicDisplayName: 'Player One',
          teamId: 'home', teamName: 'Private Rankings Alias', value: 20, gp: 1,
        }],
      }},
    ],
    generatedAt: '2026-09-10T21:00:00.000Z',
    ...overrides,
  };
}

test('public snapshot exposes one versioned approved result and strips private source fields', () => {
  const snapshot = buildPublicSnapshot({
    ...fixture(),
  });

  assert.match(snapshot.snapshotVersion, /^[a-f0-9]{64}$/);
  assert.equal(snapshot.publication.snapshotVersion, snapshot.snapshotVersion);
  assert.equal(snapshot.publication.verificationStatus, 'legacyApproved');
  assert.equal(snapshot.publication.privacyEpoch, 7);
  assert.equal(snapshot.season.name, '2026 NBL');
  assert.equal(snapshot.divisions[0].name, 'Premier');
  assert.equal(snapshot.schedule[0].status, 'final');
  assert.equal(snapshot.schedule[0].title, 'Home Team vs Away Team');
  assert.equal(snapshot.schedule[0].homeScore, 82);
  assert.match(snapshot.schedule[0].resultVersion, /^[a-f0-9]{64}$/);
  assert.equal(snapshot.schedule[0].playerLines[0].displayName, 'Player One');
  assert.equal(snapshot.schedule[0].playerLines[0].turnovers, 2);
  assert.equal(snapshot.schedule[0].playerLines[0].threePointMade, null);
  assert.equal(snapshot.standings[0].wins, 1);
  assert.equal(snapshot.standings[0].divisionId, 'premier');
  assert.equal(snapshot.leaderboards[0].rankings[0].displayName, 'Player One');
  assert.deepEqual(snapshot.leaderboards.map((entry) => entry.category), ['ppg', 'apg']);
  const serialized = JSON.stringify(snapshot);
  for (const forbidden of [
    'privateNotes', 'repIds', 'managerUid', 'createdBy', 'description',
    'submittedBy', 'approvedBy', 'privatePlayerId', 'Private Player',
    'Private Alias', 'never@example.com', 'Never Public School',
    'internalRecap', 'processedEvents',
    'Private Admin Title', 'Private Home Alias', 'Private Away Alias',
    'Private Standings Alias', 'Private Rankings Alias',
  ]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('unapproved scores are never returned to guests', () => {
  const snapshot = buildPublicSnapshot({
    associationId: 'jba',
    association: {name: 'JBA', currentSeasonId: 'season-1', publicLeagueState: 'published'},
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
  assert.equal(snapshot.schedule[0].resultVersion, null);
});

test('unreviewed player names never cross the public projection boundary', () => {
  const base = fixture();
  base.gameStats[0].data.publicPlayerLines = [{
    playerId: 'private-player', teamId: 'home', name: 'Private Player', points: 99,
  }];
  base.leaderboards[0].data.rankings = [{
    playerId: 'private-player', name: 'Private Player', teamName: 'Home Team', value: 99, gp: 1,
  }];
  base.leaderboards[1].data.rankings = base.leaderboards[0].data.rankings;

  const snapshot = buildPublicSnapshot(base);

  assert.deepEqual(snapshot.schedule[0].playerLines, []);
  assert.deepEqual(snapshot.leaderboards[0].rankings, []);
  assert.equal(JSON.stringify(snapshot).includes('Private Player'), false);
});

test('player identity stays suppressed without a public privacy epoch', () => {
  const missingPolicy = fixture();
  delete missingPolicy.association.publicPrivacyEpoch;

  const snapshot = buildPublicSnapshot(missingPolicy);

  assert.equal(snapshot.privacyEpoch, null);
  assert.deepEqual(snapshot.schedule[0].playerLines, []);
  assert.equal(
    snapshot.leaderboards.every((board) => board.rankings.length === 0),
    true,
  );
  assert.equal(JSON.stringify(snapshot).includes('Player One'), false);
});

test('snapshot fingerprint is stable across rebuild time and changes with published content', () => {
  const first = buildPublicSnapshot(fixture({generatedAt: '2026-09-10T21:00:00.000Z'}));
  const replay = buildPublicSnapshot(fixture({generatedAt: '2026-09-11T21:00:00.000Z'}));
  assert.equal(first.snapshotVersion, replay.snapshotVersion);
  assert.equal(first.schedule[0].resultVersion, replay.schedule[0].resultVersion);

  const changed = fixture();
  changed.gameStats[0].data.homeScore = 83;
  const corrected = buildPublicSnapshot(changed);
  assert.notEqual(first.snapshotVersion, corrected.snapshotVersion);
  assert.notEqual(first.schedule[0].resultVersion, corrected.schedule[0].resultVersion);
});

test('division and season scope exclude other-season public candidates', () => {
  const scoped = fixture();
  scoped.divisions.push({id: 'archived', data: {name: 'Other Season Division', seasonId: 'season-2'}});
  scoped.teams.push({id: 'other-team', data: {name: 'Other Season Team', seasonId: 'season-2'}});
  scoped.events.push({id: 'other-game', data: {
    type: 'game', seasonId: 'season-2', title: 'Other Season Game',
    startTime: Timestamp.fromDate(new Date('2025-09-10T20:00:00Z')),
    teamIds: ['other-team', 'away'],
  }});
  scoped.standings.push({id: 'season-2', data: {
    seasonId: 'season-2', standings: [{teamId: 'other-team', wins: 9, losses: 0}],
  }});
  scoped.leaderboards.push({id: 'season-2-ppg', data: {
    seasonId: 'season-2', category: 'ppg', rankings: [{
      playerId: 'other-player', publicDisplayName: 'Other Season Player',
      teamId: 'other-team', value: 99, gp: 9,
    }],
  }});

  const snapshot = buildPublicSnapshot(scoped);
  const serialized = JSON.stringify(snapshot);

  assert.equal(serialized.includes('Other Season'), false);
  assert.equal(snapshot.schedule.length, 1);
  assert.equal(snapshot.divisions.length, 1);
  assert.equal(snapshot.teams.length, 2);
});

test('retracted snapshots retain scope metadata but no stale public rows', () => {
  const retracted = fixture();
  retracted.association = {...retracted.association, publicLeagueState: 'retracted'};

  const snapshot = buildPublicSnapshot(retracted);

  assert.equal(snapshot.published, false);
  assert.equal(snapshot.publication.state, 'retracted');
  assert.equal(snapshot.season.name, '2026 NBL');
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.teams, []);
  assert.deepEqual(snapshot.standings, []);
  assert.deepEqual(snapshot.leaderboards, []);
});

test('unknown historical values remain null instead of becoming zero', () => {
  const sparse = fixture();
  delete sparse.standings[0].data.standings[0].wins;
  delete sparse.standings[0].data.standings[0].pointsFor;
  delete sparse.standings[0].data.standings[0].rank;
  delete sparse.leaderboards[0].data.rankings[0].value;
  delete sparse.leaderboards[0].data.rankings[0].gp;

  const snapshot = buildPublicSnapshot(sparse);

  assert.equal(snapshot.standings[0].wins, null);
  assert.equal(snapshot.standings[0].pointsFor, null);
  assert.equal(snapshot.standings[0].rank, null);
  assert.equal(snapshot.standings[0].rankStatus, 'unresolved');
  assert.equal(snapshot.leaderboards[1].rankings[0].value, null);
  assert.equal(snapshot.leaderboards[1].rankings[0].gamesPlayed, null);
});

test('an unrecognized publication state fails closed', () => {
  const invalid = fixture();
  invalid.association = {...invalid.association, publicLeagueState: 'publsihed'};

  const snapshot = buildPublicSnapshot(invalid);

  assert.equal(snapshot.publication.state, 'unavailable');
  assert.equal(snapshot.published, false);
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.leaderboards, []);
});

test('a missing publication state fails closed', () => {
  const missing = fixture();
  delete missing.association.publicLeagueState;

  const snapshot = buildPublicSnapshot(missing);

  assert.equal(snapshot.publication.state, 'unavailable');
  assert.equal(snapshot.published, false);
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.leaderboards, []);
});
