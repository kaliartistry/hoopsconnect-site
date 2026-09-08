#!/usr/bin/env node
// Seed script: Jamaica NBL (National Basketball League)
// Real teams from the 2025-2026 season

const { execSync } = require('child_process');
const https = require('https');
const http = require('http');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

const TARGET = guardFirestoreTarget({mode: 'write'});
const PROJECT_ID = TARGET.projectId;
const BASE_URL = TARGET.baseUrl;
const firestoreTransport = TARGET.isEmulator ? http : https;

function getToken() {
  if (TARGET.isEmulator) return null;
  const os = require('os');
  const fs = require('fs');
  const path = require('path');
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (fs.existsSync(configPath)) {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    if (config.tokens && config.tokens.access_token) {
      return config.tokens.access_token;
    }
  }
  throw new Error('Could not get Firebase auth token. Run: firebase login');
}

function firestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'number' && Number.isInteger(val)) return { integerValue: String(val) };
  if (typeof val === 'number') return { doubleValue: val };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (val instanceof Date) return { timestampValue: val.toISOString() };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(firestoreValue) } };
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = firestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function makeDoc(data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    fields[k] = firestoreValue(v);
  }
  return { fields };
}

async function request(method, path, body) {
  const token = getToken();
  const url = new URL(`${BASE_URL}${path}`);

  return new Promise((resolve, reject) => {
    const options = {
      hostname: url.hostname,
      path: url.pathname + url.search,
      method,
      headers: {
        ...(token ? {'Authorization': `Bearer ${token}`} : {}),
        'Content-Type': 'application/json',
      },
    };

    const req = firestoreTransport.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 400) {
          console.error(`  ⚠ HTTP ${res.statusCode} on ${method} ${path.substring(0, 60)}`);
          resolve(null); // Continue despite errors (doc may already exist)
        } else {
          resolve(JSON.parse(data || '{}'));
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function createDoc(collection, docId, data) {
  const doc = makeDoc(data);
  const path = `/${collection}?documentId=${docId}`;
  return request('POST', path, doc);
}

async function patchDoc(collection, docId, data) {
  const doc = makeDoc(data);
  const path = `/${collection}/${docId}`;
  return request('PATCH', path, doc);
}

async function addDoc(collection, data) {
  const doc = makeDoc(data);
  const result = await request('POST', `/${collection}`, doc);
  if (result && result.name) {
    return result.name.split('/').pop();
  }
  return null;
}

async function seed() {
  console.log('🏀 Seeding Jamaica NBL Data...\n');
  const assocId = 'jba';
  const seasonId = 'spring-2026';

  // ─── 1. Association ───
  await patchDoc('associations', assocId, {
    name: 'Jamaica Basketball Association',
    logoUrl: null,
    currentSeasonId: seasonId,
    createdAt: new Date(),
  });
  console.log('✓ Association updated');

  // ─── 2. Season ───
  await patchDoc(`associations/${assocId}/seasons`, seasonId, {
    name: 'NBL 2025-26',
    startDate: new Date('2025-11-01'),
    endDate: new Date('2026-06-30'),
    isActive: true,
  });
  console.log('✓ Season: NBL 2025-26');

  // ─── 3. Divisions ───
  const divisions = [
    { id: 'nbl-premier', name: 'NBL Premier' },
    { id: 'womens-league', name: "Women's League" },
  ];
  for (const div of divisions) {
    await createDoc(`associations/${assocId}/divisions`, div.id, {
      name: div.name,
      seasonId,
    });
  }
  console.log('✓ 2 divisions created');

  // ─── 4. Teams (real Jamaica NBL teams) ───
  const teams = [
    { id: 'portmore-flames',     name: 'Portmore Flames',             div: 'nbl-premier' },
    { id: 'upper-room-eagles',   name: 'Upper Room Eagles',           div: 'nbl-premier' },
    { id: 'st-georges-slayers',  name: "St George's Slayers",         div: 'nbl-premier' },
    { id: 'urban-knights',       name: 'Urban Knights',               div: 'nbl-premier' },
    { id: 'mobay-warriors',      name: 'Mo Bay Boys Club Warriors',   div: 'nbl-premier' },
    { id: 'runnin-rebels',       name: "Runnin' Rebels",              div: 'nbl-premier' },
    { id: 'rae-town-raptors',    name: 'Rae Town Raptors',            div: 'nbl-premier' },
    { id: 'spanish-town-spartans', name: 'Spanish Town Spartans',     div: 'nbl-premier' },
    { id: 'central-celtics',     name: 'Central Celtics',             div: 'nbl-premier' },
    { id: 'tivoli-wizards',      name: 'Tivoli Wizards All-Stars',    div: 'nbl-premier' },
  ];
  for (const team of teams) {
    await createDoc(`associations/${assocId}/teams`, team.id, {
      name: team.name,
      divisionId: team.div,
      seasonId,
      logoUrl: null,
      repIds: [],
    });
  }
  console.log('✓ 10 NBL teams created');

  // ─── 5. Standings ───
  const standingsData = [
    { teamId: 'portmore-flames',     teamName: 'Portmore Flames',           w: 8, l: 1, streak: 'W5', lastTen: '8-1', pf: 612, pa: 498 },
    { teamId: 'upper-room-eagles',   teamName: 'Upper Room Eagles',         w: 7, l: 2, streak: 'W2', lastTen: '7-2', pf: 589, pa: 510 },
    { teamId: 'st-georges-slayers',  teamName: "St George's Slayers",       w: 7, l: 3, streak: 'L1', lastTen: '6-4', pf: 601, pa: 555 },
    { teamId: 'urban-knights',       teamName: 'Urban Knights',             w: 6, l: 3, streak: 'W1', lastTen: '6-3', pf: 578, pa: 534 },
    { teamId: 'mobay-warriors',      teamName: 'Mo Bay Boys Club Warriors', w: 5, l: 4, streak: 'L2', lastTen: '5-4', pf: 552, pa: 540 },
    { teamId: 'runnin-rebels',       teamName: "Runnin' Rebels",            w: 4, l: 4, streak: 'W1', lastTen: '4-4', pf: 520, pa: 515 },
    { teamId: 'rae-town-raptors',    teamName: 'Rae Town Raptors',          w: 4, l: 5, streak: 'L1', lastTen: '4-5', pf: 510, pa: 530 },
    { teamId: 'spanish-town-spartans', teamName: 'Spanish Town Spartans',   w: 3, l: 7, streak: 'L3', lastTen: '2-7', pf: 488, pa: 562 },
    { teamId: 'central-celtics',     teamName: 'Central Celtics',           w: 1, l: 8, streak: 'L5', lastTen: '1-8', pf: 430, pa: 580 },
    { teamId: 'tivoli-wizards',      teamName: 'Tivoli Wizards All-Stars',  w: 0, l: 9, streak: 'L9', lastTen: '0-9', pf: 398, pa: 610 },
  ];

  // Calculate PCT and GB
  const leader = standingsData[0];
  const leaderPct = leader.w / (leader.w + leader.l);
  const standings = standingsData.map(t => {
    const pct = t.w + t.l > 0 ? t.w / (t.w + t.l) : 0;
    const gb = ((leader.w - leader.l) - (t.w - t.l)) / 2;
    return {
      teamId: t.teamId,
      teamName: t.teamName,
      divisionId: 'nbl-premier',
      wins: t.w,
      losses: t.l,
      pct: Math.round(pct * 1000) / 1000,
      gb,
      streak: t.streak,
      lastTen: t.lastTen,
      pointsFor: t.pf,
      pointsAgainst: t.pa,
    };
  });

  await createDoc(`associations/${assocId}/standings`, `${seasonId}_all`, {
    seasonId,
    divisionId: null,
    updatedAt: new Date(),
    standings,
  });
  await createDoc(`associations/${assocId}/standings`, `${seasonId}_nbl-premier`, {
    seasonId,
    divisionId: 'nbl-premier',
    updatedAt: new Date(),
    standings,
  });
  console.log('✓ Standings created (10 teams)');

  // ─── 6. Games (past + upcoming) ───
  const games = [
    // Completed games (past)
    {
      title: 'Portmore Flames vs Urban Knights',
      type: 'game', statsStatus: 'approved',
      startTime: new Date('2026-02-22T19:00:00'),
      endTime: new Date('2026-02-22T21:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['portmore-flames', 'urban-knights'],
      createdBy: 'system', description: null,
    },
    {
      title: 'Upper Room Eagles vs Rae Town Raptors',
      type: 'game', statsStatus: 'approved',
      startTime: new Date('2026-02-22T21:00:00'),
      endTime: new Date('2026-02-22T23:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['upper-room-eagles', 'rae-town-raptors'],
      createdBy: 'system', description: null,
    },
    {
      title: "St George's Slayers vs Runnin' Rebels",
      type: 'game', statsStatus: 'approved',
      startTime: new Date('2026-02-25T19:00:00'),
      endTime: new Date('2026-02-25T21:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['st-georges-slayers', 'runnin-rebels'],
      createdBy: 'system', description: null,
    },
    // Games needing stats
    {
      title: 'Mo Bay Warriors vs Spanish Town Spartans',
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-02-27T19:00:00'),
      endTime: new Date('2026-02-27T21:00:00'),
      location: 'Catherine Hall, Montego Bay',
      divisionId: 'nbl-premier',
      teamIds: ['mobay-warriors', 'spanish-town-spartans'],
      createdBy: 'system', description: null,
    },
    // Upcoming games
    {
      title: 'Portmore Flames vs Upper Room Eagles',
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-01T19:00:00'),
      endTime: new Date('2026-03-01T21:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['portmore-flames', 'upper-room-eagles'],
      createdBy: 'system', description: null,
    },
    {
      title: "Urban Knights vs St George's Slayers",
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-01T21:00:00'),
      endTime: new Date('2026-03-01T23:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['urban-knights', 'st-georges-slayers'],
      createdBy: 'system', description: null,
    },
    {
      title: "Runnin' Rebels vs Rae Town Raptors",
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-04T19:00:00'),
      endTime: new Date('2026-03-04T21:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['runnin-rebels', 'rae-town-raptors'],
      createdBy: 'system', description: null,
    },
    {
      title: 'Central Celtics vs Tivoli Wizards All-Stars',
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-04T21:00:00'),
      endTime: new Date('2026-03-04T23:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: 'nbl-premier',
      teamIds: ['central-celtics', 'tivoli-wizards'],
      createdBy: 'system', description: null,
    },
    {
      title: 'Spanish Town Spartans vs Portmore Flames',
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-08T17:00:00'),
      endTime: new Date('2026-03-08T19:00:00'),
      location: 'Spanish Town Civic Centre',
      divisionId: 'nbl-premier',
      teamIds: ['spanish-town-spartans', 'portmore-flames'],
      createdBy: 'system', description: null,
    },
    {
      title: 'Mo Bay Warriors vs Urban Knights',
      type: 'game', statsStatus: 'pending',
      startTime: new Date('2026-03-08T19:00:00'),
      endTime: new Date('2026-03-08T21:00:00'),
      location: 'Catherine Hall, Montego Bay',
      divisionId: 'nbl-premier',
      teamIds: ['mobay-warriors', 'urban-knights'],
      createdBy: 'system', description: null,
    },
    // Non-game events
    {
      title: 'Roster Lock Deadline',
      type: 'deadline', statsStatus: 'pending',
      startTime: new Date('2026-03-15T23:59:00'),
      endTime: null,
      location: null, divisionId: null, teamIds: [],
      createdBy: 'system', description: 'All NBL team rosters must be finalized',
    },
    {
      title: 'NBL All-Star Weekend',
      type: 'meeting', statsStatus: 'pending',
      startTime: new Date('2026-04-11T14:00:00'),
      endTime: new Date('2026-04-12T22:00:00'),
      location: 'National Indoor Sports Centre',
      divisionId: null, teamIds: [],
      createdBy: 'system', description: 'Skills challenge, 3-point contest, and All-Star game',
    },
  ];

  const gameIds = [];
  for (const game of games) {
    const id = await addDoc(`associations/${assocId}/events`, game);
    gameIds.push(id);
  }
  console.log(`✓ ${games.length} events created (3 completed, ${games.length - 3} upcoming/other)`);

  // ─── 7. Game Stats for completed games ───
  // Game 1: Portmore Flames 78 vs Urban Knights 71
  if (gameIds[0]) {
    await createDoc(`associations/${assocId}/gameStats`, gameIds[0], {
      eventId: gameIds[0],
      seasonId,
      divisionId: 'nbl-premier',
      homeTeamId: 'portmore-flames',
      awayTeamId: 'urban-knights',
      homeTeamName: 'Portmore Flames',
      awayTeamName: 'Urban Knights',
      homeScore: 78,
      awayScore: 71,
      status: 'approved',
      submittedBy: 'system',
      submittedAt: new Date('2026-02-22T21:10:00'),
      approvedBy: 'system',
      approvedAt: new Date('2026-02-22T21:15:00'),
      playerLines: {
        // Portmore Flames
        'pf-1': { name: 'Ricardo Thompson', teamId: 'portmore-flames', pts: 22, reb: 8, ast: 3, stl: 2, blk: 1, fls: 2, min: 34 },
        'pf-2': { name: 'Andre Mitchell', teamId: 'portmore-flames', pts: 18, reb: 5, ast: 6, stl: 1, blk: 0, fls: 3, min: 32 },
        'pf-3': { name: 'Kevin Richards', teamId: 'portmore-flames', pts: 14, reb: 3, ast: 2, stl: 3, blk: 0, fls: 1, min: 28 },
        'pf-4': { name: 'Damion Stewart', teamId: 'portmore-flames', pts: 12, reb: 10, ast: 1, stl: 0, blk: 3, fls: 4, min: 30 },
        'pf-5': { name: 'Marcus Brown', teamId: 'portmore-flames', pts: 8, reb: 2, ast: 4, stl: 1, blk: 0, fls: 2, min: 26 },
        'pf-6': { name: 'Troy Williams', teamId: 'portmore-flames', pts: 4, reb: 3, ast: 1, stl: 0, blk: 0, fls: 1, min: 18 },
        // Urban Knights
        'uk-1': { name: 'Nicholai Brown', teamId: 'urban-knights', pts: 24, reb: 6, ast: 2, stl: 1, blk: 0, fls: 3, min: 36 },
        'uk-2': { name: 'Ramone Spence', teamId: 'urban-knights', pts: 18, reb: 9, ast: 3, stl: 0, blk: 2, fls: 4, min: 34 },
        'uk-3': { name: "D'Andre Forbes", teamId: 'urban-knights', pts: 12, reb: 2, ast: 5, stl: 3, blk: 0, fls: 2, min: 30 },
        'uk-4': { name: 'Jermaine Brown', teamId: 'urban-knights', pts: 10, reb: 4, ast: 4, stl: 2, blk: 0, fls: 1, min: 28 },
        'uk-5': { name: 'Shavair Francis', teamId: 'urban-knights', pts: 5, reb: 7, ast: 0, stl: 0, blk: 3, fls: 3, min: 24 },
        'uk-6': { name: 'Tyrese Campbell', teamId: 'urban-knights', pts: 2, reb: 1, ast: 1, stl: 1, blk: 0, fls: 2, min: 12 },
      },
    });
    console.log('✓ Box score: Portmore 78 - Urban Knights 71');
  }

  // Game 2: Upper Room Eagles 85 vs Rae Town Raptors 68
  if (gameIds[1]) {
    await createDoc(`associations/${assocId}/gameStats`, gameIds[1], {
      eventId: gameIds[1],
      seasonId,
      divisionId: 'nbl-premier',
      homeTeamId: 'upper-room-eagles',
      awayTeamId: 'rae-town-raptors',
      homeTeamName: 'Upper Room Eagles',
      awayTeamName: 'Rae Town Raptors',
      homeScore: 85,
      awayScore: 68,
      status: 'approved',
      submittedBy: 'system',
      submittedAt: new Date('2026-02-22T23:10:00'),
      approvedBy: 'system',
      approvedAt: new Date('2026-02-22T23:15:00'),
      playerLines: {
        // Upper Room Eagles
        'ure-1': { name: 'Omar Barnes', teamId: 'upper-room-eagles', pts: 26, reb: 7, ast: 4, stl: 2, blk: 1, fls: 2, min: 35 },
        'ure-2': { name: 'Juvane Carthy', teamId: 'upper-room-eagles', pts: 20, reb: 4, ast: 7, stl: 3, blk: 0, fls: 1, min: 33 },
        'ure-3': { name: 'Kavon Williams', teamId: 'upper-room-eagles', pts: 15, reb: 8, ast: 1, stl: 0, blk: 2, fls: 3, min: 30 },
        'ure-4': { name: 'Rashane Blake', teamId: 'upper-room-eagles', pts: 12, reb: 3, ast: 3, stl: 1, blk: 0, fls: 2, min: 26 },
        'ure-5': { name: 'Devon Clarke', teamId: 'upper-room-eagles', pts: 8, reb: 5, ast: 2, stl: 0, blk: 1, fls: 4, min: 28 },
        'ure-6': { name: 'Tyrell Grant', teamId: 'upper-room-eagles', pts: 4, reb: 1, ast: 0, stl: 1, blk: 0, fls: 1, min: 14 },
        // Rae Town Raptors
        'rtr-1': { name: 'Marlon Davis', teamId: 'rae-town-raptors', pts: 20, reb: 5, ast: 3, stl: 1, blk: 0, fls: 3, min: 34 },
        'rtr-2': { name: 'Shane Patterson', teamId: 'rae-town-raptors', pts: 16, reb: 6, ast: 2, stl: 2, blk: 1, fls: 2, min: 32 },
        'rtr-3': { name: 'Kadeem Powell', teamId: 'rae-town-raptors', pts: 14, reb: 4, ast: 4, stl: 0, blk: 0, fls: 1, min: 28 },
        'rtr-4': { name: 'Rohan Stephens', teamId: 'rae-town-raptors', pts: 10, reb: 3, ast: 1, stl: 1, blk: 0, fls: 4, min: 24 },
        'rtr-5': { name: 'Dwayne Morgan', teamId: 'rae-town-raptors', pts: 6, reb: 8, ast: 0, stl: 0, blk: 2, fls: 3, min: 26 },
        'rtr-6': { name: 'Jason Henry', teamId: 'rae-town-raptors', pts: 2, reb: 1, ast: 2, stl: 0, blk: 0, fls: 1, min: 10 },
      },
    });
    console.log('✓ Box score: Eagles 85 - Raptors 68');
  }

  // Game 3: Slayers 63 vs Rebels 45
  if (gameIds[2]) {
    await createDoc(`associations/${assocId}/gameStats`, gameIds[2], {
      eventId: gameIds[2],
      seasonId,
      divisionId: 'nbl-premier',
      homeTeamId: 'st-georges-slayers',
      awayTeamId: 'runnin-rebels',
      homeTeamName: "St George's Slayers",
      awayTeamName: "Runnin' Rebels",
      homeScore: 63,
      awayScore: 45,
      status: 'approved',
      submittedBy: 'system',
      submittedAt: new Date('2026-02-25T21:10:00'),
      approvedBy: 'system',
      approvedAt: new Date('2026-02-25T21:15:00'),
      playerLines: {
        // Slayers
        'sgs-1': { name: 'Brandon Taylor', teamId: 'st-georges-slayers', pts: 18, reb: 5, ast: 4, stl: 2, blk: 0, fls: 2, min: 32 },
        'sgs-2': { name: 'Akeem Wright', teamId: 'st-georges-slayers', pts: 15, reb: 7, ast: 2, stl: 1, blk: 2, fls: 3, min: 30 },
        'sgs-3': { name: 'Ryan Campbell', teamId: 'st-georges-slayers', pts: 12, reb: 3, ast: 5, stl: 3, blk: 0, fls: 1, min: 28 },
        'sgs-4': { name: 'Jerome Ellis', teamId: 'st-georges-slayers', pts: 10, reb: 6, ast: 1, stl: 0, blk: 1, fls: 4, min: 26 },
        'sgs-5': { name: 'Donovan Lee', teamId: 'st-georges-slayers', pts: 8, reb: 2, ast: 3, stl: 1, blk: 0, fls: 2, min: 22 },
        // Rebels
        'rr-1': { name: 'Corey Edwards', teamId: 'runnin-rebels', pts: 14, reb: 4, ast: 2, stl: 1, blk: 0, fls: 3, min: 30 },
        'rr-2': { name: 'Javon Sinclair', teamId: 'runnin-rebels', pts: 11, reb: 5, ast: 3, stl: 0, blk: 1, fls: 2, min: 28 },
        'rr-3': { name: 'Romario Johnson', teamId: 'runnin-rebels', pts: 8, reb: 3, ast: 1, stl: 2, blk: 0, fls: 4, min: 24 },
        'rr-4': { name: 'Kemar Wallace', teamId: 'runnin-rebels', pts: 7, reb: 6, ast: 0, stl: 0, blk: 2, fls: 3, min: 26 },
        'rr-5': { name: 'Tristan Reid', teamId: 'runnin-rebels', pts: 5, reb: 2, ast: 4, stl: 1, blk: 0, fls: 1, min: 20 },
      },
    });
    console.log('✓ Box score: Slayers 63 - Rebels 45');
  }

  // ─── 8. Leaderboard (top scorers) ───
  const leaderboardEntries = [
    { playerId: 'ure-omar-barnes',     name: 'Omar Barnes',       teamName: 'Upper Room Eagles',  gp: 9, ppg: 22.3, rpg: 6.1, apg: 3.8 },
    { playerId: 'uk-nicholai-brown',   name: 'Nicholai Brown',    teamName: 'Urban Knights',      gp: 9, ppg: 21.5, rpg: 5.8, apg: 2.1 },
    { playerId: 'pf-ricardo-thompson', name: 'Ricardo Thompson',  teamName: 'Portmore Flames',    gp: 9, ppg: 20.8, rpg: 7.4, apg: 2.9 },
    { playerId: 'uk-ramone-spence',    name: 'Ramone Spence',     teamName: 'Urban Knights',      gp: 9, ppg: 19.2, rpg: 8.6, apg: 2.4 },
    { playerId: 'ure-juvane-carthy',   name: 'Juvane Carthy',     teamName: 'Upper Room Eagles',  gp: 9, ppg: 18.5, rpg: 3.2, apg: 6.5 },
    { playerId: 'sgs-brandon-taylor',  name: 'Brandon Taylor',    teamName: "St George's Slayers",gp: 10, ppg: 17.8, rpg: 4.9, apg: 3.6 },
    { playerId: 'pf-andre-mitchell',   name: 'Andre Mitchell',    teamName: 'Portmore Flames',    gp: 9, ppg: 17.2, rpg: 4.1, apg: 5.8 },
    { playerId: 'rtr-marlon-davis',    name: 'Marlon Davis',      teamName: 'Rae Town Raptors',   gp: 9, ppg: 16.9, rpg: 5.3, apg: 2.7 },
    { playerId: 'uk-dandre-forbes',    name: "D'Andre Forbes",    teamName: 'Urban Knights',      gp: 9, ppg: 15.4, rpg: 2.5, apg: 5.2 },
    { playerId: 'mbw-garfield-scott',  name: 'Garfield Scott',    teamName: 'Mo Bay Warriors',    gp: 9, ppg: 14.8, rpg: 3.8, apg: 4.1 },
  ];

  // Points per game leaderboard
  await createDoc(`associations/${assocId}/leaderboard`, `${seasonId}_null_ppg`, {
    seasonId,
    divisionId: null,
    category: 'ppg',
    updatedAt: new Date(),
    rankings: leaderboardEntries.map(e => ({
      playerId: e.playerId, name: e.name, teamName: e.teamName, gp: e.gp, value: e.ppg,
    })),
  });

  // Rebounds per game
  const rpgSorted = [...leaderboardEntries].sort((a, b) => b.rpg - a.rpg);
  await createDoc(`associations/${assocId}/leaderboard`, `${seasonId}_null_rpg`, {
    seasonId,
    divisionId: null,
    category: 'rpg',
    updatedAt: new Date(),
    rankings: rpgSorted.map(e => ({
      playerId: e.playerId, name: e.name, teamName: e.teamName, gp: e.gp, value: e.rpg,
    })),
  });

  // Assists per game
  const apgSorted = [...leaderboardEntries].sort((a, b) => b.apg - a.apg);
  await createDoc(`associations/${assocId}/leaderboard`, `${seasonId}_null_apg`, {
    seasonId,
    divisionId: null,
    category: 'apg',
    updatedAt: new Date(),
    rankings: apgSorted.map(e => ({
      playerId: e.playerId, name: e.name, teamName: e.teamName, gp: e.gp, value: e.apg,
    })),
  });
  console.log('✓ Leaderboards created (PPG, RPG, APG)');

  // ─── 9. Posts ───
  const posts = [
    {
      authorId: 'system', authorName: 'JBA Commissioner', authorRole: 'superAdmin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'NBL 2025-26 Season — Week 5 Schedule Released',
      body: 'Week 5 games have been finalized. Highlight: Portmore Flames vs Upper Room Eagles on Saturday March 1st at the National Indoor Sports Centre. Gates open at 6pm. All games broadcast live on JBA social media.',
      imageUrl: null, divisionFilter: null, pinned: true, urgent: false,
      createdAt: new Date('2026-02-26T10:00:00'), reactions: {}, requiresAck: false,
      ackDeadline: null, ackTargetScope: null,
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'JBA Commissioner', authorRole: 'superAdmin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'Roster Lock Deadline — March 15',
      body: 'All NBL team rosters must be finalized by March 15, 2026. No player additions or transfers after this date. Team reps must confirm their final 15-man roster through the app.',
      imageUrl: null, divisionFilter: null, pinned: true, urgent: true,
      createdAt: new Date('2026-02-25T08:00:00'), reactions: {}, requiresAck: true,
      ackDeadline: new Date('2026-03-14T23:59:00'), ackTargetScope: 'all',
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'JBA Commissioner', authorRole: 'superAdmin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'Venue Change: Mo Bay Warriors Home Games',
      body: 'Due to renovations at Catherine Hall, all Mo Bay Boys Club Warriors home games from March 8-22 will be played at Montego Bay High School gymnasium. Parking available on site.',
      imageUrl: null, divisionFilter: 'NBL Premier', pinned: false, urgent: true,
      createdAt: new Date('2026-02-27T14:00:00'), reactions: {}, requiresAck: true,
      ackDeadline: new Date('2026-03-06T18:00:00'), ackTargetScope: 'all',
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'Coach Thompson', authorRole: 'rep',
      teamId: 'portmore-flames', teamName: 'Portmore Flames', type: 'announcement',
      title: 'Practice Schedule Update',
      body: 'Practice moved to Tuesday/Thursday 6-8pm at Portmore Community Centre for the rest of the month. Saturday morning shootaround still 8am at the usual spot.',
      imageUrl: null, divisionFilter: 'NBL Premier', pinned: false, urgent: false,
      createdAt: new Date('2026-02-27T09:00:00'), reactions: {}, requiresAck: false,
      ackDeadline: null, ackTargetScope: null,
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'JBA Media', authorRole: 'admin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'Player of the Week: Omar Barnes (Upper Room Eagles)',
      body: 'Congratulations to Omar Barnes for earning NBL Player of the Week! Barnes averaged 26 points, 7 rebounds, and 4 assists in two wins for the Eagles. Big performance against Rae Town Raptors with 26-7-4 line.',
      imageUrl: null, divisionFilter: null, pinned: false, urgent: false,
      createdAt: new Date('2026-02-24T12:00:00'), reactions: {}, requiresAck: false,
      ackDeadline: null, ackTargetScope: null,
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
  ];
  for (const post of posts) {
    await addDoc(`associations/${assocId}/posts`, post);
  }
  console.log(`✓ ${posts.length} posts created`);

  // ─── 10. Invite Codes ───
  const inviteCodes = [
    { code: 'FLAMES-2026',   teamId: 'portmore-flames',    role: 'rep',   usesRemaining: 5 },
    { code: 'EAGLES-2026',   teamId: 'upper-room-eagles',  role: 'rep',   usesRemaining: 5 },
    { code: 'KNIGHTS-2026',  teamId: 'urban-knights',      role: 'rep',   usesRemaining: 5 },
    { code: 'SLAYERS-2026',  teamId: 'st-georges-slayers', role: 'rep',   usesRemaining: 5 },
    { code: 'WARRIORS-2026', teamId: 'mobay-warriors',      role: 'rep',   usesRemaining: 5 },
    { code: 'REBELS-2026',   teamId: 'runnin-rebels',       role: 'rep',   usesRemaining: 5 },
    { code: 'RAPTORS-2026',  teamId: 'rae-town-raptors',    role: 'rep',   usesRemaining: 5 },
    { code: 'SPARTANS-2026', teamId: 'spanish-town-spartans', role: 'rep', usesRemaining: 5 },
    { code: 'CELTICS-2026',  teamId: 'central-celtics',     role: 'rep',   usesRemaining: 5 },
    { code: 'WIZARDS-2026',  teamId: 'tivoli-wizards',      role: 'rep',   usesRemaining: 5 },
    { code: 'NBL-MEDIA',     teamId: '',                     role: 'media', usesRemaining: 10 },
    { code: 'NBL-ADMIN',     teamId: '',                     role: 'admin', usesRemaining: 3 },
    { code: 'NBL-SUPER',     teamId: '',                     role: 'superAdmin', usesRemaining: 1 },
  ];
  for (const ic of inviteCodes) {
    await createDoc('inviteCodes', ic.code, {
      teamId: ic.teamId,
      role: ic.role,
      usesRemaining: ic.usesRemaining,
      expiresAt: new Date('2026-12-31'),
      associationId: 'jba',
    });
  }
  console.log(`✓ ${inviteCodes.length} invite codes created`);

  // ─── Done ───
  console.log('\n🏀 Jamaica NBL seed complete!\n');
  console.log('═══════════════════════════════════════════');
  console.log('  INVITE CODES');
  console.log('═══════════════════════════════════════════');
  console.log('  FLAMES-2026    → Portmore Flames (rep)');
  console.log('  EAGLES-2026    → Upper Room Eagles (rep)');
  console.log('  KNIGHTS-2026   → Urban Knights (rep)');
  console.log('  SLAYERS-2026   → St George\'s Slayers (rep)');
  console.log('  WARRIORS-2026  → Mo Bay Warriors (rep)');
  console.log('  REBELS-2026    → Runnin\' Rebels (rep)');
  console.log('  RAPTORS-2026   → Rae Town Raptors (rep)');
  console.log('  SPARTANS-2026  → Spanish Town Spartans (rep)');
  console.log('  CELTICS-2026   → Central Celtics (rep)');
  console.log('  WIZARDS-2026   → Tivoli Wizards (rep)');
  console.log('  NBL-MEDIA      → Media role');
  console.log('  NBL-ADMIN      → Admin role');
  console.log('  NBL-SUPER      → Super Admin role');
  console.log('═══════════════════════════════════════════');
  console.log('\n  To become superAdmin: use code NBL-SUPER');
  console.log('  Or set role to "superAdmin" in Firebase Console');
}

seed().catch(err => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
