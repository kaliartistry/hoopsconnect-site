# Security Rules Audit

Date: 2026-06-30

Status: FAIL-BLOCKING for public launch. FAIL-NON-BLOCKING for local PWA/demo preparation.

## Summary

The rules do not expose private app collections to unauthenticated public reads. That is good for the private PWA approach. However, several write/read boundaries are too broad for public launch or real season production and should be fixed before JBA opens self-signup broadly.

## Current Read/Write Model

Firestore:

- `/users/{userId}`: authenticated users can read all user docs.
- `/users/{userId}` create: authenticated users can create their own user doc with any allowed non-admin role.
- Association-scoped app data under `/associations/{assocId}` requires authentication for reads.
- Admins write seasons, divisions, events, teams, posts, and stat approvals.
- Statisticians can create/update game stats but cannot approve/reject.
- Leaderboards, standings, and team season stats are read-only to clients and written by Cloud Functions/Admin SDK.

Storage:

- `/posts/**`, `/teams/**`, and `/documents/**` require authentication.
- Upload type and size are constrained.

## What Is Good

- No private Firestore collection has unauthenticated public read access.
- Catch-all Firestore rule denies unmatched paths.
- Leaderboards/standings/team season stats block client writes.
- Stats approval/rejection is admin-only.
- Self-updates block changing `role` and `associationId`.
- Storage requires authentication and validates basic content type/size.

## Blocking Risks Before Public Launch

1. Public self-create can request elevated non-admin roles.
   - Current rule allows self-created user docs with `media`, `rep`, `statistician`, `press`, or `fan`.
   - App code now defaults to `fan`, but direct Firestore clients could still self-create as statistician/rep/media.
   - Fix: self-create should only allow `fan`; invite-code role assignment should be moved to a trusted backend or constrained by validated invite-code state.

2. Any authenticated user can read all user docs.
   - This may expose emails, names, phone numbers, team IDs, roles, and notification metadata to fans.
   - Fix: limit user reads to self and admin, or create public user/profile documents with safe fields.

3. Team rep team updates are not field-limited.
   - Rule allows a rep in `repIds` to update the whole team doc.
   - Fix: restrict rep updates to specific approved fields or move team edits through admin approval.

4. Rep acknowledgment updates are too broad.
   - Rule lets reps update the `ackStatus` field, but does not verify they only add/update their own ack entry.
   - Fix: validate nested map changes so reps can only write `ackStatus[request.auth.uid]`.

5. Storage writes are too broad for authenticated users.
   - Any authenticated user can write to post/team/document storage paths if size/type pass.
   - Fix: require role checks and path ownership, such as admins for team logos/documents and authors/admins for post media.

## Public Data Exposure Risk

Private collections are not public today, and they should stay private. The public JBA website must not be given direct public read access to these collections.

Use one of:

- Cloud Function HTTP endpoints.
- Scheduled static JSON exports.
- Dedicated public-data documents with strict public read rules.
- Website widgets/pages consuming approved public DTOs only.

## Association Scoping Risks

Most app data is association-scoped in paths, but rules generally check only user role, not whether the user belongs to the same association as `{assocId}`.

Fix recommendation:

- Add a helper like `isSameAssociation(assocId)` checking `getUserDoc().associationId == assocId`.
- Apply it to association-scoped reads/writes.

## Emulator Tests

No Firebase rules unit test suite was found.

Recommendation:

- Add Firestore rules emulator tests for:
  - public unauthenticated denial
  - fan cannot write stats/admin data
  - self-create can only create fan
  - invite-code signup flow
  - statistician can submit but not approve
  - admin can approve
  - rep can only ack self
  - rep cannot edit arbitrary team fields
  - storage path ownership/role checks

## Status Classification

- Public launch: FAIL-BLOCKING until self-create and broad read/write risks are tightened.
- Controlled private demo/PWA prep: FAIL-NON-BLOCKING because the Flutter web app can still be demonstrated with trusted accounts and no public data exposure.

