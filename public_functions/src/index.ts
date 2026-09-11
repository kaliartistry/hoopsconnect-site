import {createHash} from "node:crypto";

import * as admin from "firebase-admin";
import {Timestamp} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";

admin.initializeApp();

const PUBLIC_SCHEMA_VERSION = 1;
const PUBLIC_CONTRACT_VERSION = "legacy-public-snapshot-v1.1";
const PUBLIC_ASSOCIATION_ID = "jba";
const PUBLIC_SOURCE_COLLECTIONS = new Set([
  "divisions",
  "events",
  "gameStats",
  "leaderboard",
  "seasons",
  "standings",
  "teams",
]);
const LEADERBOARD_ORDER = ["ppg", "rpg", "apg", "spg", "bpg"];
const SHA256 = /^[a-f0-9]{64}$/;

type RecordWithId = {id: string; data: Record<string, unknown>};
type PublicState = "published" | "retracted" | "unavailable";

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value.trim().slice(0, 160) : fallback;
}

function longText(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim().slice(0, 3000) : null;
}

function nullableText(value: unknown): string | null {
  const valueText = text(value);
  return valueText.length > 0 ? valueText : null;
}

function numberValue(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function nullableInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) ? value : null;
}

function timestampIso(value: unknown): string | null {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (typeof value !== "string") return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function objectList(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ?
    value.filter((entry): entry is Record<string, unknown> =>
      Boolean(entry) && typeof entry === "object" && !Array.isArray(entry)) : [];
}

function objectValue(value: unknown): Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(record).sort().map((key) => [key, canonicalValue(record[key])]),
    );
  }
  return value;
}

function fingerprint(value: unknown): string {
  return createHash("sha256")
    .update(JSON.stringify(canonicalValue(value)), "utf8")
    .digest("hex");
}

function publicationState(association: Record<string, unknown>): PublicState {
  const state = text(association.publicLeagueState);
  if (state === "published") return "published";
  if (state === "retracted" || state === "unavailable") return state;
  return "unavailable";
}

function publicPeriodScores(stats: Record<string, unknown> | undefined) {
  const home = objectValue(stats?.homeQuarterScores);
  const away = objectValue(stats?.awayQuarterScores);
  const periods = new Set([...Object.keys(home), ...Object.keys(away)]);
  return [...periods]
    .map((key) => ({
      period: Number(key),
      homeScore: nullableInteger(home[key]),
      awayScore: nullableInteger(away[key]),
    }))
    .filter((row) => Number.isSafeInteger(row.period) && row.period > 0 &&
      row.homeScore !== null && row.awayScore !== null)
    .sort((a, b) => a.period - b.period)
    .map((row) => ({
      period: row.period,
      homeScore: row.homeScore as number,
      awayScore: row.awayScore as number,
    }));
}

function publicPlayerLines(stats: Record<string, unknown> | undefined) {
  // Only a pre-whitelisted publicPlayerLines array crosses this boundary.
  // Legacy playerLines may contain unreviewed names or identity-bearing keys.
  return objectList(stats?.publicPlayerLines).slice(0, 100).map((row) => ({
    playerId: text(row.playerId),
    displayName: text(row.publicDisplayName),
    teamId: text(row.teamId),
    minutes: nullableInteger(row.minutes),
    points: nullableInteger(row.points),
    twoPointMade: nullableInteger(row.twoPointMade),
    twoPointAttempted: nullableInteger(row.twoPointAttempted),
    threePointMade: nullableInteger(row.threePointMade),
    threePointAttempted: nullableInteger(row.threePointAttempted),
    freeThrowMade: nullableInteger(row.freeThrowMade),
    freeThrowAttempted: nullableInteger(row.freeThrowAttempted),
    offensiveRebounds: nullableInteger(row.offensiveRebounds),
    defensiveRebounds: nullableInteger(row.defensiveRebounds),
    assists: nullableInteger(row.assists),
    steals: nullableInteger(row.steals),
    blocks: nullableInteger(row.blocks),
    turnovers: nullableInteger(row.turnovers),
    fouls: nullableInteger(row.fouls),
  })).filter((row) => row.playerId && row.displayName && row.teamId);
}

function leaderboardOrder(category: string): number {
  const index = LEADERBOARD_ORDER.indexOf(category.toLowerCase());
  return index < 0 ? LEADERBOARD_ORDER.length : index;
}

export function buildPublicSnapshot(input: {
  associationId: string;
  association: Record<string, unknown>;
  season?: RecordWithId | null;
  divisions?: RecordWithId[];
  events: RecordWithId[];
  gameStats: RecordWithId[];
  standings: RecordWithId[];
  leaderboards: RecordWithId[];
  teams: RecordWithId[];
  generatedAt?: string;
}) {
  const seasonId = text(input.association.currentSeasonId);
  if (!seasonId) throw new Error("Association currentSeasonId is required.");
  const state = publicationState(input.association);
  const parsedPrivacyEpoch = nullableInteger(input.association.publicPrivacyEpoch);
  const privacyEpoch = parsedPrivacyEpoch !== null && parsedPrivacyEpoch >= 0 ?
    parsedPrivacyEpoch : null;
  const canPublishPlayerIdentity = privacyEpoch !== null;
  const generatedAt = input.generatedAt || new Date().toISOString();
  const seasonTeams = input.teams.filter(
    (entry) => !entry.data.seasonId || entry.data.seasonId === seasonId,
  );
  const teamNames = new Map(
    seasonTeams.map((entry) => [entry.id, text(entry.data.name, "Team")]),
  );
  const approvedStats = new Map(
    input.gameStats
      .filter((entry) => entry.data.status === "approved" && entry.data.seasonId === seasonId)
      .map((entry) => [entry.id, entry.data]),
  );

  const schedule = input.events
    .filter((entry) => entry.data.type === "game" && entry.data.seasonId === seasonId)
    .map((entry) => {
      const stats = approvedStats.get(entry.id);
      const teamIds = Array.isArray(entry.data.teamIds) ?
        entry.data.teamIds.filter((value): value is string => typeof value === "string").slice(0, 2) : [];
      const homeTeamId = text(stats?.homeTeamId, teamIds[0] || "");
      const awayTeamId = text(stats?.awayTeamId, teamIds[1] || "");
      const result = stats ? {
        homeScore: numberValue(stats.homeScore),
        awayScore: numberValue(stats.awayScore),
        periodScores: publicPeriodScores(stats),
        playerLines: canPublishPlayerIdentity ? publicPlayerLines(stats) : [],
        recap: longText(stats.publicRecap),
      } : null;
      const explicitVersion = text(stats?.publicResultVersion);
      const resultVersion = stats ?
        (SHA256.test(explicitVersion) ? explicitVersion : fingerprint({gameId: entry.id, ...result})) : null;
      return {
        gameId: entry.id,
        title: `${teamNames.get(homeTeamId) || "Home"} vs ${teamNames.get(awayTeamId) || "Away"}`,
        startTime: timestampIso(entry.data.startTime),
        endTime: timestampIso(entry.data.endTime),
        venue: nullableText(entry.data.location),
        divisionId: nullableText(entry.data.divisionId),
        homeTeamId: homeTeamId || null,
        homeTeamName: teamNames.get(homeTeamId) || null,
        awayTeamId: awayTeamId || null,
        awayTeamName: teamNames.get(awayTeamId) || null,
        status: stats ? "final" : "scheduled",
        homeScore: stats ? numberValue(stats.homeScore) : null,
        awayScore: stats ? numberValue(stats.awayScore) : null,
        resultVersion,
        recap: result?.recap ?? null,
        periodScores: result?.periodScores ?? [],
        playerLines: result?.playerLines ?? [],
      };
    })
    .filter((entry) => entry.startTime !== null)
    .sort((a, b) => a.startTime!.localeCompare(b.startTime!) || a.gameId.localeCompare(b.gameId))
    .slice(-250);

  const standings = input.standings
    .filter((entry) => entry.data.seasonId === seasonId)
    .flatMap((entry) => {
      const divisionId = nullableText(entry.data.divisionId);
      return objectList(entry.data.standings).slice(0, 100).map((row) => {
        const teamId = text(row.teamId);
        const parsedRank = nullableInteger(row.rank);
        const rank = parsedRank !== null && parsedRank > 0 ? parsedRank : null;
        const rankStatus = text(row.rankStatus);
        return {
          teamId,
          teamName: teamNames.get(teamId) || "Team",
          divisionId: nullableText(row.divisionId) || divisionId,
          rank,
          rankStatus: rank !== null && (rankStatus === "ranked" || rankStatus === "tied") ?
            rankStatus : "unresolved",
          wins: nullableInteger(row.wins),
          losses: nullableInteger(row.losses),
          pct: numberValue(row.pct),
          gamesBehind: numberValue(row.gb),
          streak: nullableText(row.streak),
          lastTen: nullableText(row.lastTen),
          pointsFor: nullableInteger(row.pointsFor),
          pointsAgainst: nullableInteger(row.pointsAgainst),
        };
      }).filter((row) => row.teamId.length > 0);
    });

  const leaderboards = input.leaderboards
    .filter((entry) => entry.data.seasonId === seasonId)
    .map((entry) => {
      const divisionId = nullableText(entry.data.divisionId);
      return {
        category: text(entry.data.category),
        divisionId,
        qualificationLabel: nullableText(entry.data.qualificationLabel),
        rankings: (canPublishPlayerIdentity ?
          objectList(entry.data.rankings).slice(0, 25) : []).map((row) => {
          const teamId = text(row.teamId);
          return {
            playerId: text(row.playerId),
            displayName: text(row.publicDisplayName),
            teamId,
            teamName: teamNames.get(teamId) || "Team",
            divisionId: nullableText(row.divisionId) || divisionId,
            value: numberValue(row.value),
            gamesPlayed: nullableInteger(row.gp),
          };
        }).filter((row) => row.playerId && row.displayName && row.teamId),
      };
    })
    .filter((entry) => entry.category.length > 0)
    .sort((a, b) => leaderboardOrder(a.category) - leaderboardOrder(b.category) ||
      a.category.localeCompare(b.category));

  const divisions = (input.divisions || [])
    .filter((entry) => !entry.data.seasonId || entry.data.seasonId === seasonId)
    .map((entry) => ({divisionId: entry.id, name: text(entry.data.name, "Division")}))
    .sort((a, b) => a.name.localeCompare(b.name) || a.divisionId.localeCompare(b.divisionId));
  const teams = seasonTeams
    .map((entry) => ({
      teamId: entry.id,
      name: text(entry.data.name, "Team"),
      divisionId: nullableText(entry.data.divisionId),
    }))
    .sort((a, b) => a.name.localeCompare(b.name) || a.teamId.localeCompare(b.teamId));
  const league = {
    name: text(input.association.name, "Jamaica Basketball Association"),
    shortName: text(input.association.shortName, "JBA"),
    logoUrl: nullableText(input.association.logoUrl),
    primaryColor: nullableText(input.association.primaryColor),
    sponsorName: nullableText(input.association.sponsorName),
    sponsorLogoUrl: nullableText(input.association.sponsorLogoUrl),
  };

  const publishedContent = state === "published" ? {
    divisions,
    teams,
    schedule,
    standings,
    leaderboards,
  } : {
    divisions: [],
    teams: [],
    schedule: [],
    standings: [],
    leaderboards: [],
  };
  const snapshotVersion = fingerprint({
    associationId: input.associationId,
    contractVersion: PUBLIC_CONTRACT_VERSION,
    state,
    seasonId,
    seasonName: text(input.season?.data.name, seasonId),
    standingsPolicyLabel: nullableText(input.association.standingsPolicyLabel),
    privacyEpoch,
    league,
    ...publishedContent,
  });

  return {
    associationId: input.associationId,
    schemaVersion: PUBLIC_SCHEMA_VERSION,
    contractVersion: PUBLIC_CONTRACT_VERSION,
    published: state === "published",
    certificationStatus: "legacyApproved",
    publicationState: state,
    snapshotVersion,
    generatedAt,
    privacyEpoch,
    publication: {
      state,
      contractVersion: PUBLIC_CONTRACT_VERSION,
      snapshotVersion,
      verificationStatus: "legacyApproved",
      privacyEpoch,
      generatedAt,
    },
    league,
    seasonId,
    season: {seasonId, name: text(input.season?.data.name, seasonId)},
    standingsPolicyLabel: nullableText(input.association.standingsPolicyLabel),
    ...publishedContent,
  };
}

function documentRecords(snapshot: admin.firestore.QuerySnapshot): RecordWithId[] {
  return snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
}

export async function rebuildPublicSnapshot(associationId: string): Promise<void> {
  if (associationId !== PUBLIC_ASSOCIATION_ID) return;
  const db = admin.firestore();
  const associationRef = db.doc(`associations/${associationId}`);
  const publicSnapshotRef = db.doc(`publicData/${associationId}/snapshots/current`);
  const associationSnap = await associationRef.get();
  if (!associationSnap.exists) {
    await publicSnapshotRef.delete();
    return;
  }
  const association = associationSnap.data() || {};
  const seasonId = text(association.currentSeasonId);
  if (!seasonId) {
    await publicSnapshotRef.delete();
    return;
  }
  const [season, divisions, events, gameStats, standings, leaderboards, teams] = await Promise.all([
    associationRef.collection("seasons").doc(seasonId).get(),
    associationRef.collection("divisions").limit(50).get(),
    associationRef.collection("events").orderBy("startTime").limit(250).get(),
    associationRef.collection("gameStats").limit(250).get(),
    associationRef.collection("standings").limit(50).get(),
    associationRef.collection("leaderboard").limit(50).get(),
    associationRef.collection("teams").limit(100).get(),
  ]);
  const snapshot = buildPublicSnapshot({
    associationId,
    association,
    season: season.exists ? {id: season.id, data: season.data() || {}} : null,
    divisions: documentRecords(divisions),
    events: documentRecords(events),
    gameStats: documentRecords(gameStats),
    standings: documentRecords(standings),
    leaderboards: documentRecords(leaderboards),
    teams: documentRecords(teams),
  });
  await publicSnapshotRef.set(snapshot, {merge: false});
}

export const onPublicLeagueSourceWritten = onDocumentWritten(
  "associations/{associationId}/{collectionId}/{documentId}",
  async (event) => {
    const {associationId, collectionId} = event.params;
    if (associationId !== PUBLIC_ASSOCIATION_ID || !PUBLIC_SOURCE_COLLECTIONS.has(collectionId)) return;
    await rebuildPublicSnapshot(associationId);
  },
);

export const onPublicAssociationWritten = onDocumentWritten(
  "associations/{associationId}",
  async (event) => {
    if (event.params.associationId !== PUBLIC_ASSOCIATION_ID) return;
    if (!event.data?.after.exists) {
      await admin.firestore()
        .doc(`publicData/${event.params.associationId}/snapshots/current`)
        .delete();
      return;
    }
    await rebuildPublicSnapshot(event.params.associationId);
  },
);
