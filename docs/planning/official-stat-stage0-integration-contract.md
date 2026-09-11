# Official-stat Stage 0 integration contract

Status: **implemented as a candidate-only read adapter; dormant and not
activated**

Prepared: 11 September 2026

This document fixes the Workstream D interface that league operations (C), fan
and media presentation (E), and the integration owner (I) can build against.
It does not make a legacy game official, connect the v2 calculator to the app,
write a v2 document, create a local journal, or change an activation gate.

## Inventory at the Stage 0 baseline

| Surface | Implemented foundation | Current production reachability | Stage 0 conclusion |
| --- | --- | --- | --- |
| Legacy `GameStatsModel` | Game/team scores, player point/rebound/assist/steal/block/foul/minute totals, legacy quarter maps, entry mode, and a five-value review status | Active through `StatsRepository` and current stat screens | It is the compatibility source only. Its parsers default missing numeric player facts and scores to zero, so a migration/integration adapter must read raw field presence rather than adapt an already-collapsed model. |
| Legacy `StatsRepository` | Direct game-stat reads/writes, legacy status updates, live-event append/tombstone, and aggregate readers | Active | It has no immutable revision, writer fencing, exact-revision review, or accepted-result boundary. It is intentionally unchanged in Stage 0. |
| Official-stat v2 domain | Complete scope, explicit facts, lifecycle, revision and publication contracts, canonical encoding, authority/bootstrap fixtures | Dormant | Reuse it. Do not invent a second scope, identity, lifecycle, or unknown-value vocabulary. |
| Normalized box-score calculator v2 | Dart and TypeScript implementations plus 61 shared fixture cases covering complete, result-only, administrative, overtime, exceptional-scoring, discipline, time, and resource/error cases | Dormant | It accepts a complete exact input schema. A partial legacy line is not calculator input. Missing shots, turnovers, participation, exact time, team-only counts, or official evidence cannot be changed to zero to make it run. |
| Durable local game journal | SQLite and IndexedDB stores, exact partition/package/operation/receipt contracts, recovery export, pruning, deletion reconciliation, and migration tests | Dormant; no app screen/provider/repository imports it | It already pins `rulesProfileId`, calculator version, reducer version, roster snapshot, assignment, writer epoch, and accepted head. Later integration must construct the authoritative preparation package and foreground delivery; Stage 0 does not open or write a journal. |
| Activation gates | 14 named playing-rule, competition-policy, privacy, certification, staging, restore, recovery, rollout, and cost gates | `activationAllowed` is `false` | No Stage 0 evidence resolves JBA/NBL rules adoption or another release gate. Candidate code stays unreachable from production. |

## Candidate adapter boundary

The pure Dart adapter is
`lib/models/official_stats/legacy_game_stats_v2_adapter.dart`.
Its stable versions are:

```text
candidateSchemaVersion: 1
adapterVersion: legacy-game-stats-to-official-v2-candidate-v1
sourceSchemaVersion: legacy-game-stats-v1
targetCalculatorVersion: hoopsconnect-normalized-box-score-v2
```

`ReadOnlyLegacyGameStatsV2Adapter.adapt` requires all of the following. There
are no ambient defaults:

1. A raw legacy document map, before `GameStatsModel` has supplied zero
   defaults.
2. A full reviewed v2 `GameScope`, including competition and phase.
3. A `LegacyGameStatsSourceReference` with the exact source path and payload
   hash produced by the read-only inventory/export boundary.
4. An `OfficialStatRulesProfilePin` containing a named profile ID and immutable
   association-scoped ruleset version/hash.

The adapter rejects a source season, division, or game that disagrees with the
reviewed scope. It never derives a scope from the current season, a team name,
or a display field. It records legacy team IDs as evidence and leaves v2 season
team-entry IDs unknown until a reviewed C-owned mapping exists. Player keys and
names likewise remain source evidence, not identity matches.

The candidate separates three kinds of data:

- `reportedLegacyFacts` preserve exact field presence. Explicit zero is known
  zero; an absent or null value is an explicit unknown with a stable reason.
- `normalizedInputFacts` expose the required v2 fields but keep shooting
  composition, turnovers, participation, starter state, and exact playing time
  unknown. Legacy total points and rounded minutes do not fill those fields.
- `unmappedSourcePaths`, together with the bound source payload hash, make
  unconsumed extensions visible without treating them as trusted v2 fields.

Legacy quarter-map keys become ordered `LegacyPeriodScoreEvidence`. They are
not labelled regulation or overtime and contain no nominal duration. The
rules-profile dependency supplies those meanings later. The adapter therefore
cannot select FIBA 2024, four quarters, ten-minute periods, or another format
from the number of stored quarter keys or from the runtime date.

Every adapter candidate has `calculatorInputAllowed: false` and
`certificationAllowed: false`. Its stable blocker list names the missing
official-score evidence, identity mapping, participation/starter facts, period
rules interpretation, time provenance, shooting detail, team-only counts, and
turnovers. Legacy `approved` adds
`legacyApprovalIsNotCertification`; it remains `unverified` rather than mapping
to v2 `certified`. Rebound, team, or score/period contradictions remain visible
and classify the candidate as `contradictory`.

## Contract for dependent workstreams

### C: league operations and roster ownership

C must supply reviewed mappings from durable legacy team/player/registration
evidence to v2 season-team entries, participant snapshots, player identities,
and roster membership versions. A team ID or player-line map key cannot be
copied into a v2 identity merely because it is syntactically valid. C also
supplies the competition, phase, and adopted rules-profile decision used in the
full game scope and preparation package.

### E: fan and media presentation

E may consume a later accepted result/public projection interface. It must not
treat this adapter candidate as published official data. A separately approved
staff compatibility view may label the source as legacy and unverified, show
reported totals, and render absent shooting/time/turnover facts as unavailable.
It may not display invented `0-0`, shooting percentages, games played, or a new
certification/publication version from this candidate.

### D: later calculator, review, and journal integration

D must first obtain the missing mappings/evidence and construct the calculator's
exact input. The same pinned rules profile must appear in the calculator
provenance, local journal preparation package, journal operation hash, server
validation, and immutable revision. A version mismatch fails closed. A legacy
candidate that cannot become a complete revision can remain result-only or
blocked for operator review according to the eventual adopted policy; it is not
silently padded.

### I: activation and shared roots

No shared-root change is requested by Stage 0. Later production wiring requires
an explicit dormancy transition owned by I, reviewed updates to import-graph and
pin tests, local/staging evidence, and the still-pending policy/operational
gates. Do not import this adapter from `lib/app`, `lib/features`, `lib/providers`,
or `lib/services/repositories` as an incidental refactor.

## Deterministic verification

The fixture
`contracts/official_stats/v2/legacy_game_stats_adapter_fixtures.json` pins the
candidate schema, adapter version, canonical byte length, semantic ordering,
and SHA-256 candidate hash. Tests prove:

- identical source evidence produces byte-identical canonical output;
- source player-map order cannot change output order or hash;
- known zero stays distinct from an absent field;
- missing normalized statistics remain unknown;
- a rules-profile change changes candidate identity while period count does not
  select rules or duration;
- scope mismatch and malformed counters fail closed;
- contradictions remain reviewable but uncertifiable; and
- production import roots do not import the candidate module.

These tests establish only the candidate interface. They do not establish JBA
rules adoption, calculator readiness, journal delivery, certified results,
public presentation authority, staging readiness, or deployment readiness.
