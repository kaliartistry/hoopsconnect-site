import {
  AccountDeletionJobContract,
  accountDeletionVersions,
  accountGenerationHash,
  isProviderCheckpointTerminal,
} from "../domain/account_deletion_contract";
import {
  AccountLifecycleAuthorityV2,
  MembershipAuthorityV2,
  parseMembershipAuthorityV2,
} from "../domain/auth_incarnation_v2";
import {canonicalSha256} from "../domain/official_stats_contract";
import {
  ACCOUNT_DELETION_AD04_MAX_SWEEP_ITEMS_V1,
  CandidateDeletionEffectReceiptV1,
  CandidateDeletionJobBindingV1,
  CandidateDeletionProviderBindingV1,
  CandidateDeletionRepositoryV1,
  CandidateDeletionTaskV1,
  CandidateProviderEventReceiptV1,
  DeletionProviderRelationshipV1,
  ad04CounterV1,
  ad04ExactKeysV1,
  ad04FailV1,
  ad04HashV1,
  ad04OpaqueIdV1,
  ad04RecordV1,
  ad04ScopeV1,
  authNamespaceForScopeV1,
  candidateAccountLifecycleAuthorityPathV1,
  candidateMembershipAuthorityPathV1,
  deletionEffectReceiptPathV1,
  deletionInternalJobIdV1,
  deletionJobBindingPathV1,
  deletionJobPathV1,
  deletionProviderBindingPathV1,
  deletionProviderCheckpointPathV1,
  deletionProviderEventReceiptPathV1,
  deletionTaskPathV1,
  initialDeletionTasksV1,
  parseCandidateDeletionJobBindingV1,
  parseCandidateAccountLifecycleAuthorityV2ForDeletionV1,
  parseCandidateDeletionJobV1,
  parseCandidateDeletionProviderBindingV1,
  parseCandidateDeletionTaskV1,
  parseCandidateEffectReceiptV1,
  parseCandidateProviderEventReceiptV1,
  parseCandidateProviderCheckpointV1,
  sameAd04ScopeV1,
} from "./ad04_records";

export interface CandidateVerifiedAuthDeletionEventV1 {
  schemaVersion: 1;
  eventIdV1: string;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  authCreatedAtIsoV1: string;
  generationHash: string;
  accountLifecycleEpochV2: number;
  providerRelationshipV1: DeletionProviderRelationshipV1;
  appleProviderSubjectHashV1: string | null;
  observedDeletedAtSecV1: number;
}

export interface CandidateAuthDeletionEventVerifierV1 {
  verifyAuthDeletionEventV1(event: unknown): Promise<unknown>;
}

export interface CandidateAuthOrphanScannerV1 {
  listVerifiedAbsentAccountsV1(input: {
    configuredProjectId: string;
    limitV1: number;
  }): Promise<readonly unknown[]>;
}

export interface CandidateVerifiedAppleEventV1 {
  schemaVersion: 1;
  eventIdV1: string;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  internalJobId: string;
  providerSubjectHashV1: string;
  observedAtSecV1: number;
}

export interface CandidateAppleEventVerifierV1 {
  verifyAppleCredentialEventV1(event: unknown): Promise<unknown>;
}

function asWriteRecord(value: object): Readonly<Record<string, unknown>> {
  return value as unknown as Readonly<Record<string, unknown>>;
}

function parseIso(value: unknown): string {
  if (typeof value !== "string" || !Number.isFinite(new Date(value).getTime()) ||
      new Date(value).toISOString() !== value) ad04FailV1("AD04_AUTHORITY_DENIED");
  return value;
}

function parseRelationship(value: unknown): DeletionProviderRelationshipV1 {
  if (value !== "apple" && value !== "nonApple" && value !== "unknown") {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return value;
}

function parseAuthDeletionEventV1(value: unknown): CandidateVerifiedAuthDeletionEventV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "eventIdV1", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "authCreatedAtIsoV1", "generationHash", "accountLifecycleEpochV2",
    "providerRelationshipV1", "appleProviderSubjectHashV1", "observedDeletedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) || data.schemaVersion !== 1) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const scope = ad04ScopeV1({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  const relationship = parseRelationship(data.providerRelationshipV1);
  const subject = data.appleProviderSubjectHashV1 === null
    ? null : ad04HashV1(data.appleProviderSubjectHashV1);
  if ((relationship === "apple") !== (subject !== null)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const authCreatedAtIsoV1 = parseIso(data.authCreatedAtIsoV1);
  const generationHash = ad04HashV1(data.generationHash);
  if (accountGenerationHash({
    authNamespace: authNamespaceForScopeV1(scope),
    accountId: scope.authUidV2,
    authCreatedAt: new Date(authCreatedAtIsoV1),
  }) !== generationHash) ad04FailV1("AD04_AUTHORITY_DENIED");
  return Object.freeze({
    schemaVersion: 1,
    eventIdV1: ad04OpaqueIdV1(data.eventIdV1),
    ...scope,
    authCreatedAtIsoV1,
    generationHash,
    accountLifecycleEpochV2: ad04CounterV1(data.accountLifecycleEpochV2),
    providerRelationshipV1: relationship,
    appleProviderSubjectHashV1: subject,
    observedDeletedAtSecV1: ad04CounterV1(data.observedDeletedAtSecV1),
  });
}

function parseAppleEventV1(value: unknown): CandidateVerifiedAppleEventV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "eventIdV1", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "generationHash", "acceptedLifecycleEpochV2", "internalJobId",
    "providerSubjectHashV1", "observedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) || data.schemaVersion !== 1) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  return Object.freeze({
    schemaVersion: 1,
    eventIdV1: ad04OpaqueIdV1(data.eventIdV1),
    ...ad04ScopeV1({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: data.authUidV2,
    }),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    providerSubjectHashV1: ad04HashV1(data.providerSubjectHashV1),
    observedAtSecV1: ad04CounterV1(data.observedAtSecV1),
  });
}

function parseLifecycleOrNull(value: unknown): AccountLifecycleAuthorityV2 | null {
  if (value === null) return null;
  try {
    return parseCandidateAccountLifecycleAuthorityV2ForDeletionV1(value);
  } catch {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
}

function parseMembershipOrNull(value: unknown): MembershipAuthorityV2 | null {
  if (value === null) return null;
  try {
    return parseMembershipAuthorityV2(value);
  } catch {
    return null;
  }
}

function eventFingerprintV1(event: CandidateVerifiedAuthDeletionEventV1): string {
  return canonicalSha256({contract: "account-deletion-auth-on-delete-v1", ...event});
}

function eventReceiptMatchesV1(input: {
  receipt: CandidateProviderEventReceiptV1;
  eventIdV1: string;
  eventKindV1: CandidateProviderEventReceiptV1["eventKindV1"];
  scope: ReturnType<typeof ad04ScopeV1>;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  internalJobId: string;
  eventFingerprintV1: string;
}): boolean {
  return input.receipt.eventIdV1 === input.eventIdV1 &&
    input.receipt.eventKindV1 === input.eventKindV1 &&
    input.receipt.internalJobId === input.internalJobId &&
    input.receipt.generationHash === input.generationHash &&
    input.receipt.acceptedLifecycleEpochV2 === input.acceptedLifecycleEpochV2 &&
    input.receipt.eventFingerprintV1 === input.eventFingerprintV1 &&
    sameAd04ScopeV1(input.receipt, input.scope);
}

function completedAuthTaskV1(
  task: CandidateDeletionTaskV1,
  nowSecV1: number,
): CandidateDeletionTaskV1 {
  return parseCandidateDeletionTaskV1({
    ...task,
    stateV1: "complete",
    leaseOwnerV1: null,
    leaseExpiresAtSecV1: null,
    safeErrorCodeV1: null,
    completedAtSecV1: nowSecV1,
  });
}

function authEffectReceiptV1(input: {
  task: CandidateDeletionTaskV1;
  nowSecV1: number;
}): CandidateDeletionEffectReceiptV1 {
  return parseCandidateEffectReceiptV1({
    schemaVersion: 1,
    internalJobId: input.task.internalJobId,
    ...ad04ScopeV1(input.task),
    generationHash: input.task.generationHash,
    acceptedLifecycleEpochV2: input.task.acceptedLifecycleEpochV2,
    effectIdV1: input.task.effectIdV1,
    effectFingerprintV1: input.task.effectFingerprintV1,
    kindV1: input.task.kindV1,
    adapterIdV1: null,
    outcomeV1: "alreadySatisfied",
    evidenceCodeV1: "auth_on_delete_verified_absence",
    recordedAtSecV1: input.nowSecV1,
  });
}

function effectReceiptMatchesTaskV1(
  receipt: CandidateDeletionEffectReceiptV1,
  task: CandidateDeletionTaskV1,
): boolean {
  return sameAd04ScopeV1(receipt, task) &&
    receipt.internalJobId === task.internalJobId &&
    receipt.generationHash === task.generationHash &&
    receipt.acceptedLifecycleEpochV2 === task.acceptedLifecycleEpochV2 &&
    receipt.effectIdV1 === task.effectIdV1 &&
    receipt.effectFingerprintV1 === task.effectFingerprintV1 &&
    receipt.kindV1 === task.kindV1 &&
    receipt.adapterIdV1 === task.adapterIdV1;
}

async function recordVerifiedUnexpectedAuthDeletionV1(input: {
  repository: CandidateDeletionRepositoryV1;
  event: CandidateVerifiedAuthDeletionEventV1;
  configuredProjectId: string;
}): Promise<AccountDeletionJobContract> {
  const event = input.event;
  if (event.authProjectIdV2 !== ad04OpaqueIdV1(input.configuredProjectId)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const scope = ad04ScopeV1(event);
  const internalJobId = deletionInternalJobIdV1(scope, event.generationHash);
  const fingerprint = eventFingerprintV1(event);
  const eventReceiptPath = deletionProviderEventReceiptPathV1(event.eventIdV1);
  if (event.accountLifecycleEpochV2 === Number.MAX_SAFE_INTEGER) {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
  const deletingEpochV2 = event.accountLifecycleEpochV2 + 1;
  return input.repository.runTransaction(async (transaction) => {
    const tasks = initialDeletionTasksV1({
      scope,
      internalJobId,
      generationHash: event.generationHash,
      acceptedLifecycleEpochV2: deletingEpochV2,
      nowSecV1: event.observedDeletedAtSecV1,
    });
    const authTasks = tasks.filter((task) => task.kindV1.startsWith("auth"));
    const [eventReceiptRaw, jobRaw, bindingRaw, providerBindingRaw, lifecycleRaw,
      membershipRaw, firebaseRaw, appleRaw, ...taskAndReceiptRows] = await Promise.all([
      transaction.read(eventReceiptPath),
      transaction.read(deletionJobPathV1(internalJobId)),
      transaction.read(deletionJobBindingPathV1(internalJobId)),
      transaction.read(deletionProviderBindingPathV1(internalJobId)),
      transaction.read(candidateAccountLifecycleAuthorityPathV1(scope)),
      transaction.read(candidateMembershipAuthorityPathV1(scope)),
      transaction.read(deletionProviderCheckpointPathV1(internalJobId, "firebaseAuth")),
      transaction.read(deletionProviderCheckpointPathV1(internalJobId, "appleCredential")),
      ...tasks.map((task) => transaction.read(
        deletionTaskPathV1(internalJobId, task.effectIdV1),
      )),
      ...authTasks.map((task) => transaction.read(
        deletionEffectReceiptPathV1(internalJobId, task.effectIdV1),
      )),
    ]);
    if (eventReceiptRaw !== null) {
      const receipt = parseCandidateProviderEventReceiptV1(eventReceiptRaw);
      if (!eventReceiptMatchesV1({
        receipt,
        eventIdV1: event.eventIdV1,
        eventKindV1: "authOnDelete",
        scope,
        generationHash: event.generationHash,
        acceptedLifecycleEpochV2: deletingEpochV2,
        internalJobId,
        eventFingerprintV1: fingerprint,
      }) || jobRaw === null) ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    const lifecycle = parseLifecycleOrNull(lifecycleRaw);
    if (lifecycle !== null && (!sameAd04ScopeV1(lifecycle, scope) ||
        lifecycle.accountGenerationV2 !== event.generationHash)) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    const membership = parseMembershipOrNull(membershipRaw);
    let job: AccountDeletionJobContract;
    let binding: CandidateDeletionJobBindingV1;
    let providerBinding: CandidateDeletionProviderBindingV1;
    if (jobRaw !== null || bindingRaw !== null || providerBindingRaw !== null) {
      if (jobRaw === null || bindingRaw === null || providerBindingRaw === null) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      job = parseCandidateDeletionJobV1(jobRaw);
      binding = parseCandidateDeletionJobBindingV1(bindingRaw);
      providerBinding = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
      if (job.internalJobId !== internalJobId || job.generationHash !== event.generationHash ||
          job.policyVersion !== binding.policyVersion ||
          !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
          binding.internalJobId !== internalJobId ||
          binding.generationHash !== event.generationHash ||
          binding.acceptedLifecycleEpochV2 !== deletingEpochV2 ||
          providerBinding.internalJobId !== internalJobId ||
          providerBinding.generationHash !== event.generationHash ||
          providerBinding.acceptedLifecycleEpochV2 !== deletingEpochV2 ||
          providerBinding.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
          !sameAd04ScopeV1(binding, scope) || !sameAd04ScopeV1(providerBinding, scope)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      if (event.accountLifecycleEpochV2 === Number.MAX_SAFE_INTEGER ||
          event.accountLifecycleEpochV2 + 1 !== binding.acceptedLifecycleEpochV2 ||
          (lifecycle !== null &&
           (lifecycle.accountLifecycleEpochV2 !== binding.acceptedLifecycleEpochV2 ||
            !["deleting", "deleted"].includes(lifecycle.lifecycleStateV2)))) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    } else {
      if (lifecycle !== null &&
          (lifecycle.accountLifecycleEpochV2 !== event.accountLifecycleEpochV2 ||
           lifecycle.lifecycleStateV2 !== "active")) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      const acceptedSemanticFingerprint = canonicalSha256({
        contract: "account-deletion-unexpected-auth-absence-v1",
        ...scope,
        generationHash: event.generationHash,
      });
      job = parseCandidateDeletionJobV1({
        schemaVersion: 1,
        internalJobId,
        generationHash: event.generationHash,
        state: "accepted",
        resumeStage: null,
        policyVersion: "unapproved",
        inventoryVersion: accountDeletionVersions.inventoryVersion,
        attempt: 0,
        leaseGeneration: 0,
        authorityFenceDurable: true,
        minimumCleanupReferencesCaptured: true,
        authDeletionCheckpointState: "complete",
        authAbsent: true,
        dataDispositionVerified: false,
        publicPrivacyVerified: false,
        custodyRecorded: false,
        providerDispositionRecorded: false,
        restoreSuppressionDurable: false,
        safeErrorCode: null,
      });
      binding = parseCandidateDeletionJobBindingV1({
        schemaVersion: 1,
        internalJobId,
        ...scope,
        generationHash: event.generationHash,
        authCreatedAtIsoV1: event.authCreatedAtIsoV1,
        acceptedLifecycleEpochV2: deletingEpochV2,
        acceptedSemanticFingerprint,
        winningOperationId: `auth_${canonicalSha256({
          contract: "account-deletion-auth-event-operation-v1",
          eventIdV1: event.eventIdV1,
        })}`,
        policyVersion: "unapproved",
        impactVersion: "unexpected_auth_deletion",
        custodyChoice: "ordinary",
        associationId: null,
        custodyOutcomeV1: "policyBlockedButDeletionMustReceiveOperationalResolution",
        custodyRequiresAttentionV1: true,
        acceptedAtSecV1: event.observedDeletedAtSecV1,
        statusAliasCountV1: 0,
      });
      providerBinding = parseCandidateDeletionProviderBindingV1({
        schemaVersion: 1,
        internalJobId,
        ...scope,
        generationHash: event.generationHash,
        acceptedLifecycleEpochV2: deletingEpochV2,
        providerRelationshipV1: event.providerRelationshipV1,
        appleProviderSubjectHashV1: event.appleProviderSubjectHashV1,
        providerRevocationRefV1: null,
        materialStateV1: event.providerRelationshipV1 === "apple"
          ? "missing" : event.providerRelationshipV1 === "nonApple"
            ? "notApplicable" : "unknown",
        recordedAtSecV1: event.observedDeletedAtSecV1,
      });
    }
    const existingTaskRows = taskAndReceiptRows.slice(0, tasks.length);
    const existingReceiptRows = taskAndReceiptRows.slice(tasks.length);
    for (let index = 0; index < tasks.length; index += 1) {
      const expected = tasks[index];
      const raw = existingTaskRows[index];
      if (raw !== null) {
        const actual = parseCandidateDeletionTaskV1(raw);
        if (!sameAd04ScopeV1(actual, expected) ||
            actual.internalJobId !== expected.internalJobId ||
            actual.generationHash !== expected.generationHash ||
            actual.acceptedLifecycleEpochV2 !== expected.acceptedLifecycleEpochV2 ||
            actual.effectIdV1 !== expected.effectIdV1 ||
            actual.effectFingerprintV1 !== expected.effectFingerprintV1 ||
            actual.kindV1 !== expected.kindV1 ||
            actual.adapterIdV1 !== expected.adapterIdV1 ||
            actual.adapterVersionV1 !== expected.adapterVersionV1 ||
            actual.createdAtSecV1 !== binding.acceptedAtSecV1) {
          ad04FailV1("AD04_EFFECT_CONFLICT");
        }
      } else if (jobRaw !== null) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    }
    const eventReceipt = parseCandidateProviderEventReceiptV1({
      schemaVersion: 1,
      eventIdV1: event.eventIdV1,
      eventKindV1: "authOnDelete",
      internalJobId,
      ...scope,
      generationHash: event.generationHash,
      acceptedLifecycleEpochV2: deletingEpochV2,
      eventFingerprintV1: fingerprint,
      recordedAtSecV1: event.observedDeletedAtSecV1,
    });
    transaction.write(candidateAccountLifecycleAuthorityPathV1(scope), {
      authIncarnationSchemaVersionV2: 2,
      ...scope,
      accountGenerationV2: event.generationHash,
      accountLifecycleEpochV2: deletingEpochV2,
      lifecycleStateV2: lifecycle?.lifecycleStateV2 === "deleted" ? "deleted" : "deleting",
      reauthAfterSecV2: event.observedDeletedAtSecV1,
    });
    if (membership !== null && sameAd04ScopeV1(membership, scope) &&
        membership.accountGenerationV2 === event.generationHash) {
      transaction.write(candidateMembershipAuthorityPathV1(scope), {
        ...membership,
        accountLifecycleEpochV2: deletingEpochV2,
        membershipStatusV2: "revoked",
        capabilities: [],
      });
    }
    transaction.write(deletionJobPathV1(internalJobId), asWriteRecord({
      ...job,
      authDeletionCheckpointState: "complete",
      authAbsent: true,
    }));
    transaction.write(deletionJobBindingPathV1(internalJobId), asWriteRecord(binding));
    transaction.write(deletionProviderBindingPathV1(internalJobId),
      asWriteRecord(providerBinding));
    transaction.write(deletionProviderCheckpointPathV1(internalJobId, "firebaseAuth"), {
      schemaVersion: 1,
      provider: "firebaseAuth",
      state: "complete",
      evidenceCode: "auth_on_delete_verified_absence",
      checkedAt: new Date(event.observedDeletedAtSecV1 * 1000),
    });
    if (appleRaw === null) {
      transaction.write(deletionProviderCheckpointPathV1(internalJobId, "appleCredential"), {
        schemaVersion: 1,
        provider: "appleCredential",
        state: "pending",
        evidenceCode: "auth_on_delete_provider_reconcile_pending",
        checkedAt: new Date(event.observedDeletedAtSecV1 * 1000),
      });
    }
    if (firebaseRaw !== null) {
      const firebaseCheckpoint = parseCandidateProviderCheckpointV1(firebaseRaw);
      if (firebaseCheckpoint.provider !== "firebaseAuth") {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    }
    if (appleRaw !== null) {
      const appleCheckpoint = parseCandidateProviderCheckpointV1(appleRaw);
      if (appleCheckpoint.provider !== "appleCredential") {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
    }
    for (const task of tasks) {
      const existing = existingTaskRows[tasks.indexOf(task)];
      if (task.kindV1.startsWith("auth")) {
        const existingTask = existing === null
          ? task : parseCandidateDeletionTaskV1(existing);
        const authIndex = authTasks.findIndex((candidate) =>
          candidate.effectIdV1 === task.effectIdV1);
        const existingReceipt = existingReceiptRows[authIndex];
        let receipt: CandidateDeletionEffectReceiptV1;
        let completedAtSecV1 = event.observedDeletedAtSecV1;
        if (existingReceipt !== null) {
          receipt = parseCandidateEffectReceiptV1(existingReceipt);
          if (!effectReceiptMatchesTaskV1(receipt, existingTask)) {
            ad04FailV1("AD04_EFFECT_CONFLICT");
          }
          completedAtSecV1 = receipt.recordedAtSecV1;
        } else {
          if (existingTask.stateV1 === "complete" &&
              existingTask.completedAtSecV1 !== null) {
            completedAtSecV1 = existingTask.completedAtSecV1;
          }
          receipt = authEffectReceiptV1({
            task: existingTask,
            nowSecV1: completedAtSecV1,
          });
          transaction.write(deletionEffectReceiptPathV1(
            internalJobId,
            task.effectIdV1,
          ), asWriteRecord(receipt));
        }
        const completeTask = existingTask.stateV1 === "complete"
          ? existingTask
          : completedAuthTaskV1(existingTask, completedAtSecV1);
        if (completeTask.completedAtSecV1 !== receipt.recordedAtSecV1) {
          ad04FailV1("AD04_EFFECT_CONFLICT");
        }
        transaction.write(deletionTaskPathV1(internalJobId, task.effectIdV1),
          asWriteRecord(completeTask));
      } else if (existing === null) {
        transaction.write(deletionTaskPathV1(internalJobId, task.effectIdV1),
          asWriteRecord(task));
      }
    }
    transaction.write(eventReceiptPath, asWriteRecord(eventReceipt));
    return parseCandidateDeletionJobV1({
      ...job,
      authDeletionCheckpointState: "complete",
      authAbsent: true,
    });
  });
}

export async function handleCandidateUnexpectedAuthDeletionV1(input: {
  repository: CandidateDeletionRepositoryV1;
  verifier: CandidateAuthDeletionEventVerifierV1;
  event: unknown;
  configuredProjectId: string;
}): Promise<AccountDeletionJobContract> {
  const verified = parseAuthDeletionEventV1(
    await input.verifier.verifyAuthDeletionEventV1(input.event),
  );
  return recordVerifiedUnexpectedAuthDeletionV1({
    repository: input.repository,
    event: verified,
    configuredProjectId: input.configuredProjectId,
  });
}

export async function runCandidateAuthOrphanReconciliationV1(input: {
  repository: CandidateDeletionRepositoryV1;
  scanner: CandidateAuthOrphanScannerV1;
  configuredProjectId: string;
  limitV1: number;
}): Promise<readonly AccountDeletionJobContract[]> {
  const limitV1 = ad04CounterV1(input.limitV1);
  if (limitV1 === 0 || limitV1 > ACCOUNT_DELETION_AD04_MAX_SWEEP_ITEMS_V1) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const rows = await input.scanner.listVerifiedAbsentAccountsV1({
    configuredProjectId: ad04OpaqueIdV1(input.configuredProjectId),
    limitV1,
  });
  if (!Array.isArray(rows) || rows.length > limitV1) {
    ad04FailV1("AD04_EFFECT_CONFLICT");
  }
  const events = rows.map(parseAuthDeletionEventV1);
  const results: AccountDeletionJobContract[] = [];
  for (const event of events) {
    results.push(await recordVerifiedUnexpectedAuthDeletionV1({
      repository: input.repository,
      event,
      configuredProjectId: input.configuredProjectId,
    }));
  }
  return Object.freeze(results);
}

export async function handleCandidateAppleCredentialEventV1(input: {
  repository: CandidateDeletionRepositoryV1;
  verifier: CandidateAppleEventVerifierV1;
  event: unknown;
  configuredProjectId: string;
}): Promise<"recorded" | "replayed"> {
  const event = parseAppleEventV1(
    await input.verifier.verifyAppleCredentialEventV1(input.event),
  );
  if (event.authProjectIdV2 !== ad04OpaqueIdV1(input.configuredProjectId)) {
    ad04FailV1("AD04_AUTHORITY_DENIED");
  }
  const fingerprint = canonicalSha256({
    contract: "account-deletion-apple-provider-event-v1",
    ...event,
  });
  const eventPath = deletionProviderEventReceiptPathV1(event.eventIdV1);
  return input.repository.runTransaction(async (transaction) => {
    const [eventRaw, jobRaw, bindingRaw, providerBindingRaw, checkpointRaw] =
      await Promise.all([
      transaction.read(eventPath),
      transaction.read(deletionJobPathV1(event.internalJobId)),
      transaction.read(deletionJobBindingPathV1(event.internalJobId)),
      transaction.read(deletionProviderBindingPathV1(event.internalJobId)),
      transaction.read(deletionProviderCheckpointPathV1(
        event.internalJobId,
        "appleCredential",
      )),
    ]);
    if (jobRaw === null || bindingRaw === null || providerBindingRaw === null ||
        checkpointRaw === null) ad04FailV1("AD04_EFFECT_CONFLICT");
    const job = parseCandidateDeletionJobV1(jobRaw);
    const binding = parseCandidateDeletionJobBindingV1(bindingRaw);
    const provider = parseCandidateDeletionProviderBindingV1(providerBindingRaw);
    const checkpoint = parseCandidateProviderCheckpointV1(checkpointRaw);
    if (job.internalJobId !== event.internalJobId ||
        job.generationHash !== event.generationHash ||
        job.policyVersion !== binding.policyVersion ||
        !job.authorityFenceDurable || !job.minimumCleanupReferencesCaptured ||
        binding.internalJobId !== event.internalJobId ||
        binding.generationHash !== event.generationHash ||
        binding.acceptedLifecycleEpochV2 !== event.acceptedLifecycleEpochV2 ||
        provider.internalJobId !== event.internalJobId ||
        provider.generationHash !== event.generationHash ||
        provider.acceptedLifecycleEpochV2 !== event.acceptedLifecycleEpochV2 ||
        provider.recordedAtSecV1 !== binding.acceptedAtSecV1 ||
        provider.providerRelationshipV1 !== "apple" ||
        provider.appleProviderSubjectHashV1 !== event.providerSubjectHashV1 ||
        checkpoint.provider !== "appleCredential" ||
        event.observedAtSecV1 < binding.acceptedAtSecV1 ||
        !sameAd04ScopeV1(binding, event) || !sameAd04ScopeV1(provider, event)) {
      ad04FailV1("AD04_EFFECT_CONFLICT");
    }
    if (eventRaw !== null) {
      const receipt = parseCandidateProviderEventReceiptV1(eventRaw);
      if (!eventReceiptMatchesV1({
        receipt,
        eventIdV1: event.eventIdV1,
        eventKindV1: "appleCredentialRevoked",
        scope: ad04ScopeV1(event),
        generationHash: event.generationHash,
        acceptedLifecycleEpochV2: event.acceptedLifecycleEpochV2,
        internalJobId: event.internalJobId,
        eventFingerprintV1: fingerprint,
      }) || !isProviderCheckpointTerminal(checkpoint)) {
        ad04FailV1("AD04_EFFECT_CONFLICT");
      }
      return "replayed";
    }
    const receipt = parseCandidateProviderEventReceiptV1({
      schemaVersion: 1,
      eventIdV1: event.eventIdV1,
      eventKindV1: "appleCredentialRevoked",
      internalJobId: event.internalJobId,
      ...ad04ScopeV1(event),
      generationHash: event.generationHash,
      acceptedLifecycleEpochV2: event.acceptedLifecycleEpochV2,
      eventFingerprintV1: fingerprint,
      recordedAtSecV1: event.observedAtSecV1,
    });
    transaction.write(deletionProviderCheckpointPathV1(
      event.internalJobId,
      "appleCredential",
    ), {
      schemaVersion: 1,
      provider: "appleCredential",
      state: "complete",
      evidenceCode: "apple_provider_event_verified",
      checkedAt: new Date(event.observedAtSecV1 * 1000),
    });
    transaction.write(eventPath, asWriteRecord(receipt));
    return "recorded";
  });
}

export const ACCOUNT_DELETION_AD04_AUTH_ON_DELETE_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD04_SCHEDULED_SWEEPER_EXPORT_ALLOWED_V1 = false;

export function candidateAuthSafetyNetExportReadyV1(): false {
  return false;
}

export function candidateScheduledSweeperExportReadyV1(): false {
  return false;
}
