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
    "playerId": null,
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
inside the applying transaction. A stale or already-decided proposal returns a
deterministic receipt/error; it is never applied twice.

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

The current candidate performs two dependency reads and stops deletion when it
finds named team or event references. This is useful UI protection but cannot
close the race between its final query and a direct document delete.

Add `deleteDivisionIfUnreferenced` as an idempotent admin callable. In one
server-controlled operation, verify lifecycle/custody and association-management
authority, query all reference classes (at minimum legacy teams and events plus
canonical team entries/schedule records), and delete only when zero references
remain. Return named dependency summaries when blocked. Then replace the
candidate repository's direct delete with this callable and keep archive as the
safe alternative. No rule should permit representatives or ordinary readers to
delete divisions.

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

No production activation, migration, rule deployment, or real league-data
change is part of this integration request.
