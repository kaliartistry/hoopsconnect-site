'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const BASE = 'associations/jba/';
const DIVISION = 'jbl-2025-first-round';
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');

function buildPlan(backup, source, logoUrls) {
  assert.ok(['hoops-connect-jm', 'hoopsconnect-jba-staging'].includes(backup.projectId));
  assert.equal(source.players.length, 188);
  assert.equal(source.teams.length, 10);
  assert.equal(source.players.reduce((sum, p) => sum + p.points, 0), 5555);
  const original = new Map(backup.records.map(row => [row.path, row]));
  const association = original.get('associations/jba').data;
  const seasonId = association.currentSeasonId;
  assert.ok(seasonId);
  const catalog = structuredClone(association.leagueCatalogV1 || {schemaVersion: 1, leagues: [
    {leagueId: 'nbl', name: 'National Basketball League', shortName: 'NBL', divisionIds: ['nbl-premier'], status: 'active', sortOrder: 0},
    {leagueId: 'womens', name: 'Women’s National League', shortName: 'Women’s', divisionIds: ['womens-league'], status: 'active', sortOrder: 1},
  ]});
  const candidates = catalog.leagues.filter(league => league.leagueId === 'nbl');
  assert.equal(candidates.length, 1, 'Require exactly one NBL, refusing repeated or ambiguous replacement');
  const oldDivisions = new Set(candidates[0].divisionIds);
  for (const id of oldDivisions) assert.ok(original.has(`${BASE}divisions/${id}`));
  const top = collection => backup.records.filter(row => row.path.startsWith(`${BASE}${collection}/`) && row.path.split('/').length === 4);
  const oldTeams = new Set(top('teams').filter(row => oldDivisions.has(row.data.divisionId)).map(row => row.path.split('/').pop()));
  assert.ok(oldTeams.size > 0);
  const oldPlayers = new Set(top('playerSeasonStats').filter(row => oldTeams.has(row.data.teamId)).map(row => row.data.playerId));
  const playerTeams = new Map(top('playerSeasonStats').map(row => [row.data.playerId, row.data.teamId]));
  const oldGames = new Set(top('events').filter(row => oldDivisions.has(row.data.divisionId) || row.data.teamIds?.some(id => oldTeams.has(id)) || /\bNBL\b|National Basketball League/.test(row.data.title || '')).map(row => row.path.split('/').pop()));
  const oldEntries = new Set(backup.records.filter(row => row.path.includes('/teamEntries/') && oldTeams.has(row.data.teamId)).map(row => row.path.split('/').pop()));
  const changes = new Map();
  const put = (path, data, reason) => {
    assert.ok(path === 'associations/jba' || path.startsWith(BASE));
    const previous = original.get(path);
    if (previous && digest(previous.data) === digest(data)) return;
    changes.set(path, {path, action: 'set', data, before: previous || null, reason});
  };
  const remove = (row, reason) => changes.set(row.path, {path: row.path, action: 'delete', before: row, reason});
  const inScope = data => oldDivisions.has(data.divisionId) || oldTeams.has(data.teamId) ||
    oldTeams.has(data.homeTeamId) || oldTeams.has(data.awayTeamId) || oldPlayers.has(data.playerId) || oldGames.has(data.eventId);
  for (const row of backup.records) {
    if (!row.path.startsWith(BASE)) continue;
    const relative = row.path.slice(BASE.length), parts = relative.split('/'), data = row.data;
    if (parts[0] === 'divisions' && oldDivisions.has(parts[1]) ||
        ['teams', 'teamIdentities'].includes(parts[0]) && oldTeams.has(parts[1]) ||
        parts[0] === 'events' && oldGames.has(parts[1]) ||
        parts[0] === 'gameStats' && oldGames.has(parts[1]) ||
        ['playerSeasonStats', 'teamSeasonStats'].includes(parts[0]) && inScope(data) ||
        parts[0] === 'players' && oldPlayers.has(parts[1]) ||
        parts[0] === 'persons' && oldPlayers.has(data.personId?.replace(/-person$/, '')) ||
        relative.includes('/teamEntries/') && (oldTeams.has(data.teamId) || oldEntries.has(parts.at(-1))) ||
        relative.includes('/rosterMemberships/') && (oldPlayers.has(data.playerId) || oldEntries.has(data.teamEntryId))) {
      remove(row, 'NBL-owned record');
    }
    if (['standings', 'leaderboard'].includes(parts[0]) && parts.length === 2) {
      if (oldDivisions.has(data.divisionId)) remove(row, 'NBL division aggregate');
      else {
        const field = parts[0] === 'standings' ? 'standings' : 'rankings';
        const next = structuredClone(data);
        if (Array.isArray(next[field])) next[field] = next[field].filter(item => !inScope(item));
        if (Array.isArray(next.processedEvents)) next.processedEvents = next.processedEvents.filter(id => !oldGames.has(id));
        // Existing names were already public in the previous production feed.
        if (parts[0] === 'leaderboard' && backup.projectId === 'hoops-connect-jm') {
          const publicNames = new Set((original.get('publicData/jba/snapshots/current')?.data.leaderboards || []).flatMap(board => board.rankings.map(p => p.displayName)));
          next.rankings = next.rankings.map(item => publicNames.has(item.name) ? {
            ...item, publicDisplayName: item.name,
            teamId: item.teamId || playerTeams.get(item.playerId),
          } : item);
        }
        put(row.path, next, 'Remove only NBL rows from shared aggregate');
      }
    }
    if (parts[0] === 'posts' && parts.length === 2 &&
        (oldDivisions.has(data.divisionFilter) || oldTeams.has(data.teamId) ||
         /\bNBL\b|National Basketball League/.test(`${data.title || ''} ${data.body || ''}`) ||
         backup.projectId === 'hoops-connect-jm' && parts[1] === 'WnuAalTyUq3uDIpjR9AV')) {
      remove(row, 'NBL announcement or media item');
    }
  }
  // Descendants of explicitly removed records must not be orphaned.
  const deletedRoots = [...changes.values()].filter(row => row.action === 'delete').map(row => row.path + '/');
  for (const row of backup.records) if (deletedRoots.some(prefix => row.path.startsWith(prefix))) remove(row, 'Descendant of NBL record');
  const logo = asset => {
    const file = asset.replace('asset:assets/images/', '');
    assert.ok(logoUrls[file]?.startsWith('https://'), `Missing public logo ${file}`);
    return logoUrls[file];
  };
  const league = {leagueId: 'jbl', name: source.leagueName, shortName: 'JBL',
    description: `First-round player statistics as of ${source.asOf}`,
    seasonLabel: source.seasonLabel, historicalStatistics: true,
    divisionIds: [DIVISION], status: 'active', sortOrder: candidates[0].sortOrder || 0,
    branding: {schemaVersion: 1, logoUrl: logo('asset:assets/images/jbl_full.png'),
      primaryColorHex: '#234EBD', secondaryColorHex: '#102A70', accentColorHex: '#F2B632',
      sponsor: {enabled: true, name: 'FOSKA Oats', label: 'Main Sponsor',
        logoUrl: logo('asset:assets/images/jbl_foska.png'), websiteUrl: null}}};
  catalog.leagues = catalog.leagues.map(entry => entry.leagueId === 'nbl' ? league : entry);
  put('associations/jba', {...association, leagueCatalogV1: catalog,
    publicLeagueState: 'published', publicPrivacyEpoch: association.publicPrivacyEpoch ?? 1}, 'Replace only NBL catalog entry');
  put(`${BASE}divisions/${DIVISION}`, {name: source.seasonLabel, leagueId: 'jbl', seasonId,
    description: 'Historical statistical period, not a current competition division.',
    historicalStatistics: true, status: 'active', version: 0}, 'JBL historical statistics partition');
  for (const team of source.teams) {
    const target = `${BASE}teams/${team.teamId}`;
    assert.ok(!original.has(target) || oldTeams.has(team.teamId), 'Team collision with another league');
    put(target, {associationId: 'jba', name: team.name, normalizedName: team.name.trim().toLowerCase(),
      divisionId: DIVISION, leagueId: 'jbl', seasonId, logoUrl: logo(team.logoUrl), repIds: [],
      historicalStatistics: true, statisticsPeriod: source.seasonLabel,
      sourceWorkbookSha256: source.source.sha256}, 'Kurt-supplied JBL team');
  }
  const timestamp = {$type: 'timestamp', seconds: Math.floor(Date.parse(source.asOf + 'T00:00:00Z') / 1000), nanoseconds: 0};
  const sourceMeta = {sourceWorkbookSha256: source.source.sha256, sourceAsOf: source.asOf,
    statisticsPeriod: source.seasonLabel, historicalStatistics: true};
  for (const player of source.players) {
    const target = `${BASE}playerSeasonStats/${player.playerId}_${seasonId}`;
    assert.ok(!original.has(target), 'Imported player record already exists');
    put(target, {playerId: player.playerId, playerName: player.displayName, teamId: player.teamId,
      teamName: player.teamName, seasonId, divisionId: DIVISION,
      gamesPlayed: player.gamesPlayed,
      totals: {pts: player.points, reb: player.rebounds, ast: player.assists, stl: player.steals,
        blk: player.blocks, twoMade: player.twoMade, threeMade: player.threeMade, ftMade: player.ftMade},
      averages: {ppg: player.points / player.gamesPlayed, rpg: player.rebounds / player.gamesPlayed,
        apg: player.assists / player.gamesPlayed, spg: player.steals / player.gamesPlayed, bpg: player.blocks / player.gamesPlayed},
      gameLog: [], ...sourceMeta, sourceRow: player.sourceRow,
      sourcePercentages: player.sourcePercentages}, 'Historical player totals, not a current roster registration');
  }
  for (const [category, field] of Object.entries({ppg: 'points', rpg: 'rebounds', apg: 'assists', spg: 'steals', bpg: 'blocks'})) {
    const rankings = source.players.map(player => ({playerId: player.playerId, name: player.displayName,
      publicDisplayName: player.displayName, teamId: player.teamId, teamName: player.teamName,
      divisionId: DIVISION, gp: player.gamesPlayed, value: player[field] / player.gamesPlayed,
      cumulativeTotal: player[field]})).sort((a, b) => b.value - a.value || a.playerId.localeCompare(b.playerId));
    put(`${BASE}leaderboard/${seasonId}_${DIVISION}_${category}`, {seasonId, divisionId: DIVISION,
      category, updatedAt: timestamp, rankings, qualificationLabel: `${source.seasonLabel} · Per game · All recorded players`,
      ...sourceMeta}, 'JBL period leaderboard from source totals');
  }
  // Shared season IDs are preserved, so women's records and saved references
  // are not deleted or silently moved into another season.
  const sharedSeason = original.get(`${BASE}seasons/${seasonId}`);
  if (sharedSeason && /\bNBL\b/.test(sharedSeason.data.name)) put(sharedSeason.path,
    {...sharedSeason.data, name: sharedSeason.data.name.replace(/\bNBL\s*/, '')}, 'Remove NBL label from shared season');
  // This pre-existing QA container includes other leagues. Keep its IDs and
  // children; rename the shared display label instead of deleting their data.
  const sharedCompetition = original.get(`${BASE}competitions/qa-nbl`);
  if (sharedCompetition) put(sharedCompetition.path,
    {...sharedCompetition.data, name: 'Jamaica Basketball competitions'}, 'Neutral label for preserved shared competition container');
  const operations = [...changes.values()].sort((a,b) => a.path.localeCompare(b.path));
  const counts = {};
  for (const operation of operations) {
    const key = `${operation.action}:${operation.path.split('/')[2] || 'association'}`;
    counts[key] = (counts[key] || 0) + 1;
  }
  return {schemaVersion: 1, projectId: backup.projectId, sourceSha256: source.source.sha256,
    backupSha256: digest(backup), oldDivisions: [...oldDivisions], oldTeams: [...oldTeams],
    oldPlayers: [...oldPlayers], oldGames: [...oldGames], seasonId, counts, operations};
}

module.exports = {buildPlan, digest, DIVISION};
