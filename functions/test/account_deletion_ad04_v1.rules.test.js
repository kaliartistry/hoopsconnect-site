'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  runTransaction,
  setDoc,
} = require('firebase/firestore');

const contract = require('../lib/domain/account_deletion_contract');
const records = require('../lib/account_deletion/ad04_records');
const coordinator = require('../lib/account_deletion/ad04_coordinator');
const worker = require('../lib/account_deletion/ad04_worker');
const reconciliation = require('../lib/account_deletion/ad04_reconciliation');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad04/lifecycle_cleanup_fixtures_v1.json',
), 'utf8'));
const rules = fs.readFileSync(path.resolve(
  __dirname,
  'fixtures/account_deletion_ad04_v1/firestore.rules',
), 'utf8');

const NOW = fixture.nowSecV1;
const CREATED = fixture.authCreatedAtIsoV1;
let testEnv;

function normalize(value) {
  if (value === null || value === undefined) return value;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (Array.isArray(value)) return value.map(normalize);
  if (typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, normalize(entry)]));
  }
  return value;
}

class EmulatorTransactionRepository {
  constructor(db) {
    this.db = db;
  }

  async read(pathValue) {
    const snapshot = await getDoc(doc(this.db, pathValue));
    return snapshot.exists() ? normalize(snapshot.data()) : null;
  }

  async runTransaction(operation) {
    return runTransaction(this.db, async (firestoreTransaction) => {
      let writeStarted = false;
      const adapter = {
        read: async (pathValue) => {
          if (writeStarted) throw new Error('AD04 emulator adapter read after write');
          const snapshot = await firestoreTransaction.get(doc(this.db, pathValue));
          return snapshot.exists() ? normalize(snapshot.data()) : null;
        },
        write: (pathValue, value) => {
          writeStarted = true;
          firestoreTransaction.set(doc(this.db, pathValue), value);
        },
      };
      return operation(adapter);
    });
  }
}

function scope(uid = 'owner-a') {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: null,
    authUidV2: uid,
  };
}

function generationFor(uid) {
  return contract.accountGenerationHash({
    authNamespace: `firebase:${fixture.projectId}:root`,
    accountId: uid,
    authCreatedAt: new Date(CREATED),
  });
}

function snapshot(uid = 'owner-a', authTimeSecV1 = NOW - 10) {
  return {
    schemaVersion: 1,
    ...scope(uid),
    authCreatedAtIsoV1: CREATED,
    accountGenerationV2: generationFor(uid),
    accountLifecycleEpochV2: 7,
    authTimeSecV1,
    issuerV1: `https://securetoken.google.com/${fixture.projectId}`,
    audienceV1: fixture.projectId,
    providerIdsV1: ['password'],
    appleProviderSubjectHashV1: null,
    revocationCheckedV1: true,
    appAttestationVerifiedV1: true,
  };
}

async function principal(uid = 'owner-a') {
  return coordinator.establishVerifiedDeletionPrincipalV1({
    verifier: {verifyCurrentAccountV1: async () => snapshot(uid)},
    presentedCredential: {opaque: true},
    configuredProjectId: fixture.projectId,
    nowSecV1: NOW,
  });
}

function deletionRequest(operationId, requestId, statusSecretHash) {
  return {
    schemaVersion: 1,
    intentId: 'intent_race',
    policyVersion: 'policy_v1',
    impactVersion: 'impact_v1',
    operationId,
    requestId,
    statusSecretHash,
    confirmation: 'deleteAccount',
    custodyChoice: 'ordinary',
  };
}

async function seedAndPrepare(repository, db, currentPrincipal, seedLifecycle = true) {
  if (seedLifecycle) {
    await setDoc(doc(db, records.candidateAccountLifecycleAuthorityPathV1(currentPrincipal)), {
      authIncarnationSchemaVersionV2: 2,
      ...scope(currentPrincipal.authUidV2),
      accountGenerationV2: currentPrincipal.accountGenerationV2,
      accountLifecycleEpochV2: 7,
      lifecycleStateV2: 'active',
      reauthAfterSecV2: NOW - 120,
    });
  }
  await coordinator.prepareCandidateAccountDeletionV1({
    repository,
    principal: currentPrincipal,
    request: {schemaVersion: 1},
    impact: {
      schemaVersion: 1,
      policyVersion: 'policy_v1',
      impactVersion: 'impact_v1',
      custodyChoice: 'ordinary',
      associationId: null,
      ownerDepartureRequestV2: null,
      candidateTestCustodyPolicyIdV2: null,
    },
    intentId: 'intent_race',
    nowSecV1: NOW,
  });
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: fixture.projectId,
    firestore: {rules},
  });
});

test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all raw AD04 intent, job, status, receipt, material, event, and alert paths are private', async () => {
  const db = testEnv.authenticatedContext('owner-a', {role: 'superAdmin'}).firestore();
  for (const pathValue of [
    'accountDeletionIntentsV1/intent_one',
    'accountDeletionJobsV1/job_one',
    'accountDeletionJobsV1/job_one/tasks/effect_one',
    'accountDeletionStatusV1/request_one',
    'accountDeletionStatusControlsV1/request_one',
    'accountDeletionReceiptsV1/receipt_one',
    'accountDeletionRevocationMaterialV1/material_one',
    'accountDeletionProviderEventsV1/event_one',
    'accountDeletionAlertsV1/alert_one',
  ]) {
    await assertFails(getDoc(doc(db, pathValue)));
    await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
  }
});

test('real Firestore transactions converge a two-device acceptance race to one job and two aliases', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorTransactionRepository(db);
    const firstPrincipal = await principal();
    const secondPrincipal = await principal();
    await seedAndPrepare(repository, db, firstPrincipal);
    const requests = [
      deletionRequest('operation_race_a', 'request_race_a',
        fixture.status.secretHash),
      deletionRequest('operation_race_b', 'request_race_b',
        contract.statusSecretHash(Buffer.alloc(32, 1).toString('base64url'))),
    ];
    const outcomes = await Promise.all(requests.map((request) =>
      coordinator.acceptCandidateAccountDeletionV1({
        repository,
        principal: request.operationId.endsWith('_a') ? firstPrincipal : secondPrincipal,
        request,
        nowSecV1: NOW + 1,
      })));
    assert.equal(new Set(outcomes.map((value) => value.internalJobId)).size, 1);
    assert.deepEqual(outcomes.map((value) => value.bindingKind).sort(),
      ['sameGenerationConvergence', 'winningOperation']);
    const internalJobId = outcomes[0].internalJobId;
    const binding = normalize((await getDoc(doc(db,
      records.deletionJobBindingPathV1(internalJobId)))).data());
    assert.equal(binding.statusAliasCountV1, 2);
    assert.equal(['operation_race_a', 'operation_race_b'].includes(
      binding.winningOperationId), true);
    const aliases = await getDocs(collection(db, 'accountDeletionStatusV1'));
    const jobs = await getDocs(collection(db, 'accountDeletionJobsV1'));
    const tasks = await getDocs(collection(db, `accountDeletionJobsV1/${internalJobId}/tasks`));
    assert.equal(aliases.size, 2);
    assert.equal(jobs.size, 1);
    assert.equal(tasks.size, 33);
  });
});

test('real Firestore accepts an unprovisioned Auth-only account with a provider-owned UID', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorTransactionRepository(db);
    const uid = fixture.providerOwnedUidPath.uid;
    const currentPrincipal = await principal(uid);
    await seedAndPrepare(repository, db, currentPrincipal, false);
    const accepted = await coordinator.acceptCandidateAccountDeletionV1({
      repository,
      principal: currentPrincipal,
      request: deletionRequest('operation_provider_uid', 'request_provider_uid',
        fixture.status.secretHash),
      nowSecV1: NOW + 1,
    });
    const lifecyclePath = records.candidateAccountLifecycleAuthorityPathV1(currentPrincipal);
    assert.equal(lifecyclePath,
      `accountLifecycleV2Root/${fixture.providerOwnedUidPath.encodedSegment}`);
    const lifecycle = normalize((await getDoc(doc(db, lifecyclePath))).data());
    assert.equal(lifecycle.authUidV2, uid);
    assert.equal(lifecycle.lifecycleStateV2, 'deleting');
    const tasks = await getDocs(collection(db,
      `accountDeletionJobsV1/${accepted.internalJobId}/tasks`));
    assert.equal(tasks.size, 33);
  });
});

test('real Firestore leases allow one provider effect during a duplicate worker race', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorTransactionRepository(db);
    const currentPrincipal = await principal();
    await seedAndPrepare(repository, db, currentPrincipal);
    const accepted = await coordinator.acceptCandidateAccountDeletionV1({
      repository,
      principal: currentPrincipal,
      request: deletionRequest('operation_worker', 'request_worker',
        fixture.status.secretHash),
      nowSecV1: NOW + 1,
    });
    const task = records.initialDeletionTasksV1({
      scope: currentPrincipal,
      internalJobId: accepted.internalJobId,
      generationHash: currentPrincipal.accountGenerationV2,
      acceptedLifecycleEpochV2: currentPrincipal.accountLifecycleEpochV2 + 1,
      nowSecV1: NOW + 1,
    }).find((entry) => entry.kindV1 === 'authDisable');
    let disabled = false;
    let disableCalls = 0;
    let releaseEffect;
    let effectStartedResolve;
    const effectStarted = new Promise((resolve) => { effectStartedResolve = resolve; });
    const effectGate = new Promise((resolve) => { releaseEffect = resolve; });
    const authState = () => ({
      accountStateV1: 'present',
      observedGenerationHashV1: currentPrincipal.accountGenerationV2,
      disabledV1: disabled,
      refreshTokensRevokedV1: false,
    });
    const authAdapter = {
      inspectSingleUserV1: async () => authState(),
      disableSingleUserIfGenerationMatchesV1: async ({generationHash}) => {
        assert.equal(generationHash, currentPrincipal.accountGenerationV2);
        disableCalls += 1;
        effectStartedResolve();
        await effectGate;
        disabled = true;
        return authState();
      },
      revokeRefreshTokensIfGenerationMatchesV1: async () =>
        assert.fail('unexpected revoke'),
      deleteSingleUserIfGenerationMatchesV1: async () =>
        assert.fail('unexpected delete'),
    };
    const run = (workerIdV1) => worker.runCandidateDeletionTaskV1({
      repository,
      locator: worker.candidateTaskLocatorV1(task),
      workerIdV1,
      configuredProjectId: fixture.projectId,
      nowSecV1: NOW + 2,
      firebaseAuthAdapterV1: authAdapter,
      appleCredentialAdapterV1: null,
      cleanupAdaptersV1: [],
    });
    const first = run('worker_race_a');
    await effectStarted;
    const second = await run('worker_race_b');
    assert.equal(second.stateV1, 'busy');
    releaseEffect();
    assert.equal((await first).stateV1, 'completed');
    assert.equal(disableCalls, 1);
    const receipt = await getDoc(doc(db, records.deletionEffectReceiptPathV1(
      accepted.internalJobId, task.effectIdV1)));
    assert.equal(receipt.exists(), true);
  });
});

test('concurrent verified Auth absence events create one deterministic safety-net job', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorTransactionRepository(db);
    const event = {
      schemaVersion: 1,
      eventIdV1: 'auth_event_race',
      ...scope('orphan-user'),
      authCreatedAtIsoV1: CREATED,
      generationHash: generationFor('orphan-user'),
      accountLifecycleEpochV2: 3,
      providerRelationshipV1: 'nonApple',
      appleProviderSubjectHashV1: null,
      observedDeletedAtSecV1: NOW,
    };
    const verifier = {verifyAuthDeletionEventV1: async () => event};
    const outcomes = await Promise.all([
      reconciliation.handleCandidateUnexpectedAuthDeletionV1({
        repository, verifier, event: {delivery: 1}, configuredProjectId: fixture.projectId,
      }),
      reconciliation.handleCandidateUnexpectedAuthDeletionV1({
        repository, verifier, event: {delivery: 2}, configuredProjectId: fixture.projectId,
      }),
    ]);
    assert.equal(outcomes[0].internalJobId, outcomes[1].internalJobId);
    assert.equal(outcomes[0].authAbsent, true);
    const internalJobId = outcomes[0].internalJobId;
    const jobs = await getDocs(collection(db, 'accountDeletionJobsV1'));
    const tasks = await getDocs(collection(db, `accountDeletionJobsV1/${internalJobId}/tasks`));
    const receipts = await getDocs(collection(db,
      `accountDeletionJobsV1/${internalJobId}/effectReceipts`));
    assert.equal(jobs.size, 1);
    assert.equal(tasks.size, 33);
    assert.equal(receipts.size, 4);
  });
});
