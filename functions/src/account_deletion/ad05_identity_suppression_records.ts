import {firebaseUidUtf16LeBase64Url} from "../domain/account_deletion_contract";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  AccountDeletionAdapterId,
  CandidateAd05ExecutionBindingV1,
  CandidateAd05SealedManifestV1,
  ad05FailV1,
  parseCandidateAd05ExecutionBindingV1,
  parseCandidateAd05SealedManifestV1,
  assertCandidateAd05ManifestBindingV1,
} from "./ad05_records";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04HashV1,
  ad04NamespaceV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export const ACCOUNT_DELETION_AD05B_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05B_PRODUCTION_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD05B_SCHEMA_VERSION_V1 = 1;
export const ACCOUNT_DELETION_AD05B_MAX_REFERENCE_ITEMS_V1 = 32;

export const ad05bIdentityAdapterIdsV1 = [
  "account_person_claims",
  "person_identity_evidence",
  "public_projections_exports",
] as const satisfies readonly AccountDeletionAdapterId[];
export type Ad05bIdentityAdapterIdV1 = typeof ad05bIdentityAdapterIdsV1[number];

export const ad05bIdentityReferenceClassesV1 = [
  "accountPersonClaim",
  "personIdentityEvidenceCapsule",
  "personIdentityEvidenceMaterial",
  "publicProfile",
  "publicProjection",
  "leaderboard",
  "ranking",
  "pressView",
  "rawCompatibilityPath",
  "exportArtifact",
  "downloadableFile",
  "searchIndex",
  "shareAsset",
  "cacheDerivative",
  "restoreReplayInput",
  "rebuildInput",
] as const;
export type Ad05bIdentityReferenceClassV1 =
  typeof ad05bIdentityReferenceClassesV1[number];

export type Ad05bReferenceGuaranteeV1 =
  "transactionalRecordVersion" |
  "versionOrProviderGuaranteeUnavailable";

export type Ad05bMinorStatusV1 = "verifiedAdult" | "verifiedMinor" | "unknown";

export class AccountDeletionAd05bErrorV1 extends Error {
  readonly codeV1: "AD05B_INVALID_RECORD" | "AD05B_BINDING_CONFLICT" |
    "AD05B_BLOCKED" | "AD05B_UNSUPPORTED";

  constructor(codeV1: AccountDeletionAd05bErrorV1["codeV1"]) {
    super(codeV1);
    this.name = "AccountDeletionAd05bErrorV1";
    this.codeV1 = codeV1;
  }
}

export function ad05bFailV1(
  codeV1: AccountDeletionAd05bErrorV1["codeV1"],
): never {
  throw new AccountDeletionAd05bErrorV1(codeV1);
}

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  return record;
}

function identityAdapterId(value: unknown): Ad05bIdentityAdapterIdV1 {
  const id = ad04OpaqueIdV1(value);
  if (!ad05bIdentityAdapterIdsV1.includes(id as Ad05bIdentityAdapterIdV1)) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  return id as Ad05bIdentityAdapterIdV1;
}

function referenceClass(value: unknown): Ad05bIdentityReferenceClassV1 {
  if (typeof value !== "string" ||
      !ad05bIdentityReferenceClassesV1.includes(
        value as Ad05bIdentityReferenceClassV1,
      )) ad05bFailV1("AD05B_INVALID_RECORD");
  return value as Ad05bIdentityReferenceClassV1;
}

function guarantee(value: unknown): Ad05bReferenceGuaranteeV1 {
  if (value !== "transactionalRecordVersion" &&
      value !== "versionOrProviderGuaranteeUnavailable") {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  return value;
}

function minorStatus(value: unknown): Ad05bMinorStatusV1 {
  if (value !== "verifiedAdult" && value !== "verifiedMinor" &&
      value !== "unknown") ad05bFailV1("AD05B_INVALID_RECORD");
  return value;
}

function adapterForReferenceClassV1(
  value: Ad05bIdentityReferenceClassV1,
): Ad05bIdentityAdapterIdV1 {
  if (value === "accountPersonClaim") return "account_person_claims";
  if (value === "personIdentityEvidenceCapsule" ||
      value === "personIdentityEvidenceMaterial") {
    return "person_identity_evidence";
  }
  return "public_projections_exports";
}

export type CandidateAd05bIdentityEffectBindingV1 =
  CandidateAd05ExecutionBindingV1;

export interface CandidateAd05bIdentityReferenceV1 {
  schemaVersion: 1;
  referenceIdV1: string;
  ordinalV1: number;
  adapterIdV1: Ad05bIdentityAdapterIdV1;
  referenceClassV1: Ad05bIdentityReferenceClassV1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  sourceSystemIdV1: string;
  sourceSchemaIdV1: string;
  sourceSchemaVersionV1: string;
  referenceVersionV1: string;
  referencePathHashV1: string;
  provenanceIdV1: string;
  classificationV1: "applicable" | "notApplicable";
  identityBearingV1: true;
  guaranteeV1: Ad05bReferenceGuaranteeV1;
  referenceFingerprintV1: string;
}

export type Ad05bReferenceCoverageStateV1 =
  "referencesEnumerated" | "verifiedAbsent";

export interface CandidateAd05bIdentityReferenceCoverageV1 {
  schemaVersion: 1;
  ordinalV1: number;
  adapterIdV1: Ad05bIdentityAdapterIdV1;
  referenceClassV1: Ad05bIdentityReferenceClassV1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  coverageStateV1: Ad05bReferenceCoverageStateV1;
  scannedSourceIdV1: string;
  scannedSourceVersionV1: string;
  provenanceIdV1: string;
  evidenceIdV1: string;
  completeV1: true;
  coverageFingerprintV1: string;
}

export function ad05bIdentityReferenceCoverageFingerprintV1(
  value: Omit<CandidateAd05bIdentityReferenceCoverageV1,
    "coverageFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-reference-coverage-v1",
    ...value,
  });
}

export function parseCandidateAd05bIdentityReferenceCoverageV1(
  value: unknown,
): CandidateAd05bIdentityReferenceCoverageV1 {
  const data = exact(value, [
    "schemaVersion", "ordinalV1", "adapterIdV1", "referenceClassV1",
    "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authUidUtf16LeBase64UrlV1", "generationHash",
    "acceptedLifecycleEpochV2", "associationIdV1", "subjectIdV1", "claimIdV1",
    "coverageStateV1", "scannedSourceIdV1", "scannedSourceVersionV1",
    "provenanceIdV1", "evidenceIdV1", "completeV1",
    "coverageFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.completeV1 !== true ||
      (data.coverageStateV1 !== "referencesEnumerated" &&
       data.coverageStateV1 !== "verifiedAbsent")) {
    ad05bFailV1("AD05B_BLOCKED");
  }
  const referenceClassV1 = referenceClass(data.referenceClassV1);
  const scope = ad04ScopeV1(data);
  const candidate: CandidateAd05bIdentityReferenceCoverageV1 = Object.freeze({
    schemaVersion: 1,
    ...scope,
    ordinalV1: ad04CounterV1(data.ordinalV1),
    adapterIdV1: identityAdapterId(data.adapterIdV1),
    referenceClassV1,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
    coverageStateV1: data.coverageStateV1,
    scannedSourceIdV1: ad04OpaqueIdV1(data.scannedSourceIdV1),
    scannedSourceVersionV1: ad04OpaqueIdV1(data.scannedSourceVersionV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    evidenceIdV1: ad04OpaqueIdV1(data.evidenceIdV1),
    completeV1: true,
    coverageFingerprintV1: ad04HashV1(data.coverageFingerprintV1),
  });
  if (candidate.adapterIdV1 !== adapterForReferenceClassV1(referenceClassV1) ||
      candidate.authUidUtf16LeBase64UrlV1 !==
        firebaseUidUtf16LeBase64Url(candidate.authUidV2)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const {coverageFingerprintV1, ...fingerprintInput} = candidate;
  if (coverageFingerprintV1 !==
      ad05bIdentityReferenceCoverageFingerprintV1(fingerprintInput)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return candidate;
}

export function ad05bIdentityReferenceFingerprintV1(
  value: Omit<CandidateAd05bIdentityReferenceV1, "referenceFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-identity-reference-v1",
    ...value,
  });
}

export function parseCandidateAd05bIdentityReferenceV1(
  value: unknown,
): CandidateAd05bIdentityReferenceV1 {
  const data = exact(value, [
    "schemaVersion", "referenceIdV1", "ordinalV1", "adapterIdV1",
    "referenceClassV1", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authUidUtf16LeBase64UrlV1", "generationHash",
    "acceptedLifecycleEpochV2", "associationIdV1", "subjectIdV1", "claimIdV1",
    "sourceSystemIdV1", "sourceSchemaIdV1", "sourceSchemaVersionV1",
    "referenceVersionV1", "referencePathHashV1", "provenanceIdV1",
    "classificationV1", "identityBearingV1", "guaranteeV1",
    "referenceFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.identityBearingV1 !== true ||
      (data.classificationV1 !== "applicable" &&
       data.classificationV1 !== "notApplicable")) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  const referenceClassV1 = referenceClass(data.referenceClassV1);
  const scope = ad04ScopeV1(data);
  const candidate: CandidateAd05bIdentityReferenceV1 = Object.freeze({
    schemaVersion: 1,
    ...scope,
    referenceIdV1: ad04OpaqueIdV1(data.referenceIdV1),
    ordinalV1: ad04CounterV1(data.ordinalV1),
    adapterIdV1: identityAdapterId(data.adapterIdV1),
    referenceClassV1,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
    sourceSystemIdV1: ad04OpaqueIdV1(data.sourceSystemIdV1),
    sourceSchemaIdV1: ad04OpaqueIdV1(data.sourceSchemaIdV1),
    sourceSchemaVersionV1: ad04OpaqueIdV1(data.sourceSchemaVersionV1),
    referenceVersionV1: ad04OpaqueIdV1(data.referenceVersionV1),
    referencePathHashV1: ad04HashV1(data.referencePathHashV1),
    provenanceIdV1: ad04OpaqueIdV1(data.provenanceIdV1),
    classificationV1: data.classificationV1,
    identityBearingV1: true,
    guaranteeV1: guarantee(data.guaranteeV1),
    referenceFingerprintV1: ad04HashV1(data.referenceFingerprintV1),
  });
  if (candidate.adapterIdV1 !== adapterForReferenceClassV1(referenceClassV1) ||
      candidate.authUidUtf16LeBase64UrlV1 !==
        firebaseUidUtf16LeBase64Url(candidate.authUidV2) ||
      (referenceClassV1 === "accountPersonClaim") !==
        (candidate.guaranteeV1 === "transactionalRecordVersion")) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const {referenceFingerprintV1, ...fingerprintInput} = candidate;
  if (referenceFingerprintV1 !==
      ad05bIdentityReferenceFingerprintV1(fingerprintInput)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05bIdentityReferenceManifestV1 {
  schemaVersion: 1;
  manifestIdV1: string;
  manifestVersionV1: string;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  lifecycleStateV1: "deleting";
  internalJobId: string;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  claimProvenanceIdV1: string;
  identityEvidenceIdV1: string;
  identityEvidenceProvenanceIdV1: string;
  publicationPolicyDecisionIdV1: string;
  publicationPolicyVersionV1: string;
  fieldLevelPublicationPolicyIdV1: string;
  fieldLevelPublicationPolicyVersionV1: string;
  fieldLevelPublicationPolicyProvenanceIdV1: string;
  fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic";
  minorStatusV1: Ad05bMinorStatusV1;
  identityPublicationAllowedV1: false;
  scopeAuthorityV1: "verifiedAccountAssociationOnly";
  personErasureAuthorityV1: false;
  effectBindingsV1: readonly CandidateAd05ExecutionBindingV1[];
  referenceCoverageV1:
    readonly CandidateAd05bIdentityReferenceCoverageV1[];
  referenceCoverageSetFingerprintV1: string;
  referenceCountV1: number;
  referencesV1: readonly CandidateAd05bIdentityReferenceV1[];
  referenceSetFingerprintV1: string;
  rawPathCoverageVerifiedV1: true;
  restoreSuppressionCoverageVerifiedV1: true;
  verifierIdV1: string;
  verificationEvidenceIdV1: string;
  verifiedAtSecV1: number;
  completeV1: true;
  sealedV1: true;
  allVersionOrProviderGuaranteesVerifiedV1: false;
  manifestFingerprintV1: string;
}

export function ad05bIdentityReferenceSetFingerprintV1(
  referencesV1: readonly CandidateAd05bIdentityReferenceV1[],
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-identity-reference-set-v1",
    referenceFingerprintsV1: referencesV1.map((reference) =>
      reference.referenceFingerprintV1),
  });
}

export function ad05bIdentityReferenceCoverageSetFingerprintV1(
  coverageV1: readonly CandidateAd05bIdentityReferenceCoverageV1[],
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-reference-coverage-set-v1",
    coverageFingerprintsV1: coverageV1.map((entry) =>
      entry.coverageFingerprintV1),
  });
}

export function ad05bIdentityReferenceManifestFingerprintV1(
  value: Omit<CandidateAd05bIdentityReferenceManifestV1, "manifestFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-identity-reference-manifest-v1",
    ...value,
  });
}

export function parseCandidateAd05bIdentityReferenceManifestV1(
  value: unknown,
): CandidateAd05bIdentityReferenceManifestV1 {
  const data = exact(value, [
    "schemaVersion", "manifestIdV1", "manifestVersionV1", "authProjectIdV2",
    "authTenantIdV2", "authUidV2", "authUidUtf16LeBase64UrlV1",
    "generationHash", "acceptedLifecycleEpochV2", "lifecycleStateV1",
    "internalJobId", "associationIdV1", "subjectIdV1", "claimIdV1",
    "claimProvenanceIdV1", "identityEvidenceIdV1",
    "identityEvidenceProvenanceIdV1", "publicationPolicyDecisionIdV1",
    "publicationPolicyVersionV1", "fieldLevelPublicationPolicyIdV1",
    "fieldLevelPublicationPolicyVersionV1",
    "fieldLevelPublicationPolicyProvenanceIdV1",
    "fieldLevelPublicationPolicyApprovalV1", "minorStatusV1",
    "identityPublicationAllowedV1", "scopeAuthorityV1",
    "personErasureAuthorityV1", "effectBindingsV1", "referenceCoverageV1",
    "referenceCoverageSetFingerprintV1", "referenceCountV1", "referencesV1",
    "referenceSetFingerprintV1",
    "rawPathCoverageVerifiedV1", "restoreSuppressionCoverageVerifiedV1",
    "verifierIdV1", "verificationEvidenceIdV1", "verifiedAtSecV1",
    "completeV1", "sealedV1", "allVersionOrProviderGuaranteesVerifiedV1",
    "manifestFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.lifecycleStateV1 !== "deleting" ||
      data.identityPublicationAllowedV1 !== false ||
      data.scopeAuthorityV1 !== "verifiedAccountAssociationOnly" ||
      data.fieldLevelPublicationPolicyApprovalV1 !==
        "explicitTestOnlySynthetic" ||
      data.personErasureAuthorityV1 !== false ||
      data.rawPathCoverageVerifiedV1 !== true ||
      data.restoreSuppressionCoverageVerifiedV1 !== true ||
      data.completeV1 !== true || data.sealedV1 !== true ||
      data.allVersionOrProviderGuaranteesVerifiedV1 !== false ||
      !Array.isArray(data.effectBindingsV1) ||
      !Array.isArray(data.referenceCoverageV1) ||
      !Array.isArray(data.referencesV1) ||
      data.referencesV1.length > ACCOUNT_DELETION_AD05B_MAX_REFERENCE_ITEMS_V1) {
    ad05bFailV1("AD05B_BLOCKED");
  }
  const scope = ad04ScopeV1(data);
  const effects = data.effectBindingsV1.map(parseCandidateAd05ExecutionBindingV1);
  const referenceCoverage = data.referenceCoverageV1.map(
    parseCandidateAd05bIdentityReferenceCoverageV1,
  );
  const references = data.referencesV1.map(parseCandidateAd05bIdentityReferenceV1);
  const candidate: CandidateAd05bIdentityReferenceManifestV1 = Object.freeze({
    schemaVersion: 1,
    ...scope,
    manifestIdV1: ad04OpaqueIdV1(data.manifestIdV1),
    manifestVersionV1: ad04OpaqueIdV1(data.manifestVersionV1),
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    lifecycleStateV1: "deleting",
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
    claimProvenanceIdV1: ad04OpaqueIdV1(data.claimProvenanceIdV1),
    identityEvidenceIdV1: ad04OpaqueIdV1(data.identityEvidenceIdV1),
    identityEvidenceProvenanceIdV1: ad04OpaqueIdV1(
      data.identityEvidenceProvenanceIdV1,
    ),
    publicationPolicyDecisionIdV1: ad04NamespaceV1(
      data.publicationPolicyDecisionIdV1,
    ),
    publicationPolicyVersionV1: ad04OpaqueIdV1(
      data.publicationPolicyVersionV1,
    ),
    fieldLevelPublicationPolicyIdV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyIdV1,
    ),
    fieldLevelPublicationPolicyVersionV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyVersionV1,
    ),
    fieldLevelPublicationPolicyProvenanceIdV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyProvenanceIdV1,
    ),
    fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic",
    minorStatusV1: minorStatus(data.minorStatusV1),
    identityPublicationAllowedV1: false,
    scopeAuthorityV1: "verifiedAccountAssociationOnly",
    personErasureAuthorityV1: false,
    effectBindingsV1: Object.freeze(effects),
    referenceCoverageV1: Object.freeze(referenceCoverage),
    referenceCoverageSetFingerprintV1: ad04HashV1(
      data.referenceCoverageSetFingerprintV1,
    ),
    referenceCountV1: ad04CounterV1(data.referenceCountV1),
    referencesV1: Object.freeze(references),
    referenceSetFingerprintV1: ad04HashV1(data.referenceSetFingerprintV1),
    rawPathCoverageVerifiedV1: true,
    restoreSuppressionCoverageVerifiedV1: true,
    verifierIdV1: ad04OpaqueIdV1(data.verifierIdV1),
    verificationEvidenceIdV1: ad04OpaqueIdV1(data.verificationEvidenceIdV1),
    verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
    completeV1: true,
    sealedV1: true,
    allVersionOrProviderGuaranteesVerifiedV1: false,
    manifestFingerprintV1: ad04HashV1(data.manifestFingerprintV1),
  });
  const exactEffectIds = effects.map((effect) => effect.adapterIdV1);
  const exactCoverageClasses = referenceCoverage.map((entry) =>
    entry.referenceClassV1);
  if (candidate.authUidUtf16LeBase64UrlV1 !==
        firebaseUidUtf16LeBase64Url(candidate.authUidV2) ||
      candidate.publicationPolicyDecisionIdV1 !==
        "retention.public_projections_exports" ||
      effects.length !== ad05bIdentityAdapterIdsV1.length ||
      !ad05bIdentityAdapterIdsV1.every((id, index) => exactEffectIds[index] === id) ||
      effects.some((effect) => !sameAd04ScopeV1(effect, candidate) ||
        effect.authUidUtf16LeBase64UrlV1 !==
          candidate.authUidUtf16LeBase64UrlV1 ||
        effect.generationHash !== candidate.generationHash ||
        effect.acceptedLifecycleEpochV2 !==
          candidate.acceptedLifecycleEpochV2 ||
        effect.internalJobId !== candidate.internalJobId ||
        effect.policyVersionV1 !== candidate.publicationPolicyVersionV1) ||
      referenceCoverage.length !== ad05bIdentityReferenceClassesV1.length ||
      !ad05bIdentityReferenceClassesV1.every((entry, index) =>
        exactCoverageClasses[index] === entry) ||
      referenceCoverage.some((coverage, index) =>
        coverage.ordinalV1 !== index ||
        !sameAd04ScopeV1(coverage, candidate) ||
        coverage.authUidUtf16LeBase64UrlV1 !==
          candidate.authUidUtf16LeBase64UrlV1 ||
        coverage.generationHash !== candidate.generationHash ||
        coverage.acceptedLifecycleEpochV2 !==
          candidate.acceptedLifecycleEpochV2 ||
        coverage.associationIdV1 !== candidate.associationIdV1 ||
        coverage.subjectIdV1 !== candidate.subjectIdV1 ||
        coverage.claimIdV1 !== candidate.claimIdV1 ||
        (coverage.coverageStateV1 === "verifiedAbsent" && references.some(
          (reference) => reference.referenceClassV1 ===
            coverage.referenceClassV1)) ||
        (coverage.coverageStateV1 === "referencesEnumerated" && !references.some(
          (reference) => reference.referenceClassV1 ===
            coverage.referenceClassV1))) ||
      candidate.referenceCoverageSetFingerprintV1 !==
        ad05bIdentityReferenceCoverageSetFingerprintV1(referenceCoverage) ||
      new Set(references.map((reference) => reference.referenceIdV1)).size !==
        references.length ||
      references.some((reference, index) =>
        reference.ordinalV1 !== index ||
        !sameAd04ScopeV1(reference, candidate) ||
        reference.authUidUtf16LeBase64UrlV1 !==
          candidate.authUidUtf16LeBase64UrlV1 ||
        reference.generationHash !== candidate.generationHash ||
        reference.acceptedLifecycleEpochV2 !==
          candidate.acceptedLifecycleEpochV2 ||
        reference.associationIdV1 !== candidate.associationIdV1 ||
        reference.subjectIdV1 !== candidate.subjectIdV1 ||
        reference.claimIdV1 !== candidate.claimIdV1) ||
      references.filter((reference) =>
        reference.referenceClassV1 === "personIdentityEvidenceCapsule" &&
        reference.referenceIdV1 === candidate.identityEvidenceIdV1 &&
        reference.provenanceIdV1 ===
          candidate.identityEvidenceProvenanceIdV1 &&
        reference.classificationV1 === "applicable").length !== 1 ||
      candidate.referenceCountV1 !== references.length ||
      candidate.referenceSetFingerprintV1 !==
        ad05bIdentityReferenceSetFingerprintV1(references)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const {manifestFingerprintV1, ...fingerprintInput} = candidate;
  if (manifestFingerprintV1 !==
      ad05bIdentityReferenceManifestFingerprintV1(fingerprintInput)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return candidate;
}

export interface CandidateAd05bIdentitySuppressionV1 {
  schemaVersion: 1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authUidUtf16LeBase64UrlV1: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  lifecycleStateV1: "deleting";
  internalJobId: string;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  claimProvenanceIdV1: string;
  identityEvidenceIdV1: string;
  identityEvidenceProvenanceIdV1: string;
  policyVersionV1: string;
  fieldLevelPublicationPolicyIdV1: string;
  fieldLevelPublicationPolicyVersionV1: string;
  fieldLevelPublicationPolicyProvenanceIdV1: string;
  fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic";
  scopeAuthorityV1: "verifiedAccountAssociationOnly";
  personErasureAuthorityV1: false;
  identityPublicationAllowedV1: false;
  minorStatusV1: Ad05bMinorStatusV1;
  referenceManifestIdV1: string;
  referenceManifestFingerprintV1: string;
  claimSourceManifestFingerprintV1: string;
  restoreSuppressionReferenceIdV1: string;
  durableV1: true;
  blocksPublicationV1: true;
  blocksRebuildV1: true;
  blocksRestoreReplayV1: true;
  officialStatGlobalIdentityMutationAllowedV1: false;
  snapshotEpochMutationAllowedV1: false;
  releaseHeadMutationAllowedV1: false;
  publicEpochMutationAllowedV1: false;
  canonicalBytesMutationAllowedV1: false;
  certifiedHashMutationAllowedV1: false;
  actorProvenanceMutationAllowedV1: false;
  correctionLineageMutationAllowedV1: false;
  createdAtSecV1: number;
  suppressionFingerprintV1: string;
}

export function ad05bIdentitySuppressionFingerprintV1(
  value: Omit<CandidateAd05bIdentitySuppressionV1, "suppressionFingerprintV1">,
): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-identity-suppression-v1",
    ...value,
  });
}

export function parseCandidateAd05bIdentitySuppressionV1(
  value: unknown,
): CandidateAd05bIdentitySuppressionV1 {
  const data = exact(value, [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authUidUtf16LeBase64UrlV1", "generationHash",
    "acceptedLifecycleEpochV2", "lifecycleStateV1", "internalJobId",
    "associationIdV1", "subjectIdV1", "claimIdV1", "claimProvenanceIdV1",
    "identityEvidenceIdV1", "identityEvidenceProvenanceIdV1",
    "policyVersionV1", "fieldLevelPublicationPolicyIdV1",
    "fieldLevelPublicationPolicyVersionV1",
    "fieldLevelPublicationPolicyProvenanceIdV1",
    "fieldLevelPublicationPolicyApprovalV1", "scopeAuthorityV1",
    "personErasureAuthorityV1",
    "identityPublicationAllowedV1", "minorStatusV1", "referenceManifestIdV1",
    "referenceManifestFingerprintV1", "claimSourceManifestFingerprintV1",
    "restoreSuppressionReferenceIdV1", "durableV1", "blocksPublicationV1",
    "blocksRebuildV1", "blocksRestoreReplayV1",
    "officialStatGlobalIdentityMutationAllowedV1", "snapshotEpochMutationAllowedV1",
    "releaseHeadMutationAllowedV1", "publicEpochMutationAllowedV1",
    "canonicalBytesMutationAllowedV1", "certifiedHashMutationAllowedV1",
    "actorProvenanceMutationAllowedV1", "correctionLineageMutationAllowedV1",
    "createdAtSecV1", "suppressionFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 || data.lifecycleStateV1 !== "deleting" ||
      data.scopeAuthorityV1 !== "verifiedAccountAssociationOnly" ||
      data.fieldLevelPublicationPolicyApprovalV1 !==
        "explicitTestOnlySynthetic" ||
      data.personErasureAuthorityV1 !== false ||
      data.identityPublicationAllowedV1 !== false || data.durableV1 !== true ||
      data.blocksPublicationV1 !== true || data.blocksRebuildV1 !== true ||
      data.blocksRestoreReplayV1 !== true ||
      data.officialStatGlobalIdentityMutationAllowedV1 !== false ||
      data.snapshotEpochMutationAllowedV1 !== false ||
      data.releaseHeadMutationAllowedV1 !== false ||
      data.publicEpochMutationAllowedV1 !== false ||
      data.canonicalBytesMutationAllowedV1 !== false ||
      data.certifiedHashMutationAllowedV1 !== false ||
      data.actorProvenanceMutationAllowedV1 !== false ||
      data.correctionLineageMutationAllowedV1 !== false) {
    ad05bFailV1("AD05B_BLOCKED");
  }
  const scope = ad04ScopeV1(data);
  const candidate: CandidateAd05bIdentitySuppressionV1 = Object.freeze({
    schemaVersion: 1,
    ...scope,
    authUidUtf16LeBase64UrlV1: ad04OpaqueIdV1(
      data.authUidUtf16LeBase64UrlV1,
    ),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    lifecycleStateV1: "deleting",
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
    claimProvenanceIdV1: ad04OpaqueIdV1(data.claimProvenanceIdV1),
    identityEvidenceIdV1: ad04OpaqueIdV1(data.identityEvidenceIdV1),
    identityEvidenceProvenanceIdV1: ad04OpaqueIdV1(
      data.identityEvidenceProvenanceIdV1,
    ),
    policyVersionV1: ad04OpaqueIdV1(data.policyVersionV1),
    fieldLevelPublicationPolicyIdV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyIdV1,
    ),
    fieldLevelPublicationPolicyVersionV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyVersionV1,
    ),
    fieldLevelPublicationPolicyProvenanceIdV1: ad04OpaqueIdV1(
      data.fieldLevelPublicationPolicyProvenanceIdV1,
    ),
    fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic",
    scopeAuthorityV1: "verifiedAccountAssociationOnly",
    personErasureAuthorityV1: false,
    identityPublicationAllowedV1: false,
    minorStatusV1: minorStatus(data.minorStatusV1),
    referenceManifestIdV1: ad04OpaqueIdV1(data.referenceManifestIdV1),
    referenceManifestFingerprintV1: ad04HashV1(
      data.referenceManifestFingerprintV1,
    ),
    claimSourceManifestFingerprintV1: ad04HashV1(
      data.claimSourceManifestFingerprintV1,
    ),
    restoreSuppressionReferenceIdV1: ad04OpaqueIdV1(
      data.restoreSuppressionReferenceIdV1,
    ),
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
    createdAtSecV1: ad04CounterV1(data.createdAtSecV1),
    suppressionFingerprintV1: ad04HashV1(data.suppressionFingerprintV1),
  });
  if (candidate.authUidUtf16LeBase64UrlV1 !==
      firebaseUidUtf16LeBase64Url(candidate.authUidV2)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const {suppressionFingerprintV1, ...fingerprintInput} = candidate;
  if (suppressionFingerprintV1 !==
      ad05bIdentitySuppressionFingerprintV1(fingerprintInput)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return candidate;
}

export function assertCandidateAd05bManifestSuppressionBindingV1(input: {
  manifest: CandidateAd05bIdentityReferenceManifestV1;
  suppression: CandidateAd05bIdentitySuppressionV1;
  claimSourceManifest: CandidateAd05SealedManifestV1;
}): void {
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1(input.manifest);
  const suppression = parseCandidateAd05bIdentitySuppressionV1(input.suppression);
  const claimBinding = manifest.effectBindingsV1[0];
  const claimSourceManifest = parseCandidateAd05SealedManifestV1(
    input.claimSourceManifest,
  );
  assertCandidateAd05ManifestBindingV1({
    binding: claimBinding,
    manifest: claimSourceManifest,
  });
  assertCandidateAd05bClaimSourceReferenceClosureV1({
    manifest,
    claimSourceManifest,
  });
  if (!sameAd04ScopeV1(manifest, suppression) ||
      manifest.authUidUtf16LeBase64UrlV1 !==
        suppression.authUidUtf16LeBase64UrlV1 ||
      manifest.generationHash !== suppression.generationHash ||
      manifest.acceptedLifecycleEpochV2 !==
        suppression.acceptedLifecycleEpochV2 ||
      manifest.internalJobId !== suppression.internalJobId ||
      manifest.associationIdV1 !== suppression.associationIdV1 ||
      manifest.subjectIdV1 !== suppression.subjectIdV1 ||
      manifest.claimIdV1 !== suppression.claimIdV1 ||
      manifest.claimProvenanceIdV1 !== suppression.claimProvenanceIdV1 ||
      manifest.identityEvidenceIdV1 !== suppression.identityEvidenceIdV1 ||
      manifest.identityEvidenceProvenanceIdV1 !==
        suppression.identityEvidenceProvenanceIdV1 ||
      manifest.publicationPolicyVersionV1 !== suppression.policyVersionV1 ||
      manifest.fieldLevelPublicationPolicyIdV1 !==
        suppression.fieldLevelPublicationPolicyIdV1 ||
      manifest.fieldLevelPublicationPolicyVersionV1 !==
        suppression.fieldLevelPublicationPolicyVersionV1 ||
      manifest.fieldLevelPublicationPolicyProvenanceIdV1 !==
        suppression.fieldLevelPublicationPolicyProvenanceIdV1 ||
      manifest.minorStatusV1 !== suppression.minorStatusV1 ||
      manifest.manifestIdV1 !== suppression.referenceManifestIdV1 ||
      manifest.manifestFingerprintV1 !==
        suppression.referenceManifestFingerprintV1 ||
      claimSourceManifest.manifestFingerprintV1 !==
        suppression.claimSourceManifestFingerprintV1 ||
      claimSourceManifest.manifestIdV1 !== claimBinding.sourceManifestIdV1 ||
      claimSourceManifest.manifestVersionV1 !==
        claimBinding.sourceManifestVersionV1 ||
      suppression.createdAtSecV1 < manifest.verifiedAtSecV1) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
}

export function assertCandidateAd05bClaimSourceReferenceClosureV1(input: {
  manifest: CandidateAd05bIdentityReferenceManifestV1;
  claimSourceManifest: CandidateAd05SealedManifestV1;
}): void {
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1(input.manifest);
  const claimSourceManifest = parseCandidateAd05SealedManifestV1(
    input.claimSourceManifest,
  );
  const claimReferences = manifest.referencesV1.filter((reference) =>
    reference.referenceClassV1 === "accountPersonClaim" &&
    reference.classificationV1 === "applicable");
  const applicableItems = claimSourceManifest.itemsV1.filter((item) =>
    item.classificationV1 === "applicable");
  const associationScopeHashV1 = canonicalSha256(manifest.associationIdV1);
  const matchingReferencesFor = (item: typeof applicableItems[number]) =>
    claimReferences.filter((reference) =>
      reference.referencePathHashV1 === item.sourceDocumentPathHashV1 &&
      reference.sourceSchemaIdV1 === item.sourceSchemaIdV1 &&
      reference.sourceSchemaVersionV1 === item.sourceSchemaVersionV1 &&
      reference.referenceVersionV1 === item.sourceRecordVersionV1 &&
      reference.provenanceIdV1 === item.provenanceIdV1 &&
      item.associationScopeHashV1 === associationScopeHashV1 &&
      reference.associationIdV1 === manifest.associationIdV1 &&
      reference.subjectIdV1 === manifest.subjectIdV1 &&
      reference.claimIdV1 === manifest.claimIdV1);
  if (applicableItems.some((item) => matchingReferencesFor(item).length !== 1) ||
      claimReferences.some((reference) => applicableItems.filter((item) =>
        matchingReferencesFor(item).includes(reference)).length !== 1)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
}

function hashedPathId(prefix: string, value: unknown): string {
  return `${prefix}_${canonicalSha256(value)}`;
}

export function ad05bIdentityReferenceManifestPathV1(input: {
  internalJobId: string;
  manifestIdV1: string;
}): string {
  const job = ad04OpaqueIdV1(input.internalJobId);
  const manifest = ad04OpaqueIdV1(input.manifestIdV1);
  return `accountDeletionJobsV1/${job}/ad05IdentityReferenceManifestsV1/${
    hashedPathId("identity_manifest", manifest)}`;
}

export function ad05bIdentitySuppressionPathV1(input: {
  internalJobId: string;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
}): string {
  const job = ad04OpaqueIdV1(input.internalJobId);
  return `accountDeletionJobsV1/${job}/ad05IdentitySuppressionsV1/${
    hashedPathId("identity_suppression", {
      associationIdV1: ad04OpaqueIdV1(input.associationIdV1),
      subjectIdV1: ad04OpaqueIdV1(input.subjectIdV1),
      claimIdV1: ad04OpaqueIdV1(input.claimIdV1),
    })}`;
}

export function assertCandidateAd05bBindingsShareScopeV1(
  bindings: readonly CandidateAd05ExecutionBindingV1[],
): readonly CandidateAd05ExecutionBindingV1[] {
  if (bindings.length !== ad05bIdentityAdapterIdsV1.length) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const parsed = bindings.map(parseCandidateAd05ExecutionBindingV1);
  const first = parsed[0];
  if (!ad05bIdentityAdapterIdsV1.every((id, index) =>
    parsed[index].adapterIdV1 === id) || parsed.some((binding) =>
    !sameAd04ScopeV1(binding, first) ||
    binding.authUidUtf16LeBase64UrlV1 !== first.authUidUtf16LeBase64UrlV1 ||
    binding.generationHash !== first.generationHash ||
    binding.acceptedLifecycleEpochV2 !== first.acceptedLifecycleEpochV2 ||
    binding.lifecycleStateV1 !== "deleting" ||
    binding.internalJobId !== first.internalJobId ||
    binding.policyVersionV1 !== first.policyVersionV1)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return Object.freeze(parsed);
}

// Re-export only the AD05-A failure helper for callers that bridge to the
// frozen manifest/effect kernel. AD05-B never changes its semantics.
export const ad05bFrozenKernelFailureV1 = ad05FailV1;
