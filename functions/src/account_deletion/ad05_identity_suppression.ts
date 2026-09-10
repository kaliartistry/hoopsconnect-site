import {firebaseUidUtf16LeBase64Url} from "../domain/account_deletion_contract";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  CandidateAd05SyntheticPolicyRegistryV1,
  parseCandidateAd05SyntheticPolicyRegistryV1,
} from "./ad05_adapters";
import {
  CandidateAd05ItemEffectResultV1,
  CandidateAd05TransactionRepositoryV1,
  CandidateAd05TransactionalDocumentEffectV1,
  applyCandidateAd05TransactionalDocumentItemV1,
} from "./ad05_effects";
import {
  CandidateAd05ManifestReaderV1,
  requireCandidateAd05CanonicalManifestV1,
} from "./ad05_inventory";
import {
  CandidateAd05ExecutionBindingV1,
  CandidateAd05ManifestItemV1,
  CandidateAd05SealedManifestV1,
  ad05ManifestPathV1,
  assertCandidateAd05ManifestBindingV1,
  parseCandidateAd05ExecutionBindingV1,
  parseCandidateAd05SealedManifestV1,
} from "./ad05_records";
import {
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04FirebaseUidV1,
  ad04HashV1,
  ad04NamespaceV1,
  ad04NullableCounterV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  sameAd04ScopeV1,
} from "./ad04_records";
import {
  ACCOUNT_DELETION_AD05B_MAX_REFERENCE_ITEMS_V1,
  Ad05bIdentityAdapterIdV1,
  Ad05bMinorStatusV1,
  CandidateAd05bIdentityReferenceCoverageV1,
  CandidateAd05bIdentityReferenceManifestV1,
  CandidateAd05bIdentityReferenceV1,
  CandidateAd05bIdentitySuppressionV1,
  ad05bFailV1,
  ad05bIdentityAdapterIdsV1,
  ad05bIdentityReferenceCoverageSetFingerprintV1,
  ad05bIdentityReferenceManifestFingerprintV1,
  ad05bIdentityReferenceManifestPathV1,
  ad05bIdentityReferenceSetFingerprintV1,
  ad05bIdentitySuppressionFingerprintV1,
  ad05bIdentitySuppressionPathV1,
  assertCandidateAd05bBindingsShareScopeV1,
  assertCandidateAd05bClaimSourceReferenceClosureV1,
  assertCandidateAd05bManifestSuppressionBindingV1,
  parseCandidateAd05bIdentityReferenceCoverageV1,
  parseCandidateAd05bIdentityReferenceManifestV1,
  parseCandidateAd05bIdentityReferenceV1,
  parseCandidateAd05bIdentitySuppressionV1,
} from "./ad05_identity_suppression_records";

export interface CandidateAd05bIdentityReferenceSourceV1 {
  enumerateIdentityReferencesV1(input: {
    bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
    associationIdV1: string;
    subjectIdV1: string;
    claimIdV1: string;
    limitV1: number;
  }): Promise<unknown>;
}

interface CandidateAd05bIdentityReferencePageV1 {
  schemaVersion: 1;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
  completeV1: true;
  continuationTokenV1: null;
  referenceCoverageV1: readonly CandidateAd05bIdentityReferenceCoverageV1[];
  referencesV1: readonly CandidateAd05bIdentityReferenceV1[];
}

export interface CandidateAd05bIdentityReferenceVerificationV1 {
  schemaVersion: 1;
  referenceSetFingerprintV1: string;
  referenceCoverageSetFingerprintV1: string;
  claimSourceManifestFingerprintV1: string;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  claimReferenceClosureVerifiedV1: true;
  rawPathCoverageVerifiedV1: true;
  restoreSuppressionCoverageVerifiedV1: true;
  completeV1: true;
  verifierIdV1: string;
  verificationEvidenceIdV1: string;
  verifiedAtSecV1: number;
  verificationFingerprintV1: string;
}

export interface CandidateAd05bIdentityReferenceVerifierV1 {
  verifyIdentityReferencesV1(input: {
    bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
    claimSourceManifestV1: CandidateAd05SealedManifestV1;
    associationIdV1: string;
    subjectIdV1: string;
    claimIdV1: string;
    referenceCoverageV1: readonly CandidateAd05bIdentityReferenceCoverageV1[];
    referencesV1: readonly CandidateAd05bIdentityReferenceV1[];
    referenceCoverageSetFingerprintV1: string;
    referenceSetFingerprintV1: string;
  }): Promise<unknown>;
}

export interface CandidateAd05bIdentitySuppressionSealResultV1 {
  stateV1: "sealed" | "replayed";
  manifestV1: CandidateAd05bIdentityReferenceManifestV1;
  suppressionV1: CandidateAd05bIdentitySuppressionV1;
}

export interface CandidateAd05bDormantPlanV1 {
  stateV1: "blocked";
  evidenceCodeV1: "authoritative_policy_not_approved";
  writesAllowedV1: false;
}

export function createDormantCandidateAd05bIdentitySuppressionPlanV1():
CandidateAd05bDormantPlanV1 {
  return Object.freeze({
    stateV1: "blocked",
    evidenceCodeV1: "authoritative_policy_not_approved",
    writesAllowedV1: false,
  });
}

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  return record;
}

function pageV1(value: unknown): CandidateAd05bIdentityReferencePageV1 {
  const data = exact(value, [
    "schemaVersion", "inventorySourceIdV1", "inventorySourceVersionV1",
    "completeV1", "continuationTokenV1", "referenceCoverageV1",
    "referencesV1",
  ]);
  if (data.schemaVersion !== 1 || data.completeV1 !== true ||
      data.continuationTokenV1 !== null ||
      !Array.isArray(data.referenceCoverageV1) ||
      !Array.isArray(data.referencesV1) ||
      data.referencesV1.length > ACCOUNT_DELETION_AD05B_MAX_REFERENCE_ITEMS_V1) {
    ad05bFailV1("AD05B_BLOCKED");
  }
  return Object.freeze({
    schemaVersion: 1,
    inventorySourceIdV1: ad04OpaqueIdV1(data.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(data.inventorySourceVersionV1),
    completeV1: true,
    continuationTokenV1: null,
    referenceCoverageV1: Object.freeze(data.referenceCoverageV1.map(
      parseCandidateAd05bIdentityReferenceCoverageV1,
    )),
    referencesV1: Object.freeze(data.referencesV1.map(
      parseCandidateAd05bIdentityReferenceV1,
    )),
  });
}

export function ad05bIdentityReferenceVerificationFingerprintV1(input: Omit<
  CandidateAd05bIdentityReferenceVerificationV1, "verificationFingerprintV1"
>): string {
  return canonicalSha256({
    contract: "account-deletion-ad05b-reference-verification-v1",
    ...input,
  });
}

function verificationV1(value: unknown):
CandidateAd05bIdentityReferenceVerificationV1 {
  const data = exact(value, [
    "schemaVersion", "referenceSetFingerprintV1",
    "referenceCoverageSetFingerprintV1", "claimSourceManifestFingerprintV1",
    "associationIdV1", "subjectIdV1", "claimIdV1",
    "claimReferenceClosureVerifiedV1", "rawPathCoverageVerifiedV1",
    "restoreSuppressionCoverageVerifiedV1", "completeV1", "verifierIdV1",
    "verificationEvidenceIdV1", "verifiedAtSecV1",
    "verificationFingerprintV1",
  ]);
  if (data.schemaVersion !== 1 ||
      data.claimReferenceClosureVerifiedV1 !== true ||
      data.rawPathCoverageVerifiedV1 !== true ||
      data.restoreSuppressionCoverageVerifiedV1 !== true ||
      data.completeV1 !== true) ad05bFailV1("AD05B_BLOCKED");
  const candidate: CandidateAd05bIdentityReferenceVerificationV1 =
    Object.freeze({
      schemaVersion: 1,
      referenceSetFingerprintV1: ad04HashV1(data.referenceSetFingerprintV1),
      referenceCoverageSetFingerprintV1: ad04HashV1(
        data.referenceCoverageSetFingerprintV1,
      ),
      claimSourceManifestFingerprintV1: ad04HashV1(
        data.claimSourceManifestFingerprintV1,
      ),
      associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
      subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
      claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
      claimReferenceClosureVerifiedV1: true,
      rawPathCoverageVerifiedV1: true,
      restoreSuppressionCoverageVerifiedV1: true,
      completeV1: true,
      verifierIdV1: ad04OpaqueIdV1(data.verifierIdV1),
      verificationEvidenceIdV1: ad04OpaqueIdV1(data.verificationEvidenceIdV1),
      verifiedAtSecV1: ad04CounterV1(data.verifiedAtSecV1),
      verificationFingerprintV1: ad04HashV1(data.verificationFingerprintV1),
    });
  const {verificationFingerprintV1: fingerprint, ...fingerprintInput} = candidate;
  if (fingerprint !==
      ad05bIdentityReferenceVerificationFingerprintV1(fingerprintInput)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return candidate;
}

function requireSyntheticDecisionsV1(input: {
  syntheticPolicyV1: unknown;
  bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
}): CandidateAd05SyntheticPolicyRegistryV1 {
  const policy = parseCandidateAd05SyntheticPolicyRegistryV1(
    input.syntheticPolicyV1,
  );
  for (const binding of input.bindingsV1) {
    const decision = policy.decisionsV1.find((entry) =>
      entry.adapterIdV1 === binding.adapterIdV1);
    if (decision?.approvedV1 !== true ||
        decision.policyVersionV1 !== binding.policyVersionV1 ||
        decision.policyDecisionIdV1 !== binding.policyDecisionIdV1 ||
        decision.actionV1 !== binding.actionV1) {
      ad05bFailV1("AD05B_BLOCKED");
    }
  }
  return policy;
}

export function deterministicAd05bIdentityReferenceManifestIdV1(input: {
  bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  inventorySourceIdV1: string;
  inventorySourceVersionV1: string;
}): string {
  const effects = assertCandidateAd05bBindingsShareScopeV1(input.bindingsV1);
  return `identity_manifest_${canonicalSha256({
    contract: "account-deletion-ad05b-identity-manifest-identity-v1",
    executionBindingFingerprintsV1: effects.map((effect) =>
      effect.bindingFingerprintV1),
    associationIdV1: ad04OpaqueIdV1(input.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(input.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(input.claimIdV1),
    inventorySourceIdV1: ad04OpaqueIdV1(input.inventorySourceIdV1),
    inventorySourceVersionV1: ad04OpaqueIdV1(input.inventorySourceVersionV1),
  })}`;
}

export async function buildTestOnlySyntheticCandidateAd05bIdentityManifestV1(
  input: {
    syntheticPolicyV1: unknown;
    bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
    claimSourceManifestV1: CandidateAd05SealedManifestV1;
    associationIdV1: string;
    subjectIdV1: string;
    claimIdV1: string;
    claimProvenanceIdV1: string;
    identityEvidenceIdV1: string;
    identityEvidenceProvenanceIdV1: string;
    fieldLevelPublicationPolicyIdV1: string;
    fieldLevelPublicationPolicyVersionV1: string;
    fieldLevelPublicationPolicyProvenanceIdV1: string;
    minorStatusV1: Ad05bMinorStatusV1;
    sourceV1: CandidateAd05bIdentityReferenceSourceV1;
    verifierV1: CandidateAd05bIdentityReferenceVerifierV1;
  },
): Promise<CandidateAd05bIdentityReferenceManifestV1> {
  const bindings = assertCandidateAd05bBindingsShareScopeV1(input.bindingsV1);
  requireSyntheticDecisionsV1({
    syntheticPolicyV1: input.syntheticPolicyV1,
    bindingsV1: bindings,
  });
  const claimSourceManifest = parseCandidateAd05SealedManifestV1(
    input.claimSourceManifestV1,
  );
  assertCandidateAd05ManifestBindingV1({
    binding: bindings[0],
    manifest: claimSourceManifest,
  });
  const associationIdV1 = ad04OpaqueIdV1(input.associationIdV1);
  const subjectIdV1 = ad04OpaqueIdV1(input.subjectIdV1);
  const claimIdV1 = ad04OpaqueIdV1(input.claimIdV1);
  const page = pageV1(await input.sourceV1.enumerateIdentityReferencesV1({
    bindingsV1: bindings,
    associationIdV1,
    subjectIdV1,
    claimIdV1,
    limitV1: ACCOUNT_DELETION_AD05B_MAX_REFERENCE_ITEMS_V1,
  }));
  const referenceCoverageSetFingerprintV1 =
    ad05bIdentityReferenceCoverageSetFingerprintV1(page.referenceCoverageV1);
  const referenceSetFingerprintV1 =
    ad05bIdentityReferenceSetFingerprintV1(page.referencesV1);
  const manifestIdV1 = deterministicAd05bIdentityReferenceManifestIdV1({
    bindingsV1: bindings,
    associationIdV1,
    subjectIdV1,
    claimIdV1,
    inventorySourceIdV1: page.inventorySourceIdV1,
    inventorySourceVersionV1: page.inventorySourceVersionV1,
  });
  const verification = verificationV1(
    await input.verifierV1.verifyIdentityReferencesV1({
      bindingsV1: bindings,
      claimSourceManifestV1: claimSourceManifest,
      associationIdV1,
      subjectIdV1,
      claimIdV1,
      referenceCoverageV1: page.referenceCoverageV1,
      referencesV1: page.referencesV1,
      referenceCoverageSetFingerprintV1,
      referenceSetFingerprintV1,
    }),
  );
  if (verification.referenceSetFingerprintV1 !== referenceSetFingerprintV1 ||
      verification.referenceCoverageSetFingerprintV1 !==
        referenceCoverageSetFingerprintV1 ||
      verification.claimSourceManifestFingerprintV1 !==
        claimSourceManifest.manifestFingerprintV1 ||
      verification.associationIdV1 !== associationIdV1 ||
      verification.subjectIdV1 !== subjectIdV1 ||
      verification.claimIdV1 !== claimIdV1) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const first = bindings[0];
  const withoutFingerprint: Omit<CandidateAd05bIdentityReferenceManifestV1,
    "manifestFingerprintV1"> = {
    schemaVersion: 1,
    manifestIdV1,
    manifestVersionV1: page.inventorySourceVersionV1,
    authProjectIdV2: first.authProjectIdV2,
    authTenantIdV2: first.authTenantIdV2,
    authUidV2: first.authUidV2,
    authUidUtf16LeBase64UrlV1: first.authUidUtf16LeBase64UrlV1,
    generationHash: first.generationHash,
    acceptedLifecycleEpochV2: first.acceptedLifecycleEpochV2,
    lifecycleStateV1: "deleting",
    internalJobId: first.internalJobId,
    associationIdV1,
    subjectIdV1,
    claimIdV1,
    claimProvenanceIdV1: ad04OpaqueIdV1(input.claimProvenanceIdV1),
    identityEvidenceIdV1: ad04OpaqueIdV1(input.identityEvidenceIdV1),
    identityEvidenceProvenanceIdV1: ad04OpaqueIdV1(
      input.identityEvidenceProvenanceIdV1,
    ),
    publicationPolicyDecisionIdV1: "retention.public_projections_exports",
    publicationPolicyVersionV1: first.policyVersionV1,
    fieldLevelPublicationPolicyIdV1: ad04OpaqueIdV1(
      input.fieldLevelPublicationPolicyIdV1,
    ),
    fieldLevelPublicationPolicyVersionV1: ad04OpaqueIdV1(
      input.fieldLevelPublicationPolicyVersionV1,
    ),
    fieldLevelPublicationPolicyProvenanceIdV1: ad04OpaqueIdV1(
      input.fieldLevelPublicationPolicyProvenanceIdV1,
    ),
    fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic",
    minorStatusV1: input.minorStatusV1,
    identityPublicationAllowedV1: false,
    scopeAuthorityV1: "verifiedAccountAssociationOnly",
    personErasureAuthorityV1: false,
    effectBindingsV1: bindings,
    referenceCoverageV1: page.referenceCoverageV1,
    referenceCoverageSetFingerprintV1,
    referenceCountV1: page.referencesV1.length,
    referencesV1: page.referencesV1,
    referenceSetFingerprintV1,
    rawPathCoverageVerifiedV1: true,
    restoreSuppressionCoverageVerifiedV1: true,
    verifierIdV1: verification.verifierIdV1,
    verificationEvidenceIdV1: verification.verificationEvidenceIdV1,
    verifiedAtSecV1: verification.verifiedAtSecV1,
    completeV1: true,
    sealedV1: true,
    // AD05-B deliberately does not upgrade the V/E families.
    allVersionOrProviderGuaranteesVerifiedV1: false,
  };
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1({
    ...withoutFingerprint,
    manifestFingerprintV1:
      ad05bIdentityReferenceManifestFingerprintV1(withoutFingerprint),
  });
  assertCandidateAd05bClaimSourceReferenceClosureV1({
    manifest,
    claimSourceManifest,
  });
  return manifest;
}

function writeRecord(value: object): Readonly<Record<string, unknown>> {
  return value as unknown as Readonly<Record<string, unknown>>;
}

export async function sealTestOnlySyntheticCandidateAd05bIdentitySuppressionV1(
  input: {
    repository: CandidateAd05TransactionRepositoryV1;
    syntheticPolicyV1: unknown;
    bindingsV1: readonly CandidateAd05ExecutionBindingV1[];
    claimSourceManifestV1: CandidateAd05SealedManifestV1;
    associationIdV1: string;
    subjectIdV1: string;
    claimIdV1: string;
    claimProvenanceIdV1: string;
    identityEvidenceIdV1: string;
    identityEvidenceProvenanceIdV1: string;
    fieldLevelPublicationPolicyIdV1: string;
    fieldLevelPublicationPolicyVersionV1: string;
    fieldLevelPublicationPolicyProvenanceIdV1: string;
    minorStatusV1: Ad05bMinorStatusV1;
    restoreSuppressionReferenceIdV1: string;
    createdAtSecV1: number;
    sourceV1: CandidateAd05bIdentityReferenceSourceV1;
    verifierV1: CandidateAd05bIdentityReferenceVerifierV1;
  },
): Promise<CandidateAd05bIdentitySuppressionSealResultV1> {
  const bindings = assertCandidateAd05bBindingsShareScopeV1(input.bindingsV1);
  const claimSourceManifest = await requireCandidateAd05CanonicalManifestV1({
    repository: input.repository,
    binding: bindings[0],
    manifest: input.claimSourceManifestV1,
  });
  const manifest = await buildTestOnlySyntheticCandidateAd05bIdentityManifestV1({
    ...input,
    bindingsV1: bindings,
    claimSourceManifestV1: claimSourceManifest,
  });
  const createdAtSecV1 = ad04CounterV1(input.createdAtSecV1);
  if (createdAtSecV1 < manifest.verifiedAtSecV1) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const first = bindings[0];
  const suppressionWithoutFingerprint: Omit<CandidateAd05bIdentitySuppressionV1,
    "suppressionFingerprintV1"> = {
    schemaVersion: 1,
    authProjectIdV2: first.authProjectIdV2,
    authTenantIdV2: first.authTenantIdV2,
    authUidV2: first.authUidV2,
    authUidUtf16LeBase64UrlV1: first.authUidUtf16LeBase64UrlV1,
    generationHash: first.generationHash,
    acceptedLifecycleEpochV2: first.acceptedLifecycleEpochV2,
    lifecycleStateV1: "deleting",
    internalJobId: first.internalJobId,
    associationIdV1: manifest.associationIdV1,
    subjectIdV1: manifest.subjectIdV1,
    claimIdV1: manifest.claimIdV1,
    claimProvenanceIdV1: manifest.claimProvenanceIdV1,
    identityEvidenceIdV1: manifest.identityEvidenceIdV1,
    identityEvidenceProvenanceIdV1: manifest.identityEvidenceProvenanceIdV1,
    policyVersionV1: manifest.publicationPolicyVersionV1,
    fieldLevelPublicationPolicyIdV1:
      manifest.fieldLevelPublicationPolicyIdV1,
    fieldLevelPublicationPolicyVersionV1:
      manifest.fieldLevelPublicationPolicyVersionV1,
    fieldLevelPublicationPolicyProvenanceIdV1:
      manifest.fieldLevelPublicationPolicyProvenanceIdV1,
    fieldLevelPublicationPolicyApprovalV1: "explicitTestOnlySynthetic",
    scopeAuthorityV1: "verifiedAccountAssociationOnly",
    personErasureAuthorityV1: false,
    identityPublicationAllowedV1: false,
    minorStatusV1: manifest.minorStatusV1,
    referenceManifestIdV1: manifest.manifestIdV1,
    referenceManifestFingerprintV1: manifest.manifestFingerprintV1,
    claimSourceManifestFingerprintV1: claimSourceManifest.manifestFingerprintV1,
    restoreSuppressionReferenceIdV1: ad04OpaqueIdV1(
      input.restoreSuppressionReferenceIdV1,
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
    createdAtSecV1,
  };
  const suppression = parseCandidateAd05bIdentitySuppressionV1({
    ...suppressionWithoutFingerprint,
    suppressionFingerprintV1:
      ad05bIdentitySuppressionFingerprintV1(suppressionWithoutFingerprint),
  });
  assertCandidateAd05bManifestSuppressionBindingV1({
    manifest,
    suppression,
    claimSourceManifest,
  });
  const manifestPath = ad05bIdentityReferenceManifestPathV1({
    internalJobId: first.internalJobId,
    manifestIdV1: manifest.manifestIdV1,
  });
  const suppressionPath = ad05bIdentitySuppressionPathV1(suppression);
  return input.repository.runTransaction(async (transaction) => {
    const [existingManifestRaw, existingSuppressionRaw,
      persistedClaimManifestRaw] = await Promise.all([
      transaction.read(manifestPath),
      transaction.read(suppressionPath),
      transaction.read(ad05ManifestPathV1(first)),
    ]);
    if (persistedClaimManifestRaw === null) ad05bFailV1("AD05B_BLOCKED");
    const persistedClaimManifest = parseCandidateAd05SealedManifestV1(
      persistedClaimManifestRaw,
    );
    if (canonicalSha256(persistedClaimManifest) !==
        canonicalSha256(claimSourceManifest)) {
      ad05bFailV1("AD05B_BINDING_CONFLICT");
    }
    if (existingManifestRaw === null && existingSuppressionRaw === null) {
      transaction.write(manifestPath, writeRecord(manifest));
      transaction.write(suppressionPath, writeRecord(suppression));
      return Object.freeze({
        stateV1: "sealed" as const,
        manifestV1: manifest,
        suppressionV1: suppression,
      });
    }
    if (existingManifestRaw === null || existingSuppressionRaw === null) {
      ad05bFailV1("AD05B_BINDING_CONFLICT");
    }
    const existingManifest = parseCandidateAd05bIdentityReferenceManifestV1(
      existingManifestRaw,
    );
    const existingSuppression = parseCandidateAd05bIdentitySuppressionV1(
      existingSuppressionRaw,
    );
    assertCandidateAd05bManifestSuppressionBindingV1({
      manifest: existingManifest,
      suppression: existingSuppression,
      claimSourceManifest: persistedClaimManifest,
    });
    if (canonicalSha256(existingManifest) !== canonicalSha256(manifest) ||
        canonicalSha256(existingSuppression) !== canonicalSha256(suppression)) {
      ad05bFailV1("AD05B_BINDING_CONFLICT");
    }
    return Object.freeze({
      stateV1: "replayed" as const,
      manifestV1: existingManifest,
      suppressionV1: existingSuppression,
    });
  });
}

export async function requireCandidateAd05bIdentitySuppressionBundleV1(input: {
  repository: CandidateAd05ManifestReaderV1;
  manifestV1: CandidateAd05bIdentityReferenceManifestV1;
  suppressionV1: CandidateAd05bIdentitySuppressionV1;
  claimSourceManifestV1: CandidateAd05SealedManifestV1;
}): Promise<void> {
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1(input.manifestV1);
  const suppression = parseCandidateAd05bIdentitySuppressionV1(input.suppressionV1);
  const claimSourceManifest = parseCandidateAd05SealedManifestV1(
    input.claimSourceManifestV1,
  );
  const claimBinding = manifest.effectBindingsV1[0];
  const [persistedManifestRaw, persistedSuppressionRaw,
    persistedClaimSourceRaw] = await Promise.all([
    input.repository.read(ad05bIdentityReferenceManifestPathV1({
      internalJobId: manifest.internalJobId,
      manifestIdV1: manifest.manifestIdV1,
    })),
    input.repository.read(ad05bIdentitySuppressionPathV1(suppression)),
    input.repository.read(ad05ManifestPathV1(claimBinding)),
  ]);
  if (persistedManifestRaw === null || persistedSuppressionRaw === null ||
      persistedClaimSourceRaw === null) ad05bFailV1("AD05B_BLOCKED");
  const persistedManifest = parseCandidateAd05bIdentityReferenceManifestV1(
    persistedManifestRaw,
  );
  const persistedSuppression = parseCandidateAd05bIdentitySuppressionV1(
    persistedSuppressionRaw,
  );
  const persistedClaimSource = parseCandidateAd05SealedManifestV1(
    persistedClaimSourceRaw,
  );
  assertCandidateAd05bManifestSuppressionBindingV1({
    manifest: persistedManifest,
    suppression: persistedSuppression,
    claimSourceManifest: persistedClaimSource,
  });
  if (canonicalSha256(persistedManifest) !== canonicalSha256(manifest) ||
      canonicalSha256(persistedSuppression) !== canonicalSha256(suppression) ||
      canonicalSha256(persistedClaimSource) !==
        canonicalSha256(claimSourceManifest)) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
}

export interface CandidateAd05bAccountPersonClaimV1 {
  schemaVersion: 1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationIdV1: string;
  subjectIdV1: string;
  claimIdV1: string;
  claimKindV1: "self" | "player" | "guardian";
  claimVerificationStateV1: "verified";
  claimProvenanceIdV1: string;
  identityEvidenceIdV1: string;
  identityEvidenceProvenanceIdV1: string;
  publicationPolicyDecisionIdV1: string;
  fieldLevelPublicationPolicyIdV1: string;
  fieldLevelPublicationPolicyVersionV1: string;
  fieldLevelPublicationPolicyProvenanceIdV1: string;
  minorStatusV1: Ad05bMinorStatusV1;
  accountAssociationStateV1: "active" | "suppressedForDeletedGeneration";
  authUidV2: string | null;
  authUidUtf16LeBase64UrlV1: string | null;
  generationHash: string | null;
  accountLifecycleEpochV2: number | null;
  suppressionFingerprintV1: string | null;
  identityReferenceManifestFingerprintV1: string | null;
  recordVersionV1: string;
}

export function parseCandidateAd05bAccountPersonClaimV1(
  value: unknown,
): CandidateAd05bAccountPersonClaimV1 {
  const data = exact(value, [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "associationIdV1",
    "subjectIdV1", "claimIdV1", "claimKindV1",
    "claimVerificationStateV1", "claimProvenanceIdV1", "identityEvidenceIdV1",
    "identityEvidenceProvenanceIdV1", "publicationPolicyDecisionIdV1",
    "fieldLevelPublicationPolicyIdV1", "fieldLevelPublicationPolicyVersionV1",
    "fieldLevelPublicationPolicyProvenanceIdV1", "minorStatusV1",
    "accountAssociationStateV1", "authUidV2",
    "authUidUtf16LeBase64UrlV1", "generationHash",
    "accountLifecycleEpochV2", "suppressionFingerprintV1",
    "identityReferenceManifestFingerprintV1", "recordVersionV1",
  ]);
  if (data.schemaVersion !== 1 ||
      !["self", "player", "guardian"].includes(data.claimKindV1 as string) ||
      data.claimVerificationStateV1 !== "verified" ||
      !["verifiedAdult", "verifiedMinor", "unknown"].includes(
        data.minorStatusV1 as string,
      ) ||
      (data.accountAssociationStateV1 !== "active" &&
       data.accountAssociationStateV1 !== "suppressedForDeletedGeneration")) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  const active = data.accountAssociationStateV1 === "active";
  const authUidV2 = data.authUidV2 === null ? null :
    ad04FirebaseUidV1(data.authUidV2);
  const uidBytes = data.authUidUtf16LeBase64UrlV1 === null ? null :
    ad04OpaqueIdV1(data.authUidUtf16LeBase64UrlV1);
  const generationHash = data.generationHash === null ? null :
    ad04HashV1(data.generationHash);
  const accountLifecycleEpochV2 = ad04NullableCounterV1(
    data.accountLifecycleEpochV2,
  );
  const suppressionFingerprint = data.suppressionFingerprintV1 === null ? null :
    ad04HashV1(data.suppressionFingerprintV1);
  const referenceManifestFingerprint =
    data.identityReferenceManifestFingerprintV1 === null ? null :
      ad04HashV1(data.identityReferenceManifestFingerprintV1);
  if (active !== (authUidV2 !== null && uidBytes !== null &&
      generationHash !== null && accountLifecycleEpochV2 !== null &&
      suppressionFingerprint === null && referenceManifestFingerprint === null) ||
      (active && uidBytes !== firebaseUidUtf16LeBase64Url(authUidV2 as string)) ||
      (!active && (authUidV2 !== null || uidBytes !== null ||
       generationHash !== null || accountLifecycleEpochV2 !== null ||
       suppressionFingerprint === null || referenceManifestFingerprint === null))) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  return Object.freeze({
    schemaVersion: 1,
    ...ad04ScopeV1({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: active ? authUidV2 : "suppressed-account-binding",
    }),
    associationIdV1: ad04OpaqueIdV1(data.associationIdV1),
    subjectIdV1: ad04OpaqueIdV1(data.subjectIdV1),
    claimIdV1: ad04OpaqueIdV1(data.claimIdV1),
    claimKindV1: data.claimKindV1 as CandidateAd05bAccountPersonClaimV1["claimKindV1"],
    claimVerificationStateV1: "verified",
    claimProvenanceIdV1: ad04OpaqueIdV1(data.claimProvenanceIdV1),
    identityEvidenceIdV1: ad04OpaqueIdV1(data.identityEvidenceIdV1),
    identityEvidenceProvenanceIdV1: ad04OpaqueIdV1(
      data.identityEvidenceProvenanceIdV1,
    ),
    publicationPolicyDecisionIdV1: ad04NamespaceV1(
      data.publicationPolicyDecisionIdV1,
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
    minorStatusV1: data.minorStatusV1 as Ad05bMinorStatusV1,
    accountAssociationStateV1: data.accountAssociationStateV1,
    authUidV2,
    authUidUtf16LeBase64UrlV1: uidBytes,
    generationHash,
    accountLifecycleEpochV2,
    suppressionFingerprintV1: suppressionFingerprint,
    identityReferenceManifestFingerprintV1: referenceManifestFingerprint,
    recordVersionV1: ad04OpaqueIdV1(data.recordVersionV1),
  });
}

function createClaimDetachmentEffectV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05bIdentityReferenceManifestV1;
  suppressionV1: CandidateAd05bIdentitySuppressionV1;
  sourceRecordVersionAfterV1: string;
}): CandidateAd05TransactionalDocumentEffectV1 {
  const binding = parseCandidateAd05ExecutionBindingV1(input.bindingV1);
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1(input.manifestV1);
  const suppression = parseCandidateAd05bIdentitySuppressionV1(input.suppressionV1);
  const sourceRecordVersionAfterV1 = ad04OpaqueIdV1(
    input.sourceRecordVersionAfterV1,
  );
  return Object.freeze({
    sourceRecordVersionV1: (value: unknown) =>
      parseCandidateAd05bAccountPersonClaimV1(value).recordVersionV1,
    mutateBoundSourceV1: ({item, transaction}: {
      binding: CandidateAd05ExecutionBindingV1;
      item: CandidateAd05ManifestItemV1;
      transaction: Parameters<CandidateAd05TransactionalDocumentEffectV1[
        "mutateBoundSourceV1"
      ]>[0]["transaction"];
    }) => {
      const claim = parseCandidateAd05bAccountPersonClaimV1(
        transaction.sourceRecordBeforeV1,
      );
      if (binding.adapterIdV1 !== "account_person_claims" ||
          binding.actionV1 !== "detach" ||
          item.sourceSchemaIdV1 !== "account_person_claim_v1" ||
          item.sourceSchemaVersionV1 !== "schema_v1" ||
          item.provenanceIdV1 !== suppression.claimProvenanceIdV1 ||
          item.associationScopeHashV1 !==
            canonicalSha256(suppression.associationIdV1) ||
          claim.authProjectIdV2 !== binding.authProjectIdV2 ||
          claim.authTenantIdV2 !== binding.authTenantIdV2 ||
          claim.authUidV2 !== binding.authUidV2 ||
          claim.authUidUtf16LeBase64UrlV1 !==
            binding.authUidUtf16LeBase64UrlV1 ||
          claim.generationHash !== binding.generationHash ||
          claim.accountLifecycleEpochV2 !== binding.acceptedLifecycleEpochV2 ||
          claim.associationIdV1 !== suppression.associationIdV1 ||
          claim.subjectIdV1 !== suppression.subjectIdV1 ||
          claim.claimIdV1 !== suppression.claimIdV1 ||
          claim.claimProvenanceIdV1 !== suppression.claimProvenanceIdV1 ||
          claim.identityEvidenceIdV1 !== suppression.identityEvidenceIdV1 ||
          claim.identityEvidenceProvenanceIdV1 !==
            suppression.identityEvidenceProvenanceIdV1 ||
          claim.publicationPolicyDecisionIdV1 !==
            manifest.publicationPolicyDecisionIdV1 ||
          claim.fieldLevelPublicationPolicyIdV1 !==
            manifest.fieldLevelPublicationPolicyIdV1 ||
          claim.fieldLevelPublicationPolicyVersionV1 !==
            manifest.fieldLevelPublicationPolicyVersionV1 ||
          claim.fieldLevelPublicationPolicyProvenanceIdV1 !==
            manifest.fieldLevelPublicationPolicyProvenanceIdV1 ||
          claim.minorStatusV1 !== suppression.minorStatusV1 ||
          claim.accountAssociationStateV1 !== "active" ||
          sourceRecordVersionAfterV1 === claim.recordVersionV1) {
        ad05bFailV1("AD05B_BINDING_CONFLICT");
      }
      const after = parseCandidateAd05bAccountPersonClaimV1({
        ...claim,
        accountAssociationStateV1: "suppressedForDeletedGeneration",
        authUidV2: null,
        authUidUtf16LeBase64UrlV1: null,
        generationHash: null,
        accountLifecycleEpochV2: null,
        suppressionFingerprintV1: suppression.suppressionFingerprintV1,
        identityReferenceManifestFingerprintV1: manifest.manifestFingerprintV1,
        recordVersionV1: sourceRecordVersionAfterV1,
      });
      transaction.writeSourceV1(writeRecord(after));
      return Object.freeze({
        schemaVersion: 1,
        sourceRecordVersionAfterV1,
        evidenceCodeV1: "account_person_claim_binding_detached",
      });
    },
  });
}

export async function applyTestOnlySyntheticCandidateAd05bClaimDetachmentV1(
  input: {
    repository: CandidateAd05TransactionRepositoryV1;
    bindingV1: CandidateAd05ExecutionBindingV1;
    claimSourceManifestV1: CandidateAd05SealedManifestV1;
    itemV1: CandidateAd05ManifestItemV1;
    identityManifestV1: CandidateAd05bIdentityReferenceManifestV1;
    suppressionV1: CandidateAd05bIdentitySuppressionV1;
    sourceRecordVersionAfterV1: string;
    committedAtSecV1: number;
  },
): Promise<CandidateAd05ItemEffectResultV1> {
  const binding = parseCandidateAd05ExecutionBindingV1(input.bindingV1);
  const identityManifest = parseCandidateAd05bIdentityReferenceManifestV1(
    input.identityManifestV1,
  );
  const suppression = parseCandidateAd05bIdentitySuppressionV1(
    input.suppressionV1,
  );
  const claimSourceManifest = parseCandidateAd05SealedManifestV1(
    input.claimSourceManifestV1,
  );
  const committedAtSecV1 = ad04CounterV1(input.committedAtSecV1);
  if (binding.bindingFingerprintV1 !==
        identityManifest.effectBindingsV1[0].bindingFingerprintV1 ||
      committedAtSecV1 < suppression.createdAtSecV1) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
  const guardedRepository: CandidateAd05TransactionRepositoryV1 = {
    read: (path: string) => input.repository.read(path),
    runTransaction: async <T>(operation: (
      transaction: Parameters<Parameters<
        CandidateAd05TransactionRepositoryV1["runTransaction"]
      >[0]>[0],
    ) => Promise<T>): Promise<T> => input.repository.runTransaction<T>(
      async (transaction) => {
      // This guard runs inside the exact source/receipt transaction used by the
      // frozen AD05-A kernel. The suppression cannot be a pre-read TOCTOU check.
      await requireCandidateAd05bIdentitySuppressionBundleV1({
        repository: transaction,
        manifestV1: identityManifest,
        suppressionV1: suppression,
        claimSourceManifestV1: claimSourceManifest,
      });
      return operation(transaction);
      },
    ),
  };
  return applyCandidateAd05TransactionalDocumentItemV1({
    repository: guardedRepository,
    binding,
    manifest: claimSourceManifest,
    item: input.itemV1,
    effect: createClaimDetachmentEffectV1({
      bindingV1: binding,
      manifestV1: identityManifest,
      suppressionV1: suppression,
      sourceRecordVersionAfterV1: input.sourceRecordVersionAfterV1,
    }),
    committedAtSecV1,
  });
}

export function candidateAd05bMechanicalSupportV1(
  adapterIdV1: Ad05bIdentityAdapterIdV1,
): Readonly<{stateV1: "ready" | "unsupported"; evidenceCodeV1: string}> {
  if (!ad05bIdentityAdapterIdsV1.includes(adapterIdV1)) {
    ad05bFailV1("AD05B_INVALID_RECORD");
  }
  if (adapterIdV1 === "account_person_claims") {
    return Object.freeze({
      stateV1: "ready",
      evidenceCodeV1: "test_only_transactional_claim_detachment",
    });
  }
  return Object.freeze({
    stateV1: "unsupported",
    evidenceCodeV1: adapterIdV1 === "person_identity_evidence" ?
      "versioned_identity_material_guarantee_unavailable" :
      "public_external_cleanup_guarantee_unavailable",
  });
}

export async function evaluateCandidateAd05bSuppressedDeliveryV1(input: {
  repository: CandidateAd05ManifestReaderV1;
  manifestV1: CandidateAd05bIdentityReferenceManifestV1;
  suppressionV1: CandidateAd05bIdentitySuppressionV1;
  claimSourceManifestV1: CandidateAd05SealedManifestV1;
  actionV1: "publication" | "rebuild" | "restoreReplay";
}): Promise<Readonly<{
  allowedV1: false;
  stateV1: "suppressed";
  evidenceCodeV1: string;
  privacyEpochMutationRequestedV1: false;
  releaseHeadMutationRequestedV1: false;
}>> {
  await requireCandidateAd05bIdentitySuppressionBundleV1(input);
  return Object.freeze({
    allowedV1: false,
    stateV1: "suppressed",
    evidenceCodeV1: `identity_${input.actionV1}_suppressed`,
    privacyEpochMutationRequestedV1: false,
    releaseHeadMutationRequestedV1: false,
  });
}

export function assertCandidateAd05bBindingMatchesManifestV1(input: {
  bindingV1: CandidateAd05ExecutionBindingV1;
  manifestV1: CandidateAd05bIdentityReferenceManifestV1;
}): void {
  const binding = parseCandidateAd05ExecutionBindingV1(input.bindingV1);
  const manifest = parseCandidateAd05bIdentityReferenceManifestV1(
    input.manifestV1,
  );
  const expected = manifest.effectBindingsV1.find((entry) =>
    entry.adapterIdV1 === binding.adapterIdV1);
  if (expected === undefined || !sameAd04ScopeV1(expected, binding) ||
      expected.bindingFingerprintV1 !== binding.bindingFingerprintV1) {
    ad05bFailV1("AD05B_BINDING_CONFLICT");
  }
}
