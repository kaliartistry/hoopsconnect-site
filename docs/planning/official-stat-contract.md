# HoopsConnect Official-Stat Contract v2

Status: **implemented as a disabled contract; not activated or deployed**

Architecture source: approved HoopsConnect Stat Integrity Architecture Plan, SHA-256 `8399812d7ff524c3a0b9f5b2d76e7a044c8ae478db641cf21760c09cf7038205`

Baseline: `3feb0fe359e3c69b6f9a1d27044a5d82f69b212f`

This document is the executable boundary for implementation packets 02–17. The typed Dart and TypeScript contracts and shared fixtures under `contracts/official_stats/v2/` are normative with this document. A later packet must change the contract and its fixtures deliberately if it needs a different field, state, transition, encoding, error, or activation gate. It must not silently invent one.

## 1. Authority and scope

The association/operator is the tenant. JBA is an association and NBL is its first competition. Nothing in v2 creates a global person registry or authorizes cross-association identity matching.

The complete game scope is:

```text
associationId / competitionId / seasonId / divisionId / phaseId / gameId
```

`GameScope` requires every component. A null or missing scope field never means “all.” The path determines scope; every duplicated scope field in a document must match its path. New opaque IDs use 1–128 ASCII letters, digits, `_`, or `-`, begin with a letter or digit, and are never derived from a name, email, jersey, or likeness. Migration IDs may be deterministic only through an approved versioned namespace mapping.

Canonical path aliases are:

```text
A = associations/{associationId}
C = A/competitions/{competitionId}
S = C/seasons/{seasonId}
G = S/games/{gameId}
P = publicData/{associationId}/competitions/{competitionId}/seasons/{seasonId}
```

All new records carry `dataSchemaVersion: 2`. This packet does not add Firestore access or activate any path.

## 2. Version contract

Every official candidate and every reproducible release pins these independent concepts:

| Concept | Contract field | Meaning |
|---|---|---|
| Stored shape | `dataSchemaVersion` | Document representation, currently `2` |
| Domain semantics | `domainSchemaVersion` | Identity, state, and invariant vocabulary, currently `2` |
| Command envelope | `commandSchemaVersion` | Request/idempotency shape, currently `2` |
| Authorization | `authorizationSchemaVersion` | Required scoped-grant semantics, proposed `2`; not active yet |
| Playing rules | `rulesetVersion` | Pinned playing rules, foul/time/outcome interpretation and adoption evidence |
| Competition policy | `policyVersion` | Standings, qualification, transfer, correction, certification, and publication choices |
| Calculation | `calculatorVersion` | Immutable reducer/calculator artifact |
| Projection | `projectionVersion` | Public/internal DTO and aggregate builder semantics |
| Identity resolution | `identityResolutionVersion` | Approved alias/merge map used for an aggregate build |
| Privacy | `privacyPolicyVersion` | Field-level public identity authority |
| Branding | `brandingVersion` | Approved team/association display assets and names |
| Publication | `PublicationReleaseVersion` | Release ID, source-set/projection hashes, publication epoch, privacy epoch, and all pinned versions |

A `VersionReference` is `{associationId, versionId, sha256}`. Version IDs have no authority outside their association. Runtime dates must never select a ruleset. Volatile build/activation timestamps do not participate in content identity.

Independent compatibility controls will later be:

```text
minimumAuthorizationSchemaVersion
minimumDomainSchemaVersion
minimumCommandSchemaVersion
acceptedCalculatorVersions
authorityMode: disabled | shadow | v2
```

Packet 01 leaves authority mode effectively disabled.

## 3. Identity and temporal domain

- `PersonIdentityContract` holds minimum necessary identity and restricted eligibility evidence. It is private and association-scoped.
- `PlayerIdentityContract` is durable sporting identity and links privately to one person. It has an independently versioned display name and may be provisional, verified, merged, suspended, or archived.
- `TeamIdentityContract` is the durable team. It is not a season registration.
- `SeasonTeamEntryContract` places one durable team in one season/division with a seasonal name/branding version and registration state.
- `RosterMembershipContract` links one player to one season team entry through a versioned eligibility spell.
- Effective intervals are half-open: `[effectiveFrom, effectiveTo)`. `recordedAt` is separate from the effective time. A release, transfer, suspension, or correction creates history; it never deletes identity or prior membership.
- Player aliases are reviewed append-only mappings. Neither names nor emails nor jerseys merge identities.
- Jerseys are strings. `"0"` and `"00"` are distinct and must round-trip unchanged.
- `GameParticipantSnapshotContract` copies exact participant, player, membership/version, team entry, jersey, display-name version, eligibility state, and evidence into a game-owned immutable snapshot. Later roster, transfer, rename, team archive, or identity resolution does not rewrite it.

The executable entity inventory in `schema_registry.dart` fixes path, classification, mutability, visibility, required fields, and fields that require explicit fact state.

## 4. Explicit facts: known, unknown, and not applicable

All facts that can be missing or inapplicable use one of:

```json
{"state":"known","value":0}
{"reasonCode":"not_recorded","state":"unknown","value":null}
{"reasonCode":"result_only","state":"notApplicable","value":null}
```

Known zero is evidence-backed zero. Unknown is not zero. Not applicable means the field does not apply under the pinned disposition/policy. Consumers must display or withhold these states honestly and may not coerce either absent state to zero, an empty string, or `false`.

In particular:

- Never invent minutes. `playedTimeMs` remains unknown when no time source exists.
- Exact time pins `timeSource` and `timePrecisionMs`. Rounded sheet minutes retain their precision and rounding policy rather than becoming fabricated seconds.
- `enteredPlay`, not nonzero stats or rounded minutes, determines participation.
- DNP/inactive participants have no time or on-court statistics. A separately classified bench incident may exist without creating a game played.
- Result-only historical evidence may affect standings only if the adopted policy permits; it never fabricates player appearances or box-score counters.
- A percentage with zero attempts is undefined, not zero.

## 5. Official box-score revision

Live capture, official-sheet entry, and historical import all seal the same immutable revision contract. A mutable final box score must not coexist with the journal. Switching capture modes creates a successor workspace/revision with a reason and diff.

The manifest requires:

```text
dataSchemaVersion
associationId, competitionId, seasonId, divisionId, phaseId, gameId
revisionId, revisionNumber, supersedesRevisionId
captureMode: liveCapture | officialSheet | historicalImport
resultDisposition: played | forfeit | default | annulled | otherAdjudicated
statisticsDisposition: complete | resultOnly | excluded
rulesetVersion, policyVersion, calculatorVersion
scheduleRevisionId, rosterSnapshotId, rosterSnapshotHash
sourceWorkspaceId, acceptedThroughSequence, journalHash
officialScoreEvidenceRefs
inputParts: [{partId, kind, count, sha256}]
inputHash, derivedHash, validationReportHash
createdBy, createdAt
```

Revision parts have fixed schemas and a maximum encoded size of 128 KiB. The server creates parts before the manifest and must prove complete counts/hashes first.

Required first-release player inputs are participant/player/membership/team-entry identity; entered-play, starter, active/DNP/inactive status; time and provenance; 2PM/2PA, 3PM/3PA, FTM/FTA; offensive/defensive rebounds; assists, steals, blocks, turnovers; typed discipline; departure state; and plus-minus only when complete validated lineup/scoring evidence exists. Required team/game inputs include team-only rebounds and turnovers, player/coach/bench/team incidents, period team-foul/penalty derivation, repeatable overtime periods, played versus awarded score, official score reconciliation, actual start/suspension/resumption/completion evidence, and field coverage/provenance.

Derived values are `FGM = 2PM + 3PM`, `FGA = 2PA + 3PA`, `PTS = 2×2PM + 3×3PM + FTM`, and `REB = OREB + DREB`. Counters are finite nonnegative integers; makes cannot exceed attempts. Team totals equal player sums plus explicitly permitted team-only categories. Period, played, and attributed scores must reconcile under the pinned rules. There is no balance-score field.

No universal 48-minute, five-foul, or 100-point ceiling exists. Overtime, short-handed intervals, own baskets, goaltending, administrative awards, disciplinary subtypes, and incomplete time require rule-aware treatment. Ranking uses exact values and display rounding happens afterward.

Deferred fields—shot charts, possession analytics, advanced efficiency, public play-by-play, manual player-by-period detail, lineup reports, and computed plus-minus—remain absent or explicitly unavailable.

## 6. Lifecycle contract

Three dimensions remain separate:

- Play: `scheduled`, `postponed`, `inProgress`, `suspended`, `completed`, `cancelled`, `administrativelyTerminated`.
- Review of one revision: `draft`, `submitted`, `underReview`, `changesRequested`, `certified`.
- Publication of one certificate: `absent`, `published`, `superseded`, `retracted`.

The exact allowed edges live in the shared fixture and `OfficialStatLifecycle`; all other edges fail closed. A schedule revision does not fake a state change. A changes-requested resubmission must point to a successor revision. Certified revisions never reopen; corrections start successor work. Published content can coexist with a private correction workspace.

Starting play requires `stats.enter`, an exact assignment, prepared package, frozen snapshot, and writer epoch. Completion is explicit and never inferred from wall-clock time. Submission binds an immutable candidate to the accepted journal head/hash. Review claims the exact revision/hash. Certification requires fresh authority, validation/evidence, and separation of duties. Self-certification is disabled pending an activation decision.

After play begins, cancellation cannot erase evidence. Suspension keeps the same game. A replay uses a linked new game ID. Forfeit/default/annulment decisions preserve separately:

```text
playedScore
awardedScore
resultWinner
standingsTreatment
playerStatisticsTreatment
adjudicationEvidence
```

They do not manufacture player points.

## 7. Journal, idempotency, and writer fencing

`JournalOperationContract` fixes the future local/server operation vocabulary: operation/command IDs, full scope, workspace, actor, device session, writer epoch, local sequence, previous-operation hash, expected server head, operation/reducer/ruleset versions, typed operation and payload hash, basketball ordering metadata, observation time, delivery state, retry state, and receipt.

Later packets must save the local operation and checkpoint transactionally before displaying “Saved on this device.” Native uses transactional SQLite; web/PWA uses IndexedDB transactions behind one Dart repository interface. Firestore cache is not the pending-operation authority.

Server ingress is ordered, atomic, and bounded to 25 operations / 128 KiB per batch. It validates current authority, assignment, epoch, sequence, schemas, and hashes, then commits accepted operations, receipts, and the workspace head together. A lost response is retried with the same command ID and identical payload. Exact replay returns the original semantic result; the same ID with another payload returns `payloadKeyConflict`.

There is initially one authoritative writer session per game. Transfer is explicit and online and increments `writerEpoch`; heartbeat expiry alone cannot take authority. An old epoch becomes a preserved conflict branch. Automatic multi-device merge is prohibited.

## 8. Command errors

Stable error codes and retry classes are executable in the fixture and `OfficialStatCommandErrors`.

| Retry class | Client behavior |
|---|---|
| `never` | Stop; do not retry the same semantic request |
| `retrySameCommand` | Exponential backoff with jitter, capped at 60 seconds; preserve command ID and payload |
| `refreshAuthenticationThenRetrySameCommand` | Reauthenticate, then retry the identical command |
| `refreshStateThenCreateNewCommand` | Fetch current authority/head, show any conflict, and create a new command only after reconciliation |
| `operatorResolutionRequired` | Pause visibly; preserve pending evidence for an authorized person to resolve |

Errors cover invalid arguments/IDs, unsupported schemas, unopened policy gates, authentication/permission/scope/assignment, stale authority/control/revision, idempotency payload conflict, sequence gaps/conflicts, stale writer epoch/transfer, denied lifecycle, invariants/evidence, preserved branches, local resource exhaustion, rate limiting, transient availability, deadline, and internal failure. `429`, transient, deadline, and uncertain internal responses never discard local work.

## 9. Certification, projection, publication, and privacy

A certificate attests exactly one immutable revision/hash. A correction targets a certificate and appends reason, field diff, evidence, and successor workspace/revision. Neither mutates the original.

Certification and publication selection are independent. A public selection starts from the previous explicit selection and applies only reviewed additions, replacements, and removals. It never includes every latest internal certificate automatically; publishing game B must not expose privately certified game A.

A projection build freezes exact certificates and approved schedule revisions plus rules, competition policy, identity resolution, privacy, branding, calculator, and projection versions. It recomputes privately, validates reference closure/counts/arithmetic/privacy/checksums, and seals. Partial builds are unreadable.

The content identities are:

```text
sourceSetHash = SHA256(canonical sorted selected source tuples)

releaseId = SHA256(
  scope + sourceSetHash + calculatorVersion
  + rulesAndCompetitionPolicyHashes + identityResolutionVersion
  + privacyPolicyHash + brandingVersion + projectionSchemaVersion
)
```

One small final transaction rechecks current membership/grants, game/revision/certificate state, control epochs, publication head, privacy epoch, and pinned policies. It advances the season release head to exactly one sealed release. A retraction atomically makes the head absent. Do not construct a hybrid release in that transaction.

V2 public Firestore is server-only. Public clients use bounded HTTP projections with one pinned release per screen/export. Every delivery coherently checks release and privacy authority; changed releases return `409`, retracted content `410`, and unknown/private identity `404`. There is no private-model fallback. Initially responses/assets use `Cache-Control: no-store` and no permanent Firebase download-token URL may bypass revocation.

Privacy is field-specific. Permission for name never implies photo, bio, birthday, school, guardian, or contact. Unknown/minor defaults closed for individual public identity. A privacy revocation increments the association privacy epoch and invalidates stale releases across seasons. Previously downloaded files and screenshots cannot be remotely erased, so clients must stop treating a known-revoked release as current.

## 10. Canonical encoding v1

`official-stat-canonical-json-v1` is UTF-8 JSON with these rules:

1. Allowed values are explicit null, boolean, Unicode string, cross-runtime safe integer (`±9,007,199,254,740,991`), UTC timestamp, ordered list, and string-keyed map.
2. Floating point, NaN/infinity, unsafe integers, sets, arbitrary objects, and implicit/undefined values are rejected.
3. Schema keys are nonempty printable ASCII and sorted ascending by ASCII code point at every map level.
4. Text values normalize to Unicode NFC before JSON escaping. Case and meaningful whitespace are preserved; identifiers use their stricter ASCII grammar.
5. Timestamps use years 0001–9999 and normalize to RFC 3339 UTC with exactly millisecond precision, e.g. `2026-10-01T06:02:03.456Z`.
6. Array order is preserved. Any semantically unordered collection must be explicitly sorted by its contract key before encoding.
7. Explicit null fields remain present. Volatile timestamps and delivery metadata are excluded from content identity by the enclosing schema, not silently removed by the encoder.
8. SHA-256 is lowercase hexadecimal over the exact UTF-8 canonical bytes. Hashes detect reproducibility/alteration; they are not signatures or proof that input facts are true.
9. The encoding version is pinned alongside any persisted content identity. A change requires a new encoding version and golden fixtures.

Dart and TypeScript execute the same Unicode, timestamp, nested-key, jersey, and SHA-256 fixtures.

## 11. Activation gates

`contracts/official_stats/v2/activation_gates.json` is normative and currently says `activationAllowed: false`. Every entry remains unresolved until supported by authoritative evidence and a named owner. Required gates include:

- JBA/NBL regulations and explicit FIBA 2024 versus rules-effective-2026-10-01 adoption.
- Standings, qualification, playoffs, tie-breakers, deductions, forfeits/defaults/abandonment, and transfers/eligibility.
- Named certifiers and an exceptional self-certification policy; the exception remains disabled by default.
- Player/minor public name and photo/publicity rights with field-level revocation.
- Staging ownership/proof; backup, retention, Storage coverage, restore drill; recovery RPO/RTO and ownership; rollout/rollback authority; and cost ownership/thresholds.

No implementation packet may convert these defaults into league policy. A default is a safe disabled behavior only.

## 12. Legacy compatibility and reversibility

This packet is additive and has no data migration. Existing `A/teams`, `A/events`, game stats, aggregates, approval flags, rules, functions, and public readers remain unchanged.

Legacy `approved` means unverified migration evidence, not certification. Generated/backfilled records are `synthetic`; they are never auto-certified. Later inventory uses `evidenced`, `unverified`, `synthetic`, `orphaned`, `contradictory`, `duplicateCandidate`, and `privacyRestricted`. Unknown scope or conflicting identity blocks migration rather than inventing a join.

Before activation, Packet 01 can be reverted by removing its contract/types/tests and dependency; no cloud or local user data needs reversal. Later migration must shadow-write create-only v2 paths, retain source documents, use deterministic mappings and dry-run manifests, and reject hash conflicts. Cutover should reject old official-stat writes rather than two-way dual-writing. A read-only compatibility adapter may show clearly labelled unverified data to authorized staff but cannot certify or publish it.

Rollback after eventual activation is not a return to permissive legacy authority. Stop affected commands, preserve accepted journals/certificates/evidence, restore and replay in staging, verify hashes and authority, then roll forward or execute a reviewed recovery plan. Never discard acknowledged new work, restore vulnerable rules, or reopen raw public reads.

## 13. Packet 01 acceptance evidence

The following must pass before review:

- Dart tests for exact versions, scope/ID constraints, entity inventory, fact semantics, jersey strings, half-open time, privacy defaults, lifecycle transitions, command classifications, canonical encoding, Unicode NFC, timestamps, rejected ambiguous values, and golden hashes.
- Functions TypeScript build and Node tests over the same golden fixtures.
- Existing Flutter test suite and `flutter analyze`.
- Existing Functions/security suites and repository-safety checks as proportionate to this foundation-only change.

Passing these tests establishes the contract only. It does not establish production authorization, game-day reliability, privacy authority, staging readiness, migration safety, or deployment readiness.
