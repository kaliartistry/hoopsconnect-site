'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const official = require('../lib/domain/official_stats_contract');
const ad05 = require('../lib/account_deletion/ad05_records');
const inventory = require('../lib/account_deletion/ad05_inventory');
const records = require('../lib/account_deletion/ad05_storage_media_records');
const mechanics = require('../lib/account_deletion/ad05_storage_media');

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
    let writing = false;
    return operation({
      read: async (path) => {
        if (writing) throw new Error('read after write');
        return this.values.has(path) ? clone(this.values.get(path)) : null;
      },
      write: () => {
        writing = true;
        this.writeCount++;
        throw new Error('AD05-D must never write');
      },
    });
  }
}

function binding(adapterIdV1, variant = '', actionOverride = null) {
  return ad05.createCandidateAd05ExecutionBindingV1({
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant-a',
    authUidV2: 'account-uid-alpha',
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 12,
    lifecycleStateV1: 'deleting',
    internalJobId: 'job-ad05d',
    taskEffectIdV1: `effect-${adapterIdV1}${variant}`,
    taskEffectFingerprintV1: official.canonicalSha256(
      `effect-${adapterIdV1}${variant}`),
    adapterIdV1,
    adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: 'storage-media-evidence-v1',
    policyDecisionIdV1: `retention.${adapterIdV1}`,
    policyVersionV1: 'synthetic_policy_v1',
    actionV1: actionOverride ||
      (adapterIdV1 === 'personal_storage_media' ? 'erase' : 'detach'),
    sourceManifestIdV1: `manifest-${adapterIdV1}${variant}`,
    sourceManifestVersionV1: 'inventory-v1',
  });
}

function manifestPacket(adapterIdV1, variant = '', classificationV1 = 'applicable') {
  const effectBinding = binding(adapterIdV1, variant,
    classificationV1 === 'notApplicable' ? 'notApplicable' : null);
  const sourceDocumentPathV1 =
    `candidateAd05dMediaEvidenceV1/${adapterIdV1}${variant || '-primary'}`;
  const associationScopeHashV1 = adapterIdV1 === 'personal_storage_media' ?
    null : official.canonicalSha256('association-a');
  const trusted = {
    schemaVersion: 1,
    adapterIdV1,
    sourceSchemaIdV1: 'account_deletion_ad05d_media_evidence_v1',
    sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1,
    sourceRecordVersionV1: 'evidence-record-v1',
    provenanceIdV1: `provenance-${adapterIdV1}`,
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
  return {effectBinding, item, manifest, sourceDocumentPathV1,
    associationScopeHashV1};
}

function mediaObject(adapterIdV1, index, patch = {}) {
  const personal = adapterIdV1 === 'personal_storage_media';
  const uidBytes = 'YQBjAGMAbwB1AG4AdAAtAHUAaQBkAC0AYQBsAHAAaABhAA';
  const name = `candidate-ad05d/tenant-a/${uidBytes}/file-${index}.png`;
  const encodedName = records.ad05dObjectNameUtf8Base64UrlV1(name);
  const generation = String(1000 + index);
  const core = {
    schemaVersion: 1,
    objectIdV1: `object_${official.canonicalSha256({
      bucketNameV1: 'demo-hoopsconnect.appspot.com',
      objectNameUtf8Base64UrlV1: encodedName,
      objectGenerationV1: generation,
    })}`,
    objectNameUtf8Base64UrlV1: encodedName,
    objectNameHashV1: official.canonicalSha256(name),
    objectGenerationV1: generation,
    objectMetagenerationV1: '1',
    contentHashV1: official.canonicalSha256(`content-${index}`),
    metadataHashV1: official.canonicalSha256(`metadata-${index}`),
    derivativeOfObjectIdV1: null,
    transformIdV1: null,
    transformVersionV1: null,
    versionStateV1: personal ? 'absent' : 'live',
    tokenStateV1: 'absent',
    tokenSetFingerprintV1: null,
    restoreTokenFingerprintV1: null,
    ...patch,
  };
  return {...core, recordFingerprintV1: records.ad05dObjectFingerprintV1(core)};
}

function evidence(packet, options = {}) {
  const personal = packet.effectBinding.adapterIdV1 === 'personal_storage_media';
  const objectsV1 = options.objectsV1 || [
    mediaObject(packet.effectBinding.adapterIdV1, 0),
    mediaObject(packet.effectBinding.adapterIdV1, 1),
  ];
  const ownershipCore = {
    schemaVersion: 1,
    classificationV1: personal ? 'personalExclusive' : 'associationShared',
    associationScopeHashV1: packet.associationScopeHashV1,
    ownershipSourcePathHashV1: official.canonicalSha256(
      `registered-synthetic/${packet.effectBinding.adapterIdV1}/ownership`),
    ownershipSourceVersionV1: 'ownership-v1',
    ownershipSourceHashV1: official.canonicalSha256('ownership-record'),
    accountGenerationOwnerV1: packet.effectBinding.generationHash,
    accountReferencePresentV1: false,
    subjectSetHashV1: official.canonicalSha256('subjects'),
    protectedFactsHashV1: official.canonicalSha256('protected-facts'),
    unrelatedReferencesHashV1: official.canonicalSha256('unrelated-references'),
    rightsDecisionPathHashV1: official.canonicalSha256(
      `registered-synthetic/${packet.effectBinding.adapterIdV1}/rights`),
    rightsDecisionHashV1: official.canonicalSha256({
      registeredRightsPath:
        `registered-synthetic/${packet.effectBinding.adapterIdV1}/rights`,
      classificationV1: personal ? 'personalExclusive' : 'associationShared',
      associationScopeHashV1: packet.associationScopeHashV1,
    }),
    ...(options.ownershipPatch || {}),
  };
  const ownershipV1 = {...ownershipCore,
    ownershipFingerprintV1: records.ad05dOwnershipFingerprintV1(ownershipCore)};
  const observedObjectFingerprintsV1 = objectsV1
    .map((entry) => entry.recordFingerprintV1).sort();
  const observationCore = {
    schemaVersion: 1,
    backendIdV1: 'synthetic_storage_backend_v1',
    backendVersionV1: '1',
    attemptIdV1: 'attempt-ad05d',
    observationSequenceV1: 1,
    observedObjectFingerprintsV1,
    referenceClosureHashV1: official.canonicalSha256({
      contract: 'account-deletion-ad05d-reference-closure-v1',
      objectVersionsV1: objectsV1.map((entry) => ({
        objectIdV1: entry.objectIdV1,
        recordFingerprintV1: entry.recordFingerprintV1,
        derivativeOfObjectIdV1: entry.derivativeOfObjectIdV1,
        transformIdV1: entry.transformIdV1,
        transformVersionV1: entry.transformVersionV1,
      })),
    }),
    preservedSetHashV1: official.canonicalSha256({
      contract: 'account-deletion-ad05d-preserved-set-v1',
      preservedObjectFingerprintsV1: objectsV1.filter((entry) =>
        entry.versionStateV1 === 'live' || entry.versionStateV1 === 'retained')
        .map((entry) => entry.recordFingerprintV1).sort(),
      protectedFactsHashV1: ownershipV1.protectedFactsHashV1,
      unrelatedReferencesHashV1: ownershipV1.unrelatedReferencesHashV1,
    }),
    candidateOutcomeV1: personal ? 'personalVersionEraseVerified' :
      'sharedAccountReferenceDetachVerified',
    observedAtSecV1: 1770000000,
    ...(options.observationPatch || {}),
  };
  const observationV1 = {...observationCore,
    observationFingerprintV1:
      records.ad05dObservationFingerprintV1(observationCore)};
  const core = {
    schemaVersion: 1,
    adapterIdV1: packet.effectBinding.adapterIdV1,
    bindingV1: packet.effectBinding,
    sourceDocumentPathHashV1:
      official.canonicalSha256(packet.sourceDocumentPathV1),
    sourceSchemaIdV1: 'account_deletion_ad05d_media_evidence_v1',
    sourceSchemaVersionV1: 'schema_v1',
    provenanceIdV1: `provenance-${packet.effectBinding.adapterIdV1}`,
    producerIdV1: 'synthetic_storage_fixture_v1',
    producerVersionV1: 1,
    inventoryCompleteV1: true,
    referenceCoverageCompleteV1: true,
    highWaterMarkV1: 'registered-synthetic-high-water-v1',
    bucketV1: {
      schemaVersion: 1,
      bucketRegistryVersionV1: 'synthetic_bucket_registry_v1',
      bucketNameV1: 'demo-hoopsconnect.appspot.com',
      providerProjectIdV1: 'demo-hoopsconnect',
      authTenantIdV2: 'tenant-a',
      hierarchicalNamespaceV1: false,
      versioningStateV1: 'enabled',
      softDeleteStateV1: 'disabled',
      retentionStateV1: 'none',
    },
    ownershipV1,
    objectsV1,
    observationV1,
    recordVersionV1: 'evidence-record-v1',
    ...(options.evidencePatch || {}),
  };
  return {...core,
    evidenceFingerprintV1: records.ad05dEvidenceFingerprintV1(core)};
}

function repositoryFor(packet, mediaEvidence) {
  const entries = {
    [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
    [packet.sourceDocumentPathV1]: mediaEvidence,
  };
  for (const record of mechanics.buildTestOnlyCandidateAd05dSupportingRecordsV1({
    bindingV1: packet.effectBinding,
    manifestV1: packet.manifest,
    itemV1: packet.item,
    evidenceV1: mediaEvidence,
  })) {
    entries[mechanics.ad05dSupportingRecordPathV1({
      bindingV1: packet.effectBinding,
      itemV1: packet.item,
      recordTypeV1: record.recordTypeV1,
    })] = record;
  }
  entries[mechanics.ad05dSourceAuthorityPathV1({
    bindingV1: packet.effectBinding,
    itemV1: packet.item,
  })] = mechanics.buildTestOnlyCandidateAd05dSourceAuthorityV1({
    bindingV1: packet.effectBinding,
    evidenceV1: mediaEvidence,
  });
  entries[mechanics.ad05dReceiptSealPathV1({
    bindingV1: packet.effectBinding,
    itemV1: packet.item,
  })] = mechanics.buildTestOnlyCandidateAd05dReceiptSealV1({
    bindingV1: packet.effectBinding,
    manifestV1: packet.manifest,
    itemV1: packet.item,
    evidenceV1: mediaEvidence,
  });
  return new MemoryRepository(entries);
}

async function rejectsAd05(operation) {
  await assert.rejects(operation, (error) =>
    error && /^AD05_/.test(error.codeV1));
}

for (const adapterIdV1 of records.ad05dAdapterIdsV1) {
  test(`${adapterIdV1} verifies persisted exact evidence without writes`, async () => {
    const packet = manifestPacket(adapterIdV1);
    const mediaEvidence = evidence(packet);
    const repository = repositoryFor(packet, mediaEvidence);
    const receipt = await mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
      repository,
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: mediaEvidence,
    });
    assert.equal(repository.writeCount, 0);
    assert.equal(receipt.syntheticDispositionEvidenceVerifiedV1, true);
    assert.equal(receipt.productionActivationAllowedV1, false);
    assert.equal(receipt.adapterResultEligibleV1, false);
    assert.equal(receipt.providerErasureVerifiedV1, false);
    assert.equal(receipt.publicPrivacyVerifiedV1, false);
    assert.equal(receipt.restoreSuppressionVerifiedV1, false);
    assert.deepEqual(mechanics.parseCandidateAd05dEvidenceReceiptV1(receipt),
      receipt);
  });
}

test('missing or caller-altered persisted evidence fails closed', async () => {
  const packet = manifestPacket('personal_storage_media');
  const mediaEvidence = evidence(packet);
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: new MemoryRepository({
      [ad05.ad05ManifestPathV1(packet.effectBinding)]: packet.manifest,
    }),
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: mediaEvidence,
  }));
  const altered = clone(mediaEvidence);
  altered.highWaterMarkV1 = 'caller-substitution';
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: repositoryFor(packet, mediaEvidence),
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: altered,
  }));
});

test('every separately persisted ownership, rights, graph, coverage, plan, and observation record is required', async () => {
  const packet = manifestPacket('personal_storage_media');
  const mediaEvidence = evidence(packet);
  for (const recordTypeV1 of [
    'ownership', 'rights', 'graph', 'coverage', 'effectPlan', 'observation',
  ]) {
    const repository = repositoryFor(packet, mediaEvidence);
    repository.values.delete(mechanics.ad05dSupportingRecordPathV1({
      bindingV1: packet.effectBinding,
      itemV1: packet.item,
      recordTypeV1,
    }));
    await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
      repository, bindingV1: packet.effectBinding,
      manifestV1: packet.manifest, itemV1: packet.item,
      evidenceV1: mediaEvidence,
    }));
  }
});

test('registered source authority is mandatory and exact', async () => {
  const packet = manifestPacket('personal_storage_media');
  const mediaEvidence = evidence(packet);
  const authorityPath = mechanics.ad05dSourceAuthorityPathV1({
    bindingV1: packet.effectBinding, itemV1: packet.item,
  });
  const missing = repositoryFor(packet, mediaEvidence);
  missing.values.delete(authorityPath);
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: missing, bindingV1: packet.effectBinding,
    manifestV1: packet.manifest, itemV1: packet.item,
    evidenceV1: mediaEvidence,
  }));
  const forgedEvidence = evidence(packet, {ownershipPatch: {
    ownershipSourceVersionV1: 'nonexistent-version',
    ownershipSourceHashV1: 'f'.repeat(64),
  }});
  const forged = repositoryFor(packet, forgedEvidence);
  forged.values.set(authorityPath,
    mechanics.buildTestOnlyCandidateAd05dSourceAuthorityV1({
      bindingV1: packet.effectBinding, evidenceV1: mediaEvidence,
    }));
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: forged, bindingV1: packet.effectBinding,
    manifestV1: packet.manifest, itemV1: packet.item,
    evidenceV1: forgedEvidence,
  }));
});

test('immutable receipt seal rejects a changed observation under the same source version', async () => {
  const packet = manifestPacket('shared_association_media');
  const firstEvidence = evidence(packet);
  const repository = repositoryFor(packet, firstEvidence);
  const changedEvidence = evidence(packet, {observationPatch: {
    observedAtSecV1: 1770000001,
    attemptIdV1: 'attempt-ad05d-later',
  }});
  repository.values.set(packet.sourceDocumentPathV1, changedEvidence);
  for (const record of mechanics.buildTestOnlyCandidateAd05dSupportingRecordsV1({
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: changedEvidence,
  })) {
    repository.values.set(mechanics.ad05dSupportingRecordPathV1({
      bindingV1: packet.effectBinding,
      itemV1: packet.item,
      recordTypeV1: record.recordTypeV1,
    }), record);
  }
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository, bindingV1: packet.effectBinding,
    manifestV1: packet.manifest, itemV1: packet.item,
    evidenceV1: changedEvidence,
  }));
});

test('generation, manifest, item, path, and association substitutions fail closed', async () => {
  const packet = manifestPacket('shared_association_media');
  const mediaEvidence = evidence(packet);
  const other = manifestPacket('shared_association_media', '-other');
  for (const overrides of [
    {bindingV1: other.effectBinding},
    {manifestV1: other.manifest},
    {itemV1: other.item},
  ]) {
    await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
      repository: repositoryFor(packet, mediaEvidence),
      bindingV1: packet.effectBinding,
      manifestV1: packet.manifest,
      itemV1: packet.item,
      evidenceV1: mediaEvidence,
      ...overrides,
    }));
  }
  const wrongAssociation = evidence(packet, {ownershipPatch: {
    associationScopeHashV1: official.canonicalSha256('association-other'),
  }});
  await rejectsAd05(() => mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: repositoryFor(packet, wrongAssociation),
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: wrongAssociation,
  }));
});

test('object names and generations are canonical and derivative graph is closed', () => {
  const packet = manifestPacket('shared_association_media');
  const numericGeneration = mediaObject('shared_association_media', 0,
    {objectGenerationV1: 1000});
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [numericGeneration]})));
  const encodedPath = mediaObject('shared_association_media', 0,
    {objectNameUtf8Base64UrlV1: 'candidate-ad05d/tenant-a/account/%2F.png'});
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [encodedPath]})));
  const dangling = mediaObject('shared_association_media', 1,
    {derivativeOfObjectIdV1: 'missing-parent'});
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [dangling]})));
  const left = mediaObject('shared_association_media', 0, {
    derivativeOfObjectIdV1: 'object-1', transformIdV1: 'a',
    transformVersionV1: 'v1',
  });
  const right = mediaObject('shared_association_media', 1, {
    derivativeOfObjectIdV1: 'object-0', transformIdV1: 'b',
    transformVersionV1: 'v1',
  });
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [left, right]})));
  const oversizedGeneration = mediaObject('shared_association_media', 0,
    {objectGenerationV1: '18446744073709551616'});
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [oversizedGeneration]})));
  const duplicate = clone(mediaObject('shared_association_media', 0));
  duplicate.objectIdV1 = 'object_' + 'f'.repeat(64);
  const {recordFingerprintV1: ignored, ...duplicateCore} = duplicate;
  duplicate.recordFingerprintV1 = records.ad05dObjectFingerprintV1(duplicateCore);
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [
      mediaObject('shared_association_media', 0), duplicate,
    ]})));
  const rogueName = 'candidate-ad05d/tenant-a/other-account/file.png';
  const rogueEncoded = records.ad05dObjectNameUtf8Base64UrlV1(rogueName);
  const rogue = mediaObject('shared_association_media', 0, {
    objectNameUtf8Base64UrlV1: rogueEncoded,
    objectNameHashV1: official.canonicalSha256(rogueName),
  });
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [rogue]})));
});

test('personal evidence rejects live, retained, soft-deleted, unknown, or token-bearing versions', () => {
  const packet = manifestPacket('personal_storage_media');
  for (const versionStateV1 of ['live', 'retained', 'softDeleted', 'unknown']) {
    const object = mediaObject('personal_storage_media', 0, {versionStateV1});
    assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
      evidence(packet, {objectsV1: [object]})));
  }
  const tokenObject = mediaObject('personal_storage_media', 0, {
    tokenStateV1: 'present',
    tokenSetFingerprintV1: official.canonicalSha256('token-set'),
  });
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(packet, {objectsV1: [tokenObject]})));
});

test('personal and shared classifications and outcomes cannot be exchanged', () => {
  const personal = manifestPacket('personal_storage_media');
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(personal, {ownershipPatch: {classificationV1: 'associationShared'}})));
  const shared = manifestPacket('shared_association_media');
  assert.throws(() => records.parseCandidateAd05dMediaEvidenceV1(
    evidence(shared, {observationPatch: {
      candidateOutcomeV1: 'personalVersionEraseVerified',
    }})));
});

test('receipt capability escalation and unsupported adapter ids fail closed', async () => {
  const packet = manifestPacket('personal_storage_media');
  const mediaEvidence = evidence(packet);
  const receipt = await mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: repositoryFor(packet, mediaEvidence),
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: mediaEvidence,
  });
  assert.throws(() => mechanics.parseCandidateAd05dEvidenceReceiptV1({
    ...receipt, providerErasureVerifiedV1: true,
  }));
  assert.deepEqual(mechanics.candidateAd05dMechanicalSupportV1(
    'personal_storage_media'), {
    stateV1: 'candidateEvidenceOnly', adapterResultEligibleV1: false,
  });
  assert.throws(() => mechanics.candidateAd05dMechanicalSupportV1('user_profile'));
});

test('positive notApplicable requires complete persisted zero-object evidence', async () => {
  const packet = manifestPacket(
    'personal_storage_media', '-none', 'notApplicable');
  const mediaEvidence = evidence(packet, {
    objectsV1: [],
    observationPatch: {
      candidateOutcomeV1: 'positiveNotApplicableEvidenceVerified',
    },
  });
  const receipt = await mechanics.verifyTestOnlySyntheticCandidateAd05dEvidenceV1({
    repository: repositoryFor(packet, mediaEvidence),
    bindingV1: packet.effectBinding, manifestV1: packet.manifest,
    itemV1: packet.item, evidenceV1: mediaEvidence,
  });
  assert.equal(receipt.candidateOutcomeV1,
    'positiveNotApplicableEvidenceVerified');
});
