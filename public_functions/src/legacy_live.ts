// Explicit compatibility deployment entrypoint. The official-stat v2 publisher
// in index.ts remains dormant. This replaces only the older live v1 trigger.
import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {buildPublicSnapshot} from "./index";

const COLLECTIONS = ["seasons", "divisions", "events", "gameStats",
  "standings", "leaderboard", "teams", "posts"];

export function buildApprovedLegacySnapshot(
  association: admin.firestore.DocumentData,
  sources: Record<string, {id: string; data: admin.firestore.DocumentData}[]>,
) {
  const candidate = buildPublicSnapshot({associationId: "jba", association,
    season: sources.seasons.find((season) => season.id === association.currentSeasonId),
    divisions: sources.divisions, events: sources.events, gameStats: sources.gameStats,
    teams: sources.teams, posts: sources.posts,
    standings: sources.standings.filter((row) => typeof row.data.divisionId === "string"),
    leaderboards: sources.leaderboard.filter((row) => typeof row.data.divisionId === "string"),
  });
  const approved = {...candidate, certificationStatus: "certified",
    publication: {...candidate.publication, verificationStatus: "legacyApproved"}};
  if (Buffer.byteLength(JSON.stringify(approved)) > 850000) {
    throw new Error("Public snapshot exceeds conservative document size bound");
  }
  return approved;
}

export function canPublishLegacy(control: admin.firestore.DocumentData | undefined) {
  return control?.schemaVersion === 1 && control?.enabled === true &&
    control?.maintenance !== true && control?.associationId === "jba" &&
    control?.contractVersion === "legacy-public-snapshot-v1.1";
}

export async function rebuildLegacyLiveSnapshot(db: admin.firestore.Firestore) {
  // Both configuration and lock are server-only. Never infer authority from a
  // private game status or from a client-editable branding field alone.
  const controlRef = db.doc("publicSnapshotControls/jba");
  const early = await controlRef.get();
  if (!canPublishLegacy(early.data())) return;
  await db.runTransaction(async (tx) => {
    const control = await tx.get(controlRef);
    if (!canPublishLegacy(control.data())) return;
    const associationRef = db.doc("associations/jba");
    const association = await tx.get(associationRef);
    if (!association.exists) throw new Error("Missing association");
    const data = association.data()!;
    const seasonId = data.currentSeasonId;
    if (typeof seasonId !== "string" || !seasonId) throw new Error("Missing season");
    const sources: Record<string, {id: string; data: admin.firestore.DocumentData}[]> = {};
    for (const name of COLLECTIONS) {
      const result = await tx.get(associationRef.collection(name).limit(1001));
      if (result.size > 1000) throw new Error("Public source bound exceeded");
      sources[name] = result.docs.map((doc) => ({id: doc.id, data: doc.data()}));
    }
    const currentRef = db.doc("publicData/jba/snapshots/current");
    const current = await tx.get(currentRef);
    const approved = buildApprovedLegacySnapshot(data, sources);
    if (current.data()?.snapshotVersion === approved.snapshotVersion) return;
    tx.set(currentRef, approved);
  });
}

export const onPublicLeagueSourceWritten = onDocumentWritten({
  document: "associations/{associationId}/{collectionId}/{documentId}",
  region: "us-central1", maxInstances: 1, concurrency: 8,
  labels: {"jbl-compatibility": "v1-20260917"},
  timeoutSeconds: 120, memory: "256MiB", retry: false,
}, async (event) => {
  if (event.params.associationId !== "jba" ||
      !COLLECTIONS.includes(event.params.collectionId)) return;
  const db = admin.firestore();
  const control = (await db.doc("publicSnapshotControls/jba").get()).data();
  if (!canPublishLegacy(control)) return;
  // The atomic migration publishes its own matching snapshot. Skip its queued
  // source events without rereading every collection for each imported player.
  const through = control?.ignoreEventsThrough;
  if (through instanceof admin.firestore.Timestamp &&
      Date.parse(event.time) <= through.toMillis()) return;
  await rebuildLegacyLiveSnapshot(db);
});
