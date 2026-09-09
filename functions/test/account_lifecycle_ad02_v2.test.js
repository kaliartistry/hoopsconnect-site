'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ad02 = require('../lib/domain/account_lifecycle_ad02_v2');
const v2 = require('../lib/domain/auth_incarnation_v2');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad02/lifecycle_fixtures_v2.json',
), 'utf8'));

const generationA = fixture.rootScope.authUidV2 && 'a'.repeat(64);
const generationB = 'b'.repeat(64);

function scope(tenant = null) {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    authUidV2: fixture.rootScope.authUidV2,
  };
}

function lifecycle(overrides = {}, tenant = null) {
  return Object.assign({
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    lifecycleStateV2: 'active',
    reauthAfterSecV2: 1700000000,
  }, overrides);
}

function membership(overrides = {}, tenant = null) {
  return Object.assign({
    authIncarnationSchemaVersionV2: 2,
    ...scope(tenant),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    membershipStatusV2: 'active',
    associationId: 'jba',
    capabilities: ['association.read', 'members.read', 'stats.approve'],
  }, overrides);
}

function profile(overrides = {}, tenant = null) {
  return Object.assign({
    accountProfileSchemaVersionV2: 2,
    ...scope(tenant),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    associationId: 'jba',
    displayName: '  Active Member  ',
    teamId: 'team_a',
    divisionId: 'division_a',
    notificationPrefs: {newPosts: true},
  }, overrides);
}

function providerAuth(overrides = {}, tenant = null) {
  const token = Object.assign({
    aud: fixture.projectId,
    sub: fixture.rootScope.authUidV2,
    firebase: tenant === null ? {sign_in_provider: 'password'} : {tenant},
    authIncarnationSchemaVersionV2: 2,
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    authUidV2: fixture.rootScope.authUidV2,
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
    auth_time: 1700000001,
  }, overrides);
  return {uid: fixture.rootScope.authUidV2, token};
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries));
  }

  async read(pathValue) {
    return this.values.has(pathValue) ? structuredClone(this.values.get(pathValue)) : null;
  }
}

function repositoryFor(tenant = null, overrides = {}) {
  const expectedScope = scope(tenant);
  return new MemoryRepository({
    [ad02.accountLifecycleAuthorityPathV2(expectedScope)]:
      overrides.lifecycle ?? lifecycle({}, tenant),
    [ad02.membershipAuthorityPathV2(expectedScope)]:
      overrides.membership ?? membership({}, tenant),
  });
}

function attempt() {
  return {
    sessionAttemptIdV2: 'candidate-attempt',
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: {},
  };
}

async function authorize({tenant = null, auth, repository, capability = 'association.read'} = {}) {
  return ad02.evaluateCandidateRequestAuthorityV2({
    repository: repository ?? repositoryFor(tenant),
    auth: auth ?? providerAuth({}, tenant),
    configuredProjectId: fixture.projectId,
    attempt: attempt(),
    requiredCapability: capability,
    expectedAssociationId: 'jba',
  });
}

test('AD02 stays dormant, has no V1 bridge, and uses exact tenant-aware paths', () => {
  assert.equal(ad02.ACCOUNT_LIFECYCLE_AD02_ACTIVATION_ALLOWED_V2, false);
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.v1Interoperability, 'none');
  for (const [name, tenant] of [['root', null], ['tenant', 'tenant-a']]) {
    const expectedScope = scope(tenant);
    const prefix = name === 'root' ? '' : 'Tenants/tenant-a/users';
    assert.equal(
      ad02.accountLifecycleAuthorityPathV2(expectedScope),
      name === 'root'
        ? `accountLifecycleV2Root/${expectedScope.authUidV2}`
        : `accountLifecycleV2${prefix}/${expectedScope.authUidV2}`,
    );
    assert.equal(
      ad02.membershipAuthorityPathV2(expectedScope),
      name === 'root'
        ? `membershipsV2Root/${expectedScope.authUidV2}`
        : `membershipsV2${prefix}/${expectedScope.authUidV2}`,
    );
    assert.equal(
      ad02.storageAuthorizationProjectionPathV2(expectedScope),
      name === 'root'
        ? `storageAuthorizationsV2Root/${expectedScope.authUidV2}`
        : `storageAuthorizationsV2${prefix}/${expectedScope.authUidV2}`,
    );
  }
  assert.equal(
    ad02.accountLifecycleAuthorityPathV2(fixture.rootScope),
    fixture.paths.root.lifecycle,
  );
  assert.equal(
    ad02.accountLifecycleAuthorityPathV2(fixture.tenantScope),
    `accountLifecycleV2Tenants/${fixture.tenantScope.authTenantIdV2}/users/${fixture.tenantScope.authUidV2}`,
  );
  assert.equal(
    ad02.accountFcmRegistrationPathV2(fixture.rootScope, 'slot0'),
    fixture.paths.root.registration,
  );
  assert.equal(
    ad02.accountFcmRegistrationPathV2(fixture.tenantScope, 'slot0'),
    fixture.paths.tenant.registration,
  );
  assert.deepEqual(fixture.rootScope, scope(null));
  for (const invalidScope of [
    {...scope(), authUidV2: 'unsafe/uid'},
    {...scope(), authTenantIdV2: 'unsafe/tenant'},
  ]) {
    assert.throws(
      () => ad02.accountLifecycleAuthorityPathV2(invalidScope),
      /path segment/,
    );
  }
  assert.throws(
    () => ad02.accountFcmRegistrationPathV2(fixture.rootScope, 'slot8'),
    /installation slot/,
  );
});

test('provider proof is bound to aud, provider tenant, custom scope, UID, G, and E', async () => {
  assert.equal((await authorize()).authorized, true);
  assert.equal((await authorize({tenant: 'tenant-a'})).authorized, true);

  for (const badAuth of [
    providerAuth({aud: 'other-project'}),
    providerAuth({sub: 'other-user'}),
    providerAuth({authProjectIdV2: 'other-project'}),
    providerAuth({authUidV2: 'other-user'}),
    providerAuth({authTenantIdV2: 'tenant-a'}),
    providerAuth({authUidV2: 'unsafe/uid'}),
    providerAuth({accountGenerationV2: generationB}),
    providerAuth({accountLifecycleEpochV2: 8}),
  ]) {
    assert.equal((await authorize({auth: badAuth})).authorized, false);
  }
});

test('root and tenant same-UID lanes never fall back to each other', async () => {
  const shared = new MemoryRepository({
    [ad02.accountLifecycleAuthorityPathV2(scope(null))]: lifecycle({}, null),
    [ad02.membershipAuthorityPathV2(scope(null))]: membership({}, null),
    [ad02.accountLifecycleAuthorityPathV2(scope('tenant-a'))]: lifecycle({}, 'tenant-a'),
    [ad02.membershipAuthorityPathV2(scope('tenant-a'))]: membership({}, 'tenant-a'),
  });
  assert.equal((await authorize({repository: shared})).authorized, true);
  assert.equal((await authorize({tenant: 'tenant-a', repository: shared})).authorized, true);

  shared.values.delete(ad02.accountLifecycleAuthorityPathV2(scope('tenant-a')));
  shared.values.delete(ad02.membershipAuthorityPathV2(scope('tenant-a')));
  const denied = await authorize({tenant: 'tenant-a', repository: shared});
  assert.equal(denied.authorized, false);
  assert.equal(denied.code, 'invalid_lifecycle');
});

test('request authority binds the caller-selected association exactly', async () => {
  const repository = repositoryFor(null, {
    membership: membership({associationId: 'other'}),
  });
  const denied = await authorize({repository});
  assert.deepEqual(denied, {authorized: false, code: 'scope_mismatch'});
});

test('full V2 denial matrix remains fail closed, including strict freshness equality', async () => {
  const baseInput = {
    sessionAttemptIdV2: 'matrix-attempt',
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: {},
    expectedScope: scope(),
    tokenProof: v2.parseAuthIncarnationTokenProofV2({
      authIncarnationSchemaVersionV2: 2,
      ...scope(),
      accountGenerationV2: generationA,
      accountLifecycleEpochV2: 7,
      authTimeSec: 1700000001,
    }),
    lifecycle: lifecycle(),
    membership: membership(),
    requiredCapability: 'association.read',
  };
  const cases = [
    ['missing_token_proof', {tokenProof: null}],
    ['invalid_token_proof', {tokenProof: {...baseInput.tokenProof, extra: true}}],
    ['invalid_lifecycle', {lifecycle: {...lifecycle(), extra: true}}],
    ['lifecycle_inactive', {lifecycle: lifecycle({lifecycleStateV2: 'deleting'})}],
    ['invalid_membership', {membership: {...membership(), extra: true}}],
    ['membership_inactive', {membership: membership({membershipStatusV2: 'revoked'})}],
    ['scope_mismatch', {lifecycle: lifecycle({authTenantIdV2: 'tenant-a'})}],
    ['generation_mismatch', {lifecycle: lifecycle({accountGenerationV2: generationB})}],
    ['epoch_mismatch', {membership: membership({accountLifecycleEpochV2: 8})}],
    ['reauthentication_required', {
      tokenProof: {...baseInput.tokenProof, authTimeSec: 1700000000},
    }],
    ['capability_denied', {requiredCapability: 'stats.enter'}],
  ];
  assert.deepEqual(cases.map(([code]) => code), fixture.denials ?? fixture.denialMatrix ??
    fixture.authorityDenials ?? fixture.requiredDenials);
  for (const [expectedCode, override] of cases) {
    const decision = v2.evaluateAccountAuthorizationV2({...baseInput, ...override});
    assert.deepEqual(decision, {authorized: false, code: expectedCode});
  }
});

test('V1 claims, creation time, and legacy membership never manufacture V2 authority', async () => {
  const legacyOnly = providerAuth({
    authIncarnationSchemaVersionV2: undefined,
    accountGenerationV2: undefined,
    accountLifecycleEpochV2: undefined,
    accountGenerationHashV1: 'c'.repeat(64),
    authCreatedAt: '2026-01-02T03:04:05.678Z',
  });
  const denied = await authorize({auth: legacyOnly});
  assert.deepEqual(denied, {authorized: false, code: 'invalid_token_proof'});

  const repository = new MemoryRepository({
    [`memberships/${scope().authUidV2}`]: {
      authorizationSchemaVersion: 1,
      status: 'active',
      role: 'superAdmin',
      capabilities: ['association.manage'],
    },
  });
  assert.deepEqual(
    await authorize({repository}),
    {authorized: false, code: 'invalid_lifecycle'},
  );
});

test('pending bootstrap is non-granting and rejects suppressed recreation', () => {
  const pending = {
    authIncarnationSchemaVersionV2: 2,
    ...scope(),
    accountGenerationV2: generationB,
    accountLifecycleEpochV2: 0,
    bindingStateV2: 'pending',
    reauthAfterSecV2: 1700000000,
  };
  const allowed = ad02.evaluatePendingLifecycleBootstrapV2({
    pendingBinding: pending,
    currentLifecycle: null,
    suppression: null,
  });
  assert.equal(allowed.allowed, true);
  assert.equal(allowed.pending.bindingStateV2, 'pending');
  assert.equal(Object.prototype.hasOwnProperty.call(allowed.pending, 'lifecycleStateV2'), false);

  const suppression = {
    authIncarnationSchemaVersionV2: 2,
    ...scope(),
    suppressionStateV2: 'uid_reuse_prohibited',
    suppressedAccountGenerationV2: generationA,
    suppressedAccountLifecycleEpochV2: 8,
    recordedAtSecV2: 1700000010,
  };
  assert.deepEqual(
    ad02.evaluatePendingLifecycleBootstrapV2({
      pendingBinding: pending,
      currentLifecycle: null,
      suppression,
    }),
    {allowed: false, code: 'uid_reuse_prohibited'},
  );
  assert.deepEqual(
    ad02.evaluatePendingLifecycleBootstrapV2({
      pendingBinding: pending,
      currentLifecycle: null,
      suppression: {...suppression, unexpected: true},
    }),
    {allowed: false, code: 'invalid_suppression'},
  );
});

test('active-member directory strips authority, delivery, contact, and role data', () => {
  const member = ad02.evaluatePersistedActiveMemberV2({
    expectedScope: scope(),
    lifecycle: lifecycle(),
    membership: membership({role: undefined}),
    profile: profile(),
    requiredCapability: 'members.read',
    expectedAssociationId: 'jba',
  });
  // An unknown legacy role field poisons the exact V2 membership instead of
  // becoming authority.
  assert.equal(member, null);

  const active = ad02.evaluatePersistedActiveMemberV2({
    expectedScope: scope(),
    lifecycle: lifecycle(),
    membership: membership(),
    profile: profile(),
    requiredCapability: 'members.read',
    expectedAssociationId: 'jba',
  });
  assert.ok(active);
  const directory = ad02.buildActiveMemberDirectoryV2({
    members: [active],
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: null,
    associationId: 'jba',
  });
  assert.deepEqual(directory, {
    accountDirectorySchemaVersionV2: 2,
    users: [{
      accountDirectorySchemaVersionV2: 2,
      uid: scope().authUidV2,
      displayName: 'Active Member',
      teamId: 'team_a',
      divisionId: 'division_a',
    }],
    truncated: false,
  });
  const serialized = JSON.stringify(directory);
  for (const forbidden of ['fcmTokens', 'notificationPrefs', 'capabilities', 'role', 'email']) {
    assert.doesNotMatch(serialized, new RegExp(forbidden));
  }

  for (const foreign of [
    {...active, scope: {...active.scope, authProjectIdV2: 'other-project'}},
    {...active, scope: {...active.scope, authTenantIdV2: 'tenant-a'}},
    {...active, associationId: 'other'},
  ]) {
    assert.throws(() => ad02.buildActiveMemberDirectoryV2({
      members: [active, foreign],
      authProjectIdV2: fixture.projectId,
      authTenantIdV2: null,
      associationId: 'jba',
    }), /Mixed-scope/);
  }
});

test('directory and recipient authority reject lifecycle changes during selection', () => {
  for (const changed of [
    lifecycle({lifecycleStateV2: 'deleting', accountLifecycleEpochV2: 8}),
    lifecycle({accountGenerationV2: generationB}),
    lifecycle({authTenantIdV2: 'tenant-a'}),
  ]) {
    assert.equal(ad02.evaluatePersistedActiveMemberV2({
      expectedScope: scope(),
      lifecycle: changed,
      membership: membership(),
      profile: profile(),
      requiredCapability: 'members.read',
      expectedAssociationId: 'jba',
    }), null);
  }
});

test('legacy derived writers bind original approval scope/G/E and recheck inside commit', async () => {
  const actorStamp = {
    authIncarnationSchemaVersionV2: 2,
    ...scope(),
    accountGenerationV2: generationA,
    accountLifecycleEpochV2: 7,
  };
  const captured = ad02.evaluateLegacyDerivedWriterFenceV2({
    actorStamp,
    lifecycle: lifecycle(),
    membership: membership(),
    requiredCapability: 'stats.approve',
    expectedAssociationId: 'jba',
  });
  assert.ok(captured);

  const values = new Map([
    [ad02.accountLifecycleAuthorityPathV2(scope()), lifecycle({
      lifecycleStateV2: 'deleting',
      accountLifecycleEpochV2: 8,
    })],
    [ad02.membershipAuthorityPathV2(scope()), membership({
      membershipStatusV2: 'revoked',
      accountLifecycleEpochV2: 8,
    })],
  ]);
  const committed = new Map();
  const repository = {
    async read(key) { return values.get(key) ?? null; },
    async runTransaction(operation) {
      const staged = new Map();
      const transaction = {
        async read(key) { return structuredClone(values.get(key) ?? null); },
        write(key, value) { staged.set(key, structuredClone(value)); },
      };
      const result = await operation(transaction);
      for (const [key, value] of staged) committed.set(key, value);
      return result;
    },
  };

  values.set(ad02.accountLifecycleAuthorityPathV2(scope()), lifecycle());
  values.set(ad02.membershipAuthorityPathV2(scope()), membership());
  const committedResult = await ad02.commitCandidateDerivedWriteV2({
    repository,
    expectedFence: captured,
    commit(transaction) {
      transaction.write('candidateDerived/output', {written: true});
      return 'committed';
    },
  });
  assert.equal(committedResult, 'committed');
  assert.deepEqual(committed.get('candidateDerived/output'), {written: true});
  committed.clear();

  values.set(ad02.accountLifecycleAuthorityPathV2(scope()), lifecycle({
    lifecycleStateV2: 'deleting',
    accountLifecycleEpochV2: 8,
  }));
  values.set(ad02.membershipAuthorityPathV2(scope()), membership({
    membershipStatusV2: 'revoked',
    accountLifecycleEpochV2: 8,
  }));
  await assert.rejects(
    ad02.commitCandidateDerivedWriteV2({
      repository,
      expectedFence: captured,
      commit(transaction) {
        transaction.write('candidateDerived/output', {written: true});
      },
    }),
    /lifecycle fence denied/,
  );
  assert.equal(committed.has('candidateDerived/output'), false);

  assert.equal(ad02.evaluateLegacyDerivedWriterFenceV2({
    actorStamp,
    lifecycle: lifecycle({accountGenerationV2: generationB}),
    membership: membership({accountGenerationV2: generationB}),
    requiredCapability: 'stats.approve',
    expectedAssociationId: 'jba',
  }), null);
  assert.equal(ad02.evaluateLegacyDerivedWriterFenceV2({
    actorStamp,
    lifecycle: lifecycle({}, 'tenant-a'),
    membership: membership({}, 'tenant-a'),
    requiredCapability: 'stats.approve',
    expectedAssociationId: 'jba',
  }), null);
});
