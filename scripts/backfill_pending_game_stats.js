#!/usr/bin/env node

const { execSync } = require('child_process');
const https = require('https');
const http = require('http');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

const DEFAULT_ASSOC = 'jba';
const DEFAULT_SEASON = 'nbl-2025-26';
const BACKFILL_SOURCE = 'codex-demo-stat-backfill-2026-06-30';

const args = new Set(process.argv.slice(2));
const COMMIT = args.has('--commit');
const ASSOC_ID = readArg('--assoc', DEFAULT_ASSOC);
const SEASON_ID = readArg('--season', DEFAULT_SEASON);
const NOW = new Date(readArg('--now', '2026-06-30T00:00:00-04:00'));
const TARGET = guardFirestoreTarget({mode: COMMIT ? 'write' : 'read'});
const PROJECT_ID = TARGET.projectId;
const BASE_URL = TARGET.baseUrl;
const firestoreTransport = TARGET.isEmulator ? http : https;

function readArg(name, fallback) {
  const idx = process.argv.indexOf(name);
  if (idx === -1 || idx + 1 >= process.argv.length) return fallback;
  return process.argv[idx + 1];
}

function getAccessToken() {
  if (TARGET.isEmulator) return null;
  return execSync('gcloud auth print-access-token', {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

let accessToken;

async function request(method, docPath, body = null) {
  accessToken ||= getAccessToken();
  const url = new URL(`${BASE_URL}${docPath}`);

  return new Promise((resolve, reject) => {
    const req = firestoreTransport.request(
      {
        hostname: url.hostname,
        path: url.pathname + url.search,
        method,
        headers: {
          ...(accessToken ? {Authorization: `Bearer ${accessToken}`} : {}),
          'Content-Type': 'application/json',
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          if (res.statusCode >= 400) {
            reject(
              new Error(
                `HTTP ${res.statusCode} ${method} ${docPath}: ${data.slice(0, 1000)}`
              )
            );
            return;
          }
          resolve(data ? JSON.parse(data) : {});
        });
      }
    );

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function decodeValue(value) {
  if (!value) return undefined;
  if ('nullValue' in value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) {
    return (value.arrayValue.values || []).map(decodeValue);
  }
  if ('mapValue' in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields || {}).map(([key, val]) => [
        key,
        decodeValue(val),
      ])
    );
  }
  return undefined;
}

function decodeDoc(doc) {
  const fields = Object.fromEntries(
    Object.entries(doc.fields || {}).map(([key, value]) => [
      key,
      decodeValue(value),
    ])
  );
  fields.id = doc.name.split('/').pop();
  return fields;
}

function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, val]) => [key, encodeValue(val)])
        ),
      },
    };
  }
  return { stringValue: String(value) };
}

function encodeDoc(data) {
  return {
    fields: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, encodeValue(value)])
    ),
  };
}

async function listCollection(collectionPath) {
  const docs = [];
  let pageToken = '';

  do {
    const query = `?pageSize=300${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const result = await request('GET', `/${collectionPath}${query}`);
    docs.push(...(result.documents || []).map(decodeDoc));
    pageToken = result.nextPageToken || '';
  } while (pageToken);

  return docs;
}

async function patchDoc(docPath, data, updateMask = null) {
  const maskQuery = updateMask
    ? `?${updateMask
        .map((field) => `updateMask.fieldPaths=${encodeURIComponent(field)}`)
        .join('&')}`
    : '';
  await request('PATCH', `/${docPath}${maskQuery}`, encodeDoc(data));
}

function hashString(input) {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function rng(seed) {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b79f5;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function round1(value) {
  return Math.round(value * 10) / 10;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function parseDate(value) {
  return value ? new Date(value) : new Date(0);
}

function teamStrength(standingsByTeam, teamId) {
  const standing = standingsByTeam.get(teamId);
  if (!standing) return 0.5;
  const games = (standing.wins || 0) + (standing.losses || 0);
  const pct = games ? standing.wins / games : 0.5;
  const pointDiff = ((standing.pointsFor || 0) - (standing.pointsAgainst || 0)) / Math.max(games, 1);
  return pct + pointDiff / 100;
}

function chooseWinner(event, standingsByTeam, random) {
  const [homeId, awayId] = event.teamIds;
  const homeStrength = teamStrength(standingsByTeam, homeId) + 0.08;
  const awayStrength = teamStrength(standingsByTeam, awayId);
  const probability = clamp(0.5 + (homeStrength - awayStrength) * 0.22, 0.28, 0.72);
  return random() <= probability ? homeId : awayId;
}

function generateScore(event, winnerId, random) {
  const [homeId, awayId] = event.teamIds;
  const isWomens = event.divisionId === 'womens-league';
  const baseLow = isWomens ? 62 : 72;
  const baseHigh = isWomens ? 79 : 92;
  const winnerScore = baseLow + Math.floor(random() * (baseHigh - baseLow + 1));
  const margin = 3 + Math.floor(random() * (isWomens ? 14 : 18));
  const loserScore = Math.max(isWomens ? 48 : 58, winnerScore - margin);

  return {
    homeScore: winnerId === homeId ? winnerScore : loserScore,
    awayScore: winnerId === awayId ? winnerScore : loserScore,
  };
}

function distributeTotal(total, weights, minValues = []) {
  const values = weights.map((_, idx) => minValues[idx] || 0);
  let remaining = total - values.reduce((sum, value) => sum + value, 0);
  const weightSum = weights.reduce((sum, value) => sum + value, 0);

  for (let i = 0; i < weights.length; i += 1) {
    const add = Math.floor((remaining * weights[i]) / weightSum);
    values[i] += add;
  }

  let diff = total - values.reduce((sum, value) => sum + value, 0);
  let idx = 0;
  while (diff > 0) {
    values[idx % values.length] += 1;
    diff -= 1;
    idx += 1;
  }

  return values;
}

function generateQuarterScores(total, random) {
  const weights = [
    0.95 + random() * 0.2,
    0.95 + random() * 0.2,
    0.95 + random() * 0.2,
    0.95 + random() * 0.2,
  ];
  const scores = distributeTotal(total, weights);
  return {
    1: scores[0],
    2: scores[1],
    3: scores[2],
    4: scores[3],
  };
}

function rosterWeight(player, idx, random) {
  const ppg = Number(player.averages?.ppg || player.averages?.pts || 0);
  const role = Math.max(0.4, 1.8 - idx * 0.16);
  return Math.max(0.3, role + ppg / 18 + random() * 0.35);
}

function generateTeamLines(eventId, team, score, roster, random) {
  const players = roster.slice(0, 8);
  if (players.length === 0) {
    throw new Error(`No roster found for ${team.id}`);
  }

  const weights = players.map((player, idx) => rosterWeight(player, idx, random));
  const pointFloor = players.map((_, idx) => (idx < 5 ? 2 : 0));
  const points = distributeTotal(score, weights, pointFloor);
  const rebounds = distributeTotal(
    29 + Math.floor(random() * 16),
    players.map((player, idx) => Math.max(0.5, 1.2 + (player.averages?.rpg || 0) / 6 - idx * 0.04))
  );
  const assists = distributeTotal(
    Math.max(10, Math.round(score * (0.45 + random() * 0.1))),
    players.map((player, idx) => Math.max(0.5, 1 + (player.averages?.apg || 0) / 4 - idx * 0.03))
  );
  const steals = distributeTotal(4 + Math.floor(random() * 6), weights);
  const blocks = distributeTotal(2 + Math.floor(random() * 5), weights);
  const fouls = distributeTotal(12 + Math.floor(random() * 8), players.map(() => 1));
  const minutes = distributeTotal(
    200,
    players.map((_, idx) => (idx < 5 ? 1.7 - idx * 0.12 : 0.75 - (idx - 5) * 0.08)),
    players.map((_, idx) => (idx < 5 ? 18 : 8))
  ).map((value) => clamp(value, 5, 40));

  return Object.fromEntries(
    players.map((player, idx) => {
      const playerId = player.playerId || player.id.replace(`_${SEASON_ID}`, '');
      const reb = rebounds[idx];
      const oreb = Math.min(reb, Math.floor(reb * (0.25 + random() * 0.18)));
      const dreb = reb - oreb;
      return [
        playerId,
        {
          name: player.playerName,
          teamId: team.id,
          pts: points[idx],
          oreb,
          dreb,
          reb,
          ast: assists[idx],
          stl: steals[idx],
          blk: blocks[idx],
          fls: Math.min(6, fouls[idx]),
          min: minutes[idx],
        },
      ];
    })
  );
}

function generateGameStats(event, teamsById, rosterByTeam, standingsByTeam) {
  const random = rng(hashString(event.id));
  const [homeTeamId, awayTeamId] = event.teamIds || [];
  const homeTeam = teamsById.get(homeTeamId);
  const awayTeam = teamsById.get(awayTeamId);

  if (!homeTeam || !awayTeam) {
    throw new Error(`Missing team metadata for ${event.id}: ${homeTeamId} vs ${awayTeamId}`);
  }

  const winnerId = chooseWinner(event, standingsByTeam, random);
  const { homeScore, awayScore } = generateScore(event, winnerId, random);
  const submittedAt = new Date(parseDate(event.endTime || event.startTime).getTime() + 10 * 60 * 1000);
  const approvedAt = new Date(submittedAt.getTime() + 5 * 60 * 1000);
  const homeLines = generateTeamLines(
    event.id,
    homeTeam,
    homeScore,
    rosterByTeam.get(homeTeamId) || [],
    random
  );
  const awayLines = generateTeamLines(
    event.id,
    awayTeam,
    awayScore,
    rosterByTeam.get(awayTeamId) || [],
    random
  );

  return {
    eventId: event.id,
    seasonId: event.seasonId || SEASON_ID,
    divisionId: event.divisionId,
    homeTeamId,
    awayTeamId,
    homeTeamName: homeTeam.name,
    awayTeamName: awayTeam.name,
    homeScore,
    awayScore,
    status: 'approved',
    submittedBy: 'system',
    submittedAt,
    approvedBy: 'system',
    approvedAt,
    entryMode: 'postGame',
    playerLines: { ...homeLines, ...awayLines },
    homeQuarterScores: generateQuarterScores(homeScore, random),
    awayQuarterScores: generateQuarterScores(awayScore, random),
    generatedBy: BACKFILL_SOURCE,
    generatedAt: new Date(),
  };
}

function resultForTeam(game, teamId) {
  const homeWon = game.homeScore > game.awayScore;
  return teamId === game.homeTeamId ? (homeWon ? 'W' : 'L') : homeWon ? 'L' : 'W';
}

function opponentForTeam(game, teamId) {
  return teamId === game.homeTeamId
    ? { teamId: game.awayTeamId, name: game.awayTeamName }
    : { teamId: game.homeTeamId, name: game.homeTeamName };
}

function sortedApprovedGames(gameStats, eventsById) {
  return gameStats
    .filter((game) => game.status === 'approved')
    .sort((a, b) => {
      const aDate = parseDate(eventsById.get(a.eventId)?.startTime || a.approvedAt);
      const bDate = parseDate(eventsById.get(b.eventId)?.startTime || b.approvedAt);
      return aDate - bDate;
    });
}

function buildPlayerSeasonStats(gameStats, teamsById, eventsById) {
  const players = new Map();

  for (const game of sortedApprovedGames(gameStats, eventsById)) {
    const approvedAt = parseDate(game.approvedAt);
    for (const [playerId, line] of Object.entries(game.playerLines || {})) {
      const team = teamsById.get(line.teamId);
      if (!players.has(`${playerId}_${game.seasonId}`)) {
        players.set(`${playerId}_${game.seasonId}`, {
          playerId,
          playerName: line.name,
          teamId: line.teamId,
          teamName: team?.name || '',
          seasonId: game.seasonId,
          divisionId: game.divisionId,
          gamesPlayed: 0,
          totals: { pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, fls: 0, min: 0, oreb: 0, dreb: 0 },
          averages: {},
          gameLog: [],
        });
      }

      const doc = players.get(`${playerId}_${game.seasonId}`);
      const reb = Number(line.reb ?? (line.oreb || 0) + (line.dreb || 0));
      const oreb = Number(line.oreb || 0);
      const dreb = Number(line.dreb || Math.max(0, reb - oreb));
      doc.gamesPlayed += 1;
      doc.totals.pts += Number(line.pts || 0);
      doc.totals.reb += reb;
      doc.totals.ast += Number(line.ast || 0);
      doc.totals.stl += Number(line.stl || 0);
      doc.totals.blk += Number(line.blk || 0);
      doc.totals.fls += Number(line.fls || 0);
      doc.totals.min += Number(line.min || 0);
      doc.totals.oreb += oreb;
      doc.totals.dreb += dreb;
      doc.gameLog.push({
        eventId: game.eventId,
        date: approvedAt,
        vs: opponentForTeam(game, line.teamId).name,
        pts: Number(line.pts || 0),
        reb,
        ast: Number(line.ast || 0),
        stl: Number(line.stl || 0),
        blk: Number(line.blk || 0),
        result: resultForTeam(game, line.teamId),
      });
    }
  }

  for (const doc of players.values()) {
    const gp = doc.gamesPlayed;
    doc.averages = {
      pts: round1(doc.totals.pts / gp),
      ppg: round1(doc.totals.pts / gp),
      reb: round1(doc.totals.reb / gp),
      rpg: round1(doc.totals.reb / gp),
      ast: round1(doc.totals.ast / gp),
      apg: round1(doc.totals.ast / gp),
      stl: round1(doc.totals.stl / gp),
      spg: round1(doc.totals.stl / gp),
      blk: round1(doc.totals.blk / gp),
      bpg: round1(doc.totals.blk / gp),
    };
  }

  return players;
}

function buildTeamSeasonStats(gameStats, teamsById, eventsById) {
  const teams = new Map();

  for (const game of sortedApprovedGames(gameStats, eventsById)) {
    const approvedAt = parseDate(game.approvedAt);
    const gameTeamTotals = new Map();

    for (const line of Object.values(game.playerLines || {})) {
      const reb = Number(line.reb ?? (line.oreb || 0) + (line.dreb || 0));
      const totals = gameTeamTotals.get(line.teamId) || {
        pts: 0,
        oreb: 0,
        dreb: 0,
        reb: 0,
        ast: 0,
        stl: 0,
        blk: 0,
        to: 0,
        fls: 0,
        min: 0,
      };
      totals.pts += Number(line.pts || 0);
      totals.oreb += Number(line.oreb || 0);
      totals.dreb += Number(line.dreb || Math.max(0, reb - (line.oreb || 0)));
      totals.reb += reb;
      totals.ast += Number(line.ast || 0);
      totals.stl += Number(line.stl || 0);
      totals.blk += Number(line.blk || 0);
      totals.fls += Number(line.fls || 0);
      totals.min += Number(line.min || 0);
      gameTeamTotals.set(line.teamId, totals);
    }

    for (const teamId of [game.homeTeamId, game.awayTeamId]) {
      const team = teamsById.get(teamId);
      const key = `${teamId}_${game.seasonId}`;
      if (!teams.has(key)) {
        teams.set(key, {
          teamId,
          teamName: team?.name || (teamId === game.homeTeamId ? game.homeTeamName : game.awayTeamName),
          seasonId: game.seasonId,
          divisionId: game.divisionId,
          gamesPlayed: 0,
          totals: { pts: 0, oreb: 0, dreb: 0, reb: 0, ast: 0, stl: 0, blk: 0, to: 0, fls: 0, min: 0 },
          averages: {},
          gameLog: [],
        });
      }

      const doc = teams.get(key);
      const totals = gameTeamTotals.get(teamId) || {
        pts: teamId === game.homeTeamId ? game.homeScore : game.awayScore,
        oreb: 0,
        dreb: 0,
        reb: 0,
        ast: 0,
        stl: 0,
        blk: 0,
        to: 0,
        fls: 0,
        min: 0,
      };
      const opponent = opponentForTeam(game, teamId);
      doc.gamesPlayed += 1;
      for (const stat of Object.keys(doc.totals)) {
        doc.totals[stat] += Number(totals[stat] || 0);
      }
      doc.gameLog.push({
        eventId: game.eventId,
        opponentName: opponent.name,
        opponentTeamId: opponent.teamId,
        date: approvedAt,
        pts: totals.pts,
        oreb: totals.oreb,
        dreb: totals.dreb,
        reb: totals.reb,
        ast: totals.ast,
        stl: totals.stl,
        blk: totals.blk,
        to: totals.to,
        fls: totals.fls,
        result: resultForTeam(game, teamId),
        quarterScores: teamId === game.homeTeamId ? game.homeQuarterScores || null : game.awayQuarterScores || null,
        opponentQuarterScores: teamId === game.homeTeamId ? game.awayQuarterScores || null : game.homeQuarterScores || null,
      });
    }
  }

  for (const doc of teams.values()) {
    const gp = doc.gamesPlayed;
    doc.averages = {
      ppg: round1(doc.totals.pts / gp),
      rpg: round1(doc.totals.reb / gp),
      apg: round1(doc.totals.ast / gp),
      spg: round1(doc.totals.stl / gp),
      bpg: round1(doc.totals.blk / gp),
      topg: round1(doc.totals.to / gp),
      fpg: round1(doc.totals.fls / gp),
    };
  }

  return teams;
}

function emptyStanding(team) {
  return {
    teamId: team.id,
    teamName: team.name,
    divisionId: team.divisionId || null,
    wins: 0,
    losses: 0,
    pct: 0,
    gb: 0,
    streak: '-',
    lastTen: '-',
    pointsFor: 0,
    pointsAgainst: 0,
    results: [],
  };
}

function finalizeStandings(records) {
  const standings = [...records.values()].sort(
    (a, b) =>
      b.pct - a.pct ||
      b.wins - a.wins ||
      b.pointsFor - b.pointsAgainst - (a.pointsFor - a.pointsAgainst)
  );
  const leader = standings[0];
  const leaderDiff = leader ? leader.wins - leader.losses : 0;

  return standings.map((entry) => {
    const lastTenResults = entry.results.slice(-10);
    const lastTenWins = lastTenResults.filter((result) => result === 'W').length;
    const streakType = entry.results.at(-1) || '-';
    let streakCount = 0;
    for (let i = entry.results.length - 1; i >= 0; i -= 1) {
      if (entry.results[i] !== streakType) break;
      streakCount += 1;
    }

    return {
      teamId: entry.teamId,
      teamName: entry.teamName,
      divisionId: entry.divisionId,
      wins: entry.wins,
      losses: entry.losses,
      pct: entry.wins + entry.losses ? round1((entry.wins / (entry.wins + entry.losses)) * 1000) / 1000 : 0,
      gb: ((leaderDiff - (entry.wins - entry.losses)) / 2),
      streak: streakType === '-' ? '-' : `${streakType}${streakCount}`,
      lastTen: lastTenResults.length ? `${lastTenWins}-${lastTenResults.length - lastTenWins}` : '-',
      pointsFor: entry.pointsFor,
      pointsAgainst: entry.pointsAgainst,
    };
  });
}

function buildStandings(gameStats, teamsById, eventsById) {
  const allRecords = new Map();
  const divisionRecords = new Map();
  const processedByDivision = new Map();
  const processedAll = [];

  for (const team of teamsById.values()) {
    if (!allRecords.has(team.id)) allRecords.set(team.id, emptyStanding(team));
    const div = team.divisionId || 'all';
    if (!divisionRecords.has(div)) divisionRecords.set(div, new Map());
    divisionRecords.get(div).set(team.id, emptyStanding(team));
  }

  for (const game of sortedApprovedGames(gameStats, eventsById)) {
    const homeWon = game.homeScore > game.awayScore;
    const apply = (records) => {
      const home = records.get(game.homeTeamId);
      const away = records.get(game.awayTeamId);
      if (!home || !away) return;
      home.pointsFor += game.homeScore;
      home.pointsAgainst += game.awayScore;
      away.pointsFor += game.awayScore;
      away.pointsAgainst += game.homeScore;
      if (homeWon) {
        home.wins += 1;
        away.losses += 1;
        home.results.push('W');
        away.results.push('L');
      } else {
        away.wins += 1;
        home.losses += 1;
        away.results.push('W');
        home.results.push('L');
      }
      for (const entry of [home, away]) {
        entry.pct = entry.wins + entry.losses ? entry.wins / (entry.wins + entry.losses) : 0;
      }
    };

    const processed = {
      eventId: game.eventId,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
    };

    apply(allRecords);
    processedAll.push(processed);
    if (game.divisionId) {
      apply(divisionRecords.get(game.divisionId));
      if (!processedByDivision.has(game.divisionId)) processedByDivision.set(game.divisionId, []);
      processedByDivision.get(game.divisionId).push(processed);
    }
  }

  const docs = new Map();
  docs.set(`${SEASON_ID}_all`, {
    seasonId: SEASON_ID,
    divisionId: null,
    updatedAt: new Date(),
    standings: finalizeStandings(allRecords),
    processedEvents: processedAll,
  });

  for (const [divisionId, records] of divisionRecords.entries()) {
    docs.set(`${SEASON_ID}_${divisionId}`, {
      seasonId: SEASON_ID,
      divisionId,
      updatedAt: new Date(),
      standings: finalizeStandings(records),
      processedEvents: processedByDivision.get(divisionId) || [],
    });
  }

  return docs;
}

function buildLeaderboards(playerDocs) {
  const categories = [
    ['ppg', 'ppg'],
    ['rpg', 'rpg'],
    ['apg', 'apg'],
    ['spg', 'spg'],
    ['bpg', 'bpg'],
  ];
  const docs = new Map();
  const players = [...playerDocs.values()].filter((player) => player.gamesPlayed >= 1);
  const divisions = new Set(players.map((player) => player.divisionId).filter(Boolean));

  function makeDocs(scopePlayers, divisionId) {
    for (const [category, field] of categories) {
      const rankings = [...scopePlayers]
        .sort((a, b) => (b.averages[field] || 0) - (a.averages[field] || 0))
        .slice(0, 50)
        .map((player) => ({
          playerId: player.playerId,
          name: player.playerName,
          teamName: player.teamName || '',
          value: player.averages[field] || 0,
          gp: player.gamesPlayed,
        }));
      const key = `${SEASON_ID}_${divisionId || 'all'}_${category}`;
      docs.set(key, {
        seasonId: SEASON_ID,
        divisionId: divisionId || null,
        category,
        updatedAt: new Date(),
        rankings,
      });
    }
  }

  makeDocs(players, null);
  for (const divisionId of divisions) {
    makeDocs(players.filter((player) => player.divisionId === divisionId), divisionId);
  }

  return docs;
}

function summarizeBackfill(games) {
  return games.map((game) => ({
    id: game.eventId,
    matchup: `${game.homeTeamName} ${game.homeScore} - ${game.awayScore} ${game.awayTeamName}`,
    divisionId: game.divisionId,
    approvedAt: game.approvedAt.toISOString(),
    players: Object.keys(game.playerLines || {}).length,
  }));
}

async function main() {
  console.log(`${COMMIT ? 'COMMIT' : 'DRY RUN'} pending game stats backfill`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Association: ${ASSOC_ID}`);
  console.log(`Season: ${SEASON_ID}`);
  console.log(`Cutoff: ${NOW.toISOString()}`);

  const base = `associations/${ASSOC_ID}`;
  const [events, existingGameStats, teams, playerSeasonStats, standingsDocs] = await Promise.all([
    listCollection(`${base}/events`),
    listCollection(`${base}/gameStats`),
    listCollection(`${base}/teams`),
    listCollection(`${base}/playerSeasonStats`),
    listCollection(`${base}/standings`),
  ]);

  const eventsById = new Map(events.map((event) => [event.id, event]));
  const statsById = new Map(existingGameStats.map((stats) => [stats.id, stats]));
  const teamsById = new Map(teams.map((team) => [team.id, team]));
  const rosterByTeam = new Map();
  for (const player of playerSeasonStats) {
    if (player.seasonId !== SEASON_ID) continue;
    if (!rosterByTeam.has(player.teamId)) rosterByTeam.set(player.teamId, []);
    rosterByTeam.get(player.teamId).push(player);
  }
  for (const roster of rosterByTeam.values()) {
    roster.sort((a, b) => {
      const bPpg = Number(b.averages?.ppg || b.averages?.pts || 0);
      const aPpg = Number(a.averages?.ppg || a.averages?.pts || 0);
      return bPpg - aPpg || a.playerName.localeCompare(b.playerName);
    });
  }

  const standingsByTeam = new Map();
  for (const doc of standingsDocs) {
    if (doc.id !== `${SEASON_ID}_all`) continue;
    for (const standing of doc.standings || []) {
      standingsByTeam.set(standing.teamId, standing);
    }
  }

  const pendingGames = events
    .filter((event) => event.type === 'game')
    .filter((event) => (event.seasonId || SEASON_ID) === SEASON_ID)
    .filter((event) => parseDate(event.startTime) < NOW)
    .filter((event) => event.statsStatus !== 'approved' || statsById.get(event.id)?.status !== 'approved')
    .filter((event) => !statsById.has(event.id) || statsById.get(event.id)?.status !== 'approved')
    .sort((a, b) => parseDate(a.startTime) - parseDate(b.startTime));

  const generatedGameStats = pendingGames.map((event) =>
    generateGameStats(event, teamsById, rosterByTeam, standingsByTeam)
  );
  const allApprovedStats = [
    ...existingGameStats.filter((stats) => stats.status === 'approved' && stats.seasonId === SEASON_ID),
    ...generatedGameStats,
  ];
  const playerDocs = buildPlayerSeasonStats(allApprovedStats, teamsById, eventsById);
  const teamDocs = buildTeamSeasonStats(allApprovedStats, teamsById, eventsById);
  const standings = buildStandings(allApprovedStats, teamsById, eventsById);
  const leaderboards = buildLeaderboards(playerDocs);

  console.log(`Existing approved gameStats: ${existingGameStats.filter((s) => s.status === 'approved').length}`);
  console.log(`Past pending games selected: ${pendingGames.length}`);
  console.table(summarizeBackfill(generatedGameStats));
  console.log(`Will write gameStats: ${generatedGameStats.length}`);
  console.log(`Will mark events approved: ${pendingGames.length}`);
  console.log(`Will rebuild playerSeasonStats: ${playerDocs.size}`);
  console.log(`Will rebuild teamSeasonStats: ${teamDocs.size}`);
  console.log(`Will rebuild standings docs: ${standings.size}`);
  console.log(`Will rebuild leaderboard docs: ${leaderboards.size}`);

  if (!COMMIT) {
    console.log('Dry run only. Re-run with --commit to write Firestore.');
    return;
  }

  for (const stats of generatedGameStats) {
    await patchDoc(`${base}/gameStats/${stats.eventId}`, stats);
  }
  console.log(`Wrote ${generatedGameStats.length} gameStats docs.`);

  for (const event of pendingGames) {
    await patchDoc(`${base}/events/${event.id}`, { statsStatus: 'approved' }, ['statsStatus']);
  }
  console.log(`Marked ${pendingGames.length} events as approved.`);

  for (const [docId, doc] of playerDocs.entries()) {
    await patchDoc(`${base}/playerSeasonStats/${docId}`, doc);
  }
  console.log(`Rebuilt ${playerDocs.size} playerSeasonStats docs.`);

  for (const [docId, doc] of teamDocs.entries()) {
    await patchDoc(`${base}/teamSeasonStats/${docId}`, doc);
  }
  console.log(`Rebuilt ${teamDocs.size} teamSeasonStats docs.`);

  for (const [docId, doc] of standings.entries()) {
    await patchDoc(`${base}/standings/${docId}`, doc);
  }
  console.log(`Rebuilt ${standings.size} standings docs.`);

  for (const [docId, doc] of leaderboards.entries()) {
    await patchDoc(`${base}/leaderboard/${docId}`, doc);
  }
  console.log(`Rebuilt ${leaderboards.size} leaderboard docs.`);

  console.log('Backfill complete.');
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
