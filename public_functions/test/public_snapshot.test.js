'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {Timestamp} = require('firebase-admin/firestore');
const {
  MAX_PUBLIC_RELEASE_PAGES,
  PUBLIC_PAGE_TARGET_BYTES,
  buildPublicReleasePackage,
  buildPublicSnapshot,
  canAdvancePublicReleasePointer,
  currentPointerAllowsCandidate,
  immutablePublicDocumentMatches,
} = require('../lib/index');

function fixture(overrides = {}) {
  return {
    associationId: 'jba',
    association: {
      name: 'Jamaica Basketball Association', shortName: 'JBA',
      currentSeasonId: 'season-1', publicLeagueState: 'published', publicPrivacyEpoch: 7,
      standingsPolicyLabel: 'Winning percentage; unresolved ties remain tied',
      privateNotes: 'never public',
    },
    season: {id: 'season-1', data: {name: '2026 NBL'}},
    divisions: [{id: 'premier', data: {name: 'Premier', seasonId: 'season-1', managerUid: 'private'}}],
    teams: [
      {id: 'home', data: {name: 'Home Team', seasonId: 'season-1', divisionId: 'premier', repIds: ['private-user']}},
      {id: 'away', data: {name: 'Away Team', seasonId: 'season-1', divisionId: 'premier'}},
    ],
    events: [{id: 'game-1', data: {
      type: 'game', seasonId: 'season-1', divisionId: 'premier', title: 'Private Admin Title',
      startTime: Timestamp.fromDate(new Date('2026-09-10T20:00:00Z')),
      teamIds: ['home', 'away'], createdBy: 'private-user', description: 'private note',
    }}],
    gameStats: [{id: 'game-1', data: {
      status: 'approved', seasonId: 'season-1', homeTeamId: 'home', awayTeamId: 'away',
      homeTeamName: 'Private Home Alias', awayTeamName: 'Private Away Alias', homeScore: 82, awayScore: 79,
      homeQuarterScores: {'1': 20, '2': 22}, awayQuarterScores: {'1': 18, '2': 21},
      submittedBy: 'private-user', approvedBy: 'private-admin',
      playerLines: {privatePlayerId: {name: 'Private Player'}},
      publicPlayerLines: [{
        playerId: 'player-1', publicDisplayName: 'Player One', teamId: 'home',
        points: 20, twoPointMade: 6, twoPointAttempted: 10, turnovers: 2,
        email: 'never@example.com', school: 'Never Public School',
      }],
      publicRecap: 'Home Team won a close game.', internalRecap: 'private recap',
    }}],
    standings: [{id: 'season-1_premier', data: {
      seasonId: 'season-1', divisionId: 'premier',
      standings: [{
        teamId: 'home', teamName: 'Private Standings Alias', wins: 1, losses: 0, pct: 1,
        rank: 1, rankStatus: 'ranked',
      }],
      processedEvents: ['private-event'],
    }}],
    leaderboards: [
      {id: 'season-1_premier_apg', data: {
        seasonId: 'season-1', divisionId: 'premier', category: 'apg',
        rankings: [{
          playerId: 'player-1', name: 'Private Alias', publicDisplayName: 'Player One',
          teamId: 'home', teamName: 'Private Rankings Alias', value: 4, gp: 1,
        }],
      }},
      {id: 'season-1_premier_ppg', data: {
        seasonId: 'season-1', divisionId: 'premier', category: 'ppg',
        rankings: [{
          playerId: 'player-1', name: 'Private Alias', publicDisplayName: 'Player One',
          teamId: 'home', teamName: 'Private Rankings Alias', value: 20, gp: 1,
        }],
      }},
    ],
    generatedAt: '2026-09-10T21:00:00.000Z',
    ...overrides,
  };
}

test('public snapshot exposes one versioned approved result and strips private source fields', () => {
  const snapshot = buildPublicSnapshot({
    ...fixture(),
  });

  assert.match(snapshot.snapshotVersion, /^[a-f0-9]{64}$/);
  assert.equal(snapshot.publication.snapshotVersion, snapshot.snapshotVersion);
  assert.equal(snapshot.publication.verificationStatus, 'compatibilityCandidate');
  assert.equal(snapshot.certificationStatus, 'compatibilityCandidate');
  assert.equal(snapshot.publication.privacyEpoch, 7);
  assert.equal(snapshot.season.name, '2026 NBL');
  assert.equal(snapshot.divisions[0].name, 'Premier');
  assert.equal(snapshot.schedule[0].status, 'final');
  assert.equal(snapshot.schedule[0].title, 'Home Team vs Away Team');
  assert.equal(snapshot.schedule[0].homeScore, 82);
  assert.match(snapshot.schedule[0].resultVersion, /^[a-f0-9]{64}$/);
  assert.equal(snapshot.schedule[0].playerLines[0].displayName, 'Player One');
  assert.equal(snapshot.schedule[0].playerLines[0].turnovers, 2);
  assert.equal(snapshot.schedule[0].playerLines[0].threePointMade, null);
  assert.equal(snapshot.standings[0].wins, 1);
  assert.equal(snapshot.standings[0].divisionId, 'premier');
  assert.equal(snapshot.leaderboards[0].rankings[0].displayName, 'Player One');
  assert.deepEqual(snapshot.leaderboards.map((entry) => entry.category), ['ppg', 'apg']);
  const serialized = JSON.stringify(snapshot);
  for (const forbidden of [
    'privateNotes', 'repIds', 'managerUid', 'createdBy', 'description',
    'submittedBy', 'approvedBy', 'privatePlayerId', 'Private Player',
    'Private Alias', 'never@example.com', 'Never Public School',
    'internalRecap', 'processedEvents',
    'Private Admin Title', 'Private Home Alias', 'Private Away Alias',
    'Private Standings Alias', 'Private Rankings Alias',
  ]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test('unapproved scores are never returned to guests', () => {
  const snapshot = buildPublicSnapshot({
    associationId: 'jba',
    association: {name: 'JBA', currentSeasonId: 'season-1', publicLeagueState: 'published'},
    teams: [],
    events: [{id: 'game-1', data: {
      type: 'game', seasonId: 'season-1', title: 'Game',
      startTime: Timestamp.fromDate(new Date('2026-09-10T20:00:00Z')),
    }}],
    gameStats: [{id: 'game-1', data: {
      status: 'submitted', seasonId: 'season-1', homeScore: 99, awayScore: 98,
    }}],
    standings: [],
    leaderboards: [],
  });
  assert.equal(snapshot.schedule[0].status, 'scheduled');
  assert.equal(snapshot.schedule[0].homeScore, null);
  assert.equal(snapshot.schedule[0].awayScore, null);
  assert.equal(snapshot.schedule[0].resultVersion, null);
});

test('unreviewed player names never cross the public projection boundary', () => {
  const base = fixture();
  base.gameStats[0].data.publicPlayerLines = [{
    playerId: 'private-player', teamId: 'home', name: 'Private Player', points: 99,
  }];
  base.leaderboards[0].data.rankings = [{
    playerId: 'private-player', name: 'Private Player', teamName: 'Home Team', value: 99, gp: 1,
  }];
  base.leaderboards[1].data.rankings = base.leaderboards[0].data.rankings;

  const snapshot = buildPublicSnapshot(base);

  assert.deepEqual(snapshot.schedule[0].playerLines, []);
  assert.deepEqual(snapshot.leaderboards[0].rankings, []);
  assert.equal(JSON.stringify(snapshot).includes('Private Player'), false);
});

test('player identity stays suppressed without a public privacy epoch', () => {
  const missingPolicy = fixture();
  delete missingPolicy.association.publicPrivacyEpoch;

  const snapshot = buildPublicSnapshot(missingPolicy);

  assert.equal(snapshot.privacyEpoch, null);
  assert.deepEqual(snapshot.schedule[0].playerLines, []);
  assert.equal(
    snapshot.leaderboards.every((board) => board.rankings.length === 0),
    true,
  );
  assert.equal(JSON.stringify(snapshot).includes('Player One'), false);
});

test('snapshot fingerprint is stable across rebuild time and changes with published content', () => {
  const first = buildPublicSnapshot(fixture({generatedAt: '2026-09-10T21:00:00.000Z'}));
  const replay = buildPublicSnapshot(fixture({generatedAt: '2026-09-11T21:00:00.000Z'}));
  assert.equal(first.snapshotVersion, replay.snapshotVersion);
  assert.equal(first.schedule[0].resultVersion, replay.schedule[0].resultVersion);

  const changed = fixture();
  changed.gameStats[0].data.homeScore = 83;
  const corrected = buildPublicSnapshot(changed);
  assert.notEqual(first.snapshotVersion, corrected.snapshotVersion);
  assert.notEqual(first.schedule[0].resultVersion, corrected.schedule[0].resultVersion);
});

test('mixed aggregate and division standings publish one deterministic row per team scope', () => {
  const mixed = fixture();
  mixed.divisions.push({
    id: 'development',
    data: {name: 'Development', seasonId: 'season-1'},
  });
  mixed.teams.push({
    id: 'development-team',
    data: {name: 'Development Team', seasonId: 'season-1', divisionId: 'development'},
  });
  mixed.standings[0].data.standings.push({
    teamId: 'away', wins: 2, losses: 0, pct: 1, rank: 2, rankStatus: 'ranked',
  });
  mixed.standings.unshift({
    id: 'season-1_all',
    data: {
      seasonId: 'season-1',
      divisionId: null,
      standings: [
        {
          teamId: 'home', divisionId: 'premier', wins: 99, losses: 0,
          pct: 1, rank: 1, rankStatus: 'ranked',
        },
        {
          teamId: 'away', divisionId: 'premier', wins: 98, losses: 1,
          pct: 0.99, rank: 2, rankStatus: 'ranked',
        },
        {
          teamId: 'development-team', divisionId: 'development', wins: 3, losses: 1,
          pct: 0.75, rank: 1, rankStatus: 'ranked',
        },
      ],
    },
  });

  const snapshot = buildPublicSnapshot(mixed);
  const replay = fixture({
    divisions: mixed.divisions,
    teams: mixed.teams,
    standings: [...mixed.standings].reverse(),
  });
  const replaySnapshot = buildPublicSnapshot(replay);

  assert.deepEqual(snapshot.standings, [
    {
      teamId: 'development-team', teamName: 'Development Team', divisionId: 'development',
      rank: 1, rankStatus: 'ranked', wins: 3, losses: 1, pct: 0.75,
      gamesBehind: null, streak: null, lastTen: null, pointsFor: null, pointsAgainst: null,
    },
    {
      teamId: 'home', teamName: 'Home Team', divisionId: 'premier',
      rank: 1, rankStatus: 'ranked', wins: 1, losses: 0, pct: 1,
      gamesBehind: null, streak: null, lastTen: null, pointsFor: null, pointsAgainst: null,
    },
    {
      teamId: 'away', teamName: 'Away Team', divisionId: 'premier',
      rank: 2, rankStatus: 'ranked', wins: 2, losses: 0, pct: 1,
      gamesBehind: null, streak: null, lastTen: null, pointsFor: null, pointsAgainst: null,
    },
  ]);
  assert.equal(
    new Set(snapshot.standings.map((row) => `${row.divisionId}:${row.teamId}`)).size,
    snapshot.standings.length,
  );
  assert.equal(
    new Set(snapshot.standings.map((row) => row.teamId)).size,
    snapshot.standings.length,
  );
  assert.deepEqual(replaySnapshot.standings, snapshot.standings);
  assert.equal(replaySnapshot.snapshotVersion, snapshot.snapshotVersion);

  const sourceVersion = 'a'.repeat(64);
  const release = buildPublicReleasePackage(
    snapshot, sourceVersion, 42, '2026-09-10T21:00:00.000Z',
  );
  const replayRelease = buildPublicReleasePackage(
    replaySnapshot, sourceVersion, 42, '2026-09-10T21:00:00.000Z',
  );
  assert.equal(replayRelease.releaseId, release.releaseId);
  assert.deepEqual(replayRelease.manifest, release.manifest);
  assert.deepEqual(replayRelease.pages, release.pages);
  const nextSourceRelease = buildPublicReleasePackage(
    replaySnapshot, 'b'.repeat(64), 42, '2026-09-10T21:00:00.000Z',
  );
  assert.notEqual(nextSourceRelease.releaseId, release.releaseId);
});

test('standings authority changes bind versions while shadow aggregate changes do not', () => {
  const baseline = fixture();
  baseline.standings.push({
    id: 'season-1_all',
    data: {
      seasonId: 'season-1', divisionId: null,
      standings: [{
        teamId: 'home', divisionId: 'premier', wins: 99, losses: 0,
        rank: 1, rankStatus: 'ranked',
      }],
    },
  });
  const first = buildPublicSnapshot(baseline);

  const shadowChanged = fixture({
    standings: structuredClone(baseline.standings),
  });
  shadowChanged.standings[1].data.standings[0].wins = 100;
  const ignoredCorrection = buildPublicSnapshot(shadowChanged);
  assert.equal(ignoredCorrection.snapshotVersion, first.snapshotVersion);

  const authorityChanged = fixture({
    standings: structuredClone(baseline.standings),
  });
  authorityChanged.standings[0].data.standings[0].wins = 2;
  const publishedCorrection = buildPublicSnapshot(authorityChanged);
  assert.notEqual(publishedCorrection.snapshotVersion, first.snapshotVersion);
});

test('an empty scoped standings document suppresses stale aggregate fallback', () => {
  const stale = fixture();
  stale.standings[0].data.standings = [];
  stale.standings.push({
    id: 'season-1_all',
    data: {
      seasonId: 'season-1', divisionId: null,
      standings: [{
        teamId: 'home', divisionId: 'premier', wins: 20, losses: 0,
        rank: 1, rankStatus: 'ranked',
      }],
    },
  });

  assert.deepEqual(buildPublicSnapshot(stale).standings, []);
});

test('ambiguous same-scope standings documents fail closed', () => {
  const ambiguous = fixture();
  ambiguous.standings.push({
    id: 'season-1_premier_copy',
    data: {
      seasonId: 'season-1', divisionId: 'premier',
      standings: [{teamId: 'away', wins: 1, losses: 0}],
    },
  });

  assert.throws(
    () => buildPublicSnapshot(ambiguous),
    /Standings scope premier has multiple source documents/,
  );
});

test('a supplied publicResultVersion must bind every displayed result field', () => {
  const baseline = fixture();
  const version = buildPublicSnapshot(baseline).schedule[0].resultVersion;
  baseline.gameStats[0].data.publicResultVersion = version;
  assert.equal(buildPublicSnapshot(baseline).schedule[0].resultVersion, version);

  const corrections = [
    (input) => { input.gameStats[0].data.homeScore = 83; },
    (input) => { input.gameStats[0].data.homeQuarterScores['1'] = 21; },
    (input) => { input.gameStats[0].data.publicPlayerLines[0].points = 21; },
    (input) => { input.gameStats[0].data.publicRecap = 'Corrected recap.'; },
    (input) => { input.teams[0].data.name = 'Corrected Home Team'; },
  ];
  for (const correct of corrections) {
    const stale = fixture();
    stale.gameStats[0].data.publicResultVersion = version;
    correct(stale);
    assert.throws(
      () => buildPublicSnapshot(stale),
      /publicResultVersion does not match its public result content/,
    );
  }
});

test('division and season scope exclude other-season public candidates', () => {
  const scoped = fixture();
  scoped.divisions.push({id: 'archived', data: {name: 'Other Season Division', seasonId: 'season-2'}});
  scoped.teams.push({id: 'other-team', data: {name: 'Other Season Team', seasonId: 'season-2'}});
  scoped.events.push({id: 'other-game', data: {
    type: 'game', seasonId: 'season-2', title: 'Other Season Game',
    startTime: Timestamp.fromDate(new Date('2025-09-10T20:00:00Z')),
    teamIds: ['other-team', 'away'],
  }});
  scoped.standings.push({id: 'season-2', data: {
    seasonId: 'season-2', standings: [{teamId: 'other-team', wins: 9, losses: 0}],
  }});
  scoped.leaderboards.push({id: 'season-2-ppg', data: {
    seasonId: 'season-2', category: 'ppg', rankings: [{
      playerId: 'other-player', publicDisplayName: 'Other Season Player',
      teamId: 'other-team', value: 99, gp: 9,
    }],
  }});

  const snapshot = buildPublicSnapshot(scoped);
  const serialized = JSON.stringify(snapshot);

  assert.equal(serialized.includes('Other Season'), false);
  assert.equal(snapshot.schedule.length, 1);
  assert.equal(snapshot.divisions.length, 1);
  assert.equal(snapshot.teams.length, 2);
});

test('retracted snapshots retain scope metadata but no stale public rows', () => {
  const retracted = fixture();
  retracted.association = {...retracted.association, publicLeagueState: 'retracted'};

  const snapshot = buildPublicSnapshot(retracted);

  assert.equal(snapshot.published, false);
  assert.equal(snapshot.publication.state, 'retracted');
  assert.equal(snapshot.season.name, '2026 NBL');
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.teams, []);
  assert.deepEqual(snapshot.standings, []);
  assert.deepEqual(snapshot.leaderboards, []);
});

test('unknown historical values remain null instead of becoming zero', () => {
  const sparse = fixture();
  delete sparse.standings[0].data.standings[0].wins;
  delete sparse.standings[0].data.standings[0].pointsFor;
  delete sparse.standings[0].data.standings[0].rank;
  delete sparse.leaderboards[0].data.rankings[0].value;
  delete sparse.leaderboards[0].data.rankings[0].gp;

  const snapshot = buildPublicSnapshot(sparse);

  assert.equal(snapshot.standings[0].wins, null);
  assert.equal(snapshot.standings[0].pointsFor, null);
  assert.equal(snapshot.standings[0].rank, null);
  assert.equal(snapshot.standings[0].rankStatus, 'unresolved');
  assert.equal(snapshot.leaderboards[1].rankings[0].value, null);
  assert.equal(snapshot.leaderboards[1].rankings[0].gamesPlayed, null);
});

test('an unrecognized publication state fails closed', () => {
  const invalid = fixture();
  invalid.association = {...invalid.association, publicLeagueState: 'publsihed'};

  const snapshot = buildPublicSnapshot(invalid);

  assert.equal(snapshot.publication.state, 'unavailable');
  assert.equal(snapshot.published, false);
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.leaderboards, []);
});

test('a missing publication state fails closed', () => {
  const missing = fixture();
  delete missing.association.publicLeagueState;

  const snapshot = buildPublicSnapshot(missing);

  assert.equal(snapshot.publication.state, 'unavailable');
  assert.equal(snapshot.published, false);
  assert.deepEqual(snapshot.schedule, []);
  assert.deepEqual(snapshot.leaderboards, []);
});

test('projection keeps complete current-season coverage without legacy caps', () => {
  const complete = fixture();
  complete.events = Array.from({length: 333}, (_, index) => ({
    id: `game-${index.toString().padStart(4, '0')}`,
    data: {
      type: 'game',
      seasonId: 'season-1',
      startTime: Timestamp.fromMillis(1_800_000_000_000 + index * 60_000),
      teamIds: ['home', 'away'],
    },
  }));
  complete.gameStats = [];
  complete.leaderboards = Array.from({length: 73}, (_, index) => ({
    id: `board-${index}`,
    data: {
      seasonId: 'season-1', category: `custom-${index}`,
      rankings: Array.from({length: 41}, (_, rank) => ({
        playerId: `player-${index}-${rank}`,
        publicDisplayName: `Player ${index} ${rank}`,
        teamId: 'home', value: rank, gp: 1,
      })),
    },
  }));

  const snapshot = buildPublicSnapshot(complete);

  assert.equal(snapshot.schedule.length, 333);
  assert.equal(snapshot.leaderboards.length, 73);
  assert.equal(snapshot.leaderboards[0].rankings.length, 41);
});

test('versioned release pages stay far below Firestore 1 MiB at worst-case volume', () => {
  const large = fixture();
  large.events = Array.from({length: 300}, (_, index) => ({
    id: `game-${index.toString().padStart(4, '0')}`,
    data: {
      type: 'game', seasonId: 'season-1',
      startTime: Timestamp.fromMillis(1_800_000_000_000 + index * 60_000),
      location: `${'V'.repeat(150)} ${index}`,
      teamIds: ['home', 'away'],
    },
  }));
  large.gameStats = large.events.map((event, index) => ({
    id: event.id,
    data: {
      status: 'approved', seasonId: 'season-1',
      homeTeamId: 'home', awayTeamId: 'away', homeScore: 90, awayScore: 80,
      publicRecap: `${'R'.repeat(2990)} ${index}`,
      publicPlayerLines: Array.from({length: 100}, (_, player) => ({
        playerId: `p-${index}-${player}`,
        publicDisplayName: `${'N'.repeat(140)} ${player}`,
        teamId: player % 2 === 0 ? 'home' : 'away', points: player,
      })),
    },
  }));
  const snapshot = buildPublicSnapshot(large);
  const sourceVersion = 'b'.repeat(64);
  const release = buildPublicReleasePackage(
    snapshot, sourceVersion, 42, '2026-09-10T21:00:00.000Z',
  );

  assert.equal(release.manifest.pageCount, release.pages.length);
  assert.ok(release.pages.length > 1);
  assert.ok(release.pages.length <= MAX_PUBLIC_RELEASE_PAGES);
  assert.equal(release.manifest.counts.schedule, 300);
  for (const page of release.pages) {
    assert.ok(
      Buffer.byteLength(JSON.stringify(page.data), 'utf8') <= PUBLIC_PAGE_TARGET_BYTES,
      `${page.id} exceeded the safe page budget`,
    );
  }
  assert.ok(
    Buffer.byteLength(JSON.stringify(release.manifest), 'utf8') <= PUBLIC_PAGE_TARGET_BYTES,
  );
});

test('an oversized item or release fails explicitly instead of truncating', () => {
  const snapshot = buildPublicSnapshot(fixture());
  snapshot.schedule[0].recap = 'x'.repeat(PUBLIC_PAGE_TARGET_BYTES);
  assert.throws(
    () => buildPublicReleasePackage(
      snapshot, 'c'.repeat(64), 42, '2026-09-10T21:00:00.000Z',
    ),
    /exceeds the safe document budget/,
  );

  const tiny = buildPublicSnapshot(fixture());
  const original = tiny.schedule[0];
  tiny.schedule = Array.from(
    {length: MAX_PUBLIC_RELEASE_PAGES + 20},
    (_, index) => ({...original, gameId: `capacity-${index}`, recap: 'z'.repeat(470_000)}),
  );
  assert.throws(
    () => buildPublicReleasePackage(
      tiny, 'd'.repeat(64), 42, '2026-09-10T21:00:00.000Z',
    ),
    /maximum is/,
  );
});

test('immutable retry accepts only an exact release document replay', () => {
  const release = buildPublicReleasePackage(
    buildPublicSnapshot(fixture()),
    '9'.repeat(64),
    42,
    '2026-09-10T21:00:00.000Z',
  );
  const replay = buildPublicReleasePackage(
    buildPublicSnapshot(fixture()),
    '9'.repeat(64),
    42,
    '2026-09-10T21:00:00.000Z',
  );
  assert.equal(
    immutablePublicDocumentMatches(release.manifest, replay.manifest),
    true,
  );
  assert.equal(
    immutablePublicDocumentMatches(release.pages[0].data, replay.pages[0].data),
    true,
  );
  assert.equal(
    immutablePublicDocumentMatches(
      release.pages[0].data,
      {...replay.pages[0].data, itemCount: replay.pages[0].data.itemCount + 1},
    ),
    false,
  );
});

test('oversized public source fields fail explicitly instead of being clipped', () => {
  const oversized = fixture();
  oversized.teams[0].data.name = 'x'.repeat(161);
  assert.throws(
    () => buildPublicSnapshot(oversized),
    /exceeds the 160-character contract limit/,
  );

  const extraTeam = fixture();
  extraTeam.events[0].data.teamIds = ['team-a', 'team-b', 'team-c'];
  assert.throws(
    () => buildPublicSnapshot(extraTeam),
    /more than two team IDs/,
  );
});

test('current pointer guard rejects stale source, season, state, and privacy epoch', () => {
  const expected = {
    expectedSourceVersion: 'e'.repeat(64),
    expectedSourceSequence: 42,
    expectedSourceCommittedAt: '2026-09-11T12:00:00.000Z',
    expectedSeasonId: 'season-1',
    expectedState: 'published',
    expectedPrivacyEpoch: 7,
  };
  const association = {
    currentSeasonId: 'season-1', publicLeagueState: 'published', publicPrivacyEpoch: 7,
    publicProjectionProtocol: 'public-release-v2',
    publicProjectionSourceVersion: 'e'.repeat(64),
    publicProjectionSourceSequence: 42,
    publicProjectionSourceCommittedAt: '2026-09-11T12:00:00.000Z',
  };
  assert.equal(canAdvancePublicReleasePointer({...expected, association}), true);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, publicProjectionSourceVersion: 'f'.repeat(64)},
  }), false);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, publicLeagueState: 'retracted'},
  }), false);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, currentSeasonId: 'season-2'},
  }), false);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, publicPrivacyEpoch: 8},
  }), false);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, publicProjectionSourceSequence: 41},
  }), false);
  assert.equal(canAdvancePublicReleasePointer({
    ...expected,
    association: {...association, publicProjectionSourceCommittedAt: '2026-09-11T12:00:01.000Z'},
  }), false);
});

test('current pointer refuses a conflicting release at the same sequence', () => {
  const candidate = {
    releaseId: 'a'.repeat(64),
    releaseDigest: 'b'.repeat(64),
    sourceVersion: 'c'.repeat(64),
    sourceSequence: 42,
    sourceCommittedAt: '2026-09-11T12:00:00.000Z',
    state: 'published',
    seasonId: 'season-1',
    privacyEpoch: 7,
  };
  const current = {
    protocolVersion: 'public-release-v2',
    ...candidate,
  };
  assert.equal(currentPointerAllowsCandidate(null, candidate), true);
  assert.equal(currentPointerAllowsCandidate({...current, sourceSequence: 41}, candidate), true);
  assert.equal(currentPointerAllowsCandidate(current, candidate), true);
  assert.equal(currentPointerAllowsCandidate({...current, releaseId: 'd'.repeat(64)}, candidate), false);
  assert.equal(currentPointerAllowsCandidate({...current, state: 'retracted'}, candidate), false);
  assert.equal(currentPointerAllowsCandidate({
    ...current, sourceCommittedAt: '2026-09-11T12:00:00Z',
  }, candidate), false);
  assert.equal(currentPointerAllowsCandidate({...current, sourceSequence: 43}, candidate), false);
  assert.equal(currentPointerAllowsCandidate({...current, sourceSequence: '42'}, candidate), false);
});

test('compatibility module registers no deployable projection triggers', () => {
  const moduleExports = require('../lib/index');
  assert.equal(moduleExports.onPublicLeagueSourceWritten, undefined);
  assert.equal(moduleExports.onPublicAssociationWritten, undefined);
});
