"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const calculator = require("../lib/domain/stats/calculator.js");
const contract = require("../lib/domain/official_stats_contract.js");

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, "../../contracts/official_stats/v2/box_score_calculator_fixtures.json"),
  "utf8",
));
const clone = (value) => structuredClone(value);
const byName = (name) => fixture.cases.find((entry) => entry.name === name);
const base = () => clone(byName("complete_zero_disciplinary_incidents").input);
const exactTime = (value) => ({
  playedTimeMs: {state: "known", value},
  roundingMode: "notApplicable",
  timePrecisionMs: {state: "known", value: 1},
  timeSource: "liveClock",
});
const valueAt = (value, dottedPath) => dottedPath.split(".").reduce(
  (current, key) => current[Number.isInteger(Number(key)) ? Number(key) : key],
  value,
);
const reviewedFixtureHashes = Object.freeze({
  complete_zero_disciplinary_incidents: "6d464d01c32b6feda8d4051248beaa9d5a11e665b9239f083323756cad7e2755",
  own_basket_is_credited_and_included_once: "4326f46698936f0977d2cfaf5179a56d768a7c133aef7cabf3bbb58382d65c7b",
  reject_dnp_with_assist: "60a709756764e4d82408d925c2cdb324c7d32ee16e72b2444134b7c198e49cae",
  partial_period_keeps_nominal_and_elapsed_separate: "ea717faf4c9993e71c8ed6fe8cb7249aac230769603c303aac75f07ebc61a1a2",
  fiba_reference_groups_q4_and_repeated_overtime: "405f2024121b6a3962b55acfab84aa8eb9b67557afb379c0c9f4948c16de51d8",
  reject_safe_integer_arithmetic_overflow: "54d9b13316c81b5733c8a949c9beda857070386e4aa9a0de848eddaea471b110",
});

test("calculator versions and vocabularies are unique and fixture-bound", () => {
  assert.equal(fixture.fixtureSchemaVersion, 2);
  assert.equal(fixture.calculatorVersion, calculator.normalizedBoxScoreCalculatorVersion);
  assert.equal(fixture.unicodeNormalizationVersion, calculator.normalizedBoxScoreUnicodeVersion);
  assert.equal(fixture.canonicalEncodingVersion, contract.officialStatVersions.canonicalEncodingVersion);
  assert.equal(new Set(calculator.playerCountFields).size, calculator.playerCountFields.length);
  assert.equal(new Set(calculator.calculatorErrorCodes).size, calculator.calculatorErrorCodes.length);
  assert.doesNotThrow(() => calculator.assertCalculatorErrorVocabulary());
});

test("Node consumes every shared fixture with exact semantics, bytes, and SHA-256", () => {
  for (const entry of fixture.cases) {
    const before = contract.canonicalEncode(entry.input);
    const outcome = calculator.calculateNormalizedBoxScore(entry.input);
    assert.equal(outcome.status, entry.expectedSemantics.status, entry.name);
    if (outcome.status === "accepted") {
      for (const check of entry.expectedSemantics.checks) {
        assert.deepEqual(valueAt(outcome, check.path), check.value, `${entry.name}: ${check.path}`);
      }
    } else {
      assert.deepEqual(outcome.errors[0], entry.expectedSemantics.error, entry.name);
    }
    const canonical = contract.canonicalEncode(outcome);
    assert.equal(canonical, entry.expectedCanonical, entry.name);
    assert.equal(Buffer.byteLength(canonical, "utf8"), entry.expectedCanonicalByteLength, entry.name);
    assert.equal(contract.canonicalSha256(outcome), entry.expectedSha256, entry.name);
    assert.equal(contract.canonicalEncode(entry.input), before, `${entry.name} mutated its input`);
  }
});

test("reviewed sentinel hashes are independent of the fixture generator", () => {
  for (const [name, expectedSha256] of Object.entries(reviewedFixtureHashes)) {
    assert.equal(byName(name).expectedSha256, expectedSha256, name);
  }
});

test("accepted and rejected result graphs are deeply immutable", () => {
  const accepted = calculator.calculateNormalizedBoxScore(base());
  assert.equal(accepted.status, "accepted");
  assert.ok(Object.isFrozen(accepted));
  assert.ok(Object.isFrozen(accepted.normalizedBoxScore));
  assert.ok(Object.isFrozen(accepted.normalizedBoxScore.teams));
  assert.ok(Object.isFrozen(accepted.normalizedBoxScore.teams[0].totals));
  assert.equal(Reflect.set(accepted.normalizedBoxScore.playedScore, "home", 99), false);
  assert.throws(() => accepted.normalizedBoxScore.teams.push({}), TypeError);

  const rejected = calculator.calculateNormalizedBoxScore({});
  assert.equal(rejected.status, "rejected");
  assert.ok(Object.isFrozen(rejected));
  assert.ok(Object.isFrozen(rejected.errors));
  assert.ok(Object.isFrozen(rejected.errors[0]));
  assert.equal(Reflect.set(rejected.errors[0], "path", "mutated"), false);
});

test("mathematical integers are normalized at object and raw JSON boundaries", () => {
  const runtime = base();
  runtime.schemaVersion = 1.0 + 1.0;
  assert.equal(calculator.calculateNormalizedBoxScore(runtime).status, "accepted");

  const raw = JSON.stringify(base());
  for (const spelling of ["2.0", "2e0"]) {
    const variant = raw.replace('"schemaVersion":2', `"schemaVersion":${spelling}`);
    const outcome = calculator.calculateNormalizedBoxScoreFromJson(variant);
    assert.equal(outcome.status, "accepted", spelling);
    assert.equal(outcome.normalizedBoxScore.schemaVersion, 2, spelling);
  }
});

test("an unsupported Node Unicode runtime fails closed", () => {
  const descriptor = Object.getOwnPropertyDescriptor(process.versions, "unicode");
  assert.ok(descriptor?.configurable);
  Object.defineProperty(process.versions, "unicode", {...descriptor, value: "16.0"});
  try {
    assert.throws(() => contract.assertOfficialStatUnicodeRuntime(), TypeError);
    assert.deepEqual(calculator.calculateNormalizedBoxScore(base()), {
      calculatorVersion: calculator.normalizedBoxScoreCalculatorVersion,
      errors: [{code: "invalidCanonicalValue", path: "$"}],
      status: "rejected",
    });
  } finally {
    Object.defineProperty(process.versions, "unicode", descriptor);
  }
});

test("fractional, negative, non-finite, malformed, and oversized raw values fail closed", () => {
  for (const value of [0.5, -1, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    const input = base();
    input.teams[0].players[0].counts.turnovers.value = value;
    const outcome = calculator.calculateNormalizedBoxScore(input);
    assert.equal(outcome.status, "rejected");
    assert.equal(outcome.errors[0].code, "invalidNonnegativeSafeInteger");
  }
  assert.deepEqual(calculator.calculateNormalizedBoxScoreFromJson("{"), {
    calculatorVersion: calculator.normalizedBoxScoreCalculatorVersion,
    errors: [{code: "invalidCanonicalValue", path: "$"}],
    status: "rejected",
  });
  const oversizedRaw = `{"padding":"${"x".repeat(calculator.normalizedBoxScoreLimits.maxRawTransportBytes)}"}`;
  assert.equal(
    calculator.calculateNormalizedBoxScoreFromJson(oversizedRaw).errors[0].code,
    "resourceLimitExceeded",
  );
});

test("preflight bounds depth, width, strings, player count, and canonical bytes", () => {
  const oversizedString = base();
  oversizedString.provenance.sourceLabel = "x".repeat(1025);
  assert.equal(calculator.calculateNormalizedBoxScore(oversizedString).errors[0].code, "resourceLimitExceeded");

  const wide = base();
  wide.probe = Object.fromEntries(Array.from({length: 129}, (_, index) => [`k${index}`, 0]));
  assert.equal(calculator.calculateNormalizedBoxScore(wide).errors[0].code, "resourceLimitExceeded");

  const deep = base();
  let nested = 0;
  for (let index = 0; index < 18; index += 1) nested = [nested];
  deep.probe = nested;
  assert.equal(calculator.calculateNormalizedBoxScore(deep).errors[0].code, "resourceLimitExceeded");

  const canonicalHeavy = base();
  canonicalHeavy.probe = Array.from({length: 1024}, () => "x".repeat(1024));
  assert.equal(calculator.calculateNormalizedBoxScore(canonicalHeavy).errors[0].code, "resourceLimitExceeded");

  const tooManyPlayers = base();
  const prototype = tooManyPlayers.teams[0].players[0];
  tooManyPlayers.teams[0].players = Array.from({length: 65}, (_, index) => ({
    ...clone(prototype),
    participantId: `participant_resource_${index}`,
    playerId: `player_resource_${index}`,
    rosterMembershipId: `membership_resource_${index}`,
    rosterMembershipVersionId: `membership_version_resource_${index}`,
  }));
  assert.equal(calculator.calculateNormalizedBoxScore(tooManyPlayers).errors[0].code, "resourceLimitExceeded");
});

test("accessors are rejected without invocation and first errors ignore insertion order", () => {
  const input = base();
  let accessed = false;
  Object.defineProperty(input.teams, "0", {
    enumerable: true,
    get() {
      accessed = true;
      return null;
    },
  });
  assert.deepEqual(calculator.calculateNormalizedBoxScore(input).errors, [{
    code: "invalidCanonicalValue", path: "$.teams[0]",
  }]);
  assert.equal(accessed, false);

  const invalid = clone(byName("reject_player_79_scoreboard_80_periods_78").input);
  const reverseRecords = (value) => {
    if (Array.isArray(value)) return value.map(reverseRecords);
    if (value && typeof value === "object") {
      return Object.fromEntries(Object.keys(value).reverse().map((key) => [key, reverseRecords(value[key])]));
    }
    return value;
  };
  assert.deepEqual(
    calculator.calculateNormalizedBoxScore(reverseRecords(invalid)),
    calculator.calculateNormalizedBoxScore(invalid),
  );
});

test("preflight consumes one descriptor snapshot despite hostile Proxy behavior", () => {
  const descriptorGraph = base();
  let gets = 0;
  let enumerations = 0;
  const hostile = new Proxy(descriptorGraph, {
    get() {
      gets += 1;
      return Array.from({length: 50000}, () => "x".repeat(1024));
    },
    ownKeys(target) {
      enumerations += 1;
      if (enumerations > 1) return Array.from({length: 50000}, (_, index) => `hostile_${index}`);
      return Reflect.ownKeys(target);
    },
  });
  assert.equal(calculator.calculateNormalizedBoxScore(hostile).status, "accepted");
  assert.equal(gets, 0);
  assert.equal(enumerations, 1);

  const descriptorReads = new Map();
  const descriptorStateful = new Proxy(base(), {
    getOwnPropertyDescriptor(target, key) {
      const reads = (descriptorReads.get(key) ?? 0) + 1;
      descriptorReads.set(key, reads);
      if (reads > 1) {
        return {
          configurable: true,
          enumerable: true,
          value: Array.from({length: 50000}, () => "x".repeat(1024)),
          writable: true,
        };
      }
      return Reflect.getOwnPropertyDescriptor(target, key);
    },
  });
  assert.equal(calculator.calculateNormalizedBoxScore(descriptorStateful).status, "accepted");
  assert.equal(Math.max(...descriptorReads.values()), 1);

  const cyclic = base();
  cyclic.cycle = cyclic;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(cyclic).errors, [{
    code: "invalidCanonicalValue", path: "$.cycle",
  }]);
});

test("a permanent departure constrains cumulative opportunity across prior periods", () => {
  const input = clone(byName("legitimate_double_overtime_50_minutes").input);
  const line = input.teams[0].players[0];
  line.departure = {
    clockRemainingMs: {state: "known", value: 500000},
    evidenceRefs: {state: "known", value: ["departure_period_2"]},
    kind: "ejected",
    periodNumber: {state: "known", value: 2},
  };
  line.time = {
    playedTimeMs: {state: "known", value: 700000},
    roundingMode: "notApplicable",
    timePrecisionMs: {state: "known", value: 1},
    timeSource: "liveClock",
  };
  assert.equal(calculator.calculateNormalizedBoxScore(input).status, "accepted");
  line.time.playedTimeMs.value = 700001;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(input).errors, [{
    code: "departureTimeConflict",
    path: "$.participants.participant_home_1.time",
  }]);
});

test("time feasibility uses nominal, aggregate-capacity, and unknown-clock departure bounds", () => {
  const aggregate = base();
  aggregate.rules.teamTimeCapacityMultiplier.value = 5;
  aggregate.teams[0].players[0].time = exactTime(600000);
  const prototype = clone(aggregate.teams[1].players[0]);
  aggregate.teams[0].players.push(...Array.from({length: 5}, (_, index) => ({
    ...clone(prototype),
    participantId: `participant_capacity_${index}`,
    playerId: `player_capacity_${index}`,
    rosterMembershipId: `membership_capacity_${index}`,
    rosterMembershipVersionId: `membership_version_capacity_${index}`,
    teamEntryId: "team_home",
    time: exactTime(600000),
  })));
  assert.equal(
    calculator.calculateNormalizedBoxScore(aggregate).errors[0].code,
    "timeOutsideGameDuration",
  );

  const nominal = clone(byName("partial_period_keeps_nominal_and_elapsed_separate").input);
  nominal.periods[0].elapsedDurationMs = {state: "unknown", value: null, reasonCode: "not_recorded"};
  nominal.teams[0].players[0].time = exactTime(900000);
  assert.equal(
    calculator.calculateNormalizedBoxScore(nominal).errors[0].code,
    "timeOutsideGameDuration",
  );

  const departure = clone(byName("legitimate_double_overtime_50_minutes").input);
  departure.teams[0].players[0].time = exactTime(3000000);
  departure.teams[0].players[0].departure = {
    clockRemainingMs: {state: "unknown", value: null, reasonCode: "not_recorded"},
    evidenceRefs: {state: "known", value: ["ejection_period_1"]},
    kind: "ejected",
    periodNumber: {state: "known", value: 1},
  };
  assert.equal(
    calculator.calculateNormalizedBoxScore(departure).errors[0].code,
    "departureTimeConflict",
  );
});

test("complete labels cannot fabricate play in an otherwise empty game", () => {
  const input = clone(byName("pregame_default_administrative_only").input);
  input.statisticsDisposition = "complete";
  input.administrativeResult.playerStatisticsTreatment = "includePlayedStatistics";
  const line = input.teams[0].players[0];
  line.participationStatus = "active";
  line.enteredPlay = true;
  line.participationReasonCode = {state: "notApplicable", value: null, reasonCode: "entered_play"};
  line.starter = {state: "known", value: true};
  line.time = clone(byName("stats_only_capture_never_invents_time").input.teams[0].players[0].time);
  assert.equal(
    calculator.calculateNormalizedBoxScore(input).errors[0].code,
    "invalidNoPlayStatistics",
  );
});

test("a zero-elapsed period row cannot conceal no-play counters", () => {
  const input = clone(byName("partial_period_keeps_nominal_and_elapsed_separate").input);
  input.periods[0].elapsedDurationMs = {state: "known", value: 0};
  input.periods[0].homeScore = 0;
  input.periods[0].awayScore = 0;
  input.periods[0].playerCounterPoints = {away: 0, home: 0};
  input.periods[0].exceptionalScoringPoints = {away: 0, home: 0};
  input.playedScore = {away: 0, home: 0};
  input.officialScore.score.value = {away: 0, home: 0};
  for (const team of input.teams) {
    for (const field of calculator.playerCountFields) team.reportedTotals[field].value = 0;
    for (const player of team.players) {
      for (const field of calculator.playerCountFields) player.counts[field].value = 0;
      player.time = exactTime(0);
    }
  }
  input.teams[0].players[0].counts.turnovers.value = 1;
  input.teams[0].reportedTotals.turnovers.value = 1;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(input).errors[0], {
    code: "invalidNoPlayStatistics",
    path: "$.teams",
  });
});

const moveExceptionalCreditToPeriodTwo = (input) => {
  input.rules.regulationPeriodCount = 2;
  input.rules.penaltyAccumulationGroups = [1, 2].map((number) => ({
    groupId: `period_${number}`,
    penaltyStartsAtFoul: {state: "known", value: 5},
    periodNumbers: [number],
  }));
  const scoringPeriod = clone(input.periods[0]);
  scoringPeriod.number = 2;
  input.periods[0].homeScore = 0;
  input.periods[0].playerCounterPoints.home = 0;
  input.periods[0].exceptionalScoringPoints.home = 0;
  input.periods.push(scoringPeriod);
  input.playedScoreAdjustments[0].periodNumber = {state: "known", value: 2};
};

test("exceptional credits require period eligibility for both scoring kinds", () => {
  for (const name of [
    "own_basket_is_credited_and_included_once",
    "defensive_goaltending_credits_shooter_and_counters",
  ]) {
    const later = clone(byName(name).input);
    moveExceptionalCreditToPeriodTwo(later);
    const player = later.teams[0].players[0];
    player.time = exactTime(1000);
    player.departure = {
      clockRemainingMs: {state: "known", value: 599000},
      evidenceRefs: {state: "known", value: ["ejection_period_1"]},
      kind: "ejected",
      periodNumber: {state: "known", value: 1},
    };
    assert.equal(
      calculator.calculateNormalizedBoxScore(later).errors[0].code,
      "invalidScoreAdjustment",
      name,
    );

    const samePeriod = clone(byName(name).input);
    samePeriod.teams[0].players[0].time = exactTime(600000);
    samePeriod.teams[0].players[0].departure = {
      clockRemainingMs: {state: "known", value: 0},
      evidenceRefs: {state: "known", value: ["departure_period_1_end"]},
      kind: "ejected",
      periodNumber: {state: "known", value: 1},
    };
    assert.equal(calculator.calculateNormalizedBoxScore(samePeriod).status, "accepted", name);
  }

  const disqualified = clone(byName("own_basket_is_credited_and_included_once").input);
  moveExceptionalCreditToPeriodTwo(disqualified);
  disqualified.disciplineIncidents = [{
    chargedParticipantId: {state: "known", value: "participant_home_1"},
    chargedPartyKind: "player",
    clockRemainingMs: {state: "known", value: 0},
    context: "onCourt",
    countsTowardPlayerDisqualification: true,
    countsTowardTeamFoul: true,
    evidenceRefs: {state: "known", value: ["disqualification_period_1"]},
    incidentId: "disqualification_period_1",
    incidentType: "disqualifying",
    periodNumber: {state: "known", value: 1},
    relatedParticipantId: {state: "unknown", value: null, reasonCode: "not_recorded"},
    scoresheetCode: "D",
    teamEntryId: "team_home",
  }];
  assert.equal(
    calculator.calculateNormalizedBoxScore(disqualified).errors[0].code,
    "invalidScoreAdjustment",
  );
});

test("score-adjustment shape keeps precedence over unrelated discipline errors", () => {
  const input = clone(byName("own_basket_is_credited_and_included_once").input);
  input.playedScoreAdjustments[0].points = 3;
  input.disciplineIncidents = [{
    chargedParticipantId: {state: "notApplicable", value: null, reasonCode: "not_player_charge"},
    chargedPartyKind: "coach",
    clockRemainingMs: {state: "known", value: 300000},
    context: "onCourt",
    countsTowardPlayerDisqualification: false,
    countsTowardTeamFoul: false,
    evidenceRefs: {state: "known", value: ["invalid_coach_on_court"]},
    incidentId: "invalid_coach_on_court",
    incidentType: "technical",
    periodNumber: {state: "known", value: 1},
    relatedParticipantId: {
      state: "notApplicable", value: null, reasonCode: "no_related_participant",
    },
    scoresheetCode: "C",
    teamEntryId: "team_home",
  }];
  assert.deepEqual(calculator.calculateNormalizedBoxScore(input).errors[0], {
    code: "invalidScoreAdjustment",
    path: "$.playedScoreAdjustments[0].points",
  });
});

test("penalty accumulation resets in regulation and can continue through repeated overtime", () => {
  const input = clone(byName("fiba_reference_groups_q4_and_repeated_overtime").input);
  const template = input.disciplineIncidents[0];
  input.disciplineIncidents = [
    ...Array.from({length: 4}, (_, index) => ({
      ...clone(template), incidentId: `q1_${index}`, periodNumber: {state: "known", value: 1},
    })),
    {...clone(template), incidentId: "q2_1", periodNumber: {state: "known", value: 2}},
  ];
  const outcome = calculator.calculateNormalizedBoxScore(input);
  assert.equal(outcome.status, "accepted");
  const discipline = outcome.normalizedBoxScore.teams[0].discipline;
  assert.equal(discipline.penaltyGroups[0].teamFouls, 4);
  assert.equal(discipline.penaltyGroups[1].teamFouls, 1);
  assert.equal(discipline.penaltyStateByPeriod["2"].groupTeamFoulsThroughPeriod, 1);

  for (const foulCount of [3, 4, 5]) {
    const transition = clone(byName("fiba_reference_groups_q4_and_repeated_overtime").input);
    transition.disciplineIncidents = Array.from({length: foulCount}, (_, index) => ({
      ...clone(transition.disciplineIncidents[0]),
      incidentId: `q4_transition_${foulCount}_${index}`,
      periodNumber: {state: "known", value: 4},
    }));
    const transitionOutcome = calculator.calculateNormalizedBoxScore(transition);
    assert.equal(transitionOutcome.status, "accepted");
    assert.equal(
      transitionOutcome.normalizedBoxScore.teams[0].discipline
        .penaltyStateByPeriod["4"].inPenalty.value,
      foulCount >= 4,
    );
  }

  const overtime = calculator.calculateNormalizedBoxScore(
    byName("fiba_reference_groups_q4_and_repeated_overtime").input,
  );
  assert.equal(overtime.status, "accepted");
  const overtimeDiscipline = overtime.normalizedBoxScore.teams[0].discipline;
  assert.equal(overtimeDiscipline.penaltyGroups[3].teamFouls, 6);
  assert.equal(overtimeDiscipline.penaltyStateByPeriod["4"].inPenalty.value, true);
  assert.equal(overtimeDiscipline.penaltyStateByPeriod["5"].inPenalty.value, true);

  const alternative = clone(byName("alternative_league_resets_each_overtime").input);
  for (const group of alternative.rules.penaltyAccumulationGroups) {
    group.penaltyStartsAtFoul.value = 5;
  }
  const alternativeOutcome = calculator.calculateNormalizedBoxScore(alternative);
  const alternativePenalty = alternativeOutcome.normalizedBoxScore.teams[0].discipline;
  assert.equal(alternativePenalty.penaltyStateByPeriod["4"].inPenalty.value, true);
  assert.equal(alternativePenalty.penaltyStateByPeriod["5"].inPenalty.value, false);
  assert.equal(alternativePenalty.penaltyStateByPeriod["6"].inPenalty.value, false);
});

test("cross-team steals are diagnostic while shot, no-play, and exceptional invariants reject", () => {
  const diagnostic = base();
  diagnostic.teams[0].players[0].counts.steals.value = 1;
  diagnostic.teams[0].reportedTotals.steals.value = 1;
  const accepted = calculator.calculateNormalizedBoxScore(diagnostic);
  assert.equal(accepted.status, "accepted");
  assert.equal(accepted.normalizedBoxScore.diagnostics.length, 1);
  assert.equal(accepted.normalizedBoxScore.diagnostics[0].severity, "evidenceReview");

  for (const name of [
    "reject_three_makes_above_attempts", "reject_dnp_with_assist", "reject_no_play_turnover",
    "reject_wrong_period_exceptional_scoring", "reject_missing_exceptional_credit",
    "reject_wrong_exceptional_team", "reject_additive_exceptional_double_count_policy",
  ]) {
    assert.equal(calculator.calculateNormalizedBoxScore(byName(name).input).status, "rejected", name);
  }
});

test("bounded shooting grid preserves all arithmetic invariants", () => {
  for (let twoAttempted = 0; twoAttempted <= 2; twoAttempted += 1) {
    for (let twoMade = 0; twoMade <= twoAttempted; twoMade += 1) {
      for (let threeAttempted = 0; threeAttempted <= 2; threeAttempted += 1) {
        for (let threeMade = 0; threeMade <= threeAttempted; threeMade += 1) {
          for (let freeAttempted = 0; freeAttempted <= 2; freeAttempted += 1) {
            for (let freeMade = 0; freeMade <= freeAttempted; freeMade += 1) {
              const input = base();
              const values = {freeAttempted, freeMade, threeAttempted, threeMade, twoAttempted, twoMade};
              for (const [field, value] of Object.entries(values)) {
                input.teams[0].players[0].counts[field].value = value;
                input.teams[0].reportedTotals[field].value = value;
              }
              const points = (2 * twoMade) + (3 * threeMade) + freeMade;
              input.rules.completedTiesAllowed = points === 0;
              input.playedScore.home = points;
              input.periods[0].homeScore = points;
              input.periods[0].playerCounterPoints.home = points;
              input.officialScore.score.value.home = points;
              const outcome = calculator.calculateNormalizedBoxScore(input);
              assert.equal(outcome.status, "accepted", JSON.stringify(values));
              assert.equal(outcome.normalizedBoxScore.teams[0].totals.points, points);
            }
          }
        }
      }
    }
  }
});
