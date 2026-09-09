# Scoped authority v2 and assigned-game bootstrap contract

Packet 02 is additive, inactive, and server-internal. It defines the persisted
authorization contract, pure evaluators, and transaction wrappers. It exports
no Cloud Function, adds no app provider or UI, and performs no seed, migration,
deployment, or activation. Packet 01 remains unchanged.

The executable source fixtures are:

- `contracts/official_stats/v2/authority_fixtures.json`
- `contracts/official_stats/v2/assigned_game_bootstrap_fixtures.json`

## Persisted sources

For `A = associations/{associationId}`,
`S = A/competitions/{competitionId}/seasons/{seasonId}`, and
`G = S/games/{gameId}`, the server reads these exact paths:

1. `memberships/{uid}`
2. `A/domainControl/current`
3. `A/access/{uid}`
4. `S/control/current`
5. `S/access/{uid}`
6. `G`
7. `G/assignments/{uid}`

The path determines scope. Every duplicated UID and scope identifier must match
the trusted UID and constructed path. Authority IDs contain 1-128 ASCII
alphanumeric, underscore, or hyphen characters; `|` is therefore unavailable
inside an ID and remains a safe deterministic-slot separator. Every authority
counter is a positive JavaScript-safe integer.

`A/access/{uid}` and `S/access/{uid}` use one representation. The exact common
envelope is:

```text
dataSchemaVersion: 2
authorizationSchemaVersion: 2
uid
associationId
scopeKind: association | season
status: active | suspended | revoked
membershipVersion
accessVersion
grants: map
```

The season envelope additionally requires exact `competitionId` and
`seasonId`; the association envelope forbids them. Flat capabilities, grant
arrays, null placeholders, fallback fields, and unknown fields are invalid.

Each grant is an exact discriminated map with common fields `grantId`,
`capability`, `scopeKind`, `associationId`, `status`, `membershipVersion`,
`effectiveFrom`, and required `effectiveTo`. `effectiveFrom` and non-null
`effectiveTo` are Firestore Timestamps. Intervals are half-open:
`[effectiveFrom, effectiveTo)`; null end is open-ended. Season grants add
competition and season; division grants add division; team-entry grants add
division and team entry. Lower or forbidden fields are rejected.

Deterministic map slots are:

```text
<capability>|association
<capability>|season
<capability>|division|<divisionId>
<capability>|teamEntry|<divisionId>|<teamEntryId>
```

Association slots exist only in the association envelope. Every lower slot
exists only in the exact season envelope. At most 64 slots may exist across the
two maps. Candidate grants are evaluated most-specific first; an invalid or
inactive leaf supplies no authority and does not poison a valid independent
parent. A present malformed envelope does poison the request. A missing or
well-formed but suspended, revoked, or stale unused envelope supplies no grant.
Only the selected envelope must be active at the current membership version.

## Controls and actions

`A/domainControl/current` is the master interlock for every v2 action.
Lower-than-association actions also require `S/control/current`; season control
cannot reopen a disabled association. Both require exact mode `v2`, schema
version 2, minima 2, scope identity, a safe independent control version, and
zero to four unique grammar-valid calculator versions. Missing, disabled,
shadow, unknown, null, or malformed controls deny. Association, season, and
game control versions are independent values; the fixtures intentionally use
2, 7, and 11.

Action scopes are exact:

| Capability | Scope | Calculator | Assignment |
|---|---|---|---|
| `association.read`, `players.manage`, `players.private.read` | association | absent | no |
| `rosters.assert` | team entry | absent | no |
| `rosters.manage` | season | absent | no |
| `games.schedule` | division | absent | no |
| `stats.enter`, `stats.submit` | game | required | yes |
| `stats.review`, `stats.correct` | game | required | no |
| `stats.certify` | game | required | no; hard closed |
| `results.publish` | season | required | no |
| `results.retract` | season | absent | no |
| `official.override` | association | absent | no; hard closed |

A game scope is exactly association, competition, season, division, phase, and
game. It never contains a team entry. A team grant cannot authorize a whole
game. The canonical game head repeats the full path scope, carries ordered and
distinct `homeTeamEntryId` and `awayTeamEntryId`, forbids the old
`teamEntryIds` alternative, and has its own safe control version.

The assignment is an exact 15-field authority object: `uid`,
`dataSchemaVersion`, association, competition, season, division, phase, game,
ordered home and away team entries, `status`, `duties`, `membershipVersion`,
`writerEpoch`, and `assignmentVersion`. Unknown fields are rejected. Duties
are unique and limited to `enter` and `submit`; the required duty must exist.

Calculator selection is command-specific. Calculator-dependent commands must
supply one grammar-valid `calculatorVersion` accepted by both controls.
Calculator-independent commands reject an unsolicited calculator. Empty
allowlists therefore deny calculator-dependent commands while permitting
independent commands. `stats.certify` and `official.override` remain hard
closed regardless of grants.

## Fixed-purpose bootstrap read

Direct Firestore reads of v2 access, controls, canonical games, assignments,
and their private descendants are denied. A complete read-time Rules predicate
cannot safely support the worst valid parent-grant fallback within Firestore's
1,000-expression limit. Packet 02 therefore uses an internal server-mediated
contract rather than weakening checks or materializing a revocation-sensitive
permit.

`evaluateAssignedGameBootstrapRead` is pure.
`requireAssignedGameBootstrapReadInTransaction` constructs and reads all seven
paths in one coherent server transaction. Neither is exported from
`functions/src/index.ts`; no callable endpoint exists yet.

The request is at most 4 KiB and has only:

```text
readSchemaVersion: 2
locator: { associationId, competitionId, seasonId, gameId }
```

UID comes from trusted server authentication. The request rejects caller UID,
capability, selector, path, calculator, time, expected versions, and writer
epoch. The purpose is fixed to `stats.enter` plus duty `enter`; the client never
chooses the action. This read validates current game, assignment, and epoch
facts but is not a command: it selects no calculator and accepts no optimistic
expected-version fields.

Success is a deeply immutable internal binding with kind
`assignedGameBootstrapReadAllowed`. It contains only trusted UID, fixed purpose
and capability, full game scope, read/domain/authorization schema versions,
membership version, selected grant provenance/path/version/key/ID, both access
source presence and version facts, independent association and season control
facts, exact game path/version/ordered teams, exact assignment
path/version/epoch/duty, and trusted evaluation time. It is deliberately not a
command-authorization result.

The separately serialized DTO is at most 16 KiB and has an exact allowlist:

```text
readSchemaVersion, kind, actorAccountId, scope,
homeTeamEntryId, awayTeamEntryId, gameControlVersion,
assignment { assignmentVersion, writerEpoch, duties },
controlVersions { association, season },
compatibility {
  authorizationSchemaVersion, domainSchemaVersion, commandSchemaVersion,
  acceptedCalculatorVersions
},
evaluatedAt
```

The calculator list is the sorted intersection of the two validated control
allowlists. The DTO contains no raw membership, access map, grants collection,
role, private identity data, or `authorizedToWrite` claim. Every denial returns
only a stable denial code; partial payloads are forbidden.

## Rules and compatibility

Firestore Rules deny every client read, list, create, update, and delete for
the new v2 sources. Existing public projection behavior is unchanged. Legacy
v1 stat writes remain compatible only while association control is absent,
disabled, or shadow. Exact v2 and unknown/null modes close legacy writes.

The Admin transaction is the authoritative bootstrap read boundary. The Dart
model validates only the minimized DTO's exact wire shape and cannot grant
authority. Roles are never authority in either path.

Before a future endpoint is enabled, it must derive UID from authenticated
server context, run App Check and rate limits, use the existing transaction,
return only the DTO, and pass the activation gates. Packet 05 owns the canonical
game and assignment representation, including assignment-version
reconciliation with this safe-integer contract. Packet 07 owns local bootstrap
and journal consumption plus recovery adapter behavior. Packet 08 owns the
authenticated server-session/bootstrap integration, fenced ingress,
takeover/replay behavior, and command-time revalidation. Calculator versions
and offline reducer versions are different concepts and must never be
substituted for one another. Offline journal work consumes a successful
bootstrap but cannot extend authority or bypass a later server re-check for
submission or mutation.
