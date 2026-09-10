import {canonicalSha256} from "../domain/official_stats_contract";
import {
  CandidateAd05ExecutionBindingV1,
  ad05FailV1,
  parseCandidateAd05ExecutionBindingV1,
} from "./ad05_records";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
} from "./ad04_records";

export const ACCOUNT_DELETION_AD05E_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_PRODUCTION_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_TERMINAL_ADAPTER_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_PROVIDER_REVOCATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_DELIVERY_RECALL_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_LIVE_SUPPRESSION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05E_DEVICE_CLEARING_ALLOWED_V1 = false;

export const ad05eReferenceClassesV1 = [
  "registeredInstallation",
  "notificationPreference",
  "legacyProfileSurface",
  "queuedRecipient",
  "deliveryAttempt",
  "deletionBarrier",
  "retryReplaySource",
] as const;

export type Ad05eReferenceClassV1 = typeof ad05eReferenceClassesV1[number];
export type Ad05eOwnerRelationV1 =
  "deletingAccount" | "laterGeneration" | "otherOwner" | "unattributable";
export type Ad05eDispositionV1 =
  "plannedRemoveAccountReference" | "preserveSharedHistory" |
  "unresolvedExternalDependency";
export type Ad05eDeliveryStateV1 =
  "reserved" | "dispatchCommitted" | "submitted" | "succeeded" |
  "partial" | "failed" | "skipped";
export type Ad05eBarrierStateV1 = "held" | "released";
export type Ad05eCoverageStateV1 =
  "completeEnumerated" | "positiveAbsenceVerified";
export type Ad05eCandidateOutcomeV1 =
  "syntheticInventoryVerified" |
  "syntheticInventoryVerifiedWithUnresolvedDispatch" |
  "positiveNotApplicableEvidenceVerified";

export interface CandidateAd05eReferenceV1 {
  schemaVersion: 1;
  referenceIdV1: string;
  referenceClassV1: Ad05eReferenceClassV1;
  sourcePathHashV1: string;
  sourceSchemaIdV1: string;
  sourceSchemaVersionV1: string;
  sourceRecordVersionV1: string;
  provenanceIdV1: string;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidUtf16LeBase64UrlV1: string;
  accountGenerationOwnerV1: string;
  sourceLifecycleEpochV2: number;
  associationScopeHashV1: string;
  ownerRelationV1: Ad05eOwnerRelationV1;
  installationSlotV2: string | null;
  preferenceNameV2: "ackReminders" | "statReminders" | "newPosts" | null;
  preferenceValueV2: boolean | null;
  tokenFingerprintV1: string | null;
  deliveryStateV2: Ad05eDeliveryStateV1 | null;
  barrierStateV2: Ad05eBarrierStateV1 | null;
  payloadHashV2: string | null;
  intendedRecipientSetHashV2: string | null;
  dispositionV1: Ad05eDispositionV1;
  referenceFingerprintV1: string;
}

export interface CandidateAd05eCoverageV1 {
  schemaVersion: 1;
  referenceClassV1: Ad05eReferenceClassV1;
  coverageStateV1: Ad05eCoverageStateV1;
  enumeratedCountV1: number;
  coverageSourcePathHashV1: string;
  coverageSourceVersionV1: string;
  coverageSourceHashV1: string;
  coverageFingerprintV1: string;
}

export interface CandidateAd05eEvidenceV1 {
  schemaVersion: 1;
  adapterIdV1: "device_fcm_preferences";
  bindingV1: CandidateAd05ExecutionBindingV1;
  sourceDocumentPathHashV1: string;
  sourceSchemaIdV1: "account_deletion_ad05e_fcm_preferences_evidence_v1";
  sourceSchemaVersionV1: "schema_v1";
  provenanceIdV1: string;
  producerIdV1: "synthetic_notification_inventory_v1";
  producerVersionV1: 1;
  inventoryCompleteV1: true;
  referenceCoverageCompleteV1: true;
  highWaterMarkV1: string;
  associationScopeHashV1: string;
  referencesV1: readonly CandidateAd05eReferenceV1[];
  coverageV1: readonly CandidateAd05eCoverageV1[];
  candidateOutcomeV1: Ad05eCandidateOutcomeV1;
  observedAtSecV1: number;
  recordVersionV1: string;
  evidenceFingerprintV1: string;
}

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return record;
}

function nullableHash(value: unknown): string | null {
  return value === null ? null : ad04HashV1(value);
}

function nullableOpaque(value: unknown): string | null {
  return value === null ? null : ad04OpaqueIdV1(value);
}

function enumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
): T {
  if (!allowed.includes(value as T)) ad05FailV1("AD05_INVALID_RECORD");
  return value as T;
}

export function ad05eReferenceFingerprintV1(value: Omit<
  CandidateAd05eReferenceV1, "referenceFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-reference-v1",
    ...value,
  });
}

export function ad05eCoverageFingerprintV1(value: Omit<
  CandidateAd05eCoverageV1, "coverageFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-coverage-v1",
    ...value,
  });
}

export function ad05eEvidenceFingerprintV1(value: Omit<
  CandidateAd05eEvidenceV1, "evidenceFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05e-evidence-v1",
    ...value,
  });
}

function parseReference(value: unknown): CandidateAd05eReferenceV1 {
  const data = exact(value, [
    "schemaVersion", "referenceIdV1", "referenceClassV1",
    "sourcePathHashV1", "sourceSchemaIdV1", "sourceSchemaVersionV1",
    "sourceRecordVersionV1", "provenanceIdV1", "authProjectIdV2",
    "authTenantIdV2", "authUidUtf16LeBase64UrlV1",
    "accountGenerationOwnerV1", "sourceLifecycleEpochV2",
    "associationScopeHashV1", "ownerRelationV1", "installationSlotV2",
    "preferenceNameV2", "preferenceValueV2", "tokenFingerprintV1",
    "deliveryStateV2", "barrierStateV2", "payloadHashV2",
    "intendedRecipientSetHashV2", "dispositionV1",
    "referenceFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      (data.authTenantIdV2 !== null && typeof data.authTenantIdV2 !== "string") ||
      (data.preferenceValueV2 !== null &&
       typeof data.preferenceValueV2 !== "boolean")) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const referenceClassV1 = enumValue(data.referenceClassV1,
    ad05eReferenceClassesV1);
  const ownerRelationV1 = enumValue(data.ownerRelationV1, [
    "deletingAccount", "laterGeneration", "otherOwner", "unattributable",
  ] as const);
  const dispositionV1 = enumValue(data.dispositionV1, [
    "plannedRemoveAccountReference", "preserveSharedHistory",
    "unresolvedExternalDependency",
  ] as const);
  const deliveryStateV2 = data.deliveryStateV2 === null ? null :
    enumValue(data.deliveryStateV2, [
      "reserved", "dispatchCommitted", "submitted", "succeeded", "partial",
      "failed", "skipped",
    ] as const);
  const barrierStateV2 = data.barrierStateV2 === null ? null :
    enumValue(data.barrierStateV2, ["held", "released"] as const);
  const preferenceNameV2 = data.preferenceNameV2 === null ? null :
    enumValue(data.preferenceNameV2,
      ["ackReminders", "statReminders", "newPosts"] as const);
  const candidate: CandidateAd05eReferenceV1 = Object.freeze({
    schemaVersion: 1,
    referenceIdV1: ad04OpaqueIdV1(data.referenceIdV1),
    referenceClassV1,
    sourcePathHashV1: ad04HashV1(data.sourcePathHashV1),
    sourceSchemaIdV1: ad04OpaqueIdV1(data.sourceSchemaIdV1),
    sourceSchemaVersionV1: ad04OpaqueIdV1(data.sourceSchemaVersionV1),
    sourceRecordVersionV1: ad04OpaqueIdV1(data.sourceRecordVersionV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    authProjectIdV2: ad04OpaqueIdV1(data.authProjectIdV2),
    authTenantIdV2: nullableOpaque(data.authTenantIdV2),
    authUidUtf16LeBase64UrlV1:
      ad04OpaqueIdV1(data.authUidUtf16LeBase64UrlV1),
    accountGenerationOwnerV1: ad04HashV1(data.accountGenerationOwnerV1),
    sourceLifecycleEpochV2: ad04CounterV1(data.sourceLifecycleEpochV2),
    associationScopeHashV1: ad04HashV1(data.associationScopeHashV1),
    ownerRelationV1,
    installationSlotV2: nullableOpaque(data.installationSlotV2),
    preferenceNameV2,
    preferenceValueV2: data.preferenceValueV2 as boolean | null,
    tokenFingerprintV1: nullableHash(data.tokenFingerprintV1),
    deliveryStateV2,
    barrierStateV2,
    payloadHashV2: nullableHash(data.payloadHashV2),
    intendedRecipientSetHashV2:
      nullableHash(data.intendedRecipientSetHashV2),
    dispositionV1,
    referenceFingerprintV1: ad04HashV1(data.referenceFingerprintV1),
  });
  const {referenceFingerprintV1, ...core} = candidate;
  if (referenceFingerprintV1 !== ad05eReferenceFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  assertReferenceShape(candidate);
  return candidate;
}

function assertReferenceShape(value: CandidateAd05eReferenceV1): void {
  const registration = value.referenceClassV1 === "registeredInstallation";
  const preference = value.referenceClassV1 === "notificationPreference";
  const attempt = value.referenceClassV1 === "deliveryAttempt";
  const barrier = value.referenceClassV1 === "deletionBarrier";
  const tokenSurface = registration ||
    value.referenceClassV1 === "legacyProfileSurface";
  const expectedSchemaIdV1 = `ad05e_${value.referenceClassV1}_v1`;
  const expectedProvenanceIdV1 =
    `registered_synthetic_${value.referenceClassV1}_v1`;
  if (value.sourceSchemaIdV1 !== expectedSchemaIdV1 ||
      value.sourceSchemaVersionV1 !== "schema_v1" ||
      value.provenanceIdV1 !== expectedProvenanceIdV1 ||
      (value.installationSlotV2 !== null) !== registration ||
      (registration && !/^slot[0-7]$/.test(value.installationSlotV2!)) ||
      (value.preferenceNameV2 !== null) !== preference ||
      (value.preferenceValueV2 !== null) !== preference ||
      (value.tokenFingerprintV1 !== null) !== tokenSurface ||
      (value.deliveryStateV2 !== null) !== attempt ||
      (value.barrierStateV2 !== null) !== barrier ||
      (value.payloadHashV2 !== null) !== attempt ||
      (value.intendedRecipientSetHashV2 !== null) !== attempt) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const uncertainAttempt = attempt && [
    "reserved", "dispatchCommitted", "submitted",
  ].includes(value.deliveryStateV2!);
  const requiresUnresolved = uncertainAttempt ||
    barrier && value.barrierStateV2 === "held" ||
    value.ownerRelationV1 === "unattributable";
  if (requiresUnresolved !==
      (value.dispositionV1 === "unresolvedExternalDependency")) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  if (value.ownerRelationV1 === "laterGeneration" ||
      value.ownerRelationV1 === "otherOwner") {
    if (value.dispositionV1 !== "preserveSharedHistory") {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
  } else if (value.ownerRelationV1 === "unattributable" &&
      value.dispositionV1 !== "unresolvedExternalDependency") {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

function parseCoverage(value: unknown): CandidateAd05eCoverageV1 {
  const data = exact(value, [
    "schemaVersion", "referenceClassV1", "coverageStateV1",
    "enumeratedCountV1", "coverageSourcePathHashV1",
    "coverageSourceVersionV1", "coverageSourceHashV1",
    "coverageFingerprintV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  const candidate: CandidateAd05eCoverageV1 = Object.freeze({
    schemaVersion: 1,
    referenceClassV1: enumValue(data.referenceClassV1,
      ad05eReferenceClassesV1),
    coverageStateV1: enumValue(data.coverageStateV1,
      ["completeEnumerated", "positiveAbsenceVerified"] as const),
    enumeratedCountV1: ad04CounterV1(data.enumeratedCountV1),
    coverageSourcePathHashV1:
      ad04HashV1(data.coverageSourcePathHashV1),
    coverageSourceVersionV1:
      ad04OpaqueIdV1(data.coverageSourceVersionV1),
    coverageSourceHashV1: ad04HashV1(data.coverageSourceHashV1),
    coverageFingerprintV1: ad04HashV1(data.coverageFingerprintV1),
  });
  const {coverageFingerprintV1, ...core} = candidate;
  if (coverageFingerprintV1 !== ad05eCoverageFingerprintV1(core) ||
      candidate.coverageSourcePathHashV1 !== canonicalSha256(
        `registered-synthetic/coverage/${candidate.referenceClassV1}`,
      ) || candidate.coverageSourceVersionV1 !== "coverage-v1" ||
      (candidate.coverageStateV1 === "positiveAbsenceVerified" &&
       candidate.enumeratedCountV1 !== 0)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function parseCandidateAd05eEvidenceV1(
  value: unknown,
): CandidateAd05eEvidenceV1 {
  const data = exact(value, [
    "schemaVersion", "adapterIdV1", "bindingV1",
    "sourceDocumentPathHashV1", "sourceSchemaIdV1",
    "sourceSchemaVersionV1", "provenanceIdV1", "producerIdV1",
    "producerVersionV1", "inventoryCompleteV1",
    "referenceCoverageCompleteV1", "highWaterMarkV1",
    "associationScopeHashV1", "referencesV1", "coverageV1",
    "candidateOutcomeV1", "observedAtSecV1",
    "recordVersionV1", "evidenceFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      data.adapterIdV1 !== "device_fcm_preferences" ||
      data.sourceSchemaIdV1 !==
        "account_deletion_ad05e_fcm_preferences_evidence_v1" ||
      data.sourceSchemaVersionV1 !== "schema_v1" ||
      data.producerIdV1 !== "synthetic_notification_inventory_v1" ||
      data.producerVersionV1 !== 1 || data.inventoryCompleteV1 !== true ||
      data.referenceCoverageCompleteV1 !== true ||
      !Array.isArray(data.referencesV1) || !Array.isArray(data.coverageV1) ||
      data.referencesV1.length > 200 ||
      JSON.stringify(data).length > 250000) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const bindingV1 = parseCandidateAd05ExecutionBindingV1(data.bindingV1);
  const referencesV1 = data.referencesV1.map(parseReference);
  const coverageV1 = data.coverageV1.map(parseCoverage);
  const candidateOutcomeV1 = enumValue(data.candidateOutcomeV1, [
    "syntheticInventoryVerified",
    "syntheticInventoryVerifiedWithUnresolvedDispatch",
    "positiveNotApplicableEvidenceVerified",
  ] as const);
  const candidate: CandidateAd05eEvidenceV1 = Object.freeze({
    schemaVersion: 1,
    adapterIdV1: "device_fcm_preferences",
    bindingV1,
    sourceDocumentPathHashV1:
      ad04HashV1(data.sourceDocumentPathHashV1),
    sourceSchemaIdV1:
      "account_deletion_ad05e_fcm_preferences_evidence_v1",
    sourceSchemaVersionV1: "schema_v1",
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    producerIdV1: "synthetic_notification_inventory_v1",
    producerVersionV1: 1,
    inventoryCompleteV1: true,
    referenceCoverageCompleteV1: true,
    highWaterMarkV1: ad04OpaqueIdV1(data.highWaterMarkV1),
    associationScopeHashV1: ad04HashV1(data.associationScopeHashV1),
    referencesV1: Object.freeze(referencesV1),
    coverageV1: Object.freeze(coverageV1),
    candidateOutcomeV1,
    observedAtSecV1: ad04CounterV1(data.observedAtSecV1),
    recordVersionV1: ad04OpaqueIdV1(data.recordVersionV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
  });
  assertEvidenceSemantics(candidate);
  const {evidenceFingerprintV1, ...core} = candidate;
  if (evidenceFingerprintV1 !== ad05eEvidenceFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

function assertEvidenceSemantics(value: CandidateAd05eEvidenceV1): void {
  const binding = value.bindingV1;
  if (binding.adapterIdV1 !== "device_fcm_preferences" ||
      binding.policyVersionV1 !== "synthetic_policy_v1" ||
      value.highWaterMarkV1 !== "registered-synthetic-high-water-v1") {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const ids = new Set(value.referencesV1.map((entry) => entry.referenceIdV1));
  const fingerprints = new Set(value.referencesV1.map((entry) =>
    entry.referenceFingerprintV1));
  if (ids.size !== value.referencesV1.length ||
      fingerprints.size !== value.referencesV1.length ||
      value.coverageV1.length !== ad05eReferenceClassesV1.length ||
      new Set(value.coverageV1.map((entry) => entry.referenceClassV1)).size !==
        ad05eReferenceClassesV1.length) {
    ad05FailV1("AD05_INCOMPLETE_INVENTORY");
  }
  for (const referenceClassV1 of ad05eReferenceClassesV1) {
    const coverage = value.coverageV1.find((entry) =>
      entry.referenceClassV1 === referenceClassV1);
    const count = value.referencesV1.filter((entry) =>
      entry.referenceClassV1 === referenceClassV1).length;
    if (coverage === undefined || coverage.enumeratedCountV1 !== count ||
        (count === 0) !==
          (coverage.coverageStateV1 === "positiveAbsenceVerified")) {
      ad05FailV1("AD05_INCOMPLETE_INVENTORY");
    }
  }
  for (const reference of value.referencesV1) {
    if (reference.associationScopeHashV1 !== value.associationScopeHashV1) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    if (reference.ownerRelationV1 === "deletingAccount") {
      if (reference.authProjectIdV2 !== binding.authProjectIdV2 ||
          reference.authTenantIdV2 !== binding.authTenantIdV2 ||
          reference.authUidUtf16LeBase64UrlV1 !==
            binding.authUidUtf16LeBase64UrlV1 ||
          reference.accountGenerationOwnerV1 !== binding.generationHash ||
          reference.sourceLifecycleEpochV2 >
            binding.acceptedLifecycleEpochV2) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
    }
    if (reference.ownerRelationV1 === "laterGeneration" &&
        (reference.authProjectIdV2 !== binding.authProjectIdV2 ||
         reference.authTenantIdV2 !== binding.authTenantIdV2 ||
         reference.authUidUtf16LeBase64UrlV1 !==
          binding.authUidUtf16LeBase64UrlV1 ||
         reference.accountGenerationOwnerV1 === binding.generationHash)) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    const expectedId = `reference_${canonicalSha256({
      referenceClassV1: reference.referenceClassV1,
      sourcePathHashV1: reference.sourcePathHashV1,
      sourceRecordVersionV1: reference.sourceRecordVersionV1,
      ownerRelationV1: reference.ownerRelationV1,
    })}`;
    if (reference.referenceIdV1 !== expectedId) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
  }
  const unresolved = value.referencesV1.some((entry) =>
    entry.dispositionV1 === "unresolvedExternalDependency");
  const notApplicable = value.referencesV1.length === 0;
  if ((notApplicable &&
       (binding.actionV1 !== "notApplicable" ||
        value.candidateOutcomeV1 !==
          "positiveNotApplicableEvidenceVerified")) ||
      (!notApplicable && binding.actionV1 !== "erase") ||
      (!notApplicable && unresolved && value.candidateOutcomeV1 !==
        "syntheticInventoryVerifiedWithUnresolvedDispatch") ||
      (!notApplicable && !unresolved && value.candidateOutcomeV1 !==
        "syntheticInventoryVerified")) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}

export function assertCandidateAd05eEvidenceBindingV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  evidenceV1: CandidateAd05eEvidenceV1;
}): void {
  const expected = parseCandidateAd05ExecutionBindingV1(input.bindingV1);
  const evidence = parseCandidateAd05eEvidenceV1(input.evidenceV1);
  if (canonicalSha256(expected) !== canonicalSha256(evidence.bindingV1)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}
