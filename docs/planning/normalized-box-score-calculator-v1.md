# HoopsConnect normalized box-score calculator v1

Status: **implemented as a pure, disabled domain component; not activated or deployed**

Architecture source: HoopsConnect Stat Integrity Architecture Plan, SHA-256 `8399812d7ff524c3a0b9f5b2d76e7a044c8ae478db641cf21760c09cf7038205`

Packet 01 dependency: `official-stat-canonical-json-v1` and the explicit-fact contract in [official-stat-contract.md](official-stat-contract.md)

## 1. Immutable versions and execution boundary

The calculator identity is `hoopsconnect-normalized-box-score-v1`. Its accepted Unicode normalization profile is `official-stat-unicode-nfc-v1`, and its canonical encoding is `official-stat-canonical-json-v1`. All three identifiers are input fields and fail closed when they do not match.

The TypeScript implementation is under `functions/src/domain/stats/`. The Dart implementation is under `lib/models/official_stats/calculators/`. Both are pure functions: they import no Firebase runtime, perform no network or storage I/O, expose no endpoint, update no aggregate, and do not mutate the supplied input.

An accepted calculator result is not certification. Later packets must bind the exact normalized bytes/hash to an immutable revision and separately establish authority, evidence, review, and certification.

## 2. Input envelope

The root object has an exact key allowlist:

```text
schemaVersion = 1
calculatorVersion
canonicalEncodingVersion
unicodeNormalizationVersion
scope = associationId + competitionId + seasonId + divisionId + phaseId + gameId
resultDisposition
statisticsDisposition = complete
provenance
rules
teams
periods
playedScore
playedScoreAdjustments
administrativeResult
officialScore
disciplineIncidents
```

Unknown keys and missing keys are rejected. V1 deliberately accepts complete box-score calculation only. A result-only or excluded revision remains representable in Packet 01, but a future immutable calculator version must define its different required-field and reconciliation semantics before this function accepts it.

`provenance` contains the capture mode, pinned ruleset version, source ID, and a human-readable source label. It applies to every player/team counter unless a field has a more specific source: time carries `timeSource`, each period carries `source`, discipline and exceptional scoring carry evidence, and official/admin results carry evidence. Source labels and scoresheet codes normalize to NFC; identifiers stay in Packet 01's strict ASCII grammar.

The calculator does not select rules by date. `rules.regulationPeriodCount`, `rules.completedTiesAllowed`, and explicit-fact regulation/overtime team-foul penalty thresholds are pinned inputs. A fixture may use a value such as five; that is fixture policy, not a universal basketball or NBL limit.

## 3. Facts and counter meanings

Every nullable value uses the Packet 01 wire fact:

```json
{"state":"known","value":0}
{"reasonCode":"not_recorded","state":"unknown","value":null}
{"reasonCode":"not_adjudicated","state":"notApplicable","value":null}
```

All complete player counters, team-only counters, and reported team totals must be known nonnegative mathematical safe integers. Unknown and not-applicable are rejected for those fields rather than coerced to zero. Known zero means the source affirmatively records zero.

Each player line contains these twelve input counters:

| Counter | Exact v1 meaning |
|---|---|
| `twoMade` | Successful two-point field goals attributed to the player. |
| `twoAttempted` | Two-point field-goal attempts attributed to the player, including makes. |
| `threeMade` | Successful three-point field goals attributed to the player. |
| `threeAttempted` | Three-point field-goal attempts attributed to the player, including makes. |
| `freeMade` | Successful free throws attributed to the player. |
| `freeAttempted` | Free-throw attempts attributed to the player, including makes. |
| `offensiveRebounds` | Offensive rebounds individually credited to the player. It excludes team rebounds. |
| `defensiveRebounds` | Defensive rebounds individually credited to the player. It excludes team rebounds. |
| `assists` | Assists individually credited to the player by the adopted statistics interpretation. |
| `steals` | Steals individually credited to the player. It is not required to equal opponent turnovers. |
| `blocks` | Blocked shots individually credited to the player. |
| `turnovers` | Turnovers individually charged to the player. Fractional values are invalid. |

Derived values are:

```text
fieldMade = twoMade + threeMade
fieldAttempted = twoAttempted + threeAttempted
points = 2 * twoMade + 3 * threeMade + freeMade
totalRebounds = offensiveRebounds + defensiveRebounds
```

Each two-point, three-point, free-throw, and total field-goal percentage is stored as an exact `{makes, attempts}` fraction. Zero attempts produce `unknown(zero_attempts)`, never numeric zero. Display conversion and rounding are outside this calculator.

The calculator does not require every missed shot to have a rebound. It does not infer attempts from points, rebounds from misses, assists from makes, or steals from opponent turnovers.

## 4. Participation and time

Every calculator run is bound to the complete Packet 01 tenant/game scope. Every player line locks participant, player, roster-membership, membership-version, and team-entry IDs. A participant or durable player can occur only once in the game and cannot cross teams. Resolving those locked IDs to records in that scope remains an authority/repository responsibility in later packets; the calculator never performs an external lookup.

Participation states are:

- `active`: requires `enteredPlay=true`, `participationReasonCode=notApplicable(entered_play)`, and contributes one game played.
- `dnp`: requires `enteredPlay=false`, a known or explicitly unknown private participation reason code, a false or absent starter fact, no departure, no playing time, and all ordinary counters at known zero.
- `inactive`: has the same no-play statistical constraints as DNP but preserves the distinct roster status and its private reason fact.

Games played is derived only from `enteredPlay`. Points and recorded/rounded minutes never create an appearance. A DNP/inactive participant can be linked to a bench incident through `relatedParticipantId`; that preserves discipline without charging an ordinary player statistic or a game played.

Time inputs are:

| Source | Required representation |
|---|---|
| `liveClock` | Known `playedTimeMs`, known positive precision, no rounding mode. |
| `officialSheetExact` | Known `playedTimeMs`, known positive precision, no rounding mode. |
| `officialSheetRounded` | Known value divisible by known positive precision, `nearestHalfUp`. |
| `notRecorded` | Unknown time, `notApplicable(no_time_source)` precision, no rounding mode. |
| `notApplicable` | Used only for no participation; time and precision are `notApplicable(did_not_enter)`. |

Exact values produce the discrete interval `[playedTimeMs, playedTimeMs + precisionMs)`. A rounded nonnegative value `R` with precision `P` produces `[max(0, R - floor(P/2)), R + ceil(P/2))`. The calculator validates that this possible interval overlaps the game's known elapsed duration. It never replaces a missing source with 30 or 40 minutes and never treats a rounded minute as exact seconds.

There is no universal game-minute ceiling. Elapsed duration comes from the supplied regulation and repeatable-overtime periods. A legitimate 50-minute double-overtime line therefore passes when its six period durations reconcile.

## 5. Teams, periods, and score reconciliation

The game has exactly one home and one away team with distinct team-entry IDs. Player order is retained; normalized team order is home then away.

`teamOnly` contains offensive rebounds, defensive rebounds, and turnovers that are attributed to the team rather than any player. They remain visibly separate. Calculated team totals equal player sums plus these values only for those three fields. `reportedTotals` supplies the complete source totals and must equal the calculated result field by field.

Period numbers start at one and are contiguous. A played result must include at least the pinned `regulationPeriodCount`; a pregame default or another adjudicated result may have zero or partial played periods. The first `regulationPeriodCount` rows are regulation with `notApplicable(regulation_period)` overtime indexes. Every later row is overtime and carries the next exact 1-based overtime index. Up to 64 rows are accepted as a payload resource bound, not a playing-rule ceiling. Period durations are positive known or explicit absent facts; scores are unbounded except by safe-integer arithmetic.

The sum of period scores must equal `playedScore`. Player point totals plus explicit played-score adjustments must also equal `playedScore` for each team.

Only `ownBasket` and `goaltending` can be played-score adjustments in v1. Each has its own ID, team, known period, and nonempty evidence. An own basket is exactly two points; goaltending is one, two, or three points. This prevents either typed field from becoming an arbitrary score balancer. Administrative awards never enter player/team played-stat totals; they live only under `administrativeResult`.

`officialScore.reconciliationStatus` must be `reconciled`, its score must equal `playedScore`, and it must carry nonempty evidence. The calculator preserves a played winner as an explicit fact; a tied score is `unknown(tied_played_score)` only when the pinned rules permit a completed tie.

For `played`, every administrative fact is `notApplicable(not_adjudicated)` and treatment follows played statistics/results. For an adjudicated disposition, evidence is mandatory. Forfeit/default and any `awardedResult` standing treatment additionally require a known awarded score and winner; that winner must lead the awarded score. Awarded score, standings treatment, and player-statistics treatment remain separate from played facts and do not manufacture a box score.

## 6. Discipline and departures

One discipline incident has exactly one exclusive `incidentType`: `personal`, `technical`, `unsportsmanlike`, or `disqualifying`. Its charged party is exactly one of player, coach, bench, or team. A player charge requires the locked participant ID; non-player charges require `notApplicable(not_player_charge)`. A separately known related participant can preserve who was involved in a bench incident.

The pinned rules interpretation is captured per incident by `countsTowardTeamFoul` and `countsTowardPlayerDisqualification`. Each incident increments `chargedFouls` exactly once. An unsportsmanlike incident therefore appears once in the unsportsmanlike bucket and never also increments the generic personal subtype. An incident that counts toward the team foul must have a known period. Team-foul counts and penalty facts are derived by period from the explicit threshold; unknown thresholds keep penalty state unknown.

Departures are `none`, `fouledOut`, `ejected`, `injured`, or `other`. A real departure carries a known or explicit unknown period/clock and known nonempty evidence; not-applicable timing is invalid. `none` uses `notApplicable(no_departure)`. A known clock requires a known valid period and cannot exceed that period's known duration. V1 records `fouledOut`; it does not impose a universal disqualification foul number.

## 7. Diagnostics versus invariants

Cross-team steals exceeding opponent turnovers produces `crossTeamStealsVsTurnoversNeedsReview` with `evidenceReview` severity. It does not reject an otherwise valid box score. This is intentionally different from arithmetic invariants such as makes exceeding attempts or score reconciliation.

The function returns exactly one first error. This is an immutable v1 behavior that prevents runtime-dependent aggregation/order differences. Validation order is:

1. Canonical type/depth/node/string and total-byte preflight.
2. Root allowlist and version pins.
3. Provenance, rules, teams, players, participation, counters, shooting, time, and departures.
4. Team-only and reported-total reconciliation.
5. Period and overtime sequence, elapsed-time and departure checks.
6. Period-score reconciliation, tie rule, and exceptional played scoring.
7. Played-score attribution.
8. Discipline, clocks, and penalty derivation.
9. Administrative outcome.
10. Official-score evidence and reconciliation.

The stable error-code vocabulary is exported in both runtimes. Codes distinguish canonical/type failures, resource limits, schema/version mismatches, identifiers/strings/facts, safe integers/overflow, team/participant/participation errors, time/departure/clock errors, shooting/team/score reconciliation, exceptional scoring, discipline, administrative result, and official-score evidence/mismatch.

## 8. Resource limits

The pure parser rejects before calculation when these implementation-safety bounds are exceeded:

| Resource | V1 bound |
|---|---:|
| Canonical input bytes | 128 KiB |
| Nesting depth | 16 |
| Traversed nodes | 20,000 |
| UTF-8 bytes per string | 1,024 (narrower field limits also apply) |
| Players per team | 64 |
| Period rows | 64 |
| Discipline incidents | 512 |
| Played-score adjustments | 128 |
| Evidence references in one fact | 64 |

All arithmetic is checked against `9,007,199,254,740,991`. No score, foul, or minute value has a lower sport-specific universal cap. These limits protect deterministic parsing and memory use; later ingress remains separately limited to 25 operations and 128 KiB per batch by Packet 01.

## 9. Shared fixtures and browser proof

`contracts/official_stats/v2/box_score_calculator_fixtures.json` is the single normative fixture file. Every case stores its complete input plus the exact canonical outcome bytes, UTF-8 byte length, and SHA-256.

Node reads that JSON directly. Dart VM reads the same file directly. `flutter_test` does not serve arbitrary workspace files to its Chrome test server, so `scripts/generate_box_score_browser_fixture.js` creates a gzip-compressed Dart mirror. The VM test proves the decompressed mirror equals the normative file byte for byte and verifies its source SHA-256 before the real-Chrome test uses it. This makes source drift fail rather than allowing independently copied browser expectations.

`scripts/generate_box_score_calculator_fixtures.js` is a deliberate golden generator, not part of test execution. Regenerating expected bytes is a contract change and requires a reviewed diff. After changing the normative JSON, regenerate and review the browser mirror too.

Fixtures cover complete tenant/game scope, zero incidents, an unattributed miss without a rebound, team-only counts, all departure kinds, player/coach/bench/team discipline, subtype non-double-counting, repeated overtime and 50-minute play, no time source, DNP bench discipline, postgame adjudication, a pregame default with zero played periods, explicit own-basket attribution, makes above attempts, three-way score mismatch, DNP ordinary stats, and safe-integer overflow. Runtime-only tests cover fractional, NaN, positive/negative infinity, negative time, resource bounds, hostile array accessors, incomplete played regulation, unsupported Unicode versions, NFC normalization, a bounded shooting-invariant grid, and insertion-order-independent errors.

## 10. Deferred scope

V1 does not add shot charts, possession analytics, public play-by-play, manual player-by-period detail, lineup reports, computed plus/minus, standings, leaderboards, Firebase commands, certification, publication, or live aggregate mutation. Those remain later packets and may consume this immutable normalized result only through their own reviewed contracts.
