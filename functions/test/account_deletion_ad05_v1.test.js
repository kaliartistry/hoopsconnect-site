'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const contract = require('../lib/domain/account_deletion_contract');
const official = require('../lib/domain/official_stats_contract');
const records = require('../lib/account_deletion/ad05_records');
const inventory = require('../lib/account_deletion/ad05_inventory');
const effects = require('../lib/account_deletion/ad05_effects');
const adapters = require('../lib/account_deletion/ad05_adapters');

const fixture = JSON.parse(fs.readFileSync(path.resolve(
  __dirname, '../../contracts/account_deletion/ad05/adapter_fixtures_v1.json',
), 'utf8'));
const normativePolicy = JSON.parse(fs.readFileSync(path.resolve(
  __dirname, '../../contracts/account_deletion/v1/retention_policy_registry.json',
), 'utf8'));
const NOW = 1_800_000_000;

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

class MemoryRepository {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries).map(([key, value]) => [key, clone(value)]));
    this.mutationCount = 0;
  }

  async read(pathValue) {
    return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
  }

  async runTransaction(operation) {
    const staged = new Map();
    let writeStarted = false;
    const result = await operation({
      read: async (pathValue) => {
        if (writeStarted) throw new Error('AD05 read after write');
        return this.values.has(pathValue) ? clone(this.values.get(pathValue)) : null;
      },
      write: (pathValue, value) => {
        writeStarted = true;
        staged.set(pathValue, clone(value));
      },
    });
    for (const [key, value] of staged) {
      this.values.set(key, value);
      this.mutationCount += 1;
    }
    return result;
  }
}

function binding(overrides = {}) {
  const core = {
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: null,
    authUidV2: 'owner-a',
    generationHash: 'a'.repeat(64),
    acceptedLifecycleEpochV2: 8,
    lifecycleStateV1: 'deleting',
    internalJobId: 'job_ad05_one',
    taskEffectIdV1: 'effect_ad05_one',
    taskEffectFingerprintV1: 'b'.repeat(64),
    adapterIdV1: 'user_profile',
    adapterVersionV1: 'account-deletion-adapter-v1',
    effectVersionV1: 'transactional-document-v1',
    policyDecisionIdV1: 'retention.user_profile',
    policyVersionV1: 'synthetic_policy_v1',
    actionV1: 'erase',
    sourceManifestIdV1: inventory.deterministicAd05SourceManifestIdV1({
      internalJobId: 'job_ad05_one',
      taskEffectIdV1: 'effect_ad05_one',
      adapterIdV1: 'user_profile',
      inventorySourceIdV1: 'trusted_profile_inventory',
      inventorySourceVersionV1: 'inventory_v1',
    }),
    sourceManifestVersionV1: 'inventory_v1',
    ...overrides,
  };
  return records.createCandidateAd05ExecutionBindingV1(core);
}

function trustedRecords(count = 2) {
  return Array.from({length: count}, (_, index) => ({
    schemaVersion: 1,
    adapterIdV1: 'user_profile',
    sourceSchemaIdV1: 'profile_v1',
    sourceSchemaVersionV1: 'schema_v1',
    sourceDocumentPathV1: `users/private-${index}`,
    sourceRecordVersionV1: 'record_v1',
    provenanceIdV1: `verified_claim_${index}`,
    associationScopeHashV1: official.canonicalSha256(`association-${index}`),
    classificationV1: 'applicable',
  }));
}

async function manifestFor(currentBinding = binding(), recordValues = trustedRecords()) {
  return inventory.buildCandidateAd05SealedManifestV1({
    binding: currentBinding,
    source: {
      adapterIdV1: 'user_profile',
      enumerateBoundRecordsV1: async ({binding: bound, limitV1}) => {
        assert.equal(bound.bindingFingerprintV1, currentBinding.bindingFingerprintV1);
        assert.equal(limitV1, 100);
        return {
          schemaVersion: 1,
          inventorySourceIdV1: 'trusted_profile_inventory',
          inventorySourceVersionV1: 'inventory_v1',
          completeV1: true,
          continuationTokenV1: null,
          referenceCoverageVerifiedV1: true,
          referenceCoverageEvidenceIdV1: 'independent_reference_scan_v1',
          recordsV1: recordValues,
        };
      },
    },
  });
}

function seedRepository(manifest, another = true) {
  const entries = Object.fromEntries(manifest.itemsV1.map((item) => [
    item.sourceDocumentPathV1,
    {schemaVersion: 1, recordVersionV1: 'record_v1', ownerUid: 'owner-a', deleted: false},
  ]));
  if (another) {
    entries['users/unrelated-association'] = {
      schemaVersion: 1, recordVersionV1: 'record_v1', ownerUid: 'owner-b', deleted: false,
    };
  }
  return new MemoryRepository(entries);
}

function documentEffect(counter) {
  return {
    sourceRecordVersionV1: (value) => value.recordVersionV1,
    mutateBoundSourceV1: ({binding: currentBinding, transaction}) => {
      assert.equal(currentBinding.authUidV2, 'owner-a');
      counter.calls += 1;
      transaction.writeSourceV1({
        ...transaction.sourceRecordBeforeV1,
        recordVersionV1: 'record_v2',
        deleted: true,
      });
      return {
        schemaVersion: 1,
        sourceRecordVersionAfterV1: 'record_v2',
        evidenceCodeV1: 'profile_erased_atomically',
      };
    },
  };
}

function assertAd05Code(code) {
  return (error) => error && error.codeV1 === code;
}

test('registry is the exact ordered 27-row AD01 contract with unique decisions and T/V/E/D/R', () => {
  const parsed = adapters.validateCandidateAd05AdapterRegistryV1(fixture.adapterRows);
  assert.deepEqual(parsed, adapters.candidateAd05AdapterRegistryV1);
  assert.equal(parsed.length, 27);
  assert.deepEqual(parsed.map((row) => row.adapterIdV1), contract.accountDeletionAdapterIds);
  assert.equal(new Set(parsed.map((row) => row.policyDecisionIdV1)).size, 27);
  assert.deepEqual(new Set(parsed.map((row) => row.protectionFamilyV1)),
    new Set(['T', 'V', 'E', 'D', 'R']));
  assert.equal(parsed.every((row) => ['T', 'R'].includes(row.protectionFamilyV1) ||
    row.mechanicalSupportV1 === 'unsupported'), true);
  for (const mutation of [
    [...fixture.adapterRows, fixture.adapterRows[0]],
    fixture.adapterRows.slice(0, -1),
    fixture.adapterRows.map((row, index) => index === 0 ? {...row, adapterIdV1: 'future'} : row),
    fixture.adapterRows.map((row, index) => index === 0 ? {...row, futureField: true} : row),
  ]) assert.throws(() => adapters.validateCandidateAd05AdapterRegistryV1(mutation),
    assertAd05Code('AD05_INVALID_RECORD'));
});

test('normative pending registry creates 27 dormant wrappers with zero mutation and no terminal result', async () => {
  adapters.validateNormativeAd05PolicyRegistryV1(normativePolicy);
  assert.throws(() => adapters.validateNormativeAd05PolicyRegistryV1({
    ...normativePolicy, unknownFutureSchema: true,
  }), assertAd05Code('AD05_INVALID_RECORD'));
  assert.equal(fixture.normativePolicy.policyVersion, null);
  assert.equal(fixture.normativePolicy.activationApproved, false);
  const wrappers = adapters.createDormantCandidateAd05AdaptersV1();
  assert.equal(wrappers.length, 27);
  let mutations = 0;
  for (const adapter of wrappers) {
    const input = {
      scope: {authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a'},
      generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
      internalJobId: 'job_ad05_one', effectIdV1: 'effect_ad05_one',
      policyVersion: 'pending_policy_v1',
    };
    const inspected = await adapter.inspectEffectV1(input);
    const applied = await adapter.applyEffectV1(input);
    assert.equal(inspected.state, 'blocked');
    assert.equal(applied.state, 'blocked');
    assert.equal(inspected.policyDecisionId, `retention.${adapter.adapterIdV1}`);
    assert.equal(contract.isDeletionComplete({
      schemaVersion: 1, authAbsent: true,
      checkpoints: {dataDispositionVerified: true, publicPrivacyVerified: true,
        custodyRecorded: true, providerDispositionRecorded: true,
        restoreSuppressionDurable: true},
      requiredAdapterIds: contract.accountDeletionAdapterIds,
      adapterResults: wrappers.map(() => inspected), providerCheckpoints: [],
      unknownRequiredState: false,
    }), false);
  }
  assert.equal(mutations, 0);
});

test('strict bindings include exact project, tenant, UID bytes, generation, lifecycle, job, task, effect, adapter, policy and manifest', () => {
  const current = binding();
  assert.equal(current.authUidUtf16LeBase64UrlV1,
    contract.firebaseUidUtf16LeBase64Url('owner-a'));
  for (const [field, value] of [
    ['authProjectIdV2', 'other-project'], ['authTenantIdV2', 'tenant-a'],
    ['authUidV2', 'owner-b'], ['generationHash', 'c'.repeat(64)],
    ['acceptedLifecycleEpochV2', 9], ['lifecycleStateV1', 'deleted'],
    ['internalJobId', 'job_other'],
    ['taskEffectIdV1', 'effect_other'], ['taskEffectFingerprintV1', 'd'.repeat(64)],
    ['effectVersionV1', 'transactional-document-v2'], ['policyVersionV1', 'policy_v2'],
    ['sourceManifestVersionV1', 'inventory_v2'],
  ]) {
    assert.throws(() => records.parseCandidateAd05ExecutionBindingV1({...current, [field]: value}),
      (error) => error && ['AD05_BINDING_CONFLICT', 'AD05_INVALID_RECORD'].includes(error.codeV1));
  }
});

test('trusted inventory seals deterministically and rejects missing provenance, unknown schema, incomplete coverage, duplicates, and caller-like extras', async () => {
  const current = binding();
  const first = await manifestFor(current);
  const second = await manifestFor(current, [...trustedRecords()].reverse());
  assert.equal(first.manifestFingerprintV1, second.manifestFingerprintV1);
  assert.deepEqual(first.itemsV1.map((item) => item.itemIdV1),
    second.itemsV1.map((item) => item.itemIdV1));
  for (const patch of [
    {provenanceIdV1: null},
    {classificationV1: 'unknownSchema'},
    {classificationV1: 'unclassified'},
  ]) {
    await assert.rejects(() => manifestFor(current, [{...trustedRecords(1)[0], ...patch}]),
      assertAd05Code('AD05_INCOMPLETE_INVENTORY'));
  }
  await assert.rejects(() => inventory.buildCandidateAd05SealedManifestV1({
    binding: current,
    source: {adapterIdV1: 'user_profile', enumerateBoundRecordsV1: async () => ({
      schemaVersion: 1, inventorySourceIdV1: 'trusted_profile_inventory',
      inventorySourceVersionV1: 'inventory_v1', completeV1: true,
      continuationTokenV1: null, referenceCoverageVerifiedV1: false,
      referenceCoverageEvidenceIdV1: null, recordsV1: [],
    })},
  }), assertAd05Code('AD05_INCOMPLETE_INVENTORY'));
  await assert.rejects(() => manifestFor(current, [trustedRecords(1)[0], trustedRecords(1)[0]]),
    assertAd05Code('AD05_INCOMPLETE_INVENTORY'));
  await assert.rejects(() => manifestFor(current,
    [{...trustedRecords(1)[0], callerEmail: 'not-authority@example.com'}]),
  assertAd05Code('AD05_INVALID_RECORD'));
});

test('every manifest consumer rejects adversarially re-fingerprinted ID and version drift', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const resign = (patch) => {
    const core = {...manifest, ...patch};
    delete core.manifestFingerprintV1;
    return records.parseCandidateAd05SealedManifestV1({...core,
      manifestFingerprintV1: records.ad05ManifestFingerprintV1(core)});
  };
  const wrongId = resign({manifestIdV1: 'manifest_adversarial'});
  const wrongVersion = resign({manifestVersionV1: 'inventory_v2',
    inventorySourceVersionV1: 'inventory_v2'});
  for (const candidate of [wrongId, wrongVersion]) {
    assert.throws(() => effects.initialCandidateAd05ContinuationV1({
      binding: current, manifest: candidate,
    }), assertAd05Code('AD05_BINDING_CONFLICT'));
    const continuation = effects.initialCandidateAd05ContinuationV1({
      binding: current, manifest,
    });
    await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentPageV1({
      repository: seedRepository(manifest), binding: current, manifest: candidate,
      continuation, effect: documentEffect({calls: 0}), committedAtSecV1: NOW,
    }), assertAd05Code('AD05_BINDING_CONFLICT'));
    const receiptSet = {schemaVersion: 1,
      bindingFingerprintV1: current.bindingFingerprintV1,
      manifestFingerprintV1: candidate.manifestFingerprintV1,
      itemCountV1: candidate.itemCountV1,
      receiptSetFingerprintV1: 'c'.repeat(64), latestReceiptCommittedAtSecV1: 0};
    await assert.rejects(() => inventory.verifyCandidateAd05RemainingReferencesV1({
      binding: current, manifest: candidate, receiptSet,
      verifier: {verifyRemainingReferencesV1: async () => {
        throw new Error('must not run');
      }},
    }), assertAd05Code('AD05_BINDING_CONFLICT'));
    await assert.rejects(() => effects.finalizeCandidateAd05TransactionalAdapterV1({
      repository: seedRepository(manifest), binding: current, manifest: candidate,
      remainingReferenceVerifier: {verifyRemainingReferencesV1: async () => {
        throw new Error('must not run');
      }},
      finalVerifier: {verifyFinalStateV1: async () => { throw new Error('must not run'); }},
    }), assertAd05Code('AD05_BINDING_CONFLICT'));
  }
  const inconsistentCore = {...manifest, manifestVersionV1: 'inventory_v2'};
  delete inconsistentCore.manifestFingerprintV1;
  assert.throws(() => records.parseCandidateAd05SealedManifestV1({...inconsistentCore,
    manifestFingerprintV1: records.ad05ManifestFingerprintV1(inconsistentCore)}),
  assertAd05Code('AD05_BINDING_CONFLICT'));
});

test('transactional effect commits source mutation and immutable receipt exactly once across replay and lost response', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  const counter = {calls: 0};
  const input = {repository, binding: current, item: manifest.itemsV1[0],
    effect: documentEffect(counter), committedAtSecV1: NOW};
  const first = await effects.applyCandidateAd05TransactionalDocumentItemV1(input);
  const second = await effects.applyCandidateAd05TransactionalDocumentItemV1(
    {...input, committedAtSecV1: NOW + 90});
  assert.equal(first.stateV1, 'committed');
  assert.equal(second.stateV1, 'replayed');
  assert.equal(counter.calls, 1);
  assert.deepEqual(await repository.read(manifest.itemsV1[0].sourceDocumentPathV1),
    {schemaVersion: 1, recordVersionV1: 'record_v2', ownerUid: 'owner-a', deleted: true});
  assert.deepEqual(await repository.read('users/unrelated-association'),
    {schemaVersion: 1, recordVersionV1: 'record_v1', ownerUid: 'owner-b', deleted: false});
  assert.equal(second.receiptV1.receiptFingerprintV1, first.receiptV1.receiptFingerprintV1);
});

test('classification-aware execution mutates applicable items only and receipts notApplicable without a source write', async () => {
  const current = binding();
  const candidates = trustedRecords(2);
  candidates[1] = {...candidates[1], classificationV1: 'notApplicable'};
  const manifest = await manifestFor(current, candidates);
  const repository = seedRepository(manifest);
  const beforeNotApplicable = await repository.read(candidates[1].sourceDocumentPathV1);
  const counter = {calls: 0};
  const continuation = await effects.applyCandidateAd05TransactionalDocumentPageV1({
    repository, binding: current, manifest,
    continuation: effects.initialCandidateAd05ContinuationV1({binding: current, manifest}),
    effect: documentEffect(counter), committedAtSecV1: NOW,
  });
  assert.equal(continuation.completeV1, true);
  assert.equal(counter.calls, 1);
  const notApplicableItem = manifest.itemsV1.find((item) =>
    item.classificationV1 === 'notApplicable');
  assert.deepEqual(await repository.read(notApplicableItem.sourceDocumentPathV1),
    beforeNotApplicable);
  const receipt = await repository.read(records.ad05ItemReceiptPathV1({
    binding: current, itemIdV1: notApplicableItem.itemIdV1,
  }));
  assert.equal(receipt.outcomeV1, 'notApplicableVerified');
  assert.equal(receipt.sourceRecordVersionAfterV1, receipt.sourceRecordVersionBeforeV1);
});

test('notApplicable policy rejects applicable items before mutation and applicable effects must advance source version', async () => {
  const notApplicableBinding = binding({actionV1: 'notApplicable'});
  await assert.rejects(() => manifestFor(notApplicableBinding, trustedRecords(1)),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  const applicableRecord = trustedRecords(1)[0];
  const applicableItemCore = {...applicableRecord,
    itemIdV1: inventory.deterministicAd05ManifestItemIdV1({
      binding: notApplicableBinding, record: applicableRecord,
    }),
    ordinalV1: 0,
    sourceDocumentPathHashV1: official.canonicalSha256(
      applicableRecord.sourceDocumentPathV1,
    )};
  const applicableItem = records.parseCandidateAd05ManifestItemV1({
    ...applicableItemCore,
    itemFingerprintV1: records.ad05ManifestItemFingerprintV1(applicableItemCore),
  });
  const policyMismatchRepository = new MemoryRepository({
    [applicableItem.sourceDocumentPathV1]: {
      schemaVersion: 1, recordVersionV1: 'record_v1', deleted: false,
    },
  });
  const policyMismatchCounter = {calls: 0};
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentItemV1({
    repository: policyMismatchRepository, binding: notApplicableBinding,
    item: applicableItem, effect: documentEffect(policyMismatchCounter),
    committedAtSecV1: NOW,
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
  assert.equal(policyMismatchCounter.calls, 0);
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  let calls = 0;
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentItemV1({
    repository, binding: current, item: manifest.itemsV1[0], committedAtSecV1: NOW,
    effect: {sourceRecordVersionV1: (value) => value.recordVersionV1,
      mutateBoundSourceV1: ({transaction}) => {
        calls += 1;
        transaction.writeSourceV1({...transaction.sourceRecordBeforeV1, deleted: true});
        return {schemaVersion: 1, sourceRecordVersionAfterV1: 'record_v1',
          evidenceCodeV1: 'invalid_unversioned_write'};
      }},
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
  assert.equal(calls, 1);
  assert.equal((await repository.read(manifest.itemsV1[0].sourceDocumentPathV1)).deleted, false);
  assert.equal(await repository.read(records.ad05ItemReceiptPathV1({
    binding: current, itemIdV1: manifest.itemsV1[0].itemIdV1,
  })), null);
});

test('same receipt key with changed binding, action, version, policy, payload, or scope conflicts and cannot overwrite receipt', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  const counter = {calls: 0};
  await effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding: current,
    item: manifest.itemsV1[0], effect: documentEffect(counter), committedAtSecV1: NOW});
  const receiptPath = records.ad05ItemReceiptPathV1({binding: current,
    itemIdV1: manifest.itemsV1[0].itemIdV1});
  const originalReceipt = await repository.read(receiptPath);
  for (const changed of [
    binding({authUidV2: 'owner-b'}),
    binding({actionV1: 'detach'}),
    binding({effectVersionV1: 'transactional-document-v2'}),
    binding({policyVersionV1: 'synthetic_policy_v2'}),
  ]) {
    await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentItemV1({
      repository, binding: changed, item: manifest.itemsV1[0], effect: documentEffect(counter),
      committedAtSecV1: NOW + 1,
    }), assertAd05Code('AD05_BINDING_CONFLICT'));
  }
  const changedItem = {...manifest.itemsV1[0], sourceRecordVersionV1: 'record_changed'};
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentItemV1({
    repository, binding: current, item: changedItem, effect: documentEffect(counter),
    committedAtSecV1: NOW + 1,
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
  assert.deepEqual(await repository.read(receiptPath), originalReceipt);
  assert.equal(counter.calls, 1);
});

test('crash before transaction and after commit resumes without skipping an uncommitted item', async () => {
  const current = binding();
  const manifest = await manifestFor(current);
  const repository = seedRepository(manifest);
  const counter = {calls: 0};
  const initial = effects.initialCandidateAd05ContinuationV1({binding: current, manifest});
  assert.equal(initial.nextItemIdV1, manifest.itemsV1[0].itemIdV1);
  assert.equal(counter.calls, 0, 'crash before invocation changes nothing');
  let simulatedCrash = true;
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentPageV1({
    repository, binding: current, manifest, continuation: initial,
    effect: documentEffect(counter), committedAtSecV1: NOW, pageLimitV1: 2,
    afterItemCommitV1: () => {
      if (simulatedCrash) { simulatedCrash = false; throw new Error('lost response'); }
    },
  }), /lost response/);
  assert.equal(counter.calls, 1);
  const resumed = await effects.applyCandidateAd05TransactionalDocumentPageV1({
    repository, binding: current, manifest, continuation: initial,
    effect: documentEffect(counter), committedAtSecV1: NOW + 60, pageLimitV1: 2,
  });
  assert.equal(resumed.completeV1, true);
  assert.equal(counter.calls, 2, 'committed first item replays; second item mutates once');
  const forged = {...initial, nextOrdinalV1: 1, committedItemCountV1: 1,
    nextItemIdV1: manifest.itemsV1[1].itemIdV1};
  assert.throws(() => records.parseCandidateAd05ContinuationV1(forged),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  const emptyRepository = seedRepository(manifest);
  const validLookingCore = {schemaVersion: 1,
    bindingFingerprintV1: current.bindingFingerprintV1,
    manifestFingerprintV1: manifest.manifestFingerprintV1,
    nextOrdinalV1: 1, nextItemIdV1: manifest.itemsV1[1].itemIdV1,
    committedItemCountV1: 1, completeV1: false};
  const validLookingForgery = records.parseCandidateAd05ContinuationV1({...validLookingCore,
    continuationFingerprintV1: records.ad05ContinuationFingerprintV1(validLookingCore)});
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentPageV1({
    repository: emptyRepository, binding: current, manifest,
    continuation: validLookingForgery, effect: documentEffect({calls: 0}),
    committedAtSecV1: NOW, pageLimitV1: 1,
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
});

test('empty reverse index is not absence proof and terminal result requires all receipts plus independent final verification', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  const verifierWith = (remainingReferenceCountV1) => ({
    verifyRemainingReferencesV1: async ({receiptSet}) => {
      const core = {schemaVersion: 1,
        manifestFingerprintV1: manifest.manifestFingerprintV1,
        receiptSetFingerprintV1: receiptSet.receiptSetFingerprintV1,
        latestReceiptCommittedAtSecV1: receiptSet.latestReceiptCommittedAtSecV1,
        inventorySourceIdV1: manifest.inventorySourceIdV1,
        inventorySourceVersionV1: manifest.inventorySourceVersionV1,
        independentSourceIdV1: 'full_reference_scan', independentSourceVersionV1: 'scan_v1',
        independenceProofIdV1: 'independent_scan_attestation_v1', completeV1: true,
        remainingReferenceCountV1, verifiedAtSecV1: NOW + 1,
        evidenceIdV1: 'reference_evidence_v1'};
      return {...core, evidenceFingerprintV1:
        inventory.ad05RemainingReferenceEvidenceFingerprintV1(core)};
    },
  });
  let finalCalls = 0;
  const finalVerifier = {verifyFinalStateV1: async ({receiptSet,
    remainingReferenceEvidence}) => {
    finalCalls += 1;
    const core = {schemaVersion: 1, manifestFingerprintV1: manifest.manifestFingerprintV1,
      receiptSetFingerprintV1: receiptSet.receiptSetFingerprintV1,
      remainingEvidenceFingerprintV1: remainingReferenceEvidence.evidenceFingerprintV1,
      sourceDispositionVerifiedV1: true, publicPrivacyVerifiedV1: true,
      restoreSuppressionVerifiedV1: true, unrelatedAssociationUnchangedV1: true,
      evidenceCodeV1: 'profile_erasure_finally_verified', evidenceIdV1: 'final_evidence_v1',
      verifiedAtSecV1: NOW + 2};
    return {...core, evidenceFingerprintV1: effects.ad05FinalVerificationFingerprintV1(core)};
  }};
  assert.equal(await effects.finalizeCandidateAd05TransactionalAdapterV1({repository,
    binding: current, manifest, remainingReferenceVerifier: verifierWith(0), finalVerifier}), null,
  'private chunk progress is null before item receipt');
  await effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding: current,
    item: manifest.itemsV1[0], effect: documentEffect({calls: 0}), committedAtSecV1: NOW});
  assert.equal(await effects.finalizeCandidateAd05TransactionalAdapterV1({repository,
    binding: current, manifest, remainingReferenceVerifier: verifierWith(1), finalVerifier}), null,
  'an empty reverse index cannot replace an independent scan that finds a reference');
  assert.equal(finalCalls, 0);
  const result = await effects.finalizeCandidateAd05TransactionalAdapterV1({repository,
    binding: current, manifest, remainingReferenceVerifier: verifierWith(0), finalVerifier});
  assert.equal(result.state, 'complete');
  assert.equal(result.policyDecisionId, 'retention.user_profile');
  assert.equal(finalCalls, 1);
});

test('independent and final evidence bind the exact receipt set and must postdate every commit', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  await effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding: current,
    item: manifest.itemsV1[0], effect: documentEffect({calls: 0}), committedAtSecV1: NOW});
  const remainingVerifier = (overrides = {}) => ({
    verifyRemainingReferencesV1: async ({receiptSet}) => {
      const core = {schemaVersion: 1,
        manifestFingerprintV1: manifest.manifestFingerprintV1,
        receiptSetFingerprintV1: receiptSet.receiptSetFingerprintV1,
        latestReceiptCommittedAtSecV1: receiptSet.latestReceiptCommittedAtSecV1,
        inventorySourceIdV1: manifest.inventorySourceIdV1,
        inventorySourceVersionV1: manifest.inventorySourceVersionV1,
        independentSourceIdV1: 'full_reference_scan', independentSourceVersionV1: 'scan_v1',
        independenceProofIdV1: 'independent_scan_attestation_v1', completeV1: true,
        remainingReferenceCountV1: 0, verifiedAtSecV1: NOW + 1,
        evidenceIdV1: 'reference_evidence_v1', ...overrides};
      return {...core, evidenceFingerprintV1:
        inventory.ad05RemainingReferenceEvidenceFingerprintV1(core)};
    },
  });
  const finalVerifier = (overrides = {}) => ({
    verifyFinalStateV1: async ({receiptSet, remainingReferenceEvidence}) => {
      const core = {schemaVersion: 1, manifestFingerprintV1: manifest.manifestFingerprintV1,
        receiptSetFingerprintV1: receiptSet.receiptSetFingerprintV1,
        remainingEvidenceFingerprintV1: remainingReferenceEvidence.evidenceFingerprintV1,
        sourceDispositionVerifiedV1: true, publicPrivacyVerifiedV1: true,
        restoreSuppressionVerifiedV1: true, unrelatedAssociationUnchangedV1: true,
        evidenceCodeV1: 'profile_erasure_finally_verified', evidenceIdV1: 'final_evidence_v1',
        verifiedAtSecV1: NOW + 2, ...overrides};
      return {...core,
        evidenceFingerprintV1: effects.ad05FinalVerificationFingerprintV1(core)};
    },
  });
  const finalize = (remainingOverrides = {}, finalOverrides = {}) =>
    effects.finalizeCandidateAd05TransactionalAdapterV1({repository, binding: current,
      manifest, remainingReferenceVerifier: remainingVerifier(remainingOverrides),
      finalVerifier: finalVerifier(finalOverrides)});
  await assert.rejects(() => finalize({independentSourceIdV1: manifest.inventorySourceIdV1}),
    assertAd05Code('AD05_INCOMPLETE_INVENTORY'));
  await assert.rejects(() => finalize({verifiedAtSecV1: NOW - 1}),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  await assert.rejects(() => finalize({receiptSetFingerprintV1: 'd'.repeat(64)}),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  await assert.rejects(() => finalize({}, {verifiedAtSecV1: NOW}),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  await assert.rejects(() => finalize({}, {receiptSetFingerprintV1: 'e'.repeat(64)}),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  await assert.rejects(() => finalize({}, {remainingEvidenceFingerprintV1: 'f'.repeat(64)}),
    assertAd05Code('AD05_BINDING_CONFLICT'));
  assert.equal((await finalize()).state, 'complete');
});

test('finalization rejects a validly fingerprinted receipt whose outcome contradicts item classification', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  await effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding: current,
    item: manifest.itemsV1[0], effect: documentEffect({calls: 0}), committedAtSecV1: NOW});
  const receiptPath = records.ad05ItemReceiptPathV1({binding: current,
    itemIdV1: manifest.itemsV1[0].itemIdV1});
  const forgedCore = {...await repository.read(receiptPath),
    classificationV1: 'notApplicable', outcomeV1: 'notApplicableVerified',
    sourceRecordVersionAfterV1: 'record_v1'};
  delete forgedCore.receiptFingerprintV1;
  repository.values.set(receiptPath, {...forgedCore,
    receiptFingerprintV1: records.ad05ItemReceiptFingerprintV1(forgedCore)});
  await assert.rejects(() => effects.finalizeCandidateAd05TransactionalAdapterV1({
    repository, binding: current, manifest,
    remainingReferenceVerifier: {verifyRemainingReferencesV1: async () => {
      throw new Error('must not run');
    }},
    finalVerifier: {verifyFinalStateV1: async () => { throw new Error('must not run'); }},
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
});

test('completed receipt is immutable and future hold release requires a new versioned effect', async () => {
  const current = binding();
  const manifest = await manifestFor(current, trustedRecords(1));
  const repository = seedRepository(manifest);
  await effects.applyCandidateAd05TransactionalDocumentItemV1({repository, binding: current,
    item: manifest.itemsV1[0], effect: documentEffect({calls: 0}), committedAtSecV1: NOW});
  const release = binding({actionV1: 'erase', effectVersionV1: 'hold-release-v2'});
  await assert.rejects(() => effects.applyCandidateAd05TransactionalDocumentItemV1({
    repository, binding: release, item: manifest.itemsV1[0], effect: documentEffect({calls: 0}),
    committedAtSecV1: NOW + 1,
  }), assertAd05Code('AD05_BINDING_CONFLICT'));
});

test('synthetic approved policies are test-only; unimplemented V/E/D rows stay unsupported', async () => {
  const wrappers = adapters.createTestOnlySyntheticCandidateAd05AdaptersV1({
    syntheticPolicyV1: fixture.testOnlySyntheticApprovedPolicy,
    runtimesV1: [],
  });
  const adapter = wrappers.find((entry) => entry.adapterIdV1 === 'personal_storage_media');
  const result = await adapter.applyEffectV1({
    scope: {authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a'},
    generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
    internalJobId: 'job_ad05_one', effectIdV1: 'effect_ad05_one',
    policyVersion: 'synthetic_policy_v1',
  });
  assert.equal(result.state, 'unsupported');
  assert.equal(result.policyDecisionState, 'approved');
  assert.throws(() => adapters.parseCandidateAd05SyntheticPolicyRegistryV1({
    ...fixture.testOnlySyntheticApprovedPolicy, testOnlySyntheticV1: false,
  }), assertAd05Code('AD05_INVALID_RECORD'));
});

test('every synthetic unapproved decision is blocked before a runtime can inspect or mutate', async () => {
  let calls = 0;
  const pending = clone(fixture.testOnlySyntheticApprovedPolicy);
  pending.decisionsV1[1] = {...pending.decisionsV1[1],
    decisionStateV1: 'pendingOperationalProof', approvedV1: false, actionV1: null};
  const wrappers = adapters.createTestOnlySyntheticCandidateAd05AdaptersV1({
    syntheticPolicyV1: pending,
    runtimesV1: [{adapterIdV1: 'user_profile',
      inspectEffectV1: async () => { calls += 1; return null; },
      applyEffectV1: async () => { calls += 1; throw new Error('must not run'); }}],
  });
  const result = await wrappers[1].applyEffectV1({
    scope: {authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a'},
    generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
    internalJobId: 'job_ad05_one', effectIdV1: 'effect_ad05_one',
    policyVersion: 'synthetic_policy_v1',
  });
  assert.equal(result.state, 'blocked');
  assert.equal(calls, 0);
});

test('approved transactional chunk progress stays private as null, never a nonterminal AD04 result', async () => {
  const wrappers = adapters.createTestOnlySyntheticCandidateAd05AdaptersV1({
    syntheticPolicyV1: fixture.testOnlySyntheticApprovedPolicy,
    runtimesV1: [{adapterIdV1: 'user_profile', inspectEffectV1: async () => null,
      applyEffectV1: async () => null}],
  });
  const input = {
    scope: {authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a'},
    generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
    internalJobId: 'job_ad05_one', effectIdV1: 'effect_ad05_one',
    policyVersion: 'synthetic_policy_v1',
  };
  assert.equal(await wrappers[1].inspectEffectV1(input), null);
  assert.equal(await wrappers[1].applyEffectV1(input), null);
});

test('firebase_auth_identity is evidence-only and cannot claim completion without exact bound AD04 evidence', async () => {
  let verifierCalls = 0;
  const runtime = adapters.createFirebaseAuthEvidenceOnlyRuntimeV1({
    verifyBoundAd04AuthEvidenceV1: async (input) => {
      verifierCalls += 1;
      return {schemaVersion: 1, ...input.scope, internalJobId: input.internalJobId,
        effectIdV1: input.effectIdV1,
        generationHash: input.generationHash,
        acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
        policyVersionV1: input.policyVersion,
        ad04AuthCheckpointCompleteV1: true, ad04AuthEffectReceiptCompleteV1: true,
        evidenceCodeV1: 'ad04_auth_absence_verified', evidenceIdV1: 'auth_evidence_v1'};
    },
  });
  const wrapper = adapters.createTestOnlySyntheticCandidateAd05AdaptersV1({
    syntheticPolicyV1: fixture.testOnlySyntheticApprovedPolicy,
    runtimesV1: [runtime],
  })[0];
  const result = await wrapper.applyEffectV1({
    scope: {authProjectIdV2: 'demo-hoopsconnect', authTenantIdV2: null, authUidV2: 'owner-a'},
    generationHash: 'a'.repeat(64), acceptedLifecycleEpochV2: 8,
    internalJobId: 'job_ad05_one', effectIdV1: 'effect_auth_identity',
    policyVersion: 'synthetic_policy_v1',
  });
  assert.equal(result.state, 'complete');
  assert.equal(verifierCalls, 1);
  assert.equal(Object.keys(runtime).some((key) => /delete|disable|revoke|mutate/i.test(key)), false);
});
