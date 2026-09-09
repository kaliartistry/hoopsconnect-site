import {
  AccountLifecycleAuthorityV2,
  AuthIncarnationScopeV2,
  MembershipAuthorityV2,
  ValidatedActiveAuthorityV2,
  buildStorageAuthorizationProjectionV2,
  evaluateAccountAuthorizationV2,
  parseAccountLifecycleAuthorityV2,
  parseAuthIncarnationScopeV2,
  parseMembershipAuthorityV2,
} from "./auth_incarnation_v2";
import {
  CandidateAuthorityTransactionV2,
  CandidateSessionAttemptV2,
  CandidateTransactionalAuthorityRepositoryV2,
  VerifiedProviderAuthContextV2,
  accountLifecycleAuthorityPathV2,
  extractProviderTokenProofV2,
  membershipAuthorityPathV2,
} from "./account_lifecycle_ad02_v2";
import {CustodyOutcome, custodyOutcomes} from "./account_deletion_contract";
import {canonicalSha256} from "./official_stats_contract";

/**
 * Dormant AD03 ownership/custody candidate.
 *
 * This module is deliberately absent from the Functions entry point. It has no
 * Firebase Admin/Auth imports, no owner bootstrap, and no production custody
 * authorizer. All writes occur through an injected transaction so AD04 can
 * eventually compose the ownership disposition with its lifecycle fence.
 */
export const ASSOCIATION_OWNERSHIP_AD03_ACTIVATION_ALLOWED_V2 = false;
export const ASSOCIATION_OWNERSHIP_SCHEMA_VERSION_V2 = 2;
export const ASSOCIATION_OWNERSHIP_FRESH_AUTH_MAX_AGE_SEC_V2 = 300;
export const ASSOCIATION_OWNERSHIP_MAX_OWNERS_V2 = 16;
export const ASSOCIATION_TRANSFER_TTL_SEC_V2 = 600;
export const ASSOCIATION_RECIPIENT_EVIDENCE_MAX_AGE_SEC_V2 = 300;

export const associationOperationalStatesV2 = [
  "operating",
  "transferPending",
  "custodyRequired",
  "suspendedToCustody",
  "recoveryReview",
] as const;
export type AssociationOperationalStateV2 =
  typeof associationOperationalStatesV2[number];

export const transferIntentStatesV2 = [
  "pendingRecipientAcceptance",
  "recipientAccepted",
  "declined",
  "expired",
  "committed",
  "supersededByCustody",
  "cancelledByOwnerDeparture",
] as const;
export type TransferIntentStateV2 = typeof transferIntentStatesV2[number];

export const custodyRecoveryStatesV2 = [
  "operatorUnassigned",
  "suspended",
  "recoveryReview",
  "resolved",
] as const;
export type CustodyRecoveryStateV2 = typeof custodyRecoveryStatesV2[number];

export const ownershipDepartureChoicesV2 = [
  "ordinary",
  "transferThenDelete",
  "suspendToCustody",
] as const;
export type OwnershipDepartureChoiceV2 = typeof ownershipDepartureChoicesV2[number];

export const associationCustodyOperationClassesV2 = [
  "ordinaryMembershipMutation",
  "ordinaryInviteMutation",
  "ordinaryRoleMutation",
  "ordinaryRosterMutation",
  "ordinaryGameAssignment",
  "ordinaryStatAcceptance",
  "ordinaryReviewCertification",
  "ordinaryPublication",
  "deletionPrivacyCleanup",
  "trustedRecoveryWorker",
  "auditedServiceCustodyRecovery",
  "historicalPresentation",
] as const;
export type AssociationCustodyOperationClassV2 =
  typeof associationCustodyOperationClassesV2[number];

export type AssociationCustodyBarrierRequirementV2 =
  | "ordinaryAuthorityMayProceed"
  | "serverDeletionAuthorityRequired"
  | "trustedRecoveryAuthorityRequired"
  | "auditedServiceCustodyAuthorityRequired"
  | "ad06CurrentPrivacyDecisionRequired"
  | "associationOperationSuspended";

export type AssociationOwnershipErrorCodeV2 =
  | "AD03_INVALID_REQUEST"
  | "AD03_AUTHORITY_DENIED"
  | "AD03_FRESH_AUTH_REQUIRED"
  | "AD03_CONTROL_MISSING"
  | "AD03_CONTROL_INVALID"
  | "AD03_CONTROL_CONFLICT"
  | "AD03_NOT_RECOVERABLE_OWNER"
  | "AD03_TRANSFER_CONFLICT"
  | "AD03_TRANSFER_NOT_READY"
  | "AD03_RECIPIENT_INELIGIBLE"
  | "AD03_RECIPIENT_RESPONSE_CONFLICT"
  | "AD03_CUSTODY_RECOVERY_NOT_READY"
  | "AD03_SERVICE_AUTHORITY_DENIED";

export class AssociationOwnershipErrorV2 extends Error {
  readonly codeV2: AssociationOwnershipErrorCodeV2;

  constructor(codeV2: AssociationOwnershipErrorCodeV2) {
    super(codeV2);
    this.name = "AssociationOwnershipErrorV2";
    this.codeV2 = codeV2;
  }
}

export interface RecoverableOwnerBindingV2 extends AuthIncarnationScopeV2 {
  ownerBindingSchemaVersionV2: 2;
  ownerBindingIdV2: string;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  bindingVersionV2: number;
}

export interface AssociationOwnershipControlV2 {
  associationOwnershipSchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  controlVersionV2: number;
  operationalStateV2: AssociationOperationalStateV2;
  recoverableOwnersV2: readonly RecoverableOwnerBindingV2[];
  pendingTransferIntentIdV2: string | null;
  activeCustodyCaseIdV2: string | null;
  custodyPolicyIdV2: string | null;
}

export interface RecipientEligibilityEvidenceV2 extends AuthIncarnationScopeV2 {
  recipientEligibilitySchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  evidenceIdV2: string;
  authIdentityStateV2: "present" | "absent" | "unknown";
  recoveryChannelStateV2: "verified" | "unverified" | "unknown";
  checkedAtSecV2: number;
  expiresAtSecV2: number;
}

export interface OwnershipTransferIntentV2 {
  ownershipTransferIntentSchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  transferIntentIdV2: string;
  requestFingerprintV2: string;
  stateV2: TransferIntentStateV2;
  preparedByOwnerV2: RecoverableOwnerBindingV2;
  recipientOwnerV2: RecoverableOwnerBindingV2;
  controlVersionAtPrepareV2: number;
  controlVersionAtResponseV2: number | null;
  controlVersionAtCommitV2: number | null;
  preparedAtSecV2: number;
  expiresAtSecV2: number;
  respondedAtSecV2: number | null;
  committedAtSecV2: number | null;
  recipientAcceptedAuthTimeSecV2: number | null;
}

export interface ServiceCustodyPolicyV2 {
  serviceCustodyPolicySchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  custodyPolicyIdV2: string;
  custodyPolicyVersionV2: number;
  configurationClassV2: "testFixture" | "production";
  decisionStateV2: "unresolved" | "testOnly" | "approved";
  namedOperatorRefV2: string | null;
  namedCaseOwnerRefV2: string | null;
  escalationCoverageRefV2: string | null;
  independentInfrastructureOwnerRefV2: string | null;
  recoveryDeadlineSecV2: number | null;
}

export interface CustodyRecoveryCaseV2 {
  custodyRecoveryCaseSchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  custodyCaseIdV2: string;
  stateV2: CustodyRecoveryStateV2;
  safeErrorCodeV2: "CUSTODY_CONFLICT" | null;
  custodyPolicyIdV2: string | null;
  custodyPolicyVersionV2: number | null;
  custodyPolicyFingerprintV2: string | null;
  namedOperatorRefV2: string | null;
  namedCaseOwnerRefV2: string | null;
  controlVersionAtOpenV2: number;
  currentControlVersionV2: number;
  openedAtSecV2: number;
  deadlineAtSecV2: number | null;
  successorOwnerV2: RecoverableOwnerBindingV2 | null;
  successorAcceptanceIdV2: string | null;
  successorAcceptedAtSecV2: number | null;
  successorAcceptedAuthTimeSecV2: number | null;
  reviewEvidenceRefV2: string | null;
  resolvedAtSecV2: number | null;
}

export interface AssociationOwnershipAuditEventV2 {
  associationOwnershipAuditSchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  eventIdV2: string;
  eventTypeV2:
    | "transferCommitted"
    | "ownerDeparted"
    | "custodyRequired"
    | "custodySuspended"
    | "recoveryResolved";
  controlVersionBeforeV2: number;
  controlVersionAfterV2: number;
  ownerBindingRefV2: string | null;
  counterpartyBindingRefV2: string | null;
  transferIntentIdV2: string | null;
  custodyCaseIdV2: string | null;
  custodyPolicyIdV2: string | null;
  recordedAtSecV2: number;
}

export interface OwnerDepartureReceiptV2 extends AuthIncarnationScopeV2 {
  ownerDepartureReceiptSchemaVersionV2: 2;
  associationId: string;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  departureOperationIdV2: string;
  requestFingerprintV2: string;
  outcomeV2: CustodyOutcome;
  custodyStateV2: AssociationOperationalStateV2;
  controlVersionBeforeV2: number;
  controlVersionAfterV2: number;
  transferIntentIdV2: string | null;
  custodyCaseIdV2: string | null;
  requiresOperationalAttentionV2: boolean;
  personalDeletionMayContinueV2: true;
  recordedAtSecV2: number;
}

export interface TransferPrepareRequestV2 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  transferIntentIdV2: string;
  recipientAuthUidV2: string;
  expectedControlVersionV2: number;
}

export interface TransferResponseRequestV2 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  transferIntentIdV2: string;
  expectedControlVersionV2: number;
  responseV2: "accept" | "decline";
}

export interface TransferCommitRequestV2 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  transferIntentIdV2: string;
  expectedControlVersionV2: number;
}

export interface OwnerDepartureRequestV2 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  departureOperationIdV2: string;
  expectedControlVersionV2: number;
  custodyChoiceV2: OwnershipDepartureChoiceV2;
  transferIntentIdV2: string | null;
  custodyCaseIdV2: string | null;
}

export interface CustodySuccessorAcceptanceRequestV2 {
  associationOwnershipSchemaVersionV2: 2;
  associationId: string;
  custodyCaseIdV2: string;
  successorAcceptanceIdV2: string;
  expectedControlVersionV2: number;
}

export interface ServiceCustodyRecoveryCommandV2 {
  serviceCustodyCommandSchemaVersionV2: 2;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
  custodyPolicyIdV2: string;
  custodyPolicyVersionV2: number;
  custodyPolicyFingerprintV2: string;
  custodyCaseIdV2: string;
  commandIdV2: string;
  operatorRefV2: string;
  caseOwnerRefV2: string;
  reviewEvidenceRefV2: string;
  issuedAtSecV2: number;
  expiresAtSecV2: number;
  actionV2: "completeRecovery";
}

export interface VerifiedTestServiceCustodyCommandV2 {
  readonly command: ServiceCustodyRecoveryCommandV2;
  readonly verificationNonceV2: object;
}

export interface OwnershipServiceInputV2 {
  repository: CandidateTransactionalAuthorityRepositoryV2;
  auth: VerifiedProviderAuthContextV2;
  configuredProjectId: string;
  attempt: CandidateSessionAttemptV2;
  nowSecV2: number;
}

type JsonRecord = Record<string, unknown>;

const generationPattern = /^[a-f0-9]{64}$/;
const hashPattern = /^[a-f0-9]{64}$/;
const pathIdentifierPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const opaqueReferencePattern = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,191}$/;
const verifiedTestCommands = new WeakSet<object>();

const ownerBindingKeys = [
  "ownerBindingSchemaVersionV2",
  "ownerBindingIdV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "accountGenerationV2",
  "accountLifecycleEpochV2",
  "bindingVersionV2",
] as const;
const controlKeys = [
  "associationOwnershipSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "associationId",
  "controlVersionV2",
  "operationalStateV2",
  "recoverableOwnersV2",
  "pendingTransferIntentIdV2",
  "activeCustodyCaseIdV2",
  "custodyPolicyIdV2",
] as const;
const eligibilityKeys = [
  "recipientEligibilitySchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "accountGenerationV2",
  "accountLifecycleEpochV2",
  "evidenceIdV2",
  "authIdentityStateV2",
  "recoveryChannelStateV2",
  "checkedAtSecV2",
  "expiresAtSecV2",
] as const;
const transferIntentKeys = [
  "ownershipTransferIntentSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "associationId",
  "transferIntentIdV2",
  "requestFingerprintV2",
  "stateV2",
  "preparedByOwnerV2",
  "recipientOwnerV2",
  "controlVersionAtPrepareV2",
  "controlVersionAtResponseV2",
  "controlVersionAtCommitV2",
  "preparedAtSecV2",
  "expiresAtSecV2",
  "respondedAtSecV2",
  "committedAtSecV2",
  "recipientAcceptedAuthTimeSecV2",
] as const;
const custodyPolicyKeys = [
  "serviceCustodyPolicySchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "associationId",
  "custodyPolicyIdV2",
  "custodyPolicyVersionV2",
  "configurationClassV2",
  "decisionStateV2",
  "namedOperatorRefV2",
  "namedCaseOwnerRefV2",
  "escalationCoverageRefV2",
  "independentInfrastructureOwnerRefV2",
  "recoveryDeadlineSecV2",
] as const;
const custodyCaseKeys = [
  "custodyRecoveryCaseSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "associationId",
  "custodyCaseIdV2",
  "stateV2",
  "safeErrorCodeV2",
  "custodyPolicyIdV2",
  "custodyPolicyVersionV2",
  "custodyPolicyFingerprintV2",
  "namedOperatorRefV2",
  "namedCaseOwnerRefV2",
  "controlVersionAtOpenV2",
  "currentControlVersionV2",
  "openedAtSecV2",
  "deadlineAtSecV2",
  "successorOwnerV2",
  "successorAcceptanceIdV2",
  "successorAcceptedAtSecV2",
  "successorAcceptedAuthTimeSecV2",
  "reviewEvidenceRefV2",
  "resolvedAtSecV2",
] as const;
const departureReceiptKeys = [
  "ownerDepartureReceiptSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "associationId",
  "accountGenerationV2",
  "accountLifecycleEpochV2",
  "departureOperationIdV2",
  "requestFingerprintV2",
  "outcomeV2",
  "custodyStateV2",
  "controlVersionBeforeV2",
  "controlVersionAfterV2",
  "transferIntentIdV2",
  "custodyCaseIdV2",
  "requiresOperationalAttentionV2",
  "personalDeletionMayContinueV2",
  "recordedAtSecV2",
] as const;

function fail(code: AssociationOwnershipErrorCodeV2): never {
  throw new AssociationOwnershipErrorV2(code);
}

function record(value: unknown): JsonRecord | null {
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

function exactKeys(value: JsonRecord, expected: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length &&
    expected.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

function wireRecord(value: object): Readonly<Record<string, unknown>> {
  return value as unknown as Readonly<Record<string, unknown>>;
}

function safeCounter(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function pathIdentifier(value: unknown): string {
  if (typeof value !== "string" || !pathIdentifierPattern.test(value)) {
    fail("AD03_INVALID_REQUEST");
  }
  return value;
}

function opaqueReference(value: unknown): string {
  if (typeof value !== "string" || !opaqueReferencePattern.test(value)) {
    fail("AD03_INVALID_REQUEST");
  }
  return value;
}

function optionalOpaqueReference(value: unknown): string | null {
  return value === null ? null : opaqueReference(value);
}

function requiredCounter(value: unknown): number {
  if (!safeCounter(value)) fail("AD03_INVALID_REQUEST");
  return value;
}

function incrementCounter(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0 || value >= Number.MAX_SAFE_INTEGER) {
    fail("AD03_CONTROL_CONFLICT");
  }
  return value + 1;
}

function sameScope(left: AuthIncarnationScopeV2, right: AuthIncarnationScopeV2): boolean {
  return left.authProjectIdV2 === right.authProjectIdV2 &&
    left.authTenantIdV2 === right.authTenantIdV2 &&
    left.authUidV2 === right.authUidV2;
}

function sameAssociationScope(
  left: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  right: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
): boolean {
  return left.authProjectIdV2 === right.authProjectIdV2 &&
    left.authTenantIdV2 === right.authTenantIdV2 &&
    left.associationId === right.associationId;
}

function scopeFromAssociation(value: {
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
}): AuthIncarnationScopeV2 {
  return {
    authProjectIdV2: value.authProjectIdV2,
    authTenantIdV2: value.authTenantIdV2,
    authUidV2: "scope-placeholder",
  };
}

function ownerIdentityEquals(
  left: RecoverableOwnerBindingV2,
  right: RecoverableOwnerBindingV2,
): boolean {
  return sameScope(left, right) &&
    left.accountGenerationV2 === right.accountGenerationV2 &&
    left.accountLifecycleEpochV2 === right.accountLifecycleEpochV2 &&
    left.ownerBindingIdV2 === right.ownerBindingIdV2 &&
    left.bindingVersionV2 === right.bindingVersionV2;
}

function ownerMatchesAuthority(
  owner: RecoverableOwnerBindingV2,
  authority: ValidatedActiveAuthorityV2,
): boolean {
  return sameScope(owner, authority.scope) &&
    owner.accountGenerationV2 === authority.accountGenerationV2 &&
    owner.accountLifecycleEpochV2 === authority.accountLifecycleEpochV2;
}

function sortedOwners(
  owners: readonly RecoverableOwnerBindingV2[],
): readonly RecoverableOwnerBindingV2[] {
  return Object.freeze([...owners].sort((left, right) =>
    left.ownerBindingIdV2.localeCompare(right.ownerBindingIdV2)));
}

function associationScopeFromAuthority(
  authority: ValidatedActiveAuthorityV2,
): {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string} {
  return {
    authProjectIdV2: authority.scope.authProjectIdV2,
    authTenantIdV2: authority.scope.authTenantIdV2,
    associationId: authority.associationId,
  };
}

function isFreshAt(authTimeSecV2: number, nowSecV2: number): boolean {
  return safeCounter(nowSecV2) &&
    authTimeSecV2 <= nowSecV2 &&
    nowSecV2 - authTimeSecV2 <= ASSOCIATION_OWNERSHIP_FRESH_AUTH_MAX_AGE_SEC_V2;
}

function assertAssociation(
  authority: ValidatedActiveAuthorityV2,
  associationId: string,
): void {
  if (authority.associationId !== associationId) fail("AD03_AUTHORITY_DENIED");
}

function assertTransferIntentLocatorV2(input: {
  intent: OwnershipTransferIntentV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  transferIntentIdV2: string;
}): void {
  if (!sameAssociationScope(input.intent, input.scope) ||
      input.intent.transferIntentIdV2 !== input.transferIntentIdV2) {
    fail("AD03_TRANSFER_CONFLICT");
  }
}

function assertCustodyCaseLocatorV2(input: {
  caseRecord: CustodyRecoveryCaseV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  custodyCaseIdV2: string;
}): void {
  if (!sameAssociationScope(input.caseRecord, input.scope) ||
      input.caseRecord.custodyCaseIdV2 !== input.custodyCaseIdV2) {
    fail("AD03_CUSTODY_RECOVERY_NOT_READY");
  }
}

function parseNullableCounter(value: unknown): number | null {
  return value === null ? null : requiredCounter(value);
}

function nullableOwner(value: unknown): RecoverableOwnerBindingV2 | null {
  return value === null ? null : parseRecoverableOwnerBindingV2(value);
}

export function recoverableOwnerBindingIdV2(input: {
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
}): string {
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: input.authProjectIdV2,
    authTenantIdV2: input.authTenantIdV2,
    authUidV2: input.authUidV2,
  });
  if (!generationPattern.test(input.accountGenerationV2) ||
      !safeCounter(input.accountLifecycleEpochV2)) {
    fail("AD03_INVALID_REQUEST");
  }
  return canonicalSha256([
    "association-owner-binding-v2",
    scope.authProjectIdV2,
    scope.authTenantIdV2,
    scope.authUidV2,
    input.accountGenerationV2,
    input.accountLifecycleEpochV2,
  ]);
}

export function recoverableOwnerFromAuthorityV2(
  authority: ValidatedActiveAuthorityV2,
): RecoverableOwnerBindingV2 {
  return Object.freeze({
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: recoverableOwnerBindingIdV2({
      ...authority.scope,
      accountGenerationV2: authority.accountGenerationV2,
      accountLifecycleEpochV2: authority.accountLifecycleEpochV2,
    }),
    ...authority.scope,
    accountGenerationV2: authority.accountGenerationV2,
    accountLifecycleEpochV2: authority.accountLifecycleEpochV2,
    bindingVersionV2: 1,
  });
}

export function parseRecoverableOwnerBindingV2(value: unknown): RecoverableOwnerBindingV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, ownerBindingKeys)) fail("AD03_CONTROL_INVALID");
  let scope: AuthIncarnationScopeV2;
  try {
    scope = parseAuthIncarnationScopeV2({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: data.authUidV2,
    });
  } catch {
    fail("AD03_CONTROL_INVALID");
  }
  if (
    data.ownerBindingSchemaVersionV2 !== 2 ||
    typeof data.ownerBindingIdV2 !== "string" ||
    !hashPattern.test(data.ownerBindingIdV2) ||
    typeof data.accountGenerationV2 !== "string" ||
    !generationPattern.test(data.accountGenerationV2) ||
    !safeCounter(data.accountLifecycleEpochV2) ||
    data.bindingVersionV2 !== 1
  ) fail("AD03_CONTROL_INVALID");
  const expectedId = recoverableOwnerBindingIdV2({
    ...scope,
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
  });
  if (data.ownerBindingIdV2 !== expectedId) fail("AD03_CONTROL_INVALID");
  return Object.freeze({
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: data.ownerBindingIdV2,
    ...scope,
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
    bindingVersionV2: 1,
  });
}

export function parseAssociationOwnershipControlV2(
  value: unknown,
): AssociationOwnershipControlV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, controlKeys)) fail("AD03_CONTROL_INVALID");
  const associationId = pathIdentifier(data.associationId);
  let associationScope: AuthIncarnationScopeV2;
  try {
    associationScope = parseAuthIncarnationScopeV2({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: "scope-placeholder",
    });
  } catch {
    fail("AD03_CONTROL_INVALID");
  }
  if (
    data.associationOwnershipSchemaVersionV2 !== 2 ||
    !safeCounter(data.controlVersionV2) ||
    data.controlVersionV2 === 0 ||
    !associationOperationalStatesV2.includes(data.operationalStateV2 as AssociationOperationalStateV2) ||
    !Array.isArray(data.recoverableOwnersV2) ||
    data.recoverableOwnersV2.length > ASSOCIATION_OWNERSHIP_MAX_OWNERS_V2
  ) fail("AD03_CONTROL_INVALID");
  const owners = data.recoverableOwnersV2.map(parseRecoverableOwnerBindingV2);
  if (
    owners.some((owner) =>
      owner.authProjectIdV2 !== associationScope.authProjectIdV2 ||
      owner.authTenantIdV2 !== associationScope.authTenantIdV2) ||
    new Set(owners.map((owner) => owner.ownerBindingIdV2)).size !== owners.length ||
    new Set(owners.map((owner) => owner.authUidV2)).size !== owners.length
  ) fail("AD03_CONTROL_INVALID");
  const pendingTransferIntentIdV2 = data.pendingTransferIntentIdV2 === null
    ? null
    : pathIdentifier(data.pendingTransferIntentIdV2);
  const activeCustodyCaseIdV2 = data.activeCustodyCaseIdV2 === null
    ? null
    : pathIdentifier(data.activeCustodyCaseIdV2);
  const custodyPolicyIdV2 = data.custodyPolicyIdV2 === null
    ? null
    : pathIdentifier(data.custodyPolicyIdV2);
  const state = data.operationalStateV2 as AssociationOperationalStateV2;
  const operatingShape = state === "operating" && owners.length > 0 &&
    pendingTransferIntentIdV2 === null && activeCustodyCaseIdV2 === null;
  const transferShape = state === "transferPending" && owners.length > 0 &&
    pendingTransferIntentIdV2 !== null && activeCustodyCaseIdV2 === null;
  const unresolvedCustodyShape = state === "custodyRequired" && owners.length === 0 &&
    pendingTransferIntentIdV2 === null && activeCustodyCaseIdV2 !== null;
  const namedCustodyShape = (state === "suspendedToCustody" || state === "recoveryReview") &&
    owners.length === 0 && pendingTransferIntentIdV2 === null &&
    activeCustodyCaseIdV2 !== null && custodyPolicyIdV2 !== null;
  if (!(operatingShape || transferShape || unresolvedCustodyShape || namedCustodyShape)) {
    fail("AD03_CONTROL_INVALID");
  }
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    authProjectIdV2: associationScope.authProjectIdV2,
    authTenantIdV2: associationScope.authTenantIdV2,
    associationId,
    controlVersionV2: data.controlVersionV2,
    operationalStateV2: state,
    recoverableOwnersV2: sortedOwners(owners),
    pendingTransferIntentIdV2,
    activeCustodyCaseIdV2,
    custodyPolicyIdV2,
  });
}

export function parseRecipientEligibilityEvidenceV2(
  value: unknown,
): RecipientEligibilityEvidenceV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, eligibilityKeys)) fail("AD03_RECIPIENT_INELIGIBLE");
  let scope: AuthIncarnationScopeV2;
  try {
    scope = parseAuthIncarnationScopeV2({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: data.authUidV2,
    });
  } catch {
    fail("AD03_RECIPIENT_INELIGIBLE");
  }
  if (
    data.recipientEligibilitySchemaVersionV2 !== 2 ||
    typeof data.accountGenerationV2 !== "string" ||
    !generationPattern.test(data.accountGenerationV2) ||
    !safeCounter(data.accountLifecycleEpochV2) ||
    typeof data.evidenceIdV2 !== "string" ||
    !opaqueReferencePattern.test(data.evidenceIdV2) ||
    !["present", "absent", "unknown"].includes(data.authIdentityStateV2 as string) ||
    !["verified", "unverified", "unknown"].includes(data.recoveryChannelStateV2 as string) ||
    !safeCounter(data.checkedAtSecV2) ||
    !safeCounter(data.expiresAtSecV2) ||
    data.expiresAtSecV2 < data.checkedAtSecV2 ||
    data.expiresAtSecV2 - data.checkedAtSecV2 > ASSOCIATION_RECIPIENT_EVIDENCE_MAX_AGE_SEC_V2
  ) fail("AD03_RECIPIENT_INELIGIBLE");
  return Object.freeze({
    recipientEligibilitySchemaVersionV2: 2,
    ...scope,
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
    evidenceIdV2: data.evidenceIdV2,
    authIdentityStateV2: data.authIdentityStateV2 as "present" | "absent" | "unknown",
    recoveryChannelStateV2:
      data.recoveryChannelStateV2 as "verified" | "unverified" | "unknown",
    checkedAtSecV2: data.checkedAtSecV2,
    expiresAtSecV2: data.expiresAtSecV2,
  });
}

export function parseOwnershipTransferIntentV2(value: unknown): OwnershipTransferIntentV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, transferIntentKeys)) fail("AD03_TRANSFER_CONFLICT");
  let owner: RecoverableOwnerBindingV2;
  let recipient: RecoverableOwnerBindingV2;
  try {
    owner = parseRecoverableOwnerBindingV2(data.preparedByOwnerV2);
    recipient = parseRecoverableOwnerBindingV2(data.recipientOwnerV2);
  } catch {
    fail("AD03_TRANSFER_CONFLICT");
  }
  const associationId = pathIdentifier(data.associationId);
  const transferIntentIdV2 = pathIdentifier(data.transferIntentIdV2);
  const state = data.stateV2 as TransferIntentStateV2;
  if (
    data.ownershipTransferIntentSchemaVersionV2 !== 2 ||
    typeof data.authProjectIdV2 !== "string" ||
    data.authProjectIdV2 !== owner.authProjectIdV2 ||
    data.authProjectIdV2 !== recipient.authProjectIdV2 ||
    data.authTenantIdV2 !== owner.authTenantIdV2 ||
    data.authTenantIdV2 !== recipient.authTenantIdV2 ||
    typeof data.requestFingerprintV2 !== "string" ||
    !hashPattern.test(data.requestFingerprintV2) ||
    !transferIntentStatesV2.includes(state) ||
    ownerIdentityEquals(owner, recipient) ||
    !safeCounter(data.controlVersionAtPrepareV2) ||
    !safeCounter(data.preparedAtSecV2) ||
    !safeCounter(data.expiresAtSecV2) ||
    data.expiresAtSecV2 <= data.preparedAtSecV2 ||
    data.expiresAtSecV2 - data.preparedAtSecV2 > ASSOCIATION_TRANSFER_TTL_SEC_V2
  ) fail("AD03_TRANSFER_CONFLICT");
  const controlVersionAtResponseV2 = parseNullableCounter(data.controlVersionAtResponseV2);
  const controlVersionAtCommitV2 = parseNullableCounter(data.controlVersionAtCommitV2);
  const respondedAtSecV2 = parseNullableCounter(data.respondedAtSecV2);
  const committedAtSecV2 = parseNullableCounter(data.committedAtSecV2);
  const recipientAcceptedAuthTimeSecV2 =
    parseNullableCounter(data.recipientAcceptedAuthTimeSecV2);
  const pendingShape = state === "pendingRecipientAcceptance" &&
    controlVersionAtResponseV2 === null && controlVersionAtCommitV2 === null &&
    respondedAtSecV2 === null && committedAtSecV2 === null &&
    recipientAcceptedAuthTimeSecV2 === null;
  const acceptedShape = state === "recipientAccepted" &&
    controlVersionAtResponseV2 !== null && controlVersionAtCommitV2 === null &&
    respondedAtSecV2 !== null && committedAtSecV2 === null &&
    recipientAcceptedAuthTimeSecV2 !== null;
  const declinedOrExpiredShape = ["declined", "expired"].includes(state) &&
    controlVersionAtResponseV2 !== null && controlVersionAtCommitV2 === null &&
    respondedAtSecV2 !== null && committedAtSecV2 === null &&
    recipientAcceptedAuthTimeSecV2 === null;
  const alternateClosedShape = [
    "supersededByCustody", "cancelledByOwnerDeparture",
  ].includes(state) &&
    controlVersionAtResponseV2 !== null && controlVersionAtCommitV2 === null &&
    respondedAtSecV2 !== null && committedAtSecV2 === null;
  const committedShape = state === "committed" &&
    controlVersionAtResponseV2 !== null && controlVersionAtCommitV2 !== null &&
    respondedAtSecV2 !== null && committedAtSecV2 !== null &&
    recipientAcceptedAuthTimeSecV2 !== null;
  if (!(pendingShape || acceptedShape || declinedOrExpiredShape ||
      alternateClosedShape || committedShape)) {
    fail("AD03_TRANSFER_CONFLICT");
  }
  return Object.freeze({
    ownershipTransferIntentSchemaVersionV2: 2,
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2 as string | null,
    associationId,
    transferIntentIdV2,
    requestFingerprintV2: data.requestFingerprintV2,
    stateV2: state,
    preparedByOwnerV2: owner,
    recipientOwnerV2: recipient,
    controlVersionAtPrepareV2: data.controlVersionAtPrepareV2,
    controlVersionAtResponseV2,
    controlVersionAtCommitV2,
    preparedAtSecV2: data.preparedAtSecV2,
    expiresAtSecV2: data.expiresAtSecV2,
    respondedAtSecV2,
    committedAtSecV2,
    recipientAcceptedAuthTimeSecV2,
  });
}

export function parseServiceCustodyPolicyV2(value: unknown): ServiceCustodyPolicyV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, custodyPolicyKeys)) fail("AD03_CONTROL_INVALID");
  const policy: ServiceCustodyPolicyV2 = {
    serviceCustodyPolicySchemaVersionV2: data.serviceCustodyPolicySchemaVersionV2 as 2,
    authProjectIdV2: data.authProjectIdV2 as string,
    authTenantIdV2: data.authTenantIdV2 as string | null,
    associationId: pathIdentifier(data.associationId),
    custodyPolicyIdV2: pathIdentifier(data.custodyPolicyIdV2),
    custodyPolicyVersionV2: requiredCounter(data.custodyPolicyVersionV2),
    configurationClassV2: data.configurationClassV2 as "testFixture" | "production",
    decisionStateV2: data.decisionStateV2 as "unresolved" | "testOnly" | "approved",
    namedOperatorRefV2: optionalOpaqueReference(data.namedOperatorRefV2),
    namedCaseOwnerRefV2: optionalOpaqueReference(data.namedCaseOwnerRefV2),
    escalationCoverageRefV2: optionalOpaqueReference(data.escalationCoverageRefV2),
    independentInfrastructureOwnerRefV2:
      optionalOpaqueReference(data.independentInfrastructureOwnerRefV2),
    recoveryDeadlineSecV2: parseNullableCounter(data.recoveryDeadlineSecV2),
  };
  try {
    parseAuthIncarnationScopeV2({...scopeFromAssociation(policy)});
  } catch {
    fail("AD03_CONTROL_INVALID");
  }
  if (
    policy.serviceCustodyPolicySchemaVersionV2 !== 2 ||
    policy.custodyPolicyVersionV2 === 0 ||
    !["testFixture", "production"].includes(policy.configurationClassV2) ||
    !["unresolved", "testOnly", "approved"].includes(policy.decisionStateV2) ||
    (policy.recoveryDeadlineSecV2 !== null && policy.recoveryDeadlineSecV2 === 0)
  ) fail("AD03_CONTROL_INVALID");
  return Object.freeze(policy);
}

export function serviceCustodyPolicyFingerprintV2(value: unknown): string {
  const policy = parseServiceCustodyPolicyV2(value);
  return canonicalSha256({
    serviceCustodyPolicySchemaVersionV2: policy.serviceCustodyPolicySchemaVersionV2,
    authProjectIdV2: policy.authProjectIdV2,
    authTenantIdV2: policy.authTenantIdV2,
    associationId: policy.associationId,
    custodyPolicyIdV2: policy.custodyPolicyIdV2,
    custodyPolicyVersionV2: policy.custodyPolicyVersionV2,
    configurationClassV2: policy.configurationClassV2,
    decisionStateV2: policy.decisionStateV2,
    namedOperatorRefV2: policy.namedOperatorRefV2,
    namedCaseOwnerRefV2: policy.namedCaseOwnerRefV2,
    escalationCoverageRefV2: policy.escalationCoverageRefV2,
    independentInfrastructureOwnerRefV2: policy.independentInfrastructureOwnerRefV2,
    recoveryDeadlineSecV2: policy.recoveryDeadlineSecV2,
  });
}

export function parseCustodyRecoveryCaseV2(value: unknown): CustodyRecoveryCaseV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, custodyCaseKeys)) fail("AD03_CONTROL_INVALID");
  const state = data.stateV2 as CustodyRecoveryStateV2;
  const successor = nullableOwner(data.successorOwnerV2);
  const result: CustodyRecoveryCaseV2 = {
    custodyRecoveryCaseSchemaVersionV2: data.custodyRecoveryCaseSchemaVersionV2 as 2,
    authProjectIdV2: data.authProjectIdV2 as string,
    authTenantIdV2: data.authTenantIdV2 as string | null,
    associationId: pathIdentifier(data.associationId),
    custodyCaseIdV2: pathIdentifier(data.custodyCaseIdV2),
    stateV2: state,
    safeErrorCodeV2: data.safeErrorCodeV2 as "CUSTODY_CONFLICT" | null,
    custodyPolicyIdV2: data.custodyPolicyIdV2 === null
      ? null
      : pathIdentifier(data.custodyPolicyIdV2),
    custodyPolicyVersionV2: parseNullableCounter(data.custodyPolicyVersionV2),
    custodyPolicyFingerprintV2: data.custodyPolicyFingerprintV2 === null
      ? null
      : typeof data.custodyPolicyFingerprintV2 === "string" &&
        hashPattern.test(data.custodyPolicyFingerprintV2)
        ? data.custodyPolicyFingerprintV2
        : fail("AD03_CONTROL_INVALID"),
    namedOperatorRefV2: optionalOpaqueReference(data.namedOperatorRefV2),
    namedCaseOwnerRefV2: optionalOpaqueReference(data.namedCaseOwnerRefV2),
    controlVersionAtOpenV2: requiredCounter(data.controlVersionAtOpenV2),
    currentControlVersionV2: requiredCounter(data.currentControlVersionV2),
    openedAtSecV2: requiredCounter(data.openedAtSecV2),
    deadlineAtSecV2: parseNullableCounter(data.deadlineAtSecV2),
    successorOwnerV2: successor,
    successorAcceptanceIdV2: data.successorAcceptanceIdV2 === null
      ? null
      : pathIdentifier(data.successorAcceptanceIdV2),
    successorAcceptedAtSecV2: parseNullableCounter(data.successorAcceptedAtSecV2),
    successorAcceptedAuthTimeSecV2:
      parseNullableCounter(data.successorAcceptedAuthTimeSecV2),
    reviewEvidenceRefV2: optionalOpaqueReference(data.reviewEvidenceRefV2),
    resolvedAtSecV2: parseNullableCounter(data.resolvedAtSecV2),
  };
  try {
    parseAuthIncarnationScopeV2({...scopeFromAssociation(result)});
  } catch {
    fail("AD03_CONTROL_INVALID");
  }
  if (
    result.custodyRecoveryCaseSchemaVersionV2 !== 2 ||
    !custodyRecoveryStatesV2.includes(state) ||
    !safeCounter(result.controlVersionAtOpenV2) ||
    !safeCounter(result.currentControlVersionV2) ||
    result.currentControlVersionV2 < result.controlVersionAtOpenV2
  ) fail("AD03_CONTROL_INVALID");
  const unassignedShape = state === "operatorUnassigned" &&
    result.safeErrorCodeV2 === "CUSTODY_CONFLICT" &&
    result.custodyPolicyIdV2 === null && result.namedOperatorRefV2 === null &&
    result.custodyPolicyVersionV2 === null &&
    result.custodyPolicyFingerprintV2 === null &&
    result.namedCaseOwnerRefV2 === null && result.deadlineAtSecV2 === null &&
    successor === null && result.successorAcceptanceIdV2 === null &&
    result.successorAcceptedAtSecV2 === null &&
    result.successorAcceptedAuthTimeSecV2 === null &&
    result.reviewEvidenceRefV2 === null && result.resolvedAtSecV2 === null;
  const suspendedShape = state === "suspended" && result.safeErrorCodeV2 === null &&
    result.custodyPolicyIdV2 !== null && result.namedOperatorRefV2 !== null &&
    result.custodyPolicyVersionV2 !== null && result.custodyPolicyVersionV2 > 0 &&
    result.custodyPolicyFingerprintV2 !== null &&
    result.namedCaseOwnerRefV2 !== null && result.deadlineAtSecV2 !== null &&
    successor === null && result.successorAcceptanceIdV2 === null &&
    result.successorAcceptedAtSecV2 === null &&
    result.successorAcceptedAuthTimeSecV2 === null &&
    result.reviewEvidenceRefV2 === null && result.resolvedAtSecV2 === null;
  const reviewShape = state === "recoveryReview" && result.safeErrorCodeV2 === null &&
    result.custodyPolicyIdV2 !== null && result.namedOperatorRefV2 !== null &&
    result.custodyPolicyVersionV2 !== null && result.custodyPolicyVersionV2 > 0 &&
    result.custodyPolicyFingerprintV2 !== null &&
    result.namedCaseOwnerRefV2 !== null && result.deadlineAtSecV2 !== null &&
    successor !== null && result.successorAcceptanceIdV2 !== null &&
    result.successorAcceptedAtSecV2 !== null &&
    result.successorAcceptedAuthTimeSecV2 !== null &&
    result.reviewEvidenceRefV2 === null && result.resolvedAtSecV2 === null;
  const resolvedShape = state === "resolved" && result.safeErrorCodeV2 === null &&
    result.custodyPolicyIdV2 !== null && result.namedOperatorRefV2 !== null &&
    result.custodyPolicyVersionV2 !== null && result.custodyPolicyVersionV2 > 0 &&
    result.custodyPolicyFingerprintV2 !== null &&
    result.namedCaseOwnerRefV2 !== null && result.deadlineAtSecV2 !== null &&
    successor !== null && result.successorAcceptanceIdV2 !== null &&
    result.successorAcceptedAtSecV2 !== null &&
    result.successorAcceptedAuthTimeSecV2 !== null &&
    result.reviewEvidenceRefV2 !== null && result.resolvedAtSecV2 !== null;
  if (!(unassignedShape || suspendedShape || reviewShape || resolvedShape)) {
    fail("AD03_CONTROL_INVALID");
  }
  if (result.successorAcceptedAuthTimeSecV2 !== null &&
      result.successorAcceptedAtSecV2 !== null &&
      (result.successorAcceptedAuthTimeSecV2 > result.successorAcceptedAtSecV2 ||
       result.successorAcceptedAtSecV2 - result.successorAcceptedAuthTimeSecV2 >
        ASSOCIATION_OWNERSHIP_FRESH_AUTH_MAX_AGE_SEC_V2)) {
    fail("AD03_CONTROL_INVALID");
  }
  if (successor !== null &&
      (successor.authProjectIdV2 !== result.authProjectIdV2 ||
       successor.authTenantIdV2 !== result.authTenantIdV2)) {
    fail("AD03_CONTROL_INVALID");
  }
  return Object.freeze(result);
}

export function parseOwnerDepartureReceiptV2(value: unknown): OwnerDepartureReceiptV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, departureReceiptKeys)) fail("AD03_TRANSFER_CONFLICT");
  let scope: AuthIncarnationScopeV2;
  try {
    scope = parseAuthIncarnationScopeV2({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: data.authUidV2,
    });
  } catch {
    fail("AD03_TRANSFER_CONFLICT");
  }
  if (
    data.ownerDepartureReceiptSchemaVersionV2 !== 2 ||
    typeof data.accountGenerationV2 !== "string" ||
    !generationPattern.test(data.accountGenerationV2) ||
    !safeCounter(data.accountLifecycleEpochV2) ||
    typeof data.requestFingerprintV2 !== "string" ||
    !hashPattern.test(data.requestFingerprintV2) ||
    !custodyOutcomes.includes(data.outcomeV2 as CustodyOutcome) ||
    !associationOperationalStatesV2.includes(data.custodyStateV2 as AssociationOperationalStateV2) ||
    !safeCounter(data.controlVersionBeforeV2) ||
    !safeCounter(data.controlVersionAfterV2) ||
    typeof data.requiresOperationalAttentionV2 !== "boolean" ||
    data.personalDeletionMayContinueV2 !== true ||
    !safeCounter(data.recordedAtSecV2)
  ) fail("AD03_TRANSFER_CONFLICT");
  return Object.freeze({
    ownerDepartureReceiptSchemaVersionV2: 2,
    ...scope,
    associationId: pathIdentifier(data.associationId),
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
    departureOperationIdV2: pathIdentifier(data.departureOperationIdV2),
    requestFingerprintV2: data.requestFingerprintV2,
    outcomeV2: data.outcomeV2 as CustodyOutcome,
    custodyStateV2: data.custodyStateV2 as AssociationOperationalStateV2,
    controlVersionBeforeV2: data.controlVersionBeforeV2,
    controlVersionAfterV2: data.controlVersionAfterV2,
    transferIntentIdV2: data.transferIntentIdV2 === null
      ? null
      : pathIdentifier(data.transferIntentIdV2),
    custodyCaseIdV2: data.custodyCaseIdV2 === null
      ? null
      : pathIdentifier(data.custodyCaseIdV2),
    requiresOperationalAttentionV2: data.requiresOperationalAttentionV2,
    personalDeletionMayContinueV2: true,
    recordedAtSecV2: data.recordedAtSecV2,
  });
}

export function associationOwnershipControlPathV2(input: {
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  associationId: string;
}): string {
  const scope = parseAuthIncarnationScopeV2({...scopeFromAssociation(input)});
  const associationId = pathIdentifier(input.associationId);
  return scope.authTenantIdV2 === null
    ? `associationOwnershipV2Root/${associationId}`
    : `associationOwnershipV2Tenants/${pathIdentifier(scope.authTenantIdV2)}` +
      `/associations/${associationId}`;
}

export function ownershipTransferIntentPathV2(
  input: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  transferIntentIdV2: string,
): string {
  return `${associationOwnershipControlPathV2(input)}/transferIntents/` +
    pathIdentifier(transferIntentIdV2);
}

export function custodyRecoveryCasePathV2(
  input: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  custodyCaseIdV2: string,
): string {
  return `${associationOwnershipControlPathV2(input)}/custodyCases/` +
    pathIdentifier(custodyCaseIdV2);
}

export function serviceCustodyPolicyPathV2(
  input: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  custodyPolicyIdV2: string,
): string {
  return `${associationOwnershipControlPathV2(input)}/custodyPolicies/` +
    pathIdentifier(custodyPolicyIdV2);
}

export function ownerDepartureReceiptPathV2(
  input: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  departureOperationIdV2: string,
): string {
  return `${associationOwnershipControlPathV2(input)}/departureReceipts/` +
    pathIdentifier(departureOperationIdV2);
}

export function associationOwnershipAuditPathV2(
  input: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
  eventIdV2: string,
): string {
  return `${associationOwnershipControlPathV2(input)}/auditEvents/` +
    pathIdentifier(eventIdV2);
}

export function associationOwnershipAuditEventIdV2(
  purposeV2: "transferCommit" | "ownerDeparture" | "custodyRecovery",
  sourceIdV2: string,
): string {
  if (!["transferCommit", "ownerDeparture", "custodyRecovery"].includes(purposeV2)) {
    fail("AD03_INVALID_REQUEST");
  }
  const sourceId = pathIdentifier(sourceIdV2);
  return `a-${canonicalSha256({
    contract: "association-ownership-audit-id-v2",
    purposeV2,
    sourceIdV2: sourceId,
  })}`;
}

export function recipientEligibilityEvidencePathV2(scopeValue: unknown): string {
  const data = record(scopeValue);
  if (data === null) fail("AD03_INVALID_REQUEST");
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  const uid = pathIdentifier(scope.authUidV2);
  return scope.authTenantIdV2 === null
    ? `recipientEligibilityV2Root/${uid}`
    : `recipientEligibilityV2Tenants/${pathIdentifier(scope.authTenantIdV2)}` +
      `/users/${uid}`;
}

function parsePrepareRequest(value: unknown): TransferPrepareRequestV2 {
  const data = record(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "transferIntentIdV2",
    "recipientAuthUidV2", "expectedControlVersionV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2) fail("AD03_INVALID_REQUEST");
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: pathIdentifier(data.associationId),
    transferIntentIdV2: pathIdentifier(data.transferIntentIdV2),
    recipientAuthUidV2: pathIdentifier(data.recipientAuthUidV2),
    expectedControlVersionV2: requiredCounter(data.expectedControlVersionV2),
  });
}

function parseResponseRequest(value: unknown): TransferResponseRequestV2 {
  const data = record(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "transferIntentIdV2",
    "expectedControlVersionV2", "responseV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2 ||
      !["accept", "decline"].includes(data.responseV2 as string)) {
    fail("AD03_INVALID_REQUEST");
  }
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: pathIdentifier(data.associationId),
    transferIntentIdV2: pathIdentifier(data.transferIntentIdV2),
    expectedControlVersionV2: requiredCounter(data.expectedControlVersionV2),
    responseV2: data.responseV2 as "accept" | "decline",
  });
}

function parseCommitRequest(value: unknown): TransferCommitRequestV2 {
  const data = record(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "transferIntentIdV2",
    "expectedControlVersionV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2) fail("AD03_INVALID_REQUEST");
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: pathIdentifier(data.associationId),
    transferIntentIdV2: pathIdentifier(data.transferIntentIdV2),
    expectedControlVersionV2: requiredCounter(data.expectedControlVersionV2),
  });
}

function parseDepartureRequest(value: unknown): OwnerDepartureRequestV2 {
  const data = record(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "departureOperationIdV2",
    "expectedControlVersionV2", "custodyChoiceV2", "transferIntentIdV2",
    "custodyCaseIdV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2 ||
      !ownershipDepartureChoicesV2.includes(data.custodyChoiceV2 as OwnershipDepartureChoiceV2)) {
    fail("AD03_INVALID_REQUEST");
  }
  const choice = data.custodyChoiceV2 as OwnershipDepartureChoiceV2;
  const transferIntentIdV2 = data.transferIntentIdV2 === null
    ? null
    : pathIdentifier(data.transferIntentIdV2);
  const custodyCaseIdV2 = data.custodyCaseIdV2 === null
    ? null
    : pathIdentifier(data.custodyCaseIdV2);
  if (
    (choice === "ordinary" && (transferIntentIdV2 !== null || custodyCaseIdV2 !== null)) ||
    (choice === "transferThenDelete" &&
      (transferIntentIdV2 === null || custodyCaseIdV2 !== null)) ||
    (choice === "suspendToCustody" && custodyCaseIdV2 === null)
  ) fail("AD03_INVALID_REQUEST");
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: pathIdentifier(data.associationId),
    departureOperationIdV2: pathIdentifier(data.departureOperationIdV2),
    expectedControlVersionV2: requiredCounter(data.expectedControlVersionV2),
    custodyChoiceV2: choice,
    transferIntentIdV2,
    custodyCaseIdV2,
  });
}

function parseSuccessorRequest(value: unknown): CustodySuccessorAcceptanceRequestV2 {
  const data = record(value);
  const keys = [
    "associationOwnershipSchemaVersionV2", "associationId", "custodyCaseIdV2",
    "successorAcceptanceIdV2", "expectedControlVersionV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.associationOwnershipSchemaVersionV2 !== 2) fail("AD03_INVALID_REQUEST");
  return Object.freeze({
    associationOwnershipSchemaVersionV2: 2,
    associationId: pathIdentifier(data.associationId),
    custodyCaseIdV2: pathIdentifier(data.custodyCaseIdV2),
    successorAcceptanceIdV2: pathIdentifier(data.successorAcceptanceIdV2),
    expectedControlVersionV2: requiredCounter(data.expectedControlVersionV2),
  });
}

function parseServiceCommand(value: unknown): ServiceCustodyRecoveryCommandV2 {
  const data = record(value);
  const keys = [
    "serviceCustodyCommandSchemaVersionV2", "authProjectIdV2", "authTenantIdV2",
    "associationId", "custodyPolicyIdV2", "custodyPolicyVersionV2",
    "custodyPolicyFingerprintV2", "custodyCaseIdV2", "commandIdV2", "operatorRefV2",
    "caseOwnerRefV2", "reviewEvidenceRefV2", "issuedAtSecV2", "expiresAtSecV2",
    "actionV2",
  ];
  if (data === null || !exactKeys(data, keys) ||
      data.serviceCustodyCommandSchemaVersionV2 !== 2 ||
      data.actionV2 !== "completeRecovery") fail("AD03_INVALID_REQUEST");
  let scope: AuthIncarnationScopeV2;
  try {
    scope = parseAuthIncarnationScopeV2({
      authProjectIdV2: data.authProjectIdV2,
      authTenantIdV2: data.authTenantIdV2,
      authUidV2: "scope-placeholder",
    });
  } catch {
    fail("AD03_INVALID_REQUEST");
  }
  const issuedAtSecV2 = requiredCounter(data.issuedAtSecV2);
  const expiresAtSecV2 = requiredCounter(data.expiresAtSecV2);
  if (data.custodyPolicyVersionV2 === 0 ||
      expiresAtSecV2 <= issuedAtSecV2 ||
      expiresAtSecV2 - issuedAtSecV2 > ASSOCIATION_OWNERSHIP_FRESH_AUTH_MAX_AGE_SEC_V2) {
    fail("AD03_INVALID_REQUEST");
  }
  return Object.freeze({
    serviceCustodyCommandSchemaVersionV2: 2,
    authProjectIdV2: scope.authProjectIdV2,
    authTenantIdV2: scope.authTenantIdV2,
    associationId: pathIdentifier(data.associationId),
    custodyPolicyIdV2: pathIdentifier(data.custodyPolicyIdV2),
    custodyPolicyVersionV2: requiredCounter(data.custodyPolicyVersionV2),
    custodyPolicyFingerprintV2:
      typeof data.custodyPolicyFingerprintV2 === "string" &&
      hashPattern.test(data.custodyPolicyFingerprintV2)
        ? data.custodyPolicyFingerprintV2
        : fail("AD03_INVALID_REQUEST"),
    custodyCaseIdV2: pathIdentifier(data.custodyCaseIdV2),
    commandIdV2: pathIdentifier(data.commandIdV2),
    operatorRefV2: opaqueReference(data.operatorRefV2),
    caseOwnerRefV2: opaqueReference(data.caseOwnerRefV2),
    reviewEvidenceRefV2: opaqueReference(data.reviewEvidenceRefV2),
    issuedAtSecV2,
    expiresAtSecV2,
    actionV2: "completeRecovery",
  });
}

async function authorizeFreshInTransactionV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  auth: VerifiedProviderAuthContextV2;
  configuredProjectId: string;
  attempt: CandidateSessionAttemptV2;
  associationId: string;
  nowSecV2: number;
}): Promise<{authority: ValidatedActiveAuthorityV2; authTimeSecV2: number}> {
  const tokenProof = extractProviderTokenProofV2(input.auth, input.configuredProjectId);
  if (tokenProof === null) fail("AD03_AUTHORITY_DENIED");
  if (!isFreshAt(tokenProof.authTimeSec, input.nowSecV2)) {
    fail("AD03_FRESH_AUTH_REQUIRED");
  }
  const expectedScope: AuthIncarnationScopeV2 = {
    authProjectIdV2: input.configuredProjectId,
    authTenantIdV2: tokenProof.authTenantIdV2,
    authUidV2: input.auth.uid,
  };
  const [lifecycle, membership] = await Promise.all([
    input.transaction.read(accountLifecycleAuthorityPathV2(expectedScope)),
    input.transaction.read(membershipAuthorityPathV2(expectedScope)),
  ]);
  const decision = evaluateAccountAuthorizationV2({
    ...input.attempt,
    expectedScope,
    tokenProof,
    lifecycle,
    membership,
    requiredCapability: "association.manage",
  });
  if (!decision.authorized || decision.binding.associationId !== input.associationId) {
    fail("AD03_AUTHORITY_DENIED");
  }
  return {authority: decision.binding, authTimeSecV2: tokenProof.authTimeSec};
}

async function revalidateDepartingAuthorityInTransactionV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  authority: ValidatedActiveAuthorityV2;
}): Promise<void> {
  // The brand rejects caller-forged bindings. The transaction reads below are
  // still mandatory: an authentic binding may have been minted before a
  // lifecycle, generation, epoch, membership, or capability change.
  const projection = buildStorageAuthorizationProjectionV2(input.authority);
  const [lifecycleRaw, membershipRaw] = await Promise.all([
    input.transaction.read(accountLifecycleAuthorityPathV2(projection)),
    input.transaction.read(membershipAuthorityPathV2(projection)),
  ]);
  let lifecycle: AccountLifecycleAuthorityV2;
  let membership: MembershipAuthorityV2;
  try {
    lifecycle = parseAccountLifecycleAuthorityV2(lifecycleRaw);
    membership = parseMembershipAuthorityV2(membershipRaw);
  } catch {
    fail("AD03_AUTHORITY_DENIED");
  }
  if (
    lifecycle.lifecycleStateV2 !== "active" ||
    membership.membershipStatusV2 !== "active" ||
    !sameScope(lifecycle, projection) ||
    !sameScope(membership, projection) ||
    lifecycle.accountGenerationV2 !== projection.accountGenerationV2 ||
    membership.accountGenerationV2 !== projection.accountGenerationV2 ||
    lifecycle.accountLifecycleEpochV2 !== projection.accountLifecycleEpochV2 ||
    membership.accountLifecycleEpochV2 !== projection.accountLifecycleEpochV2 ||
    lifecycle.reauthAfterSecV2 !== projection.reauthAfterSecV2 ||
    membership.associationId !== projection.associationId ||
    !membership.capabilities.includes("association.manage")
  ) fail("AD03_AUTHORITY_DENIED");
}

async function eligibleRecipientInTransactionV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  scope: AuthIncarnationScopeV2;
  associationId: string;
  nowSecV2: number;
  acceptedAuthTimeSecV2?: number;
}): Promise<RecoverableOwnerBindingV2> {
  const [lifecycleRaw, membershipRaw, evidenceRaw] = await Promise.all([
    input.transaction.read(accountLifecycleAuthorityPathV2(input.scope)),
    input.transaction.read(membershipAuthorityPathV2(input.scope)),
    input.transaction.read(recipientEligibilityEvidencePathV2(input.scope)),
  ]);
  let lifecycle: AccountLifecycleAuthorityV2;
  let membership: MembershipAuthorityV2;
  let evidence: RecipientEligibilityEvidenceV2;
  try {
    lifecycle = parseAccountLifecycleAuthorityV2(lifecycleRaw);
    membership = parseMembershipAuthorityV2(membershipRaw);
    evidence = parseRecipientEligibilityEvidenceV2(evidenceRaw);
  } catch {
    fail("AD03_RECIPIENT_INELIGIBLE");
  }
  if (
    lifecycle.lifecycleStateV2 !== "active" ||
    membership.membershipStatusV2 !== "active" ||
    !sameScope(lifecycle, input.scope) ||
    !sameScope(membership, input.scope) ||
    !sameScope(evidence, input.scope) ||
    lifecycle.accountGenerationV2 !== membership.accountGenerationV2 ||
    lifecycle.accountGenerationV2 !== evidence.accountGenerationV2 ||
    lifecycle.accountLifecycleEpochV2 !== membership.accountLifecycleEpochV2 ||
    lifecycle.accountLifecycleEpochV2 !== evidence.accountLifecycleEpochV2 ||
    membership.associationId !== input.associationId ||
    !membership.capabilities.includes("association.manage") ||
    (input.acceptedAuthTimeSecV2 !== undefined &&
      (!safeCounter(input.acceptedAuthTimeSecV2) ||
       input.acceptedAuthTimeSecV2 > input.nowSecV2 ||
       input.acceptedAuthTimeSecV2 <= lifecycle.reauthAfterSecV2)) ||
    evidence.authIdentityStateV2 !== "present" ||
    evidence.recoveryChannelStateV2 !== "verified" ||
    evidence.checkedAtSecV2 > input.nowSecV2 ||
    evidence.expiresAtSecV2 < input.nowSecV2
  ) fail("AD03_RECIPIENT_INELIGIBLE");
  return Object.freeze({
    ownerBindingSchemaVersionV2: 2,
    ownerBindingIdV2: recoverableOwnerBindingIdV2({
      ...input.scope,
      accountGenerationV2: lifecycle.accountGenerationV2,
      accountLifecycleEpochV2: lifecycle.accountLifecycleEpochV2,
    }),
    ...input.scope,
    accountGenerationV2: lifecycle.accountGenerationV2,
    accountLifecycleEpochV2: lifecycle.accountLifecycleEpochV2,
    bindingVersionV2: 1,
  });
}

function transferRequestFingerprintV2(input: {
  authority: ValidatedActiveAuthorityV2;
  request: TransferPrepareRequestV2;
}): string {
  return canonicalSha256({
    contract: "association-ownership-transfer-prepare-v2",
    associationId: input.request.associationId,
    transferIntentIdV2: input.request.transferIntentIdV2,
    recipientAuthUidV2: input.request.recipientAuthUidV2,
    expectedControlVersionV2: input.request.expectedControlVersionV2,
    preparedBy: {
      ...input.authority.scope,
      accountGenerationV2: input.authority.accountGenerationV2,
      accountLifecycleEpochV2: input.authority.accountLifecycleEpochV2,
    },
  });
}

function departureRequestFingerprintV2(input: {
  authority: ValidatedActiveAuthorityV2;
  request: OwnerDepartureRequestV2;
}): string {
  return canonicalSha256({
    contract: "association-owner-departure-v2",
    associationId: input.request.associationId,
    departureOperationIdV2: input.request.departureOperationIdV2,
    expectedControlVersionV2: input.request.expectedControlVersionV2,
    custodyChoiceV2: input.request.custodyChoiceV2,
    transferIntentIdV2: input.request.transferIntentIdV2,
    custodyCaseIdV2: input.request.custodyCaseIdV2,
    departingOwner: {
      ...input.authority.scope,
      accountGenerationV2: input.authority.accountGenerationV2,
      accountLifecycleEpochV2: input.authority.accountLifecycleEpochV2,
    },
  });
}

function custodyPolicyReadyForCandidateV2(
  policy: ServiceCustodyPolicyV2 | null,
): policy is ServiceCustodyPolicyV2 {
  return policy !== null &&
    policy.configurationClassV2 === "testFixture" &&
    policy.decisionStateV2 === "testOnly" &&
    policy.namedOperatorRefV2 !== null &&
    policy.namedCaseOwnerRefV2 !== null &&
    policy.escalationCoverageRefV2 !== null &&
    policy.independentInfrastructureOwnerRefV2 !== null &&
    policy.recoveryDeadlineSecV2 !== null &&
    policy.recoveryDeadlineSecV2 > 0;
}

export function productionCustodyActivationReadyV2(input: {
  policy: unknown;
  gateG3Passed: boolean;
}): false {
  void input.policy;
  void input.gateG3Passed;
  return false;
}

function ownershipControlWith(input: {
  current: AssociationOwnershipControlV2;
  operationalStateV2: AssociationOperationalStateV2;
  recoverableOwnersV2: readonly RecoverableOwnerBindingV2[];
  pendingTransferIntentIdV2: string | null;
  activeCustodyCaseIdV2: string | null;
  custodyPolicyIdV2: string | null;
}): AssociationOwnershipControlV2 {
  return parseAssociationOwnershipControlV2({
    ...input.current,
    controlVersionV2: incrementCounter(input.current.controlVersionV2),
    operationalStateV2: input.operationalStateV2,
    recoverableOwnersV2: sortedOwners(input.recoverableOwnersV2),
    pendingTransferIntentIdV2: input.pendingTransferIntentIdV2,
    activeCustodyCaseIdV2: input.activeCustodyCaseIdV2,
    custodyPolicyIdV2: input.custodyPolicyIdV2,
  });
}

function expireLinkedTransferV2(input: {
  control: AssociationOwnershipControlV2;
  intent: OwnershipTransferIntentV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  nowSecV2: number;
  replacementTransferIntentIdV2: string | null;
}): {control: AssociationOwnershipControlV2; intent: OwnershipTransferIntentV2} {
  assertTransferIntentLocatorV2({
    intent: input.intent,
    scope: input.scope,
    transferIntentIdV2: input.intent.transferIntentIdV2,
  });
  const linkedControlVersionV2 = input.intent.stateV2 === "pendingRecipientAcceptance"
    ? input.intent.controlVersionAtPrepareV2
    : input.intent.stateV2 === "recipientAccepted"
      ? input.intent.controlVersionAtResponseV2
      : null;
  if (
    input.control.operationalStateV2 !== "transferPending" ||
    input.control.pendingTransferIntentIdV2 !== input.intent.transferIntentIdV2 ||
    linkedControlVersionV2 !== input.control.controlVersionV2 ||
    !input.control.recoverableOwnersV2.some((owner) =>
      ownerIdentityEquals(owner, input.intent.preparedByOwnerV2)) ||
    input.nowSecV2 <= input.intent.expiresAtSecV2 ||
    input.replacementTransferIntentIdV2 === input.intent.transferIntentIdV2
  ) fail("AD03_TRANSFER_NOT_READY");
  const nextControl = ownershipControlWith({
    current: input.control,
    operationalStateV2: input.replacementTransferIntentIdV2 === null
      ? "operating"
      : "transferPending",
    recoverableOwnersV2: input.control.recoverableOwnersV2,
    pendingTransferIntentIdV2: input.replacementTransferIntentIdV2,
    activeCustodyCaseIdV2: null,
    custodyPolicyIdV2: input.control.custodyPolicyIdV2,
  });
  const expiredIntent = parseOwnershipTransferIntentV2({
    ...input.intent,
    stateV2: "expired",
    controlVersionAtResponseV2: nextControl.controlVersionV2,
    controlVersionAtCommitV2: null,
    respondedAtSecV2: input.nowSecV2,
    committedAtSecV2: null,
    recipientAcceptedAuthTimeSecV2: null,
  });
  return {control: nextControl, intent: expiredIntent};
}

function auditEventV2(input: {
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  eventIdV2: string;
  eventTypeV2: AssociationOwnershipAuditEventV2["eventTypeV2"];
  before: number;
  after: number;
  ownerBindingRefV2: string | null;
  counterpartyBindingRefV2: string | null;
  transferIntentIdV2: string | null;
  custodyCaseIdV2: string | null;
  custodyPolicyIdV2: string | null;
  nowSecV2: number;
}): AssociationOwnershipAuditEventV2 {
  return Object.freeze({
    associationOwnershipAuditSchemaVersionV2: 2,
    ...input.scope,
    eventIdV2: pathIdentifier(input.eventIdV2),
    eventTypeV2: input.eventTypeV2,
    controlVersionBeforeV2: input.before,
    controlVersionAfterV2: input.after,
    ownerBindingRefV2: input.ownerBindingRefV2,
    counterpartyBindingRefV2: input.counterpartyBindingRefV2,
    transferIntentIdV2: input.transferIntentIdV2,
    custodyCaseIdV2: input.custodyCaseIdV2,
    custodyPolicyIdV2: input.custodyPolicyIdV2,
    recordedAtSecV2: input.nowSecV2,
  });
}

function assertControlVersion(
  control: AssociationOwnershipControlV2,
  expected: number,
): void {
  if (control.controlVersionV2 !== expected) fail("AD03_CONTROL_CONFLICT");
}

function assertControlScope(
  control: AssociationOwnershipControlV2,
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
): void {
  if (!sameAssociationScope(control, scope)) fail("AD03_CONTROL_CONFLICT");
}

async function readControlV2(
  transaction: CandidateAuthorityTransactionV2,
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string},
): Promise<AssociationOwnershipControlV2> {
  const raw = await transaction.read(associationOwnershipControlPathV2(scope));
  if (raw === null) fail("AD03_CONTROL_MISSING");
  const control = parseAssociationOwnershipControlV2(raw);
  assertControlScope(control, scope);
  return control;
}

export async function prepareCandidateOwnershipTransferV2(input: OwnershipServiceInputV2 & {
  request: unknown;
}): Promise<OwnershipTransferIntentV2> {
  const request = parsePrepareRequest(input.request);
  if (!safeCounter(input.nowSecV2)) fail("AD03_INVALID_REQUEST");
  return input.repository.runTransaction(async (transaction) => {
    const {authority} = await authorizeFreshInTransactionV2({
      transaction,
      auth: input.auth,
      configuredProjectId: input.configuredProjectId,
      attempt: input.attempt,
      associationId: request.associationId,
      nowSecV2: input.nowSecV2,
    });
    assertAssociation(authority, request.associationId);
    const scope = associationScopeFromAuthority(authority);
    const intentPath = ownershipTransferIntentPathV2(scope, request.transferIntentIdV2);
    const [control, existingRaw] = await Promise.all([
      readControlV2(transaction, scope),
      transaction.read(intentPath),
    ]);
    const requestFingerprintV2 = transferRequestFingerprintV2({authority, request});
    if (existingRaw !== null) {
      const existing = parseOwnershipTransferIntentV2(existingRaw);
      assertTransferIntentLocatorV2({
        intent: existing,
        scope,
        transferIntentIdV2: request.transferIntentIdV2,
      });
      if (existing.requestFingerprintV2 !== requestFingerprintV2) {
        fail("AD03_TRANSFER_CONFLICT");
      }
      return existing;
    }
    const departing = recoverableOwnerFromAuthorityV2(authority);
    if (!control.recoverableOwnersV2.some((owner) => ownerIdentityEquals(owner, departing))) {
      fail("AD03_NOT_RECOVERABLE_OWNER");
    }
    assertControlVersion(control, request.expectedControlVersionV2);
    let expiredIntent: OwnershipTransferIntentV2 | null = null;
    let nextControl: AssociationOwnershipControlV2;
    if (control.operationalStateV2 === "operating" &&
        control.pendingTransferIntentIdV2 === null) {
      nextControl = ownershipControlWith({
        current: control,
        operationalStateV2: "transferPending",
        recoverableOwnersV2: control.recoverableOwnersV2,
        pendingTransferIntentIdV2: request.transferIntentIdV2,
        activeCustodyCaseIdV2: null,
        custodyPolicyIdV2: control.custodyPolicyIdV2,
      });
    } else if (control.operationalStateV2 === "transferPending" &&
        control.pendingTransferIntentIdV2 !== null &&
        control.pendingTransferIntentIdV2 !== request.transferIntentIdV2) {
      // A fresh ID is the replacement boundary. The old intent is closed and
      // the new unaccepted intent is installed under one control-version write.
      const pendingIntentRaw = await transaction.read(ownershipTransferIntentPathV2(
        scope,
        control.pendingTransferIntentIdV2,
      ));
      if (pendingIntentRaw === null) fail("AD03_TRANSFER_NOT_READY");
      const transition = expireLinkedTransferV2({
        control,
        intent: parseOwnershipTransferIntentV2(pendingIntentRaw),
        scope,
        nowSecV2: input.nowSecV2,
        replacementTransferIntentIdV2: request.transferIntentIdV2,
      });
      nextControl = transition.control;
      expiredIntent = transition.intent;
    } else {
      fail("AD03_CONTROL_CONFLICT");
    }
    const recipientScope: AuthIncarnationScopeV2 = {
      authProjectIdV2: scope.authProjectIdV2,
      authTenantIdV2: scope.authTenantIdV2,
      authUidV2: request.recipientAuthUidV2,
    };
    const recipient = await eligibleRecipientInTransactionV2({
      transaction,
      scope: recipientScope,
      associationId: scope.associationId,
      nowSecV2: input.nowSecV2,
    });
    if (ownerIdentityEquals(departing, recipient) ||
        control.recoverableOwnersV2.some((owner) => ownerIdentityEquals(owner, recipient))) {
      fail("AD03_RECIPIENT_INELIGIBLE");
    }
    const intent = parseOwnershipTransferIntentV2({
      ownershipTransferIntentSchemaVersionV2: 2,
      ...scope,
      transferIntentIdV2: request.transferIntentIdV2,
      requestFingerprintV2,
      stateV2: "pendingRecipientAcceptance",
      preparedByOwnerV2: departing,
      recipientOwnerV2: recipient,
      controlVersionAtPrepareV2: nextControl.controlVersionV2,
      controlVersionAtResponseV2: null,
      controlVersionAtCommitV2: null,
      preparedAtSecV2: input.nowSecV2,
      expiresAtSecV2: input.nowSecV2 + ASSOCIATION_TRANSFER_TTL_SEC_V2,
      respondedAtSecV2: null,
      committedAtSecV2: null,
      recipientAcceptedAuthTimeSecV2: null,
    });
    if (expiredIntent !== null) {
      transaction.write(
        ownershipTransferIntentPathV2(scope, expiredIntent.transferIntentIdV2),
        wireRecord(expiredIntent),
      );
    }
    transaction.write(associationOwnershipControlPathV2(scope), wireRecord(nextControl));
    transaction.write(intentPath, wireRecord(intent));
    return intent;
  });
}

export async function respondToCandidateOwnershipTransferV2(
  input: OwnershipServiceInputV2 & {request: unknown},
): Promise<OwnershipTransferIntentV2> {
  const request = parseResponseRequest(input.request);
  if (!safeCounter(input.nowSecV2)) fail("AD03_INVALID_REQUEST");
  return input.repository.runTransaction(async (transaction) => {
    const {authority, authTimeSecV2} = await authorizeFreshInTransactionV2({
      transaction,
      auth: input.auth,
      configuredProjectId: input.configuredProjectId,
      attempt: input.attempt,
      associationId: request.associationId,
      nowSecV2: input.nowSecV2,
    });
    const scope = associationScopeFromAuthority(authority);
    const [control, intentRaw] = await Promise.all([
      readControlV2(transaction, scope),
      transaction.read(ownershipTransferIntentPathV2(scope, request.transferIntentIdV2)),
    ]);
    if (intentRaw === null) fail("AD03_TRANSFER_NOT_READY");
    const intent = parseOwnershipTransferIntentV2(intentRaw);
    assertTransferIntentLocatorV2({
      intent,
      scope,
      transferIntentIdV2: request.transferIntentIdV2,
    });
    if (!ownerMatchesAuthority(intent.recipientOwnerV2, authority)) {
      fail("AD03_AUTHORITY_DENIED");
    }
    if (["pendingRecipientAcceptance", "recipientAccepted"].includes(intent.stateV2) &&
        input.nowSecV2 > intent.expiresAtSecV2) {
      const linkedControlVersionV2 = intent.stateV2 === "pendingRecipientAcceptance"
        ? intent.controlVersionAtPrepareV2
        : intent.controlVersionAtResponseV2;
      const exactResponseVersionV2 = request.expectedControlVersionV2 ===
        intent.controlVersionAtPrepareV2 &&
        (intent.stateV2 === "pendingRecipientAcceptance" ||
          intent.controlVersionAtResponseV2 === intent.controlVersionAtPrepareV2 + 1);
      if (
        control.operationalStateV2 !== "transferPending" ||
        control.pendingTransferIntentIdV2 !== intent.transferIntentIdV2 ||
        linkedControlVersionV2 !== control.controlVersionV2 ||
        !exactResponseVersionV2 ||
        !control.recoverableOwnersV2.some((owner) =>
          ownerIdentityEquals(owner, intent.preparedByOwnerV2))
      ) fail("AD03_CONTROL_CONFLICT");
      fail("AD03_TRANSFER_NOT_READY");
    }
    if (intent.stateV2 === "recipientAccepted" && request.responseV2 === "accept") {
      if (control.operationalStateV2 !== "transferPending" ||
          control.pendingTransferIntentIdV2 !== request.transferIntentIdV2 ||
          intent.controlVersionAtResponseV2 !== control.controlVersionV2 ||
          request.expectedControlVersionV2 !== intent.controlVersionAtPrepareV2) {
        fail("AD03_CONTROL_CONFLICT");
      }
      return intent;
    }
    if (intent.stateV2 === "declined" && request.responseV2 === "decline") {
      if (control.operationalStateV2 !== "operating" ||
          control.pendingTransferIntentIdV2 !== null ||
          intent.controlVersionAtResponseV2 !== control.controlVersionV2 ||
          request.expectedControlVersionV2 !== intent.controlVersionAtPrepareV2) {
        fail("AD03_CONTROL_CONFLICT");
      }
      return intent;
    }
    if (intent.stateV2 !== "pendingRecipientAcceptance") {
      fail("AD03_RECIPIENT_RESPONSE_CONFLICT");
    }
    assertControlVersion(control, request.expectedControlVersionV2);
    if (control.operationalStateV2 !== "transferPending" ||
        control.pendingTransferIntentIdV2 !== intent.transferIntentIdV2) {
      fail("AD03_CONTROL_CONFLICT");
    }
    const currentRecipient = await eligibleRecipientInTransactionV2({
      transaction,
      scope: intent.recipientOwnerV2,
      associationId: scope.associationId,
      nowSecV2: input.nowSecV2,
    });
    if (!ownerIdentityEquals(currentRecipient, intent.recipientOwnerV2)) {
      fail("AD03_RECIPIENT_INELIGIBLE");
    }
    const nextControl = ownershipControlWith({
      current: control,
      operationalStateV2: request.responseV2 === "accept" ? "transferPending" : "operating",
      recoverableOwnersV2: control.recoverableOwnersV2,
      pendingTransferIntentIdV2:
        request.responseV2 === "accept" ? intent.transferIntentIdV2 : null,
      activeCustodyCaseIdV2: null,
      custodyPolicyIdV2: control.custodyPolicyIdV2,
    });
    const stateV2: TransferIntentStateV2 = request.responseV2 === "accept"
      ? "recipientAccepted"
      : "declined";
    const updated = parseOwnershipTransferIntentV2({
      ...intent,
      stateV2,
      controlVersionAtResponseV2: nextControl.controlVersionV2,
      respondedAtSecV2: input.nowSecV2,
      recipientAcceptedAuthTimeSecV2:
        stateV2 === "recipientAccepted" ? authTimeSecV2 : null,
    });
    transaction.write(associationOwnershipControlPathV2(scope), wireRecord(nextControl));
    transaction.write(
      ownershipTransferIntentPathV2(scope, intent.transferIntentIdV2),
      wireRecord(updated),
    );
    return updated;
  });
}

async function revalidateAcceptedRecipientV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  intent: OwnershipTransferIntentV2;
  nowSecV2: number;
}): Promise<RecoverableOwnerBindingV2> {
  if (input.intent.stateV2 !== "recipientAccepted" ||
      input.intent.recipientAcceptedAuthTimeSecV2 === null ||
      input.nowSecV2 > input.intent.expiresAtSecV2) {
    fail("AD03_TRANSFER_NOT_READY");
  }
  const recipient = await eligibleRecipientInTransactionV2({
    transaction: input.transaction,
    scope: input.intent.recipientOwnerV2,
    associationId: input.scope.associationId,
    nowSecV2: input.nowSecV2,
    acceptedAuthTimeSecV2: input.intent.recipientAcceptedAuthTimeSecV2,
  });
  if (!ownerIdentityEquals(recipient, input.intent.recipientOwnerV2)) {
    fail("AD03_RECIPIENT_INELIGIBLE");
  }
  return recipient;
}

function committedIntentV2(
  intent: OwnershipTransferIntentV2,
  controlVersionAtCommitV2: number,
  nowSecV2: number,
): OwnershipTransferIntentV2 {
  return parseOwnershipTransferIntentV2({
    ...intent,
    stateV2: "committed",
    controlVersionAtCommitV2,
    committedAtSecV2: nowSecV2,
  });
}

async function commitAcceptedTransferInTransactionV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  control: AssociationOwnershipControlV2;
  intent: OwnershipTransferIntentV2;
  departing: RecoverableOwnerBindingV2;
  expectedTransferIntentIdV2: string;
  nowSecV2: number;
  auditEventIdV2: string;
}): Promise<{control: AssociationOwnershipControlV2; intent: OwnershipTransferIntentV2}> {
  assertTransferIntentLocatorV2({
    intent: input.intent,
    scope: input.scope,
    transferIntentIdV2: input.expectedTransferIntentIdV2,
  });
  if (
    input.control.operationalStateV2 !== "transferPending" ||
    input.control.pendingTransferIntentIdV2 !== input.expectedTransferIntentIdV2 ||
    input.intent.controlVersionAtResponseV2 !== input.control.controlVersionV2 ||
    !ownerIdentityEquals(input.intent.preparedByOwnerV2, input.departing)
  ) fail("AD03_TRANSFER_NOT_READY");
  const recipient = await revalidateAcceptedRecipientV2({
    transaction: input.transaction,
    scope: input.scope,
    intent: input.intent,
    nowSecV2: input.nowSecV2,
  });
  const retained = input.control.recoverableOwnersV2.filter((owner) =>
    !ownerIdentityEquals(owner, input.departing) && !ownerIdentityEquals(owner, recipient));
  const nextControl = ownershipControlWith({
    current: input.control,
    operationalStateV2: "operating",
    recoverableOwnersV2: [...retained, recipient],
    pendingTransferIntentIdV2: null,
    activeCustodyCaseIdV2: null,
    custodyPolicyIdV2: input.control.custodyPolicyIdV2,
  });
  const committed = committedIntentV2(
    input.intent,
    nextControl.controlVersionV2,
    input.nowSecV2,
  );
  input.transaction.write(
    associationOwnershipControlPathV2(input.scope),
    wireRecord(nextControl),
  );
  input.transaction.write(
    ownershipTransferIntentPathV2(input.scope, input.intent.transferIntentIdV2),
    wireRecord(committed),
  );
  input.transaction.write(
    associationOwnershipAuditPathV2(input.scope, input.auditEventIdV2),
    wireRecord(auditEventV2({
      scope: input.scope,
      eventIdV2: input.auditEventIdV2,
      eventTypeV2: "transferCommitted",
      before: input.control.controlVersionV2,
      after: nextControl.controlVersionV2,
      ownerBindingRefV2: input.departing.ownerBindingIdV2,
      counterpartyBindingRefV2: recipient.ownerBindingIdV2,
      transferIntentIdV2: input.intent.transferIntentIdV2,
      custodyCaseIdV2: null,
      custodyPolicyIdV2: nextControl.custodyPolicyIdV2,
      nowSecV2: input.nowSecV2,
    })),
  );
  return {control: nextControl, intent: committed};
}

export async function commitCandidateOwnershipTransferV2(
  input: OwnershipServiceInputV2 & {request: unknown},
): Promise<OwnershipTransferIntentV2> {
  const request = parseCommitRequest(input.request);
  if (!safeCounter(input.nowSecV2)) fail("AD03_INVALID_REQUEST");
  const outcome = await input.repository.runTransaction(async (transaction) => {
    const {authority} = await authorizeFreshInTransactionV2({
      transaction,
      auth: input.auth,
      configuredProjectId: input.configuredProjectId,
      attempt: input.attempt,
      associationId: request.associationId,
      nowSecV2: input.nowSecV2,
    });
    const scope = associationScopeFromAuthority(authority);
    const [control, intentRaw] = await Promise.all([
      readControlV2(transaction, scope),
      transaction.read(ownershipTransferIntentPathV2(scope, request.transferIntentIdV2)),
    ]);
    if (intentRaw === null) fail("AD03_TRANSFER_NOT_READY");
    const intent = parseOwnershipTransferIntentV2(intentRaw);
    assertTransferIntentLocatorV2({
      intent,
      scope,
      transferIntentIdV2: request.transferIntentIdV2,
    });
    if (intent.stateV2 === "committed" && ownerMatchesAuthority(intent.preparedByOwnerV2, authority)) {
      const replayIsConsistent = control.operationalStateV2 === "operating" &&
        control.pendingTransferIntentIdV2 === null &&
        intent.controlVersionAtCommitV2 === control.controlVersionV2 &&
        request.expectedControlVersionV2 === intent.controlVersionAtResponseV2 &&
        control.recoverableOwnersV2.some((owner) =>
          ownerIdentityEquals(owner, intent.recipientOwnerV2)) &&
        !control.recoverableOwnersV2.some((owner) =>
          ownerIdentityEquals(owner, intent.preparedByOwnerV2));
      if (!replayIsConsistent) fail("AD03_CONTROL_CONFLICT");
      return {kindV2: "committed" as const, intent};
    }
    const departing = recoverableOwnerFromAuthorityV2(authority);
    if (!control.recoverableOwnersV2.some((owner) => ownerIdentityEquals(owner, departing))) {
      fail("AD03_NOT_RECOVERABLE_OWNER");
    }
    if (intent.stateV2 === "expired") {
      const exactExpiryReplay = control.operationalStateV2 === "operating" &&
        control.pendingTransferIntentIdV2 === null &&
        intent.controlVersionAtResponseV2 === control.controlVersionV2 &&
        control.controlVersionV2 > 0 &&
        request.expectedControlVersionV2 === control.controlVersionV2 - 1;
      if (!exactExpiryReplay) fail("AD03_CONTROL_CONFLICT");
      return {kindV2: "expired" as const, intent};
    }
    assertControlVersion(control, request.expectedControlVersionV2);
    if (["pendingRecipientAcceptance", "recipientAccepted"].includes(intent.stateV2) &&
        input.nowSecV2 > intent.expiresAtSecV2) {
      const expired = expireLinkedTransferV2({
        control,
        intent,
        scope,
        nowSecV2: input.nowSecV2,
        replacementTransferIntentIdV2: null,
      });
      transaction.write(
        associationOwnershipControlPathV2(scope),
        wireRecord(expired.control),
      );
      transaction.write(
        ownershipTransferIntentPathV2(scope, intent.transferIntentIdV2),
        wireRecord(expired.intent),
      );
      return {kindV2: "expired" as const, intent: expired.intent};
    }
    const result = await commitAcceptedTransferInTransactionV2({
      transaction,
      scope,
      control,
      intent,
      departing,
      expectedTransferIntentIdV2: request.transferIntentIdV2,
      nowSecV2: input.nowSecV2,
      auditEventIdV2: associationOwnershipAuditEventIdV2(
        "transferCommit",
        intent.transferIntentIdV2,
      ),
    });
    return {kindV2: "committed" as const, intent: result.intent};
  });
  // Throw only after the transaction returns so the fail-closed expiry writes
  // are durable; throwing inside a Firestore transaction would roll them back.
  if (outcome.kindV2 === "expired") fail("AD03_TRANSFER_NOT_READY");
  return outcome.intent;
}

async function optionalCandidatePolicyV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  candidateTestCustodyPolicyIdV2: string | null;
}): Promise<ServiceCustodyPolicyV2 | null> {
  if (input.candidateTestCustodyPolicyIdV2 === null) return null;
  const raw = await input.transaction.read(serviceCustodyPolicyPathV2(
    input.scope,
    input.candidateTestCustodyPolicyIdV2,
  ));
  if (raw === null) return null;
  let policy: ServiceCustodyPolicyV2;
  try {
    policy = parseServiceCustodyPolicyV2(raw);
  } catch {
    return null;
  }
  return sameAssociationScope(policy, input.scope) &&
    policy.custodyPolicyIdV2 === input.candidateTestCustodyPolicyIdV2
    ? policy
    : null;
}

function custodyCaseV2(input: {
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  custodyCaseIdV2: string;
  policy: ServiceCustodyPolicyV2 | null;
  controlVersionV2: number;
  nowSecV2: number;
}): CustodyRecoveryCaseV2 {
  const policy = input.policy;
  const configured = custodyPolicyReadyForCandidateV2(policy);
  return parseCustodyRecoveryCaseV2({
    custodyRecoveryCaseSchemaVersionV2: 2,
    ...input.scope,
    custodyCaseIdV2: input.custodyCaseIdV2,
    stateV2: configured ? "suspended" : "operatorUnassigned",
    safeErrorCodeV2: configured ? null : "CUSTODY_CONFLICT",
    custodyPolicyIdV2: configured ? policy.custodyPolicyIdV2 : null,
    custodyPolicyVersionV2: configured ? policy.custodyPolicyVersionV2 : null,
    custodyPolicyFingerprintV2: configured
      ? serviceCustodyPolicyFingerprintV2(policy)
      : null,
    namedOperatorRefV2: configured ? policy.namedOperatorRefV2 : null,
    namedCaseOwnerRefV2: configured ? policy.namedCaseOwnerRefV2 : null,
    controlVersionAtOpenV2: input.controlVersionV2,
    currentControlVersionV2: input.controlVersionV2,
    openedAtSecV2: input.nowSecV2,
    deadlineAtSecV2: configured && policy.recoveryDeadlineSecV2 !== null
      ? input.nowSecV2 + policy.recoveryDeadlineSecV2
      : null,
    successorOwnerV2: null,
    successorAcceptanceIdV2: null,
    successorAcceptedAtSecV2: null,
    successorAcceptedAuthTimeSecV2: null,
    reviewEvidenceRefV2: null,
    resolvedAtSecV2: null,
  });
}

function ownerDepartureReceiptMatchesV2(input: {
  receipt: OwnerDepartureReceiptV2;
  request: OwnerDepartureRequestV2;
  authority: ValidatedActiveAuthorityV2;
  scope: {authProjectIdV2: string; authTenantIdV2: string | null; associationId: string};
  requestFingerprintV2: string;
}): boolean {
  const receipt = input.receipt;
  const request = input.request;
  const expectedOutcomeV2: CustodyOutcome =
    request.custodyChoiceV2 === "suspendToCustody" &&
      receipt.custodyStateV2 === "custodyRequired"
      ? "policyBlockedButDeletionMustReceiveOperationalResolution"
      : request.custodyChoiceV2;
  const common = receipt.requestFingerprintV2 === input.requestFingerprintV2 &&
    sameScope(receipt, input.authority.scope) &&
    sameAssociationScope(receipt, input.scope) &&
    receipt.associationId === request.associationId &&
    receipt.departureOperationIdV2 === request.departureOperationIdV2 &&
    receipt.accountGenerationV2 === input.authority.accountGenerationV2 &&
    receipt.accountLifecycleEpochV2 === input.authority.accountLifecycleEpochV2 &&
    receipt.outcomeV2 === expectedOutcomeV2 &&
    receipt.controlVersionBeforeV2 === request.expectedControlVersionV2 &&
    receipt.controlVersionAfterV2 === request.expectedControlVersionV2 + 1 &&
    receipt.transferIntentIdV2 === request.transferIntentIdV2 &&
    receipt.custodyCaseIdV2 === request.custodyCaseIdV2;
  if (!common) return false;
  if (request.custodyChoiceV2 === "ordinary") {
    return receipt.custodyStateV2 === "operating" &&
      !receipt.requiresOperationalAttentionV2;
  }
  if (request.custodyChoiceV2 === "transferThenDelete") {
    return receipt.custodyStateV2 === "operating" &&
      !receipt.requiresOperationalAttentionV2;
  }
  return (receipt.custodyStateV2 === "suspendedToCustody" &&
      !receipt.requiresOperationalAttentionV2) ||
    (receipt.custodyStateV2 === "custodyRequired" &&
      receipt.requiresOperationalAttentionV2);
}

/**
 * Transaction-composable AD04 seam. The caller passes an AD02-branded active
 * binding before any staged lifecycle writes. A first execution re-reads and
 * validates lifecycle and membership in this transaction; an exact receipt
 * replay is read-only. This helper never mutates lifecycle/Auth itself.
 */
export async function applyOwnerDepartureInTransactionV2(input: {
  transaction: CandidateAuthorityTransactionV2;
  departingAuthority: ValidatedActiveAuthorityV2;
  request: unknown;
  nowSecV2: number;
  candidateTestCustodyPolicyIdV2: string | null;
}): Promise<OwnerDepartureReceiptV2> {
  // This is a brand check: structurally forged authority objects are rejected.
  void buildStorageAuthorizationProjectionV2(input.departingAuthority);
  const request = parseDepartureRequest(input.request);
  if (!safeCounter(input.nowSecV2)) fail("AD03_INVALID_REQUEST");
  assertAssociation(input.departingAuthority, request.associationId);
  const scope = associationScopeFromAuthority(input.departingAuthority);
  const receiptPath = ownerDepartureReceiptPathV2(scope, request.departureOperationIdV2);
  const [control, existingReceiptRaw] = await Promise.all([
    readControlV2(input.transaction, scope),
    input.transaction.read(receiptPath),
  ]);
  const requestFingerprintV2 = departureRequestFingerprintV2({
    authority: input.departingAuthority,
    request,
  });
  if (existingReceiptRaw !== null) {
    const receipt = parseOwnerDepartureReceiptV2(existingReceiptRaw);
    if (!ownerDepartureReceiptMatchesV2({
      receipt,
      request,
      authority: input.departingAuthority,
      scope,
      requestFingerprintV2,
    })) {
      fail("AD03_TRANSFER_CONFLICT");
    }
    return receipt;
  }
  await revalidateDepartingAuthorityInTransactionV2({
    transaction: input.transaction,
    authority: input.departingAuthority,
  });
  assertControlVersion(control, request.expectedControlVersionV2);
  const departing = recoverableOwnerFromAuthorityV2(input.departingAuthority);
  if (!control.recoverableOwnersV2.some((owner) => ownerIdentityEquals(owner, departing))) {
    fail("AD03_NOT_RECOVERABLE_OWNER");
  }
  const otherOwners = control.recoverableOwnersV2.filter((owner) =>
    !ownerIdentityEquals(owner, departing));
  let nextControl: AssociationOwnershipControlV2;
  let transferIntentIdV2: string | null = null;
  let custodyCaseIdV2: string | null = null;
  let requiresOperationalAttentionV2 = false;
  let eventTypeV2: AssociationOwnershipAuditEventV2["eventTypeV2"] = "ownerDeparted";
  let eventCounterparty: string | null = null;
  if (otherOwners.length > 0) {
    if (request.custodyChoiceV2 !== "ordinary" ||
        !["operating", "transferPending"].includes(control.operationalStateV2)) {
      fail("AD03_CONTROL_CONFLICT");
    }
    if (control.operationalStateV2 === "operating") {
      nextControl = ownershipControlWith({
        current: control,
        operationalStateV2: "operating",
        recoverableOwnersV2: otherOwners,
        pendingTransferIntentIdV2: null,
        activeCustodyCaseIdV2: null,
        custodyPolicyIdV2: control.custodyPolicyIdV2,
      });
    } else {
      if (control.pendingTransferIntentIdV2 === null) fail("AD03_CONTROL_CONFLICT");
      const pendingIntentRaw = await input.transaction.read(
        ownershipTransferIntentPathV2(scope, control.pendingTransferIntentIdV2),
      );
      if (pendingIntentRaw === null) fail("AD03_TRANSFER_NOT_READY");
      const pendingIntent = parseOwnershipTransferIntentV2(pendingIntentRaw);
      assertTransferIntentLocatorV2({
        intent: pendingIntent,
        scope,
        transferIntentIdV2: control.pendingTransferIntentIdV2,
      });
      if (!["pendingRecipientAcceptance", "recipientAccepted"].includes(
        pendingIntent.stateV2,
      )) fail("AD03_TRANSFER_NOT_READY");
      if (!ownerIdentityEquals(pendingIntent.preparedByOwnerV2, departing) &&
          !otherOwners.some((owner) =>
            ownerIdentityEquals(owner, pendingIntent.preparedByOwnerV2))) {
        fail("AD03_TRANSFER_NOT_READY");
      }
      // Any owner-set change invalidates the prepared impact and any recorded
      // recipient consent. Close the old intent and require a fresh prepare /
      // accept sequence against the new control version.
      nextControl = ownershipControlWith({
        current: control,
        operationalStateV2: "operating",
        recoverableOwnersV2: otherOwners,
        pendingTransferIntentIdV2: null,
        activeCustodyCaseIdV2: null,
        custodyPolicyIdV2: control.custodyPolicyIdV2,
      });
      const cancelled = parseOwnershipTransferIntentV2({
        ...pendingIntent,
        stateV2: "cancelledByOwnerDeparture",
        controlVersionAtResponseV2:
          pendingIntent.controlVersionAtResponseV2 ?? nextControl.controlVersionV2,
        respondedAtSecV2: pendingIntent.respondedAtSecV2 ?? input.nowSecV2,
      });
      input.transaction.write(
        ownershipTransferIntentPathV2(scope, pendingIntent.transferIntentIdV2),
        wireRecord(cancelled),
      );
    }
  } else if (request.custodyChoiceV2 === "ordinary") {
    fail("AD03_CONTROL_CONFLICT");
  } else if (request.custodyChoiceV2 === "transferThenDelete") {
    if (request.transferIntentIdV2 === null) fail("AD03_TRANSFER_NOT_READY");
    const intentRaw = await input.transaction.read(
      ownershipTransferIntentPathV2(scope, request.transferIntentIdV2),
    );
    if (intentRaw === null) fail("AD03_TRANSFER_NOT_READY");
    const result = await commitAcceptedTransferInTransactionV2({
      transaction: input.transaction,
      scope,
      control,
      intent: parseOwnershipTransferIntentV2(intentRaw),
      departing,
      expectedTransferIntentIdV2: request.transferIntentIdV2,
      nowSecV2: input.nowSecV2,
      auditEventIdV2: associationOwnershipAuditEventIdV2(
        "ownerDeparture",
        request.departureOperationIdV2,
      ),
    });
    nextControl = result.control;
    transferIntentIdV2 = request.transferIntentIdV2;
    eventTypeV2 = "transferCommitted";
    eventCounterparty = result.intent.recipientOwnerV2.ownerBindingIdV2;
  } else {
    if (request.custodyCaseIdV2 === null) fail("AD03_INVALID_REQUEST");
    let supersededIntent: OwnershipTransferIntentV2 | null = null;
    if (control.operationalStateV2 === "transferPending") {
      if (control.pendingTransferIntentIdV2 === null ||
          request.transferIntentIdV2 !== control.pendingTransferIntentIdV2) {
        fail("AD03_CONTROL_CONFLICT");
      }
      const intentRaw = await input.transaction.read(
        ownershipTransferIntentPathV2(scope, control.pendingTransferIntentIdV2),
      );
      if (intentRaw === null) fail("AD03_TRANSFER_NOT_READY");
      const intent = parseOwnershipTransferIntentV2(intentRaw);
      assertTransferIntentLocatorV2({
        intent,
        scope,
        transferIntentIdV2: control.pendingTransferIntentIdV2,
      });
      if (!ownerIdentityEquals(intent.preparedByOwnerV2, departing) ||
          !["pendingRecipientAcceptance", "recipientAccepted"].includes(intent.stateV2)) {
        fail("AD03_TRANSFER_NOT_READY");
      }
      supersededIntent = parseOwnershipTransferIntentV2({
        ...intent,
        stateV2: "supersededByCustody",
        controlVersionAtResponseV2:
          intent.controlVersionAtResponseV2 ?? incrementCounter(control.controlVersionV2),
        respondedAtSecV2: intent.respondedAtSecV2 ?? input.nowSecV2,
        recipientAcceptedAuthTimeSecV2: intent.recipientAcceptedAuthTimeSecV2,
      });
    } else if (control.operationalStateV2 === "operating") {
      if (request.transferIntentIdV2 !== null) {
        const closedIntentRaw = await input.transaction.read(
          ownershipTransferIntentPathV2(scope, request.transferIntentIdV2),
        );
        if (closedIntentRaw === null) fail("AD03_TRANSFER_NOT_READY");
        const closedIntent = parseOwnershipTransferIntentV2(closedIntentRaw);
        assertTransferIntentLocatorV2({
          intent: closedIntent,
          scope,
          transferIntentIdV2: request.transferIntentIdV2,
        });
        if (!ownerIdentityEquals(closedIntent.preparedByOwnerV2, departing) ||
            !["declined", "expired", "cancelledByOwnerDeparture"].includes(
              closedIntent.stateV2,
            )) {
          fail("AD03_TRANSFER_NOT_READY");
        }
        transferIntentIdV2 = closedIntent.transferIntentIdV2;
      }
    } else {
      fail("AD03_CONTROL_CONFLICT");
    }
    const policy = await optionalCandidatePolicyV2({
      transaction: input.transaction,
      scope,
      candidateTestCustodyPolicyIdV2: input.candidateTestCustodyPolicyIdV2,
    });
    const configured = custodyPolicyReadyForCandidateV2(policy);
    nextControl = ownershipControlWith({
      current: control,
      operationalStateV2: configured ? "suspendedToCustody" : "custodyRequired",
      recoverableOwnersV2: [],
      pendingTransferIntentIdV2: null,
      activeCustodyCaseIdV2: request.custodyCaseIdV2,
      custodyPolicyIdV2: configured && policy !== null ? policy.custodyPolicyIdV2 : null,
    });
    const caseRecord = custodyCaseV2({
      scope,
      custodyCaseIdV2: request.custodyCaseIdV2,
      policy,
      controlVersionV2: nextControl.controlVersionV2,
      nowSecV2: input.nowSecV2,
    });
    const existingCase = await input.transaction.read(
      custodyRecoveryCasePathV2(scope, request.custodyCaseIdV2),
    );
    if (existingCase !== null) fail("AD03_TRANSFER_CONFLICT");
    input.transaction.write(
      custodyRecoveryCasePathV2(scope, request.custodyCaseIdV2),
      wireRecord(caseRecord),
    );
    if (supersededIntent !== null) {
      input.transaction.write(
        ownershipTransferIntentPathV2(scope, supersededIntent.transferIntentIdV2),
        wireRecord(supersededIntent),
      );
      transferIntentIdV2 = supersededIntent.transferIntentIdV2;
    }
    custodyCaseIdV2 = request.custodyCaseIdV2;
    requiresOperationalAttentionV2 = !configured;
    eventTypeV2 = configured ? "custodySuspended" : "custodyRequired";
  }
  const receipt = parseOwnerDepartureReceiptV2({
    ownerDepartureReceiptSchemaVersionV2: 2,
    ...input.departingAuthority.scope,
    associationId: scope.associationId,
    accountGenerationV2: input.departingAuthority.accountGenerationV2,
    accountLifecycleEpochV2: input.departingAuthority.accountLifecycleEpochV2,
    departureOperationIdV2: request.departureOperationIdV2,
    requestFingerprintV2,
    outcomeV2: request.custodyChoiceV2 === "suspendToCustody" &&
      nextControl.operationalStateV2 === "custodyRequired"
      ? "policyBlockedButDeletionMustReceiveOperationalResolution"
      : request.custodyChoiceV2,
    custodyStateV2: nextControl.operationalStateV2,
    controlVersionBeforeV2: control.controlVersionV2,
    controlVersionAfterV2: nextControl.controlVersionV2,
    transferIntentIdV2,
    custodyCaseIdV2,
    requiresOperationalAttentionV2,
    personalDeletionMayContinueV2: true,
    recordedAtSecV2: input.nowSecV2,
  });
  input.transaction.write(associationOwnershipControlPathV2(scope), wireRecord(nextControl));
  input.transaction.write(receiptPath, wireRecord(receipt));
  if (request.custodyChoiceV2 !== "transferThenDelete") {
    const departureAuditIdV2 = associationOwnershipAuditEventIdV2(
      "ownerDeparture",
      request.departureOperationIdV2,
    );
    input.transaction.write(
      associationOwnershipAuditPathV2(scope, departureAuditIdV2),
      wireRecord(auditEventV2({
        scope,
        eventIdV2: departureAuditIdV2,
        eventTypeV2,
        before: control.controlVersionV2,
        after: nextControl.controlVersionV2,
        ownerBindingRefV2: departing.ownerBindingIdV2,
        counterpartyBindingRefV2: eventCounterparty,
        transferIntentIdV2,
        custodyCaseIdV2,
        custodyPolicyIdV2: nextControl.custodyPolicyIdV2,
        nowSecV2: input.nowSecV2,
      })),
    );
  }
  return receipt;
}

export async function commitCandidateOwnerDepartureV2(
  input: OwnershipServiceInputV2 & {
    request: unknown;
    candidateTestCustodyPolicyIdV2: string | null;
  },
): Promise<OwnerDepartureReceiptV2> {
  const parsedRequest = parseDepartureRequest(input.request);
  return input.repository.runTransaction(async (transaction) => {
    const {authority} = await authorizeFreshInTransactionV2({
      transaction,
      auth: input.auth,
      configuredProjectId: input.configuredProjectId,
      attempt: input.attempt,
      associationId: parsedRequest.associationId,
      nowSecV2: input.nowSecV2,
    });
    return applyOwnerDepartureInTransactionV2({
      transaction,
      departingAuthority: authority,
      request: parsedRequest,
      nowSecV2: input.nowSecV2,
      candidateTestCustodyPolicyIdV2: input.candidateTestCustodyPolicyIdV2,
    });
  });
}

export async function acceptCandidateCustodySuccessorV2(
  input: OwnershipServiceInputV2 & {request: unknown},
): Promise<CustodyRecoveryCaseV2> {
  const request = parseSuccessorRequest(input.request);
  if (!safeCounter(input.nowSecV2)) fail("AD03_INVALID_REQUEST");
  return input.repository.runTransaction(async (transaction) => {
    const {authority, authTimeSecV2} = await authorizeFreshInTransactionV2({
      transaction,
      auth: input.auth,
      configuredProjectId: input.configuredProjectId,
      attempt: input.attempt,
      associationId: request.associationId,
      nowSecV2: input.nowSecV2,
    });
    const scope = associationScopeFromAuthority(authority);
    const [control, caseRaw] = await Promise.all([
      readControlV2(transaction, scope),
      transaction.read(custodyRecoveryCasePathV2(scope, request.custodyCaseIdV2)),
    ]);
    if (caseRaw === null) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    const caseRecord = parseCustodyRecoveryCaseV2(caseRaw);
    assertCustodyCaseLocatorV2({
      caseRecord,
      scope,
      custodyCaseIdV2: request.custodyCaseIdV2,
    });
    if (caseRecord.custodyPolicyIdV2 === null) {
      fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    }
    const policyRaw = await transaction.read(
      serviceCustodyPolicyPathV2(scope, caseRecord.custodyPolicyIdV2),
    );
    if (policyRaw === null) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    const policy = parseServiceCustodyPolicyV2(policyRaw);
    const custodyLinkageIsCurrent = custodyPolicyReadyForCandidateV2(policy) &&
      sameAssociationScope(policy, scope) &&
      policy.custodyPolicyIdV2 === caseRecord.custodyPolicyIdV2 &&
      policy.custodyPolicyVersionV2 === caseRecord.custodyPolicyVersionV2 &&
      serviceCustodyPolicyFingerprintV2(policy) ===
        caseRecord.custodyPolicyFingerprintV2 &&
      control.custodyPolicyIdV2 === caseRecord.custodyPolicyIdV2 &&
      control.activeCustodyCaseIdV2 === request.custodyCaseIdV2 &&
      caseRecord.namedOperatorRefV2 === policy.namedOperatorRefV2 &&
      caseRecord.namedCaseOwnerRefV2 === policy.namedCaseOwnerRefV2 &&
      policy.recoveryDeadlineSecV2 !== null &&
      caseRecord.deadlineAtSecV2 ===
        caseRecord.openedAtSecV2 + policy.recoveryDeadlineSecV2 &&
      caseRecord.currentControlVersionV2 === control.controlVersionV2;
    if (!custodyLinkageIsCurrent) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    if (caseRecord.stateV2 === "recoveryReview" && caseRecord.successorOwnerV2 !== null &&
        ownerMatchesAuthority(caseRecord.successorOwnerV2, authority)) {
      if (control.operationalStateV2 !== "recoveryReview") {
        fail("AD03_CUSTODY_RECOVERY_NOT_READY");
      }
      if (caseRecord.successorAcceptanceIdV2 !== request.successorAcceptanceIdV2) {
        fail("AD03_RECIPIENT_RESPONSE_CONFLICT");
      }
      return caseRecord;
    }
    assertControlVersion(control, request.expectedControlVersionV2);
    if (control.operationalStateV2 !== "suspendedToCustody" ||
        control.activeCustodyCaseIdV2 !== request.custodyCaseIdV2 ||
        caseRecord.stateV2 !== "suspended" || caseRecord.custodyPolicyIdV2 === null) {
      fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    }
    const successor = await eligibleRecipientInTransactionV2({
      transaction,
      scope: authority.scope,
      associationId: scope.associationId,
      nowSecV2: input.nowSecV2,
    });
    const nextControl = ownershipControlWith({
      current: control,
      operationalStateV2: "recoveryReview",
      recoverableOwnersV2: [],
      pendingTransferIntentIdV2: null,
      activeCustodyCaseIdV2: caseRecord.custodyCaseIdV2,
      custodyPolicyIdV2: caseRecord.custodyPolicyIdV2,
    });
    const updated = parseCustodyRecoveryCaseV2({
      ...caseRecord,
      stateV2: "recoveryReview",
      currentControlVersionV2: nextControl.controlVersionV2,
      successorOwnerV2: successor,
      successorAcceptanceIdV2: request.successorAcceptanceIdV2,
      successorAcceptedAtSecV2: input.nowSecV2,
      successorAcceptedAuthTimeSecV2: authTimeSecV2,
    });
    transaction.write(associationOwnershipControlPathV2(scope), wireRecord(nextControl));
    transaction.write(
      custodyRecoveryCasePathV2(scope, caseRecord.custodyCaseIdV2),
      wireRecord(updated),
    );
    return updated;
  });
}

/**
 * The only authorizer included in AD03 is explicitly test-only. A production
 * adapter must be independently reviewed and cannot be inferred from fixture
 * strings or legacy roles.
 */
export function verifyTestServiceCustodyCommandV2(input: {
  policy: unknown;
  command: unknown;
  nowSecV2: number;
}): VerifiedTestServiceCustodyCommandV2 {
  const policy = parseServiceCustodyPolicyV2(input.policy);
  const command = parseServiceCommand(input.command);
  if (!custodyPolicyReadyForCandidateV2(policy) ||
      !sameAssociationScope(policy, command) ||
      command.custodyPolicyIdV2 !== policy.custodyPolicyIdV2 ||
      command.custodyPolicyVersionV2 !== policy.custodyPolicyVersionV2 ||
      command.custodyPolicyFingerprintV2 !== serviceCustodyPolicyFingerprintV2(policy) ||
      command.operatorRefV2 !== policy.namedOperatorRefV2 ||
      command.caseOwnerRefV2 !== policy.namedCaseOwnerRefV2 ||
      command.issuedAtSecV2 > input.nowSecV2 || command.expiresAtSecV2 < input.nowSecV2) {
    fail("AD03_SERVICE_AUTHORITY_DENIED");
  }
  const verified = Object.freeze({
    command,
    verificationNonceV2: {},
  });
  verifiedTestCommands.add(verified);
  return verified;
}

export async function completeCandidateCustodyRecoveryV2(input: {
  repository: CandidateTransactionalAuthorityRepositoryV2;
  verifiedTestCommand: VerifiedTestServiceCustodyCommandV2;
  nowSecV2: number;
}): Promise<CustodyRecoveryCaseV2> {
  if (!safeCounter(input.nowSecV2) ||
      !verifiedTestCommands.has(input.verifiedTestCommand)) {
    fail("AD03_SERVICE_AUTHORITY_DENIED");
  }
  const command = input.verifiedTestCommand.command;
  if (command.issuedAtSecV2 > input.nowSecV2 || command.expiresAtSecV2 < input.nowSecV2) {
    fail("AD03_SERVICE_AUTHORITY_DENIED");
  }
  const scope = {
    authProjectIdV2: command.authProjectIdV2,
    authTenantIdV2: command.authTenantIdV2,
    associationId: command.associationId,
  };
  return input.repository.runTransaction(async (transaction) => {
    const [control, caseRaw, policyRaw] = await Promise.all([
      readControlV2(transaction, scope),
      transaction.read(custodyRecoveryCasePathV2(scope, command.custodyCaseIdV2)),
      transaction.read(serviceCustodyPolicyPathV2(scope, command.custodyPolicyIdV2)),
    ]);
    if (caseRaw === null || policyRaw === null) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    const caseRecord = parseCustodyRecoveryCaseV2(caseRaw);
    const policy = parseServiceCustodyPolicyV2(policyRaw);
    assertCustodyCaseLocatorV2({
      caseRecord,
      scope,
      custodyCaseIdV2: command.custodyCaseIdV2,
    });
    const caseLinkageIsCurrent = caseRecord.custodyPolicyIdV2 === command.custodyPolicyIdV2 &&
      caseRecord.custodyPolicyVersionV2 === command.custodyPolicyVersionV2 &&
      caseRecord.custodyPolicyFingerprintV2 === command.custodyPolicyFingerprintV2 &&
      caseRecord.namedOperatorRefV2 === command.operatorRefV2 &&
      caseRecord.namedCaseOwnerRefV2 === command.caseOwnerRefV2 &&
      caseRecord.currentControlVersionV2 === control.controlVersionV2;
    if (!caseLinkageIsCurrent) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    const policyMatchesCase = custodyPolicyReadyForCandidateV2(policy) &&
      sameAssociationScope(policy, scope) &&
      policy.custodyPolicyIdV2 === command.custodyPolicyIdV2 &&
      policy.custodyPolicyVersionV2 === command.custodyPolicyVersionV2 &&
      serviceCustodyPolicyFingerprintV2(policy) === command.custodyPolicyFingerprintV2 &&
      policy.recoveryDeadlineSecV2 !== null &&
      caseRecord.deadlineAtSecV2 ===
        caseRecord.openedAtSecV2 + policy.recoveryDeadlineSecV2;
    if (!policyMatchesCase) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    if (caseRecord.stateV2 === "resolved" && caseRecord.successorOwnerV2 !== null) {
      const exactReplay = custodyPolicyReadyForCandidateV2(policy) &&
        sameAssociationScope(policy, scope) &&
        policy.custodyPolicyIdV2 === command.custodyPolicyIdV2 &&
        policy.custodyPolicyVersionV2 === command.custodyPolicyVersionV2 &&
        serviceCustodyPolicyFingerprintV2(policy) === command.custodyPolicyFingerprintV2 &&
        policy.namedOperatorRefV2 === command.operatorRefV2 &&
        policy.namedCaseOwnerRefV2 === command.caseOwnerRefV2 &&
        caseRecord.reviewEvidenceRefV2 === command.reviewEvidenceRefV2 &&
        control.operationalStateV2 === "operating" &&
        control.activeCustodyCaseIdV2 === null &&
        control.custodyPolicyIdV2 === policy.custodyPolicyIdV2 &&
        control.recoverableOwnersV2.length === 1 &&
        ownerIdentityEquals(control.recoverableOwnersV2[0], caseRecord.successorOwnerV2);
      if (!exactReplay) fail("AD03_CUSTODY_RECOVERY_NOT_READY");
      return caseRecord;
    }
    if (!custodyPolicyReadyForCandidateV2(policy) ||
        !sameAssociationScope(policy, scope) ||
        policy.custodyPolicyIdV2 !== command.custodyPolicyIdV2 ||
        policy.custodyPolicyVersionV2 !== command.custodyPolicyVersionV2 ||
        serviceCustodyPolicyFingerprintV2(policy) !== command.custodyPolicyFingerprintV2 ||
        policy.namedOperatorRefV2 !== command.operatorRefV2 ||
        policy.namedCaseOwnerRefV2 !== command.caseOwnerRefV2 ||
        control.operationalStateV2 !== "recoveryReview" ||
        control.activeCustodyCaseIdV2 !== caseRecord.custodyCaseIdV2 ||
        control.custodyPolicyIdV2 !== policy.custodyPolicyIdV2 ||
        caseRecord.stateV2 !== "recoveryReview" ||
        caseRecord.successorOwnerV2 === null ||
        caseRecord.successorAcceptedAuthTimeSecV2 === null) {
      fail("AD03_CUSTODY_RECOVERY_NOT_READY");
    }
    const successor = await eligibleRecipientInTransactionV2({
      transaction,
      scope: caseRecord.successorOwnerV2,
      associationId: scope.associationId,
      nowSecV2: input.nowSecV2,
      acceptedAuthTimeSecV2: caseRecord.successorAcceptedAuthTimeSecV2,
    });
    if (!ownerIdentityEquals(successor, caseRecord.successorOwnerV2)) {
      fail("AD03_RECIPIENT_INELIGIBLE");
    }
    const nextControl = ownershipControlWith({
      current: control,
      operationalStateV2: "operating",
      recoverableOwnersV2: [successor],
      pendingTransferIntentIdV2: null,
      activeCustodyCaseIdV2: null,
      custodyPolicyIdV2: policy.custodyPolicyIdV2,
    });
    const resolved = parseCustodyRecoveryCaseV2({
      ...caseRecord,
      stateV2: "resolved",
      currentControlVersionV2: nextControl.controlVersionV2,
      reviewEvidenceRefV2: command.reviewEvidenceRefV2,
      resolvedAtSecV2: input.nowSecV2,
    });
    transaction.write(associationOwnershipControlPathV2(scope), wireRecord(nextControl));
    transaction.write(
      custodyRecoveryCasePathV2(scope, caseRecord.custodyCaseIdV2),
      wireRecord(resolved),
    );
    const recoveryAuditIdV2 = associationOwnershipAuditEventIdV2(
      "custodyRecovery",
      command.commandIdV2,
    );
    transaction.write(
      associationOwnershipAuditPathV2(scope, recoveryAuditIdV2),
      wireRecord(auditEventV2({
        scope,
        eventIdV2: recoveryAuditIdV2,
        eventTypeV2: "recoveryResolved",
        before: control.controlVersionV2,
        after: nextControl.controlVersionV2,
        ownerBindingRefV2: null,
        counterpartyBindingRefV2: successor.ownerBindingIdV2,
        transferIntentIdV2: null,
        custodyCaseIdV2: caseRecord.custodyCaseIdV2,
        custodyPolicyIdV2: policy.custodyPolicyIdV2,
        nowSecV2: input.nowSecV2,
      })),
    );
    return resolved;
  });
}

export function associationCustodyBarrierRequirementV2(input: {
  control: unknown;
  operationClassV2: AssociationCustodyOperationClassV2;
}): AssociationCustodyBarrierRequirementV2 {
  if (!associationCustodyOperationClassesV2.includes(input.operationClassV2)) {
    fail("AD03_INVALID_REQUEST");
  }
  const control = parseAssociationOwnershipControlV2(input.control);
  if (input.operationClassV2 === "deletionPrivacyCleanup") {
    return "serverDeletionAuthorityRequired";
  }
  if (input.operationClassV2 === "trustedRecoveryWorker") {
    return "trustedRecoveryAuthorityRequired";
  }
  if (input.operationClassV2 === "auditedServiceCustodyRecovery") {
    return "auditedServiceCustodyAuthorityRequired";
  }
  if (input.operationClassV2 === "historicalPresentation") {
    return "ad06CurrentPrivacyDecisionRequired";
  }
  if (control.operationalStateV2 === "operating" ||
      control.operationalStateV2 === "transferPending") {
    return "ordinaryAuthorityMayProceed";
  }
  return "associationOperationSuspended";
}
