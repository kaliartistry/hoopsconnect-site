#!/usr/bin/env node

/*
 * Deliberate golden-fixture generator for Packet 06.
 *
 * Run only after building Functions. The checked-in JSON output is normative;
 * tests never regenerate it. Any regenerated canonical bytes/hashes require an
 * explicit reviewed diff.
 */
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
const roundedTime = (playedTimeMs = 600000) => ({
  playedTimeMs: known(playedTimeMs),
  roundingMode: "nearestHalfUp",
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
const team = ({side, teamEntryId, players}) => {
  const summed = Object.fromEntries(counterNames.map((name) => [name, 0]));
  for (const line of players) {
    for (const name of counterNames) summed[name] += line.counts[name].value;
  }
  return {
    players,
    reportedTotals: counts(summed),
    side,
    teamEntryId,
    teamOnly: {
      defensiveRebounds: known(0),
      offensiveRebounds: known(0),
      turnovers: known(0),
    },
  };
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
const regulationPeriod = (number, homeScore, awayScore) => ({
  awayScore,
  durationMs: known(600000),
  homeScore,
  kind: "regulation",
  number,
  overtimeIndex: na("regulation_period"),
  source: "officialSheet",
});
const overtimePeriod = (number, overtimeIndex, homeScore, awayScore) => ({
  awayScore,
  durationMs: known(300000),
  homeScore,
  kind: "overtime",
  number,
  overtimeIndex: known(overtimeIndex),
  source: "officialSheet",
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
  rules: {
    completedTiesAllowed: false,
    regulationPeriodCount: 1,
    teamFoulPenaltyThresholds: {
      overtime: known(5),
      regulation: known(5),
    },
  },
  schemaVersion: 1,
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
        // One unattributed miss and zero rebounds is valid; the calculator
        // deliberately has no false miss-to-rebound invariant.
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

const cases = [];
const add = (name, input) => cases.push({name, input});

add("complete_zero_disciplinary_incidents", clone(base));

{
  const input = clone(base);
  input.scope.gameId = "game_team_only_counts";
  input.teams[0].players[0].counts.offensiveRebounds = known(1);
  input.teams[0].players[0].counts.defensiveRebounds = known(2);
  input.teams[0].players[0].counts.turnovers = known(1);
  input.teams[0].teamOnly = {
    defensiveRebounds: known(3),
    offensiveRebounds: known(2),
    turnovers: known(4),
  };
  input.teams[0].reportedTotals.offensiveRebounds = known(3);
  input.teams[0].reportedTotals.defensiveRebounds = known(5);
  input.teams[0].reportedTotals.turnovers = known(5);
  add("team_only_rebounds_and_turnovers_are_separate", input);
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
  input.disciplineIncidents = [
    {
      chargedParticipantId: known("participant_home_fouled_out"),
      chargedPartyKind: "player",
      clockRemainingMs: known(100000),
      countsTowardPlayerDisqualification: true,
      countsTowardTeamFoul: true,
      evidenceRefs: known(["discipline_evidence_unsportsmanlike"]),
      incidentId: "incident_unsportsmanlike_1",
      incidentType: "unsportsmanlike",
      periodNumber: known(1),
      relatedParticipantId: na("no_related_participant"),
      scoresheetCode: "U",
      teamEntryId: "team_home",
    },
    {
      chargedParticipantId: na("not_player_charge"),
      chargedPartyKind: "coach",
      clockRemainingMs: unknown("not_recorded"),
      countsTowardPlayerDisqualification: false,
      countsTowardTeamFoul: false,
      evidenceRefs: known(["discipline_evidence_coach"]),
      incidentId: "incident_coach_1",
      incidentType: "technical",
      periodNumber: known(1),
      relatedParticipantId: na("no_related_participant"),
      scoresheetCode: "C",
      teamEntryId: "team_home",
    },
    {
      chargedParticipantId: na("not_player_charge"),
      chargedPartyKind: "team",
      clockRemainingMs: unknown("not_recorded"),
      countsTowardPlayerDisqualification: false,
      countsTowardTeamFoul: false,
      evidenceRefs: known(["discipline_evidence_team"]),
      incidentId: "incident_team_1",
      incidentType: "technical",
      periodNumber: known(1),
      relatedParticipantId: na("no_related_participant"),
      scoresheetCode: "T",
      teamEntryId: "team_home",
    },
  ];
  add("departure_vocabulary_and_typed_discipline", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_double_overtime";
  input.rules.regulationPeriodCount = 4;
  input.periods = [
    regulationPeriod(1, 2, 2),
    regulationPeriod(2, 2, 2),
    regulationPeriod(3, 2, 2),
    regulationPeriod(4, 2, 2),
    overtimePeriod(5, 1, 2, 2),
    overtimePeriod(6, 2, 2, 0),
  ];
  input.playedScore = {away: 10, home: 12};
  input.officialScore = officialScore(12, 10);
  input.teams[0].players[0].counts = counts({twoMade: 6, twoAttempted: 6});
  input.teams[0].players[0].time = exactTime(3000000);
  input.teams[0].reportedTotals = counts({twoMade: 6, twoAttempted: 6});
  input.teams[1].players[0].counts = counts({twoMade: 5, twoAttempted: 5});
  input.teams[1].players[0].time = exactTime(3000000);
  input.teams[1].reportedTotals = counts({twoMade: 5, twoAttempted: 5});
  add("legitimate_double_overtime_50_minutes", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_no_time_source";
  input.teams[0].players[0].time = noRecordedTime();
  input.teams[1].players[0].time = noRecordedTime();
  add("stats_only_capture_never_invents_time", input);
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
  input.disciplineIncidents = [{
    chargedParticipantId: na("not_player_charge"),
    chargedPartyKind: "bench",
    clockRemainingMs: unknown("not_recorded"),
    countsTowardPlayerDisqualification: false,
    countsTowardTeamFoul: false,
    evidenceRefs: known(["official_sheet_discipline_1"]),
    incidentId: "incident_bench_1",
    incidentType: "technical",
    periodNumber: known(1),
    relatedParticipantId: known("participant_home_dnp"),
    scoresheetCode: "B-T",
    teamEntryId: "team_home",
  }];
  add("dnp_bench_technical_preserves_discipline_without_gp", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_forfeit_outcome";
  input.resultDisposition = "forfeit";
  input.administrativeResult = {
    awardedScore: known({away: 20, home: 0}),
    evidenceRefs: known(["adjudication_decision_1"]),
    playerStatisticsTreatment: "includePlayedStatistics",
    standingsTreatment: "awardedResult",
    winnerTeamEntryId: known("team_away"),
  };
add("played_score_separate_from_administrative_result", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_pregame_default";
  input.resultDisposition = "default";
  input.rules.regulationPeriodCount = 4;
  input.periods = [];
  input.playedScore = {away: 0, home: 0};
  input.officialScore = officialScore(0, 0);
  input.teams = [
    team({
      side: "home",
      teamEntryId: "team_home",
      players: [player({
        participantId: "participant_home_1",
        playerId: "player_home_1",
        teamEntryId: "team_home",
        participationStatus: "dnp",
        enteredPlay: false,
        time: noParticipationTime(),
      })],
    }),
    team({
      side: "away",
      teamEntryId: "team_away",
      players: [player({
        participantId: "participant_away_1",
        playerId: "player_away_1",
        teamEntryId: "team_away",
        participationStatus: "dnp",
        enteredPlay: false,
        time: noParticipationTime(),
      })],
    }),
  ];
  input.administrativeResult = {
    awardedScore: known({away: 0, home: 20}),
    evidenceRefs: known(["adjudication_default_1"]),
    playerStatisticsTreatment: "exclude",
    standingsTreatment: "awardedResult",
    winnerTeamEntryId: known("team_home"),
  };
  add("pregame_default_allows_zero_played_periods", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_own_basket";
  input.teams[0].players[0].counts = counts();
  input.teams[0].reportedTotals = counts();
  input.playedScoreAdjustments = [{
    adjustmentId: "adjustment_own_basket_1",
    evidenceRefs: known(["play_evidence_own_basket_1"]),
    kind: "ownBasket",
    periodNumber: known(1),
    points: 2,
    teamEntryId: "team_home",
  }];
  add("explicit_own_basket_not_balance_score", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_invalid_three_pointer";
  input.teams[0].players[0].counts = counts({threeMade: 4, threeAttempted: 3});
  add("reject_three_makes_above_attempts", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_score_mismatch";
  input.teams[0].players[0].counts = counts({
    twoMade: 38,
    twoAttempted: 38,
    freeMade: 3,
    freeAttempted: 3,
  });
  input.teams[0].reportedTotals = counts({
    twoMade: 38,
    twoAttempted: 38,
    freeMade: 3,
    freeAttempted: 3,
  });
  input.playedScore = {away: 0, home: 80};
  input.periods = [regulationPeriod(1, 78, 0)];
  input.officialScore = officialScore(80, 0);
  add("reject_player_79_scoreboard_80_periods_78", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_dnp_assist";
  const dnp = player({
    participantId: "participant_home_dnp",
    playerId: "player_home_dnp",
    teamEntryId: "team_home",
    participationStatus: "dnp",
    enteredPlay: false,
    time: noParticipationTime(),
  });
  dnp.counts.assists = known(1);
  input.teams[0].players.push(dnp);
  add("reject_dnp_with_assist", input);
}

{
  const input = clone(base);
  input.scope.gameId = "game_safe_integer_overflow";
  const maximum = Number.MAX_SAFE_INTEGER;
  input.teams[0].players[0].counts = counts({
    twoMade: maximum,
    twoAttempted: maximum,
  });
  input.teams[0].reportedTotals = counts({
    twoMade: maximum,
    twoAttempted: maximum,
  });
  add("reject_safe_integer_arithmetic_overflow", input);
}

const fixtures = {
  calculatorVersion: calculator.normalizedBoxScoreCalculatorVersion,
  canonicalEncodingVersion: contract.officialStatVersions.canonicalEncodingVersion,
  fixtureSchemaVersion: 1,
  cases: cases.map(({name, input}) => {
    const outcome = calculator.calculateNormalizedBoxScore(input);
    const expectedCanonical = contract.canonicalEncode(outcome);
    return {
      expectedCanonical,
      expectedCanonicalByteLength: Buffer.byteLength(expectedCanonical, "utf8"),
      expectedSha256: contract.canonicalSha256(outcome),
      input,
      name,
    };
  }),
  unicodeNormalizationVersion: calculator.normalizedBoxScoreUnicodeVersion,
};

process.stdout.write(`${JSON.stringify(fixtures, null, 2)}\n`);
