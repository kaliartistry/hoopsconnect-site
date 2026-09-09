import {createHash, timingSafeEqual} from "node:crypto";

import {canonicalSha256} from "./official_stats_contract";

/**
 * Disabled account-deletion contract for AD01.
 *
 * This module has no Firebase imports and is deliberately not exported from
 * the Functions runtime entrypoint. It defines schemas for later packets; it
 * does not delete, disable, revoke, read, or write anything.
 */
export const accountDeletionVersions = {
  schemaVersion: 1,
  domainVersion: "account-deletion-domain-v1",
  policyRegistryVersion: "unapproved",
  inventoryVersion: "account-deletion-adapter-inventory-v1",
  canonicalEncodingVersion: "official-stat-canonical-json-v1",
  fingerprintVersion: "account-deletion-fingerprint-v1",
  statusCapabilityVersion: "account-deletion-status-capability-v1",
} as const;

export const accountLifecycleStates = ["active", "deleting", "deleted"] as const;
export type AccountLifecycleState = typeof accountLifecycleStates[number];

export const deletionJobStates = [
  "accepted", "fencingExternalAccess", "inventory", "disposition", "verify",
  "retryWait", "needsAttention", "complete",
] as const;
export type DeletionJobState = typeof deletionJobStates[number];

export const resumeStages = [
  "fencingExternalAccess", "inventory", "disposition", "verify",
] as const;
export type ResumeStage = typeof resumeStages[number];

export const custodyChoices = [
  "ordinary", "transferThenDelete", "suspendToCustody",
] as const;
export type CustodyChoice = typeof custodyChoices[number];

export const custodyOutcomes = [
  "ordinary", "transferThenDelete", "suspendToCustody",
  "policyBlockedButDeletionMustReceiveOperationalResolution",
] as const;
export type CustodyOutcome = typeof custodyOutcomes[number];

export const associationCustodyStates = [
  "operating", "transferPending", "custodyRequired", "suspendedToCustody",
  "recoveryReview",
] as const;
export type AssociationCustodyState = typeof associationCustodyStates[number];

export const holdStates = ["none", "activeApproved", "releasePending", "unknown"] as const;
export type HoldState = typeof holdStates[number];

export const adapterApplicabilities = ["applicable", "notApplicable", "unknown"] as const;
export type AdapterApplicability = typeof adapterApplicabilities[number];

export const adapterResultStates = [
  "pending", "blocked", "complete", "notApplicable", "unsupported",
] as const;
export type AdapterResultState = typeof adapterResultStates[number];

export const dispositionActions = [
  "erase", "detach", "pseudonymize", "restrictedRetention",
  "accessRevokedAwaitingExpiry", "notApplicable", "unresolved",
] as const;
export type DispositionAction = typeof dispositionActions[number];

export const providerCheckpointStates = [
  "pending", "complete", "retryRequired", "manualActionGuidance",
  "notApplicable", "unknown",
] as const;
export type ProviderCheckpointState = typeof providerCheckpointStates[number];

export const providerNames = ["firebaseAuth", "appleCredential"] as const;
export type ProviderName = typeof providerNames[number];

export const statusAliasBindingKinds = [
  "winningOperation", "sameGenerationConvergence",
] as const;
export type StatusAliasBindingKind = typeof statusAliasBindingKinds[number];

export const authDeletionCheckpointStates = [
  "notScheduled", "scheduled", "retryRequired", "needsAttention", "complete",
] as const;
export type AuthDeletionCheckpointState = typeof authDeletionCheckpointStates[number];

export const deletionStatusPhases = [
  "processing", "accountRemovedCleanupPending", "attentionRequired", "complete",
] as const;
export type DeletionStatusPhase = typeof deletionStatusPhases[number];

export const idempotencyDecisions = [
  "acceptNew", "exactReplay", "attachStatusAlias", "conflict", "denyFenced",
] as const;
export type IdempotencyDecision = typeof idempotencyDecisions[number];

export type PolicyDecisionState =
  | "pendingAuthoritativeDecision"
  | "pendingOperationalProof"
  | "approved"
  | "rejected"
  | "superseded";

export const completionCheckpointNames = [
  "dataDispositionVerified", "publicPrivacyVerified", "custodyRecorded",
  "providerDispositionRecorded", "restoreSuppressionDurable",
] as const;

export interface AccountGeneration {
  authNamespace: string;
  accountId: string;
  authCreatedAt: Date;
}

export interface AccountLifecycleContract {
  schemaVersion: 1;
  state: AccountLifecycleState;
  epoch: number;
  generationHash: string;
  internalJobId: string | null;
  acceptedAt: Date | null;
  completedAt: Date | null;
}

export interface AccountDeletionJobContract {
  schemaVersion: 1;
  internalJobId: string;
  generationHash: string;
  state: DeletionJobState;
  resumeStage: ResumeStage | null;
  policyVersion: string;
  inventoryVersion: string;
  attempt: number;
  leaseGeneration: number;
  authorityFenceDurable: boolean;
  minimumCleanupReferencesCaptured: boolean;
  authDeletionCheckpointState: AuthDeletionCheckpointState;
  authAbsent: boolean;
  dataDispositionVerified: boolean;
  publicPrivacyVerified: boolean;
  custodyRecorded: boolean;
  providerDispositionRecorded: boolean;
  restoreSuppressionDurable: boolean;
  safeErrorCode: string | null;
}

export interface AccountDeletionStatusAliasContract {
  schemaVersion: 1;
  requestId: string;
  internalJobId: string;
  generationHash: string;
  acceptedSemanticFingerprint: string;
  bindingKind: StatusAliasBindingKind;
  purpose: "readOnlyDeletionStatus";
  statusSecretHash: string;
  createdAt: Date;
  expiryPolicyDecisionId: string;
}

export interface MinimalDeletionTombstoneContract {
  schemaVersion: 1;
  generationHmac: string;
  deletionEpoch: number;
  policyVersion: string;
  suppressionKeyVersion: string;
  acceptedAt: Date;
  completedAt: Date | null;
  minimumReplayCutoff: Date;
}

export interface ProviderCheckpointContract {
  schemaVersion: 1;
  provider: ProviderName;
  state: ProviderCheckpointState;
  evidenceCode: string;
  checkedAt: Date;
}

export interface AdapterResultContract {
  schemaVersion: 1;
  adapterId: string;
  applicability: AdapterApplicability;
  state: AdapterResultState;
  disposition: DispositionAction;
  policyDecisionState: PolicyDecisionState;
  policyDecisionId: string;
  policyVersion: string;
  holdState: HoldState;
  evidenceCode: string | null;
  evidenceRef: string;
  holdBoundaryAt: Date | null;
}

export interface PrepareDeletionRequest {
  schemaVersion: 1;
}

export interface RequestDeletion {
  schemaVersion: 1;
  intentId: string;
  policyVersion: string;
  impactVersion: string;
  operationId: string;
  requestId: string;
  statusSecretHash: string;
  confirmation: "deleteAccount";
  custodyChoice: CustodyChoice;
  providerRevocationRef?: string;
}

export interface DeletionStatusRequest {
  schemaVersion: 1;
  requestId: string;
  statusSecret: string;
}

export interface DeletionCompletionInput {
  schemaVersion: 1;
  authAbsent: boolean;
  checkpoints: {
    dataDispositionVerified: boolean;
    publicPrivacyVerified: boolean;
    custodyRecorded: boolean;
    providerDispositionRecorded: boolean;
    restoreSuppressionDurable: boolean;
  };
  requiredAdapterIds: readonly string[];
  adapterResults: readonly AdapterResultContract[];
  providerCheckpoints: readonly ProviderCheckpointContract[];
  unknownRequiredState: boolean;
}

export const submittedOperationStatusResolutions = [
  "notAttempted", "accepted", "notAccepted", "unresolved",
] as const;
export type SubmittedOperationStatusResolution =
  typeof submittedOperationStatusResolutions[number];

const opaqueId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const namespaceId = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const sha256Hex = /^[0-9a-f]{64}$/;
const base64Url32 = /^[A-Za-z0-9_-]{43}$/;

function requireRecord(value: unknown, name: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError(`${name} must be a plain record`);
  }
  return value as Record<string, unknown>;
}

function assertExactKeys(
  record: Readonly<Record<string, unknown>>,
  required: readonly string[],
  optional: readonly string[] = [],
): void {
  const allowed = new Set([...required, ...optional]);
  const keys = Object.keys(record);
  for (const key of required) {
    if (!Object.prototype.hasOwnProperty.call(record, key)) {
      throw new TypeError(`Missing required field: ${key}`);
    }
  }
  for (const key of keys) {
    if (!allowed.has(key)) throw new TypeError(`Unknown field: ${key}`);
  }
}

function requireOpaqueId(field: string, value: unknown): asserts value is string {
  if (typeof value !== "string" || !opaqueId.test(value)) {
    throw new TypeError(`${field} must be an opaque 1-128 character ID`);
  }
}

function requireFirebaseUid(value: unknown): asserts value is string {
  // Firebase Admin accepts any non-empty UID of at most 128 JavaScript
  // characters. Do not narrow or normalize that provider-owned identity.
  if (typeof value !== "string" || value.length === 0 || value.length > 128) {
    throw new TypeError("accountId must be a valid Firebase UID");
  }
}

function requireHash(field: string, value: unknown): asserts value is string {
  if (typeof value !== "string" || !sha256Hex.test(value)) {
    throw new TypeError(`${field} must be lowercase SHA-256 hex`);
  }
}

export function decodeWireSafeInteger(
  field: string,
  value: unknown,
  options: {nonnegative?: boolean} = {},
): number {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      !Number.isSafeInteger(value) || (options.nonnegative === true && value < 0)) {
    throw new TypeError(
      `${field} must be a${options.nonnegative === true ? " nonnegative" : ""} finite safe integer`,
    );
  }
  return Object.is(value, -0) ? 0 : value;
}

function requireSchemaVersion(value: unknown): void {
  if (decodeWireSafeInteger("schemaVersion", value, {nonnegative: true}) !== 1) {
    throw new TypeError("Unsupported schemaVersion");
  }
}

function requireValidDate(field: string, value: unknown): asserts value is Date {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
    throw new TypeError(`${field} must be a valid Date`);
  }
}

function includesValue<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === "string" && (values as readonly string[]).includes(value);
}

export const accountLifecycleTransitions = new Set([
  "active->deleting", "deleting->deleted",
]);

export const deletionJobTransitions = new Set([
  "accepted->fencingExternalAccess", "accepted->retryWait", "accepted->needsAttention",
  "fencingExternalAccess->inventory", "fencingExternalAccess->retryWait", "fencingExternalAccess->needsAttention",
  "inventory->disposition", "inventory->retryWait", "inventory->needsAttention",
  "disposition->verify", "disposition->retryWait", "disposition->needsAttention",
  "verify->complete", "verify->retryWait", "verify->needsAttention",
  "retryWait->fencingExternalAccess", "retryWait->inventory", "retryWait->disposition", "retryWait->verify", "retryWait->needsAttention",
  "needsAttention->fencingExternalAccess", "needsAttention->inventory", "needsAttention->disposition", "needsAttention->verify", "needsAttention->retryWait",
]);

export function canTransitionAccountLifecycle(
  from: AccountLifecycleState,
  to: AccountLifecycleState,
): boolean {
  return accountLifecycleTransitions.has(`${from}->${to}`);
}

export function canTransitionDeletionJob(
  from: DeletionJobState,
  to: DeletionJobState,
): boolean {
  return deletionJobTransitions.has(`${from}->${to}`);
}

export function validatePrepareDeletionRequest(value: unknown): PrepareDeletionRequest {
  const record = requireRecord(value, "PrepareDeletionRequest");
  assertExactKeys(record, ["schemaVersion"]);
  requireSchemaVersion(record.schemaVersion);
  return record as unknown as PrepareDeletionRequest;
}

export function validateRequestDeletion(value: unknown): RequestDeletion {
  const record = requireRecord(value, "RequestDeletion");
  assertExactKeys(record, [
    "schemaVersion", "intentId", "policyVersion", "impactVersion", "operationId",
    "requestId", "statusSecretHash", "confirmation", "custodyChoice",
  ], ["providerRevocationRef"]);
  requireSchemaVersion(record.schemaVersion);
  for (const field of ["intentId", "policyVersion", "impactVersion", "operationId", "requestId"]) {
    requireOpaqueId(field, record[field]);
  }
  requireHash("statusSecretHash", record.statusSecretHash);
  if (record.confirmation !== "deleteAccount") throw new TypeError("Irreversible confirmation is required");
  if (!includesValue(custodyChoices, record.custodyChoice)) throw new TypeError("Invalid custodyChoice");
  if (record.providerRevocationRef !== undefined) {
    requireOpaqueId("providerRevocationRef", record.providerRevocationRef);
  }
  return record as unknown as RequestDeletion;
}

export function validateDeletionStatusRequest(value: unknown): DeletionStatusRequest {
  const record = requireRecord(value, "DeletionStatusRequest");
  assertExactKeys(record, ["schemaVersion", "requestId", "statusSecret"]);
  requireSchemaVersion(record.schemaVersion);
  requireOpaqueId("requestId", record.requestId);
  decodeStatusSecret(record.statusSecret);
  return record as unknown as DeletionStatusRequest;
}

export function validateStatusAlias(value: unknown): AccountDeletionStatusAliasContract {
  const record = requireRecord(value, "AccountDeletionStatusAliasContract");
  assertExactKeys(record, [
    "schemaVersion", "requestId", "internalJobId", "generationHash",
    "acceptedSemanticFingerprint", "bindingKind", "purpose",
    "statusSecretHash", "createdAt", "expiryPolicyDecisionId",
  ]);
  requireSchemaVersion(record.schemaVersion);
  requireOpaqueId("requestId", record.requestId);
  requireOpaqueId("internalJobId", record.internalJobId);
  requireHash("generationHash", record.generationHash);
  requireHash("acceptedSemanticFingerprint", record.acceptedSemanticFingerprint);
  if (!includesValue(statusAliasBindingKinds, record.bindingKind)) {
    throw new TypeError("Invalid status alias bindingKind");
  }
  if (record.purpose !== "readOnlyDeletionStatus") {
    throw new TypeError("Status aliases are read-only deletion status capabilities");
  }
  requireHash("statusSecretHash", record.statusSecretHash);
  requireValidDate("createdAt", record.createdAt);
  if (typeof record.expiryPolicyDecisionId !== "string" ||
      !namespaceId.test(record.expiryPolicyDecisionId)) {
    throw new TypeError("expiryPolicyDecisionId must be a versioned policy reference");
  }
  return record as unknown as AccountDeletionStatusAliasContract;
}

export function validateMinimalTombstone(value: unknown): MinimalDeletionTombstoneContract {
  const record = requireRecord(value, "MinimalDeletionTombstoneContract");
  assertExactKeys(record, [
    "schemaVersion", "generationHmac", "deletionEpoch", "policyVersion",
    "suppressionKeyVersion", "acceptedAt", "completedAt", "minimumReplayCutoff",
  ]);
  requireSchemaVersion(record.schemaVersion);
  requireHash("generationHmac", record.generationHmac);
  decodeWireSafeInteger("deletionEpoch", record.deletionEpoch, {nonnegative: true});
  requireOpaqueId("policyVersion", record.policyVersion);
  requireOpaqueId("suppressionKeyVersion", record.suppressionKeyVersion);
  for (const field of ["acceptedAt", "minimumReplayCutoff"] as const) {
    requireValidDate(field, record[field]);
  }
  if (record.completedAt !== null &&
      (!(record.completedAt instanceof Date) || !Number.isFinite(record.completedAt.getTime()))) {
    throw new TypeError("completedAt must be a valid Date or null");
  }
  const acceptedAt = record.acceptedAt as Date;
  const minimumReplayCutoff = record.minimumReplayCutoff as Date;
  if ((record.completedAt !== null && (record.completedAt as Date) < acceptedAt) ||
      minimumReplayCutoff < acceptedAt) {
    throw new TypeError("Tombstone timestamps violate lifecycle chronology");
  }
  return record as unknown as MinimalDeletionTombstoneContract;
}

export function validateAccountLifecycle(value: unknown): AccountLifecycleContract {
  const record = requireRecord(value, "AccountLifecycleContract");
  assertExactKeys(record, [
    "schemaVersion", "state", "epoch", "generationHash", "internalJobId",
    "acceptedAt", "completedAt",
  ]);
  requireSchemaVersion(record.schemaVersion);
  if (!includesValue(accountLifecycleStates, record.state)) {
    throw new TypeError("Invalid lifecycle version or state");
  }
  decodeWireSafeInteger("epoch", record.epoch, {nonnegative: true});
  requireHash("generationHash", record.generationHash);
  if (record.internalJobId !== null) requireOpaqueId("internalJobId", record.internalJobId);
  if (record.acceptedAt !== null) requireValidDate("acceptedAt", record.acceptedAt);
  if (record.completedAt !== null) requireValidDate("completedAt", record.completedAt);
  if (record.acceptedAt !== null && record.completedAt !== null &&
      record.completedAt < record.acceptedAt) {
    throw new TypeError("completedAt cannot precede acceptedAt");
  }
  if (record.state === "active" && (record.internalJobId !== null || record.acceptedAt !== null || record.completedAt !== null)) {
    throw new TypeError("Active lifecycle cannot carry deletion state");
  }
  if (record.state === "deleting" && (record.internalJobId === null || record.acceptedAt === null || record.completedAt !== null)) {
    throw new TypeError("Deleting lifecycle requires job and acceptance only");
  }
  if (record.state === "deleted" && (record.internalJobId === null || record.acceptedAt === null || record.completedAt === null)) {
    throw new TypeError("Deleted lifecycle requires terminal evidence");
  }
  return record as unknown as AccountLifecycleContract;
}

export function validateDeletionJob(value: unknown): AccountDeletionJobContract {
  const record = requireRecord(value, "AccountDeletionJobContract");
  assertExactKeys(record, [
    "schemaVersion", "internalJobId", "generationHash", "state", "resumeStage",
    "policyVersion", "inventoryVersion", "attempt", "leaseGeneration",
    "authorityFenceDurable", "minimumCleanupReferencesCaptured",
    "authDeletionCheckpointState", "authAbsent", "dataDispositionVerified",
    "publicPrivacyVerified", "custodyRecorded", "providerDispositionRecorded",
    "restoreSuppressionDurable", "safeErrorCode",
  ]);
  requireSchemaVersion(record.schemaVersion);
  if (!includesValue(deletionJobStates, record.state)) {
    throw new TypeError("Invalid deletion job version or state");
  }
  requireOpaqueId("internalJobId", record.internalJobId);
  requireHash("generationHash", record.generationHash);
  requireOpaqueId("policyVersion", record.policyVersion);
  if (record.inventoryVersion !== accountDeletionVersions.inventoryVersion) throw new TypeError("Unknown inventory version");
  decodeWireSafeInteger("attempt", record.attempt, {nonnegative: true});
  decodeWireSafeInteger("leaseGeneration", record.leaseGeneration, {nonnegative: true});
  if (!includesValue(authDeletionCheckpointStates, record.authDeletionCheckpointState)) {
    throw new TypeError("Invalid authDeletionCheckpointState");
  }
  const needsResume = record.state === "retryWait" || record.state === "needsAttention";
  if ((needsResume && !includesValue(resumeStages, record.resumeStage)) ||
      (!needsResume && record.resumeStage !== null)) {
    throw new TypeError("retryWait/needsAttention require an exact resumeStage and other states forbid it");
  }
  const completionFields = [
    "authorityFenceDurable", "minimumCleanupReferencesCaptured",
    "authAbsent", "dataDispositionVerified", "publicPrivacyVerified", "custodyRecorded",
    "providerDispositionRecorded", "restoreSuppressionDurable",
  ] as const;
  for (const field of completionFields) {
    if (typeof record[field] !== "boolean") throw new TypeError(`${field} must be boolean`);
  }
  if (record.safeErrorCode !== null &&
      (typeof record.safeErrorCode !== "string" ||
       !Object.prototype.hasOwnProperty.call(accountDeletionErrorPolicies, record.safeErrorCode))) {
    throw new TypeError("safeErrorCode must be a stable external deletion error or null");
  }
  if (record.authorityFenceDurable === true &&
      record.minimumCleanupReferencesCaptured === true &&
      record.authAbsent === false && record.authDeletionCheckpointState === "notScheduled") {
    throw new TypeError("Auth deletion must be scheduled independently after its durable preconditions");
  }
  if (record.authAbsent === true && record.authDeletionCheckpointState !== "complete") {
    throw new TypeError("Verified Auth absence requires a complete Auth checkpoint");
  }
  if (record.authDeletionCheckpointState === "complete" && record.authAbsent !== true) {
    throw new TypeError("A complete Auth checkpoint requires verified Auth absence");
  }
  if (record.state === "complete" &&
      (!completionFields.every((field) => record[field] === true) ||
       record.authDeletionCheckpointState !== "complete" || record.safeErrorCode !== null)) {
    throw new TypeError("Complete jobs require every summary checkpoint and no error");
  }
  return record as unknown as AccountDeletionJobContract;
}

export function accountGenerationHash(generation: AccountGeneration): string {
  if (!namespaceId.test(generation.authNamespace)) throw new TypeError("Invalid auth namespace");
  requireFirebaseUid(generation.accountId);
  if (!(generation.authCreatedAt instanceof Date) || !Number.isFinite(generation.authCreatedAt.getTime())) {
    throw new TypeError("authCreatedAt must be a valid Date");
  }
  return canonicalSha256({
    accountIdUtf16LeBase64Url: firebaseUidUtf16LeBase64Url(generation.accountId),
    authCreatedAt: generation.authCreatedAt,
    authNamespace: generation.authNamespace,
  });
}

export function firebaseUidUtf16LeBase64Url(uid: string): string {
  requireFirebaseUid(uid);
  return Buffer.from(uid, "utf16le").toString("base64url");
}

export function semanticFingerprintInput(
  request: RequestDeletion,
  generation: AccountGeneration,
): Readonly<Record<string, unknown>> {
  return {
    accountGeneration: accountGenerationHash(generation),
    accountIdUtf16LeBase64Url: firebaseUidUtf16LeBase64Url(generation.accountId),
    authNamespace: generation.authNamespace,
    confirmation: request.confirmation,
    custodyChoice: request.custodyChoice,
    impactVersion: request.impactVersion,
    policyVersion: request.policyVersion,
    schemaVersion: request.schemaVersion,
  };
}

export function semanticFingerprint(request: RequestDeletion, generation: AccountGeneration): string {
  validateRequestDeletion(request);
  return canonicalSha256(semanticFingerprintInput(request, generation));
}

export function operationEnvelopeInput(
  request: RequestDeletion,
  semanticHash: string,
): Readonly<Record<string, unknown>> {
  requireHash("semanticFingerprint", semanticHash);
  return {
    operationId: request.operationId,
    requestId: request.requestId,
    semanticFingerprint: semanticHash,
    statusSecretHash: request.statusSecretHash,
  };
}

export function operationEnvelopeFingerprint(
  request: RequestDeletion,
  semanticHash: string,
): string {
  validateRequestDeletion(request);
  return canonicalSha256(operationEnvelopeInput(request, semanticHash));
}

export function decodeStatusSecret(value: unknown): Buffer {
  if (typeof value !== "string" || !base64Url32.test(value)) {
    throw new TypeError("statusSecret must be canonical unpadded base64url for 32 bytes");
  }
  const decoded = Buffer.from(value, "base64url");
  if (decoded.length !== 32 || decoded.toString("base64url") !== value) {
    throw new TypeError("statusSecret must decode canonically to exactly 32 bytes");
  }
  return decoded;
}

export function statusSecretHash(value: string): string {
  return createHash("sha256").update(decodeStatusSecret(value)).digest("hex");
}

export function statusSecretMatches(value: string, expectedHash: string): boolean {
  requireHash("expectedHash", expectedHash);
  const actual = Buffer.from(statusSecretHash(value), "hex");
  return timingSafeEqual(actual, Buffer.from(expectedHash, "hex"));
}

export interface IdempotencyEvaluationInput {
  hasJob: boolean;
  sameOperation: boolean;
  sameSemantic: boolean;
  sameEnvelope: boolean;
  authenticatedSameGeneration: boolean;
  lifecycle: AccountLifecycleState;
}

export function evaluateIdempotency(input: IdempotencyEvaluationInput): IdempotencyDecision {
  if (!input.authenticatedSameGeneration) {
    return input.lifecycle === "active" ? "conflict" : "denyFenced";
  }
  if (!input.hasJob) {
    return input.lifecycle === "active" ? "acceptNew" : "denyFenced";
  }
  if (input.sameOperation) {
    return input.sameSemantic && input.sameEnvelope ? "exactReplay" : "conflict";
  }
  return "attachStatusAlias";
}

const statusFirstFailureCodes = new Set([
  "AD_UNAUTHENTICATED", "AD_REAUTH_REQUIRED", "AD_APP_ATTESTATION_REQUIRED",
]);

export function resolveSubmittedOperationFailure(input: {
  errorCode: AccountDeletionErrorCode;
  hasPersistedRequestMaterial: boolean;
  statusResolution: SubmittedOperationStatusResolution;
}): AccountDeletionErrorCode {
  if (!statusFirstFailureCodes.has(input.errorCode) ||
      input.hasPersistedRequestMaterial !== true) return input.errorCode;
  if (input.statusResolution === "accepted") return "AD_ALREADY_ACCEPTED";
  if (input.statusResolution === "notAccepted") return input.errorCode;
  if (input.statusResolution === "unresolved") return "AD_STATUS_UNAVAILABLE";
  return "AD_ACCEPTANCE_UNKNOWN";
}

export function canReplayGrant(input: {
  lifecycle: AccountLifecycleState;
  generationMatches: boolean;
  epochMatches: boolean;
  capabilityPresent: boolean;
}): boolean {
  return input.lifecycle === "active" && input.generationMatches &&
    input.epochMatches && input.capabilityPresent;
}

export function validateAdapterResult(value: unknown): AdapterResultContract {
  const result = requireRecord(value, "AdapterResultContract");
  assertExactKeys(result, [
    "schemaVersion", "adapterId", "applicability", "state", "disposition",
    "policyDecisionState", "policyDecisionId", "policyVersion", "holdState",
    "evidenceCode", "evidenceRef", "holdBoundaryAt",
  ]);
  requireSchemaVersion(result.schemaVersion);
  requireOpaqueId("adapterId", result.adapterId);
  if (!includesValue(adapterApplicabilities, result.applicability) ||
      !includesValue(adapterResultStates, result.state) ||
      !includesValue(dispositionActions, result.disposition) ||
      !includesValue(holdStates, result.holdState) ||
      typeof result.policyDecisionState !== "string" ||
      !["pendingAuthoritativeDecision", "pendingOperationalProof", "approved", "rejected", "superseded"]
        .includes(result.policyDecisionState)) {
    throw new TypeError("Invalid adapter result state");
  }
  requireOpaqueId("policyVersion", result.policyVersion);
  if (typeof result.policyDecisionId !== "string" || !namespaceId.test(result.policyDecisionId)) {
    throw new TypeError("policyDecisionId must be a versioned policy reference");
  }
  if (result.evidenceCode !== null) requireOpaqueId("evidenceCode", result.evidenceCode);
  requireOpaqueId("evidenceRef", result.evidenceRef);
  if (result.holdBoundaryAt !== null) requireValidDate("holdBoundaryAt", result.holdBoundaryAt);
  return result as unknown as AdapterResultContract;
}

export function validateProviderCheckpoint(value: unknown): ProviderCheckpointContract {
  const checkpoint = requireRecord(value, "ProviderCheckpointContract");
  assertExactKeys(checkpoint, [
    "schemaVersion", "provider", "state", "evidenceCode", "checkedAt",
  ]);
  requireSchemaVersion(checkpoint.schemaVersion);
  if (!includesValue(providerNames, checkpoint.provider) ||
      !includesValue(providerCheckpointStates, checkpoint.state)) {
    throw new TypeError("Invalid provider checkpoint state");
  }
  requireOpaqueId("evidenceCode", checkpoint.evidenceCode);
  requireValidDate("checkedAt", checkpoint.checkedAt);
  return checkpoint as unknown as ProviderCheckpointContract;
}

export function validateDeletionCompletionInput(value: unknown): DeletionCompletionInput {
  const input = requireRecord(value, "DeletionCompletionInput");
  assertExactKeys(input, [
    "schemaVersion", "authAbsent", "checkpoints", "requiredAdapterIds",
    "adapterResults", "providerCheckpoints", "unknownRequiredState",
  ]);
  requireSchemaVersion(input.schemaVersion);
  if (typeof input.authAbsent !== "boolean" ||
      typeof input.unknownRequiredState !== "boolean") {
    throw new TypeError("Completion envelope predicates must be boolean");
  }
  const checkpoints = requireRecord(input.checkpoints, "DeletionCompletionInput.checkpoints");
  assertExactKeys(checkpoints, completionCheckpointNames);
  for (const field of completionCheckpointNames) {
    if (typeof checkpoints[field] !== "boolean") {
      throw new TypeError(`${field} must be boolean`);
    }
  }
  if (!Array.isArray(input.requiredAdapterIds) ||
      !input.requiredAdapterIds.every((id) => typeof id === "string") ||
      !Array.isArray(input.adapterResults) || !Array.isArray(input.providerCheckpoints)) {
    throw new TypeError("Completion inventory and checkpoints must be arrays");
  }
  input.adapterResults.forEach(validateAdapterResult);
  input.providerCheckpoints.forEach(validateProviderCheckpoint);
  return input as unknown as DeletionCompletionInput;
}

export function authDeletionScheduleRequired(input: {
  authorityFenceDurable: boolean;
  minimumCleanupReferencesCaptured: boolean;
  authAbsent: boolean;
  hasUnknownAdapter: boolean;
  retentionClassificationResolved: boolean;
  custodyResolved: boolean;
}): boolean {
  return input.authorityFenceDurable === true &&
    input.minimumCleanupReferencesCaptured === true && input.authAbsent === false;
}

function adapterDispositionComplete(result: AdapterResultContract): boolean {
  try {
    validateAdapterResult(result);
  } catch {
    return false;
  }
  if (!accountDeletionAdapterIds.includes(result.adapterId as typeof accountDeletionAdapterIds[number]) ||
      !includesValue(adapterApplicabilities, result.applicability) ||
      !includesValue(adapterResultStates, result.state) ||
      !includesValue(dispositionActions, result.disposition) ||
      !includesValue(holdStates, result.holdState) ||
      result.policyDecisionState !== "approved" ||
      result.policyDecisionId !== `retention.${result.adapterId}` ||
      !namespaceId.test(result.policyDecisionId) ||
      typeof result.policyVersion !== "string" || !opaqueId.test(result.policyVersion) ||
      typeof result.evidenceCode !== "string" || !opaqueId.test(result.evidenceCode) ||
      typeof result.evidenceRef !== "string" || !opaqueId.test(result.evidenceRef) ||
      result.applicability === "unknown" || result.holdState === "unknown") return false;
  if (result.state === "notApplicable") {
    return result.applicability === "notApplicable" &&
      result.disposition === "notApplicable" && result.holdState === "none" &&
      result.holdBoundaryAt === null;
  }
  if (result.applicability !== "applicable" || result.state !== "complete" ||
      result.disposition === "unresolved" || result.disposition === "notApplicable") return false;
  if (result.disposition === "restrictedRetention") {
    return result.holdState === "activeApproved" && result.holdBoundaryAt instanceof Date;
  }
  return result.holdState === "none" && result.holdBoundaryAt === null;
}

export function isProviderCheckpointTerminal(checkpoint: ProviderCheckpointContract): boolean {
  try {
    validateProviderCheckpoint(checkpoint);
  } catch {
    return false;
  }
  if (checkpoint.provider === "firebaseAuth") return checkpoint.state === "complete";
  if (checkpoint.provider !== "appleCredential") return false;
  return checkpoint.state === "complete" || checkpoint.state === "notApplicable" ||
    checkpoint.state === "manualActionGuidance";
}

export function isDeletionComplete(input: DeletionCompletionInput): boolean {
  try {
    validateDeletionCompletionInput(input);
  } catch {
    return false;
  }
  if (input.authAbsent !== true || input.unknownRequiredState !== false) return false;
  const checkpointKeys = Object.keys(input.checkpoints);
  if (checkpointKeys.length !== completionCheckpointNames.length ||
      !completionCheckpointNames.every((field) => input.checkpoints[field] === true)) return false;
  if (input.requiredAdapterIds.length !== accountDeletionAdapterIds.length ||
      !accountDeletionAdapterIds.every((id, index) => input.requiredAdapterIds[index] === id) ||
      input.adapterResults.length !== accountDeletionAdapterIds.length) return false;
  if (input.providerCheckpoints.length !== providerNames.length) return false;
  const providerResults = new Map<string, ProviderCheckpointContract>();
  for (const checkpoint of input.providerCheckpoints) {
    if (providerResults.has(checkpoint.provider) ||
        !isProviderCheckpointTerminal(checkpoint)) return false;
    providerResults.set(checkpoint.provider, checkpoint);
  }
  if (!providerNames.every((provider) => providerResults.has(provider))) return false;
  const results = new Map<string, AdapterResultContract>();
  for (const result of input.adapterResults) {
    if (results.has(result.adapterId)) return false;
    results.set(result.adapterId, result);
  }
  return accountDeletionAdapterIds.every((adapterId) => {
    const result = results.get(adapterId);
    return result !== undefined && adapterDispositionComplete(result);
  });
}

export function selfDeletionEligible(input: {
  authenticatedSameGeneration: boolean;
  hasProfile: boolean;
  hasMembership: boolean;
  legacyRole: string | null;
}): boolean {
  void input.hasProfile;
  void input.hasMembership;
  void input.legacyRole;
  return input.authenticatedSameGeneration;
}

export function resolveCustodyOutcome(input: {
  isLastRecoverableOwner: boolean;
  transferVerified: boolean;
  namedCustodyAvailable: boolean;
}): CustodyOutcome {
  if (!input.isLastRecoverableOwner) return "ordinary";
  if (input.transferVerified) return "transferThenDelete";
  if (input.namedCustodyAvailable) return "suspendToCustody";
  return "policyBlockedButDeletionMustReceiveOperationalResolution";
}

export const accountDeletionAdapterIds = [
  "firebase_auth_identity", "user_profile", "memberships_capabilities",
  "device_fcm_preferences", "notification_inbox", "team_assignments",
  "pending_invites", "historical_invites", "authorization_evidence",
  "personal_ugc", "official_notices", "acknowledgements", "event_attribution",
  "account_person_claims", "person_identity_evidence", "legacy_player_identity",
  "legacy_game_evidence", "v2_journal_operations", "local_offline_journal",
  "v2_certified_evidence", "public_projections_exports", "personal_storage_media",
  "shared_association_media", "device_local_state", "diagnostics_processors",
  "backups_restores", "deletion_operational_residue",
] as const;

export type AccountDeletionErrorCode = keyof typeof accountDeletionErrorPolicies;
export type AccountDeletionRetryClass =
  | "never"
  | "resolveSavedStatusBeforeNewAuthentication"
  | "refreshImpactThenCreateNewOperation"
  | "returnBoundStatusAlias"
  | "operatorResolutionRequired"
  | "retrySameOperation"
  | "resolveStatusThenRetrySameOperation"
  | "useExistingReceiptOrVerifiedRecovery";
export type AccountDeletionIdempotencyClass =
  | "notAccepted"
  | "acceptanceUnknownUnlessStatusResolved"
  | "sameKeyDifferentPayloadRejected"
  | "safeReplayReturnsOriginalAcceptance"
  | "notAcceptedUnlessReceiptExists"
  | "mayAlreadyBeAccepted"
  | "noMutation"
  | "acceptedJobRemainsFenced";

export const accountDeletionErrorPolicies = {
  AD_UNAUTHENTICATED: {transport: "unauthenticated", retry: "resolveSavedStatusBeforeNewAuthentication", idempotency: "acceptanceUnknownUnlessStatusResolved"},
  AD_REAUTH_REQUIRED: {transport: "unauthenticated", retry: "resolveSavedStatusBeforeNewAuthentication", idempotency: "acceptanceUnknownUnlessStatusResolved"},
  AD_IDENTITY_MISMATCH: {transport: "permission-denied", retry: "never", idempotency: "notAccepted"},
  AD_APP_ATTESTATION_REQUIRED: {transport: "failed-precondition", retry: "resolveSavedStatusBeforeNewAuthentication", idempotency: "acceptanceUnknownUnlessStatusResolved"},
  AD_INVALID_REQUEST: {transport: "invalid-argument", retry: "never", idempotency: "notAccepted"},
  AD_INTENT_EXPIRED: {transport: "failed-precondition", retry: "refreshImpactThenCreateNewOperation", idempotency: "notAccepted"},
  AD_IMPACT_CHANGED: {transport: "failed-precondition", retry: "refreshImpactThenCreateNewOperation", idempotency: "notAccepted"},
  AD_OPERATION_CONFLICT: {transport: "already-exists", retry: "never", idempotency: "sameKeyDifferentPayloadRejected"},
  AD_ALREADY_ACCEPTED: {transport: "success", retry: "returnBoundStatusAlias", idempotency: "safeReplayReturnsOriginalAcceptance"},
  AD_ACCEPTANCE_UNKNOWN: {transport: "acceptance-unknown", retry: "resolveSavedStatusBeforeNewAuthentication", idempotency: "mayAlreadyBeAccepted"},
  AD_TRANSFER_NOT_READY: {transport: "failed-precondition", retry: "operatorResolutionRequired", idempotency: "notAccepted"},
  AD_POLICY_NOT_READY: {transport: "failed-precondition", retry: "operatorResolutionRequired", idempotency: "notAccepted"},
  AD_RATE_LIMITED: {transport: "resource-exhausted", retry: "retrySameOperation", idempotency: "notAcceptedUnlessReceiptExists"},
  AD_TEMPORARILY_UNAVAILABLE: {transport: "unavailable", retry: "resolveStatusThenRetrySameOperation", idempotency: "mayAlreadyBeAccepted"},
  AD_STATUS_UNAVAILABLE: {transport: "uniform-status-error", retry: "useExistingReceiptOrVerifiedRecovery", idempotency: "noMutation"},
  AD_REVIEW_REQUIRED: {transport: "accepted-status", retry: "operatorResolutionRequired", idempotency: "acceptedJobRemainsFenced"},
} as const satisfies Readonly<Record<string, {
  transport: string;
  retry: AccountDeletionRetryClass;
  idempotency: AccountDeletionIdempotencyClass;
}>>;

export const internalDeletionErrorCodes = [
  "AUTH_DELETE_RETRY", "MEDIA_VERSION_CONFLICT", "RETENTION_CLASS_UNKNOWN",
  "REFERENCE_REMAINS", "CUSTODY_CONFLICT", "UNSUPPORTED_REQUIRED_ADAPTER",
] as const;
