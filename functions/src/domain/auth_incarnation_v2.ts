export const AUTH_INCARNATION_SCHEMA_VERSION_V2 = 2;
export const ACCOUNT_GENERATION_CLAIM_V2 = "accountGenerationV2";
export const ACCOUNT_LIFECYCLE_EPOCH_CLAIM_V2 = "accountLifecycleEpochV2";
export const MAX_SAFE_AUTHORITY_INTEGER_V2 = 9007199254740991;
export const AUTH_INCARNATION_CAPABILITIES_V2 = [
  "association.read", "association.manage", "members.read", "members.manage",
  "invites.manage", "schedule.manage", "teams.manage", "teams.represent",
  "posts.create", "posts.manage", "posts.internal.read", "posts.acknowledge",
  "stats.enter", "stats.approve", "stats.export", "press.read", "players.manage",
  "players.private.read", "rosters.assert", "rosters.manage", "games.schedule",
  "stats.submit", "stats.review", "stats.correct", "stats.certify",
  "results.publish", "results.retract", "official.override",
] as const;

export type AccountLifecycleStateV2 = "pending" | "active" | "deleting" | "deleted";
export type MembershipStatusV2 = "active" | "suspended" | "revoked";

export interface AuthIncarnationScopeV2 {
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  authUidV2: string;
}

export interface AuthIncarnationTokenProofV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  authTimeSec: number;
}

export interface AccountLifecycleAuthorityV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  lifecycleStateV2: AccountLifecycleStateV2;
  reauthAfterSecV2: number;
}

export interface MembershipAuthorityV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  membershipStatusV2: MembershipStatusV2;
  associationId: string;
  capabilities: string[];
}

export interface StorageAuthorizationProjectionV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  lifecycleStateV2: AccountLifecycleStateV2;
  membershipStatusV2: MembershipStatusV2;
  reauthAfterSecV2: number;
  associationId: string;
  capabilities: string[];
}

export interface PendingAuthIncarnationBindingV2 extends AuthIncarnationScopeV2 {
  authIncarnationSchemaVersionV2: 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  bindingStateV2: "pending";
  reauthAfterSecV2: number;
}

export type AuthIncarnationDenialCodeV2 =
  "missing_token_proof" |
  "invalid_token_proof" |
  "invalid_lifecycle" |
  "lifecycle_inactive" |
  "invalid_membership" |
  "membership_inactive" |
  "invalid_projection" |
  "scope_mismatch" |
  "generation_mismatch" |
  "epoch_mismatch" |
  "reauthentication_required" |
  "capability_denied";

export interface ValidatedActiveAuthorityV2 {
  readonly sessionAttemptIdV2: string;
  readonly scope: AuthIncarnationScopeV2;
  readonly accountGenerationV2: string;
  readonly accountLifecycleEpochV2: number;
  readonly reauthAfterSecV2: number;
  readonly associationId: string;
  readonly capabilities: readonly string[];
}

export type AuthIncarnationAuthorizationDecisionV2 =
  {authorized: false; code: AuthIncarnationDenialCodeV2} |
  {authorized: true; binding: ValidatedActiveAuthorityV2};

type JsonRecord = Record<string, unknown>;

const generationPattern = /^[a-f0-9]{64}$/;
const controlPattern = /[\u0000-\u001f\u007f]/;
const capabilitySet = new Set<string>(AUTH_INCARNATION_CAPABILITIES_V2);
const validatedBindings = new WeakSet<object>();

const scopeKeys = ["authProjectIdV2", "authTenantIdV2", "authUidV2"] as const;
const tokenKeys = [
  "authIncarnationSchemaVersionV2", ...scopeKeys, "accountGenerationV2",
  "accountLifecycleEpochV2", "authTimeSec",
] as const;
const lifecycleKeys = [
  "authIncarnationSchemaVersionV2", ...scopeKeys, "accountGenerationV2",
  "accountLifecycleEpochV2", "lifecycleStateV2", "reauthAfterSecV2",
] as const;
const membershipKeys = [
  "authIncarnationSchemaVersionV2", ...scopeKeys, "accountGenerationV2",
  "accountLifecycleEpochV2", "membershipStatusV2", "associationId", "capabilities",
] as const;
const projectionKeys = [
  "authIncarnationSchemaVersionV2", ...scopeKeys, "accountGenerationV2",
  "accountLifecycleEpochV2", "lifecycleStateV2", "membershipStatusV2",
  "reauthAfterSecV2", "associationId", "capabilities",
] as const;
const pendingKeys = [
  "authIncarnationSchemaVersionV2", ...scopeKeys, "accountGenerationV2",
  "accountLifecycleEpochV2", "bindingStateV2", "reauthAfterSecV2",
] as const;

function invalid(label: string): never {
  throw new TypeError(`Invalid Auth incarnation V2 ${label}.`);
}

function record(value: unknown, label: string): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) invalid(label);
  return value as JsonRecord;
}

function exactKeys(value: JsonRecord, expected: readonly string[], label: string): void {
  const actual = Object.keys(value);
  if (actual.length !== expected.length || !expected.every((key) => actual.includes(key))) {
    invalid(`${label} keys`);
  }
}

function identifier(value: unknown, label: string): string {
  // JavaScript String.length and Dart String.length both count UTF-16 code
  // units. Do not normalize: canonically distinct Auth identifiers remain
  // distinct scope values.
  if (typeof value !== "string" || value.length === 0 || value.length > 128 ||
      controlPattern.test(value)) invalid(label);
  return value;
}

function tenant(value: unknown): string | null {
  if (value === null) return null;
  return identifier(value, "tenant ID");
}

function safeCounter(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0 ||
      (value as number) > MAX_SAFE_AUTHORITY_INTEGER_V2) invalid(label);
  return value as number;
}

function generation(value: unknown): string {
  if (typeof value !== "string" || !generationPattern.test(value)) invalid("generation");
  return value;
}

function schema(value: unknown): 2 {
  if (value !== AUTH_INCARNATION_SCHEMA_VERSION_V2) invalid("schema version");
  return 2;
}

function scopeFrom(value: JsonRecord): AuthIncarnationScopeV2 {
  return Object.freeze({
    authProjectIdV2: identifier(value.authProjectIdV2, "project ID"),
    authTenantIdV2: tenant(value.authTenantIdV2),
    authUidV2: identifier(value.authUidV2, "UID"),
  });
}

function stringList(value: unknown, label: string): string[] {
  if (!Array.isArray(value) || value.length > 64 ||
      !value.every((entry) => typeof entry === "string" && entry.length > 0 &&
        entry.length <= 128 && !controlPattern.test(entry) && capabilitySet.has(entry)) ||
      new Set(value).size !== value.length) invalid(label);
  return Object.freeze([...value]) as string[];
}

export function parseAuthIncarnationScopeV2(value: unknown): AuthIncarnationScopeV2 {
  const data = record(value, "scope");
  exactKeys(data, scopeKeys, "scope");
  return scopeFrom(data);
}

export function parseAuthIncarnationTokenProofV2(value: unknown): AuthIncarnationTokenProofV2 {
  const data = record(value, "token proof");
  exactKeys(data, tokenKeys, "token proof");
  return Object.freeze({
    authIncarnationSchemaVersionV2: schema(data.authIncarnationSchemaVersionV2),
    ...scopeFrom(data),
    accountGenerationV2: generation(data.accountGenerationV2),
    accountLifecycleEpochV2: safeCounter(data.accountLifecycleEpochV2, "lifecycle epoch"),
    authTimeSec: safeCounter(data.authTimeSec, "authentication time"),
  });
}

export function parseAccountLifecycleAuthorityV2(value: unknown): AccountLifecycleAuthorityV2 {
  const data = record(value, "lifecycle");
  exactKeys(data, lifecycleKeys, "lifecycle");
  if (!["pending", "active", "deleting", "deleted"].includes(data.lifecycleStateV2 as string)) {
    invalid("lifecycle state");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: schema(data.authIncarnationSchemaVersionV2),
    ...scopeFrom(data),
    accountGenerationV2: generation(data.accountGenerationV2),
    accountLifecycleEpochV2: safeCounter(data.accountLifecycleEpochV2, "lifecycle epoch"),
    lifecycleStateV2: data.lifecycleStateV2 as AccountLifecycleStateV2,
    reauthAfterSecV2: safeCounter(data.reauthAfterSecV2, "reauthentication boundary"),
  });
}

export function parseMembershipAuthorityV2(value: unknown): MembershipAuthorityV2 {
  const data = record(value, "membership");
  exactKeys(data, membershipKeys, "membership");
  if (!["active", "suspended", "revoked"].includes(data.membershipStatusV2 as string)) {
    invalid("membership status");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: schema(data.authIncarnationSchemaVersionV2),
    ...scopeFrom(data),
    accountGenerationV2: generation(data.accountGenerationV2),
    accountLifecycleEpochV2: safeCounter(data.accountLifecycleEpochV2, "lifecycle epoch"),
    membershipStatusV2: data.membershipStatusV2 as MembershipStatusV2,
    associationId: identifier(data.associationId, "association ID"),
    capabilities: stringList(data.capabilities, "capabilities"),
  });
}

export function parseStorageAuthorizationProjectionV2(value: unknown): StorageAuthorizationProjectionV2 {
  const data = record(value, "Storage projection");
  exactKeys(data, projectionKeys, "Storage projection");
  if (!["pending", "active", "deleting", "deleted"].includes(data.lifecycleStateV2 as string)) {
    invalid("lifecycle state");
  }
  if (!["active", "suspended", "revoked"].includes(data.membershipStatusV2 as string)) {
    invalid("membership status");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: schema(data.authIncarnationSchemaVersionV2),
    ...scopeFrom(data),
    accountGenerationV2: generation(data.accountGenerationV2),
    accountLifecycleEpochV2: safeCounter(data.accountLifecycleEpochV2, "lifecycle epoch"),
    lifecycleStateV2: data.lifecycleStateV2 as AccountLifecycleStateV2,
    membershipStatusV2: data.membershipStatusV2 as MembershipStatusV2,
    reauthAfterSecV2: safeCounter(data.reauthAfterSecV2, "reauthentication boundary"),
    associationId: identifier(data.associationId, "association ID"),
    capabilities: stringList(data.capabilities, "capabilities"),
  });
}

export function parsePendingAuthIncarnationBindingV2(value: unknown): PendingAuthIncarnationBindingV2 {
  const data = record(value, "pending binding");
  exactKeys(data, pendingKeys, "pending binding");
  if (data.bindingStateV2 !== "pending") invalid("pending binding state");
  return Object.freeze({
    authIncarnationSchemaVersionV2: schema(data.authIncarnationSchemaVersionV2),
    ...scopeFrom(data),
    accountGenerationV2: generation(data.accountGenerationV2),
    accountLifecycleEpochV2: safeCounter(data.accountLifecycleEpochV2, "lifecycle epoch"),
    bindingStateV2: "pending",
    reauthAfterSecV2: safeCounter(data.reauthAfterSecV2, "reauthentication boundary"),
  });
}

function sameScope(left: AuthIncarnationScopeV2, right: AuthIncarnationScopeV2): boolean {
  return left.authProjectIdV2 === right.authProjectIdV2 &&
    left.authTenantIdV2 === right.authTenantIdV2 &&
    left.authUidV2 === right.authUidV2;
}

function denied(code: AuthIncarnationDenialCodeV2): AuthIncarnationAuthorizationDecisionV2 {
  return {authorized: false, code};
}

function activeBinding(
  sessionAttemptIdV2: string,
  token: AuthIncarnationTokenProofV2,
  lifecycle: AccountLifecycleAuthorityV2,
  membership: MembershipAuthorityV2,
): ValidatedActiveAuthorityV2 {
  const binding = Object.freeze({
    sessionAttemptIdV2,
    scope: Object.freeze({
      authProjectIdV2: token.authProjectIdV2,
      authTenantIdV2: token.authTenantIdV2,
      authUidV2: token.authUidV2,
    }),
    accountGenerationV2: token.accountGenerationV2,
    accountLifecycleEpochV2: token.accountLifecycleEpochV2,
    reauthAfterSecV2: lifecycle.reauthAfterSecV2,
    associationId: membership.associationId,
    capabilities: Object.freeze([...membership.capabilities]),
  });
  validatedBindings.add(binding);
  return binding;
}

export function evaluateAccountAuthorizationV2(input: {
  sessionAttemptIdV2: unknown;
  expectedScope: unknown;
  tokenProof: unknown | null | undefined;
  lifecycle: unknown;
  membership: unknown;
  requiredCapability: string;
}): AuthIncarnationAuthorizationDecisionV2 {
  let sessionAttemptIdV2: string;
  try {
    sessionAttemptIdV2 = identifier(input.sessionAttemptIdV2, "session attempt ID");
  } catch {
    return denied("invalid_token_proof");
  }
  let expectedScope: AuthIncarnationScopeV2;
  try {
    expectedScope = parseAuthIncarnationScopeV2(input.expectedScope);
  } catch {
    return denied("scope_mismatch");
  }
  if (input.tokenProof === null || input.tokenProof === undefined) {
    return denied("missing_token_proof");
  }
  let token: AuthIncarnationTokenProofV2;
  let lifecycle: AccountLifecycleAuthorityV2;
  let membership: MembershipAuthorityV2;
  try {
    token = parseAuthIncarnationTokenProofV2(input.tokenProof);
  } catch {
    return denied("invalid_token_proof");
  }
  try {
    lifecycle = parseAccountLifecycleAuthorityV2(input.lifecycle);
  } catch {
    return denied("invalid_lifecycle");
  }
  if (lifecycle.lifecycleStateV2 !== "active") return denied("lifecycle_inactive");
  try {
    membership = parseMembershipAuthorityV2(input.membership);
  } catch {
    return denied("invalid_membership");
  }
  if (membership.membershipStatusV2 !== "active") return denied("membership_inactive");
  if (!sameScope(token, expectedScope) || !sameScope(lifecycle, expectedScope) ||
      !sameScope(membership, expectedScope)) return denied("scope_mismatch");
  if (token.accountGenerationV2 !== lifecycle.accountGenerationV2 ||
      token.accountGenerationV2 !== membership.accountGenerationV2) {
    return denied("generation_mismatch");
  }
  if (token.accountLifecycleEpochV2 !== lifecycle.accountLifecycleEpochV2 ||
      token.accountLifecycleEpochV2 !== membership.accountLifecycleEpochV2) {
    return denied("epoch_mismatch");
  }
  if (token.authTimeSec <= lifecycle.reauthAfterSecV2) {
    return denied("reauthentication_required");
  }
  if (!membership.capabilities.includes(input.requiredCapability)) {
    return denied("capability_denied");
  }
  return {
    authorized: true,
    binding: activeBinding(sessionAttemptIdV2, token, lifecycle, membership),
  };
}

export function evaluateStorageAuthorizationV2(input: {
  sessionAttemptIdV2: unknown;
  expectedScope: unknown;
  tokenProof: unknown | null | undefined;
  projection: unknown;
  requiredCapability: string;
}): AuthIncarnationAuthorizationDecisionV2 {
  let sessionAttemptIdV2: string;
  try {
    sessionAttemptIdV2 = identifier(input.sessionAttemptIdV2, "session attempt ID");
  } catch {
    return denied("invalid_token_proof");
  }
  let expectedScope: AuthIncarnationScopeV2;
  try {
    expectedScope = parseAuthIncarnationScopeV2(input.expectedScope);
  } catch {
    return denied("scope_mismatch");
  }
  if (input.tokenProof === null || input.tokenProof === undefined) {
    return denied("missing_token_proof");
  }
  let token: AuthIncarnationTokenProofV2;
  let projection: StorageAuthorizationProjectionV2;
  try {
    token = parseAuthIncarnationTokenProofV2(input.tokenProof);
  } catch {
    return denied("invalid_token_proof");
  }
  try {
    projection = parseStorageAuthorizationProjectionV2(input.projection);
  } catch {
    return denied("invalid_projection");
  }
  if (projection.lifecycleStateV2 !== "active") return denied("lifecycle_inactive");
  if (projection.membershipStatusV2 !== "active") return denied("membership_inactive");
  if (!sameScope(token, expectedScope) || !sameScope(projection, expectedScope)) {
    return denied("scope_mismatch");
  }
  if (token.accountGenerationV2 !== projection.accountGenerationV2) {
    return denied("generation_mismatch");
  }
  if (token.accountLifecycleEpochV2 !== projection.accountLifecycleEpochV2) {
    return denied("epoch_mismatch");
  }
  if (token.authTimeSec <= projection.reauthAfterSecV2) {
    return denied("reauthentication_required");
  }
  if (!projection.capabilities.includes(input.requiredCapability)) {
    return denied("capability_denied");
  }
  const membership: MembershipAuthorityV2 = {
    authIncarnationSchemaVersionV2: 2,
    ...expectedScope,
    accountGenerationV2: projection.accountGenerationV2,
    accountLifecycleEpochV2: projection.accountLifecycleEpochV2,
    membershipStatusV2: "active",
    associationId: projection.associationId,
    capabilities: [...projection.capabilities],
  };
  const lifecycle: AccountLifecycleAuthorityV2 = {
    authIncarnationSchemaVersionV2: 2,
    ...expectedScope,
    accountGenerationV2: projection.accountGenerationV2,
    accountLifecycleEpochV2: projection.accountLifecycleEpochV2,
    lifecycleStateV2: "active",
    reauthAfterSecV2: projection.reauthAfterSecV2,
  };
  return {
    authorized: true,
    binding: activeBinding(sessionAttemptIdV2, token, lifecycle, membership),
  };
}

export function buildStorageAuthorizationProjectionV2(
  binding: ValidatedActiveAuthorityV2,
): StorageAuthorizationProjectionV2 {
  if (typeof binding !== "object" || binding === null || !validatedBindings.has(binding)) {
    invalid("validated authority binding");
  }
  return Object.freeze({
    authIncarnationSchemaVersionV2: 2,
    ...binding.scope,
    accountGenerationV2: binding.accountGenerationV2,
    accountLifecycleEpochV2: binding.accountLifecycleEpochV2,
    lifecycleStateV2: "active",
    membershipStatusV2: "active",
    reauthAfterSecV2: binding.reauthAfterSecV2,
    associationId: binding.associationId,
    capabilities: Object.freeze([...binding.capabilities]) as string[],
  });
}
