'use strict';

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

let testEnv;

function authed(uid, email) {
  return testEnv.authenticatedContext(uid, {email}).firestore();
}

async function seed(setup) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setup(context.firestore());
  });
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
