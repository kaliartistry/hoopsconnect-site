#!/usr/bin/env node
// Seed script for HoopsConnect Firestore
// Uses Firebase REST API with the firebase CLI auth token

const { execSync } = require('child_process');
const https = require('https');
const http = require('http');
const {guardFirestoreTarget} = require('./lib/firebase_target_guard');

const TARGET = guardFirestoreTarget({mode: 'write'});
const PROJECT_ID = TARGET.projectId;
const BASE_URL = TARGET.baseUrl;
const firestoreTransport = TARGET.isEmulator ? http : https;

// Get the auth token from firebase CLI
function getToken() {
  if (TARGET.isEmulator) return null;
  // Read the firebase token from the config file
  const os = require('os');
  const fs = require('fs');
  const path = require('path');

  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (fs.existsSync(configPath)) {
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    if (config.tokens && config.tokens.access_token) {
      return config.tokens.access_token;
    }
    if (config.tokens && config.tokens.refresh_token) {
      // Use firebase CLI to get a fresh token
      try {
        const result = execSync('firebase --non-interactive login:ci 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();
        if (result) return result;
      } catch {}
    }
  }

  // Fallback: try to get token via firebase CLI
  try {
    const token = execSync('cat ~/.config/configstore/firebase-tools.json | node -e "process.stdin.resume(); let d=\\"\\"; process.stdin.on(\\"data\\", c => d+=c); process.stdin.on(\\"end\\", () => { const j=JSON.parse(d); console.log(j.tokens.access_token); })"',
      { encoding: 'utf8' }).trim();
    return token;
  } catch {
    throw new Error('Could not get Firebase auth token. Run: firebase login');
  }
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
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
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

async function addDoc(collection, data) {
  const doc = makeDoc(data);
  return request('POST', `/${collection}`, doc);
}

async function seed() {
  console.log('Seeding HoopsConnect Firestore...\n');
  const assocId = 'jba';

  // 1. Association
  await createDoc('associations', assocId, {
    name: 'Jamaica Basketball Association',
    logoUrl: null,
    currentSeasonId: 'spring-2026',
    createdAt: new Date(),
  });
  console.log('✓ Association created');

  // 2. Season
  await createDoc(`associations/${assocId}/seasons`, 'spring-2026', {
    name: 'Spring 2026',
    startDate: new Date('2026-02-01'),
    endDate: new Date('2026-06-30'),
    isActive: true,
  });
  console.log('✓ Season created');

  // 3. Divisions
  const divisions = [
    { id: 'mens-open', name: "Men's Open" },
    { id: 'womens-30', name: "Women's 30+" },
    { id: 'co-ed', name: 'Co-Ed' },
  ];
  for (const div of divisions) {
    await createDoc(`associations/${assocId}/divisions`, div.id, {
      name: div.name,
      seasonId: 'spring-2026',
    });
  }
  console.log('✓ 3 divisions created');

  // 4. Teams
  const teams = [
    { id: 'thunderbolts', name: 'Thunderbolts', divisionId: 'mens-open' },
    { id: 'blazers', name: 'Blazers', divisionId: 'mens-open' },
    { id: 'raptors', name: 'Raptors', divisionId: 'mens-open' },
    { id: 'hawks', name: 'Hawks', divisionId: 'mens-open' },
    { id: 'nets', name: 'Nets', divisionId: 'mens-open' },
    { id: 'celtics', name: 'Celtics', divisionId: 'mens-open' },
    { id: 'lady-hoops', name: 'Lady Hoops', divisionId: 'womens-30' },
    { id: 'storm', name: 'Storm', divisionId: 'womens-30' },
    { id: 'phoenix', name: 'Phoenix', divisionId: 'co-ed' },
    { id: 'wildcats', name: 'Wildcats', divisionId: 'co-ed' },
  ];
  for (const team of teams) {
    await createDoc(`associations/${assocId}/teams`, team.id, {
      name: team.name,
      divisionId: team.divisionId,
      seasonId: 'spring-2026',
      logoUrl: null,
      repIds: [],
    });
  }
  console.log('✓ 10 teams created');

  // 5. Invite codes
  const inviteCodes = [
    { code: 'THUNDER-2026', teamId: 'thunderbolts', role: 'rep', usesRemaining: 5 },
    { code: 'BLAZERS-2026', teamId: 'blazers', role: 'rep', usesRemaining: 5 },
    { code: 'RAPTORS-2026', teamId: 'raptors', role: 'rep', usesRemaining: 5 },
    { code: 'MEDIA-2026', teamId: '', role: 'media', usesRemaining: 10 },
    { code: 'ADMIN-2026', teamId: '', role: 'admin', usesRemaining: 3 },
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
  console.log('✓ 5 invite codes created');

  // 6. Sample posts
  const posts = [
    {
      authorId: 'system', authorName: 'Commissioner Davis', authorRole: 'admin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'Gym 3 Closed This Saturday — All Games Relocated',
      body: 'All Saturday games at Lincoln Rec Gym 3 relocated to Washington Community Center. Game times unchanged.',
      imageUrl: null, divisionFilter: null, pinned: true, urgent: true,
      createdAt: new Date(), reactions: {}, requiresAck: true,
      ackDeadline: new Date('2026-03-07T18:00:00'), ackTargetScope: 'all',
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'Commissioner Davis', authorRole: 'admin',
      teamId: null, teamName: null, type: 'announcement',
      title: 'Spring 2026 Registration Deadline — March 15',
      body: 'All team rosters must be finalized by March 15.',
      imageUrl: null, divisionFilter: null, pinned: true, urgent: false,
      createdAt: new Date('2026-02-25'), reactions: {}, requiresAck: true,
      ackDeadline: new Date('2026-03-14T18:00:00'), ackTargetScope: 'all',
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
    {
      authorId: 'system', authorName: 'Mike R.', authorRole: 'rep',
      teamId: 'thunderbolts', teamName: 'Thunderbolts', type: 'refRequest',
      title: 'Need 1 Ref for Saturday 2PM Game',
      body: 'Looking for a certified ref. $45/game.',
      imageUrl: null, divisionFilter: "Men's Open", pinned: false, urgent: false,
      createdAt: new Date('2026-02-27T04:00:00'), reactions: {},
      requiresAck: false, ackDeadline: null, ackTargetScope: null,
      expectedAcks: {}, ackStatus: {}, ackRemindersSent: 0,
    },
  ];
  for (const post of posts) {
    await addDoc(`associations/${assocId}/posts`, post);
  }
  console.log('✓ 3 sample posts created');

  // 7. Sample events
  const events = [
    {
      title: 'Thunderbolts vs Blazers', type: 'game',
      startTime: new Date('2026-03-07T14:00:00'),
      endTime: new Date('2026-03-07T15:30:00'),
      location: 'Washington CC', divisionId: 'mens-open',
      teamIds: ['thunderbolts', 'blazers'], description: null,
      createdBy: 'system', statsStatus: 'pending',
    },
    {
      title: 'Nets vs Hawks', type: 'game',
      startTime: new Date('2026-03-07T15:30:00'),
      endTime: new Date('2026-03-07T17:00:00'),
      location: 'Washington CC', divisionId: 'mens-open',
      teamIds: ['nets', 'hawks'], description: null,
      createdBy: 'system', statsStatus: 'pending',
    },
    {
      title: 'Roster Deadline', type: 'deadline',
      startTime: new Date('2026-03-15T18:00:00'), endTime: null,
      location: null, divisionId: null, teamIds: [],
      description: 'All rosters must be finalized',
      createdBy: 'system', statsStatus: 'pending',
    },
  ];
  for (const event of events) {
    await addDoc(`associations/${assocId}/events`, event);
  }
  console.log('✓ 3 sample events created');

  console.log('\n🏀 Seed complete!\n');
  console.log('Invite codes:');
  console.log('  THUNDER-2026  → Thunderbolts (rep)');
  console.log('  BLAZERS-2026  → Blazers (rep)');
  console.log('  RAPTORS-2026  → Raptors (rep)');
  console.log('  MEDIA-2026    → Media role');
  console.log('  ADMIN-2026    → Admin role');
}

seed().catch(err => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
