import {DocumentSnapshot, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";

export const AUTHORIZATION_SCHEMA_V2 = 2;
export const DOMAIN_SCHEMA_V2 = 2;
export const COMMAND_SCHEMA_V2 = 2;
export const MAX_SAFE_AUTHORITY_INTEGER = 9007199254740991;

export const v2Capabilities = [
  "association.read", "players.manage", "players.private.read", "rosters.assert",
  "rosters.manage", "games.schedule", "stats.enter", "stats.submit", "stats.review",
  "stats.correct", "stats.certify", "results.publish", "results.retract", "official.override",
] as const;
export type V2Capability = typeof v2Capabilities[number];
export type AuthorityMode = "disabled" | "shadow" | "v2";
export type ScopeKind = "association" | "season" | "division" | "teamEntry";
export type AccessOrigin = "association" | "season";

export interface AssociationScope {associationId: string}
export interface SeasonScope extends AssociationScope {competitionId: string; seasonId: string}
export interface DivisionScope extends SeasonScope {divisionId: string}
export interface TeamEntryScope extends DivisionScope {teamEntryId: string}
export interface GameScope extends DivisionScope {phaseId: string; gameId: string}
export type CommandScope = AssociationScope | SeasonScope | DivisionScope | TeamEntryScope | GameScope;

export interface CommandVersions {
  authorizationSchemaVersion: unknown;
  domainSchemaVersion: unknown;
  commandSchemaVersion: unknown;
  calculatorVersion?: unknown;
}
export interface MembershipAuthorityV2 {
  authorizationSchemaVersion: unknown;
  associationId: unknown;
  status: unknown;
  membershipVersion: unknown;
  capabilities: unknown;
}
export interface AccessGrant {
  grantId: unknown;
  capability: unknown;
  scopeKind: unknown;
  associationId: unknown;
  competitionId?: unknown;
  seasonId?: unknown;
  divisionId?: unknown;
  teamEntryId?: unknown;
  status: unknown;
  membershipVersion: unknown;
  effectiveFrom: unknown;
  effectiveTo: unknown;
}
export interface AccessEnvelope {
  dataSchemaVersion: unknown;
  authorizationSchemaVersion: unknown;
  uid: unknown;
  associationId: unknown;
  competitionId?: unknown;
  seasonId?: unknown;
  scopeKind: unknown;
  status: unknown;
  membershipVersion: unknown;
  accessVersion: unknown;
  grants: unknown;
}
export interface AuthorityControl {
  dataSchemaVersion: unknown;
  associationId: unknown;
  competitionId?: unknown;
  seasonId?: unknown;
  authorityMode: unknown;
  minimumAuthorizationSchemaVersion: unknown;
  minimumDomainSchemaVersion: unknown;
  minimumCommandSchemaVersion: unknown;
  acceptedCalculatorVersions: unknown;
  controlVersion: unknown;
}
export interface GameAssignment {
  uid: unknown;
  dataSchemaVersion: unknown;
  associationId: unknown;
  competitionId: unknown;
  seasonId: unknown;
  divisionId: unknown;
  phaseId: unknown;
  gameId: unknown;
  homeTeamEntryId: unknown;
  awayTeamEntryId: unknown;
  status: unknown;
  duties: unknown;
  membershipVersion: unknown;
  writerEpoch: unknown;
  assignmentVersion: unknown;
}
export interface GameAuthorityHead {
  dataSchemaVersion: unknown;
  associationId: unknown;
  competitionId: unknown;
  seasonId: unknown;
  divisionId: unknown;
  phaseId: unknown;
  gameId: unknown;
  homeTeamEntryId: unknown;
  awayTeamEntryId: unknown;
  controlVersion: unknown;
}

type ScopeLevel = "association" | "season" | "division" | "teamEntry" | "game";
export const capabilityRequirements: Record<V2Capability, {
  scope: ScopeLevel;
  calculator: boolean;
  game: boolean;
  assignment: boolean;
  closed?: boolean;
}> = {
  "association.read": {scope: "association", calculator: false, game: false, assignment: false},
  "players.manage": {scope: "association", calculator: false, game: false, assignment: false},
  "players.private.read": {scope: "association", calculator: false, game: false, assignment: false},
  "rosters.assert": {scope: "teamEntry", calculator: false, game: false, assignment: false},
  "rosters.manage": {scope: "season", calculator: false, game: false, assignment: false},
  "games.schedule": {scope: "division", calculator: false, game: false, assignment: false},
  "stats.enter": {scope: "game", calculator: true, game: true, assignment: true},
  "stats.submit": {scope: "game", calculator: true, game: true, assignment: true},
  "stats.review": {scope: "game", calculator: true, game: true, assignment: false},
  "stats.correct": {scope: "game", calculator: true, game: true, assignment: false},
  "stats.certify": {scope: "game", calculator: true, game: true, assignment: false, closed: true},
  "results.publish": {scope: "season", calculator: true, game: false, assignment: false},
  "results.retract": {scope: "season", calculator: false, game: false, assignment: false},
  "official.override": {scope: "association", calculator: false, game: false, assignment: false, closed: true},
};

export type AuthorityDenialCode =
  "authority_disabled" | "authority_shadow_only" | "invalid_scope" |
  "unsupported_schema" | "unsupported_calculator" | "membership_denied" |
  "capability_denied" | "scope_denied" | "grant_inactive" |
  "assignment_denied" | "stale_assignment_version" | "stale_writer_epoch" |
  "game_control_denied" | "stale_control_version" | "policy_gate_closed";

export interface AuthoritySuccess {
  authorized: true;
  mode: "v2";
  uid: string;
  capability: V2Capability;
  scope: CommandScope;
  versions: {
    authorizationSchemaVersion: 2;
    domainSchemaVersion: 2;
    commandSchemaVersion: 2;
    calculatorVersion?: string;
  };
  membershipVersion: number;
  grant: {
    origin: AccessOrigin;
    accessPath: string;
    accessVersion: number;
    grantKey: string;
    grantId: string;
  };
  associationControlVersion: number;
  seasonControlVersion?: number;
  game?: {
    gamePath: string;
    controlVersion: number;
    homeTeamEntryId: string;
    awayTeamEntryId: string;
  };
  assignment?: {
    assignmentPath: string;
    assignmentVersion: number;
    writerEpoch: number;
  };
  evaluatedAt: Date;
}
export type AuthorityDecision = AuthoritySuccess | {
  authorized: false;
  mode: AuthorityMode | "invalid";
  code: AuthorityDenialCode;
};

const idPattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const statusValues = ["active", "suspended", "revoked"];
const dutyValues = ["enter", "submit"];

export function validAuthorityId(value: unknown): value is string {
  return typeof value === "string" && idPattern.test(value);
}
export function positiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) > 0;
}
function record(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  try {
    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}
function hasExactKeys(value: Record<string, unknown>, expected: string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}
function validBoundedUniqueList(value: unknown, allowlist: readonly string[], maximum: number): value is string[] {
  return Array.isArray(value) && value.length <= maximum && value.every((item) => typeof item === "string" && allowlist.includes(item)) && new Set(value).size === value.length;
}
function validCalculatorList(value: unknown): value is string[] {
  return Array.isArray(value) && value.length <= 4 && value.every(validAuthorityId) && new Set(value).size === value.length;
}
function modeOf(value: unknown): AuthorityMode | "invalid" {
  return value === "disabled" || value === "shadow" || value === "v2" ? value : "invalid";
}
export function timestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.getTime();
  return null;
}

const scopeKeys: Record<ScopeLevel, string[]> = {
  association: ["associationId"],
  season: ["associationId", "competitionId", "seasonId"],
  division: ["associationId", "competitionId", "seasonId", "divisionId"],
  teamEntry: ["associationId", "competitionId", "seasonId", "divisionId", "teamEntryId"],
  game: ["associationId", "competitionId", "seasonId", "divisionId", "phaseId", "gameId"],
};

function isExactScope(value: unknown, level: ScopeLevel): value is CommandScope {
  const candidate = record(value);
  return candidate !== null && hasExactKeys(candidate, scopeKeys[level]) && Object.values(candidate).every(validAuthorityId);
}
export function isCommandScope(value: unknown): value is CommandScope {
  return (Object.keys(scopeKeys) as ScopeLevel[]).some((level) => isExactScope(value, level));
}
export function isExactScopeForAction(value: unknown, capability: V2Capability): value is CommandScope {
  return isExactScope(value, capabilityRequirements[capability].scope);
}

function controlModeError(control: AuthorityControl | undefined): AuthorityDenialCode | null {
  const mode = modeOf(control?.authorityMode);
  if (mode === "shadow") return "authority_shadow_only";
  if (mode !== "v2") return "authority_disabled";
  return null;
}
export function isAuthorityControl(control: unknown, scope: AssociationScope | SeasonScope, origin: AccessOrigin): control is AuthorityControl {
  const value = record(control);
  if (!value || value.dataSchemaVersion !== 2 || value.associationId !== scope.associationId ||
      value.minimumAuthorizationSchemaVersion !== 2 || value.minimumDomainSchemaVersion !== 2 ||
      value.minimumCommandSchemaVersion !== 2 || !positiveSafeInteger(value.controlVersion) ||
      !validCalculatorList(value.acceptedCalculatorVersions)) return false;
  if (origin === "association") return !Object.prototype.hasOwnProperty.call(value, "competitionId") && !Object.prototype.hasOwnProperty.call(value, "seasonId");
  const season = scope as SeasonScope;
  return value.competitionId === season.competitionId && value.seasonId === season.seasonId;
}
function versionsAccepted(
  associationControl: AuthorityControl,
  seasonControl: AuthorityControl | undefined,
  versions: CommandVersions,
  requirement: typeof capabilityRequirements[V2Capability],
): AuthorityDenialCode | null {
  const value = record(versions);
  const baseKeys = ["authorizationSchemaVersion", "domainSchemaVersion", "commandSchemaVersion"];
  if (!value || !baseKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key)) ||
      value.authorizationSchemaVersion !== 2 || value.domainSchemaVersion !== 2 || value.commandSchemaVersion !== 2) return "unsupported_schema";
  const actualKeys = Object.keys(value);
  if (actualKeys.some((key) => ![...baseKeys, "calculatorVersion"].includes(key))) return "unsupported_schema";
  const hasCalculator = Object.prototype.hasOwnProperty.call(value, "calculatorVersion");
  if (!requirement.calculator) return hasCalculator ? "unsupported_calculator" : null;
  if (!hasCalculator) return "unsupported_calculator";
  if (!validAuthorityId(value.calculatorVersion)) return "unsupported_calculator";
  if (!(associationControl.acceptedCalculatorVersions as string[]).includes(value.calculatorVersion)) return "unsupported_calculator";
  if (!seasonControl || !(seasonControl.acceptedCalculatorVersions as string[]).includes(value.calculatorVersion)) return "unsupported_calculator";
  return null;
}

const grantCommon = ["grantId", "capability", "scopeKind", "associationId", "status", "membershipVersion", "effectiveFrom", "effectiveTo"];
const grantKeys: Record<ScopeKind, string[]> = {
  association: grantCommon,
  season: [...grantCommon, "competitionId", "seasonId"],
  division: [...grantCommon, "competitionId", "seasonId", "divisionId"],
  teamEntry: [...grantCommon, "competitionId", "seasonId", "divisionId", "teamEntryId"],
};

export function isStrictAccessGrant(value: unknown): value is AccessGrant {
  const grant = record(value);
  if (!grant || !validAuthorityId(grant.grantId) || typeof grant.capability !== "string" ||
      !v2Capabilities.includes(grant.capability as V2Capability) || !validAuthorityId(grant.associationId) ||
      !statusValues.includes(grant.status as string) || !positiveSafeInteger(grant.membershipVersion) ||
      !(grant.effectiveFrom instanceof Timestamp) || !(grant.effectiveTo === null || grant.effectiveTo instanceof Timestamp)) return false;
  const kind = grant.scopeKind;
  if (kind !== "association" && kind !== "season" && kind !== "division" && kind !== "teamEntry") return false;
  if (!hasExactKeys(grant, grantKeys[kind])) return false;
  if (kind === "association") return true;
  if (!validAuthorityId(grant.competitionId) || !validAuthorityId(grant.seasonId)) return false;
  if (kind === "season") return true;
  if (!validAuthorityId(grant.divisionId)) return false;
  return kind === "division" || validAuthorityId(grant.teamEntryId);
}

export function authorityGrantKey(grant: AccessGrant): string | null {
  if (!isStrictAccessGrant(grant)) return null;
  const capability = grant.capability as string;
  if (grant.scopeKind === "association" || grant.scopeKind === "season") return `${capability}|${grant.scopeKind}`;
  if (grant.scopeKind === "division") return `${capability}|division|${grant.divisionId as string}`;
  return `${capability}|teamEntry|${grant.divisionId as string}|${grant.teamEntryId as string}`;
}

export function accessGrantMatchesScope(grant: unknown, scope: CommandScope): boolean {
  if (!isStrictAccessGrant(grant) || grant.associationId !== scope.associationId) return false;
  if (grant.scopeKind === "association") return true;
  const lower = scope as Partial<SeasonScope & DivisionScope & TeamEntryScope>;
  if (grant.competitionId !== lower.competitionId || grant.seasonId !== lower.seasonId) return false;
  if (grant.scopeKind === "season") return true;
  if (grant.divisionId !== lower.divisionId) return false;
  return grant.scopeKind === "division" || grant.teamEntryId === lower.teamEntryId;
}

const associationEnvelopeKeys = ["dataSchemaVersion", "authorizationSchemaVersion", "uid", "associationId", "scopeKind", "status", "membershipVersion", "accessVersion", "grants"];
const seasonEnvelopeKeys = [...associationEnvelopeKeys, "competitionId", "seasonId"];
function accessGrantMap(value: unknown): Record<string, unknown> | null {
  return record(value);
}
export function isStrictAccessEnvelope(value: unknown, origin: AccessOrigin, uid: string, scope: AssociationScope | SeasonScope): value is AccessEnvelope {
  const envelope = record(value);
  if (!envelope || !hasExactKeys(envelope, origin === "association" ? associationEnvelopeKeys : seasonEnvelopeKeys) ||
      envelope.dataSchemaVersion !== 2 || envelope.authorizationSchemaVersion !== 2 || envelope.uid !== uid ||
      envelope.associationId !== scope.associationId || envelope.scopeKind !== origin || !statusValues.includes(envelope.status as string) ||
      !positiveSafeInteger(envelope.membershipVersion) || !positiveSafeInteger(envelope.accessVersion) || accessGrantMap(envelope.grants) === null) return false;
  if (origin === "association") return true;
  const season = scope as SeasonScope;
  return envelope.competitionId === season.competitionId && envelope.seasonId === season.seasonId;
}

export function validAuthorityTeamEntryIds(value: unknown): value is [string, string] {
  return Array.isArray(value) && value.length === 2 && value.every(validAuthorityId) && new Set(value).size === 2;
}
export function validCanonicalGame(value: unknown, scope: GameScope): value is GameAuthorityHead {
  const game = record(value);
  return game !== null && game.dataSchemaVersion === 2 && game.associationId === scope.associationId &&
    game.competitionId === scope.competitionId && game.seasonId === scope.seasonId && game.divisionId === scope.divisionId &&
    validAuthorityId(game.divisionId) && game.phaseId === scope.phaseId && validAuthorityId(game.phaseId) &&
    game.gameId === scope.gameId && validAuthorityId(game.homeTeamEntryId) &&
    validAuthorityId(game.awayTeamEntryId) && game.homeTeamEntryId !== game.awayTeamEntryId &&
    !Object.prototype.hasOwnProperty.call(game, "teamEntryIds") && positiveSafeInteger(game.controlVersion);
}
export function validAssignment(value: unknown, uid: string, scope: GameScope, game: GameAuthorityHead, membershipVersion: number, duty: string): value is GameAssignment {
  const assignment = record(value);
  return assignment !== null && hasExactKeys(assignment, [
    "uid", "dataSchemaVersion", "associationId", "competitionId", "seasonId",
    "divisionId", "phaseId", "gameId", "homeTeamEntryId", "awayTeamEntryId",
    "status", "duties", "membershipVersion", "writerEpoch", "assignmentVersion",
  ]) && assignment.uid === uid && assignment.dataSchemaVersion === 2 &&
    assignment.associationId === scope.associationId && assignment.competitionId === scope.competitionId &&
    assignment.seasonId === scope.seasonId && assignment.divisionId === scope.divisionId && assignment.phaseId === scope.phaseId &&
    assignment.gameId === scope.gameId && assignment.homeTeamEntryId === game.homeTeamEntryId &&
    assignment.awayTeamEntryId === game.awayTeamEntryId && !Object.prototype.hasOwnProperty.call(assignment, "teamEntryIds") && assignment.status === "active" &&
    assignment.membershipVersion === membershipVersion && positiveSafeInteger(assignment.assignmentVersion) &&
    positiveSafeInteger(assignment.writerEpoch) && validBoundedUniqueList(assignment.duties, dutyValues, dutyValues.length) &&
    (assignment.duties as string[]).includes(duty);
}

function accessPath(origin: AccessOrigin, uid: string, scope: AssociationScope | SeasonScope): string {
  const association = `associations/${scope.associationId}`;
  if (origin === "association") return `${association}/access/${uid}`;
  const season = scope as SeasonScope;
  return `${association}/competitions/${season.competitionId}/seasons/${season.seasonId}/access/${uid}`;
}
function gamePath(scope: GameScope): string {
  return `associations/${scope.associationId}/competitions/${scope.competitionId}/seasons/${scope.seasonId}/games/${scope.gameId}`;
}
function grantCandidates(capability: V2Capability, scope: CommandScope, requirement: typeof capabilityRequirements[V2Capability]): Array<{origin: AccessOrigin; key: string}> {
  const candidates: Array<{origin: AccessOrigin; key: string}> = [];
  if (requirement.scope === "teamEntry") {
    const team = scope as TeamEntryScope;
    candidates.push({origin: "season", key: `${capability}|teamEntry|${team.divisionId}|${team.teamEntryId}`});
  }
  if (requirement.scope === "division" || requirement.scope === "teamEntry" || requirement.scope === "game") {
    candidates.push({origin: "season", key: `${capability}|division|${(scope as DivisionScope).divisionId}`});
  }
  if (requirement.scope !== "association") candidates.push({origin: "season", key: `${capability}|season`});
  candidates.push({origin: "association", key: `${capability}|association`});
  return candidates;
}

export interface AccessSourceFact {
  present: boolean;
  accessVersion?: number;
  membershipVersion?: number;
  status?: "active" | "suspended" | "revoked";
}

export interface ScopedAuthoritySourceSuccess {
  authorized: true;
  membershipVersion: number;
  grant: {
    origin: AccessOrigin;
    accessPath: string;
    accessVersion: number;
    grantKey: string;
    grantId: string;
  };
  accessSources: {
    association: AccessSourceFact;
    season: AccessSourceFact;
  };
}

export type ScopedAuthoritySourceDecision = ScopedAuthoritySourceSuccess | {
  authorized: false;
  code: "membership_denied" | "capability_denied" | "scope_denied" | "grant_inactive";
};

function accessSourceFact(envelope: AccessEnvelope | undefined): AccessSourceFact {
  if (!envelope) return {present: false};
  return {
    present: true,
    accessVersion: envelope.accessVersion as number,
    membershipVersion: envelope.membershipVersion as number,
    status: envelope.status as "active" | "suspended" | "revoked",
  };
}

export function evaluateScopedAuthoritySources(input: {
  uid: string;
  membership?: MembershipAuthorityV2;
  associationAccess?: AccessEnvelope;
  seasonAccess?: AccessEnvelope;
  capability: V2Capability;
  scope: CommandScope;
  evaluationTime: Date | Timestamp;
}): ScopedAuthoritySourceDecision {
  const nowMs = timestampMillis(input.evaluationTime);
  if (nowMs === null) return {authorized: false, code: "grant_inactive"};
  const member = input.membership;
  if (!member || member.authorizationSchemaVersion !== 2 || member.status !== "active" ||
      member.associationId !== input.scope.associationId || !positiveSafeInteger(member.membershipVersion) ||
      !validBoundedUniqueList(member.capabilities, v2Capabilities, v2Capabilities.length)) {
    return {authorized: false, code: "membership_denied"};
  }
  if (!(member.capabilities as string[]).includes(input.capability)) {
    return {authorized: false, code: "capability_denied"};
  }

  const requirement = capabilityRequirements[input.capability];
  const lower = requirement.scope !== "association";
  const associationPresent = input.associationAccess !== undefined;
  const seasonPresent = lower && input.seasonAccess !== undefined;
  if (associationPresent && !isStrictAccessEnvelope(
    input.associationAccess, "association", input.uid, input.scope,
  )) return {authorized: false, code: "scope_denied"};
  if (seasonPresent && !isStrictAccessEnvelope(
    input.seasonAccess, "season", input.uid, input.scope as SeasonScope,
  )) return {authorized: false, code: "scope_denied"};
  const associationGrantMap = associationPresent ? accessGrantMap(input.associationAccess!.grants)! : {};
  const seasonGrantMap = seasonPresent ? accessGrantMap(input.seasonAccess!.grants)! : {};
  if (Object.keys(associationGrantMap).length + Object.keys(seasonGrantMap).length > 64) {
    return {authorized: false, code: "scope_denied"};
  }

  const currentVersion = member.membershipVersion as number;
  const associationUsable = associationPresent && input.associationAccess!.status === "active" &&
    input.associationAccess!.membershipVersion === currentVersion;
  const seasonUsable = seasonPresent && input.seasonAccess!.status === "active" &&
    input.seasonAccess!.membershipVersion === currentVersion;
  let selected: {origin: AccessOrigin; envelope: AccessEnvelope; key: string; grant: AccessGrant} | undefined;
  let temporalFailure = false;
  for (const candidate of grantCandidates(input.capability, input.scope, requirement)) {
    const usable = candidate.origin === "association" ? associationUsable : seasonUsable;
    const envelope = candidate.origin === "association" ? input.associationAccess : input.seasonAccess;
    const grants = candidate.origin === "association" ? associationGrantMap : seasonGrantMap;
    if (!usable || !envelope || !Object.prototype.hasOwnProperty.call(grants, candidate.key)) continue;
    const grant = grants[candidate.key];
    if (!isStrictAccessGrant(grant) || authorityGrantKey(grant) !== candidate.key ||
        grant.capability !== input.capability || grant.membershipVersion !== currentVersion ||
        grant.associationId !== input.scope.associationId ||
        (candidate.origin === "association" && grant.scopeKind !== "association") ||
        (candidate.origin === "season" && grant.scopeKind === "association") ||
        !accessGrantMatchesScope(grant, input.scope)) continue;
    const from = (grant.effectiveFrom as Timestamp).toMillis();
    const to = grant.effectiveTo === null ? null : (grant.effectiveTo as Timestamp).toMillis();
    if (grant.status !== "active" || (to !== null && from >= to) || nowMs < from ||
        (to !== null && nowMs >= to)) {
      temporalFailure = true;
      continue;
    }
    selected = {origin: candidate.origin, envelope, key: candidate.key, grant};
    break;
  }
  if (!selected) {
    return {authorized: false, code: temporalFailure ? "grant_inactive" : "scope_denied"};
  }
  return {
    authorized: true,
    membershipVersion: currentVersion,
    grant: {
      origin: selected.origin,
      accessPath: accessPath(selected.origin, input.uid, input.scope),
      accessVersion: selected.envelope.accessVersion as number,
      grantKey: selected.key,
      grantId: selected.grant.grantId as string,
    },
    accessSources: {
      association: accessSourceFact(input.associationAccess),
      season: lower ? accessSourceFact(input.seasonAccess) : {present: false},
    },
  };
}

export function evaluateScopedAuthority(input: {
  uid: unknown;
  membership?: MembershipAuthorityV2;
  associationAccess?: AccessEnvelope;
  seasonAccess?: AccessEnvelope;
  assignment?: GameAssignment;
  game?: GameAuthorityHead;
  associationControl?: AuthorityControl;
  seasonControl?: AuthorityControl;
  capability: V2Capability;
  scope: unknown;
  versions: CommandVersions;
  evaluationTime: Date | Timestamp;
  expectedAssignmentVersion?: number;
  writerEpoch?: number;
  expectedGameControlVersion?: number;
}): AuthorityDecision {
  const associationMode = modeOf(input.associationControl?.authorityMode);
  const associationModeError = controlModeError(input.associationControl);
  if (associationModeError) return {authorized: false, mode: associationMode, code: associationModeError};
  if (!validAuthorityId(input.uid) || !isExactScopeForAction(input.scope, input.capability)) return {authorized: false, mode: "v2", code: "invalid_scope"};
  const requirement = capabilityRequirements[input.capability];
  if (requirement.closed) return {authorized: false, mode: "v2", code: "policy_gate_closed"};
  const scope = input.scope;
  const lower = requirement.scope !== "association";
  if (lower) {
    const seasonModeError = controlModeError(input.seasonControl);
    if (seasonModeError) return {authorized: false, mode: "v2", code: seasonModeError};
  }
  if (!isAuthorityControl(input.associationControl, scope, "association") ||
      (lower && !isAuthorityControl(input.seasonControl, scope as SeasonScope, "season"))) {
    return {authorized: false, mode: "v2", code: "unsupported_schema"};
  }
  const versionError = versionsAccepted(input.associationControl, input.seasonControl, input.versions, requirement);
  if (versionError) return {authorized: false, mode: "v2", code: versionError};
  const sourceDecision = evaluateScopedAuthoritySources({
    uid: input.uid,
    membership: input.membership,
    associationAccess: input.associationAccess,
    seasonAccess: input.seasonAccess,
    capability: input.capability,
    scope,
    evaluationTime: input.evaluationTime,
  });
  if (!sourceDecision.authorized) {
    return {authorized: false, mode: "v2", code: sourceDecision.code};
  }
  const currentVersion = sourceDecision.membershipVersion;
  const nowMs = timestampMillis(input.evaluationTime)!;

  let gameBinding: AuthoritySuccess["game"];
  let assignmentBinding: AuthoritySuccess["assignment"];
  if (requirement.game) {
    const gameScope = scope as GameScope;
    if (!validCanonicalGame(input.game, gameScope)) return {authorized: false, mode: "v2", code: "game_control_denied"};
    if (!positiveSafeInteger(input.expectedGameControlVersion) || input.expectedGameControlVersion !== input.game.controlVersion) return {authorized: false, mode: "v2", code: "stale_control_version"};
    gameBinding = {
      gamePath: gamePath(gameScope),
      controlVersion: input.game.controlVersion as number,
      homeTeamEntryId: input.game.homeTeamEntryId as string,
      awayTeamEntryId: input.game.awayTeamEntryId as string,
    };
    if (requirement.assignment) {
      const duty = input.capability === "stats.enter" ? "enter" : "submit";
      if (!validAssignment(input.assignment, input.uid, gameScope, input.game, currentVersion, duty)) return {authorized: false, mode: "v2", code: "assignment_denied"};
      if (!positiveSafeInteger(input.expectedAssignmentVersion) || input.expectedAssignmentVersion !== input.assignment.assignmentVersion) return {authorized: false, mode: "v2", code: "stale_assignment_version"};
      if (!positiveSafeInteger(input.writerEpoch) || input.writerEpoch !== input.assignment.writerEpoch) return {authorized: false, mode: "v2", code: "stale_writer_epoch"};
      assignmentBinding = {
        assignmentPath: `${gamePath(gameScope)}/assignments/${input.uid}`,
        assignmentVersion: input.assignment.assignmentVersion as number,
        writerEpoch: input.assignment.writerEpoch as number,
      };
    }
  }

  const calculatorVersion = requirement.calculator ? input.versions.calculatorVersion as string : undefined;
  return {
    authorized: true,
    mode: "v2",
    uid: input.uid,
    capability: input.capability,
    scope: {...scope},
    versions: {
      authorizationSchemaVersion: 2,
      domainSchemaVersion: 2,
      commandSchemaVersion: 2,
      ...(calculatorVersion === undefined ? {} : {calculatorVersion}),
    },
    membershipVersion: currentVersion,
    grant: {...sourceDecision.grant},
    associationControlVersion: input.associationControl.controlVersion as number,
    ...(lower ? {seasonControlVersion: input.seasonControl!.controlVersion as number} : {}),
    ...(gameBinding ? {game: gameBinding} : {}),
    ...(assignmentBinding ? {assignment: assignmentBinding} : {}),
    evaluatedAt: new Date(nowMs),
  };
}

function data<T>(snapshot: DocumentSnapshot): T | undefined {
  return snapshot.exists ? snapshot.data() as T : undefined;
}
export interface TransactionAuthorityRequest {
  uid: string;
  scope: CommandScope;
  capability: V2Capability;
  versions: CommandVersions;
  expectedAssignmentVersion?: number;
  writerEpoch?: number;
  expectedGameControlVersion?: number;
}
export async function requireScopedAuthorityInTransaction(
  transaction: Transaction,
  db: Firestore,
  request: TransactionAuthorityRequest,
): Promise<AuthoritySuccess> {
  const evaluationTime = Timestamp.now();
  if (!validAuthorityId(request.uid) || !isExactScopeForAction(request.scope, request.capability)) throw new ScopedAuthorityError("invalid_scope");
  const requirement = capabilityRequirements[request.capability];
  const {uid, scope} = request;
  const association = `associations/${scope.associationId}`;
  const refs = [
    db.doc(`memberships/${uid}`),
    db.doc(`${association}/domainControl/current`),
    db.doc(`${association}/access/${uid}`),
  ];
  let seasonPath: string | null = null;
  if (requirement.scope !== "association") {
    const season = scope as SeasonScope;
    seasonPath = `${association}/competitions/${season.competitionId}/seasons/${season.seasonId}`;
    refs.push(db.doc(`${seasonPath}/control/current`), db.doc(`${seasonPath}/access/${uid}`));
  }
  if (requirement.game) refs.push(db.doc(`${seasonPath}/games/${(scope as GameScope).gameId}`));
  if (requirement.assignment) refs.push(db.doc(`${seasonPath}/games/${(scope as GameScope).gameId}/assignments/${uid}`));
  const snapshots = await transaction.getAll(...refs);
  let index = 0;
  const membership = data<MembershipAuthorityV2>(snapshots[index++]);
  const associationControl = data<AuthorityControl>(snapshots[index++]);
  const associationAccess = data<AccessEnvelope>(snapshots[index++]);
  const seasonControl = requirement.scope !== "association" ? data<AuthorityControl>(snapshots[index++]) : undefined;
  const seasonAccess = requirement.scope !== "association" ? data<AccessEnvelope>(snapshots[index++]) : undefined;
  const game = requirement.game ? data<GameAuthorityHead>(snapshots[index++]) : undefined;
  const assignment = requirement.assignment ? data<GameAssignment>(snapshots[index++]) : undefined;
  const decision = evaluateScopedAuthority({...request, membership, associationControl, associationAccess, seasonControl, seasonAccess, game, assignment, evaluationTime});
  if (!decision.authorized) throw new ScopedAuthorityError(decision.code);
  return decision;
}
export class ScopedAuthorityError extends Error {
  constructor(readonly code: AuthorityDenialCode) {
    super(code);
    this.name = "ScopedAuthorityError";
  }
}
