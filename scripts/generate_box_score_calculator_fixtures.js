#!/usr/bin/env node

/*
 * Deliberate Packet 06 golden-fixture generator.
 *
 * The checked-in JSON is normative and tests never regenerate it. Every case
 * carries independently declared semantic expectations which are asserted
 * before exact canonical bytes and hashes are emitted. The calculator is thus
 * not accepted as its own basketball-semantics oracle.
 */
const assert = require("node:assert/strict");
const calculator = require("../functions/lib/domain/stats/calculator.js");
const contract = require("../functions/lib/domain/official_stats_contract.js");

const known = (value) => ({state: "known", value});
const unknown = (reasonCode) => ({reasonCode, state: "unknown", value: null});
const na = (reasonCode) => ({reasonCode, state: "notApplicable", value: null});
const clone = (value) => structuredClone(value);

const counterNames = calculator.playerCountFields;
const counts = (changes = {}) => Object.fromEntries(
  counterNames.map((name) => [name, known(changes[name] ?? 0)]),
);
const noDeparture = () => ({
  clockRemainingMs: na("no_departure"),
  evidenceRefs: na("no_departure"),
  kind: "none",
  periodNumber: na("no_departure"),
});
const roundedTime = (playedTimeMs = 600000, mode = "nearestHalfUp") => ({
  playedTimeMs: known(playedTimeMs),
  roundingMode: mode,
  timePrecisionMs: known(60000),
  timeSource: "officialSheetRounded",
});
const exactTime = (playedTimeMs) => ({
  playedTimeMs: known(playedTimeMs),
  roundingMode: "notApplicable",
  timePrecisionMs: known(1),
  timeSource: "liveClock",
});
const noRecordedTime = () => ({
  playedTimeMs: unknown("not_recorded"),
  roundingMode: "notApplicable",
  timePrecisionMs: na("no_time_source"),
  timeSource: "notRecorded",
});
const noParticipationTime = () => ({
  playedTimeMs: na("did_not_enter"),
  roundingMode: "notApplicable",
  timePrecisionMs: na("did_not_enter"),
  timeSource: "notApplicable",
});
const player = ({
  participantId,
  playerId,
  teamEntryId,
  countChanges = {},
  participationStatus = "active",
  enteredPlay = true,
  participationReasonCode = enteredPlay ? na("entered_play") : unknown("not_recorded"),
  time = roundedTime(),
}) => ({
  counts: counts(countChanges),
  departure: noDeparture(),
  enteredPlay,
  participantId,
  participationReasonCode,
  participationStatus,
  playerId,
  rosterMembershipId: `membership_${playerId}`,
  rosterMembershipVersionId: `membership_version_${playerId}`,
  starter: known(enteredPlay),
  teamEntryId,
  time,
});
const team = ({side, teamEntryId, players}) => ({
  players,
  reportedTotals: counts(),
  side,
  teamEntryId,
  teamOnly: {
    defensiveRebounds: known(0),
    offensiveRebounds: known(0),
    turnovers: known(0),
  },
});
const syncTeam = (value) => {
  const totals = Object.fromEntries(counterNames.map((name) => [name, 0]));
  for (const line of value.players) {
    for (const name of counterNames) totals[name] += line.counts[name].value;
  }
  totals.offensiveRebounds += value.teamOnly.offensiveRebounds.value;
  totals.defensiveRebounds += value.teamOnly.defensiveRebounds.value;
  totals.turnovers += value.teamOnly.turnovers.value;
  value.reportedTotals = counts(totals);
};
const setPlayerCounts = (input, teamIndex, playerIndex, changes) => {
  input.teams[teamIndex].players[playerIndex].counts = counts(changes);
  syncTeam(input.teams[teamIndex]);
};
const playedAdministration = () => ({
  awardedScore: na("not_adjudicated"),
  evidenceRefs: na("not_adjudicated"),
  playerStatisticsTreatment: "includePlayedStatistics",
  standingsTreatment: "playedResult",
  winnerTeamEntryId: na("not_adjudicated"),
});
const officialScore = (home, away) => ({
  evidenceRefs: known(["official_sheet_page_1"]),
  reconciliationStatus: "reconciled",
  score: known({away, home}),
});
const regulationPeriod = (
  number,
  homeScore,
  awayScore,
  {completionState = "completed", elapsedDurationMs = 600000,
    exceptionalHome = 0, exceptionalAway = 0} = {},
) => ({
  awayScore,
  completionState,
  elapsedDurationMs: elapsedDurationMs === null ? unknown("not_recorded") : known(elapsedDurationMs),
  exceptionalScoringPoints: {away: exceptionalAway, home: exceptionalHome},
  homeScore,
  kind: "regulation",
  nominalDurationMs: known(600000),
  number,
  overtimeIndex: na("regulation_period"),
  playerCounterPoints: {away: awayScore, home: homeScore},
  source: "officialSheet",
});
const overtimePeriod = (number, overtimeIndex, homeScore, awayScore) => ({
  awayScore,
  completionState: "completed",
  elapsedDurationMs: known(300000),
  exceptionalScoringPoints: {away: 0, home: 0},
  homeScore,
  kind: "overtime",
  nominalDurationMs: known(300000),
  number,
  overtimeIndex: known(overtimeIndex),
  playerCounterPoints: {away: awayScore, home: homeScore},
  source: "officialSheet",
});
const group = (groupId, periodNumbers, threshold = known(5)) => ({
  groupId,
  penaltyStartsAtFoul: threshold,
  periodNumbers,
});
const resetGroups = (count, threshold = known(5)) =>
  Array.from({length: count}, (_, index) => group(`period_${index + 1}`, [index + 1], threshold));
const fibaGroups = (count) => count === 0 ? [] : [
  group("fiba_period_1", [1]),
  ...(count >= 2 ? [group("fiba_period_2", [2])] : []),
  ...(count >= 3 ? [group("fiba_period_3", [3])] : []),
  ...(count >= 4 ? [group("fiba_fourth_and_overtimes",
    Array.from({length: count - 3}, (_, index) => index + 4))] : []),
];
const genericRules = (periodCount = 1) => ({
  completedTiesAllowed: false,
  exceptionalScoringProfile: "fiba-2024-reference-attribution-v1",
  overtimePolicy: {allowed: true, nominalDurationMs: known(300000)},
  penaltyAccumulationGroups: resetGroups(periodCount),
  playingTimeRoundingProfile: "nearest-half-up-v1",
  regulationPeriodCount: Math.min(periodCount, 4),
  rulesProfileId: "generic-explicit-v2",
  teamTimeCapacityMultiplier: known(1),
});
const fibaRules = (periodCount) => ({
  completedTiesAllowed: false,
  exceptionalScoringProfile: "fiba-2024-reference-attribution-v1",
  overtimePolicy: {allowed: true, nominalDurationMs: known(300000)},
  penaltyAccumulationGroups: fibaGroups(periodCount),
  playingTimeRoundingProfile: "fiba-2024-reference-sheet-v1",
  regulationPeriodCount: 4,
  rulesProfileId: "fiba-2024-reference-v1",
  teamTimeCapacityMultiplier: known(5),
});
const incident = ({
  incidentId,
  teamEntryId = "team_home",
  participantId = "participant_home_1",
  periodNumber = 1,
  context = "onCourt",
  type = "personal",
  countsTowardTeamFoul = true,
}) => ({
  chargedParticipantId: context === "onCourt" ? known(participantId) : na("not_player_charge"),
  chargedPartyKind: context === "onCourt" ? "player" : "bench",
  clockRemainingMs: context === "preGame" ?
    na("no_play_context") : context === "onCourt" ? known(300000) : na("interval_or_bench_context"),
  context,
  countsTowardPlayerDisqualification: false,
  countsTowardTeamFoul,
  evidenceRefs: known([`evidence_${incidentId}`]),
  incidentId,
  incidentType: type,
  periodNumber: context === "preGame" ? na("no_play_context") : known(periodNumber),
  relatedParticipantId: na("no_related_participant"),
  scoresheetCode: type === "personal" ? "P" : "T",
  teamEntryId,
});

const base = {
  administrativeResult: playedAdministration(),
  calculatorVersion: calculator.normalizedBoxScoreCalculatorVersion,
  canonicalEncodingVersion: contract.officialStatVersions.canonicalEncodingVersion,
  disciplineIncidents: [],
  officialScore: officialScore(2, 0),
  periods: [regulationPeriod(1, 2, 0)],
  playedScore: {away: 0, home: 2},
  playedScoreAdjustments: [],
  provenance: {
    captureMode: "officialSheet",
    rulesetVersion: "rules_fixture_1",
    sourceId: "source_fixture_1",
    sourceLabel: "Cafe\u0301 official sheet",
  },
  resultDisposition: "played",
  rules: genericRules(1),
  schemaVersion: 2,
  scope: {
    associationId: "association_fixture_1",
    competitionId: "competition_fixture_1",
    divisionId: "division_fixture_1",
    gameId: "game_fixture_1",
    phaseId: "phase_fixture_1",
    seasonId: "season_fixture_1",
  },
  statisticsDisposition: "complete",
  teams: [
    team({
      side: "home",
      teamEntryId: "team_home",
      players: [player({
        participantId: "participant_home_1",
        playerId: "player_home_1",
        teamEntryId: "team_home",
        countChanges: {twoMade: 1, twoAttempted: 2},
      })],
    }),
    team({
      side: "away",
      teamEntryId: "team_away",
      players: [player({
        participantId: "participant_away_1",
        playerId: "player_away_1",
        teamEntryId: "team_away",
      })],
    }),
  ],
  unicodeNormalizationVersion: calculator.normalizedBoxScoreUnicodeVersion,
};
syncTeam(base.teams[0]);
syncTeam(base.teams[1]);

const pathValue = (value, dottedPath) => dottedPath.split(".").reduce(
  (current, key) => current[Number.isInteger(Number(key)) ? Number(key) : key],
  value,
);
const cases = [];
const add = (name, input, expectedSemantics) => cases.push({name, input, expectedSemantics});
const accepted = (...checks) => ({checks, status: "accepted"});
const rejected = (code, path) => ({error: {code, path}, status: "rejected"});

add("complete_zero_disciplinary_incidents", clone(base), accepted(
  {path: "normalizedBoxScore.teams.0.totals.points", value: 2},
  {path: "normalizedBoxScore.teams.0.totals.twoAttempted", value: 2},
  {path: "normalizedBoxScore.teams.0.totals.totalRebounds", value: 0},
  {path: "normalizedBoxScore.disciplineIncidents.length", value: 0},
));

{
  const input = clone(base);
  input.scope.gameId = "game_team_only_counts";
  input.teams[0].players[0].counts.offensiveRebounds = known(1);
  input.teams[0].players[0].counts.defensiveRebounds = known(2);
  input.teams[0].players[0].counts.turnovers = known(1);
  input.teams[0].teamOnly = {
    defensiveRebounds: known(3), offensiveRebounds: known(2), turnovers: known(4),
  };
  syncTeam(input.teams[0]);
  add("team_only_rebounds_and_turnovers_are_separate", input, accepted(
    {path: "normalizedBoxScore.teams.0.totals.totalRebounds", value: 8},
    {path: "normalizedBoxScore.teams.0.totals.turnovers", value: 5},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_departures_and_discipline";
  const additions = [
    ["fouled_out", "fouledOut", known(1), known(100000)],
    ["ejected", "ejected", unknown("not_recorded"), unknown("not_recorded")],
    ["injured", "injured", known(1), unknown("not_recorded")],
    ["other", "other", unknown("not_recorded"), unknown("not_recorded")],
  ].map(([suffix, kind, periodNumber, clockRemainingMs]) => {
    const line = player({
      participantId: `participant_home_${suffix}`,
      playerId: `player_home_${suffix}`,
      teamEntryId: "team_home",
      time: exactTime(100000),
    });
    line.departure = {
      clockRemainingMs,
      evidenceRefs: known([`departure_evidence_${suffix}`]),
      kind,
      periodNumber,
    };
    return line;
  });
  input.teams[0].players.push(...additions);
  syncTeam(input.teams[0]);
  const playerIncident = incident({
    incidentId: "incident_unsportsmanlike_1",
    participantId: "participant_home_fouled_out",
    type: "unsportsmanlike",
  });
  playerIncident.clockRemainingMs = known(100000);
  playerIncident.countsTowardPlayerDisqualification = true;
  playerIncident.scoresheetCode = "U";
  const coachIncident = incident({
    incidentId: "incident_coach_1", context: "bench", type: "technical",
    countsTowardTeamFoul: false,
  });
  coachIncident.chargedPartyKind = "coach";
  coachIncident.scoresheetCode = "C";
  const teamIncident = incident({
    incidentId: "incident_team_1", context: "interval", type: "technical",
    countsTowardTeamFoul: false,
  });
  teamIncident.chargedPartyKind = "team";
  teamIncident.scoresheetCode = "T";
  input.disciplineIncidents = [playerIncident, coachIncident, teamIncident];
  add("departure_vocabulary_and_typed_discipline", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.1.departure.kind", value: "fouledOut"},
    {path: "normalizedBoxScore.teams.0.players.2.departure.kind", value: "ejected"},
    {path: "normalizedBoxScore.teams.0.players.3.departure.kind", value: "injured"},
    {path: "normalizedBoxScore.teams.0.players.4.departure.kind", value: "other"},
    {path: "normalizedBoxScore.teams.0.discipline.byParty.coach", value: 1},
    {path: "normalizedBoxScore.teams.0.discipline.byParty.team", value: 1},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_double_overtime";
  input.rules = genericRules(6);
  input.rules.regulationPeriodCount = 4;
  input.periods = [
    regulationPeriod(1, 2, 2), regulationPeriod(2, 2, 2),
    regulationPeriod(3, 2, 2), regulationPeriod(4, 2, 2),
    overtimePeriod(5, 1, 2, 2), overtimePeriod(6, 2, 2, 0),
  ];
  input.playedScore = {away: 10, home: 12};
  input.officialScore = officialScore(12, 10);
  setPlayerCounts(input, 0, 0, {twoMade: 6, twoAttempted: 6});
  setPlayerCounts(input, 1, 0, {twoMade: 5, twoAttempted: 5});
  input.teams[0].players[0].time = exactTime(3000000);
  input.teams[1].players[0].time = exactTime(3000000);
  add("legitimate_double_overtime_50_minutes", input, accepted(
    {path: "normalizedBoxScore.periods.length", value: 6},
    {path: "normalizedBoxScore.totalElapsedPlayMs.value", value: 3000000},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_forfeit_after_play";
  input.resultDisposition = "forfeit";
  input.administrativeResult = {
    awardedScore: known({away: 20, home: 0}),
    evidenceRefs: known(["adjudication_decision_1"]),
    playerStatisticsTreatment: "includePlayedStatistics",
    standingsTreatment: "awardedResult",
    winnerTeamEntryId: known("team_away"),
  };
  add("played_score_separate_from_administrative_result", input, accepted(
    {path: "normalizedBoxScore.playedScore.home", value: 2},
    {path: "normalizedBoxScore.administrativeResult.awardedScore.value.away", value: 20},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_no_time_source";
  input.teams[0].players[0].time = noRecordedTime();
  input.teams[1].players[0].time = noRecordedTime();
  add("stats_only_capture_never_invents_time", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.state", value: "unknown"},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_dnp_assist";
  input.teams[0].players.push(player({
    participantId: "participant_home_dnp_assist",
    playerId: "player_home_dnp_assist",
    teamEntryId: "team_home",
    participationStatus: "dnp",
    enteredPlay: false,
    time: noParticipationTime(),
    countChanges: {assists: 1},
  }));
  syncTeam(input.teams[0]);
  add("reject_dnp_with_assist", input, rejected(
    "dnpOrdinaryStat", "$.teams[0].players[1].counts",
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_dnp_bench_technical";
  input.teams[0].players.push(player({
    participantId: "participant_home_dnp",
    playerId: "player_home_dnp",
    teamEntryId: "team_home",
    participationStatus: "dnp",
    enteredPlay: false,
    time: noParticipationTime(),
  }));
  syncTeam(input.teams[0]);
  const bench = incident({incidentId: "incident_bench_1", context: "bench", type: "technical",
    countsTowardTeamFoul: false});
  bench.relatedParticipantId = known("participant_home_dnp");
  input.disciplineIncidents = [bench];
  add("dnp_bench_technical_preserves_discipline_without_gp", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.1.gamesPlayed", value: 0},
    {path: "normalizedBoxScore.teams.0.discipline.byParty.bench", value: 1},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_dnp_player_foul";
  input.teams[0].players.push(player({
    participantId: "participant_home_dnp", playerId: "player_home_dnp",
    teamEntryId: "team_home", participationStatus: "dnp", enteredPlay: false,
    time: noParticipationTime(),
  }));
  syncTeam(input.teams[0]);
  input.disciplineIncidents = [incident({
    incidentId: "incident_dnp_personal", participantId: "participant_home_dnp",
  })];
  add("reject_never_entered_player_on_court_foul", input, rejected(
    "playerNotEnteredForIncident", "$.disciplineIncidents[0].chargedParticipantId",
  ));
}

const noPlayDefault = () => {
  const input = clone(base);
  input.scope.gameId = "game_pregame_default";
  input.resultDisposition = "default";
  input.statisticsDisposition = "excluded";
  input.rules.regulationPeriodCount = 4;
  input.rules.penaltyAccumulationGroups = [];
  input.periods = [];
  input.playedScore = {away: 0, home: 0};
  input.officialScore = officialScore(0, 0);
  for (const teamValue of input.teams) {
    for (const line of teamValue.players) {
      line.participationStatus = "dnp";
      line.enteredPlay = false;
      line.participationReasonCode = unknown("not_recorded");
      line.starter = known(false);
      line.time = noParticipationTime();
      line.counts = counts();
      line.departure = noDeparture();
    }
    teamValue.teamOnly = {
      defensiveRebounds: known(0), offensiveRebounds: known(0), turnovers: known(0),
    };
    syncTeam(teamValue);
  }
  input.administrativeResult = {
    awardedScore: known({away: 0, home: 20}),
    evidenceRefs: known(["adjudication_default_1"]),
    playerStatisticsTreatment: "exclude",
    standingsTreatment: "awardedResult",
    winnerTeamEntryId: known("team_home"),
  };
  return input;
};

add("pregame_default_administrative_only", noPlayDefault(), accepted(
  {path: "normalizedBoxScore.periods.length", value: 0},
  {path: "normalizedBoxScore.statisticsDisposition", value: "excluded"},
));

{
  const input = noPlayDefault();
  input.scope.gameId = "game_pregame_discipline";
  input.disciplineIncidents = [incident({
    incidentId: "pregame_bench_technical", context: "preGame", type: "technical",
    countsTowardTeamFoul: false,
  })];
  add("pregame_default_allows_evidenced_bench_discipline", input, accepted(
    {path: "normalizedBoxScore.teams.0.discipline.byParty.bench", value: 1},
  ));
}

for (const [name, mutate, error] of [
  ["reject_entered_participant_in_no_play", (input) => {
    const line = input.teams[0].players[0];
    line.participationStatus = "active";
    line.enteredPlay = true;
    line.participationReasonCode = na("entered_play");
    line.starter = known(true);
    line.time = noRecordedTime();
  }, ["invalidNoPlayStatistics", "$.participants.participant_home_1.enteredPlay"]],
  ["reject_no_play_turnover", (input) => {
    input.teams[0].players[0].counts.turnovers = known(1);
    syncTeam(input.teams[0]);
  }, ["dnpOrdinaryStat", "$.teams[0].players[0].counts"]],
  ["reject_no_play_shot", (input) => {
    input.teams[0].players[0].counts.twoMade = known(1);
    input.teams[0].players[0].counts.twoAttempted = known(1);
    syncTeam(input.teams[0]);
  }, ["dnpOrdinaryStat", "$.teams[0].players[0].counts"]],
  ["reject_no_play_fabricated_time", (input) => {
    input.teams[0].players[0].time = exactTime(1000);
  }, ["invalidTimeProvenance", "$.teams[0].players[0].time"]],
]) {
  const input = noPlayDefault();
  input.scope.gameId = name;
  mutate(input);
  add(name, input, rejected(error[0], error[1]));
}

{
  const input = clone(base);
  input.scope.gameId = "game_own_basket";
  setPlayerCounts(input, 0, 0, {twoMade: 1, twoAttempted: 1});
  input.periods[0].exceptionalScoringPoints.home = 2;
  input.playedScoreAdjustments = [{
    adjustmentId: "adjustment_own_basket_1",
    creditedParticipantId: known("participant_home_1"),
    creditedShot: "twoPointMade",
    evidenceRefs: known(["play_evidence_own_basket_1"]),
    kind: "accidentalOwnBasket",
    periodNumber: known(1),
    points: 2,
    statisticalTreatment: "includedInPlayerCounters",
    teamEntryId: "team_home",
    violatingTeamEntryId: "team_away",
  }];
  add("own_basket_is_credited_and_included_once", input, accepted(
    {path: "normalizedBoxScore.playedScoreAdjustments.0.requiredCounterChanges.twoMade", value: 1},
    {path: "normalizedBoxScore.teams.0.totals.points", value: 2},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_defensive_goaltending";
  setPlayerCounts(input, 0, 0, {threeMade: 1, threeAttempted: 1});
  input.periods[0].homeScore = 3;
  input.periods[0].playerCounterPoints.home = 3;
  input.periods[0].exceptionalScoringPoints.home = 3;
  input.playedScore.home = 3;
  input.officialScore = officialScore(3, 0);
  input.playedScoreAdjustments = [{
    adjustmentId: "adjustment_goaltending_1",
    creditedParticipantId: known("participant_home_1"),
    creditedShot: "threePointMade",
    evidenceRefs: known(["play_evidence_goaltending_1"]),
    kind: "defensiveGoaltending",
    periodNumber: known(1),
    points: 3,
    statisticalTreatment: "includedInPlayerCounters",
    teamEntryId: "team_home",
    violatingTeamEntryId: "team_away",
  }];
  add("defensive_goaltending_credits_shooter_and_counters", input, accepted(
    {path: "normalizedBoxScore.playedScoreAdjustments.0.creditedShot", value: "threePointMade"},
  ));
}

for (const [name, mutate, errorPath] of [
  ["reject_wrong_period_exceptional_scoring", (input) => {
    input.rules.penaltyAccumulationGroups = resetGroups(2);
    input.rules.regulationPeriodCount = 2;
    input.periods.push(regulationPeriod(2, 0, 0));
    input.playedScoreAdjustments[0].periodNumber = known(2);
  }, "$.periods[0].exceptionalScoringPoints"],
  ["reject_missing_exceptional_credit", (input) => {
    input.playedScoreAdjustments[0].creditedParticipantId = unknown("not_recorded");
  }, "$.playedScoreAdjustments[0].creditedParticipantId"],
  ["reject_wrong_exceptional_team", (input) => {
    input.playedScoreAdjustments[0].violatingTeamEntryId = "team_home";
  }, "$.playedScoreAdjustments[0].violatingTeamEntryId"],
  ["reject_additive_exceptional_double_count_policy", (input) => {
    input.playedScoreAdjustments[0].statisticalTreatment = "additiveToPlayerCounters";
  }, "$.playedScoreAdjustments[0].statisticalTreatment"],
]) {
  const input = clone(cases.find((entry) => entry.name === "own_basket_is_credited_and_included_once").input);
  input.scope.gameId = name;
  mutate(input);
  add(name, input, rejected("invalidScoreAdjustment", errorPath));
}

{
  const input = clone(base);
  input.scope.gameId = "game_one_second_ejection";
  input.teams[0].players[0].time = roundedTime(600000);
  input.teams[0].players[0].departure = {
    clockRemainingMs: known(599000), evidenceRefs: known(["ejection_evidence"]),
    kind: "ejected", periodNumber: known(1),
  };
  add("reject_time_impossible_before_one_second_ejection", input, rejected(
    "departureTimeConflict", "$.participants.participant_home_1.time",
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_exit_exact_boundary";
  input.teams[0].players[0].time = exactTime(1000);
  input.teams[0].players[0].departure = {
    clockRemainingMs: known(599000), evidenceRefs: known(["ejection_evidence"]),
    kind: "ejected", periodNumber: known(1),
  };
  add("departure_time_exact_boundary_is_valid", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.value.lowerInclusive", value: 1000},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_partial_adjudicated";
  input.resultDisposition = "otherAdjudicated";
  input.periods[0].completionState = "partial";
  input.periods[0].elapsedDurationMs = known(1000);
  input.teams[0].players[0].time = exactTime(1000);
  input.teams[1].players[0].time = exactTime(1000);
  input.administrativeResult = {
    awardedScore: known({away: 0, home: 2}), evidenceRefs: known(["adjudication_evidence"]),
    playerStatisticsTreatment: "includePlayedStatistics", standingsTreatment: "awardedResult",
    winnerTeamEntryId: known("team_home"),
  };
  add("partial_period_keeps_nominal_and_elapsed_separate", input, accepted(
    {path: "normalizedBoxScore.periods.0.nominalDurationMs.value", value: 600000},
    {path: "normalizedBoxScore.periods.0.elapsedDurationMs.value", value: 1000},
  ));
}

for (const state of ["suspended", "abandoned", "adjudicated"]) {
  const input = clone(cases.find((entry) => entry.name === "partial_period_keeps_nominal_and_elapsed_separate").input);
  input.scope.gameId = `game_period_${state}`;
  input.periods[0].completionState = state;
  add(`period_state_${state}_preserves_actual_elapsed`, input, accepted(
    {path: "normalizedBoxScore.periods.0.completionState", value: state},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_resumed_completed";
  input.periods[0].completionState = "resumedCompleted";
  add("resumed_period_can_complete_at_nominal_elapsed", input, accepted(
    {path: "normalizedBoxScore.periods.0.completionState", value: "resumedCompleted"},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_unknown_departure";
  input.teams[0].players[0].departure = {
    clockRemainingMs: unknown("not_recorded"), evidenceRefs: known(["injury_evidence"]),
    kind: "injured", periodNumber: unknown("not_recorded"),
  };
  add("unknown_departure_time_remains_unknown", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.0.departure.clockRemainingMs.state", value: "unknown"},
  ));
}

const fourQuarterBase = () => {
  const input = clone(base);
  input.rules = fibaRules(4);
  input.periods = [
    regulationPeriod(1, 2, 0), regulationPeriod(2, 0, 0),
    regulationPeriod(3, 0, 0), regulationPeriod(4, 0, 0),
  ];
  input.teams[0].players[0].time = exactTime(2400000);
  input.teams[1].players[0].time = exactTime(2400000);
  return input;
};

{
  const input = fourQuarterBase();
  input.scope.gameId = "game_fiba_rounded_subminute";
  input.teams[0].players[0].time = roundedTime(60000, "fiba2024ReferenceSheet");
  add("fiba_reference_positive_subminute_maps_to_displayed_one", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.value.lowerInclusive", value: 1},
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.value.upperExclusive", value: 90000},
  ));
}

{
  const input = fourQuarterBase();
  input.scope.gameId = "game_fiba_rounded_39";
  input.teams[0].players[0].time = roundedTime(2340000, "fiba2024ReferenceSheet");
  add("fiba_reference_39_50_remains_displayed_39", input, accepted(
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.value.lowerInclusive", value: 2310000},
    {path: "normalizedBoxScore.teams.0.players.0.time.possibleIntervalMs.value.upperExclusive", value: 2400000},
  ));
}

{
  const input = fourQuarterBase();
  input.scope.gameId = "game_fiba_double_overtime_penalty";
  input.rules = fibaRules(6);
  input.periods = [
    regulationPeriod(1, 2, 2), regulationPeriod(2, 0, 0),
    regulationPeriod(3, 0, 0), regulationPeriod(4, 0, 0),
    overtimePeriod(5, 1, 0, 0), overtimePeriod(6, 2, 2, 0),
  ];
  input.playedScore = {away: 2, home: 4};
  input.officialScore = officialScore(4, 2);
  setPlayerCounts(input, 0, 0, {twoMade: 2, twoAttempted: 2});
  setPlayerCounts(input, 1, 0, {twoMade: 1, twoAttempted: 1});
  input.teams[0].players[0].time = exactTime(3000000);
  input.teams[1].players[0].time = exactTime(3000000);
  input.disciplineIncidents = [
    ...Array.from({length: 4}, (_, index) => incident({
      incidentId: `q4_foul_${index + 1}`, periodNumber: 4,
    })),
    incident({incidentId: "ot1_foul", periodNumber: 5}),
    incident({incidentId: "ot2_foul", periodNumber: 6}),
  ];
  add("fiba_reference_groups_q4_and_repeated_overtime", input, accepted(
    {path: "normalizedBoxScore.teams.0.discipline.teamFoulsByPeriod.5", value: 1},
    {path: "normalizedBoxScore.teams.0.discipline.penaltyStateByPeriod.5.groupTeamFoulsThroughPeriod", value: 5},
    {path: "normalizedBoxScore.teams.0.discipline.penaltyStateByPeriod.5.inPenalty.value", value: true},
    {path: "normalizedBoxScore.teams.0.discipline.penaltyGroups.3.teamFouls", value: 6},
  ));
}

{
  const input = clone(cases.find((entry) => entry.name === "fiba_reference_groups_q4_and_repeated_overtime").input);
  input.scope.gameId = "game_alternative_ot_reset";
  input.rules.rulesProfileId = "generic-explicit-v2";
  input.rules.playingTimeRoundingProfile = "nearest-half-up-v1";
  input.rules.teamTimeCapacityMultiplier = known(1);
  input.rules.penaltyAccumulationGroups = resetGroups(6, known(2));
  add("alternative_league_resets_each_overtime", input, accepted(
    {path: "normalizedBoxScore.teams.0.discipline.penaltyStateByPeriod.5.groupTeamFoulsThroughPeriod", value: 1},
    {path: "normalizedBoxScore.teams.0.discipline.penaltyStateByPeriod.5.inPenalty.value", value: false},
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_missing_penalty_group";
  input.rules.penaltyAccumulationGroups = [];
  add("reject_missing_penalty_accumulation_group", input, rejected(
    "invalidPenaltyPolicy", "$.rules.penaltyAccumulationGroups",
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_invalid_three_pointer";
  setPlayerCounts(input, 0, 0, {threeMade: 4, threeAttempted: 3});
  add("reject_three_makes_above_attempts", input, rejected(
    "makesExceedAttempts", "$.teams[0].players[0].counts.threeMade",
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_score_mismatch";
  setPlayerCounts(input, 0, 0, {
    freeAttempted: 3, freeMade: 3, twoAttempted: 38, twoMade: 38,
  });
  input.playedScore = {away: 0, home: 80};
  input.periods[0].homeScore = 78;
  input.periods[0].playerCounterPoints.home = 78;
  input.officialScore = officialScore(80, 0);
  add("reject_player_79_scoreboard_80_periods_78", input, rejected(
    "playedScorePeriodMismatch", "$.playedScore",
  ));
}

{
  const input = clone(base);
  input.scope.gameId = "game_safe_integer_overflow";
  setPlayerCounts(input, 0, 0, {
    twoMade: Number.MAX_SAFE_INTEGER, twoAttempted: Number.MAX_SAFE_INTEGER,
  });
  add("reject_safe_integer_arithmetic_overflow", input, rejected(
    "arithmeticOverflow", "$.derived.points",
  ));
}

const outputCases = cases.map(({name, input, expectedSemantics}) => {
  const outcome = calculator.calculateNormalizedBoxScore(input);
  assert.equal(outcome.status, expectedSemantics.status, name);
  if (expectedSemantics.status === "rejected") {
    assert.deepEqual(outcome.errors[0], expectedSemantics.error, name);
  } else {
    for (const check of expectedSemantics.checks) {
      assert.deepEqual(pathValue(outcome, check.path), check.value, `${name}: ${check.path}`);
    }
  }
  const expectedCanonical = contract.canonicalEncode(outcome);
  return {
    expectedCanonical,
    expectedCanonicalByteLength: Buffer.byteLength(expectedCanonical, "utf8"),
    expectedSemantics,
    expectedSha256: contract.canonicalSha256(outcome),
    input,
    name,
  };
});

const fixtures = {
  calculatorVersion: calculator.normalizedBoxScoreCalculatorVersion,
  canonicalEncodingVersion: contract.officialStatVersions.canonicalEncodingVersion,
  fixtureSchemaVersion: 2,
  cases: outputCases,
  unicodeNormalizationVersion: calculator.normalizedBoxScoreUnicodeVersion,
};

process.stdout.write(`${JSON.stringify(fixtures, null, 2)}\n`);
