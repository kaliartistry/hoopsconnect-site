#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────
// Seed: Full NBL 2025-26 season — 42 remaining completed games
// Run AFTER seed_nbl.js (which creates teams, 3 games, etc.)
//
// This script:
//  1. Creates 42 completed game events (the rest of the single RR)
//  2. Creates gameStats (box scores) for each
//  3. Creates playerSeasonStats for every player
//  4. Updates standings & leaderboards
// ─────────────────────────────────────────────────────────────────────

const https = require('https');
const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

const TARGET = guardFirestoreTarget({mode: 'write'});
const PROJECT_ID = TARGET.projectId;
const BASE_URL = TARGET.baseUrl;
const firestoreTransport = TARGET.isEmulator ? http : https;

// ── Firebase helpers (same as seed_nbl.js) ──────────────────────────

let _cachedToken = null;

async function getToken() {
  if (TARGET.isEmulator) return null;
  if (_cachedToken) return _cachedToken;

  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(configPath)) throw new Error('No Firebase config. Run: firebase login');

  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  if (!config.tokens || !config.tokens.refresh_token) {
    throw new Error('No refresh token. Run: firebase login');
  }

  // Use refresh token to get a fresh access token
  const postData = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: config.tokens.refresh_token,
    client_id: config.tokens.client_id || '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
    client_secret: config.tokens.client_secret || 'j9iVZfS8kkCEFUPaAeJV0sAi',
  }).toString();

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`Token refresh failed: ${data}`));
          return;
        }
        const result = JSON.parse(data);
        _cachedToken = result.access_token;
        resolve(_cachedToken);
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
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
    for (const [k, v] of Object.entries(val)) fields[k] = firestoreValue(v);
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function makeDoc(data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) fields[k] = firestoreValue(v);
  return { fields };
}

async function request(method, urlPath, body) {
  const token = await getToken();
  const url = new URL(`${BASE_URL}${urlPath}`);
  return new Promise((resolve, reject) => {
    const options = {
      hostname: url.hostname, port: url.port, path: url.pathname + url.search, method,
      headers: {
        ...(token ? {'Authorization': `Bearer ${token}`} : {}),
        'Content-Type': 'application/json',
      },
    };
    const req = firestoreTransport.request(options, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 400) { console.error(`  ⚠ ${res.statusCode} ${method} ${urlPath.substring(0, 80)}`); resolve(null); }
        else resolve(JSON.parse(data || '{}'));
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function addDoc(collection, data) {
  const result = await request('POST', `/${collection}`, makeDoc(data));
  return result?.name?.split('/').pop() ?? null;
}
async function createDoc(collection, docId, data) {
  return request('POST', `/${collection}?documentId=${docId}`, makeDoc(data));
}
async function patchDoc(collection, docId, data) {
  return request('PATCH', `/${collection}/${docId}`, makeDoc(data));
}

// ── Team data ───────────────────────────────────────────────────────

const ASSOC = 'jba';
const SEASON = 'spring-2026';

const TEAMS = {
  'portmore-flames':       { name: 'Portmore Flames',           strength: 0.88 },
  'upper-room-eagles':     { name: 'Upper Room Eagles',         strength: 0.82 },
  'st-georges-slayers':    { name: "St George's Slayers",       strength: 0.78 },
  'urban-knights':         { name: 'Urban Knights',             strength: 0.72 },
  'mobay-warriors':        { name: 'Mo Bay Boys Club Warriors', strength: 0.60 },
  'runnin-rebels':         { name: "Runnin' Rebels",            strength: 0.50 },
  'rae-town-raptors':      { name: 'Rae Town Raptors',          strength: 0.48 },
  'spanish-town-spartans': { name: 'Spanish Town Spartans',     strength: 0.38 },
  'central-celtics':       { name: 'Central Celtics',           strength: 0.22 },
  'tivoli-wizards':        { name: 'Tivoli Wizards All-Stars',  strength: 0.12 },
};

// Full 8-player rosters per team  [playerId, name, skillTier (1=star, 2=starter, 3=bench)]
const ROSTERS = {
  'portmore-flames': [
    ['pf-1', 'Ricardo Thompson', 1], ['pf-2', 'Andre Mitchell', 1],
    ['pf-3', 'Kevin Richards', 2],   ['pf-4', 'Damion Stewart', 2],
    ['pf-5', 'Marcus Brown', 2],     ['pf-6', 'Troy Williams', 3],
    ['pf-7', 'Levar Brown', 3],      ['pf-8', 'Javaughn Simpson', 3],
  ],
  'upper-room-eagles': [
    ['ure-1', 'Omar Barnes', 1],     ['ure-2', 'Juvane Carthy', 1],
    ['ure-3', 'Kavon Williams', 2],  ['ure-4', 'Rashane Blake', 2],
    ['ure-5', 'Devon Clarke', 2],    ['ure-6', 'Tyrell Grant', 3],
    ['ure-7', 'Michael Green', 3],   ['ure-8', 'Kemar Thomas', 3],
  ],
  'st-georges-slayers': [
    ['sgs-1', 'Brandon Taylor', 1],  ['sgs-2', 'Akeem Wright', 1],
    ['sgs-3', 'Ryan Campbell', 2],   ['sgs-4', 'Jerome Ellis', 2],
    ['sgs-5', 'Donovan Lee', 2],     ['sgs-6', 'Shamar Nelson', 3],
    ['sgs-7', 'Keron Bailey', 3],    ['sgs-8', 'Carlton James', 3],
  ],
  'urban-knights': [
    ['uk-1', 'Nicholai Brown', 1],   ['uk-2', 'Ramone Spence', 1],
    ['uk-3', "D'Andre Forbes", 2],   ['uk-4', 'Jermaine Brown', 2],
    ['uk-5', 'Shavair Francis', 2],  ['uk-6', 'Tyrese Campbell', 3],
    ['uk-7', 'Devon Powell', 3],     ['uk-8', 'Ashanti Murray', 3],
  ],
  'mobay-warriors': [
    ['mbw-1', 'Garfield Scott', 1],  ['mbw-2', 'Desmond Bryan', 1],
    ['mbw-3', 'Akeem Simpson', 2],   ['mbw-4', 'Rasheed Clarke', 2],
    ['mbw-5', 'Joel Thompson', 2],   ['mbw-6', 'Travis Brown', 3],
    ['mbw-7', 'Damian Gordon', 3],   ['mbw-8', 'Miguel Lewis', 3],
  ],
  'runnin-rebels': [
    ['rr-1', 'Corey Edwards', 1],    ['rr-2', 'Javon Sinclair', 1],
    ['rr-3', 'Romario Johnson', 2],  ['rr-4', 'Kemar Wallace', 2],
    ['rr-5', 'Tristan Reid', 2],     ['rr-6', 'Orlando Smith', 3],
    ['rr-7', 'Nathan Graham', 3],    ['rr-8', 'Andre Williams', 3],
  ],
  'rae-town-raptors': [
    ['rtr-1', 'Marlon Davis', 1],    ['rtr-2', 'Shane Patterson', 1],
    ['rtr-3', 'Kadeem Powell', 2],   ['rtr-4', 'Rohan Stephens', 2],
    ['rtr-5', 'Dwayne Morgan', 2],   ['rtr-6', 'Jason Henry', 3],
    ['rtr-7', 'Carlton Hewitt', 3],  ['rtr-8', 'Tavares Lynch', 3],
  ],
  'spanish-town-spartans': [
    ['sts-1', 'Daniel Maxwell', 1],  ['sts-2', 'Shayne Foster', 1],
    ['sts-3', 'Romaine Mitchell', 2],['sts-4', 'Troy Anderson', 2],
    ['sts-5', 'Keshawn Harris', 2],  ['sts-6', 'Patrick Davis', 3],
    ['sts-7', 'Andre Thomas', 3],    ['sts-8', 'Mario Clarke', 3],
  ],
  'central-celtics': [
    ['cc-1', 'Dillon Burke', 1],     ['cc-2', 'Gareth Williams', 1],
    ['cc-3', 'Marvin Small', 2],     ['cc-4', 'Stefan Nelson', 2],
    ['cc-5', 'Christopher Grant', 2],['cc-6', 'Kenroy James', 3],
    ['cc-7', 'Ryan Morris', 3],      ['cc-8', 'Tyrone Campbell', 3],
  ],
  'tivoli-wizards': [
    ['tw-1', 'Javon Palmer', 1],     ['tw-2', 'Dexter Reid', 1],
    ['tw-3', 'Samuel Gordon', 2],    ['tw-4', 'Kenard Francis', 2],
    ['tw-5', 'Terrence Blake', 2],   ['tw-6', 'Ahmad Wilson', 3],
    ['tw-7', 'Darren Lewis', 3],     ['tw-8', 'Stefan Harris', 3],
  ],
};

// ── Predefined matchup results (single round-robin) ────────────────
// Each entry: [homeTeamId, awayTeamId, winnerId]
// 3 existing games are marked 'EXISTING' and skipped for event creation
// but their stats are included in season aggregates.

const ALL_MATCHUPS = [
  // POR matchups
  ['portmore-flames', 'upper-room-eagles',     'upper-room-eagles',   'NEW'],
  ['portmore-flames', 'st-georges-slayers',    'portmore-flames',     'NEW'],
  ['portmore-flames', 'urban-knights',         'portmore-flames',     'EXISTING'], // Game 1
  ['portmore-flames', 'mobay-warriors',        'portmore-flames',     'NEW'],
  ['portmore-flames', 'runnin-rebels',         'portmore-flames',     'NEW'],
  ['portmore-flames', 'rae-town-raptors',      'portmore-flames',     'NEW'],
  ['portmore-flames', 'spanish-town-spartans', 'portmore-flames',     'NEW'],
  ['portmore-flames', 'central-celtics',       'portmore-flames',     'NEW'],
  ['portmore-flames', 'tivoli-wizards',        'portmore-flames',     'NEW'],
  // EAG matchups (POR already done)
  ['upper-room-eagles', 'st-georges-slayers',  'st-georges-slayers',  'NEW'],
  ['upper-room-eagles', 'urban-knights',       'urban-knights',       'NEW'],
  ['upper-room-eagles', 'mobay-warriors',      'upper-room-eagles',   'NEW'],
  ['upper-room-eagles', 'runnin-rebels',       'upper-room-eagles',   'NEW'],
  ['upper-room-eagles', 'rae-town-raptors',    'upper-room-eagles',   'EXISTING'], // Game 2
  ['upper-room-eagles', 'spanish-town-spartans','upper-room-eagles',  'NEW'],
  ['upper-room-eagles', 'central-celtics',     'upper-room-eagles',   'NEW'],
  ['upper-room-eagles', 'tivoli-wizards',      'upper-room-eagles',   'NEW'],
  // SLA matchups
  ['st-georges-slayers', 'urban-knights',      'st-georges-slayers',  'NEW'],
  ['st-georges-slayers', 'mobay-warriors',     'mobay-warriors',      'NEW'],
  ['st-georges-slayers', 'runnin-rebels',      'st-georges-slayers',  'EXISTING'], // Game 3
  ['st-georges-slayers', 'rae-town-raptors',   'st-georges-slayers',  'NEW'],
  ['st-georges-slayers', 'spanish-town-spartans','st-georges-slayers','NEW'],
  ['st-georges-slayers', 'central-celtics',    'st-georges-slayers',  'NEW'],
  ['st-georges-slayers', 'tivoli-wizards',     'st-georges-slayers',  'NEW'],
  // KNI matchups
  ['urban-knights', 'mobay-warriors',          'urban-knights',       'NEW'],
  ['urban-knights', 'runnin-rebels',           'runnin-rebels',       'NEW'],
  ['urban-knights', 'rae-town-raptors',        'urban-knights',       'NEW'],
  ['urban-knights', 'spanish-town-spartans',   'urban-knights',       'NEW'],
  ['urban-knights', 'central-celtics',         'urban-knights',       'NEW'],
  ['urban-knights', 'tivoli-wizards',          'urban-knights',       'NEW'],
  // MOB matchups
  ['mobay-warriors', 'runnin-rebels',          'runnin-rebels',       'NEW'],
  ['mobay-warriors', 'rae-town-raptors',       'mobay-warriors',      'NEW'],
  ['mobay-warriors', 'spanish-town-spartans',  'mobay-warriors',      'NEW'],
  ['mobay-warriors', 'central-celtics',        'mobay-warriors',      'NEW'],
  ['mobay-warriors', 'tivoli-wizards',         'mobay-warriors',      'NEW'],
  // REB matchups
  ['runnin-rebels', 'rae-town-raptors',        'rae-town-raptors',    'NEW'],
  ['runnin-rebels', 'spanish-town-spartans',   'spanish-town-spartans','NEW'],
  ['runnin-rebels', 'central-celtics',         'runnin-rebels',       'NEW'],
  ['runnin-rebels', 'tivoli-wizards',          'runnin-rebels',       'NEW'],
  // RAP matchups
  ['rae-town-raptors', 'spanish-town-spartans','rae-town-raptors',   'NEW'],
  ['rae-town-raptors', 'central-celtics',      'rae-town-raptors',   'NEW'],
  ['rae-town-raptors', 'tivoli-wizards',       'rae-town-raptors',   'NEW'],
  // SPA matchups
  ['spanish-town-spartans', 'central-celtics', 'spanish-town-spartans','NEW'],
  ['spanish-town-spartans', 'tivoli-wizards',  'spanish-town-spartans','NEW'],
  // CEL vs WIZ
  ['central-celtics', 'tivoli-wizards',        'central-celtics',     'NEW'],
];

// ── Venues ──────────────────────────────────────────────────────────

const VENUES = {
  'portmore-flames':       'Portmore HEART Academy',
  'upper-room-eagles':     'National Indoor Sports Centre',
  'st-georges-slayers':    'National Indoor Sports Centre',
  'urban-knights':         'National Arena, Kingston',
  'mobay-warriors':        'Catherine Hall, Montego Bay',
  'runnin-rebels':         'National Indoor Sports Centre',
  'rae-town-raptors':      'National Indoor Sports Centre',
  'spanish-town-spartans': 'GC Foster College, Spanish Town',
  'central-celtics':       'National Indoor Sports Centre',
  'tivoli-wizards':        'Tivoli Gardens Community Centre',
};

// ── Score & stat generation ─────────────────────────────────────────

function rand(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function generateScore(winnerStrength, loserStrength) {
  const diff = winnerStrength - loserStrength;
  // Winner score: 58-88 depending on strength
  const winnerBase = Math.round(55 + winnerStrength * 30);
  const winnerScore = winnerBase + rand(-5, 8);
  // Margin based on strength gap: close games for even teams, blowouts for mismatches
  const marginBase = Math.round(diff * 40);
  const margin = Math.max(1, marginBase + rand(-5, 5));
  const loserScore = winnerScore - margin;
  return [Math.max(winnerScore, 45), Math.max(loserScore, 32)];
}

function generatePlayerLines(teamId, teamScore) {
  const roster = ROSTERS[teamId];
  // 6 players see court time (5 starters + 1 key sub)
  const active = roster.slice(0, 6);
  const lines = {};

  // Distribute points based on skill tier
  const weights = active.map(p => p[2] === 1 ? 4 : p[2] === 2 ? 2.5 : 1);
  const totalWeight = weights.reduce((a, b) => a + b, 0);

  let pointsLeft = teamScore;
  for (let i = 0; i < active.length; i++) {
    const [pId, pName] = active[i];
    const isLast = i === active.length - 1;
    const targetPts = isLast ? pointsLeft : Math.round((weights[i] / totalWeight) * teamScore + rand(-3, 3));
    const pts = isLast ? pointsLeft : Math.min(Math.max(targetPts, 0), pointsLeft);
    pointsLeft -= pts;

    const tier = active[i][2];
    const minBase = tier === 1 ? 30 : tier === 2 ? 24 : 14;
    lines[pId] = {
      name: pName,
      teamId,
      pts,
      reb: tier === 1 ? rand(4, 10) : tier === 2 ? rand(2, 7) : rand(1, 4),
      ast: tier === 1 ? rand(2, 7) : tier === 2 ? rand(1, 5) : rand(0, 3),
      stl: rand(0, 3),
      blk: rand(0, 2),
      fls: rand(1, 4),
      min: minBase + rand(-2, 4),
    };
  }
  return lines;
}

// ── Existing game stats (for season aggregates) ─────────────────────

const EXISTING_GAME_LINES = [
  // Game 1: POR 78 - KNI 71
  {
    homeId: 'portmore-flames', awayId: 'urban-knights',
    homeScore: 78, awayScore: 71,
    date: new Date('2026-02-22T19:00:00'),
    lines: {
      'pf-1': { teamId: 'portmore-flames', pts: 22, reb: 8, ast: 3, stl: 2, blk: 1, fls: 2, min: 34 },
      'pf-2': { teamId: 'portmore-flames', pts: 18, reb: 5, ast: 6, stl: 1, blk: 0, fls: 3, min: 32 },
      'pf-3': { teamId: 'portmore-flames', pts: 14, reb: 3, ast: 2, stl: 3, blk: 0, fls: 1, min: 28 },
      'pf-4': { teamId: 'portmore-flames', pts: 12, reb: 10, ast: 1, stl: 0, blk: 3, fls: 4, min: 30 },
      'pf-5': { teamId: 'portmore-flames', pts: 8, reb: 2, ast: 4, stl: 1, blk: 0, fls: 2, min: 26 },
      'pf-6': { teamId: 'portmore-flames', pts: 4, reb: 3, ast: 1, stl: 0, blk: 0, fls: 1, min: 18 },
      'uk-1': { teamId: 'urban-knights', pts: 24, reb: 6, ast: 2, stl: 1, blk: 0, fls: 3, min: 36 },
      'uk-2': { teamId: 'urban-knights', pts: 18, reb: 9, ast: 3, stl: 0, blk: 2, fls: 4, min: 34 },
      'uk-3': { teamId: 'urban-knights', pts: 12, reb: 2, ast: 5, stl: 3, blk: 0, fls: 2, min: 30 },
      'uk-4': { teamId: 'urban-knights', pts: 10, reb: 4, ast: 4, stl: 2, blk: 0, fls: 1, min: 28 },
      'uk-5': { teamId: 'urban-knights', pts: 5, reb: 7, ast: 0, stl: 0, blk: 3, fls: 3, min: 24 },
      'uk-6': { teamId: 'urban-knights', pts: 2, reb: 1, ast: 1, stl: 1, blk: 0, fls: 2, min: 12 },
    },
  },
  // Game 2: EAG 85 - RAP 68
  {
    homeId: 'upper-room-eagles', awayId: 'rae-town-raptors',
    homeScore: 85, awayScore: 68,
    date: new Date('2026-02-22T21:00:00'),
    lines: {
      'ure-1': { teamId: 'upper-room-eagles', pts: 26, reb: 7, ast: 4, stl: 2, blk: 1, fls: 2, min: 35 },
      'ure-2': { teamId: 'upper-room-eagles', pts: 20, reb: 4, ast: 7, stl: 3, blk: 0, fls: 1, min: 33 },
      'ure-3': { teamId: 'upper-room-eagles', pts: 15, reb: 8, ast: 1, stl: 0, blk: 2, fls: 3, min: 30 },
      'ure-4': { teamId: 'upper-room-eagles', pts: 12, reb: 3, ast: 3, stl: 1, blk: 0, fls: 2, min: 26 },
      'ure-5': { teamId: 'upper-room-eagles', pts: 8, reb: 5, ast: 2, stl: 0, blk: 1, fls: 4, min: 28 },
      'ure-6': { teamId: 'upper-room-eagles', pts: 4, reb: 1, ast: 0, stl: 1, blk: 0, fls: 1, min: 14 },
      'rtr-1': { teamId: 'rae-town-raptors', pts: 20, reb: 5, ast: 3, stl: 1, blk: 0, fls: 3, min: 34 },
      'rtr-2': { teamId: 'rae-town-raptors', pts: 16, reb: 6, ast: 2, stl: 2, blk: 1, fls: 2, min: 32 },
      'rtr-3': { teamId: 'rae-town-raptors', pts: 14, reb: 4, ast: 4, stl: 0, blk: 0, fls: 1, min: 28 },
      'rtr-4': { teamId: 'rae-town-raptors', pts: 10, reb: 3, ast: 1, stl: 1, blk: 0, fls: 4, min: 24 },
      'rtr-5': { teamId: 'rae-town-raptors', pts: 6, reb: 8, ast: 0, stl: 0, blk: 2, fls: 3, min: 26 },
      'rtr-6': { teamId: 'rae-town-raptors', pts: 2, reb: 1, ast: 2, stl: 0, blk: 0, fls: 1, min: 10 },
    },
  },
  // Game 3: SLA 63 - REB 45
  {
    homeId: 'st-georges-slayers', awayId: 'runnin-rebels',
    homeScore: 63, awayScore: 45,
    date: new Date('2026-02-25T19:00:00'),
    lines: {
      'sgs-1': { teamId: 'st-georges-slayers', pts: 18, reb: 5, ast: 4, stl: 2, blk: 0, fls: 2, min: 32 },
      'sgs-2': { teamId: 'st-georges-slayers', pts: 15, reb: 7, ast: 2, stl: 1, blk: 2, fls: 3, min: 30 },
      'sgs-3': { teamId: 'st-georges-slayers', pts: 12, reb: 3, ast: 5, stl: 3, blk: 0, fls: 1, min: 28 },
      'sgs-4': { teamId: 'st-georges-slayers', pts: 10, reb: 6, ast: 1, stl: 0, blk: 1, fls: 4, min: 26 },
      'sgs-5': { teamId: 'st-georges-slayers', pts: 8, reb: 2, ast: 3, stl: 1, blk: 0, fls: 2, min: 22 },
      'rr-1': { teamId: 'runnin-rebels', pts: 14, reb: 4, ast: 2, stl: 1, blk: 0, fls: 3, min: 30 },
      'rr-2': { teamId: 'runnin-rebels', pts: 11, reb: 5, ast: 3, stl: 0, blk: 1, fls: 2, min: 28 },
      'rr-3': { teamId: 'runnin-rebels', pts: 8, reb: 3, ast: 1, stl: 2, blk: 0, fls: 4, min: 24 },
      'rr-4': { teamId: 'runnin-rebels', pts: 7, reb: 6, ast: 0, stl: 0, blk: 2, fls: 3, min: 26 },
      'rr-5': { teamId: 'runnin-rebels', pts: 5, reb: 2, ast: 4, stl: 1, blk: 0, fls: 1, min: 20 },
    },
  },
];

// ── Game date scheduling ────────────────────────────────────────────
// Spread 42 games across Nov 2025 to mid-Feb 2026
// Game nights: Tuesday (2) and Saturday (6), 2 games per night at 7pm + 9pm

function generateGameDates(count) {
  const dates = [];
  let d = new Date('2025-11-04T00:00:00'); // First Tuesday
  const cutoff = new Date('2026-02-20T00:00:00'); // Before existing games

  while (dates.length < count && d < cutoff) {
    const dow = d.getDay(); // 0=Sun, 2=Tue, 6=Sat
    if (dow === 2 || dow === 6) {
      // Skip Christmas/New Year break
      const month = d.getMonth();
      const day = d.getDate();
      const isBreak = month === 11 && day >= 20; // Dec 20+
      const isNewYear = month === 0 && day <= 5; // Jan 1-5

      if (!isBreak && !isNewYear) {
        // Two games: 7pm and 9pm
        dates.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 19, 0));
        if (dates.length < count) {
          dates.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 21, 0));
        }
      }
    }
    d = new Date(d.getTime() + 86400000); // next day
  }
  return dates;
}

// ── Main seed function ──────────────────────────────────────────────

async function seed() {
  console.log('🏀 Seeding full NBL 2025-26 season...\n');

  // Collect all player stats across ALL games (existing + new)
  const playerSeasonData = {}; // playerId → { name, teamId, games: [{ pts, reb, ... }] }

  // Include existing game stats in aggregates
  for (const existing of EXISTING_GAME_LINES) {
    for (const [pId, line] of Object.entries(existing.lines)) {
      if (!playerSeasonData[pId]) {
        const roster = Object.values(ROSTERS).flat().find(r => r[0] === pId);
        playerSeasonData[pId] = { name: roster?.[1] ?? line.name ?? pId, teamId: line.teamId, games: [] };
      }
      playerSeasonData[pId].games.push({
        pts: line.pts, reb: line.reb, ast: line.ast,
        stl: line.stl, blk: line.blk, fls: line.fls, min: line.min,
        opponentId: line.teamId === existing.homeId ? existing.awayId : existing.homeId,
        date: existing.date,
      });
    }
  }

  // Get only NEW matchups (skip EXISTING)
  const newMatchups = ALL_MATCHUPS.filter(m => m[3] === 'NEW');
  const gameDates = generateGameDates(newMatchups.length);

  console.log(`📅 ${gameDates.length} game dates generated (Nov 2025 - Feb 2026)`);
  console.log(`🎮 ${newMatchups.length} new games to create\n`);

  // Track wins/losses and points for standings
  const teamRecords = {};
  for (const tId of Object.keys(TEAMS)) {
    teamRecords[tId] = { w: 0, l: 0, pf: 0, pa: 0 };
  }

  // Include existing game results in records
  for (const existing of EXISTING_GAME_LINES) {
    const hw = existing.homeScore > existing.awayScore;
    teamRecords[existing.homeId].w += hw ? 1 : 0;
    teamRecords[existing.homeId].l += hw ? 0 : 1;
    teamRecords[existing.homeId].pf += existing.homeScore;
    teamRecords[existing.homeId].pa += existing.awayScore;
    teamRecords[existing.awayId].w += hw ? 0 : 1;
    teamRecords[existing.awayId].l += hw ? 1 : 0;
    teamRecords[existing.awayId].pf += existing.awayScore;
    teamRecords[existing.awayId].pa += existing.homeScore;
  }

  // ─── Create 42 new games ───
  let created = 0;
  for (let i = 0; i < newMatchups.length; i++) {
    const [homeId, awayId, winnerId] = newMatchups[i];
    const gameDate = gameDates[i];
    const homeName = TEAMS[homeId].name;
    const awayName = TEAMS[awayId].name;
    const venue = VENUES[homeId]; // home team's venue

    // Generate score
    const winnerStr = TEAMS[winnerId].strength;
    const loserId = winnerId === homeId ? awayId : homeId;
    const loserStr = TEAMS[loserId].strength;
    let [winScore, loseScore] = generateScore(winnerStr, loserStr);

    const homeScore = winnerId === homeId ? winScore : loseScore;
    const awayScore = winnerId === awayId ? winScore : loseScore;

    // Update records
    teamRecords[homeId].pf += homeScore;
    teamRecords[homeId].pa += awayScore;
    teamRecords[awayId].pf += awayScore;
    teamRecords[awayId].pa += homeScore;
    if (homeScore > awayScore) { teamRecords[homeId].w++; teamRecords[awayId].l++; }
    else { teamRecords[awayId].w++; teamRecords[homeId].l++; }

    // Generate player stats
    const homeLines = generatePlayerLines(homeId, homeScore);
    const awayLines = generatePlayerLines(awayId, awayScore);
    const allLines = { ...homeLines, ...awayLines };

    // Track for season aggregates
    for (const [pId, line] of Object.entries(allLines)) {
      if (!playerSeasonData[pId]) {
        playerSeasonData[pId] = { name: line.name, teamId: line.teamId, games: [] };
      }
      playerSeasonData[pId].games.push({
        pts: line.pts, reb: line.reb, ast: line.ast,
        stl: line.stl, blk: line.blk, fls: line.fls, min: line.min,
        opponentId: line.teamId === homeId ? awayId : homeId,
        date: gameDate,
      });
    }

    // Create event
    const endTime = new Date(gameDate.getTime() + 2 * 3600000);
    const eventId = await addDoc(`associations/${ASSOC}/events`, {
      title: `${homeName} vs ${awayName}`,
      type: 'game',
      statsStatus: 'approved',
      startTime: gameDate,
      endTime,
      location: venue,
      divisionId: 'nbl-premier',
      teamIds: [homeId, awayId],
      createdBy: 'system',
      description: null,
    });

    // Create gameStats
    if (eventId) {
      // Remove 'name' from lines for Firestore (it's stored as a sub-field)
      await createDoc(`associations/${ASSOC}/gameStats`, eventId, {
        eventId,
        seasonId: SEASON,
        divisionId: 'nbl-premier',
        homeTeamId: homeId,
        awayTeamId: awayId,
        homeTeamName: homeName,
        awayTeamName: awayName,
        homeScore,
        awayScore,
        status: 'approved',
        submittedBy: 'system',
        submittedAt: new Date(gameDate.getTime() + 2 * 3600000 + 600000),
        approvedBy: 'system',
        approvedAt: new Date(gameDate.getTime() + 2 * 3600000 + 900000),
        playerLines: allLines,
      });
    }

    created++;
    if (created % 10 === 0) console.log(`  ${created}/${newMatchups.length} games created...`);
  }
  console.log(`✅ ${created} games with box scores created\n`);

  // ─── Player season stats ───
  console.log('📊 Creating player season stats...');
  let playerCount = 0;
  for (const [pId, data] of Object.entries(playerSeasonData)) {
    const gp = data.games.length;
    if (gp === 0) continue;

    const totals = { pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, fls: 0, min: 0 };
    for (const g of data.games) {
      totals.pts += g.pts; totals.reb += g.reb; totals.ast += g.ast;
      totals.stl += g.stl; totals.blk += g.blk; totals.fls += g.fls; totals.min += g.min;
    }
    const averages = {};
    for (const k of Object.keys(totals)) {
      averages[k] = Math.round((totals[k] / gp) * 10) / 10;
    }

    const teamName = TEAMS[data.teamId]?.name ?? data.teamId;
    const docId = `${pId}_${SEASON}`;

    const gameLog = data.games.map(g => ({
      opponentName: TEAMS[g.opponentId]?.name ?? g.opponentId,
      date: g.date,
      pts: g.pts, reb: g.reb, ast: g.ast, stl: g.stl, blk: g.blk,
    }));

    await patchDoc(`associations/${ASSOC}/playerSeasonStats`, docId, {
      playerId: pId,
      playerName: data.name,
      teamId: data.teamId,
      teamName,
      seasonId: SEASON,
      divisionId: 'nbl-premier',
      gamesPlayed: gp,
      totals,
      averages,
      gameLog,
    });
    playerCount++;
  }
  console.log(`✅ ${playerCount} player season stats created\n`);

  // ─── Updated standings ───
  console.log('📋 Updating standings...');
  const sortedTeams = Object.entries(teamRecords)
    .map(([teamId, r]) => ({
      teamId,
      teamName: TEAMS[teamId].name,
      divisionId: 'nbl-premier',
      wins: r.w, losses: r.l,
      pct: r.w + r.l > 0 ? Math.round((r.w / (r.w + r.l)) * 1000) / 1000 : 0,
      pointsFor: r.pf, pointsAgainst: r.pa,
    }))
    .sort((a, b) => b.pct - a.pct || (b.pointsFor - b.pointsAgainst) - (a.pointsFor - a.pointsAgainst));

  // Calculate GB from leader
  const leaderDiff = sortedTeams[0].wins - sortedTeams[0].losses;
  for (const t of sortedTeams) {
    t.gb = (leaderDiff - (t.wins - t.losses)) / 2;
    t.streak = t.wins > t.losses ? `W${Math.min(t.wins, 3)}` : t.losses > t.wins ? `L${Math.min(t.losses, 3)}` : 'W1';
    t.lastTen = `${Math.min(t.wins, 7)}-${Math.min(t.losses, 3)}`;
  }

  await patchDoc(`associations/${ASSOC}/standings`, `${SEASON}_all`, {
    seasonId: SEASON, divisionId: null, updatedAt: new Date(), standings: sortedTeams,
  });
  await patchDoc(`associations/${ASSOC}/standings`, `${SEASON}_nbl-premier`, {
    seasonId: SEASON, divisionId: 'nbl-premier', updatedAt: new Date(), standings: sortedTeams,
  });
  console.log('✅ Standings updated\n');

  // ─── Updated leaderboards ───
  console.log('🏆 Updating leaderboards...');
  const allPlayers = Object.entries(playerSeasonData)
    .filter(([_, d]) => d.games.length >= 3) // min 3 games
    .map(([pId, d]) => {
      const gp = d.games.length;
      const totPts = d.games.reduce((s, g) => s + g.pts, 0);
      const totReb = d.games.reduce((s, g) => s + g.reb, 0);
      const totAst = d.games.reduce((s, g) => s + g.ast, 0);
      const totStl = d.games.reduce((s, g) => s + g.stl, 0);
      const totBlk = d.games.reduce((s, g) => s + g.blk, 0);
      return {
        playerId: pId, name: d.name, teamName: TEAMS[d.teamId]?.name ?? '', gp,
        ppg: Math.round((totPts / gp) * 10) / 10,
        rpg: Math.round((totReb / gp) * 10) / 10,
        apg: Math.round((totAst / gp) * 10) / 10,
        spg: Math.round((totStl / gp) * 10) / 10,
        bpg: Math.round((totBlk / gp) * 10) / 10,
      };
    });

  const categories = ['ppg', 'rpg', 'apg', 'spg', 'bpg'];
  for (const cat of categories) {
    const sorted = [...allPlayers].sort((a, b) => b[cat] - a[cat]).slice(0, 15);
    await patchDoc(`associations/${ASSOC}/leaderboard`, `${SEASON}_null_${cat}`, {
      seasonId: SEASON, divisionId: null, category: cat, updatedAt: new Date(),
      rankings: sorted.map(e => ({
        playerId: e.playerId, name: e.name, teamName: e.teamName, gp: e.gp, value: e[cat],
      })),
    });
  }
  console.log('✅ Leaderboards updated (PPG, RPG, APG, SPG, BPG)\n');

  // ─── Summary ───
  console.log('═══════════════════════════════════════════════');
  console.log('  FINAL STANDINGS');
  console.log('═══════════════════════════════════════════════');
  for (let i = 0; i < sortedTeams.length; i++) {
    const t = sortedTeams[i];
    console.log(`  ${i + 1}. ${t.teamName.padEnd(30)} ${t.wins}-${t.losses}  (.${String(Math.round(t.pct * 1000)).padStart(3, '0')})  PF:${t.pointsFor} PA:${t.pointsAgainst}`);
  }
  console.log('═══════════════════════════════════════════════');

  // Top scorers
  const topScorers = [...allPlayers].sort((a, b) => b.ppg - a.ppg).slice(0, 5);
  console.log('\n  TOP SCORERS');
  for (const p of topScorers) {
    console.log(`  ${p.name.padEnd(22)} ${p.teamName.padEnd(28)} ${p.ppg} PPG (${p.gp} GP)`);
  }

  console.log('\n🏀 Full season seed complete!');
  console.log(`   ${created} games · ${playerCount} players · 5 leaderboards · standings updated`);
}

seed().catch(err => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
