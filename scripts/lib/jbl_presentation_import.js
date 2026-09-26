'use strict';

const {createHash} = require('node:crypto');

// Pure local transformation. It deliberately has no Firebase dependency.
function replaceNblPresentation(snapshot, source) {
  const next = structuredClone(snapshot);
  const matches = next.leagues.filter((league) => ['nbl', 'jbl'].includes(league.leagueId));
  if (matches.length !== 1) throw new Error('Expected exactly one NBL/JBL presentation league.');
  const old = matches[0];
  const divisions = new Set(old.divisionIds);
  const priorTeams = new Set(next.teams.filter(t => divisions.has(t.divisionId)).map(t => t.teamId));
  const inScope = row => divisions.has(row.divisionId) || priorTeams.has(row.teamId);
  next.leagues = next.leagues.map(league => league === old ? {
    ...league, leagueId: 'jbl', name: source.leagueName, shortName: source.shortName,
    description: `Player statistics as of ${source.asOf}`,
    seasonLabel: source.seasonLabel, historicalStatistics: true,
    divisionIds: ['jbl-2025-first-round'],
    supportingSponsorExamples: [
      {enabled: true, name: 'ShipSafe SDK', label: 'Demo supporting sponsor', logoUrl: 'asset:assets/images/sponsor_shipsafe.png'},
      {enabled: true, name: 'YardCourt Sporting Co.', label: 'Demo supporting sponsor', logoUrl: 'asset:assets/images/sponsor_yardcourt.png'},
    ],
    branding: {...league.branding, name: source.leagueName, shortName: source.shortName,
      logoUrl: 'asset:assets/images/jbl_full.png',
      sponsor: {enabled: true, name: 'FOSKA Oats', label: 'Main Sponsor',
        logoUrl: 'asset:assets/images/jbl_foska.png', websiteUrl: null}},
  } : league);
  next.divisions = [...next.divisions.filter(d => !divisions.has(d.divisionId)),
    // Internal statistics partition, not a claim about an official division.
    {divisionId: 'jbl-2025-first-round', name: source.seasonLabel}];
  next.teams = [...next.teams.filter(t => !inScope(t)), ...source.teams.map(({sourceTeam, ...team}) => team)];
  next.schedule = next.schedule.filter(g => !inScope(g) && !priorTeams.has(g.homeTeamId) && !priorTeams.has(g.awayTeamId));
  // Aggregate player totals cannot establish team records or official standings.
  next.standings = next.standings.filter(s => !inScope(s));
  next.leaderboards = next.leaderboards.filter(b => !divisions.has(b.divisionId))
    .map(b => ({...b, rankings: b.rankings.filter(p => !inScope(p))}));
  for (const [category, field] of Object.entries({ppg: 'points', rpg: 'rebounds', apg: 'assists', spg: 'steals', bpg: 'blocks'})) {
    const rankings = source.players.map(player => ({
      playerId: player.playerId, displayName: player.displayName,
      teamId: player.teamId, teamName: player.teamName, divisionId: 'jbl-2025-first-round',
      gamesPlayed: player.gamesPlayed, value: player[field] / player.gamesPlayed,
      cumulativeTotal: player[field],
    })).sort((a, b) => b.value - a.value || a.playerId.localeCompare(b.playerId));
    next.leaderboards.push({category, divisionId: 'jbl-2025-first-round',
      qualificationLabel: `${source.seasonLabel} · Per game · All recorded players`, rankings});
  }
  if (next.media) next.media = next.media.filter(m => !inScope(m));
  next.generatedAt = '2026-09-17T18:30:00.000Z';
  next.publication.generatedAt = next.generatedAt;
  delete next.snapshotVersion;
  delete next.publication.snapshotVersion;
  const version = createHash('sha256').update(JSON.stringify(next)).digest('hex');
  next.snapshotVersion = version;
  next.publication.snapshotVersion = version;
  return next;
}

module.exports = {replaceNblPresentation};
