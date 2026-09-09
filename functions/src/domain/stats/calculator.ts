import {
  canonicalEncode,
  officialStatVersions,
  type ExplicitFact,
} from "../official_stats_contract";
import {
  calculatorErrorCodes,
  normalizedBoxScoreCalculatorVersion,
  normalizedBoxScoreUnicodeVersion,
  playerCountFields,
  type CalculatorAccepted,
  type CalculatorDiagnostic,
  type CalculatorErrorCode,
  type CalculatorOutcome,
  type NormalizedBoxScoreInput,
  type PlayerCountField,
  type PlayerLineInput,
  type ScorePair,
  type TeamInput,
} from "./types";

export * from "./types";

export const normalizedBoxScoreLimits = {
  maxCanonicalPayloadBytes: 128 * 1024,
  maxDepth: 16,
  maxEvidenceRefsPerFact: 64,
  maxIncidents: 512,
  maxNodes: 20_000,
  maxPeriods: 64,
  maxPlayedScoreAdjustments: 128,
  maxPlayersPerTeam: 64,
  maxStringBytes: 1024,
} as const;

const opaqueId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const factStates = new Set(["known", "unknown", "notApplicable"]);
const playerCounterSet = new Set<string>(playerCountFields);

class ValidationFailure extends Error {
  constructor(readonly code: CalculatorErrorCode, readonly path: string) {
    super(`${code} at ${path}`);
  }
}

function fail(code: CalculatorErrorCode, path: string): never {
  throw new ValidationFailure(code, path);
}

function utf8Length(value: string): number {
  return Buffer.byteLength(value, "utf8");
}

function sortedObjectKeys(value: Record<string, unknown>): string[] {
  return Object.keys(value).sort();
}

function preflight(value: unknown): void {
  let nodes = 0;
  const visit = (current: unknown, path: string, depth: number): void => {
    nodes += 1;
    if (nodes > normalizedBoxScoreLimits.maxNodes || depth > normalizedBoxScoreLimits.maxDepth) {
      fail("resourceLimitExceeded", path);
    }
    if (current === null || typeof current === "boolean") return;
    if (typeof current === "string") {
      if (utf8Length(current) > normalizedBoxScoreLimits.maxStringBytes) {
        fail("resourceLimitExceeded", path);
      }
      return;
    }
    if (typeof current === "number") {
      if (!Number.isSafeInteger(current) || current < 0) {
        fail("invalidNonnegativeSafeInteger", path);
      }
      return;
    }
    if (Array.isArray(current)) {
      if (Object.getPrototypeOf(current) !== Array.prototype ||
          Object.getOwnPropertyNames(current).length !== current.length + 1 ||
          Object.getOwnPropertySymbols(current).length !== 0) {
        fail("invalidCanonicalValue", path);
      }
      for (let index = 0; index < current.length; index += 1) {
        const descriptor = Object.getOwnPropertyDescriptor(current, String(index));
        if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) {
          fail("invalidCanonicalValue", `${path}[${index}]`);
        }
        visit(descriptor.value, `${path}[${index}]`, depth + 1);
      }
      return;
    }
    if (typeof current === "object") {
      const prototype = Object.getPrototypeOf(current);
      if ((prototype !== Object.prototype && prototype !== null) ||
          Object.getOwnPropertySymbols(current).length !== 0) {
        fail("invalidCanonicalValue", path);
      }
      const record = current as Record<string, unknown>;
      const keys = sortedObjectKeys(record);
      if (Object.getOwnPropertyNames(record).length !== keys.length) {
        fail("invalidCanonicalValue", path);
      }
      for (const key of keys) {
        if (!/^[\x21-\x7e]+$/.test(key)) fail("invalidCanonicalValue", path);
        if (utf8Length(key) > normalizedBoxScoreLimits.maxStringBytes) {
          fail("resourceLimitExceeded", path);
        }
        const descriptor = Object.getOwnPropertyDescriptor(record, key);
        if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) {
          fail("invalidCanonicalValue", `${path}.${key}`);
        }
        visit(descriptor.value, `${path}.${key}`, depth + 1);
      }
      return;
    }
    fail("invalidCanonicalValue", path);
  };
  visit(value, "$", 0);
  let encoded: string;
  try {
    encoded = canonicalEncode(value);
  } catch {
    fail("invalidCanonicalValue", "$");
  }
  if (utf8Length(encoded) > normalizedBoxScoreLimits.maxCanonicalPayloadBytes) {
    fail("resourceLimitExceeded", "$");
  }
}

function record(value: unknown, path: string, exactKeys?: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("invalidShape", path);
  }
  const result = value as Record<string, unknown>;
  if (exactKeys) {
    const actual = sortedObjectKeys(result);
    const expected = [...exactKeys].sort();
    if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
      fail("invalidShape", path);
    }
  }
  return result;
}

function array(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) fail("invalidShape", path);
  return value;
}

function textValue(value: unknown, path: string, maxBytes = 512): string {
  if (typeof value !== "string" || value.length === 0 || utf8Length(value) > maxBytes) {
    fail("invalidString", path);
  }
  const normalized = value.normalize("NFC");
  if (utf8Length(normalized) > maxBytes) fail("invalidString", path);
  return normalized;
}

function identifier(value: unknown, path: string): string {
  if (typeof value !== "string" || !opaqueId.test(value)) fail("invalidIdentifier", path);
  return value;
}

function nonnegativeInteger(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    fail("invalidNonnegativeSafeInteger", path);
  }
  return value;
}

function booleanValue(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") fail("invalidShape", path);
  return value;
}

function enumeration<T extends string>(value: unknown, path: string, values: readonly T[]): T {
  if (typeof value !== "string" || !values.includes(value as T)) fail("invalidShape", path);
  return value as T;
}

function fact<T>(
  value: unknown,
  path: string,
  parseKnown: (known: unknown, knownPath: string) => T,
): ExplicitFact<T> {
  const raw = record(value, path);
  const state = raw.state;
  if (typeof state !== "string" || !factStates.has(state)) fail("invalidFact", path);
  if (state === "known") {
    if (sortedObjectKeys(raw).join(",") !== "state,value") fail("invalidFact", path);
    return {state: "known", value: parseKnown(raw.value, `${path}.value`)};
  }
  if (sortedObjectKeys(raw).join(",") !== "reasonCode,state,value" || raw.value !== null) {
    fail("invalidFact", path);
  }
  if (state === "unknown") {
    if (raw.reasonCode !== null && (typeof raw.reasonCode !== "string" || raw.reasonCode.length === 0)) {
      fail("invalidFact", `${path}.reasonCode`);
    }
    return {
      state: "unknown",
      value: null,
      reasonCode: raw.reasonCode === null ? null : textValue(raw.reasonCode, `${path}.reasonCode`),
    };
  }
  if (typeof raw.reasonCode !== "string" || raw.reasonCode.length === 0) {
    fail("invalidFact", `${path}.reasonCode`);
  }
  return {
    state: "notApplicable",
    value: null,
    reasonCode: textValue(raw.reasonCode, `${path}.reasonCode`),
  };
}

function validateScope(value: unknown): Record<string, string> {
  const raw = record(value, "$.scope", [
    "associationId", "competitionId", "divisionId", "gameId", "phaseId", "seasonId",
  ]);
  return {
    associationId: identifier(raw.associationId, "$.scope.associationId"),
    competitionId: identifier(raw.competitionId, "$.scope.competitionId"),
    divisionId: identifier(raw.divisionId, "$.scope.divisionId"),
    gameId: identifier(raw.gameId, "$.scope.gameId"),
    phaseId: identifier(raw.phaseId, "$.scope.phaseId"),
    seasonId: identifier(raw.seasonId, "$.scope.seasonId"),
  };
}

function countFact(value: unknown, path: string): ExplicitFact<number> {
  return fact(value, path, nonnegativeInteger);
}

function knownCount(value: unknown, path: string): number {
  const parsed = countFact(value, path);
  if (parsed.state !== "known") fail("requiredKnownCount", path);
  return parsed.value;
}

function stringList(value: unknown, path: string): string[] {
  const raw = array(value, path);
  if (raw.length > normalizedBoxScoreLimits.maxEvidenceRefsPerFact) {
    fail("resourceLimitExceeded", path);
  }
  return raw.map((item, index) => textValue(item, `${path}[${index}]`));
}

function scorePair(value: unknown, path: string): ScorePair {
  const raw = record(value, path, ["away", "home"]);
  return {
    home: nonnegativeInteger(raw.home, `${path}.home`),
    away: nonnegativeInteger(raw.away, `${path}.away`),
  };
}

function safeAdd(left: number, right: number, path: string): number {
  const result = left + right;
  if (!Number.isSafeInteger(result)) fail("arithmeticOverflow", path);
  return result;
}

function safeMultiply(value: number, multiplier: number, path: string): number {
  const result = value * multiplier;
  if (!Number.isSafeInteger(result)) fail("arithmeticOverflow", path);
  return result;
}

function zeroCounts(): Record<PlayerCountField, number> {
  return Object.fromEntries(playerCountFields.map((field) => [field, 0])) as
    Record<PlayerCountField, number>;
}

function parseCounts(rawValue: unknown, path: string): Record<PlayerCountField, number> {
  const raw = record(rawValue, path, playerCountFields);
  const result = zeroCounts();
  for (const field of playerCountFields) result[field] = knownCount(raw[field], `${path}.${field}`);
  return result;
}

function derivedTotals(
  counts: Readonly<Record<PlayerCountField, number>>,
): Record<string, number> {
  const fieldMade = safeAdd(counts.twoMade, counts.threeMade, "$.derived.fieldMade");
  const fieldAttempted = safeAdd(
    counts.twoAttempted,
    counts.threeAttempted,
    "$.derived.fieldAttempted",
  );
  const totalRebounds = safeAdd(
    counts.offensiveRebounds,
    counts.defensiveRebounds,
    "$.derived.totalRebounds",
  );
  const points = safeAdd(
    safeAdd(
      safeMultiply(counts.twoMade, 2, "$.derived.points"),
      safeMultiply(counts.threeMade, 3, "$.derived.points"),
      "$.derived.points",
    ),
    counts.freeMade,
    "$.derived.points",
  );
  return {...counts, fieldMade, fieldAttempted, totalRebounds, points};
}

function shootingPercentages(
  totals: Readonly<Record<string, number>>,
): Record<string, ExplicitFact<Record<string, number>>> {
  const ratio = (makes: number, attempts: number): ExplicitFact<Record<string, number>> =>
    attempts === 0 ?
      {state: "unknown", value: null, reasonCode: "zero_attempts"} :
      {state: "known", value: {attempts, makes}};
  return {
    field: ratio(totals.fieldMade, totals.fieldAttempted),
    free: ratio(totals.freeMade, totals.freeAttempted),
    three: ratio(totals.threeMade, totals.threeAttempted),
    two: ratio(totals.twoMade, totals.twoAttempted),
  };
}

function addCounts(
  target: Record<PlayerCountField, number>,
  source: Readonly<Record<PlayerCountField, number>>,
  path: string,
): void {
  for (const field of playerCountFields) {
    target[field] = safeAdd(target[field], source[field], `${path}.${field}`);
  }
}

function isZeroCounts(counts: Readonly<Record<PlayerCountField, number>>): boolean {
  return playerCountFields.every((field) => counts[field] === 0);
}

function absentFact(value: ExplicitFact<unknown>, reason: string): boolean {
  return value.state === "notApplicable" && value.reasonCode === reason;
}

function validateTime(
  rawValue: unknown,
  path: string,
  enteredPlay: boolean,
): Record<string, unknown> {
  const raw = record(rawValue, path, [
    "playedTimeMs", "roundingMode", "timePrecisionMs", "timeSource",
  ]);
  const playedTimeMs = countFact(raw.playedTimeMs, `${path}.playedTimeMs`);
  const timePrecisionMs = countFact(raw.timePrecisionMs, `${path}.timePrecisionMs`);
  const timeSource = enumeration(raw.timeSource, `${path}.timeSource`, [
    "liveClock", "officialSheetExact", "officialSheetRounded", "notRecorded", "notApplicable",
  ] as const);
  const roundingMode = enumeration(raw.roundingMode, `${path}.roundingMode`, [
    "nearestHalfUp", "notApplicable",
  ] as const);

  if (!enteredPlay) {
    if (timeSource !== "notApplicable" || roundingMode !== "notApplicable" ||
        !absentFact(playedTimeMs, "did_not_enter") ||
        !absentFact(timePrecisionMs, "did_not_enter")) {
      fail("invalidTimeProvenance", path);
    }
    return {
      playedTimeMs,
      possibleIntervalMs: {state: "notApplicable", value: null, reasonCode: "did_not_enter"},
      roundingMode,
      timePrecisionMs,
      timeSource,
    };
  }

  if (timeSource === "notRecorded") {
    if (playedTimeMs.state !== "unknown" || roundingMode !== "notApplicable" ||
        !absentFact(timePrecisionMs, "no_time_source")) {
      fail("invalidTimeProvenance", path);
    }
    return {
      playedTimeMs,
      possibleIntervalMs: {state: "unknown", value: null, reasonCode: "no_time_source"},
      roundingMode,
      timePrecisionMs,
      timeSource,
    };
  }

  if (timeSource === "notApplicable" || playedTimeMs.state !== "known" ||
      timePrecisionMs.state !== "known" || timePrecisionMs.value === 0) {
    fail("invalidTimeProvenance", path);
  }
  const played = playedTimeMs.value;
  const precision = timePrecisionMs.value;
  if (timeSource === "officialSheetRounded") {
    if (roundingMode !== "nearestHalfUp" || played % precision !== 0) {
      fail("invalidTimeProvenance", path);
    }
    const lowerInclusive = Math.max(0, played - Math.floor(precision / 2));
    const upperExclusive = safeAdd(played, Math.ceil(precision / 2), path);
    return {
      playedTimeMs,
      possibleIntervalMs: {state: "known", value: {lowerInclusive, upperExclusive}},
      roundingMode,
      timePrecisionMs,
      timeSource,
    };
  }
  if (roundingMode !== "notApplicable") fail("invalidTimeProvenance", path);
  return {
    playedTimeMs,
    possibleIntervalMs: {
      state: "known",
      value: {lowerInclusive: played, upperExclusive: safeAdd(played, precision, path)},
    },
    roundingMode,
    timePrecisionMs,
    timeSource,
  };
}

function validateDeparture(rawValue: unknown, path: string): Record<string, unknown> {
  const raw = record(rawValue, path, ["clockRemainingMs", "evidenceRefs", "kind", "periodNumber"]);
  const kind = enumeration(raw.kind, `${path}.kind`, [
    "none", "fouledOut", "ejected", "injured", "other",
  ] as const);
  const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
  const clockRemainingMs = fact(raw.clockRemainingMs, `${path}.clockRemainingMs`, nonnegativeInteger);
  const evidenceRefs = fact(raw.evidenceRefs, `${path}.evidenceRefs`, stringList);
  if (kind === "none") {
    if (!absentFact(periodNumber, "no_departure") ||
        !absentFact(clockRemainingMs, "no_departure") ||
        !absentFact(evidenceRefs, "no_departure")) fail("invalidDeparture", path);
  } else {
    if (periodNumber.state === "notApplicable" || clockRemainingMs.state === "notApplicable" ||
        evidenceRefs.state !== "known") fail("invalidDeparture", path);
    if (periodNumber.state === "known" && periodNumber.value === 0) fail("invalidDeparture", path);
    if (evidenceRefs.state === "known" && evidenceRefs.value.length === 0) {
      fail("invalidDeparture", `${path}.evidenceRefs`);
    }
  }
  return {clockRemainingMs, evidenceRefs, kind, periodNumber};
}

function validatePlayer(
  rawValue: unknown,
  path: string,
  teamEntryId: string,
): {input: PlayerLineInput; counts: Record<PlayerCountField, number>; output: Record<string, unknown>} {
  const raw = record(rawValue, path, [
    "counts", "departure", "enteredPlay", "participantId", "participationStatus",
    "participationReasonCode", "playerId", "rosterMembershipId", "rosterMembershipVersionId", "starter",
    "teamEntryId", "time",
  ]);
  const participantId = identifier(raw.participantId, `${path}.participantId`);
  const playerId = identifier(raw.playerId, `${path}.playerId`);
  const rosterMembershipId = identifier(raw.rosterMembershipId, `${path}.rosterMembershipId`);
  const rosterMembershipVersionId = identifier(
    raw.rosterMembershipVersionId,
    `${path}.rosterMembershipVersionId`,
  );
  const playerTeamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
  if (playerTeamEntryId !== teamEntryId) fail("participantTeamMismatch", `${path}.teamEntryId`);
  const participationStatus = enumeration(raw.participationStatus, `${path}.participationStatus`, [
    "active", "dnp", "inactive",
  ] as const);
  const enteredPlay = booleanValue(raw.enteredPlay, `${path}.enteredPlay`);
  if ((participationStatus === "active") !== enteredPlay) {
    fail("invalidParticipation", path);
  }
  const participationReasonCode = fact(
    raw.participationReasonCode,
    `${path}.participationReasonCode`,
    identifier,
  );
  if (enteredPlay) {
    if (!absentFact(participationReasonCode, "entered_play")) {
      fail("invalidParticipation", `${path}.participationReasonCode`);
    }
  } else if (participationReasonCode.state === "notApplicable") {
    fail("invalidParticipation", `${path}.participationReasonCode`);
  }
  const starter = fact(raw.starter, `${path}.starter`, booleanValue);
  if (!enteredPlay && starter.state === "known" && starter.value) {
    fail("invalidParticipation", `${path}.starter`);
  }
  const counts = parseCounts(raw.counts, `${path}.counts`);
  if (!enteredPlay && !isZeroCounts(counts)) fail("dnpOrdinaryStat", `${path}.counts`);
  if (counts.twoMade > counts.twoAttempted) fail("makesExceedAttempts", `${path}.counts.twoMade`);
  if (counts.threeMade > counts.threeAttempted) {
    fail("makesExceedAttempts", `${path}.counts.threeMade`);
  }
  if (counts.freeMade > counts.freeAttempted) fail("makesExceedAttempts", `${path}.counts.freeMade`);
  const time = validateTime(raw.time, `${path}.time`, enteredPlay);
  const departure = validateDeparture(raw.departure, `${path}.departure`);
  if (!enteredPlay && (departure.kind as string) !== "none") fail("invalidDeparture", `${path}.departure`);
  const input = rawValue as PlayerLineInput;
  const totals = derivedTotals(counts);
  return {
    input,
    counts,
    output: {
      departure,
      enteredPlay,
      gamesPlayed: enteredPlay ? 1 : 0,
      participantId,
      participationReasonCode,
      participationStatus,
      playerId,
      rosterMembershipId,
      rosterMembershipVersionId,
      starter,
      teamEntryId,
      time,
      totals,
      shootingPercentages: shootingPercentages(totals),
    },
  };
}

function validateTeam(
  rawValue: unknown,
  path: string,
  seenParticipants: Set<string>,
  seenPlayers: Set<string>,
): {input: TeamInput; counts: Record<PlayerCountField, number>; output: Record<string, unknown>} {
  const raw = record(rawValue, path, ["players", "reportedTotals", "side", "teamEntryId", "teamOnly"]);
  const teamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
  const side = enumeration(raw.side, `${path}.side`, ["home", "away"] as const);
  const playerValues = array(raw.players, `${path}.players`);
  if (playerValues.length === 0) fail("invalidTeamStructure", `${path}.players`);
  if (playerValues.length > normalizedBoxScoreLimits.maxPlayersPerTeam) {
    fail("resourceLimitExceeded", `${path}.players`);
  }
  const counts = zeroCounts();
  const players = playerValues.map((player, index) => {
    const parsed = validatePlayer(player, `${path}.players[${index}]`, teamEntryId);
    if (seenParticipants.has(parsed.output.participantId as string) ||
        seenPlayers.has(parsed.output.playerId as string)) {
      fail("duplicateParticipant", `${path}.players[${index}]`);
    }
    seenParticipants.add(parsed.output.participantId as string);
    seenPlayers.add(parsed.output.playerId as string);
    addCounts(counts, parsed.counts, `${path}.players`);
    return parsed.output;
  });
  const teamOnlyRaw = record(raw.teamOnly, `${path}.teamOnly`, [
    "defensiveRebounds", "offensiveRebounds", "turnovers",
  ]);
  const teamOnly = {
    offensiveRebounds: knownCount(teamOnlyRaw.offensiveRebounds, `${path}.teamOnly.offensiveRebounds`),
    defensiveRebounds: knownCount(teamOnlyRaw.defensiveRebounds, `${path}.teamOnly.defensiveRebounds`),
    turnovers: knownCount(teamOnlyRaw.turnovers, `${path}.teamOnly.turnovers`),
  };
  counts.offensiveRebounds = safeAdd(
    counts.offensiveRebounds,
    teamOnly.offensiveRebounds,
    `${path}.teamOnly.offensiveRebounds`,
  );
  counts.defensiveRebounds = safeAdd(
    counts.defensiveRebounds,
    teamOnly.defensiveRebounds,
    `${path}.teamOnly.defensiveRebounds`,
  );
  counts.turnovers = safeAdd(counts.turnovers, teamOnly.turnovers, `${path}.teamOnly.turnovers`);
  const reportedTotals = parseCounts(raw.reportedTotals, `${path}.reportedTotals`);
  for (const field of playerCountFields) {
    if (reportedTotals[field] !== counts[field]) {
      fail("reportedTeamTotalMismatch", `${path}.reportedTotals.${field}`);
    }
  }
  const totals = derivedTotals(counts);
  return {
    input: rawValue as TeamInput,
    counts,
    output: {
      players,
      side,
      shootingPercentages: shootingPercentages(totals),
      teamEntryId,
      teamOnly,
      totals,
    },
  };
}

function validatePeriods(
  rawValue: unknown,
  regulationPeriodCount: number,
  requiresCompleteRegulation: boolean,
): {periods: Record<string, unknown>[]; score: ScorePair} {
  const rawPeriods = array(rawValue, "$.periods");
  if (rawPeriods.length > normalizedBoxScoreLimits.maxPeriods) {
    fail("resourceLimitExceeded", "$.periods");
  }
  if (requiresCompleteRegulation && rawPeriods.length < regulationPeriodCount) {
    fail("invalidPeriodSequence", "$.periods");
  }
  const score = {home: 0, away: 0};
  const periods = rawPeriods.map((value, index) => {
    const path = `$.periods[${index}]`;
    const raw = record(value, path, [
      "awayScore", "durationMs", "homeScore", "kind", "number", "overtimeIndex", "source",
    ]);
    const number = nonnegativeInteger(raw.number, `${path}.number`);
    if (number !== index + 1) fail("invalidPeriodSequence", `${path}.number`);
    const kind = enumeration(raw.kind, `${path}.kind`, ["regulation", "overtime"] as const);
    const overtimeIndex = fact(raw.overtimeIndex, `${path}.overtimeIndex`, nonnegativeInteger);
    if (number <= regulationPeriodCount) {
      if (kind !== "regulation" || !absentFact(overtimeIndex, "regulation_period")) {
        fail("invalidPeriodSequence", path);
      }
    } else {
      const expectedOvertime = number - regulationPeriodCount;
      if (kind !== "overtime" || overtimeIndex.state !== "known" ||
          overtimeIndex.value !== expectedOvertime) {
        fail("invalidOvertimeSequence", path);
      }
    }
    const durationMs = countFact(raw.durationMs, `${path}.durationMs`);
    if (durationMs.state === "known" && durationMs.value === 0) {
      fail("invalidPeriodSequence", `${path}.durationMs`);
    }
    const homeScore = nonnegativeInteger(raw.homeScore, `${path}.homeScore`);
    const awayScore = nonnegativeInteger(raw.awayScore, `${path}.awayScore`);
    score.home = safeAdd(score.home, homeScore, "$.periods.homeScore");
    score.away = safeAdd(score.away, awayScore, "$.periods.awayScore");
    const source = enumeration(raw.source, `${path}.source`, [
      "liveCounter", "officialSheet", "historicalEvidence",
    ] as const);
    return {awayScore, durationMs, homeScore, kind, number, overtimeIndex, source};
  });
  return {periods, score};
}

function validatePlayerTimeline(
  teams: readonly {output: Record<string, unknown>}[],
  periods: readonly Record<string, unknown>[],
): void {
  let elapsedMs: number | null = 0;
  for (const period of periods) {
    const duration = period.durationMs as ExplicitFact<number>;
    if (duration.state !== "known") {
      elapsedMs = null;
      break;
    }
    elapsedMs = safeAdd(elapsedMs!, duration.value, "$.periods.durationMs");
  }
  for (const team of teams) {
    for (const player of team.output.players as Record<string, unknown>[]) {
      const time = player.time as Record<string, unknown>;
      const interval = time.possibleIntervalMs as ExplicitFact<Record<string, number>>;
      if (elapsedMs !== null && interval.state === "known" &&
          interval.value.lowerInclusive > elapsedMs) {
        fail("timeOutsideGameDuration", `$.participants.${player.participantId}.time`);
      }
      const departure = player.departure as Record<string, unknown>;
      if (departure.kind === "none") continue;
      const periodNumber = departure.periodNumber as ExplicitFact<number>;
      const clock = departure.clockRemainingMs as ExplicitFact<number>;
      if (clock.state === "known" && periodNumber.state !== "known") {
        fail("eventClockOutsidePeriod", `$.participants.${player.participantId}.departure`);
      }
      if (periodNumber.state === "known") {
        if (periodNumber.value === 0 || periodNumber.value > periods.length) {
          fail("invalidDeparture", `$.participants.${player.participantId}.departure.periodNumber`);
        }
        const duration = periods[periodNumber.value - 1].durationMs as ExplicitFact<number>;
        if (clock.state === "known" && duration.state === "known" && clock.value > duration.value) {
          fail("eventClockOutsidePeriod", `$.participants.${player.participantId}.departure.clockRemainingMs`);
        }
      }
    }
  }
}

function validateEvidenceFact(rawValue: unknown, path: string): ExplicitFact<string[]> {
  return fact(rawValue, path, stringList);
}

function validateDiscipline(
  rawValue: unknown,
  teams: ReadonlyMap<string, Record<string, unknown>>,
  participants: ReadonlyMap<string, {teamEntryId: string; enteredPlay: boolean}>,
  periods: readonly Record<string, unknown>[],
  penaltyThresholds: {regulation: ExplicitFact<number>; overtime: ExplicitFact<number>},
): {
  incidents: Record<string, unknown>[];
  byTeam: Map<string, Record<string, unknown>>;
  byParticipant: Map<string, Record<string, unknown>>;
} {
  const rawIncidents = array(rawValue, "$.disciplineIncidents");
  if (rawIncidents.length > normalizedBoxScoreLimits.maxIncidents) {
    fail("resourceLimitExceeded", "$.disciplineIncidents");
  }
  const incidentIds = new Set<string>();
  const byTeam = new Map<string, Record<string, unknown>>();
  const byParticipant = new Map<string, Record<string, unknown>>();
  for (const participantId of participants.keys()) {
    byParticipant.set(participantId, {
      byType: {disqualifying: 0, personal: 0, technical: 0, unsportsmanlike: 0},
      chargedFouls: 0,
      playerDisqualificationCharges: 0,
      relatedIncidentIds: [],
    });
  }
  for (const teamEntryId of teams.keys()) {
    byTeam.set(teamEntryId, {
      byParty: {bench: 0, coach: 0, player: 0, team: 0},
      byType: {disqualifying: 0, personal: 0, technical: 0, unsportsmanlike: 0},
      chargedFouls: 0,
      playerDisqualificationCharges: 0,
      teamFoulsByPeriod: {},
    });
  }
  const incidents = rawIncidents.map((value, index) => {
    const path = `$.disciplineIncidents[${index}]`;
    const raw = record(value, path, [
      "chargedParticipantId", "chargedPartyKind", "clockRemainingMs",
      "countsTowardPlayerDisqualification", "countsTowardTeamFoul", "evidenceRefs",
      "incidentId", "incidentType", "periodNumber", "relatedParticipantId",
      "scoresheetCode", "teamEntryId",
    ]);
    const incidentId = identifier(raw.incidentId, `${path}.incidentId`);
    if (incidentIds.has(incidentId)) fail("invalidDisciplineIncident", `${path}.incidentId`);
    incidentIds.add(incidentId);
    const teamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
    if (!teams.has(teamEntryId)) fail("invalidDisciplineIncident", `${path}.teamEntryId`);
    const chargedPartyKind = enumeration(raw.chargedPartyKind, `${path}.chargedPartyKind`, [
      "player", "coach", "bench", "team",
    ] as const);
    const chargedParticipantId = fact(
      raw.chargedParticipantId,
      `${path}.chargedParticipantId`,
      identifier,
    );
    const relatedParticipantId = fact(
      raw.relatedParticipantId,
      `${path}.relatedParticipantId`,
      identifier,
    );
    if (chargedPartyKind === "player") {
      if (chargedParticipantId.state !== "known") fail("invalidDisciplineIncident", path);
      const participant = participants.get(chargedParticipantId.value);
      if (!participant || participant.teamEntryId !== teamEntryId) {
        fail("invalidDisciplineIncident", `${path}.chargedParticipantId`);
      }
    } else if (!absentFact(chargedParticipantId, "not_player_charge")) {
      fail("invalidDisciplineIncident", `${path}.chargedParticipantId`);
    }
    if (relatedParticipantId.state === "known") {
      const related = participants.get(relatedParticipantId.value);
      if (!related || related.teamEntryId !== teamEntryId) {
        fail("invalidDisciplineIncident", `${path}.relatedParticipantId`);
      }
    }
    const incidentType = enumeration(raw.incidentType, `${path}.incidentType`, [
      "personal", "technical", "unsportsmanlike", "disqualifying",
    ] as const);
    const scoresheetCode = textValue(raw.scoresheetCode, `${path}.scoresheetCode`, 64);
    const countsTowardTeamFoul = booleanValue(
      raw.countsTowardTeamFoul,
      `${path}.countsTowardTeamFoul`,
    );
    const countsTowardPlayerDisqualification = booleanValue(
      raw.countsTowardPlayerDisqualification,
      `${path}.countsTowardPlayerDisqualification`,
    );
    if (countsTowardPlayerDisqualification && chargedPartyKind !== "player") {
      fail("invalidDisciplineIncident", `${path}.countsTowardPlayerDisqualification`);
    }
    const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
    if (periodNumber.state === "known" && periodNumber.value === 0) {
      fail("invalidDisciplineIncident", `${path}.periodNumber`);
    }
    if (countsTowardTeamFoul && periodNumber.state !== "known") {
      fail("invalidDisciplineIncident", `${path}.periodNumber`);
    }
    const clockRemainingMs = fact(
      raw.clockRemainingMs,
      `${path}.clockRemainingMs`,
      nonnegativeInteger,
    );
    if (clockRemainingMs.state === "known" && periodNumber.state !== "known") {
      fail("eventClockOutsidePeriod", `${path}.clockRemainingMs`);
    }
    if (periodNumber.state === "known") {
      if (periodNumber.value > periods.length) {
        fail("invalidDisciplineIncident", `${path}.periodNumber`);
      }
      const duration = periods[periodNumber.value - 1].durationMs as ExplicitFact<number>;
      if (clockRemainingMs.state === "known" && duration.state === "known" &&
          clockRemainingMs.value > duration.value) {
        fail("eventClockOutsidePeriod", `${path}.clockRemainingMs`);
      }
    }
    const evidenceRefs = validateEvidenceFact(raw.evidenceRefs, `${path}.evidenceRefs`);
    if (evidenceRefs.state === "known" && evidenceRefs.value.length === 0) {
      fail("invalidDisciplineIncident", `${path}.evidenceRefs`);
    }
    const summary = byTeam.get(teamEntryId)!;
    const byParty = summary.byParty as Record<string, number>;
    const byType = summary.byType as Record<string, number>;
    byParty[chargedPartyKind] = safeAdd(byParty[chargedPartyKind], 1, path);
    byType[incidentType] = safeAdd(byType[incidentType], 1, path);
    summary.chargedFouls = safeAdd(summary.chargedFouls as number, 1, path);
    if (countsTowardPlayerDisqualification) {
      summary.playerDisqualificationCharges = safeAdd(
        summary.playerDisqualificationCharges as number,
        1,
        path,
      );
    }
    if (chargedPartyKind === "player" && chargedParticipantId.state === "known") {
      const participantSummary = byParticipant.get(chargedParticipantId.value)!;
      const participantByType = participantSummary.byType as Record<string, number>;
      participantByType[incidentType] = safeAdd(participantByType[incidentType], 1, path);
      participantSummary.chargedFouls = safeAdd(
        participantSummary.chargedFouls as number,
        1,
        path,
      );
      if (countsTowardPlayerDisqualification) {
        participantSummary.playerDisqualificationCharges = safeAdd(
          participantSummary.playerDisqualificationCharges as number,
          1,
          path,
        );
      }
    }
    if (relatedParticipantId.state === "known") {
      (byParticipant.get(relatedParticipantId.value)!.relatedIncidentIds as string[]).push(incidentId);
    }
    if (countsTowardTeamFoul && periodNumber.state === "known") {
      const teamFouls = summary.teamFoulsByPeriod as Record<string, number>;
      const key = String(periodNumber.value);
      teamFouls[key] = safeAdd(teamFouls[key] ?? 0, 1, path);
    }
    return {
      chargedParticipantId,
      chargedPartyKind,
      clockRemainingMs,
      countsTowardPlayerDisqualification,
      countsTowardTeamFoul,
      evidenceRefs,
      incidentId,
      incidentType,
      periodNumber,
      relatedParticipantId,
      scoresheetCode,
      teamEntryId,
    };
  });
  for (const summary of byTeam.values()) {
    const teamFouls = summary.teamFoulsByPeriod as Record<string, number>;
    const penaltyStateByPeriod: Record<string, unknown> = {};
    for (const period of periods) {
      const periodNumber = period.number as number;
      const threshold = period.kind === "regulation" ?
        penaltyThresholds.regulation : penaltyThresholds.overtime;
      penaltyStateByPeriod[String(periodNumber)] = threshold.state === "known" ? {
        state: "known",
        value: {
          inPenalty: (teamFouls[String(periodNumber)] ?? 0) >= threshold.value,
          teamFouls: teamFouls[String(periodNumber)] ?? 0,
          threshold: threshold.value,
        },
      } : threshold;
    }
    summary.penaltyStateByPeriod = penaltyStateByPeriod;
  }
  return {incidents, byParticipant, byTeam};
}

function validateAdministrativeResult(
  rawValue: unknown,
  disposition: NormalizedBoxScoreInput["resultDisposition"],
  teamIds: ReadonlySet<string>,
  homeTeamEntryId: string,
): Record<string, unknown> {
  const raw = record(rawValue, "$.administrativeResult", [
    "awardedScore", "evidenceRefs", "playerStatisticsTreatment",
    "standingsTreatment", "winnerTeamEntryId",
  ]);
  const awardedScore = fact(raw.awardedScore, "$.administrativeResult.awardedScore", scorePair);
  const winnerTeamEntryId = fact(
    raw.winnerTeamEntryId,
    "$.administrativeResult.winnerTeamEntryId",
    identifier,
  );
  const evidenceRefs = validateEvidenceFact(
    raw.evidenceRefs,
    "$.administrativeResult.evidenceRefs",
  );
  const standingsTreatment = enumeration(
    raw.standingsTreatment,
    "$.administrativeResult.standingsTreatment",
    ["playedResult", "awardedResult", "excluded", "policyPending"] as const,
  );
  const playerStatisticsTreatment = enumeration(
    raw.playerStatisticsTreatment,
    "$.administrativeResult.playerStatisticsTreatment",
    ["includePlayedStatistics", "exclude", "policyPending"] as const,
  );
  if (disposition === "played") {
    if (!absentFact(awardedScore, "not_adjudicated") ||
        !absentFact(winnerTeamEntryId, "not_adjudicated") ||
        !absentFact(evidenceRefs, "not_adjudicated") ||
        standingsTreatment !== "playedResult" ||
        playerStatisticsTreatment !== "includePlayedStatistics") {
      fail("invalidAdministrativeResult", "$.administrativeResult");
    }
  } else {
    if (winnerTeamEntryId.state === "known" && !teamIds.has(winnerTeamEntryId.value)) {
      fail("invalidAdministrativeResult", "$.administrativeResult.winnerTeamEntryId");
    }
    if (evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
      fail("invalidAdministrativeResult", "$.administrativeResult.evidenceRefs");
    }
    if ((disposition === "forfeit" || disposition === "default") &&
        (awardedScore.state !== "known" || winnerTeamEntryId.state !== "known")) {
      fail("invalidAdministrativeResult", "$.administrativeResult");
    }
    if (standingsTreatment === "awardedResult" &&
        (awardedScore.state !== "known" || winnerTeamEntryId.state !== "known")) {
      fail("invalidAdministrativeResult", "$.administrativeResult");
    }
    if (awardedScore.state === "known" && winnerTeamEntryId.state === "known") {
      const winnerIsHome = winnerTeamEntryId.value === homeTeamEntryId;
      const winnerScore = winnerIsHome ? awardedScore.value.home : awardedScore.value.away;
      const loserScore = winnerIsHome ? awardedScore.value.away : awardedScore.value.home;
      if (winnerScore <= loserScore) {
        fail("invalidAdministrativeResult", "$.administrativeResult.winnerTeamEntryId");
      }
    }
  }
  return {
    awardedScore,
    evidenceRefs,
    playerStatisticsTreatment,
    standingsTreatment,
    winnerTeamEntryId,
  };
}

function validateOfficialScore(rawValue: unknown, playedScore: ScorePair): Record<string, unknown> {
  const raw = record(rawValue, "$.officialScore", ["evidenceRefs", "reconciliationStatus", "score"]);
  const score = fact(raw.score, "$.officialScore.score", scorePair);
  const evidenceRefs = validateEvidenceFact(raw.evidenceRefs, "$.officialScore.evidenceRefs");
  const reconciliationStatus = enumeration(
    raw.reconciliationStatus,
    "$.officialScore.reconciliationStatus",
    ["reconciled", "unreconciled", "notAvailable"] as const,
  );
  if (reconciliationStatus !== "reconciled") {
    fail("officialScoreEvidenceRequired", "$.officialScore.reconciliationStatus");
  }
  if (reconciliationStatus === "reconciled") {
    if (score.state !== "known" || evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
      fail("officialScoreEvidenceRequired", "$.officialScore");
    }
    if (score.value.home !== playedScore.home || score.value.away !== playedScore.away) {
      fail("officialScoreMismatch", "$.officialScore.score");
    }
  }
  return {evidenceRefs, reconciliationStatus, score};
}

function validateRoot(rawValue: unknown): NormalizedBoxScoreInput {
  const raw = record(rawValue, "$", [
    "administrativeResult", "calculatorVersion", "canonicalEncodingVersion",
    "disciplineIncidents", "officialScore", "periods", "playedScore",
    "playedScoreAdjustments", "provenance", "resultDisposition", "rules",
    "schemaVersion", "scope", "statisticsDisposition", "teams", "unicodeNormalizationVersion",
  ]);
  if (raw.schemaVersion !== 1) fail("unsupportedSchemaVersion", "$.schemaVersion");
  if (raw.calculatorVersion !== normalizedBoxScoreCalculatorVersion) {
    fail("unsupportedCalculatorVersion", "$.calculatorVersion");
  }
  if (raw.canonicalEncodingVersion !== officialStatVersions.canonicalEncodingVersion) {
    fail("unsupportedCanonicalEncodingVersion", "$.canonicalEncodingVersion");
  }
  if (raw.unicodeNormalizationVersion !== normalizedBoxScoreUnicodeVersion) {
    fail("unsupportedUnicodeNormalizationVersion", "$.unicodeNormalizationVersion");
  }
  validateScope(raw.scope);
  enumeration(raw.resultDisposition, "$.resultDisposition", [
    "played", "forfeit", "default", "annulled", "otherAdjudicated",
  ] as const);
  if (raw.statisticsDisposition !== "complete") {
    fail("invalidShape", "$.statisticsDisposition");
  }
  const provenance = record(raw.provenance, "$.provenance", [
    "captureMode", "rulesetVersion", "sourceId", "sourceLabel",
  ]);
  enumeration(provenance.captureMode, "$.provenance.captureMode", [
    "liveCapture", "officialSheet", "historicalImport",
  ] as const);
  identifier(provenance.sourceId, "$.provenance.sourceId");
  textValue(provenance.sourceLabel, "$.provenance.sourceLabel");
  identifier(provenance.rulesetVersion, "$.provenance.rulesetVersion");
  const rules = record(raw.rules, "$.rules", [
    "completedTiesAllowed", "regulationPeriodCount", "teamFoulPenaltyThresholds",
  ]);
  const regulationPeriodCount = nonnegativeInteger(
    rules.regulationPeriodCount,
    "$.rules.regulationPeriodCount",
  );
  if (regulationPeriodCount === 0) fail("invalidPeriodSequence", "$.rules.regulationPeriodCount");
  booleanValue(rules.completedTiesAllowed, "$.rules.completedTiesAllowed");
  const penaltyThresholds = record(
    rules.teamFoulPenaltyThresholds,
    "$.rules.teamFoulPenaltyThresholds",
    ["overtime", "regulation"],
  );
  for (const kind of ["regulation", "overtime"] as const) {
    const threshold = countFact(
      penaltyThresholds[kind],
      `$.rules.teamFoulPenaltyThresholds.${kind}`,
    );
    if (threshold.state === "known" && threshold.value === 0) {
      fail("invalidDisciplineIncident", `$.rules.teamFoulPenaltyThresholds.${kind}`);
    }
  }
  const teams = array(raw.teams, "$.teams");
  if (teams.length !== 2) fail("invalidTeamStructure", "$.teams");
  return rawValue as NormalizedBoxScoreInput;
}

function calculateAccepted(rawInput: unknown): CalculatorAccepted {
  const input = validateRoot(rawInput);
  const scope = validateScope(input.scope);
  const seenParticipants = new Set<string>();
  const seenPlayers = new Set<string>();
  const teamResults = input.teams.map((team, index) =>
    validateTeam(team, `$.teams[${index}]`, seenParticipants, seenPlayers));
  if (teamResults[0].output.side === teamResults[1].output.side ||
      teamResults[0].output.teamEntryId === teamResults[1].output.teamEntryId) {
    fail("invalidTeamStructure", "$.teams");
  }
  teamResults.sort((left, right) =>
    left.output.side === "home" ? -1 : right.output.side === "home" ? 1 : 0);
  const homeTeam = teamResults[0];
  const awayTeam = teamResults[1];
  const rulesRaw = input.rules;
  const penaltyThresholds = {
    overtime: countFact(
      rulesRaw.teamFoulPenaltyThresholds.overtime,
      "$.rules.teamFoulPenaltyThresholds.overtime",
    ),
    regulation: countFact(
      rulesRaw.teamFoulPenaltyThresholds.regulation,
      "$.rules.teamFoulPenaltyThresholds.regulation",
    ),
  };
  const periodResult = validatePeriods(
    input.periods,
    rulesRaw.regulationPeriodCount,
    input.resultDisposition === "played",
  );
  validatePlayerTimeline(teamResults, periodResult.periods);
  const playedScore = scorePair(input.playedScore, "$.playedScore");
  if (periodResult.score.home !== playedScore.home || periodResult.score.away !== playedScore.away) {
    fail("playedScorePeriodMismatch", "$.playedScore");
  }
  if (input.resultDisposition === "played" && !rulesRaw.completedTiesAllowed &&
      playedScore.home === playedScore.away) {
    fail("invalidPeriodSequence", "$.playedScore");
  }

  const adjustmentValues = array(input.playedScoreAdjustments, "$.playedScoreAdjustments");
  if (adjustmentValues.length > normalizedBoxScoreLimits.maxPlayedScoreAdjustments) {
    fail("resourceLimitExceeded", "$.playedScoreAdjustments");
  }
  const adjustmentIds = new Set<string>();
  const adjustmentPoints = new Map<string, number>([
    [homeTeam.output.teamEntryId as string, 0],
    [awayTeam.output.teamEntryId as string, 0],
  ]);
  const adjustments = adjustmentValues.map((value, index) => {
    const path = `$.playedScoreAdjustments[${index}]`;
    const raw = record(value, path, [
      "adjustmentId", "evidenceRefs", "kind", "periodNumber", "points", "teamEntryId",
    ]);
    const adjustmentId = identifier(raw.adjustmentId, `${path}.adjustmentId`);
    if (adjustmentIds.has(adjustmentId)) fail("invalidScoreAdjustment", `${path}.adjustmentId`);
    adjustmentIds.add(adjustmentId);
    const teamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
    if (!adjustmentPoints.has(teamEntryId)) fail("invalidScoreAdjustment", `${path}.teamEntryId`);
    const kind = enumeration(raw.kind, `${path}.kind`, ["ownBasket", "goaltending"] as const);
    const points = nonnegativeInteger(raw.points, `${path}.points`);
    if (points === 0 || points > 3 || (kind === "ownBasket" && points !== 2)) {
      fail("invalidScoreAdjustment", `${path}.points`);
    }
    const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
    if (periodNumber.state !== "known" || periodNumber.value === 0 ||
        periodNumber.value > periodResult.periods.length) {
      fail("invalidScoreAdjustment", `${path}.periodNumber`);
    }
    const evidenceRefs = validateEvidenceFact(raw.evidenceRefs, `${path}.evidenceRefs`);
    if (evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
      fail("invalidScoreAdjustment", `${path}.evidenceRefs`);
    }
    adjustmentPoints.set(
      teamEntryId,
      safeAdd(adjustmentPoints.get(teamEntryId)!, points, `${path}.points`),
    );
    return {adjustmentId, evidenceRefs, kind, periodNumber, points, teamEntryId};
  });

  const attributedHome = safeAdd(
    (homeTeam.output.totals as Record<string, number>).points,
    adjustmentPoints.get(homeTeam.output.teamEntryId as string)!,
    "$.playedScore.home",
  );
  const attributedAway = safeAdd(
    (awayTeam.output.totals as Record<string, number>).points,
    adjustmentPoints.get(awayTeam.output.teamEntryId as string)!,
    "$.playedScore.away",
  );
  if (attributedHome !== playedScore.home || attributedAway !== playedScore.away) {
    fail("playedScoreAttributionMismatch", "$.playedScore");
  }

  const teamMap = new Map<string, Record<string, unknown>>([
    [homeTeam.output.teamEntryId as string, homeTeam.output],
    [awayTeam.output.teamEntryId as string, awayTeam.output],
  ]);
  const participantMap = new Map<string, {teamEntryId: string; enteredPlay: boolean}>();
  for (const team of teamResults) {
    for (const player of team.output.players as Record<string, unknown>[]) {
      participantMap.set(player.participantId as string, {
        enteredPlay: player.enteredPlay as boolean,
        teamEntryId: player.teamEntryId as string,
      });
    }
  }
  const discipline = validateDiscipline(
    input.disciplineIncidents,
    teamMap,
    participantMap,
    periodResult.periods,
    penaltyThresholds,
  );
  for (const team of teamResults) {
    team.output.discipline = discipline.byTeam.get(team.output.teamEntryId as string)!;
    for (const player of team.output.players as Record<string, unknown>[]) {
      player.discipline = discipline.byParticipant.get(player.participantId as string)!;
    }
  }
  const teamIds = new Set(teamMap.keys());
  const administrativeResult = validateAdministrativeResult(
    input.administrativeResult,
    input.resultDisposition,
    teamIds,
    homeTeam.output.teamEntryId as string,
  );
  const officialScore = validateOfficialScore(input.officialScore, playedScore);

  const diagnostics: CalculatorDiagnostic[] = [];
  const homeTotals = homeTeam.output.totals as Record<string, number>;
  const awayTotals = awayTeam.output.totals as Record<string, number>;
  if (homeTotals.steals > awayTotals.turnovers) {
    diagnostics.push({
      code: "crossTeamStealsVsTurnoversNeedsReview",
      opponentTurnovers: awayTotals.turnovers,
      path: `$.teams.${homeTeam.output.teamEntryId}.totals.steals`,
      severity: "evidenceReview",
      steals: homeTotals.steals,
    });
  }
  if (awayTotals.steals > homeTotals.turnovers) {
    diagnostics.push({
      code: "crossTeamStealsVsTurnoversNeedsReview",
      opponentTurnovers: homeTotals.turnovers,
      path: `$.teams.${awayTeam.output.teamEntryId}.totals.steals`,
      severity: "evidenceReview",
      steals: awayTotals.steals,
    });
  }
  diagnostics.sort((left, right) =>
    left.path < right.path ? -1 : left.path > right.path ? 1 : 0);

  const playedWinnerTeamEntryId: ExplicitFact<string> = playedScore.home === playedScore.away ?
    {state: "unknown", value: null, reasonCode: "tied_played_score"} :
    {
      state: "known",
      value: playedScore.home > playedScore.away ?
        homeTeam.output.teamEntryId as string : awayTeam.output.teamEntryId as string,
    };
  return {
    calculatorVersion: normalizedBoxScoreCalculatorVersion,
    normalizedBoxScore: {
      administrativeResult,
      canonicalEncodingVersion: officialStatVersions.canonicalEncodingVersion,
      diagnostics,
      disciplineIncidents: discipline.incidents,
      officialScore,
      periods: periodResult.periods,
      playedScore,
      playedScoreAdjustments: adjustments,
      playedWinnerTeamEntryId,
      provenance: {
        captureMode: input.provenance.captureMode,
        rulesetVersion: input.provenance.rulesetVersion,
        sourceId: input.provenance.sourceId,
        sourceLabel: input.provenance.sourceLabel.normalize("NFC"),
      },
      resultDisposition: input.resultDisposition,
      rules: {
        completedTiesAllowed: rulesRaw.completedTiesAllowed,
        regulationPeriodCount: rulesRaw.regulationPeriodCount,
        teamFoulPenaltyThresholds: penaltyThresholds,
      },
      schemaVersion: 1,
      scope,
      statisticsDisposition: input.statisticsDisposition,
      teams: teamResults.map((team) => team.output),
      unicodeNormalizationVersion: normalizedBoxScoreUnicodeVersion,
    },
    status: "accepted",
  };
}

/**
 * Pure, deterministic, fail-closed normalized box-score calculator.
 *
 * Validation returns exactly the first error in the documented validation
 * sequence. It never imports Firebase, performs I/O, or mutates its input.
 */
export function calculateNormalizedBoxScore(input: unknown): CalculatorOutcome {
  try {
    preflight(input);
    return calculateAccepted(input);
  } catch (error) {
    if (error instanceof ValidationFailure) {
      return {
        calculatorVersion: normalizedBoxScoreCalculatorVersion,
        errors: [{code: error.code, path: error.path}],
        status: "rejected",
      };
    }
    return {
      calculatorVersion: normalizedBoxScoreCalculatorVersion,
      errors: [{code: "invalidCanonicalValue", path: "$"}],
      status: "rejected",
    };
  }
}

export function assertCalculatorErrorVocabulary(): void {
  if (new Set(calculatorErrorCodes).size !== calculatorErrorCodes.length) {
    throw new Error("Calculator error codes must remain unique");
  }
  if (playerCounterSet.size !== playerCountFields.length) {
    throw new Error("Player counter fields must remain unique");
  }
}
