#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// seed_mock_league.js — Comprehensive mock league seed for HoopsConnect
//
// Creates a full late-season Jamaica NBL 2025-26 league in Firestore as of
// April 2026 (5+ months of regular season played):
//   - Association, Season, Divisions, Teams, Rosters
//   - ~56 completed games with box scores (44 premier + 12 women's)
//   - ~17 upcoming games through end of regular season (May 2026)
//   - playerSeasonStats, teamSeasonStats, standings, leaderboards
//   - Board posts and calendar events
//
// Usage:
//   node scripts/seed_mock_league.js
// ─────────────────────────────────────────────────────────────────────────────

const https = require('https');
const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

const TARGET = guardFirestoreTarget({
  mode: 'destructive',
  destructiveScope: 'associations/jba',
});
const PROJECT_ID = TARGET.projectId;
const BASE_URL = TARGET.baseUrl;
const firestoreTransport = TARGET.isEmulator ? http : https;

// ── CLI args ────────────────────────────────────────────────────────────────

const UID_ARG = process.argv.find(a => a.startsWith('--uid='));
if (UID_ARG) {
  throw new Error('--uid provisioning is disabled; use the reviewed membership administration workflow.');
}

// ── Firebase REST helpers ───────────────────────────────────────────────────

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

const delay = ms => new Promise(r => setTimeout(r, ms));

async function request(method, urlPath, body, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const result = await _doRequest(method, urlPath, body);
      return result;
    } catch (err) {
      if (attempt < retries && (err.code === 'ECONNRESET' || err.code === 'EPIPE' || err.code === 'ETIMEDOUT')) {
        console.error(`  Retry ${attempt}/${retries} for ${method} ${urlPath.substring(0, 60)}...`);
        await delay(1000 * attempt);
      } else {
        throw err;
      }
    }
  }
}

async function _doRequest(method, urlPath, body) {
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
        if (res.statusCode >= 400) {
          console.error(`  WARNING: ${res.statusCode} ${method} ${urlPath.substring(0, 100)}`);
          resolve(null);
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

async function addDoc(collection, data) {
  await delay(50);
  const result = await request('POST', `/${collection}`, makeDoc(data));
  return result?.name?.split('/').pop() ?? null;
}

async function createDoc(collection, docId, data) {
  await delay(50);
  return request('POST', `/${collection}?documentId=${docId}`, makeDoc(data));
}

async function patchDoc(collection, docId, data) {
  await delay(50);
  return request('PATCH', `/${collection}/${docId}`, makeDoc(data));
}

async function deleteDoc(fullPath) {
  await delay(30);
  return request('DELETE', `/${fullPath}`, null);
}

async function listDocs(collection, pageToken) {
  const suffix = pageToken ? `?pageSize=100&pageToken=${pageToken}` : '?pageSize=100';
  return request('GET', `/${collection}${suffix}`, null);
}

// ── Delete all docs in a collection ─────────────────────────────────────────

async function deleteCollection(collectionPath) {
  let deleted = 0;
  let pageToken = null;
  do {
    const result = await listDocs(collectionPath, pageToken);
    if (!result || !result.documents || result.documents.length === 0) break;
    for (const doc of result.documents) {
      const docPath = doc.name.split('/documents/')[1];
      await deleteDoc(docPath);
      deleted++;
    }
    pageToken = result.nextPageToken;
  } while (pageToken);
  return deleted;
}

// ── Random helpers ──────────────────────────────────────────────────────────

function rand(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function round1(n) {
  return Math.round(n * 10) / 10;
}

// Generate a balanced schedule of matchups with strength-weighted winners.
// Returns array of [homeId, awayId, winnerId].
function generateMatchupSchedule(teamIds, teamsMap, gameCount) {
  const matchups = [];
  const played = Object.fromEntries(teamIds.map(id => [id, 0]));

  while (matchups.length < gameCount) {
    const sortedAsc = [...teamIds].sort((a, b) => played[a] - played[b]);
    const homePool = sortedAsc.slice(0, Math.max(2, Math.ceil(sortedAsc.length / 3)));
    const home = pick(homePool);
    const awayCandidates = sortedAsc.filter(id => id !== home);
    const awayPool = awayCandidates.slice(0, Math.max(2, Math.ceil(awayCandidates.length / 2)));
    const away = pick(awayPool);

    const sH = teamsMap[home].strength;
    const sA = teamsMap[away].strength;
    // Home advantage baseline + strength gap, clamped.  Strength weighted
    // heavily so the final standings roughly track the team strength ratings.
    const pHome = Math.max(0.10, Math.min(0.92, 0.52 + (sH - sA) * 0.90));
    const winner = Math.random() < pHome ? home : away;

    matchups.push([home, away, winner]);
    played[home]++;
    played[away]++;
  }
  return matchups;
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

const ASSOC = 'jba';
const SEASON = 'nbl-2025-26';

// ── Premier Teams (8) ────────────────────────────────────────────────────

const PREMIER_TEAMS = {
  'portmore-flames':       { name: 'Portmore Flames',           short: 'POR', strength: 0.88, divisionId: 'nbl-premier' },
  'upper-room-eagles':     { name: 'Upper Room Eagles',         short: 'EAG', strength: 0.82, divisionId: 'nbl-premier' },
  'st-georges-slayers':    { name: "St George's Slayers",       short: 'SLA', strength: 0.78, divisionId: 'nbl-premier' },
  'urban-knights':         { name: 'Urban Knights',             short: 'KNI', strength: 0.72, divisionId: 'nbl-premier' },
  'mobay-warriors':        { name: "Mo Bay Warriors",           short: 'MOB', strength: 0.60, divisionId: 'nbl-premier' },
  'runnin-rebels':         { name: "Runnin' Rebels",            short: 'REB', strength: 0.50, divisionId: 'nbl-premier' },
  'rae-town-raptors':      { name: 'Rae Town Raptors',          short: 'RAP', strength: 0.48, divisionId: 'nbl-premier' },
  'spanish-town-spartans': { name: 'Spanish Town Spartans',     short: 'SPA', strength: 0.38, divisionId: 'nbl-premier' },
};

// ── Women's Teams (4) ───────────────────────────────────────────────────

const WOMENS_TEAMS = {
  'kingston-queens':    { name: 'Kingston Queens',         short: 'QUE', strength: 0.80, divisionId: 'womens-league' },
  'mobay-angels':       { name: 'Montego Bay Angels',      short: 'ANG', strength: 0.65, divisionId: 'womens-league' },
  'ocho-rios-mystics':  { name: 'Ocho Rios Mystics',       short: 'MYS', strength: 0.55, divisionId: 'womens-league' },
  'portmore-stars':     { name: 'Portmore Stars',          short: 'PST', strength: 0.45, divisionId: 'womens-league' },
};

const ALL_TEAMS = { ...PREMIER_TEAMS, ...WOMENS_TEAMS };

// ── Premier Rosters (10 per team) ───────────────────────────────────────
// [playerId, name, tier]  1=star, 2=starter, 3=bench

const PREMIER_ROSTERS = {
  'portmore-flames': [
    ['pf-1', 'Ricardo Thompson', 1], ['pf-2', 'Andre Mitchell', 1],
    ['pf-3', 'Kevin Richards', 2],   ['pf-4', 'Damion Stewart', 2],
    ['pf-5', 'Marcus Brown', 2],     ['pf-6', 'Troy Williams', 3],
    ['pf-7', 'Levar Brown', 3],      ['pf-8', 'Javaughn Simpson', 3],
    ['pf-9', 'Donte Hylton', 3],     ['pf-10', 'Oshane Barnett', 3],
  ],
  'upper-room-eagles': [
    ['ure-1', 'Omar Barnes', 1],     ['ure-2', 'Juvane Carthy', 1],
    ['ure-3', 'Kavon Williams', 2],  ['ure-4', 'Rashane Blake', 2],
    ['ure-5', 'Devon Clarke', 2],    ['ure-6', 'Tyrell Grant', 3],
    ['ure-7', 'Michael Green', 3],   ['ure-8', 'Kemar Thomas', 3],
    ['ure-9', 'Shaquille Henry', 3], ['ure-10', 'Adrian Forbes', 3],
  ],
  'st-georges-slayers': [
    ['sgs-1', 'Brandon Taylor', 1],  ['sgs-2', 'Akeem Wright', 1],
    ['sgs-3', 'Ryan Campbell', 2],   ['sgs-4', 'Jerome Ellis', 2],
    ['sgs-5', 'Donovan Lee', 2],     ['sgs-6', 'Shamar Nelson', 3],
    ['sgs-7', 'Keron Bailey', 3],    ['sgs-8', 'Carlton James', 3],
    ['sgs-9', 'Gareth Whyte', 3],    ['sgs-10', 'Tajay Morrison', 3],
  ],
  'urban-knights': [
    ['uk-1', 'Nicholai Brown', 1],   ['uk-2', 'Ramone Spence', 1],
    ['uk-3', "D'Andre Forbes", 2],   ['uk-4', 'Jermaine Brown', 2],
    ['uk-5', 'Shavair Francis', 2],  ['uk-6', 'Tyrese Campbell', 3],
    ['uk-7', 'Devon Powell', 3],     ['uk-8', 'Ashanti Murray', 3],
    ['uk-9', 'Kevon Stewart', 3],    ['uk-10', 'Sheldon Bryan', 3],
  ],
  'mobay-warriors': [
    ['mbw-1', 'Garfield Scott', 1],  ['mbw-2', 'Desmond Bryan', 1],
    ['mbw-3', 'Akeem Simpson', 2],   ['mbw-4', 'Rasheed Clarke', 2],
    ['mbw-5', 'Joel Thompson', 2],   ['mbw-6', 'Travis Brown', 3],
    ['mbw-7', 'Damian Gordon', 3],   ['mbw-8', 'Miguel Lewis', 3],
    ['mbw-9', 'Renaldo Cunningham', 3], ['mbw-10', 'Romain Palmer', 3],
  ],
  'runnin-rebels': [
    ['rr-1', 'Corey Edwards', 1],    ['rr-2', 'Javon Sinclair', 1],
    ['rr-3', 'Romario Johnson', 2],  ['rr-4', 'Kemar Wallace', 2],
    ['rr-5', 'Tristan Reid', 2],     ['rr-6', 'Orlando Smith', 3],
    ['rr-7', 'Nathan Graham', 3],    ['rr-8', 'Andre Williams', 3],
    ['rr-9', 'Tyreek Dawkins', 3],   ['rr-10', 'Damari Robinson', 3],
  ],
  'rae-town-raptors': [
    ['rtr-1', 'Marlon Davis', 1],    ['rtr-2', 'Shane Patterson', 1],
    ['rtr-3', 'Kadeem Powell', 2],   ['rtr-4', 'Rohan Stephens', 2],
    ['rtr-5', 'Dwayne Morgan', 2],   ['rtr-6', 'Jason Henry', 3],
    ['rtr-7', 'Carlton Hewitt', 3],  ['rtr-8', 'Tavares Lynch', 3],
    ['rtr-9', 'Raheem Beckford', 3], ['rtr-10', 'Stefan Chambers', 3],
  ],
  'spanish-town-spartans': [
    ['sts-1', 'Daniel Maxwell', 1],  ['sts-2', 'Shayne Foster', 1],
    ['sts-3', 'Romaine Mitchell', 2],['sts-4', 'Troy Anderson', 2],
    ['sts-5', 'Keshawn Harris', 2],  ['sts-6', 'Patrick Davis', 3],
    ['sts-7', 'Andre Thomas', 3],    ['sts-8', 'Mario Clarke', 3],
    ['sts-9', 'Othneil Lawrence', 3],['sts-10', 'Javani Wright', 3],
  ],
};

// ── Women's Rosters (8 per team) ────────────────────────────────────────

const WOMENS_ROSTERS = {
  'kingston-queens': [
    ['kq-1', 'Simone Richards', 1],  ['kq-2', 'Tanya Mitchell', 1],
    ['kq-3', 'Keisha Brown', 2],     ['kq-4', 'Monique Stewart', 2],
    ['kq-5', 'Alicia Thompson', 2],  ['kq-6', 'Shanice Campbell', 3],
    ['kq-7', 'Danielle Grant', 3],   ['kq-8', 'Patrice Morgan', 3],
  ],
  'mobay-angels': [
    ['ma-1', 'Crystal Williams', 1], ['ma-2', 'Jada Palmer', 1],
    ['ma-3', 'Renae Clarke', 2],     ['ma-4', 'Shelly-Ann Davis', 2],
    ['ma-5', 'Nicole Beckford', 2],  ['ma-6', 'Tamara Lewis', 3],
    ['ma-7', 'Camille Reid', 3],     ['ma-8', 'Bianca Scott', 3],
  ],
  'ocho-rios-mystics': [
    ['orm-1', 'Kayla Francis', 1],   ['orm-2', 'Brianna Henry', 1],
    ['orm-3', 'Natasha Gordon', 2],  ['orm-4', 'Sashell Johnson', 2],
    ['orm-5', 'Tiffany Barrett', 2], ['orm-6', 'Jasmine Foster', 3],
    ['orm-7', 'Samantha Ellis', 3],  ['orm-8', 'Latoya Cunningham', 3],
  ],
  'portmore-stars': [
    ['ps-1', 'Desiree Marshall', 1], ['ps-2', 'Khadija Nelson', 1],
    ['ps-3', 'Andrea Simpson', 2],   ['ps-4', 'Rochelle Thomas', 2],
    ['ps-5', 'Vanessa Blake', 2],    ['ps-6', 'Carlene Whyte', 3],
    ['ps-7', 'Sophia Morrison', 3],  ['ps-8', 'Melissa Campbell', 3],
  ],
};

const ALL_ROSTERS = { ...PREMIER_ROSTERS, ...WOMENS_ROSTERS };

// ── Completed matchups are generated at runtime via generateMatchupSchedule() ─
// Target: ~3/4 of the way through the regular season (as of Apr 12, 2026).
// Premier regular season is ~20 games/team → 80 total; 60 completed = 75%.
// Women's regular season is ~11 games/team → 22 total; 16 completed = 73%.
// Winners are picked by team strength with a home-court bump, so standings
// end up roughly proportional to each team's strength rating.

const PREMIER_COMPLETED_GAME_COUNT = 60;
const WOMENS_COMPLETED_GAME_COUNT = 16;

// ── Upcoming matchups (no scores) ───────────────────────────────────────

const PREMIER_UPCOMING_MATCHUPS = [
  ['portmore-flames',       'rae-town-raptors'],
  ['upper-room-eagles',     'st-georges-slayers'],
  ['urban-knights',         'runnin-rebels'],
  ['mobay-warriors',        'rae-town-raptors'],
  ['portmore-flames',       'urban-knights'],
  ['st-georges-slayers',    'mobay-warriors'],
  ['upper-room-eagles',     'spanish-town-spartans'],
  ['runnin-rebels',         'rae-town-raptors'],
  ['portmore-flames',       'st-georges-slayers'],
  ['urban-knights',         'spanish-town-spartans'],
  ['upper-room-eagles',     'mobay-warriors'],
  ['runnin-rebels',         'spanish-town-spartans'],
  ['rae-town-raptors',      'urban-knights'],
  ['st-georges-slayers',    'upper-room-eagles'],
  ['portmore-flames',       'upper-room-eagles'],
  ['mobay-warriors',        'runnin-rebels'],
  ['st-georges-slayers',    'rae-town-raptors'],
  ['urban-knights',         'mobay-warriors'],
  ['spanish-town-spartans', 'portmore-flames'],
  ['rae-town-raptors',      'spanish-town-spartans'],
];

const WOMENS_UPCOMING_MATCHUPS = [
  ['portmore-stars',     'mobay-angels'],
  ['ocho-rios-mystics',  'kingston-queens'],
  ['mobay-angels',       'portmore-stars'],
  ['kingston-queens',    'mobay-angels'],
  ['ocho-rios-mystics',  'portmore-stars'],
  ['kingston-queens',    'portmore-stars'],
];

// ── Venues ──────────────────────────────────────────────────────────────

const MAIN_VENUE = 'National Indoor Sports Centre, Kingston';
const ALT_VENUE = 'Montego Bay Convention Centre';

function venueForTeam(teamId) {
  if (teamId === 'mobay-warriors' || teamId === 'mobay-angels') return ALT_VENUE;
  return MAIN_VENUE;
}

// ── Score generation ────────────────────────────────────────────────────

function generateScore(winnerStrength, loserStrength) {
  const diff = winnerStrength - loserStrength;
  const winnerBase = Math.round(58 + winnerStrength * 28);
  const winnerScore = winnerBase + rand(-5, 8);
  const marginBase = Math.round(diff * 35);
  const margin = Math.max(1, marginBase + rand(-4, 6));
  const loserScore = winnerScore - margin;
  return [Math.max(winnerScore, 50), Math.max(loserScore, 38)];
}

function generateQuarterScores(total) {
  // Split total into 4 quarters roughly evenly
  let remaining = total;
  const quarters = {};
  for (let q = 1; q <= 4; q++) {
    if (q === 4) {
      quarters[String(q)] = remaining;
    } else {
      const avg = remaining / (5 - q);
      const qScore = Math.max(8, Math.round(avg + rand(-5, 5)));
      quarters[String(q)] = Math.min(qScore, remaining - (4 - q) * 8);
      remaining -= quarters[String(q)];
    }
  }
  return quarters;
}

// ── Player stat line generation ─────────────────────────────────────────

function generatePlayerLines(teamId, teamScore, roster) {
  // Pick 8 active players: first 5 = starters, next 3 = bench (from indices 5-9)
  const starters = roster.slice(0, 5);
  const benchPool = roster.slice(5);
  const bench = benchPool.slice(0, 3);
  const active = [...starters, ...bench];

  const lines = {};

  // Weight distribution by tier
  const weights = active.map(p => {
    const tier = p[2];
    return tier === 1 ? 4 : tier === 2 ? 2.5 : 1;
  });
  const totalWeight = weights.reduce((a, b) => a + b, 0);

  let pointsLeft = teamScore;
  for (let i = 0; i < active.length; i++) {
    const [pId, pName, tier] = active[i];
    const isLast = i === active.length - 1;

    // Points
    const targetPts = isLast
      ? pointsLeft
      : Math.round((weights[i] / totalWeight) * teamScore + rand(-3, 3));
    const pts = isLast ? pointsLeft : Math.min(Math.max(targetPts, 0), pointsLeft);
    pointsLeft -= pts;

    // Minutes by tier
    const minVal = tier === 1 ? rand(28, 36) : tier === 2 ? rand(20, 28) : rand(8, 18);

    // Rebounds split into oreb (~30%) and dreb (~70%)
    const totalReb = tier === 1 ? rand(4, 10) : tier === 2 ? rand(2, 7) : rand(1, 4);
    const oreb = Math.round(totalReb * 0.3) + (Math.random() < 0.3 ? 1 : 0);
    const dreb = totalReb - Math.min(oreb, totalReb);

    lines[pId] = {
      name: pName,
      teamId,
      pts,
      oreb: Math.min(oreb, totalReb),
      dreb: Math.max(dreb, 0),
      reb: totalReb,
      ast: tier === 1 ? rand(2, 7) : tier === 2 ? rand(1, 5) : rand(0, 3),
      stl: rand(0, 3),
      blk: rand(0, 2),
      fls: rand(1, 5),
      min: minVal,
    };
  }
  return lines;
}

// ── Game date scheduling ────────────────────────────────────────────────

function generateCompletedDates(count) {
  // Collect ALL available game slots from Nov 4 2025 through Apr 11 2026
  // (today's date is 2026-04-12, so games scheduled up to yesterday are "played")
  const allSlots = [];
  let d = new Date('2025-11-04T00:00:00');
  const cutoff = new Date('2026-04-12T00:00:00');

  while (d < cutoff) {
    const dow = d.getDay(); // 0=Sun, 2=Tue, 4=Thu, 6=Sat
    if (dow === 2 || dow === 4 || dow === 6) {
      const month = d.getMonth();
      const day = d.getDate();
      // Skip Dec 20 - Jan 5
      const isBreak = (month === 11 && day >= 20) || (month === 0 && day <= 5);
      if (!isBreak) {
        allSlots.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 19, 0));
        allSlots.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 21, 0));
      }
    }
    d = new Date(d.getTime() + 86400000);
  }

  // Spread games evenly across all available slots (end-inclusive) so the
  // first game falls near Nov 4 and the last game lands near Apr 11.
  const dates = [];
  if (allSlots.length === 0) return dates;
  for (let i = 0; i < count; i++) {
    const idx = Math.min(
      allSlots.length - 1,
      Math.round((i * (allSlots.length - 1)) / Math.max(1, count - 1)),
    );
    dates.push(allSlots[idx]);
  }
  return dates;
}

function generateUpcomingDates(count) {
  const dates = [];
  let d = new Date('2026-04-14T00:00:00');
  const cutoff = new Date('2026-06-01T00:00:00');

  while (dates.length < count && d < cutoff) {
    const dow = d.getDay();
    if (dow === 2 || dow === 4 || dow === 6) {
      dates.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 19, 0));
      if (dates.length < count) {
        dates.push(new Date(d.getFullYear(), d.getMonth(), d.getDate(), 21, 0));
      }
    }
    d = new Date(d.getTime() + 86400000);
  }
  return dates.slice(0, count);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN SEED
// ═══════════════════════════════════════════════════════════════════════════

async function seed() {
  console.log('');
  console.log('================================================================');
  console.log('  HoopsConnect - Mock League Seed');
  console.log('  Jamaica NBL 2025-26 Late-Season (April 2026)');
  console.log('================================================================');
  console.log('');

  // ─── Step 0: Delete existing data ─────────────────────────────────────
  console.log('[1/12] Deleting existing data under associations/jba/...');

  const subcollections = [
    'seasons', 'divisions', 'teams', 'events', 'gameStats',
    'playerSeasonStats', 'teamSeasonStats', 'standings', 'leaderboard', 'posts',
  ];

  let totalDeleted = 0;
  for (const sub of subcollections) {
    const n = await deleteCollection(`associations/${ASSOC}/${sub}`);
    if (n > 0) console.log(`  Deleted ${n} docs from ${sub}`);
    totalDeleted += n;
  }

  // Delete the association doc itself
  await deleteDoc(`associations/${ASSOC}`);
  totalDeleted++;

  // Delete invite codes with associationId=jba (list all, filter)
  let icPage = null;
  let icDeleted = 0;
  do {
    const result = await listDocs('inviteCodes', icPage);
    if (!result || !result.documents) break;
    for (const doc of result.documents) {
      const assocField = doc.fields?.associationId?.stringValue;
      if (assocField === ASSOC) {
        const docPath = doc.name.split('/documents/')[1];
        await deleteDoc(docPath);
        icDeleted++;
      }
    }
    icPage = result.nextPageToken;
  } while (icPage);
  if (icDeleted > 0) console.log(`  Deleted ${icDeleted} invite codes`);
  totalDeleted += icDeleted;

  console.log(`  Total: ${totalDeleted} documents deleted`);
  console.log('');

  // ─── Step 1: Association ──────────────────────────────────────────────
  console.log('[2/12] Creating association...');
  await createDoc('associations', ASSOC, {
    name: 'Jamaica Basketball Association',
    currentSeasonId: SEASON,
    createdAt: new Date('2025-10-01T00:00:00'),
  });
  console.log('  Created: associations/jba');

  // ─── Step 2: Season ───────────────────────────────────────────────────
  console.log('[3/12] Creating season...');
  await createDoc(`associations/${ASSOC}/seasons`, SEASON, {
    name: 'NBL 2025-26',
    startDate: new Date('2025-11-01T00:00:00'),
    endDate: new Date('2026-06-30T00:00:00'),
    isActive: true,
    associationId: ASSOC,
  });
  console.log(`  Created: seasons/${SEASON}`);

  // ─── Step 3: Divisions ────────────────────────────────────────────────
  console.log('[4/12] Creating divisions...');
  await createDoc(`associations/${ASSOC}/divisions`, 'nbl-premier', {
    name: 'NBL Premier Division',
    seasonId: SEASON,
    associationId: ASSOC,
  });
  await createDoc(`associations/${ASSOC}/divisions`, 'womens-league', {
    name: "Women's National League",
    seasonId: SEASON,
    associationId: ASSOC,
  });
  console.log('  Created: nbl-premier, womens-league');

  // ─── Step 4: Teams ────────────────────────────────────────────────────
  console.log('[5/12] Creating teams...');
  for (const [teamId, team] of Object.entries(ALL_TEAMS)) {
    const roster = ALL_ROSTERS[teamId];
    await createDoc(`associations/${ASSOC}/teams`, teamId, {
      name: team.name,
      shortName: team.short,
      divisionId: team.divisionId,
      seasonId: SEASON,
      associationId: ASSOC,
      roster: roster.map(([pId, pName, tier]) => ({
        playerId: pId,
        name: pName,
        jerseyNumber: String(rand(0, 55)),
        position: pick(['PG', 'SG', 'SF', 'PF', 'C']),
      })),
    });
  }
  console.log(`  Created: ${Object.keys(ALL_TEAMS).length} teams`);

  // ─── Step 5: Completed games with box scores ─────────────────────────
  console.log('[6/12] Creating completed games + box scores...');

  // Tracking structures
  const playerSeasonData = {}; // playerId -> { name, teamId, teamName, divisionId, games: [...] }
  const teamRecords = {};
  for (const [teamId, team] of Object.entries(ALL_TEAMS)) {
    teamRecords[teamId] = { w: 0, l: 0, pf: 0, pa: 0, divisionId: team.divisionId };
  }

  // Generate balanced completed matchups at runtime
  const premierCompletedMatchups = generateMatchupSchedule(
    Object.keys(PREMIER_TEAMS), PREMIER_TEAMS, PREMIER_COMPLETED_GAME_COUNT,
  );
  const womensCompletedMatchups = generateMatchupSchedule(
    Object.keys(WOMENS_TEAMS), WOMENS_TEAMS, WOMENS_COMPLETED_GAME_COUNT,
  );

  // Combine all completed matchups
  const allCompletedMatchups = [
    ...premierCompletedMatchups.map(m => [...m, 'nbl-premier']),
    ...womensCompletedMatchups.map(m => [...m, 'womens-league']),
  ];

  const completedDates = generateCompletedDates(allCompletedMatchups.length);
  const completedEventIds = []; // track for game log references

  let gamesCreated = 0;
  for (let i = 0; i < allCompletedMatchups.length; i++) {
    const [homeId, awayId, winnerId, divisionId] = allCompletedMatchups[i];
    const gameDate = completedDates[i];
    const homeName = ALL_TEAMS[homeId].name;
    const awayName = ALL_TEAMS[awayId].name;
    const venue = venueForTeam(homeId);

    // Generate score
    const winnerStr = ALL_TEAMS[winnerId].strength;
    const loserId = winnerId === homeId ? awayId : homeId;
    const loserStr = ALL_TEAMS[loserId].strength;
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

    // Generate player stat lines
    const homeRoster = ALL_ROSTERS[homeId];
    const awayRoster = ALL_ROSTERS[awayId];
    const homeLines = generatePlayerLines(homeId, homeScore, homeRoster);
    const awayLines = generatePlayerLines(awayId, awayScore, awayRoster);
    const allLines = { ...homeLines, ...awayLines };

    // Create event
    const endTime = new Date(gameDate.getTime() + 2 * 3600000);
    const eventId = await addDoc(`associations/${ASSOC}/events`, {
      title: `${homeName} vs ${awayName}`,
      type: 'game',
      statsStatus: 'approved',
      startTime: gameDate,
      endTime,
      location: venue,
      divisionId,
      seasonId: SEASON,
      teamIds: [homeId, awayId],
      createdBy: 'system',
      description: null,
    });

    completedEventIds.push(eventId);

    // Create gameStats
    if (eventId) {
      await createDoc(`associations/${ASSOC}/gameStats`, eventId, {
        eventId,
        seasonId: SEASON,
        divisionId,
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
        homeQuarterScores: generateQuarterScores(homeScore),
        awayQuarterScores: generateQuarterScores(awayScore),
      });
    }

    // Track player season data
    for (const [pId, line] of Object.entries(allLines)) {
      const opponentId = line.teamId === homeId ? awayId : homeId;
      const opponentName = ALL_TEAMS[opponentId].name;
      const isWin = (line.teamId === homeId && homeScore > awayScore) ||
                    (line.teamId === awayId && awayScore > homeScore);
      if (!playerSeasonData[pId]) {
        playerSeasonData[pId] = {
          name: line.name,
          teamId: line.teamId,
          teamName: ALL_TEAMS[line.teamId].name,
          divisionId,
          games: [],
        };
      }
      playerSeasonData[pId].games.push({
        eventId,
        date: gameDate,
        vs: opponentName,
        pts: line.pts,
        oreb: line.oreb,
        dreb: line.dreb,
        reb: line.reb,
        ast: line.ast,
        stl: line.stl,
        blk: line.blk,
        fls: line.fls,
        min: line.min,
        result: isWin ? 'W' : 'L',
        // for team aggregation
        _opponentId: opponentId,
        _opponentName: opponentName,
      });
    }

    gamesCreated++;
    if (gamesCreated % 5 === 0) {
      console.log(`  ${gamesCreated}/${allCompletedMatchups.length} completed games created...`);
      await delay(200);
    }
  }
  console.log(`  ${gamesCreated} completed games with box scores created`);

  // ─── Step 6: Upcoming games ───────────────────────────────────────────
  console.log('[7/12] Creating upcoming games...');

  const allUpcomingMatchups = [
    ...PREMIER_UPCOMING_MATCHUPS.map(m => [...m, 'nbl-premier']),
    ...WOMENS_UPCOMING_MATCHUPS.map(m => [...m, 'womens-league']),
  ];

  const upcomingDates = generateUpcomingDates(allUpcomingMatchups.length);
  let upcomingCreated = 0;

  for (let i = 0; i < allUpcomingMatchups.length; i++) {
    const [homeId, awayId, divisionId] = allUpcomingMatchups[i];
    const gameDate = upcomingDates[i];
    const homeName = ALL_TEAMS[homeId].name;
    const awayName = ALL_TEAMS[awayId].name;
    const venue = venueForTeam(homeId);
    const endTime = new Date(gameDate.getTime() + 2 * 3600000);

    await addDoc(`associations/${ASSOC}/events`, {
      title: `${homeName} vs ${awayName}`,
      type: 'game',
      statsStatus: 'pending',
      startTime: gameDate,
      endTime,
      location: venue,
      divisionId,
      seasonId: SEASON,
      teamIds: [homeId, awayId],
      createdBy: 'system',
      description: null,
    });

    upcomingCreated++;
  }
  console.log(`  ${upcomingCreated} upcoming games created`);

  // ─── Step 6b: Non-game calendar events ────────────────────────────────
  console.log('  Creating 5 calendar events...');

  const calendarEvents = [
    {
      title: 'Roster Lock Deadline',
      type: 'deadline',
      startTime: new Date('2026-03-15T23:59:00'),
      location: null,
      description: 'All team rosters must be finalized by midnight. No additions or changes after this date.',
    },
    {
      title: 'NBL All-Star Weekend',
      type: 'event',
      startTime: new Date('2026-04-18T14:00:00'),
      location: MAIN_VENUE,
      description: 'Annual All-Star game featuring the best players from the Premier Division. Skills challenge at 2pm, game at 7pm.',
    },
    {
      title: 'Playoff Bracket Announcement',
      type: 'meeting',
      startTime: new Date('2026-05-01T18:00:00'),
      location: 'JBA Headquarters, Kingston',
      description: 'Official announcement of playoff seedings and bracket. All team reps must attend.',
    },
    {
      title: 'End of Regular Season',
      type: 'deadline',
      startTime: new Date('2026-05-15T23:59:00'),
      location: null,
      description: 'Final day of regular season games. Playoff positions locked after tonight.',
    },
    {
      title: 'Coaches Meeting - Rule Changes',
      type: 'meeting',
      startTime: new Date('2026-04-05T10:00:00'),
      location: 'JBA Headquarters, Kingston',
      description: 'Discussion of proposed rule changes for the 2026-27 season. All head coaches invited.',
    },
  ];

  for (const evt of calendarEvents) {
    const endTime = new Date(evt.startTime.getTime() + 2 * 3600000);
    await addDoc(`associations/${ASSOC}/events`, {
      title: evt.title,
      type: evt.type,
      statsStatus: 'pending',
      startTime: evt.startTime,
      endTime,
      location: evt.location,
      divisionId: null,
      seasonId: SEASON,
      teamIds: [],
      createdBy: 'system',
      description: evt.description,
    });
  }
  console.log('  5 calendar events created');

  // ─── Step 7: playerSeasonStats ────────────────────────────────────────
  console.log('[8/12] Creating player season stats...');

  let playerCount = 0;
  for (const [pId, data] of Object.entries(playerSeasonData)) {
    const gp = data.games.length;
    if (gp === 0) continue;

    // Compute totals
    const totals = { pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, oreb: 0, dreb: 0, fls: 0, min: 0 };
    for (const g of data.games) {
      totals.pts += g.pts; totals.reb += g.reb; totals.ast += g.ast;
      totals.stl += g.stl; totals.blk += g.blk; totals.fls += g.fls;
      totals.min += g.min; totals.oreb += g.oreb; totals.dreb += g.dreb;
    }

    // Averages with standard keys ppg, rpg, apg, spg, bpg
    const averages = {
      ppg: round1(totals.pts / gp),
      rpg: round1(totals.reb / gp),
      apg: round1(totals.ast / gp),
      spg: round1(totals.stl / gp),
      bpg: round1(totals.blk / gp),
      pts: round1(totals.pts / gp),
      reb: round1(totals.reb / gp),
      ast: round1(totals.ast / gp),
      stl: round1(totals.stl / gp),
      blk: round1(totals.blk / gp),
    };

    // Game log entries (matching GameLogEntry model exactly)
    const gameLog = data.games.map(g => ({
      eventId: g.eventId,
      date: g.date,
      vs: g.vs,
      pts: g.pts,
      reb: g.reb,
      ast: g.ast,
      stl: g.stl,
      blk: g.blk,
      result: g.result,
    }));

    const docId = `${pId}_${SEASON}`;
    await patchDoc(`associations/${ASSOC}/playerSeasonStats`, docId, {
      playerId: pId,
      playerName: data.name,
      teamId: data.teamId,
      teamName: data.teamName,
      seasonId: SEASON,
      divisionId: data.divisionId,
      gamesPlayed: gp,
      totals,
      averages,
      gameLog,
    });
    playerCount++;
  }
  console.log(`  ${playerCount} player season stats created`);

  // ─── Step 8: teamSeasonStats ──────────────────────────────────────────
  console.log('[9/12] Creating team season stats...');

  // Aggregate team stats from player data
  const teamStatAgg = {}; // teamId -> { totals, gameLog, gamesPlayed }

  // Build team game-level data from completed matchups
  for (let i = 0; i < allCompletedMatchups.length; i++) {
    const [homeId, awayId, winnerId, divisionId] = allCompletedMatchups[i];
    const eventId = completedEventIds[i];
    const gameDate = completedDates[i];

    for (const teamId of [homeId, awayId]) {
      if (!teamStatAgg[teamId]) {
        teamStatAgg[teamId] = { gp: 0, totals: { pts: 0, oreb: 0, dreb: 0, reb: 0, ast: 0, stl: 0, blk: 0, to: 0, fls: 0, min: 0 }, gameLog: [] };
      }
      teamStatAgg[teamId].gp++;

      const opponentId = teamId === homeId ? awayId : homeId;
      const opponentName = ALL_TEAMS[opponentId].name;
      const isWin = teamId === winnerId;

      // Sum all player stats for this team in this game
      const gamePlayerStats = { pts: 0, oreb: 0, dreb: 0, reb: 0, ast: 0, stl: 0, blk: 0, fls: 0, min: 0 };
      for (const [pId, pData] of Object.entries(playerSeasonData)) {
        if (pData.teamId !== teamId) continue;
        const gameEntry = pData.games.find(g => g.eventId === eventId);
        if (!gameEntry) continue;
        gamePlayerStats.pts += gameEntry.pts;
        gamePlayerStats.oreb += gameEntry.oreb;
        gamePlayerStats.dreb += gameEntry.dreb;
        gamePlayerStats.reb += gameEntry.reb;
        gamePlayerStats.ast += gameEntry.ast;
        gamePlayerStats.stl += gameEntry.stl;
        gamePlayerStats.blk += gameEntry.blk;
        gamePlayerStats.fls += gameEntry.fls;
        gamePlayerStats.min += gameEntry.min;
      }

      // Accumulate totals
      for (const k of Object.keys(gamePlayerStats)) {
        teamStatAgg[teamId].totals[k] += gamePlayerStats[k];
      }
      teamStatAgg[teamId].totals.to += rand(8, 18); // turnovers are team-level

      teamStatAgg[teamId].gameLog.push({
        eventId,
        opponentName,
        date: gameDate,
        pts: gamePlayerStats.pts,
        oreb: gamePlayerStats.oreb,
        dreb: gamePlayerStats.dreb,
        reb: gamePlayerStats.reb,
        ast: gamePlayerStats.ast,
        stl: gamePlayerStats.stl,
        blk: gamePlayerStats.blk,
        to: rand(8, 18),
        fls: gamePlayerStats.fls,
        result: isWin ? 'W' : 'L',
      });
    }
  }

  let teamStatsCount = 0;
  for (const [teamId, agg] of Object.entries(teamStatAgg)) {
    const gp = agg.gp;
    if (gp === 0) continue;

    const averages = {
      ppg: round1(agg.totals.pts / gp),
      rpg: round1(agg.totals.reb / gp),
      apg: round1(agg.totals.ast / gp),
      spg: round1(agg.totals.stl / gp),
      bpg: round1(agg.totals.blk / gp),
      topg: round1(agg.totals.to / gp),
      fpg: round1(agg.totals.fls / gp),
    };

    const docId = `${teamId}_${SEASON}`;
    await patchDoc(`associations/${ASSOC}/teamSeasonStats`, docId, {
      teamId,
      teamName: ALL_TEAMS[teamId].name,
      seasonId: SEASON,
      divisionId: ALL_TEAMS[teamId].divisionId,
      gamesPlayed: gp,
      totals: agg.totals,
      averages,
      gameLog: agg.gameLog,
    });
    teamStatsCount++;
  }
  console.log(`  ${teamStatsCount} team season stats created`);

  // ─── Step 9: Standings ────────────────────────────────────────────────
  console.log('[10/12] Creating standings...');

  function buildStandings(teamIds, divisionId) {
    const sorted = teamIds
      .map(teamId => {
        const r = teamRecords[teamId];
        return {
          teamId,
          teamName: ALL_TEAMS[teamId].name,
          divisionId: ALL_TEAMS[teamId].divisionId,
          wins: r.w,
          losses: r.l,
          pct: r.w + r.l > 0 ? round1(r.w / (r.w + r.l) * 1000) / 1000 : 0,
          pointsFor: r.pf,
          pointsAgainst: r.pa,
        };
      })
      .sort((a, b) => b.pct - a.pct || (b.pointsFor - b.pointsAgainst) - (a.pointsFor - a.pointsAgainst));

    // Calculate GB from leader
    const leaderDiff = sorted[0].wins - sorted[0].losses;
    for (const t of sorted) {
      t.gb = (leaderDiff - (t.wins - t.losses)) / 2;
      t.streak = t.wins > t.losses ? `W${Math.min(t.wins, 3)}` : t.losses > t.wins ? `L${Math.min(t.losses, 3)}` : 'W1';
      t.lastTen = `${Math.min(t.wins, 7)}-${Math.min(t.losses, 3)}`;
    }
    return sorted;
  }

  const premierTeamIds = Object.keys(PREMIER_TEAMS);
  const womensTeamIds = Object.keys(WOMENS_TEAMS);

  const premierStandings = buildStandings(premierTeamIds, 'nbl-premier');
  const womensStandings = buildStandings(womensTeamIds, 'womens-league');
  const allStandings = [...premierStandings, ...womensStandings];

  await patchDoc(`associations/${ASSOC}/standings`, `${SEASON}_nbl-premier`, {
    seasonId: SEASON, divisionId: 'nbl-premier', updatedAt: new Date(), standings: premierStandings,
  });
  await patchDoc(`associations/${ASSOC}/standings`, `${SEASON}_womens-league`, {
    seasonId: SEASON, divisionId: 'womens-league', updatedAt: new Date(), standings: womensStandings,
  });
  await patchDoc(`associations/${ASSOC}/standings`, `${SEASON}_all`, {
    seasonId: SEASON, divisionId: null, updatedAt: new Date(), standings: allStandings,
  });
  console.log('  3 standings docs created (nbl-premier, womens-league, all)');

  // ─── Step 10: Leaderboards ────────────────────────────────────────────
  console.log('[11/12] Creating leaderboards...');

  const allPlayersForLB = Object.entries(playerSeasonData)
    .filter(([_, d]) => d.games.length >= 1)
    .map(([pId, d]) => {
      const gp = d.games.length;
      const totPts = d.games.reduce((s, g) => s + g.pts, 0);
      const totReb = d.games.reduce((s, g) => s + g.reb, 0);
      const totAst = d.games.reduce((s, g) => s + g.ast, 0);
      const totStl = d.games.reduce((s, g) => s + g.stl, 0);
      const totBlk = d.games.reduce((s, g) => s + g.blk, 0);
      return {
        playerId: pId,
        name: d.name,
        teamName: d.teamName,
        teamId: d.teamId,
        divisionId: d.divisionId,
        gp,
        ppg: round1(totPts / gp),
        rpg: round1(totReb / gp),
        apg: round1(totAst / gp),
        spg: round1(totStl / gp),
        bpg: round1(totBlk / gp),
      };
    });

  const categories = ['ppg', 'rpg', 'apg', 'spg', 'bpg'];
  const scopes = [
    { divisionId: null, label: 'all', filter: () => true },
    { divisionId: 'nbl-premier', label: 'nbl-premier', filter: p => p.divisionId === 'nbl-premier' },
  ];

  let lbCount = 0;
  for (const cat of categories) {
    for (const scope of scopes) {
      const filtered = allPlayersForLB.filter(scope.filter);
      const sorted = [...filtered].sort((a, b) => b[cat] - a[cat]).slice(0, 15);
      const docId = `${SEASON}_${scope.label}_${cat}`;

      await patchDoc(`associations/${ASSOC}/leaderboard`, docId, {
        seasonId: SEASON,
        divisionId: scope.divisionId,
        category: cat,
        updatedAt: new Date(),
        rankings: sorted.map(e => ({
          playerId: e.playerId,
          name: e.name,
          teamName: e.teamName,
          gp: e.gp,
          value: e[cat],
        })),
      });
      lbCount++;
    }
  }
  console.log(`  ${lbCount} leaderboard docs created`);

  // ─── Step 11: Board posts ─────────────────────────────────────────────
  console.log('[12/12] Creating board posts...');

  const boardPosts = [
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'NBL 2025-26 Season Officially Underway!',
      body: 'Welcome to the new season of the National Basketball League! We have 8 premier division teams and 4 women\'s league teams competing this year. Games begin November 4th at the National Indoor Sports Centre. Let\'s have a great season!',
      pinned: true, urgent: false, requiresAck: false,
      createdAt: new Date('2025-11-01T09:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'Week 3 Schedule Update - Additional Games Added',
      body: 'Due to venue availability, we have added Thursday night games starting Week 3. Games will now run Tuesday, Thursday, and Saturday. Please check the calendar for updated times.',
      pinned: false, urgent: false, requiresAck: false,
      createdAt: new Date('2025-11-20T14:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'Christmas Break - No Games Dec 20 to Jan 5',
      body: 'The league will be on break from December 20th through January 5th. No games or practices will be scheduled during this period. Games resume January 6th. All team representatives must acknowledge this notice.',
      pinned: true, urgent: false, requiresAck: true,
      ackDeadline: new Date('2025-12-19T23:59:00'),
      ackTargetScope: 'all-reps',
      createdAt: new Date('2025-12-18T10:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'URGENT: Venue Change for Feb 15 Games',
      body: 'Due to a scheduling conflict at the National Indoor Sports Centre, all games on February 15th have been moved to the National Arena, Kingston. Doors open at 6:00 PM. All reps must confirm receipt of this notice.',
      pinned: false, urgent: true, requiresAck: true,
      ackDeadline: new Date('2026-02-14T18:00:00'),
      ackTargetScope: 'all-reps',
      createdAt: new Date('2026-02-13T08:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'Player of the Month - January 2026',
      body: 'Congratulations to Ricardo Thompson (Portmore Flames) for being named NBL Player of the Month for January! Thompson averaged 24.5 points and 7.2 rebounds per game during the month. Honorable mention to Omar Barnes (Upper Room Eagles).',
      pinned: false, urgent: false, requiresAck: false,
      createdAt: new Date('2026-02-01T12:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'ROSTER LOCK DEADLINE - March 15, 2026',
      body: 'Reminder: All team rosters must be finalized by March 15, 2026 at 11:59 PM. After this date, no new players can be added. Trades and releases will still be allowed until the trade deadline (April 1). Each team rep must acknowledge this deadline.',
      pinned: true, urgent: true, requiresAck: true,
      ackDeadline: new Date('2026-03-14T23:59:00'),
      ackTargetScope: 'all-reps',
      createdAt: new Date('2026-03-10T09:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: "Women's League Update - Great Start to the Season",
      body: "The Women's National League is off to an exciting start! Kingston Queens lead the way with a 2-0 record. We encourage all fans to come out and support the women's games. Next women's game: Portmore Stars vs Montego Bay Angels.",
      pinned: false, urgent: false, requiresAck: false,
      createdAt: new Date('2026-03-10T15:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'refRequest', title: 'Referees Needed - This Week\'s Games',
      body: 'We are short on referees for the upcoming Tuesday and Thursday games. If you know any certified officials, please have them contact the JBA office. We need at least 2 additional refs for each game night. Compensation is standard JBA rates.',
      pinned: false, urgent: false, requiresAck: false,
      createdAt: new Date('2026-03-24T11:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'Player of the Month - March 2026',
      body: 'Congratulations to Omar Barnes (Upper Room Eagles) for being named NBL Player of the Month for March! Barnes averaged 26.1 points, 5.3 assists and 4.2 rebounds across 6 games as the Eagles went 5-1 on the month. Honorable mention to Brandon Taylor (St George\'s Slayers).',
      pinned: false, urgent: false, requiresAck: false,
      createdAt: new Date('2026-04-02T09:30:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'Playoff Race Update - 4 Weeks to Go',
      body: 'With only a handful of games left in the regular season, the top four seeds in the Premier Division are still up for grabs. Portmore Flames and Upper Room Eagles have clinched playoff spots, while Slayers, Knights and Warriors are fighting for the last two. Every game matters from here. Full standings and remaining schedule available in the app.',
      pinned: true, urgent: false, requiresAck: false,
      createdAt: new Date('2026-04-08T10:00:00'),
    },
    {
      authorId: 'system', authorName: 'JBA Admin', authorRole: 'admin',
      type: 'announcement', title: 'All-Star Weekend Reminder - April 18',
      body: 'Don\'t forget — NBL All-Star Weekend is this Saturday, April 18th at the National Indoor Sports Centre. Skills challenge tips off at 2pm, All-Star game at 7pm. All team reps must confirm their roster submissions by end of day Tuesday April 14th.',
      pinned: false, urgent: true, requiresAck: true,
      ackDeadline: new Date('2026-04-14T23:59:00'),
      ackTargetScope: 'all-reps',
      createdAt: new Date('2026-04-11T08:00:00'),
    },
  ];

  let postCount = 0;
  for (const post of boardPosts) {
    const postData = {
      authorId: post.authorId,
      authorName: post.authorName,
      authorRole: post.authorRole,
      teamId: null,
      teamName: null,
      type: post.type,
      title: post.title,
      body: post.body,
      imageUrl: null,
      divisionFilter: null,
      pinned: post.pinned,
      urgent: post.urgent,
      createdAt: post.createdAt,
      reactions: {},
      requiresAck: post.requiresAck,
      ackDeadline: post.ackDeadline || null,
      ackTargetScope: post.ackTargetScope || null,
      expectedAcks: {},
      ackStatus: {},
      ackRemindersSent: 0,
    };
    await addDoc(`associations/${ASSOC}/posts`, postData);
    postCount++;
  }
  console.log(`  ${postCount} board posts created`);

  // Invite credentials are never seeded or printed. Use the authorized
  // createPrivilegedInvite callable after the data seed completes.

  // ═══════════════════════════════════════════════════════════════════════
  // SUMMARY
  // ═══════════════════════════════════════════════════════════════════════

  console.log('');
  console.log('================================================================');
  console.log('  PREMIER DIVISION STANDINGS');
  console.log('================================================================');
  console.log('  #   Team                           W    L    PCT    PF    PA');
  console.log('  --- ------------------------------ ---- ---- ------ ----- -----');
  for (let i = 0; i < premierStandings.length; i++) {
    const t = premierStandings[i];
    const pctStr = t.pct > 0 ? `.${String(Math.round(t.pct * 1000)).padStart(3, '0')}` : '.000';
    console.log(
      `  ${String(i + 1).padStart(2)}.  ${t.teamName.padEnd(30)} ${String(t.wins).padStart(4)} ${String(t.losses).padStart(4)} ${pctStr.padStart(6)} ${String(t.pointsFor).padStart(5)} ${String(t.pointsAgainst).padStart(5)}`
    );
  }

  console.log('');
  console.log("  WOMEN'S LEAGUE STANDINGS");
  console.log('  --- ------------------------------ ---- ---- ------ ----- -----');
  for (let i = 0; i < womensStandings.length; i++) {
    const t = womensStandings[i];
    const pctStr = t.pct > 0 ? `.${String(Math.round(t.pct * 1000)).padStart(3, '0')}` : '.000';
    console.log(
      `  ${String(i + 1).padStart(2)}.  ${t.teamName.padEnd(30)} ${String(t.wins).padStart(4)} ${String(t.losses).padStart(4)} ${pctStr.padStart(6)} ${String(t.pointsFor).padStart(5)} ${String(t.pointsAgainst).padStart(5)}`
    );
  }

  // Top 5 scorers
  console.log('');
  console.log('  TOP 5 SCORERS (All Divisions)');
  console.log('  --- ---------------------- ------------------------------ -----');
  const topScorers = [...allPlayersForLB].sort((a, b) => b.ppg - a.ppg).slice(0, 5);
  for (let i = 0; i < topScorers.length; i++) {
    const p = topScorers[i];
    console.log(
      `  ${String(i + 1).padStart(2)}.  ${p.name.padEnd(22)} ${p.teamName.padEnd(30)} ${p.ppg} PPG (${p.gp} GP)`
    );
  }

  console.log('');
  console.log('================================================================');
  console.log('  SEED COMPLETE');
  console.log('================================================================');
  console.log(`  Association:     jba (Jamaica Basketball Association)`);
  console.log(`  Season:          ${SEASON}`);
  console.log(`  Divisions:       2 (Premier + Women's)`);
  console.log(`  Teams:           ${Object.keys(ALL_TEAMS).length} (${Object.keys(PREMIER_TEAMS).length} premier + ${Object.keys(WOMENS_TEAMS).length} women's)`);
  console.log(`  Completed games: ${gamesCreated} (with full box scores)`);
  console.log(`  Upcoming games:  ${upcomingCreated}`);
  console.log(`  Calendar events: 5`);
  console.log(`  Player stats:    ${playerCount}`);
  console.log(`  Team stats:      ${teamStatsCount}`);
  console.log(`  Standings:       3 docs`);
  console.log(`  Leaderboards:    ${lbCount} docs`);
  console.log(`  Board posts:     ${postCount}`);
  console.log('  Invite codes:    not seeded');
  console.log('================================================================');
  console.log('');
}

seed().catch(err => {
  console.error('Seed failed:', err.message);
  console.error(err.stack);
  process.exit(1);
});
