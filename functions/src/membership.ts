import {createHash, createHmac} from "crypto";
import * as admin from "firebase-admin";
import {DocumentSnapshot, FieldValue, Timestamp, Transaction} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {
  AUTHORIZATION_SCHEMA_VERSION,
  PUBLIC_ASSOCIATION_ID,
  Role,
  canGrantRole,
  capabilities,
  capabilitiesForRole,
  isRole,
} from "./authorization";

const INVITE_CREDENTIAL_VERSION = 2;
const INVITE_TOKEN_HMAC_KEY_V1 = defineSecret("INVITE_TOKEN_HMAC_KEY_V1");
const operationPattern = /^[A-Za-z0-9_-]{16,128}$/;
const inviteIdPattern = /^v2_[a-f0-9]{64}$/;
const tokenPattern = /^[A-Za-z0-9_-]{43}$/;

interface CallerIdentity {
  uid: string;
  email: string;
}

interface Authority {
  associationId: string;
  role: Role;
  capabilities: string[];
}

interface InviteData {
  authorizationSchemaVersion?: unknown;
  credentialVersion?: unknown;
  inviteId?: unknown;
  associationId?: unknown;
  teamId?: unknown;
  divisionId?: unknown;
  seasonId?: unknown;
  role?: unknown;
  status?: unknown;
  usesRemaining?: unknown;
  expiresAt?: unknown;
  redeemedBy?: unknown;
  revokedAt?: unknown;
}

function requireCaller(request: CallableRequest<unknown>): CallerIdentity {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in before completing this action.");
  }
  const email = request.auth.token.email;
  if (typeof email !== "string" || email.trim().length === 0) {
    throw new HttpsError("failed-precondition", "The signed-in account must have an email address.");
  }
  return {uid: request.auth.uid, email: email.trim().toLowerCase()};
}

function requireObject(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A request object is required.");
  }
  return data as Record<string, unknown>;
}

function requireAuthorizationSchema(data: Record<string, unknown>): void {
  if (data.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION) {
    throw new HttpsError(
      "failed-precondition",
      "This app version is too old for the current authorization contract.",
    );
  }
}

function requireText(data: Record<string, unknown>, key: string, maxLength: number): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0 || value.trim().length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} is required and must be at most ${maxLength} characters.`);
  }
  return value.trim();
}

function optionalText(data: Record<string, unknown>, key: string, maxLength: number): string | null {
  const value = data[key];
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw new HttpsError("invalid-argument", `${key} must be at most ${maxLength} characters.`);
  }
  return value.trim();
}

function requireDocumentId(value: string | null, key: string): string | null {
  if (value !== null && !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new HttpsError("invalid-argument", `${key} must be a Firestore document ID.`);
  }
  return value;
}

function requireOperationId(data: Record<string, unknown>): string {
  const operationId = requireText(data, "operationId", 128);
  if (!operationPattern.test(operationId)) {
    throw new HttpsError("invalid-argument", "operationId must be an opaque URL-safe identifier.");
  }
  return operationId;
}

function normalizeToken(value: unknown): string {
  if (typeof value !== "string" || !tokenPattern.test(value.trim())) {
    // The strict v2 format makes all legacy/static raw document IDs fail closed.
    throw new HttpsError("invalid-argument", "Invite code format is invalid.");
  }
  return value.trim();
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function inviteIdForToken(token: string): string {
  return `v2_${sha256(normalizeToken(token))}`;
}

function receiptId(actorId: string, operation: string, operationId: string): string {
  return sha256(`${actorId}\u0000${operation}\u0000${operationId}`);
}

function requestFingerprint(value: Record<string, unknown>): string {
  const ordered = Object.keys(value).sort().reduce<Record<string, unknown>>((result, key) => {
    result[key] = value[key];
    return result;
  }, {});
  return sha256(JSON.stringify(ordered));
}

function inviteHmacKey(): string {
  const key = process.env.INVITE_TOKEN_HMAC_KEY_V1;
  if (typeof key !== "string" || Buffer.byteLength(key, "utf8") < 32) {
    throw new HttpsError("failed-precondition", "Invite issuance is not configured.");
  }
  return key;
}

function deriveToken(actorId: string, operationId: string): string {
  return createHmac("sha256", inviteHmacKey())
    .update(`hoopsconnect-invite-v2\u0000${actorId}\u0000${operationId}`, "utf8")
    .digest("base64url");
}

function timestampOrNull(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function inviteIsActive(invite: InviteData, inviteId: string, now: Timestamp): boolean {
  const expiresAt = timestampOrNull(invite.expiresAt);
  return invite.authorizationSchemaVersion === AUTHORIZATION_SCHEMA_VERSION
    && invite.credentialVersion === INVITE_CREDENTIAL_VERSION
    && invite.inviteId === inviteId
    && invite.status === "active"
    && invite.usesRemaining === 1
    && expiresAt !== null
    && expiresAt.toMillis() > now.toMillis()
    && !invite.revokedAt
    && !invite.redeemedBy;
}

function requireInviteShape(invite: InviteData, inviteId: string): {
  associationId: string;
  teamId: string | null;
  divisionId: string | null;
  seasonId: string | null;
  role: Role;
} {
  if (
    invite.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
    || invite.credentialVersion !== INVITE_CREDENTIAL_VERSION
    || invite.inviteId !== inviteId
    || typeof invite.associationId !== "string"
    || !/^[A-Za-z0-9_-]+$/.test(invite.associationId)
    || !isRole(invite.role)
  ) {
    throw new HttpsError("failed-precondition", "Invite is malformed.");
  }
  if (invite.role === "fan" || invite.role === "superAdmin") {
    throw new HttpsError("permission-denied", "This role cannot be assigned with an invite.");
  }
  const teamId = typeof invite.teamId === "string" && /^[A-Za-z0-9_-]+$/.test(invite.teamId)
    ? invite.teamId
    : null;
  if (invite.role === "rep" && teamId === null) {
    throw new HttpsError("failed-precondition", "Representative invites must identify a team.");
  }
  return {
    associationId: invite.associationId,
    teamId,
    divisionId: typeof invite.divisionId === "string" ? invite.divisionId : null,
    seasonId: typeof invite.seasonId === "string" ? invite.seasonId : null,
    role: invite.role,
  };
}

function authorityFromSnapshot(snapshot: DocumentSnapshot, requiredCapability: string): Authority {
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "Active membership is required.");
  }
  const membership = snapshot.data() ?? {};
  const memberCapabilities = Array.isArray(membership.capabilities)
    ? membership.capabilities.filter((value): value is string => typeof value === "string")
    : [];
  if (
    membership.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
    || membership.status !== "active"
    || !isRole(membership.role)
    || typeof membership.associationId !== "string"
    || !memberCapabilities.includes(requiredCapability)
  ) {
    throw new HttpsError("permission-denied", "You do not have permission to complete this action.");
  }
  return {
    associationId: membership.associationId,
    role: membership.role,
    capabilities: memberCapabilities,
  };
}

async function getAuthorityInTransaction(
  transaction: Transaction,
  uid: string,
  requiredCapability: string,
): Promise<Authority> {
  const snapshot = await transaction.get(admin.firestore().doc(`memberships/${uid}`));
  return authorityFromSnapshot(snapshot, requiredCapability);
}

async function requireDivisionAcceptsNewReferences(
  transaction: Transaction,
  associationId: string,
  divisionId: string | null,
): Promise<void> {
  if (divisionId === null) return;
  const division = await transaction.get(admin.firestore().doc(
    `associations/${associationId}/divisions/${divisionId}`,
  ));
  if (!division.exists || division.get("status") !== "active" || division.get("deletionPending")) {
    throw new HttpsError("failed-precondition", "The invite division is unavailable for new assignments.");
  }
}

function validMembershipAuthority(snapshot: DocumentSnapshot): Authority | null {
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  if (
    data.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
    || data.status !== "active"
    || data.associationId !== PUBLIC_ASSOCIATION_ID
    || !isRole(data.role)
    || !Array.isArray(data.capabilities)
    || JSON.stringify([...data.capabilities].sort()) !== JSON.stringify(capabilitiesForRole(data.role).sort())
  ) {
    return null;
  }
  return {
    associationId: data.associationId,
    role: data.role,
    capabilities: [...data.capabilities] as string[],
  };
}

function userMatchesAuthority(
  snapshot: DocumentSnapshot,
  caller: CallerIdentity,
  authority: Authority,
  membershipSnapshot: DocumentSnapshot,
): boolean {
  if (!snapshot.exists) return false;
  const data = snapshot.data() ?? {};
  const membership = membershipSnapshot.data() ?? {};
  const profileTeamId = typeof data.teamId === "string" ? data.teamId : null;
  const membershipTeamId = typeof membership.teamId === "string" ? membership.teamId : null;
  const profileDivisionId = typeof data.divisionId === "string" ? data.divisionId : null;
  const membershipDivisionId = typeof membership.divisionId === "string" ? membership.divisionId : null;
  return data.authorizationSchemaVersion === AUTHORIZATION_SCHEMA_VERSION
    && data.associationId === authority.associationId
    && data.role === authority.role
    && profileTeamId === membershipTeamId
    && profileDivisionId === membershipDivisionId
    && typeof data.email === "string"
    && data.email.toLowerCase() === caller.email;
}

export async function provisionFanProfileHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const displayName = requireText(data, "displayName", 120);
  const db = admin.firestore();
  const associationRef = db.doc(`associations/${PUBLIC_ASSOCIATION_ID}`);
  const userRef = db.doc(`users/${caller.uid}`);
  const membershipRef = db.doc(`memberships/${caller.uid}`);

  return db.runTransaction(async (transaction) => {
    const [associationSnap, userSnap, membershipSnap] = await Promise.all([
      transaction.get(associationRef),
      transaction.get(userRef),
      transaction.get(membershipRef),
    ]);
    if (!associationSnap.exists) {
      throw new HttpsError("failed-precondition", "Public signup is not configured for this association.");
    }
    const now = FieldValue.serverTimestamp();
    if (userSnap.exists && membershipSnap.exists) {
      const authority = validMembershipAuthority(membershipSnap);
      if (!authority || !userMatchesAuthority(userSnap, caller, authority, membershipSnap)) {
        throw new HttpsError("failed-precondition", "Account authorization records require administrator recovery.");
      }
      return {created: false, repaired: false, role: authority.role, associationId: authority.associationId};
    }
    if (userSnap.exists) {
      throw new HttpsError("failed-precondition", "Account authorization records require administrator recovery.");
    }
    if (membershipSnap.exists) {
      const authority = validMembershipAuthority(membershipSnap);
      if (!authority) {
        throw new HttpsError("failed-precondition", "Account authorization records require administrator recovery.");
      }
      transaction.create(userRef, {
        email: caller.email,
        displayName,
        phone: null,
        associationId: authority.associationId,
        teamId: membershipSnap.get("teamId") ?? null,
        role: authority.role,
        divisionId: membershipSnap.get("divisionId") ?? null,
        fcmTokens: [],
        notificationPrefs: {ackReminders: true, statReminders: true, newPosts: true},
        authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
        createdAt: now,
        updatedAt: now,
      });
      return {created: false, repaired: true, role: authority.role, associationId: authority.associationId};
    }

    transaction.create(userRef, {
      email: caller.email,
      displayName,
      phone: null,
      associationId: PUBLIC_ASSOCIATION_ID,
      teamId: null,
      role: "fan",
      divisionId: null,
      fcmTokens: [],
      notificationPrefs: {ackReminders: true, statReminders: true, newPosts: true},
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      createdAt: now,
      updatedAt: now,
    });
    transaction.create(membershipRef, {
      associationId: PUBLIC_ASSOCIATION_ID,
      role: "fan",
      capabilities: capabilitiesForRole("fan"),
      status: "active",
      teamId: null,
      divisionId: null,
      seasonId: associationSnap.get("currentSeasonId") ?? null,
      competitionId: null,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      createdAt: now,
      updatedAt: now,
    });
    return {created: true, repaired: false, role: "fan", associationId: PUBLIC_ASSOCIATION_ID};
  });
}

export async function inspectPrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const token = normalizeToken(data.code);
  const inviteId = inviteIdForToken(token);
  const inviteSnap = await admin.firestore().doc(`inviteCodes/${inviteId}`).get();
  const now = Timestamp.now();
  if (!inviteSnap.exists || !inviteIsActive(inviteSnap.data() as InviteData, inviteId, now)) {
    throw new HttpsError("not-found", "Invite code is invalid, expired, revoked, or already used.");
  }
  const invite = requireInviteShape(inviteSnap.data() as InviteData, inviteId);
  return {
    inviteId,
    role: invite.role,
    associationId: invite.associationId,
    teamId: invite.teamId,
    expiresAt: timestampOrNull((inviteSnap.data() as InviteData).expiresAt)?.toDate().toISOString(),
  };
}

export async function redeemPrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const token = normalizeToken(data.code);
  const inviteId = inviteIdForToken(token);
  const displayName = requireText(data, "displayName", 120);
  const operationId = requireOperationId(data);
  const fingerprint = requestFingerprint({inviteId, displayName, email: caller.email});
  const db = admin.firestore();
  const inviteRef = db.doc(`inviteCodes/${inviteId}`);
  const userRef = db.doc(`users/${caller.uid}`);
  const membershipRef = db.doc(`memberships/${caller.uid}`);
  const operationReceiptId = receiptId(caller.uid, "invite.redeem", operationId);
  const receiptRef = db.doc(`authorizationOperationReceipts/${operationReceiptId}`);
  const auditRef = db.doc(`authorizationAudit/redeem_${operationReceiptId}`);

  return db.runTransaction(async (transaction) => {
    const receiptSnap = await transaction.get(receiptRef);
    if (receiptSnap.exists) {
      const receipt = receiptSnap.data() ?? {};
      if (
        receipt.actorId !== caller.uid
        || receipt.operation !== "invite.redeem"
        || receipt.requestFingerprint !== fingerprint
        || receipt.inviteId !== inviteId
      ) {
        throw new HttpsError("failed-precondition", "Operation identifier was already used for a different request.");
      }
      return receipt.result;
    }

    const [inviteSnap, userSnap, membershipSnap] = await Promise.all([
      transaction.get(inviteRef),
      transaction.get(userRef),
      transaction.get(membershipRef),
    ]);
    if (!inviteSnap.exists || !inviteIsActive(inviteSnap.data() as InviteData, inviteId, Timestamp.now())) {
      throw new HttpsError("failed-precondition", "Invite code is invalid, expired, revoked, or already used.");
    }
    if (userSnap.exists || membershipSnap.exists) {
      throw new HttpsError("already-exists", "This account already has authorization records.");
    }

    const invite = requireInviteShape(inviteSnap.data() as InviteData, inviteId);
    const associationSnap = await transaction.get(db.doc(`associations/${invite.associationId}`));
    if (!associationSnap.exists) {
      throw new HttpsError("failed-precondition", "Invite association no longer exists.");
    }
    let resolvedDivisionId = invite.divisionId;
    if (invite.teamId) {
      const teamSnap = await transaction.get(db.doc(`associations/${invite.associationId}/teams/${invite.teamId}`));
      if (!teamSnap.exists) {
        throw new HttpsError("failed-precondition", "Invite team no longer exists.");
      }
      resolvedDivisionId = typeof teamSnap.get("divisionId") === "string" ? teamSnap.get("divisionId") : null;
    }
    await requireDivisionAcceptsNewReferences(
      transaction,
      invite.associationId,
      resolvedDivisionId,
    );

    const serverNow = FieldValue.serverTimestamp();
    const result = {role: invite.role, associationId: invite.associationId, teamId: invite.teamId};
    transaction.create(userRef, {
      email: caller.email,
      displayName,
      phone: null,
      associationId: invite.associationId,
      teamId: invite.teamId,
      role: invite.role,
      divisionId: resolvedDivisionId,
      fcmTokens: [],
      notificationPrefs: {ackReminders: true, statReminders: true, newPosts: true},
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      createdAt: serverNow,
      updatedAt: serverNow,
    });
    transaction.create(membershipRef, {
      associationId: invite.associationId,
      role: invite.role,
      capabilities: capabilitiesForRole(invite.role),
      status: "active",
      teamId: invite.teamId,
      divisionId: resolvedDivisionId,
      seasonId: invite.seasonId ?? associationSnap.get("currentSeasonId") ?? null,
      competitionId: null,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      source: "privilegedInvite",
      createdAt: serverNow,
      updatedAt: serverNow,
    });
    transaction.update(inviteRef, {
      status: "redeemed",
      usesRemaining: 0,
      redeemedBy: caller.uid,
      redeemedAt: serverNow,
    });
    transaction.create(receiptRef, {
      actorId: caller.uid,
      operation: "invite.redeem",
      associationId: invite.associationId,
      inviteId,
      requestFingerprint: fingerprint,
      result,
      createdAt: serverNow,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
    transaction.create(auditRef, {
      action: "invite.redeemed",
      actorId: caller.uid,
      subjectId: caller.uid,
      associationId: invite.associationId,
      inviteId,
      role: invite.role,
      teamId: invite.teamId,
      operationReceiptId,
      createdAt: serverNow,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
    return result;
  });
}

export async function createPrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const operationId = requireOperationId(data);
  if (!isRole(data.role)) {
    throw new HttpsError("invalid-argument", "A valid role is required.");
  }
  const role = data.role;
  const teamId = requireDocumentId(optionalText(data, "teamId", 160), "teamId");
  if (role === "rep" && !teamId) {
    throw new HttpsError("invalid-argument", "Representative invites require a team.");
  }
  const requestedDays = data.daysValid;
  if (typeof requestedDays !== "number" || !Number.isInteger(requestedDays) || requestedDays < 1 || requestedDays > 30) {
    throw new HttpsError("invalid-argument", "daysValid must be an integer from 1 to 30.");
  }

  const token = deriveToken(caller.uid, operationId);
  const inviteId = inviteIdForToken(token);
  const fingerprint = requestFingerprint({role, teamId, daysValid: requestedDays});
  const operationReceiptId = receiptId(caller.uid, "invite.create", operationId);
  const db = admin.firestore();
  const inviteRef = db.doc(`inviteCodes/${inviteId}`);
  const receiptRef = db.doc(`authorizationOperationReceipts/${operationReceiptId}`);
  const auditRef = db.doc(`authorizationAudit/create_${operationReceiptId}`);
  const expiresAt = Timestamp.fromMillis(Date.now() + requestedDays * 24 * 60 * 60 * 1000);

  const result = await db.runTransaction(async (transaction) => {
    const authority = await getAuthorityInTransaction(transaction, caller.uid, capabilities.invitesManage);
    const receiptSnap = await transaction.get(receiptRef);
    if (receiptSnap.exists) {
      const receipt = receiptSnap.data() ?? {};
      if (
        receipt.actorId !== caller.uid
        || receipt.operation !== "invite.create"
        || receipt.requestFingerprint !== fingerprint
        || receipt.inviteId !== inviteId
        || receipt.associationId !== authority.associationId
      ) {
        throw new HttpsError("failed-precondition", "Operation identifier was already used for a different request.");
      }
      return receipt.result as Record<string, unknown>;
    }

    if (!canGrantRole(authority.role, role)) {
      throw new HttpsError("permission-denied", "The requested role is outside your grant authority.");
    }
    const associationSnap = await transaction.get(db.doc(`associations/${authority.associationId}`));
    if (!associationSnap.exists) {
      throw new HttpsError("failed-precondition", "Your association no longer exists.");
    }
    const currentSeasonId = associationSnap.get("currentSeasonId");
    if (typeof currentSeasonId !== "string" || !/^[A-Za-z0-9_-]+$/.test(currentSeasonId)) {
      throw new HttpsError("failed-precondition", "Your association does not have a valid current season.");
    }
    let divisionId: string | null = null;
    if (teamId) {
      const teamSnap = await transaction.get(db.doc(`associations/${authority.associationId}/teams/${teamId}`));
      if (!teamSnap.exists) {
        throw new HttpsError("invalid-argument", "Team does not exist in your association.");
      }
      const teamStatus = teamSnap.get("status");
      if (teamSnap.get("seasonId") !== currentSeasonId ||
          (teamStatus !== undefined && teamStatus !== "active") || teamSnap.get("active") === false) {
        throw new HttpsError("failed-precondition", "Team is not active in your association's current season.");
      }
      divisionId = typeof teamSnap.get("divisionId") === "string" ? teamSnap.get("divisionId") : null;
    }
    await requireDivisionAcceptsNewReferences(
      transaction,
      authority.associationId,
      divisionId,
    );
    const serverNow = FieldValue.serverTimestamp();
    const semanticResult = {
      inviteId,
      associationId: authority.associationId,
      teamId,
      role,
      usesRemaining: 1,
      status: "active",
      expiresAt: expiresAt.toDate().toISOString(),
    };
    transaction.create(inviteRef, {
      inviteId,
      credentialVersion: INVITE_CREDENTIAL_VERSION,
      associationId: authority.associationId,
      seasonId: currentSeasonId,
      competitionId: null,
      teamId,
      divisionId,
      role,
      capabilities: capabilitiesForRole(role),
      status: "active",
      usesRemaining: 1,
      createdBy: caller.uid,
      createdAt: serverNow,
      expiresAt,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
    transaction.create(receiptRef, {
      actorId: caller.uid,
      operation: "invite.create",
      associationId: authority.associationId,
      inviteId,
      requestFingerprint: fingerprint,
      result: semanticResult,
      createdAt: serverNow,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
    transaction.create(auditRef, {
      action: "invite.created",
      actorId: caller.uid,
      associationId: authority.associationId,
      inviteId,
      role,
      teamId,
      operationReceiptId,
      createdAt: serverNow,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
    return semanticResult;
  });
  return {...result, code: token};
}

export async function revokePrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const inviteId = requireText(data, "inviteId", 67);
  if (!inviteIdPattern.test(inviteId)) {
    throw new HttpsError("invalid-argument", "Invite identifier is invalid.");
  }
  const db = admin.firestore();
  const ref = db.doc(`inviteCodes/${inviteId}`);
  await db.runTransaction(async (transaction) => {
    const authority = await getAuthorityInTransaction(transaction, caller.uid, capabilities.invitesManage);
    const snap = await transaction.get(ref);
    if (!snap.exists || snap.get("associationId") !== authority.associationId) {
      throw new HttpsError("not-found", "Invite was not found in your association.");
    }
    if (!inviteIsActive(snap.data() as InviteData, inviteId, Timestamp.now())) {
      throw new HttpsError("failed-precondition", "Only an active invite can be revoked.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.update(ref, {status: "revoked", revokedBy: caller.uid, revokedAt: now});
    transaction.create(db.collection("authorizationAudit").doc(), {
      action: "invite.revoked",
      actorId: caller.uid,
      associationId: authority.associationId,
      inviteId,
      createdAt: now,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
  });
  return {revoked: true};
}

export async function setMemberRoleHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const targetUid = requireText(data, "userId", 128);
  if (!isRole(data.role) || data.role === "superAdmin") {
    throw new HttpsError("permission-denied", "The requested role cannot be assigned here.");
  }
  const newRole = data.role;
  if (targetUid === caller.uid) {
    throw new HttpsError("failed-precondition", "You cannot change your own role.");
  }
  const db = admin.firestore();
  const userRef = db.doc(`users/${targetUid}`);
  const membershipRef = db.doc(`memberships/${targetUid}`);
  await db.runTransaction(async (transaction) => {
    const authority = await getAuthorityInTransaction(transaction, caller.uid, capabilities.membersManage);
    const [userSnap, membershipSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(membershipRef),
    ]);
    if (!userSnap.exists || !membershipSnap.exists) {
      throw new HttpsError("not-found", "Complete user authorization records were not found in your association.");
    }
    if (
      userSnap.get("associationId") !== authority.associationId
      || membershipSnap.get("associationId") !== authority.associationId
      || userSnap.get("authorizationSchemaVersion") !== AUTHORIZATION_SCHEMA_VERSION
      || membershipSnap.get("authorizationSchemaVersion") !== AUTHORIZATION_SCHEMA_VERSION
      || membershipSnap.get("status") !== "active"
      || !isRole(membershipSnap.get("role"))
      || userSnap.get("role") !== membershipSnap.get("role")
      || (userSnap.get("teamId") ?? null) !== (membershipSnap.get("teamId") ?? null)
      || (userSnap.get("divisionId") ?? null) !== (membershipSnap.get("divisionId") ?? null)
      || !Array.isArray(membershipSnap.get("capabilities"))
      || JSON.stringify([...membershipSnap.get("capabilities")].sort())
        !== JSON.stringify(capabilitiesForRole(membershipSnap.get("role")).sort())
    ) {
      throw new HttpsError("failed-precondition", "User authorization records are inactive or have conflicting scope.");
    }
    if (membershipSnap.get("role") === "superAdmin") {
      throw new HttpsError("failed-precondition", "Super-admin changes require the break-glass owner workflow.");
    }
    const teamId = membershipSnap.get("teamId") ?? null;
    if (newRole === "rep" && !teamId) {
      throw new HttpsError("failed-precondition", "Assign a team before granting the representative role.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.update(userRef, {role: newRole, authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION, updatedAt: now});
    transaction.update(membershipRef, {
      role: newRole,
      capabilities: capabilitiesForRole(newRole),
      updatedAt: now,
    });
    transaction.create(db.collection("authorizationAudit").doc(), {
      action: "membership.role.changed",
      actorId: caller.uid,
      subjectId: targetUid,
      associationId: authority.associationId,
      previousRole: membershipSnap.get("role"),
      role: newRole,
      createdAt: now,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
  });
  return {updated: true, role: newRole};
}

export const provisionFanProfile = onCall(provisionFanProfileHandler);
export const inspectPrivilegedInvite = onCall(inspectPrivilegedInviteHandler);
export const redeemPrivilegedInvite = onCall(redeemPrivilegedInviteHandler);
export const createPrivilegedInvite = process.env.FUNCTIONS_EMULATOR === "true"
  ? onCall(createPrivilegedInviteHandler)
  : onCall({secrets: [INVITE_TOKEN_HMAC_KEY_V1]}, createPrivilegedInviteHandler);
export const revokePrivilegedInvite = onCall(revokePrivilegedInviteHandler);
export const setMemberRole = onCall(setMemberRoleHandler);
