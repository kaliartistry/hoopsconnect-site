'use strict';

const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const test = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

const authorityFixture = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, '../../contracts/official_stats/v2/authority_fixtures.json'),
  'utf8',
));
const bootstrapFixture = JSON.parse(fs.readFileSync(
  path.resolve(__dirname, '../../contracts/official_stats/v2/assigned_game_bootstrap_fixtures.json'),
  'utf8',
));

let testEnv;

function authed(uid, email) {
  return testEnv.authenticatedContext(uid, {email}).firestore();
}

async function assertDeniedWithoutBudgetExhaustion(operation) {
  try {
    await operation;
    assert.fail('expected permission denial');
  } catch (error) {
    assert.equal(error.code, 'permission-denied');
    assert.doesNotMatch(error.message, /maximum of 1000 expressions/i);
  }
}

async function seed(setup) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setup(context.firestore());
  });
}

const v2SeasonPath = 'associations/jba/competitions/nbl/seasons/s2026';
const v2GamePath = `${v2SeasonPath}/games/game-1`;

function rulesGrant(capability = 'stats.enter', scopeKind = 'division', changes = {}) {
  const grant = {
    grantId: `grant-${capability.replaceAll('.', '-')}`,
    capability,
    scopeKind,
    associationId: 'jba',
    status: 'active',
    membershipVersion: 7,
    effectiveFrom: new Date('2026-01-01T00:00:00.000Z'),
    effectiveTo: null,
  };
  if (scopeKind !== 'association') Object.assign(grant, {competitionId: 'nbl', seasonId: 's2026'});
  if (scopeKind === 'division' || scopeKind === 'teamEntry') grant.divisionId = 'premier';
  if (scopeKind === 'teamEntry') grant.teamEntryId = 'team-a';
  return Object.assign(grant, changes);
}

function rulesGrantKey(grant) {
  if (grant.scopeKind === 'association' || grant.scopeKind === 'season') return `${grant.capability}|${grant.scopeKind}`;
  if (grant.scopeKind === 'division') return `${grant.capability}|division|${grant.divisionId}`;
  return `${grant.capability}|teamEntry|${grant.divisionId}|${grant.teamEntryId}`;
}

async function seedV2Authority(db, changes = {}) {
  const statsGrant = rulesGrant();
  const membership = {...authorityFixture.membershipBase, capabilities: ['stats.enter'], ...(changes.membership || {})};
  const associationControl = {...authorityFixture.associationControlBase, ...(changes.associationControl || {})};
  const seasonControl = {...authorityFixture.seasonControlBase, ...(changes.seasonControl || {})};
  const associationAccess = {...authorityFixture.associationEnvelopeBase, grants: {}, ...(changes.associationAccess || {})};
  const seasonAccess = {
    ...authorityFixture.seasonEnvelopeBase,
    grants: {[rulesGrantKey(statsGrant)]: statsGrant},
    ...(changes.seasonAccess || {}),
  };
  const game = {...authorityFixture.gameBase, ...(changes.game || {})};
  const assignment = {...authorityFixture.assignmentBase, ...(changes.assignment || {})};
  await setDoc(doc(db, 'memberships/operator'), membership);
  if (changes.omitAssociationControl !== true) await setDoc(doc(db, 'associations/jba/domainControl/current'), associationControl);
  if (changes.omitSeasonControl !== true) await setDoc(doc(db, `${v2SeasonPath}/control/current`), seasonControl);
  if (changes.omitAssociationAccess !== true) await setDoc(doc(db, 'associations/jba/access/operator'), associationAccess);
  if (changes.omitSeasonAccess !== true) await setDoc(doc(db, `${v2SeasonPath}/access/operator`), seasonAccess);
  if (changes.omitGame !== true) await setDoc(doc(db, v2GamePath), game);
  if (changes.omitAssignment !== true) await setDoc(doc(db, `${v2GamePath}/assignments/operator`), assignment);
}

async function writeAssociationAccessWithRestDoubleMembershipVersion() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const endpoint = `http://${host}/v1/projects/demo-hoopsconnect/databases/(default)/documents/associations/jba/access/operator`;
  const response = await fetch(endpoint, {
    method: 'PATCH',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer owner',
    },
    body: JSON.stringify({fields: {
      dataSchemaVersion: {integerValue: '2'},
      authorizationSchemaVersion: {integerValue: '2'},
      uid: {stringValue: 'operator'},
      associationId: {stringValue: 'jba'},
      scopeKind: {stringValue: 'association'},
      status: {stringValue: 'active'},
      membershipVersion: {doubleValue: 7},
      accessVersion: {integerValue: '3'},
      grants: {mapValue: {fields: {}}},
    }}),
  });
  assert.equal(response.ok, true, await response.text());
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

test.after(async () => {
  await testEnv.cleanup();
});

test('clients cannot self-create authority documents or self-assign a role', async () => {
  const fan = authed('fan-1', 'fan@example.com');
  await assertFails(
    setDoc(doc(fan, 'users/fan-1'), {
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: 'fan',
    }),
  );
  await assertFails(
    setDoc(doc(fan, 'memberships/fan-1'), {
      associationId: 'jba',
      role: 'superAdmin',
      status: 'active',
      capabilities: ['members.manage'],
    }),
  );

  await seed(async (db) => {
    await setDoc(doc(db, 'users/fan-1'), {
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: 'fan',
    });
    await setDoc(doc(db, 'memberships/fan-1'), {
      associationId: 'jba',
      role: 'fan',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read'],
    });
  });
  await assertFails(updateDoc(doc(fan, 'users/fan-1'), {role: 'statistician'}));
  await assertSucceeds(
    updateDoc(doc(fan, 'users/fan-1'), {displayName: 'Fan Updated'}),
  );
});

test('league operations remain callable-only even for a super administrator', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/root'), {
      associationId: 'jba',
      role: 'superAdmin',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read', 'association.manage', 'teams.manage', 'schedule.manage'],
    });
    await setDoc(doc(db, 'associations/jba/divisions/premier'), {
      name: 'Premier', status: 'active', version: 7,
    });
    await setDoc(doc(db, 'associations/jba/events/game-1'), {
      title: 'One vs Two', type: 'game', divisionId: 'premier',
    });
    await setDoc(doc(db, 'associations/jba/leagueWorkflowControl/current'), {
      schemaVersion: 1, scheduling: true,
    });
    await setDoc(doc(db, 'associations/jba/playerSeasonStats/player-1'), {
      playerId: 'player-1', points: 0,
    });
  });
  const root = authed('root', 'root@example.com');
  await assertFails(deleteDoc(doc(root, 'associations/jba/divisions/premier')));
  await assertFails(setDoc(doc(root, 'associations/jba/events/game-2'), {type: 'game'}));
  await assertFails(updateDoc(doc(root, 'associations/jba/events/game-1'), {status: 'cancelled'}));
  await assertFails(deleteDoc(doc(root, 'associations/jba/events/game-1')));
  await assertFails(updateDoc(doc(root, 'associations/jba/leagueWorkflowControl/current'), {scheduling: false}));
  await assertFails(setDoc(doc(root, 'leagueOperationReceipts/forged'), {status: 'created'}));
  await assertFails(setDoc(doc(root, 'associations/jba/leagueActorAuthorities/root'), {status: 'active'}));
  await assertFails(setDoc(doc(root, 'associations/jba/leagueActorQuotas/root'), {minuteCount: 0}));
  await assertFails(setDoc(doc(root, 'associations/jba/leagueIdentityAuthorities/player-1'), {rosterReadable: true}));
  await assertFails(setDoc(doc(root, 'associations/jba/divisionDeletionOperations/op-1'), {status: 'deleted'}));
  await assertFails(setDoc(doc(root,
    'associations/jba/competitions/nbl/seasons/s2026/rosterOutstandingProposals/proposal-1'),
  {teamId: 'team-1', status: 'pending'}));
  await assertFails(setDoc(doc(root,
    'associations/jba/competitions/nbl/seasons/s2026/rosterProposalQueues/team-entry-1'),
  {teamId: 'team-1', outstandingCount: 1}));
  await assertFails(updateDoc(doc(root, 'associations/jba/playerSeasonStats/player-1'), {points: 999}));
});

test('direct division creates and every edit advance an exact integer version', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/root'), {
      associationId: 'jba', role: 'superAdmin', status: 'active',
      authorizationSchemaVersion: 1, capabilities: ['association.read', 'association.manage'],
    });
  });
  const root = authed('root', 'root@example.com');
  const division = doc(root, 'associations/jba/divisions/versioned');
  await assertFails(setDoc(division, {name: 'Versioned', status: 'active'}));
  await assertFails(setDoc(division, {name: 'Versioned', status: 'active', version: 2}));
  await assertSucceeds(setDoc(division, {name: 'Versioned', status: 'active', version: 1}));
  await assertFails(updateDoc(division, {name: 'Skipped', version: 3, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(division, {name: 'Unversioned', updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(division, {name: 'Edited', version: 2, updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(division, {
    status: 'archived', archivedAt: serverTimestamp(), version: 3, updatedAt: serverTimestamp(),
  }));
});

test('direct team writers cannot bypass a pending division deletion guard', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/root'), {
      email: 'root@example.com', displayName: 'Root', associationId: 'jba', role: 'superAdmin',
    });
    await setDoc(doc(db, 'memberships/root'), {
      associationId: 'jba', role: 'superAdmin', status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: [
        'association.read', 'association.manage', 'teams.manage', 'stats.enter',
        'posts.create', 'posts.manage',
      ],
    });
    await setDoc(doc(db, 'associations/jba/divisions/open'), {name: 'Open', status: 'active'});
    await setDoc(doc(db, 'associations/jba/divisions/pending'), {
      name: 'Pending', status: 'active', deletionPending: {operationId: 'delete_operation_01'},
    });
    await setDoc(doc(db, 'associations/jba/teams/team-1'), {
      name: 'One', divisionId: 'open', seasonId: 's2026',
    });
    await setDoc(doc(db, 'associations/jba/events/game-open'), {
      type: 'game', divisionId: 'open',
    });
    await setDoc(doc(db, 'associations/jba/events/game-pending'), {
      type: 'game', divisionId: 'pending',
    });
  });
  const root = authed('root', 'root@example.com');
  await assertSucceeds(setDoc(doc(root, 'associations/jba/teams/team-2'), {
    name: 'Two', divisionId: 'open', seasonId: 's2026',
  }));
  await assertFails(setDoc(doc(root, 'associations/jba/teams/team-3'), {
    name: 'Three', divisionId: 'pending', seasonId: 's2026',
  }));
  await assertFails(updateDoc(doc(root, 'associations/jba/teams/team-1'), {divisionId: 'pending'}));
  await assertFails(updateDoc(doc(root, 'associations/jba/divisions/pending'), {deletionPending: null}));
  const post = {
    authorId: 'root', authorName: 'Root', authorRole: 'superAdmin',
    title: 'Division notice', body: 'Body', type: 'announcement',
    createdAt: serverTimestamp(), visibility: 'internal', pinned: false,
    urgent: false, requiresAck: false, expectedAcks: {}, ackStatus: {},
  };
  await assertSucceeds(setDoc(
    doc(root, 'associations/jba/posts/open-post'),
    {...post, divisionFilter: 'open'},
  ));
  await assertFails(setDoc(
    doc(root, 'associations/jba/posts/pending-post'),
    {...post, divisionFilter: 'pending'},
  ));
  await assertSucceeds(setDoc(
    doc(root, 'associations/jba/posts/unscoped-post'),
    {...post, divisionFilter: null},
  ));
  await assertFails(updateDoc(
    doc(root, 'associations/jba/posts/unscoped-post'),
    {divisionFilter: 'pending'},
  ));
  await assertSucceeds(updateDoc(
    doc(root, 'associations/jba/posts/unscoped-post'),
    {divisionFilter: 'open'},
  ));
  await assertSucceeds(setDoc(doc(root, 'associations/jba/gameStats/game-open'), {
    status: 'draft', homeScore: 0, awayScore: 0,
  }));
  await assertFails(setDoc(doc(root, 'associations/jba/gameStats/game-pending'), {
    status: 'draft', homeScore: 0, awayScore: 0,
  }));
});

test('archived divisions allow corrections to existing stat references but no new references', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/stats'), {
      associationId: 'jba', role: 'statistician', status: 'active',
      authorizationSchemaVersion: 1, capabilities: ['association.read', 'stats.enter'],
    });
    await setDoc(doc(db, 'associations/jba/divisions/archived'), {
      name: 'Archived', status: 'archived', version: 4,
    });
    for (const gameId of ['existing-game', 'new-game']) {
      await setDoc(doc(db, `associations/jba/events/${gameId}`), {
        type: 'game', divisionId: 'archived',
      });
    }
    await setDoc(doc(db, 'associations/jba/gameStats/existing-game'), {
      eventId: 'existing-game', divisionId: 'archived', status: 'draft', homeScore: 0, awayScore: 0,
    });
  });
  const stats = authed('stats', 'stats@example.com');
  await assertSucceeds(updateDoc(doc(stats, 'associations/jba/gameStats/existing-game'), {
    homeScore: 2,
  }));
  await assertFails(updateDoc(doc(stats, 'associations/jba/gameStats/existing-game'), {
    divisionId: 'other', homeScore: 3,
  }));
  await assertFails(setDoc(doc(stats, 'associations/jba/gameStats/new-game'), {
    eventId: 'new-game', divisionId: 'archived', status: 'draft', homeScore: 0, awayScore: 0,
  }));
});

test('fan can read self and same-association public data but not other users or tenants', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/fan-1'), {
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: 'fan',
    });
    await setDoc(doc(db, 'memberships/fan-1'), {
      associationId: 'jba',
      role: 'fan',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read'],
    });
    await setDoc(doc(db, 'users/fan-2'), {
      email: 'other@example.com',
      displayName: 'Other',
      associationId: 'jba',
      role: 'fan',
    });
    await setDoc(doc(db, 'associations/jba'), {name: 'JBA'});
    await setDoc(doc(db, 'associations/other'), {name: 'Other'});
    await setDoc(doc(db, 'associations/jba/teams/team-1'), {name: 'Team'});
  });
  const fan = authed('fan-1', 'fan@example.com');
  await assertSucceeds(getDoc(doc(fan, 'users/fan-1')));
  await assertFails(getDoc(doc(fan, 'users/fan-2')));
  await assertSucceeds(getDoc(doc(fan, 'associations/jba')));
  await assertSucceeds(getDoc(doc(fan, 'associations/jba/teams/team-1')));
  await assertFails(getDoc(doc(fan, 'associations/other')));
});

test('fan query proves public non-ack visibility and internal reads fail', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/fan-1'), {
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: 'fan',
    });
    await setDoc(doc(db, 'memberships/fan-1'), {
      associationId: 'jba',
      role: 'fan',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read'],
    });
    const base = {pinned: false, createdAt: new Date()};
    await setDoc(doc(db, 'associations/jba/posts/public'), Object.assign({}, base, {
      visibility: 'public',
      requiresAck: false,
      title: 'Public',
    }));
    await setDoc(doc(db, 'associations/jba/posts/internal'), Object.assign({}, base, {
      visibility: 'internal',
      requiresAck: false,
      title: 'Internal',
    }));
    await setDoc(doc(db, 'associations/jba/posts/ack'), Object.assign({}, base, {
      visibility: 'public',
      requiresAck: true,
      expectedAcks: {rep: {name: 'Rep', teamName: 'Team'}},
      title: 'Ack',
    }));
  });
  const fan = authed('fan-1', 'fan@example.com');
  const safeQuery = query(
    collection(fan, 'associations/jba/posts'),
    where('visibility', '==', 'public'),
    where('requiresAck', '==', false),
    orderBy('pinned', 'desc'),
    orderBy('createdAt', 'desc'),
  );
  await assertSucceeds(getDocs(safeQuery));
  await assertFails(getDocs(collection(fan, 'associations/jba/posts')));
  await assertFails(getDoc(doc(fan, 'associations/jba/posts/internal')));
  await assertFails(getDoc(doc(fan, 'associations/jba/posts/ack')));
});

test('member directory reads require capability and a same-association query', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/root'), {
      email: 'root@example.com',
      displayName: 'Root',
      associationId: 'jba',
      role: 'superAdmin',
    });
    await setDoc(doc(db, 'memberships/root'), {
      associationId: 'jba',
      role: 'superAdmin',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['members.read', 'association.read'],
    });
    await setDoc(doc(db, 'users/jba-user'), {
      email: 'jba@example.com',
      displayName: 'JBA',
      associationId: 'jba',
      role: 'fan',
    });
    await setDoc(doc(db, 'users/other-user'), {
      email: 'other@example.com',
      displayName: 'Other',
      associationId: 'other',
      role: 'fan',
    });
  });
  const root = authed('root', 'root@example.com');
  await assertSucceeds(
    getDocs(
      query(
        collection(root, 'users'),
        where('associationId', '==', 'jba'),
      ),
    ),
  );
  await assertFails(getDocs(collection(root, 'users')));
  await assertFails(getDoc(doc(root, 'users/other-user')));
});

test('statistician writes are tenant-bound and cannot approve', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/stats'), {
      email: 'stats@example.com',
      displayName: 'Stats',
      associationId: 'jba',
      role: 'statistician',
    });
    await setDoc(doc(db, 'memberships/stats'), {
      associationId: 'jba',
      role: 'statistician',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read', 'stats.enter'],
    });
    await setDoc(doc(db, 'associations/jba/divisions/premier'), {
      name: 'Premier', status: 'active',
    });
    await setDoc(doc(db, 'associations/jba/events/game-1'), {
      type: 'game', divisionId: 'premier',
    });
    await setDoc(doc(db, 'associations/jba/events/game-2'), {
      type: 'game', divisionId: 'premier',
    });
    await setDoc(doc(db, 'associations/jba/events/forged-approved'), {
      type: 'game', divisionId: 'premier',
    });
    await setDoc(doc(db, 'associations/jba/gameStats/game-2'), {
      status: 'submitted',
      homeScore: 1,
      awayScore: 0,
    });
  });
  const stats = authed('stats', 'stats@example.com');
  await assertSucceeds(
    setDoc(doc(stats, 'associations/jba/gameStats/game-1'), {
      status: 'inProgress',
      homeScore: 0,
      awayScore: 0,
    }),
  );
  await assertFails(
    setDoc(doc(stats, 'associations/other/gameStats/game-1'), {
      status: 'inProgress',
      homeScore: 0,
      awayScore: 0,
    }),
  );
  await assertFails(
    setDoc(doc(stats, 'associations/jba/gameStats/forged-approved'), {
      status: 'approved',
      approvedBy: 'stats',
      homeScore: 999,
      awayScore: 0,
    }),
  );
  await assertFails(
    updateDoc(doc(stats, 'associations/jba/gameStats/game-2'), {
      status: 'approved',
      approvedBy: 'stats',
    }),
  );
});

test('legacy role-only users and suspended authors cannot mutate protected data', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/legacy-stats'), {
      email: 'legacy@example.com',
      displayName: 'Legacy Stats',
      associationId: 'jba',
      role: 'statistician',
    });
    await setDoc(doc(db, 'users/suspended-rep'), {
      email: 'suspended@example.com',
      displayName: 'Suspended Rep',
      associationId: 'jba',
      role: 'rep',
    });
    await setDoc(doc(db, 'memberships/suspended-rep'), {
      associationId: 'jba',
      role: 'rep',
      status: 'suspended',
      authorizationSchemaVersion: 1,
      capabilities: ['association.read', 'posts.create'],
    });
    await setDoc(doc(db, 'associations/jba/posts/authored'), {
      authorId: 'suspended-rep',
      title: 'Original',
      visibility: 'public',
      requiresAck: false,
    });
  });

  const legacy = authed('legacy-stats', 'legacy@example.com');
  await assertFails(
    setDoc(doc(legacy, 'associations/jba/gameStats/legacy-bypass'), {
      status: 'inProgress',
      homeScore: 0,
      awayScore: 0,
    }),
  );

  const suspended = authed('suspended-rep', 'suspended@example.com');
  await assertFails(
    updateDoc(doc(suspended, 'associations/jba/posts/authored'), {
      title: 'Changed while suspended',
    }),
  );
});

test('all raw v2 authority, control, game, assignment, and descendant reads and writes stay denied', async () => {
  assert.equal(bootstrapFixture.transportGuarantees.directFirestoreReadsAllowed, false);
  assert.equal(bootstrapFixture.transportGuarantees.deployedFunctionExported, false);
  await seed(async (db) => {
    await seedV2Authority(db);
    await setDoc(doc(db, `${v2GamePath}/reviews/r1`), {private: true});
    await setDoc(doc(db, `${v2SeasonPath}/rosterMemberships/r1`), {private: true});
  });
  const operator = authed('operator', 'stats@example.com');
  for (const documentPath of [
    'associations/jba/access/operator',
    'associations/jba/domainControl/current',
    `${v2SeasonPath}/access/operator`,
    `${v2SeasonPath}/control/current`,
    v2GamePath,
    `${v2GamePath}/assignments/operator`,
    `${v2GamePath}/reviews/r1`,
    `${v2SeasonPath}/rosterMemberships/r1`,
  ]) {
    await assertDeniedWithoutBudgetExhaustion(getDoc(doc(operator, documentPath)));
    await assertDeniedWithoutBudgetExhaustion(setDoc(doc(operator, documentPath), {forged: true}));
    await assertDeniedWithoutBudgetExhaustion(deleteDoc(doc(operator, documentPath)));
  }
  for (const collectionPath of [
    'associations/jba/access',
    `${v2SeasonPath}/access`,
    `${v2SeasonPath}/games`,
    `${v2GamePath}/assignments`,
    `${v2GamePath}/reviews`,
    `${v2SeasonPath}/rosterMemberships`,
  ]) await assertDeniedWithoutBudgetExhaustion(getDocs(collection(operator, collectionPath)));
});

test('explicit v2 cutover rejects legacy stat writes while disabled and shadow remain compatible', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'memberships/legacy-stats'), {
      associationId: 'jba', role: 'statistician', status: 'active',
      authorizationSchemaVersion: 1, capabilities: ['stats.enter'],
    });
    await setDoc(doc(db, 'associations/jba/divisions/premier'), {name: 'Premier', status: 'active'});
    for (const eventId of ['disabled', 'shadow', 'cutover-bypass', 'unknown-enabled', 'unknown-null']) {
      await setDoc(doc(db, `associations/jba/events/${eventId}`), {type: 'game', divisionId: 'premier'});
    }
  });
  const stats = authed('legacy-stats', 'legacy@example.com');
  for (const mode of ['disabled', 'shadow']) {
    await seed(async (db) => setDoc(doc(db, 'associations/jba/domainControl/current'), {authorityMode: mode}));
    await assertSucceeds(setDoc(doc(stats, `associations/jba/gameStats/${mode}`), {
      status: 'inProgress', homeScore: 0, awayScore: 0,
    }));
  }
  await seed(async (db) => setDoc(doc(db, 'associations/jba/domainControl/current'), {authorityMode: 'v2'}));
  await assertFails(setDoc(doc(stats, 'associations/jba/gameStats/cutover-bypass'), {
    status: 'inProgress', homeScore: 0, awayScore: 0,
  }));
  await assertFails(setDoc(doc(stats, 'associations/jba/gameStats/cutover-bypass/events/e1'), {type: 'shot'}));
  for (const authorityMode of ['enabled', null]) {
    await seed(async (db) => setDoc(doc(db, 'associations/jba/domainControl/current'), {authorityMode}));
    await assertFails(setDoc(doc(stats, `associations/jba/gameStats/unknown-${String(authorityMode)}`), {
      status: 'inProgress', homeScore: 0, awayScore: 0,
    }));
  }
});

test('REST doubleValue authority counters do not create a client-readable bypass', async () => {
  await seed(async (db) => seedV2Authority(db, {
    membership: {capabilities: ['association.read']},
    associationAccess: {grants: {}},
  }));
  await writeAssociationAccessWithRestDoubleMembershipVersion();
  const operator = authed('operator', 'operator@example.com');
  await assertFails(getDoc(doc(operator, 'associations/jba/access/operator')));
  await assertFails(updateDoc(doc(operator, 'associations/jba/access/operator'), {membershipVersion: 7}));
});

test('invite lifecycle cannot be modified by a client', async () => {
  const inviteId = 'v2_' + 'a'.repeat(64);
  await seed(async (db) => {
    await setDoc(doc(db, 'users/root'), {
      email: 'root@example.com',
      displayName: 'Root',
      associationId: 'jba',
      role: 'superAdmin',
    });
    await setDoc(doc(db, 'memberships/root'), {
      associationId: 'jba',
      role: 'superAdmin',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: ['invites.manage'],
    });
    await setDoc(doc(db, 'inviteCodes/' + inviteId), {
      inviteId,
      credentialVersion: 2,
      associationId: 'jba',
      role: 'media',
      status: 'active',
      usesRemaining: 1,
    });
    await setDoc(doc(db, 'authorizationOperationReceipts/private'), {
      actorId: 'root',
      associationId: 'jba',
      operation: 'invite.create',
    });
  });
  const root = authed('root', 'root@example.com');
  await assertSucceeds(getDoc(doc(root, 'inviteCodes/' + inviteId)));
  await assertFails(getDoc(doc(root, 'authorizationOperationReceipts/private')));
  await assertFails(
    updateDoc(doc(root, 'inviteCodes/' + inviteId), {usesRemaining: 0}),
  );
  await assertFails(
    setDoc(doc(root, 'inviteCodes/FORGED1'), {
      associationId: 'jba',
      role: 'superAdmin',
      status: 'active',
      usesRemaining: 1,
    }),
  );
});

test('representative can add only their own expected acknowledgment with trusted metadata', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users/rep-1'), {
      email: 'rep@example.com',
      displayName: 'Rep One',
      associationId: 'jba',
      role: 'rep',
    });
    await setDoc(doc(db, 'memberships/rep-1'), {
      associationId: 'jba',
      role: 'rep',
      status: 'active',
      authorizationSchemaVersion: 1,
      capabilities: [
        'association.read',
        'posts.internal.read',
        'posts.acknowledge',
      ],
    });
    await setDoc(doc(db, 'associations/jba/posts/ack-post'), {
      authorId: 'admin',
      visibility: 'internal',
      requiresAck: true,
      expectedAcks: {
        'rep-1': {name: 'Rep One', teamName: 'Team One'},
        'rep-2': {name: 'Rep Two', teamName: 'Team Two'},
      },
      ackStatus: {},
    });
  });
  const rep = authed('rep-1', 'rep@example.com');
  const ref = doc(rep, 'associations/jba/posts/ack-post');

  await assertFails(
    updateDoc(ref, {
      'ackStatus.rep-2': {
        ackedAt: serverTimestamp(),
        name: 'Rep Two',
        teamName: 'Team Two',
      },
    }),
  );
  await assertFails(
    updateDoc(ref, {
      'ackStatus.rep-1': {
        ackedAt: serverTimestamp(),
        name: 'Forged',
        teamName: 'Team One',
      },
    }),
  );
  await assertSucceeds(
    updateDoc(ref, {
      'ackStatus.rep-1': {
        ackedAt: serverTimestamp(),
        name: 'Rep One',
        teamName: 'Team One',
      },
    }),
  );
  await assertFails(
    updateDoc(ref, {
      'ackStatus.rep-1': {
        ackedAt: serverTimestamp(),
        name: 'Rep One',
        teamName: 'Team One',
      },
    }),
  );
});
