import {canonicalSha256} from "../domain/official_stats_contract";
import {accountLifecycleAuthorityPathV2} from
  "../domain/account_lifecycle_ad02_v2";
import {CandidateAd05TransactionRepositoryV1} from "./ad05_effects";
import {
  CandidateAd05ExecutionBindingV1,
  CandidateAd05ManifestItemV1,
  CandidateAd05SealedManifestV1,
  ad05FailV1,
  parseCandidateAd05ManifestItemV1,
  parseCandidateAd05SealedManifestV1,
} from "./ad05_records";
import {
  deterministicAd05ManifestItemIdV1,
  requireCandidateAd05CanonicalManifestV1,
} from "./ad05_inventory";
import {
  ad04CounterV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  deletionJobBindingPathV1,
  parseCandidateAccountLifecycleAuthorityV2ForDeletionV1,
  parseCandidateDeletionJobBindingV1,
  sameAd04ScopeV1,
} from "./ad04_records";
import {
  Ad05eCandidateOutcomeV1,
  CandidateAd05eEvidenceV1,
  assertCandidateAd05eEvidenceBindingV1,
  parseCandidateAd05eEvidenceV1,
} from "./ad05_fcm_preferences_records";

type ChainKindV1 = "suppression" | "dispositionPlan" | "observation";
const chainKindsV1: readonly ChainKindV1[] = Object.freeze([
  "suppression", "dispositionPlan", "observation",
]);

export interface CandidateAd05eSourceAuthorityV1 {
  schemaVersion: 1;
  producerIdV1: "synthetic_notification_inventory_v1";
  bindingFingerprintV1: string;
  itemFingerprintV1: string;
  provenanceIdV1: string;
  highWaterMarkV1: string;
  referenceFingerprintsV1: readonly string[];
  coverageFingerprintsV1: readonly string[];
  sourceSetHashV1: string;
  authorityFingerprintV1: string;
}

export interface CandidateAd05eChainRecordV1 {
  schemaVersion: 1;
  recordTypeV1: ChainKindV1;
  bindingFingerprintV1: string;
  itemFingerprintV1: string;
  previousRecordFingerprintV1: string | null;
  payloadV1: Readonly<Record<string, unknown>>;
  payloadFingerprintV1: string;
  recordFingerprintV1: string;
}

export interface CandidateAd05eEvidenceReceiptV1 {
  schemaVersion: 1;
  adapterIdV1: "device_fcm_preferences";
  manifestFingerprintV1: string;
  itemFingerprintV1: string;
  evidenceFingerprintV1: string;
  sourceAuthorityFingerprintV1: string;
  chainFingerprintV1: string;
  candidateOutcomeV1: Ad05eCandidateOutcomeV1;
  verifiedAtSecV1: number;
  syntheticEvidenceVerifiedV1: true;
  productionActivationAllowedV1: false;
  adapterResultEligibleV1: false;
  providerRevocationVerifiedV1: false;
  deliveryRecallVerifiedV1: false;
  liveSuppressionVerifiedV1: false;
  deviceClearingVerifiedV1: false;
  uncertainDispatchBarrierResolvedV1: false;
  receiptFingerprintV1: string;
}

export interface CandidateAd05eDormantPlanV1 {
  stateV1: "blocked";
  evidenceCodeV1:
    "notification_provider_and_dispatch_reconciliation_not_approved";
  writesAllowedV1: false;
  providerCallsAllowedV1: false;
  uncertainAttemptRetryAllowedV1: false;
  barrierReleaseAllowedV1: false;
}

export function createDormantCandidateAd05ePlanV1():
CandidateAd05eDormantPlanV1 {
  return Object.freeze({
    stateV1: "blocked",
    evidenceCodeV1:
      "notification_provider_and_dispatch_reconciliation_not_approved",
    writesAllowedV1: false,
    providerCallsAllowedV1: false,
    uncertainAttemptRetryAllowedV1: false,
    barrierReleaseAllowedV1: false,
  });
}

function sortedUniqueHashes(values: readonly string[]): readonly string[] {
  const parsed = values.map(ad04HashV1).sort();
  if (new Set(parsed).size !== parsed.length) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return Object.freeze(parsed);
}

export function ad05eSourceAuthorityFingerprintV1(value: Omit<
  CandidateAd05eSourceAuthorityV1, "authorityFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-source-authority-v1", ...value,
  });
}

export function ad05eSourceAuthorityPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
}): string {
  return `candidateAd05eFcmPreferencesV1/${
    input.bindingV1.internalJobId}/authoritiesV1/source_${canonicalSha256({
    bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
  })}`;
}

export function buildTestOnlyCandidateAd05eSourceAuthorityV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): CandidateAd05eSourceAuthorityV1 {
  const referenceFingerprintsV1 = sortedUniqueHashes(
    input.evidenceV1.referencesV1.map((entry) =>
      entry.referenceFingerprintV1),
  );
  const coverageFingerprintsV1 = sortedUniqueHashes(
    input.evidenceV1.coverageV1.map((entry) => entry.coverageFingerprintV1),
  );
  const core = {
    schemaVersion: 1 as const,
    producerIdV1: "synthetic_notification_inventory_v1" as const,
    bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
    provenanceIdV1: input.evidenceV1.provenanceIdV1,
    highWaterMarkV1: input.evidenceV1.highWaterMarkV1,
    referenceFingerprintsV1,
    coverageFingerprintsV1,
    sourceSetHashV1: canonicalSha256({
      referencesV1: input.evidenceV1.referencesV1,
      coverageV1: input.evidenceV1.coverageV1,
    }),
  };
  return Object.freeze({...core,
    authorityFingerprintV1: ad05eSourceAuthorityFingerprintV1(core)});
}

function parseSourceAuthorityV1(
  value: unknown,
): CandidateAd05eSourceAuthorityV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = [
    "schemaVersion", "producerIdV1", "bindingFingerprintV1",
    "itemFingerprintV1", "provenanceIdV1", "highWaterMarkV1",
    "referenceFingerprintsV1", "coverageFingerprintsV1", "sourceSetHashV1",
    "authorityFingerprintV1",
  ];
  if (Object.keys(data).length !== keys.length || !keys.every((key) =>
    Object.prototype.hasOwnProperty.call(data, key)) || data.schemaVersion !== 1 ||
    data.producerIdV1 !== "synthetic_notification_inventory_v1" ||
    !Array.isArray(data.referenceFingerprintsV1) ||
    !Array.isArray(data.coverageFingerprintsV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const candidate: CandidateAd05eSourceAuthorityV1 = Object.freeze({
    schemaVersion: 1,
    producerIdV1: "synthetic_notification_inventory_v1",
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    highWaterMarkV1: ad04OpaqueIdV1(data.highWaterMarkV1),
    referenceFingerprintsV1:
      sortedUniqueHashes(data.referenceFingerprintsV1),
    coverageFingerprintsV1:
      sortedUniqueHashes(data.coverageFingerprintsV1),
    sourceSetHashV1: ad04HashV1(data.sourceSetHashV1),
    authorityFingerprintV1: ad04HashV1(data.authorityFingerprintV1),
  });
  const {authorityFingerprintV1, ...core} = candidate;
  if (authorityFingerprintV1 !== ad05eSourceAuthorityFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function ad05eChainRecordPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
  recordTypeV1: ChainKindV1;
}): string {
  if (!chainKindsV1.includes(input.recordTypeV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return `candidateAd05eFcmPreferencesV1/${
    input.bindingV1.internalJobId}/recordsV1/${
    input.recordTypeV1}_${canonicalSha256({
    bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
    recordTypeV1: input.recordTypeV1,
  })}`;
}

function chainRecordFingerprintV1(value: Omit<
  CandidateAd05eChainRecordV1, "recordFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-chain-record-v1", ...value,
  });
}

function chainPayloadsV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): Readonly<Record<ChainKindV1, Readonly<Record<string, unknown>>>> {
  const unresolvedAttemptFingerprintsV1 = input.evidenceV1.referencesV1
    .filter((entry) => entry.dispositionV1 ===
      "unresolvedExternalDependency")
    .map((entry) => entry.referenceFingerprintV1).sort();
  return Object.freeze({
    suppression: Object.freeze({
      internalJobId: input.bindingV1.internalJobId,
      generationHash: input.bindingV1.generationHash,
      acceptedLifecycleEpochV2: input.bindingV1.acceptedLifecycleEpochV2,
      lifecycleStateV1: "deleting",
      candidateRegistrationTargetingDeniedV1: true,
      liveProducerEnforcementVerifiedV1: false,
      providerTokenRevocationVerifiedV1: false,
    }),
    dispositionPlan: Object.freeze({
      manifestFingerprintV1: input.manifestV1.manifestFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
      referencePlansV1: input.evidenceV1.referencesV1.map((entry) => ({
        referenceFingerprintV1: entry.referenceFingerprintV1,
        referenceClassV1: entry.referenceClassV1,
        ownerRelationV1: entry.ownerRelationV1,
        dispositionV1: entry.dispositionV1,
        sourceRecordVersionV1: entry.sourceRecordVersionV1,
      })),
      executesLiveMutationV1: false,
      rewritesDeliveryAttemptV1: false,
      recallsSubmittedDeliveryV1: false,
    }),
    observation: Object.freeze({
      observedAtSecV1: input.evidenceV1.observedAtSecV1,
      highWaterMarkV1: input.evidenceV1.highWaterMarkV1,
      sourceSetHashV1: canonicalSha256({
        referencesV1: input.evidenceV1.referencesV1,
        coverageV1: input.evidenceV1.coverageV1,
      }),
      unresolvedAttemptFingerprintsV1,
      uncertainAttemptRetryAllowedV1: false,
      barrierReleaseAllowedV1: false,
      candidateOutcomeV1: input.evidenceV1.candidateOutcomeV1,
    }),
  });
}

export function buildTestOnlyCandidateAd05eChainRecordsV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): readonly CandidateAd05eChainRecordV1[] {
  const payloads = chainPayloadsV1(input);
  let previousRecordFingerprintV1: string | null = null;
  return Object.freeze(chainKindsV1.map((recordTypeV1) => {
    const payloadV1 = payloads[recordTypeV1];
    const core = {
      schemaVersion: 1 as const,
      recordTypeV1,
      bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
      previousRecordFingerprintV1,
      payloadV1,
      payloadFingerprintV1: canonicalSha256(payloadV1),
    };
    const record = Object.freeze({...core,
      recordFingerprintV1: chainRecordFingerprintV1(core)});
    previousRecordFingerprintV1 = record.recordFingerprintV1;
    return record;
  }));
}

function parseChainRecordV1(value: unknown): CandidateAd05eChainRecordV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = [
    "schemaVersion", "recordTypeV1", "bindingFingerprintV1",
    "itemFingerprintV1", "previousRecordFingerprintV1", "payloadV1",
    "payloadFingerprintV1", "recordFingerprintV1",
  ];
  if (Object.keys(data).length !== keys.length || !keys.every((key) =>
    Object.prototype.hasOwnProperty.call(data, key)) || data.schemaVersion !== 1 ||
    !chainKindsV1.includes(data.recordTypeV1 as ChainKindV1) ||
    data.payloadV1 === null || typeof data.payloadV1 !== "object" ||
    Array.isArray(data.payloadV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const candidate: CandidateAd05eChainRecordV1 = Object.freeze({
    schemaVersion: 1,
    recordTypeV1: data.recordTypeV1 as ChainKindV1,
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
    previousRecordFingerprintV1: data.previousRecordFingerprintV1 === null ?
      null : ad04HashV1(data.previousRecordFingerprintV1),
    payloadV1: Object.freeze(data.payloadV1 as Record<string, unknown>),
    payloadFingerprintV1: ad04HashV1(data.payloadFingerprintV1),
    recordFingerprintV1: ad04HashV1(data.recordFingerprintV1),
  });
  const {recordFingerprintV1, ...core} = candidate;
  if (candidate.payloadFingerprintV1 !== canonicalSha256(candidate.payloadV1) ||
      recordFingerprintV1 !== chainRecordFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

function assertExactManifestMemberV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
}): void {
  const member = input.manifestV1.itemsV1[input.itemV1.ordinalV1];
  const expectedId = deterministicAd05ManifestItemIdV1({
    binding: input.bindingV1,
    record: {
      schemaVersion: 1,
      adapterIdV1: input.itemV1.adapterIdV1,
      sourceSchemaIdV1: input.itemV1.sourceSchemaIdV1,
      sourceSchemaVersionV1: input.itemV1.sourceSchemaVersionV1,
      sourceDocumentPathV1: input.itemV1.sourceDocumentPathV1,
      sourceRecordVersionV1: input.itemV1.sourceRecordVersionV1,
      provenanceIdV1: input.itemV1.provenanceIdV1,
      associationScopeHashV1: input.itemV1.associationScopeHashV1,
      classificationV1: input.itemV1.classificationV1,
    },
  });
  if (member === undefined ||
      canonicalSha256(member) !== canonicalSha256(input.itemV1) ||
      input.itemV1.itemIdV1 !== expectedId) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

export function ad05eEvidenceReceiptFingerprintV1(value: Omit<
  CandidateAd05eEvidenceReceiptV1, "receiptFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-evidence-receipt-v1", ...value,
  });
}

function receiptFor(input: {
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
  authorityV1: CandidateAd05eSourceAuthorityV1;
  chainV1: readonly CandidateAd05eChainRecordV1[];
}): CandidateAd05eEvidenceReceiptV1 {
  const core = {
    schemaVersion: 1 as const,
    adapterIdV1: "device_fcm_preferences" as const,
    manifestFingerprintV1: input.manifestV1.manifestFingerprintV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
    evidenceFingerprintV1: input.evidenceV1.evidenceFingerprintV1,
    sourceAuthorityFingerprintV1: input.authorityV1.authorityFingerprintV1,
    chainFingerprintV1: canonicalSha256(input.chainV1),
    candidateOutcomeV1: input.evidenceV1.candidateOutcomeV1,
    verifiedAtSecV1: input.evidenceV1.observedAtSecV1,
    syntheticEvidenceVerifiedV1: true as const,
    productionActivationAllowedV1: false as const,
    adapterResultEligibleV1: false as const,
    providerRevocationVerifiedV1: false as const,
    deliveryRecallVerifiedV1: false as const,
    liveSuppressionVerifiedV1: false as const,
    deviceClearingVerifiedV1: false as const,
    uncertainDispatchBarrierResolvedV1: false as const,
  };
  return Object.freeze({...core,
    receiptFingerprintV1: ad05eEvidenceReceiptFingerprintV1(core)});
}

export function ad05eReceiptSealPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
}): string {
  return `candidateAd05eFcmPreferencesV1/${
    input.bindingV1.internalJobId}/receiptsV1/receipt_${canonicalSha256({
    bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
  })}`;
}

export function buildTestOnlyCandidateAd05eReceiptSealV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): CandidateAd05eEvidenceReceiptV1 {
  const authorityV1 = buildTestOnlyCandidateAd05eSourceAuthorityV1(input);
  const chainV1 = buildTestOnlyCandidateAd05eChainRecordsV1(input);
  return receiptFor({...input, authorityV1, chainV1});
}

function assertPersistedAd04AuthorityV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  jobBindingRawV1: unknown;
  lifecycleRawV1: unknown;
}): void {
  const job = parseCandidateDeletionJobBindingV1(input.jobBindingRawV1);
  const lifecycle =
    parseCandidateAccountLifecycleAuthorityV2ForDeletionV1(
      input.lifecycleRawV1,
    );
  if (!sameAd04ScopeV1(job, input.bindingV1) ||
      !sameAd04ScopeV1(lifecycle, input.bindingV1) ||
      job.internalJobId !== input.bindingV1.internalJobId ||
      job.generationHash !== input.bindingV1.generationHash ||
      job.acceptedLifecycleEpochV2 !==
        input.bindingV1.acceptedLifecycleEpochV2 ||
      job.policyVersion !== input.bindingV1.policyVersionV1 ||
      lifecycle.accountGenerationV2 !== input.bindingV1.generationHash ||
      lifecycle.accountLifecycleEpochV2 !==
        input.bindingV1.acceptedLifecycleEpochV2 ||
      (lifecycle.lifecycleStateV2 !== "deleting" &&
       lifecycle.lifecycleStateV2 !== "deleted")) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

export async function verifyTestOnlySyntheticCandidateAd05eEvidenceV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): Promise<CandidateAd05eEvidenceReceiptV1> {
  const manifestV1 = parseCandidateAd05SealedManifestV1(input.manifestV1);
  const itemV1 = parseCandidateAd05ManifestItemV1(input.itemV1);
  const suppliedEvidenceV1 = parseCandidateAd05eEvidenceV1(input.evidenceV1);
  return input.repository.runTransaction(async (transaction) => {
    const canonicalManifestV1 = await requireCandidateAd05CanonicalManifestV1({
      repository: transaction, binding: input.bindingV1, manifest: manifestV1,
    });
    assertExactManifestMemberV1({
      bindingV1: input.bindingV1,
      manifestV1: canonicalManifestV1,
      itemV1,
    });
    const [evidenceRawV1, jobBindingRawV1, lifecycleRawV1] = await Promise.all([
      transaction.read(itemV1.sourceDocumentPathV1),
      transaction.read(deletionJobBindingPathV1(
        input.bindingV1.internalJobId,
      )),
      transaction.read(accountLifecycleAuthorityPathV2(input.bindingV1)),
    ]);
    if (evidenceRawV1 === null || jobBindingRawV1 === null ||
        lifecycleRawV1 === null) {
      ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    }
    assertPersistedAd04AuthorityV1({
      bindingV1: input.bindingV1,
      jobBindingRawV1,
      lifecycleRawV1,
    });
    const evidenceV1 = parseCandidateAd05eEvidenceV1(evidenceRawV1);
    if (canonicalSha256(evidenceV1) !== canonicalSha256(suppliedEvidenceV1)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    assertCandidateAd05eEvidenceBindingV1({
      bindingV1: input.bindingV1, evidenceV1,
    });
    if (itemV1.adapterIdV1 !== evidenceV1.adapterIdV1 ||
        itemV1.sourceSchemaIdV1 !== evidenceV1.sourceSchemaIdV1 ||
        itemV1.sourceSchemaVersionV1 !== evidenceV1.sourceSchemaVersionV1 ||
        itemV1.sourceRecordVersionV1 !== evidenceV1.recordVersionV1 ||
        itemV1.sourceDocumentPathHashV1 !==
          canonicalSha256(itemV1.sourceDocumentPathV1) ||
        itemV1.sourceDocumentPathHashV1 !==
          evidenceV1.sourceDocumentPathHashV1 ||
        itemV1.provenanceIdV1 !== evidenceV1.provenanceIdV1 ||
        itemV1.associationScopeHashV1 === null ||
        itemV1.associationScopeHashV1 !==
          evidenceV1.associationScopeHashV1 ||
        (itemV1.classificationV1 === "notApplicable") !==
          (evidenceV1.referencesV1.length === 0)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const expectedAuthorityV1 =
      buildTestOnlyCandidateAd05eSourceAuthorityV1({
        bindingV1: input.bindingV1, itemV1, evidenceV1,
      });
    const authorityRawV1 = await transaction.read(
      ad05eSourceAuthorityPathV1({bindingV1: input.bindingV1, itemV1}),
    );
    if (authorityRawV1 === null) ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    const authorityV1 = parseSourceAuthorityV1(authorityRawV1);
    if (canonicalSha256(authorityV1) !==
        canonicalSha256(expectedAuthorityV1)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const expectedChainV1 = buildTestOnlyCandidateAd05eChainRecordsV1({
      bindingV1: input.bindingV1,
      manifestV1: canonicalManifestV1,
      itemV1,
      evidenceV1,
    });
    const chainV1: CandidateAd05eChainRecordV1[] = [];
    for (const [index, expected] of expectedChainV1.entries()) {
      const recordTypeV1 = chainKindsV1[index];
      const raw = await transaction.read(ad05eChainRecordPathV1({
        bindingV1: input.bindingV1, itemV1, recordTypeV1,
      }));
      if (raw === null) ad05FailV1("AD05_INCOMPLETE_INVENTORY");
      const parsed = parseChainRecordV1(raw);
      if (canonicalSha256(parsed) !== canonicalSha256(expected)) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      chainV1.push(parsed);
    }
    const expectedReceiptV1 = receiptFor({
      manifestV1: canonicalManifestV1,
      itemV1,
      evidenceV1,
      authorityV1,
      chainV1,
    });
    const receiptRawV1 = await transaction.read(ad05eReceiptSealPathV1({
      bindingV1: input.bindingV1, itemV1,
    }));
    if (receiptRawV1 === null) ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    const receiptV1 = parseCandidateAd05eEvidenceReceiptV1(receiptRawV1);
    if (canonicalSha256(receiptV1) !== canonicalSha256(expectedReceiptV1)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    return receiptV1;
  });
}

export function parseCandidateAd05eEvidenceReceiptV1(
  value: unknown,
): CandidateAd05eEvidenceReceiptV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = [
    "schemaVersion", "adapterIdV1", "manifestFingerprintV1",
    "itemFingerprintV1", "evidenceFingerprintV1",
    "sourceAuthorityFingerprintV1", "chainFingerprintV1",
    "candidateOutcomeV1", "verifiedAtSecV1", "syntheticEvidenceVerifiedV1",
    "productionActivationAllowedV1", "adapterResultEligibleV1",
    "providerRevocationVerifiedV1", "deliveryRecallVerifiedV1",
    "liveSuppressionVerifiedV1", "deviceClearingVerifiedV1",
    "uncertainDispatchBarrierResolvedV1", "receiptFingerprintV1",
  ];
  if (Object.keys(data).length !== keys.length || !keys.every((key) =>
    Object.prototype.hasOwnProperty.call(data, key)) || data.schemaVersion !== 1 ||
    data.adapterIdV1 !== "device_fcm_preferences" ||
    !["syntheticInventoryVerified",
      "syntheticInventoryVerifiedWithUnresolvedDispatch",
      "positiveNotApplicableEvidenceVerified"].includes(
      data.candidateOutcomeV1 as string,
    ) || data.syntheticEvidenceVerifiedV1 !== true ||
    data.productionActivationAllowedV1 !== false ||
    data.adapterResultEligibleV1 !== false ||
    data.providerRevocationVerifiedV1 !== false ||
    data.deliveryRecallVerifiedV1 !== false ||
    data.liveSuppressionVerifiedV1 !== false ||
    data.deviceClearingVerifiedV1 !== false ||
    data.uncertainDispatchBarrierResolvedV1 !== false) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const candidate: CandidateAd05eEvidenceReceiptV1 = Object.freeze({
    schemaVersion: 1,
    adapterIdV1: "device_fcm_preferences",
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
    sourceAuthorityFingerprintV1:
      ad04HashV1(data.sourceAuthorityFingerprintV1),
    chainFingerprintV1: ad04HashV1(data.chainFingerprintV1),
    candidateOutcomeV1: data.candidateOutcomeV1 as Ad05eCandidateOutcomeV1,
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    syntheticEvidenceVerifiedV1: true,
    productionActivationAllowedV1: false,
    adapterResultEligibleV1: false,
    providerRevocationVerifiedV1: false,
    deliveryRecallVerifiedV1: false,
    liveSuppressionVerifiedV1: false,
    deviceClearingVerifiedV1: false,
    uncertainDispatchBarrierResolvedV1: false,
    receiptFingerprintV1: ad04HashV1(data.receiptFingerprintV1),
  });
  const {receiptFingerprintV1, ...core} = candidate;
  if (receiptFingerprintV1 !== ad05eEvidenceReceiptFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function candidateAd05eMechanicalSupportV1(
  adapterIdV1: string,
): Readonly<{stateV1: "candidateEvidenceOnly";
  adapterResultEligibleV1: false}> {
  if (adapterIdV1 !== "device_fcm_preferences") {
    ad05FailV1("AD05_UNSUPPORTED");
  }
  return Object.freeze({
    stateV1: "candidateEvidenceOnly",
    adapterResultEligibleV1: false,
  });
}
