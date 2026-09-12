import * as admin from "firebase-admin";
import {DocumentSnapshot, FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {capabilities} from "./authorization";
import {
  Authority,
  Caller,
  LEAGUE_CALLABLE_OPTIONS,
  WorkflowControl,
  authorityInTransaction,
  caller,
  consumeInvocationQuota,
  counter,
  exactKeys,
  hash,
  id,
  object,
  operationReceiptRef,
  receiptReplay,
  requireActorWorkflowBinding,
  requireCapability,
  requireWorkflowReady,
  saveReceipt,
  schema,
  text,
  workflowRef,
} from "./league_operations";

const SCHEMA_VERSION = 1;
const LEAGUE_TIMEZONE = "America/Jamaica";
type Json = Record<string, unknown>;
type SeasonState = "prepared" | "active" | "inactive" | "archived";

function dateOnly(value: unknown, key: string, stored = false): string {
  const code = stored ? "failed-precondition" : "invalid-argument";
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpsError(code, `${key} must be a calendar date in YYYY-MM-DD form.`);
  }
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) {
    throw new HttpsError(code, `${key} must be a real calendar date.`);
  }
  return value;
}

function seasonStatus(value: unknown): SeasonState {
  if (value !== "prepared" && value !== "active" && value !== "inactive" && value !== "archived") {
    throw new HttpsError("failed-precondition", "The season has an unsupported lifecycle state.");
  }
  return value;
}

function storedSeasonVersion(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1 ||
      (value as number) >= Number.MAX_SAFE_INTEGER) {
    throw new HttpsError("failed-precondition", "The stored season version is malformed.");
  }
  return value as number;
}

function requireSeasonLifecycleAuthority(authority: Authority, workflow: WorkflowControl): void {
  if (workflow.authorityMode !== "legacyV1" || authority.schemaVersion !== 1) {
    throw new HttpsError(
      "failed-precondition",
      "Season lifecycle remains closed until a v2 season-management capability is adopted.",
    );
  }
  requireCapability(authority, capabilities.associationManage);
}

async function context(
  transaction: Transaction,
  db: Firestore,
  actor: Caller,
): Promise<{
  authority: Authority;
  workflow: WorkflowControl;
  control: DocumentSnapshot;
  association: DocumentSnapshot;
}> {
  const authority = await authorityInTransaction(transaction, db, actor);
  const [control, association] = await Promise.all([
    transaction.get(workflowRef(db, authority.associationId)),
    transaction.get(db.doc(`associations/${authority.associationId}`)),
  ]);
  const workflow = requireWorkflowReady(control, authority.associationId, "seasonLifecycle");
  await requireActorWorkflowBinding(transaction, db, actor, authority, workflow);
  requireSeasonLifecycleAuthority(authority, workflow);
  if (!association.exists || association.get("currentSeasonId") !== workflow.seasonId) {
    throw new HttpsError("failed-precondition", "The authoritative current-season pointers do not agree.");
  }
  return {authority, workflow, control, association};
}

function expectation(authority: Authority, operation: string, operationId: string) {
  return {
    actorId: authority.uid,
    associationId: authority.associationId,
    operation,
    operationId,
  };
}

function seasonRef(db: Firestore, associationId: string, seasonId: string) {
  return db.doc(`associations/${associationId}/seasons/${seasonId}`);
}

function stableSeasonId(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

export async function seasonPrepareHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, ["schemaVersion", "operationId", "seasonId", "name", "startDate", "endDate"]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const seasonId = id(data.seasonId, "seasonId");
  const name = text(data.name, "name", 120)!;
  if (stableSeasonId(name) !== seasonId) {
    throw new HttpsError("invalid-argument", "seasonId must be the stable ID derived from the season name.");
  }
  const startDate = dateOnly(data.startDate, "startDate");
  const endDate = dateOnly(data.endDate, "endDate");
  if (startDate > endDate) {
    throw new HttpsError("invalid-argument", "The season start date must be on or before the end date.");
  }
  const fingerprint = hash({schemaVersion: SCHEMA_VERSION, operationId, seasonId, name, startDate, endDate});
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "season.prepare", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;

  return db.runTransaction(async (transaction) => {
    const operationContext = await context(transaction, db, actor);
    const receiptRef = operationReceiptRef(db, actor.uid, "season.prepare", operationId);
    const targetRef = seasonRef(db, operationContext.authority.associationId, seasonId);
    const [receipt, existing] = await Promise.all([
      transaction.get(receiptRef),
      transaction.get(targetRef),
    ]);
    const replay = receiptReplay(
      receipt,
      fingerprint,
      expectation(operationContext.authority, "season.prepare", operationId),
    );
    if (replay) return replay;
    if (existing.exists) {
      throw new HttpsError("already-exists", "That stable season ID already exists. No season was overwritten.");
    }
    transaction.create(targetRef, {
      schemaVersion: SCHEMA_VERSION,
      associationId: operationContext.authority.associationId,
      seasonId,
      name,
      startDate,
      endDate,
      timezone: LEAGUE_TIMEZONE,
      status: "prepared",
      isActive: false,
      version: 1,
      preparedBy: actor.uid,
      preparedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const result: Json = {
      operationId,
      status: "prepared",
      seasonId,
      seasonVersion: 1,
      currentSeasonId: operationContext.workflow.seasonId,
    };
    saveReceipt(transaction, receiptRef, {
      actorId: actor.uid,
      associationId: operationContext.authority.associationId,
      operation: "season.prepare",
      operationId,
      requestFingerprint: fingerprint,
      result,
    });
    return result;
  });
}

export async function seasonActivateHandler(request: CallableRequest<unknown>) {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, [
    "schemaVersion", "operationId", "seasonId", "expectedSeasonVersion", "expectedCurrentSeasonId",
  ]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const seasonId = id(data.seasonId, "seasonId");
  const expectedSeasonVersion = counter(data.expectedSeasonVersion, "expectedSeasonVersion", false);
  const expectedCurrentSeasonId = id(data.expectedCurrentSeasonId, "expectedCurrentSeasonId");
  if (seasonId === expectedCurrentSeasonId) {
    throw new HttpsError("failed-precondition", "The requested season is already current.");
  }
  const fingerprint = hash({
    schemaVersion: SCHEMA_VERSION,
    operationId,
    seasonId,
    expectedSeasonVersion,
    expectedCurrentSeasonId,
  });
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {
    operation: "season.activate", operationId, fingerprint,
  });
  if (earlyReplay) return earlyReplay;

  return db.runTransaction(async (transaction) => {
    const operationContext = await context(transaction, db, actor);
    const receiptRef = operationReceiptRef(db, actor.uid, "season.activate", operationId);
    const targetRef = seasonRef(db, operationContext.authority.associationId, seasonId);
    const currentRef = seasonRef(db, operationContext.authority.associationId, expectedCurrentSeasonId);
    const [receipt, target, current] = await Promise.all([
      transaction.get(receiptRef),
      transaction.get(targetRef),
      transaction.get(currentRef),
    ]);
    const replay = receiptReplay(
      receipt,
      fingerprint,
      expectation(operationContext.authority, "season.activate", operationId),
    );
    if (replay) return replay;
    if (operationContext.workflow.seasonId !== expectedCurrentSeasonId ||
        operationContext.association.get("currentSeasonId") !== expectedCurrentSeasonId) {
      throw new HttpsError("aborted", "The current season changed. Reload before activating another season.");
    }
    if (!target.exists || target.get("schemaVersion") !== SCHEMA_VERSION ||
        target.get("associationId") !== operationContext.authority.associationId || target.get("seasonId") !== seasonId ||
        seasonStatus(target.get("status")) !== "prepared" || target.get("isActive") !== false ||
        target.get("timezone") !== LEAGUE_TIMEZONE ||
        dateOnly(target.get("startDate"), "stored startDate", true) >
          dateOnly(target.get("endDate"), "stored endDate", true)) {
      throw new HttpsError("failed-precondition", "Only an eligible prepared season can be activated.");
    }
    const targetVersion = storedSeasonVersion(target.get("version"));
    if (targetVersion !== expectedSeasonVersion) {
      throw new HttpsError("aborted", "The prepared season changed. Reload before activating it.");
    }
    const currentStatus = current.exists ? current.get("status") : undefined;
    const currentIsActive = current.exists ? current.get("isActive") : undefined;
    const legacyCurrent = current.exists && currentStatus === undefined && currentIsActive === true;
    const activeWithoutLegacyFlag = current.exists && currentStatus === "active" &&
      (currentIsActive === undefined || currentIsActive === true);
    const currentAssociationId = current.exists ? current.get("associationId") : undefined;
    const storedCurrentSeasonId = current.exists ? current.get("seasonId") : undefined;
    if (!current.exists || (!activeWithoutLegacyFlag && !legacyCurrent) ||
        (currentAssociationId !== undefined && currentAssociationId !== operationContext.authority.associationId) ||
        (storedCurrentSeasonId !== undefined && storedCurrentSeasonId !== expectedCurrentSeasonId)) {
      throw new HttpsError("failed-precondition", "The current season record is not eligible for a safe handoff.");
    }
    const currentVersion = current.get("version");
    if (currentVersion !== undefined && (!Number.isSafeInteger(currentVersion) || currentVersion < 0 ||
        currentVersion >= Number.MAX_SAFE_INTEGER)) {
      throw new HttpsError("failed-precondition", "The current season version is malformed.");
    }
    transaction.update(currentRef, {
      status: "inactive",
      isActive: false,
      version: (currentVersion ?? 0) + 1,
      deactivatedBy: actor.uid,
      deactivatedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(targetRef, {
      status: "active",
      isActive: true,
      version: targetVersion + 1,
      activatedBy: actor.uid,
      activatedAt: FieldValue.serverTimestamp(),
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(operationContext.association.ref, {
      currentSeasonId: seasonId,
      seasonUpdatedBy: actor.uid,
      seasonUpdatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(operationContext.control.ref, {
      activeSeasonId: seasonId,
      controlVersion: FieldValue.increment(1),
      seasonUpdatedBy: actor.uid,
      seasonUpdatedAt: FieldValue.serverTimestamp(),
    });
    const result: Json = {
      operationId,
      status: "active",
      seasonId,
      seasonVersion: targetVersion + 1,
      previousSeasonId: expectedCurrentSeasonId,
      currentSeasonId: seasonId,
    };
    saveReceipt(transaction, receiptRef, {
      actorId: actor.uid,
      associationId: operationContext.authority.associationId,
      operation: "season.activate",
      operationId,
      requestFingerprint: fingerprint,
      result,
    });
    return result;
  });
}

async function archiveOrRestore(request: CallableRequest<unknown>, action: "archive" | "restore") {
  const actor = caller(request);
  const data = object(request.data);
  exactKeys(data, [
    "schemaVersion", "operationId", "seasonId", "expectedSeasonVersion", "expectedCurrentSeasonId",
  ]);
  schema(data);
  const operationId = id(data.operationId, "operationId", true);
  const seasonId = id(data.seasonId, "seasonId");
  const expectedSeasonVersion = counter(data.expectedSeasonVersion, "expectedSeasonVersion", false);
  const expectedCurrentSeasonId = id(data.expectedCurrentSeasonId, "expectedCurrentSeasonId");
  const operation = `season.${action}`;
  const fingerprint = hash({
    schemaVersion: SCHEMA_VERSION,
    operationId,
    seasonId,
    expectedSeasonVersion,
    expectedCurrentSeasonId,
  });
  const db = admin.firestore();
  const earlyReplay = await consumeInvocationQuota(db, actor, 1, {operation, operationId, fingerprint});
  if (earlyReplay) return earlyReplay;

  return db.runTransaction(async (transaction) => {
    const operationContext = await context(transaction, db, actor);
    const receiptRef = operationReceiptRef(db, actor.uid, operation, operationId);
    const targetRef = seasonRef(db, operationContext.authority.associationId, seasonId);
    const [receipt, target] = await Promise.all([
      transaction.get(receiptRef),
      transaction.get(targetRef),
    ]);
    const replay = receiptReplay(
      receipt,
      fingerprint,
      expectation(operationContext.authority, operation, operationId),
    );
    if (replay) return replay;
    if (operationContext.workflow.seasonId !== expectedCurrentSeasonId ||
        operationContext.association.get("currentSeasonId") !== expectedCurrentSeasonId) {
      throw new HttpsError("aborted", "The current season changed. Reload before continuing.");
    }
    if (action === "archive" && seasonId === expectedCurrentSeasonId) {
      throw new HttpsError(
        "failed-precondition",
        "Activate another prepared season before archiving the current active season.",
      );
    }
    if (!target.exists || target.get("schemaVersion") !== SCHEMA_VERSION ||
        target.get("associationId") !== operationContext.authority.associationId || target.get("seasonId") !== seasonId) {
      throw new HttpsError("not-found", "Season not found.");
    }
    const targetVersion = storedSeasonVersion(target.get("version"));
    if (targetVersion !== expectedSeasonVersion) {
      throw new HttpsError("aborted", "The season changed. Reload before continuing.");
    }
    if (action === "archive") {
      if (target.get("isActive") === true || target.get("status") === "active") {
        throw new HttpsError(
          "failed-precondition",
          "Activate another prepared season before archiving the current active season.",
        );
      }
      const previousStatus = seasonStatus(target.get("status"));
      if (previousStatus !== "prepared" && previousStatus !== "inactive") {
        throw new HttpsError("failed-precondition", "Only an inactive season can be archived.");
      }
      transaction.update(targetRef, {
        status: "archived",
        isActive: false,
        archivedPreviousStatus: previousStatus,
        version: targetVersion + 1,
        archivedBy: actor.uid,
        archivedAt: FieldValue.serverTimestamp(),
        updatedBy: actor.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      if (seasonStatus(target.get("status")) !== "archived" || target.get("isActive") !== false ||
          (target.get("archivedPreviousStatus") !== "prepared" && target.get("archivedPreviousStatus") !== "inactive")) {
        throw new HttpsError("failed-precondition", "Only a reversibly archived season can be restored.");
      }
      transaction.update(targetRef, {
        status: target.get("archivedPreviousStatus"),
        isActive: false,
        archivedPreviousStatus: FieldValue.delete(),
        archivedBy: FieldValue.delete(),
        archivedAt: FieldValue.delete(),
        version: targetVersion + 1,
        restoredBy: actor.uid,
        restoredAt: FieldValue.serverTimestamp(),
        updatedBy: actor.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    const result: Json = {
      operationId,
      status: action === "archive" ? "archived" : "restored",
      seasonId,
      seasonVersion: targetVersion + 1,
      currentSeasonId: expectedCurrentSeasonId,
    };
    saveReceipt(transaction, receiptRef, {
      actorId: actor.uid,
      associationId: operationContext.authority.associationId,
      operation,
      operationId,
      requestFingerprint: fingerprint,
      result,
    });
    return result;
  });
}

export async function seasonArchiveHandler(request: CallableRequest<unknown>) {
  return archiveOrRestore(request, "archive");
}

export async function seasonRestoreHandler(request: CallableRequest<unknown>) {
  return archiveOrRestore(request, "restore");
}

export const seasonPrepare = onCall(LEAGUE_CALLABLE_OPTIONS, seasonPrepareHandler);
export const seasonActivate = onCall(LEAGUE_CALLABLE_OPTIONS, seasonActivateHandler);
export const seasonArchive = onCall(LEAGUE_CALLABLE_OPTIONS, seasonArchiveHandler);
export const seasonRestore = onCall(LEAGUE_CALLABLE_OPTIONS, seasonRestoreHandler);
