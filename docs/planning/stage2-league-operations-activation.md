# Stage 2 callable-only league operations

Status: implementation candidate only. All production capability fields remain
absent and therefore closed. This document does not authorize deployment,
migration, or real league-data changes.

## Trusted control

The Functions and Flutter client both fail closed unless this server-owned
document is present:

`associations/{associationId}/leagueWorkflowControl/current`

Required version-1 fields are:

```text
schemaVersion: 1
associationId
competitionId
activeSeasonId
defaultPhaseId
timezone: America/Jamaica
authorityMode: legacyV1 | v2
callablesReady: true
directWritesDenied: true
lifecycleAuthorityReady: true
custodyAuthorityReady: true
actorAuthorityReady: true
identityAuthorityReady: true
privacyAuthorityReady: true
custodyPolicyVersionV2: positive integer
privacyEpochV2: positive integer
rosters: true | false
divisionDeletion: true | false
scheduling: true | false
```

Clients may read this minimized readiness record but cannot write it. The
Functions re-read and validate it in every transaction; a visible button is
never the authority boundary. `competitionId`, `activeSeasonId`,
`defaultPhaseId`, and the timezone are server facts, not client parameters.

All authority-ready fields must remain false until the dormant account
lifecycle, ownership/custody, auth-incarnation claim issuer, and identity
suppression/privacy authorities are composed and independently verified. The
checked-in repository creates neither this control document nor the per-actor
`leagueActorAuthorities/{uid}` projection. Every callable requires an exact V2
project, nullable tenant, UID, 64-character account generation, lifecycle
epoch, active lifecycle/membership state, operating custody state, current
custody/privacy epochs, unsuppressed identity state, and strict
`auth_time > reauthAfterSecV2`. This applies before any saved receipt replay.
Every exported league callable also enforces App Check and a server-owned
per-actor token bucket with 120-call minute capacity and 2,000-call day
capacity. Tokens refill continuously rather than resetting at a window edge.
An exact actor/association/operation/fingerprint-bound receipt replay still
reauthorizes lifecycle, custody, generation, and privacy, but does not consume
another token. A missing or changed receipt does not bypass the bucket.

## Compatibility and activation order

1. Ship a client that requires the complete control above. With no control,
   roster mutation, permanent division deletion, and schedule commit remain
   unavailable.
2. Migrate legacy teams to reviewed canonical `teamEntries`, assigning each
   legacy team a server-controlled `teamEntryId`. Give divisions explicit
   nonnegative versions. Do not name-match unknown player identities.
3. Deploy the callables with feature booleans false. Verify exact request
   validation, scope, receipts, stale-version behavior, rollback, and conflicts
   in an isolated environment.
4. Deploy and read back Rules that deny direct division deletion, all direct
   event mutations, derived aggregate writes, operation/control records,
   canonical records, and lock records. Verify old and malicious clients are
   denied while Admin SDK transactions succeed.
5. Compose and verify lifecycle, custody, auth-incarnation issuance, App Check,
   actor projections, roster identity suppression/privacy projections, and
   claim-refresh fences. Then set
   `callablesReady`, `directWritesDenied`, `lifecycleAuthorityReady`, and
   `custodyAuthorityReady`, `actorAuthorityReady`,
   `identityAuthorityReady`, and `privacyAuthorityReady` true. The client also
   requires `authorityMode` to match its current membership schema.
6. Open only the individually verified feature boolean. In v2 mode, roster and
   scheduling callables require the existing scoped grants and never fall back
   to v1 capability strings. Permanent division deletion remains closed in v2
   until an adopted v2 division-management capability exists.
7. On rollback, close the affected feature boolean first. Never reopen direct
   client writes.

The order has no state in which a client action is enabled before its callable,
scope contract, lifecycle/custody fences, and deny rules are all asserted.

## Integration-owner compatibility hold

The deny rule intentionally blocks every direct legacy event update, including
the current `EventRepository.updateEvent` calls in the statistics entry and
live-stat screens. Do not deploy this Rules candidate until the statistics
workstream replaces those event-status writes with its reviewed server command
boundary. Reopening direct event writes is not a compatibility option.

The integration owner must also review and add production indexes for the
complete division-reference inventory before non-production rehearsal. This
packet intentionally does not edit `firestore.indexes.json`, because the
repository does not yet carry any reviewed `COLLECTION_GROUP` index definitions
for this boundary. At minimum the equality pairs `associationId + divisionId`
must be reviewed for root collections `users`, `memberships`, and `inviteCodes`
and for the collection groups `teamEntries`, `games`, `scheduleRevisions`,
`assignments`, `rosterHeads`, `rosterMemberships`, `versions`,
`rosterAssertions`, `rosterAssertionDecisions`, `rosterOutstandingProposals`,
`rosterProposalQueues`, `rosterSnapshots`,
`participantSnapshots`, `operations`, `operationReceipts`, `statRevisions`,
`officialResults`, `reviews`, `certificates`, `certificateActions`,
`corrections`, `aggregateReleases`, `publicSelections`, and `projectionBuilds`.
The bounded roster workspace also needs the reviewed active-registration
`teamId + status` query and outstanding-queue `teamId + seasonId` query before
activation.
The association-local `posts.divisionFilter` query must also remain in the
inventory for both current division IDs and the historical exact division-name
format. New clients write division IDs; historical name values require a
reviewed migration before names may change. Direct post creation or
reassignment and invite creation/redemption
read the referenced division and require it to be active and free of a deletion
guard. Membership and invite records remain client-immutable. These reads
serialize new reference writers against guard acquisition so no reference can
be added after the out-of-transaction inventory begins.
Team-bound privileged invites additionally require the exact association
current season and reject a team carrying any explicit non-active state.
An index/query/size failure persists `inventoryFailed`, releases the division
guard, and fails closed. It must not be worked around by skipping a reference
class. `divisionDeletion` must remain false until this exact inventory succeeds
against representative non-production data.

The stats direct-event-update cutover remains separately closed. Existing
`gameStats` documents may be corrected after a division is archived because
that changes no reference, but creating a new archived-division stat reference
is denied. Direct compatibility event writes remain denied.

## Persistence boundaries

- Roster writes use canonical people, players, identity/display-name versions,
  season team entries, roster heads, memberships and immutable membership
  versions. Representative assertions and their decisions are separate
  immutable records. A server-owned per-team queue state serializes the
  outstanding proposal count at 100, while the workspace reads only that
  bounded active queue rather than unbounded proposal/decision history. No
  `playerSeasonStats` document is created.
- Schedule writes atomically maintain the compatibility event, canonical game,
  immutable schedule revision, per-team/day lock and unordered-pair/start lock.
  Batches are all-or-none and capped at 25 games. Larger previews stay visibly
  unavailable instead of being split into a partial schedule.
- Permanent division deletion first acquires a versioned, expiring pending
  guard and persists a private operation record. Exact retries resume after a
  process restart. Inventory/query/size failures persist a retryable failure
  and safely release the guard; a stale lease can be reclaimed. A successful
  inventory records every blocker and clears the guard or deletes the division.
  The final phase must match the prepared actor, association, generation,
  lifecycle epoch, capability set, workflow scope and division version before
  touching the prepared references. The client separately persists the pending
  operation ID in an account/association/division/version-bound local record,
  reuses it after app restart, and removes it only after a matching terminal
  callable receipt. A structured, scope-bound stale-version rejection is saved
  as local proof and requires an explicit rebase to a new operation ID before
  another delete attempt; uncertain failures continue to reuse the original
  operation. Legacy version-zero divisions remain supported. Server operation
  and receipt documents remain private.
- Direct division create/edit/archive writes require exact integer versions:
  create at 1 and increment by exactly one with a server timestamp on every
  mutation.
- Roster reads and mutations validate the current person identity version,
  player display-name version, privacy epoch, and unsuppressed identity guard.
  Player name mutation remains prohibited until a governed version-chain writer
  is composed; jersey values use the existing client contract without adding a
  competition rule.
- Cancellation retains the event, canonical game, schedule revisions,
  participants, reviews and statistics. Started, reviewed, or approved games
  cannot be cancelled. Submitted, rejected, final, snapshotted, or any
  stat-bearing game is also immutable. Cancellation is visible to the client
  and excluded from the needs-stats queue.
