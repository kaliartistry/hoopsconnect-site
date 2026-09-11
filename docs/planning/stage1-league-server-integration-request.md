# Stage 1 league server integration request

Status: client candidate implemented; server integration required before F-09
and F-23 can be marked verified on the assembled app.

Owner: integration owner for Functions entrypoints, live rules, indexes, path
constants, emulator configuration, and dormancy transitions.

## Why this request exists

The active flat authorization schema lets `teams.manage` accounts write legacy
team and `playerSeasonStats` documents. It gives representatives
`teams.represent`, but there is no representative-safe roster proposal path or
callable. The v2 official-stat schema correctly makes player identity, seasonal
team entry, roster membership, membership versions, and roster assertions
server-private. A client write or a new permissive rule would bypass that
contract.

`playerSeasonStats` is a derived aggregate. Creating a zero-filled aggregate
as a side effect of registration invents an output record before any approved
game exists and makes the existing approval trigger assume fields that are not
registration facts. New registration writes must therefore go through the
canonical roster workflow and must not create `playerSeasonStats`.

## Client contract now ready

The client calls three fixed-purpose functions. All opaque actor, association,
grant, lifecycle, and trusted-time facts must come from the verified server
context, never from the request.

### `getRosterWorkspace`

Request:

```json
{"schemaVersion":1,"teamId":"opaque","seasonId":"opaque"}
```

Response:

```json
{
  "rosterVersion": 4,
  "registrations": [{
    "registrationId": "opaque",
    "playerId": "opaque",
    "displayName": "Aaliyah Brown",
    "teamId": "opaque",
    "seasonId": "opaque",
    "jerseyNumber": "00",
    "position": "Guard",
    "status": "active"
  }],
  "proposals": [{
    "proposalId": "opaque",
    "kind": "addPlayer",
    "status": "pending",
    "teamId": "opaque",
    "seasonId": "opaque",
    "before": null,
    "after": {
      "playerId": null,
      "registrationId": null,
      "displayName": "Aaliyah Brown",
      "jerseyNumber": "00",
      "position": "Guard"
    },
    "reason": "New registration",
    "requestedByName": "Team Representative",
    "requestedAt": "2026-09-11T18:00:00Z",
    "reviewNote": null
  }]
}
```

Return only the current team/season workspace. In legacy authority mode,
`teams.manage` may read any team in its association and `teams.represent` may
read only the membership's exact `teamId`. In v2 authority mode, resolve
`rosters.manage` at season scope and `rosters.assert` at the exact team-entry
scope. Account lifecycle, custody fencing, association matching, active season
entry, and identity suppression remain mandatory.

### `submitRosterChange`

The version-1 request contains:

- `operationId`, retained unchanged across a client retry;
- `teamId`, `seasonId`, and `expectedRosterVersion`;
- `kind`: `addPlayer`, `updatePlayer`, or `removePlayer`;
- `requestedOutcome`: `apply` or `propose`, which is only a client request;
- for add/update, `displayName`, exact string `jerseyNumber`, optional
  `position`, and `reason`;
- for update/remove, the exact `playerId` and `registrationId`.

Server behavior:

1. Derive authority and scope in one transaction. Never grant `apply` because
   the client requested it.
2. Treat the exact operation ID plus semantic payload as idempotent. An exact
   replay returns the same receipt; changed semantics are a conflict.
3. Reject an unrelated representative before reading or writing roster facts.
4. An authorized representative creates an immutable pending proposal. It does
   not mutate the roster, eligibility, player identity, or derived statistics.
   The proposal stores the immutable normalized `before` and `after` player
   facts plus the submitted reason. Add has `before: null`; update has both;
   remove has `after: null`. Each fact object carries display name, exact jersey
   string, optional position, and existing stable IDs where applicable.
5. An authorized roster manager may apply the same validated change directly.
6. New people/players/registrations receive server-generated stable opaque IDs
   and identity version records. Never derive identity from a display name,
   jersey, timestamp, or user account.
7. Preserve `jerseyNumber` as a string, including the distinction between `0`
   and `00`. `position` is optional descriptive data, not a fabricated playing
   fact.
8. Update/remove creates a membership version and preserves all historical
   game participant snapshots and approved statistics.
9. Compare `expectedRosterVersion`; on mismatch return a stable stale-roster
   error without partial writes.
10. Return a receipt with `operationId`, optional `proposalId`, optional new
    `playerId`/`registrationId`, `status` (`pending`, `approved`, or
    `rejected`), and the current `rosterVersion`.

### `reviewRosterProposal`

Request fields are `schemaVersion`, `operationId`, `proposalId`, `teamId`,
`seasonId`, `expectedRosterVersion`, `decision` (`approve` or `reject`), and an
optional note. Rejection requires a note. Only verified roster-management
authority may review. Approval must revalidate proposal scope, current roster
version, eligibility constraints, lifecycle/custody fences, and identity state
inside the applying transaction. The review response and audit record must
retain the exact immutable before/after/reason facts presented to the reviewer.
A stale or already-decided proposal returns a deterministic receipt/error; it
is never applied twice.

## Read projection and migration compatibility

`getRosterWorkspace` should project canonical player/registration facts for the
client. Do not expose private person evidence. Do not require a placeholder
`playerSeasonStats` document. Existing historical `playerSeasonStats` remain a
read-only compatibility source for season-stat display; they are joined by
stable `playerId`. The client already shows `Season stats not calculated` when
no aggregate exists.

Before activation, reconcile legacy roster rows to canonical stable identities
using the reviewed migration inventory. Unknown identity matches must remain
unresolved, not name-matched automatically. The statistics workstream must read
the canonical roster projection for new games before the legacy roster write
path is retired.

## Atomic division deletion

The client now exposes archive and a read-only dependency inventory. It has no
direct division-delete method or enabled delete action. Every query result is a
blocker even when its name/title is missing or malformed; the UI uses the
document ID as a fallback label instead of dropping the reference.

Add `deleteDivisionIfUnreferenced` as an idempotent admin callable. Request:

```json
{"schemaVersion":1,"operationId":"opaque","divisionId":"opaque","expectedDivisionVersion":7}
```

Result, with every reference represented even if its display label is absent:

```json
{
  "operationId":"opaque",
  "status":"blocked",
  "divisionVersion":7,
  "references":[
    {"kind":"legacyTeam","id":"team_1","displayName":"Kingston Lions"},
    {"kind":"canonicalGame","id":"game_1","displayName":null}
  ]
}
```

Successful replays return the same `{status:"deleted"}` receipt. Changed
semantics under the same operation ID are rejected.

The server inventory must include legacy `teams` and `events`, canonical
season `teamEntries`, canonical `games`, schedule revisions, and any current or
immutable operational/stat record whose scope contains the division ID. A
historical immutable reference may mean archive is the only legal outcome
unless the canonical contract introduces a retained division tombstone.

An empty query followed by delete is not concurrency-safe because a new
reference can arrive between those operations. Before enabling deletion:

1. add a versioned `deletionPending` guard on the division through the callable;
2. require every legacy and canonical reference writer to verify that the
   division is active and not deletion-pending in its server transaction;
3. remove any direct client rule that can create a reference without that
   guard;
4. enumerate references after the guard, then compare the division version and
   guard token before deletion; and
5. clear the guard and return all blockers when any reference exists.

No rule should permit representatives or ordinary readers to delete divisions.
The client delete action remains unavailable until the emulator proves this
cross-writer concurrency invariant.

## Idempotent scheduling integration

Manual and generated schedule commit actions are disabled. Local preview and
conflict checks are advisory only and never write Firestore. Add fixed-purpose
`scheduleGame` and `createScheduleBatch` callables before enabling them.

`scheduleGame` request:

```json
{
  "schemaVersion":1,
  "operationId":"schedule_opaque",
  "seasonId":"opaque",
  "divisionId":"opaque",
  "homeTeamId":"opaque",
  "awayTeamId":"opaque",
  "startTimeUtc":"2026-09-13T01:00:00.000Z",
  "endTimeUtc":"2026-09-13T03:00:00.000Z",
  "location":"National Arena"
}
```

The client creates its operation ID once when the form opens and retains it
unchanged across checks and exact retries. The server must derive actor and
association, verify the requested season is the association's active season,
verify an active division, and verify both teams belong to that exact season
and division. It must atomically reject an unordered-pair duplicate at the same
start instant and any overlap for either team. Exact operation/payload replays
return the same `{operationId,status:"created",eventId,scheduleVersion}`
receipt; changed semantics conflict. UTC instants are canonical and the
schedule revision records `America/Jamaica` as its civil timezone.

The batch callable uses one parent operation ID plus a deterministic item key
per preview row, validates the same invariants for every row and against other
rows in the request, and returns per-item results plus an overall
`created|blocked` status. It must not leave a partially created schedule after
a retry or validation failure. If the backend cannot provide one atomic batch,
use a durable server job with idempotent item receipts and expose honest
progress/recovery state before enabling the client action.

## League-time consumer inventory

Firestore and callable schedule instants are UTC. America/Jamaica is the sole
league civil timezone and is UTC-05:00 year-round. The shared `LeagueTime`
utility is now used by every identified schedule consumer in this packet:

- manual game date/time input, day conflict-query bounds, and request preview;
- schedule-generator civil dates, UTC slot generation, week grouping, and
  preview labels;
- calendar range queries, day grouping, date scroller, and game cards;
- statistician game selector;
- public league schedule;
- press dashboard "today" query boundaries and game-time labels.

New York daylight-saving conversion remains a comparison test only. Device
local timezone is not used for league dates or game times. `approvedAt`, post
deadlines, invite expiry, local journal receipt times, and other audit/account
timestamps are not schedule consumers and remain outside this migration.

## Emulator acceptance required

- Admin creates a player with a server-issued stable identity; no aggregate
  document is created and the roster workspace displays the player.
- `0` and `00` round-trip distinctly.
- Optional position may be absent; no totals, averages, minutes, or eligibility
  evidence are fabricated.
- Own-team representative proposal returns pending and leaves roster version
  unchanged; unrelated-team proposal is denied server-side.
- Admin approves the exact pending proposal once; a replay returns the receipt;
  stale-version approval does not apply.
- Rejection requires a note and remains visible to the representative.
- Removing a current registration leaves historical participant snapshots and
  aggregates unchanged.
- A lifecycle/custody-fenced actor cannot load, submit, or review.
- Division delete names blocking teams/events, survives a concurrent new
  reference without orphaning it, and succeeds only with no references.
- Malformed or missing dependency names still block division deletion and are
  returned with stable IDs.
- Manual scheduling rejects inactive season/division, cross-season or
  cross-division teams, pair duplicates, and either-team overlap; an exact
  operation replay returns one event.
- Batch scheduling cannot partially duplicate games after retry or failure.

No production activation, migration, rule deployment, or real league-data
change is part of this integration request.
