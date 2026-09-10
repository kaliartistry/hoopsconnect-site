import {
  AdapterResultContract,
  accountDeletionAdapterIds,
  validateAdapterResult,
} from "../domain/account_deletion_contract";
import {CandidateCleanupAdapterV1} from "./ad04_worker";
import {
  AccountDeletionAdapterId,
  Ad05DispositionActionV1,
  ad05FailV1,
  ad05PrivateEvidenceRefV1,
} from "./ad05_records";
import {
  ad04ExactKeysV1,
  ad04NamespaceV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
} from "./ad04_records";

export type Ad05ProtectionFamilyV1 = "T" | "V" | "E" | "D" | "R";

export interface CandidateAd05AdapterRegistryRowV1 {
  adapterIdV1: AccountDeletionAdapterId;
  policyDecisionIdV1: string;
  protectionFamilyV1: Ad05ProtectionFamilyV1;
  mechanicalSupportV1: "transactionalDocument" | "evidenceOnly" | "unsupported";
}

const families: readonly Ad05ProtectionFamilyV1[] = ["T", "V", "E", "D", "R"];
const familyByAdapter: Readonly<Record<AccountDeletionAdapterId,
  Ad05ProtectionFamilyV1>> = Object.freeze({
  firebase_auth_identity: "R",
  user_profile: "T",
  memberships_capabilities: "T",
  device_fcm_preferences: "E",
  notification_inbox: "T",
  team_assignments: "T",
  pending_invites: "T",
  historical_invites: "R",
  authorization_evidence: "R",
  personal_ugc: "T",
  official_notices: "R",
  acknowledgements: "R",
  event_attribution: "R",
  account_person_claims: "T",
  person_identity_evidence: "V",
  legacy_player_identity: "V",
  legacy_game_evidence: "V",
  v2_journal_operations: "R",
  local_offline_journal: "D",
  v2_certified_evidence: "R",
  public_projections_exports: "E",
  personal_storage_media: "V",
  shared_association_media: "V",
  device_local_state: "D",
  diagnostics_processors: "E",
  backups_restores: "E",
  deletion_operational_residue: "R",
});

export const candidateAd05AdapterRegistryV1:
readonly CandidateAd05AdapterRegistryRowV1[] = Object.freeze(
  accountDeletionAdapterIds.map((adapterIdV1) => {
    const protectionFamilyV1 = familyByAdapter[adapterIdV1];
    return Object.freeze({
      adapterIdV1,
      policyDecisionIdV1: `retention.${adapterIdV1}`,
      protectionFamilyV1,
      mechanicalSupportV1: protectionFamilyV1 === "T" ?
        "transactionalDocument" as const : protectionFamilyV1 === "R" ?
          "evidenceOnly" as const : "unsupported" as const,
    });
  }),
);

export interface CandidateAd05PolicyDecisionV1 {
  schemaVersion: 1;
  adapterIdV1: AccountDeletionAdapterId;
  policyDecisionIdV1: string;
  policyVersionV1: string;
  decisionStateV1: "approved" | "pendingAuthoritativeDecision" |
    "pendingOperationalProof" | "rejected" | "superseded";
  approvedV1: boolean;
  actionV1: Ad05DispositionActionV1 | null;
}

export interface CandidateAd05SyntheticPolicyRegistryV1 {
  schemaVersion: 1;
  testOnlySyntheticV1: true;
  activationApprovedV1: true;
  policyVersionV1: string;
  decisionsV1: readonly CandidateAd05PolicyDecisionV1[];
}

export interface CandidateAd05AdapterRuntimeV1 {
  readonly adapterIdV1: AccountDeletionAdapterId;
  inspectEffectV1(input: Parameters<CandidateCleanupAdapterV1["inspectEffectV1"]>[0]):
    Promise<AdapterResultContract | null>;
  applyEffectV1(input: Parameters<CandidateCleanupAdapterV1["applyEffectV1"]>[0]):
    Promise<AdapterResultContract | null>;
}

type Ad04CleanupEffectInputV1 = Parameters<
  CandidateCleanupAdapterV1["inspectEffectV1"]
>[0];

function exact(value: unknown, keys: readonly string[]): Record<string, unknown> {
  const record = ad04RecordV1(value);
  if (record === null || !ad04ExactKeysV1(record, keys)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return record;
}

function exactAdapterId(value: unknown): AccountDeletionAdapterId {
  const candidate = ad04OpaqueIdV1(value);
  if (!accountDeletionAdapterIds.includes(candidate as AccountDeletionAdapterId)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return candidate as AccountDeletionAdapterId;
}

function parseAction(value: unknown): Ad05DispositionActionV1 | null {
  if (value === null) return null;
  if (value !== "erase" && value !== "detach" && value !== "pseudonymize" &&
      value !== "restrictedRetention" &&
      value !== "accessRevokedAwaitingExpiry" && value !== "notApplicable") {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  return value;
}

export function validateCandidateAd05AdapterRegistryV1(
  value: unknown,
): readonly CandidateAd05AdapterRegistryRowV1[] {
  if (!Array.isArray(value) || value.length !== accountDeletionAdapterIds.length) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const parsed = value.map((entry): CandidateAd05AdapterRegistryRowV1 => {
    const data = exact(entry, [
      "adapterIdV1", "policyDecisionIdV1", "protectionFamilyV1",
      "mechanicalSupportV1",
    ]);
    const adapterIdV1 = exactAdapterId(data.adapterIdV1);
    if (typeof data.protectionFamilyV1 !== "string" ||
        !families.includes(data.protectionFamilyV1 as Ad05ProtectionFamilyV1) ||
        !["transactionalDocument", "evidenceOnly", "unsupported"].includes(
          data.mechanicalSupportV1 as string,
        )) ad05FailV1("AD05_INVALID_RECORD");
    const row: CandidateAd05AdapterRegistryRowV1 = Object.freeze({
      adapterIdV1,
      policyDecisionIdV1: ad04NamespaceV1(data.policyDecisionIdV1),
      protectionFamilyV1: data.protectionFamilyV1 as Ad05ProtectionFamilyV1,
      mechanicalSupportV1: data.mechanicalSupportV1 as
        CandidateAd05AdapterRegistryRowV1["mechanicalSupportV1"],
    });
    if (row.policyDecisionIdV1 !== `retention.${adapterIdV1}` ||
        (row.protectionFamilyV1 === "T" &&
         row.mechanicalSupportV1 !== "transactionalDocument") ||
        (row.protectionFamilyV1 === "R" &&
         row.mechanicalSupportV1 !== "evidenceOnly") ||
        (["V", "E", "D"].includes(row.protectionFamilyV1) &&
         row.mechanicalSupportV1 !== "unsupported")) {
      ad05FailV1("AD05_INVALID_RECORD");
    }
    return row;
  });
  if (new Set(parsed.map((row) => row.adapterIdV1)).size !== parsed.length ||
      !accountDeletionAdapterIds.every((id, index) =>
        parsed[index].adapterIdV1 === id)) ad05FailV1("AD05_INVALID_RECORD");
  return Object.freeze(parsed);
}

export function validateNormativeAd05PolicyRegistryV1(value: unknown): void {
  const data = exact(value, [
    "contractVersion", "policyVersion", "activationApproved", "governingMatrix",
    "policyTruths", "requiredDecisionFields", "decisions", "decisionTemplate",
  ]);
  if (data.contractVersion !== "account-deletion-contract-v1" ||
      data.policyVersion !== null || data.activationApproved !== false ||
      !Array.isArray(data.decisions) ||
      data.decisions.length !== accountDeletionAdapterIds.length) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const matrix = exact(data.governingMatrix, [
    "sourceTitle", "sha256", "adapterCount", "normativeInvariants",
  ]);
  if (typeof matrix.sourceTitle !== "string" ||
      matrix.sha256 !== "9a9d0150244fc124bbc8ab1697fba177a3c862de8b7099c5c684d02ed8537832" ||
      matrix.adapterCount !== accountDeletionAdapterIds.length ||
      !Array.isArray(matrix.normativeInvariants) ||
      matrix.normativeInvariants.length !== 5 ||
      !matrix.normativeInvariants.every((entry) => typeof entry === "string")) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const truths = exact(data.policyTruths, [
    "pseudonymizationIsAnonymity", "hashIsAnonymousByDefault",
    "nameOrEmailMatchingLinksIdentity", "unknownMinorStatusDefaultsToAdult",
    "accountDeletionDeletesTenantOrTeam",
    "officialHistoryPermitsIndefiniteIdentifiableRetention",
  ]);
  if (!Object.values(truths).every((entry) => entry === false)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const requiredDecisionFields = [
    "purpose", "approvedBasis", "action", "retentionDuration",
    "retentionClockStart", "holdAuthority", "permittedReaders", "erasureMethod",
    "backupBehavior", "processorBehavior", "minorAndPublicationRule",
    "disclosureTextVersion", "owner",
  ];
  const registryRequiredFields = data.requiredDecisionFields;
  if (!Array.isArray(registryRequiredFields) ||
      registryRequiredFields.length !== requiredDecisionFields.length ||
      !requiredDecisionFields.every((field, index) =>
        registryRequiredFields[index] === field)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const template = exact(data.decisionTemplate, [
    "decisionState", "purpose", "approvedBasis", "action", "retentionDuration",
    "retentionClockStart", "holdAuthority", "permittedReaders", "erasureMethod",
    "backupBehavior", "processorBehavior", "minorAndPublicationRule",
    "disclosureTextVersion", "owner", "evidenceRefs", "approved",
  ]);
  if (template.decisionState !== "pendingAuthoritativeDecision" ||
      template.approved !== false || !Array.isArray(template.evidenceRefs) ||
      template.evidenceRefs.length !== 0 ||
      requiredDecisionFields.some((field) => template[field] !== null)) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const ids = data.decisions.map((entry, index) => {
    const decision = exact(entry, ["id", "adapterId", "dataClass"]);
    const id = exactAdapterId(decision.adapterId);
    if (id !== accountDeletionAdapterIds[index] ||
        decision.id !== `retention.${id}` ||
        typeof decision.dataClass !== "string" || decision.dataClass.length === 0) {
      ad05FailV1("AD05_INVALID_RECORD");
    }
    return id;
  });
  if (new Set(ids).size !== accountDeletionAdapterIds.length) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
}

export function parseCandidateAd05SyntheticPolicyRegistryV1(
  value: unknown,
): CandidateAd05SyntheticPolicyRegistryV1 {
  const data = exact(value, [
    "schemaVersion", "testOnlySyntheticV1", "activationApprovedV1",
    "policyVersionV1", "decisionsV1",
  ]);
  if (data.schemaVersion !== 1 || data.testOnlySyntheticV1 !== true ||
      data.activationApprovedV1 !== true || !Array.isArray(data.decisionsV1) ||
      data.decisionsV1.length !== accountDeletionAdapterIds.length) {
    ad05FailV1("AD05_INVALID_RECORD");
  }
  const policyVersionV1 = ad04OpaqueIdV1(data.policyVersionV1);
  const decisionsV1 = data.decisionsV1.map((entry, index):
  CandidateAd05PolicyDecisionV1 => {
    const decision = exact(entry, [
      "schemaVersion", "adapterIdV1", "policyDecisionIdV1", "policyVersionV1",
      "decisionStateV1", "approvedV1", "actionV1",
    ]);
    const adapterIdV1 = exactAdapterId(decision.adapterIdV1);
    if (decision.schemaVersion !== 1 || adapterIdV1 !== accountDeletionAdapterIds[index] ||
        decision.policyDecisionIdV1 !== `retention.${adapterIdV1}` ||
        decision.policyVersionV1 !== policyVersionV1 ||
        !["approved", "pendingAuthoritativeDecision", "pendingOperationalProof",
          "rejected", "superseded"].includes(decision.decisionStateV1 as string) ||
        typeof decision.approvedV1 !== "boolean") {
      ad05FailV1("AD05_INVALID_RECORD");
    }
    const actionV1 = parseAction(decision.actionV1);
    if ((decision.approvedV1 === true) !==
        (decision.decisionStateV1 === "approved" && actionV1 !== null)) {
      ad05FailV1("AD05_INVALID_RECORD");
    }
    return Object.freeze({
      schemaVersion: 1,
      adapterIdV1,
      policyDecisionIdV1: decision.policyDecisionIdV1 as string,
      policyVersionV1,
      decisionStateV1: decision.decisionStateV1 as
        CandidateAd05PolicyDecisionV1["decisionStateV1"],
      approvedV1: decision.approvedV1,
      actionV1,
    });
  });
  if (new Set(decisionsV1.map((decision) => decision.adapterIdV1)).size !==
      accountDeletionAdapterIds.length) ad05FailV1("AD05_INVALID_RECORD");
  return Object.freeze({
    schemaVersion: 1,
    testOnlySyntheticV1: true,
    activationApprovedV1: true,
    policyVersionV1,
    decisionsV1: Object.freeze(decisionsV1),
  });
}

function blockedResultV1(adapterIdV1: AccountDeletionAdapterId,
  policyVersion: string): AdapterResultContract {
  return validateAdapterResult({
    schemaVersion: 1,
    adapterId: adapterIdV1,
    applicability: "unknown",
    state: "blocked",
    disposition: "unresolved",
    policyDecisionState: "pendingAuthoritativeDecision",
    policyDecisionId: `retention.${adapterIdV1}`,
    policyVersion,
    holdState: "unknown",
    evidenceCode: "authoritative_policy_not_approved",
    evidenceRef: ad05PrivateEvidenceRefV1({adapterIdV1, state: "blocked"}),
    holdBoundaryAt: null,
  });
}

function unsupportedResultV1(adapterIdV1: AccountDeletionAdapterId,
  policyVersion: string): AdapterResultContract {
  return validateAdapterResult({
    schemaVersion: 1,
    adapterId: adapterIdV1,
    applicability: "unknown",
    state: "unsupported",
    disposition: "unresolved",
    policyDecisionState: "approved",
    policyDecisionId: `retention.${adapterIdV1}`,
    policyVersion,
    holdState: "unknown",
    evidenceCode: "ad05_mechanical_guarantee_unsupported",
    evidenceRef: ad05PrivateEvidenceRefV1({adapterIdV1, state: "unsupported"}),
    holdBoundaryAt: null,
  });
}

function buildAdaptersV1(input: {
  decisionsV1: ReadonlyMap<AccountDeletionAdapterId, CandidateAd05PolicyDecisionV1> | null;
  runtimesV1: ReadonlyMap<AccountDeletionAdapterId, CandidateAd05AdapterRuntimeV1>;
}): readonly CandidateCleanupAdapterV1[] {
  const registry = validateCandidateAd05AdapterRegistryV1(candidateAd05AdapterRegistryV1);
  return Object.freeze(registry.map((row): CandidateCleanupAdapterV1 => {
    const evaluate = async (
      effectInput: Parameters<CandidateCleanupAdapterV1["inspectEffectV1"]>[0],
      apply: boolean,
    ): Promise<AdapterResultContract | null> => {
      const policyVersion = ad04OpaqueIdV1(effectInput.policyVersion);
      const decision = input.decisionsV1?.get(row.adapterIdV1) ?? null;
      if (decision === null || decision.approvedV1 !== true) {
        return blockedResultV1(row.adapterIdV1, policyVersion);
      }
      if (decision.policyVersionV1 !== policyVersion) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      const runtime = input.runtimesV1.get(row.adapterIdV1);
      if (row.mechanicalSupportV1 === "unsupported" || runtime === undefined ||
          runtime.adapterIdV1 !== row.adapterIdV1) {
        return unsupportedResultV1(row.adapterIdV1, policyVersion);
      }
      const result = apply ? await runtime.applyEffectV1(effectInput) :
        await runtime.inspectEffectV1(effectInput);
      if (result === null) return null;
      const parsed = validateAdapterResult(result);
      if (parsed.adapterId !== row.adapterIdV1 ||
          parsed.policyDecisionId !== row.policyDecisionIdV1 ||
          parsed.policyVersion !== policyVersion ||
          (parsed.state !== "unsupported" &&
           parsed.disposition !== decision.actionV1)) {
        ad05FailV1("AD05_BINDING_CONFLICT");
      }
      return parsed;
    };
    return Object.freeze({
      adapterIdV1: row.adapterIdV1,
      adapterVersionV1: "account-deletion-adapter-v1",
      inspectEffectV1: (effectInput: Ad04CleanupEffectInputV1) =>
        evaluate(effectInput, false),
      // AD04 ignores apply's private return and inspects again. Null is the only
      // allowed representation of nonterminal AD05 chunk progress.
      applyEffectV1: (effectInput: Ad04CleanupEffectInputV1) =>
        evaluate(effectInput, true),
    });
  }));
}

/** Normative AD01 policy is deliberately pending, so these wrappers cannot mutate. */
export function createDormantCandidateAd05AdaptersV1():
readonly CandidateCleanupAdapterV1[] {
  return buildAdaptersV1({decisionsV1: null, runtimesV1: new Map()});
}

/** Synthetic approval is accepted only through this explicitly test-only seam. */
export function createTestOnlySyntheticCandidateAd05AdaptersV1(input: {
  syntheticPolicyV1: unknown;
  runtimesV1: readonly CandidateAd05AdapterRuntimeV1[];
}): readonly CandidateCleanupAdapterV1[] {
  const policy = parseCandidateAd05SyntheticPolicyRegistryV1(input.syntheticPolicyV1);
  const decisions = new Map(policy.decisionsV1.map((decision) =>
    [decision.adapterIdV1, decision] as const));
  const runtimes = new Map<AccountDeletionAdapterId, CandidateAd05AdapterRuntimeV1>();
  for (const runtime of input.runtimesV1) {
    if (runtimes.has(runtime.adapterIdV1)) ad05FailV1("AD05_INVALID_RECORD");
    runtimes.set(runtime.adapterIdV1, runtime);
  }
  return buildAdaptersV1({decisionsV1: decisions, runtimesV1: runtimes});
}

export interface CandidateAd05FirebaseAuthEvidenceVerifierV1 {
  verifyBoundAd04AuthEvidenceV1(input:
    Parameters<CandidateCleanupAdapterV1["inspectEffectV1"]>[0]): Promise<unknown>;
}

export function createFirebaseAuthEvidenceOnlyRuntimeV1(
  verifier: CandidateAd05FirebaseAuthEvidenceVerifierV1,
): CandidateAd05AdapterRuntimeV1 {
  const inspect = async (input:
    Parameters<CandidateCleanupAdapterV1["inspectEffectV1"]>[0]):
  Promise<AdapterResultContract | null> => {
    const data = exact(await verifier.verifyBoundAd04AuthEvidenceV1(input), [
      "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
      "internalJobId", "effectIdV1", "generationHash", "acceptedLifecycleEpochV2",
      "policyVersionV1",
      "ad04AuthCheckpointCompleteV1", "ad04AuthEffectReceiptCompleteV1",
      "evidenceCodeV1", "evidenceIdV1",
    ]);
    if (data.schemaVersion !== 1 || data.effectIdV1 !== input.effectIdV1 ||
        data.authProjectIdV2 !== input.scope.authProjectIdV2 ||
        data.authTenantIdV2 !== input.scope.authTenantIdV2 ||
        data.authUidV2 !== input.scope.authUidV2 ||
        data.internalJobId !== input.internalJobId ||
        data.generationHash !== input.generationHash ||
        data.acceptedLifecycleEpochV2 !== input.acceptedLifecycleEpochV2 ||
        data.policyVersionV1 !== input.policyVersion ||
        data.ad04AuthCheckpointCompleteV1 !== true ||
        data.ad04AuthEffectReceiptCompleteV1 !== true) {
      ad05FailV1("AD05_BINDING_CONFLICT");
    }
    return validateAdapterResult({
      schemaVersion: 1,
      adapterId: "firebase_auth_identity",
      applicability: "applicable",
      state: "complete",
      disposition: "erase",
      policyDecisionState: "approved",
      policyDecisionId: "retention.firebase_auth_identity",
      policyVersion: input.policyVersion,
      holdState: "none",
      evidenceCode: ad04OpaqueIdV1(data.evidenceCodeV1),
      evidenceRef: ad05PrivateEvidenceRefV1(ad04OpaqueIdV1(data.evidenceIdV1)),
      holdBoundaryAt: null,
    });
  };
  return Object.freeze({
    adapterIdV1: "firebase_auth_identity",
    inspectEffectV1: inspect,
    // Evidence-only: apply re-verifies AD04 evidence and never issues Auth mutation.
    applyEffectV1: async (input: Ad04CleanupEffectInputV1) => {
      const result = await inspect(input);
      if (result === null) ad05FailV1("AD05_INCOMPLETE_INVENTORY");
      return result;
    },
  });
}
