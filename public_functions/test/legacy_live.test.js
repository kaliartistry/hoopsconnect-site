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
