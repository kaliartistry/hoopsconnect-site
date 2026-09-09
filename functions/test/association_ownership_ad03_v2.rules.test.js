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
  doc,
  getDoc,
  runTransaction,
  setDoc,
} = require('firebase/firestore');

const ad02 = require('../lib/domain/account_lifecycle_ad02_v2');
const ad03 = require('../lib/domain/association_ownership_ad03_v2');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad03/ownership_fixtures_v2.json',
), 'utf8'));
const rules = fs.readFileSync(path.resolve(
  __dirname,
  'fixtures/association_ownership_ad03_v2/firestore.rules',
), 'utf8');

const now = 1700000200;
let testEnv;

function accountScope(uid, tenant = null) {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    authUidV2: uid,
  };
}

function associationScope(tenant = null) {
  return {
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: tenant,
    associationId: fixture.associationId,
  };
}

function owner(uid, generation, tenant = null) {
  return {
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: ad03.recoverableOwnerBindingIdV2({
      ...accountScope(uid, tenant),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
    }),
    ...accountScope(uid, tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: 7,
    bindingVersionV2: 1,
  };
}

function lifecycle(uid, generation, tenant = null, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...accountScope(uid, tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: 7,
    lifecycleStateV2: 'active',
    reauthAfterSecV2: now - 120,
    ...patch,
  };
}

function membership(uid, generation, tenant = null, patch = {}) {
  return {
    authIncarnationSchemaVersionV2: 2,
    ...accountScope(uid, tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: 7,
    membershipStatusV2: 'active',
    associationId: fixture.associationId,
    capabilities: ['association.read', 'association.manage'],
    ...patch,
  };
}

function eligibility(uid, generation, tenant = null) {
  return {
    recipientEligibilitySchemaVersionV2: 2,
    ...accountScope(uid, tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: 7,
    evidenceIdV2: `eligibility:${uid}`,
    authIdentityStateV2: 'present',
    recoveryChannelStateV2: 'verified',
    checkedAtSecV2: now - 60,
    expiresAtSecV2: now + 240,
  };
}

function control(owners, tenant = null) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    ...associationScope(tenant),
    controlVersionV2: 1,
    operationalStateV2: 'operating',
    recoverableOwnersV2: owners,
    pendingTransferIntentIdV2: null,
    activeCustodyCaseIdV2: null,
    custodyPolicyIdV2: null,
  };
}

function providerAuth(uid, generation, tenant = null, time = now) {
  const firebase = tenant === null
    ? {sign_in_provider: 'custom'}
    : {sign_in_provider: 'custom', tenant};
  return {
    uid,
    token: {
      aud: fixture.projectId,
      sub: uid,
      firebase,
      authIncarnationSchemaVersionV2: 2,
      authProjectIdV2: fixture.projectId,
      authTenantIdV2: tenant,
      authUidV2: uid,
      accountGenerationV2: generation,
      accountLifecycleEpochV2: 7,
      auth_time: time - 10,
    },
  };
}

function attempt(uid, time = now) {
  return {
    sessionAttemptIdV2: `${uid}-${time}`,
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: {},
  };
}

function departureRequest(uid, expectedControlVersionV2, choice = 'ordinary', patch = {}) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    associationId: fixture.associationId,
    departureOperationIdV2: `delete-${uid}-${expectedControlVersionV2}`,
    expectedControlVersionV2,
    custodyChoiceV2: choice,
    transferIntentIdV2: null,
    custodyCaseIdV2: choice === 'suspendToCustody' ? `case-${uid}` : null,
    ...patch,
  };
}

class EmulatorTransactionRepository {
  constructor(db) {
    this.db = db;
  }

  async read(pathValue) {
    const snapshot = await getDoc(doc(this.db, pathValue));
    return snapshot.exists() ? snapshot.data() : null;
  }

  async runTransaction(operation) {
    return runTransaction(this.db, async (firestoreTransaction) => {
      let writeStarted = false;
      const transaction = {
        read: async (pathValue) => {
          if (writeStarted) throw new Error('AD03 test adapter read after write');
          const snapshot = await firestoreTransaction.get(doc(this.db, pathValue));
          return snapshot.exists() ? snapshot.data() : null;
        },
        write: (pathValue, value) => {
          writeStarted = true;
          firestoreTransaction.set(doc(this.db, pathValue), value);
        },
      };
      return operation(transaction);
    });
  }
}

async function seedAccount(db, uid, generation, tenant = null) {
  const scope = accountScope(uid, tenant);
  await setDoc(doc(db, ad02.accountLifecycleAuthorityPathV2(scope)), lifecycle(uid, generation, tenant));
  await setDoc(doc(db, ad02.membershipAuthorityPathV2(scope)), membership(uid, generation, tenant));
  await setDoc(
    doc(db, ad03.recipientEligibilityEvidencePathV2(scope)),
    eligibility(uid, generation, tenant),
  );
}

async function seedScenario(db, owners, tenant = null) {
  await setDoc(
    doc(db, ad03.associationOwnershipControlPathV2(associationScope(tenant))),
    control(owners, tenant),
  );
  await seedAccount(db, 'owner-a', fixture.generations.ownerA, tenant);
  await seedAccount(db, 'owner-b', fixture.generations.ownerB, tenant);
  await seedAccount(db, 'recipient-c', fixture.generations.recipientC, tenant);
}

function serviceInput(repository, uid, generation, time = now) {
  return {
    repository,
    auth: providerAuth(uid, generation, null, time),
    configuredProjectId: fixture.projectId,
    attempt: attempt(uid, time),
    nowSecV2: time,
  };
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: fixture.projectId,
    firestore: {rules},
  });
});

test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all raw AD03 control, intent, case, audit, receipt, policy, and evidence paths are private', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedScenario(context.firestore(), [
      owner('owner-a', fixture.generations.ownerA),
    ]);
  });
  const db = testEnv.authenticatedContext('owner-a', {
    authIncarnationSchemaVersionV2: 2,
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: null,
    authUidV2: 'owner-a',
    accountGenerationV2: fixture.generations.ownerA,
    accountLifecycleEpochV2: 7,
    auth_time: now - 10,
  }).firestore();
  const privatePaths = [
    fixture.paths.rootControl,
    `${fixture.paths.rootControl}/transferIntents/transfer-1`,
    `${fixture.paths.rootControl}/custodyCases/case-1`,
    `${fixture.paths.rootControl}/custodyPolicies/fixture-custody-policy`,
    `${fixture.paths.rootControl}/departureReceipts/delete-owner-a-1`,
    `${fixture.paths.rootControl}/auditEvents/departure-delete-owner-a-1`,
    'recipientEligibilityV2Root/recipient-c',
    fixture.paths.tenantControl,
    fixture.paths.tenantRecipientEvidence,
  ];
  for (const pathValue of privatePaths) {
    await assertFails(getDoc(doc(db, pathValue)));
    await assertFails(setDoc(doc(db, pathValue), {role: 'superAdmin'}));
  }
});

test('real Firestore transactions serialize two owner departures without orphaning operation', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const ownerA = owner('owner-a', fixture.generations.ownerA);
    const ownerB = owner('owner-b', fixture.generations.ownerB);
    await seedScenario(db, [ownerA, ownerB]);
    const repository = new EmulatorTransactionRepository(db);
    const results = await Promise.allSettled([
      ad03.commitCandidateOwnerDepartureV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
        request: departureRequest('owner-a', 1),
        candidateTestCustodyPolicyIdV2: null,
      }),
      ad03.commitCandidateOwnerDepartureV2({
        ...serviceInput(repository, 'owner-b', fixture.generations.ownerB),
        request: departureRequest('owner-b', 1),
        candidateTestCustodyPolicyIdV2: null,
      }),
    ]);
    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');
    assert.equal(fulfilled.length, fixture.raceExpectations.twoOwnersOrdinaryDelete.successfulTransactions);
    assert.equal(rejected.length, fixture.raceExpectations.twoOwnersOrdinaryDelete.staleTransactions);
    assert.equal(rejected[0].reason.codeV2, 'AD03_CONTROL_CONFLICT');

    const snapshot = await getDoc(doc(db, fixture.paths.rootControl));
    const serialized = ad03.parseAssociationOwnershipControlV2(snapshot.data());
    assert.equal(serialized.operationalStateV2, 'operating');
    assert.equal(serialized.recoverableOwnersV2.length, 1);
    const remaining = serialized.recoverableOwnersV2[0];

    const custody = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(
        repository,
        remaining.authUidV2,
        remaining.accountGenerationV2,
        now + 1,
      ),
      request: departureRequest(remaining.authUidV2, 2, 'suspendToCustody'),
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.equal(custody.custodyStateV2, 'custodyRequired');
    assert.equal(custody.personalDeletionMayContinueV2, true);
    const finalSnapshot = await getDoc(doc(db, fixture.paths.rootControl));
    assert.equal(finalSnapshot.data().operationalStateV2, 'custodyRequired');
    assert.deepEqual(finalSnapshot.data().recoverableOwnersV2, []);
  });
});

test('recipient loss before commit cannot falsely complete and explicit custody remains available', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await seedScenario(db, [owner('owner-a', fixture.generations.ownerA)]);
    const repository = new EmulatorTransactionRepository(db);
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: {
        associationOwnershipSchemaVersionV2: 2,
        associationId: fixture.associationId,
        transferIntentIdV2: 'transfer-1',
        recipientAuthUidV2: 'recipient-c',
        expectedControlVersionV2: 1,
      },
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: {
        associationOwnershipSchemaVersionV2: 2,
        associationId: fixture.associationId,
        transferIntentIdV2: 'transfer-1',
        expectedControlVersionV2: 2,
        responseV2: 'accept',
      },
    });
    await setDoc(
      doc(db, ad02.accountLifecycleAuthorityPathV2(accountScope('recipient-c'))),
      lifecycle('recipient-c', fixture.generations.recipientC, null, {
        lifecycleStateV2: 'deleted',
        accountLifecycleEpochV2: 8,
      }),
    );
    await setDoc(
      doc(db, ad02.membershipAuthorityPathV2(accountScope('recipient-c'))),
      membership('recipient-c', fixture.generations.recipientC, null, {
        membershipStatusV2: 'revoked',
        accountLifecycleEpochV2: 8,
      }),
    );
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: {
          associationOwnershipSchemaVersionV2: 2,
          associationId: fixture.associationId,
          transferIntentIdV2: 'transfer-1',
          expectedControlVersionV2: 3,
        },
      }),
      {codeV2: 'AD03_RECIPIENT_INELIGIBLE'},
    );
    const controlAfterFailure = await getDoc(doc(db, fixture.paths.rootControl));
    assert.equal(controlAfterFailure.data().operationalStateV2, 'transferPending');
    assert.equal(controlAfterFailure.data().recoverableOwnersV2.length, 1);

    const custody = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 3),
      request: departureRequest('owner-a', 3, 'suspendToCustody', {
        transferIntentIdV2: 'transfer-1',
        custodyCaseIdV2: 'case-owner-a',
      }),
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.equal(custody.custodyStateV2, 'custodyRequired');
    const intent = await getDoc(doc(
      db,
      ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1'),
    ));
    assert.equal(intent.data().stateV2, 'supersededByCustody');
  });
});
