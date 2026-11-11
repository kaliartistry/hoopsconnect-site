import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {capabilities} from "./authorization";
import {authorityFromSnapshot} from "./membership";
import {counter, exactKeys, hash, id, LEAGUE_CALLABLE_OPTIONS, object, text} from "./league_operations";

type RegistrationStatus = "draft" | "submitted" | "reviewed";

interface PlayerEntry {
  id: string;
  name: string;
  jersey: string;
  position: string | null;
  heightCm: number | null;
  weightKg: number | null;
  shortsSize: string | null;
  vestSize: string | null;
  shoeSize: string | null;
}

const maxPlayers = 100;
const actions = ["load", "savePlayer", "removePlayer", "submit", "review", "return"];

function measurement(value: unknown, field: string): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > 999) {
    throw new HttpsError("invalid-argument", `${field} must be a positive measurement.`);
  }
  return value;
}

function playerEntry(value: unknown): PlayerEntry {
  const data = object(value);
  exactKeys(data, ["id", "name", "jersey"], ["position", "heightCm", "weightKg", "shortsSize", "vestSize", "shoeSize"]);
  const jersey = data.jersey;
  if (typeof jersey !== "string" || !jersey || jersey.length > 8 ||
      jersey.trim() !== jersey || /[\u0000-\u001f\u007f]/.test(jersey)) {
    throw new HttpsError("invalid-argument", "Enter a jersey number of up to 8 characters without outside spaces.");
  }
  const position = text(data.position, "position", 12, true);
  if (position !== null && !["Guard", "Forward", "Center"].includes(position)) {
    throw new HttpsError("invalid-argument", "Choose Guard, Forward, or Center.");
  }
  return {
    id: id(data.id, "player entry ID"),
    name: text(data.name, "player name", 120)!,
    jersey,
    position,
    heightCm: measurement(data.heightCm, "Height"),
    weightKg: measurement(data.weightKg, "Weight"),
    shortsSize: text(data.shortsSize, "shorts size", 24, true),
    vestSize: text(data.vestSize, "vest size", 24, true),
    shoeSize: text(data.shoeSize, "shoe size", 24, true),
  };
}

export async function teamRegistrationHandler(request: CallableRequest<unknown>) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to open team registration.");
  const uid = request.auth.uid;
  const data = object(request.data);
  const action = data.action;
  if (typeof action !== "string" || !actions.includes(action)) {
    throw new HttpsError("invalid-argument", "Unknown registration action.");
  }
  const keys = ["schemaVersion", "action", "teamId", "seasonId"];
  if (action !== "load") keys.push("expectedRevision", "operationId");
  if (action === "savePlayer") keys.push("player");
  if (action === "removePlayer") keys.push("playerId");
  exactKeys(data, keys);
  if (data.schemaVersion !== 1) throw new HttpsError("invalid-argument", "Unsupported registration version.");
  const teamId = id(data.teamId, "team ID");
  const seasonId = id(data.seasonId, "season ID");
  const expected = action === "load" ? null : counter(data.expectedRevision, "expectedRevision");
  const operationId = action === "load" ? null : id(data.operationId, "operation ID", true);
  const player = action === "savePlayer" ? playerEntry(data.player) : null;
  const playerId = action === "removePlayer" ? id(data.playerId, "player entry ID") : null;
  const fingerprint = hash({action, teamId, seasonId, expected, player, playerId});
  const db = admin.firestore();
  return db.runTransaction(async tx => {
    const membership = await tx.get(db.doc(`memberships/${uid}`));
    const authority = authorityFromSnapshot(membership, capabilities.associationRead);
    const associationId = id(authority.associationId, "association ID");
    const manager = authority.capabilities.includes(capabilities.teamsManage);
    const rep = authority.role === "rep" && authority.capabilities.includes(capabilities.teamsRepresent) &&
      membership.get("teamId") === teamId && membership.get("seasonId") === seasonId;
    if ((!manager && !rep) || (action !== "load" && (
      ["review", "return"].includes(action) ? !manager : !rep
    ))) {
      throw new HttpsError("permission-denied", "Your membership does not allow this registration action.");
    }
    const root = db.doc(`associations/${associationId}`);
    const registration = root.collection("teamRegistrations").doc(hash({seasonId, teamId}));
    const receipt = operationId === null ? null : registration.collection("receipts").doc(hash({uid, operationId}));
    const [association, team, stored, prior] = await Promise.all([
      tx.get(root), tx.get(root.collection("teams").doc(teamId)), tx.get(registration),
      receipt === null ? null : tx.get(receipt),
    ]);
    if (association.get("currentSeasonId") !== seasonId || !team.exists ||
        team.get("seasonId") !== seasonId || ![undefined, "active"].includes(team.get("status")) ||
        team.get("active") === false) {
      throw new HttpsError("failed-precondition", "This team is unavailable in the active season.");
    }
    const divisionId = id(team.get("divisionId"), "division ID");
    const division = await tx.get(root.collection("divisions").doc(divisionId));
    if (!division.exists || ![undefined, "active"].includes(division.get("status")) || division.get("deletionPending") ||
        (rep && membership.get("divisionId") !== divisionId)) {
      throw new HttpsError("failed-precondition", "The team's division is unavailable.");
    }
    const storedData = stored.data();
    if (storedData && (storedData.schemaVersion !== 1 || storedData.associationId !== associationId ||
        storedData.teamId !== teamId || storedData.seasonId !== seasonId ||
        !Array.isArray(storedData.players) || !["draft", "submitted", "reviewed"].includes(storedData.status))) {
      throw new HttpsError("failed-precondition", "This registration needs administrator review.");
    }
    const current = {
      revision: counter(storedData?.revision ?? 0, "stored revision"),
      status: (storedData?.status ?? "draft") as RegistrationStatus,
      players: (storedData?.players ?? []) as PlayerEntry[],
      canEdit: rep,
      canReview: manager,
    };
    const visible = (result: typeof current) => ({
      ...result,
      players: manager && result.status === "draft" ? [] : result.players,
    });
    if (action === "load") return visible(current);
    if (prior?.exists) {
      if (prior.get("fingerprint") !== fingerprint) {
        throw new HttpsError("already-exists", "This save was already used for different details.");
      }
      return visible(current);
    }
    if (expected !== current.revision) {
      throw new HttpsError("aborted", "The roster changed. Reload the draft before saving again.");
    }
    let status = current.status;
    let players = current.players;
    if (rep && status !== "draft") {
      throw new HttpsError("failed-precondition", "The roster has been submitted. A league admin can return it for edits.");
    }
    if (action === "savePlayer") {
      const entry = player!;
      const previous = players.findIndex(row => row.id === entry.id);
      players = [...players];
      if (previous < 0) {
        if (players.length >= maxPlayers) throw new HttpsError("resource-exhausted", "This draft is full.");
        players.push(entry);
      } else {
        players[previous] = entry;
      }
    } else if (action === "removePlayer") {
      players = players.filter(row => row.id !== playerId);
      if (players.length === current.players.length) throw new HttpsError("not-found", "That player is no longer in the draft.");
    } else if (action === "submit") {
      if (!players.length) throw new HttpsError("failed-precondition", "Save at least one player before submitting.");
      status = "submitted";
    } else {
      if (status === "draft" || (action === "review" && status !== "submitted")) {
        throw new HttpsError("failed-precondition", "This roster is not awaiting review.");
      }
      status = action === "review" ? "reviewed" : "draft";
    }
    const revision = current.revision + 1;
    tx.set(registration, {
      schemaVersion: 1, associationId, seasonId, teamId, divisionId, revision, status, players,
      updatedAt: FieldValue.serverTimestamp(), updatedBy: uid,
    });
    tx.create(receipt!, {fingerprint, revision, createdAt: FieldValue.serverTimestamp()});
    return visible({...current, revision, status, players});
  });
}

export const teamRegistration = onCall({...LEAGUE_CALLABLE_OPTIONS, maxInstances: 2}, teamRegistrationHandler);
