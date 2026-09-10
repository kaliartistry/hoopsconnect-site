import {canonicalSha256} from "../domain/official_stats_contract";
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
import {ad04CounterV1, ad04HashV1, ad04OpaqueIdV1} from "./ad04_records";
import {
  CandidateAd05dMediaEvidenceV1,
  Ad05dAdapterIdV1,
  Ad05dCandidateOutcomeV1,
  assertCandidateAd05dEvidenceBindingV1,
  parseCandidateAd05dMediaEvidenceV1,
} from "./ad05_storage_media_records";

const supportingKindsV1 = [
  "ownership", "rights", "graph", "coverage", "effectPlan", "observation",
] as const;
type SupportingKindV1 = typeof supportingKindsV1[number];

export interface CandidateAd05dSourceAuthorityV1 {
  schemaVersion: 1;
  producerIdV1: "synthetic_storage_fixture_v1";
  adapterIdV1: Ad05dAdapterIdV1;
  bindingFingerprintV1: string;
  provenanceIdV1: string;
  ownershipSourcePathHashV1: string;
  ownershipSourceVersionV1: string;
  ownershipSourceHashV1: string;
  highWaterMarkV1: string;
  objectVersionFingerprintsV1: readonly string[];
  referenceSetHashV1: string;
  authorityFingerprintV1: string;
}

export function ad05dSourceAuthorityFingerprintV1(value: Omit<
  CandidateAd05dSourceAuthorityV1, "authorityFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-source-authority-v1", ...value,
  });
}

export function ad05dSourceAuthorityPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
}): string {
  return `candidateAd05dMediaV1/${input.bindingV1.internalJobId}/authoritiesV1/${
    "source_" + canonicalSha256({
      bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
    })}`;
}

export function buildTestOnlyCandidateAd05dSourceAuthorityV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): CandidateAd05dSourceAuthorityV1 {
  const core = {
    schemaVersion: 1 as const,
    producerIdV1: "synthetic_storage_fixture_v1" as const,
    adapterIdV1: input.evidenceV1.adapterIdV1,
    bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
    provenanceIdV1: input.evidenceV1.provenanceIdV1,
    ownershipSourcePathHashV1:
      input.evidenceV1.ownershipV1.ownershipSourcePathHashV1,
    ownershipSourceVersionV1:
      input.evidenceV1.ownershipV1.ownershipSourceVersionV1,
    ownershipSourceHashV1:
      input.evidenceV1.ownershipV1.ownershipSourceHashV1,
    highWaterMarkV1: input.evidenceV1.highWaterMarkV1,
    objectVersionFingerprintsV1: Object.freeze(input.evidenceV1.objectsV1
      .map((entry) => entry.recordFingerprintV1).sort()),
    referenceSetHashV1:
      input.evidenceV1.observationV1.referenceClosureHashV1,
  };
  return Object.freeze({...core,
    authorityFingerprintV1: ad05dSourceAuthorityFingerprintV1(core)});
}

function parseSourceAuthorityV1(value: unknown): CandidateAd05dSourceAuthorityV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = ["schemaVersion", "producerIdV1", "adapterIdV1",
    "bindingFingerprintV1", "provenanceIdV1", "ownershipSourcePathHashV1",
    "ownershipSourceVersionV1", "ownershipSourceHashV1", "highWaterMarkV1",
    "objectVersionFingerprintsV1", "referenceSetHashV1",
    "authorityFingerprintV1"];
  if (Object.keys(data).length !== keys.length || !keys.every((key) =>
    Object.prototype.hasOwnProperty.call(data, key)) || data.schemaVersion !== 1 ||
    data.producerIdV1 !== "synthetic_storage_fixture_v1" ||
    (data.adapterIdV1 !== "personal_storage_media" &&
     data.adapterIdV1 !== "shared_association_media") ||
    !Array.isArray(data.objectVersionFingerprintsV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const objects = data.objectVersionFingerprintsV1.map(ad04HashV1);
  if (new Set(objects).size !== objects.length ||
      [...objects].sort().some((value, index) => value !== objects[index])) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const candidate: CandidateAd05dSourceAuthorityV1 = Object.freeze({
    schemaVersion: 1, producerIdV1: "synthetic_storage_fixture_v1",
    adapterIdV1: data.adapterIdV1 as Ad05dAdapterIdV1,
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    ownershipSourcePathHashV1: ad04HashV1(data.ownershipSourcePathHashV1),
    ownershipSourceVersionV1: ad04OpaqueIdV1(data.ownershipSourceVersionV1),
    ownershipSourceHashV1: ad04HashV1(data.ownershipSourceHashV1),
    highWaterMarkV1: ad04OpaqueIdV1(data.highWaterMarkV1),
    objectVersionFingerprintsV1: Object.freeze(objects),
    referenceSetHashV1: ad04HashV1(data.referenceSetHashV1),
    authorityFingerprintV1: ad04HashV1(data.authorityFingerprintV1),
  });
  const {authorityFingerprintV1, ...core} = candidate;
  if (authorityFingerprintV1 !== ad05dSourceAuthorityFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05dSupportingRecordV1 {
  schemaVersion: 1;
  recordTypeV1: SupportingKindV1;
  recordIdV1: string;
  bindingFingerprintV1: string;
  itemFingerprintV1: string;
  previousRecordFingerprintV1: string | null;
  payloadV1: Readonly<Record<string, unknown>>;
  payloadFingerprintV1: string;
  recordFingerprintV1: string;
}

export function ad05dSupportingRecordPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
  recordTypeV1: SupportingKindV1;
}): string {
  if (!supportingKindsV1.includes(input.recordTypeV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return `candidateAd05dMediaV1/${input.bindingV1.internalJobId}/recordsV1/${
    input.recordTypeV1}_${canonicalSha256({
      bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
      recordTypeV1: input.recordTypeV1,
    })}`;
}

function supportingFingerprintV1(value: Omit<
  CandidateAd05dSupportingRecordV1, "recordFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-supporting-record-v1", ...value,
  });
}

function supportingPayloadsV1(input: {
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): Readonly<Record<SupportingKindV1, Readonly<Record<string, unknown>>>> {
  const evidence = input.evidenceV1;
  const objectPreconditionsV1 = evidence.objectsV1.map((object) => ({
    objectIdV1: object.objectIdV1,
    bucketNameV1: evidence.bucketV1.bucketNameV1,
    objectNameUtf8Base64UrlV1: object.objectNameUtf8Base64UrlV1,
    generationV1: object.objectGenerationV1,
    metagenerationV1: object.objectMetagenerationV1,
    metadataHashV1: object.metadataHashV1,
    ownershipRecordHashV1: evidence.ownershipV1.ownershipFingerprintV1,
    sourceRecordVersionV1: evidence.recordVersionV1,
    privacyEpochV1: evidence.bindingV1.acceptedLifecycleEpochV2,
  }));
  return Object.freeze({
    ownership: Object.freeze({...evidence.ownershipV1}),
    rights: Object.freeze({
      rightsDecisionPathHashV1: evidence.ownershipV1.rightsDecisionPathHashV1,
      rightsDecisionHashV1: evidence.ownershipV1.rightsDecisionHashV1,
      protectedFactsHashV1: evidence.ownershipV1.protectedFactsHashV1,
      unrelatedReferencesHashV1:
        evidence.ownershipV1.unrelatedReferencesHashV1,
    }),
    graph: Object.freeze({
      objectVersionsV1: evidence.objectsV1,
      edgesV1: evidence.objectsV1.filter((object) =>
        object.derivativeOfObjectIdV1 !== null).map((object) => ({
        parentVersionRecordIdV1: object.derivativeOfObjectIdV1,
        childVersionRecordIdV1: object.objectIdV1,
        transformIdV1: object.transformIdV1,
        transformVersionV1: object.transformVersionV1,
      })),
    }),
    coverage: Object.freeze({
      inventoryCompleteV1: evidence.inventoryCompleteV1,
      referenceCoverageCompleteV1: evidence.referenceCoverageCompleteV1,
      highWaterMarkV1: evidence.highWaterMarkV1,
      observedObjectFingerprintsV1:
        evidence.observationV1.observedObjectFingerprintsV1,
    }),
    effectPlan: Object.freeze({
      manifestFingerprintV1: input.manifestV1.manifestFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
      operationV1: evidence.objectsV1.length === 0 ? "notApplicable" :
        evidence.adapterIdV1 === "personal_storage_media" ?
          "personalVersionErase" : "sharedAccountReferenceDetach",
      objectPreconditionsV1,
      preservedSetHashV1: evidence.observationV1.preservedSetHashV1,
    }),
    observation: Object.freeze({...evidence.observationV1}),
  });
}

export function buildTestOnlyCandidateAd05dSupportingRecordsV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): readonly CandidateAd05dSupportingRecordV1[] {
  const payloads = supportingPayloadsV1(input);
  let previous: string | null = null;
  return Object.freeze(supportingKindsV1.map((recordTypeV1) => {
    const payloadV1 = payloads[recordTypeV1];
    const core = {
      schemaVersion: 1 as const,
      recordTypeV1,
      recordIdV1: ad05dSupportingRecordPathV1({
        bindingV1: input.bindingV1, itemV1: input.itemV1, recordTypeV1,
      }).split("/").slice(-1)[0],
      bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
      previousRecordFingerprintV1: previous,
      payloadV1,
      payloadFingerprintV1: canonicalSha256(payloadV1),
    };
    const record = Object.freeze({
      ...core, recordFingerprintV1: supportingFingerprintV1(core),
    });
    previous = record.recordFingerprintV1;
    return record;
  }));
}

function parseSupportingRecordV1(
  value: unknown,
): CandidateAd05dSupportingRecordV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = ["schemaVersion", "recordTypeV1", "recordIdV1",
    "bindingFingerprintV1", "itemFingerprintV1",
    "previousRecordFingerprintV1", "payloadV1", "payloadFingerprintV1",
    "recordFingerprintV1"];
  if (Object.keys(data).length !== keys.length || !keys.every((key) =>
    Object.prototype.hasOwnProperty.call(data, key)) || data.schemaVersion !== 1 ||
    !supportingKindsV1.includes(data.recordTypeV1 as SupportingKindV1) ||
    data.payloadV1 === null || typeof data.payloadV1 !== "object" ||
    Array.isArray(data.payloadV1)) ad05FailV1("AD05_INVALID_RECORD");
  const candidate: CandidateAd05dSupportingRecordV1 = Object.freeze({
    schemaVersion: 1,
    recordTypeV1: data.recordTypeV1 as SupportingKindV1,
    recordIdV1: ad04OpaqueIdV1(data.recordIdV1),
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
      recordFingerprintV1 !== supportingFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05dDormantPlanV1 {
  stateV1: "blocked";
  evidenceCodeV1: "authoritative_storage_policy_and_provider_not_approved";
  writesAllowedV1: false;
  providerCallsAllowedV1: false;
}

export function createDormantCandidateAd05dPlanV1():
CandidateAd05dDormantPlanV1 {
  return Object.freeze({
    stateV1: "blocked",
    evidenceCodeV1: "authoritative_storage_policy_and_provider_not_approved",
    writesAllowedV1: false,
    providerCallsAllowedV1: false,
  });
}

function assertExactManifestMemberV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
}): void {
  const member = input.manifestV1.itemsV1[input.itemV1.ordinalV1];
  const expectedItemId = deterministicAd05ManifestItemIdV1({
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
      input.itemV1.itemIdV1 !== expectedItemId) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

export interface CandidateAd05dEvidenceReceiptV1 {
  schemaVersion: 1;
  adapterIdV1: Ad05dAdapterIdV1;
  manifestFingerprintV1: string;
  itemIdV1: string;
  itemFingerprintV1: string;
  evidenceFingerprintV1: string;
  supportingChainFingerprintV1: string;
  candidateOutcomeV1: Ad05dCandidateOutcomeV1;
  verifiedAtSecV1: number;
  syntheticDispositionEvidenceVerifiedV1: true;
  productionActivationAllowedV1: false;
  adapterResultEligibleV1: false;
  providerErasureVerifiedV1: false;
  publicPrivacyVerifiedV1: false;
  restoreSuppressionVerifiedV1: false;
  receiptFingerprintV1: string;
}

export function ad05dEvidenceReceiptFingerprintV1(value: Omit<
  CandidateAd05dEvidenceReceiptV1, "receiptFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-evidence-receipt-v1",
    ...value,
  });
}

function receiptFor(input: {
  evidenceV1: CandidateAd05dMediaEvidenceV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  supportingChainFingerprintV1: string;
}): CandidateAd05dEvidenceReceiptV1 {
  const withoutFingerprint = {
    schemaVersion: 1 as const,
    adapterIdV1: input.evidenceV1.adapterIdV1,
    manifestFingerprintV1: input.manifestV1.manifestFingerprintV1,
    itemIdV1: input.itemV1.itemIdV1,
    itemFingerprintV1: input.itemV1.itemFingerprintV1,
    evidenceFingerprintV1: input.evidenceV1.evidenceFingerprintV1,
    supportingChainFingerprintV1: input.supportingChainFingerprintV1,
    candidateOutcomeV1: input.evidenceV1.observationV1.candidateOutcomeV1,
    verifiedAtSecV1: input.evidenceV1.observationV1.observedAtSecV1,
    syntheticDispositionEvidenceVerifiedV1: true as const,
    productionActivationAllowedV1: false as const,
    adapterResultEligibleV1: false as const,
    providerErasureVerifiedV1: false as const,
    publicPrivacyVerifiedV1: false as const,
    restoreSuppressionVerifiedV1: false as const,
  };
  return Object.freeze({
    ...withoutFingerprint,
    receiptFingerprintV1: ad05dEvidenceReceiptFingerprintV1(withoutFingerprint),
  });
}

export function ad05dReceiptSealPathV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  itemV1: CandidateAd05ManifestItemV1;
}): string {
  return `candidateAd05dMediaV1/${input.bindingV1.internalJobId}/receiptsV1/${
    "receipt_" + canonicalSha256({
      bindingFingerprintV1: input.bindingV1.bindingFingerprintV1,
      itemFingerprintV1: input.itemV1.itemFingerprintV1,
    })}`;
}

export function buildTestOnlyCandidateAd05dReceiptSealV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): CandidateAd05dEvidenceReceiptV1 {
  const records = buildTestOnlyCandidateAd05dSupportingRecordsV1(input);
  const authority = buildTestOnlyCandidateAd05dSourceAuthorityV1(input);
  return receiptFor({
    evidenceV1: input.evidenceV1,
    manifestV1: input.manifestV1,
    itemV1: input.itemV1,
    supportingChainFingerprintV1: canonicalSha256({authority, records}),
  });
}

export async function verifyTestOnlySyntheticCandidateAd05dEvidenceV1(input: {
  repository: CandidateAd05TransactionRepositoryV1;
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05SealedManifestV1;
  itemV1: CandidateAd05ManifestItemV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): Promise<CandidateAd05dEvidenceReceiptV1> {
  const manifest = parseCandidateAd05SealedManifestV1(input.manifestV1);
  const item = parseCandidateAd05ManifestItemV1(input.itemV1);
  const suppliedEvidence = parseCandidateAd05dMediaEvidenceV1(input.evidenceV1);
  return input.repository.runTransaction(async (transaction) => {
    const canonicalManifest = await requireCandidateAd05CanonicalManifestV1({
      repository: transaction,
      binding: input.bindingV1,
      manifest,
    });
    assertExactManifestMemberV1({
      bindingV1: input.bindingV1,
      manifestV1: canonicalManifest,
      itemV1: item,
    });
    const persistedRaw = await transaction.read(item.sourceDocumentPathV1);
    if (persistedRaw === null) ad05FailV1("AD05_BINDING_CONFLICT");
    const evidence = parseCandidateAd05dMediaEvidenceV1(persistedRaw);
    if (canonicalSha256(evidence) !== canonicalSha256(suppliedEvidence)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    assertCandidateAd05dEvidenceBindingV1({
      bindingV1: input.bindingV1,
      evidenceV1: evidence,
    });
    const associationHash = evidence.ownershipV1.associationScopeHashV1;
    if (item.adapterIdV1 !== evidence.adapterIdV1 ||
        item.sourceSchemaIdV1 !== evidence.sourceSchemaIdV1 ||
        item.sourceSchemaVersionV1 !== evidence.sourceSchemaVersionV1 ||
        item.sourceRecordVersionV1 !== evidence.recordVersionV1 ||
        item.sourceDocumentPathHashV1 !==
          canonicalSha256(item.sourceDocumentPathV1) ||
        item.sourceDocumentPathHashV1 !== evidence.sourceDocumentPathHashV1 ||
        item.provenanceIdV1 !== evidence.provenanceIdV1 ||
        item.associationScopeHashV1 !== associationHash ||
        (item.classificationV1 === "applicable") !==
          (evidence.objectsV1.length > 0) ||
        (item.classificationV1 === "notApplicable") !==
          (evidence.observationV1.candidateOutcomeV1 ===
            "positiveNotApplicableEvidenceVerified")) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const expectedSupporting = buildTestOnlyCandidateAd05dSupportingRecordsV1({
      bindingV1: input.bindingV1,
      manifestV1: canonicalManifest,
      itemV1: item,
      evidenceV1: evidence,
    });
    const persistedAuthorityRaw = await transaction.read(
      ad05dSourceAuthorityPathV1({bindingV1: input.bindingV1, itemV1: item}),
    );
    if (persistedAuthorityRaw === null) {
      ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    }
    const persistedAuthority = parseSourceAuthorityV1(persistedAuthorityRaw);
    const expectedAuthority = buildTestOnlyCandidateAd05dSourceAuthorityV1({
      bindingV1: input.bindingV1, evidenceV1: evidence,
    });
    if (canonicalSha256(persistedAuthority) !== canonicalSha256(expectedAuthority)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const persistedSupportingRecords: CandidateAd05dSupportingRecordV1[] = [];
    for (const [index, expected] of expectedSupporting.entries()) {
      const recordTypeV1 = supportingKindsV1[index];
      const path = ad05dSupportingRecordPathV1({
        bindingV1: input.bindingV1, itemV1: item, recordTypeV1,
      });
      const persistedSupportingRaw = await transaction.read(path);
      if (persistedSupportingRaw === null) {
        ad05FailV1("AD05_INCOMPLETE_INVENTORY");
      }
      const persistedSupporting = parseSupportingRecordV1(
        persistedSupportingRaw,
      );
      if (canonicalSha256(persistedSupporting) !== canonicalSha256(expected)) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      persistedSupportingRecords.push(persistedSupporting);
    }
    const candidateReceipt = receiptFor({
      evidenceV1: evidence,
      manifestV1: canonicalManifest,
      itemV1: item,
      supportingChainFingerprintV1:
        canonicalSha256({authority: persistedAuthority,
          records: persistedSupportingRecords}),
    });
    const persistedReceiptRaw = await transaction.read(ad05dReceiptSealPathV1({
      bindingV1: input.bindingV1, itemV1: item,
    }));
    if (persistedReceiptRaw === null) ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    const persistedReceipt = parseCandidateAd05dEvidenceReceiptV1(
      persistedReceiptRaw,
    );
    if (canonicalSha256(persistedReceipt) !== canonicalSha256(candidateReceipt)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    return persistedReceipt;
  });
}

export function candidateAd05dMechanicalSupportV1(
  adapterIdV1: string,
): Readonly<{stateV1: "candidateEvidenceOnly"; adapterResultEligibleV1: false}> {
  if (adapterIdV1 !== "personal_storage_media" &&
      adapterIdV1 !== "shared_association_media") {
    ad05FailV1("AD05_UNSUPPORTED");
  }
  return Object.freeze({
    stateV1: "candidateEvidenceOnly",
    adapterResultEligibleV1: false,
  });
}

export function parseCandidateAd05dEvidenceReceiptV1(
  value: unknown,
): CandidateAd05dEvidenceReceiptV1 {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const data = value as Record<string, unknown>;
  const keys = [
    "schemaVersion", "adapterIdV1", "manifestFingerprintV1", "itemIdV1",
    "itemFingerprintV1", "evidenceFingerprintV1",
    "supportingChainFingerprintV1", "candidateOutcomeV1",
    "verifiedAtSecV1", "syntheticDispositionEvidenceVerifiedV1",
    "productionActivationAllowedV1", "adapterResultEligibleV1",
    "providerErasureVerifiedV1", "publicPrivacyVerifiedV1",
    "restoreSuppressionVerifiedV1", "receiptFingerprintV1",
  ];
  if (Object.keys(data).length !== keys.length ||
      !keys.every((key) => Object.prototype.hasOwnProperty.call(data, key)) ||
      data.schemaVersion !== 1 ||
      (data.adapterIdV1 !== "personal_storage_media" &&
       data.adapterIdV1 !== "shared_association_media") ||
      (data.candidateOutcomeV1 !== "personalVersionEraseVerified" &&
       data.candidateOutcomeV1 !== "sharedAccountReferenceDetachVerified" &&
       data.candidateOutcomeV1 !== "positiveNotApplicableEvidenceVerified") ||
      data.syntheticDispositionEvidenceVerifiedV1 !== true ||
      data.productionActivationAllowedV1 !== false ||
      data.adapterResultEligibleV1 !== false ||
      data.providerErasureVerifiedV1 !== false ||
      data.publicPrivacyVerifiedV1 !== false ||
      data.restoreSuppressionVerifiedV1 !== false) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const candidate = Object.freeze({
    schemaVersion: 1 as const,
    adapterIdV1: data.adapterIdV1 as Ad05dAdapterIdV1,
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    itemIdV1: ad04OpaqueIdV1(data.itemIdV1),
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
    supportingChainFingerprintV1:
      ad04HashV1(data.supportingChainFingerprintV1),
    candidateOutcomeV1: data.candidateOutcomeV1 as Ad05dCandidateOutcomeV1,
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    syntheticDispositionEvidenceVerifiedV1: true as const,
    productionActivationAllowedV1: false as const,
    adapterResultEligibleV1: false as const,
    providerErasureVerifiedV1: false as const,
    publicPrivacyVerifiedV1: false as const,
    restoreSuppressionVerifiedV1: false as const,
    receiptFingerprintV1: ad04HashV1(data.receiptFingerprintV1),
  });
  const {receiptFingerprintV1, ...core} = candidate;
  if (receiptFingerprintV1 !== ad05dEvidenceReceiptFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}
