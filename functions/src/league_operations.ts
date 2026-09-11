import {createHash, randomUUID} from "crypto";
import * as admin from "firebase-admin";
import {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Query,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {AUTHORIZATION_SCHEMA_VERSION, Role, capabilities, isRole} from "./authorization";
import {
  CommandScope,
  ScopedAuthorityError,
  TeamEntryScope,
  V2Capability,
  requireScopedAuthorityInTransaction,
} from "./domain/scoped_authority";

const SCHEMA_VERSION = 1;
const LEAGUE_TIMEZONE = "America/Jamaica";
const MAX_BATCH_GAMES = 25;
const MAX_GAME_DURATION_MS = 24 * 60 * 60 * 1000;
const MAX_ROSTER_WORKSPACE_RECORDS = 100;
const MAX_DIVISION_REFERENCES = 500;
const ACTOR_QUOTA_PER_MINUTE = 120;
const ACTOR_QUOTA_PER_DAY = 2_000;
const QUOTA_STATE_SCHEMA_VERSION = 2;
const QUOTA_TOKEN_SCALE = 1_000;
const MINUTE_QUOTA_WINDOW_MS = 60_000;
const DAY_QUOTA_WINDOW_MS = 86_400_000;
const DIVISION_DELETE_LEASE_MS = 5 * 60 * 1000;
const idPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const operationPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{7,127}$/;
const generationPattern = /^[a-f0-9]{64}$/;

type Json = Record<string, unknown>;
type RosterKind = "addPlayer" | "updatePlayer" | "removePlayer";

interface Caller {
  uid: string;
  authProjectIdV2: string;
  authTenantIdV2: string | null;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
  authTimeSec: number;
}

interface Authority {
  uid: string;
  associationId: string;
  role: Role | null;
  capabilities: string[];
  teamId: string | null;
  schemaVersion: 1 | 2;
  accountGenerationV2: string;
  accountLifecycleEpochV2: number;
}

interface RosterFacts {
  playerId: string | null;
  registrationId: string | null;
  displayName: string;
  jerseyNumber: string;
  position: string | null;
}

interface ScheduleInput {
  seasonId: string;
  divisionId: string;
  homeTeamId: string;
  awayTeamId: string;
  startTime: Timestamp;
  endTime: Timestamp;
  location: string | null;
}

interface ScheduleAuditState {
  title: string;
  description: string | null;
  status: "scheduled" | "cancelled";
  cancellationReason: string | null;
}

interface WorkflowControl {
  competitionId: string;
  seasonId: string;
  phaseId: string;
  authorityMode: "legacyV1" | "v2";
  custodyPolicyVersionV2: number;
  privacyEpochV2: number;
}

function object(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "A request object is required.");
  }
  return value as Json;
}

function exactKeys(value: Json, required: readonly string[], optional: readonly string[] = []): void {
  const allowed = new Set([...required, ...optional]);
  if (!required.every((key) => Object.prototype.hasOwnProperty.call(value, key)) ||
      Object.keys(value).some((key) => !allowed.has(key))) {
    throw new HttpsError("invalid-argument", "The request shape is invalid.");
  }
}

function schema(value: Json): void {
  if (value.schemaVersion !== SCHEMA_VERSION) {
    throw new HttpsError("failed-precondition", "This app version is not supported.");
  }
}

function caller(request: CallableRequest<unknown>): Caller {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before completing this action.");
  const token = request.auth.token as Record<string, unknown>;
  const firebase = token.firebase && typeof token.firebase === "object" && !Array.isArray(token.firebase) ?
    token.firebase as Record<string, unknown> : {};
  const tenant = firebase.tenant === undefined ? null : firebase.tenant;
  if (token.authIncarnationSchemaVersionV2 !== 2 ||
      typeof token.aud !== "string" || !idPattern.test(token.aud) ||
      !(tenant === null || (typeof tenant === "string" && idPattern.test(tenant))) ||
      typeof token.accountGenerationV2 !== "string" || !generationPattern.test(token.accountGenerationV2) ||
      !Number.isSafeInteger(token.accountLifecycleEpochV2) || (token.accountLifecycleEpochV2 as number) < 0 ||
      !Number.isSafeInteger(token.auth_time) || (token.auth_time as number) < 0) {
    throw new HttpsError("permission-denied", "Current account-incarnation proof is required.");
  }
  return {
    uid: request.auth.uid,
    authProjectIdV2: token.aud,
    authTenantIdV2: tenant as string | null,
    accountGenerationV2: token.accountGenerationV2,
    accountLifecycleEpochV2: token.accountLifecycleEpochV2 as number,
    authTimeSec: token.auth_time as number,
  };
}

function id(value: unknown, key: string, operation = false): string {
  const pattern = operation ? operationPattern : idPattern;
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new HttpsError("invalid-argument", `${key} must be an opaque identifier.`);
  }
  return value;
}

function text(value: unknown, key: string, maximum: number, nullable = false): string | null {
  if (nullable && (value === null || value === undefined || value === "")) return null;
  if (typeof value !== "string" || value.trim().length === 0 || value.trim().length > maximum || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new HttpsError("invalid-argument", `${key} must be between 1 and ${maximum} characters.`);
  }
  return value.trim().normalize("NFC");
}

function counter(value: unknown, key: string, allowZero = true): number {
  if (!Number.isSafeInteger(value) || (value as number) < (allowZero ? 0 : 1)) {
    throw new HttpsError("invalid-argument", `${key} must be a valid version.`);
  }
  return value as number;
}

function isoTimestamp(value: unknown, key: string): Timestamp {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${key} must be an ISO UTC instant.`);
  const date = new Date(value);
  if (Number.isNaN(date.getTime()) || !value.endsWith("Z") || date.toISOString() !== value) {
    throw new HttpsError("invalid-argument", `${key} must be a canonical ISO UTC instant.`);
  }
  return Timestamp.fromDate(date);
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object" && !(value instanceof Timestamp)) {
    return Object.keys(value as Json).sort().reduce<Json>((result, key) => {
      result[key] = canonical((value as Json)[key]);
      return result;
    }, {});
  }
  return value;
}

function hash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(canonical(value)), "utf8").digest("hex");
}

function scheduleSemantic(input: ScheduleInput): Json {
  return {
    seasonId: input.seasonId,
    divisionId: input.divisionId,
    homeTeamId: input.homeTeamId,
    awayTeamId: input.awayTeamId,
    startTimeUtc: input.startTime.toDate().toISOString(),
    endTimeUtc: input.endTime.toDate().toISOString(),
    location: input.location,
  };
}

function operationReceiptRef(db: Firestore, actorId: string, operation: string, operationId: string) {
  return db.doc(`leagueOperationReceipts/${hash({actorId, operation, operationId})}`);
}

function receiptReplay(snapshot: DocumentSnapshot, fingerprint: string, expected: {
  actorId: string;
  associationId: string;
  operation: string;
  operationId: string;
}): Json | null {
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  if (data.requestFingerprint !== fingerprint || data.actorId !== expected.actorId ||
      data.associationId !== expected.associationId || data.operation !== expected.operation ||
      data.operationId !== expected.operationId || !data.result || typeof data.result !== "object") {
    throw new HttpsError("already-exists", "This operation ID was already used for different details.");
  }
  return data.result as Json;
}

function saveReceipt(transaction: Transaction, ref: DocumentReference, input: {
  actorId: string;
  associationId: string;
  operation: string;
  operationId: string;
  requestFingerprint: string;
  result: Json;
}): void {
  transaction.create(ref, {
    schemaVersion: SCHEMA_VERSION,
    ...input,
    createdAt: FieldValue.serverTimestamp(),
  });
}

function safeStoredCounter(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function actorAuthorityRef(db: Firestore, associationId: string, uid: string) {
  return db.doc(`associations/${associationId}/leagueActorAuthorities/${uid}`);
}

async function enforceActorQuota(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  cost: number,
): Promise<void> {
  const now = Timestamp.now();
  const ref = db.doc(`associations/${authority.associationId}/leagueActorQuotas/${hash({uid: authority.uid})}`);
  const snapshot = await transaction.get(ref);
  const data = snapshot.data() ?? {};
  if (snapshot.exists && (data.schemaVersion !== QUOTA_STATE_SCHEMA_VERSION ||
      data.associationId !== authority.associationId || data.actorId !== authority.uid)) {
    throw new HttpsError("failed-precondition", "The league operation quota state requires administrator recovery.");
  }
  const refill = (tokens: unknown, refilledAt: unknown, capacity: number, windowMs: number): number => {
    if (!snapshot.exists) return capacity * QUOTA_TOKEN_SCALE;
    if (!safeStoredCounter(tokens) || tokens > capacity * QUOTA_TOKEN_SCALE || !(refilledAt instanceof Timestamp)) {
      throw new HttpsError("failed-precondition", "The league operation quota state requires administrator recovery.");
    }
    const elapsedMs = Math.max(0, Math.min(windowMs, now.toMillis() - refilledAt.toMillis()));
    const replenished = Math.floor(elapsedMs * capacity * QUOTA_TOKEN_SCALE / windowMs);
    return Math.min(capacity * QUOTA_TOKEN_SCALE, tokens + replenished);
  };
  const minuteTokens = refill(data.minuteTokens, data.minuteRefilledAt, ACTOR_QUOTA_PER_MINUTE, MINUTE_QUOTA_WINDOW_MS);
  const dayTokens = refill(data.dayTokens, data.dayRefilledAt, ACTOR_QUOTA_PER_DAY, DAY_QUOTA_WINDOW_MS);
  const tokenCost = cost * QUOTA_TOKEN_SCALE;
  if (cost < 1 || cost > MAX_BATCH_GAMES || minuteTokens < tokenCost || dayTokens < tokenCost) {
    throw new HttpsError("resource-exhausted", "The league operation quota has been reached. Try again later.");
  }
  transaction.set(ref, {
    schemaVersion: QUOTA_STATE_SCHEMA_VERSION,
    associationId: authority.associationId,
    actorId: authority.uid,
    minuteTokens: minuteTokens - tokenCost,
    minuteRefilledAt: now,
    dayTokens: dayTokens - tokenCost,
    dayRefilledAt: now,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: false});
}

async function authorityInTransaction(
  transaction: Transaction,
  db: Firestore,
  actor: Caller,
): Promise<Authority> {
  const membership = await transaction.get(db.doc(`memberships/${actor.uid}`));
  if (!membership.exists) throw new HttpsError("permission-denied", "Active league access is required.");
  const data = membership.data() ?? {};
  const version = data.authorizationSchemaVersion;
  const caps = Array.isArray(data.capabilities) ? data.capabilities.filter((entry): entry is string => typeof entry === "string") : [];
  const legacyRoleValid = version !== AUTHORIZATION_SCHEMA_VERSION || isRole(data.role);
  if ((version !== AUTHORIZATION_SCHEMA_VERSION && version !== 2) || !legacyRoleValid ||
      data.status !== "active" || data.membershipStatusV2 !== "active" ||
      data.authIncarnationSchemaVersionV2 !== 2 || data.authProjectIdV2 !== actor.authProjectIdV2 ||
      data.authTenantIdV2 !== actor.authTenantIdV2 || data.authUidV2 !== actor.uid ||
      data.accountGenerationV2 !== actor.accountGenerationV2 ||
      data.accountLifecycleEpochV2 !== actor.accountLifecycleEpochV2 ||
      typeof data.associationId !== "string" || !idPattern.test(data.associationId) || !Array.isArray(data.capabilities)) {
    throw new HttpsError("permission-denied", "Active league access is required.");
  }
  const projection = await transaction.get(actorAuthorityRef(db, data.associationId, actor.uid));
  const guard = projection.data() ?? {};
  if (!projection.exists || guard.schemaVersion !== SCHEMA_VERSION ||
      guard.authIncarnationSchemaVersionV2 !== 2 || guard.authProjectIdV2 !== actor.authProjectIdV2 ||
      guard.authTenantIdV2 !== actor.authTenantIdV2 || guard.authUidV2 !== actor.uid ||
      guard.accountGenerationV2 !== actor.accountGenerationV2 ||
      guard.accountLifecycleEpochV2 !== actor.accountLifecycleEpochV2 ||
      guard.lifecycleStateV2 !== "active" || guard.membershipStatusV2 !== "active" ||
      guard.associationId !== data.associationId || guard.authorizationSchemaVersion !== version ||
      guard.operationalStateV2 !== "operating" || guard.custodyStateV2 !== "operating" ||
      !safeStoredCounter(guard.custodyPolicyVersionV2) || guard.custodyPolicyVersionV2 < 1 ||
      guard.identitySuppressedV2 !== false || guard.privacyStateV2 !== "internal" ||
      !safeStoredCounter(guard.privacyEpochV2) || guard.privacyEpochV2 < 1 ||
      !safeStoredCounter(guard.reauthAfterSecV2) || actor.authTimeSec <= guard.reauthAfterSecV2) {
    throw new HttpsError("permission-denied", "Current lifecycle, custody, and privacy authority is required.");
  }
  const authority: Authority = {
    uid: actor.uid,
    associationId: data.associationId,
    role: isRole(data.role) ? data.role : null,
    capabilities: caps,
    teamId: typeof data.teamId === "string" ? data.teamId : null,
    schemaVersion: version,
    accountGenerationV2: actor.accountGenerationV2,
    accountLifecycleEpochV2: actor.accountLifecycleEpochV2,
  };
  return authority;
}

interface ReceiptQuotaCheck {
  operation: string;
  operationId: string;
  fingerprint: string;
}

async function consumeInvocationQuota(
  db: Firestore,
  actor: Caller,
  cost = 1,
  receiptCheck?: ReceiptQuotaCheck,
): Promise<Json | null> {
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    if (receiptCheck) {
      const receipt = await transaction.get(operationReceiptRef(
        db,
        actor.uid,
        receiptCheck.operation,
        receiptCheck.operationId,
      ));
      const replay = receiptReplay(receipt, receiptCheck.fingerprint, {
        actorId: actor.uid,
        associationId: authority.associationId,
        operation: receiptCheck.operation,
        operationId: receiptCheck.operationId,
      });
      if (replay) return replay;
    }
    await enforceActorQuota(transaction, db, authority, cost);
    return null;
  });
}

function requireCapability(authority: Authority, required: string): void {
  if (!authority.capabilities.includes(required)) {
    throw new HttpsError("permission-denied", "You do not have permission to complete this action.");
  }
}

function requireWorkflowReady(
  control: DocumentSnapshot,
  associationId: string,
  capability: "rosters" | "divisionDeletion" | "scheduling",
): WorkflowControl {
  const data = control.data() ?? {};
  if (!control.exists || data.schemaVersion !== SCHEMA_VERSION || data.callablesReady !== true ||
      data.directWritesDenied !== true || data.lifecycleAuthorityReady !== true ||
      data.custodyAuthorityReady !== true || data.actorAuthorityReady !== true ||
      data.identityAuthorityReady !== true || data.privacyAuthorityReady !== true || data[capability] !== true ||
      data.associationId !== associationId || !idPattern.test(data.competitionId) ||
      !idPattern.test(data.activeSeasonId) || !idPattern.test(data.defaultPhaseId) ||
      !safeStoredCounter(data.custodyPolicyVersionV2) || data.custodyPolicyVersionV2 < 1 ||
      !safeStoredCounter(data.privacyEpochV2) || data.privacyEpochV2 < 1 ||
      data.timezone !== LEAGUE_TIMEZONE || (data.authorityMode !== "legacyV1" && data.authorityMode !== "v2")) {
    throw new HttpsError("failed-precondition", "This league workflow is not active yet.");
  }
  return {
    competitionId: data.competitionId,
    seasonId: data.activeSeasonId,
    phaseId: data.defaultPhaseId,
    authorityMode: data.authorityMode,
    custodyPolicyVersionV2: data.custodyPolicyVersionV2,
    privacyEpochV2: data.privacyEpochV2,
  };
}

async function requireActorWorkflowBinding(
  transaction: Transaction,
  db: Firestore,
  actor: Caller,
  authority: Authority,
  workflow: WorkflowControl,
): Promise<void> {
  const projection = await transaction.get(actorAuthorityRef(db, authority.associationId, actor.uid));
  if (projection.get("custodyPolicyVersionV2") !== workflow.custodyPolicyVersionV2 ||
      projection.get("privacyEpochV2") !== workflow.privacyEpochV2) {
    throw new HttpsError("permission-denied", "The actor authority projection is stale.");
  }
}

async function requireV2Authority(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  capability: V2Capability,
  scope: CommandScope,
): Promise<void> {
  try {
    await requireScopedAuthorityInTransaction(transaction, db, {
      uid: authority.uid,
      capability,
      scope,
      versions: {
        authorizationSchemaVersion: 2,
        domainSchemaVersion: 2,
        commandSchemaVersion: 2,
      },
    });
  } catch (error) {
    if (error instanceof ScopedAuthorityError) {
      throw new HttpsError("permission-denied", `Scoped authority denied: ${error.code}.`);
    }
    throw error;
  }
}

function workflowRef(db: Firestore, associationId: string) {
  return db.doc(`associations/${associationId}/leagueWorkflowControl/current`);
}

function rosterRefs(
  db: Firestore,
  associationId: string,
  competitionId: string,
  teamEntryId: string,
  seasonId: string,
) {
  const root = `associations/${associationId}/competitions/${competitionId}/seasons/${seasonId}`;
  return {
    head: db.doc(`${root}/rosterHeads/${teamEntryId}`),
    registrations: db.collection(`${root}/rosterMemberships`),
    proposals: db.collection(`${root}/rosterAssertions`),
    decisions: db.collection(`${root}/rosterAssertionDecisions`),
  };
}

function rosterIdentityGuardRef(db: Firestore, associationId: string, playerId: string) {
  return db.doc(`associations/${associationId}/leagueIdentityAuthorities/${playerId}`);
}

async function requireRosterIdentity(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  workflow: WorkflowControl,
  registration: DocumentSnapshot,
): Promise<void> {
  const playerId = id(registration.get("playerId"), "stored playerId");
  const player = await transaction.get(db.doc(`associations/${authority.associationId}/players/${playerId}`));
  const personId = player.exists ? id(player.get("personId"), "stored personId") : "missing";
  const person = player.exists ? await transaction.get(db.doc(
    `associations/${authority.associationId}/persons/${personId}`,
  )) : null;
  const personVersionId = person?.exists ? id(person.get("identityVersionId"), "stored identityVersionId") : "missing";
  const playerVersionId = player.exists ? id(player.get("displayNameVersionId"), "stored displayNameVersionId") : "missing";
  const [personVersion, playerVersion, guard] = player.exists && person?.exists ? await Promise.all([
    transaction.get(db.doc(`associations/${authority.associationId}/persons/${personId}/identityVersions/${personVersionId}`)),
    transaction.get(db.doc(`associations/${authority.associationId}/players/${playerId}/displayNameVersions/${playerVersionId}`)),
    transaction.get(rosterIdentityGuardRef(db, authority.associationId, playerId)),
  ]) : [null, null, null];
  const displayName = registration.get("displayName");
  if (!player.exists || !person?.exists || !personVersion?.exists || !playerVersion?.exists || !guard?.exists ||
      player.get("status") !== "active" || person.get("status") !== "active" ||
      player.get("identitySuppressedV2") !== false || person.get("identitySuppressedV2") !== false ||
      player.get("privacyStateV2") !== "internal" || person.get("privacyStateV2") !== "internal" ||
      player.get("privacyEpochV2") !== workflow.privacyEpochV2 || person.get("privacyEpochV2") !== workflow.privacyEpochV2 ||
      personVersion.get("versionId") !== personVersionId || playerVersion.get("versionId") !== playerVersionId ||
      personVersion.get("displayName") !== displayName || playerVersion.get("displayName") !== displayName ||
      player.get("displayName") !== displayName ||
      guard.get("schemaVersion") !== SCHEMA_VERSION || guard.get("associationId") !== authority.associationId ||
      guard.get("playerId") !== playerId || guard.get("personId") !== personId ||
      guard.get("identitySuppressedV2") !== false || guard.get("privacyStateV2") !== "internal" ||
      guard.get("privacyEpochV2") !== workflow.privacyEpochV2 ||
      guard.get("currentPersonIdentityVersionId") !== personVersionId ||
      guard.get("currentPlayerDisplayNameVersionId") !== playerVersionId ||
      guard.get("rosterReadable") !== true || guard.get("rosterMutable") !== true) {
    throw new HttpsError("failed-precondition", "Current unsuppressed roster identity authority is required.");
  }
}

async function requireTeamScope(transaction: Transaction, db: Firestore, authority: Authority, teamId: string, seasonId: string): Promise<DocumentSnapshot> {
  const team = await transaction.get(db.doc(`associations/${authority.associationId}/teams/${teamId}`));
  const data = team.data() ?? {};
  if (!team.exists || data.seasonId !== seasonId || data.status === "archived") {
    throw new HttpsError("failed-precondition", "The team is not active in this season.");
  }
  const divisionId = id(data.divisionId, "divisionId");
  const division = await transaction.get(db.doc(`associations/${authority.associationId}/divisions/${divisionId}`));
  if (!division.exists || division.get("status") === "archived" || division.get("deletionPending")) {
    throw new HttpsError("failed-precondition", "The team's division is not active for roster changes.");
  }
  return team;
}

async function requireCanonicalTeamEntry(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  workflow: WorkflowControl,
  team: DocumentSnapshot,
  teamId: string,
  seasonId: string,
): Promise<{teamEntryId: string; divisionId: string}> {
  const teamEntryId = id(team.get("teamEntryId"), "teamEntryId");
  const divisionId = id(team.get("divisionId"), "divisionId");
  const entry = await transaction.get(db.doc(
    `associations/${authority.associationId}/competitions/${workflow.competitionId}/seasons/${seasonId}/teamEntries/${teamEntryId}`,
  ));
  if (!entry.exists || entry.get("dataSchemaVersion") !== 2 || entry.get("associationId") !== authority.associationId ||
      entry.get("competitionId") !== workflow.competitionId || entry.get("seasonId") !== seasonId ||
      entry.get("divisionId") !== divisionId || entry.get("teamEntryId") !== teamEntryId ||
      entry.get("teamId") !== teamId || entry.get("registrationStatus") !== "active") {
    throw new HttpsError("failed-precondition", "The canonical team entry is not active or does not match this team.");
  }
  return {teamEntryId, divisionId};
}

async function requireRosterAuthority(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  workflow: WorkflowControl,
  team: DocumentSnapshot,
  teamId: string,
  seasonId: string,
): Promise<{manager: boolean; teamEntryId: string}> {
  if (workflow.seasonId !== seasonId) throw new HttpsError("failed-precondition", "The requested season is not active.");
  const canonicalTeam = await requireCanonicalTeamEntry(transaction, db, authority, workflow, team, teamId, seasonId);
  if (workflow.authorityMode === "legacyV1") {
    if (authority.schemaVersion !== 1) throw new HttpsError("permission-denied", "Legacy authority is not available to this account.");
    if (authority.capabilities.includes(capabilities.teamsManage)) return {manager: true, teamEntryId: canonicalTeam.teamEntryId};
    if (!authority.capabilities.includes(capabilities.teamsRepresent) || authority.teamId !== teamId) {
      throw new HttpsError("permission-denied", "Representatives may use only their assigned team.");
    }
    return {manager: false, teamEntryId: canonicalTeam.teamEntryId};
  }
  if (authority.schemaVersion !== 2) throw new HttpsError("permission-denied", "V2 authority is required for this workflow.");
  if (authority.capabilities.includes("rosters.manage")) {
    await requireV2Authority(transaction, db, authority, "rosters.manage", {
      associationId: authority.associationId,
      competitionId: workflow.competitionId,
      seasonId,
    });
    return {manager: true, teamEntryId: canonicalTeam.teamEntryId};
  }
  const scope: TeamEntryScope = {
    associationId: authority.associationId,
    competitionId: workflow.competitionId,
    seasonId,
    divisionId: canonicalTeam.divisionId,
    teamEntryId: canonicalTeam.teamEntryId,
  };
  await requireV2Authority(transaction, db, authority, "rosters.assert", scope);
  return {manager: false, teamEntryId: canonicalTeam.teamEntryId};
}

async function requireSchedulingAuthority(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  workflow: WorkflowControl,
  seasonId: string,
  divisionId: string,
): Promise<void> {
  if (workflow.seasonId !== seasonId) throw new HttpsError("failed-precondition", "The requested season is not active.");
  if (workflow.authorityMode === "legacyV1") {
    if (authority.schemaVersion !== 1) throw new HttpsError("permission-denied", "Legacy authority is not available to this account.");
    requireCapability(authority, capabilities.scheduleManage);
    return;
  }
  if (authority.schemaVersion !== 2) throw new HttpsError("permission-denied", "V2 authority is required for this workflow.");
  await requireV2Authority(transaction, db, authority, "games.schedule", {
    associationId: authority.associationId,
    competitionId: workflow.competitionId,
    seasonId,
    divisionId,
  });
}

function requestRosterFacts(data: Json, kind: RosterKind): RosterFacts | null {
  if (kind === "removePlayer") return null;
  const jersey = data.jerseyNumber;
  if (typeof jersey !== "string" || jersey.length < 1 || jersey.length > 8 ||
      jersey.trim() !== jersey || /[\u0000-\u001f\u007f]/.test(jersey)) {
    throw new HttpsError("invalid-argument", "jerseyNumber must be a 1-8 character value without outside spaces.");
  }
  return {
    playerId: kind === "addPlayer" ? null : id(data.playerId, "playerId"),
    registrationId: kind === "addPlayer" ? null : id(data.registrationId, "registrationId"),
    displayName: text(data.displayName, "displayName", 120)!,
    jerseyNumber: jersey,
    position: text(data.position, "position", 40, true),
  };
}

function storedRosterFacts(data: DocumentData, registrationId: string): RosterFacts {
  if (typeof data.playerId !== "string" || typeof data.displayName !== "string" || typeof data.jerseyNumber !== "string") {
    throw new HttpsError("failed-precondition", "The roster registration is malformed.");
  }
  return {
    playerId: data.playerId,
    registrationId,
    displayName: data.displayName,
    jerseyNumber: data.jerseyNumber,
    position: typeof data.position === "string" ? data.position : null,
  };
}

function immutableRosterFacts(value: unknown, field: string): RosterFacts | null {
  if (value === null) return null;
  const data = object(value);
  exactKeys(data, ["playerId", "registrationId", "displayName", "jerseyNumber", "position"]);
  if (typeof data.jerseyNumber !== "string" || data.jerseyNumber.length < 1 || data.jerseyNumber.length > 8 ||
      data.jerseyNumber.trim() !== data.jerseyNumber || /[\u0000-\u001f\u007f]/.test(data.jerseyNumber)) {
    throw new HttpsError("failed-precondition", `${field} has an invalid jersey number.`);
  }
  const optionalId = (entry: unknown, key: string) => entry === null ? null : id(entry, `${field}.${key}`);
  return {
    playerId: optionalId(data.playerId, "playerId"),
    registrationId: optionalId(data.registrationId, "registrationId"),
    displayName: text(data.displayName, `${field}.displayName`, 120)!,
    jerseyNumber: data.jerseyNumber,
    position: text(data.position, `${field}.position`, 40, true),
  };
}

function newOpaque(prefix: string): string {
  return `${prefix}_${randomUUID().replace(/-/g, "")}`;
}

async function applyRosterChange(input: {
  transaction: Transaction;
  db: Firestore;
  authority: Authority;
  actorId: string;
  teamId: string;
  seasonId: string;
  kind: RosterKind;
  before: RosterFacts | null;
  after: RosterFacts | null;
  reason: string;
  expectedRosterVersion: number;
  operationId: string;
  workflow: WorkflowControl;
  teamEntryId: string;
  divisionId: string;
}): Promise<{playerId?: string; registrationId?: string; rosterVersion: number}> {
  const {transaction, db, authority, teamId, seasonId, kind} = input;
  const refs = rosterRefs(db, authority.associationId, input.workflow.competitionId, input.teamEntryId, seasonId);
  const headSnap = await transaction.get(refs.head);
  const currentVersion = headSnap.exists ? counter(headSnap.get("rosterVersion"), "stored rosterVersion") : 0;
  if (currentVersion !== input.expectedRosterVersion) {
    throw new HttpsError("aborted", "The roster changed. Reload it before trying again.");
  }

  let playerId = input.before?.playerId ?? undefined;
  let registrationId = input.before?.registrationId ?? undefined;
  const nextVersion = currentVersion + 1;
  if (kind === "addPlayer") {
    playerId = newOpaque("player");
    registrationId = newOpaque("registration");
    const personId = newOpaque("person");
    const identityVersionId = newOpaque("identity");
    transaction.create(db.doc(`associations/${authority.associationId}/persons/${personId}`), {
      dataSchemaVersion: 2, associationId: authority.associationId, personId,
      identityVersionId, status: "active", identitySuppressedV2: false,
      privacyStateV2: "internal", privacyEpochV2: input.workflow.privacyEpochV2,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.doc(`associations/${authority.associationId}/persons/${personId}/identityVersions/${identityVersionId}`), {
      dataSchemaVersion: 2, associationId: authority.associationId, personId,
      versionId: identityVersionId, displayName: input.after!.displayName,
      actorId: input.actorId, recordedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.doc(`associations/${authority.associationId}/players/${playerId}`), {
      dataSchemaVersion: 2, associationId: authority.associationId, playerId, personId,
      displayNameVersionId: identityVersionId, displayName: input.after!.displayName,
      status: "active", identitySuppressedV2: false,
      privacyStateV2: "internal", privacyEpochV2: input.workflow.privacyEpochV2,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.create(db.doc(`associations/${authority.associationId}/players/${playerId}/displayNameVersions/${identityVersionId}`), {
      dataSchemaVersion: 2, associationId: authority.associationId, playerId,
      versionId: identityVersionId, displayName: input.after!.displayName,
      actorId: input.actorId, recordedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(rosterIdentityGuardRef(db, authority.associationId, playerId), {
      schemaVersion: SCHEMA_VERSION,
      associationId: authority.associationId,
      playerId,
      personId,
      identitySuppressedV2: false,
      privacyStateV2: "internal",
      privacyEpochV2: input.workflow.privacyEpochV2,
      currentPersonIdentityVersionId: identityVersionId,
      currentPlayerDisplayNameVersionId: identityVersionId,
      rosterReadable: true,
      rosterMutable: true,
      createdBy: input.actorId,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  const registrationRef = refs.registrations.doc(registrationId!);
  const existingRegistration = kind === "addPlayer" ? null : await transaction.get(registrationRef);
  if (kind !== "addPlayer" && (!existingRegistration!.exists || existingRegistration!.get("status") !== "active")) {
    throw new HttpsError("failed-precondition", "The roster registration is no longer active.");
  }
  if (existingRegistration) {
    await requireRosterIdentity(transaction, db, authority, input.workflow, existingRegistration);
  }
  if (existingRegistration && hash(storedRosterFacts(existingRegistration.data()!, existingRegistration.id)) !== hash(input.before)) {
    throw new HttpsError("failed-precondition", "The roster facts changed after this action was prepared.");
  }
  if (kind === "updatePlayer" && input.after!.displayName !== input.before!.displayName) {
    throw new HttpsError(
      "failed-precondition",
      "Player name changes remain unavailable until governed identity version advancement is active.",
    );
  }
  const membershipVersionId = newOpaque("rosterVersion");
  const versionRef = registrationRef.collection("versions").doc(membershipVersionId);
  const common = {
    dataSchemaVersion: 2,
    associationId: authority.associationId,
    competitionId: input.workflow.competitionId,
    seasonId,
    teamId,
    teamEntryId: input.teamEntryId,
    divisionId: input.divisionId,
    registrationId,
    membershipId: registrationId,
    playerId,
    membershipVersionId,
    rosterVersion: nextVersion,
    eligibilityStatus: kind === "removePlayer" ? "inactive" : "unknown",
    effectiveFrom: existingRegistration?.get("effectiveFrom") ?? FieldValue.serverTimestamp(),
    recordedAt: FieldValue.serverTimestamp(),
  };
  if (kind === "removePlayer") {
    transaction.update(registrationRef, {...common, status: "removed", effectiveTo: FieldValue.serverTimestamp()});
  } else {
    transaction.set(registrationRef, {
      ...common,
      displayName: input.after!.displayName,
      jerseyNumber: input.after!.jerseyNumber,
      position: input.after!.position,
      status: "active",
      effectiveTo: null,
    }, {merge: false});
  }
  transaction.create(versionRef, {
    ...common,
    versionId: membershipVersionId,
    completeFacts: {before: input.before, after: input.after},
    actorId: input.actorId,
    reasonCode: input.reason,
    evidenceRefs: [],
    operationId: input.operationId,
  });
  transaction.set(refs.head, {
    schemaVersion: SCHEMA_VERSION,
    associationId: authority.associationId,
    competitionId: input.workflow.competitionId,
    teamId,
    teamEntryId: input.teamEntryId,
    divisionId: input.divisionId,
    seasonId,
    rosterVersion: nextVersion,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: false});
  return {playerId, registrationId, rosterVersion: nextVersion};
}

export async function getRosterWorkspaceHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "teamId", "seasonId"]);
  schema(data);
  const teamId = id(data.teamId, "teamId");
  const seasonId = id(data.seasonId, "seasonId");
  const db = admin.firestore();
  await consumeInvocationQuota(db, actor);
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const [control, team] = await Promise.all([
      transaction.get(workflowRef(db, authority.associationId)),
      requireTeamScope(transaction, db, authority, teamId, seasonId),
    ]);
    const workflow = requireWorkflowReady(control, authority.associationId, "rosters");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    const rosterAuthority = await requireRosterAuthority(transaction, db, authority, workflow, team, teamId, seasonId);
    const refs = rosterRefs(db, authority.associationId, workflow.competitionId, rosterAuthority.teamEntryId, seasonId);
    const [head, registrations, proposals, decisions] = await Promise.all([
      transaction.get(refs.head),
      transaction.get(refs.registrations.where("teamId", "==", teamId).where("seasonId", "==", seasonId)),
      transaction.get(refs.proposals.where("teamId", "==", teamId).where("seasonId", "==", seasonId)),
      transaction.get(refs.decisions.where("teamId", "==", teamId).where("seasonId", "==", seasonId)),
    ]);
    const decisionsByProposal = new Map(decisions.docs.map((entry) => [entry.get("proposalId"), entry.data()]));
    const rosterVersion = head.exists ? counter(head.get("rosterVersion"), "stored rosterVersion") : 0;
    if (registrations.size > MAX_ROSTER_WORKSPACE_RECORDS || proposals.size > MAX_ROSTER_WORKSPACE_RECORDS ||
        decisions.size > MAX_ROSTER_WORKSPACE_RECORDS) {
      throw new HttpsError("resource-exhausted", "The roster workspace is too large for this reviewed read surface.");
    }
    const activeRegistrations = registrations.docs.filter((entry) => entry.get("status") === "active");
    for (const registration of activeRegistrations) {
      await requireRosterIdentity(transaction, db, authority, workflow, registration);
    }
    return {
      rosterVersion,
      registrations: activeRegistrations.map((entry) => ({
        registrationId: entry.id,
        playerId: entry.get("playerId"),
        displayName: entry.get("displayName"),
        teamId,
        seasonId,
        jerseyNumber: entry.get("jerseyNumber"),
        ...(typeof entry.get("position") === "string" ? {position: entry.get("position")} : {}),
        status: "active",
      })),
      proposals: proposals.docs.map((entry) => {
        const proposal = entry.data();
        const decision = decisionsByProposal.get(entry.id);
        return {
          proposalId: entry.id,
          kind: proposal.kind,
          status: decision?.decision === "approve" ? "approved" : decision?.decision === "reject" ? "rejected" : "pending",
          teamId,
          seasonId,
          before: proposal.before ?? null,
          after: proposal.after ?? null,
          reason: proposal.reason,
          requestedByName: proposal.requestedByName,
          requestedAt: proposal.requestedAt instanceof Timestamp ? proposal.requestedAt.toDate().toISOString() : null,
          reviewNote: decision?.note ?? null,
        };
      }),
    };
  });
}

export async function submitRosterChangeHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "teamId", "seasonId", "expectedRosterVersion", "kind", "requestedOutcome", "reason"],
    ["playerId", "registrationId", "displayName", "jerseyNumber", "position"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const teamId = id(data.teamId, "teamId");
  const seasonId = id(data.seasonId, "seasonId");
  const expectedRosterVersion = counter(data.expectedRosterVersion, "expectedRosterVersion");
  if (data.kind !== "addPlayer" && data.kind !== "updatePlayer" && data.kind !== "removePlayer") {
    throw new HttpsError("invalid-argument", "kind is invalid.");
  }
  const kind = data.kind;
  if (data.requestedOutcome !== "apply" && data.requestedOutcome !== "propose") {
    throw new HttpsError("invalid-argument", "requestedOutcome is invalid.");
  }
  const reason = text(data.reason, "reason", 500)!;
  const after = requestRosterFacts(data, kind);
  if (kind === "addPlayer" && (data.playerId !== undefined || data.registrationId !== undefined)) {
    throw new HttpsError("invalid-argument", "New identities are issued by the server.");
  }
  if (kind === "removePlayer" && [data.displayName, data.jerseyNumber, data.position].some((value) => value !== undefined)) {
    throw new HttpsError("invalid-argument", "Remove requests cannot replace player facts.");
  }
  const semanticRequest = {
    schemaVersion: SCHEMA_VERSION,
    operationId,
    teamId,
    seasonId,
    expectedRosterVersion,
    kind,
    requestedOutcome: data.requestedOutcome,
    reason,
    after: after === null ? null : {
      playerId: after.playerId,
      registrationId: after.registrationId,
      displayName: after.displayName,
      jerseyNumber: after.jerseyNumber,
      position: after.position,
    },
    requestedPlayerId: kind === "addPlayer" ? null : id(data.playerId, "playerId"),
    requestedRegistrationId: kind === "addPlayer" ? null : id(data.registrationId, "registrationId"),
  };
  const fingerprint = hash(semanticRequest);
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "roster.submit", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const [control, team] = await Promise.all([
      transaction.get(workflowRef(db, authority.associationId)),
      requireTeamScope(transaction, db, authority, teamId, seasonId),
    ]);
    const workflow = requireWorkflowReady(control, authority.associationId, "rosters");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    const rosterAuthority = await requireRosterAuthority(transaction, db, authority, workflow, team, teamId, seasonId);
    const receiptRef = operationReceiptRef(db, actor.uid, "roster.submit", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "roster.submit", operationId,
    });
    if (replay) return replay;
    const refs = rosterRefs(db, authority.associationId, workflow.competitionId, rosterAuthority.teamEntryId, seasonId);
    const head = await transaction.get(refs.head);
    const currentVersion = head.exists ? counter(head.get("rosterVersion"), "stored rosterVersion") : 0;
    if (currentVersion !== expectedRosterVersion) throw new HttpsError("aborted", "The roster changed. Reload it before trying again.");

    let before: RosterFacts | null = null;
    if (kind !== "addPlayer") {
      const registrationId = id(data.registrationId, "registrationId");
      const registration = await transaction.get(refs.registrations.doc(registrationId));
      if (!registration.exists || registration.get("teamId") !== teamId || registration.get("seasonId") !== seasonId ||
          registration.get("playerId") !== id(data.playerId, "playerId") || registration.get("status") !== "active") {
        throw new HttpsError("failed-precondition", "The roster registration is not active in this workspace.");
      }
      before = storedRosterFacts(registration.data()!, registration.id);
      await requireRosterIdentity(transaction, db, authority, workflow, registration);
    }
    const normalizedAfter = after === null ? null : {...after, playerId: before?.playerId ?? null, registrationId: before?.registrationId ?? null};
    const manager = rosterAuthority.manager;
    if (!manager) {
      const proposalId = newOpaque("proposal");
      const requestedBy = await transaction.get(db.doc(`users/${actor.uid}`));
      const result = {operationId, proposalId, status: "pending", rosterVersion: currentVersion};
      transaction.create(refs.proposals.doc(proposalId), {
        schemaVersion: SCHEMA_VERSION,
        proposalId,
        associationId: authority.associationId,
        competitionId: workflow.competitionId,
        teamId,
        teamEntryId: rosterAuthority.teamEntryId,
        divisionId: id(team.get("divisionId"), "divisionId"),
        seasonId,
        kind,
        status: "pending",
        before,
        after: normalizedAfter,
        reason,
        requestedBy: actor.uid,
        requestedByName: typeof requestedBy.get("displayName") === "string" ? requestedBy.get("displayName") : "Team Representative",
        requestedAt: FieldValue.serverTimestamp(),
        expectedRosterVersion,
        reviewNote: null,
      });
      saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "roster.submit", operationId, requestFingerprint: fingerprint, result});
      return result;
    }
    const applied = await applyRosterChange({
      transaction, db, authority, actorId: actor.uid, teamId, seasonId, kind,
      before, after: normalizedAfter, reason, expectedRosterVersion, operationId,
      workflow, teamEntryId: rosterAuthority.teamEntryId,
      divisionId: id(team.get("divisionId"), "divisionId"),
    });
    const result = {operationId, status: "approved", ...applied};
    saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "roster.submit", operationId, requestFingerprint: fingerprint, result});
    return result;
  });
}

export async function reviewRosterProposalHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "proposalId", "teamId", "seasonId", "expectedRosterVersion", "decision"], ["note"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const proposalId = id(data.proposalId, "proposalId");
  const teamId = id(data.teamId, "teamId");
  const seasonId = id(data.seasonId, "seasonId");
  const expectedRosterVersion = counter(data.expectedRosterVersion, "expectedRosterVersion");
  if (data.decision !== "approve" && data.decision !== "reject") throw new HttpsError("invalid-argument", "decision is invalid.");
  const note = text(data.note, "note", 500, true);
  if (data.decision === "reject" && note === null) throw new HttpsError("invalid-argument", "A rejection note is required.");
  const fingerprint = hash({
    schemaVersion: SCHEMA_VERSION,
    operationId,
    proposalId,
    teamId,
    seasonId,
    expectedRosterVersion,
    decision: data.decision,
    note,
  });
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "roster.review", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const [control, team] = await Promise.all([
      transaction.get(workflowRef(db, authority.associationId)),
      requireTeamScope(transaction, db, authority, teamId, seasonId),
    ]);
    const workflow = requireWorkflowReady(control, authority.associationId, "rosters");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    const rosterAuthority = await requireRosterAuthority(transaction, db, authority, workflow, team, teamId, seasonId);
    if (!rosterAuthority.manager) throw new HttpsError("permission-denied", "Roster-management authority is required.");
    const receiptRef = operationReceiptRef(db, actor.uid, "roster.review", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "roster.review", operationId,
    });
    if (replay) return replay;
    const refs = rosterRefs(db, authority.associationId, workflow.competitionId, rosterAuthority.teamEntryId, seasonId);
    const proposalRef = refs.proposals.doc(proposalId);
    const decisionRef = refs.decisions.doc(proposalId);
    const [proposal, decision, head] = await Promise.all([
      transaction.get(proposalRef), transaction.get(decisionRef), transaction.get(refs.head),
    ]);
    if (!proposal.exists || proposal.get("schemaVersion") !== SCHEMA_VERSION ||
        proposal.get("associationId") !== authority.associationId || proposal.get("competitionId") !== workflow.competitionId ||
        proposal.get("teamId") !== teamId || proposal.get("teamEntryId") !== rosterAuthority.teamEntryId ||
        proposal.get("divisionId") !== team.get("divisionId") || proposal.get("seasonId") !== seasonId) {
      throw new HttpsError("not-found", "Roster proposal not found.");
    }
    if (proposal.get("status") !== "pending" || decision.exists) throw new HttpsError("failed-precondition", "This roster proposal has already been decided.");
    const currentVersion = head.exists ? counter(head.get("rosterVersion"), "stored rosterVersion") : 0;
    if (currentVersion !== expectedRosterVersion || proposal.get("expectedRosterVersion") !== expectedRosterVersion) {
      throw new HttpsError("aborted", "The roster changed. Reload before reviewing this proposal.");
    }
    let result: Json;
    if (data.decision === "reject") {
      result = {operationId, proposalId, status: "rejected", rosterVersion: currentVersion};
    } else {
      const kind = proposal.get("kind") as RosterKind;
      if (!(["addPlayer", "updatePlayer", "removePlayer"] as string[]).includes(kind)) throw new HttpsError("failed-precondition", "The proposal is malformed.");
      const proposalBefore = immutableRosterFacts(proposal.get("before") ?? null, "proposal.before");
      const proposalAfter = immutableRosterFacts(proposal.get("after") ?? null, "proposal.after");
      const validFactShape = kind === "addPlayer" ? proposalBefore === null && proposalAfter?.playerId === null && proposalAfter.registrationId === null :
        kind === "removePlayer" ? proposalBefore !== null && proposalAfter === null :
          proposalBefore !== null && proposalAfter !== null && proposalBefore.playerId === proposalAfter.playerId &&
            proposalBefore.registrationId === proposalAfter.registrationId;
      if (!validFactShape) throw new HttpsError("failed-precondition", "The roster proposal facts are malformed.");
      const applied = await applyRosterChange({
        transaction, db, authority, actorId: actor.uid, teamId, seasonId, kind,
        before: proposalBefore,
        after: proposalAfter,
        reason: text(proposal.get("reason"), "proposal.reason", 500)!, expectedRosterVersion, operationId, workflow,
        teamEntryId: rosterAuthority.teamEntryId,
        divisionId: id(team.get("divisionId"), "divisionId"),
      });
      result = {operationId, proposalId, status: "approved", ...applied};
    }
    transaction.create(decisionRef, {
      schemaVersion: SCHEMA_VERSION, associationId: authority.associationId, proposalId,
      competitionId: workflow.competitionId,
      teamId, seasonId, divisionId: id(team.get("divisionId"), "divisionId"),
      before: proposal.get("before") ?? null, after: proposal.get("after") ?? null,
      reason: proposal.get("reason"), decision: data.decision, note, actorId: actor.uid,
      reviewOperationId: operationId,
      createdAt: FieldValue.serverTimestamp(),
    });
    saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "roster.review", operationId, requestFingerprint: fingerprint, result});
    return result;
  });
}

function divisionReferenceQueries(
  db: Firestore,
  associationId: string,
  divisionId: string,
  legacyDivisionName: string | null,
): Array<{kind: string; query: Query}> {
  const root = `associations/${associationId}`;
  const limited = (query: Query) => query.limit(MAX_DIVISION_REFERENCES + 1);
  return [
    {kind: "userAssignment", query: limited(db.collection("users").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "membershipAssignment", query: limited(db.collection("memberships").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "inviteAssignment", query: limited(db.collection("inviteCodes").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "boardPost", query: limited(db.collection(`${root}/posts`).where("divisionFilter", "==", divisionId))},
    ...(legacyDivisionName !== null && legacyDivisionName !== divisionId ? [{
      kind: "boardPostLegacyName",
      query: limited(db.collection(`${root}/posts`).where("divisionFilter", "==", legacyDivisionName)),
    }] : []),
    {kind: "legacyTeam", query: limited(db.collection(`${root}/teams`).where("divisionId", "==", divisionId))},
    {kind: "legacyEvent", query: limited(db.collection(`${root}/events`).where("divisionId", "==", divisionId))},
    {kind: "legacyGameStats", query: limited(db.collection(`${root}/gameStats`).where("divisionId", "==", divisionId))},
    {kind: "legacyPlayerSeasonStats", query: limited(db.collection(`${root}/playerSeasonStats`).where("divisionId", "==", divisionId))},
    {kind: "legacyTeamSeasonStats", query: limited(db.collection(`${root}/teamSeasonStats`).where("divisionId", "==", divisionId))},
    {kind: "legacyStandings", query: limited(db.collection(`${root}/standings`).where("divisionId", "==", divisionId))},
    {kind: "legacyLeaderboard", query: limited(db.collection(`${root}/leaderboard`).where("divisionId", "==", divisionId))},
    {kind: "canonicalTeamEntry", query: limited(db.collectionGroup("teamEntries").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "canonicalGame", query: limited(db.collectionGroup("games").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "scheduleRevision", query: limited(db.collectionGroup("scheduleRevisions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "gameAssignment", query: limited(db.collectionGroup("assignments").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterHead", query: limited(db.collectionGroup("rosterHeads").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterMembership", query: limited(db.collectionGroup("rosterMemberships").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterMembershipVersion", query: limited(db.collectionGroup("versions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterAssertion", query: limited(db.collectionGroup("rosterAssertions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterAssertionDecision", query: limited(db.collectionGroup("rosterAssertionDecisions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "rosterSnapshot", query: limited(db.collectionGroup("rosterSnapshots").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "participantSnapshot", query: limited(db.collectionGroup("participantSnapshots").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "journalOperation", query: limited(db.collectionGroup("operations").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "operationReceipt", query: limited(db.collectionGroup("operationReceipts").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "statRevision", query: limited(db.collectionGroup("statRevisions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "officialResult", query: limited(db.collectionGroup("officialResults").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "review", query: limited(db.collectionGroup("reviews").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "certificate", query: limited(db.collectionGroup("certificates").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "certificateAction", query: limited(db.collectionGroup("certificateActions").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "correction", query: limited(db.collectionGroup("corrections").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "aggregateRelease", query: limited(db.collectionGroup("aggregateReleases").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "publicSelection", query: limited(db.collectionGroup("publicSelections").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
    {kind: "projectionBuild", query: limited(db.collectionGroup("projectionBuilds").where("associationId", "==", associationId).where("divisionId", "==", divisionId))},
  ];
}

function divisionDeletionAuthorityBinding(
  authority: Authority,
  workflow: WorkflowControl,
  divisionId: string,
): string {
  return hash({
    actorId: authority.uid,
    associationId: authority.associationId,
    authorizationSchemaVersion: authority.schemaVersion,
    accountGenerationV2: authority.accountGenerationV2,
    accountLifecycleEpochV2: authority.accountLifecycleEpochV2,
    role: authority.role,
    capabilities: [...authority.capabilities].sort(),
    teamId: authority.teamId,
    competitionId: workflow.competitionId,
    seasonId: workflow.seasonId,
    phaseId: workflow.phaseId,
    authorityMode: workflow.authorityMode,
    custodyPolicyVersionV2: workflow.custodyPolicyVersionV2,
    privacyEpochV2: workflow.privacyEpochV2,
    divisionId,
  });
}

interface DivisionDeletionTestHooks {
  afterInventory?: () => Promise<void>;
}

function referenceName(data: DocumentData): string | null {
  for (const key of ["displayName", "name", "title"]) {
    if (typeof data[key] === "string" && data[key].trim().length > 0) return data[key].trim();
  }
  return null;
}

async function executeDeleteDivisionIfUnreferenced(
  request: CallableRequest<unknown>,
  testHooks: DivisionDeletionTestHooks,
) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "divisionId", "expectedDivisionVersion"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const divisionId = id(data.divisionId, "divisionId");
  const expectedDivisionVersion = counter(data.expectedDivisionVersion, "expectedDivisionVersion");
  const fingerprint = hash({schemaVersion: SCHEMA_VERSION, operationId, divisionId, expectedDivisionVersion});
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "division.delete", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  const prepared = await db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const control = await transaction.get(workflowRef(db, authority.associationId));
    const workflow = requireWorkflowReady(control, authority.associationId, "divisionDeletion");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    if (workflow.authorityMode !== "legacyV1" || authority.schemaVersion !== 1) {
      throw new HttpsError("failed-precondition", "Division deletion remains closed until a v2 division-management capability is adopted.");
    }
    requireCapability(authority, capabilities.associationManage);
    const receiptRef = operationReceiptRef(db, actor.uid, "division.delete", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "division.delete", operationId,
    });
    if (replay) return {replay};
    const operationRef = db.doc(
      `associations/${authority.associationId}/divisionDeletionOperations/${hash({actorId: actor.uid, operationId})}`,
    );
    const divisionRef = db.doc(`associations/${authority.associationId}/divisions/${divisionId}`);
    const [division, operation] = await Promise.all([transaction.get(divisionRef), transaction.get(operationRef)]);
    if (!division.exists) throw new HttpsError("not-found", "Division not found.");
    const version = counter(division.get("version") ?? 0, "division version");
    if (version !== expectedDivisionVersion) throw new HttpsError("aborted", "The division changed. Reload it before deleting.");
    if (operation.exists && (operation.get("requestFingerprint") !== fingerprint ||
        !["guarding", "inventoryFailed"].includes(operation.get("status")))) {
      throw new HttpsError("already-exists", "This deletion operation cannot be resumed with different state.");
    }
    const pending = division.get("deletionPending");
    const now = Timestamp.now();
    const expired = pending?.leaseExpiresAt instanceof Timestamp && pending.leaseExpiresAt.toMillis() <= now.toMillis();
    if (pending && !expired && (pending.operationId !== operationId || pending.actorId !== actor.uid)) {
      throw new HttpsError("aborted", "Another division operation is in progress.");
    }
    const leaseExpiresAt = Timestamp.fromMillis(now.toMillis() + DIVISION_DELETE_LEASE_MS);
    transaction.update(divisionRef, {
      deletionPending: {schemaVersion: SCHEMA_VERSION, operationId, actorId: actor.uid, expectedDivisionVersion, leaseExpiresAt},
      deletionPendingAt: FieldValue.serverTimestamp(),
    });
    transaction.set(operationRef, {
      schemaVersion: SCHEMA_VERSION,
      associationId: authority.associationId,
      actorId: actor.uid,
      operationId,
      divisionId,
      expectedDivisionVersion,
      requestFingerprint: fingerprint,
      status: "guarding",
      attempt: operation.exists && safeStoredCounter(operation.get("attempt")) ? operation.get("attempt") + 1 : 1,
      leaseExpiresAt,
      updatedAt: FieldValue.serverTimestamp(),
      ...(operation.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
    }, {merge: operation.exists});
    return {
      authority,
      authorityBinding: divisionDeletionAuthorityBinding(authority, workflow, divisionId),
      legacyDivisionName: typeof division.get("name") === "string" && division.get("name").trim().length > 0 ?
        division.get("name").trim() as string : null,
      divisionRef,
      receiptRef,
      operationRef,
    };
  });
  if ("replay" in prepared) return prepared.replay;
  const queries = divisionReferenceQueries(
    db,
    prepared.authority.associationId,
    divisionId,
    prepared.legacyDivisionName,
  );
  let snapshots: Awaited<ReturnType<Query["get"]>>[];
  try {
    snapshots = await Promise.all(queries.map((entry) => entry.query.get()));
    const total = snapshots.reduce((sum, snapshot) => sum + snapshot.size, 0);
    if (total > MAX_DIVISION_REFERENCES || snapshots.some((snapshot) => snapshot.size > MAX_DIVISION_REFERENCES)) {
      throw new HttpsError("resource-exhausted", "The complete division reference inventory exceeds the reviewed bound.");
    }
  } catch (error) {
    await db.runTransaction(async (transaction) => {
      const [division, operation] = await Promise.all([
        transaction.get(prepared.divisionRef), transaction.get(prepared.operationRef),
      ]);
      const pending = division.get("deletionPending");
      if (division.exists && pending?.operationId === operationId && pending?.actorId === actor.uid) {
        transaction.update(prepared.divisionRef, {
          deletionPending: FieldValue.delete(), deletionPendingAt: FieldValue.delete(),
        });
      }
      if (operation.exists && operation.get("requestFingerprint") === fingerprint) {
        transaction.update(prepared.operationRef, {
          status: "inventoryFailed",
          failureCode: error instanceof HttpsError && error.code === "resource-exhausted" ? "inventory-too-large" : "inventory-unavailable",
          leaseExpiresAt: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("unavailable", "The division inventory could not be completed; the guard was safely released for retry.");
  }

  await testHooks.afterInventory?.();

  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const control = await transaction.get(workflowRef(db, authority.associationId));
    const workflow = requireWorkflowReady(control, authority.associationId, "divisionDeletion");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    if (divisionDeletionAuthorityBinding(authority, workflow, divisionId) !== prepared.authorityBinding) {
      throw new HttpsError("permission-denied", "The division deletion authority or scope changed during inventory.");
    }
    if (workflow.authorityMode !== "legacyV1" || authority.schemaVersion !== 1) {
      throw new HttpsError("failed-precondition", "Division deletion remains closed until a v2 division-management capability is adopted.");
    }
    requireCapability(authority, capabilities.associationManage);
    const [receipt, division, operation] = await Promise.all([
      transaction.get(prepared.receiptRef), transaction.get(prepared.divisionRef), transaction.get(prepared.operationRef),
    ]);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "division.delete", operationId,
    });
    if (replay) return replay;
    if (!division.exists || !operation.exists || operation.get("status") !== "guarding" ||
        operation.get("requestFingerprint") !== fingerprint) {
      throw new HttpsError("aborted", "The division deletion recovery state changed.");
    }
    if (division.get("version") !== expectedDivisionVersion) {
      throw new HttpsError("aborted", "The division changed during reference inventory.");
    }
    const pending = division.get("deletionPending");
    if (!pending || pending.operationId !== operationId || pending.actorId !== actor.uid ||
        pending.expectedDivisionVersion !== expectedDivisionVersion) {
      throw new HttpsError("aborted", "The division deletion guard changed.");
    }
    const references = snapshots.flatMap((snapshot, index) => snapshot.docs.map((entry) => ({
      kind: queries[index].kind,
      id: entry.id,
      displayName: referenceName(entry.data()),
    })));
    let result: Json;
    if (references.length > 0) {
      result = {operationId, status: "blocked", divisionVersion: expectedDivisionVersion, references};
      transaction.update(prepared.divisionRef, {deletionPending: FieldValue.delete(), deletionPendingAt: FieldValue.delete()});
      transaction.update(prepared.operationRef, {status: "blocked", references, leaseExpiresAt: FieldValue.delete(), completedAt: FieldValue.serverTimestamp()});
    } else {
      result = {operationId, status: "deleted", divisionVersion: expectedDivisionVersion};
      transaction.delete(prepared.divisionRef);
      transaction.update(prepared.operationRef, {status: "deleted", leaseExpiresAt: FieldValue.delete(), completedAt: FieldValue.serverTimestamp()});
    }
    saveReceipt(transaction, prepared.receiptRef, {
      actorId: actor.uid, associationId: prepared.authority.associationId, operation: "division.delete",
      operationId, requestFingerprint: fingerprint, result,
    });
    return result;
  });
}

export async function deleteDivisionIfUnreferencedHandler(request: CallableRequest<unknown>) {
  return executeDeleteDivisionIfUnreferenced(request, {});
}

export async function deleteDivisionIfUnreferencedHandlerForTest(
  request: CallableRequest<unknown>,
  testHooks: DivisionDeletionTestHooks,
) {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new HttpsError("failed-precondition", "Division deletion test hooks require the Firestore emulator.");
  }
  return executeDeleteDivisionIfUnreferenced(request, testHooks);
}

function parseSchedule(data: Json): ScheduleInput {
  const startTime = isoTimestamp(data.startTimeUtc, "startTimeUtc");
  const endTime = isoTimestamp(data.endTimeUtc, "endTimeUtc");
  const duration = endTime.toMillis() - startTime.toMillis();
  if (duration <= 0 || duration > MAX_GAME_DURATION_MS) throw new HttpsError("invalid-argument", "The game interval is invalid.");
  const homeTeamId = id(data.homeTeamId, "homeTeamId");
  const awayTeamId = id(data.awayTeamId, "awayTeamId");
  if (homeTeamId === awayTeamId) throw new HttpsError("invalid-argument", "Home and away teams must differ.");
  return {
    seasonId: id(data.seasonId, "seasonId"),
    divisionId: id(data.divisionId, "divisionId"),
    homeTeamId,
    awayTeamId,
    startTime,
    endTime,
    location: text(data.location, "location", 200, true),
  };
}

function utcDays(start: Timestamp, end: Timestamp): string[] {
  const result: string[] = [];
  const cursor = new Date(start.toMillis());
  cursor.setUTCHours(0, 0, 0, 0);
  const last = new Date(end.toMillis() - 1);
  last.setUTCHours(0, 0, 0, 0);
  while (cursor.getTime() <= last.getTime()) {
    result.push(cursor.toISOString().slice(0, 10).replace(/-/g, ""));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return result;
}

function scheduleLockRefs(
  db: Firestore,
  associationId: string,
  input: ScheduleInput,
  teamEntryIds: [string, string],
): DocumentReference[] {
  const days = utcDays(input.startTime, input.endTime);
  const teams = [...teamEntryIds].sort();
  const dayLocks = teams.flatMap((teamEntryId) =>
    days.map((day) => db.doc(`associations/${associationId}/scheduleLocks/${input.seasonId}__${teamEntryId}__${day}`)));
  const pairStart = hash({seasonId: input.seasonId, teams, startTime: input.startTime.toDate().toISOString()});
  return [...dayLocks, db.doc(`associations/${associationId}/schedulePairStarts/${pairStart}`)];
}

async function validateScheduleScope(transaction: Transaction, db: Firestore, authority: Authority, input: ScheduleInput): Promise<{
  competitionId: string;
  phaseId: string;
  homeName: string;
  awayName: string;
  homeTeamEntryId: string;
  awayTeamEntryId: string;
}> {
  const associationRef = db.doc(`associations/${authority.associationId}`);
  const controlRef = workflowRef(db, authority.associationId);
  const divisionRef = db.doc(`associations/${authority.associationId}/divisions/${input.divisionId}`);
  const seasonRef = db.doc(`associations/${authority.associationId}/seasons/${input.seasonId}`);
  const homeRef = db.doc(`associations/${authority.associationId}/teams/${input.homeTeamId}`);
  const awayRef = db.doc(`associations/${authority.associationId}/teams/${input.awayTeamId}`);
  const [association, control, division, season, home, away] = await Promise.all([
    transaction.get(associationRef), transaction.get(controlRef), transaction.get(divisionRef), transaction.get(seasonRef),
    transaction.get(homeRef), transaction.get(awayRef),
  ]);
  const workflow = requireWorkflowReady(control, authority.associationId, "scheduling");
  const competitionId = workflow.competitionId;
  if (workflow.seasonId !== input.seasonId || association.get("currentSeasonId") !== input.seasonId) {
    throw new HttpsError("failed-precondition", "The requested season is not the active competition season.");
  }
  if (!season.exists || season.get("status") === "archived" || season.get("active") === false) {
    throw new HttpsError("failed-precondition", "The season is not active.");
  }
  if (!division.exists || division.get("status") === "archived" || division.get("deletionPending")) {
    throw new HttpsError("failed-precondition", "The division is not active for scheduling.");
  }
  for (const team of [home, away]) {
    if (!team.exists || team.get("seasonId") !== input.seasonId || team.get("divisionId") !== input.divisionId || team.get("status") === "archived") {
      throw new HttpsError("failed-precondition", "Both teams must be active in the requested season and division.");
    }
  }
  const homeCanonical = await requireCanonicalTeamEntry(transaction, db, authority, workflow, home, input.homeTeamId, input.seasonId);
  const awayCanonical = await requireCanonicalTeamEntry(transaction, db, authority, workflow, away, input.awayTeamId, input.seasonId);
  if (homeCanonical.divisionId !== input.divisionId || awayCanonical.divisionId !== input.divisionId) {
    throw new HttpsError("failed-precondition", "Canonical team entries do not match the requested division.");
  }
  return {
    competitionId,
    phaseId: workflow.phaseId,
    homeName: typeof home.get("name") === "string" ? home.get("name") : input.homeTeamId,
    awayName: typeof away.get("name") === "string" ? away.get("name") : input.awayTeamId,
    homeTeamEntryId: homeCanonical.teamEntryId,
    awayTeamEntryId: awayCanonical.teamEntryId,
  };
}

async function conflictingEvents(transaction: Transaction, db: Firestore, associationId: string, input: ScheduleInput, excludingEventId?: string): Promise<DocumentSnapshot[]> {
  const events = db.collection(`associations/${associationId}/events`);
  const [home, away] = await Promise.all([
    transaction.get(events.where("teamIds", "array-contains", input.homeTeamId)),
    transaction.get(events.where("teamIds", "array-contains", input.awayTeamId)),
  ]);
  const unique = new Map<string, DocumentSnapshot>();
  for (const entry of [...home.docs, ...away.docs]) unique.set(entry.id, entry);
  return [...unique.values()].filter((entry) => {
    if (entry.id === excludingEventId || entry.get("status") === "cancelled" || entry.get("type") !== "game") return false;
    const start = entry.get("startTime");
    const end = entry.get("endTime");
    if (!(start instanceof Timestamp) || !(end instanceof Timestamp)) return true;
    const teams = Array.isArray(entry.get("teamIds")) ? entry.get("teamIds") as unknown[] : [];
    const samePair = teams.length === 2 && teams.includes(input.homeTeamId) && teams.includes(input.awayTeamId);
    return (samePair && start.toMillis() === input.startTime.toMillis()) ||
      (input.startTime.toMillis() < end.toMillis() && input.endTime.toMillis() > start.toMillis());
  });
}

function scheduleRevisionData(input: ScheduleInput, audit: ScheduleAuditState, scope: {
  associationId: string;
  competitionId: string;
  gameId: string;
  versionId: string;
  predecessorVersionId: string | null;
  reasonCode: string;
  homeTeamEntryId: string;
  awayTeamEntryId: string;
  actorId: string;
}) {
  return {
    dataSchemaVersion: 2,
    associationId: scope.associationId,
    competitionId: scope.competitionId,
    seasonId: input.seasonId,
    divisionId: input.divisionId,
    gameId: scope.gameId,
    versionId: scope.versionId,
    predecessorVersionId: scope.predecessorVersionId,
    scheduledStart: input.startTime,
    scheduledEnd: input.endTime,
    timezone: LEAGUE_TIMEZONE,
    venueId: input.location,
    courtId: null,
    homeTeamEntryId: scope.homeTeamEntryId,
    awayTeamEntryId: scope.awayTeamEntryId,
    reasonCode: scope.reasonCode,
    actorId: scope.actorId,
    title: audit.title,
    description: audit.description,
    location: input.location,
    status: audit.status,
    cancellationReason: audit.cancellationReason,
    recordedAt: FieldValue.serverTimestamp(),
  };
}

type ScheduledGameScope = Awaited<ReturnType<typeof validateScheduleScope>>;

interface PreparedScheduledGame {
  scope: ScheduledGameScope;
  locks: DocumentReference[];
}

async function prepareScheduledGame(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  input: ScheduleInput,
): Promise<PreparedScheduledGame> {
  const scope = await validateScheduleScope(transaction, db, authority, input);
  const locks = scheduleLockRefs(db, authority.associationId, input, [scope.homeTeamEntryId, scope.awayTeamEntryId]);
  await transaction.getAll(...locks);
  const conflicts = await conflictingEvents(transaction, db, authority.associationId, input);
  if (conflicts.length > 0) throw new HttpsError("already-exists", "A duplicate or overlapping game already exists.");
  return {scope, locks};
}

function writeScheduledGame(
  transaction: Transaction,
  db: Firestore,
  authority: Authority,
  actorId: string,
  input: ScheduleInput,
  eventId: string,
  prepared: PreparedScheduledGame,
): number {
  const {scope, locks} = prepared;
  const eventRef = db.doc(`associations/${authority.associationId}/events/${eventId}`);
  const gamePath = `associations/${authority.associationId}/competitions/${scope.competitionId}/seasons/${input.seasonId}/games/${eventId}`;
  const gameRef = db.doc(gamePath);
  const versionId = "schedule_1";
  transaction.create(eventRef, {
    associationId: authority.associationId,
    competitionId: scope.competitionId,
    seasonId: input.seasonId,
    divisionId: input.divisionId,
    phaseId: scope.phaseId,
    title: `${scope.homeName} vs ${scope.awayName}`,
    description: null,
    type: "game",
    startTime: input.startTime,
    endTime: input.endTime,
    location: input.location,
    teamIds: [input.homeTeamId, input.awayTeamId],
    homeTeamId: input.homeTeamId,
    awayTeamId: input.awayTeamId,
    homeTeamEntryId: scope.homeTeamEntryId,
    awayTeamEntryId: scope.awayTeamEntryId,
    createdBy: actorId,
    createdAt: FieldValue.serverTimestamp(),
    status: "scheduled",
    statsStatus: "pending",
    scheduleVersion: 1,
    scheduleRevisionId: versionId,
    timezone: LEAGUE_TIMEZONE,
  });
  transaction.create(gameRef, {
    dataSchemaVersion: 2, associationId: authority.associationId, competitionId: scope.competitionId,
    seasonId: input.seasonId, divisionId: input.divisionId, phaseId: scope.phaseId,
    gameId: eventId, homeTeamEntryId: scope.homeTeamEntryId, awayTeamEntryId: scope.awayTeamEntryId,
    playState: "scheduled", reviewState: "none", publicationState: "unpublished",
    controlVersion: 1, scheduleVersion: 1, scheduleRevisionId: versionId,
  });
  transaction.create(gameRef.collection("scheduleRevisions").doc(versionId), scheduleRevisionData(input, {
    title: `${scope.homeName} vs ${scope.awayName}`,
    description: null,
    status: "scheduled",
    cancellationReason: null,
  }, {
    associationId: authority.associationId, competitionId: scope.competitionId, gameId: eventId,
    versionId, predecessorVersionId: null, reasonCode: "created",
    homeTeamEntryId: scope.homeTeamEntryId, awayTeamEntryId: scope.awayTeamEntryId,
    actorId,
  }));
  for (const lock of locks) transaction.set(lock, {version: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
  return 1;
}

async function createScheduledGame(transaction: Transaction, db: Firestore, authority: Authority, actorId: string, input: ScheduleInput, eventId: string): Promise<number> {
  const prepared = await prepareScheduledGame(transaction, db, authority, input);
  return writeScheduledGame(transaction, db, authority, actorId, input, eventId, prepared);
}

export async function scheduleGameHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "seasonId", "divisionId", "homeTeamId", "awayTeamId", "startTimeUtc", "endTimeUtc"], ["location"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const input = parseSchedule(data);
  const fingerprint = hash({schemaVersion: SCHEMA_VERSION, operationId, ...scheduleSemantic(input)});
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "schedule.create", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const control = await transaction.get(workflowRef(db, authority.associationId));
    const workflow = requireWorkflowReady(control, authority.associationId, "scheduling");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    await requireSchedulingAuthority(transaction, db, authority, workflow, input.seasonId, input.divisionId);
    const receiptRef = operationReceiptRef(db, actor.uid, "schedule.create", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "schedule.create", operationId,
    });
    if (replay) return replay;
    const eventId = `game_${hash({associationId: authority.associationId, actorId: actor.uid, operationId}).slice(0, 40)}`;
    const scheduleVersion = await createScheduledGame(transaction, db, authority, actor.uid, input, eventId);
    const result = {operationId, status: "created", eventId, scheduleVersion};
    saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "schedule.create", operationId, requestFingerprint: fingerprint, result});
    return result;
  });
}

export async function createScheduleBatchHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "games"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  if (!Array.isArray(data.games) || data.games.length === 0 || data.games.length > MAX_BATCH_GAMES) {
    throw new HttpsError("invalid-argument", `games must contain 1-${MAX_BATCH_GAMES} entries.`);
  }
  const parsed = data.games.map((raw, index) => {
    const game = object(raw);
    exactKeys(game, ["itemKey", "seasonId", "divisionId", "homeTeamId", "awayTeamId", "startTimeUtc", "endTimeUtc"], ["location"]);
    return {itemKey: id(game.itemKey, `games[${index}].itemKey`), input: parseSchedule(game)};
  });
  if (new Set(parsed.map((entry) => entry.itemKey)).size !== parsed.length) throw new HttpsError("invalid-argument", "Batch item keys must be unique.");
  for (let first = 0; first < parsed.length; first++) {
    for (let second = first + 1; second < parsed.length; second++) {
      const a = parsed[first].input;
      const b = parsed[second].input;
      const shared = [a.homeTeamId, a.awayTeamId].some((team) => team === b.homeTeamId || team === b.awayTeamId);
      if (shared && a.startTime.toMillis() < b.endTime.toMillis() && a.endTime.toMillis() > b.startTime.toMillis()) {
        throw new HttpsError("already-exists", "Games in this batch overlap for the same team.");
      }
    }
  }
  const fingerprint = hash({
    schemaVersion: SCHEMA_VERSION,
    operationId,
    games: parsed.map((entry) => ({itemKey: entry.itemKey, ...scheduleSemantic(entry.input)})),
  });
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, parsed.length, {
    operation: "schedule.batch", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const control = await transaction.get(workflowRef(db, authority.associationId));
    const workflow = requireWorkflowReady(control, authority.associationId, "scheduling");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    for (const entry of parsed) {
      await requireSchedulingAuthority(transaction, db, authority, workflow, entry.input.seasonId, entry.input.divisionId);
    }
    const receiptRef = operationReceiptRef(db, actor.uid, "schedule.batch", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "schedule.batch", operationId,
    });
    if (replay) return replay;
    const prepared: Array<{entry: typeof parsed[number]; eventId: string; prepared: PreparedScheduledGame}> = [];
    for (const entry of parsed) {
      const eventId = `game_${hash({associationId: authority.associationId, actorId: actor.uid, operationId, itemKey: entry.itemKey}).slice(0, 40)}`;
      prepared.push({entry, eventId, prepared: await prepareScheduledGame(transaction, db, authority, entry.input)});
    }
    const results: Json[] = [];
    for (const plan of prepared) {
      const scheduleVersion = writeScheduledGame(
        transaction,
        db,
        authority,
        actor.uid,
        plan.entry.input,
        plan.eventId,
        plan.prepared,
      );
      results.push({itemKey: plan.entry.itemKey, status: "created", eventId: plan.eventId, scheduleVersion});
    }
    const result = {operationId, status: "created", results};
    saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "schedule.batch", operationId, requestFingerprint: fingerprint, result});
    return result;
  });
}

export async function mutateScheduledGameHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "eventId", "expectedScheduleVersion", "action"],
    ["startTimeUtc", "endTimeUtc", "location", "title", "description", "reason"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const eventId = id(data.eventId, "eventId");
  const expectedScheduleVersion = counter(data.expectedScheduleVersion, "expectedScheduleVersion", false);
  if (data.action !== "edit" && data.action !== "reschedule" && data.action !== "cancel") throw new HttpsError("invalid-argument", "action is invalid.");
  const action = data.action;
  let normalizedTitle: string | null = null;
  let normalizedDescription: string | null = null;
  let normalizedLocation: string | null = null;
  let normalizedReason: string | null = null;
  if (action === "edit") {
    if (data.startTimeUtc !== undefined || data.endTimeUtc !== undefined || data.reason !== undefined ||
        (data.location === undefined && data.title === undefined && data.description === undefined)) {
      throw new HttpsError("invalid-argument", "Edit accepts only changed title, description, or location fields.");
    }
    normalizedTitle = data.title === undefined ? null : text(data.title, "title", 160)!;
    normalizedDescription = data.description === undefined ? null : text(data.description, "description", 2000, true);
    normalizedLocation = data.location === undefined ? null : text(data.location, "location", 200, true);
  } else if (action === "reschedule") {
    if (data.startTimeUtc === undefined || data.endTimeUtc === undefined || data.title !== undefined ||
        data.description !== undefined || data.reason !== undefined) {
      throw new HttpsError("invalid-argument", "Reschedule requires the new interval and optional location only.");
    }
    normalizedLocation = data.location === undefined ? null : text(data.location, "location", 200, true);
  } else if (text(data.reason, "reason", 500, true) === null ||
      data.startTimeUtc !== undefined || data.endTimeUtc !== undefined || data.location !== undefined ||
      data.title !== undefined || data.description !== undefined) {
    throw new HttpsError("invalid-argument", "Cancel requires only a cancellation reason.");
  } else {
    normalizedReason = text(data.reason, "reason", 500)!;
  }
  const semanticMutation: Json = {
    schemaVersion: SCHEMA_VERSION,
    operationId,
    eventId,
    expectedScheduleVersion,
    action,
    titleProvided: data.title !== undefined,
    title: data.title === undefined ? null : normalizedTitle,
    descriptionProvided: data.description !== undefined,
    description: data.description === undefined ? null : normalizedDescription,
    locationProvided: data.location !== undefined,
    location: data.location === undefined ? null : normalizedLocation,
    reason: normalizedReason,
  };
  if (action === "reschedule") {
    semanticMutation.startTimeUtc = isoTimestamp(data.startTimeUtc, "startTimeUtc").toDate().toISOString();
    semanticMutation.endTimeUtc = isoTimestamp(data.endTimeUtc, "endTimeUtc").toDate().toISOString();
  }
  const fingerprint = hash(semanticMutation);
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "schedule.mutate", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;
  return db.runTransaction(async (transaction) => {
    const authority = await authorityInTransaction(transaction, db, actor);
    const control = await transaction.get(workflowRef(db, authority.associationId));
    const workflow = requireWorkflowReady(control, authority.associationId, "scheduling");
    await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
    const eventRef = db.doc(`associations/${authority.associationId}/events/${eventId}`);
    const event = await transaction.get(eventRef);
    if (!event.exists || event.get("type") !== "game") throw new HttpsError("not-found", "Scheduled game not found.");
    if (event.get("competitionId") !== workflow.competitionId || event.get("phaseId") !== workflow.phaseId ||
        event.get("seasonId") !== workflow.seasonId) {
      throw new HttpsError("failed-precondition", "The scheduled game is outside the active league control scope.");
    }
    await requireSchedulingAuthority(
      transaction,
      db,
      authority,
      workflow,
      id(event.get("seasonId"), "stored seasonId"),
      id(event.get("divisionId"), "stored divisionId"),
    );
    const receiptRef = operationReceiptRef(db, actor.uid, "schedule.mutate", operationId);
    const receipt = await transaction.get(receiptRef);
    const replay = receiptReplay(receipt, fingerprint, {
      actorId: actor.uid, associationId: authority.associationId, operation: "schedule.mutate", operationId,
    });
    if (replay) return replay;
    if (event.get("scheduleVersion") !== expectedScheduleVersion) throw new HttpsError("aborted", "The schedule changed. Reload it before trying again.");
    const competitionId = workflow.competitionId;
    const gameRef = db.doc(`associations/${authority.associationId}/competitions/${competitionId}/seasons/${event.get("seasonId")}/games/${eventId}`);
    const [game, approvedStats, statRevisions, rosterSnapshots, participantSnapshots] = await Promise.all([
      transaction.get(gameRef),
      transaction.get(db.doc(`associations/${authority.associationId}/gameStats/${eventId}`)),
      transaction.get(gameRef.collection("statRevisions").limit(1)),
      transaction.get(gameRef.collection("rosterSnapshots").limit(1)),
      transaction.get(gameRef.collection("participantSnapshots").limit(1)),
    ]);
    if (!game.exists) throw new HttpsError("failed-precondition", "The canonical game is missing.");
    if (event.get("status") !== "scheduled" || event.get("statsStatus") !== "pending" ||
        game.get("playState") !== "scheduled" || !["none", "draft"].includes(game.get("reviewState")) ||
        approvedStats.exists || !statRevisions.empty || !rosterSnapshots.empty || !participantSnapshots.empty) {
      throw new HttpsError("failed-precondition", "A started, reviewed, rejected, submitted, final, or snapshotted game cannot be changed.");
    }
    const current: ScheduleInput = {
      seasonId: event.get("seasonId"), divisionId: event.get("divisionId"),
      homeTeamId: event.get("homeTeamId"), awayTeamId: event.get("awayTeamId"),
      startTime: event.get("startTime"), endTime: event.get("endTime"),
      location: typeof event.get("location") === "string" ? event.get("location") : null,
    };
    const next: ScheduleInput = action === "reschedule" ? {
      ...current,
      startTime: isoTimestamp(data.startTimeUtc, "startTimeUtc"),
      endTime: isoTimestamp(data.endTimeUtc, "endTimeUtc"),
      location: data.location === undefined ? current.location : normalizedLocation,
    } : {...current, location: data.location === undefined ? current.location : normalizedLocation};
    const duration = next.endTime.toMillis() - next.startTime.toMillis();
    if (duration <= 0 || duration > MAX_GAME_DURATION_MS) throw new HttpsError("invalid-argument", "The game interval is invalid.");
    let locks: DocumentReference[] = [];
    if (action !== "cancel") {
      await validateScheduleScope(transaction, db, authority, next);
      const canonicalTeams: [string, string] = [
        id(game.get("homeTeamEntryId"), "stored homeTeamEntryId"),
        id(game.get("awayTeamEntryId"), "stored awayTeamEntryId"),
      ];
      locks = [
        ...scheduleLockRefs(db, authority.associationId, current, canonicalTeams),
        ...scheduleLockRefs(db, authority.associationId, next, canonicalTeams),
      ];
      locks = [...new Map(locks.map((entry) => [entry.path, entry])).values()];
      await transaction.getAll(...locks);
      const conflicts = await conflictingEvents(transaction, db, authority.associationId, next, eventId);
      if (conflicts.length > 0) throw new HttpsError("already-exists", "A duplicate or overlapping game already exists.");
    }
    const nextVersion = expectedScheduleVersion + 1;
    const versionId = `schedule_${nextVersion}`;
    const predecessorVersionId = event.get("scheduleRevisionId");
    const eventUpdate: Json = {
      scheduleVersion: nextVersion,
      scheduleRevisionId: versionId,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (action === "reschedule") Object.assign(eventUpdate, {startTime: next.startTime, endTime: next.endTime, location: next.location});
    if (action === "edit") {
      if (data.title !== undefined) eventUpdate.title = normalizedTitle;
      if (data.description !== undefined) eventUpdate.description = normalizedDescription;
      if (data.location !== undefined) eventUpdate.location = next.location;
    }
    if (action === "cancel") Object.assign(eventUpdate, {
      status: "cancelled", cancelledAt: FieldValue.serverTimestamp(), cancelledBy: actor.uid,
      cancellationReason: normalizedReason,
      statsStatus: "cancelled",
    });
    transaction.update(eventRef, eventUpdate);
    transaction.update(gameRef, {
      scheduleVersion: nextVersion, scheduleRevisionId: versionId, controlVersion: FieldValue.increment(1),
      ...(action === "cancel" ? {playState: "cancelled"} : {}),
    });
    const nextAudit: ScheduleAuditState = {
      title: (data.title === undefined ? event.get("title") : normalizedTitle) as string,
      description: data.description === undefined ?
        (typeof event.get("description") === "string" ? event.get("description") : null) : normalizedDescription,
      status: action === "cancel" ? "cancelled" : "scheduled",
      cancellationReason: action === "cancel" ? normalizedReason : null,
    };
    transaction.create(gameRef.collection("scheduleRevisions").doc(versionId), {
      ...scheduleRevisionData(next, nextAudit, {
        associationId: authority.associationId,
        competitionId,
        gameId: eventId,
        versionId,
        predecessorVersionId,
        reasonCode: action,
        homeTeamEntryId: id(game.get("homeTeamEntryId"), "stored homeTeamEntryId"),
        awayTeamEntryId: id(game.get("awayTeamEntryId"), "stored awayTeamEntryId"),
        actorId: actor.uid,
      }),
    });
    for (const lock of locks) transaction.set(lock, {version: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    const result = {operationId, status: action === "cancel" ? "cancelled" : "updated", eventId, scheduleVersion: nextVersion};
    saveReceipt(transaction, receiptRef, {actorId: actor.uid, associationId: authority.associationId, operation: "schedule.mutate", operationId, requestFingerprint: fingerprint, result});
    return result;
  });
}

export const LEAGUE_CALLABLE_OPTIONS = Object.freeze({enforceAppCheck: true});

export const getRosterWorkspace = onCall(LEAGUE_CALLABLE_OPTIONS, getRosterWorkspaceHandler);
export const submitRosterChange = onCall(LEAGUE_CALLABLE_OPTIONS, submitRosterChangeHandler);
export const reviewRosterProposal = onCall(LEAGUE_CALLABLE_OPTIONS, reviewRosterProposalHandler);
export const deleteDivisionIfUnreferenced = onCall(LEAGUE_CALLABLE_OPTIONS, deleteDivisionIfUnreferencedHandler);
export const scheduleGame = onCall(LEAGUE_CALLABLE_OPTIONS, scheduleGameHandler);
export const createScheduleBatch = onCall(LEAGUE_CALLABLE_OPTIONS, createScheduleBatchHandler);
export const mutateScheduledGame = onCall(LEAGUE_CALLABLE_OPTIONS, mutateScheduledGameHandler);
