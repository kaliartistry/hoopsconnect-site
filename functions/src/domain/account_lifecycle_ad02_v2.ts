import {
  ACCOUNT_GENERATION_CLAIM_V2,
  ACCOUNT_LIFECYCLE_EPOCH_CLAIM_V2,
  AccountLifecycleAuthorityV2,
  AuthIncarnationAuthorizationDecisionV2,
  AuthIncarnationScopeV2,
  AuthIncarnationTokenProofV2,
  MembershipAuthorityV2,
  PendingAuthIncarnationBindingV2,
  evaluateAccountAuthorizationV2,
  parseAccountLifecycleAuthorityV2,
  parseAuthIncarnationScopeV2,
  parseAuthIncarnationTokenProofV2,
  parseMembershipAuthorityV2,
  parsePendingAuthIncarnationBindingV2,
} from "./auth_incarnation_v2";

/**
 * AD02 is an isolated consumer of the dormant Auth Incarnation V2 contract.
 * Nothing in this module is exported from the Functions entry point.
 */
export const ACCOUNT_LIFECYCLE_AD02_ACTIVATION_ALLOWED_V2 = false;
export const ACCOUNT_DIRECTORY_SCHEMA_VERSION_V2 = 2;
export const ACCOUNT_RECREATION_SUPPRESSION_SCHEMA_VERSION_V2 = 2;

export type AccountLifecycleAd02DenialCodeV2 =
  | "invalid_provider_context"
  | "invalid_profile"
  | "profile_mismatch"
  | "association_mismatch"
  | "invalid_actor_stamp"
  | "invalid_suppression"
  | "uid_reuse_prohibited"
  | "existing_lifecycle_conflict"
  | "legacy_authority_not_adopted";

export interface CandidateSessionAttemptV2 {
  sessionAttemptIdV2: string;
  sessionAttemptEpochV2: number;
  sessionAttemptNonceV2: object;
}

export interface VerifiedProviderAuthContextV2 {
  uid: string;
  token: Readonly<Record<string, unknown>>;
}

export interface CandidateAuthorityRepositoryV2 {
  read(path: string): Promise<unknown | null>;
}

export interface CandidateAuthorityTransactionV2 {
  read(path: string): Promise<unknown | null>;
  write(path: string, value: Readonly<Record<string, unknown>>): void;
}

export interface CandidateTransactionalAuthorityRepositoryV2
extends CandidateAuthorityRepositoryV2 {
  runTransaction<T>(
    operation: (transaction: CandidateAuthorityTransactionV2) => Promise<T>,
  ): Promise<T>;
}

export interface AccountProfileAuthorityV2 extends AuthIncarnationScopeV2 {
  accountProfileSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  associationId: string;
  displayName: string;
  teamId: string | null;
  divisionId: string | null;
  notificationPrefs: Readonly<Record<string, boolean>>;
}

export interface ActiveMemberDirectoryEntryV2 {
  accountDirectorySchemaVersionV2: 2;
  uid: string;
  displayName: string;
  teamId: string | null;
  divisionId: string | null;
}

export interface ActiveMemberDirectoryV2 {
  accountDirectorySchemaVersionV2: 2;
  users: readonly ActiveMemberDirectoryEntryV2[];
  truncated: boolean;
}

export interface PersistedActiveMemberV2 {
  readonly scope: AuthIncarnationScopeV2;
  readonly accountGenerationV2: string;
  readonly accountLifecycleEpochV2: number;
  readonly associationId: string;
  readonly capabilities: readonly string[];
  readonly profile: AccountProfileAuthorityV2;
}

export interface AccountRecreationSuppressionV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  suppressionStateV2: "uid_reuse_prohibited";
  suppressedAccountGenerationV2: string;
  suppressedAccountLifecycleEpochV2: number;
  recordedAtSecV2: number;
}

export type PendingLifecycleBootstrapDecisionV2 =
  | {allowed: false; code: AccountLifecycleAd02DenialCodeV2}
  | {allowed: true; pending: PendingAuthIncarnationBindingV2; create: boolean};

export interface ActorAuthorityStampV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
}

export interface LegacyDerivedWriterFenceV2 extends ActorAuthorityStampV2 {
  readonly associationId: string;
  readonly capability: string;
}

type JsonRecord = Record<string, unknown>;

const profileKeys = [
  "accountProfileSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "accountGenerationV2",
  "accountLifecycleEpochV2",
  "associationId",
  "displayName",
  "teamId",
  "divisionId",
  "notificationPrefs",
] as const;
const suppressionKeys = [
  "authIncarnationSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "suppressionStateV2",
  "suppressedAccountGenerationV2",
  "suppressedAccountLifecycleEpochV2",
  "recordedAtSecV2",
] as const;
const actorStampKeys = [
  "authIncarnationSchemaVersionV2",
  "authProjectIdV2",
  "authTenantIdV2",
  "authUidV2",
  "accountGenerationV2",
  "accountLifecycleEpochV2",
] as const;
const generationPattern = /^[a-f0-9]{64}$/;
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const controlPattern = /[\u0000-\u001f\u007f]/;
const preferenceKeys = new Set(["ackReminders", "statReminders", "newPosts"]);

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

function safeCounter(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function sameScope(left: AuthIncarnationScopeV2, right: AuthIncarnationScopeV2): boolean {
  return left.authProjectIdV2 === right.authProjectIdV2 &&
    left.authTenantIdV2 === right.authTenantIdV2 &&
    left.authUidV2 === right.authUidV2;
}

function pathSegment(value: string, label: string): string {
  if (!identifierPattern.test(value)) {
    throw new TypeError(`Invalid AD02 V2 ${label}.`);
  }
  return value;
}

function scopedPath(
  scopeValue: unknown,
  rootCollection: string,
  tenantCollection: string,
): string {
  const value = record(scopeValue);
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: value?.authProjectIdV2,
    authTenantIdV2: value?.authTenantIdV2,
    authUidV2: value?.authUidV2,
  });
  const uid = pathSegment(scope.authUidV2, "UID path segment");
  return scope.authTenantIdV2 === null
    ? `${rootCollection}/${uid}`
    : `${tenantCollection}/${pathSegment(scope.authTenantIdV2, "tenant path segment")}` +
      `/users/${uid}`;
}

function scopedCollectionPath(
  scopeValue: unknown,
  rootCollection: string,
  tenantCollection: string,
): string {
  const value = record(scopeValue);
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: value?.authProjectIdV2,
    authTenantIdV2: value?.authTenantIdV2,
    authUidV2: value?.authUidV2,
  });
  pathSegment(scope.authUidV2, "UID path segment");
  return scope.authTenantIdV2 === null
    ? rootCollection
    : `${tenantCollection}/${pathSegment(scope.authTenantIdV2, "tenant path segment")}/users`;
}

export function accountLifecycleAuthorityPathV2(scope: unknown): string {
  return scopedPath(scope, "accountLifecycleV2Root", "accountLifecycleV2Tenants");
}

export function membershipAuthorityPathV2(scope: unknown): string {
  return scopedPath(scope, "membershipsV2Root", "membershipsV2Tenants");
}

export function membershipAuthorityCollectionPathV2(scope: unknown): string {
  return scopedCollectionPath(scope, "membershipsV2Root", "membershipsV2Tenants");
}

export function storageAuthorizationProjectionPathV2(scope: unknown): string {
  return scopedPath(scope, "storageAuthorizationsV2Root", "storageAuthorizationsV2Tenants");
}

export function accountProfileAuthorityPathV2(scope: unknown): string {
  return scopedPath(scope, "accountProfilesV2Root", "accountProfilesV2Tenants");
}

export function accountFcmRegistrationPathV2(
  scopeValue: unknown,
  installationId: string,
): string {
  if (!identifierPattern.test(installationId)) {
    throw new TypeError("Invalid AD02 V2 installation ID.");
  }
  const value = record(scopeValue);
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: value?.authProjectIdV2,
    authTenantIdV2: value?.authTenantIdV2,
    authUidV2: value?.authUidV2,
  });
  const uid = pathSegment(scope.authUidV2, "UID path segment");
  return scope.authTenantIdV2 === null
    ? `accountFcmRegistrationsV2Root/${uid}/installations/${installationId}`
    : `accountFcmRegistrationsV2Tenants/${pathSegment(scope.authTenantIdV2, "tenant path segment")}` +
      `/users/${uid}/installations/${installationId}`;
}

export function accountRecreationSuppressionPathV2(scope: unknown): string {
  return scopedPath(
    scope,
    "accountGenerationSuppressionsV2Root",
    "accountGenerationSuppressionsV2Tenants",
  );
}

function providerTenant(token: JsonRecord): string | null | undefined {
  const firebase = record(token.firebase);
  if (firebase === null) return undefined;
  if (!Object.prototype.hasOwnProperty.call(firebase, "tenant")) return null;
  return typeof firebase.tenant === "string" ? firebase.tenant : undefined;
}

/**
 * Extract only from provider-verified callable context. A V1 claim, profile,
 * membership, creation timestamp, or forced refresh is never consulted.
 */
export function extractProviderTokenProofV2(
  auth: unknown,
  configuredProjectId: string,
): AuthIncarnationTokenProofV2 | null {
  const context = record(auth);
  const token = record(context?.token);
  if (
    context === null ||
    token === null ||
    typeof context.uid !== "string" ||
    !identifierPattern.test(context.uid) ||
    !identifierPattern.test(configuredProjectId) ||
    token.aud !== configuredProjectId ||
    token.sub !== context.uid
  ) {
    return null;
  }
  const firebaseTenant = providerTenant(token);
  if (
    firebaseTenant === undefined ||
    token.authTenantIdV2 !== firebaseTenant ||
    (firebaseTenant !== null && !identifierPattern.test(firebaseTenant))
  ) return null;
  try {
    return parseAuthIncarnationTokenProofV2({
      authIncarnationSchemaVersionV2: token.authIncarnationSchemaVersionV2,
      authProjectIdV2: token.authProjectIdV2,
      authTenantIdV2: token.authTenantIdV2,
      authUidV2: token.authUidV2,
      accountGenerationV2: token[ACCOUNT_GENERATION_CLAIM_V2],
      accountLifecycleEpochV2: token[ACCOUNT_LIFECYCLE_EPOCH_CLAIM_V2],
      authTimeSec: token.auth_time,
    });
  } catch {
    return null;
  }
}

export async function evaluateCandidateRequestAuthorityV2(input: {
  repository: CandidateAuthorityRepositoryV2;
  auth: VerifiedProviderAuthContextV2;
  configuredProjectId: string;
  attempt: CandidateSessionAttemptV2;
  requiredCapability: string;
}): Promise<AuthIncarnationAuthorizationDecisionV2> {
  const tokenProof = extractProviderTokenProofV2(input.auth, input.configuredProjectId);
  if (tokenProof === null) return {authorized: false, code: "invalid_token_proof"};
  const expectedScope: AuthIncarnationScopeV2 = {
    authProjectIdV2: input.configuredProjectId,
    authTenantIdV2: tokenProof.authTenantIdV2,
    authUidV2: input.auth.uid,
  };
  const [lifecycle, membership] = await Promise.all([
    input.repository.read(accountLifecycleAuthorityPathV2(expectedScope)),
    input.repository.read(membershipAuthorityPathV2(expectedScope)),
  ]);
  return evaluateAccountAuthorizationV2({
    ...input.attempt,
    expectedScope,
    tokenProof,
    lifecycle,
    membership,
    requiredCapability: input.requiredCapability,
  });
}

export function parseAccountProfileAuthorityV2(value: unknown): AccountProfileAuthorityV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, profileKeys)) throw new TypeError("Invalid AD02 V2 profile.");
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  if (
    data.accountProfileSchemaVersionV2 !== 2 ||
    typeof data.accountGenerationV2 !== "string" ||
    !generationPattern.test(data.accountGenerationV2) ||
    !safeCounter(data.accountLifecycleEpochV2) ||
    typeof data.associationId !== "string" ||
    !identifierPattern.test(data.associationId) ||
    typeof data.displayName !== "string" ||
    data.displayName.trim().length === 0 ||
    data.displayName.length > 160 ||
    controlPattern.test(data.displayName) ||
    !(data.teamId === null || (typeof data.teamId === "string" && identifierPattern.test(data.teamId))) ||
    !(data.divisionId === null ||
      (typeof data.divisionId === "string" && identifierPattern.test(data.divisionId)))
  ) {
    throw new TypeError("Invalid AD02 V2 profile.");
  }
  const preferences = record(data.notificationPrefs);
  if (
    preferences === null ||
    Object.keys(preferences).some((key) =>
      !preferenceKeys.has(key) || typeof preferences[key] !== "boolean")
  ) {
    throw new TypeError("Invalid AD02 V2 notification preferences.");
  }
  return Object.freeze({
    accountProfileSchemaVersionV2: 2,
    ...scope,
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
    associationId: data.associationId,
    displayName: data.displayName.trim(),
    teamId: data.teamId,
    divisionId: data.divisionId,
    notificationPrefs: Object.freeze({...preferences}) as Readonly<Record<string, boolean>>,
  });
}

export function evaluatePersistedActiveMemberV2(input: {
  expectedScope: unknown;
  lifecycle: unknown;
  membership: unknown;
  profile: unknown;
  requiredCapability: string;
  expectedAssociationId: string;
}): PersistedActiveMemberV2 | null {
  let expectedScope: AuthIncarnationScopeV2;
  let lifecycle: AccountLifecycleAuthorityV2;
  let membership: MembershipAuthorityV2;
  let profile: AccountProfileAuthorityV2;
  try {
    expectedScope = parseAuthIncarnationScopeV2(input.expectedScope);
    lifecycle = parseAccountLifecycleAuthorityV2(input.lifecycle);
    membership = parseMembershipAuthorityV2(input.membership);
    profile = parseAccountProfileAuthorityV2(input.profile);
  } catch {
    return null;
  }
  if (
    lifecycle.lifecycleStateV2 !== "active" ||
    membership.membershipStatusV2 !== "active" ||
    !sameScope(lifecycle, expectedScope) ||
    !sameScope(membership, expectedScope) ||
    !sameScope(profile, expectedScope) ||
    lifecycle.accountGenerationV2 !== membership.accountGenerationV2 ||
    lifecycle.accountGenerationV2 !== profile.accountGenerationV2 ||
    lifecycle.accountLifecycleEpochV2 !== membership.accountLifecycleEpochV2 ||
    lifecycle.accountLifecycleEpochV2 !== profile.accountLifecycleEpochV2 ||
    membership.associationId !== input.expectedAssociationId ||
    profile.associationId !== input.expectedAssociationId ||
    !membership.capabilities.includes(input.requiredCapability)
  ) {
    return null;
  }
  return Object.freeze({
    scope: Object.freeze({...expectedScope}),
    accountGenerationV2: lifecycle.accountGenerationV2,
    accountLifecycleEpochV2: lifecycle.accountLifecycleEpochV2,
    associationId: membership.associationId,
    capabilities: Object.freeze([...membership.capabilities]),
    profile,
  });
}

export function buildActiveMemberDirectoryV2(
  members: readonly PersistedActiveMemberV2[],
  maximumEntries = 200,
): ActiveMemberDirectoryV2 {
  if (!Number.isSafeInteger(maximumEntries) || maximumEntries < 1 || maximumEntries > 200) {
    throw new RangeError("Invalid AD02 V2 directory limit.");
  }
  const ordered = [...members].sort((left, right) =>
    left.scope.authUidV2.localeCompare(right.scope.authUidV2));
  if (new Set(ordered.map((member) => member.scope.authUidV2)).size !== ordered.length) {
    throw new TypeError("Duplicate AD02 V2 directory member.");
  }
  const users = ordered.slice(0, maximumEntries).map((member) => Object.freeze({
    accountDirectorySchemaVersionV2: ACCOUNT_DIRECTORY_SCHEMA_VERSION_V2,
    uid: member.scope.authUidV2,
    displayName: member.profile.displayName,
    teamId: member.profile.teamId,
    divisionId: member.profile.divisionId,
  }));
  return Object.freeze({
    accountDirectorySchemaVersionV2: ACCOUNT_DIRECTORY_SCHEMA_VERSION_V2,
    users: Object.freeze(users),
    truncated: ordered.length > maximumEntries,
  });
}

export function parseAccountRecreationSuppressionV2(
  value: unknown,
): AccountRecreationSuppressionV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, suppressionKeys)) {
    throw new TypeError("Invalid AD02 V2 recreation suppression.");
  }
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  if (
    data.authIncarnationSchemaVersionV2 !== 2 ||
    data.suppressionStateV2 !== "uid_reuse_prohibited" ||
    typeof data.suppressedAccountGenerationV2 !== "string" ||
    !generationPattern.test(data.suppressedAccountGenerationV2) ||
    !safeCounter(data.suppressedAccountLifecycleEpochV2) ||
    !safeCounter(data.recordedAtSecV2)
  ) {
    throw new TypeError("Invalid AD02 V2 recreation suppression.");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: 2,
    ...scope,
    suppressionStateV2: "uid_reuse_prohibited",
    suppressedAccountGenerationV2: data.suppressedAccountGenerationV2,
    suppressedAccountLifecycleEpochV2: data.suppressedAccountLifecycleEpochV2,
    recordedAtSecV2: data.recordedAtSecV2,
  });
}

/**
 * Candidate-only bootstrap evaluation. It never issues G, promotes active, or
 * writes a claim. Only a future trusted issuer may supply the pending binding.
 */
export function evaluatePendingLifecycleBootstrapV2(input: {
  pendingBinding: unknown;
  currentLifecycle: unknown | null;
  suppression: unknown | null;
}): PendingLifecycleBootstrapDecisionV2 {
  let pending: PendingAuthIncarnationBindingV2;
  try {
    pending = parsePendingAuthIncarnationBindingV2(input.pendingBinding);
  } catch {
    return {allowed: false, code: "invalid_provider_context"};
  }
  if (input.suppression !== null) {
    let suppression: AccountRecreationSuppressionV2;
    try {
      suppression = parseAccountRecreationSuppressionV2(input.suppression);
    } catch {
      return {allowed: false, code: "invalid_suppression"};
    }
    if (!sameScope(suppression, pending)) {
      return {allowed: false, code: "invalid_suppression"};
    }
    return {allowed: false, code: "uid_reuse_prohibited"};
  }
  if (input.currentLifecycle === null) {
    return {allowed: true, pending, create: true};
  }
  let lifecycle: AccountLifecycleAuthorityV2;
  try {
    lifecycle = parseAccountLifecycleAuthorityV2(input.currentLifecycle);
  } catch {
    return {allowed: false, code: "existing_lifecycle_conflict"};
  }
  const matchesPending = lifecycle.lifecycleStateV2 === "pending" &&
    sameScope(lifecycle, pending) &&
    lifecycle.accountGenerationV2 === pending.accountGenerationV2 &&
    lifecycle.accountLifecycleEpochV2 === pending.accountLifecycleEpochV2 &&
    lifecycle.reauthAfterSecV2 === pending.reauthAfterSecV2;
  return matchesPending
    ? {allowed: true, pending, create: false}
    : {allowed: false, code: "existing_lifecycle_conflict"};
}

export function parseActorAuthorityStampV2(value: unknown): ActorAuthorityStampV2 {
  const data = record(value);
  if (data === null || !exactKeys(data, actorStampKeys)) {
    throw new TypeError("Invalid AD02 V2 actor stamp.");
  }
  const scope = parseAuthIncarnationScopeV2({
    authProjectIdV2: data.authProjectIdV2,
    authTenantIdV2: data.authTenantIdV2,
    authUidV2: data.authUidV2,
  });
  if (
    data.authIncarnationSchemaVersionV2 !== 2 ||
    typeof data.accountGenerationV2 !== "string" ||
    !generationPattern.test(data.accountGenerationV2) ||
    !safeCounter(data.accountLifecycleEpochV2)
  ) {
    throw new TypeError("Invalid AD02 V2 actor stamp.");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: 2,
    ...scope,
    accountGenerationV2: data.accountGenerationV2,
    accountLifecycleEpochV2: data.accountLifecycleEpochV2,
  });
}

export function evaluateLegacyDerivedWriterFenceV2(input: {
  actorStamp: unknown;
  lifecycle: unknown;
  membership: unknown;
  requiredCapability: string;
  expectedAssociationId: string;
}): LegacyDerivedWriterFenceV2 | null {
  let stamp: ActorAuthorityStampV2;
  let lifecycle: AccountLifecycleAuthorityV2;
  let membership: MembershipAuthorityV2;
  try {
    stamp = parseActorAuthorityStampV2(input.actorStamp);
    lifecycle = parseAccountLifecycleAuthorityV2(input.lifecycle);
    membership = parseMembershipAuthorityV2(input.membership);
  } catch {
    return null;
  }
  if (
    lifecycle.lifecycleStateV2 !== "active" ||
    membership.membershipStatusV2 !== "active" ||
    !sameScope(stamp, lifecycle) ||
    !sameScope(stamp, membership) ||
    stamp.accountGenerationV2 !== lifecycle.accountGenerationV2 ||
    stamp.accountGenerationV2 !== membership.accountGenerationV2 ||
    stamp.accountLifecycleEpochV2 !== lifecycle.accountLifecycleEpochV2 ||
    stamp.accountLifecycleEpochV2 !== membership.accountLifecycleEpochV2 ||
    membership.associationId !== input.expectedAssociationId ||
    !membership.capabilities.includes(input.requiredCapability)
  ) {
    return null;
  }
  return Object.freeze({
    ...stamp,
    associationId: membership.associationId,
    capability: input.requiredCapability,
  });
}

export async function assertLegacyDerivedWriterFenceV2(
  transaction: CandidateAuthorityTransactionV2,
  expected: LegacyDerivedWriterFenceV2,
): Promise<LegacyDerivedWriterFenceV2> {
  const [lifecycle, membership] = await Promise.all([
    transaction.read(accountLifecycleAuthorityPathV2(expected)),
    transaction.read(membershipAuthorityPathV2(expected)),
  ]);
  const current = evaluateLegacyDerivedWriterFenceV2({
    actorStamp: expected,
    lifecycle,
    membership,
    requiredCapability: expected.capability,
    expectedAssociationId: expected.associationId,
  });
  if (
    current === null ||
    current.authProjectIdV2 !== expected.authProjectIdV2 ||
    current.authTenantIdV2 !== expected.authTenantIdV2 ||
    current.authUidV2 !== expected.authUidV2 ||
    current.accountGenerationV2 !== expected.accountGenerationV2 ||
    current.accountLifecycleEpochV2 !== expected.accountLifecycleEpochV2
  ) {
    throw new Error("AD02 V2 derived-writer lifecycle fence denied.");
  }
  return current;
}

export async function commitCandidateDerivedWriteV2<T>(input: {
  repository: CandidateTransactionalAuthorityRepositoryV2;
  expectedFence: LegacyDerivedWriterFenceV2;
  commit: (
    transaction: CandidateAuthorityTransactionV2,
    fence: LegacyDerivedWriterFenceV2,
  ) => Promise<T> | T;
}): Promise<T> {
  return input.repository.runTransaction(async (transaction) => {
    const fence = await assertLegacyDerivedWriterFenceV2(
      transaction,
      input.expectedFence,
    );
    return input.commit(transaction, fence);
  });
}
