import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

// ── Types ───────────────────────────────────────────────────────────

interface PlayerSeasonStatsDoc {
  playerId: string;
  playerName: string;
  teamId: string;
  teamName?: string;
  seasonId: string;
  divisionId?: string;
  gamesPlayed: number;
  totals: Record<string, number>;
  averages: Record<string, number>;
}

interface LeaderboardEntry {
  playerId: string;
  name: string;
  teamName: string;
  value: number;
  gp: number;
}

// The 5 stat categories to rank
const CATEGORIES: { key: string; avgField: string }[] = [
  { key: "ppg", avgField: "ppg" },
  { key: "rpg", avgField: "rpg" },
  { key: "apg", avgField: "apg" },
  { key: "spg", avgField: "spg" },
  { key: "bpg", avgField: "bpg" },
];

// Minimum games to qualify for leaderboard
const MIN_GAMES = 1;

// Maximum entries per leaderboard
const MAX_ENTRIES = 50;

// ── Main function ───────────────────────────────────────────────────

/**
 * Rebuild leaderboard docs for a given association, season, and division.
 *
 * Called from onGameStatsApproved after player stats are updated.
 * Creates/updates docs at:
 *   associations/{assocId}/leaderboard/{seasonId}_{divisionId}_{category}
 */
export async function rebuildLeaderboards(
  assocId: string,
  seasonId: string,
  divisionId: string
): Promise<void> {
  const db = admin.firestore();
  const statsPath = `associations/${assocId}/playerSeasonStats`;

  // Query all player stats for this season + division
  let query: admin.firestore.Query = db
    .collection(statsPath)
    .where("seasonId", "==", seasonId);

  // Only filter by division if it's set
  if (divisionId) {
    query = query.where("divisionId", "==", divisionId);
  }

  const snapshot = await query.get();
  const allPlayers: PlayerSeasonStatsDoc[] = snapshot.docs.map(
    (doc) => doc.data() as PlayerSeasonStatsDoc
  );

  // Filter out players below minimum games threshold
  const qualified = allPlayers.filter((p) => p.gamesPlayed >= MIN_GAMES);

  logger.info(
    `Rebuilding leaderboards: assoc=${assocId}, season=${seasonId}, ` +
    `division=${divisionId}, qualified=${qualified.length}/${allPlayers.length}`
  );

  const batch = db.batch();
  const leaderboardPath = `associations/${assocId}/leaderboard`;

  for (const category of CATEGORIES) {
    // Sort by the average field, descending
    const sorted = [...qualified].sort((a, b) => {
      const aVal = a.averages[category.avgField] || 0;
      const bVal = b.averages[category.avgField] || 0;
      return bVal - aVal;
    });

    // Take top N
    const topPlayers = sorted.slice(0, MAX_ENTRIES);

    const rankings: LeaderboardEntry[] = topPlayers.map((p) => ({
      playerId: p.playerId,
      name: p.playerName,
      teamName: p.teamName || "",
      value: p.averages[category.avgField] || 0,
      gp: p.gamesPlayed,
    }));

    const docId = divisionId
      ? `${seasonId}_${divisionId}_${category.key}`
      : `${seasonId}_all_${category.key}`;

    const docRef = db.doc(`${leaderboardPath}/${docId}`);

    batch.set(docRef, {
      seasonId,
      divisionId: divisionId || null,
      category: category.key,
      updatedAt: admin.firestore.Timestamp.now(),
      rankings,
    });
  }

  await batch.commit();
  logger.info(
    `Rebuilt ${CATEGORIES.length} leaderboard docs for season=${seasonId}, division=${divisionId}`
  );
}
