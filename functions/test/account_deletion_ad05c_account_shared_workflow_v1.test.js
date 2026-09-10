'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const official = require('../lib/domain/official_stats_contract');
const ad05 = require('../lib/account_deletion/ad05_records');
const inventory = require('../lib/account_deletion/ad05_inventory');
const ad02 = require('../lib/domain/account_lifecycle_ad02_v2');
const ad03 = require('../lib/domain/association_ownership_ad03_v2');
const authV2 = require('../lib/domain/auth_incarnation_v2');
const records = require('../lib/account_deletion/ad05_account_shared_workflow_records');
const mechanics = require('../lib/account_deletion/ad05_account_shared_workflow');
const fixture = require(
  '../../contracts/account_deletion/ad05/account_shared_workflow_fixtures_v1.json');

function clone(value) {
  return structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([key, value]) =>
      [key, clone(value)]));
    this.writeCount = 0;
  }
  async read(path) {
    return this.values.has(path) ? clone(this.values.get(path)) : null;
  }
  async runTransaction(operation) {
    const staged = new Map();
    let writing = false;
    const result = await operation({
      read: async (path) => {
        if (writing) throw new Error('read after write');
        return this.values.has(path) ? clone(this.values.get(path)) : null;
      },
      write: (path, value) => {
        writing = true;
        staged.set(path, clone(value));
      },
    });
    for (const [path, value] of staged) {
      this.values.set(path, value);
      this.writeCount++;
    }
    return result;
  }
}

const actions = fixture.actionsV1;
const evidenceStates = {
  firebase_auth_identity: 'exactGenerationAbsent',
  notification_inbox: 'verifiedNotApplicable',
  historical_invites: 'restrictedRetentionVerified',
  authorization_evidence: 'restrictedRetentionVerified',
  official_notices: 'sharedAttributionDetached',
  acknowledgements: 'completedAcknowledgementPreserved',
  event_attribution: 'sharedAttributionDetached',
};
const schemas = {
  user_profile: 'account_profile_field_owned_v1',
  memberships_capabilities: 'account_membership_authority_v1',
  team_assignments: 'account_team_assignment_v1',
  pending_invites: 'account_pending_invite_v1',
  personal_ugc: 'account_personal_ugc_v1',
  firebase_auth_identity: 'firebase_auth_absence_v1',
  notification_inbox: 'notification_inbox_absence_v1',
  historical_invites: 'historical_invite_evidence_v1',
  authorization_evidence: 'authorization_evidence_v1',
  official_notices: 'official_notice_attribution_evidence_v1',
  acknowledgements: 'acknowledgement_preservation_evidence_v1',
  event_attribution: 'event_attribution_evidence_v1',
};

function binding(adapterIdV1, variant = '') {
  return ad05.createCandidateAd05ExecutionBindingV1({
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant-a',
    authUidV2: 'account-uid-alpha',
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 9,
    lifecycleStateV1: 'deleting',
    internalJobId: 'job-ad05c',
    taskEffectIdV1: `effect-${adapterIdV1}${variant}`,
    taskEffectFingerprintV1:
      official.canonicalSha256(`effect-${adapterIdV1}${variant}`),
    adapterIdV1,
    adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: 'account-shared-workflow-v1',
    policyDecisionIdV1: `retention.${adapterIdV1}`,
    policyVersionV1: 'synthetic_policy_v1',
    actionV1: actions[adapterIdV1],
    sourceManifestIdV1: `manifest-${adapterIdV1}`,
    sourceManifestVersionV1: 'inventory-v1',
  });
}

function itemAndManifest(adapterIdV1, classificationV1 = 'applicable') {
  const effectBinding = binding(adapterIdV1);
  const sourceDocumentPathV1 = `candidateAd05cSources/${adapterIdV1}`;
  const associationIdV1 = adapterIdV1 === 'firebase_auth_identity' ||
    adapterIdV1 === 'user_profile' || adapterIdV1 === 'notification_inbox' ?
      null : 'association-a';
  const trusted = {
    schemaVersion: 1,
    adapterIdV1,
    sourceSchemaIdV1: schemas[adapterIdV1],
    sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1,
    sourceRecordVersionV1: 'record-v1',
    provenanceIdV1: `provenance-${adapterIdV1}`,
    associationScopeHashV1: associationIdV1 === null ? null :
      official.canonicalSha256(associationIdV1),
    classificationV1,
  };
  const itemIdV1 = inventory.deterministicAd05ManifestItemIdV1({
    binding: effectBinding,
    record: trusted,
  });
  const itemCore = {
    ...trusted,
    itemIdV1,
    ordinalV1: 0,
    sourceDocumentPathHashV1: official.canonicalSha256(sourceDocumentPathV1),
  };
  const item = ad05.parseCandidateAd05ManifestItemV1({
    ...itemCore,
    itemFingerprintV1: ad05.ad05ManifestItemFingerprintV1(itemCore),
  });
  const manifestCore = {
    schemaVersion: 1,
    manifestIdV1: effectBinding.sourceManifestIdV1,
    manifestVersionV1: effectBinding.sourceManifestVersionV1,
    bindingFingerprintV1: effectBinding.bindingFingerprintV1,
    adapterIdV1,
    inventorySourceIdV1: `inventory-${adapterIdV1}`,
    inventorySourceVersionV1: effectBinding.sourceManifestVersionV1,
    referenceCoverageEvidenceIdV1: `coverage-${adapterIdV1}`,
    completeV1: true,
    sealedV1: true,
    itemCountV1: 1,
    itemsV1: [item],
  };
  const manifest = ad05.parseCandidateAd05SealedManifestV1({
    ...manifestCore,
    manifestFingerprintV1: ad05.ad05ManifestFingerprintV1(manifestCore),
  });
  return {effectBinding, item, manifest, sourceDocumentPathV1, associationIdV1};
}

function fieldRecord(effectBinding, associationIdV1, patch = {}, custodyReceiptV2 = null) {
  const custodyRequired = effectBinding.adapterIdV1 === 'memberships_capabilities' ||
    effectBinding.adapterIdV1 === 'team_assignments';
  const core = {
    schemaVersion: 1,
    adapterIdV1: effectBinding.adapterIdV1,
    authProjectIdV2: effectBinding.authProjectIdV2,
    authTenantIdV2: effectBinding.authTenantIdV2,
    authUidV2: effectBinding.authUidV2,
    authUidUtf16LeBase64UrlV1: effectBinding.authUidUtf16LeBase64UrlV1,
    generationHash: effectBinding.generationHash,
    acceptedLifecycleEpochV2: effectBinding.acceptedLifecycleEpochV2,
    lifecycleStateV1: 'deleting',
    internalJobId: effectBinding.internalJobId,
    associationIdV1,
    sourceDocumentPathHashV1: official.canonicalSha256(
      `candidateAd05cSources/${effectBinding.adapterIdV1}`),
    provenanceIdV1: `provenance-${effectBinding.adapterIdV1}`,
    generationProvenanceVerifiedV1: true,
    liveMixedDocumentV1: false,
    custodyStateV1: custodyRequired ? 'ownerDepartureComplete' : 'notRequired',
    custodyDepartureOperationIdV2: custodyRequired ?
      'departure-operation-1' : null,
    custodyProofFingerprintV1: custodyReceiptV2 === null ? null :
      official.canonicalSha256(custodyReceiptV2),
    accountBindingPresentV1: true,
    grantingAuthorityV1: effectBinding.adapterIdV1 !== 'user_profile' &&
      effectBinding.adapterIdV1 !== 'personal_ugc',
    sharedFactsPreservedV1: true,
    completedOutcomesPreservedV1: true,
    dispositionStateV1: 'active',
    recordVersionV1: 'record-v1',
    ...patch,
  };
  return records.parseCandidateAd05cFieldOwnedRecordV1({
    ...core,
    recordFingerprintV1: records.ad05cFieldOwnedRecordFingerprintV1(core),
  });
}

async function producedCustodyReceipt(effectBinding, associationIdV1) {
  const departingEpochV2 = effectBinding.acceptedLifecycleEpochV2 - 1;
  const accountScope = {
    authProjectIdV2: effectBinding.authProjectIdV2,
    authTenantIdV2: effectBinding.authTenantIdV2,
    authUidV2: effectBinding.authUidV2,
  };
  const associationScope = {
    authProjectIdV2: effectBinding.authProjectIdV2,
    authTenantIdV2: effectBinding.authTenantIdV2,
    associationId: associationIdV1,
  };
  const lifecycle = {
    authIncarnationSchemaVersionV2: 2,
    ...accountScope,
    accountGenerationV2: effectBinding.generationHash,
    accountLifecycleEpochV2: departingEpochV2,
    lifecycleStateV2: 'active',
    reauthAfterSecV2: 10,
  };
  const membership = {
    authIncarnationSchemaVersionV2: 2,
    ...accountScope,
    accountGenerationV2: effectBinding.generationHash,
    accountLifecycleEpochV2: departingEpochV2,
    membershipStatusV2: 'active',
    associationId: associationIdV1,
    capabilities: ['association.read', 'association.manage'],
  };
  const owner = {
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: ad03.recoverableOwnerBindingIdV2({
      ...accountScope,
      accountGenerationV2: effectBinding.generationHash,
      accountLifecycleEpochV2: departingEpochV2,
    }),
    ...accountScope,
    accountGenerationV2: effectBinding.generationHash,
    accountLifecycleEpochV2: departingEpochV2,
    bindingVersionV2: 1,
  };
  const otherOwnerScope = {
    authProjectIdV2: effectBinding.authProjectIdV2,
    authTenantIdV2: effectBinding.authTenantIdV2,
    authUidV2: 'other-owner',
  };
  const otherOwner = {
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: ad03.recoverableOwnerBindingIdV2({
      ...otherOwnerScope,
      accountGenerationV2: 'f'.repeat(64),
      accountLifecycleEpochV2: departingEpochV2,
    }),
    ...otherOwnerScope,
    accountGenerationV2: 'f'.repeat(64),
    accountLifecycleEpochV2: departingEpochV2,
    bindingVersionV2: 1,
  };
  const decision = authV2.evaluateAccountAuthorizationV2({
    sessionAttemptIdV2: `ad05c-custody-${effectBinding.adapterIdV1}`,
    sessionAttemptEpochV2: 1,
    sessionAttemptNonceV2: {},
    expectedScope: accountScope,
    tokenProof: {
      authIncarnationSchemaVersionV2: 2,
      ...accountScope,
      accountGenerationV2: effectBinding.generationHash,
      accountLifecycleEpochV2: departingEpochV2,
      authTimeSec: 20,
    },
    lifecycle,
    membership,
    requiredCapability: 'association.manage',
  });
  assert.equal(decision.authorized, true);
  const repository = new MemoryRepository({
    [ad02.accountLifecycleAuthorityPathV2(accountScope)]: lifecycle,
    [ad02.membershipAuthorityPathV2(accountScope)]: membership,
    [ad03.associationOwnershipControlPathV2(associationScope)]: {
      associationOwnershipSchemaVersionV2: 2,
      ...associationScope,
      controlVersionV2: 1,
      operationalStateV2: 'operating',
      recoverableOwnersV2: [owner, otherOwner],
      pendingTransferIntentIdV2: null,
      activeCustodyCaseIdV2: null,
      custodyPolicyIdV2: null,
    },
  });
  return repository.runTransaction((transaction) =>
    ad03.applyOwnerDepartureInTransactionV2({
      transaction,
      departingAuthority: decision.binding,
      request: {
        associationOwnershipSchemaVersionV2: 2,
        associationId: associationIdV1,
        departureOperationIdV2: 'departure-operation-1',
        expectedControlVersionV2: 1,
        custodyChoiceV2: 'ordinary',
        transferIntentIdV2: null,
        custodyCaseIdV2: null,
      },
      nowSecV2: 30,
      candidateTestCustodyPolicyIdV2: null,
    }));
}

function evidenceRecord(effectBinding, associationIdV1, patch = {}) {
  const core = {
    schemaVersion: 1,
    adapterIdV1: effectBinding.adapterIdV1,
    authProjectIdV2: effectBinding.authProjectIdV2,
    authTenantIdV2: effectBinding.authTenantIdV2,
    authUidV2: effectBinding.authUidV2,
    authUidUtf16LeBase64UrlV1: effectBinding.authUidUtf16LeBase64UrlV1,
    generationHash: effectBinding.generationHash,
    acceptedLifecycleEpochV2: effectBinding.acceptedLifecycleEpochV2,
    lifecycleStateV1: 'deleting',
    internalJobId: effectBinding.internalJobId,
    associationIdV1,
    sourceDocumentPathHashV1: official.canonicalSha256(
      `candidateAd05cSources/${effectBinding.adapterIdV1}`),
    provenanceIdV1: `provenance-${effectBinding.adapterIdV1}`,
    generationProvenanceVerifiedV1: true,
    evidenceStateV1: evidenceStates[effectBinding.adapterIdV1],
    mutationAllowedV1: false,
    grantingAuthorityV1: false,
    sharedFactsPreservedV1: true,
    evidenceIdV1: `evidence-${effectBinding.adapterIdV1}`,
    verifiedAtSecV1: 20,
    recordVersionV1: 'record-v1',
    ...patch,
  };
  return records.parseCandidateAd05cEvidenceRecordV1({
    ...core,
    evidenceFingerprintV1: records.ad05cEvidenceRecordFingerprintV1(core),
  });
}

test('fixture freezes the exact 12-row AD05-C boundary and support split', () => {
  assert.deepEqual(fixture.adapterIdsV1, records.ad05cAdapterIdsV1);
  assert.deepEqual(fixture.transactionalAdapterIdsV1,
    records.ad05cTransactionalAdapterIdsV1);
  assert.deepEqual(fixture.evidenceOnlyAdapterIdsV1,
    records.ad05cEvidenceOnlyAdapterIdsV1);
  assert.equal(fixture.activationAllowed, false);
  assert.equal(fixture.productionExportAllowed, false);
  assert.equal(fixture.persistedAd03ReceiptRequiredV1, true);
  assert.equal(fixture.ad03ReceiptEpochPrecedesAcceptedLifecycleEpochV1, true);
  assert.equal(fixture.canonicalManifestRequiredForEvidenceV1, true);
  assert.equal(fixture.sourcePathAndProvenanceBindingRequiredV1, true);
});

test('all five field-owned effects preserve shared facts and replay exactly once', async () => {
  const expected = {
    user_profile: 'erased',
    memberships_capabilities: 'revoked',
    team_assignments: 'detached',
    pending_invites: 'revoked',
    personal_ugc: 'erased',
  };
  for (const adapterIdV1 of fixture.transactionalAdapterIdsV1) {
    const packet = itemAndManifest(adapterIdV1);
    const custodyRequired = adapterIdV1 === 'memberships_capabilities' ||
      adapterIdV1 === 'team_assignments';
    const custodyReceiptV2 = custodyRequired ?
      await producedCustodyReceipt(packet.effectBinding, packet.associationIdV1) :
      null;
    const source = fieldRecord(packet.effectBinding, packet.associationIdV1, {},
      custodyReceiptV2);
    const entries = {
      [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
      [packet.sourceDocumentPathV1]: source,
    };
    if (custodyReceiptV2 !== null) {
      assert.equal(custodyReceiptV2.accountLifecycleEpochV2 + 1,
        packet.effectBinding.acceptedLifecycleEpochV2);
      entries[ad03.ownerDepartureReceiptPathV2({
        authProjectIdV2: packet.effectBinding.authProjectIdV2,
        authTenantIdV2: packet.effectBinding.authTenantIdV2,
        associationId: packet.associationIdV1,
      }, source.custodyDepartureOperationIdV2)] = custodyReceiptV2;
    }
    const repository = new MemoryRepository(entries);
    const first = await mechanics.applyTestOnlySyntheticCandidateAd05cItemV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      sourceRecordVersionAfterV1: 'record-v2',
      committedAtSecV1: 30,
    });
    assert.equal(first.stateV1, 'committed');
    const after = records.parseCandidateAd05cFieldOwnedRecordV1(
      await repository.read(packet.sourceDocumentPathV1));
    assert.equal(after.dispositionStateV1, expected[adapterIdV1]);
    assert.equal(after.accountBindingPresentV1, false);
    assert.equal(after.grantingAuthorityV1, false);
    assert.equal(after.sharedFactsPreservedV1, true);
    assert.equal(after.completedOutcomesPreservedV1, true);
    const writes = repository.writeCount;
    const replay = await mechanics.applyTestOnlySyntheticCandidateAd05cItemV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      sourceRecordVersionAfterV1: 'record-v2',
      committedAtSecV1: 30,
    });
    assert.equal(replay.stateV1, 'replayed');
    assert.equal(repository.writeCount, writes);
  }
});

test('evidence-only rows and missing inbox never request mutation or grant authority', async () => {
  for (const adapterIdV1 of [
    ...fixture.evidenceOnlyAdapterIdsV1,
    'notification_inbox',
  ]) {
    const packet = itemAndManifest(adapterIdV1,
      adapterIdV1 === 'notification_inbox' ? 'notApplicable' : 'applicable');
    const repository = new MemoryRepository({
      [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
    });
    const result = await mechanics.verifyTestOnlySyntheticCandidateAd05cEvidenceV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: evidenceRecord(packet.effectBinding, packet.associationIdV1),
    });
    assert.equal(result.mutationRequestedV1, false);
    assert.equal(result.grantingAuthorityV1, false);
    assert.equal(result.sharedFactsPreservedV1, true);
  }
});

test('cross-generation and live mixed-document records fail closed', () => {
  const packet = itemAndManifest('user_profile');
  const crossGeneration = fieldRecord(packet.effectBinding,
    packet.associationIdV1, {generationHash: 'c'.repeat(64)});
  assert.throws(() => records.assertCandidateAd05cRecordMatchesBindingV1({
    bindingV1: packet.effectBinding,
    recordV1: crossGeneration,
  }), /AD05_BINDING_CONFLICT/);
  assert.throws(() => fieldRecord(packet.effectBinding,
    packet.associationIdV1, {liveMixedDocumentV1: true}),
  /AD05_INVALID_RECORD/);
});

test('membership and assignment mutation require a persisted bound AD03 receipt', async () => {
  for (const adapterIdV1 of ['memberships_capabilities', 'team_assignments']) {
    const packet = itemAndManifest(adapterIdV1);
    const receipt = await producedCustodyReceipt(packet.effectBinding,
      packet.associationIdV1);
    const source = fieldRecord(packet.effectBinding, packet.associationIdV1, {},
      receipt);
    const repository = new MemoryRepository({
      [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
      [packet.sourceDocumentPathV1]: source,
    });
    await assert.rejects(
      mechanics.applyTestOnlySyntheticCandidateAd05cItemV1({
        repository,
        bindingV1: packet.effectBinding,
        manifestV1: packet.manifest,
        itemV1: packet.item,
        sourceRecordVersionAfterV1: 'record-v2',
        committedAtSecV1: 30,
      }),
      /AD05_BINDING_CONFLICT/,
    );
    assert.equal(repository.writeCount, 0);
  }
});

test('custody receipt must match exact account generation and fingerprint', async () => {
  const packet = itemAndManifest('memberships_capabilities');
  const receipt = await producedCustodyReceipt(packet.effectBinding,
    packet.associationIdV1);
  const source = fieldRecord(packet.effectBinding, packet.associationIdV1, {},
    receipt);
  const wrongReceipt = ad03.parseOwnerDepartureReceiptV2({
    ...receipt,
    accountGenerationV2: 'e'.repeat(64),
  });
  const receiptPath = ad03.ownerDepartureReceiptPathV2({
    authProjectIdV2: packet.effectBinding.authProjectIdV2,
    authTenantIdV2: packet.effectBinding.authTenantIdV2,
    associationId: packet.associationIdV1,
  }, source.custodyDepartureOperationIdV2);
  const repository = new MemoryRepository({
    [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
    [packet.sourceDocumentPathV1]: source,
    [receiptPath]: wrongReceipt,
  });
  await assert.rejects(
    mechanics.applyTestOnlySyntheticCandidateAd05cItemV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      sourceRecordVersionAfterV1: 'record-v2',
      committedAtSecV1: 30,
    }), /AD05_BINDING_CONFLICT/);
  assert.equal(repository.writeCount, 0);
});

test('custody receipt must be from the lifecycle epoch before deletion acceptance', async () => {
  const packet = itemAndManifest('team_assignments');
  const producedReceipt = await producedCustodyReceipt(packet.effectBinding,
    packet.associationIdV1);
  const wrongEpochReceipt = ad03.parseOwnerDepartureReceiptV2({
    ...producedReceipt,
    accountLifecycleEpochV2: packet.effectBinding.acceptedLifecycleEpochV2,
  });
  const source = fieldRecord(packet.effectBinding, packet.associationIdV1, {},
    wrongEpochReceipt);
  const receiptPath = ad03.ownerDepartureReceiptPathV2({
    authProjectIdV2: packet.effectBinding.authProjectIdV2,
    authTenantIdV2: packet.effectBinding.authTenantIdV2,
    associationId: packet.associationIdV1,
  }, source.custodyDepartureOperationIdV2);
  const repository = new MemoryRepository({
    [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
    [packet.sourceDocumentPathV1]: source,
    [receiptPath]: wrongEpochReceipt,
  });
  await assert.rejects(
    mechanics.applyTestOnlySyntheticCandidateAd05cItemV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      sourceRecordVersionAfterV1: 'record-v2',
      committedAtSecV1: 30,
    }), /AD05_BINDING_CONFLICT/);
  assert.equal(repository.writeCount, 0);
});

test('evidence verification binds canonical manifest, full effect, path, and provenance', async () => {
  const packet = itemAndManifest('acknowledgements');
  const repository = new MemoryRepository({
    [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
  });
  const changedEffectBinding = binding('acknowledgements', '-changed');
  await assert.rejects(
    mechanics.verifyTestOnlySyntheticCandidateAd05cEvidenceV1({
      repository,
      bindingV1: changedEffectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: evidenceRecord(packet.effectBinding, packet.associationIdV1),
    }), /AD05_BINDING_CONFLICT/);
  const wrongProvenance = evidenceRecord(packet.effectBinding,
    packet.associationIdV1, {provenanceIdV1: 'different-provenance'});
  await assert.rejects(
    mechanics.verifyTestOnlySyntheticCandidateAd05cEvidenceV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: wrongProvenance,
    }), /AD05_BINDING_CONFLICT/);
});

test('notification inbox cannot be represented as an applicable source', async () => {
  const packet = itemAndManifest('notification_inbox', 'applicable');
  const repository = new MemoryRepository({
    [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
  });
  await assert.rejects(
    mechanics.verifyTestOnlySyntheticCandidateAd05cEvidenceV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: evidenceRecord(packet.effectBinding, packet.associationIdV1),
    }), /AD05_BINDING_CONFLICT/);
});

test('normative posture stays blocked and support never claims Auth mutation', () => {
  assert.deepEqual(mechanics.createDormantCandidateAd05cPlanV1(), {
    stateV1: 'blocked',
    evidenceCodeV1: 'authoritative_policy_not_approved',
    writesAllowedV1: false,
  });
  assert.equal(mechanics.candidateAd05cMechanicalSupportV1(
    'firebase_auth_identity').stateV1, 'evidenceOnly');
  assert.equal(mechanics.candidateAd05cMechanicalSupportV1(
    'notification_inbox').stateV1, 'notApplicableOnly');
});
