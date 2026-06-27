import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK (must happen before importing other modules)
admin.initializeApp();

// ── Stats & Leaderboard ─────────────────────────────────────────────
export { onGameStatsApproved } from "./stats";

// ── Notifications ───────────────────────────────────────────────────
export {
  onPostCreatedWithAck,
  onAckWrite,
  ackDeadlineChecker,
  statDeadlineReminder,
} from "./notifications";
