'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const official = require('../lib/domain/official_stats_contract');
const ad05Records = require('../lib/account_deletion/ad05_records');
const ad05Inventory = require('../lib/account_deletion/ad05_inventory');
const records = require('../lib/account_deletion/ad05_identity_suppression_records');
const mechanics = require('../lib/account_deletion/ad05_identity_suppression');

const fixture = require('../../contracts/account_deletion/ad05/identity_suppression_fixtures_v1.json');
const ad05Fixture = require('../../contracts/account_deletion/ad05/adapter_fixtures_v1.json');

function clone(value) {
  return structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([key, value]) =>
      [key, clone(value)]));
    this.writeCount = 0;
  }
  async read(pathValue) {
    return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
  }
  async runTransaction(operation) {
    const staged = new Map();
    let writeStarted = false;
    const result = await operation({
      read: async (pathValue) => {
        if (writeStarted) throw new Error('AD05-B read after write');
        return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
      },
      write: (pathValue, value) => {
        writeStarted = true;
        staged.set(pathValue, clone(value));
      },
    });
    for (const [key, value] of staged) {
      this.values.set(key, value);
      this.writeCount += 1;
    }
    return result;
  }
}

function executionBinding(adapterIdV1, index) {
  const actions = {
    account_person_claims: 'detach',
    person_identity_evidence: 'restrictedRetention',
    public_projections_exports: 'erase',
  };
  return ad05Records.createCandidateAd05ExecutionBindingV1({
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant-a',
    authUidV2: 'account@example.com/α',
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 17,
    lifecycleStateV1: 'deleting',
    internalJobId: 'job_identity_suppression',
    taskEffectIdV1: `effect_identity_${index}`,
    taskEffectFingerprintV1: String(index + 1).repeat(64),
    adapterIdV1,
    adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: adapterIdV1 === 'account_person_claims' ?
      'transactional-document-v1' : 'unsupported-v1',
    policyDecisionIdV1: `retention.${adapterIdV1}`,
    policyVersionV1: 'synthetic_policy_v1',
    actionV1: actions[adapterIdV1],
    sourceManifestIdV1: `source_manifest_${index}`,
    sourceManifestVersionV1: 'identity_inventory_v1',
  });
}

function reference(referenceClassV1, ordinalV1) {
  const adapterIdV1 = referenceClassV1 === 'accountPersonClaim' ?
    'account_person_claims' : referenceClassV1.startsWith('personIdentity') ?
      'person_identity_evidence' : 'public_projections_exports';
  const withoutFingerprint = {
    schemaVersion: 1,
    referenceIdV1: referenceClassV1 === 'personIdentityEvidenceCapsule' ?
      'identity_evidence_capsule_a' : `reference_${ordinalV1}`,
    ordinalV1,
    adapterIdV1,
    referenceClassV1,
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: 'tenant-a',
    authUidV2: 'account@example.com/α',
    authUidUtf16LeBase64UrlV1:
      executionBinding('account_person_claims', 0).authUidUtf16LeBase64UrlV1,
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 17,
    associationIdV1: 'association-a',
    subjectIdV1: 'subject-a',
    claimIdV1: 'claim-a',
    sourceSystemIdV1: `source_system_${ordinalV1}`,
    sourceSchemaIdV1: referenceClassV1 === 'accountPersonClaim' ?
      'account_person_claim_v1' : `source_schema_${ordinalV1}`,
    sourceSchemaVersionV1: 'schema_v1',
    referenceVersionV1: referenceClassV1 === 'accountPersonClaim' ?
      'claim_record_v1' : `reference_version_${ordinalV1}`,
    referencePathHashV1: official.canonicalSha256(
      referenceClassV1 === 'accountPersonClaim' ?
        'privateAccountPersonClaims/claim-a' : `private/path/${ordinalV1}`),
    provenanceIdV1: referenceClassV1 === 'accountPersonClaim' ?
      'verified_claim_provenance_a' :
      referenceClassV1 === 'personIdentityEvidenceCapsule' ?
        'identity_evidence_provenance_a' : `provenance_${ordinalV1}`,
    classificationV1: 'applicable',
    identityBearingV1: true,
    guaranteeV1: referenceClassV1 === 'accountPersonClaim' ?
      'transactionalRecordVersion' : 'versionOrProviderGuaranteeUnavailable',
  };
  return records.parseCandidateAd05bIdentityReferenceV1({
    ...withoutFingerprint,
    referenceFingerprintV1:
      records.ad05bIdentityReferenceFingerprintV1(withoutFingerprint),
  });
}

function completeBundle() {
  const bindings = fixture.identityAdapterIdsV1.map(executionBinding);
  const effects = records.assertCandidateAd05bBindingsShareScopeV1(bindings);
  const presentClasses = [
    'accountPersonClaim', 'personIdentityEvidenceCapsule',
    'personIdentityEvidenceMaterial', 'rawCompatibilityPath', 'exportArtifact',
    'restoreReplayInput', 'rebuildInput',
  ];
  const references = presentClasses.map(reference);
  const referenceCoverage = fixture.identityReferenceClassesV1.map(
    (referenceClassV1, ordinalV1) => {
      const adapterIdV1 = referenceClassV1 === 'accountPersonClaim' ?
        'account_person_claims' : referenceClassV1.startsWith('personIdentity') ?
          'person_identity_evidence' : 'public_projections_exports';
      const coverageCore = {
        schemaVersion: 1, ordinalV1, adapterIdV1, referenceClassV1,
        authProjectIdV2: bindings[0].authProjectIdV2,
        authTenantIdV2: bindings[0].authTenantIdV2,
        authUidV2: bindings[0].authUidV2,
        authUidUtf16LeBase64UrlV1: bindings[0].authUidUtf16LeBase64UrlV1,
        generationHash: bindings[0].generationHash,
        acceptedLifecycleEpochV2: bindings[0].acceptedLifecycleEpochV2,
        associationIdV1: 'association-a', subjectIdV1: 'subject-a',
        claimIdV1: 'claim-a',
        coverageStateV1: presentClasses.includes(referenceClassV1) ?
          'referencesEnumerated' : 'verifiedAbsent',
        scannedSourceIdV1: `coverage_source_${ordinalV1}`,
        scannedSourceVersionV1: 'coverage_source_v1',
        provenanceIdV1: `coverage_provenance_${ordinalV1}`,
        evidenceIdV1: `coverage_evidence_${ordinalV1}`,
        completeV1: true,
      };
      return records.parseCandidateAd05bIdentityReferenceCoverageV1({
        ...coverageCore,
        coverageFingerprintV1:
          records.ad05bIdentityReferenceCoverageFingerprintV1(coverageCore),
      });
    });
  const trustedClaimRecord = {
    schemaVersion: 1, adapterIdV1: 'account_person_claims',
    sourceSchemaIdV1: 'account_person_claim_v1',
    sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1: 'privateAccountPersonClaims/claim-a',
    sourceRecordVersionV1: 'claim_record_v1',
    provenanceIdV1: 'verified_claim_provenance_a',
    associationScopeHashV1: official.canonicalSha256('association-a'),
    classificationV1: 'applicable',
  };
  const claimItemCore = {
    ...trustedClaimRecord,
    itemIdV1: ad05Inventory.deterministicAd05ManifestItemIdV1({
      binding: bindings[0], record: trustedClaimRecord,
    }),
    ordinalV1: 0,
    sourceDocumentPathHashV1:
      official.canonicalSha256(trustedClaimRecord.sourceDocumentPathV1),
  };
  const claimItem = ad05Records.parseCandidateAd05ManifestItemV1({
    ...claimItemCore,
    itemFingerprintV1: ad05Records.ad05ManifestItemFingerprintV1(claimItemCore),
  });
  const claimSourceManifestCore = {
    schemaVersion: 1,
    manifestIdV1: bindings[0].sourceManifestIdV1,
    manifestVersionV1: bindings[0].sourceManifestVersionV1,
    bindingFingerprintV1: bindings[0].bindingFingerprintV1,
    adapterIdV1: 'account_person_claims',
    inventorySourceIdV1: 'trusted_account_person_claim_inventory',
    inventorySourceVersionV1: bindings[0].sourceManifestVersionV1,
    referenceCoverageEvidenceIdV1: 'claim_reference_coverage_evidence',
    completeV1: true, sealedV1: true, itemCountV1: 1, itemsV1: [claimItem],
  };
  const claimSourceManifest = ad05Records.parseCandidateAd05SealedManifestV1({
    ...claimSourceManifestCore,
    manifestFingerprintV1:
      ad05Records.ad05ManifestFingerprintV1(claimSourceManifestCore),
  });
  const manifestCore = {
    schemaVersion: 1,
    manifestIdV1: 'identity_reference_manifest_a',
    manifestVersionV1: 'identity_reference_manifest_v1',
    authProjectIdV2: bindings[0].authProjectIdV2,
    authTenantIdV2: bindings[0].authTenantIdV2,
    authUidV2: bindings[0].authUidV2,
    authUidUtf16LeBase64UrlV1: bindings[0].authUidUtf16LeBase64UrlV1,
    generationHash: bindings[0].generationHash,
    acceptedLifecycleEpochV2: bindings[0].acceptedLifecycleEpochV2,
    lifecycleStateV1: 'deleting',
    internalJobId: bindings[0].internalJobId,
    associationIdV1: 'association-a',
    subjectIdV1: 'subject-a',
    claimIdV1: 'claim-a',
    claimProvenanceIdV1: 'verified_claim_provenance_a',
    identityEvidenceIdV1: 'identity_evidence_capsule_a',
    identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
    publicationPolicyDecisionIdV1: 'retention.public_projections_exports',
    publicationPolicyVersionV1: 'synthetic_policy_v1',
    fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
    fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
    fieldLevelPublicationPolicyProvenanceIdV1:
      'test_field_publication_provenance_a',
    fieldLevelPublicationPolicyApprovalV1: 'explicitTestOnlySynthetic',
    minorStatusV1: 'unknown',
    identityPublicationAllowedV1: false,
    scopeAuthorityV1: 'verifiedAccountAssociationOnly',
    personErasureAuthorityV1: false,
    effectBindingsV1: effects,
    referenceCoverageV1: referenceCoverage,
    referenceCoverageSetFingerprintV1:
      records.ad05bIdentityReferenceCoverageSetFingerprintV1(referenceCoverage),
    referenceCountV1: references.length,
    referencesV1: references,
    referenceSetFingerprintV1:
      records.ad05bIdentityReferenceSetFingerprintV1(references),
    rawPathCoverageVerifiedV1: true,
    restoreSuppressionCoverageVerifiedV1: true,
    verifierIdV1: 'test_only_reference_verifier',
    verificationEvidenceIdV1: 'test_only_reference_evidence',
    verifiedAtSecV1: 1_800_000_000,
    completeV1: true,
    sealedV1: true,
    allVersionOrProviderGuaranteesVerifiedV1: false,
  };
  const manifest = records.parseCandidateAd05bIdentityReferenceManifestV1({
    ...manifestCore,
    manifestFingerprintV1:
      records.ad05bIdentityReferenceManifestFingerprintV1(manifestCore),
  });
  const suppressionCore = {
    schemaVersion: 1,
    authProjectIdV2: manifest.authProjectIdV2,
    authTenantIdV2: manifest.authTenantIdV2,
    authUidV2: manifest.authUidV2,
    authUidUtf16LeBase64UrlV1: manifest.authUidUtf16LeBase64UrlV1,
    generationHash: manifest.generationHash,
    acceptedLifecycleEpochV2: manifest.acceptedLifecycleEpochV2,
    lifecycleStateV1: 'deleting',
    internalJobId: manifest.internalJobId,
    associationIdV1: manifest.associationIdV1,
    subjectIdV1: manifest.subjectIdV1,
    claimIdV1: manifest.claimIdV1,
    claimProvenanceIdV1: manifest.claimProvenanceIdV1,
    identityEvidenceIdV1: manifest.identityEvidenceIdV1,
    identityEvidenceProvenanceIdV1: manifest.identityEvidenceProvenanceIdV1,
    policyVersionV1: manifest.publicationPolicyVersionV1,
    fieldLevelPublicationPolicyIdV1: manifest.fieldLevelPublicationPolicyIdV1,
    fieldLevelPublicationPolicyVersionV1:
      manifest.fieldLevelPublicationPolicyVersionV1,
    fieldLevelPublicationPolicyProvenanceIdV1:
      manifest.fieldLevelPublicationPolicyProvenanceIdV1,
    fieldLevelPublicationPolicyApprovalV1: 'explicitTestOnlySynthetic',
    scopeAuthorityV1: 'verifiedAccountAssociationOnly',
    personErasureAuthorityV1: false,
    identityPublicationAllowedV1: false,
    minorStatusV1: manifest.minorStatusV1,
    referenceManifestIdV1: manifest.manifestIdV1,
    referenceManifestFingerprintV1: manifest.manifestFingerprintV1,
    claimSourceManifestFingerprintV1: claimSourceManifest.manifestFingerprintV1,
    restoreSuppressionReferenceIdV1: 'restore_suppression_reference_a',
    durableV1: true,
    blocksPublicationV1: true,
    blocksRebuildV1: true,
    blocksRestoreReplayV1: true,
    officialStatGlobalIdentityMutationAllowedV1: false,
    snapshotEpochMutationAllowedV1: false,
    releaseHeadMutationAllowedV1: false,
    publicEpochMutationAllowedV1: false,
    canonicalBytesMutationAllowedV1: false,
    certifiedHashMutationAllowedV1: false,
    actorProvenanceMutationAllowedV1: false,
    correctionLineageMutationAllowedV1: false,
    createdAtSecV1: 1_800_000_001,
  };
  const suppression = records.parseCandidateAd05bIdentitySuppressionV1({
    ...suppressionCore,
    suppressionFingerprintV1:
      records.ad05bIdentitySuppressionFingerprintV1(suppressionCore),
  });
  return {bindings, manifest, suppression, claimSourceManifest};
}

function refingerprintManifest(value) {
  const copy = clone(value);
  delete copy.manifestFingerprintV1;
  return {...copy,
    manifestFingerprintV1:
      records.ad05bIdentityReferenceManifestFingerprintV1(copy)};
}

function refingerprintSuppression(value) {
  const copy = clone(value);
  delete copy.suppressionFingerprintV1;
  return {...copy,
    suppressionFingerprintV1:
      records.ad05bIdentitySuppressionFingerprintV1(copy)};
}

function verificationFor(input) {
  const core = {
    schemaVersion: 1,
    referenceSetFingerprintV1: input.referenceSetFingerprintV1,
    referenceCoverageSetFingerprintV1:
      input.referenceCoverageSetFingerprintV1,
    claimSourceManifestFingerprintV1:
      input.claimSourceManifestV1.manifestFingerprintV1,
    associationIdV1: input.associationIdV1,
    subjectIdV1: input.subjectIdV1,
    claimIdV1: input.claimIdV1,
    claimReferenceClosureVerifiedV1: true,
    rawPathCoverageVerifiedV1: true,
    restoreSuppressionCoverageVerifiedV1: true,
    completeV1: true,
    verifierIdV1: 'explicit_test_only_reference_verifier',
    verificationEvidenceIdV1: 'explicit_test_only_reference_evidence',
    verifiedAtSecV1: 1_800_000_000,
  };
  return {...core, verificationFingerprintV1:
    mechanics.ad05bIdentityReferenceVerificationFingerprintV1(core)};
}

async function sealBundle() {
  const template = completeBundle();
  const repository = new MemoryRepository({
    [ad05Records.ad05ManifestPathV1(template.bindings[0])]:
      template.claimSourceManifest,
  });
  const result = await mechanics.sealTestOnlySyntheticCandidateAd05bIdentitySuppressionV1({
    repository,
    syntheticPolicyV1: ad05Fixture.testOnlySyntheticApprovedPolicy,
    bindingsV1: template.bindings,
    claimSourceManifestV1: template.claimSourceManifest,
    associationIdV1: 'association-a',
    subjectIdV1: 'subject-a',
    claimIdV1: 'claim-a',
    claimProvenanceIdV1: 'verified_claim_provenance_a',
    identityEvidenceIdV1: 'identity_evidence_capsule_a',
    identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
    fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
    fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
    fieldLevelPublicationPolicyProvenanceIdV1:
      'test_field_publication_provenance_a',
    minorStatusV1: 'unknown',
    restoreSuppressionReferenceIdV1: 'restore_suppression_reference_a',
    createdAtSecV1: 1_800_000_001,
    sourceV1: {enumerateIdentityReferencesV1: async () => ({
      schemaVersion: 1,
      inventorySourceIdV1: 'trusted_identity_reference_inventory',
      inventorySourceVersionV1: 'identity_reference_inventory_v1',
      completeV1: true,
      continuationTokenV1: null,
      referenceCoverageV1: template.manifest.referenceCoverageV1,
      referencesV1: template.manifest.referencesV1,
    })},
    verifierV1: {verifyIdentityReferencesV1: async (input) =>
      verificationFor(input)},
  });
  return {...template, ...result, repository};
}

test('AD05-B fixture freezes exactly three candidate adapters and the T versus V/E split', () => {
  assert.equal(fixture.exactBaseCommit,
    'd133416157be5cfbf35cd2f4d00e03c2840bf2b2');
  assert.deepEqual(fixture.identityAdapterIdsV1,
    records.ad05bIdentityAdapterIdsV1);
  assert.deepEqual(fixture.identityReferenceClassesV1,
    records.ad05bIdentityReferenceClassesV1);
  assert.deepEqual(fixture.mechanicalSupportV1, {
    account_person_claims: 'transactionalDocument',
    person_identity_evidence: 'unsupportedVersionedMaterial',
    public_projections_exports:
      'suppressionPrerequisiteOnlyExternalStillUnsupported',
  });
  assert.equal(fixture.normativePolicy.policyVersion, null);
  assert.equal(fixture.normativePolicy.activationApproved, false);
  assert.equal(fixture.normativePolicy.mutationsAllowed, false);
});

test('strict records bind UID bytes, generation, tenant, association, subject, claim, evidence, and exact effects', () => {
  const {bindings, manifest, suppression, claimSourceManifest} = completeBundle();
  records.assertCandidateAd05bManifestSuppressionBindingV1({
    manifest, suppression, claimSourceManifest,
  });
  assert.equal(manifest.effectBindingsV1.length, 3);
  assert.deepEqual(manifest.effectBindingsV1.map((entry) => entry.adapterIdV1),
    fixture.identityAdapterIdsV1);
  assert.equal(manifest.authUidUtf16LeBase64UrlV1,
    bindings[0].authUidUtf16LeBase64UrlV1);
  assert.equal(manifest.scopeAuthorityV1, 'verifiedAccountAssociationOnly');
  assert.equal(manifest.personErasureAuthorityV1, false);
  assert.equal(suppression.durableV1, true);
});

test('unknown minor status stays non-public and every sporting-integrity mutation remains forbidden', () => {
  const {manifest, suppression} = completeBundle();
  assert.equal(manifest.minorStatusV1, 'unknown');
  assert.equal(manifest.identityPublicationAllowedV1, false);
  for (const field of [
    'officialStatGlobalIdentityMutationAllowedV1',
    'snapshotEpochMutationAllowedV1',
    'releaseHeadMutationAllowedV1',
    'publicEpochMutationAllowedV1',
    'canonicalBytesMutationAllowedV1',
    'certifiedHashMutationAllowedV1',
    'actorProvenanceMutationAllowedV1',
    'correctionLineageMutationAllowedV1',
  ]) assert.equal(suppression[field], false, field);
});

test('missing claim or identity evidence provenance fails closed even after re-fingerprinting', () => {
  const {manifest} = completeBundle();
  for (const field of [
    'claimProvenanceIdV1', 'identityEvidenceIdV1',
    'identityEvidenceProvenanceIdV1', 'fieldLevelPublicationPolicyIdV1',
    'fieldLevelPublicationPolicyVersionV1',
    'fieldLevelPublicationPolicyProvenanceIdV1',
  ]) {
    const changed = clone(manifest);
    changed[field] = null;
    assert.throws(() =>
      records.parseCandidateAd05bIdentityReferenceManifestV1(
        refingerprintManifest(changed)),
    );
  }
});

test('missing raw/export/restore/rebuild class coverage fails closed', () => {
  const {manifest} = completeBundle();
  for (const referenceClassV1 of [
    'rawCompatibilityPath', 'exportArtifact', 'restoreReplayInput', 'rebuildInput',
  ]) {
    const changed = clone(manifest);
    changed.referenceCoverageV1 = changed.referenceCoverageV1.filter((entry) =>
      entry.referenceClassV1 !== referenceClassV1);
    changed.referenceCoverageV1.forEach((entry, index) => {
      entry.ordinalV1 = index;
      delete entry.coverageFingerprintV1;
      entry.coverageFingerprintV1 =
        records.ad05bIdentityReferenceCoverageFingerprintV1(entry);
    });
    changed.referenceCoverageSetFingerprintV1 =
      records.ad05bIdentityReferenceCoverageSetFingerprintV1(
        changed.referenceCoverageV1);
    assert.throws(() => records.parseCandidateAd05bIdentityReferenceManifestV1(
      refingerprintManifest(changed)), {codeV1: 'AD05B_BINDING_CONFLICT'});
  }
});

test('V and E references explicitly lack guarantees and cannot be relabelled transactional', () => {
  const {manifest} = completeBundle();
  assert.equal(manifest.referencesV1[0].guaranteeV1,
    'transactionalRecordVersion');
  assert.ok(manifest.referencesV1.slice(1).every((entry) =>
    entry.guaranteeV1 === 'versionOrProviderGuaranteeUnavailable'));
  const changed = clone(manifest.referencesV1[2]);
  changed.guaranteeV1 = 'transactionalRecordVersion';
  delete changed.referenceFingerprintV1;
  changed.referenceFingerprintV1 =
    records.ad05bIdentityReferenceFingerprintV1(changed);
  assert.throws(() => records.parseCandidateAd05bIdentityReferenceV1(changed),
    {codeV1: 'AD05B_BINDING_CONFLICT'});
});

test('coverage is separate from instances: verified absence and multiple artifacts are representable', () => {
  const {manifest} = completeBundle();
  const publicProfileCoverage = manifest.referenceCoverageV1.find((entry) =>
    entry.referenceClassV1 === 'publicProfile');
  assert.equal(publicProfileCoverage.coverageStateV1, 'verifiedAbsent');
  assert.equal(manifest.referencesV1.some((entry) =>
    entry.referenceClassV1 === 'publicProfile'), false);

  const changed = clone(manifest);
  const extra = reference('exportArtifact', changed.referencesV1.length);
  changed.referencesV1.push(extra);
  changed.referenceCountV1 = changed.referencesV1.length;
  changed.referenceSetFingerprintV1 =
    records.ad05bIdentityReferenceSetFingerprintV1(changed.referencesV1);
  const parsed = records.parseCandidateAd05bIdentityReferenceManifestV1(
    refingerprintManifest(changed));
  assert.equal(parsed.referencesV1.filter((entry) =>
    entry.referenceClassV1 === 'exportArtifact').length, 2);
});

test('cross-tenant, cross-generation, cross-association, and cross-claim drift fail exact binding', () => {
  const {manifest, suppression, claimSourceManifest} = completeBundle();
  for (const [field, value] of [
    ['authTenantIdV2', 'tenant-b'],
    ['generationHash', 'b'.repeat(64)],
    ['associationIdV1', 'association-b'],
    ['subjectIdV1', 'subject-b'],
    ['claimIdV1', 'claim-b'],
  ]) {
    const changed = refingerprintSuppression({...clone(suppression), [field]: value});
    assert.throws(() => records.assertCandidateAd05bManifestSuppressionBindingV1({
      manifest, suppression: changed, claimSourceManifest,
    }), {codeV1: 'AD05B_BINDING_CONFLICT'});
  }
});

test('unknown fields and enabling any public or immutable mutation fail closed', () => {
  const {manifest, suppression} = completeBundle();
  assert.throws(() => records.parseCandidateAd05bIdentityReferenceManifestV1({
    ...manifest, displayName: 'Do not infer identity',
  }), {codeV1: 'AD05B_INVALID_RECORD'});
  for (const field of [
    'identityPublicationAllowedV1', 'personErasureAuthorityV1',
    'publicEpochMutationAllowedV1', 'certifiedHashMutationAllowedV1',
  ]) {
    const target = field in manifest ? manifest : suppression;
    const changed = clone(target);
    changed[field] = true;
    const parser = target === manifest ?
      records.parseCandidateAd05bIdentityReferenceManifestV1 :
      records.parseCandidateAd05bIdentitySuppressionV1;
    assert.throws(() => parser(target === manifest ?
      refingerprintManifest(changed) : refingerprintSuppression(changed)),
    {codeV1: 'AD05B_BLOCKED'});
  }
});

test('private paths hash association, subject, and claim identifiers', () => {
  const {manifest, suppression} = completeBundle();
  const manifestPath = records.ad05bIdentityReferenceManifestPathV1({
    internalJobId: manifest.internalJobId,
    manifestIdV1: manifest.manifestIdV1,
  });
  const suppressionPath = records.ad05bIdentitySuppressionPathV1(suppression);
  assert.match(manifestPath,
    /^accountDeletionJobsV1\/job_identity_suppression\/ad05IdentityReferenceManifestsV1\/identity_manifest_[0-9a-f]{64}$/);
  assert.match(suppressionPath,
    /^accountDeletionJobsV1\/job_identity_suppression\/ad05IdentitySuppressionsV1\/identity_suppression_[0-9a-f]{64}$/);
  assert.doesNotMatch(suppressionPath, /association-a|subject-a|claim-a/);
});

test('normative AD01 posture yields a blocked plan with zero mutation authority', () => {
  assert.deepEqual(mechanics.createDormantCandidateAd05bIdentitySuppressionPlanV1(), {
    stateV1: 'blocked',
    evidenceCodeV1: 'authoritative_policy_not_approved',
    writesAllowedV1: false,
  });
});

test('explicit synthetic test seam persists the manifest and suppression create-once before mutation', async () => {
  const sealed = await sealBundle();
  assert.equal(sealed.stateV1, 'sealed');
  assert.equal(sealed.repository.writeCount, 2);
  const replay = await mechanics.sealTestOnlySyntheticCandidateAd05bIdentitySuppressionV1({
    repository: sealed.repository,
    syntheticPolicyV1: ad05Fixture.testOnlySyntheticApprovedPolicy,
    bindingsV1: sealed.bindings,
    claimSourceManifestV1: sealed.claimSourceManifest,
    associationIdV1: 'association-a', subjectIdV1: 'subject-a', claimIdV1: 'claim-a',
    claimProvenanceIdV1: 'verified_claim_provenance_a',
    identityEvidenceIdV1: 'identity_evidence_capsule_a',
    identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
    fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
    fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
    fieldLevelPublicationPolicyProvenanceIdV1:
      'test_field_publication_provenance_a',
    minorStatusV1: 'unknown',
    restoreSuppressionReferenceIdV1: 'restore_suppression_reference_a',
    createdAtSecV1: 1_800_000_001,
    sourceV1: {enumerateIdentityReferencesV1: async () => ({
      schemaVersion: 1, inventorySourceIdV1: 'trusted_identity_reference_inventory',
      inventorySourceVersionV1: 'identity_reference_inventory_v1',
      completeV1: true, continuationTokenV1: null,
      referenceCoverageV1: sealed.manifest.referenceCoverageV1,
      referencesV1: sealed.manifest.referencesV1,
    })},
    verifierV1: {verifyIdentityReferencesV1: async (input) => verificationFor(input)},
  });
  assert.equal(replay.stateV1, 'replayed');
  assert.equal(sealed.repository.writeCount, 2);
});

test('claim detachment runs through the frozen kernel after in-transaction suppression proof', async () => {
  const sealed = await sealBundle();
  const item = sealed.claimSourceManifest.itemsV1[0];
  const before = mechanics.parseCandidateAd05bAccountPersonClaimV1({
    schemaVersion: 1,
    authProjectIdV2: sealed.bindings[0].authProjectIdV2,
    authTenantIdV2: sealed.bindings[0].authTenantIdV2,
    associationIdV1: 'association-a', subjectIdV1: 'subject-a', claimIdV1: 'claim-a',
    claimKindV1: 'player', claimVerificationStateV1: 'verified',
    claimProvenanceIdV1: 'verified_claim_provenance_a',
    identityEvidenceIdV1: 'identity_evidence_capsule_a',
    identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
    publicationPolicyDecisionIdV1: 'retention.public_projections_exports',
    fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
    fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
    fieldLevelPublicationPolicyProvenanceIdV1:
      'test_field_publication_provenance_a',
    minorStatusV1: 'unknown', accountAssociationStateV1: 'active',
    authUidV2: sealed.bindings[0].authUidV2,
    authUidUtf16LeBase64UrlV1: sealed.bindings[0].authUidUtf16LeBase64UrlV1,
    generationHash: sealed.bindings[0].generationHash,
    accountLifecycleEpochV2: sealed.bindings[0].acceptedLifecycleEpochV2,
    suppressionFingerprintV1: null,
    identityReferenceManifestFingerprintV1: null,
    recordVersionV1: 'claim_record_v1',
  });
  sealed.repository.values.set(item.sourceDocumentPathV1, before);
  const result = await mechanics.applyTestOnlySyntheticCandidateAd05bClaimDetachmentV1({
    repository: sealed.repository,
    bindingV1: sealed.bindings[0],
    claimSourceManifestV1: sealed.claimSourceManifest,
    itemV1: item,
    identityManifestV1: sealed.manifestV1,
    suppressionV1: sealed.suppressionV1,
    sourceRecordVersionAfterV1: 'claim_record_v2',
    committedAtSecV1: 1_800_000_002,
  });
  assert.equal(result.stateV1, 'committed');
  const after = await sealed.repository.read(item.sourceDocumentPathV1);
  assert.equal(after.accountAssociationStateV1, 'suppressedForDeletedGeneration');
  assert.equal(after.authUidV2, null);
  assert.equal(after.generationHash, null);
  assert.equal(after.claimProvenanceIdV1, before.claimProvenanceIdV1);
  assert.equal(after.identityEvidenceIdV1, before.identityEvidenceIdV1);
  assert.equal(after.identityEvidenceProvenanceIdV1,
    before.identityEvidenceProvenanceIdV1);
  assert.equal(after.minorStatusV1, 'unknown');
  assert.equal(after.suppressionFingerprintV1,
    sealed.suppressionV1.suppressionFingerprintV1);
  const replay = await mechanics.applyTestOnlySyntheticCandidateAd05bClaimDetachmentV1({
    repository: sealed.repository, bindingV1: sealed.bindings[0],
    claimSourceManifestV1: sealed.claimSourceManifest, itemV1: item,
    identityManifestV1: sealed.manifestV1, suppressionV1: sealed.suppressionV1,
    sourceRecordVersionAfterV1: 'claim_record_v2', committedAtSecV1: 1_800_000_003,
  });
  assert.equal(replay.stateV1, 'replayed');
});

test('missing suppression at transaction time blocks claim mutation and writes no receipt', async () => {
  const sealed = await sealBundle();
  const item = sealed.claimSourceManifest.itemsV1[0];
  sealed.repository.values.set(item.sourceDocumentPathV1, {
    schemaVersion: 1, authProjectIdV2: sealed.bindings[0].authProjectIdV2,
    authTenantIdV2: sealed.bindings[0].authTenantIdV2,
    associationIdV1: 'association-a', subjectIdV1: 'subject-a', claimIdV1: 'claim-a',
    claimKindV1: 'player', claimVerificationStateV1: 'verified',
    claimProvenanceIdV1: 'verified_claim_provenance_a',
    identityEvidenceIdV1: 'identity_evidence_capsule_a',
    identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
    publicationPolicyDecisionIdV1: 'retention.public_projections_exports',
    fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
    fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
    fieldLevelPublicationPolicyProvenanceIdV1:
      'test_field_publication_provenance_a',
    minorStatusV1: 'unknown', accountAssociationStateV1: 'active',
    authUidV2: sealed.bindings[0].authUidV2,
    authUidUtf16LeBase64UrlV1: sealed.bindings[0].authUidUtf16LeBase64UrlV1,
    generationHash: sealed.bindings[0].generationHash,
    accountLifecycleEpochV2: sealed.bindings[0].acceptedLifecycleEpochV2,
    suppressionFingerprintV1: null, identityReferenceManifestFingerprintV1: null,
    recordVersionV1: 'claim_record_v1',
  });
  sealed.repository.values.delete(records.ad05bIdentitySuppressionPathV1(
    sealed.suppressionV1));
  await assert.rejects(() =>
    mechanics.applyTestOnlySyntheticCandidateAd05bClaimDetachmentV1({
      repository: sealed.repository, bindingV1: sealed.bindings[0],
      claimSourceManifestV1: sealed.claimSourceManifest, itemV1: item,
      identityManifestV1: sealed.manifestV1, suppressionV1: sealed.suppressionV1,
      sourceRecordVersionAfterV1: 'claim_record_v2', committedAtSecV1: 1_800_000_002,
    }), {codeV1: 'AD05B_BLOCKED'});
  assert.equal((await sealed.repository.read(item.sourceDocumentPathV1)).recordVersionV1,
    'claim_record_v1');
});

test('persisted cross-claim-incomplete manifest is rejected by the same-transaction guard', async () => {
  const sealed = await sealBundle();
  const manifestPath = records.ad05bIdentityReferenceManifestPathV1({
    internalJobId: sealed.manifestV1.internalJobId,
    manifestIdV1: sealed.manifestV1.manifestIdV1,
  });
  const changed = clone(sealed.manifestV1);
  const claimReference = changed.referencesV1.find((entry) =>
    entry.referenceClassV1 === 'accountPersonClaim');
  claimReference.referencePathHashV1 = official.canonicalSha256('claims/unrelated-b');
  delete claimReference.referenceFingerprintV1;
  claimReference.referenceFingerprintV1 =
    records.ad05bIdentityReferenceFingerprintV1(claimReference);
  changed.referenceSetFingerprintV1 =
    records.ad05bIdentityReferenceSetFingerprintV1(changed.referencesV1);
  sealed.repository.values.set(manifestPath, refingerprintManifest(changed));
  await assert.rejects(() => mechanics.requireCandidateAd05bIdentitySuppressionBundleV1({
    repository: sealed.repository,
    manifestV1: sealed.repository.values.get(manifestPath),
    suppressionV1: sealed.suppressionV1,
    claimSourceManifestV1: sealed.claimSourceManifest,
  }), {codeV1: 'AD05B_BINDING_CONFLICT'});
});

test('V/E stay unsupported while suppression denies publication, rebuild, and restore without epoch writes', async () => {
  assert.deepEqual(mechanics.candidateAd05bMechanicalSupportV1(
    'person_identity_evidence'), {
    stateV1: 'unsupported',
    evidenceCodeV1: 'versioned_identity_material_guarantee_unavailable',
  });
  assert.equal(mechanics.candidateAd05bMechanicalSupportV1(
    'public_projections_exports').stateV1, 'unsupported');
  const sealed = await sealBundle();
  for (const actionV1 of ['publication', 'rebuild', 'restoreReplay']) {
    const result = await mechanics.evaluateCandidateAd05bSuppressedDeliveryV1({
      repository: sealed.repository,
      manifestV1: sealed.manifestV1,
      suppressionV1: sealed.suppressionV1,
      claimSourceManifestV1: sealed.claimSourceManifest,
      actionV1,
    });
    assert.equal(result.allowedV1, false);
    assert.equal(result.privacyEpochMutationRequestedV1, false);
    assert.equal(result.releaseHeadMutationRequestedV1, false);
  }
});
