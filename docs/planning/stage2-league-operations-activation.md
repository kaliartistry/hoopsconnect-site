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
rosters: true | false
divisionDeletion: true | false
scheduling: true | false
```

Clients may read this minimized readiness record but cannot write it. The
Functions re-read and validate it in every transaction; a visible button is
never the authority boundary. `competitionId`, `activeSeasonId`,
`defaultPhaseId`, and the timezone are server facts, not client parameters.

`lifecycleAuthorityReady` and `custodyAuthorityReady` must remain false until
the dormant account lifecycle and ownership/custody authority are composed and
independently verified. The checked-in repository does not create this control
document, so every new action remains unavailable by default.

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
5. Compose and verify lifecycle and custody fences. Then set
   `callablesReady`, `directWritesDenied`, `lifecycleAuthorityReady`, and
   `custodyAuthorityReady` true.
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

The integration owner must also review production indexes for the canonical
division-reference inventory before non-production rehearsal. This packet does
not edit `firestore.indexes.json`; an index failure remains fail-closed and must
not be worked around by skipping a reference class.

## Persistence boundaries

- Roster writes use canonical people, players, identity/display-name versions,
  season team entries, roster heads, memberships and immutable membership
  versions. Representative assertions and their decisions are separate
  immutable records. No `playerSeasonStats` document is created.
- Schedule writes atomically maintain the compatibility event, canonical game,
  immutable schedule revision, per-team/day lock and unordered-pair/start lock.
  Batches are all-or-none and capped at 25 games. Larger previews stay visibly
  unavailable instead of being split into a partial schedule.
- Permanent division deletion first acquires a versioned pending guard. After
  the guard commits, it inventories legacy and canonical references and then
  either records every blocker and clears the guard or deletes the division.
  Exact retries resume or return the immutable receipt.
- Cancellation retains the event, canonical game, schedule revisions,
  participants, reviews and statistics. Started, reviewed, or approved games
  cannot be cancelled.
