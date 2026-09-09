'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const ad02 = require('../lib/domain/account_lifecycle_ad02_v2');
const ad03 = require('../lib/domain/association_ownership_ad03_v2');
const authV2 = require('../lib/domain/auth_incarnation_v2');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname,
  '../../contracts/account_deletion/ad03/ownership_fixtures_v2.json',
), 'utf8'));

const now = 1700000200;

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([key, value]) => [key, clone(value)]));
  }

  async read(pathValue) {
    return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
  }

  async runTransaction(operation) {
    const staged = new Map();
    const transaction = {
      read: async (pathValue) => this.values.has(pathValue)
        ? clone(this.values.get(pathValue))
        : null,
      write: (pathValue, value) => staged.set(pathValue, clone(value)),
    };
    const result = await operation(transaction);
    for (const [key, value] of staged) this.values.set(key, value);
    return result;
  }
}

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

function owner(uid, generation, tenant = null, epoch = 7) {
  return {
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: ad03.recoverableOwnerBindingIdV2({
      ...accountScope(uid, tenant),
      accountGenerationV2: generation,
      accountLifecycleEpochV2: epoch,
    }),
    ...accountScope(uid, tenant),
    accountGenerationV2: generation,
    accountLifecycleEpochV2: epoch,
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

function eligibility(uid, generation, tenant = null, patch = {}) {
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
    ...patch,
  };
}

function providerAuth(uid, generation, tenant = null, authTimeSec = now - 10) {
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
      auth_time: authTimeSec,
    },
  };
}

function control(owners, patch = {}, tenant = null) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    ...associationScope(tenant),
    controlVersionV2: 1,
    operationalStateV2: 'operating',
    recoverableOwnersV2: owners,
    pendingTransferIntentIdV2: null,
    activeCustodyCaseIdV2: null,
    custodyPolicyIdV2: null,
    ...patch,
  };
}

function seedAccount(entries, uid, generation, tenant = null, options = {}) {
  const scope = accountScope(uid, tenant);
  entries[ad02.accountLifecycleAuthorityPathV2(scope)] =
    lifecycle(uid, generation, tenant, options.lifecycle);
  entries[ad02.membershipAuthorityPathV2(scope)] =
    membership(uid, generation, tenant, options.membership);
  if (options.withEligibility !== false) {
    entries[ad03.recipientEligibilityEvidencePathV2(scope)] =
      eligibility(uid, generation, tenant, options.eligibility);
  }
}

function repositoryWith({owners, tenant = null, policy = null} = {}) {
  const ownerA = owner('owner-a', fixture.generations.ownerA, tenant);
  const ownerB = owner('owner-b', fixture.generations.ownerB, tenant);
  const recipientC = owner('recipient-c', fixture.generations.recipientC, tenant);
  const entries = {
    [ad03.associationOwnershipControlPathV2(associationScope(tenant))]:
      control(owners ?? [ownerA], {}, tenant),
  };
  seedAccount(entries, 'owner-a', fixture.generations.ownerA, tenant);
  seedAccount(entries, 'owner-b', fixture.generations.ownerB, tenant);
  seedAccount(entries, 'recipient-c', fixture.generations.recipientC, tenant);
  if (policy !== null) {
    entries[ad03.serviceCustodyPolicyPathV2(
      associationScope(tenant),
      policy.custodyPolicyIdV2,
    )] = {...policy, authTenantIdV2: tenant};
  }
  return {repository: new MemoryRepository(entries), ownerA, ownerB, recipientC};
}

function attempt(id) {
  return {
    sessionAttemptIdV2: id,
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: {},
  };
}

function serviceInput(repository, uid, generation, time = now, tenant = null) {
  return {
    repository,
    auth: providerAuth(uid, generation, tenant, time - 10),
    configuredProjectId: fixture.projectId,
    attempt: attempt(`${uid}-${time}`),
    nowSecV2: time,
  };
}

function validatedAuthority(uid, generation, tenant = null) {
  const auth = providerAuth(uid, generation, tenant);
  const currentAttempt = attempt(`validated-${uid}`);
  const decision = authV2.evaluateAccountAuthorizationV2({
    ...currentAttempt,
    expectedScope: accountScope(uid, tenant),
    tokenProof: ad02.extractProviderTokenProofV2(auth, fixture.projectId),
    lifecycle: lifecycle(uid, generation, tenant),
    membership: membership(uid, generation, tenant),
    requiredCapability: 'association.manage',
  });
  assert.equal(decision.authorized, true);
  return decision.binding;
}

function prepareRequest(expectedControlVersionV2 = 1) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    associationId: fixture.associationId,
    transferIntentIdV2: 'transfer-1',
    recipientAuthUidV2: 'recipient-c',
    expectedControlVersionV2,
  };
}

function responseRequest(responseV2, expectedControlVersionV2 = 2) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    associationId: fixture.associationId,
    transferIntentIdV2: 'transfer-1',
    expectedControlVersionV2,
    responseV2,
  };
}

function commitRequest(expectedControlVersionV2 = 3) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    associationId: fixture.associationId,
    transferIntentIdV2: 'transfer-1',
    expectedControlVersionV2,
  };
}

function departureRequest({
  operation = 'departure-1',
  expected = 1,
  choice = 'ordinary',
  transferIntent = null,
  custodyCase = null,
} = {}) {
  return {
    associationOwnershipSchemaVersionV2: 2,
    associationId: fixture.associationId,
    departureOperationIdV2: operation,
    expectedControlVersionV2: expected,
    custodyChoiceV2: choice,
    transferIntentIdV2: transferIntent,
    custodyCaseIdV2: custodyCase,
  };
}

function recoveryCommand(patch = {}) {
  return {
    serviceCustodyCommandSchemaVersionV2: 2,
    authProjectIdV2: fixture.projectId,
    authTenantIdV2: null,
    associationId: fixture.associationId,
    custodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
    custodyPolicyVersionV2: fixture.testCustodyPolicy.custodyPolicyVersionV2,
    custodyPolicyFingerprintV2: fixture.testCustodyPolicyFingerprintV2,
    custodyCaseIdV2: 'case-test-custody',
    commandIdV2: 'recovery-command-1',
    operatorRefV2: fixture.testCustodyPolicy.namedOperatorRefV2,
    caseOwnerRefV2: fixture.testCustodyPolicy.namedCaseOwnerRefV2,
    reviewEvidenceRefV2: 'fixture:review-passed',
    issuedAtSecV2: now,
    expiresAtSecV2: now + 300,
    actionV2: 'completeRecovery',
    ...patch,
  };
}

async function stored(repository, pathValue) {
  return repository.read(pathValue);
}

test('AD03 remains dormant with separate exact root and tenant lanes', () => {
  assert.equal(ad03.ASSOCIATION_OWNERSHIP_AD03_ACTIVATION_ALLOWED_V2, false);
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionCustodyConfigured, false);
  assert.equal(fixture.productionOwnerBootstrapImplemented, false);
  assert.equal(fixture.firebaseIamMutationAllowed, false);
  assert.equal(ad03.ASSOCIATION_OWNERSHIP_FRESH_AUTH_MAX_AGE_SEC_V2, 300);
  assert.equal(
    ad03.serviceCustodyPolicyFingerprintV2(fixture.testCustodyPolicy),
    fixture.testCustodyPolicyFingerprintV2,
  );
  assert.equal(
    ad03.associationOwnershipControlPathV2(associationScope()),
    fixture.paths.rootControl,
  );
  assert.equal(
    ad03.associationOwnershipControlPathV2(associationScope('league-tenant')),
    fixture.paths.tenantControl,
  );
  assert.equal(
    ad03.recipientEligibilityEvidencePathV2(accountScope('recipient-c')),
    fixture.paths.rootRecipientEvidence,
  );
  assert.equal(
    ad03.recipientEligibilityEvidencePathV2(accountScope('recipient-c', 'league-tenant')),
    fixture.paths.tenantRecipientEvidence,
  );
  assert.throws(
    () => ad03.associationOwnershipControlPathV2({...associationScope(), associationId: '../jba'}),
    {codeV2: 'AD03_INVALID_REQUEST'},
  );
});

test('strict schemas reject UID-only, legacy-role, unknown-field, and forged owner records', () => {
  assert.deepEqual(
    ad03.parseRecoverableOwnerBindingV2(fixture.ownerBindings.ownerA),
    fixture.ownerBindings.ownerA,
  );
  for (const invalid of [
    {uid: 'owner-a', role: 'superAdmin'},
    {...fixture.ownerBindings.ownerA, role: 'superAdmin'},
    {...fixture.ownerBindings.ownerA, accountGenerationV2: fixture.generations.ownerB},
    {...fixture.ownerBindings.ownerA, authTenantIdV2: 'league-tenant'},
    {...fixture.ownerBindings.ownerA, accountLifecycleEpochV2: 8},
  ]) {
    assert.throws(
      () => ad03.parseRecoverableOwnerBindingV2(invalid),
      {codeV2: 'AD03_CONTROL_INVALID'},
    );
  }
  assert.throws(
    () => ad03.parseAssociationOwnershipControlV2(control([])),
    {codeV2: 'AD03_CONTROL_INVALID'},
  );
  assert.throws(
    () => ad03.parseAssociationOwnershipControlV2(control([
      fixture.ownerBindings.ownerA,
      {...fixture.ownerBindings.ownerA},
    ])),
    {codeV2: 'AD03_CONTROL_INVALID'},
  );
  assert.throws(
    () => ad03.parseAssociationOwnershipControlV2({
      ...control([fixture.ownerBindings.ownerA]),
      futureField: true,
    }),
    {codeV2: 'AD03_CONTROL_INVALID'},
  );
  assert.throws(
    () => ad03.parseAssociationOwnershipControlV2(control(
      Array.from({length: 17}, (_, index) =>
        owner(`bounded-owner-${index}`, 'd'.repeat(64))),
    )),
    {codeV2: 'AD03_CONTROL_INVALID'},
  );
});

test('maximum-length operation IDs remain committable through hashed audit IDs', async () => {
  const transferIntentIdV2 = `t${'x'.repeat(127)}`;
  const {repository} = repositoryWith();
  await ad03.prepareCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: {...prepareRequest(), transferIntentIdV2},
  });
  await ad03.respondToCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: {...responseRequest('accept'), transferIntentIdV2},
  });
  const committed = await ad03.commitCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
    request: {...commitRequest(), transferIntentIdV2},
  });
  assert.equal(committed.stateV2, 'committed');
  const auditId = ad03.associationOwnershipAuditEventIdV2(
    'transferCommit',
    transferIntentIdV2,
  );
  assert.equal(auditId.length, 66);
  assert.equal(
    ad03.associationOwnershipAuditEventIdV2('ownerDeparture', `d${'y'.repeat(127)}`).length,
    66,
  );
  assert.equal(
    ad03.associationOwnershipAuditEventIdV2('custodyRecovery', `r${'z'.repeat(127)}`).length,
    66,
  );
  assert.notEqual(await stored(
    repository,
    ad03.associationOwnershipAuditPathV2(associationScope(), auditId),
  ), null);
  assert.throws(
    () => ad03.associationOwnershipAuditEventIdV2('transferCommit', `t${'x'.repeat(128)}`),
    {codeV2: 'AD03_INVALID_REQUEST'},
  );
});

test('prepare, fresh recipient acceptance, and commit transfer exact ownership atomically', async () => {
  const {repository, ownerA, recipientC} = repositoryWith();
  const prepared = await ad03.prepareCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: prepareRequest(),
  });
  assert.equal(prepared.stateV2, 'pendingRecipientAcceptance');
  assert.deepEqual(prepared.preparedByOwnerV2, ownerA);
  assert.deepEqual(prepared.recipientOwnerV2, recipientC);
  assert.equal(prepared.controlVersionAtPrepareV2, 2);

  const accepted = await ad03.respondToCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: responseRequest('accept'),
  });
  assert.equal(accepted.stateV2, 'recipientAccepted');
  assert.equal(accepted.controlVersionAtResponseV2, 3);
  assert.equal(accepted.recipientAcceptedAuthTimeSecV2, now - 9);

  const committed = await ad03.commitCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
    request: commitRequest(),
  });
  assert.equal(committed.stateV2, 'committed');
  assert.equal(committed.controlVersionAtCommitV2, 4);
  const finalControl = await stored(
    repository,
    ad03.associationOwnershipControlPathV2(associationScope()),
  );
  assert.equal(finalControl.operationalStateV2, 'operating');
  assert.deepEqual(finalControl.recoverableOwnersV2, [recipientC]);
  assert.equal(finalControl.pendingTransferIntentIdV2, null);
  const audit = await stored(
    repository,
    ad03.associationOwnershipAuditPathV2(
      associationScope(),
      ad03.associationOwnershipAuditEventIdV2('transferCommit', 'transfer-1'),
    ),
  );
  assert.deepEqual(Object.keys(audit).sort(), [
    'associationId',
    'associationOwnershipAuditSchemaVersionV2',
    'authProjectIdV2',
    'authTenantIdV2',
    'controlVersionAfterV2',
    'controlVersionBeforeV2',
    'counterpartyBindingRefV2',
    'custodyCaseIdV2',
    'custodyPolicyIdV2',
    'eventIdV2',
    'eventTypeV2',
    'ownerBindingRefV2',
    'recordedAtSecV2',
    'transferIntentIdV2',
  ].sort());
  const serializedAudit = JSON.stringify(audit);
  for (const forbidden of ['owner-a', 'recipient-c', '@', 'displayName', 'email', 'role']) {
    assert.doesNotMatch(serializedAudit, new RegExp(forbidden));
  }
});

test('transfer replay is idempotent and changed payload under one intent conflicts', async () => {
  const {repository} = repositoryWith();
  const input = {
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: prepareRequest(),
  };
  const first = await ad03.prepareCandidateOwnershipTransferV2(input);
  const replay = await ad03.prepareCandidateOwnershipTransferV2(input);
  assert.deepEqual(replay, first);
  await assert.rejects(
    ad03.prepareCandidateOwnershipTransferV2({
      ...input,
      request: {...prepareRequest(), recipientAuthUidV2: 'owner-b'},
    }),
    {codeV2: 'AD03_TRANSFER_CONFLICT'},
  );
});

test('recipient freshness is <=300 seconds and strict AD02 freshness still applies', async () => {
  const {repository} = repositoryWith();
  await ad03.prepareCandidateOwnershipTransferV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: prepareRequest(),
  });
  await assert.rejects(
    ad03.respondToCandidateOwnershipTransferV2({
      repository,
      auth: providerAuth('recipient-c', fixture.generations.recipientC, null, now - 301),
      configuredProjectId: fixture.projectId,
      attempt: attempt('stale-recipient'),
      nowSecV2: now,
      request: responseRequest('accept'),
    }),
    {codeV2: 'AD03_FRESH_AUTH_REQUIRED'},
  );
  await assert.rejects(
    ad03.respondToCandidateOwnershipTransferV2({
      repository,
      auth: providerAuth('recipient-c', fixture.generations.recipientC, null, now - 120),
      configuredProjectId: fixture.projectId,
      attempt: attempt('equal-reauth-cutoff'),
      nowSecV2: now,
      request: responseRequest('accept'),
    }),
    {codeV2: 'AD03_AUTHORITY_DENIED'},
  );
});

test('decline and loss of recipient eligibility never become a completed transfer', async () => {
  {
    const {repository, ownerA} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    const declined = await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('decline'),
    });
    assert.equal(declined.stateV2, 'declined');
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: commitRequest(),
      }),
      {codeV2: 'AD03_TRANSFER_NOT_READY'},
    );
    const current = await stored(repository, ad03.associationOwnershipControlPathV2(associationScope()));
    assert.deepEqual(current.recoverableOwnersV2, [ownerA]);
    const custodyRequest = departureRequest({
      operation: 'declined-transfer-custody',
      expected: 3,
      choice: 'suspendToCustody',
      transferIntent: 'transfer-1',
      custodyCase: 'case-after-decline',
    });
    const custody = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
      request: custodyRequest,
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.equal(custody.transferIntentIdV2, 'transfer-1');
    assert.equal(custody.outcomeV2,
      'policyBlockedButDeletionMustReceiveOperationalResolution');
    const replay = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
      request: custodyRequest,
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.deepEqual(replay, custody);
  }

  {
    const {repository} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    repository.values.set(
      ad02.accountLifecycleAuthorityPathV2(accountScope('recipient-c')),
      lifecycle('recipient-c', fixture.generations.recipientC, null, {
        lifecycleStateV2: 'deleted',
        accountLifecycleEpochV2: 8,
      }),
    );
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: commitRequest(),
      }),
      {codeV2: 'AD03_RECIPIENT_INELIGIBLE'},
    );
    const custody = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 3),
      request: departureRequest({
        operation: 'fallback-custody',
        expected: 3,
        choice: 'suspendToCustody',
        transferIntent: 'transfer-1',
        custodyCase: 'case-fallback',
      }),
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.equal(custody.custodyStateV2, 'custodyRequired');
    assert.equal(custody.personalDeletionMayContinueV2, true);
  }

  {
    const {repository, ownerA} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    const accepted = await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    repository.values.set(
      ad02.accountLifecycleAuthorityPathV2(accountScope('recipient-c')),
      lifecycle('recipient-c', fixture.generations.recipientC, null, {
        reauthAfterSecV2: accepted.recipientAcceptedAuthTimeSecV2,
      }),
    );
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: commitRequest(),
      }),
      {codeV2: 'AD03_RECIPIENT_INELIGIBLE'},
    );
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.deepEqual(current.recoverableOwnersV2, [ownerA]);
  }
});

test('transfer commits reject cross-association records and path-ID redirection', async () => {
  {
    const {repository, ownerA} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    const intentPath = ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1');
    const intent = await stored(repository, intentPath);
    repository.values.set(intentPath, {...intent, associationId: 'other-association'});
    repository.values.set(
      ad02.membershipAuthorityPathV2(accountScope('recipient-c')),
      membership('recipient-c', fixture.generations.recipientC, null, {
        associationId: 'other-association',
      }),
    );
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: commitRequest(),
      }),
      {codeV2: 'AD03_TRANSFER_CONFLICT'},
    );
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.deepEqual(current.recoverableOwnersV2, [ownerA]);
  }

  {
    const {repository, ownerA} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    const intentPath = ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1');
    const controlPath = ad03.associationOwnershipControlPathV2(associationScope());
    const intent = await stored(repository, intentPath);
    const current = await stored(repository, controlPath);
    repository.values.set(intentPath, {...intent, transferIntentIdV2: 'redirected-intent'});
    repository.values.set(controlPath, {
      ...current,
      pendingTransferIntentIdV2: 'redirected-intent',
    });
    await assert.rejects(
      ad03.commitCandidateOwnerDepartureV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: departureRequest({
          expected: 3,
          choice: 'transferThenDelete',
          transferIntent: 'transfer-1',
        }),
        candidateTestCustodyPolicyIdV2: null,
      }),
      {codeV2: 'AD03_TRANSFER_CONFLICT'},
    );
    const unchanged = await stored(repository, controlPath);
    assert.deepEqual(unchanged.recoverableOwnersV2, [ownerA]);
  }

  {
    const {repository, ownerA} = repositoryWith();
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    const intentPath = ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1');
    const intent = await stored(repository, intentPath);
    repository.values.set(intentPath, {...intent, controlVersionAtResponseV2: 2});
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 2),
        request: commitRequest(),
      }),
      {codeV2: 'AD03_TRANSFER_NOT_READY'},
    );
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.deepEqual(current.recoverableOwnersV2, [ownerA]);
  }
});

test('ordinary owner departure never silently orphans an association', async () => {
  const ownerA = owner('owner-a', fixture.generations.ownerA);
  const ownerB = owner('owner-b', fixture.generations.ownerB);
  const {repository} = repositoryWith({owners: [ownerA, ownerB]});
  const receipt = await ad03.commitCandidateOwnerDepartureV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: departureRequest(),
    candidateTestCustodyPolicyIdV2: null,
  });
  assert.equal(receipt.outcomeV2, 'ordinary');
  assert.equal(receipt.personalDeletionMayContinueV2, true);
  const current = await stored(repository, ad03.associationOwnershipControlPathV2(associationScope()));
  assert.deepEqual(current.recoverableOwnersV2, [ownerB]);
  await assert.rejects(
    ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-b', fixture.generations.ownerB, now + 1),
      request: departureRequest({operation: 'departure-2', expected: 2}),
      candidateTestCustodyPolicyIdV2: null,
    }),
    {codeV2: 'AD03_CONTROL_CONFLICT'},
  );
  const unchanged = await stored(repository, ad03.associationOwnershipControlPathV2(associationScope()));
  assert.deepEqual(unchanged.recoverableOwnersV2, [ownerB]);
});

test('AD04 departure seam revalidates current AD02 authority in its transaction', async () => {
  for (const mutate of [
    (repository) => {
      repository.values.delete(ad02.accountLifecycleAuthorityPathV2(accountScope('owner-a')));
      repository.values.delete(ad02.membershipAuthorityPathV2(accountScope('owner-a')));
    },
    (repository) => repository.values.set(
      ad02.accountLifecycleAuthorityPathV2(accountScope('owner-a')),
      lifecycle('owner-a', fixture.generations.ownerA, null, {
        lifecycleStateV2: 'deleting',
        accountLifecycleEpochV2: 8,
      }),
    ),
    (repository) => repository.values.set(
      ad02.membershipAuthorityPathV2(accountScope('owner-a')),
      membership('owner-a', fixture.generations.ownerA, null, {
        membershipStatusV2: 'revoked',
        capabilities: [],
      }),
    ),
  ]) {
    const ownerA = owner('owner-a', fixture.generations.ownerA);
    const ownerB = owner('owner-b', fixture.generations.ownerB);
    const {repository} = repositoryWith({owners: [ownerA, ownerB]});
    const staleAuthority = validatedAuthority('owner-a', fixture.generations.ownerA);
    mutate(repository);
    await assert.rejects(
      repository.runTransaction((transaction) =>
        ad03.applyOwnerDepartureInTransactionV2({
          transaction,
          departingAuthority: staleAuthority,
          request: departureRequest(),
          nowSecV2: now,
          candidateTestCustodyPolicyIdV2: null,
        })),
      {codeV2: 'AD03_AUTHORITY_DENIED'},
    );
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.deepEqual(current.recoverableOwnersV2, [ownerA, ownerB]);
    assert.equal(await stored(
      repository,
      ad03.ownerDepartureReceiptPathV2(associationScope(), 'departure-1'),
    ), null);
  }
});

test('owner-set changes cancel pending consent without stranding departure', async () => {
  {
    const ownerA = owner('owner-a', fixture.generations.ownerA);
    const ownerB = owner('owner-b', fixture.generations.ownerB);
    const {repository} = repositoryWith({owners: [ownerA, ownerB]});
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    const receipt = await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 1),
      request: departureRequest({operation: 'pending-owner-departure', expected: 2}),
      candidateTestCustodyPolicyIdV2: null,
    });
    assert.equal(receipt.outcomeV2, 'ordinary');
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.equal(current.operationalStateV2, 'operating');
    assert.deepEqual(current.recoverableOwnersV2, [ownerB]);
    assert.equal(current.pendingTransferIntentIdV2, null);
    const cancelled = await stored(
      repository,
      ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1'),
    );
    assert.equal(cancelled.stateV2, 'cancelledByOwnerDeparture');
  }

  {
    const ownerA = owner('owner-a', fixture.generations.ownerA);
    const ownerB = owner('owner-b', fixture.generations.ownerB);
    const {repository} = repositoryWith({owners: [ownerA, ownerB]});
    await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: prepareRequest(),
    });
    await ad03.respondToCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: responseRequest('accept'),
    });
    await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-b', fixture.generations.ownerB, now + 2),
      request: departureRequest({operation: 'co-owner-departure', expected: 3}),
      candidateTestCustodyPolicyIdV2: null,
    });
    const current = await stored(
      repository,
      ad03.associationOwnershipControlPathV2(associationScope()),
    );
    assert.equal(current.operationalStateV2, 'operating');
    assert.deepEqual(current.recoverableOwnersV2, [ownerA]);
    const cancelled = await stored(
      repository,
      ad03.ownershipTransferIntentPathV2(associationScope(), 'transfer-1'),
    );
    assert.equal(cancelled.stateV2, 'cancelledByOwnerDeparture');
    await assert.rejects(
      ad03.commitCandidateOwnershipTransferV2({
        ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 3),
        request: commitRequest(4),
      }),
      {codeV2: 'AD03_TRANSFER_NOT_READY'},
    );
    const renewed = await ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA, now + 3),
      request: {
        ...prepareRequest(4),
        transferIntentIdV2: 'transfer-renewed',
      },
    });
    assert.equal(renewed.stateV2, 'pendingRecipientAcceptance');
  }
});

test('missing named custody suspends fail closed and tracks CUSTODY_CONFLICT without blocking deletion', async () => {
  const {repository} = repositoryWith();
  const receipt = await ad03.commitCandidateOwnerDepartureV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: departureRequest({
      choice: 'suspendToCustody',
      custodyCase: 'case-unassigned',
    }),
    candidateTestCustodyPolicyIdV2: null,
  });
  assert.equal(
    receipt.outcomeV2,
    fixture.raceExpectations.lastOwnerMissingCustody.custodyOutcomeV2,
  );
  assert.equal(receipt.custodyStateV2, 'custodyRequired');
  assert.equal(receipt.requiresOperationalAttentionV2, true);
  assert.equal(receipt.personalDeletionMayContinueV2, true);
  const current = await stored(repository, ad03.associationOwnershipControlPathV2(associationScope()));
  assert.equal(current.operationalStateV2, 'custodyRequired');
  assert.deepEqual(current.recoverableOwnersV2, []);
  const caseRecord = await stored(
    repository,
    ad03.custodyRecoveryCasePathV2(associationScope(), 'case-unassigned'),
  );
  assert.equal(caseRecord.stateV2, 'operatorUnassigned');
  assert.equal(caseRecord.safeErrorCodeV2, 'CUSTODY_CONFLICT');
  assert.equal(caseRecord.namedOperatorRefV2, null);
  assert.equal(caseRecord.custodyPolicyIdV2, null);
  assert.equal(ad03.productionCustodyActivationReadyV2({
    policy: fixture.unresolvedProductionCustodyPolicy,
    gateG3Passed: true,
  }), false);
});

test('test-only named custody supports explicit successor acceptance and audited recovery', async () => {
  const {repository, recipientC} = repositoryWith({policy: fixture.testCustodyPolicy});
  const departure = await ad03.commitCandidateOwnerDepartureV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: departureRequest({
      choice: 'suspendToCustody',
      custodyCase: 'case-test-custody',
    }),
    candidateTestCustodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
  });
  assert.equal(departure.custodyStateV2, 'suspendedToCustody');
  assert.equal(departure.requiresOperationalAttentionV2, false);

  const accepted = await ad03.acceptCandidateCustodySuccessorV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: {
      associationOwnershipSchemaVersionV2: 2,
      associationId: fixture.associationId,
      custodyCaseIdV2: 'case-test-custody',
      successorAcceptanceIdV2: 'successor-acceptance-1',
      expectedControlVersionV2: 2,
    },
  });
  assert.equal(accepted.stateV2, 'recoveryReview');
  assert.deepEqual(accepted.successorOwnerV2, recipientC);
  assert.equal(accepted.successorAcceptanceIdV2, 'successor-acceptance-1');
  assert.equal(accepted.successorAcceptedAuthTimeSecV2, now - 9);
  const acceptedReplay = await ad03.acceptCandidateCustodySuccessorV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: {
      associationOwnershipSchemaVersionV2: 2,
      associationId: fixture.associationId,
      custodyCaseIdV2: 'case-test-custody',
      successorAcceptanceIdV2: 'successor-acceptance-1',
      expectedControlVersionV2: 2,
    },
  });
  assert.deepEqual(acceptedReplay, accepted);
  await assert.rejects(
    ad03.acceptCandidateCustodySuccessorV2({
      ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
      request: {
        associationOwnershipSchemaVersionV2: 2,
        associationId: fixture.associationId,
        custodyCaseIdV2: 'case-test-custody',
        successorAcceptanceIdV2: 'changed-acceptance',
        expectedControlVersionV2: 3,
      },
    }),
    {codeV2: 'AD03_RECIPIENT_RESPONSE_CONFLICT'},
  );

  const command = recoveryCommand();
  await assert.rejects(
    ad03.completeCandidateCustodyRecoveryV2({
      repository,
      verifiedTestCommand: {command, verificationNonceV2: {}},
      nowSecV2: now + 2,
    }),
    {codeV2: 'AD03_SERVICE_AUTHORITY_DENIED'},
  );
  assert.throws(
    () => ad03.verifyTestServiceCustodyCommandV2({
      policy: fixture.testCustodyPolicy,
      command: recoveryCommand({operatorRefV2: 'fixture:wrong-operator'}),
      nowSecV2: now + 2,
    }),
    {codeV2: 'AD03_SERVICE_AUTHORITY_DENIED'},
  );
  assert.throws(
    () => ad03.verifyTestServiceCustodyCommandV2({
      policy: fixture.testCustodyPolicy,
      command: recoveryCommand({custodyPolicyVersionV2: 2}),
      nowSecV2: now + 2,
    }),
    {codeV2: 'AD03_SERVICE_AUTHORITY_DENIED'},
  );
  const verified = ad03.verifyTestServiceCustodyCommandV2({
    policy: fixture.testCustodyPolicy,
    command,
    nowSecV2: now + 2,
  });
  const resolved = await ad03.completeCandidateCustodyRecoveryV2({
    repository,
    verifiedTestCommand: verified,
    nowSecV2: now + 2,
  });
  assert.equal(resolved.stateV2, 'resolved');
  assert.equal(resolved.reviewEvidenceRefV2, 'fixture:review-passed');
  const resolvedReplay = await ad03.completeCandidateCustodyRecoveryV2({
    repository,
    verifiedTestCommand: verified,
    nowSecV2: now + 2,
  });
  assert.deepEqual(resolvedReplay, resolved);
  const finalControl = await stored(repository, ad03.associationOwnershipControlPathV2(associationScope()));
  assert.equal(finalControl.operationalStateV2, 'operating');
  assert.deepEqual(finalControl.recoverableOwnersV2, [recipientC]);
});

test('recovery rejects stale policy configuration under the same policy ID', async () => {
  const {repository} = repositoryWith({policy: fixture.testCustodyPolicy});
  await ad03.commitCandidateOwnerDepartureV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: departureRequest({
      choice: 'suspendToCustody',
      custodyCase: 'case-test-custody',
    }),
    candidateTestCustodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
  });
  await ad03.acceptCandidateCustodySuccessorV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: {
      associationOwnershipSchemaVersionV2: 2,
      associationId: fixture.associationId,
      custodyCaseIdV2: 'case-test-custody',
      successorAcceptanceIdV2: 'successor-acceptance-stale-policy',
      expectedControlVersionV2: 2,
    },
  });
  const verified = ad03.verifyTestServiceCustodyCommandV2({
    policy: fixture.testCustodyPolicy,
    command: recoveryCommand({commandIdV2: 'stale-policy-command'}),
    nowSecV2: now + 2,
  });
  const policyPath = ad03.serviceCustodyPolicyPathV2(
    associationScope(),
    fixture.testCustodyPolicy.custodyPolicyIdV2,
  );
  repository.values.set(policyPath, {
    ...fixture.testCustodyPolicy,
    recoveryDeadlineSecV2: fixture.testCustodyPolicy.recoveryDeadlineSecV2 + 1,
  });
  await assert.rejects(
    ad03.completeCandidateCustodyRecoveryV2({
      repository,
      verifiedTestCommand: verified,
      nowSecV2: now + 2,
    }),
    {codeV2: 'AD03_CUSTODY_RECOVERY_NOT_READY'},
  );
});

test('recovery rejects a successor whose reauth fence advanced after acceptance', async () => {
  const {repository} = repositoryWith({policy: fixture.testCustodyPolicy});
  await ad03.commitCandidateOwnerDepartureV2({
    ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
    request: departureRequest({
      choice: 'suspendToCustody',
      custodyCase: 'case-test-custody',
    }),
    candidateTestCustodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
  });
  const accepted = await ad03.acceptCandidateCustodySuccessorV2({
    ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
    request: {
      associationOwnershipSchemaVersionV2: 2,
      associationId: fixture.associationId,
      custodyCaseIdV2: 'case-test-custody',
      successorAcceptanceIdV2: 'successor-acceptance-reauth-race',
      expectedControlVersionV2: 2,
    },
  });
  repository.values.set(
    ad02.accountLifecycleAuthorityPathV2(accountScope('recipient-c')),
    lifecycle('recipient-c', fixture.generations.recipientC, null, {
      reauthAfterSecV2: accepted.successorAcceptedAuthTimeSecV2,
    }),
  );
  const command = recoveryCommand({commandIdV2: 'reauth-race-command'});
  const verified = ad03.verifyTestServiceCustodyCommandV2({
    policy: fixture.testCustodyPolicy,
    command,
    nowSecV2: now + 2,
  });
  await assert.rejects(
    ad03.completeCandidateCustodyRecoveryV2({
      repository,
      verifiedTestCommand: verified,
      nowSecV2: now + 2,
    }),
    {codeV2: 'AD03_RECIPIENT_INELIGIBLE'},
  );
});

test('custody case and receipt replays reject cross-scope or redirected records', async () => {
  {
    const {repository} = repositoryWith({policy: fixture.testCustodyPolicy});
    await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: departureRequest({
        choice: 'suspendToCustody',
        custodyCase: 'case-test-custody',
      }),
      candidateTestCustodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
    });
    const casePath = ad03.custodyRecoveryCasePathV2(
      associationScope(),
      'case-test-custody',
    );
    const caseRecord = await stored(repository, casePath);
    repository.values.set(casePath, {...caseRecord, associationId: 'other-association'});
    await assert.rejects(
      ad03.acceptCandidateCustodySuccessorV2({
        ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
        request: {
          associationOwnershipSchemaVersionV2: 2,
          associationId: fixture.associationId,
          custodyCaseIdV2: 'case-test-custody',
          successorAcceptanceIdV2: 'case-scope-rejected',
          expectedControlVersionV2: 2,
        },
      }),
      {codeV2: 'AD03_CUSTODY_RECOVERY_NOT_READY'},
    );
  }

  {
    const {repository} = repositoryWith({policy: fixture.testCustodyPolicy});
    await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request: departureRequest({
        choice: 'suspendToCustody',
        custodyCase: 'case-test-custody',
      }),
      candidateTestCustodyPolicyIdV2: fixture.testCustodyPolicy.custodyPolicyIdV2,
    });
    const casePath = ad03.custodyRecoveryCasePathV2(
      associationScope(),
      'case-test-custody',
    );
    const caseRecord = await stored(repository, casePath);
    repository.values.set(casePath, {...caseRecord, currentControlVersionV2: 3});
    await assert.rejects(
      ad03.acceptCandidateCustodySuccessorV2({
        ...serviceInput(repository, 'recipient-c', fixture.generations.recipientC, now + 1),
        request: {
          associationOwnershipSchemaVersionV2: 2,
          associationId: fixture.associationId,
          custodyCaseIdV2: 'case-test-custody',
          successorAcceptanceIdV2: 'case-version-rejected',
          expectedControlVersionV2: 2,
        },
      }),
      {codeV2: 'AD03_CUSTODY_RECOVERY_NOT_READY'},
    );
  }

  {
    const ownerA = owner('owner-a', fixture.generations.ownerA);
    const ownerB = owner('owner-b', fixture.generations.ownerB);
    const {repository} = repositoryWith({owners: [ownerA, ownerB]});
    const request = departureRequest({operation: 'receipt-linkage'});
    await ad03.commitCandidateOwnerDepartureV2({
      ...serviceInput(repository, 'owner-a', fixture.generations.ownerA),
      request,
      candidateTestCustodyPolicyIdV2: null,
    });
    const receiptPath = ad03.ownerDepartureReceiptPathV2(
      associationScope(),
      request.departureOperationIdV2,
    );
    const receipt = await stored(repository, receiptPath);
    repository.values.set(receiptPath, {...receipt, departureOperationIdV2: 'redirected'});
    await assert.rejects(
      repository.runTransaction((transaction) =>
        ad03.applyOwnerDepartureInTransactionV2({
          transaction,
          departingAuthority: validatedAuthority('owner-a', fixture.generations.ownerA),
          request,
          nowSecV2: now,
          candidateTestCustodyPolicyIdV2: null,
        })),
      {codeV2: 'AD03_TRANSFER_CONFLICT'},
    );
  }
});

test('custody barrier keeps transfer operational but suspends ordinary and defers privacy to AD06', () => {
  const ownerA = fixture.ownerBindings.ownerA;
  const operating = control([ownerA]);
  const transferPending = control([ownerA], {
    operationalStateV2: 'transferPending',
    pendingTransferIntentIdV2: 'transfer-1',
  });
  const custodyRequired = control([], {
    operationalStateV2: 'custodyRequired',
    activeCustodyCaseIdV2: 'case-unassigned',
  });
  for (const current of [operating, transferPending]) {
    assert.equal(ad03.associationCustodyBarrierRequirementV2({
      control: current,
      operationClassV2: 'ordinaryStatAcceptance',
    }), 'ordinaryAuthorityMayProceed');
    for (const [operationClassV2, expected] of [
      ['deletionPrivacyCleanup', 'serverDeletionAuthorityRequired'],
      ['trustedRecoveryWorker', 'trustedRecoveryAuthorityRequired'],
      ['auditedServiceCustodyRecovery', 'auditedServiceCustodyAuthorityRequired'],
      ['historicalPresentation', 'ad06CurrentPrivacyDecisionRequired'],
    ]) {
      assert.equal(ad03.associationCustodyBarrierRequirementV2({
        control: current,
        operationClassV2,
      }), expected);
    }
  }
  for (const operationClassV2 of fixture.custodyBarrier.blockedOrdinaryOperations) {
    assert.equal(ad03.associationCustodyBarrierRequirementV2({
      control: custodyRequired,
      operationClassV2,
    }), 'associationOperationSuspended');
  }
  assert.equal(ad03.associationCustodyBarrierRequirementV2({
    control: custodyRequired,
    operationClassV2: 'deletionPrivacyCleanup',
  }), 'serverDeletionAuthorityRequired');
  assert.equal(ad03.associationCustodyBarrierRequirementV2({
    control: custodyRequired,
    operationClassV2: 'historicalPresentation',
  }), 'ad06CurrentPrivacyDecisionRequired');
});

test('root and tenant controls with the same UID and association never cross-read', async () => {
  const root = repositoryWith();
  const tenant = repositoryWith({tenant: 'league-tenant'});
  await assert.rejects(
    ad03.prepareCandidateOwnershipTransferV2({
      ...serviceInput(root.repository, 'owner-a', fixture.generations.ownerA, now, 'league-tenant'),
      request: prepareRequest(),
    }),
    {codeV2: 'AD03_AUTHORITY_DENIED'},
  );
  const prepared = await ad03.prepareCandidateOwnershipTransferV2({
    ...serviceInput(
      tenant.repository,
      'owner-a',
      fixture.generations.ownerA,
      now,
      'league-tenant',
    ),
    request: prepareRequest(),
  });
  assert.equal(prepared.authTenantIdV2, 'league-tenant');
});
