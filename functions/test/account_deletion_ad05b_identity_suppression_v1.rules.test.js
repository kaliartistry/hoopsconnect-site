'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {assertFails, initializeTestEnvironment} =
  require('@firebase/rules-unit-testing');
const {doc, getDoc, runTransaction, setDoc} = require('firebase/firestore');

const official = require('../lib/domain/official_stats_contract');
const ad05Fixture = require('../../contracts/account_deletion/ad05/adapter_fixtures_v1.json');
const ad05Records = require('../lib/account_deletion/ad05_records');
const ad05Inventory = require('../lib/account_deletion/ad05_inventory');
const records = require('../lib/account_deletion/ad05_identity_suppression_records');
const mechanics = require('../lib/account_deletion/ad05_identity_suppression');

const rules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05b_v1/firestore.rules',
), 'utf8');

let testEnv;

function normalize(value) {
  if (value === null || value === undefined) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (Array.isArray(value)) return value.map(normalize);
  if (typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) =>
      [key, normalize(entry)]));
  }
  return value;
}

class EmulatorRepository {
  constructor(db) { this.db = db; }
  async read(pathValue) {
    const snapshot = await getDoc(doc(this.db, pathValue));
    return snapshot.exists() ? normalize(snapshot.data()) : null;
  }
  async runTransaction(operation) {
    return runTransaction(this.db, async (transaction) => {
      let writeStarted = false;
      return operation({
        read: async (pathValue) => {
          if (writeStarted) throw new Error('AD05-B emulator read after write');
          const snapshot = await transaction.get(doc(this.db, pathValue));
          return snapshot.exists() ? normalize(snapshot.data()) : null;
        },
        write: (pathValue, value) => {
          writeStarted = true;
          transaction.set(doc(this.db, pathValue), value);
        },
      });
    });
  }
}

function binding(adapterIdV1, index) {
  const actions = {
    account_person_claims: 'detach',
    person_identity_evidence: 'restrictedRetention',
    public_projections_exports: 'erase',
  };
  return ad05Records.createCandidateAd05ExecutionBindingV1({
    authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null,
    authUidV2: 'owner-a', generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 9, lifecycleStateV1: 'deleting',
    internalJobId: 'job_identity_emulator',
    taskEffectIdV1: `identity_effect_${index}`,
    taskEffectFingerprintV1: String(index + 1).repeat(64),
    adapterIdV1, adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: adapterIdV1 === 'account_person_claims' ?
      'transactional-document-v1' : 'unsupported-v1',
    policyDecisionIdV1: `retention.${adapterIdV1}`,
    policyVersionV1: 'synthetic_policy_v1', actionV1: actions[adapterIdV1],
    sourceManifestIdV1: `emulator_source_manifest_${index}`,
    sourceManifestVersionV1: 'emulator_source_v1',
  });
}

function packetFixture() {
  const bindings = records.ad05bIdentityAdapterIdsV1.map(binding);
  const trustedClaimRecord = {
    schemaVersion: 1, adapterIdV1: 'account_person_claims',
    sourceSchemaIdV1: 'account_person_claim_v1', sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1: 'privateAccountPersonClaims/claim-a',
    sourceRecordVersionV1: 'claim_record_v1',
    provenanceIdV1: 'verified_claim_provenance_a',
    associationScopeHashV1: official.canonicalSha256('association-a'),
    classificationV1: 'applicable',
  };
  const itemCore = {...trustedClaimRecord,
    itemIdV1: ad05Inventory.deterministicAd05ManifestItemIdV1({
      binding: bindings[0], record: trustedClaimRecord,
    }), ordinalV1: 0,
    sourceDocumentPathHashV1:
      official.canonicalSha256(trustedClaimRecord.sourceDocumentPathV1)};
  const item = ad05Records.parseCandidateAd05ManifestItemV1({...itemCore,
    itemFingerprintV1: ad05Records.ad05ManifestItemFingerprintV1(itemCore)});
  const sourceManifestCore = {
    schemaVersion: 1, manifestIdV1: bindings[0].sourceManifestIdV1,
    manifestVersionV1: bindings[0].sourceManifestVersionV1,
    bindingFingerprintV1: bindings[0].bindingFingerprintV1,
    adapterIdV1: 'account_person_claims',
    inventorySourceIdV1: 'emulator_claim_inventory',
    inventorySourceVersionV1: bindings[0].sourceManifestVersionV1,
    referenceCoverageEvidenceIdV1: 'emulator_claim_coverage',
    completeV1: true, sealedV1: true, itemCountV1: 1, itemsV1: [item],
  };
  const claimSourceManifest = ad05Records.parseCandidateAd05SealedManifestV1({
    ...sourceManifestCore,
    manifestFingerprintV1: ad05Records.ad05ManifestFingerprintV1(sourceManifestCore),
  });
  const presentClasses = new Set([
    'accountPersonClaim', 'personIdentityEvidenceCapsule',
    'personIdentityEvidenceMaterial', 'rawCompatibilityPath',
    'restoreReplayInput', 'rebuildInput',
  ]);
  const referencesV1 = [...presentClasses].map((referenceClassV1, ordinalV1) => {
    const adapterIdV1 = referenceClassV1 === 'accountPersonClaim' ?
      'account_person_claims' : referenceClassV1.startsWith('personIdentity') ?
        'person_identity_evidence' : 'public_projections_exports';
    const core = {
      schemaVersion: 1,
      referenceIdV1: referenceClassV1 === 'personIdentityEvidenceCapsule' ?
        'identity_evidence_capsule_a' : `emulator_reference_${ordinalV1}`,
      ordinalV1, adapterIdV1, referenceClassV1,
      authProjectIdV2: bindings[0].authProjectIdV2,
      authTenantIdV2: bindings[0].authTenantIdV2,
      authUidV2: bindings[0].authUidV2,
      authUidUtf16LeBase64UrlV1: bindings[0].authUidUtf16LeBase64UrlV1,
      generationHash: bindings[0].generationHash,
      acceptedLifecycleEpochV2: bindings[0].acceptedLifecycleEpochV2,
      associationIdV1: 'association-a', subjectIdV1: 'subject-a', claimIdV1: 'claim-a',
      sourceSystemIdV1: `emulator_source_${ordinalV1}`,
      sourceSchemaIdV1: referenceClassV1 === 'accountPersonClaim' ?
        item.sourceSchemaIdV1 : `emulator_schema_${ordinalV1}`,
      sourceSchemaVersionV1: referenceClassV1 === 'accountPersonClaim' ?
        item.sourceSchemaVersionV1 : 'schema_v1',
      referenceVersionV1: referenceClassV1 === 'accountPersonClaim' ?
        item.sourceRecordVersionV1 : `reference_v${ordinalV1}`,
      referencePathHashV1: referenceClassV1 === 'accountPersonClaim' ?
        item.sourceDocumentPathHashV1 : official.canonicalSha256(`private/${ordinalV1}`),
      provenanceIdV1: referenceClassV1 === 'accountPersonClaim' ?
        item.provenanceIdV1 : referenceClassV1 === 'personIdentityEvidenceCapsule' ?
          'identity_evidence_provenance_a' : `emulator_provenance_${ordinalV1}`,
      classificationV1: 'applicable', identityBearingV1: true,
      guaranteeV1: referenceClassV1 === 'accountPersonClaim' ?
        'transactionalRecordVersion' : 'versionOrProviderGuaranteeUnavailable',
    };
    return records.parseCandidateAd05bIdentityReferenceV1({...core,
      referenceFingerprintV1:
        records.ad05bIdentityReferenceFingerprintV1(core)});
  });
  const referenceCoverageV1 = records.ad05bIdentityReferenceClassesV1.map(
    (referenceClassV1, ordinalV1) => {
      const adapterIdV1 = referenceClassV1 === 'accountPersonClaim' ?
        'account_person_claims' : referenceClassV1.startsWith('personIdentity') ?
          'person_identity_evidence' : 'public_projections_exports';
      const core = {schemaVersion: 1, ordinalV1, adapterIdV1, referenceClassV1,
        authProjectIdV2: bindings[0].authProjectIdV2,
        authTenantIdV2: bindings[0].authTenantIdV2,
        authUidV2: bindings[0].authUidV2,
        authUidUtf16LeBase64UrlV1: bindings[0].authUidUtf16LeBase64UrlV1,
        generationHash: bindings[0].generationHash,
        acceptedLifecycleEpochV2: bindings[0].acceptedLifecycleEpochV2,
        associationIdV1: 'association-a', subjectIdV1: 'subject-a', claimIdV1: 'claim-a',
        coverageStateV1: presentClasses.has(referenceClassV1) ?
          'referencesEnumerated' : 'verifiedAbsent',
        scannedSourceIdV1: `scan_source_${ordinalV1}`,
        scannedSourceVersionV1: 'scan_v1',
        provenanceIdV1: `scan_provenance_${ordinalV1}`,
        evidenceIdV1: `scan_evidence_${ordinalV1}`, completeV1: true};
      return records.parseCandidateAd05bIdentityReferenceCoverageV1({...core,
        coverageFingerprintV1:
          records.ad05bIdentityReferenceCoverageFingerprintV1(core)});
    });
  return {bindings, claimSourceManifest, item, referencesV1, referenceCoverageV1};
}

function verification(input) {
  const core = {schemaVersion: 1,
    referenceSetFingerprintV1: input.referenceSetFingerprintV1,
    referenceCoverageSetFingerprintV1: input.referenceCoverageSetFingerprintV1,
    claimSourceManifestFingerprintV1:
      input.claimSourceManifestV1.manifestFingerprintV1,
    associationIdV1: input.associationIdV1, subjectIdV1: input.subjectIdV1,
    claimIdV1: input.claimIdV1, claimReferenceClosureVerifiedV1: true,
    rawPathCoverageVerifiedV1: true, restoreSuppressionCoverageVerifiedV1: true,
    completeV1: true, verifierIdV1: 'emulator_reference_verifier',
    verificationEvidenceIdV1: 'emulator_reference_evidence',
    verifiedAtSecV1: 1_800_000_000};
  return {...core, verificationFingerprintV1:
    mechanics.ad05bIdentityReferenceVerificationFingerprintV1(core)};
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect', firestore: {rules},
  });
});
test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all AD05-B suppression and reference-manifest records deny every client', async () => {
  for (const context of [testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'})]) {
    const db = context.firestore();
    for (const pathValue of [
      'accountDeletionJobsV1/job-a/ad05IdentityReferenceManifestsV1/manifest-a',
      'accountDeletionJobsV1/job-a/ad05IdentitySuppressionsV1/suppression-a',
    ]) {
      await assertFails(getDoc(doc(db, pathValue)));
      await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
    }
  }
});

test('real Firestore transactions seal suppression then exact-once detach one account claim', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorRepository(db);
    const packet = packetFixture();
    await setDoc(doc(db, ad05Records.ad05ManifestPathV1(packet.bindings[0])),
      packet.claimSourceManifest);
    const seal = await mechanics.sealTestOnlySyntheticCandidateAd05bIdentitySuppressionV1({
      repository, syntheticPolicyV1: ad05Fixture.testOnlySyntheticApprovedPolicy,
      bindingsV1: packet.bindings, claimSourceManifestV1: packet.claimSourceManifest,
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
        schemaVersion: 1, inventorySourceIdV1: 'emulator_identity_inventory',
        inventorySourceVersionV1: 'emulator_identity_inventory_v1',
        completeV1: true, continuationTokenV1: null,
        referenceCoverageV1: packet.referenceCoverageV1,
        referencesV1: packet.referencesV1,
      })},
      verifierV1: {verifyIdentityReferencesV1: async (input) => verification(input)},
    });
    assert.equal(seal.stateV1, 'sealed');
    await setDoc(doc(db, packet.item.sourceDocumentPathV1), {
      schemaVersion: 1, authProjectIdV2: packet.bindings[0].authProjectIdV2,
      authTenantIdV2: null, associationIdV1: 'association-a', subjectIdV1: 'subject-a',
      claimIdV1: 'claim-a', claimKindV1: 'player',
      claimVerificationStateV1: 'verified',
      claimProvenanceIdV1: 'verified_claim_provenance_a',
      identityEvidenceIdV1: 'identity_evidence_capsule_a',
      identityEvidenceProvenanceIdV1: 'identity_evidence_provenance_a',
      publicationPolicyDecisionIdV1: 'retention.public_projections_exports',
      fieldLevelPublicationPolicyIdV1: 'test_field_publication_policy_a',
      fieldLevelPublicationPolicyVersionV1: 'test_field_publication_v1',
      fieldLevelPublicationPolicyProvenanceIdV1:
        'test_field_publication_provenance_a',
      minorStatusV1: 'unknown', accountAssociationStateV1: 'active',
      authUidV2: packet.bindings[0].authUidV2,
      authUidUtf16LeBase64UrlV1: packet.bindings[0].authUidUtf16LeBase64UrlV1,
      generationHash: packet.bindings[0].generationHash,
      accountLifecycleEpochV2: packet.bindings[0].acceptedLifecycleEpochV2,
      suppressionFingerprintV1: null, identityReferenceManifestFingerprintV1: null,
      recordVersionV1: 'claim_record_v1',
    });
    const outcomes = await Promise.all([1, 2].map(() =>
      mechanics.applyTestOnlySyntheticCandidateAd05bClaimDetachmentV1({
        repository, bindingV1: packet.bindings[0],
        claimSourceManifestV1: packet.claimSourceManifest, itemV1: packet.item,
        identityManifestV1: seal.manifestV1, suppressionV1: seal.suppressionV1,
        sourceRecordVersionAfterV1: 'claim_record_v2',
        committedAtSecV1: 1_800_000_002,
      })));
    assert.equal(outcomes.filter((entry) => entry.stateV1 === 'committed').length, 1);
    assert.equal(outcomes.filter((entry) => entry.stateV1 === 'replayed').length, 1);
    const claim = await repository.read(packet.item.sourceDocumentPathV1);
    assert.equal(claim.accountAssociationStateV1,
      'suppressedForDeletedGeneration');
    assert.equal(claim.authUidV2, null);
    assert.equal(claim.minorStatusV1, 'unknown');
  });
});
