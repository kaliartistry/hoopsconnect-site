import {createHash} from "node:crypto";

import {
  AccountDeletionJobContract,
  AccountDeletionStatusAliasContract,
  AdapterResultContract,
  CustodyChoice,
  ProviderCheckpointContract,
  accountDeletionAdapterIds,
  firebaseUidUtf16LeBase64Url,
  validateAccountLifecycle,
  validateAdapterResult,
  validateDeletionJob,
  validateProviderCheckpoint,
  validateStatusAlias,
} from "../domain/account_deletion_contract";
import {
  AccountLifecycleAuthorityV2,
  AccountLifecycleStateV2,
  AuthIncarnationScopeV2,
} from "../domain/auth_incarnation_v2";
import {canonicalSha256} from "../domain/official_stats_contract";

export const ACCOUNT_DELETION_AD04_ACTIVATION_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD04_PRODUCTION_EXPORT_ALLOWED_V1 = false;
export const ACCOUNT_DELETION_AD04_AUTH_GENERATION_MUTATION_PROVEN_V1 = false;
export const ACCOUNT_DELETION_AD04_SHARED_AD02_UID_PATH_CODEC_PROVEN_V1 = false;
export const ACCOUNT_DELETION_AD04_SCHEMA_VERSION_V1 = 1;
export const ACCOUNT_DELETION_AD04_FRESH_AUTH_MAX_AGE_SEC_V1 = 300;
export const ACCOUNT_DELETION_AD04_INTENT_TTL_SEC_V1 = 600;
export const ACCOUNT_DELETION_AD04_LEASE_SEC_V1 = 60;
export const ACCOUNT_DELETION_AD04_INITIAL_RETRY_SEC_V1 = 60;
export const ACCOUNT_DELETION_AD04_MAX_RETRY_SEC_V1 = 1800;
export const ACCOUNT_DELETION_AD04_ATTENTION_ATTEMPT_V1 = 20;
export const ACCOUNT_DELETION_AD04_MAX_STATUS_ALIASES_V1 = 8;
export const ACCOUNT_DELETION_AD04_MAX_SWEEP_ITEMS_V1 = 100;

export const deletionTaskKindsV1 = [
  "authDisable",
  "authRevokeRefreshTokens",
  "authDeleteSingleUser",
  "authVerifyAbsence",
  "appleCredentialDisposition",
  "cleanupAdapter",
  "reconcileCompletion",
] as const;
export type DeletionTaskKindV1 = typeof deletionTaskKindsV1[number];

export const deletionTaskStatesV1 = [
  "pending",
  "leased",
  "retryWait",
  "needsAttention",
  "complete",
] as const;
export type DeletionTaskStateV1 = typeof deletionTaskStatesV1[number];

export const deletionProviderRelationshipsV1 = [
  "apple",
  "nonApple",
  "unknown",
] as const;
export type DeletionProviderRelationshipV1 =
  typeof deletionProviderRelationshipsV1[number];

export type DeletionEffectOutcomeV1 =
  | "applied"
  | "alreadySatisfied"
  | "notApplicable"
  | "manualActionGuidance"
  | "verifiedComplete";

export type AccountDeletionAd04ErrorCodeV1 =
  | "AD04_INVALID_REQUEST"
  | "AD04_AUTHORITY_DENIED"
  | "AD04_REAUTH_REQUIRED"
  | "AD04_APP_ATTESTATION_REQUIRED"
  | "AD04_INTENT_EXPIRED"
  | "AD04_IMPACT_CHANGED"
  | "AD04_OPERATION_CONFLICT"
  | "AD04_STATUS_UNAVAILABLE"
  | "AD04_TASK_NOT_READY"
  | "AD04_LEASE_CONFLICT"
  | "AD04_EFFECT_CONFLICT"
  | "AD04_TEMPORARILY_UNAVAILABLE"
  | "AD04_REVIEW_REQUIRED";

export class AccountDeletionAd04ErrorV1 extends Error {
  readonly codeV1: AccountDeletionAd04ErrorCodeV1;

  constructor(codeV1: AccountDeletionAd04ErrorCodeV1) {
    super(codeV1);
    this.name = "AccountDeletionAd04ErrorV1";
    this.codeV1 = codeV1;
  }
}

export interface CandidateDeletionTransactionV1 {
  read(path: string): Promise<unknown | null>;
  write(path: string, value: Readonly<Record<string, unknown>>): void;
}

export interface CandidateDeletionRepositoryV1 {
  read(path: string): Promise<unknown | null>;
  runTransaction<T>(
    operation: (transaction: CandidateDeletionTransactionV1) => Promise<T>,
  ): Promise<T>;
}

export interface OwnerDepartureRequestRecordV1 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  departureOperationIdV2: string;
  expectedControlVersionV2: number;
  custodyChoiceV2: CustodyChoice;
  transferIntentIdV2: string | null;
  custodyCaseIdV2: string | null;
}

export interface CandidateDeletionIntentV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  intentId: string;
  generationHash: string;
  expectedLifecycleEpochV2: number;
  policyVersion: string;
  impactVersion: string;
  custodyChoice: CustodyChoice;
  associationId: string | null;
  ownerDepartureRequestV2: OwnerDepartureRequestRecordV1 | null;
  candidateTestCustodyPolicyIdV2: string | null;
  providerRelationshipV1: DeletionProviderRelationshipV1;
  preparedAtSecV1: number;
  expiresAtSecV1: number;
  intentFingerprintV1: string;
}

export interface CandidateDeletionJobBindingV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  internalJobId: string;
  generationHash: string;
  authCreatedAtIsoV1: string;
  acceptedLifecycleEpochV2: number;
  acceptedSemanticFingerprint: string;
  winningOperationId: string;
  policyVersion: string;
  impactVersion: string;
  custodyChoice: CustodyChoice;
  associationId: string | null;
  custodyOutcomeV1: string;
  custodyRequiresAttentionV1: boolean;
  acceptedAtSecV1: number;
  statusAliasCountV1: number;
}

export interface CandidateDeletionProviderBindingV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  providerRelationshipV1: DeletionProviderRelationshipV1;
  appleProviderSubjectHashV1: string | null;
  providerRevocationRefV1: string | null;
  materialStateV1: "available" | "missing" | "notApplicable" | "unknown";
  recordedAtSecV1: number;
}

export interface CandidateDeletionStatusControlV1 {
  schemaVersion: 1;
  requestId: string;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  stateV1: "active" | "expired";
  expiresAtSecV1: number | null;
  expiryPolicyDecisionId: string;
}

export interface CandidateRevocationMaterialV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  providerRevocationRefV1: string;
  generationHash: string;
  accountLifecycleEpochV2: number;
  providerV1: "appleCredential";
  providerSubjectHashV1: string;
  materialFingerprintV1: string;
  stateV1: "available" | "consumed";
  expiresAtSecV1: number;
}

export interface CandidateDeletionOperationReceiptV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  receiptIdV1: string;
  operationId: string;
  requestId: string;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  submittedSemanticFingerprint: string;
  submittedEnvelopeFingerprint: string;
  acceptedSemanticFingerprint: string;
  bindingKind: "winningOperation" | "sameGenerationConvergence";
  acceptedAtSecV1: number;
}

export interface CandidateDeletionTaskV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  effectIdV1: string;
  effectFingerprintV1: string;
  kindV1: DeletionTaskKindV1;
  adapterIdV1: string | null;
  adapterVersionV1: string;
  stateV1: DeletionTaskStateV1;
  attemptsV1: number;
  leaseGenerationV1: number;
  leaseOwnerV1: string | null;
  leaseExpiresAtSecV1: number | null;
  nextAttemptAtSecV1: number;
  safeErrorCodeV1: string | null;
  createdAtSecV1: number;
  completedAtSecV1: number | null;
}

export interface CandidateDeletionEffectReceiptV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  effectIdV1: string;
  effectFingerprintV1: string;
  kindV1: DeletionTaskKindV1;
  adapterIdV1: string | null;
  outcomeV1: DeletionEffectOutcomeV1;
  evidenceCodeV1: string;
  recordedAtSecV1: number;
}

export interface CandidateProviderEventReceiptV1 extends AuthIncarnationScopeV2 {
  schemaVersion: 1;
  eventIdV1: string;
  eventKindV1: "authOnDelete" | "appleCredentialRevoked";
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  eventFingerprintV1: string;
  recordedAtSecV1: number;
}

export interface CandidateDeletionStatusV1 {
  requestId: string;
  phase: "processing" | "accountRemovedCleanupPending" |
    "attentionRequired" | "complete";
  acceptedAt: string;
  completedAt?: string;
  nextPollAfterSeconds?: number;
  retainedCategoryCodes: readonly string[];
  providerOutcome?: "revoked" | "not_applicable" |
    "manual_action_guidance" | "pending";
  messageCode: string;
}

type JsonRecord = Record<string, unknown>;

const opaqueIdPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const namespacePattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,191}$/;
const hashPattern = /^[a-f0-9]{64}$/;
const isoPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

export function ad04FailV1(code: AccountDeletionAd04ErrorCodeV1): never {
  throw new AccountDeletionAd04ErrorV1(code);
}

export function ad04RecordV1(value: unknown): JsonRecord | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  try {
    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null
      ? value as JsonRecord
      : null;
  } catch {
    return null;
  }
}

export function ad04ExactKeysV1(
  value: JsonRecord,
  expected: readonly string[],
): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length &&
    expected.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

export function ad04OpaqueIdV1(value: unknown): string {
  if (typeof value !== "string" || !opaqueIdPattern.test(value)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return value;
}

export function ad04FirebaseUidV1(value: unknown): string {
  try {
    // Reuse the frozen AD01 definition: any non-empty Firebase UID of at most
    // 128 JavaScript UTF-16 code units, without normalization or narrowing.
    firebaseUidUtf16LeBase64Url(value as string);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return value as string;
}

export function ad04NamespaceV1(value: unknown): string {
  if (typeof value !== "string" || !namespacePattern.test(value)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return value;
}

export function ad04HashV1(value: unknown): string {
  if (typeof value !== "string" || !hashPattern.test(value)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return value;
}

export function ad04CounterV1(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.is(value, -0) ? 0 : value as number;
}

export function ad04NullableCounterV1(value: unknown): number | null {
  return value === null ? null : ad04CounterV1(value);
}

export function ad04ScopeV1(value: unknown): AuthIncarnationScopeV2 {
  const data = ad04RecordV1(value);
  if (data === null || ![
    "authProjectIdV2", "authTenantIdV2", "authUidV2",
  ].every((key) => Object.prototype.hasOwnProperty.call(data, key))) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const project = ad04OpaqueIdV1(data.authProjectIdV2);
  const uid = ad04FirebaseUidV1(data.authUidV2);
  const tenant = data.authTenantIdV2 === null
    ? null
    : ad04OpaqueIdV1(data.authTenantIdV2);
  return Object.freeze({
    authProjectIdV2: project,
    authTenantIdV2: tenant,
    authUidV2: uid,
  });
}

export function parseCandidateAccountLifecycleAuthorityV2ForDeletionV1(
  value: unknown,
): AccountLifecycleAuthorityV2 {
  const data = ad04RecordV1(value);
  const keys = [
    "authIncarnationSchemaVersionV2", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "accountGenerationV2", "accountLifecycleEpochV2",
    "lifecycleStateV2", "reauthAfterSecV2",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      data.authIncarnationSchemaVersionV2 !== 2 ||
      !["pending", "active", "deleting", "deleted"].includes(
        data.lifecycleStateV2 as string,
      )) ad04FailV1("AD04_INVALID_REQUEST");
  return Object.freeze({
    authIncarnationSchemaVersionV2: 2,
    ...ad04ScopeV1(data),
    accountGenerationV2: ad04HashV1(data.accountGenerationV2),
    accountLifecycleEpochV2: ad04CounterV1(data.accountLifecycleEpochV2),
    lifecycleStateV2: data.lifecycleStateV2 as AccountLifecycleStateV2,
    reauthAfterSecV2: ad04CounterV1(data.reauthAfterSecV2),
  });
}

export function sameAd04ScopeV1(
  left: AuthIncarnationScopeV2,
  right: AuthIncarnationScopeV2,
): boolean {
  return left.authProjectIdV2 === right.authProjectIdV2 &&
    left.authTenantIdV2 === right.authTenantIdV2 &&
    left.authUidV2 === right.authUidV2;
}

export function authNamespaceForScopeV1(scope: AuthIncarnationScopeV2): string {
  const parsed = ad04ScopeV1(scope);
  return `firebase:${parsed.authProjectIdV2}:${parsed.authTenantIdV2 ?? "root"}`;
}

function scopeFromRecord(data: JsonRecord): AuthIncarnationScopeV2 {
  return ad04ScopeV1({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
}

function requireSchemaV1(value: unknown): void {
  if (value !== 1) ad04FailV1("AD04_INVALID_REQUEST");
}

function nullableOpaque(value: unknown): string | null {
  return value === null ? null : ad04OpaqueIdV1(value);
}

function bool(value: unknown): boolean {
  if (typeof value !== "boolean") ad04FailV1("AD04_INVALID_REQUEST");
  return value;
}

function validIso(value: unknown): string {
  if (typeof value !== "string" || !isoPattern.test(value) ||
      !Number.isFinite(new Date(value).getTime()) || new Date(value).toISOString() !== value) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return value;
}

function includesValue<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === "string" && (values as readonly string[]).includes(value);
}

function ownerDeparture(value: unknown): OwnerDepartureRequestRecordV1 | null {
  if (value === null) return null;
  const data = ad04RecordV1(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "departureOperationIdV2",
    "expectedControlVersionV2", "custodyChoiceV2", "transferIntentIdV2",
    "custodyCaseIdV2",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2 ||
      !includesValue(["ordinary", "transferThenDelete", "suspendToCustody"] as const,
        data.custodyChoiceV2)) ad04FailV1("AD04_INVALID_REQUEST");
  const result: OwnerDepartureRequestRecordV1 = {
    associationOwnershipSchemaVersionV2: 2,
    associationId: ad04OpaqueIdV1(data.associationId),
    departureOperationIdV2: ad04OpaqueIdV1(data.departureOperationIdV2),
    expectedControlVersionV2: ad04CounterV1(data.expectedControlVersionV2),
    custodyChoiceV2: data.custodyChoiceV2,
    transferIntentIdV2: nullableOpaque(data.transferIntentIdV2),
    custodyCaseIdV2: nullableOpaque(data.custodyCaseIdV2),
  };
  if ((result.custodyChoiceV2 === "ordinary" &&
       (result.transferIntentIdV2 !== null || result.custodyCaseIdV2 !== null)) ||
      (result.custodyChoiceV2 === "transferThenDelete" &&
       (result.transferIntentIdV2 === null || result.custodyCaseIdV2 !== null)) ||
      (result.custodyChoiceV2 === "suspendToCustody" &&
       result.custodyCaseIdV2 === null)) ad04FailV1("AD04_INVALID_REQUEST");
  return Object.freeze(result);
}

export function deletionIntentFingerprintV1(input: Omit<
  CandidateDeletionIntentV1,
  "intentFingerprintV1"
>): string {
  return canonicalSha256(input);
}

export function parseCandidateDeletionIntentV1(value: unknown): CandidateDeletionIntentV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "intentId", "authProjectIdV2", "authTenantIdV2", "authUidV2",
    "generationHash", "expectedLifecycleEpochV2", "policyVersion", "impactVersion",
    "custodyChoice", "associationId", "ownerDepartureRequestV2",
    "candidateTestCustodyPolicyIdV2", "providerRelationshipV1", "preparedAtSecV1",
    "expiresAtSecV1", "intentFingerprintV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  requireSchemaV1(data.schemaVersion);
  if (!includesValue(["ordinary", "transferThenDelete", "suspendToCustody"] as const,
    data.custodyChoice) ||
      !includesValue(deletionProviderRelationshipsV1, data.providerRelationshipV1)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const scope = scopeFromRecord(data);
  const departure = ownerDeparture(data.ownerDepartureRequestV2);
  const associationId = nullableOpaque(data.associationId);
  const preparedAtSecV1 = ad04CounterV1(data.preparedAtSecV1);
  const expiresAtSecV1 = ad04CounterV1(data.expiresAtSecV1);
  if (expiresAtSecV1 <= preparedAtSecV1 ||
      expiresAtSecV1 - preparedAtSecV1 !== ACCOUNT_DELETION_AD04_INTENT_TTL_SEC_V1 ||
      (departure === null) !== (associationId === null) ||
      (departure !== null && (departure.associationId !== associationId ||
        departure.custodyChoiceV2 !== data.custodyChoice))) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const candidate: CandidateDeletionIntentV1 = Object.freeze({
    schemaVersion: 1,
    intentId: ad04OpaqueIdV1(data.intentId),
    ...scope,
    generationHash: ad04HashV1(data.generationHash),
    expectedLifecycleEpochV2: ad04CounterV1(data.expectedLifecycleEpochV2),
    policyVersion: ad04OpaqueIdV1(data.policyVersion),
    impactVersion: ad04OpaqueIdV1(data.impactVersion),
    custodyChoice: data.custodyChoice,
    associationId,
    ownerDepartureRequestV2: departure,
    candidateTestCustodyPolicyIdV2: nullableOpaque(data.candidateTestCustodyPolicyIdV2),
    providerRelationshipV1: data.providerRelationshipV1,
    preparedAtSecV1,
    expiresAtSecV1,
    intentFingerprintV1: ad04HashV1(data.intentFingerprintV1),
  });
  const {intentFingerprintV1, ...fingerprintInput} = candidate;
  if (deletionIntentFingerprintV1(fingerprintInput) !== intentFingerprintV1) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return candidate;
}

export function parseCandidateDeletionJobBindingV1(
  value: unknown,
): CandidateDeletionJobBindingV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "internalJobId", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "generationHash", "authCreatedAtIsoV1", "acceptedLifecycleEpochV2",
    "acceptedSemanticFingerprint", "winningOperationId", "policyVersion",
    "impactVersion", "custodyChoice", "associationId", "custodyOutcomeV1",
    "custodyRequiresAttentionV1", "acceptedAtSecV1", "statusAliasCountV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys)) ad04FailV1("AD04_INVALID_REQUEST");
  requireSchemaV1(data.schemaVersion);
  if (!includesValue(["ordinary", "transferThenDelete", "suspendToCustody"] as const,
    data.custodyChoice) || typeof data.custodyOutcomeV1 !== "string" ||
      !namespacePattern.test(data.custodyOutcomeV1)) ad04FailV1("AD04_INVALID_REQUEST");
  return Object.freeze({
    schemaVersion: 1,
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    authCreatedAtIsoV1: validIso(data.authCreatedAtIsoV1),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    acceptedSemanticFingerprint: ad04HashV1(data.acceptedSemanticFingerprint),
    winningOperationId: ad04OpaqueIdV1(data.winningOperationId),
    policyVersion: ad04OpaqueIdV1(data.policyVersion),
    impactVersion: ad04OpaqueIdV1(data.impactVersion),
    custodyChoice: data.custodyChoice,
    associationId: nullableOpaque(data.associationId),
    custodyOutcomeV1: data.custodyOutcomeV1,
    custodyRequiresAttentionV1: bool(data.custodyRequiresAttentionV1),
    acceptedAtSecV1: ad04CounterV1(data.acceptedAtSecV1),
    statusAliasCountV1: ad04CounterV1(data.statusAliasCountV1),
  });
}

export function parseCandidateDeletionProviderBindingV1(
  value: unknown,
): CandidateDeletionProviderBindingV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "internalJobId", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "generationHash", "acceptedLifecycleEpochV2",
    "providerRelationshipV1",
    "appleProviderSubjectHashV1", "providerRevocationRefV1", "materialStateV1",
    "recordedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys)) ad04FailV1("AD04_INVALID_REQUEST");
  requireSchemaV1(data.schemaVersion);
  if (!includesValue(deletionProviderRelationshipsV1, data.providerRelationshipV1) ||
      !includesValue(["available", "missing", "notApplicable", "unknown"] as const,
        data.materialStateV1)) ad04FailV1("AD04_INVALID_REQUEST");
  const relationship = data.providerRelationshipV1;
  const subject = data.appleProviderSubjectHashV1 === null
    ? null : ad04HashV1(data.appleProviderSubjectHashV1);
  const reference = nullableOpaque(data.providerRevocationRefV1);
  const state = data.materialStateV1;
  if ((relationship === "nonApple" &&
       (subject !== null || reference !== null || state !== "notApplicable")) ||
      (relationship === "apple" && (subject === null ||
        (state === "available") !== (reference !== null))) ||
      (relationship === "unknown" && state !== "unknown")) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    providerRelationshipV1: relationship,
    appleProviderSubjectHashV1: subject,
    providerRevocationRefV1: reference,
    materialStateV1: state,
    recordedAtSecV1: ad04CounterV1(data.recordedAtSecV1),
  });
}

export function parseCandidateDeletionStatusControlV1(
  value: unknown,
): CandidateDeletionStatusControlV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "requestId", "internalJobId", "generationHash",
    "acceptedLifecycleEpochV2", "stateV1", "expiresAtSecV1",
    "expiryPolicyDecisionId",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      !includesValue(["active", "expired"] as const, data.stateV1)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  requireSchemaV1(data.schemaVersion);
  const expiresAtSecV1 = ad04NullableCounterV1(data.expiresAtSecV1);
  if ((data.stateV1 === "expired") !== (expiresAtSecV1 !== null)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    requestId: ad04OpaqueIdV1(data.requestId),
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    stateV1: data.stateV1,
    expiresAtSecV1,
    expiryPolicyDecisionId: ad04NamespaceV1(data.expiryPolicyDecisionId),
  });
}

export function parseCandidateRevocationMaterialV1(
  value: unknown,
): CandidateRevocationMaterialV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "providerRevocationRefV1", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "generationHash", "accountLifecycleEpochV2", "providerV1",
    "providerSubjectHashV1",
    "materialFingerprintV1", "stateV1", "expiresAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      data.providerV1 !== "appleCredential" ||
      !includesValue(["available", "consumed"] as const, data.stateV1)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  requireSchemaV1(data.schemaVersion);
  return Object.freeze({
    schemaVersion: 1,
    providerRevocationRefV1: ad04OpaqueIdV1(data.providerRevocationRefV1),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    accountLifecycleEpochV2: ad04CounterV1(data.accountLifecycleEpochV2),
    providerV1: "appleCredential",
    providerSubjectHashV1: ad04HashV1(data.providerSubjectHashV1),
    materialFingerprintV1: ad04HashV1(data.materialFingerprintV1),
    stateV1: data.stateV1,
    expiresAtSecV1: ad04CounterV1(data.expiresAtSecV1),
  });
}

export function parseCandidateOperationReceiptV1(
  value: unknown,
): CandidateDeletionOperationReceiptV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "receiptIdV1", "operationId", "requestId", "internalJobId",
    "authProjectIdV2", "authTenantIdV2", "authUidV2", "generationHash",
    "acceptedLifecycleEpochV2",
    "submittedSemanticFingerprint", "submittedEnvelopeFingerprint",
    "acceptedSemanticFingerprint", "bindingKind", "acceptedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      !includesValue(["winningOperation", "sameGenerationConvergence"] as const,
        data.bindingKind)) ad04FailV1("AD04_INVALID_REQUEST");
  requireSchemaV1(data.schemaVersion);
  return Object.freeze({
    schemaVersion: 1,
    receiptIdV1: ad04OpaqueIdV1(data.receiptIdV1),
    operationId: ad04OpaqueIdV1(data.operationId),
    requestId: ad04OpaqueIdV1(data.requestId),
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    submittedSemanticFingerprint: ad04HashV1(data.submittedSemanticFingerprint),
    submittedEnvelopeFingerprint: ad04HashV1(data.submittedEnvelopeFingerprint),
    acceptedSemanticFingerprint: ad04HashV1(data.acceptedSemanticFingerprint),
    bindingKind: data.bindingKind,
    acceptedAtSecV1: ad04CounterV1(data.acceptedAtSecV1),
  });
}

export function parseCandidateDeletionTaskV1(value: unknown): CandidateDeletionTaskV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "internalJobId", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "generationHash", "acceptedLifecycleEpochV2", "effectIdV1",
    "effectFingerprintV1", "kindV1", "adapterIdV1", "adapterVersionV1",
    "stateV1", "attemptsV1",
    "leaseGenerationV1", "leaseOwnerV1", "leaseExpiresAtSecV1",
    "nextAttemptAtSecV1", "safeErrorCodeV1", "createdAtSecV1", "completedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      !includesValue(deletionTaskKindsV1, data.kindV1) ||
      !includesValue(deletionTaskStatesV1, data.stateV1)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  requireSchemaV1(data.schemaVersion);
  const adapterIdV1 = nullableOpaque(data.adapterIdV1);
  if ((data.kindV1 === "cleanupAdapter") !== (adapterIdV1 !== null) ||
      (adapterIdV1 !== null &&
       !accountDeletionAdapterIds.includes(adapterIdV1 as typeof accountDeletionAdapterIds[number]))) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  const state = data.stateV1;
  const leaseOwner = nullableOpaque(data.leaseOwnerV1);
  const leaseExpiry = ad04NullableCounterV1(data.leaseExpiresAtSecV1);
  const completedAt = ad04NullableCounterV1(data.completedAtSecV1);
  if ((state === "leased") !== (leaseOwner !== null && leaseExpiry !== null) ||
      (state === "complete") !== (completedAt !== null) ||
      (state !== "leased" && (leaseOwner !== null || leaseExpiry !== null))) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    effectIdV1: ad04OpaqueIdV1(data.effectIdV1),
    effectFingerprintV1: ad04HashV1(data.effectFingerprintV1),
    kindV1: data.kindV1,
    adapterIdV1,
    adapterVersionV1: ad04NamespaceV1(data.adapterVersionV1),
    stateV1: state,
    attemptsV1: ad04CounterV1(data.attemptsV1),
    leaseGenerationV1: ad04CounterV1(data.leaseGenerationV1),
    leaseOwnerV1: leaseOwner,
    leaseExpiresAtSecV1: leaseExpiry,
    nextAttemptAtSecV1: ad04CounterV1(data.nextAttemptAtSecV1),
    safeErrorCodeV1: data.safeErrorCodeV1 === null
      ? null : ad04NamespaceV1(data.safeErrorCodeV1),
    createdAtSecV1: ad04CounterV1(data.createdAtSecV1),
    completedAtSecV1: completedAt,
  });
}

export function parseCandidateEffectReceiptV1(
  value: unknown,
): CandidateDeletionEffectReceiptV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "internalJobId", "authProjectIdV2", "authTenantIdV2",
    "authUidV2", "generationHash", "acceptedLifecycleEpochV2", "effectIdV1",
    "effectFingerprintV1", "kindV1", "adapterIdV1", "outcomeV1",
    "evidenceCodeV1", "recordedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      !includesValue(deletionTaskKindsV1, data.kindV1) ||
      !includesValue([
        "applied", "alreadySatisfied", "notApplicable", "manualActionGuidance",
        "verifiedComplete",
      ] as const, data.outcomeV1)) ad04FailV1("AD04_INVALID_REQUEST");
  requireSchemaV1(data.schemaVersion);
  const adapterIdV1 = nullableOpaque(data.adapterIdV1);
  if ((data.kindV1 === "cleanupAdapter") !== (adapterIdV1 !== null)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return Object.freeze({
    schemaVersion: 1,
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    effectIdV1: ad04OpaqueIdV1(data.effectIdV1),
    effectFingerprintV1: ad04HashV1(data.effectFingerprintV1),
    kindV1: data.kindV1,
    adapterIdV1,
    outcomeV1: data.outcomeV1,
    evidenceCodeV1: ad04OpaqueIdV1(data.evidenceCodeV1),
    recordedAtSecV1: ad04CounterV1(data.recordedAtSecV1),
  });
}

export function parseCandidateProviderEventReceiptV1(
  value: unknown,
): CandidateProviderEventReceiptV1 {
  const data = ad04RecordV1(value);
  const keys = [
    "schemaVersion", "eventIdV1", "eventKindV1", "internalJobId",
    "authProjectIdV2", "authTenantIdV2", "authUidV2", "generationHash",
    "acceptedLifecycleEpochV2", "eventFingerprintV1", "recordedAtSecV1",
  ];
  if (data === null || !ad04ExactKeysV1(data, keys) ||
      !includesValue(["authOnDelete", "appleCredentialRevoked"] as const,
        data.eventKindV1)) ad04FailV1("AD04_INVALID_REQUEST");
  requireSchemaV1(data.schemaVersion);
  return Object.freeze({
    schemaVersion: 1,
    eventIdV1: ad04OpaqueIdV1(data.eventIdV1),
    eventKindV1: data.eventKindV1,
    internalJobId: ad04OpaqueIdV1(data.internalJobId),
    ...scopeFromRecord(data),
    generationHash: ad04HashV1(data.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(data.acceptedLifecycleEpochV2),
    eventFingerprintV1: ad04HashV1(data.eventFingerprintV1),
    recordedAtSecV1: ad04CounterV1(data.recordedAtSecV1),
  });
}

export function parseCandidateDeletionJobV1(value: unknown): AccountDeletionJobContract {
  try {
    return validateDeletionJob(value);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
}

export function parseCandidateStatusAliasV1(
  value: unknown,
): AccountDeletionStatusAliasContract {
  try {
    return validateStatusAlias(value);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
}

export function parseCandidateAdapterResultV1(value: unknown): AdapterResultContract {
  try {
    return validateAdapterResult(value);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
}

export function parseCandidateProviderCheckpointV1(
  value: unknown,
): ProviderCheckpointContract {
  try {
    return validateProviderCheckpoint(value);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
}

export function parseCandidateLifecycleContractV1(value: unknown): ReturnType<
  typeof validateAccountLifecycle
> {
  try {
    return validateAccountLifecycle(value);
  } catch {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
}

export function deletionInternalJobIdV1(scope: AuthIncarnationScopeV2, generationHash: string): string {
  return `job_${canonicalSha256({contract: "account-deletion-job-v1", ...ad04ScopeV1(scope),
    generationHash: ad04HashV1(generationHash)})}`;
}

export function deletionOperationReceiptIdV1(input: {
  scope: AuthIncarnationScopeV2;
  generationHash: string;
  operationId: string;
}): string {
  return `op_${canonicalSha256({contract: "account-deletion-operation-v1",
    ...ad04ScopeV1(input.scope), generationHash: ad04HashV1(input.generationHash),
    operationId: ad04OpaqueIdV1(input.operationId)})}`;
}

export function deletionTaskEffectIdV1(input: {
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  kindV1: DeletionTaskKindV1;
  adapterIdV1: string | null;
}): string {
  if (!includesValue(deletionTaskKindsV1, input.kindV1)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  if ((input.kindV1 === "cleanupAdapter") !== (input.adapterIdV1 !== null)) {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return `ef_${canonicalSha256({
    contract: "account-deletion-effect-v1",
    internalJobId: ad04OpaqueIdV1(input.internalJobId),
    generationHash: ad04HashV1(input.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(input.acceptedLifecycleEpochV2),
    kindV1: input.kindV1,
    adapterIdV1: input.adapterIdV1,
  })}`;
}

export function deletionTaskEffectFingerprintV1(input: {
  scope: AuthIncarnationScopeV2;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  kindV1: DeletionTaskKindV1;
  adapterIdV1: string | null;
  adapterVersionV1: string;
}): string {
  deletionTaskEffectIdV1(input);
  return canonicalSha256({
    contract: "account-deletion-task-v1",
    internalJobId: ad04OpaqueIdV1(input.internalJobId),
    ...ad04ScopeV1(input.scope),
    generationHash: ad04HashV1(input.generationHash),
    acceptedLifecycleEpochV2: ad04CounterV1(input.acceptedLifecycleEpochV2),
    kindV1: input.kindV1,
    adapterIdV1: input.adapterIdV1,
    adapterVersionV1: ad04NamespaceV1(input.adapterVersionV1),
  });
}

function fixedPath(root: string, id: string): string {
  return `${root}/${ad04OpaqueIdV1(id)}`;
}

function candidateAuthorityUidPathSegmentV1(uidValue: unknown): string {
  const uid = ad04FirebaseUidV1(uidValue);
  if (opaqueIdPattern.test(uid)) return uid;
  // `~` is outside the legacy opaque-ID alphabet, so this injective encoding
  // cannot collide with an existing legacy UID document ID. Encoding the
  // exact UTF-16 code units also keeps slash and Unicode UIDs path-safe.
  return `~ad04uid1~${firebaseUidUtf16LeBase64Url(uid)}`;
}

function candidateAuthorityPathV1(
  scopeValue: unknown,
  rootCollection: string,
  tenantCollection: string,
): string {
  const scope = ad04ScopeV1(scopeValue);
  const uid = candidateAuthorityUidPathSegmentV1(scope.authUidV2);
  return scope.authTenantIdV2 === null
    ? `${rootCollection}/${uid}`
    : `${tenantCollection}/${ad04OpaqueIdV1(scope.authTenantIdV2)}/users/${uid}`;
}

export function candidateAccountLifecycleAuthorityPathV1(scope: unknown): string {
  return candidateAuthorityPathV1(
    scope,
    "accountLifecycleV2Root",
    "accountLifecycleV2Tenants",
  );
}

export function candidateMembershipAuthorityPathV1(scope: unknown): string {
  return candidateAuthorityPathV1(
    scope,
    "membershipsV2Root",
    "membershipsV2Tenants",
  );
}

export function deletionIntentPathV1(intentId: string): string {
  return fixedPath("accountDeletionIntentsV1", intentId);
}

export function deletionJobPathV1(internalJobId: string): string {
  return fixedPath("accountDeletionJobsV1", internalJobId);
}

export function deletionJobBindingPathV1(internalJobId: string): string {
  return `${deletionJobPathV1(internalJobId)}/private/binding`;
}

export function deletionProviderBindingPathV1(internalJobId: string): string {
  return `${deletionJobPathV1(internalJobId)}/private/provider`;
}

export function deletionStatusAliasPathV1(requestId: string): string {
  return fixedPath("accountDeletionStatusV1", requestId);
}

export function deletionStatusControlPathV1(requestId: string): string {
  return fixedPath("accountDeletionStatusControlsV1", requestId);
}

export function deletionOperationReceiptPathV1(receiptId: string): string {
  return fixedPath("accountDeletionReceiptsV1", receiptId);
}

export function deletionRevocationMaterialPathV1(reference: string): string {
  return fixedPath("accountDeletionRevocationMaterialV1", reference);
}

export function deletionTaskPathV1(internalJobId: string, effectIdV1: string): string {
  return `${deletionJobPathV1(internalJobId)}/tasks/${ad04OpaqueIdV1(effectIdV1)}`;
}

export function deletionEffectReceiptPathV1(
  internalJobId: string,
  effectIdV1: string,
): string {
  return `${deletionJobPathV1(internalJobId)}/effectReceipts/${ad04OpaqueIdV1(effectIdV1)}`;
}

export function deletionAdapterResultPathV1(
  internalJobId: string,
  adapterId: string,
): string {
  if (!accountDeletionAdapterIds.includes(
    adapterId as typeof accountDeletionAdapterIds[number],
  )) ad04FailV1("AD04_INVALID_REQUEST");
  return `${deletionJobPathV1(internalJobId)}/adapterResults/${adapterId}`;
}

export function deletionProviderCheckpointPathV1(
  internalJobId: string,
  provider: "firebaseAuth" | "appleCredential",
): string {
  if (provider !== "firebaseAuth" && provider !== "appleCredential") {
    ad04FailV1("AD04_INVALID_REQUEST");
  }
  return `${deletionJobPathV1(internalJobId)}/providerCheckpoints/${provider}`;
}

export function deletionProviderEventReceiptPathV1(eventIdV1: string): string {
  return fixedPath("accountDeletionProviderEventsV1", eventIdV1);
}

export function deletionAlertPathV1(internalJobId: string, effectIdV1: string): string {
  ad04OpaqueIdV1(internalJobId);
  ad04OpaqueIdV1(effectIdV1);
  return `accountDeletionAlertsV1/alert_${createHash("sha256")
    .update(`${internalJobId}\0${effectIdV1}`)
    .digest("hex")}`;
}

export function initialDeletionTasksV1(input: {
  scope: AuthIncarnationScopeV2;
  internalJobId: string;
  generationHash: string;
  acceptedLifecycleEpochV2: number;
  nowSecV1: number;
}): readonly CandidateDeletionTaskV1[] {
  const scope = ad04ScopeV1(input.scope);
  const nowSecV1 = ad04CounterV1(input.nowSecV1);
  const definitions: Array<{
    kindV1: DeletionTaskKindV1;
    adapterIdV1: string | null;
    adapterVersionV1: string;
  }> = [
    {kindV1: "authDisable", adapterIdV1: null, adapterVersionV1: "firebase-auth-v1"},
    {kindV1: "authRevokeRefreshTokens", adapterIdV1: null,
      adapterVersionV1: "firebase-auth-v1"},
    {kindV1: "authDeleteSingleUser", adapterIdV1: null,
      adapterVersionV1: "firebase-auth-v1"},
    {kindV1: "authVerifyAbsence", adapterIdV1: null,
      adapterVersionV1: "firebase-auth-v1"},
    {kindV1: "appleCredentialDisposition", adapterIdV1: null,
      adapterVersionV1: "apple-credential-v1"},
    ...accountDeletionAdapterIds.map((adapterIdV1) => ({
      kindV1: "cleanupAdapter" as const,
      adapterIdV1,
      adapterVersionV1: "account-deletion-adapter-v1",
    })),
    {kindV1: "reconcileCompletion", adapterIdV1: null,
      adapterVersionV1: "account-deletion-reconcile-v1"},
  ];
  return Object.freeze(definitions.map((definition) => {
    const effectIdV1 = deletionTaskEffectIdV1({
      internalJobId: input.internalJobId,
      generationHash: input.generationHash,
      acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
      kindV1: definition.kindV1,
      adapterIdV1: definition.adapterIdV1,
    });
    return Object.freeze({
      schemaVersion: 1 as const,
      internalJobId: ad04OpaqueIdV1(input.internalJobId),
      ...scope,
      generationHash: ad04HashV1(input.generationHash),
      acceptedLifecycleEpochV2: ad04CounterV1(input.acceptedLifecycleEpochV2),
      effectIdV1,
      effectFingerprintV1: deletionTaskEffectFingerprintV1({
        scope,
        internalJobId: input.internalJobId,
        generationHash: input.generationHash,
        acceptedLifecycleEpochV2: input.acceptedLifecycleEpochV2,
        ...definition,
      }),
      ...definition,
      stateV1: "pending" as const,
      attemptsV1: 0,
      leaseGenerationV1: 0,
      leaseOwnerV1: null,
      leaseExpiresAtSecV1: null,
      nextAttemptAtSecV1: nowSecV1,
      safeErrorCodeV1: null,
      createdAtSecV1: nowSecV1,
      completedAtSecV1: null,
    });
  }));
}

export function retryDelaySecV1(attemptsV1: number): number {
  const attempts = ad04CounterV1(attemptsV1);
  return Math.min(
    ACCOUNT_DELETION_AD04_MAX_RETRY_SEC_V1,
    ACCOUNT_DELETION_AD04_INITIAL_RETRY_SEC_V1 *
      (2 ** Math.min(Math.max(0, attempts - 1), 5)),
  );
}

export function productionAccountDeletionActivationReadyV1(): false {
  return false;
}
