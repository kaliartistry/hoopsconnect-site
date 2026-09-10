'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const official = require('../lib/domain/official_stats_contract');
const lifecycle = require('../lib/domain/account_lifecycle_ad02_v2');
const ad04 = require('../lib/account_deletion/ad04_records');
const ad05 = require('../lib/account_deletion/ad05_records');
const inventory = require('../lib/account_deletion/ad05_inventory');
const records = require('../lib/account_deletion/ad05_fcm_preferences_records');
const mechanics = require('../lib/account_deletion/ad05_fcm_preferences');

function clone(value) {
  return structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([path, value]) =>
      [path, clone(value)]));
    this.readCount = 0;
    this.writeCount = 0;
  }
  async read(path) {
    this.readCount++;
    return this.values.has(path) ? clone(this.values.get(path)) : null;
  }
  async runTransaction(operation) {
    let writing = false;
    return operation({
      read: async (path) => {
        if (writing) throw new Error('read after write');
        this.readCount++;
        return this.values.has(path) ? clone(this.values.get(path)) : null;
      },
      write: () => {
        writing = true;
        this.writeCount++;
        throw new Error('AD05-E must never write');
      },
    });
  }
}

function binding(variant = '', actionV1 = 'erase') {
  return ad05.createCandidateAd05ExecutionBindingV1({
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant-a',
    authUidV2: 'account-uid-alpha',
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 12,
    lifecycleStateV1: 'deleting',
    internalJobId: `job-ad05e${variant}`,
    taskEffectIdV1: `effect-device-fcm${variant}`,
    taskEffectFingerprintV1: official.canonicalSha256(
      `effect-device-fcm${variant}`),
    adapterIdV1: 'device_fcm_preferences',
    adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: 'fcm-preferences-evidence-v1',
    policyDecisionIdV1: 'retention.device_fcm_preferences',
    policyVersionV1: 'synthetic_policy_v1',
    actionV1,
    sourceManifestIdV1: `manifest-device-fcm${variant}`,
    sourceManifestVersionV1: 'inventory-v1',
  });
}

function packet(variant = '', classificationV1 = 'applicable') {
  const effectBinding = binding(variant,
    classificationV1 === 'notApplicable' ? 'notApplicable' : 'erase');
  const sourceDocumentPathV1 =
    `candidateAd05eFcmEvidenceV1/source${variant || '-primary'}`;
  const associationScopeHashV1 = official.canonicalSha256('association-a');
  const trusted = {
    schemaVersion: 1,
    adapterIdV1: 'device_fcm_preferences',
    sourceSchemaIdV1:
      'account_deletion_ad05e_fcm_preferences_evidence_v1',
    sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1,
    sourceRecordVersionV1: 'evidence-record-v1',
    provenanceIdV1: 'provenance-device-fcm',
    associationScopeHashV1,
    classificationV1,
  };
  const itemIdV1 = inventory.deterministicAd05ManifestItemIdV1({
    binding: effectBinding, record: trusted,
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
    adapterIdV1: 'device_fcm_preferences',
    inventorySourceIdV1: 'inventory-device-fcm',
    inventorySourceVersionV1: effectBinding.sourceManifestVersionV1,
    referenceCoverageEvidenceIdV1: 'coverage-device-fcm',
    completeV1: true,
    sealedV1: true,
    itemCountV1: 1,
    itemsV1: [item],
  };
  const manifest = ad05.parseCandidateAd05SealedManifestV1({
    ...manifestCore,
    manifestFingerprintV1: ad05.ad05ManifestFingerprintV1(manifestCore),
  });
  return {effectBinding, item, manifest, sourceDocumentPathV1,
    associationScopeHashV1};
}

function reference(currentPacket, referenceClassV1, index, patch = {}) {
  const sourcePath = `registered-synthetic/${referenceClassV1}/${index}`;
  const defaults = {
    installationSlotV2: null,
    preferenceNameV2: null,
    preferenceValueV2: null,
    tokenFingerprintV1: null,
    deliveryStateV2: null,
    barrierStateV2: null,
    payloadHashV2: null,
    intendedRecipientSetHashV2: null,
  };
  if (referenceClassV1 === 'registeredInstallation') {
    defaults.installationSlotV2 = `slot${index}`;
    defaults.tokenFingerprintV1 = official.canonicalSha256(`token-${index}`);
  } else if (referenceClassV1 === 'notificationPreference') {
    defaults.preferenceNameV2 = 'ackReminders';
    defaults.preferenceValueV2 = true;
  } else if (referenceClassV1 === 'legacyProfileSurface') {
    defaults.tokenFingerprintV1 = official.canonicalSha256(`legacy-${index}`);
  } else if (referenceClassV1 === 'deliveryAttempt') {
    defaults.deliveryStateV2 = 'submitted';
    defaults.payloadHashV2 = official.canonicalSha256(`payload-${index}`);
    defaults.intendedRecipientSetHashV2 =
      official.canonicalSha256(`recipients-${index}`);
  } else if (referenceClassV1 === 'deletionBarrier') {
    defaults.barrierStateV2 = 'held';
  }
  const core = {
    schemaVersion: 1,
    referenceIdV1: '',
    referenceClassV1,
    sourcePathHashV1: official.canonicalSha256(sourcePath),
    sourceSchemaIdV1: `ad05e_${referenceClassV1}_v1`,
    sourceSchemaVersionV1: 'schema_v1',
    sourceRecordVersionV1: `record-v${index + 1}`,
    provenanceIdV1: `registered_synthetic_${referenceClassV1}_v1`,
    authProjectIdV2: currentPacket.effectBinding.authProjectIdV2,
    authTenantIdV2: currentPacket.effectBinding.authTenantIdV2,
    authUidUtf16LeBase64UrlV1:
      currentPacket.effectBinding.authUidUtf16LeBase64UrlV1,
    accountGenerationOwnerV1: currentPacket.effectBinding.generationHash,
    sourceLifecycleEpochV2: currentPacket.effectBinding.acceptedLifecycleEpochV2,
    associationScopeHashV1: currentPacket.associationScopeHashV1,
    ownerRelationV1: 'deletingAccount',
    ...defaults,
    dispositionV1: ['deliveryAttempt', 'deletionBarrier'].includes(
      referenceClassV1) ? 'unresolvedExternalDependency' :
      referenceClassV1 === 'queuedRecipient' ?
        'plannedRemoveAccountReference' : 'plannedRemoveAccountReference',
    ...patch,
  };
  core.referenceIdV1 = `reference_${official.canonicalSha256({
    referenceClassV1: core.referenceClassV1,
    sourcePathHashV1: core.sourcePathHashV1,
    sourceRecordVersionV1: core.sourceRecordVersionV1,
    ownerRelationV1: core.ownerRelationV1,
  })}`;
  return {...core,
    referenceFingerprintV1: records.ad05eReferenceFingerprintV1(core)};
}

function evidence(currentPacket, options = {}) {
  const referencesV1 = options.referencesV1 === undefined ? [
    reference(currentPacket, 'registeredInstallation', 0),
    reference(currentPacket, 'notificationPreference', 0),
    reference(currentPacket, 'legacyProfileSurface', 0),
    reference(currentPacket, 'queuedRecipient', 0),
    reference(currentPacket, 'deliveryAttempt', 0),
    reference(currentPacket, 'deletionBarrier', 0),
    reference(currentPacket, 'retryReplaySource', 0),
  ] : options.referencesV1;
  const coverageV1 = records.ad05eReferenceClassesV1.map(
    (referenceClassV1) => {
      const count = referencesV1.filter((entry) =>
        entry.referenceClassV1 === referenceClassV1).length;
      const core = {
        schemaVersion: 1,
        referenceClassV1,
        coverageStateV1: count === 0 ?
          'positiveAbsenceVerified' : 'completeEnumerated',
        enumeratedCountV1: count,
        coverageSourcePathHashV1: official.canonicalSha256(
          `registered-synthetic/coverage/${referenceClassV1}`),
        coverageSourceVersionV1: 'coverage-v1',
        coverageSourceHashV1: official.canonicalSha256(
          `coverage-source-${referenceClassV1}-${count}`),
      };
      return {...core,
        coverageFingerprintV1: records.ad05eCoverageFingerprintV1(core)};
    });
  const unresolved = referencesV1.some((entry) =>
    entry.dispositionV1 === 'unresolvedExternalDependency');
  const core = {
    schemaVersion: 1,
    adapterIdV1: 'device_fcm_preferences',
    bindingV1: currentPacket.effectBinding,
    sourceDocumentPathHashV1:
      official.canonicalSha256(currentPacket.sourceDocumentPathV1),
    sourceSchemaIdV1:
      'account_deletion_ad05e_fcm_preferences_evidence_v1',
    sourceSchemaVersionV1: 'schema_v1',
    provenanceIdV1: 'provenance-device-fcm',
    producerIdV1: 'synthetic_notification_inventory_v1',
    producerVersionV1: 1,
    inventoryCompleteV1: true,
    referenceCoverageCompleteV1: true,
    highWaterMarkV1: 'registered-synthetic-high-water-v1',
    associationScopeHashV1: currentPacket.associationScopeHashV1,
    referencesV1,
    coverageV1,
    candidateOutcomeV1: referencesV1.length === 0 ?
      'positiveNotApplicableEvidenceVerified' : unresolved ?
        'syntheticInventoryVerifiedWithUnresolvedDispatch' :
        'syntheticInventoryVerified',
    observedAtSecV1: 1770000000,
    recordVersionV1: 'evidence-record-v1',
    ...(options.patch || {}),
  };
  return {...core,
    evidenceFingerprintV1: records.ad05eEvidenceFingerprintV1(core)};
}

function jobBinding(currentPacket) {
  return {
    schemaVersion: 1,
    internalJobId: currentPacket.effectBinding.internalJobId,
    authProjectIdV2: currentPacket.effectBinding.authProjectIdV2,
    authTenantIdV2: currentPacket.effectBinding.authTenantIdV2,
    authUidV2: currentPacket.effectBinding.authUidV2,
    generationHash: currentPacket.effectBinding.generationHash,
    authCreatedAtIsoV1: '2026-09-01T00:00:00.000Z',
    acceptedLifecycleEpochV2:
      currentPacket.effectBinding.acceptedLifecycleEpochV2,
    acceptedSemanticFingerprint: official.canonicalSha256('accepted'),
    winningOperationId: 'operation-ad05e',
    policyVersion: currentPacket.effectBinding.policyVersionV1,
    impactVersion: 'impact-v1',
    custodyChoice: 'ordinary',
    associationId: 'association-a',
    custodyOutcomeV1: 'ordinary',
    custodyRequiresAttentionV1: false,
    acceptedAtSecV1: 1769900000,
    statusAliasCountV1: 1,
  };
}

function lifecycleAuthority(currentPacket) {
  return {
    authIncarnationSchemaVersionV2: 2,
    authProjectIdV2: currentPacket.effectBinding.authProjectIdV2,
    authTenantIdV2: currentPacket.effectBinding.authTenantIdV2,
    authUidV2: currentPacket.effectBinding.authUidV2,
    accountGenerationV2: currentPacket.effectBinding.generationHash,
    accountLifecycleEpochV2:
      currentPacket.effectBinding.acceptedLifecycleEpochV2,
    lifecycleStateV2: 'deleting',
    reauthAfterSecV2: 1769800000,
  };
}

function seeded(currentPacket, currentEvidence) {
  const entries = {
    [ad05.ad05ManifestPathV1(currentPacket.effectBinding)]:
      currentPacket.manifest,
    [currentPacket.sourceDocumentPathV1]: currentEvidence,
    [ad04.deletionJobBindingPathV1(
      currentPacket.effectBinding.internalJobId)]: jobBinding(currentPacket),
    [lifecycle.accountLifecycleAuthorityPathV2(
      currentPacket.effectBinding)]: lifecycleAuthority(currentPacket),
  };
  entries[mechanics.ad05eSourceAuthorityPathV1({
    bindingV1: currentPacket.effectBinding,
    itemV1: currentPacket.item,
  })] = mechanics.buildTestOnlyCandidateAd05eSourceAuthorityV1({
    bindingV1: currentPacket.effectBinding,
    itemV1: currentPacket.item,
    evidenceV1: currentEvidence,
  });
  for (const record of mechanics.buildTestOnlyCandidateAd05eChainRecordsV1({
    bindingV1: currentPacket.effectBinding,
    manifestV1: currentPacket.manifest,
    itemV1: currentPacket.item,
    evidenceV1: currentEvidence,
  })) {
    entries[mechanics.ad05eChainRecordPathV1({
      bindingV1: currentPacket.effectBinding,
      itemV1: currentPacket.item,
      recordTypeV1: record.recordTypeV1,
    })] = record;
  }
  entries[mechanics.ad05eReceiptSealPathV1({
    bindingV1: currentPacket.effectBinding,
    itemV1: currentPacket.item,
  })] = mechanics.buildTestOnlyCandidateAd05eReceiptSealV1({
    bindingV1: currentPacket.effectBinding,
    manifestV1: currentPacket.manifest,
    itemV1: currentPacket.item,
    evidenceV1: currentEvidence,
  });
  return new MemoryRepository(entries);
}

async function verify(currentPacket, currentEvidence, repository) {
  return mechanics.verifyTestOnlySyntheticCandidateAd05eEvidenceV1({
    repository,
    bindingV1: currentPacket.effectBinding,
    manifestV1: currentPacket.manifest,
    itemV1: currentPacket.item,
    evidenceV1: currentEvidence,
  });
}

test('complete persisted chain verifies with nine reads and zero writes', async () => {
  const currentPacket = packet();
  const currentEvidence = evidence(currentPacket);
  const repository = seeded(currentPacket, currentEvidence);
  const receipt = await verify(currentPacket, currentEvidence, repository);
  assert.equal(receipt.syntheticEvidenceVerifiedV1, true);
  assert.equal(receipt.adapterResultEligibleV1, false);
  assert.equal(receipt.providerRevocationVerifiedV1, false);
  assert.equal(receipt.deliveryRecallVerifiedV1, false);
  assert.equal(receipt.liveSuppressionVerifiedV1, false);
  assert.equal(receipt.uncertainDispatchBarrierResolvedV1, false);
  assert.equal(repository.readCount, 9);
  assert.equal(repository.writeCount, 0);
});

test('positive notApplicable requires all seven source classes absent', async () => {
  const currentPacket = packet('-empty', 'notApplicable');
  const currentEvidence = evidence(currentPacket, {referencesV1: []});
  const receipt = await verify(currentPacket, currentEvidence,
    seeded(currentPacket, currentEvidence));
  assert.equal(receipt.candidateOutcomeV1,
    'positiveNotApplicableEvidenceVerified');
  const forged = clone(currentEvidence);
  forged.coverageV1.pop();
  delete forged.evidenceFingerprintV1;
  forged.evidenceFingerprintV1 = records.ad05eEvidenceFingerprintV1(forged);
  assert.throws(() => records.parseCandidateAd05eEvidenceV1(forged),
    /AD05_INCOMPLETE_INVENTORY/);
});

test('uncertain attempts and held barriers cannot claim removal or success', () => {
  const currentPacket = packet();
  for (const referenceClassV1 of ['deliveryAttempt', 'deletionBarrier']) {
    const bad = reference(currentPacket, referenceClassV1, 0, {
      dispositionV1: 'plannedRemoveAccountReference',
    });
    assert.throws(() => records.parseCandidateAd05eEvidenceV1(
      evidence(currentPacket, {referencesV1: [bad]})),
    /AD05_BINDING_CONFLICT/);
  }
  const plan = mechanics.createDormantCandidateAd05ePlanV1();
  assert.deepEqual(plan, {
    stateV1: 'blocked',
    evidenceCodeV1:
      'notification_provider_and_dispatch_reconciliation_not_approved',
    writesAllowedV1: false,
    providerCallsAllowedV1: false,
    uncertainAttemptRetryAllowedV1: false,
    barrierReleaseAllowedV1: false,
  });
});

test('later generations and shared token fingerprints are preserved', () => {
  const currentPacket = packet();
  const sharedToken = official.canonicalSha256('shared-token');
  const deleting = reference(currentPacket, 'registeredInstallation', 0, {
    tokenFingerprintV1: sharedToken,
  });
  const later = reference(currentPacket, 'registeredInstallation', 1, {
    tokenFingerprintV1: sharedToken,
    accountGenerationOwnerV1: 'b'.repeat(64),
    sourceLifecycleEpochV2: 13,
    ownerRelationV1: 'laterGeneration',
    dispositionV1: 'preserveSharedHistory',
  });
  const parsed = records.parseCandidateAd05eEvidenceV1(
    evidence(currentPacket, {referencesV1: [deleting, later]}));
  assert.equal(parsed.referencesV1[0].dispositionV1,
    'plannedRemoveAccountReference');
  assert.equal(parsed.referencesV1[1].dispositionV1,
    'preserveSharedHistory');
});

test('missing preferences, raw tokens, duplicate IDs and invented absence fail', () => {
  const currentPacket = packet();
  const preference = reference(currentPacket, 'notificationPreference', 0);
  const missing = {...preference, preferenceNameV2: null,
    preferenceValueV2: null};
  delete missing.referenceFingerprintV1;
  missing.referenceFingerprintV1 =
    records.ad05eReferenceFingerprintV1(missing);
  assert.throws(() => records.parseCandidateAd05eEvidenceV1(
    evidence(currentPacket, {referencesV1: [missing]})),
  /AD05_BINDING_CONFLICT/);

  const raw = clone(evidence(currentPacket));
  raw.referencesV1[0].rawToken = 'must-never-be-persisted';
  assert.throws(() => records.parseCandidateAd05eEvidenceV1(raw),
    /AD05_INVALID_RECORD/);

  const duplicate = reference(currentPacket, 'registeredInstallation', 0);
  assert.throws(() => records.parseCandidateAd05eEvidenceV1(
    evidence(currentPacket, {referencesV1: [duplicate, duplicate]})),
  /AD05_INCOMPLETE_INVENTORY/);

  const invented = clone(evidence(currentPacket));
  invented.coverageV1[0].coverageStateV1 = 'positiveAbsenceVerified';
  assert.throws(() => records.parseCandidateAd05eEvidenceV1(invented),
    /AD05_BINDING_CONFLICT|AD05_INCOMPLETE_INVENTORY/);
});

test('cross-scope and stale-source substitutions fail after re-signing', () => {
  const currentPacket = packet();
  for (const patch of [
    {authProjectIdV2: 'other-project'},
    {authTenantIdV2: null},
    {authUidUtf16LeBase64UrlV1: 'b3RoZXI'},
    {accountGenerationOwnerV1: 'b'.repeat(64)},
    {sourceLifecycleEpochV2: 13},
    {associationScopeHashV1: official.canonicalSha256('other-association')},
  ]) {
    const changed = reference(currentPacket, 'registeredInstallation', 0,
      patch);
    assert.throws(() => records.parseCandidateAd05eEvidenceV1(
      evidence(currentPacket, {referencesV1: [changed]})),
    /AD05_BINDING_CONFLICT/);
  }
});

test('persisted AD04 job and lifecycle authority are mandatory and exact', async () => {
  const currentPacket = packet();
  const currentEvidence = evidence(currentPacket);
  for (const target of ['job', 'lifecycle']) {
    const repository = seeded(currentPacket, currentEvidence);
    const path = target === 'job' ? ad04.deletionJobBindingPathV1(
      currentPacket.effectBinding.internalJobId) :
      lifecycle.accountLifecycleAuthorityPathV2(currentPacket.effectBinding);
    const changed = clone(repository.values.get(path));
    if (target === 'job') changed.acceptedLifecycleEpochV2 = 11;
    else changed.accountLifecycleEpochV2 = 11;
    repository.values.set(path, changed);
    await assert.rejects(() => verify(currentPacket, currentEvidence, repository),
      /AD05_BINDING_CONFLICT/);
  }
});

test('changed observations and sources cannot reuse a sealed receipt', async () => {
  const currentPacket = packet();
  const original = evidence(currentPacket);
  const repository = seeded(currentPacket, original);
  const changed = clone(original);
  changed.observedAtSecV1++;
  delete changed.evidenceFingerprintV1;
  changed.evidenceFingerprintV1 = records.ad05eEvidenceFingerprintV1(changed);
  repository.values.set(currentPacket.sourceDocumentPathV1, changed);
  await assert.rejects(() => verify(currentPacket, changed, repository),
    /AD05_BINDING_CONFLICT/);

  const missingAuthority = seeded(currentPacket, original);
  missingAuthority.values.delete(mechanics.ad05eSourceAuthorityPathV1({
    bindingV1: currentPacket.effectBinding,
    itemV1: currentPacket.item,
  }));
  await assert.rejects(() => verify(currentPacket, original, missingAuthority),
    /AD05_INCOMPLETE_INVENTORY/);
});

test('only the one dormant adapter is recognized', () => {
  assert.deepEqual(mechanics.candidateAd05eMechanicalSupportV1(
    'device_fcm_preferences'), {
    stateV1: 'candidateEvidenceOnly', adapterResultEligibleV1: false,
  });
  assert.throws(() => mechanics.candidateAd05eMechanicalSupportV1(
    'device_local_state'), /AD05_UNSUPPORTED/);
});
