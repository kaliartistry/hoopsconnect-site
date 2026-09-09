import {DocumentSnapshot, Firestore, Timestamp, Transaction} from "firebase-admin/firestore";
import {
  AccessEnvelope,
  AuthorityControl,
  GameAssignment,
  GameAuthorityHead,
  GameScope,
  MembershipAuthorityV2,
  ScopedAuthoritySourceSuccess,
  evaluateScopedAuthoritySources,
  isAuthorityControl,
  validAssignment,
  validAuthorityId,
  validCanonicalGame,
} from "./scoped_authority";

const READ_SCHEMA_VERSION = 2;
const MAX_REQUEST_BYTES = 4 * 1024;
const MAX_RESPONSE_BYTES = 16 * 1024;

export interface AssignedGameBootstrapLocator {
  associationId: string;
  competitionId: string;
  seasonId: string;
  gameId: string;
}

export interface AssignedGameBootstrapRequest {
  readSchemaVersion: 2;
  locator: AssignedGameBootstrapLocator;
}

export interface AssignedGameBootstrapSnapshots {
  membership?: MembershipAuthorityV2;
  associationControl?: AuthorityControl;
  associationAccess?: AccessEnvelope;
  seasonControl?: AuthorityControl;
  seasonAccess?: AccessEnvelope;
  game?: GameAuthorityHead;
  assignment?: GameAssignment;
}

export interface AssignedGameBootstrapReadAllowed {
  kind: "assignedGameBootstrapReadAllowed";
  purpose: "assignedGameBootstrapRead";
  capability: "stats.enter";
  uid: string;
  scope: GameScope;
  schemas: {
    readSchemaVersion: 2;
    authorizationSchemaVersion: 2;
    domainSchemaVersion: 2;
  };
  membershipVersion: number;
  grant: ScopedAuthoritySourceSuccess["grant"];
  accessSources: ScopedAuthoritySourceSuccess["accessSources"];
  controls: {
    association: {
      path: string;
      controlVersion: number;
      acceptedCalculatorVersions: readonly string[];
    };
    season: {
      path: string;
      controlVersion: number;
      acceptedCalculatorVersions: readonly string[];
    };
  };
  game: {
    gamePath: string;
    controlVersion: number;
    homeTeamEntryId: string;
    awayTeamEntryId: string;
  };
  assignment: {
    assignmentPath: string;
    assignmentVersion: number;
    writerEpoch: number;
    duty: "enter";
    duties: readonly ("enter" | "submit")[];
  };
  evaluatedAt: string;
}

export type AssignedGameBootstrapDenialCode =
  "invalid_request" | "request_too_large" | "authority_disabled" |
  "unsupported_schema" | "membership_denied" | "capability_denied" |
  "scope_denied" | "grant_inactive" | "game_control_denied" |
  "assignment_denied" | "response_too_large";

export type AssignedGameBootstrapDecision = AssignedGameBootstrapReadAllowed | {
  kind: "assignedGameBootstrapReadDenied";
  code: AssignedGameBootstrapDenialCode;
};

export interface AssignedGameBootstrapDto {
  readSchemaVersion: 2;
  kind: "assignedGameBootstrap";
  actorAccountId: string;
  scope: GameScope;
  homeTeamEntryId: string;
  awayTeamEntryId: string;
  gameControlVersion: number;
  assignment: {
    assignmentVersion: number;
    writerEpoch: number;
    duties: readonly string[];
  };
  controlVersions: {association: number; season: number};
  compatibility: {
    authorizationSchemaVersion: 2;
    domainSchemaVersion: 2;
    commandSchemaVersion: 2;
    acceptedCalculatorVersions: readonly string[];
  };
  evaluatedAt: string;
}

export interface AssignedGameBootstrapTransactionResult {
  authority: AssignedGameBootstrapReadAllowed;
  dto: AssignedGameBootstrapDto;
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : null;
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === expected.length && expected.every((key) =>
    Object.prototype.hasOwnProperty.call(value, key));
}

function jsonBytes(value: unknown): number | null {
  try {
    const encoded = JSON.stringify(value);
    return encoded === undefined ? null : Buffer.byteLength(encoded, "utf8");
  } catch (_) {
    return null;
  }
}

function parsedRequest(value: unknown): AssignedGameBootstrapRequest | null {
  const request = record(value);
  if (!request || !exactKeys(request, ["readSchemaVersion", "locator"]) ||
      request.readSchemaVersion !== READ_SCHEMA_VERSION) return null;
  const locator = record(request.locator);
  if (!locator || !exactKeys(locator, [
    "associationId", "competitionId", "seasonId", "gameId",
  ]) || !Object.values(locator).every(validAuthorityId)) return null;
  return {
    readSchemaVersion: 2,
    locator: {
      associationId: locator.associationId as string,
      competitionId: locator.competitionId as string,
      seasonId: locator.seasonId as string,
      gameId: locator.gameId as string,
    },
  };
}

function isoMilliseconds(value: Date | Timestamp): string | null {
  const date = value instanceof Timestamp ? value.toDate() : value;
  return date instanceof Date && !Number.isNaN(date.getTime()) ? date.toISOString() : null;
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value as Record<string, unknown>)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

function controlModeValid(control: AuthorityControl | undefined): boolean {
  return control?.authorityMode === "v2";
}

function denied(code: AssignedGameBootstrapDenialCode): AssignedGameBootstrapDecision {
  return deepFreeze({kind: "assignedGameBootstrapReadDenied" as const, code});
}

export function evaluateAssignedGameBootstrapRead(
  trustedSnapshots: AssignedGameBootstrapSnapshots,
  trustedUid: unknown,
  requestValue: unknown,
  trustedTime: Date | Timestamp,
): AssignedGameBootstrapDecision {
  const requestBytes = jsonBytes(requestValue);
  if (requestBytes === null) return denied("invalid_request");
  if (requestBytes > MAX_REQUEST_BYTES) return denied("request_too_large");
  const request = parsedRequest(requestValue);
  if (!request || !validAuthorityId(trustedUid)) return denied("invalid_request");
  const {associationId, competitionId, seasonId, gameId} = request.locator;
  const associationPath = `associations/${associationId}`;
  const seasonPath = `${associationPath}/competitions/${competitionId}/seasons/${seasonId}`;
  const gamePath = `${seasonPath}/games/${gameId}`;

  if (!controlModeValid(trustedSnapshots.associationControl) ||
      !controlModeValid(trustedSnapshots.seasonControl)) return denied("authority_disabled");
  const controlScope = {associationId, competitionId, seasonId};
  if (!isAuthorityControl(trustedSnapshots.associationControl, controlScope, "association") ||
      !isAuthorityControl(trustedSnapshots.seasonControl, controlScope, "season")) {
    return denied("unsupported_schema");
  }

  const game = record(trustedSnapshots.game);
  if (!game) return denied("game_control_denied");
  const scope: GameScope = {
    associationId,
    competitionId,
    seasonId,
    divisionId: game.divisionId as string,
    phaseId: game.phaseId as string,
    gameId,
  };
  if (!validCanonicalGame(trustedSnapshots.game, scope)) {
    return denied("game_control_denied");
  }

  const sourceDecision = evaluateScopedAuthoritySources({
    uid: trustedUid,
    membership: trustedSnapshots.membership,
    associationAccess: trustedSnapshots.associationAccess,
    seasonAccess: trustedSnapshots.seasonAccess,
    capability: "stats.enter",
    scope,
    evaluationTime: trustedTime,
  });
  if (!sourceDecision.authorized) return denied(sourceDecision.code);
  if (!validAssignment(
    trustedSnapshots.assignment, trustedUid, scope, trustedSnapshots.game,
    sourceDecision.membershipVersion, "enter",
  )) return denied("assignment_denied");

  const evaluatedAt = isoMilliseconds(trustedTime);
  if (!evaluatedAt) return denied("grant_inactive");
  const assignment = trustedSnapshots.assignment;
  const associationControl = trustedSnapshots.associationControl;
  const seasonControl = trustedSnapshots.seasonControl;
  const allowed = deepFreeze<AssignedGameBootstrapReadAllowed>({
    kind: "assignedGameBootstrapReadAllowed",
    purpose: "assignedGameBootstrapRead",
    capability: "stats.enter",
    uid: trustedUid,
    scope: {...scope},
    schemas: {
      readSchemaVersion: 2,
      authorizationSchemaVersion: 2,
      domainSchemaVersion: 2,
    },
    membershipVersion: sourceDecision.membershipVersion,
    grant: {...sourceDecision.grant},
    accessSources: {
      association: {...sourceDecision.accessSources.association},
      season: {...sourceDecision.accessSources.season},
    },
    controls: {
      association: {
        path: `${associationPath}/domainControl/current`,
        controlVersion: associationControl.controlVersion as number,
        acceptedCalculatorVersions: [...associationControl.acceptedCalculatorVersions as string[]],
      },
      season: {
        path: `${seasonPath}/control/current`,
        controlVersion: seasonControl.controlVersion as number,
        acceptedCalculatorVersions: [...seasonControl.acceptedCalculatorVersions as string[]],
      },
    },
    game: {
      gamePath,
      controlVersion: trustedSnapshots.game.controlVersion as number,
      homeTeamEntryId: trustedSnapshots.game.homeTeamEntryId as string,
      awayTeamEntryId: trustedSnapshots.game.awayTeamEntryId as string,
    },
    assignment: {
      assignmentPath: `${gamePath}/assignments/${trustedUid}`,
      assignmentVersion: assignment.assignmentVersion as number,
      writerEpoch: assignment.writerEpoch as number,
      duty: "enter",
      duties: [...assignment.duties as ("enter" | "submit")[]],
    },
    evaluatedAt,
  });
  return allowed;
}

export function buildAssignedGameBootstrapDto(
  authority: AssignedGameBootstrapReadAllowed,
): AssignedGameBootstrapDto {
  const acceptedBySeason = new Set(authority.controls.season.acceptedCalculatorVersions);
  const intersection = [...authority.controls.association.acceptedCalculatorVersions]
    .filter((version) => acceptedBySeason.has(version)).sort();
  const dto = deepFreeze<AssignedGameBootstrapDto>({
    readSchemaVersion: 2,
    kind: "assignedGameBootstrap",
    actorAccountId: authority.uid,
    scope: {...authority.scope},
    homeTeamEntryId: authority.game.homeTeamEntryId,
    awayTeamEntryId: authority.game.awayTeamEntryId,
    gameControlVersion: authority.game.controlVersion,
    assignment: {
      assignmentVersion: authority.assignment.assignmentVersion,
      writerEpoch: authority.assignment.writerEpoch,
      duties: [...authority.assignment.duties],
    },
    controlVersions: {
      association: authority.controls.association.controlVersion,
      season: authority.controls.season.controlVersion,
    },
    compatibility: {
      authorizationSchemaVersion: 2,
      domainSchemaVersion: 2,
      commandSchemaVersion: 2,
      acceptedCalculatorVersions: intersection,
    },
    evaluatedAt: authority.evaluatedAt,
  });
  if ((jsonBytes(dto) ?? MAX_RESPONSE_BYTES + 1) > MAX_RESPONSE_BYTES) {
    throw new AssignedGameBootstrapError("response_too_large");
  }
  return dto;
}

function data<T>(snapshot: DocumentSnapshot): T | undefined {
  return snapshot.exists ? snapshot.data() as T : undefined;
}

export async function requireAssignedGameBootstrapReadInTransaction(
  transaction: Transaction,
  db: Firestore,
  trustedUid: unknown,
  requestValue: unknown,
): Promise<AssignedGameBootstrapTransactionResult> {
  const requestBytes = jsonBytes(requestValue);
  if (requestBytes === null || requestBytes > MAX_REQUEST_BYTES) {
    throw new AssignedGameBootstrapError(requestBytes === null ? "invalid_request" : "request_too_large");
  }
  const request = parsedRequest(requestValue);
  if (!request || !validAuthorityId(trustedUid)) throw new AssignedGameBootstrapError("invalid_request");
  const {associationId, competitionId, seasonId, gameId} = request.locator;
  const associationPath = `associations/${associationId}`;
  const seasonPath = `${associationPath}/competitions/${competitionId}/seasons/${seasonId}`;
  const gamePath = `${seasonPath}/games/${gameId}`;
  const snapshots = await transaction.getAll(
    db.doc(`memberships/${trustedUid}`),
    db.doc(`${associationPath}/domainControl/current`),
    db.doc(`${associationPath}/access/${trustedUid}`),
    db.doc(`${seasonPath}/control/current`),
    db.doc(`${seasonPath}/access/${trustedUid}`),
    db.doc(gamePath),
    db.doc(`${gamePath}/assignments/${trustedUid}`),
  );
  const trustedSnapshots: AssignedGameBootstrapSnapshots = {
    membership: data<MembershipAuthorityV2>(snapshots[0]),
    associationControl: data<AuthorityControl>(snapshots[1]),
    associationAccess: data<AccessEnvelope>(snapshots[2]),
    seasonControl: data<AuthorityControl>(snapshots[3]),
    seasonAccess: data<AccessEnvelope>(snapshots[4]),
    game: data<GameAuthorityHead>(snapshots[5]),
    assignment: data<GameAssignment>(snapshots[6]),
  };
  const decision = evaluateAssignedGameBootstrapRead(
    trustedSnapshots, trustedUid, request, Timestamp.now(),
  );
  if (decision.kind !== "assignedGameBootstrapReadAllowed") {
    throw new AssignedGameBootstrapError(decision.code);
  }
  return deepFreeze({
    authority: decision,
    dto: buildAssignedGameBootstrapDto(decision),
  });
}

export class AssignedGameBootstrapError extends Error {
  constructor(readonly code: AssignedGameBootstrapDenialCode) {
    super(code);
    this.name = "AssignedGameBootstrapError";
  }
}
