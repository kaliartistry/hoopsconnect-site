# Production readiness preflight

Snapshot date: 2026-09-08

Status: read-only evidence and deterministic migration proposal complete. No
provider setting or production record was changed. The current production
state is not ready for deployment.

## Provider read-back

### Functions and client protection

- Production has four active Gen 2, Node.js 22 Functions in `us-central1`:
  `onPostCreatedWithAck`, `statDeadlineReminder`, `onGameStatsApproved`, and
  `ackDeadlineChecker`. Their latest provider update timestamps are
  2026-03-26.
- The merged source additionally exports `onAckWrite` and six membership/invite
  callables. Those seven Functions are not deployed.
- Secret Manager is disabled in the project, so existing secret resources cannot
  be enumerated through the provider API and the V1 binding is operationally
  unavailable. Treat `INVITE_TOKEN_HMAC_KEY_V1` as unprovisioned until the API
  is deliberately enabled and the secret metadata is read back; the invite
  issuance Function cannot be deployed safely yet.
- App Check is `UNENFORCED` for Firestore, Storage, Identity Toolkit, and OAuth.
  The callable source does not yet set `enforceAppCheck`.

### Firestore

- Database `(default)` is Native mode in `nam5`.
- Point-in-time recovery and delete protection are disabled. Version retention
  is one hour and no backup schedule exists.
- Production has 14 ready composite indexes; the repository declares 16. The
  missing definitions are the public post visibility/ack query and the V2
  invite association/credential-version query. The normalized deployed index
  manifest SHA-256 is
  `487c829ef65fbd027073fc4b259ac7822aaa849f757bfe7f3a3ac3514a6a0147`;
  the repository manifest SHA-256 is
  `8a883df9a37cc1a43e498317da4d2536e9b4e3fe0531c6e90361c521a88f34e2`.
- The deployed Firestore release is `cloud.firestore`, last updated
  2026-04-04, using ruleset
  `6d840888-178d-4fce-8752-860b5c5afdc5` with SHA-256
  `4870442aec3c26069957e0a19b3a56b105b7fefabaf8354889534cd263b338a5`.
  The merged repository rules SHA-256 is
  `1efcd4a7331955f9b3958b87969c37a83220576d47be99ea1cce7a58b3bb7726`;
  production is not running the merged rules.

### Storage and Hosting

- The application bucket is regional `US-CENTRAL1`. Uniform bucket-level
  access is disabled, public access prevention is inherited, object soft delete
  retains objects for seven days, and no bucket retention policy or object
  versioning was reported.
- The guarded Storage audit found zero objects, zero URL references, and zero
  path, metadata, MIME, size, source-record, or download-token blockers.
- The deployed Storage release was last updated 2026-03-26, using ruleset
  `f4180db9-c69e-49d9-9101-24a6fb95567f` with SHA-256
  `4c9c9be5d48de83dc6b61f5bc6f427d33f9d6138cd54f99ddc69e3c68359eeb7`.
  The merged repository rules SHA-256 is
  `76cda53db0f6eafb658ce049b13aedc03ce780473eb294daeb9324db00f59fb7`;
  production is not running the merged rules.
- The default Hosting site exists but has no live release. Both default domains
  return HTTP 404 with title `Site Not Found`; no candidate security headers are
  present because nothing has been released.

### IAM, staging, monitoring, and recovery

- IAM has one human Owner, three service-account Editors, and one
  service-account Storage Admin. A single recoverable human owner is an access
  recovery risk; principal identifiers are intentionally excluded.
- No separate HoopsConnect staging project appears in the authenticated Firebase
  project inventory, and `.firebaserc` defines only demo development and
  production aliases.
- Billing is enabled. Cloud Billing Budget API access is unavailable because
  the API is disabled for the usable quota project and the current principal
  cannot enumerate the billing account. Budget-alert state is therefore
  unknown, not zero.
- Cloud Monitoring reports zero alert policies and zero notification channels.
- No dedicated export/backup bucket or staging restore target exists. The two
  additional project buckets are provider-managed Cloud Functions build/upload
  buckets, not recovery destinations.

## Sanitized data inventory

The guarded foundation audit exits nonzero with:

- 5 Firebase Auth identities, 3 profiles, 2 identities without profiles, no
  profiles without Auth identities, 0 memberships, and 3 legacy profile
  authorization schemas;
- 11 posts with missing visibility: 4 require acknowledgment and 7 do not;
- 31 invite documents, all missing credential and authorization schema
  versions;
- blocker codes `usersMissingMemberships=3`,
  `invalidUserAuthorizationSchemas=3`, `postsMissingVisibility=11`, and
  `legacyInviteDocuments=31`.

The broader readiness inventory found:

| Area | Sanitized count |
| --- | ---: |
| Seasons / divisions / teams | 1 / 2 / 12 |
| Embedded roster entries | 112 across all 12 teams |
| Calendar events / game events | 107 / 102 |
| Game-stat documents | 102 approved |
| Embedded game player lines | 1,632 |
| Player-season stat documents | 96 |
| Team-season stat documents | 12 |
| Standings / leaderboard documents | 3 / 15 |
| Separate player / roster documents | 0 / 0 |

Every listed league/stat collection currently lacks an explicit
`schemaVersion`. This is recorded for future schema governance; it is not, by
itself, an authorization rollout blocker because schema v1 currently applies to
profiles and memberships.

## Deterministic dry-run proposal

`scripts/audit_production_readiness_data.js` created the ignored local artifacts
below without displaying their contents:

- `.local/production-readiness/sanitized-plan.json`
- `.local/production-readiness/operator-map.json`
- `.local/production-readiness/pseudonym.key`

The directory is mode `0700`; every artifact is mode `0600`. Invite document
IDs are omitted even from the operator map. A later executor must rescan and
HMAC-match invite labels instead of persisting legacy bearer values.

Two consecutive live reads produced the same source snapshot SHA-256
`01263e6e20450b77975acaaaf20bf2710b61a6f9975b2ffbcb47fdf4ff6c207a`
and plan SHA-256
`ebdad3bce2e2e89b537eceb1e2a198109fb011f1d6c205b1ea02d5690c767f53`.
The proposed deltas are:

- 5 profile/membership cases reviewed, including 2 Auth-only identities, with
  membership records created or replaced only after manual evidence review;
  all accounts remain fail closed until approval;
- 11 legacy posts defaulted to `internal`; none defaults public;
- 31 legacy invites revoked with audited, zero-use terminal state;
- 0 Storage object copies/removals and 0 URL reference replacements.

No proposal is an authorization to apply the migration. Preconditions include
an immutable export, verified staging restore, conflict-safe write window,
reviewed operator map, approved rollout ordering, and a named rollback owner.
Postconditions require both production audits to return zero blockers.

## Decisions and consequential gates

Read-only audits, hashes, local fixtures, pseudonymous planning, and runbook
updates are no-cost and non-consequential. The following require choices and
provider mutations in later packets:

1. Choose an unused staging project ID, region/data-location policy, and billing
   account link. Create it only after those are approved.
2. Name a second independently recoverable human owner. Decide which emergency
   recovery capability truly requires Owner and replace broad Editor/Storage
   Admin grants with documented least-privilege roles where possible.
3. Choose backup/export region, retention, PITR, delete protection, restore-test
   cadence, and budget-alert recipients/thresholds. Pricing must be checked from
   official Google Cloud sources at decision time.
4. Enable Secret Manager, create a strong V1 HMAC secret, define rotation and
   old-version retention for idempotent retries, then bind it during the
   Functions rollout.
5. Decide App Check provider enrollment, monitoring period, and enforcement
   sequence for each client/service.
6. Name the rollout and rollback owners and approve an ordered maintenance
   window: export/restore proof, indexes, compatible client, Functions, data
   migration, audit-zero gate, Firestore/Storage rules, Hosting, and live
   read-back.

The exact next safe action is human review of the three pseudonymous membership
proposals in the owner-readable operator artifact, alongside selection of the
staging project location/billing and named backup/rollback owners. No production
write should occur until those decisions and a staging restore are recorded.
