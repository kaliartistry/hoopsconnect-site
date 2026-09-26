#!/usr/bin/env node
'use strict';

const path = require('node:path');

const PROJECT_ID = 'demo-hoopsconnect-stage0-platform';
const ASSOCIATION_ID = 'jba';
const EMPTY_ASSOCIATION_ID = 'jba-empty';
const PASSWORD = 'LocalQa-Only-42!';
const LOOPBACK = /^(?:localhost|127\.0\.0\.1|\[::1\]):\d+$/;
const QA_FIXTURE_VERSION = 5;
const AUTHORIZATION_SCHEMA_PATH = path.resolve(
  __dirname,
  '../../functions/src/authorization_schema_v1.json',
);
const authorizationSchema = require(AUTHORIZATION_SCHEMA_PATH);
const AUTHORIZATION_SCHEMA_VERSION = authorizationSchema.schemaVersion;
const roles = Object.freeze(
  Object.entries(authorizationSchema.roles).map(([role, capabilities]) =>
    Object.freeze([role, Object.freeze([...capabilities])])),
);

const TEAM_FIXTURES = Object.freeze([
  // The 10-team NBL field follows the complete roster reported for the 2023
  // restart. It is presentation reference data, not a claim about 2026 entry.
  {id: 'st-georges-slayers', name: 'St George’s Slayers', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'uwi-running-rebels', name: 'UWI Running Rebels', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'rae-town-raptors', name: 'Rae Town Raptors', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'urban-knights', name: 'Urban Knights', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'upper-room-eagles', name: 'Upper Room Eagles', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'tivoli-wizards', name: 'Tivoli Wizards', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'falmouth-saints', name: 'Falmouth Saints', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'central-celtics', name: 'Central Celtics', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'spanish-town-spartans', name: 'Spanish Town Spartans', divisionId: 'premier', fixtureSource: 'reported'},
  {id: 'portmore-flames', name: 'Portmore Flames', divisionId: 'premier', fixtureSource: 'reported'},

  // No reliable current women's club roster is publicly listed. These are
  // explicitly fictional presentation teams and must not be described as an
  // official JBA field.
  {id: 'kingston-royals-women', name: 'Kingston Royals', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'portmore-queens', name: 'Portmore Queens', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'spanish-town-phoenix', name: 'Spanish Town Phoenix', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'montego-bay-tides', name: 'Montego Bay Tides', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'mandeville-monarchs', name: 'Mandeville Monarchs', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'st-andrew-suns', name: 'St Andrew Suns', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'clarendon-comets', name: 'Clarendon Comets', divisionId: 'development', fixtureSource: 'fictional'},
  {id: 'st-ann-storm', name: 'St Ann Storm', divisionId: 'development', fixtureSource: 'fictional'},

  // School names are drawn from recent ISSA basketball reporting. Division
  // placement is a synthetic demonstration of the parent-child league model.
  {id: 'campion-college', name: 'Campion College', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'st-georges-college', name: 'St George’s College', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'st-catherine-high', name: 'St Catherine High', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'camperdown-high', name: 'Camperdown High', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'jamaica-college', name: 'Jamaica College', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'calabar-high', name: 'Calabar High', divisionId: 'schoolboy-a', fixtureSource: 'reported'},
  {id: 'ardenne-high', name: 'Ardenne High', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'kingston-college', name: 'Kingston College', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'st-andrew-technical', name: 'St Andrew Technical', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'bridgeport-high', name: 'Bridgeport High', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'vauxhall-high', name: 'Vauxhall High', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'yallahs-high', name: 'Yallahs High', divisionId: 'schoolboy-b', fixtureSource: 'reported'},
  {id: 'manchester-high', name: 'Manchester High', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'herbert-morrison-technical', name: 'Herbert Morrison Technical', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'knox-college', name: 'Knox College', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'york-castle-high', name: 'York Castle High', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'ocho-rios-high', name: 'Ocho Rios High', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'munro-college', name: 'Munro College', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'christiana-high', name: 'Christiana High', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'st-elizabeth-technical', name: 'St Elizabeth Technical', divisionId: 'schoolboy-c', fixtureSource: 'reported'},
  {id: 'the-queens-school-girls', name: 'The Queen’s School', divisionId: 'schoolgirls', fixtureSource: 'reported'},
  {id: 'st-andrew-high-girls', name: 'St Andrew High', divisionId: 'schoolgirls', fixtureSource: 'reported'},
  {id: 'st-andrew-technical-girls', name: 'St Andrew Technical Girls', divisionId: 'schoolgirls', fixtureSource: 'reported'},
  {id: 'camperdown-high-girls', name: 'Camperdown High Girls', divisionId: 'schoolgirls', fixtureSource: 'reported'},
]);

const PLAYER_NAMES = Object.freeze({
  'st-georges-slayers': ['Andre Blake', 'Dwayne Campbell', 'Malik Grant', 'Omar Reid', 'Tevin Brown', 'Kemar Lewis'],
  'uwi-running-rebels': ['Jordan Clarke', 'Akeem Foster', 'Ricardo Hill', 'Noel Morgan', 'Shawn Powell', 'Troy Williams'],
  'kingston-royals-women': ['Daniella Bennett', 'Jada Cole', 'Naomi Davis', 'Renee Ellis', 'Kayla Francis', 'Monique Green'],
  'portmore-queens': ['Amari Henry', 'Joelle Irving', 'Keisha James', 'Leah King', 'Michaela Lawson', 'Natalie Miller'],
  'campion-college': ['Jaden Adams', 'Kyle Bailey', 'Micah Chambers', 'Nathan Dale', 'Owen Edwards', 'Tyler Forbes'],
  'st-georges-college': ['Aaron Gordon', 'Brian Harris', 'Cory Irving', 'Dylan Johnson', 'Ethan King', 'Fabian Lee'],
});
const ROSTERED_TEAM_COUNT = Object.keys(PLAYER_NAMES).length;
const PLAYER_FIXTURE_COUNT = Object.values(PLAYER_NAMES).reduce(
  (total, names) => total + names.length,
  0,
);

function requireSafeEnvironment(env = process.env) {
  if (env.GCLOUD_PROJECT !== PROJECT_ID) {
    throw new Error(`GCLOUD_PROJECT must be ${PROJECT_ID}.`);
  }
  for (const name of [
    'FIREBASE_AUTH_EMULATOR_HOST',
    'FIRESTORE_EMULATOR_HOST',
    'FUNCTIONS_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
  ]) {
    if (!LOOPBACK.test(env[name] || '')) {
      throw new Error(`${name} must be an explicit loopback emulator endpoint.`);
    }
  }
  for (const name of [
    'FIREBASE_TOKEN',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'GOOGLE_CLOUD_ACCESS_TOKEN',
    'CLOUDSDK_AUTH_ACCESS_TOKEN',
  ]) {
    if (env[name]) throw new Error(`${name} is forbidden in local QA.`);
  }
}

async function probeCallable(env = process.env) {
  const endpoint =
    `http://${env.FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/us-central1/` +
    'inspectPrivilegedInvite';
  const deadline = Date.now() + 30000;
  let last;
  while (Date.now() < deadline) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        data: {
          code: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
        },
      }),
    });
    const responseText = await response.text();
    try {
      const body = JSON.parse(responseText);
      if (!response.ok && body?.error?.status === 'NOT_FOUND') return;
      last = `${response.status} ${JSON.stringify(body)}`;
    } catch (_error) {
      last = `${response.status} ${responseText.slice(0, 160)}`;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Functions emulator callable probe did not become ready: ${last}`);
}

function firebaseAdmin() {
  return require(path.resolve(__dirname, '../../functions/node_modules/firebase-admin'));
}

function publicSnapshotBuilder() {
  return require(
    path.resolve(__dirname, '../../public_functions/lib/index.js'),
  ).buildPublicSnapshot;
}

function certifyQaLegacySnapshot(candidate) {
  if (
    candidate?.schemaVersion !== 1 ||
    candidate?.contractVersion !== 'legacy-public-snapshot-v1.1' ||
    candidate?.published !== true ||
    candidate?.publication?.state !== 'published'
  ) {
    throw new Error('Only a published legacy v1.1 QA snapshot can be certified.');
  }
  return {
    ...candidate,
    certificationStatus: 'certified',
    publication: {
      ...candidate.publication,
      verificationStatus: 'legacyApproved',
    },
  };
}

function identity(role, dataset) {
  const suffix = dataset === 'empty' ? '-empty' : '';
  return {
    uid: `qa-${role.toLowerCase()}${suffix}`,
    email: `${role.toLowerCase()}${suffix}@hoopsconnect.test`,
    displayName: `QA ${role}${dataset === 'empty' ? ' Empty' : ''}`,
  };
}

async function upsertIdentity(auth, user) {
  try {
    await auth.updateUser(user.uid, {
      email: user.email,
      password: PASSWORD,
      displayName: user.displayName,
      disabled: false,
    });
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    await auth.createUser({...user, password: PASSWORD, emailVerified: true});
  }
}

function profile(user, role, associationId, teamId) {
  return {
    email: user.email,
    displayName: user.displayName,
    associationId,
    role,
    teamId: teamId || null,
    divisionId: teamId ? 'premier' : null,
    fcmTokens: [],
    notificationPrefs: {
      ackReminders: false,
      statReminders: false,
      newPosts: false,
      favoriteTeamUpdates: true,
    },
    favoriteLeagueIds: [],
    favoriteTeamIds: [],
    authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    qaFixtureVersion: QA_FIXTURE_VERSION,
  };
}

function membership(user, role, capabilities, associationId, teamId) {
  return {
    associationId,
    role,
    capabilities,
    status: 'active',
    authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    teamId: teamId || null,
    divisionId: teamId ? 'premier' : null,
    qaFixtureVersion: QA_FIXTURE_VERSION,
  };
}

async function seedIdentities(auth, db) {
  const writes = [];
  for (const [role, capabilities] of roles) {
    for (const dataset of ['full', 'empty']) {
      const user = identity(role, dataset);
      const associationId = dataset === 'full' ? ASSOCIATION_ID : EMPTY_ASSOCIATION_ID;
      const teamId = role === 'rep' ? 'st-georges-slayers' : null;
      await upsertIdentity(auth, user);
      writes.push(
        db.doc(`users/${user.uid}`).set(profile(user, role, associationId, teamId)),
        db.doc(`memberships/${user.uid}`).set(
          membership(user, role, capabilities, associationId, teamId),
        ),
      );
    }
  }
  await Promise.all(writes);
}

async function seedLeague(db, admin) {
  const timestamp = admin.firestore.Timestamp;
  const seasonId = 'qa-2026';
  const competitionId = 'qa-nbl';
  const updatedAt = timestamp.fromDate(new Date('2026-09-01T12:00:00.000Z'));
  const batch = db.batch();
  const set = (documentPath, value) => batch.set(db.doc(documentPath), value);

  const rosteredTeams = TEAM_FIXTURES.filter((team) => PLAYER_NAMES[team.id]);
  const players = rosteredTeams.flatMap((team, teamIndex) =>
    PLAYER_NAMES[team.id].map((name, index) => ({
      id: `${team.id}-p${index + 1}`,
      name,
      teamId: team.id,
      teamName: team.name,
      divisionId: team.divisionId,
      jerseyNumber: index === 0 ? '0' : index === 1 ? '00' : String(index + 2),
      position: ['PG', 'SG', 'SF', 'PF', 'C', 'G'][index],
      gamesPlayed: 1,
      ppg: 18.4 - teamIndex - index * 0.7,
      rpg: 8.1 - index * 0.4 + teamIndex * 0.2,
      apg: 6.8 - index * 0.5 + teamIndex * 0.1,
    })),
  );

  const playersFor = (teamId) => players.filter((player) => player.teamId === teamId);
  const playerLines = (teamIds, pointTargets) => {
    const result = {};
    teamIds.forEach((teamId, teamIndex) => {
      const teamPlayers = playersFor(teamId);
      const points = pointTargets[teamIndex];
      const distribution = [points - 42, 13, 11, 9, 5, 4];
      teamPlayers.forEach((player, index) => {
        const oreb = index % 3;
        const dreb = 2 + ((index + teamIndex) % 5);
        result[player.id] = {
          name: player.name,
          teamId,
          pts: distribution[index],
          oreb,
          dreb,
          reb: oreb + dreb,
          ast: Math.max(1, 6 - index),
          stl: index % 3,
          blk: index % 2,
          fls: 1 + (index % 3),
          min: 30 + (index % 4),
        };
      });
    });
    return result;
  };
  const publicPlayerLines = (teamIds, pointTargets) =>
    Object.entries(playerLines(teamIds, pointTargets)).map(
      ([playerId, line]) => ({
        playerId,
        publicDisplayName: line.name,
        teamId: line.teamId,
        minutes: line.min,
        points: line.pts,
        offensiveRebounds: line.oreb,
        defensiveRebounds: line.dreb,
        assists: line.ast,
        steals: line.stl,
        blocks: line.blk,
        fouls: line.fls,
      }),
    );

  const divisionTeams = new Map();
  for (const team of TEAM_FIXTURES) {
    const existing = divisionTeams.get(team.divisionId) || [];
    existing.push(team);
    divisionTeams.set(team.divisionId, existing);
  }
  const standings = [...divisionTeams.values()].flatMap((teams) => {
    const gamesPlayed = Math.max(teams.length - 1, 1);
    return teams.map((team, index) => {
      const wins = Math.max(gamesPlayed - index, 0);
      const losses = gamesPlayed - wins;
      const pointsFor = 690 - index * 17 + teams.length * 8;
      const pointsAgainst = 610 + index * 14 + teams.length * 5;
      const pct = wins / gamesPlayed;
      return {
        teamId: team.id,
        teamName: team.name,
        divisionId: team.divisionId,
        rank: index + 1,
        rankStatus: 'ranked',
        wins,
        losses,
        pct,
        gb: index,
        streak: wins >= losses ? `W${Math.min(3, Math.max(1, wins))}` : `L${Math.min(3, Math.max(1, losses))}`,
        lastTen: `${wins}-${losses}`,
        pointsFor,
        pointsAgainst,
      };
    });
  });

  set(`associations/${ASSOCIATION_ID}`, {
    name: 'Jamaica Basketball Association',
    shortName: 'JBA',
    currentSeasonId: seasonId,
    primaryColor: '#2E7D32',
    brandingV1: {
      schemaVersion: 1,
      leagueName: 'Jamaica Basketball Association',
      shortName: 'Jamaica Basketball',
      logoUrl: 'asset:assets/images/jba_logo.png',
      primaryColorHex: '#2E7D32',
      secondaryColorHex: '#1B5E20',
      accentColorHex: '#F9A825',
      sponsor: {
        enabled: true,
        name: 'Kingston Flame Kitchen',
        label: 'Association partner',
        logoUrl: 'asset:assets/images/sponsor_kingston_flame.png',
        websiteUrl: null,
      },
    },
    leagueCatalogV1: {
      schemaVersion: 1,
      leagues: [
        {
          leagueId: 'nbl', name: 'National Basketball League', shortName: 'NBL',
          description: 'Jamaica national club competition', divisionIds: ['premier', 'division-2', 'division-3', 'community'],
          status: 'active', sortOrder: 0,
          branding: {schemaVersion: 1, logoUrl: 'asset:assets/images/nbl_jamaica_logo.png', primaryColorHex: '#234EBD', secondaryColorHex: '#102A70', accentColorHex: '#F2B632', sponsor: {enabled: true, name: 'ShipSafe SDK', label: 'Title sponsor', logoUrl: 'asset:assets/images/sponsor_shipsafe.png', websiteUrl: 'https://shipsafesdk.com'}},
        },
        {
          leagueId: 'womens', name: 'Women’s League', shortName: 'Women’s',
          description: 'Women’s national competition', divisionIds: ['development'],
          status: 'active', sortOrder: 1,
          branding: {schemaVersion: 1, primaryColorHex: '#7B1FA2', secondaryColorHex: '#4A148C', accentColorHex: '#F9A825', sponsor: {enabled: true, name: 'Bank of Kingston', label: 'Title sponsor', logoUrl: 'asset:assets/images/sponsor_bank_of_kingston.png'}},
        },
        {
          leagueId: 'schools', name: 'Schoolboy League', shortName: 'Schools',
          description: 'Schoolboy and girls basketball', divisionIds: ['schoolboy-a', 'schoolboy-b', 'schoolboy-c', 'schoolgirls'],
          status: 'active', sortOrder: 2,
          branding: {schemaVersion: 1, primaryColorHex: '#1565C0', secondaryColorHex: '#0D47A1', accentColorHex: '#FFB300', sponsor: {enabled: true, name: 'YardCourt Sporting Co.', label: 'Title sponsor', logoUrl: 'asset:assets/images/sponsor_yardcourt.png'}},
        },
      ],
    },
    publicLeagueState: 'published',
    publicPrivacyEpoch: 1,
    standingsPolicyLabel:
      'Winning percentage; unresolved ties remain tied',
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });

  const seasonFixtures = [
    {id: 'qa-2025-archived', name: '2025 Season', status: 'archived', start: '2025-01-01T05:00:00.000Z', end: '2025-12-31T05:00:00.000Z'},
    {id: seasonId, name: '2026 Season', status: 'active', start: '2026-01-01T05:00:00.000Z', end: '2026-12-31T05:00:00.000Z'},
    {id: 'qa-2027-draft', name: '2027 Season', status: 'draft', start: '2027-01-01T05:00:00.000Z', end: '2027-12-31T05:00:00.000Z'},
  ];
  for (const season of seasonFixtures) {
    set(`associations/${ASSOCIATION_ID}/seasons/${season.id}`, {
      name: season.name,
      status: season.status,
      startDate: timestamp.fromDate(new Date(season.start)),
      endDate: timestamp.fromDate(new Date(season.end)),
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  for (const [id, name, leagueId] of [
    ['premier', 'Premier', 'nbl'],
    ['division-2', 'Division 2', 'nbl'],
    ['division-3', 'Division 3', 'nbl'],
    ['community', 'Community League', 'nbl'],
    ['development', 'Premier Division', 'womens'],
    ['schoolboy-a', 'Division A', 'schools'],
    ['schoolboy-b', 'Division B', 'schools'],
    ['schoolboy-c', 'Division C', 'schools'],
    ['schoolgirls', 'Girls Division', 'schools'],
  ]) {
    set(`associations/${ASSOCIATION_ID}/divisions/${id}`, {
      name, leagueId, seasonId, status: 'active', version: 1,
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  for (const team of TEAM_FIXTURES) {
    set(`associations/${ASSOCIATION_ID}/teams/${team.id}`, {
      name: team.name,
      divisionId: team.divisionId,
      seasonId,
      repIds: team.id === 'st-georges-slayers' ? ['qa-rep'] : [],
      presentationFixtureSource: team.fixtureSource,
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
    set(`associations/${ASSOCIATION_ID}/teamSeasonStats/${team.id}_${seasonId}`, {
      teamId: team.id,
      teamName: team.name,
      seasonId,
      divisionId: team.divisionId,
      gamesPlayed: 1,
      totals: {pts: 700, oreb: 92, dreb: 211, reb: 303, ast: 148, stl: 61, blk: 33, to: 102, fls: 133, min: 1800},
      averages: {ppg: 77.8, rpg: 33.7, apg: 16.4, spg: 6.8, bpg: 3.7, topg: 11.3, fpg: 14.8},
      gameLog: [],
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }

  set(`associations/${ASSOCIATION_ID}/posts/qa-public-welcome`, {
    authorId: 'qa-superadmin',
    authorName: 'QA Super Admin',
    authorRole: 'superAdmin',
    type: 'announcement',
    title: 'Welcome to the HoopsConnect presentation',
    body:
      'Use this synthetic workspace to review schedules, standings, league communications, statistics, and role-based administration.',
    imageUrl: null,
    divisionFilter: null,
    pinned: true,
    urgent: false,
    visibility: 'public',
    archived: false,
    createdAt: updatedAt,
    reactions: {},
    requiresAck: false,
    ackDeadline: null,
    ackTargetScope: 'all',
    expectedAcks: {},
    ackStatus: {},
    ackRemindersSent: 0,
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  for (const story of [
    {
      id: 'qa-media-nbl-opening-night',
      title: 'NBL opening night sets the tone',
      body:
        'St George’s Slayers and UWI Running Rebels delivered a close presentation matchup at the National Indoor Sports Centre. Open the published game to review the score, quarter totals, and player box score.',
      divisionFilter: 'premier',
      createdAt: '2026-09-13T15:00:00.000Z',
    },
    {
      id: 'qa-media-womens-preview',
      title: 'Women’s League presentation field is ready',
      body:
        'Eight presentation clubs are now organized inside the Women’s League. The field is synthetic until the association supplies and approves the official current team list.',
      divisionFilter: 'development',
      createdAt: '2026-09-12T15:00:00.000Z',
    },
    {
      id: 'qa-media-schools-weekend',
      title: 'School League divisions take shape',
      body:
        'Recent Jamaican school basketball programs are displayed beneath Division A, Division B, Division C, and Girls. The placement demonstrates the league hierarchy and is not an official ISSA classification.',
      divisionFilter: 'schoolboy-a',
      createdAt: '2026-09-11T15:00:00.000Z',
    },
  ]) {
    set(`associations/${ASSOCIATION_ID}/posts/${story.id}`, {
      authorId: 'qa-media',
      authorName: 'HoopsConnect Media Desk',
      authorRole: 'media',
      type: 'general',
      title: story.title,
      body: story.body,
      imageUrl: null,
      divisionFilter: story.divisionFilter,
      pinned: false,
      urgent: false,
      visibility: 'public',
      archived: false,
      createdAt: timestamp.fromDate(new Date(story.createdAt)),
      reactions: {},
      requiresAck: false,
      ackDeadline: null,
      ackTargetScope: 'all',
      expectedAcks: {},
      ackStatus: {},
      ackRemindersSent: 0,
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  set(`associations/${ASSOCIATION_ID}/posts/qa-game-day-check-in`, {
    authorId: 'qa-superadmin',
    authorName: 'QA Super Admin',
    authorRole: 'superAdmin',
    type: 'general',
    title: 'Game-day operations check-in',
    body:
      'Please confirm the roster and venue details for the next scheduled fixture.',
    imageUrl: null,
    divisionFilter: 'premier',
    pinned: false,
    urgent: true,
    visibility: 'internal',
    archived: false,
    createdAt: updatedAt,
    reactions: {},
    requiresAck: true,
    ackDeadline: timestamp.fromDate(new Date('2026-10-15T17:00:00.000Z')),
    ackTargetScope: 'division',
    expectedAcks: {
      'qa-rep': {name: 'QA rep', teamName: 'St George’s Slayers'},
    },
    ackStatus: {},
    ackRemindersSent: 0,
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });

  for (const [index, player] of players.entries()) {
    const totals = {
      pts: Math.round(player.ppg * player.gamesPlayed),
      reb: Math.round(player.rpg * player.gamesPlayed),
      ast: Math.round(player.apg * player.gamesPlayed),
      stl: 5 + (index % 8),
      blk: 2 + (index % 5),
      min: 150 + (index % 20),
      fls: 8 + (index % 7),
      oreb: 5 + (index % 6),
      dreb: Math.max(0, Math.round(player.rpg * player.gamesPlayed) - (5 + (index % 6))),
    };
    set(`associations/${ASSOCIATION_ID}/playerSeasonStats/${player.id}_${seasonId}`, {
      playerId: player.id,
      playerName: player.name,
      teamId: player.teamId,
      teamName: player.teamName,
      seasonId,
      divisionId: player.divisionId,
      jerseyNumber: player.jerseyNumber,
      position: player.position,
      registrationStatus: index % 6 === 5 ? 'pendingReview' : 'eligible',
      gamesPlayed: player.gamesPlayed,
      totals,
      averages: {ppg: player.ppg, rpg: player.rpg, apg: player.apg, spg: totals.stl / 5, bpg: totals.blk / 5},
      gameLog: [],
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }

  const games = [
    {id: 'qa-final-game', home: 'st-georges-slayers', away: 'uwi-running-rebels', divisionId: 'premier', start: '2026-08-20T00:00:00.000Z', venue: 'National Indoor Sports Centre', statsStatus: 'approved', status: 'approved', score: [82, 76], quarters: [[21, 19, 20, 22], [18, 20, 19, 19]]},
    {id: 'qa-overtime-final', home: 'kingston-royals-women', away: 'portmore-queens', divisionId: 'development', start: '2026-08-27T00:00:00.000Z', venue: 'GC Foster College', statsStatus: 'approved', status: 'approved', score: [91, 88], quarters: [[18, 21, 24, 22, 6], [20, 19, 23, 23, 3]]},
    {id: 'qa-awaiting-review', home: 'uwi-running-rebels', away: 'st-georges-slayers', divisionId: 'premier', start: '2026-09-03T00:00:00.000Z', venue: 'Montego Bay Community Centre', statsStatus: 'submitted', status: 'submitted', score: [74, 78], quarters: [[17, 19, 20, 18], [20, 18, 21, 19]]},
    {id: 'qa-changes-requested', home: 'portmore-queens', away: 'kingston-royals-women', divisionId: 'development', start: '2026-09-05T22:00:00.000Z', venue: 'Portmore HEART Academy', statsStatus: 'submitted', status: 'rejected', score: [69, 72], quarters: [[16, 18, 17, 18], [18, 16, 20, 18]]},
    {id: 'qa-in-progress', home: 'st-georges-slayers', away: 'uwi-running-rebels', divisionId: 'premier', start: '2026-09-10T23:00:00.000Z', venue: 'National Indoor Sports Centre', statsStatus: 'pending', status: 'inProgress', score: [38, 35], quarters: [[19, 19], [17, 18]]},
    {id: 'qa-upcoming-game', home: 'uwi-running-rebels', away: 'st-georges-slayers', divisionId: 'premier', start: '2026-10-15T23:00:00.000Z', venue: 'Montego Bay Community Centre', statsStatus: 'pending'},
    {id: 'qa-women-upcoming', home: 'kingston-royals-women', away: 'portmore-queens', divisionId: 'development', start: '2026-10-17T22:00:00.000Z', venue: 'GC Foster College', statsStatus: 'pending'},
    {id: 'qa-schools-final', home: 'campion-college', away: 'st-georges-college', divisionId: 'schoolboy-a', start: '2026-08-30T20:00:00.000Z', venue: 'National Arena', statsStatus: 'approved', status: 'approved', score: [68, 64], quarters: [[17, 18, 15, 18], [14, 16, 19, 15]]},
    {id: 'qa-schools-upcoming', home: 'st-georges-college', away: 'campion-college', divisionId: 'schoolboy-a', start: '2026-10-18T19:00:00.000Z', venue: 'Kingston College Gymnasium', statsStatus: 'pending'},
  ];
  const teamsById = new Map(TEAM_FIXTURES.map((team) => [team.id, team]));
  for (const game of games) {
    const home = teamsById.get(game.home);
    const away = teamsById.get(game.away);
    const start = new Date(game.start);
    set(`associations/${ASSOCIATION_ID}/events/${game.id}`, {
      title: `${home.name} vs ${away.name}`,
      type: 'game',
      seasonId,
      divisionId: game.divisionId,
      startTime: timestamp.fromDate(start),
      endTime: timestamp.fromDate(new Date(start.getTime() + 2 * 60 * 60 * 1000)),
      location: game.venue,
      teamIds: [game.home, game.away],
      createdBy: 'qa-superadmin',
      statsStatus: game.statsStatus,
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
    if (game.status) {
      set(`associations/${ASSOCIATION_ID}/gameStats/${game.id}`, {
        eventId: game.id,
        seasonId,
        divisionId: game.divisionId,
        status: game.status,
        homeTeamId: game.home,
        homeTeamName: home.name,
        homeScore: game.score[0],
        awayTeamId: game.away,
        awayTeamName: away.name,
        awayScore: game.score[1],
        entryMode: game.status === 'inProgress' ? 'live' : 'postGame',
        playerLines: playerLines([game.home, game.away], game.score),
        publicPlayerLines: publicPlayerLines(
          [game.home, game.away],
          game.score,
        ),
        homeQuarterScores: Object.fromEntries(game.quarters[0].map((score, index) => [String(index + 1), score])),
        awayQuarterScores: Object.fromEntries(game.quarters[1].map((score, index) => [String(index + 1), score])),
        submittedBy: game.status === 'inProgress' ? null : 'qa-statistician',
        submittedAt: game.status === 'inProgress' ? null : updatedAt,
        approvedBy: game.status === 'approved' ? 'qa-admin' : null,
        approvedAt: game.status === 'approved' ? updatedAt : null,
        rejectedBy: game.status === 'rejected' ? 'qa-admin' : null,
        rejectedAt: game.status === 'rejected' ? updatedAt : null,
        rejectionNote: game.status === 'rejected' ? 'Confirm the third-quarter team total before resubmitting.' : null,
        revisionNumber: game.status === 'rejected' ? 1 : 0,
        qaFixtureVersion: QA_FIXTURE_VERSION,
      });
    }
  }

  const populatedDivisionIds = [...divisionTeams.keys()];
  for (const divisionId of [null, ...populatedDivisionIds]) {
    const rows = divisionId
      ? standings.filter((row) => row.divisionId === divisionId)
      : standings;
    set(`associations/${ASSOCIATION_ID}/standings/${seasonId}_${divisionId || 'all'}`, {
      seasonId,
      divisionId,
      updatedAt,
      standings: rows,
      rankingPolicy: 'qa-winning-percentage-v1',
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  const categories = [['ppg', 'ppg'], ['rpg', 'rpg'], ['apg', 'apg'], ['spg', 'spg'], ['bpg', 'bpg']];
  for (const divisionId of [null, 'premier', 'development', 'schoolboy-a']) {
    const eligible = divisionId ? players.filter((player) => player.divisionId === divisionId) : players;
    for (const [category, field] of categories) {
      const rankings = [...eligible]
        .sort((a, b) => (b[field] || (field === 'spg' ? 2 : 1)) - (a[field] || (field === 'spg' ? 2 : 1)))
        .slice(0, 10)
        .map((player, index) => ({
          playerId: player.id,
          name: player.name,
          publicDisplayName: player.name,
          teamId: player.teamId,
          teamName: player.teamName,
          value: field === 'spg' ? 2.2 - index * 0.1 : field === 'bpg' ? 1.8 - index * 0.1 : player[field],
          gp: player.gamesPlayed,
        }));
      set(`associations/${ASSOCIATION_ID}/leaderboard/${seasonId}_${divisionId || 'all'}_${category}`, {
        seasonId, divisionId, category, updatedAt, rankings, qaFixtureVersion: QA_FIXTURE_VERSION,
      });
    }
  }

  // Canonical v2-shaped records let Stage 1 exercise identity, roster,
  // schedule-revision, assignment, stat-revision, and review journeys without
  // manufacturing records ad hoc. They remain synthetic and emulator-only.
  set(`associations/${ASSOCIATION_ID}/competitions/${competitionId}`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId,
    name: 'Synthetic National Basketball League', status: 'active',
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`associations/${ASSOCIATION_ID}/competitions/${competitionId}/seasons/${seasonId}`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    status: 'active', controlVersion: 1, rulesetVersion: 'qa-fiba-profile-unactivated-v1',
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  for (const team of TEAM_FIXTURES) {
    const teamEntryId = `${team.id}-entry`;
    set(`associations/${ASSOCIATION_ID}/teamIdentities/${team.id}`, {
      dataSchemaVersion: 2, associationId: ASSOCIATION_ID, teamId: team.id,
      identityVersionId: `${team.id}-identity-v1`, status: 'active', displayName: team.name,
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
    set(`associations/${ASSOCIATION_ID}/competitions/${competitionId}/seasons/${seasonId}/teamEntries/${teamEntryId}`, {
      dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
      divisionId: team.divisionId, teamEntryId, teamId: team.id,
      seasonalIdentityVersionId: `${team.id}-identity-v1`, registrationStatus: 'approved',
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  for (const player of players) {
    set(`associations/${ASSOCIATION_ID}/persons/${player.id}-person`, {
      dataSchemaVersion: 2, associationId: ASSOCIATION_ID, personId: `${player.id}-person`,
      identityVersionId: `${player.id}-name-v1`, status: 'active',
      qaFixtureVersion: QA_FIXTURE_VERSION,
    });
    set(`associations/${ASSOCIATION_ID}/players/${player.id}`, {
      dataSchemaVersion: 2, associationId: ASSOCIATION_ID, playerId: player.id,
      personId: `${player.id}-person`, displayNameVersionId: `${player.id}-name-v1`,
      displayName: player.name, status: 'active', qaFixtureVersion: QA_FIXTURE_VERSION,
    });
    const membershipId = `${player.teamId}-${player.id}`;
    set(`associations/${ASSOCIATION_ID}/competitions/${competitionId}/seasons/${seasonId}/rosterMemberships/${membershipId}`, {
      dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
      membershipId, membershipVersionId: `${membershipId}-v1`, playerId: player.id,
      teamEntryId: `${player.teamId}-entry`, eligibilityStatus: 'eligible',
      jerseyNumber: player.jerseyNumber, position: player.position,
      effectiveFrom: timestamp.fromDate(new Date('2026-01-01T05:00:00.000Z')),
      effectiveTo: null, recordedAt: updatedAt, qaFixtureVersion: QA_FIXTURE_VERSION,
    });
  }
  const canonicalGamePath = `associations/${ASSOCIATION_ID}/competitions/${competitionId}/seasons/${seasonId}/games/qa-changes-requested`;
  set(canonicalGamePath, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    divisionId: 'development', phaseId: 'regular-season', gameId: 'qa-changes-requested',
    homeTeamEntryId: 'portmore-queens-entry', awayTeamEntryId: 'kingston-royals-women-entry',
    playState: 'complete', reviewState: 'changesRequested', publicationState: 'withheld',
    controlVersion: 1, qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`${canonicalGamePath}/scheduleRevisions/schedule-v1`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    gameId: 'qa-changes-requested', versionId: 'schedule-v1', predecessorVersionId: null,
    scheduledStart: timestamp.fromDate(new Date('2026-09-05T22:00:00.000Z')),
    scheduledEnd: timestamp.fromDate(new Date('2026-09-06T00:00:00.000Z')),
    timezone: 'America/Jamaica', venueId: 'portmore-heart', courtId: 'main',
    homeTeamEntryId: 'portmore-queens-entry', awayTeamEntryId: 'kingston-royals-women-entry',
    reasonCode: 'initialSchedule', qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`${canonicalGamePath}/assignments/qa-statistician`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    gameId: 'qa-changes-requested', uid: 'qa-statistician', duties: ['stats.enter'],
    status: 'active', assignmentVersion: 1, qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`${canonicalGamePath}/statRevisions/revision-1`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    divisionId: 'development', phaseId: 'regular-season', gameId: 'qa-changes-requested',
    revisionId: 'revision-1', revisionNumber: 1, captureMode: 'postGame',
    resultDisposition: 'played', statisticsDisposition: 'complete',
    rulesetVersion: 'qa-fiba-profile-unactivated-v1', policyVersion: 'qa-policy-v1',
    calculatorVersion: 'normalized-box-score-v2', scheduleRevisionId: 'schedule-v1',
    rosterSnapshotId: 'roster-snapshot-v1', rosterSnapshotHash: 'a'.repeat(64),
    sourceWorkspaceId: 'workspace-1', acceptedThroughSequence: 42,
    journalHash: 'b'.repeat(64), inputParts: ['teamOnlyInputs', 'playerLines'],
    inputHash: 'c'.repeat(64), derivedHash: 'd'.repeat(64),
    validationReportHash: 'e'.repeat(64), createdBy: 'qa-statistician', createdAt: updatedAt,
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`${canonicalGamePath}/reviews/review-1`, {
    dataSchemaVersion: 2, associationId: ASSOCIATION_ID, competitionId, seasonId,
    gameId: 'qa-changes-requested', reviewId: 'review-1', revisionId: 'revision-1',
    revisionHash: 'd'.repeat(64), reviewerAccountId: 'qa-admin', decision: 'changesRequested',
    reasonCode: 'quarterTotalMismatch', evidenceRefs: ['qa-fixture://score-sheet'],
    qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`associations/${ASSOCIATION_ID}/qaMetadata/stage1-dataset`, {
    qaFixtureVersion: QA_FIXTURE_VERSION,
    authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    counts: {teams: TEAM_FIXTURES.length, players: players.length, games: games.length, seasons: seasonFixtures.length},
    journeys: ['roster', 'player-card', 'stats-entry', 'standings', 'leaderboards', 'revision-review', 'season-lifecycle'],
  });

  set(`associations/${EMPTY_ASSOCIATION_ID}`, {
    name: 'JBA Empty Fixture', shortName: 'JBA Empty',
    currentSeasonId: 'qa-empty-2026', qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  set(`associations/${EMPTY_ASSOCIATION_ID}/seasons/qa-empty-2026`, {
    name: 'Empty Synthetic Season', status: 'active', qaFixtureVersion: QA_FIXTURE_VERSION,
  });
  await batch.commit();
}

function normalizePublicFixtureValue(value) {
  if (Array.isArray(value)) return value.map(normalizePublicFixtureValue);
  if (value && typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        normalizePublicFixtureValue(nested),
      ]),
    );
  }
  return value;
}

async function publishQaPublicSnapshot(db) {
  const associationRef = db.doc(`associations/${ASSOCIATION_ID}`);
  const [association, season, divisions, events, gameStats, standings, leaderboards, teams, posts] =
    await Promise.all([
      associationRef.get(),
      associationRef.collection('seasons').doc('qa-2026').get(),
      associationRef.collection('divisions').get(),
      associationRef.collection('events').get(),
      associationRef.collection('gameStats').get(),
      associationRef.collection('standings').get(),
      associationRef.collection('leaderboard').get(),
      associationRef.collection('teams').get(),
      associationRef.collection('posts').get(),
    ]);
  const records = (snapshot) => snapshot.docs.map((document) => ({
    id: document.id,
    data: normalizePublicFixtureValue(document.data()),
  }));
  const scopedStandings = records(standings).filter(
    (entry) => typeof entry.data.divisionId === 'string',
  );
  const scopedLeaderboards = records(leaderboards).filter(
    (entry) => typeof entry.data.divisionId === 'string',
  );
  const snapshot = certifyQaLegacySnapshot(publicSnapshotBuilder()({
    associationId: ASSOCIATION_ID,
    association: normalizePublicFixtureValue(association.data()),
    season: {id: season.id, data: normalizePublicFixtureValue(season.data())},
    divisions: records(divisions),
    events: records(events),
    gameStats: records(gameStats),
    // The synthetic public journey exercises the populated division views. Overall
    // aggregate documents remain seeded for signed-in compatibility tests but
    // are not duplicated beside their division-scoped public equivalents.
    standings: scopedStandings,
    leaderboards: scopedLeaderboards,
    teams: records(teams),
    posts: records(posts),
    generatedAt: '2026-09-01T12:00:00.000Z',
  }));
  if (
    snapshot.published !== true ||
    snapshot.schedule?.length !== 9 ||
    snapshot.standings?.length !== TEAM_FIXTURES.length ||
    !snapshot.standings.every(
      (row) => Number.isInteger(row.rank) && row.rankStatus === 'ranked',
    ) ||
    snapshot.leaderboards?.length !== 15 ||
    !snapshot.leaderboards.every((board) => board.rankings?.length > 0) ||
    snapshot.media?.length !== 4
  ) {
    throw new Error(
      'The pure public projection did not produce the complete Stage 1 QA ' +
      `snapshot (published=${snapshot.published}, ` +
      `schedule=${snapshot.schedule?.length}, ` +
      `standings=${snapshot.standings?.length}, ` +
      `leaderboards=${snapshot.leaderboards?.length}, ` +
      `media=${snapshot.media?.length}, ` +
      `rankings=${snapshot.leaderboards?.map((board) => board.rankings?.length).join(',')}).`,
    );
  }
  await db.doc(`publicData/${ASSOCIATION_ID}/snapshots/current`).set(snapshot);
  return snapshot;
}

async function main() {
  requireSafeEnvironment();
  const admin = firebaseAdmin();
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: PROJECT_ID,
      storageBucket: `${PROJECT_ID}.appspot.com`,
    });
  }
  const db = admin.firestore();
  await seedIdentities(admin.auth(), db);
  await seedLeague(db, admin);
  const publicSnapshot = await publishQaPublicSnapshot(db);
  await probeCallable();
  await admin.storage().bucket().file('qa/public/fixture-health.txt').save(
    Buffer.from('HOOPSCONNECT_QA_STORAGE_OK\n', 'utf8'),
    {contentType: 'text/plain', resumable: false},
  );
  console.log(
    `HOOPSCONNECT_QA_FIXTURES_OK users=${roles.length * 2} ` +
    `teams=${TEAM_FIXTURES.length} rosteredTeams=${ROSTERED_TEAM_COUNT} ` +
    `players=${PLAYER_FIXTURE_COUNT} posts=2 publicGames=${publicSnapshot.schedule.length} ` +
    `leaderboards=${publicSnapshot.leaderboards.length} callable=true storage=true ` +
    `password=${PASSWORD}`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  ASSOCIATION_ID,
  AUTHORIZATION_SCHEMA_VERSION,
  EMPTY_ASSOCIATION_ID,
  PASSWORD,
  TEAM_FIXTURES,
  authorizationSchema,
  certifyQaLegacySnapshot,
  identity,
  normalizePublicFixtureValue,
  probeCallable,
  publishQaPublicSnapshot,
  requireSafeEnvironment,
  roles,
  seedIdentities,
  seedLeague,
};
