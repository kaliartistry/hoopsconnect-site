import {createHash} from "node:crypto";

export const officialStatVersions = {
  authorizationSchemaVersion: 2,
  canonicalEncodingVersion: "official-stat-canonical-json-v1",
  commandSchemaVersion: 2,
  dataSchemaVersion: 2,
  domainSchemaVersion: 2,
  projectionSchemaVersion: 2,
} as const;

export const playStates = [
  "scheduled", "postponed", "inProgress", "suspended", "completed",
  "cancelled", "administrativelyTerminated",
] as const;
export type PlayState = typeof playStates[number];

export const reviewStates = [
  "draft", "submitted", "underReview", "changesRequested", "certified",
] as const;
export type ReviewState = typeof reviewStates[number];

export const publicationStates = [
  "absent", "published", "superseded", "retracted",
] as const;
export type PublicationState = typeof publicationStates[number];

export const resultDispositions = [
  "played", "forfeit", "default", "annulled", "otherAdjudicated",
] as const;
export type ResultDisposition = typeof resultDispositions[number];

export const statisticsDispositions = [
  "complete", "resultOnly", "excluded",
] as const;
export type StatisticsDisposition = typeof statisticsDispositions[number];

export const privacyPermissionStates = [
  "unknown", "permitted", "denied", "revoked",
] as const;
export type PrivacyPermissionState = typeof privacyPermissionStates[number];

export interface GameScope {
  associationId: string;
  competitionId: string;
  seasonId: string;
  divisionId: string;
  phaseId: string;
  gameId: string;
}

export interface VersionReference {
  associationId: string;
  versionId: string;
  sha256: string;
}

export interface TemporalInterval {
  effectiveFrom: Date;
  effectiveTo: ExplicitFact<Date>;
  recordedAt: Date;
}

export const temporalOpenEndedReasonCode = "open_ended" as const;

export interface PersonIdentityContract {
  associationId: string;
  personId: string;
  status: "provisional" | "verified" | "restricted" | "merged" | "archived";
  identityVersionId: string;
  restrictedEvidenceRefs: readonly string[];
}

export interface PlayerIdentityContract {
  associationId: string;
  playerId: string;
  personId: string;
  displayNameVersionId: string;
  status: "provisional" | "verified" | "merged" | "suspended" | "archived";
}

export interface TeamIdentityContract {
  associationId: string;
  teamId: string;
  identityVersionId: string;
  status: "active" | "inactive" | "merged" | "archived";
}

export interface SeasonTeamEntryContract {
  associationId: string;
  competitionId: string;
  seasonId: string;
  divisionId: string;
  teamEntryId: string;
  teamId: string;
  seasonalIdentityVersionId: string;
  registrationStatus: "proposed" | "pending" | "approved" | "withdrawn";
}

export interface RosterMembershipContract {
  associationId: string;
  competitionId: string;
  seasonId: string;
  membershipId: string;
  membershipVersionId: string;
  playerId: string;
  teamEntryId: string;
  eligibilityStatus: "unknown" | "provisional" | "eligible" | "ineligible" | "suspended" | "released";
  interval: TemporalInterval;
}

export interface GameParticipantSnapshotContract {
  scope: GameScope;
  snapshotId: string;
  snapshotHash: string;
  participantId: string;
  playerId: string;
  rosterMembershipId: string;
  rosterMembershipVersionId: string;
  teamEntryId: string;
  jersey: string;
  displayNameVersionId: string;
  eligibilityStatus: RosterMembershipContract["eligibilityStatus"];
  eligibilityEvidenceRefs: readonly string[];
}

export interface OfficialStatVersionSet {
  authorizationSchemaVersion: 2;
  brandingVersion: VersionReference;
  calculatorVersion: VersionReference;
  commandSchemaVersion: 2;
  dataSchemaVersion: 2;
  domainSchemaVersion: 2;
  identityResolutionVersion: VersionReference;
  policyVersion: VersionReference;
  privacyPolicyVersion: VersionReference;
  projectionVersion: VersionReference;
  rulesetVersion: VersionReference;
}

export interface PublicationReleaseVersion {
  releaseId: string;
  sourceSetHash: string;
  projectionHash: string;
  publicationEpoch: number;
  privacyEpoch: number;
  versions: OfficialStatVersionSet;
}

export type ExplicitFact<T> =
  | {state: "known"; value: T}
  | {state: "unknown"; value: null; reasonCode: string | null}
  | {state: "notApplicable"; value: null; reasonCode: string};

export const journalOperationTypes = [
  "setParticipantStatus",
  "setPlayerCounter",
  "setTeamOnlyCounter",
  "setPeriodScore",
  "setClock",
  "recordDiscipline",
  "setLineup",
  "attachEvidence",
] as const;
export type JournalOperationType = typeof journalOperationTypes[number];

export const journalDeliveryStates = [
  "savedOnDevice", "queued", "sending", "accepted", "needsAttention",
] as const;
export type JournalDeliveryState = typeof journalDeliveryStates[number];

export interface JournalOperationContract {
  scope: GameScope;
  workspaceId: string;
  operationId: string;
  commandId: string;
  actorAccountId: string;
  deviceSessionId: string;
  writerEpoch: number;
  localSequence: number;
  previousOperationHash: ExplicitFact<string>;
  expectedServerHead: string;
  operationSchemaVersion: number;
  reducerVersion: string;
  rulesetVersion: string;
  operationType: JournalOperationType;
  periodNumber: ExplicitFact<number>;
  clockRemainingMs: ExplicitFact<number>;
  logicalPlayOrder: number;
  payload: Record<string, unknown>;
  semanticHash: string;
  requestHash: string;
  clientObservedAt: Date;
}

export interface OperationReceiptContract {
  receiptId: string;
  scope: GameScope;
  workspaceId: string;
  operationId: string;
  commandId: string;
  actorAccountId: string;
  commandKind: JournalOperationType;
  requestHash: string;
  serverSequence: number;
  acceptedJournalHead: string;
  acceptedJournalHash: string;
  writerEpoch: number;
  acceptedAt: Date;
}

/** Mutable local delivery metadata. It never participates in semantic hashes. */
export interface JournalDeliveryContract {
  operationId: string;
  state: JournalDeliveryState;
  retryCount: number;
  nextAttemptAt: ExplicitFact<Date>;
  lastErrorCode: ExplicitFact<string>;
  receipt: ExplicitFact<OperationReceiptContract>;
}

export const boxScorePartKinds = [
  "playerInputs", "teamOnlyInputs", "periods", "discipline", "lineups",
] as const;
export type BoxScorePartKind = typeof boxScorePartKinds[number];

export interface BoxScoreInputPartDescriptor {
  partId: string;
  kind: BoxScorePartKind;
  count: number;
  sha256: string;
}

export interface BoxScoreRevisionContract {
  scope: GameScope;
  revisionId: string;
  revisionNumber: number;
  supersedesRevisionId: ExplicitFact<string>;
  captureMode: "liveCapture" | "officialSheet" | "historicalImport";
  resultDisposition: ResultDisposition;
  statisticsDisposition: StatisticsDisposition;
  versions: OfficialStatVersionSet;
  scheduleRevisionId: string;
  rosterSnapshotId: string;
  rosterSnapshotHash: string;
  sourceWorkspaceId: string;
  acceptedThroughSequence: number;
  journalHash: string;
  officialScoreEvidenceRefs: ExplicitFact<string[]>;
  inputParts: readonly BoxScoreInputPartDescriptor[];
  inputHash: string;
  derivedHash: string;
  validationReportHash: string;
  createdBy: string;
  createdAt: Date;
}

export interface CertificationContract {
  scope: GameScope;
  certificateId: string;
  revisionId: string;
  revisionHash: string;
  certifierAccountId: string;
  predecessorCertificateId: ExplicitFact<string>;
  certificationPolicyVersion: string;
  certifiedAt: Date;
}

export interface CorrectionContract {
  scope: GameScope;
  correctionId: string;
  targetCertificateId: string;
  reasonCode: string;
  evidenceRefs: string[];
  fieldDiff: ReadonlyArray<Record<string, unknown>>;
  successorWorkspaceId: string;
}

export interface ProjectionBuildContract {
  associationId: string;
  competitionId: string;
  seasonId: string;
  buildId: string;
  state: "building" | "validating" | "sealed" | "failed" | "abandoned";
  selectionId: string;
  sourceSetHash: string;
  expectedCertificateEpoch: number;
  expectedPublicationEpoch: number;
  expectedPrivacyEpoch: number;
  sealedManifestHash: ExplicitFact<string>;
}

export interface PublicationReleaseHeadContract {
  associationId: string;
  competitionId: string;
  seasonId: string;
  state: "absent" | "active" | "retracted";
  activeReleaseId: ExplicitFact<string>;
  certificateEpoch: number;
  publicationEpoch: number;
  privacyEpoch: number;
}

export interface PrivacyReleaseContract {
  associationId: string;
  playerId: string;
  privacyPolicyVersion: string;
  privacyEpoch: number;
  isMinor: boolean;
  fieldPermissions: Readonly<Record<string, PrivacyPermissionState>>;
  authorityEvidenceRefs: readonly string[];
}

const opaqueId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const lowercaseSha256 = /^[0-9a-f]{64}$/;

function requireSafeNonNegative(field: string, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new TypeError(`${field} must be a nonnegative safe integer`);
  }
}

function requireOpaqueId(field: string, value: string): void {
  if (!opaqueId.test(value)) throw new TypeError(`${field} must be an opaque ID`);
}

function requireSha256(field: string, value: string): void {
  if (!lowercaseSha256.test(value)) {
    throw new TypeError(`${field} must be lowercase SHA-256 hex`);
  }
}

function validateOrderingFact(field: string, fact: ExplicitFact<number>): void {
  if (fact.state === "known") {
    requireSafeNonNegative(field, fact.value);
    return;
  }
  if (fact.value !== null) throw new TypeError(`${field} absent facts require null value`);
  if (fact.state === "notApplicable" && fact.reasonCode.length === 0) {
    throw new TypeError(`${field} notApplicable requires a reasonCode`);
  }
}

function validatePreviousOperationHash(
  sequence: number,
  fact: ExplicitFact<string>,
): void {
  if (sequence === 0) {
    if (fact.state !== "notApplicable" || fact.reasonCode !== "genesis") {
      throw new TypeError("Sequence zero requires previousOperationHash notApplicable(genesis)");
    }
    return;
  }
  if (fact.state !== "known") {
    throw new TypeError("Non-genesis operations require a known previousOperationHash");
  }
  requireSha256("previousOperationHash", fact.value);
}

export function validateTemporalInterval(interval: TemporalInterval): void {
  canonicalEncode(interval.effectiveFrom);
  canonicalEncode(interval.recordedAt);
  switch (interval.effectiveTo.state) {
  case "known":
    canonicalEncode(interval.effectiveTo.value);
    if (interval.effectiveTo.value.getTime() <= interval.effectiveFrom.getTime()) {
      throw new TypeError("effectiveTo must be after effectiveFrom");
    }
    break;
  case "unknown":
    if (interval.effectiveTo.value !== null) {
      throw new TypeError("unknown effectiveTo requires null value");
    }
    break;
  case "notApplicable":
    if (interval.effectiveTo.value !== null ||
        interval.effectiveTo.reasonCode !== temporalOpenEndedReasonCode) {
      throw new TypeError("notApplicable effectiveTo requires reasonCode open_ended");
    }
    break;
  default:
    throw new TypeError("Unsupported effectiveTo fact state");
  }
}

export function temporalIntervalContains(
  interval: TemporalInterval,
  instant: Date,
): boolean | null {
  validateTemporalInterval(interval);
  canonicalEncode(instant);
  if (instant.getTime() < interval.effectiveFrom.getTime()) return false;
  if (interval.effectiveTo.state === "known") {
    return instant.getTime() < interval.effectiveTo.value.getTime();
  }
  return interval.effectiveTo.state === "notApplicable" ? true : null;
}

/**
 * Immutable basketball meaning. IDs, actor/device authority, writer fencing,
 * observation time, and all delivery fields are deliberately excluded.
 */
export function journalSemanticHashInput(
  operation: JournalOperationContract,
): Readonly<Record<string, unknown>> {
  return {
    clockRemainingMs: operation.clockRemainingMs,
    logicalPlayOrder: operation.logicalPlayOrder,
    operationSchemaVersion: operation.operationSchemaVersion,
    operationType: operation.operationType,
    payload: operation.payload,
    periodNumber: operation.periodNumber,
    reducerVersion: operation.reducerVersion,
    rulesetVersion: operation.rulesetVersion,
    scope: operation.scope,
    workspaceId: operation.workspaceId,
  };
}

/**
 * Immutable request/fencing identity. commandId is the idempotency key and is
 * excluded from the value it keys; clientObservedAt and JournalDeliveryContract
 * are transport metadata and are also excluded.
 */
export function journalRequestHashInput(
  operation: JournalOperationContract,
): Readonly<Record<string, unknown>> {
  return {
    actorAccountId: operation.actorAccountId,
    deviceSessionId: operation.deviceSessionId,
    expectedServerHead: operation.expectedServerHead,
    localSequence: operation.localSequence,
    operationId: operation.operationId,
    previousOperationHash: operation.previousOperationHash,
    semanticHash: operation.semanticHash,
    writerEpoch: operation.writerEpoch,
  };
}

export function validateJournalOperation(operation: JournalOperationContract): void {
  for (const [field, value] of Object.entries({
    workspaceId: operation.workspaceId,
    operationId: operation.operationId,
    commandId: operation.commandId,
    actorAccountId: operation.actorAccountId,
    deviceSessionId: operation.deviceSessionId,
    expectedServerHead: operation.expectedServerHead,
    reducerVersion: operation.reducerVersion,
    rulesetVersion: operation.rulesetVersion,
  })) requireOpaqueId(field, value);
  for (const [field, value] of Object.entries(operation.scope)) {
    requireOpaqueId(`scope.${field}`, value);
  }
  requireSafeNonNegative("writerEpoch", operation.writerEpoch);
  requireSafeNonNegative("localSequence", operation.localSequence);
  requireSafeNonNegative("operationSchemaVersion", operation.operationSchemaVersion);
  if (operation.operationSchemaVersion === 0) {
    throw new TypeError("operationSchemaVersion must be at least one");
  }
  if (!journalOperationTypes.includes(operation.operationType)) {
    throw new TypeError(`Unsupported operationType: ${operation.operationType}`);
  }
  requireSafeNonNegative("logicalPlayOrder", operation.logicalPlayOrder);
  validatePreviousOperationHash(operation.localSequence, operation.previousOperationHash);
  validateOrderingFact("periodNumber", operation.periodNumber);
  if (operation.periodNumber.state === "known" && operation.periodNumber.value === 0) {
    throw new TypeError("periodNumber must be at least one");
  }
  validateOrderingFact("clockRemainingMs", operation.clockRemainingMs);
  requireSha256("semanticHash", operation.semanticHash);
  requireSha256("requestHash", operation.requestHash);
  canonicalEncode(operation.clientObservedAt);
  const calculatedSemanticHash = canonicalSha256(journalSemanticHashInput(operation));
  if (calculatedSemanticHash !== operation.semanticHash) {
    throw new TypeError("semanticHash does not match immutable semantic fields");
  }
  const calculatedRequestHash = canonicalSha256(journalRequestHashInput(operation));
  if (calculatedRequestHash !== operation.requestHash) {
    throw new TypeError("requestHash does not match immutable request fields");
  }
}

export function validateOperationReceipt(receipt: OperationReceiptContract): void {
  for (const [field, value] of Object.entries({
    receiptId: receipt.receiptId,
    workspaceId: receipt.workspaceId,
    operationId: receipt.operationId,
    commandId: receipt.commandId,
    actorAccountId: receipt.actorAccountId,
    acceptedJournalHead: receipt.acceptedJournalHead,
  })) requireOpaqueId(field, value);
  for (const [field, value] of Object.entries(receipt.scope)) {
    requireOpaqueId(`scope.${field}`, value);
  }
  if (!journalOperationTypes.includes(receipt.commandKind)) {
    throw new TypeError(`Unsupported commandKind: ${receipt.commandKind}`);
  }
  requireSha256("requestHash", receipt.requestHash);
  requireSha256("acceptedJournalHash", receipt.acceptedJournalHash);
  requireSafeNonNegative("serverSequence", receipt.serverSequence);
  requireSafeNonNegative("writerEpoch", receipt.writerEpoch);
  canonicalEncode(receipt.acceptedAt);
}

export function validateJournalDelivery(delivery: JournalDeliveryContract): void {
  requireOpaqueId("operationId", delivery.operationId);
  requireSafeNonNegative("retryCount", delivery.retryCount);
  if (delivery.state === "accepted" && delivery.receipt.state !== "known") {
    throw new TypeError("accepted delivery requires a known receipt");
  }
  if (delivery.nextAttemptAt.state === "known") canonicalEncode(delivery.nextAttemptAt.value);
  if (delivery.receipt.state === "known") {
    validateOperationReceipt(delivery.receipt.value);
    if (delivery.receipt.value.operationId !== delivery.operationId) {
      throw new TypeError("Delivery receipt operationId must match delivery operationId");
    }
  }
}

export function validateBoxScoreInputParts(
  parts: readonly BoxScoreInputPartDescriptor[],
  disposition?: StatisticsDisposition,
): void {
  const seenIds = new Set<string>();
  let previousSortKey: string | null = null;
  const kinds = new Set<BoxScorePartKind>();
  for (const part of parts) {
    requireOpaqueId("partId", part.partId);
    if (seenIds.has(part.partId)) throw new TypeError("inputParts partId values must be unique");
    seenIds.add(part.partId);
    requireSafeNonNegative("count", part.count);
    if (part.count === 0) throw new TypeError("inputParts count must be at least one");
    requireSha256("sha256", part.sha256);
    const kindIndex = boxScorePartKinds.indexOf(part.kind);
    if (kindIndex < 0) throw new TypeError(`Unsupported inputParts kind: ${part.kind}`);
    kinds.add(part.kind);
    const sortKey = `${String(kindIndex).padStart(2, "0")}:${part.partId}`;
    if (previousSortKey !== null && previousSortKey >= sortKey) {
      throw new TypeError("inputParts must be sorted by kind then ASCII partId");
    }
    previousSortKey = sortKey;
  }
  if (!kinds.has("teamOnlyInputs")) {
    throw new TypeError("Every revision requires teamOnlyInputs for outcome facts");
  }
  if (disposition === "complete") {
    for (const required of ["playerInputs", "periods", "discipline"] as const) {
      if (!kinds.has(required)) throw new TypeError(`Complete revisions require ${required}`);
    }
  }
}

export function boxScoreInputHash(parts: readonly BoxScoreInputPartDescriptor[]): string {
  validateBoxScoreInputParts(parts);
  return canonicalSha256(parts);
}

export function validatePublicationReleaseHead(head: PublicationReleaseHeadContract): void {
  for (const [field, value] of Object.entries({
    associationId: head.associationId,
    competitionId: head.competitionId,
    seasonId: head.seasonId,
  })) requireOpaqueId(field, value);
  requireSafeNonNegative("certificateEpoch", head.certificateEpoch);
  requireSafeNonNegative("publicationEpoch", head.publicationEpoch);
  requireSafeNonNegative("privacyEpoch", head.privacyEpoch);
  if (!(["absent", "active", "retracted"] as const).includes(head.state)) {
    throw new TypeError(`Unsupported release-head state: ${head.state}`);
  }
  if (head.state === "active") {
    if (head.activeReleaseId.state !== "known") {
      throw new TypeError("active release head requires a known activeReleaseId");
    }
    requireSha256("activeReleaseId", head.activeReleaseId.value);
    return;
  }
  const expectedReason = head.state === "absent" ? "not_activated" : "retracted";
  if (head.activeReleaseId.state !== "notApplicable" ||
      head.activeReleaseId.reasonCode !== expectedReason ||
      head.activeReleaseId.value !== null) {
    throw new TypeError(`${head.state} release head requires notApplicable(${expectedReason})`);
  }
}

export type RetryClassification =
  | "never"
  | "retrySameCommand"
  | "refreshAuthenticationThenRetrySameCommand"
  | "refreshStateThenCreateNewCommand"
  | "operatorResolutionRequired";

export const commandErrorRetries = {
  invalidArgument: "never",
  invalidIdentifier: "never",
  unsupportedSchemaVersion: "never",
  policyNotActivated: "never",
  unauthenticated: "refreshAuthenticationThenRetrySameCommand",
  permissionDenied: "never",
  scopeMismatch: "never",
  assignmentRequired: "operatorResolutionRequired",
  staleAuthority: "refreshStateThenCreateNewCommand",
  staleControlVersion: "refreshStateThenCreateNewCommand",
  staleRevision: "refreshStateThenCreateNewCommand",
  payloadKeyConflict: "never",
  sequenceGap: "retrySameCommand",
  sequenceConflict: "operatorResolutionRequired",
  staleWriterEpoch: "operatorResolutionRequired",
  writerTransferRequired: "operatorResolutionRequired",
  lifecycleTransitionDenied: "refreshStateThenCreateNewCommand",
  invariantViolation: "never",
  evidenceRequired: "operatorResolutionRequired",
  conflictBranchPreserved: "operatorResolutionRequired",
  resourceExhausted: "operatorResolutionRequired",
  rateLimited: "retrySameCommand",
  transientUnavailable: "retrySameCommand",
  deadlineExceeded: "retrySameCommand",
  internal: "retrySameCommand",
} as const satisfies Readonly<Record<string, RetryClassification>>;

export type IdempotencyClassification =
  | "safeReplayReturnsOriginalResult"
  | "sameKeyDifferentPayloadRejected"
  | "notAccepted"
  | "conflictBranchPreserved";

export const commandErrorIdempotency = {
  invalidArgument: "notAccepted",
  invalidIdentifier: "notAccepted",
  unsupportedSchemaVersion: "notAccepted",
  policyNotActivated: "notAccepted",
  unauthenticated: "notAccepted",
  permissionDenied: "notAccepted",
  scopeMismatch: "notAccepted",
  assignmentRequired: "notAccepted",
  staleAuthority: "notAccepted",
  staleControlVersion: "notAccepted",
  staleRevision: "notAccepted",
  payloadKeyConflict: "sameKeyDifferentPayloadRejected",
  sequenceGap: "notAccepted",
  sequenceConflict: "conflictBranchPreserved",
  staleWriterEpoch: "conflictBranchPreserved",
  writerTransferRequired: "notAccepted",
  lifecycleTransitionDenied: "notAccepted",
  invariantViolation: "notAccepted",
  evidenceRequired: "notAccepted",
  conflictBranchPreserved: "conflictBranchPreserved",
  resourceExhausted: "notAccepted",
  rateLimited: "notAccepted",
  transientUnavailable: "safeReplayReturnsOriginalResult",
  deadlineExceeded: "safeReplayReturnsOriginalResult",
  internal: "safeReplayReturnsOriginalResult",
} as const satisfies Readonly<Record<string, IdempotencyClassification>>;

export const maxCanonicalInteger = Number.MAX_SAFE_INTEGER;
const asciiKey = /^[\x21-\x7e]+$/;

function encodeCanonical(value: unknown): string {
  if (value === null || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "string") return JSON.stringify(value.normalize("NFC"));
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) {
      throw new TypeError("Canonical numbers must be safe integers");
    }
    return JSON.stringify(value);
  }
  if (value instanceof Date) {
    if (Object.getPrototypeOf(value) !== Date.prototype ||
        Object.getOwnPropertyNames(value).length !== 0 ||
        Object.getOwnPropertySymbols(value).length !== 0) {
      throw new TypeError("Canonical timestamps must be unmodified Date values");
    }
    if (!Number.isFinite(value.getTime())) throw new TypeError("Invalid timestamp");
    const year = value.getUTCFullYear();
    if (year < 1 || year > 9999) {
      throw new TypeError("Canonical timestamps require years 0001-9999");
    }
    return JSON.stringify(value.toISOString());
  }
  if (Array.isArray(value)) {
    if (Object.getPrototypeOf(value) !== Array.prototype ||
        Object.getOwnPropertySymbols(value).length !== 0) {
      throw new TypeError("Canonical arrays must be ordinary dense arrays");
    }
    const ownNames = Object.getOwnPropertyNames(value);
    if (ownNames.length !== value.length + 1) {
      throw new TypeError("Canonical arrays cannot have holes or extra properties");
    }
    const encoded: string[] = [];
    for (let index = 0; index < value.length; index += 1) {
      const key = String(index);
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) {
        throw new TypeError("Canonical arrays cannot have holes or accessors");
      }
      encoded.push(encodeCanonical(descriptor.value));
    }
    return `[${encoded.join(",")}]`;
  }
  if (typeof value === "object") {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw new TypeError("Canonical maps must be plain records");
    }
    if (Object.getOwnPropertySymbols(value).length !== 0) {
      throw new TypeError("Canonical maps cannot contain symbol properties");
    }
    const record = value as Record<string, unknown>;
    const ownNames = Object.getOwnPropertyNames(record);
    const keys = Object.keys(record);
    if (ownNames.length !== keys.length) {
      throw new TypeError("Canonical maps cannot contain non-enumerable properties");
    }
    for (const key of keys) {
      if (!asciiKey.test(key)) {
        throw new TypeError("Canonical map keys must be nonempty ASCII");
      }
      const descriptor = Object.getOwnPropertyDescriptor(record, key);
      if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) {
        throw new TypeError("Canonical maps cannot contain accessors");
      }
    }
    keys.sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${encodeCanonical(record[key])}`).join(",")}}`;
  }
  throw new TypeError(`Unsupported canonical value: ${typeof value}`);
}

export function canonicalEncode(value: unknown): string {
  return encodeCanonical(value);
}

export function canonicalSha256(value: unknown): string {
  return createHash("sha256").update(canonicalEncode(value), "utf8").digest("hex");
}
