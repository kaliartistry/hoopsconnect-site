import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK (must happen before importing other modules)
admin.initializeApp();

// ── Stats & Leaderboard ─────────────────────────────────────────────
export { onGameStatsApproved } from "./stats";

// ── Certified public guest data ────────────────────────────────────
export {onPublicLeagueSourceWritten} from "./public_snapshot";

// ── Notifications ───────────────────────────────────────────────────
export {
  onPostCreatedWithAck,
  onAckWrite,
  ackDeadlineChecker,
  statDeadlineReminder,
} from "./notifications";

// ── Identity, membership, and privileged invitations ─────────────────
export {
  provisionFanProfile,
  inspectPrivilegedInvite,
  redeemPrivilegedInvite,
  createPrivilegedInvite,
  revokePrivilegedInvite,
  setMemberRole,
} from "./membership";
