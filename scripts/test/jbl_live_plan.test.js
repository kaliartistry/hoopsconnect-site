'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {buildPlan, DIVISION} = require('../lib/jbl_live_plan');
const {projectPlan, decode, projectionData} = require('../lib/jbl_live_runtime');
const {encode} = require('../jbl_live_inventory');
function fixture() {
  const teams = Array.from({length: 10}, (_, i) => ({teamId: `team-${i}`, name: `Team ${i}`, logoUrl: 'asset:assets/images/jbl_full.png'}));
  const players = Array.from({length: 188}, (_, i) => ({playerId: `jbl-player-${i}`, displayName: `Player ${i}`,
    teamId: teams[i % 10].teamId, teamName: teams[i % 10].name, gamesPlayed: 5, points: i === 0 ? 132 : 29,
    rebounds: 8, assists: 4, steals: 2, blocks: 1, twoMade: 10, threeMade: 3, ftMade: 0,
    sourceRow: i + 9, sourcePercentages: {}}));
  const source = {teams, players, leagueName: 'Jamaica Basketball League', seasonLabel: '2025 First Round',
    asOf: '2025-04-10', source: {sha256: 'a'.repeat(64)}};
  const records = [
    ['associations/jba', {currentSeasonId: 'shared', brandingV1: {leagueName: 'Jamaica Basketball Association'},
      leagueCatalogV1: {schemaVersion: 1, leagues: [
        {leagueId: 'nbl', name: 'National Basketball League', divisionIds: ['nbl-premier']},
        {leagueId: 'women', name: 'Women', divisionIds: ['women']},
      ]}}],
    ['associations/jba/divisions/nbl-premier', {name: 'NBL', seasonId: 'shared'}],
    ['associations/jba/divisions/women', {name: 'Women', seasonId: 'shared'}],
    ['associations/jba/seasons/shared', {name: 'NBL 2025-26'}],
    ['associations/jba/teams/team-0', {name: 'Old team', divisionId: 'nbl-premier', seasonId: 'shared'}],
    ['associations/jba/teams/women', {name: 'Women team', divisionId: 'women', seasonId: 'shared'}],
    ['associations/jba/playerSeasonStats/old-player', {playerId: 'old-player', teamId: 'team-0', divisionId: 'nbl-premier'}],
    ['associations/jba/events/old-game', {divisionId: 'nbl-premier', teamIds: ['team-0']}],
    ['associations/jba/events/star-event', {title: 'NBL All-Star Weekend'}],
    ['associations/jba/events/women-game', {type: 'game', seasonId: 'shared', divisionId: 'women',
      teamIds: ['women'], startTime: {$type: 'timestamp', seconds: 1744243200, nanoseconds: 0}}],
    ['associations/jba/gameStats/old-game', {status: 'approved', divisionId: 'nbl-premier'}],
    ['associations/jba/events/old-game/acknowledgments/one', {value: true}],
    ['associations/jba/leaderboard/overall', {rankings: [{playerId: 'old-player'}, {playerId: 'female', teamId: 'women'}]}],
    ['associations/jba/standings/overall', {standings: [{teamId: 'team-0'}, {teamId: 'women'}]}],
    ['associations/jba/posts/internal-women', {title: 'Women news', visibility: 'internal'}],
    ['associations/jba/posts/public-women', {title: 'Published women news', body: 'Existing public article',
      visibility: 'public', createdAt: {$type: 'timestamp', seconds: 1744243200, nanoseconds: 0}}],
    ['associations/jba/posts/nbl', {title: 'NBL news', visibility: 'public'}],
    ['associations/jba/leagueActorAuthorities/admin', {role: 'superAdmin'}],
    ['associations/jba/competitions/qa-nbl', {name: 'Synthetic National Basketball League'}],
    ['associations/jba/competitions/qa-nbl/seasons/shared/teamEntries/women', {teamId: 'women'}],
  ].map(([path, data]) => ({path, data}));
  return {source, backup: {projectId: 'hoopsconnect-jba-staging', records},
    logos: {'jbl_full.png': 'https://example.test/league.png', 'jbl_foska.png': 'https://example.test/sponsor.png'}};
}
test('JBL replaces only NBL and projects all ten teams and 188 source rows', () => {
  const {source, backup, logos} = fixture();
  const plan = buildPlan(backup, source, logos);
  const {after, snapshot} = projectPlan(backup, plan);
  assert.equal(snapshot.leagues[0].historicalStatistics, true);
  assert.equal(snapshot.leagues[0].seasonLabel, '2025 First Round');
  assert.equal(snapshot.leagues[0].branding.sponsor.name, 'FOSKA Oats');
  assert.equal(snapshot.teams.filter(t => t.divisionId === DIVISION).length, 10);
  assert.equal(after.has('associations/jba/gameStats/old-game'), false);
  assert.equal(after.has('associations/jba/events/old-game/acknowledgments/one'), false);
  assert.equal(after.has('associations/jba/events/star-event'), false);
  for (const path of ['associations/jba/teams/women', 'associations/jba/divisions/women',
    'associations/jba/posts/internal-women', 'associations/jba/leagueActorAuthorities/admin',
    'associations/jba/competitions/qa-nbl/seasons/shared/teamEntries/women']) {
    assert.deepEqual(after.get(path), backup.records.find(r => r.path === path).data);
  }
  assert.deepEqual(after.get('associations/jba/leaderboard/overall').rankings, [{playerId: 'female', teamId: 'women'}]);
  assert.equal(snapshot.media.length, 1, 'Preserve only the existing public article');
  assert.equal(snapshot.media[0].mediaId, 'public-women');
  assert.equal(snapshot.schedule.length, 1, 'Preserve the existing women game and invent no JBL results');
  assert.equal(snapshot.schedule[0].gameId, 'women-game');
  assert.equal(snapshot.schedule[0].startTime, '2025-04-10T00:00:00.000Z');
  const reversed = structuredClone(backup);
  reversed.records.reverse();
  assert.equal(projectPlan(reversed, buildPlan(reversed, source, logos)).snapshot.snapshotVersion,
    snapshot.snapshotVersion, 'Publication must not depend on source query order');
  assert.equal(snapshot.certificationStatus, 'certified');
  assert.equal(snapshot.publication.verificationStatus, 'legacyApproved');
  // Every mutation has exactly enough information to restore it.
  for (const op of plan.operations) op.before ? after.set(op.path, op.before.data) : after.delete(op.path);
  assert.deepEqual([...after].sort(), backup.records.map(r => [r.path, r.data]).sort());
});
test('reject wrong source, project, repeated import and cross-league team collision', () => {
  for (const mutate of [f => f.source.players.pop(), f => f.source.players[0].points++,
    f => f.backup.projectId = 'unrelated', f => f.backup.records[0].data.leagueCatalogV1.leagues[0].leagueId = 'jbl',
    f => f.source.teams[0].teamId = 'women']) {
    const f = fixture(); mutate(f);
    assert.throws(() => buildPlan(f.backup, f.source, f.logos));
  }
});
test('backup codec preserves timestamps and structured Firestore values', () => {
  const value = {date: {$type: 'timestamp', seconds: 1744243200, nanoseconds: 1234},
    point: {$type: 'geoPoint', latitude: 18, longitude: -77}, bytes: {$type: 'bytes', value: 'YWJj'}};
  assert.deepEqual(encode(decode(value)), value);
  assert.equal(projectionData(value).date, '2025-04-10T00:00:00.000Z');
});
test('realistic Storage URLs survive publication without truncation', () => {
  const f = fixture();
  const url = 'https://firebasestorage.googleapis.com/v0/b/example.appspot.com/o/' + 'a'.repeat(150) + '?alt=media&token=public-artwork';
  f.logos['jbl_full.png'] = url;
  const {snapshot} = projectPlan(f.backup, buildPlan(f.backup, f.source, f.logos));
  assert.equal(snapshot.teams[0].logoUrl, url);
  assert.equal(snapshot.leagues[0].branding.logoUrl, url);
  f.logos['jbl_full.png'] = url + 'a'.repeat(2100);
  assert.throws(() => projectPlan(f.backup, buildPlan(f.backup, f.source, f.logos)), /2048/);
});
