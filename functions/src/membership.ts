import { randomBytes } from "crypto";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  AUTHORIZATION_SCHEMA_VERSION,
  PUBLIC_ASSOCIATION_ID,
  Role,
  canGrantRole,
  capabilities,
  capabilitiesForRole,
  isRole,
} from "./authorization";

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
  associationId?: unknown;
  teamId?: unknown;
  divisionId?: unknown;
  seasonId?: unknown;
  role?: unknown;
  capabilities?: unknown;
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

function normalizeCode(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Invite code is required.");
  }
  const code = value.trim().toUpperCase();
  // Generated codes use an ambiguity-free alphabet. The wider parser keeps
  // already-issued legacy codes redeemable without accepting punctuation.
  if (!/^[A-Z0-9-]{6,32}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Invite code format is invalid.");
  }
  return code;
}

function generateCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(10);
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

function timestampOrNull(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function inviteIsActive(invite: InviteData, now: Timestamp): boolean {
  const expiresAt = timestampOrNull(invite.expiresAt);
  return invite.authorizationSchemaVersion === AUTHORIZATION_SCHEMA_VERSION
    && invite.status === "active"
    && invite.usesRemaining === 1
    && expiresAt !== null
    && expiresAt.toMillis() > now.toMillis()
    && !invite.revokedAt
    && !invite.redeemedBy;
}

function requireInviteShape(invite: InviteData): {
  associationId: string;
  teamId: string | null;
  divisionId: string | null;
  seasonId: string | null;
  role: Role;
} {
  if (
    invite.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
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
    divisionId: typeof invite.divisionId === "string" && invite.divisionId.length > 0 ? invite.divisionId : null,
    seasonId: typeof invite.seasonId === "string" && invite.seasonId.length > 0 ? invite.seasonId : null,
    role: invite.role,
  };
}

async function getAuthority(uid: string): Promise<Authority> {
  const db = admin.firestore();
  const membershipSnap = await db.doc(`memberships/${uid}`).get();

  if (membershipSnap.exists) {
    const membership = membershipSnap.data() ?? {};
    if (
      membership.authorizationSchemaVersion !== AUTHORIZATION_SCHEMA_VERSION
      || membership.status !== "active"
      || !isRole(membership.role)
      || typeof membership.associationId !== "string"
    ) {
      throw new HttpsError("permission-denied", "Active membership is required.");
    }
    return {
      associationId: membership.associationId,
      role: membership.role,
      capabilities: Array.isArray(membership.capabilities) ? membership.capabilities.filter((v): v is string => typeof v === "string") : [],
    };
  }

  throw new HttpsError("permission-denied", "Active membership is required.");
}

function requireCapability(authority: Authority, capability: string): void {
  if (!authority.capabilities.includes(capability)) {
    throw new HttpsError("permission-denied", "You do not have permission to complete this action.");
  }
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
    if (userSnap.exists || membershipSnap.exists) {
      return {created: false};
    }

    const now = FieldValue.serverTimestamp();
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
    return {created: true, role: "fan", associationId: PUBLIC_ASSOCIATION_ID};
  });
}

export async function inspectPrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const code = normalizeCode(data.code);
  const inviteSnap = await admin.firestore().doc(`inviteCodes/${code}`).get();
  const now = Timestamp.now();
  if (!inviteSnap.exists || !inviteIsActive(inviteSnap.data() as InviteData, now)) {
    throw new HttpsError("not-found", "Invite code is invalid, expired, revoked, or already used.");
  }
  const invite = requireInviteShape(inviteSnap.data() as InviteData);
  return {
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
  const code = normalizeCode(data.code);
  const displayName = requireText(data, "displayName", 120);
  const db = admin.firestore();
  const inviteRef = db.doc(`inviteCodes/${code}`);
  const userRef = db.doc(`users/${caller.uid}`);
  const membershipRef = db.doc(`memberships/${caller.uid}`);
  const auditRef = db.collection("authorizationAudit").doc();

  return db.runTransaction(async (transaction) => {
    const [inviteSnap, userSnap, membershipSnap] = await Promise.all([
      transaction.get(inviteRef),
      transaction.get(userRef),
      transaction.get(membershipRef),
    ]);
    const now = Timestamp.now();
    if (!inviteSnap.exists || !inviteIsActive(inviteSnap.data() as InviteData, now)) {
      throw new HttpsError("failed-precondition", "Invite code is invalid, expired, revoked, or already used.");
    }
    if (membershipSnap.exists || (userSnap.exists && userSnap.get("role") !== "fan")) {
      throw new HttpsError("already-exists", "This account already has a membership.");
    }

    const invite = requireInviteShape(inviteSnap.data() as InviteData);
    const associationRef = db.doc(`associations/${invite.associationId}`);
    const associationSnap = await transaction.get(associationRef);
    if (!associationSnap.exists) {
      throw new HttpsError("failed-precondition", "Invite association no longer exists.");
    }
    let resolvedDivisionId = invite.divisionId;
    if (invite.teamId) {
      const teamSnap = await transaction.get(db.doc(`associations/${invite.associationId}/teams/${invite.teamId}`));
      if (!teamSnap.exists) {
        throw new HttpsError("failed-precondition", "Invite team no longer exists.");
      }
      resolvedDivisionId = typeof teamSnap.get("divisionId") === "string"
        ? teamSnap.get("divisionId")
        : null;
    }

    const serverNow = FieldValue.serverTimestamp();
    const memberCapabilities = capabilitiesForRole(invite.role);
    transaction.set(userRef, {
      email: caller.email,
      displayName,
      phone: userSnap.exists ? userSnap.get("phone") ?? null : null,
      associationId: invite.associationId,
      teamId: invite.teamId,
      role: invite.role,
      divisionId: resolvedDivisionId,
      fcmTokens: userSnap.exists ? userSnap.get("fcmTokens") ?? [] : [],
      notificationPrefs: userSnap.exists ? userSnap.get("notificationPrefs") ?? {ackReminders: true, statReminders: true, newPosts: true} : {ackReminders: true, statReminders: true, newPosts: true},
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      updatedAt: serverNow,
      ...(userSnap.exists ? {} : {createdAt: serverNow}),
    });
    transaction.create(membershipRef, {
      associationId: invite.associationId,
      role: invite.role,
      capabilities: memberCapabilities,
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
    transaction.create(auditRef, {
      action: "invite.redeemed",
      actorId: caller.uid,
      subjectId: caller.uid,
      associationId: invite.associationId,
      inviteCode: code,
      role: invite.role,
      teamId: invite.teamId,
      createdAt: serverNow,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });

    return {role: invite.role, associationId: invite.associationId, teamId: invite.teamId};
  });
}

export async function createPrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const authority = await getAuthority(caller.uid);
  requireCapability(authority, capabilities.invitesManage);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  if (!isRole(data.role) || !canGrantRole(authority.role, data.role)) {
    throw new HttpsError("permission-denied", "The requested role is outside your grant authority.");
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

  const db = admin.firestore();
  const associationSnap = await db.doc(`associations/${authority.associationId}`).get();
  if (!associationSnap.exists) {
    throw new HttpsError("failed-precondition", "Your association no longer exists.");
  }
  let divisionId: string | null = null;
  if (teamId) {
    const teamSnap = await db.doc(`associations/${authority.associationId}/teams/${teamId}`).get();
    if (!teamSnap.exists) {
      throw new HttpsError("invalid-argument", "Team does not exist in your association.");
    }
    divisionId = typeof teamSnap.get("divisionId") === "string" ? teamSnap.get("divisionId") : null;
  }

  const expiresAt = Timestamp.fromMillis(Date.now() + requestedDays * 24 * 60 * 60 * 1000);
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = generateCode();
    const inviteRef = db.doc(`inviteCodes/${code}`);
    try {
      const auditRef = db.collection("authorizationAudit").doc();
      const batch = db.batch();
      batch.create(inviteRef, {
        associationId: authority.associationId,
        seasonId: associationSnap.get("currentSeasonId") ?? null,
        competitionId: null,
        teamId,
        divisionId,
        role,
        capabilities: capabilitiesForRole(role),
        status: "active",
        usesRemaining: 1,
        createdBy: caller.uid,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt,
        authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      });
      batch.create(auditRef, {
        action: "invite.created",
        actorId: caller.uid,
        associationId: authority.associationId,
        inviteCode: code,
        role,
        teamId,
        createdAt: FieldValue.serverTimestamp(),
        authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      });
      await batch.commit();
      return {code, associationId: authority.associationId, teamId, role, usesRemaining: 1, expiresAt: expiresAt.toDate().toISOString()};
    } catch (error) {
      if ((error as {code?: number}).code !== 6 || attempt === 4) throw error;
    }
  }
  throw new HttpsError("internal", "Could not create a unique invite code.");
}

export async function revokePrivilegedInviteHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const authority = await getAuthority(caller.uid);
  requireCapability(authority, capabilities.invitesManage);
  const data = requireObject(request.data);
  requireAuthorizationSchema(data);
  const code = normalizeCode(data.code);
  const db = admin.firestore();
  const ref = db.doc(`inviteCodes/${code}`);
  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists || snap.get("associationId") !== authority.associationId) {
      throw new HttpsError("not-found", "Invite code was not found in your association.");
    }
    if (!inviteIsActive(snap.data() as InviteData, Timestamp.now())) {
      throw new HttpsError("failed-precondition", "Only an active invite can be revoked.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.update(ref, {status: "revoked", revokedBy: caller.uid, revokedAt: now});
    transaction.create(db.collection("authorizationAudit").doc(), {
      action: "invite.revoked",
      actorId: caller.uid,
      associationId: authority.associationId,
      inviteCode: code,
      createdAt: now,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
  });
  return {revoked: true};
}

export async function setMemberRoleHandler(request: CallableRequest<unknown>) {
  const caller = requireCaller(request);
  const authority = await getAuthority(caller.uid);
  requireCapability(authority, capabilities.membersManage);
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
    const [userSnap, membershipSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(membershipRef),
    ]);
    if (!userSnap.exists || userSnap.get("associationId") !== authority.associationId) {
      throw new HttpsError("not-found", "User was not found in your association.");
    }
    if (membershipSnap.exists && membershipSnap.get("associationId") !== authority.associationId) {
      throw new HttpsError("failed-precondition", "User authorization records have conflicting association scope.");
    }
    if (userSnap.get("role") === "superAdmin") {
      throw new HttpsError("failed-precondition", "Super-admin changes require the break-glass owner workflow.");
    }
    const teamId = membershipSnap.exists ? membershipSnap.get("teamId") ?? null : userSnap.get("teamId") ?? null;
    if (newRole === "rep" && !teamId) {
      throw new HttpsError("failed-precondition", "Assign a team before granting the representative role.");
    }
    const now = FieldValue.serverTimestamp();
    transaction.update(userRef, {role: newRole, authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION, updatedAt: now});
    transaction.set(membershipRef, {
      associationId: authority.associationId,
      role: newRole,
      capabilities: capabilitiesForRole(newRole),
      status: "active",
      teamId,
      divisionId: userSnap.get("divisionId") ?? null,
      seasonId: membershipSnap.exists ? membershipSnap.get("seasonId") ?? null : null,
      competitionId: membershipSnap.exists ? membershipSnap.get("competitionId") ?? null : null,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
      updatedAt: now,
      ...(membershipSnap.exists ? {} : {createdAt: now, source: "adminRoleChange"}),
    }, {merge: true});
    transaction.create(db.collection("authorizationAudit").doc(), {
      action: "member.roleChanged",
      actorId: caller.uid,
      subjectId: targetUid,
      associationId: authority.associationId,
      previousRole: userSnap.get("role") ?? null,
      role: newRole,
      createdAt: now,
      authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
    });
  });
  logger.info("Member role changed", {actorId: caller.uid, subjectId: targetUid, associationId: authority.associationId, role: newRole});
  return {updated: true, role: newRole};
}

export const provisionFanProfile = onCall(provisionFanProfileHandler);
export const inspectPrivilegedInvite = onCall(inspectPrivilegedInviteHandler);
export const redeemPrivilegedInvite = onCall(redeemPrivilegedInviteHandler);
export const createPrivilegedInvite = onCall(createPrivilegedInviteHandler);
export const revokePrivilegedInvite = onCall(revokePrivilegedInviteHandler);
export const setMemberRole = onCall(setMemberRoleHandler);
