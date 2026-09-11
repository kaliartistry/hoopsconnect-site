import {createHash} from "node:crypto";

import * as admin from "firebase-admin";
import {FieldPath, Timestamp} from "firebase-admin/firestore";

admin.initializeApp();

const PUBLIC_SCHEMA_VERSION = 1;
const PUBLIC_CONTRACT_VERSION = "legacy-public-snapshot-v1.1";
const PUBLIC_RELEASE_PROTOCOL = "public-release-v2";
const PUBLIC_ASSOCIATION_ID = "jba";
export const PUBLIC_PAGE_TARGET_BYTES = 480 * 1024;
export const MAX_PUBLIC_RELEASE_PAGES = 64;
const SOURCE_QUERY_PAGE_SIZE = 200;
const PUBLIC_WRITE_BATCH_PAGES = 10;
const LEADERBOARD_ORDER = ["ppg", "rpg", "apg", "spg", "bpg"];
const SHA256 = /^[a-f0-9]{64}$/;

type RecordWithId = {id: string; data: Record<string, unknown>};
type PublicState = "published" | "retracted" | "unavailable";

function text(value: unknown, fallback = ""): string {
  if (typeof value !== "string") return fallback;
  const result = value.trim();
  if (result.length > 160) {
    throw new Error("A public text field exceeds the 160-character contract limit.");
  }
  return result;
}

function longText(value: unknown): string | null {
  if (typeof value !== "string" || value.trim().length === 0) return null;
  const result = value.trim();
  if (result.length > 3000) {
    throw new Error("A public long-text field exceeds the 3000-character contract limit.");
  }
  return result;
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

export function immutablePublicDocumentMatches(
  existing: unknown,
  candidate: unknown,
): boolean {
  return existing !== undefined && fingerprint(existing) === fingerprint(candidate);
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
  return objectList(stats?.publicPlayerLines).map((row) => ({
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
    (entry) => entry.data.seasonId === seasonId,
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
        entry.data.teamIds.filter((value): value is string => typeof value === "string") : [];
      if (teamIds.length > 2) {
        throw new Error(`Game ${entry.id} has more than two team IDs.`);
      }
      const homeTeamId = text(stats?.homeTeamId, teamIds[0] || "");
      const awayTeamId = text(stats?.awayTeamId, teamIds[1] || "");
      const resultContent = stats ? {
        gameId: entry.id,
        homeTeamId: homeTeamId || null,
        homeTeamName: teamNames.get(homeTeamId) || null,
        awayTeamId: awayTeamId || null,
        awayTeamName: teamNames.get(awayTeamId) || null,
        homeScore: numberValue(stats.homeScore),
        awayScore: numberValue(stats.awayScore),
        periodScores: publicPeriodScores(stats),
        playerLines: canPublishPlayerIdentity ? publicPlayerLines(stats) : [],
        recap: longText(stats.publicRecap),
      } : null;
      const explicitVersion = text(stats?.publicResultVersion);
      const resultVersion = resultContent ? fingerprint(resultContent) : null;
      if (explicitVersion && (!SHA256.test(explicitVersion) || explicitVersion !== resultVersion)) {
        throw new Error(
          `Game ${entry.id} publicResultVersion does not match its public result content.`,
        );
      }
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
        recap: resultContent?.recap ?? null,
        periodScores: resultContent?.periodScores ?? [],
        playerLines: resultContent?.playerLines ?? [],
      };
    })
    .filter((entry) => entry.startTime !== null)
    .sort((a, b) => a.startTime!.localeCompare(b.startTime!) || a.gameId.localeCompare(b.gameId));

  const standings = input.standings
    .filter((entry) => entry.data.seasonId === seasonId)
    .flatMap((entry) => {
      const divisionId = nullableText(entry.data.divisionId);
      return objectList(entry.data.standings).map((row) => {
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
          objectList(entry.data.rankings) : []).map((row) => {
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
    .filter((entry) => entry.data.seasonId === seasonId)
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
    certificationStatus: "compatibilityCandidate",
    publicationState: state,
    snapshotVersion,
    generatedAt,
    privacyEpoch,
    publication: {
      state,
      contractVersion: PUBLIC_CONTRACT_VERSION,
      snapshotVersion,
      verificationStatus: "compatibilityCandidate",
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

type SnapshotDocument = ReturnType<typeof buildPublicSnapshot>;
type ContentKey = "divisions" | "teams" | "schedule" | "standings" | "leaderboards";

export type PublicReleasePage = {
  protocolVersion: string;
  releaseId: string;
  sourceVersion: string;
  contentType: ContentKey;
  pageIndex: number;
  itemCount: number;
  items: unknown[];
  pageDigest: string;
};

export type PublicReleasePackage = {
  releaseId: string;
  manifest: Record<string, unknown>;
  pages: Array<{id: string; data: PublicReleasePage}>;
};

function utf8JsonBytes(value: unknown): number {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}

function assertSourceVersion(value: string): void {
  if (!SHA256.test(value)) {
    throw new Error("publicProjectionSourceVersion must be a lowercase SHA-256 value.");
  }
}

/**
 * Splits a complete public projection into immutable, conservatively sized
 * Firestore page documents. Capacity failures are explicit; no row is sliced
 * or silently dropped.
 */
export function buildPublicReleasePackage(
  snapshot: SnapshotDocument,
  sourceVersion: string,
  sourceSequence: number,
  sourceCommittedAt: string,
): PublicReleasePackage {
  assertSourceVersion(sourceVersion);
  if (!Number.isSafeInteger(sourceSequence) || sourceSequence < 0) {
    throw new Error("sourceSequence must be a nonnegative safe integer.");
  }
  if (timestampIso(sourceCommittedAt) !== sourceCommittedAt) {
    throw new Error("sourceCommittedAt must be a canonical ISO timestamp.");
  }
  const releaseId = fingerprint({
    protocolVersion: PUBLIC_RELEASE_PROTOCOL,
    snapshotVersion: snapshot.snapshotVersion,
    sourceVersion,
    sourceSequence,
    sourceCommittedAt,
  });
  const pages: Array<{id: string; data: PublicReleasePage}> = [];
  const pageRefs: Array<Record<string, unknown>> = [];
  const counts: Record<string, number> = {};
  const contentKeys: ContentKey[] = [
    "divisions", "teams", "schedule", "standings", "leaderboards",
  ];

  for (const contentType of contentKeys) {
    const items = snapshot[contentType] as unknown[];
    counts[contentType] = items.length;
    let pageItems: unknown[] = [];
    let pageIndex = 0;

    const finishPage = () => {
      if (pageItems.length === 0) return;
      const pageWithoutDigest = {
        protocolVersion: PUBLIC_RELEASE_PROTOCOL,
        releaseId,
        sourceVersion,
        contentType,
        pageIndex,
        itemCount: pageItems.length,
        items: pageItems,
      };
      const data: PublicReleasePage = {
        ...pageWithoutDigest,
        pageDigest: fingerprint(pageWithoutDigest),
      };
      if (utf8JsonBytes(data) > PUBLIC_PAGE_TARGET_BYTES) {
        throw new Error(`Public ${contentType} page exceeds the safe document budget.`);
      }
      const id = `${contentType}-${pageIndex.toString().padStart(4, "0")}`;
      pages.push({id, data});
      pageRefs.push({
        id,
        contentType,
        pageIndex,
        itemCount: data.itemCount,
        pageDigest: data.pageDigest,
      });
      pageIndex += 1;
      pageItems = [];
    };

    for (const item of items) {
      const candidate = [...pageItems, item];
      const candidateDocument = {
        protocolVersion: PUBLIC_RELEASE_PROTOCOL,
        releaseId,
        sourceVersion,
        contentType,
        pageIndex,
        itemCount: candidate.length,
        items: candidate,
        pageDigest: "0".repeat(64),
      };
      if (utf8JsonBytes(candidateDocument) > PUBLIC_PAGE_TARGET_BYTES) {
        if (pageItems.length === 0) {
          throw new Error(`One public ${contentType} item exceeds the safe document budget.`);
        }
        finishPage();
      }
      pageItems.push(item);
    }
    finishPage();
  }

  if (pages.length > MAX_PUBLIC_RELEASE_PAGES) {
    throw new Error(
      `Public release requires ${pages.length} pages; maximum is ${MAX_PUBLIC_RELEASE_PAGES}.`,
    );
  }

  const metadata = Object.fromEntries(
    Object.entries(snapshot).filter(([key]) => !contentKeys.includes(key as ContentKey)),
  );
  const releaseDigest = fingerprint({
    releaseId, sourceVersion, sourceSequence, sourceCommittedAt, metadata, pageRefs, counts,
  });
  const manifest: Record<string, unknown> = {
    protocolVersion: PUBLIC_RELEASE_PROTOCOL,
    releaseId,
    sourceVersion,
    sourceSequence,
    sourceCommittedAt,
    releaseDigest,
    state: snapshot.publicationState,
    seasonId: snapshot.seasonId,
    privacyEpoch: snapshot.privacyEpoch,
    pageCount: pages.length,
    pages: pageRefs,
    counts,
    metadata,
  };
  if (utf8JsonBytes(manifest) > PUBLIC_PAGE_TARGET_BYTES) {
    throw new Error("Public release manifest exceeds the safe document budget.");
  }
  return {releaseId, manifest, pages};
}

export function canAdvancePublicReleasePointer(input: {
  expectedSourceVersion: string;
  expectedSourceSequence: number;
  expectedSourceCommittedAt: string;
  expectedSeasonId: string;
  expectedState: PublicState;
  expectedPrivacyEpoch: number | null;
  association: Record<string, unknown>;
}): boolean {
  const liveEpoch = nullableInteger(input.association.publicPrivacyEpoch);
  const liveSequence = nullableInteger(input.association.publicProjectionSourceSequence);
  const liveCommittedAt = timestampIso(input.association.publicProjectionSourceCommittedAt);
  return input.association.publicProjectionProtocol === PUBLIC_RELEASE_PROTOCOL &&
    input.association.publicProjectionSourceVersion === input.expectedSourceVersion &&
    liveSequence === input.expectedSourceSequence && input.expectedSourceSequence >= 0 &&
    liveCommittedAt === input.expectedSourceCommittedAt &&
    text(input.association.currentSeasonId) === input.expectedSeasonId &&
    publicationState(input.association) === input.expectedState &&
    liveEpoch === input.expectedPrivacyEpoch;
}

export function currentPointerAllowsCandidate(
  current: Record<string, unknown> | null,
  candidate: {
    releaseId: string;
    releaseDigest: string;
    sourceVersion: string;
    sourceSequence: number;
    sourceCommittedAt: string;
    state: PublicState;
    seasonId: string;
    privacyEpoch: number | null;
  },
): boolean {
  if (current === null) return true;
  const currentSequence = nullableInteger(current.sourceSequence);
  if (currentSequence === null || currentSequence > candidate.sourceSequence) return false;
  if (currentSequence < candidate.sourceSequence) return true;
  return current.protocolVersion === PUBLIC_RELEASE_PROTOCOL &&
    current.releaseId === candidate.releaseId &&
    current.releaseDigest === candidate.releaseDigest &&
    current.sourceVersion === candidate.sourceVersion &&
    current.sourceCommittedAt === candidate.sourceCommittedAt &&
    current.state === candidate.state &&
    current.seasonId === candidate.seasonId &&
    nullableInteger(current.privacyEpoch) === candidate.privacyEpoch;
}

async function readCurrentSeasonRecords(
  collection: admin.firestore.CollectionReference,
  seasonId: string,
): Promise<RecordWithId[]> {
  const records: RecordWithId[] = [];
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  do {
    let query: admin.firestore.Query = collection
      .where("seasonId", "==", seasonId)
      .orderBy(FieldPath.documentId())
      .limit(SOURCE_QUERY_PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) records.push({id: doc.id, data: doc.data()});
    cursor = page.docs.length === SOURCE_QUERY_PAGE_SIZE ? page.docs.at(-1) : undefined;
  } while (cursor);
  return records;
}

async function createImmutablePageChunk(
  db: admin.firestore.Firestore,
  manifestRef: admin.firestore.DocumentReference,
  pages: Array<{id: string; data: PublicReleasePage}>,
): Promise<void> {
  const refs = pages.map((page) => manifestRef.collection("pages").doc(page.id));
  const existing = await db.getAll(...refs);
  const batch = db.batch();
  let creates = 0;
  for (let index = 0; index < pages.length; index += 1) {
    const snapshot = existing[index];
    const page = pages[index];
    if (snapshot.exists) {
      if (!immutablePublicDocumentMatches(snapshot.data(), page.data)) {
        throw new Error(`Immutable public release page ${page.id} conflicts.`);
      }
      continue;
    }
    batch.create(refs[index], page.data);
    creates += 1;
  }
  if (creates === 0) return;
  try {
    await batch.commit();
  } catch (error) {
    // A concurrent identical retry may have created the whole chunk after our
    // read. Exact digest readback makes that idempotent without permitting an
    // overwrite.
    const after = await db.getAll(...refs);
    if (after.some((doc, index) =>
      !doc.exists || !immutablePublicDocumentMatches(doc.data(), pages[index].data))) {
      throw error;
    }
  }
}

/**
 * Dormant compatibility bridge for a future trusted public-release-v2
 * transport. Nothing in this module registers a Cloud Function trigger.
 *
 * The trusted writer must atomically change publicProjectionSourceVersion on
 * every source mutation. The final transaction rechecks that token plus the
 * publication state, season, and privacy epoch, so an older or mixed rebuild
 * cannot replace a newer publication or retraction.
 */
export async function rebuildVersionedPublicRelease(
  associationId: string,
  expectedSourceVersion: string,
): Promise<string> {
  if (associationId !== PUBLIC_ASSOCIATION_ID) {
    throw new Error("Only the configured public association can be projected.");
  }
  assertSourceVersion(expectedSourceVersion);
  const db = admin.firestore();
  const associationRef = db.doc(`associations/${associationId}`);
  const associationSnap = await associationRef.get();
  if (!associationSnap.exists) throw new Error("Association does not exist.");
  const association = associationSnap.data() || {};
  const seasonId = text(association.currentSeasonId);
  if (!seasonId) throw new Error("Association currentSeasonId is required.");
  const state = publicationState(association);
  const privacyEpoch = nullableInteger(association.publicPrivacyEpoch);
  const sourceSequence = nullableInteger(association.publicProjectionSourceSequence);
  const sourceCommittedAt = timestampIso(association.publicProjectionSourceCommittedAt);
  if (sourceSequence === null || sourceSequence < 0) {
    throw new Error("A nonnegative publicProjectionSourceSequence is required.");
  }
  if (sourceCommittedAt === null) {
    throw new Error("A valid publicProjectionSourceCommittedAt is required.");
  }
  if (!canAdvancePublicReleasePointer({
    expectedSourceVersion,
    expectedSourceSequence: sourceSequence,
    expectedSourceCommittedAt: sourceCommittedAt,
    expectedSeasonId: seasonId,
    expectedState: state,
    expectedPrivacyEpoch: privacyEpoch,
    association,
  })) {
    throw new Error("Public projection protocol or exact source version is not ready.");
  }

  const [season, divisions, events, gameStats, standings, leaderboards, teams] =
    await Promise.all([
      associationRef.collection("seasons").doc(seasonId).get(),
      readCurrentSeasonRecords(associationRef.collection("divisions"), seasonId),
      readCurrentSeasonRecords(associationRef.collection("events"), seasonId),
      readCurrentSeasonRecords(associationRef.collection("gameStats"), seasonId),
      readCurrentSeasonRecords(associationRef.collection("standings"), seasonId),
      readCurrentSeasonRecords(associationRef.collection("leaderboard"), seasonId),
      readCurrentSeasonRecords(associationRef.collection("teams"), seasonId),
    ]);
  const snapshot = buildPublicSnapshot({
    associationId,
    association,
    season: season.exists ? {id: season.id, data: season.data() || {}} : null,
    divisions,
    events,
    gameStats,
    standings,
    leaderboards,
    teams,
    generatedAt: sourceCommittedAt,
  });
  const release = buildPublicReleasePackage(
    snapshot,
    expectedSourceVersion,
    sourceSequence,
    sourceCommittedAt,
  );
  const manifestRef = db.doc(`publicData/${associationId}/releases/${release.releaseId}`);
  for (let offset = 0; offset < release.pages.length; offset += PUBLIC_WRITE_BATCH_PAGES) {
    await createImmutablePageChunk(
      db,
      manifestRef,
      release.pages.slice(offset, offset + PUBLIC_WRITE_BATCH_PAGES),
    );
  }
  const releaseBatch = db.batch();
  releaseBatch.create(manifestRef, release.manifest);
  try {
    await releaseBatch.commit();
  } catch (error) {
    const existing = await manifestRef.get();
    if (!existing.exists || !immutablePublicDocumentMatches(
      existing.data(), release.manifest,
    )) {
      throw error;
    }
  }

  const pointerRef = db.doc(`publicData/${associationId}/releasePointers/current`);
  await db.runTransaction(async (transaction) => {
    const liveSnap = await transaction.get(associationRef);
    const currentPointer = await transaction.get(pointerRef);
    const live = liveSnap.data() || {};
    if (!liveSnap.exists || !canAdvancePublicReleasePointer({
      expectedSourceVersion,
      expectedSourceSequence: sourceSequence,
      expectedSourceCommittedAt: sourceCommittedAt,
      expectedSeasonId: seasonId,
      expectedState: state,
      expectedPrivacyEpoch: privacyEpoch,
      association: live,
    })) {
      throw new Error("Public source changed while the release was being built.");
    }
    if (!currentPointerAllowsCandidate(
      currentPointer.exists ? currentPointer.data() || {} : null,
      {
        releaseId: release.releaseId,
        releaseDigest: release.manifest.releaseDigest as string,
        sourceVersion: expectedSourceVersion,
        sourceSequence,
        sourceCommittedAt,
        state,
        seasonId,
        privacyEpoch,
      },
    )) {
      throw new Error("The current public release pointer conflicts with this candidate.");
    }
    transaction.set(pointerRef, {
      protocolVersion: PUBLIC_RELEASE_PROTOCOL,
      associationId,
      releaseId: release.releaseId,
      manifestPath: manifestRef.path,
      releaseDigest: release.manifest.releaseDigest,
      sourceVersion: expectedSourceVersion,
      sourceSequence,
      sourceCommittedAt,
      state,
      seasonId,
      privacyEpoch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: false});
  });
  return release.releaseId;
}
