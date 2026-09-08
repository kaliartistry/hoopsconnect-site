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
  operationType: string;
  payload: Record<string, unknown>;
  payloadHash: string;
  clientObservedAt: Date;
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

const maxSafeInteger = Number.MAX_SAFE_INTEGER;
const asciiKey = /^[\x21-\x7e]+$/;

function normalizeCanonical(value: unknown): unknown {
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "string") return value.normalize("NFC");
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Math.abs(value) > maxSafeInteger) {
      throw new TypeError("Canonical numbers must be safe integers");
    }
    return value;
  }
  if (value instanceof Date) {
    if (!Number.isFinite(value.getTime())) throw new TypeError("Invalid timestamp");
    const year = value.getUTCFullYear();
    if (year < 1 || year > 9999) {
      throw new TypeError("Canonical timestamps require years 0001-9999");
    }
    return value.toISOString();
  }
  if (Array.isArray(value)) return value.map(normalizeCanonical);
  if (value instanceof Set) throw new TypeError("Unordered sets are not canonical");
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record).sort();
    for (const key of keys) {
      if (!asciiKey.test(key)) {
        throw new TypeError("Canonical map keys must be nonempty ASCII");
      }
    }
    return Object.fromEntries(keys.map((key) => [key, normalizeCanonical(record[key])]));
  }
  throw new TypeError(`Unsupported canonical value: ${typeof value}`);
}

export function canonicalEncode(value: unknown): string {
  return JSON.stringify(normalizeCanonical(value));
}

export function canonicalSha256(value: unknown): string {
  return createHash("sha256").update(canonicalEncode(value), "utf8").digest("hex");
}
