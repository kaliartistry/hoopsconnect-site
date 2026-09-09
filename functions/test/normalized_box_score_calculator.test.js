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

test("calculator vocabulary and immutable versions are unique and fixture-bound", () => {
  assert.equal(fixture.calculatorVersion, calculator.normalizedBoxScoreCalculatorVersion);
  assert.equal(fixture.unicodeNormalizationVersion, calculator.normalizedBoxScoreUnicodeVersion);
  assert.equal(fixture.canonicalEncodingVersion, contract.officialStatVersions.canonicalEncodingVersion);
  assert.equal(new Set(calculator.playerCountFields).size, calculator.playerCountFields.length);
  assert.equal(new Set(calculator.calculatorErrorCodes).size, calculator.calculatorErrorCodes.length);
  assert.doesNotThrow(() => calculator.assertCalculatorErrorVocabulary());
});

test("Node consumes every shared fixture and matches exact normalized bytes and SHA-256", () => {
  for (const entry of fixture.cases) {
    const before = contract.canonicalEncode(entry.input);
    const outcome = calculator.calculateNormalizedBoxScore(entry.input);
    const canonical = contract.canonicalEncode(outcome);
    assert.equal(canonical, entry.expectedCanonical, entry.name);
    assert.equal(Buffer.byteLength(canonical, "utf8"), entry.expectedCanonicalByteLength, entry.name);
    assert.equal(contract.canonicalSha256(outcome), entry.expectedSha256, entry.name);
    assert.equal(contract.canonicalEncode(entry.input), before, `${entry.name} mutated its input`);
  }
});

test("required counterexamples reject with stable path-aware codes", () => {
  for (const [value, code, pathSuffix] of [
    [0.5, "invalidNonnegativeSafeInteger", ".turnovers.value"],
    [Number.NaN, "invalidNonnegativeSafeInteger", ".turnovers.value"],
    [Number.POSITIVE_INFINITY, "invalidNonnegativeSafeInteger", ".turnovers.value"],
    [Number.NEGATIVE_INFINITY, "invalidNonnegativeSafeInteger", ".turnovers.value"],
  ]) {
    const input = base();
    input.teams[0].players[0].counts.turnovers.value = value;
    const outcome = calculator.calculateNormalizedBoxScore(input);
    assert.equal(outcome.status, "rejected");
    assert.equal(outcome.errors[0].code, code);
    assert.ok(outcome.errors[0].path.endsWith(pathSuffix));
  }

  const negativeTime = base();
  negativeTime.teams[0].players[0].time.playedTimeMs.value = -1;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(negativeTime).errors, [{
    code: "invalidNonnegativeSafeInteger",
    path: "$.teams[0].players[0].time.playedTimeMs.value",
  }]);
});

test("rounded sheet time is an interval and missing time stays unknown", () => {
  const rounded = calculator.calculateNormalizedBoxScore(base());
  assert.equal(rounded.status, "accepted");
  assert.deepEqual(
    rounded.normalizedBoxScore.teams[0].players[0].time.possibleIntervalMs,
    {state: "known", value: {lowerInclusive: 570000, upperExclusive: 630000}},
  );

  const missing = calculator.calculateNormalizedBoxScore(
    byName("stats_only_capture_never_invents_time").input,
  );
  assert.equal(missing.status, "accepted");
  for (const team of missing.normalizedBoxScore.teams) {
    assert.equal(team.players[0].time.playedTimeMs.state, "unknown");
    assert.equal(team.players[0].time.possibleIntervalMs.state, "unknown");
  }
});

test("double overtime, DNP bench discipline, and administrative results stay separate", () => {
  const overtime = calculator.calculateNormalizedBoxScore(
    byName("legitimate_double_overtime_50_minutes").input,
  );
  assert.equal(overtime.status, "accepted");
  assert.equal(overtime.normalizedBoxScore.periods.length, 6);
  assert.equal(overtime.normalizedBoxScore.periods[5].overtimeIndex.value, 2);
  assert.equal(overtime.normalizedBoxScore.teams[0].players[0].time.playedTimeMs.value, 3000000);

  const bench = calculator.calculateNormalizedBoxScore(
    byName("dnp_bench_technical_preserves_discipline_without_gp").input,
  );
  assert.equal(bench.status, "accepted");
  const dnp = bench.normalizedBoxScore.teams[0].players.find(
    (line) => line.participantId === "participant_home_dnp",
  );
  assert.equal(dnp.gamesPlayed, 0);
  assert.deepEqual(dnp.discipline.relatedIncidentIds, ["incident_bench_1"]);
  assert.equal(bench.normalizedBoxScore.teams[0].discipline.byParty.bench, 1);
  assert.equal(bench.normalizedBoxScore.teams[0].discipline.chargedFouls, 1);

  const adjudicated = calculator.calculateNormalizedBoxScore(
    byName("played_score_separate_from_administrative_result").input,
  );
  assert.equal(adjudicated.status, "accepted");
  assert.deepEqual(adjudicated.normalizedBoxScore.playedScore, {away: 0, home: 2});
  assert.deepEqual(
    adjudicated.normalizedBoxScore.administrativeResult.awardedScore.value,
    {away: 20, home: 0},
  );

  const pregameDefault = calculator.calculateNormalizedBoxScore(
    byName("pregame_default_allows_zero_played_periods").input,
  );
  assert.equal(pregameDefault.status, "accepted");
  assert.deepEqual(pregameDefault.normalizedBoxScore.periods, []);
  assert.deepEqual(pregameDefault.normalizedBoxScore.playedScore, {away: 0, home: 0});
  for (const team of pregameDefault.normalizedBoxScore.teams) {
    assert.equal(team.players[0].gamesPlayed, 0);
  }
});

test("zero attempts are undefined fractions and cross-team checks are diagnostics", () => {
  const input = base();
  input.teams[0].players[0].counts.steals.value = 1;
  input.teams[0].reportedTotals.steals.value = 1;
  const outcome = calculator.calculateNormalizedBoxScore(input);
  assert.equal(outcome.status, "accepted");
  assert.deepEqual(
    outcome.normalizedBoxScore.teams[1].shootingPercentages.field,
    {reasonCode: "zero_attempts", state: "unknown", value: null},
  );
  assert.equal(outcome.normalizedBoxScore.diagnostics.length, 1);
  assert.equal(outcome.normalizedBoxScore.diagnostics[0].severity, "evidenceReview");
});

test("team-only values, missed shots, departures, and foul subtypes remain explicit", () => {
  const zeroIncidents = calculator.calculateNormalizedBoxScore(base());
  assert.equal(zeroIncidents.status, "accepted");
  assert.equal(zeroIncidents.normalizedBoxScore.disciplineIncidents.length, 0);
  assert.equal(zeroIncidents.normalizedBoxScore.teams[0].totals.twoAttempted, 2);
  assert.equal(zeroIncidents.normalizedBoxScore.teams[0].totals.totalRebounds, 0);

  const teamOnly = calculator.calculateNormalizedBoxScore(
    byName("team_only_rebounds_and_turnovers_are_separate").input,
  );
  assert.equal(teamOnly.status, "accepted");
  assert.deepEqual(teamOnly.normalizedBoxScore.teams[0].teamOnly, {
    defensiveRebounds: 3,
    offensiveRebounds: 2,
    turnovers: 4,
  });
  assert.equal(teamOnly.normalizedBoxScore.teams[0].totals.totalRebounds, 8);
  assert.equal(teamOnly.normalizedBoxScore.teams[0].totals.turnovers, 5);

  const discipline = calculator.calculateNormalizedBoxScore(
    byName("departure_vocabulary_and_typed_discipline").input,
  );
  assert.equal(discipline.status, "accepted");
  const home = discipline.normalizedBoxScore.teams[0];
  assert.deepEqual(
    home.players.slice(1).map((line) => line.departure.kind),
    ["fouledOut", "ejected", "injured", "other"],
  );
  assert.deepEqual(home.discipline.byParty, {bench: 0, coach: 1, player: 1, team: 1});
  assert.deepEqual(home.discipline.byType, {
    disqualifying: 0,
    personal: 0,
    technical: 2,
    unsportsmanlike: 1,
  });
  assert.equal(home.discipline.chargedFouls, 3);
  assert.equal(home.players[1].discipline.chargedFouls, 1);
  assert.equal(home.players[1].discipline.byType.personal, 0);
  assert.deepEqual(home.discipline.penaltyStateByPeriod["1"], {
    state: "known",
    value: {inPenalty: false, teamFouls: 1, threshold: 5},
  });
});

test("resource bounds and unsupported normalization fail closed", () => {
  const longString = base();
  longString.provenance.sourceLabel = "x".repeat(1025);
  assert.equal(
    calculator.calculateNormalizedBoxScore(longString).errors[0].code,
    "resourceLimitExceeded",
  );

  const tooManyPlayers = base();
  const prototype = tooManyPlayers.teams[0].players[0];
  tooManyPlayers.teams[0].players = Array.from({length: 65}, (_, index) => ({
    ...clone(prototype),
    participantId: `participant_resource_${index}`,
    playerId: `player_resource_${index}`,
    rosterMembershipId: `membership_resource_${index}`,
    rosterMembershipVersionId: `membership_version_resource_${index}`,
  }));
  assert.equal(
    calculator.calculateNormalizedBoxScore(tooManyPlayers).errors[0].code,
    "resourceLimitExceeded",
  );

  const wrongUnicode = base();
  wrongUnicode.unicodeNormalizationVersion = "unicode-runtime-default";
  assert.deepEqual(calculator.calculateNormalizedBoxScore(wrongUnicode).errors, [{
    code: "unsupportedUnicodeNormalizationVersion",
    path: "$.unicodeNormalizationVersion",
  }]);

  const impossibleTime = base();
  impossibleTime.teams[0].players[0].time.playedTimeMs.value = 1200000;
  assert.equal(
    calculator.calculateNormalizedBoxScore(impossibleTime).errors[0].code,
    "timeOutsideGameDuration",
  );

  const oversizedKey = base();
  oversizedKey["x".repeat(1025)] = true;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(oversizedKey).errors, [{
    code: "resourceLimitExceeded",
    path: "$",
  }]);
});

test("scope, participation, evidence, and adjudication invariants fail closed", () => {
  const missingScope = base();
  delete missingScope.scope.seasonId;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(missingScope).errors, [{
    code: "invalidShape",
    path: "$.scope",
  }]);

  const invalidParticipation = base();
  invalidParticipation.teams[0].players[0].participationReasonCode = {
    state: "known",
    value: "coach_decision",
  };
  assert.equal(
    calculator.calculateNormalizedBoxScore(invalidParticipation).errors[0].code,
    "invalidParticipation",
  );

  const invalidAdjustment = clone(byName("explicit_own_basket_not_balance_score").input);
  invalidAdjustment.playedScoreAdjustments[0].points = 3;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(invalidAdjustment).errors, [{
    code: "invalidScoreAdjustment",
    path: "$.playedScoreAdjustments[0].points",
  }]);

  const missingFoulPeriod = clone(byName("departure_vocabulary_and_typed_discipline").input);
  missingFoulPeriod.disciplineIncidents[0].periodNumber = {
    reasonCode: "not_recorded",
    state: "unknown",
    value: null,
  };
  missingFoulPeriod.disciplineIncidents[0].clockRemainingMs = {
    reasonCode: "not_recorded",
    state: "unknown",
    value: null,
  };
  assert.deepEqual(calculator.calculateNormalizedBoxScore(missingFoulPeriod).errors, [{
    code: "invalidDisciplineIncident",
    path: "$.disciplineIncidents[0].periodNumber",
  }]);

  const wrongAwardedWinner = clone(
    byName("played_score_separate_from_administrative_result").input,
  );
  wrongAwardedWinner.administrativeResult.winnerTeamEntryId = {
    state: "known",
    value: "team_home",
  };
  assert.deepEqual(calculator.calculateNormalizedBoxScore(wrongAwardedWinner).errors, [{
    code: "invalidAdministrativeResult",
    path: "$.administrativeResult.winnerTeamEntryId",
  }]);

  const incompletePlayedGame = base();
  incompletePlayedGame.rules.regulationPeriodCount = 4;
  assert.deepEqual(calculator.calculateNormalizedBoxScore(incompletePlayedGame).errors, [{
    code: "invalidPeriodSequence",
    path: "$.periods",
  }]);

  const emptyRoster = base();
  emptyRoster.teams[0].players = [];
  assert.deepEqual(calculator.calculateNormalizedBoxScore(emptyRoster).errors, [{
    code: "invalidTeamStructure",
    path: "$.teams[0].players",
  }]);
});

test("all retained human text and reason codes normalize to NFC", () => {
  const input = base();
  input.rules.teamFoulPenaltyThresholds.overtime = {
    reasonCode: "Cafe\u0301",
    state: "unknown",
    value: null,
  };
  const outcome = calculator.calculateNormalizedBoxScore(input);
  assert.equal(outcome.status, "accepted");
  assert.equal(
    outcome.normalizedBoxScore.rules.teamFoulPenaltyThresholds.overtime.reasonCode,
    "Café",
  );
});

test("bounded shooting grid preserves every arithmetic invariant", () => {
  for (let twoAttempted = 0; twoAttempted <= 2; twoAttempted += 1) {
    for (let twoMade = 0; twoMade <= twoAttempted; twoMade += 1) {
      for (let threeAttempted = 0; threeAttempted <= 2; threeAttempted += 1) {
        for (let threeMade = 0; threeMade <= threeAttempted; threeMade += 1) {
          for (let freeAttempted = 0; freeAttempted <= 2; freeAttempted += 1) {
            for (let freeMade = 0; freeMade <= freeAttempted; freeMade += 1) {
              const input = base();
              const values = {
                freeAttempted,
                freeMade,
                threeAttempted,
                threeMade,
                twoAttempted,
                twoMade,
              };
              for (const [field, value] of Object.entries(values)) {
                input.teams[0].players[0].counts[field].value = value;
                input.teams[0].reportedTotals[field].value = value;
              }
              const points = (2 * twoMade) + (3 * threeMade) + freeMade;
              input.rules.completedTiesAllowed = points === 0;
              input.playedScore.home = points;
              input.periods[0].homeScore = points;
              input.officialScore.score.value.home = points;

              const outcome = calculator.calculateNormalizedBoxScore(input);
              assert.equal(outcome.status, "accepted", JSON.stringify(values));
              const totals = outcome.normalizedBoxScore.teams[0].totals;
              assert.equal(totals.fieldMade, twoMade + threeMade);
              assert.equal(totals.fieldAttempted, twoAttempted + threeAttempted);
              assert.equal(totals.points, points);
            }
          }
        }
      }
    }
  }
});

test("array accessors are rejected before calculator traversal", () => {
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
    code: "invalidCanonicalValue",
    path: "$.teams[0]",
  }]);
  assert.equal(accessed, false);
});

test("first-error output is deterministic across object insertion order", () => {
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
