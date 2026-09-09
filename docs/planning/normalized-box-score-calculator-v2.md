# HoopsConnect normalized box-score calculator v2

Status: **pure, disabled domain component; not activated, exported from a runtime entrypoint, deployed, or connected to production data**

Architecture source: HoopsConnect Stat Integrity Architecture Plan, SHA-256 `8399812d7ff524c3a0b9f5b2d76e7a044c8ae478db641cf21760c09cf7038205`

Packet 01 dependency: `official-stat-canonical-json-v1` and the explicit-fact contract in [official-stat-contract.md](official-stat-contract.md).

## Version and migration boundary

The corrected identities are:

- calculator: `hoopsconnect-normalized-box-score-v2`
- input/output schema: `2`
- Unicode profile: `official-stat-unicode-nfc-v2`
- canonical encoding: `official-stat-canonical-json-v1`

V2 is a fail-closed replacement for the rejected, never-activated v1 branch artifact. V1 inputs do not migrate implicitly: their calculator, schema, and Unicode version pins are rejected. A caller must construct and validate a complete v2 envelope. No production caller or stored v1 revision exists in this packet, so there is no live-data rewrite.

An accepted result is arithmetic normalization, not certification. Later packets must bind its exact canonical bytes and SHA-256 to an immutable revision and independently establish source authority, evidence, review, privacy, and publication eligibility.

## Pure boundary

The implementations are `functions/src/domain/stats/calculator.ts` and `lib/models/official_stats/calculators/normalized_box_score.dart`. They perform no I/O and import no Firebase, HTTP, storage, clock, random, or UI runtime. The Functions entrypoint and Flutter feature/provider trees do not call them. Both object and raw-JSON APIs return deeply immutable accepted or rejected graphs and exactly one deterministic first error.

## Input envelope and numeric policy

The root exact allowlist is:

```text
schemaVersion = 2
calculatorVersion
canonicalEncodingVersion
unicodeNormalizationVersion
scope = associationId + competitionId + seasonId + divisionId + phaseId + gameId
resultDisposition
statisticsDisposition
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

All counts are known, nonnegative mathematical safe integers. JSON spellings such as `1`, `1.0`, and `1e0` decode to the same integer value and normalize to integer output. Fractions, non-finite runtime numbers, negatives, and arithmetic above `9,007,199,254,740,991` reject. Known zero is never confused with unknown or not-applicable.

## Player, team, and participation invariants

The twelve player counters are two/three/free makes and attempts, offensive/defensive rebounds, assists, steals, blocks, and turnovers. Derived values use checked arithmetic:

```text
fieldMade = twoMade + threeMade
fieldAttempted = twoAttempted + threeAttempted
points = 2 * twoMade + 3 * threeMade + freeMade
totalRebounds = offensiveRebounds + defensiveRebounds
```

Makes cannot exceed attempts. A missed shot need not have a rebound. Steals exceeding opponent turnovers are an evidence-review diagnostic, not a rejection. Team-only offensive rebounds, defensive rebounds, and turnovers remain separate while contributing to reported team totals.

`enteredPlay` is the sole games-played signal. DNP/inactive lines require zero ordinary counters, no playing time, and no departure. A DNP may be a `relatedParticipantId` on a bench incident, but an on-court player charge requires a same-team participant who entered play. A `complete` statistics label or `includePlayedStatistics` administrative treatment is not evidence that play occurred. A period represents play only when its elapsed duration is explicitly unknown or is known to be greater than zero; a zero-elapsed partial row cannot conceal player or team counters. When there are no represented periods, points, or score adjustments, the no-play guard still rejects entered players, ordinary stats, team-only stats, and time; only evidenced non-player pregame discipline can remain.

## Period state, time, and departures

Every period separately records:

- nominal duration;
- actual elapsed duration or explicit unknown;
- `completed`, `partial`, `suspended`, `resumedCompleted`, `abandoned`, or `adjudicated` state;
- total score, player-counter points, and exceptional-scoring points for each side.

Completed/resumed-completed periods require elapsed duration equal to nominal duration. A partial state can occur only on the last represented period and never in a normal `played` result. Repeatable overtime rows require contiguous 1-based overtime indexes and the pinned overtime policy.

Exact time is a discrete interval. Generic rounded time uses the pinned nearest-half-up interval. The optional `fiba-2024-reference-sheet-v1` profile implements the cited sheet conventions, including positive sub-minute play displayed as one minute and the minute immediately below the game maximum remaining rounded down. Missing time stays unknown.

Every known player-time interval must fit within the actual represented elapsed duration, or within the sum of represented nominal durations when elapsed is unknown. Known player-time lower bounds are also summed per team and must not exceed that same conservative duration bound multiplied by the explicit team-capacity multiplier. At every known or conservative permanent-exit deadline, the known lower-bound demand that must be completed through that deadline must fit within the team capacity available through it: this includes the applicable demand of players exiting by then and, for each player who can continue later, the portion that cannot fit between that checkpoint and the player's own effective deadline.

A permanent departure or player disqualification bounds a player's possible time even when its clock is unknown. A known clock uses cumulative actual elapsed opportunity through the event; otherwise a known exit period uses the tightest available elapsed-or-nominal upper bound through that period. A line whose lower possible time exceeds the earliest supported permanent-exit opportunity rejects. Incident order is derived from period and, when both are known, the countdown clock; later incidents reject independently of input array order. Explicit departure and disqualification evidence must agree on known period and clock facts. An exit whose period itself is unknown remains unknown and is not guessed, and same-period events with an unknown clock remain indeterminate.

## Exceptional scoring attribution

V2 does not use a free-floating score-balancing adjustment. It models only:

- `accidentalOwnBasket`: exactly two points, credited as a two-point make to an entered participant on the scoring team;
- `defensiveGoaltending`: two or three points, credited as the corresponding made shot to an entered participant on the scoring team.

Each adjustment pins the scoring team, violating opponent, period, credited participant, credited shot, statistical treatment, and nonempty evidence. The credited participant must be eligible in that period: a credit in a later period than a known permanent departure or disqualifying incident rejects. Same-period credit remains possible because the adjustment contract has period granularity, not an event clock. The only accepted treatment is `includedInPlayerCounters`; the corresponding make and attempt must already exist in the credited player's counters. Each period's exceptional total must exactly equal its typed adjustments. Player counter points, period score, played score, team points, and official score must then agree without additive double counting.

The attribution profile name is `fiba-2024-reference-attribution-v1`. It is based on the [FIBA Statisticians' Manual 2024](https://assets.fiba.basketball/image/upload/documents-corporate-fiba-statisticians-manual-2024.pdf), which describes accidental own-basket and defensive-goaltending statistical credit. It is a named reference profile only. **This packet does not claim that the Jamaica Basketball Association or National Basketball League has adopted that manual or the FIBA 2024 rules.** Activation requires an authoritative adopted ruleset.

## Explicit penalty policy

Penalty accumulation is data, not a hidden universal. `penaltyAccumulationGroups` partitions every represented period exactly once and gives each group a known or unknown `penaltyStartsAtFoul` fact. Normalized output preserves raw team fouls by period, the cumulative count through each period's group, the threshold fact, and known/unknown penalty status.

`penaltyStartsAtFoul` names the next foul that receives the penalty, not the count at which the state first becomes visible. A known threshold of five therefore means the team is in the penalty situation after its fourth team foul and the fifth foul receives the penalty.

The `fiba-2024-reference-v1` profile validates four regulation periods, a five-player team-time multiplier, five-minute overtime, that known threshold of five, regulation resets, and one accumulation group spanning period four plus every overtime. That continuation follows Article 41 of the [FIBA Official Basketball Rules 2024](https://assets.fiba.basketball/image/upload/documents-corporate-fiba-official-rules-2024-v10a.pdf). Alternative leagues use `generic-explicit-v2` and may define different thresholds or reset each overtime. Again, the reference profile is a calculation profile only and is not evidence that Jamaica/JBA/NBL has adopted these rules.

## Administrative result separation

Played statistics never absorb an awarded score. `playedScore`, player/team counters, and `officialScore` reconcile independently from `administrativeResult.awardedScore`, winner, standings treatment, and player-statistics treatment. Result-only/excluded pregame defaults carry zero played facts. A forfeit or adjudication after actual play may retain complete played statistics only when its treatment explicitly says so.

## Unicode normalization provenance

Packet 01 and Packet 06 share one normalization boundary per runtime. The Functions boundary fails closed unless Node reports Unicode 17 and passes a Unicode-17-sensitive combining-order sentinel before relying on ECMAScript NFC. Dart resolves the repository-pinned `third_party/unorm_dart` 0.3.2 source, whose [published package](https://pub.dev/packages/unorm_dart) declares Unicode 17 data and an MIT license.

The reviewed Dart source carries one boundary correction in `lib/src/uchar.dart`: U+D7A4, the first scalar after the algorithmic Hangul syllable range U+AC00..U+D7A3, takes the ordinary Unicode-data path. Without the inclusive upper-bound rejection, U+D7A4 collides with the distinct Jamo input U+1113 U+1161. The patch is applied at the source decision boundary and does not post-rewrite normalized output. `source_manifest.json`, the retained MIT license, and hard-coded review anchors in `scripts/verify_unicode_normalization_source.js` pin every reviewed source file and prove that `uchar.dart` differs from upstream by exactly that one replacement.

Shared canonical fixtures cover U+D7A3 precomposed and decomposed, U+D7A4, the deliberate Jamo sequence, and a combining-order case whose NFC result changed in Unicode 17, with exact bytes and hashes on Dart VM, Chrome/DDC, optimized dart2js, and Node.

## Resource bounds

Preflight accounts incrementally before whole-payload sorting or canonicalization. The bytes-per-string ceiling is enforced both before and after NFC so normalization expansion cannot bypass a runtime's resource boundary:

| Resource | Bound |
|---|---:|
| raw JSON transport | 128 KiB |
| canonical input | 128 KiB |
| nesting depth | 16 |
| traversed nodes | 20,000 |
| entries in one list/map | 1,024 |
| keys in one object | 128 |
| bytes per string/key | 1,024 |
| players per team | 64 |
| periods | 64 |
| penalty groups | 64 |
| discipline incidents | 512 |
| score adjustments | 128 |
| evidence refs per fact | 64 |

Node additionally rejects accessors, symbols, sparse/extended arrays, non-plain records, and non-enumerable properties without invoking getters. It calculates only from the one bounded descriptor snapshot produced by preflight, so a Proxy cannot present a small graph to resource accounting and a different graph to the schema parser. Dart likewise calculates from one bounded ordinary snapshot of caller-controlled collections, and both runtimes reject an active cyclic reference at the first repeated edge as `invalidCanonicalValue`. JavaScript-specific descriptor and Proxy hazards do not exist in decoded Dart JSON graphs.

## Shared proof corpus

`contracts/official_stats/v2/box_score_calculator_fixtures.json` is normative. Every case declares independent semantic checks before storing the exact canonical result, UTF-8 length, and SHA-256. Tests never regenerate expected results. The generator is a reviewed contract-maintenance tool, not a test oracle.

The corpus includes zero discipline, non-rebound misses, team-only stats, typed discipline/departures, input-order-independent disqualification chronology, disqualification/departure reconciliation, same-period clock ordering, permanent-exit player-time and cumulative team-time deadlines, exact and rounded deadline boundaries, conservative unknown clocks, overtime and both team sides, NFC expansion/contraction boundaries, DNP and pregame barriers, double overtime, partial/suspended/abandoned/adjudicated/resumed periods, generic and FIBA-reference time intervals, accidental own basket, defensive goaltending, per-period attribution failures, regulation and repeated-overtime penalty grouping, makes-over-attempts, score mismatch, and safe-integer overflow. Runtime tests add `1.0`/`1e0`, non-finite values, hostile Proxy/getter/stateful-enumeration/cyclic graphs, deep/large resource exhaustion, no-play label and zero-elapsed-period bypasses, post-departure and post-disqualification exceptional scoring, adjustment-first error precedence, 3/4/5-foul transitions, mutation attempts, bounded arithmetic grids, and map-insertion-order stability.

`scripts/generate_box_score_browser_fixture.js` creates a compressed Dart mirror because Flutter's Chrome test server does not expose arbitrary repository files. The VM test proves the mirror is byte-identical to the normative JSON and checks its source SHA-256. `tool/official_stats_dart2js_conformance.dart` runs the same exact corpus plus numeric, Unicode collision, and immutability probes after `dart compile js -O4` in actual Chrome. The Python launcher creates a random per-run challenge in the harness URL; only the compiled Dart entrypoint reads it and writes it back to the rendered body immediately before its success marker. Its DevTools WebSocket upgrade has one monotonic deadline, rejects immediate or partial-header EOF, and closes failed sockets. Acceptance requires that exact challenge, a zero-exit Chrome process, a parsed rendered `#status` matching the pinned case count, and an independent `data-conformance="passed"` body state. Timeouts, static or pre-marked HTML, missing JavaScript, wrong counts or challenges, and runtime failures reject.

## Deferred scope

V2 does not add shot charts, possession analytics, public play-by-play, manual player-by-period detail, lineup reports, plus/minus, standings, leaderboards, Firebase commands, review/certification, publication, or aggregate mutation. Those remain separate packets and must consume a future immutable revision through their own reviewed boundaries.
