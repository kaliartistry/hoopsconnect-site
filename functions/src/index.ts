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

// ── Identity, membership, and privileged invitations ─────────────────
export {
  provisionFanProfile,
  inspectPrivilegedInvite,
  redeemPrivilegedInvite,
  createPrivilegedInvite,
  revokePrivilegedInvite,
  setMemberRole,
} from "./membership";

// ── Callable-only league operations ───────────────────────────────
export {
  getRosterWorkspace,
  submitRosterChange,
  reviewRosterProposal,
  deleteDivisionIfUnreferenced,
  scheduleGame,
  createScheduleBatch,
  mutateScheduledGame,
} from "./league_operations";

export {
  seasonPrepare,
  seasonActivate,
  seasonArchive,
  seasonRestore,
} from "./season_operations";
