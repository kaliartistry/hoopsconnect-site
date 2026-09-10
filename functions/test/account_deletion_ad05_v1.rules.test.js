'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  assertFails,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {runTransaction} = require('firebase/firestore');

const official = require('../lib/domain/official_stats_contract');
const records = require('../lib/account_deletion/ad05_records');
const effects = require('../lib/account_deletion/ad05_effects');
const inventory = require('../lib/account_deletion/ad05_inventory');

const rules = fs.readFileSync(path.resolve(
  __dirname, 'fixtures/account_deletion_ad05_v1/firestore.rules',
), 'utf8');

let testEnv;

function normalize(value) {
  if (value === null || value === undefined) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  if (Array.isArray(value)) return value.map(normalize);
  if (typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, normalize(entry)]));
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
          if (writeStarted) throw new Error('AD05 emulator read after write');
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

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-hoopsconnect',
    firestore: {rules},
  });
});
test.beforeEach(async () => testEnv.clearFirestore());
test.after(async () => testEnv.cleanup());

test('all private AD05 manifest, item receipt, and continuation records deny client access', async () => {
  for (const context of [
    testEnv.unauthenticatedContext(),
    testEnv.authenticatedContext('owner-a'),
    testEnv.authenticatedContext('admin-a', {role: 'superAdmin'}),
  ]) {
    const db = context.firestore();
    for (const pathValue of [
      'accountDeletionJobsV1/job_one/ad05ManifestsV1/manifest_one',
      'accountDeletionJobsV1/job_one/ad05ItemReceiptsV1/item_one',
      'accountDeletionJobsV1/job_one/ad05ContinuationsV1/effect_one',
    ]) {
      await assertFails(getDoc(doc(db, pathValue)));
      await assertFails(setDoc(doc(db, pathValue), {schemaVersion: 1}));
    }
  }
});

test('real Firestore transaction race seals one canonical manifest and rejects conflicting contents', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorRepository(db);
    const manifestIdV1 = inventory.deterministicAd05SourceManifestIdV1({
      internalJobId: 'job_manifest_race',
      taskEffectIdV1: 'effect_manifest_race',
      adapterIdV1: 'user_profile',
      inventorySourceIdV1: 'trusted_profile_inventory',
      inventorySourceVersionV1: 'inventory_v1',
    });
    const binding = records.createCandidateAd05ExecutionBindingV1({
      authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null,
      authUidV2: 'owner-a', generationHash: 'a'.repeat(64),
      acceptedLifecycleEpochV2: 8, lifecycleStateV1: 'deleting',
      internalJobId: 'job_manifest_race',
      taskEffectIdV1: 'effect_manifest_race',
      taskEffectFingerprintV1: 'b'.repeat(64),
      adapterIdV1: 'user_profile',
      adapterVersionV1: 'account-deletion-adapter-v1',
      effectVersionV1: 'transactional-document-v1',
      policyDecisionIdV1: 'retention.user_profile',
      policyVersionV1: 'synthetic_policy_v1', actionV1: 'erase',
      sourceManifestIdV1: manifestIdV1,
      sourceManifestVersionV1: 'inventory_v1',
    });
    const sourceFor = (sourceDocumentPathV1) => ({
      adapterIdV1: 'user_profile',
      enumerateBoundRecordsV1: async () => ({
        schemaVersion: 1,
        inventorySourceIdV1: 'trusted_profile_inventory',
        inventorySourceVersionV1: 'inventory_v1',
        completeV1: true,
        continuationTokenV1: null,
        referenceCoverageVerifiedV1: true,
        referenceCoverageEvidenceIdV1: 'independent_reference_scan_v1',
        recordsV1: [{
          schemaVersion: 1, adapterIdV1: 'user_profile',
          sourceSchemaIdV1: 'profile_v1', sourceSchemaVersionV1: 'schema_v1',
          sourceDocumentPathV1, sourceRecordVersionV1: 'record_v1',
          provenanceIdV1: 'verified_claim_v1',
          associationScopeHashV1: official.canonicalSha256('association-a'),
          classificationV1: 'applicable',
        }],
      }),
    });

    const results = await Promise.allSettled([
      inventory.sealCandidateAd05TrustedInventoryManifestV1({
        repository, binding, source: sourceFor('users/owner-a'),
      }),
      inventory.sealCandidateAd05TrustedInventoryManifestV1({
        repository, binding, source: sourceFor('users/conflicting-owner-a'),
      }),
    ]);
    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.equal(rejected[0].reason.codeV1, 'AD05_BINDING_CONFLICT');

    const canonical = records.parseCandidateAd05SealedManifestV1(
      await repository.read(records.ad05ManifestPathV1(binding)),
    );
    assert.equal(canonical.manifestFingerprintV1,
      fulfilled[0].value.manifestV1.manifestFingerprintV1);
    assert.equal(canonical.itemsV1.length, 1);
    assert.ok([
      'users/owner-a', 'users/conflicting-owner-a',
    ].includes(canonical.itemsV1[0].sourceDocumentPathV1));
  });
});

test('real Firestore transaction race commits one logical source effect and one immutable receipt', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const repository = new EmulatorRepository(db);
    const bindingCore = {
      authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a',
      generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
      lifecycleStateV1: 'deleting', internalJobId: 'job_race',
      taskEffectIdV1: 'effect_race', taskEffectFingerprintV1: 'b'.repeat(64),
      adapterIdV1: 'user_profile', adapterVersionV1: 'account-deletion-adapter-v1',
      effectVersionV1: 'transactional-document-v1',
      policyDecisionIdV1: 'retention.user_profile', policyVersionV1: 'synthetic_policy_v1',
      actionV1: 'erase', sourceManifestIdV1: 'manifest_race',
      sourceManifestVersionV1: 'inventory_v1',
    };
    const binding = records.createCandidateAd05ExecutionBindingV1(bindingCore);
    const trustedRecord = {schemaVersion: 1,
      adapterIdV1: 'user_profile', sourceSchemaIdV1: 'profile_v1',
      sourceSchemaVersionV1: 'schema_v1', sourceDocumentPathV1: 'users/owner-a',
      sourceRecordVersionV1: 'record_v1', provenanceIdV1: 'verified_claim_v1',
      associationScopeHashV1: official.canonicalSha256('association-a'),
      classificationV1: 'applicable'};
    const itemCore = {...trustedRecord,
      itemIdV1: inventory.deterministicAd05ManifestItemIdV1({binding,
        record: trustedRecord}), ordinalV1: 0,
      sourceDocumentPathHashV1: official.canonicalSha256('users/owner-a')};
    const item = records.parseCandidateAd05ManifestItemV1({...itemCore,
      itemFingerprintV1: records.ad05ManifestItemFingerprintV1(itemCore)});
    const manifestCore = {schemaVersion: 1,
      manifestIdV1: binding.sourceManifestIdV1,
      manifestVersionV1: binding.sourceManifestVersionV1,
      bindingFingerprintV1: binding.bindingFingerprintV1,
      adapterIdV1: binding.adapterIdV1,
      inventorySourceIdV1: 'trusted_profile_inventory',
      inventorySourceVersionV1: binding.sourceManifestVersionV1,
      referenceCoverageEvidenceIdV1: 'independent_reference_scan_v1',
      completeV1: true, sealedV1: true, itemCountV1: 1, itemsV1: [item]};
    const manifest = records.parseCandidateAd05SealedManifestV1({...manifestCore,
      manifestFingerprintV1: records.ad05ManifestFingerprintV1(manifestCore)});
    await setDoc(doc(db, records.ad05ManifestPathV1(binding)), manifest);
    await setDoc(doc(db, item.sourceDocumentPathV1), {
      schemaVersion: 1, recordVersionV1: 'record_v1', mutationCountV1: 0,
    });
    const effect = {
      sourceRecordVersionV1: (value) => value.recordVersionV1,
      mutateBoundSourceV1: ({transaction}) => {
        transaction.writeSourceV1({...transaction.sourceRecordBeforeV1,
          recordVersionV1: 'record_v2', mutationCountV1: 1});
        return {schemaVersion: 1, sourceRecordVersionAfterV1: 'record_v2',
          evidenceCodeV1: 'profile_erased_atomically'};
      },
    };
    const outcomes = await Promise.all([1, 2].map(() =>
      effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding,
        manifest, item, effect, committedAtSecV1: 1_800_000_000})));
    assert.equal(outcomes.filter((outcome) => outcome.stateV1 === 'committed').length, 1);
    assert.equal(outcomes.filter((outcome) => outcome.stateV1 === 'replayed').length, 1);
    assert.equal((await repository.read(item.sourceDocumentPathV1)).mutationCountV1, 1);
    const receiptPath = records.ad05ItemReceiptPathV1({binding, itemIdV1: item.itemIdV1});
    assert.equal((await repository.read(receiptPath)).receiptFingerprintV1,
      outcomes[0].receiptV1.receiptFingerprintV1);
  });
});
