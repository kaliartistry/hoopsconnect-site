import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

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

interface UserDoc {
  email: string;
  displayName: string;
  associationId: string;
  teamId?: string;
  role: string;
  divisionId?: string;
  fcmTokens: string[];
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
      // Query reps for this association
      let query: admin.firestore.Query = db
        .collection("users")
        .where("associationId", "==", assocId)
        .where("role", "==", "rep");

      // If the post targets a specific division, filter reps by division
      if (postData.divisionFilter) {
        query = query.where("divisionId", "==", postData.divisionFilter);
      }

      const repsSnap = await query.get();
      const expectedAcks: Record<string, AckExpectedEntry> = {};
      const allTokens: string[] = [];

      for (const doc of repsSnap.docs) {
        const user = doc.data() as UserDoc;

        if (!user.displayName) {
          logger.warn(`User ${doc.id} has no displayName, using fallback.`);
        }

        expectedAcks[doc.id] = {
          name: user.displayName || "Unknown",
          teamName: user.teamId || "",
          phone: undefined,
        };

        if (user.fcmTokens && Array.isArray(user.fcmTokens) && user.fcmTokens.length > 0) {
          allTokens.push(...user.fcmTokens);
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

    const expected = Object.keys(after.expectedAcks || {}).length;
    const acked = Object.keys(after.ackStatus || {}).length;
    const ackedBefore = Object.keys(before.ackStatus || {}).length;

    // Only act on the *transition* to fully-acked, not subsequent writes.
    if (expected === 0) return;
    if (acked < expected) return;
    if (ackedBefore >= expected) return;

    const assocId = event.params.assocId;
    const postId = event.params.postId;

    logger.info(
      `All acks landed: assoc=${assocId}, post=${postId}, count=${acked}/${expected} — archiving.`
    );

    try {
      await event.data?.after.ref.update({
        archived: true,
        archivedAt: admin.firestore.Timestamp.now(),
      });

      // Notify the author so they know the loop is closed.
      const authorSnap = await admin
        .firestore()
        .doc(`users/${after.authorId}`)
        .get();
      if (authorSnap.exists) {
        const author = authorSnap.data() as UserDoc;
        if (author.fcmTokens?.length) {
          await sendMulticast(author.fcmTokens, {
            title: "All reps acknowledged",
            body: `"${after.title}" is fully acknowledged.`,
            data: {
              type: "ack_complete",
              postId,
              assocId,
            },
          });
        }
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
          const tokens: string[] = [];
          for (const userId of unackedIds) {
            try {
              const userSnap = await db.doc(`users/${userId}`).get();
              if (userSnap.exists) {
                const user = userSnap.data() as UserDoc;
                if (user.fcmTokens && Array.isArray(user.fcmTokens) && user.fcmTokens.length > 0) {
                  tokens.push(...user.fcmTokens);
                }
              }
            } catch (userErr) {
              logger.warn(`Failed to fetch user ${userId} for ack reminder:`, userErr);
            }
          }

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

        // Get admin users for this association
        const adminSnap = await db
          .collection("users")
          .where("associationId", "==", assocId)
          .where("role", "in", ["admin", "superAdmin"])
          .get();

        const adminTokens: string[] = [];
        for (const adminDoc of adminSnap.docs) {
          const user = adminDoc.data() as UserDoc;
          if (user.fcmTokens && Array.isArray(user.fcmTokens) && user.fcmTokens.length > 0) {
            adminTokens.push(...user.fcmTokens);
          }
        }

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

interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Send multicast FCM message, handling token cleanup for invalid tokens.
 */
async function sendMulticast(
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
