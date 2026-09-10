import {
  AdapterResultContract,
  ProviderCheckpointContract,
  accountDeletionAdapterIds,
  isDeletionComplete,
  isProviderCheckpointTerminal,
} from "../domain/account_deletion_contract";
import {
  ACCOUNT_DELETION_AD04_ATTENTION_ATTEMPT_V1,
  ACCOUNT_DELETION_AD04_LEASE_SEC_V1,
  CandidateDeletionEffectReceiptV1,
  CandidateDeletionJobBindingV1,
  CandidateDeletionProviderBindingV1,
  CandidateDeletionRepositoryV1,
  CandidateDeletionTaskV1,
  DeletionEffectOutcomeV1,
  DeletionTaskKindV1,
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04FailV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  candidateAccountLifecycleAuthorityPathV1,
  deletionAdapterResultPathV1,
  deletionAlertPathV1,
  deletionEffectReceiptPathV1,
  deletionJobBindingPathV1,
  deletionJobPathV1,
  deletionProviderBindingPathV1,
  deletionProviderCheckpointPathV1,
  deletionTaskEffectIdV1,
  deletionTaskEffectFingerprintV1,
  deletionTaskPathV1,
  initialDeletionTasksV1,
  parseCandidateAdapterResultV1,
  parseCandidateAccountLifecycleAuthorityV2ForDeletionV1,
  parseCandidateDeletionJobBindingV1,
  parseCandidateDeletionJobV1,
  parseCandidateDeletionProviderBindingV1,
  parseCandidateDeletionTaskV1,
  parseCandidateEffectReceiptV1,
  parseCandidateProviderCheckpointV1,
  retryDelaySecV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export interface CandidateDeletionTaskLocatorV1 {
  schemaVersion: 1;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  internalJobId: string;
  effectIdV1: string;
}

export interface CandidateAuthProviderStateV1 {
  accountStateV1: "present" | "absent";
  observedGenerationHashV1: string | null;
  disabledV1: boolean;
  refreshTokensRevokedV1: boolean;
}

export interface CandidateFirebaseAuthAdapterV1 {
  inspectSingleUserV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    effectIdV1: string;
  }): Promise<CandidateAuthProviderStateV1>;
  // Each mutator must atomically compare the current Auth generation before
  // applying its single-user effect and return the observed boundary state.
  // A UID-only Admin SDK mutation does not satisfy this contract by itself.
  disableSingleUserIfGenerationMatchesV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    effectIdV1: string;
  }): Promise<CandidateAuthProviderStateV1>;
  revokeRefreshTokensIfGenerationMatchesV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    effectIdV1: string;
  }): Promise<CandidateAuthProviderStateV1>;
  deleteSingleUserIfGenerationMatchesV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    effectIdV1: string;
  }): Promise<CandidateAuthProviderStateV1>;
}

export interface CandidateAppleCredentialAdapterV1 {
  inspectRevocationV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    providerSubjectHashV1: string;
    providerRevocationRefV1: string;
    effectIdV1: string;
  }): Promise<{
    revocationStateV1: "pending" | "revoked";
    materialStateV1: "available" | "destroyed";
  }>;
  revokeCredentialV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    providerSubjectHashV1: string;
    providerRevocationRefV1: string;
    effectIdV1: string;
  }): Promise<void>;
  destroyRevocationMaterialV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    providerSubjectHashV1: string;
    providerRevocationRefV1: string;
    effectIdV1: string;
  }): Promise<void>;
}

interface CandidateAppleRevocationStateV1 {
  revocationStateV1: "pending" | "revoked";
  materialStateV1: "available" | "destroyed";
}

function parseAppleRevocationStateV1(value: unknown): CandidateAppleRevocationStateV1 {
  const data = ad04RecordV1(value);
  if (data === null || !ad04ExactKeysV1(data, [
    "revocationStateV1", "materialStateV1",
  ]) || !["pending", "revoked"].includes(data.revocationStateV1 as string) ||
      !["available", "destroyed"].includes(data.materialStateV1 as string)) {
    ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
  }
  return Object.freeze({
    revocationStateV1: data.revocationStateV1 as "pending" | "revoked",
    materialStateV1: data.materialStateV1 as "available" | "destroyed",
  });
}

export interface CandidateCleanupAdapterV1 {
  readonly adapterIdV1: string;
  readonly adapterVersionV1: string;
  inspectEffectV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    internalJobId: string;
    effectIdV1: string;
    policyVersion: string;
  }): Promise<unknown | null>;
  applyEffectV1(input: {
    scope: ReturnType<typeof ad04ScopeV1>;
    generationHash: string;
    acceptedLifecycleEpochV2: number;
    internalJobId: string;
    effectIdV1: string;
    policyVersion: string;
  }): Promise<unknown>;
}

export interface CandidateDeletionWorkerHooksV1 {
  beforeExternalCallV1?(label: string, effectIdV1: string): Promise<void> | void;
  afterExternalCallV1?(label: string, effectIdV1: string): Promise<void> | void;
  beforeCheckpointPersistV1?(effectIdV1: string): Promise<void> | void;
}

export interface CandidateTaskRunResultV1 {
  stateV1: "completed" | "alreadyCompleted" | "busy" | "notDue" |
    "dependencyPending" | "retryScheduled" | "needsAttention" | "staleLease";
  effectIdV1: string;
  providerCalledV1: boolean;
}

interface ClaimedTaskV1 {
  task: CandidateDeletionTaskV1;
  job: ReturnType<typeof parseCandidateDeletionJobV1>;
  binding: CandidateDeletionJobBindingV1;
  providerBinding: CandidateDeletionProviderBindingV1;
}

interface ExecutionResultV1 {
  terminalV1: boolean;
  attentionV1: boolean;
  outcomeV1: DeletionEffectOutcomeV1;
  evidenceCodeV1: string;
  adapterResultV1: AdapterResultContract | null;
  providerCheckpointV1: ProviderCheckpointContract | null;
  authAbsentV1: boolean | null;
  providerCalledV1: boolean;
}

function asWriteRecord(value: object): Readonly<Record<string, unknown>> {
  return value as unknown as Readonly<Record<string, unknown>>;
}

function parseLocatorV1(value: unknown): CandidateDeletionTaskLocatorV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "generationHash", "acceptedLifecycleEpochV2", "internalJobId", "effectIdV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) || data.schemaVersion !== 1) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    ...ad04ScopeV1({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: data.authUidV2,
    }),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    effectIdV1: ad04OpaqueIdV1(data.effectIdV1),
  });
}

function taskMatchesLocatorV1(
  task: CandidateDeletionTaskV1,
  locator: CandidateDeletionTaskLocatorV1,
): boolean {
  const expected = initialDeletionTasksV1({
    scope: task,
    internalJobId: task.internalJobId,
    generationHash: task.generationHash,
    acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2,
    nowSecV1: task.createdAtSecV1,
  }).find((candidate) => candidate.effectIdV1 === task.effectIdV1);
  return sameAd04ScopeV1(task, locator) &&
    task.generationHash === locator.generationHash &&
    task.acceptedLifecycleEpochV2 === locator.acceptedLifecycleEpochV2 &&
    task.internalJobId === locator.internalJobId &&
    task.effectIdV1 === locator.effectIdV1 &&
    expected !== undefined &&
    task.kindV1 === expected.kindV1 &&
    task.adapterIdV1 === expected.adapterIdV1 &&
    task.adapterVersionV1 === expected.adapterVersionV1 &&
    task.effectFingerprintV1 === expected.effectFingerprintV1 &&
    task.effectIdV1 === deletionTaskEffectIdV1({
      internalJobId: task.internalJobId,
      generationHash: task.generationHash,
      acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2,
      kindV1: task.kindV1,
      adapterIdV1: task.adapterIdV1,
    }) && task.effectFingerprintV1 === deletionTaskEffectFingerprintV1({
      scope: task,
      internalJobId: task.internalJobId,
      generationHash: task.generationHash,
      acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2,
      kindV1: task.kindV1,
      adapterIdV1: task.adapterIdV1,
      adapterVersionV1: task.adapterVersionV1,
    });
}

function receiptMatchesTaskV1(
  receipt: CandidateDeletionEffectReceiptV1,
  task: CandidateDeletionTaskV1,
): boolean {
  return sameAd04ScopeV1(receipt, task) &&
    receipt.internalJobId === task.internalJobId &&
    receipt.generationHash === task.generationHash &&
    receipt.acceptedLifecycleEpochV2 === task.acceptedLifecycleEpochV2 &&
    receipt.effectIdV1 === task.effectIdV1 &&
    receipt.effectFingerprintV1 === task.effectFingerprintV1 &&
    receipt.kindV1 === task.kindV1 && receipt.adapterIdV1 === task.adapterIdV1;
}

function taskDependenciesV1(task: CandidateDeletionTaskV1): readonly string[] {
  const dependency = (kindV1: DeletionTaskKindV1, adapterIdV1: string | null = null) =>
    deletionTaskEffectIdV1({
      internalJobId: task.internalJobId,
      generationHash: task.generationHash,
      acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2,
      kindV1,
      adapterIdV1,
    });
  if (task.kindV1 === "authRevokeRefreshTokens") return [dependency("authDisable")];
  if (task.kindV1 === "authDeleteSingleUser") {
    return [dependency("authRevokeRefreshTokens")];
  }
  if (task.kindV1 === "authVerifyAbsence") return [dependency("authDeleteSingleUser")];
  if (task.kindV1 === "reconcileCompletion") {
    return [
      dependency("authDisable"),
      dependency("authRevokeRefreshTokens"),
      dependency("authDeleteSingleUser"),
      dependency("authVerifyAbsence"),
      dependency("appleCredentialDisposition"),
      ...accountDeletionAdapterIds.map((adapterId) => dependency("cleanupAdapter", adapterId)),
    ];
  }
  return [];
}

function resumeStageForTaskV1(task: CandidateDeletionTaskV1):
  "fencingExternalAccess" | "inventory" | "verify" {
  if (task.kindV1 === "cleanupAdapter") return "inventory";
  if (task.kindV1 === "reconcileCompletion") return "verify";
  return "fencingExternalAccess";
}

function authStateV1(value: unknown): CandidateAuthProviderStateV1 {
  const data = ad04RecordV1(value);
  if (data === null || !ad04ExactKeysV1(data, [
    "accountStateV1", "observedGenerationHashV1", "disabledV1",
    "refreshTokensRevokedV1",
  ]) || !["present", "absent"].includes(data.accountStateV1 as string) ||
      typeof data.disabledV1 !== "boolean" ||
      typeof data.refreshTokensRevokedV1 !== "boolean" ||
      (data.accountStateV1 === "absent" &&
       (data.observedGenerationHashV1 !== null || data.disabledV1 !== false ||
        data.refreshTokensRevokedV1 !== false)) ||
      (data.accountStateV1 === "present" &&
       (typeof data.observedGenerationHashV1 !== "string" ||
        !/^[a-f0-9]{64}$/.test(data.observedGenerationHashV1)))) {
    ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
  }
  return Object.freeze({
    accountStateV1: data.accountStateV1 as "present" | "absent",
    observedGenerationHashV1: data.observedGenerationHashV1 as string | null,
    disabledV1: data.disabledV1,
    refreshTokensRevokedV1: data.refreshTokensRevokedV1,
  });
}

async function externalCallV1<T>(input: {
  label: string;
  effectIdV1: string;
  hooks?: CandidateDeletionWorkerHooksV1;
  operation: () => Promise<T>;
}): Promise<T> {
  await input.hooks?.beforeExternalCallV1?.(input.label, input.effectIdV1);
  const value = await input.operation();
  await input.hooks?.afterExternalCallV1?.(input.label, input.effectIdV1);
  return value;
}

async function inspectAuthV1(input: {
  adapter: CandidateFirebaseAuthAdapterV1;
  task: CandidateDeletionTaskV1;
  hooks?: CandidateDeletionWorkerHooksV1;
}): Promise<CandidateAuthProviderStateV1> {
  const state = authStateV1(await externalCallV1({
    label: "firebaseAuth.inspectSingleUserV1",
    effectIdV1: input.task.effectIdV1,
    hooks: input.hooks,
    operation: () => input.adapter.inspectSingleUserV1({
      scope: ad04ScopeV1(input.task),
      generationHash: input.task.generationHash,
      acceptedLifecycleEpochV2: input.task.acceptedLifecycleEpochV2,
      effectIdV1: input.task.effectIdV1,
    }),
  }));
  if (state.accountStateV1 === "present" &&
      state.observedGenerationHashV1 !== input.task.generationHash) {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
  return state;
}

async function mutateAuthForGenerationV1(input: {
  label: string;
  task: CandidateDeletionTaskV1;
  hooks?: CandidateDeletionWorkerHooksV1;
  operation: () => Promise<CandidateAuthProviderStateV1>;
}): Promise<void> {
  const state = authStateV1(await externalCallV1({
    label: input.label,
    effectIdV1: input.task.effectIdV1,
    hooks: input.hooks,
    operation: input.operation,
  }));
  if (state.accountStateV1 === "present" &&
      state.observedGenerationHashV1 !== input.task.generationHash) {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
}

async function executeAuthTaskV1(input: {
  task: CandidateDeletionTaskV1;
  adapter: CandidateFirebaseAuthAdapterV1;
  hooks?: CandidateDeletionWorkerHooksV1;
  nowSecV1: number;
}): Promise<ExecutionResultV1> {
  let state = await inspectAuthV1(input);
  let providerCalledV1 = false;
  const effectInput = {
    scope: ad04ScopeV1(input.task),
    generationHash: input.task.generationHash,
    acceptedLifecycleEpochV2: input.task.acceptedLifecycleEpochV2,
    effectIdV1: input.task.effectIdV1,
  };
  if (input.task.kindV1 === "authDisable") {
    if (state.accountStateV1 === "absent") {
      return successResultV1("alreadySatisfied", "auth_already_absent", false);
    }
    if (!state.disabledV1) {
      providerCalledV1 = true;
      await mutateAuthForGenerationV1({
        label: "firebaseAuth.disableSingleUserIfGenerationMatchesV1",
        task: input.task,
        hooks: input.hooks,
        operation: () => input.adapter.disableSingleUserIfGenerationMatchesV1(
          effectInput,
        ),
      });
      state = await inspectAuthV1(input);
    }
    if (state.accountStateV1 === "present" && !state.disabledV1) {
      ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
    }
    return successResultV1(providerCalledV1 ? "applied" : "alreadySatisfied",
      "auth_disabled", providerCalledV1);
  }
  if (input.task.kindV1 === "authRevokeRefreshTokens") {
    if (state.accountStateV1 === "absent") {
      return successResultV1("alreadySatisfied", "auth_already_absent", false);
    }
    if (!state.refreshTokensRevokedV1) {
      providerCalledV1 = true;
      await mutateAuthForGenerationV1({
        label: "firebaseAuth.revokeRefreshTokensIfGenerationMatchesV1",
        task: input.task,
        hooks: input.hooks,
        operation: () => input.adapter.revokeRefreshTokensIfGenerationMatchesV1(
          effectInput,
        ),
      });
      state = await inspectAuthV1(input);
    }
    if (state.accountStateV1 === "present" && !state.refreshTokensRevokedV1) {
      ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
    }
    return successResultV1(providerCalledV1 ? "applied" : "alreadySatisfied",
      "auth_refresh_tokens_revoked", providerCalledV1);
  }
  if (input.task.kindV1 === "authDeleteSingleUser") {
    if (state.accountStateV1 !== "absent") {
      providerCalledV1 = true;
      await mutateAuthForGenerationV1({
        label: "firebaseAuth.deleteSingleUserIfGenerationMatchesV1",
        task: input.task,
        hooks: input.hooks,
        operation: () => input.adapter.deleteSingleUserIfGenerationMatchesV1(
          effectInput,
        ),
      });
      state = await inspectAuthV1(input);
    }
    if (state.accountStateV1 !== "absent") {
      ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
    }
    return successResultV1(providerCalledV1 ? "applied" : "alreadySatisfied",
      "auth_single_user_absent", providerCalledV1);
  }
  if (input.task.kindV1 === "authVerifyAbsence") {
    if (state.accountStateV1 !== "absent") {
      ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
    }
    return {
      ...successResultV1("verifiedComplete", "auth_absence_verified", false),
      authAbsentV1: true,
      providerCheckpointV1: {
        schemaVersion: 1,
        provider: "firebaseAuth",
        state: "complete",
        evidenceCode: "auth_absence_verified",
        checkedAt: new Date(input.nowSecV1 * 1000),
      },
    };
  }
  ad04FailV1("AD04_INVALID_REQUEST");
}

function successResultV1(
  outcomeV1: DeletionEffectOutcomeV1,
  evidenceCodeV1: string,
  providerCalledV1: boolean,
): ExecutionResultV1 {
  return {
    terminalV1: true,
    attentionV1: false,
    outcomeV1,
    evidenceCodeV1,
    adapterResultV1: null,
    providerCheckpointV1: null,
    authAbsentV1: null,
    providerCalledV1,
  };
}

async function executeAppleTaskV1(input: {
  task: CandidateDeletionTaskV1;
  providerBinding: CandidateDeletionProviderBindingV1;
  adapter: CandidateAppleCredentialAdapterV1 | null;
  hooks?: CandidateDeletionWorkerHooksV1;
  nowSecV1: number;
}): Promise<ExecutionResultV1> {
  const binding = input.providerBinding;
  if (binding.providerRelationshipV1 === "nonApple") {
    return {
      ...successResultV1("notApplicable", "apple_not_applicable", false),
      providerCheckpointV1: {
        schemaVersion: 1,
        provider: "appleCredential",
        state: "notApplicable",
        evidenceCode: "apple_not_applicable",
        checkedAt: new Date(input.nowSecV1 * 1000),
      },
    };
  }
  if (binding.providerRelationshipV1 === "unknown" ||
      binding.materialStateV1 === "unknown") {
    return attentionResultV1("apple_relationship_unknown", null, {
      schemaVersion: 1,
      provider: "appleCredential",
      state: "unknown",
      evidenceCode: "apple_relationship_unknown",
      checkedAt: new Date(input.nowSecV1 * 1000),
    });
  }
  if (binding.materialStateV1 === "missing") {
    return {
      ...successResultV1(
        "manualActionGuidance",
        "apple_material_missing_manual_guidance",
        false,
      ),
      providerCheckpointV1: {
        schemaVersion: 1,
        provider: "appleCredential",
        state: "manualActionGuidance",
        evidenceCode: "apple_material_missing_manual_guidance",
        checkedAt: new Date(input.nowSecV1 * 1000),
      },
    };
  }
  if (binding.providerRevocationRefV1 === null ||
      binding.appleProviderSubjectHashV1 === null || input.adapter === null) {
    return attentionResultV1("apple_adapter_unavailable", null, {
      schemaVersion: 1,
      provider: "appleCredential",
      state: "retryRequired",
      evidenceCode: "apple_adapter_unavailable",
      checkedAt: new Date(input.nowSecV1 * 1000),
    });
  }
  const effectInput = {
    scope: ad04ScopeV1(input.task),
    generationHash: input.task.generationHash,
    acceptedLifecycleEpochV2: input.task.acceptedLifecycleEpochV2,
    providerSubjectHashV1: binding.appleProviderSubjectHashV1,
    providerRevocationRefV1: binding.providerRevocationRefV1,
    effectIdV1: input.task.effectIdV1,
  };
  let state = parseAppleRevocationStateV1(await externalCallV1({
    label: "appleCredential.inspectRevocationV1",
    effectIdV1: input.task.effectIdV1,
    hooks: input.hooks,
    operation: () => input.adapter!.inspectRevocationV1(effectInput),
  }));
  let providerCalledV1 = false;
  if (state.revocationStateV1 === "pending") {
    if (state.materialStateV1 !== "available") {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    providerCalledV1 = true;
    await externalCallV1({
      label: "appleCredential.revokeCredentialV1",
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => input.adapter!.revokeCredentialV1(effectInput),
    });
    state = parseAppleRevocationStateV1(await externalCallV1({
      label: "appleCredential.inspectRevocationV1",
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => input.adapter!.inspectRevocationV1(effectInput),
    }));
  }
  if (state.revocationStateV1 !== "revoked") {
    ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
  }
  if (state.materialStateV1 !== "destroyed") {
    providerCalledV1 = true;
    await externalCallV1({
      label: "appleCredential.destroyRevocationMaterialV1",
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => input.adapter!.destroyRevocationMaterialV1(effectInput),
    });
    state = parseAppleRevocationStateV1(await externalCallV1({
      label: "appleCredential.inspectRevocationV1",
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => input.adapter!.inspectRevocationV1(effectInput),
    }));
  }
  if (state.revocationStateV1 !== "revoked" || state.materialStateV1 !== "destroyed") {
    ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
  }
  return {
    ...successResultV1(providerCalledV1 ? "applied" : "alreadySatisfied",
      "apple_revocation_verified", providerCalledV1),
    providerCheckpointV1: {
      schemaVersion: 1,
      provider: "appleCredential",
      state: "complete",
      evidenceCode: "apple_revocation_verified",
      checkedAt: new Date(input.nowSecV1 * 1000),
    },
  };
}

function attentionResultV1(
  evidenceCodeV1: string,
  adapterResultV1: AdapterResultContract | null,
  providerCheckpointV1: ProviderCheckpointContract | null = null,
): ExecutionResultV1 {
  return {
    terminalV1: false,
    attentionV1: true,
    outcomeV1: "alreadySatisfied",
    evidenceCodeV1,
    adapterResultV1,
    providerCheckpointV1,
    authAbsentV1: null,
    providerCalledV1: false,
  };
}

function cleanupResultForTaskV1(input: {
  raw: unknown;
  task: CandidateDeletionTaskV1;
  binding: CandidateDeletionJobBindingV1;
}): AdapterResultContract {
  const result = parseCandidateAdapterResultV1(input.raw);
  if (result.adapterId !== input.task.adapterIdV1 ||
      result.policyVersion !== input.binding.policyVersion ||
      result.policyDecisionId !== `retention.${input.task.adapterIdV1}`) {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
  return result;
}

function adapterResultIsTerminalV1(result: AdapterResultContract): boolean {
  if (result.policyDecisionState !== "approved" || result.evidenceCode === null) return false;
  if (result.state === "notApplicable") {
    return result.applicability === "notApplicable" &&
      result.disposition === "notApplicable" && result.holdState === "none" &&
      result.holdBoundaryAt === null;
  }
  if (result.state !== "complete" || result.applicability !== "applicable" ||
      result.disposition === "unresolved" || result.disposition === "notApplicable") {
    return false;
  }
  if (result.disposition === "restrictedRetention") {
    return result.holdState === "activeApproved" && result.holdBoundaryAt instanceof Date;
  }
  return result.holdState === "none" && result.holdBoundaryAt === null;
}

async function executeCleanupTaskV1(input: {
  task: CandidateDeletionTaskV1;
  binding: CandidateDeletionJobBindingV1;
  adapters: ReadonlyMap<string, CandidateCleanupAdapterV1>;
  hooks?: CandidateDeletionWorkerHooksV1;
}): Promise<ExecutionResultV1> {
  const adapterId = input.task.adapterIdV1;
  if (adapterId === null) ad04FailV1("AD04_INVALID_REQUEST");
  const adapter = input.adapters.get(adapterId);
  if (adapter === undefined || adapter.adapterIdV1 !== adapterId ||
      adapter.adapterVersionV1 !== input.task.adapterVersionV1) {
    const unsupported = parseCandidateAdapterResultV1({
      schemaVersion: 1,
      adapterId,
      applicability: "unknown",
      state: "unsupported",
      disposition: "unresolved",
      policyDecisionState: "pendingOperationalProof",
      policyDecisionId: `retention.${adapterId}`,
      policyVersion: input.binding.policyVersion,
      holdState: "unknown",
      evidenceCode: "required_adapter_unsupported",
      evidenceRef: `effect_${input.task.effectIdV1.slice(3, 35)}`,
      holdBoundaryAt: null,
    });
    return attentionResultV1("required_adapter_unsupported", unsupported);
  }
  const effectInput = {
    scope: ad04ScopeV1(input.task),
    generationHash: input.task.generationHash,
    acceptedLifecycleEpochV2: input.task.acceptedLifecycleEpochV2,
    internalJobId: input.task.internalJobId,
    effectIdV1: input.task.effectIdV1,
    policyVersion: input.binding.policyVersion,
  };
  let raw = await externalCallV1({
    label: `${adapterId}.inspectEffectV1`,
    effectIdV1: input.task.effectIdV1,
    hooks: input.hooks,
    operation: () => adapter.inspectEffectV1(effectInput),
  });
  let providerCalledV1 = false;
  if (raw === null) {
    providerCalledV1 = true;
    await externalCallV1({
      label: `${adapterId}.applyEffectV1`,
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => adapter.applyEffectV1(effectInput),
    });
    raw = await externalCallV1({
      label: `${adapterId}.inspectEffectV1`,
      effectIdV1: input.task.effectIdV1,
      hooks: input.hooks,
      operation: () => adapter.inspectEffectV1(effectInput),
    });
    if (raw === null) ad04FailV1("AD04_TEMPORARILY_UNAVAILABLE");
  }
  const result = cleanupResultForTaskV1({raw, task: input.task, binding: input.binding});
  if (!adapterResultIsTerminalV1(result)) {
    return {
      ...attentionResultV1("required_adapter_incomplete", result),
      providerCalledV1,
    };
  }
  return {
    ...successResultV1(providerCalledV1 ? "applied" : "alreadySatisfied",
      "cleanup_adapter_verified", providerCalledV1),
    adapterResultV1: result,
  };
}

async function claimTaskV1(input: {
  repository: CandidateDeletionRepositoryV1;
  locator: CandidateDeletionTaskLocatorV1;
  workerIdV1: string;
  nowSecV1: number;
}): Promise<ClaimedTaskV1 | CandidateTaskRunResultV1> {
  return input.repository.runTransaction(async (transaction) => {
    const taskPath = deletionTaskPathV1(input.locator.internalJobId, input.locator.effectIdV1);
    const [taskRaw, jobRaw, bindingRaw, providerBindingRaw, receiptRaw] = await Promise.all([
      transaction.read(taskPath),
      transaction.read(deletionJobPathV1(input.locator.internalJobId)),
      transaction.read(deletionJobBindingPathV1(input.locator.internalJobId)),
      transaction.read(deletionProviderBindingPathV1(input.locator.internalJobId)),
      transaction.read(deletionEffectReceiptPathV1(
        input.locator.internalJobId,
        input.locator.effectIdV1,
      )),
    ]);
    if (taskRaw === null || jobRaw === null || bindingRaw === null ||
        providerBindingRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
    let task = parseCandidateDeletionTaskV1(taskRaw);
    const job = parseCandidateDeletionJobV1(jobRaw);
    const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
    const providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    if (!taskMatchesLocatorV1(task, input.locator) ||
        job.internalJobId !== task.internalJobId || job.generationHash !== task.generationHash ||
        job.policyVersion !== binding.policyVersion ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
        binding.internalJobId !== task.internalJobId ||
        binding.generationHash !== task.generationHash ||
        binding.acceptedLifecycleEpochV2 !== task.acceptedLifecycleEpochV2 ||
        task.createdAtSecV1 !== binding.acceptedAtSecV1 ||
        providerBinding.internalJobId !== task.internalJobId ||
        providerBinding.generationHash !== task.generationHash ||
        providerBinding.acceptedLifecycleEpochV2 !== task.acceptedLifecycleEpochV2 ||
        providerBinding.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
        !sameAd04ScopeV1(binding, task) || !sameAd04ScopeV1(providerBinding, task)) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    if (receiptRaw !== null) {
      const receipt = parseCandidateEffectReceiptV1(receiptRaw);
      if (!receiptMatchesTaskV1(receipt, task)) ad04FailV1("AD04_EFFECT_CONFLICT");
      if (task.stateV1 !== "complete") {
        task = parseCandidateDeletionTaskV1({
          ...task,
          stateV1: "complete",
          leaseOwnerV1: null,
          leaseExpiresAtSecV1: null,
          safeErrorCodeV1: null,
          completedAtSecV1: receipt.recordedAtSecV1,
        });
        transaction.write(taskPath, asWriteRecord(task));
      }
      return {
        stateV1: "alreadyCompleted",
        effectIdV1: task.effectIdV1,
        providerCalledV1: false,
      };
    }
    if (task.stateV1 === "complete") ad04FailV1("AD04_EFFECT_CONFLICT");
    if (task.stateV1 === "needsAttention") {
      return {
        stateV1: "needsAttention",
        effectIdV1: task.effectIdV1,
        providerCalledV1: false,
      };
    }
    if (task.stateV1 === "leased" &&
        task.leaseExpiresAtSecV1 !== null && task.leaseExpiresAtSecV1 > input.nowSecV1) {
      return {stateV1: "busy", effectIdV1: task.effectIdV1, providerCalledV1: false};
    }
    if (task.nextAttemptAtSecV1 > input.nowSecV1) {
      return {stateV1: "notDue", effectIdV1: task.effectIdV1, providerCalledV1: false};
    }
    const dependencies = taskDependenciesV1(task);
    const dependencyRows = await Promise.all(dependencies.flatMap((effectIdV1) => [
      transaction.read(deletionTaskPathV1(task.internalJobId, effectIdV1)),
      transaction.read(deletionEffectReceiptPathV1(task.internalJobId, effectIdV1)),
    ]));
    for (let index = 0; index < dependencies.length; index += 1) {
      const dependencyTaskRaw = dependencyRows[index * 2];
      const dependencyReceiptRaw = dependencyRows[(index * 2) + 1];
      if (dependencyTaskRaw === null) {
        return {
          stateV1: "dependencyPending",
          effectIdV1: task.effectIdV1,
          providerCalledV1: false,
        };
      }
      let dependencyTask: CandidateDeletionTaskV1;
      try {
        dependencyTask = parseCandidateDeletionTaskV1(dependencyTaskRaw);
      } catch {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (!taskMatchesLocatorV1(dependencyTask, {
        ...input.locator,
        effectIdV1: dependencies[index],
      }) || dependencyTask.createdAtSecV1 !== binding.acceptedAtSecV1) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (dependencyTask.stateV1 !== "complete") {
        if (dependencyReceiptRaw !== null) ad04FailV1("AD04_EFFECT_CONFLICT");
        return {
          stateV1: "dependencyPending",
          effectIdV1: task.effectIdV1,
          providerCalledV1: false,
        };
      }
      if (dependencyReceiptRaw === null) ad04FailV1("AD04_EFFECT_CONFLICT");
      let dependencyReceipt: CandidateDeletionEffectReceiptV1;
      try {
        dependencyReceipt = parseCandidateEffectReceiptV1(dependencyReceiptRaw);
      } catch {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (!receiptMatchesTaskV1(dependencyReceipt, dependencyTask)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (dependencyTask.completedAtSecV1 !== dependencyReceipt.recordedAtSecV1) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    }
    if (task.kindV1.startsWith("auth") && !job.authorityFenceDurable) {
      ad04FailV1("AD04_TASK_NOT_READY");
    }
    if (task.kindV1 === "authDeleteSingleUser" &&
        !job.minimumCleanupReferencesCaptured) {
      ad04FailV1("AD04_TASK_NOT_READY");
    }
    if (task.attemptsV1 >= ACCOUNT_DELETION_AD04_ATTENTION_ATTEMPT_V1) {
      const attentionTask = parseCandidateDeletionTaskV1({
        ...task,
        stateV1: "needsAttention",
        leaseOwnerV1: null,
        leaseExpiresAtSecV1: null,
        safeErrorCodeV1: "retry_budget_exhausted",
      });
      transaction.write(taskPath, asWriteRecord(attentionTask));
      transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
        ...job,
        state: "needsAttention",
        resumeStage: resumeStageForTaskV1(task),
        authDeletionCheckpointState: task.kindV1.startsWith("auth") && !job.authAbsent
          ? "needsAttention" : job.authDeletionCheckpointState,
        safeErrorCode: "AD_REVIEW_REQUIRED",
      }));
      transaction.write(deletionAlertPathV1(job.internalJobId, task.effectIdV1), {
        schemaVersion: 1,
        internalJobId: job.internalJobId,
        effectIdV1: task.effectIdV1,
        safeErrorCodeV1: "retry_budget_exhausted",
        recordedAtSecV1: input.nowSecV1,
      });
      return {
        stateV1: "needsAttention",
        effectIdV1: task.effectIdV1,
        providerCalledV1: false,
      };
    }
    const claimed = parseCandidateDeletionTaskV1({
      ...task,
      stateV1: "leased",
      attemptsV1: task.attemptsV1 + 1,
      leaseGenerationV1: task.leaseGenerationV1 + 1,
      leaseOwnerV1: input.workerIdV1,
      leaseExpiresAtSecV1: input.nowSecV1 + ACCOUNT_DELETION_AD04_LEASE_SEC_V1,
      safeErrorCodeV1: null,
      completedAtSecV1: null,
    });
    transaction.write(taskPath, asWriteRecord(claimed));
    transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
      ...job,
      attempt: job.attempt + 1,
      leaseGeneration: job.leaseGeneration + 1,
    }));
    return {task: claimed, job, binding, providerBinding};
  });
}

async function persistTaskResultV1(input: {
  repository: CandidateDeletionRepositoryV1;
  claim: ClaimedTaskV1;
  workerIdV1: string;
  nowSecV1: number;
  result: ExecutionResultV1;
  hooks?: CandidateDeletionWorkerHooksV1;
}): Promise<CandidateTaskRunResultV1> {
  await input.hooks?.beforeCheckpointPersistV1?.(input.claim.task.effectIdV1);
  return input.repository.runTransaction(async (transaction) => {
    const taskPath = deletionTaskPathV1(
      input.claim.task.internalJobId,
      input.claim.task.effectIdV1,
    );
    const receiptPath = deletionEffectReceiptPathV1(
      input.claim.task.internalJobId,
      input.claim.task.effectIdV1,
    );
    const [taskRaw, jobRaw, receiptRaw, adapterRaw, providerRaw] = await Promise.all([
      transaction.read(taskPath),
      transaction.read(deletionJobPathV1(input.claim.task.internalJobId)),
      transaction.read(receiptPath),
      input.claim.task.adapterIdV1 === null ? Promise.resolve(null) : transaction.read(
        deletionAdapterResultPathV1(
          input.claim.task.internalJobId,
          input.claim.task.adapterIdV1,
        ),
      ),
      input.result.providerCheckpointV1 === null ? Promise.resolve(null) : transaction.read(
        deletionProviderCheckpointPathV1(
          input.claim.task.internalJobId,
          input.result.providerCheckpointV1.provider,
        ),
      ),
    ]);
    if (taskRaw === null || jobRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
    const task = parseCandidateDeletionTaskV1(taskRaw);
    const job = parseCandidateDeletionJobV1(jobRaw);
    if (!taskMatchesLocatorV1(task, {
      schemaVersion: 1,
      ...ad04ScopeV1(input.claim.task),
      generationHash: input.claim.task.generationHash,
      acceptedLifecycleEpochV2: input.claim.task.acceptedLifecycleEpochV2,
      internalJobId: input.claim.task.internalJobId,
      effectIdV1: input.claim.task.effectIdV1,
    }) || task.createdAtSecV1 !== input.claim.binding.acceptedAtSecV1 ||
        job.internalJobId !== input.claim.job.internalJobId ||
        job.generationHash !== input.claim.job.generationHash ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    if (receiptRaw !== null) {
      const receipt = parseCandidateEffectReceiptV1(receiptRaw);
      if (!receiptMatchesTaskV1(receipt, input.claim.task)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      return {
        stateV1: "alreadyCompleted",
        effectIdV1: task.effectIdV1,
        providerCalledV1: input.result.providerCalledV1,
      };
    }
    if (task.stateV1 !== "leased" || task.leaseOwnerV1 !== input.workerIdV1 ||
        task.leaseGenerationV1 !== input.claim.task.leaseGenerationV1 ||
        task.effectFingerprintV1 !== input.claim.task.effectFingerprintV1) {
      return {
        stateV1: "staleLease",
        effectIdV1: task.effectIdV1,
        providerCalledV1: input.result.providerCalledV1,
      };
    }
    if (input.result.adapterResultV1 !== null && adapterRaw !== null) {
      const existing = cleanupResultForTaskV1({
        raw: adapterRaw,
        task: input.claim.task,
        binding: input.claim.binding,
      });
      if (JSON.stringify(existing) !== JSON.stringify(input.result.adapterResultV1) &&
          adapterResultIsTerminalV1(existing)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    }
    let writeProviderCheckpoint = input.result.providerCheckpointV1 !== null;
    if (input.result.providerCheckpointV1 !== null && providerRaw !== null) {
      const existing = parseCandidateProviderCheckpointV1(providerRaw);
      if (existing.provider !== input.result.providerCheckpointV1.provider) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (isProviderCheckpointTerminal(existing)) writeProviderCheckpoint = false;
    }
    if (input.result.attentionV1 || !input.result.terminalV1) {
      const attentionTask = parseCandidateDeletionTaskV1({
        ...task,
        stateV1: "needsAttention",
        leaseOwnerV1: null,
        leaseExpiresAtSecV1: null,
        safeErrorCodeV1: input.result.evidenceCodeV1,
      });
      transaction.write(taskPath, asWriteRecord(attentionTask));
      if (input.result.adapterResultV1 !== null) {
        transaction.write(deletionAdapterResultPathV1(
          task.internalJobId,
          input.result.adapterResultV1.adapterId,
        ), asWriteRecord(input.result.adapterResultV1));
      }
      if (input.result.providerCheckpointV1 !== null && writeProviderCheckpoint) {
        transaction.write(deletionProviderCheckpointPathV1(
          task.internalJobId,
          input.result.providerCheckpointV1.provider,
        ), asWriteRecord(input.result.providerCheckpointV1));
      }
      transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
        ...job,
        state: "needsAttention",
        resumeStage: resumeStageForTaskV1(task),
        authDeletionCheckpointState: task.kindV1.startsWith("auth") && !job.authAbsent
          ? "needsAttention" : job.authDeletionCheckpointState,
        safeErrorCode: "AD_REVIEW_REQUIRED",
      }));
      transaction.write(deletionAlertPathV1(job.internalJobId, task.effectIdV1), {
        schemaVersion: 1,
        internalJobId: job.internalJobId,
        effectIdV1: task.effectIdV1,
        safeErrorCodeV1: input.result.evidenceCodeV1,
        recordedAtSecV1: input.nowSecV1,
      });
      return {
        stateV1: "needsAttention",
        effectIdV1: task.effectIdV1,
        providerCalledV1: input.result.providerCalledV1,
      };
    }
    const receipt: CandidateDeletionEffectReceiptV1 = parseCandidateEffectReceiptV1({
      schemaVersion: 1,
      internalJobId: task.internalJobId,
      ...ad04ScopeV1(task),
      generationHash: task.generationHash,
      acceptedLifecycleEpochV2: task.acceptedLifecycleEpochV2,
      effectIdV1: task.effectIdV1,
      effectFingerprintV1: task.effectFingerprintV1,
      kindV1: task.kindV1,
      adapterIdV1: task.adapterIdV1,
      outcomeV1: input.result.outcomeV1,
      evidenceCodeV1: input.result.evidenceCodeV1,
      recordedAtSecV1: input.nowSecV1,
    });
    const completeTask = parseCandidateDeletionTaskV1({
      ...task,
      stateV1: "complete",
      leaseOwnerV1: null,
      leaseExpiresAtSecV1: null,
      safeErrorCodeV1: null,
      completedAtSecV1: input.nowSecV1,
    });
    transaction.write(receiptPath, asWriteRecord(receipt));
    transaction.write(taskPath, asWriteRecord(completeTask));
    if (input.result.adapterResultV1 !== null) {
      transaction.write(deletionAdapterResultPathV1(
        task.internalJobId,
        input.result.adapterResultV1.adapterId,
      ), asWriteRecord(input.result.adapterResultV1));
    }
    if (input.result.providerCheckpointV1 !== null && writeProviderCheckpoint) {
      transaction.write(deletionProviderCheckpointPathV1(
        task.internalJobId,
        input.result.providerCheckpointV1.provider,
      ), asWriteRecord(input.result.providerCheckpointV1));
    }
    if (input.result.authAbsentV1 === true) {
      transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
        ...job,
        authDeletionCheckpointState: "complete",
        authAbsent: true,
      }));
    }
    return {
      stateV1: "completed",
      effectIdV1: task.effectIdV1,
      providerCalledV1: input.result.providerCalledV1,
    };
  });
}

async function persistTransientFailureV1(input: {
  repository: CandidateDeletionRepositoryV1;
  claim: ClaimedTaskV1;
  workerIdV1: string;
  nowSecV1: number;
}): Promise<CandidateTaskRunResultV1> {
  return input.repository.runTransaction(async (transaction) => {
    const taskPath = deletionTaskPathV1(
      input.claim.task.internalJobId,
      input.claim.task.effectIdV1,
    );
    const [taskRaw, jobRaw] = await Promise.all([
      transaction.read(taskPath),
      transaction.read(deletionJobPathV1(input.claim.task.internalJobId)),
    ]);
    if (taskRaw === null || jobRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
    const task = parseCandidateDeletionTaskV1(taskRaw);
    const job = parseCandidateDeletionJobV1(jobRaw);
    if (!taskMatchesLocatorV1(task, {
      schemaVersion: 1,
      ...ad04ScopeV1(input.claim.task),
      generationHash: input.claim.task.generationHash,
      acceptedLifecycleEpochV2: input.claim.task.acceptedLifecycleEpochV2,
      internalJobId: input.claim.task.internalJobId,
      effectIdV1: input.claim.task.effectIdV1,
    }) || task.createdAtSecV1 !== input.claim.binding.acceptedAtSecV1 ||
        job.internalJobId !== input.claim.job.internalJobId ||
        job.generationHash !== input.claim.job.generationHash ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    if (task.stateV1 !== "leased" || task.leaseOwnerV1 !== input.workerIdV1 ||
        task.leaseGenerationV1 !== input.claim.task.leaseGenerationV1) {
      return {stateV1: "staleLease", effectIdV1: task.effectIdV1, providerCalledV1: true};
    }
    const attention = task.attemptsV1 >= ACCOUNT_DELETION_AD04_ATTENTION_ATTEMPT_V1;
    const nextTask = parseCandidateDeletionTaskV1({
      ...task,
      stateV1: attention ? "needsAttention" : "retryWait",
      leaseOwnerV1: null,
      leaseExpiresAtSecV1: null,
      nextAttemptAtSecV1: attention
        ? task.nextAttemptAtSecV1
        : input.nowSecV1 + retryDelaySecV1(task.attemptsV1),
      safeErrorCodeV1: attention ? "retry_budget_exhausted" : "transient_effect_failure",
    });
    transaction.write(taskPath, asWriteRecord(nextTask));
    transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
      ...job,
      state: attention ? "needsAttention" : "retryWait",
      resumeStage: resumeStageForTaskV1(task),
      authDeletionCheckpointState: task.kindV1.startsWith("auth") && !job.authAbsent
        ? (attention ? "needsAttention" : "retryRequired")
        : job.authDeletionCheckpointState,
      safeErrorCode: attention ? "AD_REVIEW_REQUIRED" : "AD_TEMPORARILY_UNAVAILABLE",
    }));
    if (attention) {
      transaction.write(deletionAlertPathV1(job.internalJobId, task.effectIdV1), {
        schemaVersion: 1,
        internalJobId: job.internalJobId,
        effectIdV1: task.effectIdV1,
        safeErrorCodeV1: "retry_budget_exhausted",
        recordedAtSecV1: input.nowSecV1,
      });
    }
    return {
      stateV1: attention ? "needsAttention" : "retryScheduled",
      effectIdV1: task.effectIdV1,
      providerCalledV1: true,
    };
  });
}

export async function runCandidateDeletionTaskV1(input: {
  repository: CandidateDeletionRepositoryV1;
  locator: unknown;
  workerIdV1: string;
  configuredProjectId: string;
  nowSecV1: number;
  firebaseAuthAdapterV1: CandidateFirebaseAuthAdapterV1;
  appleCredentialAdapterV1: CandidateAppleCredentialAdapterV1 | null;
  cleanupAdaptersV1: readonly CandidateCleanupAdapterV1[];
  hooksV1?: CandidateDeletionWorkerHooksV1;
}): Promise<CandidateTaskRunResultV1> {
  const locator = parseLocatorV1(input.locator);
  const workerIdV1 = ad04OpaqueIdV1(input.workerIdV1);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  if (locator.authProjectIdV2 !== ad04OpaqueIdV1(input.configuredProjectId)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const adapters = new Map<string, CandidateCleanupAdapterV1>();
  for (const adapter of input.cleanupAdaptersV1) {
    if (!accountDeletionAdapterIds.includes(
      adapter.adapterIdV1 as typeof accountDeletionAdapterIds[number],
    ) || adapters.has(adapter.adapterIdV1)) ad04FailV1("AD04_INVALID_REQUEST");
    adapters.set(adapter.adapterIdV1, adapter);
  }
  const claimed = await claimTaskV1({
    repository: input.repository,
    locator,
    workerIdV1,
    nowSecV1,
  });
  if (!("task" in claimed)) {
    if (claimed.stateV1 === "alreadyCompleted") {
      const taskRaw = await input.repository.read(deletionTaskPathV1(
        locator.internalJobId,
        locator.effectIdV1,
      ));
      if (taskRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
      const completedTask = parseCandidateDeletionTaskV1(taskRaw);
      if (!taskMatchesLocatorV1(completedTask, locator)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (completedTask.kindV1 === "reconcileCompletion") {
        await reconcileCandidateDeletionJobV1({
          repository: input.repository,
          locator,
          nowSecV1,
        });
      }
    }
    return claimed;
  }
  let result: ExecutionResultV1;
  try {
    if (["authDisable", "authRevokeRefreshTokens", "authDeleteSingleUser",
      "authVerifyAbsence"].includes(claimed.task.kindV1)) {
      result = await executeAuthTaskV1({
        task: claimed.task,
        adapter: input.firebaseAuthAdapterV1,
        hooks: input.hooksV1,
        nowSecV1,
      });
    } else if (claimed.task.kindV1 === "appleCredentialDisposition") {
      result = await executeAppleTaskV1({
        task: claimed.task,
        providerBinding: claimed.providerBinding,
        adapter: input.appleCredentialAdapterV1,
        hooks: input.hooksV1,
        nowSecV1,
      });
    } else if (claimed.task.kindV1 === "cleanupAdapter") {
      result = await executeCleanupTaskV1({
        task: claimed.task,
        binding: claimed.binding,
        adapters,
        hooks: input.hooksV1,
      });
    } else {
      result = successResultV1("verifiedComplete", "completion_reconciled", false);
    }
  } catch (error) {
    if (error !== null && typeof error === "object" && "codeV1" in error &&
        error.codeV1 !== "AD04_TEMPORARILY_UNAVAILABLE") {
      throw error;
    }
    return persistTransientFailureV1({
      repository: input.repository,
      claim: claimed,
      workerIdV1,
      nowSecV1,
    });
  }
  const persisted = await persistTaskResultV1({
    repository: input.repository,
    claim: claimed,
    workerIdV1,
    nowSecV1,
    result,
    hooks: input.hooksV1,
  });
  if (claimed.task.kindV1 === "reconcileCompletion" &&
      (persisted.stateV1 === "completed" || persisted.stateV1 === "alreadyCompleted")) {
    await reconcileCandidateDeletionJobV1({
      repository: input.repository,
      locator,
      nowSecV1,
    });
  }
  return persisted;
}

function resultReadyForSummaryV1(result: AdapterResultContract | undefined): boolean {
  return result !== undefined && adapterResultIsTerminalV1(result);
}

export async function reconcileCandidateDeletionJobV1(input: {
  repository: CandidateDeletionRepositoryV1;
  locator: unknown;
  nowSecV1: number;
}): Promise<ReturnType<typeof parseCandidateDeletionJobV1>> {
  const locator = parseLocatorV1(input.locator);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  return input.repository.runTransaction(async (transaction) => {
    const expectedTasks = initialDeletionTasksV1({
      scope: locator,
      internalJobId: locator.internalJobId,
      generationHash: locator.generationHash,
      acceptedLifecycleEpochV2: locator.acceptedLifecycleEpochV2,
      nowSecV1: 0,
    });
    const expectedReconcileTask = expectedTasks.find((task) =>
      task.kindV1 === "reconcileCompletion");
    if (expectedReconcileTask === undefined ||
        locator.effectIdV1 !== expectedReconcileTask.effectIdV1) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    const [jobRaw, bindingRaw, providerBindingRaw, lifecycleRaw, firebaseRaw, appleRaw,
      ...remainingRows] = await Promise.all([
      transaction.read(deletionJobPathV1(locator.internalJobId)),
      transaction.read(deletionJobBindingPathV1(locator.internalJobId)),
      transaction.read(deletionProviderBindingPathV1(locator.internalJobId)),
      transaction.read(candidateAccountLifecycleAuthorityPathV1(locator)),
      transaction.read(deletionProviderCheckpointPathV1(
        locator.internalJobId,
        "firebaseAuth",
      )),
      transaction.read(deletionProviderCheckpointPathV1(
        locator.internalJobId,
        "appleCredential",
      )),
      ...expectedTasks.map((task) => transaction.read(
        deletionTaskPathV1(locator.internalJobId, task.effectIdV1),
      )),
      ...expectedTasks.map((task) => transaction.read(
        deletionEffectReceiptPathV1(locator.internalJobId, task.effectIdV1),
      )),
      ...accountDeletionAdapterIds.map((adapterId) => transaction.read(
        deletionAdapterResultPathV1(locator.internalJobId, adapterId),
      )),
    ]);
    if (jobRaw === null || bindingRaw === null || providerBindingRaw === null ||
        lifecycleRaw === null ||
        firebaseRaw === null || appleRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
    const job = parseCandidateDeletionJobV1(jobRaw);
    const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
    const providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    if (job.internalJobId !== locator.internalJobId ||
        job.generationHash !== locator.generationHash ||
        job.policyVersion !== binding.policyVersion ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
        binding.internalJobId !== locator.internalJobId ||
        binding.generationHash !== locator.generationHash ||
        binding.acceptedLifecycleEpochV2 !== locator.acceptedLifecycleEpochV2 ||
        binding.acceptedAtSecV1 > nowSecV1 ||
        providerBinding.internalJobId !== locator.internalJobId ||
        providerBinding.generationHash !== locator.generationHash ||
        providerBinding.acceptedLifecycleEpochV2 !== locator.acceptedLifecycleEpochV2 ||
        providerBinding.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
        !sameAd04ScopeV1(binding, locator) ||
        !sameAd04ScopeV1(providerBinding, locator)) ad04FailV1("AD04_EFFECT_CONFLICT");
    const taskRows = remainingRows.slice(0, expectedTasks.length);
    const receiptRows = remainingRows.slice(
      expectedTasks.length,
      expectedTasks.length * 2,
    );
    const adapterRows = remainingRows.slice(expectedTasks.length * 2);
    const tasks = taskRows.map((row, index) => {
      if (row === null) ad04FailV1("AD04_TASK_NOT_READY");
      const task = parseCandidateDeletionTaskV1(row);
      const expected = expectedTasks[index];
      if (!sameAd04ScopeV1(task, expected) ||
          task.internalJobId !== expected.internalJobId ||
          task.generationHash !== expected.generationHash ||
          task.acceptedLifecycleEpochV2 !== expected.acceptedLifecycleEpochV2 ||
          task.effectIdV1 !== expected.effectIdV1 ||
          task.effectFingerprintV1 !== expected.effectFingerprintV1 ||
          task.kindV1 !== expected.kindV1 ||
          task.adapterIdV1 !== expected.adapterIdV1 ||
          task.adapterVersionV1 !== expected.adapterVersionV1 ||
          task.createdAtSecV1 !== binding.acceptedAtSecV1 ||
          task.createdAtSecV1 > nowSecV1) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      return task;
    });
    const receipts = receiptRows.map((row, index) => {
      if (row === null) {
        if (tasks[index].stateV1 === "complete") ad04FailV1("AD04_EFFECT_CONFLICT");
        return undefined;
      }
      const receipt = parseCandidateEffectReceiptV1(row);
      if (tasks[index].stateV1 !== "complete" ||
          !receiptMatchesTaskV1(receipt, tasks[index]) ||
          tasks[index].completedAtSecV1 !== receipt.recordedAtSecV1 ||
          receipt.recordedAtSecV1 > nowSecV1) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      return receipt;
    });
    const adapters = adapterRows.map((row, index) => {
      if (row === null) return undefined;
      const result = parseCandidateAdapterResultV1(row);
      const adapterId = accountDeletionAdapterIds[index];
      if (result.adapterId !== adapterId || result.policyVersion !== binding.policyVersion ||
          result.policyDecisionId !== `retention.${adapterId}`) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      return result;
    });
    const firebase = parseCandidateProviderCheckpointV1(firebaseRaw);
    const apple = parseCandidateProviderCheckpointV1(appleRaw);
    if (firebase.provider !== "firebaseAuth" || apple.provider !== "appleCredential" ||
        firebase.checkedAt.getTime() > nowSecV1 * 1000 ||
        apple.checkedAt.getTime() > nowSecV1 * 1000) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    const authAbsent = job.authAbsent && firebase.state === "complete";
    const allAdapterResults = adapters.every(resultReadyForSummaryV1) &&
      adapters.length === accountDeletionAdapterIds.length;
    const publicResult = adapters[accountDeletionAdapterIds.indexOf(
      "public_projections_exports",
    )];
    const restoreResult = adapters[accountDeletionAdapterIds.indexOf("backups_restores")];
    const providerDispositionRecorded = isProviderCheckpointTerminal(firebase) &&
      isProviderCheckpointTerminal(apple);
    const checkpoints = {
      dataDispositionVerified: allAdapterResults,
      publicPrivacyVerified: resultReadyForSummaryV1(publicResult),
      custodyRecorded: !binding.custodyRequiresAttentionV1,
      providerDispositionRecorded,
      restoreSuppressionDurable: resultReadyForSummaryV1(restoreResult),
    };
    const allTasksAndReceiptsComplete = tasks.every((task) => task.stateV1 === "complete") &&
      receipts.every((receipt) => receipt !== undefined);
    const completion = allTasksAndReceiptsComplete && isDeletionComplete({
      schemaVersion: 1,
      authAbsent,
      checkpoints,
      requiredAdapterIds: accountDeletionAdapterIds,
      adapterResults: adapters.filter((value): value is AdapterResultContract =>
        value !== undefined),
      providerCheckpoints: [firebase, apple],
      unknownRequiredState: adapters.some((value) => value === undefined ||
        value.applicability === "unknown" || value.state === "unsupported" ||
        value.disposition === "unresolved"),
    });
    const attentionTask = tasks.find((task) => task.stateV1 === "needsAttention");
    const retryTask = tasks.find((task) => task.stateV1 === "retryWait");
    const authTasks = tasks.filter((task) => task.kindV1.startsWith("auth"));
    const cleanupTasks = tasks.filter((task) => task.kindV1 === "cleanupAdapter");
    const authFenceTasksComplete = authTasks.slice(0, 2).every((task) =>
      task.stateV1 === "complete");
    const cleanupTasksComplete = cleanupTasks.every((task) => task.stateV1 === "complete");
    let state = job.state;
    let resumeStage = job.resumeStage;
    let safeErrorCode = job.safeErrorCode;
    if (completion) {
      state = "complete";
      resumeStage = null;
      safeErrorCode = null;
    } else if (attentionTask !== undefined ||
        (cleanupTasksComplete && (!allAdapterResults ||
          !providerDispositionRecorded || binding.custodyRequiresAttentionV1))) {
      state = "needsAttention";
      resumeStage = attentionTask === undefined
        ? "verify" : resumeStageForTaskV1(attentionTask);
      safeErrorCode = "AD_REVIEW_REQUIRED";
    } else if (retryTask !== undefined) {
      state = "retryWait";
      resumeStage = resumeStageForTaskV1(retryTask);
      safeErrorCode = "AD_TEMPORARILY_UNAVAILABLE";
    } else if (!authFenceTasksComplete) {
      state = "fencingExternalAccess";
      resumeStage = null;
      safeErrorCode = null;
    } else if (!cleanupTasksComplete) {
      state = "inventory";
      resumeStage = null;
      safeErrorCode = null;
    } else if (!allAdapterResults || !providerDispositionRecorded) {
      state = "disposition";
      resumeStage = null;
      safeErrorCode = null;
    } else {
      state = "verify";
      resumeStage = null;
      safeErrorCode = null;
    }
    const nextJob = parseCandidateDeletionJobV1({
      ...job,
      state,
      resumeStage,
      authDeletionCheckpointState: authAbsent
        ? "complete"
        : authTasks.some((task) => task.stateV1 === "needsAttention")
          ? "needsAttention"
          : authTasks.some((task) => task.stateV1 === "retryWait")
            ? "retryRequired" : "scheduled",
      authAbsent,
      ...checkpoints,
      safeErrorCode,
    });
    if (completion) {
      let lifecycle;
      try {
        lifecycle = parseCandidateAccountLifecycleAuthorityV2ForDeletionV1(lifecycleRaw);
      } catch {
        ad04FailV1("AD04_REVIEW_REQUIRED");
      }
      if (!sameAd04ScopeV1(lifecycle, locator) ||
          lifecycle.accountGenerationV2 !== locator.generationHash ||
          lifecycle.accountLifecycleEpochV2 !== binding.acceptedLifecycleEpochV2 ||
          !["deleting", "deleted"].includes(lifecycle.lifecycleStateV2)) {
        ad04FailV1("AD04_REVIEW_REQUIRED");
      }
      if (lifecycle.lifecycleStateV2 === "deleting") {
        transaction.write(candidateAccountLifecycleAuthorityPathV1(locator), {
          ...lifecycle,
          lifecycleStateV2: "deleted",
        });
      }
    }
    transaction.write(deletionJobPathV1(locator.internalJobId), asWriteRecord(nextJob));
    return nextJob;
  });
}

export interface CandidateResumeAuthorizerV1 {
  authorizeResumeV1(input: {
    locator: CandidateDeletionTaskLocatorV1;
    reasonCodeV1: string;
  }): Promise<boolean>;
}

export async function resumeCandidateDeletionTaskV1(input: {
  repository: CandidateDeletionRepositoryV1;
  authorizer: CandidateResumeAuthorizerV1;
  locator: unknown;
  reasonCodeV1: string;
  nowSecV1: number;
}): Promise<CandidateDeletionTaskV1> {
  const locator = parseLocatorV1(input.locator);
  const reasonCodeV1 = ad04OpaqueIdV1(input.reasonCodeV1);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  if (!await input.authorizer.authorizeResumeV1({locator, reasonCodeV1})) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return input.repository.runTransaction(async (transaction) => {
    const taskPath = deletionTaskPathV1(locator.internalJobId, locator.effectIdV1);
    const [taskRaw, jobRaw, bindingRaw, providerBindingRaw] = await Promise.all([
      transaction.read(taskPath),
      transaction.read(deletionJobPathV1(locator.internalJobId)),
      transaction.read(deletionJobBindingPathV1(locator.internalJobId)),
      transaction.read(deletionProviderBindingPathV1(locator.internalJobId)),
    ]);
    if (taskRaw === null || jobRaw === null || bindingRaw === null ||
        providerBindingRaw === null) ad04FailV1("AD04_TASK_NOT_READY");
    const task = parseCandidateDeletionTaskV1(taskRaw);
    const job = parseCandidateDeletionJobV1(jobRaw);
    const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
    const providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    if (!taskMatchesLocatorV1(task, locator) || task.stateV1 !== "needsAttention" ||
        task.createdAtSecV1 !== binding.acceptedAtSecV1 ||
        job.state !== "needsAttention" || job.internalJobId !== locator.internalJobId ||
        job.generationHash !== locator.generationHash ||
        job.policyVersion !== binding.policyVersion ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
        binding.internalJobId !== locator.internalJobId ||
        binding.generationHash !== locator.generationHash ||
        binding.acceptedLifecycleEpochV2 !== locator.acceptedLifecycleEpochV2 ||
        providerBinding.internalJobId !== locator.internalJobId ||
        providerBinding.generationHash !== locator.generationHash ||
        providerBinding.acceptedLifecycleEpochV2 !== locator.acceptedLifecycleEpochV2 ||
        providerBinding.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
        !sameAd04ScopeV1(binding, locator) ||
        !sameAd04ScopeV1(providerBinding, locator)) {
      ad04FailV1("AD04_LEASE_CONFLICT");
    }
    const resumed = parseCandidateDeletionTaskV1({
      ...task,
      stateV1: "pending",
      attemptsV1: 0,
      leaseGenerationV1: task.leaseGenerationV1 + 1,
      leaseOwnerV1: null,
      leaseExpiresAtSecV1: null,
      nextAttemptAtSecV1: nowSecV1,
      safeErrorCodeV1: null,
      completedAtSecV1: null,
    });
    transaction.write(taskPath, asWriteRecord(resumed));
    transaction.write(deletionJobPathV1(job.internalJobId), asWriteRecord({
      ...job,
      state: "retryWait",
      resumeStage: resumeStageForTaskV1(task),
      authDeletionCheckpointState: task.kindV1.startsWith("auth") && !job.authAbsent
        ? "retryRequired" : job.authDeletionCheckpointState,
      safeErrorCode: "AD_TEMPORARILY_UNAVAILABLE",
    }));
    return resumed;
  });
}

export function candidateTaskLocatorV1(task: CandidateDeletionTaskV1):
CandidateDeletionTaskLocatorV1 {
  const parsed = parseCandidateDeletionTaskV1(task);
  return Object.freeze({
    schemaVersion: 1,
    ...ad04ScopeV1(parsed),
    generationHash: parsed.generationHash,
    acceptedLifecycleEpochV2: parsed.acceptedLifecycleEpochV2,
    internalJobId: parsed.internalJobId,
    effectIdV1: parsed.effectIdV1,
  });
}
