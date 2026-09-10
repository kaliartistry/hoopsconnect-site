import {createHash} from "node:crypto";

import {
  accountDeletionAdapterIds,
  firebaseUidUtf16LeBase64Url,
} from "../domain/account_deletion_contract";
import {AuthIncarnationScopeV2} from "../domain/auth_incarnation_v2";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04NamespaceV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
} from "./ad04_records";

export const ACCOUNT_DELETION_AD05_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05_PRODUCTION_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05_SCHEMA_VERSION_V1 = 1;
export const ACCOUNT_DELETION_AD05_MAX_MANIFEST_ITEMS_V1 = 100;
export const ACCOUNT_DELETION_AD05_MAX_PAGE_ITEMS_V1 = 25;

export type AccountDeletionAdapterId = typeof accountDeletionAdapterIds[number];

export type Ad05DispositionActionV1 =
  "erase" | "detach" | "pseudonymize" | "restrictedRetention" |
  "accessRevokedAwaitingExpiry" | "notApplicable";

export class AccountDeletionAd05ErrorV1 extends Error {
  readonly codeV1: "AD05_INVALID_RECORD" | "AD05_BINDING_CONFLICT" |
    "AD05_INCOMPLETE_INVENTORY" | "AD05_UNSUPPORTED";

  constructor(codeV1: AccountDeletionAd05ErrorV1["codeV1"]) {
    super(codeV1);
    this.name = "AccountDeletionAd05ErrorV1";
    this.codeV1 = codeV1;
  }
}

export function ad05FailV1(codeV1: AccountDeletionAd05ErrorV1["codeV1"]): never {
  throw new AccountDeletionAd05ErrorV1(codeV1);
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return record;
}

function bool(value: unknown): boolean {
  if (typeof value !== "boolean") ad05FailV1("AD05_INVALID_RECORD");
  return value;
}

function adapterId(value: unknown): AccountDeletionAdapterId {
  const parsed = ad04OpaqueIdV1(value);
  if (!accountDeletionAdapterIds.includes(parsed as AccountDeletionAdapterId)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return parsed as AccountDeletionAdapterId;
}

function action(value: unknown): Ad05DispositionActionV1 {
  if (value !== "erase" && value !== "detach" && value !== "pseudonymize" &&
      value !== "restrictedRetention" &&
      value !== "accessRevokedAwaitingExpiry" && value !== "notApplicable") {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return value;
}

export interface CandidateAd05ExecutionBindingV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  lifecycleStateV1: "deleting";
  internalJobId: string;
  taskEffectIdV1: string;
  taskEffectFingerprintV1: string;
  adapterIdV1: AccountDeletionAdapterId;
  adapterVersionV1: string;
  effectVersionV1: string;
  policyDecisionIdV1: string;
  policyVersionV1: string;
  actionV1: Ad05DispositionActionV1;
  sourceManifestIdV1: string;
  sourceManifestVersionV1: string;
  bindingFingerprintV1: string;
}

type BindingWithoutFingerprintV1 = Omit<
  CandidateAd05ExecutionBindingV1, "bindingFingerprintV1"
>;

export function ad05ExecutionBindingFingerprintV1(
  binding: BindingWithoutFingerprintV1,
): string {
  return canonicalSha256({contract: "account-deletion-ad05-binding-v1", ...binding});
}

export function parseCandidateAd05ExecutionBindingV1(
  value: unknown,
): CandidateAd05ExecutionBindingV1 {
  const data = exactRecord(value, [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authUidUtf16LeBase64UrlV1", "generationHash", "acceptedLifecycleEpochV2",
    "lifecycleStateV1",
    "internalJobId", "taskEffectIdV1", "taskEffectFingerprintV1", "adapterIdV1",
    "adapterVersionV1", "effectVersionV1", "policyDecisionIdV1",
    "policyVersionV1", "actionV1", "sourceManifestIdV1",
    "sourceManifestVersionV1", "bindingFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.lifecycleStateV1 !== "deleting") {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const scope = ad04ScopeV1(data);
  const candidate: CandidateAd05ExecutionBindingV1 = Object.freeze({
    schemaVersion: 1,
    ...scope,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(data.authUidUtf16LeBase64UrlV1),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    lifecycleStateV1: "deleting",
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    taskEffectIdV1: ad04OpaqueIdV1(data.taskEffectIdV1),
    taskEffectFingerprintV1: ad04HashV1(data.taskEffectFingerprintV1),
    adapterIdV1: adapterId(data.adapterIdV1),
    adapterVersionV1: ad04OpaqueIdV1(data.adapterVersionV1),
    effectVersionV1: ad04OpaqueIdV1(data.effectVersionV1),
    policyDecisionIdV1: ad04NamespaceV1(data.policyDecisionIdV1),
    policyVersionV1: ad04OpaqueIdV1(data.policyVersionV1),
    actionV1: action(data.actionV1),
    sourceManifestIdV1: ad04OpaqueIdV1(data.sourceManifestIdV1),
    sourceManifestVersionV1: ad04OpaqueIdV1(data.sourceManifestVersionV1),
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
  });
  if (candidate.authUidUtf16LeBase64UrlV1 !==
      firebaseUidUtf16LeBase64Url(candidate.authUidV2) ||
      candidate.policyDecisionIdV1 !== `retention.${candidate.adapterIdV1}`) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {bindingFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05ExecutionBindingFingerprintV1(fingerprintInput) !== bindingFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function createCandidateAd05ExecutionBindingV1(
  input: Omit<BindingWithoutFingerprintV1, "schemaVersion" | "authUidUtf16LeBase64UrlV1">,
): CandidateAd05ExecutionBindingV1 {
  const scope = ad04ScopeV1(input);
  const withoutFingerprint: BindingWithoutFingerprintV1 = {
    schemaVersion: 1,
    ...input,
    ...scope,
    authUidUtf16LeBase64UrlV1: firebaseUidUtf16LeBase64Url(scope.authUidV2),
  };
  return parseCandidateAd05ExecutionBindingV1({
    ...withoutFingerprint,
    bindingFingerprintV1: ad05ExecutionBindingFingerprintV1(withoutFingerprint),
  });
}

export interface CandidateAd05ManifestItemV1 {
  schemaVersion: 1;
  itemIdV1: string;
  ordinalV1: number;
  adapterIdV1: AccountDeletionAdapterId;
  sourceSchemaIdV1: string;
  sourceSchemaVersionV1: string;
  sourceDocumentPathV1: string;
  sourceDocumentPathHashV1: string;
  sourceRecordVersionV1: string;
  provenanceIdV1: string;
  associationScopeHashV1: string | null;
  classificationV1: "applicable" | "notApplicable";
  itemFingerprintV1: string;
}

function safeDocumentPath(value: unknown): string {
  if (typeof value !== "string" || value.length < 3 || value.length > 1024 ||
      value.startsWith("/") || value.endsWith("/") || value.includes("//") ||
      value.split("/").length % 2 !== 0 ||
      value.split("/").some((segment) => segment === "." || segment === ".." ||
        !/^[A-Za-z0-9._~-]{1,256}$/.test(segment))) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return value;
}

export function ad05ManifestItemFingerprintV1(
  item: Omit<CandidateAd05ManifestItemV1, "itemFingerprintV1">,
): string {
  return canonicalSha256({contract: "account-deletion-ad05-manifest-item-v1", ...item});
}

export function parseCandidateAd05ManifestItemV1(
  value: unknown,
): CandidateAd05ManifestItemV1 {
  const data = exactRecord(value, [
    "schemaVersion", "itemIdV1", "ordinalV1", "adapterIdV1",
    "sourceSchemaIdV1", "sourceSchemaVersionV1", "sourceDocumentPathV1",
    "sourceDocumentPathHashV1", "sourceRecordVersionV1", "provenanceIdV1",
    "associationScopeHashV1", "classificationV1", "itemFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      (data.classificationV1 !== "applicable" &&
       data.classificationV1 !== "notApplicable")) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const sourceDocumentPathV1 = safeDocumentPath(data.sourceDocumentPathV1);
  const candidate: CandidateAd05ManifestItemV1 = Object.freeze({
    schemaVersion: 1,
    itemIdV1: ad04OpaqueIdV1(data.itemIdV1),
    ordinalV1: ad04CounterV1(data.ordinalV1),
    adapterIdV1: adapterId(data.adapterIdV1),
    sourceSchemaIdV1: ad04OpaqueIdV1(data.sourceSchemaIdV1),
    sourceSchemaVersionV1: ad04OpaqueIdV1(data.sourceSchemaVersionV1),
    sourceDocumentPathV1,
    sourceDocumentPathHashV1: ad04HashV1(data.sourceDocumentPathHashV1),
    sourceRecordVersionV1: ad04OpaqueIdV1(data.sourceRecordVersionV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    associationScopeHashV1: data.associationScopeHashV1 === null ? null :
      ad04HashV1(data.associationScopeHashV1),
    classificationV1: data.classificationV1,
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
  });
  if (candidate.sourceDocumentPathHashV1 !== canonicalSha256(sourceDocumentPathV1)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {itemFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05ManifestItemFingerprintV1(fingerprintInput) !== itemFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05SealedManifestV1 {
  schemaVersion: 1;
  manifestIdV1: string;
  manifestVersionV1: string;
  bindingFingerprintV1: string;
  adapterIdV1: AccountDeletionAdapterId;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
  referenceCoverageEvidenceIdV1: string;
  completeV1: true;
  sealedV1: true;
  itemCountV1: number;
  itemsV1: readonly CandidateAd05ManifestItemV1[];
  manifestFingerprintV1: string;
}

export function ad05ManifestFingerprintV1(
  manifest: Omit<CandidateAd05SealedManifestV1, "manifestFingerprintV1">,
): string {
  return canonicalSha256({contract: "account-deletion-ad05-manifest-v1", ...manifest});
}

export function parseCandidateAd05SealedManifestV1(
  value: unknown,
): CandidateAd05SealedManifestV1 {
  const data = exactRecord(value, [
    "schemaVersion", "manifestIdV1", "manifestVersionV1",
    "bindingFingerprintV1", "adapterIdV1", "inventorySourceIdV1",
    "inventorySourceVersionV1", "referenceCoverageEvidenceIdV1", "completeV1",
    "sealedV1", "itemCountV1", "itemsV1", "manifestFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.completeV1 !== true || data.sealedV1 !== true ||
      !Array.isArray(data.itemsV1) || data.itemsV1.length >
      ACCOUNT_DELETION_AD05_MAX_MANIFEST_ITEMS_V1) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const items = data.itemsV1.map(parseCandidateAd05ManifestItemV1);
  const itemCountV1 = ad04CounterV1(data.itemCountV1);
  if (itemCountV1 !== items.length ||
      items.some((item, index) => item.ordinalV1 !== index) ||
      new Set(items.map((item) => item.itemIdV1)).size !== items.length) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  const candidate: CandidateAd05SealedManifestV1 = Object.freeze({
    schemaVersion: 1,
    manifestIdV1: ad04OpaqueIdV1(data.manifestIdV1),
    manifestVersionV1: ad04OpaqueIdV1(data.manifestVersionV1),
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    adapterIdV1: adapterId(data.adapterIdV1),
    inventorySourceIdV1: ad04OpaqueIdV1(data.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(data.inventorySourceVersionV1),
    referenceCoverageEvidenceIdV1: ad04OpaqueIdV1(data.referenceCoverageEvidenceIdV1),
    completeV1: true,
    sealedV1: true,
    itemCountV1,
    itemsV1: Object.freeze(items),
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
  });
  if (items.some((item) => item.adapterIdV1 !== candidate.adapterIdV1)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {manifestFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05ManifestFingerprintV1(fingerprintInput) !== manifestFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05ItemReceiptV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  internalJobId: string;
  taskEffectIdV1: string;
  itemIdV1: string;
  bindingFingerprintV1: string;
  itemFingerprintV1: string;
  adapterIdV1: AccountDeletionAdapterId;
  effectVersionV1: string;
  policyDecisionIdV1: string;
  policyVersionV1: string;
  actionV1: Ad05DispositionActionV1;
  sourceRecordVersionBeforeV1: string;
  sourceRecordVersionAfterV1: string;
  evidenceCodeV1: string;
  committedAtSecV1: number;
  receiptFingerprintV1: string;
}

export function ad05ItemReceiptFingerprintV1(
  receipt: Omit<CandidateAd05ItemReceiptV1, "receiptFingerprintV1">,
): string {
  return canonicalSha256({contract: "account-deletion-ad05-item-receipt-v1", ...receipt});
}

export function parseCandidateAd05ItemReceiptV1(
  value: unknown,
): CandidateAd05ItemReceiptV1 {
  const data = exactRecord(value, [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "internalJobId", "taskEffectIdV1", "itemIdV1", "bindingFingerprintV1",
    "itemFingerprintV1", "adapterIdV1", "effectVersionV1",
    "policyDecisionIdV1", "policyVersionV1", "actionV1",
    "sourceRecordVersionBeforeV1", "sourceRecordVersionAfterV1",
    "evidenceCodeV1", "committedAtSecV1", "receiptFingerprintV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  const candidate: CandidateAd05ItemReceiptV1 = Object.freeze({
    schemaVersion: 1,
    ...ad04ScopeV1(data),
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    taskEffectIdV1: ad04OpaqueIdV1(data.taskEffectIdV1),
    itemIdV1: ad04OpaqueIdV1(data.itemIdV1),
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    itemFingerprintV1: ad04HashV1(data.itemFingerprintV1),
    adapterIdV1: adapterId(data.adapterIdV1),
    effectVersionV1: ad04OpaqueIdV1(data.effectVersionV1),
    policyDecisionIdV1: ad04NamespaceV1(data.policyDecisionIdV1),
    policyVersionV1: ad04OpaqueIdV1(data.policyVersionV1),
    actionV1: action(data.actionV1),
    sourceRecordVersionBeforeV1: ad04OpaqueIdV1(data.sourceRecordVersionBeforeV1),
    sourceRecordVersionAfterV1: ad04OpaqueIdV1(data.sourceRecordVersionAfterV1),
    evidenceCodeV1: ad04OpaqueIdV1(data.evidenceCodeV1),
    committedAtSecV1: ad04CounterV1(data.committedAtSecV1),
    receiptFingerprintV1: ad04HashV1(data.receiptFingerprintV1),
  });
  if (candidate.policyDecisionIdV1 !== `retention.${candidate.adapterIdV1}`) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {receiptFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05ItemReceiptFingerprintV1(fingerprintInput) !== receiptFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05ContinuationV1 {
  schemaVersion: 1;
  bindingFingerprintV1: string;
  manifestFingerprintV1: string;
  nextOrdinalV1: number;
  nextItemIdV1: string | null;
  committedItemCountV1: number;
  completeV1: boolean;
  continuationFingerprintV1: string;
}

export function ad05ContinuationFingerprintV1(
  continuation: Omit<CandidateAd05ContinuationV1, "continuationFingerprintV1">,
): string {
  return canonicalSha256({contract: "account-deletion-ad05-continuation-v1", ...continuation});
}

export function parseCandidateAd05ContinuationV1(
  value: unknown,
): CandidateAd05ContinuationV1 {
  const data = exactRecord(value, [
    "schemaVersion", "bindingFingerprintV1", "manifestFingerprintV1",
    "nextOrdinalV1", "nextItemIdV1", "committedItemCountV1", "completeV1",
    "continuationFingerprintV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  const candidate: CandidateAd05ContinuationV1 = Object.freeze({
    schemaVersion: 1,
    bindingFingerprintV1: ad04HashV1(data.bindingFingerprintV1),
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
    nextOrdinalV1: ad04CounterV1(data.nextOrdinalV1),
    nextItemIdV1: data.nextItemIdV1 === null ? null : ad04OpaqueIdV1(data.nextItemIdV1),
    committedItemCountV1: ad04CounterV1(data.committedItemCountV1),
    completeV1: bool(data.completeV1),
    continuationFingerprintV1: ad04HashV1(data.continuationFingerprintV1),
  });
  if (candidate.nextOrdinalV1 !== candidate.committedItemCountV1 ||
      (candidate.completeV1 !== (candidate.nextItemIdV1 === null))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {continuationFingerprintV1, ...fingerprintInput} = candidate;
  if (ad05ContinuationFingerprintV1(fingerprintInput) !== continuationFingerprintV1) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

function hashedId(prefix: string, value: unknown): string {
  return `${prefix}_${canonicalSha256(value)}`;
}

export function ad05ManifestPathV1(binding: CandidateAd05ExecutionBindingV1): string {
  const parsed = parseCandidateAd05ExecutionBindingV1(binding);
  return `accountDeletionJobsV1/${parsed.internalJobId}/ad05ManifestsV1/${
    hashedId("manifest", parsed.sourceManifestIdV1)}`;
}

export function ad05ItemReceiptPathV1(input: {
  binding: CandidateAd05ExecutionBindingV1;
  itemIdV1: string;
}): string {
  const binding = parseCandidateAd05ExecutionBindingV1(input.binding);
  const itemIdV1 = ad04OpaqueIdV1(input.itemIdV1);
  return `accountDeletionJobsV1/${binding.internalJobId}/ad05ItemReceiptsV1/${
    hashedId("item", {effect: binding.taskEffectIdV1, itemIdV1})}`;
}

export function ad05ContinuationPathV1(binding: CandidateAd05ExecutionBindingV1): string {
  const parsed = parseCandidateAd05ExecutionBindingV1(binding);
  return `accountDeletionJobsV1/${parsed.internalJobId}/ad05ContinuationsV1/${
    hashedId("effect", parsed.taskEffectIdV1)}`;
}

export function ad05PrivateEvidenceRefV1(value: unknown): string {
  return `ad05_${createHash("sha256").update(canonicalSha256(value)).digest("hex")}`;
}
