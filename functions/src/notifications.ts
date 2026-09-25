import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import {createHash} from "node:crypto";
import {capabilities} from "./authorization";
import {
  FavoriteTeamAudienceRecipient,
  loadAuthorizedRecipients,
  loadFavoriteTeamAudience,
  loadFavoriteTeamRecipients,
  loadTeamAcknowledgmentRecipients,
  selectFavoriteTeamRecipients,
} from "./notification_authorization";

// ── Types ───────────────────────────────────────────────────────────

interface AckExpectedEntry {
  name: string;
  teamName: string;
  phone?: string;
}

interface PostDoc {
  authorId: string;
  authorName: string;
  authorRole: string;
  teamId?: string;
  teamName?: string;
  type: string;
  title: string;
  body: string;
  divisionFilter?: string;
  pinned: boolean;
  urgent: boolean;
  createdAt: admin.firestore.Timestamp;
  requiresAck: boolean;
  ackDeadline?: admin.firestore.Timestamp;
  ackTargetScope?: string;
  expectedAcks: Record<string, AckExpectedEntry>;
  ackStatus: Record<string, { ackedAt: admin.firestore.Timestamp; name: string; teamName: string }>;
  ackRemindersSent: number;
}

// ── Validation helpers ──────────────────────────────────────────────

function isValidPostDoc(data: unknown): data is PostDoc {
  if (!data || typeof data !== "object") return false;
  const d = data as Record<string, unknown>;
  return (
    typeof d.authorId === "string" &&
    typeof d.title === "string" &&
    typeof d.body === "string" &&
    typeof d.type === "string" &&
    typeof d.requiresAck === "boolean"
  );
}

// ── onPostCreatedWithAck ────────────────────────────────────────────

/**
 * When a post is created that requiresAck:
 * 1. Look up all team reps (optionally filtered by division)
 * 2. Populate the expectedAcks map on the post
 * 3. Send FCM push notification to each rep's fcmTokens
 */
export const onPostCreatedWithAck = onDocumentCreated(
  "associations/{assocId}/posts/{postId}",
  async (event) => {
    const rawData = event.data?.data();

    if (!rawData) {
      logger.warn("onPostCreatedWithAck: No data on created post, skipping.");
      return;
    }

    if (!isValidPostDoc(rawData)) {
      logger.error("onPostCreatedWithAck: Post data failed validation, skipping.", {
        keys: Object.keys(rawData),
      });
      return;
    }

    const postData = rawData as PostDoc;

    if (!postData.requiresAck) {
      return;
    }

    const assocId = event.params.assocId;
    const postId = event.params.postId;
    const db = admin.firestore();

    logger.info(
      `Post created with ack: assoc=${assocId}, post=${postId}, ` +
      `title="${postData.title}", scope=${postData.ackTargetScope || "all"}, ` +
      `urgent=${postData.urgent}`
    );

    try {
      const recipients = await loadTeamAcknowledgmentRecipients(
        db,
        assocId,
        {divisionId: postData.divisionFilter},
      );
      const expectedAcks: Record<string, AckExpectedEntry> = {};
      const allTokens: string[] = [];

      for (const recipient of recipients) {
        expectedAcks[recipient.uid] = {
          name: recipient.displayName,
          teamName: recipient.teamName,
        };
        if (recipient.notificationPrefs.newPosts !== false) {
          allTokens.push(...recipient.fcmTokens);
        }
      }

      // Update the post with expectedAcks
      const postRef = db.doc(`associations/${assocId}/posts/${postId}`);
      await postRef.update({ expectedAcks });

      logger.info(
        `Populated ${Object.keys(expectedAcks).length} expectedAcks for post ${postId}`
      );

      // Send FCM notifications
      if (allTokens.length > 0) {
        await sendMulticast(allTokens, {
          title: postData.urgent ? `[URGENT] ${postData.title}` : postData.title,
          body: `New post requires your acknowledgment${
            postData.ackDeadline
              ? ` by ${postData.ackDeadline.toDate().toLocaleDateString()}`
              : ""
          }`,
          data: {
            type: "ack_required",
            postId,
            assocId,
          },
        });
      }
    } catch (err) {
      logger.error(`onPostCreatedWithAck failed for post=${postId}:`, err);
      throw err;
    }
  }
);

// ── onAckWrite ──────────────────────────────────────────────────────

/**
 * When a post is updated, check whether the ack count just reached the
 * expected count. If so, archive the post so it disappears from the
 * tracker (wireframe §02 A1) and notify the author.
 */
export const onAckWrite = onDocumentUpdated(
  "associations/{assocId}/posts/{postId}",
  async (event) => {
    const before = event.data?.before.data() as PostDoc | undefined;
    const after = event.data?.after.data() as PostDoc | undefined;
    if (!before || !after) return;

    if (!after.requiresAck) return;
    if ((after as PostDoc & { archived?: boolean }).archived === true) return;

    const expectedIds = Object.keys(after.expectedAcks || {});
    const ackedIds = new Set(Object.keys(after.ackStatus || {}));
    const beforeAckedIds = new Set(Object.keys(before.ackStatus || {}));
    const assocId = event.params.assocId;
    const postId = event.params.postId;
    const activeExpectedRecipients = await loadAuthorizedRecipients(
      admin.firestore(),
      assocId,
      capabilities.postsAcknowledge,
      {userIds: expectedIds},
    );
    const activeExpectedIds = activeExpectedRecipients.map((recipient) => recipient.uid);
    const expected = activeExpectedIds.length;
    const acked = activeExpectedIds.filter((id) => ackedIds.has(id)).length;
    const ackedBefore = activeExpectedIds.filter((id) => beforeAckedIds.has(id)).length;

    // Only act on the *transition* to fully-acked, not subsequent writes.
    if (expected === 0) return;
    if (!activeExpectedIds.every((id) => ackedIds.has(id))) return;
    if (ackedBefore >= expected) return;

    logger.info(
      `All acks landed: assoc=${assocId}, post=${postId}, count=${acked}/${expected} — archiving.`
    );

    try {
      await event.data?.after.ref.update({
        archived: true,
        archivedAt: admin.firestore.Timestamp.now(),
      });

      // Notify the author so they know the loop is closed.
      const authors = await loadAuthorizedRecipients(
        admin.firestore(),
        assocId,
        capabilities.postsManage,
        {userIds: [after.authorId]},
      );
      if (authors[0]?.fcmTokens.length) {
          await sendMulticast(authors[0].fcmTokens, {
            title: "All reps acknowledged",
            body: `"${after.title}" is fully acknowledged.`,
            data: {
              type: "ack_complete",
              postId,
              assocId,
            },
          });
      }
    } catch (err) {
      logger.error(`onAckWrite failed for post=${postId}:`, err);
    }
  }
);

// ── ackDeadlineChecker ──────────────────────────────────────────────

/**
 * Runs daily at 8:00 AM Jamaica time.
 * Finds posts with ack deadlines that have passed but still have
 * unacked reps, and sends reminder notifications.
 */
export const ackDeadlineChecker = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/Jamaica",
  },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    logger.info("Running ackDeadlineChecker...");

    try {
      // Get all associations
      const assocSnap = await db.collection("associations").get();

      let totalOverdue = 0;
      let totalReminders = 0;

      for (const assocDoc of assocSnap.docs) {
        const assocId = assocDoc.id;
        const postsPath = `associations/${assocId}/posts`;

        // Query posts that require ack and have a deadline that's passed
        const overdueSnap = await db
          .collection(postsPath)
          .where("requiresAck", "==", true)
          .where("ackDeadline", "<=", now)
          .get();

        for (const postDoc of overdueSnap.docs) {
          const post = postDoc.data() as PostDoc;

          // Validate expected fields exist
          if (!post.expectedAcks || typeof post.expectedAcks !== "object") {
            logger.warn(`Post ${postDoc.id} has requiresAck=true but no expectedAcks map.`);
            continue;
          }

          // Find reps who haven't acked yet
          const expectedIds = Object.keys(post.expectedAcks);
          const ackedIds = new Set(Object.keys(post.ackStatus || {}));
          const unackedIds = expectedIds.filter((id) => !ackedIds.has(id));

          if (unackedIds.length === 0) continue;

          totalOverdue++;

          logger.info(
            `Overdue ack: assoc=${assocId}, post=${postDoc.id}, ` +
            `unacked=${unackedIds.length}/${expectedIds.length}`
          );

          // Collect FCM tokens for unacked reps
          const recipients = await loadAuthorizedRecipients(
            db,
            assocId,
            capabilities.postsAcknowledge,
            {userIds: unackedIds, preference: "ackReminders"},
          );
          const tokens = recipients.flatMap((recipient) => recipient.fcmTokens);

          if (tokens.length > 0) {
            await sendMulticast(tokens, {
              title: "Overdue Acknowledgment",
              body: `You have not acknowledged: "${post.title}". Please respond ASAP.`,
              data: {
                type: "ack_reminder",
                postId: postDoc.id,
                assocId,
              },
            });
            totalReminders++;
          }

          // Increment reminder counter
          await postDoc.ref.update({
            ackRemindersSent: (post.ackRemindersSent || 0) + 1,
          });
        }
      }

      logger.info(
        `ackDeadlineChecker completed: ${totalOverdue} overdue posts, ${totalReminders} reminders sent.`
      );
    } catch (err) {
      logger.error("ackDeadlineChecker failed:", err);
      throw err;
    }
  }
);

// ── statDeadlineReminder ────────────────────────────────────────────

/**
 * Runs daily at 9:00 AM Jamaica time.
 * Finds game events older than 48 hours that still have pending stats,
 * and sends a reminder FCM to all admins in that association.
 */
export const statDeadlineReminder = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "America/Jamaica",
  },
  async () => {
    const db = admin.firestore();

    // 48 hours ago
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 48 * 60 * 60 * 1000)
    );

    logger.info("Running statDeadlineReminder...");

    try {
      const assocSnap = await db.collection("associations").get();

      let totalStale = 0;

      for (const assocDoc of assocSnap.docs) {
        const assocId = assocDoc.id;
        const eventsPath = `associations/${assocId}/events`;

        // Query game events older than 48h with pending stats
        const staleSnap = await db
          .collection(eventsPath)
          .where("type", "==", "game")
          .where("statsStatus", "==", "pending")
          .where("startTime", "<=", cutoff)
          .get();

        if (staleSnap.empty) continue;

        totalStale += staleSnap.size;

        logger.info(
          `Found ${staleSnap.size} games with pending stats for assoc=${assocId}`
        );

        const statRecipients = await loadAuthorizedRecipients(
          db,
          assocId,
          capabilities.statsEnter,
          {preference: "statReminders"},
        );
        const adminTokens = statRecipients.flatMap((recipient) => recipient.fcmTokens);

        if (adminTokens.length === 0) {
          logger.warn(`No admin FCM tokens found for assoc=${assocId}, skipping notification.`);
          continue;
        }

        // Build message listing overdue games
        const gameNames = staleSnap.docs
          .map((d) => {
            const title = d.data().title;
            return typeof title === "string" ? title : `Game ${d.id}`;
          })
          .slice(0, 5);
        const moreCount = staleSnap.size > 5 ? ` (+${staleSnap.size - 5} more)` : "";

        await sendMulticast(adminTokens, {
          title: "Stats Entry Reminder",
          body: `${staleSnap.size} game(s) need stats: ${gameNames.join(", ")}${moreCount}`,
          data: {
            type: "stat_reminder",
            assocId,
          },
        });
      }

      logger.info(`statDeadlineReminder completed: ${totalStale} total stale games found.`);
    } catch (err) {
      logger.error("statDeadlineReminder failed:", err);
      throw err;
    }
  }
);

// ── FCM Helper ──────────────────────────────────────────────────────

type PublicTeamUpdate = {
  type: "favorite_team_final" | "favorite_team_schedule";
  gameId: string;
  divisionId: string;
  homeTeamId: string;
  awayTeamId: string;
  homeTeamName: string;
  awayTeamName: string;
  homeScore?: number;
  awayScore?: number;
  resultVersion?: string;
  scheduleRevision?: string;
  scheduleMessage?: string;
  isNewSchedule?: boolean;
};

function isCertifiedPublicRelease(data: Record<string, unknown> | undefined): boolean {
  return data?.schemaVersion === 1 && data.published === true &&
    data.certificationStatus === "certified" &&
    (data.publication === undefined ||
      (typeof data.publication === "object" && data.publication !== null &&
        ((data.publication as Record<string, unknown>).state === undefined ||
          (data.publication as Record<string, unknown>).state === "published")));
}

function publicGame(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const game = value as Record<string, unknown>;
  return typeof game.gameId === "string" && typeof game.divisionId === "string" &&
    typeof game.homeTeamId === "string" && typeof game.awayTeamId === "string" &&
    typeof game.homeTeamName === "string" && typeof game.awayTeamName === "string" ? game : null;
}

function gameTimeMillis(value: unknown): number | null {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function scheduleFingerprint(game: Record<string, unknown>): string {
  return createHash("sha256").update(JSON.stringify([
    game.status, gameTimeMillis(game.startTime), game.venue ?? null,
    game.homeTeamId, game.awayTeamId,
  ])).digest("hex");
}

/** Changes in a certified public release only; never alert from private stats. */
export function publicTeamUpdateCandidates(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
  releaseTimeMillis = Date.now(),
): PublicTeamUpdate[] {
  if (!isCertifiedPublicRelease(before) || !isCertifiedPublicRelease(after) ||
    !Array.isArray(before?.schedule) || !Array.isArray(after?.schedule)) return [];
  const oldGames = new Map<string, Record<string, unknown>>();
  for (const raw of before.schedule) {
    const game = publicGame(raw);
    if (game) oldGames.set(game.gameId as string, game);
  }
  const changes: PublicTeamUpdate[] = [];
  for (const raw of after.schedule) {
    const game = publicGame(raw);
    if (!game) continue;
    const old = oldGames.get(game.gameId as string);
    const base = {
      gameId: game.gameId as string,
      divisionId: game.divisionId as string,
      homeTeamId: game.homeTeamId as string,
      awayTeamId: game.awayTeamId as string,
      homeTeamName: game.homeTeamName as string,
      awayTeamName: game.awayTeamName as string,
    };
    if (game.status === "final" && typeof game.homeScore === "number" &&
      typeof game.awayScore === "number") {
      if (!old || old.status !== "final" || old.homeScore !== game.homeScore ||
        old.awayScore !== game.awayScore) {
        changes.push({
          ...base, type: "favorite_team_final",
          homeScore: game.homeScore, awayScore: game.awayScore,
          resultVersion: typeof game.resultVersion === "string" ? game.resultVersion : undefined,
        });
      }
      continue;
    }
    if (!["scheduled", "postponed", "canceled", "cancelled"].includes(String(game.status))) {
      continue;
    }
    const time = gameTimeMillis(game.startTime);
    if (time === null || (!old && time <= releaseTimeMillis) || old?.status === "final") continue;
    const revision = scheduleFingerprint(game);
    if (old && scheduleFingerprint(old) === revision) continue;
    changes.push({
      ...base, type: "favorite_team_schedule", scheduleRevision: revision,
      isNewSchedule: !old,
      scheduleMessage: !old ? "New game scheduled." :
        game.status === "postponed" ? "Game postponed." :
        game.status === "canceled" || game.status === "cancelled" ? "Game canceled." :
        "Game schedule updated.",
    });
  }
  return changes;
}

/** Keep a delayed event only when its public outcome is still the current one. */
export function currentPublicTeamUpdates(
  changes: PublicTeamUpdate[],
  current: Record<string, unknown> | undefined,
): PublicTeamUpdate[] {
  if (!isCertifiedPublicRelease(current) || !Array.isArray(current?.schedule)) return [];
  const currentGames = new Map<string, Record<string, unknown>>();
  for (const raw of current.schedule) {
    const game = publicGame(raw);
    if (game) currentGames.set(game.gameId as string, game);
  }
  return changes.filter((change) => {
    const game = currentGames.get(change.gameId);
    if (!game) return false;
    if (change.type === "favorite_team_final") {
      return game.status === "final" &&
        game.homeScore === change.homeScore && game.awayScore === change.awayScore &&
        (change.resultVersion === undefined || game.resultVersion === change.resultVersion);
    }
    return scheduleFingerprint(game) === change.scheduleRevision;
  });
}

export const onPublicSnapshotPublished = onDocumentUpdated(
  {
    document: "publicData/{assocId}/snapshots/current",
    retry: true,
    timeoutSeconds: 540,
  },
  async (event) => {
    const snapshotChange = event.data;
    if (!snapshotChange) return;
    const before = snapshotChange.before.data();
    const after = snapshotChange.after.data();
    if (after?.associationId !== event.params.assocId) return;
    const releasedAt = snapshotChange.after.updateTime;
    if (!releasedAt) {
      logger.error("Public snapshot update has no server update time; refusing alerts.");
      return;
    }
    const releaseChanges = publicTeamUpdateCandidates(before, after, releasedAt.toMillis());
    if (releaseChanges.length === 0) return;
    const db = admin.firestore();
    const current = await snapshotChange.after.ref.get();
    const currentRelease = current.data();
    if (currentRelease?.associationId !== event.params.assocId) return;
    const changes = currentPublicTeamUpdates(releaseChanges, currentRelease);
    if (changes.length === 0) return;
    const audience = await loadFavoriteTeamAudience(db, event.params.assocId);
    const releaseNewGames = releaseChanges.filter((change) =>
      change.type === "favorite_team_schedule" && change.isNewSchedule);
    const newGames = changes.filter((change) =>
      change.type === "favorite_team_schedule" && change.isNewSchedule);
    if (releaseNewGames.length > 5 && newGames.length > 0) {
      await notifyFavoriteTeamScheduleDigestFans({
        db,
        associationId: event.params.assocId,
        changes: newGames,
        idChanges: releaseNewGames,
        leagues: currentRelease?.leagues,
        audience,
      });
    }
    for (const change of changes) {
      if (releaseNewGames.length > 5 && change.isNewSchedule) continue;
      const leagueIds = leaguesForDivision(currentRelease?.leagues, change.divisionId);
      if (change.type === "favorite_team_final") {
        await notifyFavoriteTeamFans({
          db, associationId: event.params.assocId, ...change,
          homeScore: change.homeScore!, awayScore: change.awayScore!, leagueIds,
          audience,
        });
      } else {
        await notifyFavoriteTeamScheduleFans({
          db, associationId: event.params.assocId, ...change,
          title: `Schedule: ${change.homeTeamName} vs ${change.awayTeamName}`,
          body: `${change.scheduleMessage} Open HoopsConnect for game details.`,
          scheduleRevision: change.scheduleRevision!, leagueIds, audience,
        });
      }
    }
  }
);

interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export async function notifyFavoriteTeamScheduleDigestFans(input: {
  db: admin.firestore.Firestore;
  associationId: string;
  changes: PublicTeamUpdate[];
  idChanges?: PublicTeamUpdate[];
  leagues: unknown;
  audience: FavoriteTeamAudienceRecipient[];
}): Promise<number> {
  const revisions = (input.idChanges ?? input.changes)
    .map((change) => `${change.gameId}:${change.scheduleRevision}`)
    .sort();
  const digestId = createHash("sha256")
    .update(JSON.stringify(revisions)).digest("hex");
  const teamIds = [...new Set(input.changes.flatMap((change) =>
    [change.homeTeamId, change.awayTeamId]))];
  const leagueIds = [...new Set(input.changes.flatMap((change) =>
    leaguesForDivision(input.leagues, change.divisionId)))];
  return deliverFavoriteTeamUpdate({
    db: input.db,
    associationId: input.associationId,
    teamIds,
    leagueIds,
    audience: input.audience,
    type: "favorite_team_schedule",
    notificationId: `favorite_team_schedule_digest_${digestId}`,
    title: "New games scheduled",
    body: "Teams or leagues you follow have new games. Open the schedule for details.",
  });
}

export async function notifyFavoriteTeamFans(input: {
  db: admin.firestore.Firestore;
  associationId: string;
  gameId: string;
  divisionId: string;
  homeTeamId: string;
  awayTeamId: string;
  homeTeamName: string;
  awayTeamName: string;
  homeScore: number;
  awayScore: number;
  resultVersion?: string;
  leagueIds?: string[];
  audience?: FavoriteTeamAudienceRecipient[];
}): Promise<number> {
  const title = `Final: ${input.homeTeamName} ${input.homeScore}, ${input.awayTeamName} ${input.awayScore}`;
  const body = "The final score is ready. Open HoopsConnect for the game details.";
  const revision = input.resultVersion ?? createHash("sha256")
    .update(`${input.homeScore}:${input.awayScore}`)
    .digest("hex");
  return deliverFavoriteTeamUpdate({
    ...input,
    teamIds: [input.homeTeamId, input.awayTeamId],
    type: "favorite_team_final",
    notificationId: `favorite_team_final_${input.gameId}_${revision}`,
    title,
    body,
  });
}

export async function notifyFavoriteTeamScheduleFans(input: {
  db: admin.firestore.Firestore;
  associationId: string;
  gameId: string;
  divisionId: string;
  homeTeamId: string;
  awayTeamId: string;
  title: string;
  body: string;
  scheduleRevision: string;
  leagueIds?: string[];
  audience?: FavoriteTeamAudienceRecipient[];
}): Promise<number> {
  return deliverFavoriteTeamUpdate({
    ...input,
    teamIds: [input.homeTeamId, input.awayTeamId],
    type: "favorite_team_schedule",
    notificationId: `favorite_team_schedule_${input.gameId}_${input.scheduleRevision}`,
  });
}

async function deliverFavoriteTeamUpdate(input: {
  db: admin.firestore.Firestore;
  associationId: string;
  gameId?: string;
  divisionId?: string;
  teamIds: string[];
  leagueIds?: string[];
  audience?: FavoriteTeamAudienceRecipient[];
  type: "favorite_team_final" | "favorite_team_schedule";
  notificationId: string;
  title: string;
  body: string;
}): Promise<number> {
  let leagueIds = input.leagueIds;
  if (leagueIds === undefined) {
    const release = await input.db.doc(
      `publicData/${input.associationId}/snapshots/current`
    ).get();
    leagueIds = input.divisionId === undefined ? [] :
      leaguesForDivision(release.data()?.leagues, input.divisionId);
  }
  const recipients = input.audience === undefined
    ? await loadFavoriteTeamRecipients(
      input.db, input.associationId,
      input.teamIds, leagueIds,
    )
    : selectFavoriteTeamRecipients(
      input.audience, input.teamIds, leagueIds,
    );
  const newlyCreated = [] as typeof recipients;
  // The inbox is durable even when a fan has disabled push or denied device
  // permission. A stable document ID prevents retries from duplicating alerts
  // or resetting a notification that the fan already read.
  for (let offset = 0; offset < recipients.length; offset += 50) {
    const page = recipients.slice(offset, offset + 50);
    const created = await Promise.all(page.map(async (recipient) => {
      const ref = input.db.doc(
        `users/${recipient.uid}/notifications/${input.notificationId}`
      );
      return input.db.runTransaction(async (transaction) => {
        const existing = await transaction.get(ref);
        if (existing.exists) return false;
        transaction.create(ref, {
          type: input.type,
          associationId: input.associationId,
          ...(input.gameId ? {gameId: input.gameId} : {}),
          title: input.title,
          body: input.body,
          createdAt: admin.firestore.Timestamp.now(),
          readAt: null,
        });
        return true;
      });
    }));
    for (let index = 0; index < page.length; index += 1) {
      if (created[index]) newlyCreated.push(page[index]);
    }
  }
  const tokens = newlyCreated
    .filter((recipient) => recipient.notificationPrefs.favoriteTeamUpdates !== false)
    .flatMap((recipient) => recipient.fcmTokens);
  await sendMulticast(tokens, {
    title: input.title,
    body: input.body,
    data: {
      type: input.type,
      assocId: input.associationId,
      ...(input.gameId ? {gameId: input.gameId} : {}),
    },
  });
  return recipients.length;
}

function leaguesForDivision(rawLeagues: unknown, divisionId: string): string[] {
  if (!Array.isArray(rawLeagues) || rawLeagues.length === 0) return ["all"];
  return rawLeagues
    .filter((league): league is Record<string, unknown> =>
      league !== null && typeof league === "object" && !Array.isArray(league))
    .filter((league) =>
      Array.isArray(league.divisionIds) && league.divisionIds.includes(divisionId))
    .map((league) => league.leagueId)
    .filter((value): value is string => typeof value === "string" && value.length > 0);
}

/**
 * Send multicast FCM message, handling token cleanup for invalid tokens.
 */
export async function sendMulticast(
  tokens: string[],
  payload: NotificationPayload
): Promise<void> {
  if (!tokens || tokens.length === 0) return;

  // Filter out any non-string or empty tokens
  const validTokens = tokens.filter((t) => typeof t === "string" && t.length > 0);
  if (validTokens.length === 0) {
    logger.warn("sendMulticast: No valid tokens after filtering.");
    return;
  }

  // Deduplicate tokens
  const uniqueTokens = [...new Set(validTokens)];

  // FCM sendEachForMulticast has a 500 token limit per call
  const chunks: string[][] = [];
  for (let i = 0; i < uniqueTokens.length; i += 500) {
    chunks.push(uniqueTokens.slice(i, i + 500));
  }

  for (const chunk of chunks) {
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: payload.data,
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body,
              },
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info(
        `FCM sent: ${response.successCount} success, ${response.failureCount} failures ` +
        `(${chunk.length} tokens)`
      );

      // Clean up invalid tokens
      if (response.failureCount > 0) {
        const invalidTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (
            resp.error &&
            (resp.error.code === "messaging/invalid-registration-token" ||
              resp.error.code === "messaging/registration-token-not-registered")
          ) {
            invalidTokens.push(chunk[idx]);
          }
        });

        if (invalidTokens.length > 0) {
          logger.info(`Cleaning up ${invalidTokens.length} invalid FCM tokens`);
          await cleanupInvalidTokens(invalidTokens);
        }
      }
    } catch (err) {
      logger.error("FCM sendEachForMulticast error:", err);
    }
  }
}

/**
 * Remove invalid FCM tokens from user documents.
 */
async function cleanupInvalidTokens(invalidTokens: string[]): Promise<void> {
  const db = admin.firestore();

  for (const token of invalidTokens) {
    try {
      // Find users with this token
      const usersSnap = await db
        .collection("users")
        .where("fcmTokens", "array-contains", token)
        .get();

      for (const userDoc of usersSnap.docs) {
        await userDoc.ref.update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
        });
      }
    } catch (err) {
      logger.warn(`Failed to clean up invalid token ${token.substring(0, 10)}...:`, err);
    }
  }
}
