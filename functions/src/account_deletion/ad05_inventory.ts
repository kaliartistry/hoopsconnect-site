import {canonicalSha256} from "../domain/official_stats_contract";
import {
  ACCOUNT_DELETION_AD05_MAX_MANIFEST_ITEMS_V1,
  AccountDeletionAdapterId,
  CandidateAd05ExecutionBindingV1,
  CandidateAd05ManifestItemV1,
  CandidateAd05SealedManifestV1,
  ad05FailV1,
  ad05ManifestFingerprintV1,
  ad05ManifestItemFingerprintV1,
  parseCandidateAd05ExecutionBindingV1,
  parseCandidateAd05ManifestItemV1,
  parseCandidateAd05SealedManifestV1,
  assertCandidateAd05ManifestBindingV1,
} from "./ad05_records";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
} from "./ad04_records";

export const ad05InventoryClassificationsV1 = [
  "applicable", "notApplicable", "unclassified", "unknownSchema",
  "missingProvenance", "missingReferenceCoverage",
] as const;
export type Ad05InventoryClassificationV1 =
  typeof ad05InventoryClassificationsV1[number];

export interface CandidateAd05TrustedInventoryRecordV1 {
  schemaVersion: 1;
  adapterIdV1: AccountDeletionAdapterId;
  sourceSchemaIdV1: string;
  sourceSchemaVersionV1: string;
  sourceDocumentPathV1: string;
  sourceRecordVersionV1: string;
  provenanceIdV1: string | null;
  associationScopeHashV1: string | null;
  classificationV1: Ad05InventoryClassificationV1;
}

export interface CandidateAd05TrustedInventoryPageV1 {
  schemaVersion: 1;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
  completeV1: boolean;
  continuationTokenV1: null;
  referenceCoverageVerifiedV1: boolean;
  referenceCoverageEvidenceIdV1: string | null;
  recordsV1: readonly CandidateAd05TrustedInventoryRecordV1[];
}

/**
 * Implementations must enumerate from a trusted source owned by the adapter.
 * There is intentionally no caller-supplied path, name, email, jersey, or
 * reverse-index key in this interface.
 */
export interface CandidateAd05TrustedInventorySourceV1 {
  readonly adapterIdV1: AccountDeletionAdapterId;
  enumerateBoundRecordsV1(input: {
    binding: CandidateAd05ExecutionBindingV1;
    limitV1: number;
  }): Promise<unknown>;
}

export interface CandidateAd05RemainingReferenceVerifierV1 {
  verifyRemainingReferencesV1(input: {
    binding: CandidateAd05ExecutionBindingV1;
    manifest: CandidateAd05SealedManifestV1;
    receiptSet: CandidateAd05ReceiptSetSummaryV1;
  }): Promise<unknown>;
}

export interface CandidateAd05ReceiptSetSummaryV1 {
  schemaVersion: 1;
  bindingFingerprintV1: string;
  manifestFingerprintV1: string;
  itemCountV1: number;
  receiptSetFingerprintV1: string;
  latestReceiptCommittedAtSecV1: number;
}

export interface CandidateAd05RemainingReferenceEvidenceV1 {
  schemaVersion: 1;
  manifestFingerprintV1: string;
  receiptSetFingerprintV1: string;
  latestReceiptCommittedAtSecV1: number;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
  independentSourceIdV1: string;
  independentSourceVersionV1: string;
  independenceProofIdV1: string;
  completeV1: true;
  remainingReferenceCountV1: number;
  verifiedAtSecV1: number;
  evidenceIdV1: string;
  evidenceFingerprintV1: string;
}

export function parseCandidateAd05ReceiptSetSummaryV1(
  value: unknown,
): CandidateAd05ReceiptSetSummaryV1 {
  const data = exact(value, [
    "schemaVersion", "bindingFingerprintV1", "manifestFingerprintV1",
    "itemCountV1", "receiptSetFingerprintV1", "latestReceiptCommittedAtSecV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  return Object.freeze({
    schemaVersion: 1,
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    itemCountV1: ad04CounterV1(data.itemCountV1),
    receiptSetFingerprintV1: ad04HashV1(data.receiptSetFingerprintV1),
    latestReceiptCommittedAtSecV1: ad04CounterV1(
      data.latestReceiptCommittedAtSecV1,
    ),
  });
}

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return record;
}

function parseClassification(value: unknown): Ad05InventoryClassificationV1 {
  if (typeof value !== "string" ||
      !ad05InventoryClassificationsV1.includes(
        value as Ad05InventoryClassificationV1,
      )) ad05FailV1("AD05_INVALID_RECORD");
  return value as Ad05InventoryClassificationV1;
}

function parseTrustedRecordV1(value: unknown): CandidateAd05TrustedInventoryRecordV1 {
  const data = exact(value, [
    "schemaVersion", "adapterIdV1", "sourceSchemaIdV1", "sourceSchemaVersionV1",
    "sourceDocumentPathV1", "sourceRecordVersionV1", "provenanceIdV1",
    "associationScopeHashV1", "classificationV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  return Object.freeze({
    schemaVersion: 1,
    adapterIdV1: ad04OpaqueIdV1(data.adapterIdV1) as AccountDeletionAdapterId,
    sourceSchemaIdV1: ad04OpaqueIdV1(data.sourceSchemaIdV1),
    sourceSchemaVersionV1: ad04OpaqueIdV1(data.sourceSchemaVersionV1),
    sourceDocumentPathV1: typeof data.sourceDocumentPathV1 === "string" ?
      data.sourceDocumentPathV1 : ad05FailV1("AD05_INVALID_RECORD"),
    sourceRecordVersionV1: ad04OpaqueIdV1(data.sourceRecordVersionV1),
    provenanceIdV1: data.provenanceIdV1 === null ? null :
      ad04OpaqueIdV1(data.provenanceIdV1),
    associationScopeHashV1: data.associationScopeHashV1 === null ? null :
      ad04HashV1(data.associationScopeHashV1),
    classificationV1: parseClassification(data.classificationV1),
  });
}

export function parseCandidateAd05TrustedInventoryPageV1(
  value: unknown,
): CandidateAd05TrustedInventoryPageV1 {
  const data = exact(value, [
    "schemaVersion", "inventorySourceIdV1", "inventorySourceVersionV1",
    "completeV1", "continuationTokenV1", "referenceCoverageVerifiedV1",
    "referenceCoverageEvidenceIdV1", "recordsV1",
  ]);
  if (data.schemaVersion !== 1 || typeof data.completeV1 !== "boolean" ||
      data.continuationTokenV1 !== null ||
      typeof data.referenceCoverageVerifiedV1 !== "boolean" ||
      !Array.isArray(data.recordsV1) ||
      data.recordsV1.length > ACCOUNT_DELETION_AD05_MAX_MANIFEST_ITEMS_V1) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return Object.freeze({
    schemaVersion: 1,
    inventorySourceIdV1: ad04OpaqueIdV1(data.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(data.inventorySourceVersionV1),
    completeV1: data.completeV1,
    continuationTokenV1: null,
    referenceCoverageVerifiedV1: data.referenceCoverageVerifiedV1,
    referenceCoverageEvidenceIdV1: data.referenceCoverageEvidenceIdV1 === null ? null :
      ad04OpaqueIdV1(data.referenceCoverageEvidenceIdV1),
    recordsV1: Object.freeze(data.recordsV1.map(parseTrustedRecordV1)),
  });
}

export function deterministicAd05ManifestIdV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
}): string {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  return deterministicAd05SourceManifestIdV1({
    internalJobId: binding.internalJobId,
    taskEffectIdV1: binding.taskEffectIdV1,
    adapterIdV1: binding.adapterIdV1,
    inventorySourceIdV1: input.inventorySourceIdV1,
    inventorySourceVersionV1: input.inventorySourceVersionV1,
  });
}

export function deterministicAd05SourceManifestIdV1(input: {
  internalJobId: string;
  taskEffectIdV1: string;
  adapterIdV1: AccountDeletionAdapterId;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
}): string {
  return `manifest_${canonicalSha256({
    contract: "account-deletion-ad05-manifest-identity-v1",
    internalJobId: ad04OpaqueIdV1(input.internalJobId),
    taskEffectIdV1: ad04OpaqueIdV1(input.taskEffectIdV1),
    adapterIdV1: input.adapterIdV1,
    inventorySourceIdV1: ad04OpaqueIdV1(input.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(input.inventorySourceVersionV1),
  })}`;
}

export function deterministicAd05ManifestItemIdV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  record: CandidateAd05TrustedInventoryRecordV1;
}): string {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const record = parseTrustedRecordV1(input.record);
  return `item_${canonicalSha256({
    contract: "account-deletion-ad05-item-identity-v1",
    bindingFingerprintV1: binding.bindingFingerprintV1,
    adapterIdV1: record.adapterIdV1,
    sourceSchemaIdV1: record.sourceSchemaIdV1,
    sourceSchemaVersionV1: record.sourceSchemaVersionV1,
    sourceDocumentPathV1: record.sourceDocumentPathV1,
    sourceRecordVersionV1: record.sourceRecordVersionV1,
    provenanceIdV1: record.provenanceIdV1,
  })}`;
}

export async function buildCandidateAd05SealedManifestV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  source: CandidateAd05TrustedInventorySourceV1;
}): Promise<CandidateAd05SealedManifestV1> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  if (input.source.adapterIdV1 !== binding.adapterIdV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const page = parseCandidateAd05TrustedInventoryPageV1(
    await input.source.enumerateBoundRecordsV1({
      binding,
      limitV1: ACCOUNT_DELETION_AD05_MAX_MANIFEST_ITEMS_V1,
    }),
  );
  if (page.completeV1 !== true || page.referenceCoverageVerifiedV1 !== true ||
      page.referenceCoverageEvidenceIdV1 === null ||
      page.recordsV1.some((record) =>
        record.adapterIdV1 !== binding.adapterIdV1 ||
        record.provenanceIdV1 === null ||
        record.classificationV1 !== "applicable" &&
        record.classificationV1 !== "notApplicable")) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const sorted = [...page.recordsV1].sort((left, right) =>
    deterministicAd05ManifestItemIdV1({binding, record: left}).localeCompare(
      deterministicAd05ManifestItemIdV1({binding, record: right}),
    ));
  if (new Set(sorted.map((record) => record.sourceDocumentPathV1)).size !== sorted.length) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const items = sorted.map((record, ordinalV1): CandidateAd05ManifestItemV1 => {
    const withoutFingerprint: Omit<CandidateAd05ManifestItemV1, "itemFingerprintV1"> = {
      schemaVersion: 1,
      itemIdV1: deterministicAd05ManifestItemIdV1({binding, record}),
      ordinalV1,
      adapterIdV1: binding.adapterIdV1,
      sourceSchemaIdV1: record.sourceSchemaIdV1,
      sourceSchemaVersionV1: record.sourceSchemaVersionV1,
      sourceDocumentPathV1: record.sourceDocumentPathV1,
      sourceDocumentPathHashV1: canonicalSha256(record.sourceDocumentPathV1),
      sourceRecordVersionV1: record.sourceRecordVersionV1,
      provenanceIdV1: record.provenanceIdV1 as string,
      associationScopeHashV1: record.associationScopeHashV1,
      classificationV1: record.classificationV1 as "applicable" | "notApplicable",
    };
    return parseCandidateAd05ManifestItemV1({
      ...withoutFingerprint,
      itemFingerprintV1: ad05ManifestItemFingerprintV1(withoutFingerprint),
    });
  });
  const manifestIdV1 = deterministicAd05ManifestIdV1({
    binding,
    inventorySourceIdV1: page.inventorySourceIdV1,
    inventorySourceVersionV1: page.inventorySourceVersionV1,
  });
  if (manifestIdV1 !== binding.sourceManifestIdV1 ||
      page.inventorySourceVersionV1 !== binding.sourceManifestVersionV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const withoutFingerprint: Omit<CandidateAd05SealedManifestV1,
    "manifestFingerprintV1"> = {
    schemaVersion: 1,
    manifestIdV1,
    manifestVersionV1: page.inventorySourceVersionV1,
    bindingFingerprintV1: binding.bindingFingerprintV1,
    adapterIdV1: binding.adapterIdV1,
    inventorySourceIdV1: page.inventorySourceIdV1,
    inventorySourceVersionV1: page.inventorySourceVersionV1,
    referenceCoverageEvidenceIdV1: page.referenceCoverageEvidenceIdV1,
    completeV1: true,
    sealedV1: true,
    itemCountV1: items.length,
    itemsV1: Object.freeze(items),
  };
  const manifest = parseCandidateAd05SealedManifestV1({
    ...withoutFingerprint,
    manifestFingerprintV1: ad05ManifestFingerprintV1(withoutFingerprint),
  });
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  return manifest;
}

export function ad05RemainingReferenceEvidenceFingerprintV1(
  evidence: Omit<CandidateAd05RemainingReferenceEvidenceV1,
    "evidenceFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05-remaining-reference-evidence-v1",
    ...evidence,
  });
}

export function parseCandidateAd05RemainingReferenceEvidenceV1(
  value: unknown,
): CandidateAd05RemainingReferenceEvidenceV1 {
  const data = exact(value, [
    "schemaVersion", "manifestFingerprintV1", "receiptSetFingerprintV1",
    "latestReceiptCommittedAtSecV1", "inventorySourceIdV1",
    "inventorySourceVersionV1", "independentSourceIdV1",
    "independentSourceVersionV1", "independenceProofIdV1", "completeV1",
    "remainingReferenceCountV1", "verifiedAtSecV1", "evidenceIdV1",
    "evidenceFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.completeV1 !== true) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const candidate: CandidateAd05RemainingReferenceEvidenceV1 = Object.freeze({
    schemaVersion: 1,
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    receiptSetFingerprintV1: ad04HashV1(data.receiptSetFingerprintV1),
    latestReceiptCommittedAtSecV1: ad04CounterV1(
      data.latestReceiptCommittedAtSecV1,
    ),
    inventorySourceIdV1: ad04OpaqueIdV1(data.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(data.inventorySourceVersionV1),
    independentSourceIdV1: ad04OpaqueIdV1(data.independentSourceIdV1),
    independentSourceVersionV1: ad04OpaqueIdV1(data.independentSourceVersionV1),
    independenceProofIdV1: ad04OpaqueIdV1(data.independenceProofIdV1),
    completeV1: true,
    remainingReferenceCountV1: ad04CounterV1(data.remainingReferenceCountV1),
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    evidenceIdV1: ad04OpaqueIdV1(data.evidenceIdV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
  });
  if (candidate.independentSourceIdV1 === candidate.inventorySourceIdV1) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const {evidenceFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05RemainingReferenceEvidenceFingerprintV1(fingerprintInput) !==
      evidenceFingerprintV1) ad05FailV1("AD05_BINDING_CONFLICT");
  return candidate;
}

export async function verifyCandidateAd05RemainingReferencesV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  manifest: CandidateAd05SealedManifestV1;
  receiptSet: CandidateAd05ReceiptSetSummaryV1;
  verifier: CandidateAd05RemainingReferenceVerifierV1;
}): Promise<CandidateAd05RemainingReferenceEvidenceV1> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const manifest = parseCandidateAd05SealedManifestV1(input.manifest);
  assertCandidateAd05ManifestBindingV1({binding, manifest});
  const receiptSet = parseCandidateAd05ReceiptSetSummaryV1(input.receiptSet);
  if (receiptSet.bindingFingerprintV1 !== binding.bindingFingerprintV1 ||
      receiptSet.manifestFingerprintV1 !== manifest.manifestFingerprintV1 ||
      receiptSet.itemCountV1 !== manifest.itemCountV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const evidence = parseCandidateAd05RemainingReferenceEvidenceV1(
    await input.verifier.verifyRemainingReferencesV1({
      binding, manifest, receiptSet,
    }),
  );
  if (evidence.manifestFingerprintV1 !== manifest.manifestFingerprintV1 ||
      evidence.receiptSetFingerprintV1 !== receiptSet.receiptSetFingerprintV1 ||
      evidence.latestReceiptCommittedAtSecV1 !==
        receiptSet.latestReceiptCommittedAtSecV1 ||
      evidence.inventorySourceIdV1 !== manifest.inventorySourceIdV1 ||
      evidence.inventorySourceVersionV1 !== manifest.inventorySourceVersionV1 ||
      evidence.verifiedAtSecV1 < receiptSet.latestReceiptCommittedAtSecV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return evidence;
}
