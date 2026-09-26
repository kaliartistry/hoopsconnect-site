'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {replaceNblPresentation} = require('../lib/jbl_presentation_import');

// Independent miniature source, so regression tests don't require the private XLS.
const source = {leagueName: 'Jamaica Basketball League', shortName: 'JBL',
  seasonLabel: '2025 First Round', asOf: '2025-04-10',
  teams: [{teamId: 'new', name: 'Source team', divisionId: 'jbl-2025-first-round'}],
  players: [{playerId: 'p1', displayName: 'Source player', teamId: 'new', teamName: 'Source team',
    gamesPlayed: 2, points: 20, rebounds: 10, assists: 6, steals: 2, blocks: 0}]};
const fixture = {leagues: [{leagueId: 'nbl', divisionIds: ['old'], branding: {}},
  {leagueId: 'women', divisionIds: ['women'], branding: {sponsor: {name: 'Unchanged'}}}],
  divisions: [{divisionId: 'old', name: 'Old'}, {divisionId: 'women', name: 'Women'}],
  teams: [{teamId: 'old-team', divisionId: 'old'}, {teamId: 'kept', divisionId: 'women'}],
  schedule: [{gameId: 'old-game', homeTeamId: 'old-team'}, {gameId: 'kept-game', divisionId: 'women'}],
  standings: [{teamId: 'old-team'}, {teamId: 'kept', divisionId: 'women'}],
  leaderboards: [{category: 'ppg', divisionId: 'old', rankings: []}, {category: 'ppg', divisionId: 'women', rankings: []}],
  associationBrand: {name: 'Existing association'}, publication: {state: 'published'}};

test('replace scoped data only; historical totals and sponsor roles are explicit', () => {
  const before = structuredClone(fixture);
  const next = replaceNblPresentation(fixture, source);
  assert.deepEqual(fixture, before);
  assert.deepEqual(next.associationBrand, before.associationBrand);
  assert.deepEqual(next.leagues[1], before.leagues[1]);
  for (const field of ['teams', 'schedule', 'standings', 'leaderboards', 'divisions']) {
    assert.deepEqual(next[field].filter(r => r.divisionId === 'women'), before[field].filter(r => r.divisionId === 'women'));
  }
  assert.equal(next.leagues[0].branding.sponsor.label, 'Main Sponsor');
  assert.equal(next.leagues[0].branding.sponsor.name, 'FOSKA Oats');
  assert.equal(next.leagues[0].supportingSponsorExamples.length, 2);
  assert.ok(next.leagues[0].supportingSponsorExamples.every(s => s.label.includes('Demo')));
  assert.equal(next.schedule.length, 1);
  assert.equal(next.standings.length, 1);
  const points = next.leaderboards.find(b => b.divisionId === 'jbl-2025-first-round' && b.category === 'ppg');
  assert.equal(points.rankings[0].value, 10);
  assert.equal(points.rankings[0].cumulativeTotal, 20);
  assert.deepEqual(replaceNblPresentation(next, source), next);
});

test('ambiguous league match fails closed', () => {
  assert.throws(() => replaceNblPresentation({...fixture, leagues: []}, source));
  assert.throws(() => replaceNblPresentation({...fixture, leagues: [...fixture.leagues, fixture.leagues[0]]}, source));
});

test('actual bundled historical league has ten teams and no fabricated competition records', () => {
  const snapshot = JSON.parse(fs.readFileSync('assets/demo/presentation_public_snapshot.json'));
  const league = snapshot.leagues.find(l => l.leagueId === 'jbl');
  assert.ok(league.historicalStatistics);
  assert.equal(snapshot.teams.filter(t => league.divisionIds.includes(t.divisionId)).length, 10);
  assert.equal(snapshot.schedule.filter(g => league.divisionIds.includes(g.divisionId)).length, 0);
  const points = snapshot.leaderboards.find(b => b.category === 'ppg' && league.divisionIds.includes(b.divisionId));
  assert.equal(points.rankings.length, 188);
  assert.equal(points.rankings.reduce((n,p) => n+p.cumulativeTotal,0), 5555);
  for (const t of snapshot.teams.filter(t => league.divisionIds.includes(t.divisionId))) assert.ok(fs.existsSync(t.logoUrl.replace('asset:', '')));
});
