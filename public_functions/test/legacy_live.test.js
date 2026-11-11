'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {canPublishLegacy} = require('../lib/legacy_live');
test('live compatibility publisher is closed without exact server approval', () => {
  const valid = {schemaVersion: 1, enabled: true, maintenance: false,
    associationId: 'jba', contractVersion: 'legacy-public-snapshot-v1.1'};
  assert.equal(canPublishLegacy(valid), true);
  for (const invalid of [undefined, {}, {...valid, maintenance: true},
    {...valid, enabled: false}, {...valid, associationId: 'other'},
    {...valid, contractVersion: 'public-release-v2'}]) {
    assert.equal(canPublishLegacy(invalid), false);
  }
});

test('approved compatibility snapshot carries the next sponsor without replacing the current sponsor', () => {
  const {buildApprovedLegacySnapshot} = require('../lib/legacy_live');
  const branding = {
    sponsor: {enabled: true, name: 'Current sponsor'},
    scheduledSponsor: {
      startsOn: '2026-12-01',
      sponsor: {enabled: true, name: 'Next sponsor', internalContact: 'private'},
    },
  };
  const snapshot = buildApprovedLegacySnapshot({
    name: 'Jamaica Basketball Association',
    currentSeasonId: '2026-27',
    leagueCatalogV1: {
      schemaVersion: 1,
      leagues: [{leagueId: 'jbl', name: 'Jamaica Basketball League', divisionIds: ['jbl-a'], branding}],
    },
  }, {
    seasons: [{id: '2026-27', data: {name: '2026-27'}}],
    divisions: [{id: 'jbl-a', data: {name: 'First Round', seasonId: '2026-27'}}],
    events: [], gameStats: [], teams: [], posts: [], standings: [], leaderboard: [],
  });
  const jbl = snapshot.leagues.find(league => league.leagueId === 'jbl');
  assert.equal(jbl.branding.sponsor.name, 'Current sponsor');
  assert.equal(jbl.branding.scheduledSponsor.startsOn, '2026-12-01');
  assert.equal(jbl.branding.scheduledSponsor.sponsor.name, 'Next sponsor');
  assert.equal('internalContact' in jbl.branding.scheduledSponsor.sponsor, false);
});

test('approved publication can exclude seeded records and their sponsor placements', () => {
  const {buildApprovedLegacySnapshot} = require('../lib/legacy_live');
  const seasonId = 'active-season';
  const association = {
    currentSeasonId: seasonId,
    publicLeagueState: 'published',
    leagueCatalogV1: {
      schemaVersion: 1,
      leagues: [
        {leagueId: 'jbl', name: 'Jamaica Basketball League', divisionIds: ['jbl-a', 'demo-extra']},
        {leagueId: 'demo', name: 'Demo League', divisionIds: ['demo-a'],
          branding: {sponsor: {enabled: true, name: 'Demo sponsor'}}},
      ],
    },
  };
  const fixture = {seasonId, divisionId: 'demo-a', qaFixtureVersion: 5};
  const startTime = '2026-11-01T19:00:00Z';
  const sources = {
    seasons: [{id: seasonId, data: {name: '2026 Season', qaFixtureVersion: 5}}],
    divisions: [
      {id: 'jbl-a', data: {name: 'JBL', seasonId}},
      {id: 'demo-a', data: {...fixture, name: 'Demo'}},
      {id: 'demo-extra', data: {...fixture, name: 'Demo extra'}},
    ],
    teams: [
      {id: 'jbl-team', data: {seasonId, divisionId: 'jbl-a', name: 'JBL club'}},
      {id: 'demo-team', data: {...fixture, name: 'Demo club'}},
    ],
    events: [
      {id: 'jbl-game', data: {seasonId, divisionId: 'jbl-a', type: 'game', startTime}},
      {id: 'demo-game', data: {...fixture, type: 'game', startTime}},
    ],
    posts: [
      {id: 'league-news', data: {visibility: 'public', title: 'League news', body: 'Registration is open.', createdAt: startTime}},
      {id: 'demo-news', data: {...fixture, visibility: 'public', title: 'Demo news', body: 'Sample announcement.', createdAt: startTime}},
    ],
    gameStats: [],
    standings: [{id: 'demo-standings', data: {...fixture, standings: [{teamId: 'demo-team'}]}}],
    leaderboard: [{id: 'demo-ppg', data: {...fixture, category: 'ppg'}}],
  };
  const regular = buildApprovedLegacySnapshot(association, sources);
  const filtered = buildApprovedLegacySnapshot(association, sources, {excludeQaFixtures: true});
  assert.equal(regular.leagues.length, 2);
  assert.equal(regular.schedule.length, 2);
  assert.equal(filtered.season.name, '2026 Season');
  assert.deepEqual(filtered.leagues.map(league => league.leagueId), ['jbl']);
  assert.deepEqual(filtered.leagues[0].divisionIds, ['jbl-a']);
  assert.deepEqual(filtered.teams.map(team => team.teamId), ['jbl-team']);
  assert.deepEqual(filtered.schedule.map(game => game.gameId), ['jbl-game']);
  assert.deepEqual(filtered.media.map(item => item.mediaId), ['league-news']);
  assert.deepEqual(filtered.standings, []);
  assert.deepEqual(filtered.leaderboards, []);
});
