import {firebaseUidUtf16LeBase64Url} from
  "../domain/account_deletion_contract";
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
  sameAd04ScopeV1,
} from "./ad04_records";

export const ACCOUNT_DELETION_AD05D_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05D_PRODUCTION_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05D_PROVIDER_MUTATION_ALLOWED_V1 = false;

export const ad05dAdapterIdsV1 = [
  "personal_storage_media",
  "shared_association_media",
] as const;

export type Ad05dAdapterIdV1 = typeof ad05dAdapterIdsV1[number];
export type Ad05dClassificationV1 = "personalExclusive" | "associationShared";
export type Ad05dObjectStateV1 =
  "live" | "absent" | "softDeleted" | "retained" | "unknown";
export type Ad05dTokenStateV1 = "absent" | "present" | "unknown";
export type Ad05dCandidateOutcomeV1 =
  "personalVersionEraseVerified" | "sharedAccountReferenceDetachVerified" |
  "positiveNotApplicableEvidenceVerified";

export interface CandidateAd05dBucketBindingV1 {
  schemaVersion: 1;
  bucketRegistryVersionV1: "synthetic_bucket_registry_v1";
  bucketNameV1: "demo-hoopsconnect.appspot.com";
  providerProjectIdV1: "demo-hoopsconnect";
  authTenantIdV2: string | null;
  hierarchicalNamespaceV1: false;
  versioningStateV1: "enabled";
  softDeleteStateV1: "disabled";
  retentionStateV1: "none";
}

export interface CandidateAd05dObjectVersionV1 {
  schemaVersion: 1;
  objectIdV1: string;
  objectNameUtf8Base64UrlV1: string;
  objectNameHashV1: string;
  objectGenerationV1: string;
  objectMetagenerationV1: string;
  contentHashV1: string;
  metadataHashV1: string;
  derivativeOfObjectIdV1: string | null;
  transformIdV1: string | null;
  transformVersionV1: string | null;
  versionStateV1: Ad05dObjectStateV1;
  tokenStateV1: Ad05dTokenStateV1;
  tokenSetFingerprintV1: string | null;
  restoreTokenFingerprintV1: null;
  recordFingerprintV1: string;
}

export interface CandidateAd05dOwnershipV1 {
  schemaVersion: 1;
  classificationV1: Ad05dClassificationV1;
  associationScopeHashV1: string | null;
  ownershipSourcePathHashV1: string;
  ownershipSourceVersionV1: string;
  ownershipSourceHashV1: string;
  accountGenerationOwnerV1: string;
  accountReferencePresentV1: false;
  subjectSetHashV1: string;
  protectedFactsHashV1: string;
  unrelatedReferencesHashV1: string;
  rightsDecisionPathHashV1: string;
  rightsDecisionHashV1: string;
  ownershipFingerprintV1: string;
}

export interface CandidateAd05dObservationV1 {
  schemaVersion: 1;
  backendIdV1: "synthetic_storage_backend_v1";
  backendVersionV1: "1";
  attemptIdV1: string;
  observationSequenceV1: number;
  observedObjectFingerprintsV1: readonly string[];
  referenceClosureHashV1: string;
  preservedSetHashV1: string;
  candidateOutcomeV1: Ad05dCandidateOutcomeV1;
  observedAtSecV1: number;
  observationFingerprintV1: string;
}

export interface CandidateAd05dMediaEvidenceV1 {
  schemaVersion: 1;
  adapterIdV1: Ad05dAdapterIdV1;
  bindingV1: CandidateAd05ExecutionBindingV1;
  sourceDocumentPathHashV1: string;
  sourceSchemaIdV1: "account_deletion_ad05d_media_evidence_v1";
  sourceSchemaVersionV1: "schema_v1";
  provenanceIdV1: string;
  producerIdV1: "synthetic_storage_fixture_v1";
  producerVersionV1: 1;
  inventoryCompleteV1: true;
  referenceCoverageCompleteV1: true;
  highWaterMarkV1: string;
  bucketV1: CandidateAd05dBucketBindingV1;
  ownershipV1: CandidateAd05dOwnershipV1;
  objectsV1: readonly CandidateAd05dObjectVersionV1[];
  observationV1: CandidateAd05dObservationV1;
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

function adapterId(value: unknown): Ad05dAdapterIdV1 {
  const id = ad04OpaqueIdV1(value);
  if (!ad05dAdapterIdsV1.includes(id as Ad05dAdapterIdV1)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return id as Ad05dAdapterIdV1;
}

function canonicalDecimal(value: unknown): string {
  if (typeof value !== "string" || !/^[1-9][0-9]{0,30}$/.test(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const uint64Max = "18446744073709551615";
  if (value.length > uint64Max.length ||
      (value.length === uint64Max.length && value > uint64Max)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return value;
}

export function ad05dObjectNameUtf8Base64UrlV1(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

function canonicalObjectName(value: unknown): {encoded: string; decoded: string} {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,512}$/.test(value)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  let decoded: string;
  try {
    decoded = Buffer.from(value, "base64url").toString("utf8");
  } catch (_) {
    return ad05FailV1("AD05_INVALID_RECORD");
  }
  if (ad05dObjectNameUtf8Base64UrlV1(decoded) !== value ||
      !/^candidate-ad05d\/[A-Za-z0-9_-]{1,64}\/[A-Za-z0-9_-]{1,64}\/[A-Za-z0-9_.-]{1,64}$/.test(decoded) ||
      decoded.split("/").some((part) => part === "." || part === "..") ||
      /%2f|%5c|https?:/i.test(decoded)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return {encoded: value, decoded};
}

export function ad05dObjectFingerprintV1(value: Omit<
  CandidateAd05dObjectVersionV1, "recordFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-object-version-v1",
    ...value,
  });
}

export function ad05dOwnershipFingerprintV1(value: Omit<
  CandidateAd05dOwnershipV1, "ownershipFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-ownership-v1",
    ...value,
  });
}

export function ad05dObservationFingerprintV1(value: Omit<
  CandidateAd05dObservationV1, "observationFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-observation-v1",
    ...value,
  });
}

export function ad05dEvidenceFingerprintV1(value: Omit<
  CandidateAd05dMediaEvidenceV1, "evidenceFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05d-media-evidence-v1",
    ...value,
  });
}

function parseBucket(value: unknown): CandidateAd05dBucketBindingV1 {
  const data = exact(value, [
    "schemaVersion", "bucketRegistryVersionV1", "bucketNameV1",
    "providerProjectIdV1", "authTenantIdV2", "hierarchicalNamespaceV1",
    "versioningStateV1", "softDeleteStateV1", "retentionStateV1",
  ]);
  if (data.schemaVersion !== 1 ||
      data.bucketRegistryVersionV1 !== "synthetic_bucket_registry_v1" ||
      data.bucketNameV1 !== "demo-hoopsconnect.appspot.com" ||
      data.providerProjectIdV1 !== "demo-hoopsconnect" ||
      (data.authTenantIdV2 !== null && typeof data.authTenantIdV2 !== "string") ||
      data.hierarchicalNamespaceV1 !== false ||
      data.versioningStateV1 !== "enabled" ||
      data.softDeleteStateV1 !== "disabled" ||
      data.retentionStateV1 !== "none") ad05FailV1("AD05_BINDING_CONFLICT");
  return Object.freeze(data as unknown as CandidateAd05dBucketBindingV1);
}

function parseObject(value: unknown): CandidateAd05dObjectVersionV1 {
  const data = exact(value, [
    "schemaVersion", "objectIdV1", "objectNameUtf8Base64UrlV1",
    "objectNameHashV1", "objectGenerationV1", "objectMetagenerationV1",
    "contentHashV1", "metadataHashV1", "derivativeOfObjectIdV1",
    "transformIdV1", "transformVersionV1", "versionStateV1",
    "tokenStateV1", "tokenSetFingerprintV1", "restoreTokenFingerprintV1",
    "recordFingerprintV1",
  ]);
  if (data.schemaVersion !== 1) ad05FailV1("AD05_INVALID_RECORD");
  const name = canonicalObjectName(data.objectNameUtf8Base64UrlV1);
  const versionState = data.versionStateV1;
  const tokenState = data.tokenStateV1;
  if (!["live", "absent", "softDeleted", "retained", "unknown"].includes(
    versionState as string,
  ) || !["absent", "present", "unknown"].includes(tokenState as string)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const derivative = data.derivativeOfObjectIdV1 === null ? null :
    ad04OpaqueIdV1(data.derivativeOfObjectIdV1);
  const transform = data.transformIdV1 === null ? null :
    ad04OpaqueIdV1(data.transformIdV1);
  const transformVersion = data.transformVersionV1 === null ? null :
    ad04OpaqueIdV1(data.transformVersionV1);
  if ((derivative === null) !== (transform === null) ||
      (derivative === null) !== (transformVersion === null) ||
      (transform !== null && (transform !== "thumbnail" ||
       transformVersion !== "v1"))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const tokenFingerprint = data.tokenSetFingerprintV1 === null ? null :
    ad04HashV1(data.tokenSetFingerprintV1);
  if ((tokenState === "absent") !== (tokenFingerprint === null) ||
      data.restoreTokenFingerprintV1 !== null) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const candidate: CandidateAd05dObjectVersionV1 = Object.freeze({
    schemaVersion: 1,
    objectIdV1: ad04OpaqueIdV1(data.objectIdV1),
    objectNameUtf8Base64UrlV1: name.encoded,
    objectNameHashV1: ad04HashV1(data.objectNameHashV1),
    objectGenerationV1: canonicalDecimal(data.objectGenerationV1),
    objectMetagenerationV1: canonicalDecimal(data.objectMetagenerationV1),
    contentHashV1: ad04HashV1(data.contentHashV1),
    metadataHashV1: ad04HashV1(data.metadataHashV1),
    derivativeOfObjectIdV1: derivative,
    transformIdV1: transform,
    transformVersionV1: transformVersion,
    versionStateV1: versionState as Ad05dObjectStateV1,
    tokenStateV1: tokenState as Ad05dTokenStateV1,
    tokenSetFingerprintV1: tokenFingerprint,
    restoreTokenFingerprintV1: null,
    recordFingerprintV1: ad04HashV1(data.recordFingerprintV1),
  });
  const {recordFingerprintV1, ...core} = candidate;
  if (candidate.objectNameHashV1 !== canonicalSha256(name.decoded) ||
      recordFingerprintV1 !== ad05dObjectFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

function parseOwnership(value: unknown): CandidateAd05dOwnershipV1 {
  const data = exact(value, [
    "schemaVersion", "classificationV1", "associationScopeHashV1",
    "ownershipSourcePathHashV1", "ownershipSourceVersionV1",
    "ownershipSourceHashV1", "accountGenerationOwnerV1",
    "accountReferencePresentV1", "subjectSetHashV1", "protectedFactsHashV1",
    "unrelatedReferencesHashV1", "rightsDecisionPathHashV1",
    "rightsDecisionHashV1", "ownershipFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      !["personalExclusive", "associationShared"].includes(
        data.classificationV1 as string,
      ) || data.accountReferencePresentV1 !== false) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const candidate: CandidateAd05dOwnershipV1 = Object.freeze({
    schemaVersion: 1,
    classificationV1: data.classificationV1 as Ad05dClassificationV1,
    associationScopeHashV1: data.associationScopeHashV1 === null ? null :
      ad04HashV1(data.associationScopeHashV1),
    ownershipSourcePathHashV1: ad04HashV1(data.ownershipSourcePathHashV1),
    ownershipSourceVersionV1: ad04OpaqueIdV1(data.ownershipSourceVersionV1),
    ownershipSourceHashV1: ad04HashV1(data.ownershipSourceHashV1),
    accountGenerationOwnerV1: ad04HashV1(data.accountGenerationOwnerV1),
    accountReferencePresentV1: false,
    subjectSetHashV1: ad04HashV1(data.subjectSetHashV1),
    protectedFactsHashV1: ad04HashV1(data.protectedFactsHashV1),
    unrelatedReferencesHashV1: ad04HashV1(data.unrelatedReferencesHashV1),
    rightsDecisionPathHashV1: ad04HashV1(data.rightsDecisionPathHashV1),
    rightsDecisionHashV1: ad04HashV1(data.rightsDecisionHashV1),
    ownershipFingerprintV1: ad04HashV1(data.ownershipFingerprintV1),
  });
  const {ownershipFingerprintV1, ...core} = candidate;
  if (ownershipFingerprintV1 !== ad05dOwnershipFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

function parseObservation(value: unknown): CandidateAd05dObservationV1 {
  const data = exact(value, [
    "schemaVersion", "backendIdV1", "backendVersionV1", "attemptIdV1",
    "observationSequenceV1", "observedObjectFingerprintsV1",
    "referenceClosureHashV1", "preservedSetHashV1", "candidateOutcomeV1",
    "observedAtSecV1", "observationFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      data.backendIdV1 !== "synthetic_storage_backend_v1" ||
      data.backendVersionV1 !== "1" ||
      !Array.isArray(data.observedObjectFingerprintsV1) ||
      !["personalVersionEraseVerified",
        "sharedAccountReferenceDetachVerified",
        "positiveNotApplicableEvidenceVerified"].includes(
        data.candidateOutcomeV1 as string,
      )) ad05FailV1("AD05_INVALID_RECORD");
  const observed = data.observedObjectFingerprintsV1.map(ad04HashV1);
  if (new Set(observed).size !== observed.length ||
      [...observed].sort().some((entry, index) => entry !== observed[index])) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const candidate: CandidateAd05dObservationV1 = Object.freeze({
    schemaVersion: 1,
    backendIdV1: "synthetic_storage_backend_v1",
    backendVersionV1: "1",
    attemptIdV1: ad04OpaqueIdV1(data.attemptIdV1),
    observationSequenceV1: ad04CounterV1(data.observationSequenceV1),
    observedObjectFingerprintsV1: Object.freeze(observed),
    referenceClosureHashV1: ad04HashV1(data.referenceClosureHashV1),
    preservedSetHashV1: ad04HashV1(data.preservedSetHashV1),
    candidateOutcomeV1: data.candidateOutcomeV1 as Ad05dCandidateOutcomeV1,
    observedAtSecV1: ad04CounterV1(data.observedAtSecV1),
    observationFingerprintV1: ad04HashV1(data.observationFingerprintV1),
  });
  const {observationFingerprintV1, ...core} = candidate;
  if (observationFingerprintV1 !== ad05dObservationFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function parseCandidateAd05dMediaEvidenceV1(
  value: unknown,
): CandidateAd05dMediaEvidenceV1 {
  const data = exact(value, [
    "schemaVersion", "adapterIdV1", "bindingV1",
    "sourceDocumentPathHashV1", "sourceSchemaIdV1",
    "sourceSchemaVersionV1", "provenanceIdV1", "producerIdV1",
    "producerVersionV1", "inventoryCompleteV1",
    "referenceCoverageCompleteV1", "highWaterMarkV1", "bucketV1",
    "ownershipV1", "objectsV1", "observationV1", "recordVersionV1",
    "evidenceFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      data.sourceSchemaIdV1 !== "account_deletion_ad05d_media_evidence_v1" ||
      data.sourceSchemaVersionV1 !== "schema_v1" ||
      data.producerIdV1 !== "synthetic_storage_fixture_v1" ||
      data.producerVersionV1 !== 1 || data.inventoryCompleteV1 !== true ||
      data.referenceCoverageCompleteV1 !== true || !Array.isArray(data.objectsV1) ||
      data.objectsV1.length > 100 || JSON.stringify(data).length > 250000) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const binding = parseCandidateAd05ExecutionBindingV1(data.bindingV1);
  const id = adapterId(data.adapterIdV1);
  const bucket = parseBucket(data.bucketV1);
  const ownership = parseOwnership(data.ownershipV1);
  const objects = data.objectsV1.map(parseObject);
  const observation = parseObservation(data.observationV1);
  if (id !== binding.adapterIdV1 ||
      binding.policyVersionV1 !== "synthetic_policy_v1" ||
      bucket.providerProjectIdV1 !== binding.authProjectIdV2 ||
      bucket.authTenantIdV2 !== binding.authTenantIdV2 ||
      ownership.accountGenerationOwnerV1 !== binding.generationHash ||
      (id === "personal_storage_media") !==
        (ownership.classificationV1 === "personalExclusive") ||
      (id === "shared_association_media") !==
        (ownership.classificationV1 === "associationShared")) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const objectIds = new Set(objects.map((entry) => entry.objectIdV1));
  const objectVersions = new Set(objects.map((entry) =>
    `${entry.objectNameUtf8Base64UrlV1}:${entry.objectGenerationV1}`));
  if (objectIds.size !== objects.length || objectVersions.size !== objects.length ||
      objects.some((entry) =>
        entry.objectIdV1 !== `object_${canonicalSha256({
          bucketNameV1: bucket.bucketNameV1,
          objectNameUtf8Base64UrlV1: entry.objectNameUtf8Base64UrlV1,
          objectGenerationV1: entry.objectGenerationV1,
        })}` ||
    entry.derivativeOfObjectIdV1 !== null &&
      (!objectIds.has(entry.derivativeOfObjectIdV1) ||
       entry.derivativeOfObjectIdV1 === entry.objectIdV1))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  for (const entry of objects) {
    const seen = new Set<string>([entry.objectIdV1]);
    let parent = entry.derivativeOfObjectIdV1;
    while (parent !== null) {
      if (seen.has(parent)) ad05FailV1("AD05_BINDING_CONFLICT");
      seen.add(parent);
      parent = objects.find((candidate) => candidate.objectIdV1 === parent)
        ?.derivativeOfObjectIdV1 ?? null;
    }
  }
  const observed = [...objects.map((entry) => entry.recordFingerprintV1)].sort();
  if (observed.some((entry, index) =>
    entry !== observation.observedObjectFingerprintsV1[index]) ||
      observed.length !== observation.observedObjectFingerprintsV1.length) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const personal = id === "personal_storage_media";
  const registeredOwnershipPath = `registered-synthetic/${id}/ownership`;
  const registeredRightsPath = `registered-synthetic/${id}/rights`;
  const expectedReferenceClosureHashV1 = canonicalSha256({
    contract: "account-deletion-ad05d-reference-closure-v1",
    objectVersionsV1: objects.map((entry) => ({
      objectIdV1: entry.objectIdV1,
      recordFingerprintV1: entry.recordFingerprintV1,
      derivativeOfObjectIdV1: entry.derivativeOfObjectIdV1,
      transformIdV1: entry.transformIdV1,
      transformVersionV1: entry.transformVersionV1,
    })),
  });
  const expectedPreservedSetHashV1 = canonicalSha256({
    contract: "account-deletion-ad05d-preserved-set-v1",
    preservedObjectFingerprintsV1: objects.filter((entry) =>
      entry.versionStateV1 === "live" || entry.versionStateV1 === "retained")
      .map((entry) => entry.recordFingerprintV1).sort(),
    protectedFactsHashV1: ownership.protectedFactsHashV1,
    unrelatedReferencesHashV1: ownership.unrelatedReferencesHashV1,
  });
  if (ownership.ownershipSourcePathHashV1 !==
        canonicalSha256(registeredOwnershipPath) ||
      ownership.rightsDecisionPathHashV1 !==
        canonicalSha256(registeredRightsPath) ||
      ownership.rightsDecisionHashV1 !== canonicalSha256({
        registeredRightsPath,
        classificationV1: ownership.classificationV1,
        associationScopeHashV1: ownership.associationScopeHashV1,
      }) ||
      observation.referenceClosureHashV1 !== expectedReferenceClosureHashV1 ||
      observation.preservedSetHashV1 !== expectedPreservedSetHashV1 ||
      data.highWaterMarkV1 !== "registered-synthetic-high-water-v1") {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const expectedTenant = binding.authTenantIdV2 ?? "root";
  const expectedAccount = binding.authUidUtf16LeBase64UrlV1;
  for (const entry of objects) {
    const decoded = Buffer.from(
      entry.objectNameUtf8Base64UrlV1, "base64url",
    ).toString("utf8");
    const segments = decoded.split("/");
    if (segments[1] !== expectedTenant || segments[2] !== expectedAccount) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
  }
  const notApplicable = objects.length === 0;
  if ((notApplicable && (binding.actionV1 !== "notApplicable" ||
       observation.candidateOutcomeV1 !==
        "positiveNotApplicableEvidenceVerified")) ||
      (!notApplicable && binding.actionV1 !== (personal ? "erase" : "detach")) ||
      (!notApplicable && personal &&
       (objects.some((entry) => entry.versionStateV1 !== "absent" ||
        entry.tokenStateV1 !== "absent") ||
      observation.candidateOutcomeV1 !== "personalVersionEraseVerified")) ||
      (!notApplicable && !personal && (objects.some((entry) =>
        entry.versionStateV1 !== "live" && entry.versionStateV1 !== "retained") ||
      observation.candidateOutcomeV1 !==
        "sharedAccountReferenceDetachVerified"))) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const candidate: CandidateAd05dMediaEvidenceV1 = Object.freeze({
    schemaVersion: 1,
    adapterIdV1: id,
    bindingV1: binding,
    sourceDocumentPathHashV1: ad04HashV1(data.sourceDocumentPathHashV1),
    sourceSchemaIdV1: "account_deletion_ad05d_media_evidence_v1",
    sourceSchemaVersionV1: "schema_v1",
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    producerIdV1: "synthetic_storage_fixture_v1",
    producerVersionV1: 1,
    inventoryCompleteV1: true,
    referenceCoverageCompleteV1: true,
    highWaterMarkV1: ad04OpaqueIdV1(data.highWaterMarkV1),
    bucketV1: bucket,
    ownershipV1: ownership,
    objectsV1: Object.freeze(objects),
    observationV1: observation,
    recordVersionV1: ad04OpaqueIdV1(data.recordVersionV1),
    evidenceFingerprintV1: ad04HashV1(data.evidenceFingerprintV1),
  });
  if (candidate.bindingV1.authUidUtf16LeBase64UrlV1 !==
      firebaseUidUtf16LeBase64Url(candidate.bindingV1.authUidV2)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  const {evidenceFingerprintV1, ...core} = candidate;
  if (evidenceFingerprintV1 !== ad05dEvidenceFingerprintV1(core)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
  return candidate;
}

export function assertCandidateAd05dEvidenceBindingV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  evidenceV1: CandidateAd05dMediaEvidenceV1;
}): void {
  const binding = parseCandidateAd05ExecutionBindingV1(input.bindingV1);
  const evidence = parseCandidateAd05dMediaEvidenceV1(input.evidenceV1);
  if (!sameAd04ScopeV1(binding, evidence.bindingV1) ||
      canonicalSha256(binding) !== canonicalSha256(evidence.bindingV1)) {
    ad05FailV1("AD05_BINDING_CONFLICT");
  }
}
