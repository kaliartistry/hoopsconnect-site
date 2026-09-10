'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const contract = require('../lib/domain/account_deletion_contract');
const ad02 = require('../lib/domain/account_lifecycle_ad02_v2');
const ad03 = require('../lib/domain/association_ownership_ad03_v2');
const records = require('../lib/account_deletion/ad04_records');
const coordinator = require('../lib/account_deletion/ad04_coordinator');
const worker = require('../lib/account_deletion/ad04_worker');
const reconciliation = require('../lib/account_deletion/ad04_reconciliation');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad04/lifecycle_cleanup_fixtures_v1.json',
), 'utf8'));

const NOW = fixture.nowSecV1;
const CREATED = fixture.authCreatedAtIsoV1;
const STATUS_SECRET = fixture.status.secret;

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([key, value]) => [key, clone(value)]));
    this.inTransaction = false;
    this.transactionCount = 0;
  }

  async read(pathValue) {
    return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
  }

  async runTransaction(operation) {
    this.transactionCount += 1;
    const staged = new Map();
    let writeStarted = false;
    this.inTransaction = true;
    try {
      const result = await operation({
        read: async (pathValue) => {
          if (writeStarted) throw new Error('AD04 test adapter read after write');
          if (staged.has(pathValue)) return clone(staged.get(pathValue));
          return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
        },
        write: (pathValue, value) => {
          writeStarted = true;
          staged.set(pathValue, clone(value));
        },
      });
      for (const [key, value] of staged) this.values.set(key, value);
      return result;
    } finally {
      this.inTransaction = false;
    }
  }
}

function scope(uid = 'owner-a', tenant = null) {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    authUidV2: uid,
  };
}

function generationFor(uid = 'owner-a', tenant = null) {
  return contract.accountGenerationHash({
    authNamespace: `firebase:${fixture.projectId}:${tenant ?? 'root'}`,
    accountId: uid,
    authCreatedAt: new Date(CREATED),
  });
}

function identitySnapshot({uid = 'owner-a', tenant = null, apple = false, patch = {}} = {}) {
  const accountScope = scope(uid, tenant);
  return {
    schemaVersion: 1,
    ...accountScope,
    authCreatedAtIsoV1: CREATED,
    accountGenerationV2: generationFor(uid, tenant),
    accountLifecycleEpochV2: 7,
    authTimeSecV1: NOW - 10,
    issuerV1: `https://securetoken.google.com/${fixture.projectId}`,
    audienceV1: fixture.projectId,
    providerIdsV1: apple ? ['apple.com'] : ['password'],
    appleProviderSubjectHashV1: apple ? 'd'.repeat(64) : null,
    revocationCheckedV1: true,
    appAttestationVerifiedV1: true,
    ...patch,
  };
}

async function principalFor(options = {}) {
  const snapshot = identitySnapshot(options);
  return coordinator.establishVerifiedDeletionPrincipalV1({
    verifier: {verifyCurrentAccountV1: async () => clone(snapshot)},
    presentedCredential: {opaque: true},
    configuredProjectId: fixture.projectId,
    nowSecV1: NOW,
  });
}

function lifecycle(principal, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(principal.authUidV2, principal.authTenantIdV2),
    accountGenerationV2: principal.accountGenerationV2,
    accountLifecycleEpochV2: principal.accountLifecycleEpochV2,
    lifecycleStateV2: 'active',
    reauthAfterSecV2: NOW - 120,
    ...patch,
  };
}

function membership(principal, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...scope(principal.authUidV2, principal.authTenantIdV2),
    accountGenerationV2: principal.accountGenerationV2,
    accountLifecycleEpochV2: principal.accountLifecycleEpochV2,
    membershipStatusV2: 'active',
    associationId: 'jba',
    capabilities: ['association.read'],
    ...patch,
  };
}

function impact(patch = {}) {
  return {
    schemaVersion: 1,
    policyVersion: 'policy_v1',
    impactVersion: 'impact_v1',
    custodyChoice: 'ordinary',
    associationId: null,
    ownerDepartureRequestV2: null,
    candidateTestCustodyPolicyIdV2: null,
    ...patch,
  };
}

function request({intentId = 'intent_owner_a', operationId = 'operation_a',
  requestId = 'request_owner_a', statusSecretHash = fixture.status.secretHash,
  patch = {}} = {}) {
  return {
    schemaVersion: 1,
    intentId,
    policyVersion: 'policy_v1',
    impactVersion: 'impact_v1',
    operationId,
    requestId,
    statusSecretHash,
    confirmation: 'deleteAccount',
    custodyChoice: 'ordinary',
    ...patch,
  };
}

async function acceptedAccount({uid = 'owner-a', apple = false, repository,
  membershipValue, impactValue, requestValue, intentId = 'intent_owner_a',
  material = null, seedLifecycle = true} = {}) {
  const principal = await principalFor({uid, apple});
  const repo = repository ?? new MemoryRepository();
  if (seedLifecycle) {
    repo.values.set(records.candidateAccountLifecycleAuthorityPathV1(principal),
      lifecycle(principal));
  }
  if (membershipValue !== undefined) {
    repo.values.set(records.candidateMembershipAuthorityPathV1(principal),
      clone(membershipValue));
  }
  const selectedImpact = impactValue ?? impact();
  await coordinator.prepareCandidateAccountDeletionV1({
    repository: repo,
    principal,
    request: {schemaVersion: 1},
    impact: selectedImpact,
    intentId,
    nowSecV1: NOW,
  });
  if (material !== null) {
    repo.values.set(records.deletionRevocationMaterialPathV1(
      material.providerRevocationRefV1,
    ), clone(material));
  }
  const selectedRequest = requestValue ?? request({intentId});
  const accepted = await coordinator.acceptCandidateAccountDeletionV1({
    repository: repo,
    principal,
    request: selectedRequest,
    nowSecV1: NOW + 1,
  });
  return {repository: repo, principal, accepted, request: selectedRequest};
}

function tasksFor(repository, accepted, principal) {
  return records.initialDeletionTasksV1({
    scope: principal,
    internalJobId: accepted.internalJobId,
    generationHash: principal.accountGenerationV2,
    acceptedLifecycleEpochV2: principal.accountLifecycleEpochV2 + 1,
    nowSecV1: NOW + 1,
  }).map((expected) => clone(repository.values.get(records.deletionTaskPathV1(
    accepted.internalJobId,
    expected.effectIdV1,
  ))));
}

class FakeAuthAdapter {
  constructor(repository, generationHash) {
    this.repository = repository;
    this.generationHash = generationHash;
    this.present = true;
    this.disabled = false;
    this.revoked = false;
    this.disableCalls = 0;
    this.revokeCalls = 0;
    this.deleteCalls = 0;
  }

  assertOutsideTransaction() {
    assert.equal(this.repository.inTransaction, false, 'provider call ran in transaction');
  }

  currentStateV1() {
    return this.present ? {
      accountStateV1: 'present',
      observedGenerationHashV1: this.generationHash,
      disabledV1: this.disabled,
      refreshTokensRevokedV1: this.revoked,
    } : {
      accountStateV1: 'absent',
      observedGenerationHashV1: null,
      disabledV1: false,
      refreshTokensRevokedV1: false,
    };
  }

  async inspectSingleUserV1() {
    this.assertOutsideTransaction();
    return this.currentStateV1();
  }

  async disableSingleUserIfGenerationMatchesV1({generationHash}) {
    this.assertOutsideTransaction();
    if (!this.present || this.generationHash !== generationHash) return this.currentStateV1();
    this.disableCalls += 1;
    this.disabled = true;
    return this.currentStateV1();
  }

  async revokeRefreshTokensIfGenerationMatchesV1({generationHash}) {
    this.assertOutsideTransaction();
    if (!this.present || this.generationHash !== generationHash) return this.currentStateV1();
    this.revokeCalls += 1;
    this.revoked = true;
    return this.currentStateV1();
  }

  async deleteSingleUserIfGenerationMatchesV1({generationHash}) {
    this.assertOutsideTransaction();
    if (!this.present || this.generationHash !== generationHash) return this.currentStateV1();
    this.deleteCalls += 1;
    this.present = false;
    return this.currentStateV1();
  }

  recreateV1(generationHash) {
    this.generationHash = generationHash;
    this.present = true;
    this.disabled = false;
    this.revoked = false;
  }
}

function terminalAdapterResult(adapterId, policyVersion = 'policy_v1') {
  return {
    schemaVersion: 1,
    adapterId,
    applicability: 'applicable',
    state: 'complete',
    disposition: 'erase',
    policyDecisionState: 'approved',
    policyDecisionId: `retention.${adapterId}`,
    policyVersion,
    holdState: 'none',
    evidenceCode: 'verified_complete',
    evidenceRef: `proof_${adapterId}`,
    holdBoundaryAt: null,
  };
}

function fakeCleanupAdapter(repository, adapterId, store = new Map()) {
  return {
    adapterIdV1: adapterId,
    adapterVersionV1: 'account-deletion-adapter-v1',
    inspectEffectV1: async ({effectIdV1}) => {
      assert.equal(repository.inTransaction, false);
      return clone(store.get(effectIdV1) ?? null);
    },
    applyEffectV1: async ({effectIdV1, policyVersion}) => {
      assert.equal(repository.inTransaction, false);
      const result = terminalAdapterResult(adapterId, policyVersion);
      store.set(effectIdV1, clone(result));
      return result;
    },
  };
}

async function runTask({repository, principal, task, authAdapter,
  appleAdapter = null, cleanupAdapters = [], now = NOW + 2, hooks}) {
  return worker.runCandidateDeletionTaskV1({
    repository,
    locator: worker.candidateTaskLocatorV1(task),
    workerIdV1: `worker_${now}`,
    configuredProjectId: fixture.projectId,
    nowSecV1: now,
    firebaseAuthAdapterV1: authAdapter,
    appleCredentialAdapterV1: appleAdapter,
    cleanupAdaptersV1: cleanupAdapters,
    ...(hooks === undefined ? {} : {hooksV1: hooks}),
  });
}

test('AD04 is dormant, version 1, deterministic, strict, and covers the required matrix', () => {
  assert.equal(records.ACCOUNT_DELETION_AD04_ACTIVATION_ALLOWED_V1, false);
  assert.equal(records.ACCOUNT_DELETION_AD04_PRODUCTION_EXPORT_ALLOWED_V1, false);
  assert.equal(reconciliation.candidateAuthSafetyNetExportReadyV1(), false);
  assert.equal(reconciliation.candidateScheduledSweeperExportReadyV1(), false);
  assert.deepEqual(fixture.requiredScenarios, [9, 10, 11, 12, 32, 33, 34, 35, 36, 40, 41]);
  const tasks = records.initialDeletionTasksV1({
    scope: fixture.rootScope,
    internalJobId: records.deletionInternalJobIdV1(fixture.rootScope, fixture.generations.ownerA),
    generationHash: fixture.generations.ownerA,
    acceptedLifecycleEpochV2: 8,
    nowSecV1: NOW,
  });
  assert.equal(tasks.length, fixture.counts.totalTasks);
  assert.equal(tasks.filter((entry) => entry.kindV1 === 'cleanupAdapter').length, 27);
  assert.equal(tasks.every((entry) => entry.acceptedLifecycleEpochV2 === 8), true);
  assert.equal(new Set(tasks.map((entry) => entry.effectIdV1)).size, tasks.length);
  const nextEpochTasks = records.initialDeletionTasksV1({
    scope: fixture.rootScope,
    internalJobId: records.deletionInternalJobIdV1(fixture.rootScope, fixture.generations.ownerA),
    generationHash: fixture.generations.ownerA,
    acceptedLifecycleEpochV2: 9,
    nowSecV1: NOW,
  });
  assert.equal(tasks.every((entry, index) =>
    entry.effectIdV1 !== nextEpochTasks[index].effectIdV1 &&
    entry.effectFingerprintV1 !== nextEpochTasks[index].effectFingerprintV1), true);
  assert.throws(
    () => records.parseCandidateDeletionTaskV1({...tasks[0], unexpected: true}),
    {codeV1: 'AD04_INVALID_REQUEST'},
  );
  assert.throws(
    () => records.deletionTaskPathV1('job_ok', 'unsafe/effect'),
    {codeV1: 'AD04_INVALID_REQUEST'},
  );
  assert.deepEqual([1, 2, 3, 4, 5, 6, 20].map(records.retryDelaySecV1),
    [60, 120, 240, 480, 960, 1800, 1800]);
});

test('identity proof binds issuer, audience, project, tenant, UID, generation, freshness, revocation, and App Check', async () => {
  const principal = await principalFor();
  assert.equal(principal.accountGenerationV2, fixture.generations.ownerA);
  const cases = [
    {issuerV1: 'https://securetoken.google.com/other-project'},
    {audienceV1: 'other-project'},
    {authProjectIdV2: 'other-project'},
    {authUidV2: 'other-user'},
    {accountGenerationV2: 'b'.repeat(64)},
    {authTimeSecV1: NOW - 301},
    {revocationCheckedV1: false},
    {appAttestationVerifiedV1: false},
    {providerIdsV1: ['apple.com'], appleProviderSubjectHashV1: null},
    {extra: true},
  ];
  for (const patch of cases) {
    await assert.rejects(() => coordinator.establishVerifiedDeletionPrincipalV1({
      verifier: {verifyCurrentAccountV1: async () => identitySnapshot({patch})},
      presentedCredential: 'opaque',
      configuredProjectId: fixture.projectId,
      nowSecV1: NOW,
    }), {codeV1: 'AD04_AUTHORITY_DENIED'});
  }
});

test('acceptance atomically composes AD02 fence and AD03 owner departure before creating the full outbox', async () => {
  const principal = await principalFor();
  const otherGeneration = generationFor('owner-b');
  const ownerBinding = (uid, generation) => ({
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: ad03.recoverableOwnerBindingIdV2({
      ...scope(uid), accountGenerationV2: generation, accountLifecycleEpochV2: 7,
    }),
    ...scope(uid),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: 7,
    bindingVersionV2: 1,
  });
  const ownerMembership = membership(principal, {
    capabilities: ['association.read', 'association.manage'],
  });
  const ownerRequest = {
    associationOwnershipSchemaVersionV2: 2,
    associationId: 'jba',
    departureOperationIdV2: 'departure_owner_a',
    expectedControlVersionV2: 1,
    custodyChoiceV2: 'ordinary',
    transferIntentIdV2: null,
    custodyCaseIdV2: null,
  };
  const repo = new MemoryRepository({
    [ad03.associationOwnershipControlPathV2({
      authProjectIdV2: fixture.projectId, authTenantIdV2: null, associationId: 'jba',
    })]: {
      associationOwnershipSchemaVersionV2: 2,
      authProjectIdV2: fixture.projectId,
      authTenantIdV2: null,
      associationId: 'jba',
      controlVersionV2: 1,
      operationalStateV2: 'operating',
      recoverableOwnersV2: [
        ownerBinding('owner-a', principal.accountGenerationV2),
        ownerBinding('owner-b', otherGeneration),
      ],
      pendingTransferIntentIdV2: null,
      activeCustodyCaseIdV2: null,
      custodyPolicyIdV2: null,
    },
  });
  const result = await acceptedAccount({
    repository: repo,
    membershipValue: ownerMembership,
    impactValue: impact({
      associationId: 'jba',
      ownerDepartureRequestV2: ownerRequest,
    }),
  });
  const nextLifecycle = repo.values.get(ad02.accountLifecycleAuthorityPathV2(principal));
  const nextMembership = repo.values.get(ad02.membershipAuthorityPathV2(principal));
  const control = repo.values.get(ad03.associationOwnershipControlPathV2({
    authProjectIdV2: fixture.projectId, authTenantIdV2: null, associationId: 'jba',
  }));
  assert.equal(nextLifecycle.lifecycleStateV2, 'deleting');
  assert.equal(nextLifecycle.accountLifecycleEpochV2, 8);
  assert.equal(nextMembership.membershipStatusV2, 'revoked');
  assert.deepEqual(nextMembership.capabilities, []);
  assert.equal(control.controlVersionV2, 2);
  assert.deepEqual(control.recoverableOwnersV2.map((entry) => entry.authUidV2), ['owner-b']);
  const job = repo.values.get(records.deletionJobPathV1(result.accepted.internalJobId));
  assert.equal(job.authorityFenceDurable, true);
  assert.equal(job.minimumCleanupReferencesCaptured, true);
  assert.equal(job.authDeletionCheckpointState, 'scheduled');
  assert.equal(tasksFor(repo, result.accepted, principal).length, 33);
});

test('exact operation replay is stable, envelope changes conflict, and a second operation gets its own alias', async () => {
  const result = await acceptedAccount();
  const refreshedSnapshot = identitySnapshot({patch: {authTimeSecV1: NOW + 890}});
  const refreshedPrincipal = await coordinator.establishVerifiedDeletionPrincipalV1({
    verifier: {verifyCurrentAccountV1: async () => refreshedSnapshot},
    presentedCredential: {refreshed: true},
    configuredProjectId: fixture.projectId,
    nowSecV1: NOW + 900,
  });
  const replay = await coordinator.acceptCandidateAccountDeletionV1({
    repository: result.repository,
    principal: refreshedPrincipal,
    request: result.request,
    nowSecV1: NOW + 900,
  });
  assert.deepEqual(replay, result.accepted);
  await assert.rejects(() => coordinator.acceptCandidateAccountDeletionV1({
    repository: result.repository,
    principal: result.principal,
    request: {...result.request, requestId: 'changed_request'},
    nowSecV1: NOW + 2,
  }), {codeV1: 'AD04_OPERATION_CONFLICT'});
  const secondRequest = request({
    intentId: result.request.intentId,
    operationId: 'operation_b',
    requestId: 'request_owner_b',
    statusSecretHash: contract.statusSecretHash(Buffer.alloc(32, 1).toString('base64url')),
  });
  const converged = await coordinator.acceptCandidateAccountDeletionV1({
    repository: result.repository,
    principal: result.principal,
    request: secondRequest,
    nowSecV1: NOW + 2,
  });
  assert.equal(converged.internalJobId, result.accepted.internalJobId);
  assert.equal(converged.bindingKind, 'sameGenerationConvergence');
  const binding = result.repository.values.get(records.deletionJobBindingPathV1(
    result.accepted.internalJobId,
  ));
  assert.equal(binding.winningOperationId, 'operation_a');
  assert.equal(binding.statusAliasCountV1, 2);
  assert.notEqual(
    result.repository.values.get(records.deletionStatusAliasPathV1('request_owner_a')).statusSecretHash,
    result.repository.values.get(records.deletionStatusAliasPathV1('request_owner_b')).statusSecretHash,
  );
});

test('status recovery is secret-gated, coarse, uniform for invalid states, and survives Auth absence', async () => {
  const result = await acceptedAccount();
  const getStatus = (secret = STATUS_SECRET) => coordinator.getCandidateAccountDeletionStatusV1({
    repository: result.repository,
    request: {schemaVersion: 1, requestId: result.request.requestId, statusSecret: secret},
    nowSecV1: NOW + 2,
  });
  const initial = await getStatus();
  assert.equal(initial.phase, 'processing');
  assert.deepEqual(Object.keys(initial).sort(), [
    'acceptedAt', 'messageCode', 'nextPollAfterSeconds', 'phase', 'providerOutcome',
    'requestId', 'retainedCategoryCodes',
  ]);
  const jobPath = records.deletionJobPathV1(result.accepted.internalJobId);
  result.repository.values.set(jobPath, {
    ...result.repository.values.get(jobPath),
    authDeletionCheckpointState: 'complete',
    authAbsent: true,
  });
  assert.equal((await getStatus()).phase, 'accountRemovedCleanupPending');
  for (const action of [
    () => getStatus('B'.repeat(43)),
    () => coordinator.getCandidateAccountDeletionStatusV1({
      repository: result.repository,
      request: {schemaVersion: 1, requestId: 'missing_request', statusSecret: STATUS_SECRET},
      nowSecV1: NOW + 2,
    }),
  ]) await assert.rejects(action, {codeV1: 'AD04_STATUS_UNAVAILABLE'});
  const controlPath = records.deletionStatusControlPathV1(result.request.requestId);
  const validControl = clone(result.repository.values.get(controlPath));
  result.repository.values.set(controlPath, {...validControl, unexpected: true});
  await assert.rejects(getStatus, {codeV1: 'AD04_STATUS_UNAVAILABLE'});
  result.repository.values.set(controlPath, {
    ...validControl,
    stateV1: 'expired',
    expiresAtSecV1: NOW + 1,
  });
  await assert.rejects(getStatus, {codeV1: 'AD04_STATUS_UNAVAILABLE'});
});

test('Auth-only and malformed legacy membership accounts remain eligible without role or profile reconstruction', async () => {
  const authOnly = await acceptedAccount({uid: 'auth-only'});
  assert.equal(authOnly.accepted.state, 'deleting');
  const legacy = await acceptedAccount({
    uid: 'legacy-user',
    membershipValue: {legacyRole: 'admin', arbitraryPath: 'memberships/legacy-user'},
    intentId: 'intent_legacy',
    requestValue: request({intentId: 'intent_legacy', operationId: 'legacy_op',
      requestId: 'legacy_request'}),
  });
  assert.equal(legacy.accepted.state, 'deleting');
  assert.equal(legacy.repository.values.has('users/legacy-user'), false);
  const legacyJob = legacy.repository.values.get(records.deletionJobPathV1(
    legacy.accepted.internalJobId));
  const legacyBinding = legacy.repository.values.get(records.deletionJobBindingPathV1(
    legacy.accepted.internalJobId));
  assert.equal(legacyJob.custodyRecorded, false);
  assert.equal(legacyBinding.custodyRequiresAttentionV1, true);
});

test('provider-owned non-opaque UID stays exact and Auth-only deletion works without provisioning', async () => {
  const uid = fixture.providerOwnedUidPath.uid;
  const lifecyclePath = records.candidateAccountLifecycleAuthorityPathV1(scope(uid));
  assert.equal(lifecyclePath,
    `accountLifecycleV2Root/${fixture.providerOwnedUidPath.encodedSegment}`);
  assert.equal(lifecyclePath.split('/').length, 2);
  assert.equal(records.candidateAccountLifecycleAuthorityPathV1(scope('owner-a')),
    ad02.accountLifecycleAuthorityPathV2(scope('owner-a')));
  assert.equal(records.candidateAccountLifecycleAuthorityPathV1(scope('slash/user'))
    .split('/').length, 2);

  const result = await acceptedAccount({
    uid,
    seedLifecycle: false,
    intentId: 'intent_provider_uid',
    requestValue: request({
      intentId: 'intent_provider_uid',
      operationId: 'operation_provider_uid',
      requestId: 'request_provider_uid',
    }),
  });
  assert.equal(result.principal.authUidV2, uid);
  assert.equal(result.repository.values.get(lifecyclePath).authUidV2, uid);
  const auth = new FakeAuthAdapter(result.repository,
    result.principal.accountGenerationV2);
  const authTasks = tasksFor(result.repository, result.accepted, result.principal)
    .filter((entry) => entry.kindV1.startsWith('auth'));
  for (let index = 0; index < authTasks.length; index += 1) {
    assert.equal((await runTask({
      repository: result.repository,
      principal: result.principal,
      task: authTasks[index],
      authAdapter: auth,
      now: NOW + 2 + index,
    })).stateV1, 'completed');
  }
  assert.equal(auth.deleteCalls, 1);
  assert.equal(auth.present, false);
});

test('malformed lifecycle authority fails closed before an intent or outbox can be written', async () => {
  const principal = await principalFor({uid: 'malformed-lifecycle'});
  const repo = new MemoryRepository({
    [ad02.accountLifecycleAuthorityPathV2(principal)]: {
      legacyState: 'active',
      arbitraryPath: 'users/malformed-lifecycle',
    },
  });
  await assert.rejects(() => coordinator.prepareCandidateAccountDeletionV1({
    repository: repo,
    principal,
    request: {schemaVersion: 1},
    impact: impact(),
    intentId: 'intent_malformed_lifecycle',
    nowSecV1: NOW,
  }), {codeV1: 'AD04_AUTHORITY_DENIED'});
  assert.equal(repo.values.has(records.deletionIntentPathV1(
    'intent_malformed_lifecycle')), false);
  assert.equal([...repo.values.keys()].some((key) =>
    key.startsWith('accountDeletionJobsV1/')), false);
});

test('Auth deletion runs after its own fence while cleanup remains pending or unsupported', async () => {
  const result = await acceptedAccount({uid: 'auth-only'});
  const allTasks = tasksFor(result.repository, result.accepted, result.principal);
  const authTasks = allTasks.filter((entry) => entry.kindV1.startsWith('auth'));
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  for (let index = 0; index < authTasks.length; index += 1) {
    const outcome = await runTask({
      repository: result.repository,
      principal: result.principal,
      task: authTasks[index],
      authAdapter: auth,
      now: NOW + 2 + index,
    });
    assert.equal(outcome.stateV1, 'completed');
  }
  assert.deepEqual({disable: auth.disableCalls, revoke: auth.revokeCalls, delete: auth.deleteCalls},
    {disable: 1, revoke: 1, delete: 1});
  const status = await coordinator.getCandidateAccountDeletionStatusV1({
    repository: result.repository,
    request: {schemaVersion: 1, requestId: result.request.requestId,
      statusSecret: STATUS_SECRET},
    nowSecV1: NOW + 10,
  });
  assert.equal(status.phase, 'accountRemovedCleanupPending');
  const cleanupTask = allTasks.find((entry) => entry.kindV1 === 'cleanupAdapter');
  const unsupported = await runTask({
    repository: result.repository,
    principal: result.principal,
    task: cleanupTask,
    authAdapter: auth,
    now: NOW + 20,
  });
  assert.equal(unsupported.stateV1, 'needsAttention');
  assert.equal(auth.deleteCalls, 1);
});

test('completed cleanup cannot hide an Auth failure and final completion waits for proven absence', async () => {
  const result = await acceptedAccount({uid: 'cleanup-first'});
  const tasks = tasksFor(result.repository, result.accepted, result.principal);
  const authTasks = tasks.filter((entry) => entry.kindV1.startsWith('auth'));
  const cleanupTasks = tasks.filter((entry) => entry.kindV1 === 'cleanupAdapter');
  const cleanupAdapters = contract.accountDeletionAdapterIds.map((adapterId) =>
    fakeCleanupAdapter(result.repository, adapterId));
  const transientAuth = {
    inspectSingleUserV1: async () => { throw new Error('transient Auth outage'); },
    disableSingleUserIfGenerationMatchesV1: async () => assert.fail('unexpected disable'),
    revokeRefreshTokensIfGenerationMatchesV1: async () => assert.fail('unexpected revoke'),
    deleteSingleUserIfGenerationMatchesV1: async () => assert.fail('unexpected delete'),
  };
  assert.equal((await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[0], authAdapter: transientAuth, cleanupAdapters,
    now: NOW + 2})).stateV1, 'retryScheduled');
  let tick = 3;
  for (const cleanupTask of cleanupTasks) {
    await runTask({repository: result.repository, principal: result.principal,
      task: cleanupTask, authAdapter: transientAuth, cleanupAdapters, now: NOW + tick++});
  }
  const appleTask = tasks.find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  await runTask({repository: result.repository, principal: result.principal,
    task: appleTask, authAdapter: transientAuth, cleanupAdapters, now: NOW + tick++});
  const reconcileTask = tasks.find((entry) => entry.kindV1 === 'reconcileCompletion');
  assert.equal((await runTask({repository: result.repository, principal: result.principal,
    task: reconcileTask, authAdapter: transientAuth, cleanupAdapters,
    now: NOW + tick++})).stateV1, 'dependencyPending');
  const pendingJob = result.repository.values.get(records.deletionJobPathV1(
    result.accepted.internalJobId));
  assert.equal(pendingJob.authAbsent, false);
  assert.notEqual(pendingJob.state, 'complete');
  assert.equal(result.repository.values.get(ad02.accountLifecycleAuthorityPathV2(
    result.principal)).lifecycleStateV2, 'deleting');

  const recoveredAuth = new FakeAuthAdapter(result.repository,
    result.principal.accountGenerationV2);
  tick = 62;
  for (const authTask of authTasks) {
    await runTask({repository: result.repository, principal: result.principal,
      task: authTask, authAdapter: recoveredAuth, cleanupAdapters, now: NOW + tick++});
  }
  assert.equal((await runTask({repository: result.repository, principal: result.principal,
    task: reconcileTask, authAdapter: recoveredAuth, cleanupAdapters,
    now: NOW + tick})).stateV1, 'completed');
  assert.equal(result.repository.values.get(records.deletionJobPathV1(
    result.accepted.internalJobId)).state, 'complete');
});

test('a crash after Auth deletion but before checkpoint retries by inspection and never deletes twice', async () => {
  const result = await acceptedAccount();
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  const authTasks = tasksFor(result.repository, result.accepted, result.principal)
    .filter((entry) => entry.kindV1.startsWith('auth'));
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[0], authAdapter: auth, now: NOW + 2});
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[1], authAdapter: auth, now: NOW + 3});
  await assert.rejects(() => runTask({
    repository: result.repository,
    principal: result.principal,
    task: authTasks[2],
    authAdapter: auth,
    now: NOW + 4,
    hooks: {beforeCheckpointPersistV1: async () => { throw new Error('simulated crash'); }},
  }), /simulated crash/);
  assert.equal(auth.deleteCalls, 1);
  const retry = await runTask({
    repository: result.repository,
    principal: result.principal,
    task: authTasks[2],
    authAdapter: auth,
    now: NOW + 65,
  });
  assert.equal(retry.stateV1, 'completed');
  assert.equal(retry.providerCalledV1, false);
  assert.equal(auth.deleteCalls, 1);
});

test('an expired lease is fenced so the stale worker cannot advance the newer checkpoint', async () => {
  const result = await acceptedAccount();
  const task = tasksFor(result.repository, result.accepted, result.principal)
    .find((entry) => entry.kindV1 === 'authDisable');
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  let releaseFirst;
  let releaseSecond;
  let firstCheckpointStartedResolve;
  let secondCheckpointStartedResolve;
  const firstGate = new Promise((resolve) => { releaseFirst = resolve; });
  const secondGate = new Promise((resolve) => { releaseSecond = resolve; });
  const firstCheckpointStarted = new Promise((resolve) => {
    firstCheckpointStartedResolve = resolve;
  });
  const secondCheckpointStarted = new Promise((resolve) => {
    secondCheckpointStartedResolve = resolve;
  });
  const first = runTask({
    repository: result.repository,
    principal: result.principal,
    task,
    authAdapter: auth,
    now: NOW + 2,
    hooks: {beforeCheckpointPersistV1: async () => {
      firstCheckpointStartedResolve();
      await firstGate;
    }},
  });
  await firstCheckpointStarted;
  const second = runTask({
    repository: result.repository,
    principal: result.principal,
    task,
    authAdapter: auth,
    now: NOW + 63,
    hooks: {beforeCheckpointPersistV1: async () => {
      secondCheckpointStartedResolve();
      await secondGate;
    }},
  });
  await secondCheckpointStarted;
  releaseFirst();
  assert.equal((await first).stateV1, 'staleLease');
  releaseSecond();
  assert.equal((await second).stateV1, 'completed');
  assert.equal(auth.disableCalls, 1);
  const receipt = result.repository.values.get(records.deletionEffectReceiptPathV1(
    result.accepted.internalJobId,
    task.effectIdV1,
  ));
  assert.equal(receipt.acceptedLifecycleEpochV2,
    result.principal.accountLifecycleEpochV2 + 1);
});

test('an expired Auth worker cannot delete a recreated UID generation', async () => {
  const result = await acceptedAccount({uid: 'auth-generation-race'});
  const authTasks = tasksFor(result.repository, result.accepted, result.principal)
    .filter((entry) => entry.kindV1.startsWith('auth'));
  const auth = new FakeAuthAdapter(result.repository,
    result.principal.accountGenerationV2);
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[0], authAdapter: auth, now: NOW + 2});
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[1], authAdapter: auth, now: NOW + 3});

  let releaseStaleWorker;
  let staleMutationStartedResolve;
  const staleGate = new Promise((resolve) => { releaseStaleWorker = resolve; });
  const staleMutationStarted = new Promise((resolve) => {
    staleMutationStartedResolve = resolve;
  });
  const stale = runTask({
    repository: result.repository,
    principal: result.principal,
    task: authTasks[2],
    authAdapter: auth,
    now: NOW + 4,
    hooks: {beforeExternalCallV1: async (label) => {
      if (label === 'firebaseAuth.deleteSingleUserIfGenerationMatchesV1') {
        staleMutationStartedResolve();
        await staleGate;
      }
    }},
  });
  await staleMutationStarted;
  assert.equal((await runTask({
    repository: result.repository,
    principal: result.principal,
    task: authTasks[2],
    authAdapter: auth,
    now: NOW + 65,
  })).stateV1, 'completed');
  const recreatedGeneration = 'e'.repeat(64);
  auth.recreateV1(recreatedGeneration);
  releaseStaleWorker();
  await assert.rejects(() => stale, {codeV1: 'AD04_EFFECT_CONFLICT'});
  assert.deepEqual({present: auth.present, generationHash: auth.generationHash,
    deleteCalls: auth.deleteCalls}, {
    present: true,
    generationHash: recreatedGeneration,
    deleteCalls: 1,
  });
});

test('faults after each mutating Auth effect converge without duplicate provider mutations', async () => {
  const result = await acceptedAccount({uid: 'auth-effect-faults'});
  const authTasks = tasksFor(result.repository, result.accepted, result.principal)
    .filter((entry) => entry.kindV1.startsWith('auth'));
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  const failOnceAfter = (targetLabel) => {
    let pending = true;
    return {afterExternalCallV1: async (label) => {
      if (pending && label === targetLabel) {
        pending = false;
        throw new Error(`fault after ${targetLabel}`);
      }
    }};
  };
  const cases = [
    {task: authTasks[0], label: 'firebaseAuth.disableSingleUserIfGenerationMatchesV1',
      firstNow: NOW + 2, retryNow: NOW + 62},
    {task: authTasks[1], label: 'firebaseAuth.revokeRefreshTokensIfGenerationMatchesV1',
      firstNow: NOW + 63, retryNow: NOW + 123},
    {task: authTasks[2], label: 'firebaseAuth.deleteSingleUserIfGenerationMatchesV1',
      firstNow: NOW + 124, retryNow: NOW + 184},
  ];
  for (const current of cases) {
    const first = await runTask({repository: result.repository,
      principal: result.principal, task: current.task, authAdapter: auth,
      now: current.firstNow, hooks: failOnceAfter(current.label)});
    assert.equal(first.stateV1, 'retryScheduled');
    const retry = await runTask({repository: result.repository,
      principal: result.principal, task: current.task, authAdapter: auth,
      now: current.retryNow});
    assert.equal(retry.stateV1, 'completed');
    assert.equal(retry.providerCalledV1, false);
  }
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[3], authAdapter: auth, now: NOW + 185});
  assert.deepEqual({disable: auth.disableCalls, revoke: auth.revokeCalls, delete: auth.deleteCalls},
    {disable: 1, revoke: 1, delete: 1});
});

test('a recreated same UID with a new generation is fenced before any Auth mutation', async () => {
  const result = await acceptedAccount();
  const task = tasksFor(result.repository, result.accepted, result.principal)
    .find((entry) => entry.kindV1 === 'authDisable');
  const auth = new FakeAuthAdapter(result.repository, 'e'.repeat(64));
  await assert.rejects(() => runTask({
    repository: result.repository,
    principal: result.principal,
    task,
    authAdapter: auth,
  }), {codeV1: 'AD04_EFFECT_CONFLICT'});
  assert.equal(auth.disableCalls, 0);
  assert.equal(auth.deleteCalls, 0);
});

test('a self-consistent but noncanonical dependency record cannot authorize the next effect', async () => {
  const result = await acceptedAccount();
  const authTasks = tasksFor(result.repository, result.accepted, result.principal)
    .filter((entry) => entry.kindV1.startsWith('auth'));
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  await runTask({repository: result.repository, principal: result.principal,
    task: authTasks[0], authAdapter: auth, now: NOW + 2});
  const dependencyPath = records.deletionTaskPathV1(result.accepted.internalJobId,
    authTasks[0].effectIdV1);
  const receiptPath = records.deletionEffectReceiptPathV1(result.accepted.internalJobId,
    authTasks[0].effectIdV1);
  const dependency = result.repository.values.get(dependencyPath);
  const noncanonicalFingerprint = records.deletionTaskEffectFingerprintV1({
    scope: dependency,
    internalJobId: dependency.internalJobId,
    generationHash: dependency.generationHash,
    acceptedLifecycleEpochV2: dependency.acceptedLifecycleEpochV2,
    kindV1: dependency.kindV1,
    adapterIdV1: dependency.adapterIdV1,
    adapterVersionV1: 'firebase-auth-v2',
  });
  result.repository.values.set(dependencyPath, {
    ...dependency,
    adapterVersionV1: 'firebase-auth-v2',
    effectFingerprintV1: noncanonicalFingerprint,
  });
  result.repository.values.set(receiptPath, {
    ...result.repository.values.get(receiptPath),
    effectFingerprintV1: noncanonicalFingerprint,
  });
  await assert.rejects(() => runTask({repository: result.repository,
    principal: result.principal, task: authTasks[1], authAdapter: auth,
    now: NOW + 3}), {codeV1: 'AD04_EFFECT_CONFLICT'});
  assert.equal(auth.revokeCalls, 0);
});

test('Apple disposition distinguishes non-Apple, missing material, and verified revoke plus destruction', async () => {
  const nonApple = await acceptedAccount();
  const nonAppleTask = tasksFor(nonApple.repository, nonApple.accepted, nonApple.principal)
    .find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  const nonAppleAuth = new FakeAuthAdapter(nonApple.repository,
    nonApple.principal.accountGenerationV2);
  assert.equal((await runTask({repository: nonApple.repository, principal: nonApple.principal,
    task: nonAppleTask, authAdapter: nonAppleAuth})).stateV1, 'completed');

  const missing = await acceptedAccount({uid: 'apple-user', apple: true,
    intentId: 'intent_apple_missing', requestValue: request({
      intentId: 'intent_apple_missing', operationId: 'apple_missing_op',
      requestId: 'apple_missing_request',
    })});
  const missingTask = tasksFor(missing.repository, missing.accepted, missing.principal)
    .find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  const missingAuth = new FakeAuthAdapter(missing.repository,
    missing.principal.accountGenerationV2);
  assert.equal((await runTask({repository: missing.repository, principal: missing.principal,
    task: missingTask, authAdapter: missingAuth})).stateV1, 'completed');
  assert.equal(missing.repository.values.get(records.deletionProviderCheckpointPathV1(
    missing.accepted.internalJobId, 'appleCredential')).state, 'manualActionGuidance');

  const applePrincipal = await principalFor({uid: 'apple-user', apple: true});
  const material = coordinator.candidateRevocationMaterialV1({
    scope: applePrincipal,
    generationHash: applePrincipal.accountGenerationV2,
    accountLifecycleEpochV2: applePrincipal.accountLifecycleEpochV2,
    providerRevocationRefV1: 'apple_material_ref',
    providerSubjectHashV1: applePrincipal.appleProviderSubjectHashV1,
    materialFingerprintV1: 'f'.repeat(64),
    expiresAtSecV1: NOW + 600,
  });
  const withMaterial = await acceptedAccount({
    uid: 'apple-user', apple: true, material,
    intentId: 'intent_apple_material',
    requestValue: request({
      intentId: 'intent_apple_material', operationId: 'apple_material_op',
      requestId: 'apple_material_request', patch: {providerRevocationRef: 'apple_material_ref'},
    }),
  });
  const appleTask = tasksFor(withMaterial.repository, withMaterial.accepted,
    withMaterial.principal).find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  const appleState = {transient: true, revoked: false, destroyed: false,
    revokeCalls: 0, destroyCalls: 0};
  const appleAdapter = {
    inspectRevocationV1: async () => {
      if (appleState.transient) {
        appleState.transient = false;
        throw new Error('transient Apple provider failure');
      }
      return {
        revocationStateV1: appleState.revoked ? 'revoked' : 'pending',
        materialStateV1: appleState.destroyed ? 'destroyed' : 'available',
      };
    },
    revokeCredentialV1: async () => { appleState.revokeCalls += 1; appleState.revoked = true; },
    destroyRevocationMaterialV1: async () => {
      appleState.destroyCalls += 1; appleState.destroyed = true;
    },
  };
  const withMaterialAuth = new FakeAuthAdapter(withMaterial.repository,
    withMaterial.principal.accountGenerationV2);
  assert.equal((await runTask({repository: withMaterial.repository,
    principal: withMaterial.principal, task: appleTask, authAdapter: withMaterialAuth,
    appleAdapter, now: NOW + 2})).stateV1, 'retryScheduled');
  assert.equal(withMaterial.repository.values.get(records.deletionProviderCheckpointPathV1(
    withMaterial.accepted.internalJobId, 'appleCredential')).state, 'pending');
  assert.equal((await runTask({repository: withMaterial.repository,
    principal: withMaterial.principal, task: appleTask, authAdapter: withMaterialAuth,
    appleAdapter, now: NOW + 62})).stateV1, 'completed');
  assert.deepEqual(appleState, {transient: false, revoked: true, destroyed: true,
    revokeCalls: 1, destroyCalls: 1});
});

test('faults after Apple and cleanup effects recover by inspection without repeating effects', async () => {
  const applePrincipal = await principalFor({uid: 'apple-effect-faults', apple: true});
  const material = coordinator.candidateRevocationMaterialV1({
    scope: applePrincipal,
    generationHash: applePrincipal.accountGenerationV2,
    accountLifecycleEpochV2: applePrincipal.accountLifecycleEpochV2,
    providerRevocationRefV1: 'apple_fault_material',
    providerSubjectHashV1: applePrincipal.appleProviderSubjectHashV1,
    materialFingerprintV1: 'c'.repeat(64),
    expiresAtSecV1: NOW + 600,
  });
  const appleResult = await acceptedAccount({uid: 'apple-effect-faults', apple: true,
    material, intentId: 'intent_apple_faults', requestValue: request({
      intentId: 'intent_apple_faults', operationId: 'apple_faults_op',
      requestId: 'apple_faults_request',
      patch: {providerRevocationRef: 'apple_fault_material'},
    })});
  const appleTask = tasksFor(appleResult.repository, appleResult.accepted,
    appleResult.principal).find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  const appleState = {revoked: false, destroyed: false, revokeCalls: 0, destroyCalls: 0};
  const appleAdapter = {
    inspectRevocationV1: async () => ({
      revocationStateV1: appleState.revoked ? 'revoked' : 'pending',
      materialStateV1: appleState.destroyed ? 'destroyed' : 'available',
    }),
    revokeCredentialV1: async () => { appleState.revokeCalls += 1; appleState.revoked = true; },
    destroyRevocationMaterialV1: async () => {
      appleState.destroyCalls += 1;
      appleState.destroyed = true;
    },
  };
  const faultLabels = new Set([
    'appleCredential.revokeCredentialV1',
    'appleCredential.destroyRevocationMaterialV1',
  ]);
  const hooks = {afterExternalCallV1: async (label) => {
    if (faultLabels.delete(label)) throw new Error(`fault after ${label}`);
  }};
  const appleAuth = new FakeAuthAdapter(appleResult.repository,
    appleResult.principal.accountGenerationV2);
  assert.equal((await runTask({repository: appleResult.repository,
    principal: appleResult.principal, task: appleTask, authAdapter: appleAuth,
    appleAdapter, hooks, now: NOW + 2})).stateV1, 'retryScheduled');
  assert.equal((await runTask({repository: appleResult.repository,
    principal: appleResult.principal, task: appleTask, authAdapter: appleAuth,
    appleAdapter, hooks, now: NOW + 62})).stateV1, 'retryScheduled');
  assert.equal((await runTask({repository: appleResult.repository,
    principal: appleResult.principal, task: appleTask, authAdapter: appleAuth,
    appleAdapter, hooks, now: NOW + 182})).stateV1, 'completed');
  assert.deepEqual(appleState, {revoked: true, destroyed: true,
    revokeCalls: 1, destroyCalls: 1});

  const cleanupResult = await acceptedAccount({uid: 'cleanup-effect-fault'});
  const cleanupTask = tasksFor(cleanupResult.repository, cleanupResult.accepted,
    cleanupResult.principal).find((entry) => entry.kindV1 === 'cleanupAdapter');
  const applied = new Map();
  let applyCalls = 0;
  const cleanupAdapter = fakeCleanupAdapter(cleanupResult.repository,
    cleanupTask.adapterIdV1, applied);
  const originalApply = cleanupAdapter.applyEffectV1;
  cleanupAdapter.applyEffectV1 = async (input) => {
    applyCalls += 1;
    return originalApply(input);
  };
  let failAfterApply = true;
  const cleanupHooks = {afterExternalCallV1: async (label) => {
    if (failAfterApply && label === `${cleanupTask.adapterIdV1}.applyEffectV1`) {
      failAfterApply = false;
      throw new Error('fault after cleanup apply');
    }
  }};
  const cleanupAuth = new FakeAuthAdapter(cleanupResult.repository,
    cleanupResult.principal.accountGenerationV2);
  assert.equal((await runTask({repository: cleanupResult.repository,
    principal: cleanupResult.principal, task: cleanupTask, authAdapter: cleanupAuth,
    cleanupAdapters: [cleanupAdapter], hooks: cleanupHooks,
    now: NOW + 2})).stateV1, 'retryScheduled');
  assert.equal((await runTask({repository: cleanupResult.repository,
    principal: cleanupResult.principal, task: cleanupTask, authAdapter: cleanupAuth,
    cleanupAdapters: [cleanupAdapter], hooks: cleanupHooks,
    now: NOW + 62})).stateV1, 'completed');
  assert.equal(applyCalls, 1);
});

test('cleanup completion requires an independent post-apply inspection', async () => {
  const result = await acceptedAccount({uid: 'cleanup-post-inspect'});
  const cleanupTask = tasksFor(result.repository, result.accepted, result.principal)
    .find((entry) => entry.kindV1 === 'cleanupAdapter');
  const auth = new FakeAuthAdapter(result.repository,
    result.principal.accountGenerationV2);
  let inspectCalls = 0;
  let applyCalls = 0;
  const optimisticAdapter = {
    adapterIdV1: cleanupTask.adapterIdV1,
    adapterVersionV1: cleanupTask.adapterVersionV1,
    inspectEffectV1: async () => {
      inspectCalls += 1;
      return null;
    },
    applyEffectV1: async ({policyVersion}) => {
      applyCalls += 1;
      return terminalAdapterResult(cleanupTask.adapterIdV1, policyVersion);
    },
  };
  const outcome = await runTask({
    repository: result.repository,
    principal: result.principal,
    task: cleanupTask,
    authAdapter: auth,
    cleanupAdapters: [optimisticAdapter],
    now: NOW + 2,
  });
  assert.equal(outcome.stateV1, 'retryScheduled');
  assert.deepEqual({inspectCalls, applyCalls}, {inspectCalls: 2, applyCalls: 1});
  assert.equal(result.repository.values.has(records.deletionEffectReceiptPathV1(
    result.accepted.internalJobId, cleanupTask.effectIdV1)), false);
  assert.equal(result.repository.values.has(records.deletionAdapterResultPathV1(
    result.accepted.internalJobId, cleanupTask.adapterIdV1)), false);
});

test('all required fake adapters and provider receipts are required before final completion', async () => {
  const result = await acceptedAccount();
  const tasks = tasksFor(result.repository, result.accepted, result.principal);
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  const cleanupAdapters = contract.accountDeletionAdapterIds.map((adapterId) =>
    fakeCleanupAdapter(result.repository, adapterId));
  let tick = 2;
  for (const taskValue of tasks.filter((entry) => entry.kindV1.startsWith('auth'))) {
    await runTask({repository: result.repository, principal: result.principal,
      task: taskValue, authAdapter: auth, cleanupAdapters, now: NOW + tick++});
  }
  const appleTask = tasks.find((entry) => entry.kindV1 === 'appleCredentialDisposition');
  await runTask({repository: result.repository, principal: result.principal,
    task: appleTask, authAdapter: auth, cleanupAdapters, now: NOW + tick++});
  const cleanupTasks = tasks.filter((entry) => entry.kindV1 === 'cleanupAdapter');
  for (const taskValue of cleanupTasks.slice(0, -1)) {
    await runTask({repository: result.repository, principal: result.principal,
      task: taskValue, authAdapter: auth, cleanupAdapters, now: NOW + tick++});
  }
  const reconcileTask = tasks.find((entry) => entry.kindV1 === 'reconcileCompletion');
  assert.equal((await runTask({repository: result.repository, principal: result.principal,
    task: reconcileTask, authAdapter: auth, cleanupAdapters, now: NOW + tick++})).stateV1,
  'dependencyPending');
  await runTask({repository: result.repository, principal: result.principal,
    task: cleanupTasks.at(-1), authAdapter: auth, cleanupAdapters, now: NOW + tick++});
  const originalRunTransaction = result.repository.runTransaction.bind(result.repository);
  let reconciliationTransactions = 0;
  result.repository.runTransaction = async (operation) => {
    reconciliationTransactions += 1;
    if (reconciliationTransactions === 3) {
      throw new Error('simulated reconciliation crash');
    }
    return originalRunTransaction(operation);
  };
  await assert.rejects(() => runTask({repository: result.repository,
    principal: result.principal, task: reconcileTask, authAdapter: auth,
    cleanupAdapters, now: NOW + tick++}), /simulated reconciliation crash/);
  result.repository.runTransaction = originalRunTransaction;
  assert.equal(result.repository.values.get(records.deletionTaskPathV1(
    result.accepted.internalJobId, reconcileTask.effectIdV1)).stateV1, 'complete');
  assert.equal(result.repository.values.get(records.deletionJobPathV1(
    result.accepted.internalJobId)).state === 'complete', false);
  assert.equal((await runTask({repository: result.repository, principal: result.principal,
    task: reconcileTask, authAdapter: auth, cleanupAdapters, now: NOW + tick++})).stateV1,
  'alreadyCompleted');
  const job = result.repository.values.get(records.deletionJobPathV1(
    result.accepted.internalJobId));
  assert.equal(job.state, 'complete');
  assert.equal(job.authAbsent, true);
  assert.equal(result.repository.values.get(ad02.accountLifecycleAuthorityPathV2(
    result.principal)).lifecycleStateV2, 'deleted');
  const status = await coordinator.getCandidateAccountDeletionStatusV1({
    repository: result.repository,
    request: {schemaVersion: 1, requestId: result.request.requestId,
      statusSecret: STATUS_SECRET},
    nowSecV1: NOW + tick,
  });
  assert.equal(status.phase, 'complete');
  assert.equal(status.providerOutcome, 'not_applicable');
  assert.match(status.completedAt, /^2026-/);
  assert.deepEqual(await coordinator.acceptCandidateAccountDeletionV1({
    repository: result.repository,
    principal: result.principal,
    request: result.request,
    nowSecV1: NOW + tick,
  }), result.accepted);
});

test('retry exhaustion raises attention, is explicitly resumable, and unfinished work has no TTL', async () => {
  const result = await acceptedAccount();
  const cleanupTask = tasksFor(result.repository, result.accepted, result.principal)
    .find((entry) => entry.kindV1 === 'cleanupAdapter');
  const taskPath = records.deletionTaskPathV1(result.accepted.internalJobId,
    cleanupTask.effectIdV1);
  result.repository.values.set(taskPath, {...result.repository.values.get(taskPath),
    attemptsV1: 19});
  const failing = {
    adapterIdV1: cleanupTask.adapterIdV1,
    adapterVersionV1: cleanupTask.adapterVersionV1,
    inspectEffectV1: async () => { throw new Error('transient'); },
    applyEffectV1: async () => { throw new Error('unreachable'); },
  };
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  const exhausted = await runTask({repository: result.repository, principal: result.principal,
    task: cleanupTask, authAdapter: auth, cleanupAdapters: [failing], now: NOW + 2});
  assert.equal(exhausted.stateV1, 'needsAttention');
  assert.equal(result.repository.values.get(taskPath).attemptsV1, 20);
  assert.equal(result.repository.values.get(taskPath).expiresAt, undefined);
  assert.equal([...result.repository.values.keys()].some((key) =>
    key.startsWith('accountDeletionAlertsV1/')), true);
  await assert.rejects(() => worker.resumeCandidateDeletionTaskV1({
    repository: result.repository,
    authorizer: {authorizeResumeV1: async () => false},
    locator: worker.candidateTaskLocatorV1(cleanupTask),
    reasonCodeV1: 'operator_reviewed',
    nowSecV1: NOW + 3,
  }), {codeV1: 'AD04_AUTHORITY_DENIED'});
  const resumed = await worker.resumeCandidateDeletionTaskV1({
    repository: result.repository,
    authorizer: {authorizeResumeV1: async () => true},
    locator: worker.candidateTaskLocatorV1(cleanupTask),
    reasonCodeV1: 'operator_reviewed',
    nowSecV1: NOW + 4,
  });
  assert.equal(resumed.stateV1, 'pending');
  assert.equal(resumed.attemptsV1, 0);
});

test('authorized resume advances exact-bound nonterminal cleanup evidence', async () => {
  const result = await acceptedAccount({uid: 'cleanup-resume-evidence'});
  const cleanupTask = tasksFor(result.repository, result.accepted, result.principal)
    .find((entry) => entry.kindV1 === 'cleanupAdapter');
  const auth = new FakeAuthAdapter(result.repository,
    result.principal.accountGenerationV2);
  assert.equal((await runTask({
    repository: result.repository,
    principal: result.principal,
    task: cleanupTask,
    authAdapter: auth,
    now: NOW + 2,
  })).stateV1, 'needsAttention');
  const resultPath = records.deletionAdapterResultPathV1(
    result.accepted.internalJobId, cleanupTask.adapterIdV1);
  assert.equal(result.repository.values.get(resultPath).state, 'unsupported');

  const adapter = fakeCleanupAdapter(result.repository, cleanupTask.adapterIdV1);
  const attentionTask = result.repository.values.get(records.deletionTaskPathV1(
    result.accepted.internalJobId, cleanupTask.effectIdV1));
  assert.equal((await runTask({
    repository: result.repository,
    principal: result.principal,
    task: cleanupTask,
    authAdapter: auth,
    cleanupAdapters: [adapter],
    now: NOW + 3,
  })).stateV1, 'needsAttention');
  assert.deepEqual(result.repository.values.get(records.deletionTaskPathV1(
    result.accepted.internalJobId, cleanupTask.effectIdV1)), attentionTask);
  assert.equal(result.repository.values.get(resultPath).state, 'unsupported');

  await worker.resumeCandidateDeletionTaskV1({
    repository: result.repository,
    authorizer: {authorizeResumeV1: async () => true},
    locator: worker.candidateTaskLocatorV1(cleanupTask),
    reasonCodeV1: 'adapter_now_available',
    nowSecV1: NOW + 4,
  });
  assert.equal((await runTask({
    repository: result.repository,
    principal: result.principal,
    task: cleanupTask,
    authAdapter: auth,
    cleanupAdapters: [adapter],
    now: NOW + 5,
  })).stateV1, 'completed');
  assert.equal(result.repository.values.get(resultPath).state, 'complete');
});

test('Auth on-delete and bounded orphan sweep are verifier-gated, replay-safe, and never reconstruct Auth', async () => {
  const repo = new MemoryRepository();
  const event = {
    schemaVersion: 1,
    eventIdV1: 'auth_event_one',
    ...scope('auth-only'),
    authCreatedAtIsoV1: CREATED,
    generationHash: generationFor('auth-only'),
    accountLifecycleEpochV2: 7,
    providerRelationshipV1: 'nonApple',
    appleProviderSubjectHashV1: null,
    observedDeletedAtSecV1: NOW,
  };
  const verifier = {verifyAuthDeletionEventV1: async () => clone(event)};
  const first = await reconciliation.handleCandidateUnexpectedAuthDeletionV1({
    repository: repo, verifier, event: {signed: true}, configuredProjectId: fixture.projectId,
  });
  const second = await reconciliation.handleCandidateUnexpectedAuthDeletionV1({
    repository: repo, verifier, event: {signed: true}, configuredProjectId: fixture.projectId,
  });
  assert.equal(first.internalJobId, second.internalJobId);
  assert.equal(first.authAbsent, true);
  assert.equal([...repo.values.keys()].some((key) => key.startsWith('users/')), false);
  const swept = await reconciliation.runCandidateAuthOrphanReconciliationV1({
    repository: repo,
    scanner: {listVerifiedAbsentAccountsV1: async ({limitV1}) => {
      assert.equal(limitV1, 1);
      return [event];
    }},
    configuredProjectId: fixture.projectId,
    limitV1: 1,
  });
  assert.equal(swept.length, 1);
  await assert.rejects(() => reconciliation.runCandidateAuthOrphanReconciliationV1({
    repository: repo,
    scanner: {listVerifiedAbsentAccountsV1: async () => []},
    configuredProjectId: fixture.projectId,
    limitV1: 101,
  }), {codeV1: 'AD04_INVALID_REQUEST'});
});

test('verified Apple events are exact and replay-safe; invalid verifier output writes nothing', async () => {
  const applePrincipal = await principalFor({uid: 'apple-user', apple: true});
  const material = coordinator.candidateRevocationMaterialV1({
    scope: applePrincipal,
    generationHash: applePrincipal.accountGenerationV2,
    accountLifecycleEpochV2: applePrincipal.accountLifecycleEpochV2,
    providerRevocationRefV1: 'apple_event_material',
    providerSubjectHashV1: applePrincipal.appleProviderSubjectHashV1,
    materialFingerprintV1: 'a'.repeat(64),
    expiresAtSecV1: NOW + 600,
  });
  const result = await acceptedAccount({uid: 'apple-user', apple: true, material,
    intentId: 'intent_apple_event', requestValue: request({
      intentId: 'intent_apple_event', operationId: 'apple_event_op',
      requestId: 'apple_event_request', patch: {providerRevocationRef: 'apple_event_material'},
    })});
  const before = result.repository.transactionCount;
  await assert.rejects(() => reconciliation.handleCandidateAppleCredentialEventV1({
    repository: result.repository,
    verifier: {verifyAppleCredentialEventV1: async () => ({invalid: true})},
    event: {signature: 'bad'},
    configuredProjectId: fixture.projectId,
  }), {codeV1: 'AD04_AUTHORITY_DENIED'});
  assert.equal(result.repository.transactionCount, before);
  const event = {
    schemaVersion: 1,
    eventIdV1: 'apple_event_one',
    ...scope('apple-user'),
    generationHash: result.principal.accountGenerationV2,
    acceptedLifecycleEpochV2: result.principal.accountLifecycleEpochV2 + 1,
    internalJobId: result.accepted.internalJobId,
    providerSubjectHashV1: result.principal.appleProviderSubjectHashV1,
    observedAtSecV1: NOW + 2,
  };
  const checkpointPath = records.deletionProviderCheckpointPathV1(
    result.accepted.internalJobId, 'appleCredential');
  const checkpointBeforeStaleEvent = clone(result.repository.values.get(checkpointPath));
  const staleEvent = {...event, eventIdV1: 'apple_event_stale', observedAtSecV1: NOW};
  await assert.rejects(() => reconciliation.handleCandidateAppleCredentialEventV1({
    repository: result.repository,
    verifier: {verifyAppleCredentialEventV1: async () => clone(staleEvent)},
    event: {signature: 'valid-but-stale'},
    configuredProjectId: fixture.projectId,
  }), {codeV1: 'AD04_EFFECT_CONFLICT'});
  assert.equal(result.repository.values.has(records.deletionProviderEventReceiptPathV1(
    staleEvent.eventIdV1)), false);
  assert.deepEqual(result.repository.values.get(checkpointPath), checkpointBeforeStaleEvent);
  const verifier = {verifyAppleCredentialEventV1: async () => clone(event)};
  assert.equal(await reconciliation.handleCandidateAppleCredentialEventV1({
    repository: result.repository, verifier, event: {signature: 'valid'},
    configuredProjectId: fixture.projectId,
  }), 'recorded');
  assert.equal(await reconciliation.handleCandidateAppleCredentialEventV1({
    repository: result.repository, verifier, event: {signature: 'valid'},
    configuredProjectId: fixture.projectId,
  }), 'replayed');
});

test('task locators bind project, tenant, UID, generation, job, and effect exactly', async () => {
  const result = await acceptedAccount();
  const task = tasksFor(result.repository, result.accepted, result.principal)[0];
  const auth = new FakeAuthAdapter(result.repository, result.principal.accountGenerationV2);
  for (const patch of [
    {authProjectIdV2: 'other-project'},
    {authUidV2: 'other-user'},
    {generationHash: 'b'.repeat(64)},
    {acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2 + 1},
    {internalJobId: 'job_other'},
    {effectIdV1: 'ef_' + 'c'.repeat(64)},
  ]) {
    await assert.rejects(() => worker.runCandidateDeletionTaskV1({
      repository: result.repository,
      locator: {...worker.candidateTaskLocatorV1(task), ...patch},
      workerIdV1: 'worker_tamper',
      configuredProjectId: fixture.projectId,
      nowSecV1: NOW + 2,
      firebaseAuthAdapterV1: auth,
      appleCredentialAdapterV1: null,
      cleanupAdaptersV1: [],
    }), (error) => ['AD04_AUTHORITY_DENIED', 'AD04_TASK_NOT_READY',
      'AD04_EFFECT_CONFLICT'].includes(error.codeV1));
  }
  assert.equal(auth.disableCalls, 0);
});
