import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {PUBLIC_ASSOCIATION_ID} from "./authorization";

const PUBLIC_SCHEMA_VERSION = 1;
const PUBLIC_SOURCE_COLLECTIONS = new Set([
  "events",
  "gameStats",
  "leaderboard",
  "standings",
  "teams",
]);

type RecordWithId = {id: string; data: Record<string, unknown>};

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value.trim().slice(0, 160) : fallback;
}

function nullableText(value: unknown): string | null {
  const valueText = text(value);
  return valueText.length > 0 ? valueText : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function integerValue(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isInteger(value) ? value : fallback;
}

function timestampIso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function objectList(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is Record<string, unknown> =>
      Boolean(entry) && typeof entry === "object" && !Array.isArray(entry))
    : [];
}

export function buildPublicSnapshot(input: {
  associationId: string;
  association: Record<string, unknown>;
  events: RecordWithId[];
  gameStats: RecordWithId[];
  standings: RecordWithId[];
  leaderboards: RecordWithId[];
  teams: RecordWithId[];
  generatedAt?: string;
}) {
  const seasonId = text(input.association.currentSeasonId);
  if (!seasonId) throw new Error("Association currentSeasonId is required.");
  const teamNames = new Map(input.teams.map((entry) => [entry.id, text(entry.data.name, "Team")]));
  const approvedStats = new Map(
    input.gameStats
      .filter((entry) => entry.data.status === "approved" && entry.data.seasonId === seasonId)
      .map((entry) => [entry.id, entry.data]),
  );

  const schedule = input.events
    .filter((entry) => entry.data.type === "game" && entry.data.seasonId === seasonId)
    .map((entry) => {
      const stats = approvedStats.get(entry.id);
      const teamIds = Array.isArray(entry.data.teamIds)
        ? entry.data.teamIds.filter((value): value is string => typeof value === "string").slice(0, 2)
        : [];
      const homeTeamId = text(stats?.homeTeamId, teamIds[0] || "");
      const awayTeamId = text(stats?.awayTeamId, teamIds[1] || "");
      return {
        gameId: entry.id,
        title: text(entry.data.title, `${teamNames.get(homeTeamId) || "Home"} vs ${teamNames.get(awayTeamId) || "Away"}`),
        startTime: timestampIso(entry.data.startTime),
        endTime: timestampIso(entry.data.endTime),
        venue: nullableText(entry.data.location),
        divisionId: nullableText(entry.data.divisionId),
        homeTeamId: homeTeamId || null,
        homeTeamName: nullableText(stats?.homeTeamName) || teamNames.get(homeTeamId) || null,
        awayTeamId: awayTeamId || null,
        awayTeamName: nullableText(stats?.awayTeamName) || teamNames.get(awayTeamId) || null,
        status: stats ? "final" : "scheduled",
        homeScore: stats ? numberValue(stats.homeScore) : null,
        awayScore: stats ? numberValue(stats.awayScore) : null,
      };
    })
    .filter((entry) => entry.startTime !== null)
    .sort((a, b) => a.startTime!.localeCompare(b.startTime!))
    .slice(-250);

  const allStandings = input.standings.find((entry) =>
    entry.data.seasonId === seasonId && (entry.data.divisionId === null || entry.data.divisionId === undefined),
  );
  const standings = objectList(allStandings?.data.standings).slice(0, 100).map((row) => ({
    teamId: text(row.teamId),
    teamName: text(row.teamName, "Team"),
    divisionId: nullableText(row.divisionId),
    wins: integerValue(row.wins),
    losses: integerValue(row.losses),
    pct: numberValue(row.pct) ?? 0,
    gamesBehind: numberValue(row.gb) ?? 0,
    streak: text(row.streak, "-"),
    lastTen: text(row.lastTen, "-"),
    pointsFor: integerValue(row.pointsFor),
    pointsAgainst: integerValue(row.pointsAgainst),
  }));

  const leaderboards = input.leaderboards
    .filter((entry) => entry.data.seasonId === seasonId &&
      (entry.data.divisionId === null || entry.data.divisionId === undefined))
    .map((entry) => ({
      category: text(entry.data.category),
      rankings: objectList(entry.data.rankings).slice(0, 25).map((row) => ({
        playerId: text(row.playerId),
        displayName: text(row.name, "Player"),
        teamName: text(row.teamName, "Team"),
        value: numberValue(row.value) ?? 0,
        gamesPlayed: integerValue(row.gp),
      })),
    }))
    .filter((entry) => entry.category.length > 0)
    .sort((a, b) => a.category.localeCompare(b.category));

  return {
    associationId: input.associationId,
    schemaVersion: PUBLIC_SCHEMA_VERSION,
    published: true,
    certificationStatus: "certified",
    generatedAt: input.generatedAt || new Date().toISOString(),
    league: {
      name: text(input.association.name, "Jamaica Basketball Association"),
      shortName: text(input.association.shortName, "JBA"),
      logoUrl: nullableText(input.association.logoUrl),
      primaryColor: nullableText(input.association.primaryColor),
      sponsorName: nullableText(input.association.sponsorName),
      sponsorLogoUrl: nullableText(input.association.sponsorLogoUrl),
    },
    seasonId,
    schedule,
    standings,
    leaderboards,
  };
}

function documentRecords(snapshot: admin.firestore.QuerySnapshot): RecordWithId[] {
  return snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
}

export async function rebuildPublicSnapshot(associationId: string): Promise<void> {
  if (associationId !== PUBLIC_ASSOCIATION_ID) return;
  const db = admin.firestore();
  const associationRef = db.doc(`associations/${associationId}`);
  const [associationSnap, events, gameStats, standings, leaderboards, teams] = await Promise.all([
    associationRef.get(),
    associationRef.collection("events").orderBy("startTime").limit(250).get(),
    associationRef.collection("gameStats").limit(250).get(),
    associationRef.collection("standings").limit(50).get(),
    associationRef.collection("leaderboard").limit(50).get(),
    associationRef.collection("teams").limit(100).get(),
  ]);
  if (!associationSnap.exists) throw new Error(`Association ${associationId} does not exist.`);
  const snapshot = buildPublicSnapshot({
    associationId,
    association: associationSnap.data() || {},
    events: documentRecords(events),
    gameStats: documentRecords(gameStats),
    standings: documentRecords(standings),
    leaderboards: documentRecords(leaderboards),
    teams: documentRecords(teams),
  });
  await db.doc(`publicData/${associationId}/snapshots/current`).set(snapshot, {merge: false});
}

export const onPublicLeagueSourceWritten = onDocumentWritten(
  "associations/{associationId}/{collectionId}/{documentId}",
  async (event) => {
    const {associationId, collectionId} = event.params;
    if (associationId !== PUBLIC_ASSOCIATION_ID || !PUBLIC_SOURCE_COLLECTIONS.has(collectionId)) return;
    await rebuildPublicSnapshot(associationId);
  },
);
