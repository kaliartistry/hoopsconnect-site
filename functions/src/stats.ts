import {
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { rebuildLeaderboards } from "./leaderboard";

// ── Types ───────────────────────────────────────────────────────────

interface PlayerStatLine {
  name: string;
  teamId: string;
  pts: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  fls: number;
  min: number;
  oreb?: number;
  dreb?: number;
}

interface GameStatsDoc {
  eventId: string;
  seasonId: string;
  divisionId: string;
  homeTeamId: string;
  awayTeamId: string;
  homeTeamName: string;
  awayTeamName: string;
  homeScore: number;
  awayScore: number;
  status: string;
  submittedBy?: string;
  submittedAt?: admin.firestore.Timestamp;
  approvedBy?: string;
  approvedAt?: admin.firestore.Timestamp;
  playerLines: Record<string, PlayerStatLine>;
  homeQuarterScores?: Record<string, number>; // "1": 25, "2": 18, ...
  awayQuarterScores?: Record<string, number>;
  playerQuarterStats?: Record<string, Record<string, Record<string, number>>>;
}

interface GameLogEntry {
  eventId: string;
  date: admin.firestore.Timestamp;
  vs: string;
  pts: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  result: string;
}

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
  gameLog: GameLogEntry[];
}

interface TeamGameLogEntry {
  eventId: string;
  opponentName: string;
  opponentTeamId: string;
  date: admin.firestore.Timestamp;
  pts: number;
  oreb: number;
  dreb: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  to: number;
  fls: number;
  result: string;
  quarterScores?: Record<string, number>; // "1": 25, "2": 18, ...
  opponentQuarterScores?: Record<string, number>;
}

interface TeamStatTotals {
  pts: number;
  oreb: number;
  dreb: number;
  reb: number;
  ast: number;
  stl: number;
  blk: number;
  to: number;
  fls: number;
  min: number;
}

interface TeamStatAverages {
  ppg: number;
  rpg: number;
  apg: number;
  spg: number;
  bpg: number;
  topg: number;
  fpg: number;
}

interface TeamSeasonStatsDoc {
  teamId: string;
  teamName: string;
  seasonId: string;
  divisionId?: string;
  gamesPlayed: number;
  totals: TeamStatTotals;
  averages: TeamStatAverages;
  gameLog: TeamGameLogEntry[];
}

interface TeamStanding {
  teamId: string;
  teamName: string;
  divisionId?: string;
  wins: number;
  losses: number;
  pct: number;
  gb: number;
  streak: string;
  lastTen: string;
  pointsFor: number;
  pointsAgainst: number;
}

interface StandingsDoc {
  seasonId: string;
  divisionId?: string;
  updatedAt: admin.firestore.Timestamp;
  standings: TeamStanding[];
}

// ── Helpers ─────────────────────────────────────────────────────────

function roundAvg(total: number, gp: number): number {
  if (gp === 0) return 0;
  return Math.round((total / gp) * 10) / 10;
}

/**
 * Determine the opponent team name for a given player's team.
 */
function opponentName(
  line: PlayerStatLine,
  doc: GameStatsDoc
): string {
  return line.teamId === doc.homeTeamId
    ? doc.awayTeamName
    : doc.homeTeamName;
}

/**
 * Determine W/L result for a player's team.
 */
function gameResult(
  line: PlayerStatLine,
  doc: GameStatsDoc
): string {
  const isHome = line.teamId === doc.homeTeamId;
  if (isHome) {
    return doc.homeScore >= doc.awayScore ? "W" : "L";
  }
  return doc.awayScore >= doc.homeScore ? "W" : "L";
}

/**
 * Parse a streak string like "W3" or "L1" into { type, count }.
 */
function parseStreak(streak: string): { type: string; count: number } {
  if (!streak || streak === "-") return { type: "", count: 0 };
  const type = streak.charAt(0);
  const count = parseInt(streak.substring(1), 10) || 0;
  return { type, count };
}

/**
 * Validate a single player stat line for reasonable ranges.
 * Returns null if valid, or an error message string if invalid.
 */
function validatePlayerStatLine(playerId: string, line: PlayerStatLine): string | null {
  if (!line.name || typeof line.name !== "string") {
    return `Player ${playerId}: missing or invalid name`;
  }
  if (!line.teamId || typeof line.teamId !== "string") {
    return `Player ${playerId}: missing or invalid teamId`;
  }
  if (typeof line.pts !== "number" || line.pts < 0 || line.pts > 200) {
    return `Player ${playerId}: pts must be 0-200, got ${line.pts}`;
  }
  if (typeof line.reb !== "number" || line.reb < 0 || line.reb > 100) {
    return `Player ${playerId}: reb must be 0-100, got ${line.reb}`;
  }
  if (typeof line.ast !== "number" || line.ast < 0 || line.ast > 100) {
    return `Player ${playerId}: ast must be 0-100, got ${line.ast}`;
  }
  if (typeof line.stl !== "number" || line.stl < 0 || line.stl > 50) {
    return `Player ${playerId}: stl must be 0-50, got ${line.stl}`;
  }
  if (typeof line.blk !== "number" || line.blk < 0 || line.blk > 50) {
    return `Player ${playerId}: blk must be 0-50, got ${line.blk}`;
  }
  if (typeof line.fls !== "number" || line.fls < 0 || line.fls > 6) {
    return `Player ${playerId}: fls must be 0-6, got ${line.fls}`;
  }
  if (typeof line.min !== "number" || line.min < 0 || line.min > 48) {
    return `Player ${playerId}: min must be 0-48, got ${line.min}`;
  }
  if (line.oreb !== undefined && (typeof line.oreb !== "number" || line.oreb < 0)) {
    return `Player ${playerId}: oreb must be >= 0`;
  }
  if (line.dreb !== undefined && (typeof line.dreb !== "number" || line.dreb < 0)) {
    return `Player ${playerId}: dreb must be >= 0`;
  }
  return null;
}

/**
 * Validate the top-level game stats document fields.
 */
function validateGameStatsDoc(doc: GameStatsDoc): string | null {
  if (!doc.eventId || typeof doc.eventId !== "string") {
    return "Missing or invalid eventId";
  }
  if (!doc.seasonId || typeof doc.seasonId !== "string") {
    return "Missing or invalid seasonId";
  }
  if (!doc.homeTeamId || typeof doc.homeTeamId !== "string") {
    return "Missing or invalid homeTeamId";
  }
  if (!doc.awayTeamId || typeof doc.awayTeamId !== "string") {
    return "Missing or invalid awayTeamId";
  }
  if (typeof doc.homeScore !== "number" || doc.homeScore < 0) {
    return `Invalid homeScore: ${doc.homeScore}`;
  }
  if (typeof doc.awayScore !== "number" || doc.awayScore < 0) {
    return `Invalid awayScore: ${doc.awayScore}`;
  }
  if (!doc.status || !["draft", "submitted", "approved"].includes(doc.status)) {
    return `Invalid status: ${doc.status}`;
  }
  return null;
}

// ── Main trigger ────────────────────────────────────────────────────

/**
 * onGameStatsApproved
 *
 * Fires when any doc under associations/{assocId}/gameStats/{docId}
 * is updated. We only act when the status transitions to "approved".
 *
 * 1. For each player in playerLines:
 *    - Read or create playerSeasonStats/{playerId}_{seasonId}
 *    - Add game totals, recalculate averages, append to gameLog
 * 2. Update standings for both teams (W/L, pts for/against, streak)
 * 3. Rebuild leaderboards
 */
export const onGameStatsApproved = onDocumentUpdated(
  "associations/{assocId}/gameStats/{docId}",
  async (event) => {
    const beforeData = event.data?.before.data() as GameStatsDoc | undefined;
    const afterData = event.data?.after.data() as GameStatsDoc | undefined;

    if (!beforeData || !afterData) {
      logger.warn("onGameStatsApproved: Missing before/after data, skipping.");
      return;
    }

    // Only process when status transitions to "approved"
    if (beforeData.status === "approved" || afterData.status !== "approved") {
      return;
    }

    const assocId = event.params.assocId;
    const docId = event.params.docId;

    // ── Validate document-level fields ──────────────────────────
    const docError = validateGameStatsDoc(afterData);
    if (docError) {
      logger.error(`onGameStatsApproved: Validation failed for ${docId}: ${docError}`);
      return;
    }

    // ── Validate all player stat lines ──────────────────────────
    const playerLines = afterData.playerLines || {};
    for (const [playerId, line] of Object.entries(playerLines)) {
      const lineError = validatePlayerStatLine(playerId, line);
      if (lineError) {
        logger.error(`onGameStatsApproved: Stat validation failed: ${lineError}`);
        return;
      }
    }

    const db = admin.firestore();

    logger.info(
      `Game stats approved: assoc=${assocId}, doc=${docId}, event=${afterData.eventId}, ` +
      `${afterData.homeTeamName} ${afterData.homeScore} vs ` +
      `${afterData.awayTeamName} ${afterData.awayScore}, ` +
      `players=${Object.keys(playerLines).length}`
    );

    try {
      // ── 1. Update player season stats ────────────────────────
      const batch = db.batch();
      const statsBasePath = `associations/${assocId}/playerSeasonStats`;
      let updatedCount = 0;

      for (const [playerId, line] of Object.entries(playerLines)) {
        const compositeId = `${playerId}_${afterData.seasonId}`;
        const docRef = db.doc(`${statsBasePath}/${compositeId}`);
        const snap = await docRef.get();

        let existing: PlayerSeasonStatsDoc;

        if (snap.exists) {
          existing = snap.data() as PlayerSeasonStatsDoc;

          // If this game is already in the log, handle as a correction:
          // subtract old values and remove old entry before re-adding
          const oldEntryIdx = existing.gameLog.findIndex((g) => g.eventId === afterData.eventId);
          if (oldEntryIdx !== -1) {
            const oldEntry = existing.gameLog[oldEntryIdx];
            logger.info(
              `Correction: replacing gameLog entry for player=${playerId}, event=${afterData.eventId}`
            );
            // Subtract old game values from totals
            existing.totals.pts = (existing.totals.pts || 0) - oldEntry.pts;
            existing.totals.reb = (existing.totals.reb || 0) - oldEntry.reb;
            existing.totals.ast = (existing.totals.ast || 0) - oldEntry.ast;
            existing.totals.stl = (existing.totals.stl || 0) - oldEntry.stl;
            existing.totals.blk = (existing.totals.blk || 0) - oldEntry.blk;
            existing.gamesPlayed = Math.max(0, existing.gamesPlayed - 1);
            // Remove old entry from log
            existing.gameLog.splice(oldEntryIdx, 1);
          }
        } else {
          // Resolve team name from the gameStats doc
          const teamName =
            line.teamId === afterData.homeTeamId
              ? afterData.homeTeamName
              : afterData.awayTeamName;

          existing = {
            playerId,
            playerName: line.name,
            teamId: line.teamId,
            teamName,
            seasonId: afterData.seasonId,
            divisionId: afterData.divisionId,
            gamesPlayed: 0,
            totals: { pts: 0, reb: 0, ast: 0, stl: 0, blk: 0, min: 0, fls: 0, oreb: 0, dreb: 0 },
            averages: { ppg: 0, rpg: 0, apg: 0, spg: 0, bpg: 0 },
            gameLog: [],
          };
        }

        const gp = existing.gamesPlayed + 1;

        const newTotals: Record<string, number> = {
          pts: (existing.totals.pts || 0) + line.pts,
          reb: (existing.totals.reb || 0) + line.reb,
          ast: (existing.totals.ast || 0) + line.ast,
          stl: (existing.totals.stl || 0) + line.stl,
          blk: (existing.totals.blk || 0) + line.blk,
          min: (existing.totals.min || 0) + line.min,
          fls: (existing.totals.fls || 0) + line.fls,
          oreb: (existing.totals.oreb || 0) + (line.oreb || 0),
          dreb: (existing.totals.dreb || 0) + (line.dreb || 0),
        };

        const newAverages: Record<string, number> = {
          ppg: roundAvg(newTotals.pts, gp),
          rpg: roundAvg(newTotals.reb, gp),
          apg: roundAvg(newTotals.ast, gp),
          spg: roundAvg(newTotals.stl, gp),
          bpg: roundAvg(newTotals.blk, gp),
        };

        const approvedAt = afterData.approvedAt || admin.firestore.Timestamp.now();

        const logEntry: GameLogEntry = {
          eventId: afterData.eventId,
          date: approvedAt,
          vs: opponentName(line, afterData),
          pts: line.pts,
          reb: line.reb,
          ast: line.ast,
          stl: line.stl,
          blk: line.blk,
          result: gameResult(line, afterData),
        };

        const updatedDoc: PlayerSeasonStatsDoc = {
          ...existing,
          gamesPlayed: gp,
          totals: newTotals,
          averages: newAverages,
          gameLog: [...existing.gameLog, logEntry],
        };

        batch.set(docRef, updatedDoc, { merge: true });
        updatedCount++;
      }

      await batch.commit();
      logger.info(`Updated playerSeasonStats for ${updatedCount} players.`);

      // ── 2. Update team season stats ────────────────────────
      await updateTeamSeasonStats(db, assocId, afterData);

      // ── 3. Update standings ──────────────────────────────────
      await updateStandings(db, assocId, afterData);

      // ── 4. Rebuild leaderboards ──────────────────────────────
      await rebuildLeaderboards(assocId, afterData.seasonId, afterData.divisionId);

      logger.info("onGameStatsApproved completed successfully.");
    } catch (err) {
      logger.error(`onGameStatsApproved failed for doc=${docId}:`, err);
      throw err; // Re-throw so Cloud Functions marks it as failed
    }
  }
);

/**
 * Update team season stats for both home and away teams.
 * Doc id: {teamId}_{seasonId}
 *
 * Aggregates all player stat lines by team, accumulates totals,
 * recalculates averages, and appends to the team game log.
 */
async function updateTeamSeasonStats(
  db: admin.firestore.Firestore,
  assocId: string,
  game: GameStatsDoc
): Promise<void> {
  const basePath = `associations/${assocId}/teamSeasonStats`;
  const playerLines = game.playerLines || {};

  // Aggregate player lines by team for this game
  const teamGameTotals: Record<string, TeamStatTotals> = {};
  for (const [, line] of Object.entries(playerLines)) {
    if (!teamGameTotals[line.teamId]) {
      teamGameTotals[line.teamId] = {
        pts: 0, oreb: 0, dreb: 0, reb: 0,
        ast: 0, stl: 0, blk: 0, to: 0, fls: 0, min: 0,
      };
    }
    const t = teamGameTotals[line.teamId];
    t.pts += line.pts || 0;
    t.oreb += line.oreb || 0;
    t.dreb += line.dreb || 0;
    t.reb += line.reb || 0;
    t.ast += line.ast || 0;
    t.stl += line.stl || 0;
    t.blk += line.blk || 0;
    t.to += 0; // turnovers not tracked per-player yet
    t.fls += line.fls || 0;
    t.min += line.min || 0;
  }

  // Process each team (home and away)
  const teams = [
    { teamId: game.homeTeamId, teamName: game.homeTeamName, opponentName: game.awayTeamName, opponentTeamId: game.awayTeamId, isHome: true },
    { teamId: game.awayTeamId, teamName: game.awayTeamName, opponentName: game.homeTeamName, opponentTeamId: game.homeTeamId, isHome: false },
  ];

  for (const team of teams) {
    const compositeId = `${team.teamId}_${game.seasonId}`;
    const docRef = db.doc(`${basePath}/${compositeId}`);
    const snap = await docRef.get();

    let existing: TeamSeasonStatsDoc;

    if (snap.exists) {
      existing = snap.data() as TeamSeasonStatsDoc;

      // If this game is already in the log, handle as a correction:
      // subtract old values and remove old entry before re-adding
      const oldIdx = existing.gameLog.findIndex((g) => g.eventId === game.eventId);
      if (oldIdx !== -1) {
        const oldEntry = existing.gameLog[oldIdx];
        logger.info(
          `Correction: replacing team gameLog entry for team=${team.teamId}, event=${game.eventId}`
        );
        // Subtract old game values from totals
        existing.totals.pts = (existing.totals.pts || 0) - oldEntry.pts;
        existing.totals.oreb = (existing.totals.oreb || 0) - oldEntry.oreb;
        existing.totals.dreb = (existing.totals.dreb || 0) - oldEntry.dreb;
        existing.totals.reb = (existing.totals.reb || 0) - oldEntry.reb;
        existing.totals.ast = (existing.totals.ast || 0) - oldEntry.ast;
        existing.totals.stl = (existing.totals.stl || 0) - oldEntry.stl;
        existing.totals.blk = (existing.totals.blk || 0) - oldEntry.blk;
        existing.totals.to = (existing.totals.to || 0) - oldEntry.to;
        existing.totals.fls = (existing.totals.fls || 0) - oldEntry.fls;
        existing.gamesPlayed = Math.max(0, existing.gamesPlayed - 1);
        // Remove old entry from log
        existing.gameLog.splice(oldIdx, 1);
      }
    } else {
      existing = {
        teamId: team.teamId,
        teamName: team.teamName,
        seasonId: game.seasonId,
        divisionId: game.divisionId,
        gamesPlayed: 0,
        totals: { pts: 0, oreb: 0, dreb: 0, reb: 0, ast: 0, stl: 0, blk: 0, to: 0, fls: 0, min: 0 },
        averages: { ppg: 0, rpg: 0, apg: 0, spg: 0, bpg: 0, topg: 0, fpg: 0 },
        gameLog: [],
      };
    }

    const gameTotals = teamGameTotals[team.teamId] || {
      pts: 0, oreb: 0, dreb: 0, reb: 0, ast: 0, stl: 0, blk: 0, to: 0, fls: 0, min: 0,
    };

    const gp = existing.gamesPlayed + 1;

    const newTotals: TeamStatTotals = {
      pts: (existing.totals.pts || 0) + gameTotals.pts,
      oreb: (existing.totals.oreb || 0) + gameTotals.oreb,
      dreb: (existing.totals.dreb || 0) + gameTotals.dreb,
      reb: (existing.totals.reb || 0) + gameTotals.reb,
      ast: (existing.totals.ast || 0) + gameTotals.ast,
      stl: (existing.totals.stl || 0) + gameTotals.stl,
      blk: (existing.totals.blk || 0) + gameTotals.blk,
      to: (existing.totals.to || 0) + gameTotals.to,
      fls: (existing.totals.fls || 0) + gameTotals.fls,
      min: (existing.totals.min || 0) + gameTotals.min,
    };

    const newAverages: TeamStatAverages = {
      ppg: roundAvg(newTotals.pts, gp),
      rpg: roundAvg(newTotals.reb, gp),
      apg: roundAvg(newTotals.ast, gp),
      spg: roundAvg(newTotals.stl, gp),
      bpg: roundAvg(newTotals.blk, gp),
      topg: roundAvg(newTotals.to, gp),
      fpg: roundAvg(newTotals.fls, gp),
    };

    // Determine W/L for this team
    const isHome = team.isHome;
    const won = isHome
      ? game.homeScore > game.awayScore
      : game.awayScore > game.homeScore;
    const result = won ? "W" : "L";

    const approvedAt = game.approvedAt || admin.firestore.Timestamp.now();

    // Include quarter scores in the team game log if available
    const teamQScores = team.isHome
      ? game.homeQuarterScores
      : game.awayQuarterScores;
    const oppQScores = team.isHome
      ? game.awayQuarterScores
      : game.homeQuarterScores;

    const logEntry: TeamGameLogEntry = {
      eventId: game.eventId,
      opponentName: team.opponentName,
      opponentTeamId: team.opponentTeamId,
      date: approvedAt,
      pts: gameTotals.pts,
      oreb: gameTotals.oreb,
      dreb: gameTotals.dreb,
      reb: gameTotals.reb,
      ast: gameTotals.ast,
      stl: gameTotals.stl,
      blk: gameTotals.blk,
      to: gameTotals.to,
      fls: gameTotals.fls,
      result,
      ...(teamQScores ? { quarterScores: teamQScores } : {}),
      ...(oppQScores ? { opponentQuarterScores: oppQScores } : {}),
    };

    const updatedDoc: TeamSeasonStatsDoc = {
      ...existing,
      gamesPlayed: gp,
      totals: newTotals,
      averages: newAverages,
      gameLog: [...existing.gameLog, logEntry],
    };

    await docRef.set(updatedDoc, { merge: true });
    logger.info(`Updated teamSeasonStats for team=${team.teamId}, gp=${gp}`);
  }
}

/**
 * Update the standings doc for the game's season+division.
 * Doc id: {seasonId}_{divisionId}
 */
async function updateStandings(
  db: admin.firestore.Firestore,
  assocId: string,
  game: GameStatsDoc
): Promise<void> {
  const standingsPath = `associations/${assocId}/standings`;
  const divisionId = game.divisionId || "all";
  const standingsId = `${game.seasonId}_${divisionId}`;
  const docRef = db.doc(`${standingsPath}/${standingsId}`);

  try {
    const snap = await docRef.get();
    let standingsDoc: StandingsDoc;

    if (snap.exists) {
      standingsDoc = snap.data() as StandingsDoc;
    } else {
      standingsDoc = {
        seasonId: game.seasonId,
        divisionId: game.divisionId,
        updatedAt: admin.firestore.Timestamp.now(),
        standings: [],
      };
    }

    const standings = [...standingsDoc.standings];

    // Idempotency / correction check: track processed events with their scores
    // so we can reverse standings if a game is corrected and re-approved
    interface ProcessedEvent {
      eventId: string;
      homeScore: number;
      awayScore: number;
      homeTeamId: string;
      awayTeamId: string;
    }
    const processedEvents: ProcessedEvent[] =
      (snap.exists && (snap.data() as any).processedEvents) || [];
    // Also support legacy string[] format from before correction support
    const legacyIds: string[] = (snap.exists && (snap.data() as any).processedEventIds) || [];
    const existingProcessed = processedEvents.find((e) => e.eventId === game.eventId);
    const isLegacyDuplicate = !existingProcessed && legacyIds.includes(game.eventId);

    if (isLegacyDuplicate) {
      // Legacy duplicate without stored scores — skip safely
      logger.info(`Skipping legacy duplicate standings update for event=${game.eventId}`);
      return;
    }

    if (existingProcessed) {
      // Correction: reverse the old result before applying the new one
      logger.info(
        `Correction: reversing old standings for event=${game.eventId} ` +
        `(old: ${existingProcessed.homeScore}-${existingProcessed.awayScore})`
      );
      const oldHomeWon = existingProcessed.homeScore > existingProcessed.awayScore;
      const oldHomeEntry = standings.find((s) => s.teamId === existingProcessed.homeTeamId);
      const oldAwayEntry = standings.find((s) => s.teamId === existingProcessed.awayTeamId);
      if (oldHomeEntry && oldAwayEntry) {
        if (oldHomeWon) {
          oldHomeEntry.wins = Math.max(0, oldHomeEntry.wins - 1);
          oldAwayEntry.losses = Math.max(0, oldAwayEntry.losses - 1);
        } else {
          oldAwayEntry.wins = Math.max(0, oldAwayEntry.wins - 1);
          oldHomeEntry.losses = Math.max(0, oldHomeEntry.losses - 1);
        }
        oldHomeEntry.pointsFor = Math.max(0, oldHomeEntry.pointsFor - existingProcessed.homeScore);
        oldHomeEntry.pointsAgainst = Math.max(0, oldHomeEntry.pointsAgainst - existingProcessed.awayScore);
        oldAwayEntry.pointsFor = Math.max(0, oldAwayEntry.pointsFor - existingProcessed.awayScore);
        oldAwayEntry.pointsAgainst = Math.max(0, oldAwayEntry.pointsAgainst - existingProcessed.homeScore);
      }
      // Remove old processed entry so we can re-add with new scores
      const oldIdx = processedEvents.indexOf(existingProcessed);
      if (oldIdx !== -1) processedEvents.splice(oldIdx, 1);
    }

    // Find or create entries for home and away teams
    let homeEntry = standings.find((s) => s.teamId === game.homeTeamId);
    let awayEntry = standings.find((s) => s.teamId === game.awayTeamId);

    if (!homeEntry) {
      homeEntry = {
        teamId: game.homeTeamId,
        teamName: game.homeTeamName,
        divisionId: game.divisionId,
        wins: 0,
        losses: 0,
        pct: 0,
        gb: 0,
        streak: "-",
        lastTen: "-",
        pointsFor: 0,
        pointsAgainst: 0,
      };
      standings.push(homeEntry);
    }

    if (!awayEntry) {
      awayEntry = {
        teamId: game.awayTeamId,
        teamName: game.awayTeamName,
        divisionId: game.divisionId,
        wins: 0,
        losses: 0,
        pct: 0,
        gb: 0,
        streak: "-",
        lastTen: "-",
        pointsFor: 0,
        pointsAgainst: 0,
      };
      standings.push(awayEntry);
    }

    // Apply W/L
    const homeWon = game.homeScore > game.awayScore;

    if (homeWon) {
      homeEntry.wins += 1;
      awayEntry.losses += 1;
    } else {
      awayEntry.wins += 1;
      homeEntry.losses += 1;
    }

    // Update points for/against
    homeEntry.pointsFor += game.homeScore;
    homeEntry.pointsAgainst += game.awayScore;
    awayEntry.pointsFor += game.awayScore;
    awayEntry.pointsAgainst += game.homeScore;

    // Recalculate pct
    for (const entry of [homeEntry, awayEntry]) {
      const total = entry.wins + entry.losses;
      entry.pct = total > 0 ? Math.round((entry.wins / total) * 1000) / 1000 : 0;

      // Update streak
      const result = entry === homeEntry ? (homeWon ? "W" : "L") : (homeWon ? "L" : "W");
      const prev = parseStreak(entry.streak);
      if (prev.type === result) {
        entry.streak = `${result}${prev.count + 1}`;
      } else {
        entry.streak = `${result}1`;
      }
    }

    // Sort standings by pct descending
    standings.sort((a, b) => b.pct - a.pct);

    // Recalculate GB relative to first place
    const leader = standings[0];
    for (const entry of standings) {
      entry.gb =
        ((leader.wins - leader.losses) - (entry.wins - entry.losses)) / 2;
    }

    await docRef.set({
      seasonId: game.seasonId,
      divisionId: game.divisionId,
      updatedAt: admin.firestore.Timestamp.now(),
      standings,
      processedEvents: [...processedEvents, {
        eventId: game.eventId,
        homeScore: game.homeScore,
        awayScore: game.awayScore,
        homeTeamId: game.homeTeamId,
        awayTeamId: game.awayTeamId,
      }],
    });

    logger.info(`Updated standings for ${standingsId}`);
  } catch (err) {
    logger.error(`Failed to update standings for ${standingsId}:`, err);
    throw err;
  }
}
