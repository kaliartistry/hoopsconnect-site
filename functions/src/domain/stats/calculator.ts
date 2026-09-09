import {
  normalizeOfficialStatText,
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
  type PlayerCountField,
  type ScorePair,
} from "./types";

export * from "./types";

export const normalizedBoxScoreLimits = {
  maxCanonicalPayloadBytes: 128 * 1024,
  maxRawTransportBytes: 128 * 1024,
  maxContainerEntries: 1024,
  maxObjectKeys: 128,
  maxDepth: 16,
  maxEvidenceRefsPerFact: 64,
  maxIncidents: 512,
  maxNodes: 20_000,
  maxPenaltyGroups: 64,
  maxPeriods: 64,
  maxPlayedScoreAdjustments: 128,
  maxPlayersPerTeam: 64,
  maxStringBytes: 1024,
} as const;

const opaqueId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const asciiKey = /^[\x21-\x7e]+$/;
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

/**
 * Performs bounded accounting before sorting or canonicalizing the full graph.
 * Every scalar is charged by its exact canonical byte length and containers are
 * width-limited before bounded key arrays are materialized.
 */
function preflight(value: unknown): void {
  let nodes = 0;
  let canonicalBytes = 0;
  const charge = (bytes: number, path: string): void => {
    canonicalBytes += bytes;
    if (canonicalBytes > normalizedBoxScoreLimits.maxCanonicalPayloadBytes) {
      fail("resourceLimitExceeded", path);
    }
  };
  const visit = (current: unknown, path: string, depth: number): void => {
    nodes += 1;
    if (nodes > normalizedBoxScoreLimits.maxNodes ||
        depth > normalizedBoxScoreLimits.maxDepth) {
      fail("resourceLimitExceeded", path);
    }
    if (current === null) {
      charge(4, path);
      return;
    }
    if (typeof current === "boolean") {
      charge(current ? 4 : 5, path);
      return;
    }
    if (typeof current === "string") {
      if (utf8Length(current) > normalizedBoxScoreLimits.maxStringBytes) {
        fail("resourceLimitExceeded", path);
      }
      charge(utf8Length(JSON.stringify(normalizeOfficialStatText(current))), path);
      return;
    }
    if (typeof current === "number") {
      if (!Number.isSafeInteger(current) || current < 0) {
        fail("invalidNonnegativeSafeInteger", path);
      }
      charge(utf8Length(JSON.stringify(current)), path);
      return;
    }
    if (Array.isArray(current)) {
      if (current.length > normalizedBoxScoreLimits.maxContainerEntries) {
        fail("resourceLimitExceeded", path);
      }
      if (Object.getPrototypeOf(current) !== Array.prototype ||
          Object.getOwnPropertySymbols(current).length !== 0) {
        fail("invalidCanonicalValue", path);
      }
      const ownNames = Object.getOwnPropertyNames(current);
      if (ownNames.length !== current.length + 1) fail("invalidCanonicalValue", path);
      charge(2 + Math.max(0, current.length - 1), path);
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
      if (prototype !== Object.prototype && prototype !== null) {
        fail("invalidCanonicalValue", path);
      }
      const record = current as Record<string, unknown>;
      const enumerableKeys: string[] = [];
      for (const key in record) {
        enumerableKeys.push(key);
        if (enumerableKeys.length > normalizedBoxScoreLimits.maxObjectKeys) {
          fail("resourceLimitExceeded", path);
        }
      }
      if (Object.getOwnPropertySymbols(record).length !== 0 ||
          Object.getOwnPropertyNames(record).length !== enumerableKeys.length) {
        fail("invalidCanonicalValue", path);
      }
      enumerableKeys.sort();
      charge(2 + Math.max(0, enumerableKeys.length - 1), path);
      for (const key of enumerableKeys) {
        if (!asciiKey.test(key)) fail("invalidCanonicalValue", path);
        if (utf8Length(key) > normalizedBoxScoreLimits.maxStringBytes) {
          fail("resourceLimitExceeded", path);
        }
        const descriptor = Object.getOwnPropertyDescriptor(record, key);
        if (!descriptor || !("value" in descriptor) || !descriptor.enumerable) {
          fail("invalidCanonicalValue", `${path}.${key}`);
        }
        charge(utf8Length(JSON.stringify(key)) + 1, path);
        visit(descriptor.value, `${path}.${key}`, depth + 1);
      }
      return;
    }
    fail("invalidCanonicalValue", path);
  };
  visit(value, "$", 0);
}

function sortedObjectKeys(value: Record<string, unknown>): string[] {
  return Object.keys(value).sort();
}

function record(
  value: unknown,
  path: string,
  exactKeys?: readonly string[],
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("invalidShape", path);
  }
  const result = value as Record<string, unknown>;
  if (exactKeys) {
    const actual = sortedObjectKeys(result);
    const expected = [...exactKeys].sort();
    if (actual.length !== expected.length ||
        actual.some((key, index) => key !== expected[index])) {
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
  const normalized = normalizeOfficialStatText(value);
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

function positiveInteger(value: unknown, path: string): number {
  const parsed = nonnegativeInteger(value, path);
  if (parsed === 0) fail("invalidNonnegativeSafeInteger", path);
  return parsed;
}

function booleanValue(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") fail("invalidShape", path);
  return value;
}

function enumeration<T extends string>(
  value: unknown,
  path: string,
  values: readonly T[],
): T {
  if (typeof value !== "string" || !values.includes(value as T)) {
    fail("invalidShape", path);
  }
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
    if (raw.reasonCode !== null &&
        (typeof raw.reasonCode !== "string" || raw.reasonCode.length === 0)) {
      fail("invalidFact", `${path}.reasonCode`);
    }
    return {
      state: "unknown",
      value: null,
      reasonCode: raw.reasonCode === null ?
        null : textValue(raw.reasonCode, `${path}.reasonCode`),
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

function countFact(value: unknown, path: string): ExplicitFact<number> {
  return fact(value, path, nonnegativeInteger);
}

function knownCount(value: unknown, path: string): number {
  const parsed = countFact(value, path);
  if (parsed.state !== "known") fail("requiredKnownCount", path);
  return parsed.value;
}

function absentFact(value: ExplicitFact<unknown>, reason: string): boolean {
  return value.state === "notApplicable" && value.reasonCode === reason;
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

function stringList(value: unknown, path: string): string[] {
  const raw = array(value, path);
  if (raw.length > normalizedBoxScoreLimits.maxEvidenceRefsPerFact) {
    fail("resourceLimitExceeded", path);
  }
  return raw.map((item, index) => textValue(item, `${path}[${index}]`));
}

function evidenceFact(value: unknown, path: string): ExplicitFact<string[]> {
  return fact(value, path, stringList);
}

function scorePair(value: unknown, path: string): ScorePair {
  const raw = record(value, path, ["away", "home"]);
  return {
    away: nonnegativeInteger(raw.away, `${path}.away`),
    home: nonnegativeInteger(raw.home, `${path}.home`),
  };
}

function zeroCounts(): Record<PlayerCountField, number> {
  return Object.fromEntries(playerCountFields.map((field) => [field, 0])) as
    Record<PlayerCountField, number>;
}

function parseCounts(rawValue: unknown, path: string): Record<PlayerCountField, number> {
  const raw = record(rawValue, path, playerCountFields);
  const result = zeroCounts();
  for (const field of playerCountFields) {
    result[field] = knownCount(raw[field], `${path}.${field}`);
  }
  return result;
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
  const ratio = (
    makes: number,
    attempts: number,
  ): ExplicitFact<Record<string, number>> => attempts === 0 ?
    {state: "unknown", value: null, reasonCode: "zero_attempts"} :
    {state: "known", value: {attempts, makes}};
  return {
    field: ratio(totals.fieldMade, totals.fieldAttempted),
    free: ratio(totals.freeMade, totals.freeAttempted),
    three: ratio(totals.threeMade, totals.threeAttempted),
    two: ratio(totals.twoMade, totals.twoAttempted),
  };
}

interface ParsedRules {
  completedTiesAllowed: boolean;
  exceptionalScoringProfile: "fiba-2024-reference-attribution-v1";
  overtimePolicy: {
    allowed: boolean;
    nominalDurationMs: ExplicitFact<number>;
  };
  penaltyAccumulationGroups: Array<{
    groupId: string;
    penaltyStartsAtFoul: ExplicitFact<number>;
    periodNumbers: number[];
  }>;
  playingTimeRoundingProfile:
    | "nearest-half-up-v1"
    | "fiba-2024-reference-sheet-v1";
  regulationPeriodCount: number;
  rulesProfileId: "generic-explicit-v2" | "fiba-2024-reference-v1";
  teamTimeCapacityMultiplier: ExplicitFact<number>;
}

function validateRules(value: unknown): ParsedRules {
  const raw = record(value, "$.rules", [
    "completedTiesAllowed", "exceptionalScoringProfile", "overtimePolicy",
    "penaltyAccumulationGroups", "playingTimeRoundingProfile",
    "regulationPeriodCount", "rulesProfileId", "teamTimeCapacityMultiplier",
  ]);
  const rulesProfileId = enumeration(raw.rulesProfileId, "$.rules.rulesProfileId", [
    "generic-explicit-v2", "fiba-2024-reference-v1",
  ] as const);
  const regulationPeriodCount = positiveInteger(
    raw.regulationPeriodCount,
    "$.rules.regulationPeriodCount",
  );
  const completedTiesAllowed = booleanValue(
    raw.completedTiesAllowed,
    "$.rules.completedTiesAllowed",
  );
  const overtimeRaw = record(raw.overtimePolicy, "$.rules.overtimePolicy", [
    "allowed", "nominalDurationMs",
  ]);
  const overtimePolicy = {
    allowed: booleanValue(overtimeRaw.allowed, "$.rules.overtimePolicy.allowed"),
    nominalDurationMs: countFact(
      overtimeRaw.nominalDurationMs,
      "$.rules.overtimePolicy.nominalDurationMs",
    ),
  };
  if (overtimePolicy.allowed) {
    if (overtimePolicy.nominalDurationMs.state !== "known" ||
        overtimePolicy.nominalDurationMs.value === 0) {
      fail("invalidRulesProfile", "$.rules.overtimePolicy.nominalDurationMs");
    }
  } else if (!absentFact(overtimePolicy.nominalDurationMs, "overtime_not_allowed")) {
    fail("invalidRulesProfile", "$.rules.overtimePolicy.nominalDurationMs");
  }
  const teamTimeCapacityMultiplier = countFact(
    raw.teamTimeCapacityMultiplier,
    "$.rules.teamTimeCapacityMultiplier",
  );
  if (teamTimeCapacityMultiplier.state === "known" &&
      teamTimeCapacityMultiplier.value === 0) {
    fail("invalidRulesProfile", "$.rules.teamTimeCapacityMultiplier");
  }
  const playingTimeRoundingProfile = enumeration(
    raw.playingTimeRoundingProfile,
    "$.rules.playingTimeRoundingProfile",
    ["nearest-half-up-v1", "fiba-2024-reference-sheet-v1"] as const,
  );
  const exceptionalScoringProfile = enumeration(
    raw.exceptionalScoringProfile,
    "$.rules.exceptionalScoringProfile",
    ["fiba-2024-reference-attribution-v1"] as const,
  );
  const groupsRaw = array(raw.penaltyAccumulationGroups, "$.rules.penaltyAccumulationGroups");
  if (groupsRaw.length > normalizedBoxScoreLimits.maxPenaltyGroups) {
    fail("resourceLimitExceeded", "$.rules.penaltyAccumulationGroups");
  }
  const groupIds = new Set<string>();
  const penaltyAccumulationGroups = groupsRaw.map((groupValue, index) => {
    const path = `$.rules.penaltyAccumulationGroups[${index}]`;
    const group = record(groupValue, path, [
      "groupId", "penaltyStartsAtFoul", "periodNumbers",
    ]);
    const groupId = identifier(group.groupId, `${path}.groupId`);
    if (groupIds.has(groupId)) fail("invalidPenaltyPolicy", `${path}.groupId`);
    groupIds.add(groupId);
    const periodValues = array(group.periodNumbers, `${path}.periodNumbers`);
    if (periodValues.length === 0 || periodValues.length > normalizedBoxScoreLimits.maxPeriods) {
      fail("invalidPenaltyPolicy", `${path}.periodNumbers`);
    }
    const periodNumbers = periodValues.map((number, numberIndex) =>
      positiveInteger(number, `${path}.periodNumbers[${numberIndex}]`));
    for (let i = 1; i < periodNumbers.length; i += 1) {
      if (periodNumbers[i] <= periodNumbers[i - 1]) {
        fail("invalidPenaltyPolicy", `${path}.periodNumbers`);
      }
    }
    const penaltyStartsAtFoul = countFact(
      group.penaltyStartsAtFoul,
      `${path}.penaltyStartsAtFoul`,
    );
    if (penaltyStartsAtFoul.state === "notApplicable" ||
        (penaltyStartsAtFoul.state === "known" && penaltyStartsAtFoul.value === 0)) {
      fail("invalidPenaltyPolicy", `${path}.penaltyStartsAtFoul`);
    }
    return {groupId, penaltyStartsAtFoul, periodNumbers};
  });
  if (rulesProfileId === "fiba-2024-reference-v1") {
    if (regulationPeriodCount !== 4 || completedTiesAllowed ||
        !overtimePolicy.allowed ||
        overtimePolicy.nominalDurationMs.state !== "known" ||
        overtimePolicy.nominalDurationMs.value !== 300000 ||
        teamTimeCapacityMultiplier.state !== "known" ||
        teamTimeCapacityMultiplier.value !== 5 ||
        playingTimeRoundingProfile !== "fiba-2024-reference-sheet-v1") {
      fail("invalidRulesProfile", "$.rules");
    }
  }
  return {
    completedTiesAllowed,
    exceptionalScoringProfile,
    overtimePolicy,
    penaltyAccumulationGroups,
    playingTimeRoundingProfile,
    regulationPeriodCount,
    rulesProfileId,
    teamTimeCapacityMultiplier,
  };
}

interface ParsedTime extends Record<string, unknown> {
  playedTimeMs: ExplicitFact<number>;
  roundingMode: string;
  timePrecisionMs: ExplicitFact<number>;
  timeSource: string;
}

function validateTime(
  rawValue: unknown,
  path: string,
  enteredPlay: boolean,
  roundingProfile: ParsedRules["playingTimeRoundingProfile"],
): ParsedTime {
  const raw = record(rawValue, path, [
    "playedTimeMs", "roundingMode", "timePrecisionMs", "timeSource",
  ]);
  const playedTimeMs = countFact(raw.playedTimeMs, `${path}.playedTimeMs`);
  const timePrecisionMs = countFact(raw.timePrecisionMs, `${path}.timePrecisionMs`);
  const timeSource = enumeration(raw.timeSource, `${path}.timeSource`, [
    "liveClock", "officialSheetExact", "officialSheetRounded", "notRecorded",
    "notApplicable",
  ] as const);
  const roundingMode = enumeration(raw.roundingMode, `${path}.roundingMode`, [
    "nearestHalfUp", "fiba2024ReferenceSheet", "notApplicable",
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
  if (timeSource === "officialSheetRounded") {
    const expectedMode = roundingProfile === "nearest-half-up-v1" ?
      "nearestHalfUp" : "fiba2024ReferenceSheet";
    if (roundingMode !== expectedMode || playedTimeMs.value % timePrecisionMs.value !== 0) {
      fail("invalidTimeProvenance", path);
    }
    if (roundingProfile === "fiba-2024-reference-sheet-v1" &&
        timePrecisionMs.value !== 60000) {
      fail("invalidTimeProvenance", `${path}.timePrecisionMs`);
    }
  } else if (roundingMode !== "notApplicable") {
    fail("invalidTimeProvenance", path);
  }
  return {playedTimeMs, roundingMode, timePrecisionMs, timeSource};
}

function validateDeparture(rawValue: unknown, path: string): Record<string, unknown> {
  const raw = record(rawValue, path, [
    "clockRemainingMs", "evidenceRefs", "kind", "periodNumber",
  ]);
  const kind = enumeration(raw.kind, `${path}.kind`, [
    "none", "fouledOut", "ejected", "injured", "other",
  ] as const);
  const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
  const clockRemainingMs = fact(
    raw.clockRemainingMs,
    `${path}.clockRemainingMs`,
    nonnegativeInteger,
  );
  const evidenceRefs = evidenceFact(raw.evidenceRefs, `${path}.evidenceRefs`);
  if (kind === "none") {
    if (!absentFact(periodNumber, "no_departure") ||
        !absentFact(clockRemainingMs, "no_departure") ||
        !absentFact(evidenceRefs, "no_departure")) {
      fail("invalidDeparture", path);
    }
  } else {
    if (periodNumber.state === "notApplicable" ||
        clockRemainingMs.state === "notApplicable" ||
        evidenceRefs.state !== "known" || evidenceRefs.value.length === 0 ||
        (periodNumber.state === "known" && periodNumber.value === 0)) {
      fail("invalidDeparture", path);
    }
  }
  return {clockRemainingMs, evidenceRefs, kind, periodNumber};
}

interface TeamResult {
  counts: Record<PlayerCountField, number>;
  output: Record<string, unknown>;
}

function validatePlayer(
  rawValue: unknown,
  path: string,
  teamEntryId: string,
  roundingProfile: ParsedRules["playingTimeRoundingProfile"],
): {counts: Record<PlayerCountField, number>; output: Record<string, unknown>} {
  const raw = record(rawValue, path, [
    "counts", "departure", "enteredPlay", "participantId", "participationStatus",
    "participationReasonCode", "playerId", "rosterMembershipId",
    "rosterMembershipVersionId", "starter", "teamEntryId", "time",
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
  if ((participationStatus === "active") !== enteredPlay) fail("invalidParticipation", path);
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
  if (counts.freeMade > counts.freeAttempted) {
    fail("makesExceedAttempts", `${path}.counts.freeMade`);
  }
  const time = validateTime(raw.time, `${path}.time`, enteredPlay, roundingProfile);
  const departure = validateDeparture(raw.departure, `${path}.departure`);
  if (!enteredPlay && departure.kind !== "none") fail("invalidDeparture", `${path}.departure`);
  const totals = derivedTotals(counts);
  return {
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
      shootingPercentages: shootingPercentages(totals),
      starter,
      teamEntryId,
      time,
      totals,
    },
  };
}

function validateTeam(
  rawValue: unknown,
  path: string,
  seenParticipants: Set<string>,
  seenPlayers: Set<string>,
  roundingProfile: ParsedRules["playingTimeRoundingProfile"],
): TeamResult {
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
    const parsed = validatePlayer(
      player,
      `${path}.players[${index}]`,
      teamEntryId,
      roundingProfile,
    );
    const participantId = parsed.output.participantId as string;
    const playerId = parsed.output.playerId as string;
    if (seenParticipants.has(participantId) || seenPlayers.has(playerId)) {
      fail("duplicateParticipant", `${path}.players[${index}]`);
    }
    seenParticipants.add(participantId);
    seenPlayers.add(playerId);
    addCounts(counts, parsed.counts, `${path}.players`);
    return parsed.output;
  });
  const teamOnlyRaw = record(raw.teamOnly, `${path}.teamOnly`, [
    "defensiveRebounds", "offensiveRebounds", "turnovers",
  ]);
  const teamOnly = {
    defensiveRebounds: knownCount(teamOnlyRaw.defensiveRebounds, `${path}.teamOnly.defensiveRebounds`),
    offensiveRebounds: knownCount(teamOnlyRaw.offensiveRebounds, `${path}.teamOnly.offensiveRebounds`),
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
    counts,
    output: {
      players,
      shootingPercentages: shootingPercentages(totals),
      side,
      teamEntryId,
      teamOnly,
      totals,
    },
  };
}

interface PeriodResult {
  counterPoints: ScorePair;
  periods: Record<string, unknown>[];
  score: ScorePair;
  totalElapsedMs: ExplicitFact<number>;
}

function validatePeriods(
  rawValue: unknown,
  rules: ParsedRules,
  requiresCompletePlay: boolean,
): PeriodResult {
  const rawPeriods = array(rawValue, "$.periods");
  if (rawPeriods.length > normalizedBoxScoreLimits.maxPeriods) {
    fail("resourceLimitExceeded", "$.periods");
  }
  if (requiresCompletePlay && rawPeriods.length < rules.regulationPeriodCount) {
    fail("invalidPeriodSequence", "$.periods");
  }
  const score: ScorePair = {away: 0, home: 0};
  const counterPoints: ScorePair = {away: 0, home: 0};
  let totalElapsed: number | null = 0;
  let cumulativeHome = 0;
  let cumulativeAway = 0;
  const periods = rawPeriods.map((value, index) => {
    const path = `$.periods[${index}]`;
    const raw = record(value, path, [
      "awayScore", "completionState", "elapsedDurationMs",
      "exceptionalScoringPoints", "homeScore", "kind", "nominalDurationMs",
      "number", "overtimeIndex", "playerCounterPoints", "source",
    ]);
    const number = positiveInteger(raw.number, `${path}.number`);
    if (number !== index + 1) fail("invalidPeriodSequence", `${path}.number`);
    const kind = enumeration(raw.kind, `${path}.kind`, ["regulation", "overtime"] as const);
    const overtimeIndex = fact(raw.overtimeIndex, `${path}.overtimeIndex`, nonnegativeInteger);
    if (number <= rules.regulationPeriodCount) {
      if (kind !== "regulation" || !absentFact(overtimeIndex, "regulation_period")) {
        fail("invalidPeriodSequence", path);
      }
    } else {
      const expectedOvertime = number - rules.regulationPeriodCount;
      if (!rules.overtimePolicy.allowed || kind !== "overtime" ||
          overtimeIndex.state !== "known" || overtimeIndex.value !== expectedOvertime) {
        fail("invalidOvertimeSequence", path);
      }
    }
    const nominalDurationMs = countFact(raw.nominalDurationMs, `${path}.nominalDurationMs`);
    if (nominalDurationMs.state !== "known" || nominalDurationMs.value === 0) {
      fail("invalidPeriodState", `${path}.nominalDurationMs`);
    }
    if (kind === "overtime" &&
        (rules.overtimePolicy.nominalDurationMs.state !== "known" ||
         nominalDurationMs.value !== rules.overtimePolicy.nominalDurationMs.value)) {
      fail("invalidOvertimeSequence", `${path}.nominalDurationMs`);
    }
    const elapsedDurationMs = countFact(raw.elapsedDurationMs, `${path}.elapsedDurationMs`);
    const completionState = enumeration(raw.completionState, `${path}.completionState`, [
      "completed", "partial", "suspended", "resumedCompleted", "abandoned", "adjudicated",
    ] as const);
    if (completionState === "completed" || completionState === "resumedCompleted") {
      if (elapsedDurationMs.state !== "known" ||
          elapsedDurationMs.value !== nominalDurationMs.value) {
        fail("invalidPeriodState", `${path}.elapsedDurationMs`);
      }
    } else {
      if (elapsedDurationMs.state === "notApplicable" ||
          (elapsedDurationMs.state === "known" &&
           elapsedDurationMs.value > nominalDurationMs.value)) {
        fail("invalidPeriodState", `${path}.elapsedDurationMs`);
      }
      if (index !== rawPeriods.length - 1) fail("invalidPeriodState", `${path}.completionState`);
    }
    if (requiresCompletePlay && completionState !== "completed" &&
        completionState !== "resumedCompleted") {
      fail("invalidPeriodState", `${path}.completionState`);
    }
    const homeScore = nonnegativeInteger(raw.homeScore, `${path}.homeScore`);
    const awayScore = nonnegativeInteger(raw.awayScore, `${path}.awayScore`);
    const playerCounterPoints = scorePair(raw.playerCounterPoints, `${path}.playerCounterPoints`);
    const exceptionalScoringPoints = scorePair(
      raw.exceptionalScoringPoints,
      `${path}.exceptionalScoringPoints`,
    );
    if (playerCounterPoints.home !== homeScore || playerCounterPoints.away !== awayScore ||
        exceptionalScoringPoints.home > playerCounterPoints.home ||
        exceptionalScoringPoints.away > playerCounterPoints.away) {
      fail("playedScoreAttributionMismatch", path);
    }
    score.home = safeAdd(score.home, homeScore, "$.periods.homeScore");
    score.away = safeAdd(score.away, awayScore, "$.periods.awayScore");
    counterPoints.home = safeAdd(
      counterPoints.home,
      playerCounterPoints.home,
      "$.periods.playerCounterPoints.home",
    );
    counterPoints.away = safeAdd(
      counterPoints.away,
      playerCounterPoints.away,
      "$.periods.playerCounterPoints.away",
    );
    cumulativeHome = safeAdd(cumulativeHome, homeScore, "$.periods.homeScore");
    cumulativeAway = safeAdd(cumulativeAway, awayScore, "$.periods.awayScore");
    if (kind === "overtime" && index < rawPeriods.length - 1 &&
        cumulativeHome !== cumulativeAway) {
      fail("invalidOvertimeSequence", path);
    }
    if (number === rules.regulationPeriodCount && rawPeriods.length > number &&
        cumulativeHome !== cumulativeAway) {
      fail("invalidOvertimeSequence", path);
    }
    if (totalElapsed !== null) {
      if (elapsedDurationMs.state === "known") {
        totalElapsed = safeAdd(totalElapsed, elapsedDurationMs.value, "$.periods.elapsedDurationMs");
      } else {
        totalElapsed = null;
      }
    }
    const source = enumeration(raw.source, `${path}.source`, [
      "liveCounter", "officialSheet", "historicalEvidence",
    ] as const);
    return {
      awayScore,
      completionState,
      elapsedDurationMs,
      exceptionalScoringPoints,
      homeScore,
      kind,
      nominalDurationMs,
      number,
      overtimeIndex,
      playerCounterPoints,
      source,
    };
  });
  return {
    counterPoints,
    periods,
    score,
    totalElapsedMs: totalElapsed === null ?
      {state: "unknown", value: null, reasonCode: "elapsed_duration_unknown"} :
      {state: "known", value: totalElapsed},
  };
}

interface PenaltyGroup {
  groupId: string;
  penaltyStartsAtFoul: ExplicitFact<number>;
  periodNumbers: number[];
}

function validatePenaltyGroups(
  rules: ParsedRules,
  periods: readonly Record<string, unknown>[],
): {groups: PenaltyGroup[]; groupByPeriod: Map<number, PenaltyGroup>} {
  const groupByPeriod = new Map<number, PenaltyGroup>();
  for (let groupIndex = 0; groupIndex < rules.penaltyAccumulationGroups.length; groupIndex += 1) {
    const group = rules.penaltyAccumulationGroups[groupIndex];
    for (const periodNumber of group.periodNumbers) {
      if (periodNumber > periods.length || groupByPeriod.has(periodNumber)) {
        fail(
          "invalidPenaltyPolicy",
          `$.rules.penaltyAccumulationGroups[${groupIndex}].periodNumbers`,
        );
      }
      groupByPeriod.set(periodNumber, group);
    }
  }
  for (let number = 1; number <= periods.length; number += 1) {
    if (!groupByPeriod.has(number)) {
      fail("invalidPenaltyPolicy", "$.rules.penaltyAccumulationGroups");
    }
  }
  if (periods.length === 0 && rules.penaltyAccumulationGroups.length !== 0) {
    fail("invalidPenaltyPolicy", "$.rules.penaltyAccumulationGroups");
  }
  if (rules.rulesProfileId === "fiba-2024-reference-v1") {
    const expected = periods.length === 0 ? [] : [
      [1],
      ...(periods.length >= 2 ? [[2]] : []),
      ...(periods.length >= 3 ? [[3]] : []),
      ...(periods.length >= 4 ? [Array.from({length: periods.length - 3}, (_, index) => index + 4)] : []),
    ];
    if (rules.penaltyAccumulationGroups.length !== expected.length) {
      fail("invalidPenaltyPolicy", "$.rules.penaltyAccumulationGroups");
    }
    for (let index = 0; index < expected.length; index += 1) {
      const group = rules.penaltyAccumulationGroups[index];
      if (group.periodNumbers.length !== expected[index].length ||
          group.periodNumbers.some((number, numberIndex) => number !== expected[index][numberIndex]) ||
          group.penaltyStartsAtFoul.state !== "known" ||
          group.penaltyStartsAtFoul.value !== 5) {
        fail("invalidPenaltyPolicy", `$.rules.penaltyAccumulationGroups[${index}]`);
      }
    }
  }
  return {groups: rules.penaltyAccumulationGroups, groupByPeriod};
}

function roundedTimeInterval(
  time: ParsedTime,
  profile: ParsedRules["playingTimeRoundingProfile"],
  totalElapsedMs: ExplicitFact<number>,
  path: string,
): ExplicitFact<Record<string, number>> {
  if (time.possibleIntervalMs) {
    return time.possibleIntervalMs as ExplicitFact<Record<string, number>>;
  }
  const played = (time.playedTimeMs as {state: "known"; value: number}).value;
  const precision = (time.timePrecisionMs as {state: "known"; value: number}).value;
  if (time.timeSource !== "officialSheetRounded") {
    return {
      state: "known",
      value: {
        lowerInclusive: played,
        upperExclusive: safeAdd(played, precision, path),
      },
    };
  }
  if (profile === "nearest-half-up-v1") {
    return {
      state: "known",
      value: {
        lowerInclusive: Math.max(0, played - Math.floor(precision / 2)),
        upperExclusive: safeAdd(played, Math.ceil(precision / 2), path),
      },
    };
  }
  if (totalElapsedMs.state !== "known") fail("invalidTimeProvenance", path);
  const maximum = totalElapsedMs.value;
  if (played === 0 || played > maximum || precision !== 60000) {
    fail("invalidTimeProvenance", path);
  }
  let lowerInclusive = Math.max(1, played - 30000);
  let upperExclusive = Math.min(safeAdd(maximum, 1, path), safeAdd(played, 30000, path));
  if (played === 60000) lowerInclusive = 1;
  if (maximum % 60000 === 0 && played === maximum - 60000) {
    lowerInclusive = Math.max(1, played - 30000);
    upperExclusive = maximum;
  }
  if (played === maximum) {
    lowerInclusive = maximum;
    upperExclusive = safeAdd(maximum, 1, path);
  }
  if (lowerInclusive >= upperExclusive) fail("invalidTimeProvenance", path);
  return {state: "known", value: {lowerInclusive, upperExclusive}};
}

function knownElapsedBefore(
  periods: readonly Record<string, unknown>[],
  periodNumber: number,
): number | null {
  let elapsed = 0;
  for (let index = 0; index < periodNumber - 1; index += 1) {
    const factValue = periods[index].elapsedDurationMs as ExplicitFact<number>;
    if (factValue.state !== "known") return null;
    elapsed = safeAdd(elapsed, factValue.value, "$.periods.elapsedDurationMs");
  }
  return elapsed;
}

function validatePlayerTimeline(
  teams: readonly TeamResult[],
  periods: readonly Record<string, unknown>[],
  totalElapsedMs: ExplicitFact<number>,
  rules: ParsedRules,
): void {
  for (const team of teams) {
    for (const player of team.output.players as Record<string, unknown>[]) {
      const time = player.time as ParsedTime;
      const path = `$.participants.${player.participantId}.time`;
      const interval = roundedTimeInterval(time, rules.playingTimeRoundingProfile, totalElapsedMs, path);
      time.possibleIntervalMs = interval;
      if (totalElapsedMs.state === "known" && interval.state === "known" &&
          interval.value.lowerInclusive > totalElapsedMs.value) {
        fail("timeOutsideGameDuration", path);
      }
      const departure = player.departure as Record<string, unknown>;
      if (departure.kind === "none") continue;
      const periodNumber = departure.periodNumber as ExplicitFact<number>;
      const clock = departure.clockRemainingMs as ExplicitFact<number>;
      if (clock.state === "known" && periodNumber.state !== "known") {
        fail("eventClockOutsidePeriod", `$.participants.${player.participantId}.departure`);
      }
      if (periodNumber.state !== "known") continue;
      if (periodNumber.value === 0 || periodNumber.value > periods.length) {
        fail("invalidDeparture", `$.participants.${player.participantId}.departure.periodNumber`);
      }
      const period = periods[periodNumber.value - 1];
      const nominal = period.nominalDurationMs as ExplicitFact<number>;
      const elapsed = period.elapsedDurationMs as ExplicitFact<number>;
      if (clock.state === "known") {
        if (nominal.state !== "known" || clock.value > nominal.value) {
          fail(
            "eventClockOutsidePeriod",
            `$.participants.${player.participantId}.departure.clockRemainingMs`,
          );
        }
        const elapsedAtDeparture = nominal.value - clock.value;
        if (elapsed.state === "known" && elapsedAtDeparture > elapsed.value) {
          fail(
            "eventClockOutsidePeriod",
            `$.participants.${player.participantId}.departure.clockRemainingMs`,
          );
        }
        const before = knownElapsedBefore(periods, periodNumber.value);
        if (before !== null && interval.state === "known") {
          const opportunity = safeAdd(
            before,
            elapsedAtDeparture,
            `$.participants.${player.participantId}.departure`,
          );
          if (interval.value.lowerInclusive > opportunity) {
            fail("departureTimeConflict", `$.participants.${player.participantId}.time`);
          }
        }
      }
    }
  }
}

interface ParticipantRef {
  counts: Record<string, number>;
  enteredPlay: boolean;
  output: Record<string, unknown>;
  teamEntryId: string;
}

function validateScoreAdjustments(
  rawValue: unknown,
  periods: readonly Record<string, unknown>[],
  teams: ReadonlySet<string>,
  participants: ReadonlyMap<string, ParticipantRef>,
): Record<string, unknown>[] {
  const rawAdjustments = array(rawValue, "$.playedScoreAdjustments");
  if (rawAdjustments.length > normalizedBoxScoreLimits.maxPlayedScoreAdjustments) {
    fail("resourceLimitExceeded", "$.playedScoreAdjustments");
  }
  const adjustmentIds = new Set<string>();
  const requiredShots = new Map<string, {three: number; two: number}>();
  const adjustments = rawAdjustments.map((value, index) => {
    const path = `$.playedScoreAdjustments[${index}]`;
    const raw = record(value, path, [
      "adjustmentId", "creditedParticipantId", "creditedShot", "evidenceRefs",
      "kind", "periodNumber", "points", "statisticalTreatment", "teamEntryId",
      "violatingTeamEntryId",
    ]);
    const adjustmentId = identifier(raw.adjustmentId, `${path}.adjustmentId`);
    if (adjustmentIds.has(adjustmentId)) fail("invalidScoreAdjustment", `${path}.adjustmentId`);
    adjustmentIds.add(adjustmentId);
    const teamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
    const violatingTeamEntryId = identifier(
      raw.violatingTeamEntryId,
      `${path}.violatingTeamEntryId`,
    );
    if (!teams.has(teamEntryId) || !teams.has(violatingTeamEntryId) ||
        teamEntryId === violatingTeamEntryId) {
      fail("invalidScoreAdjustment", `${path}.violatingTeamEntryId`);
    }
    const kind = enumeration(raw.kind, `${path}.kind`, [
      "accidentalOwnBasket", "defensiveGoaltending",
    ] as const);
    const points = positiveInteger(raw.points, `${path}.points`);
    const creditedShot = enumeration(raw.creditedShot, `${path}.creditedShot`, [
      "twoPointMade", "threePointMade",
    ] as const);
    if ((kind === "accidentalOwnBasket" && (points !== 2 || creditedShot !== "twoPointMade")) ||
        (kind === "defensiveGoaltending" &&
         ((points === 2 && creditedShot !== "twoPointMade") ||
          (points === 3 && creditedShot !== "threePointMade") ||
          (points !== 2 && points !== 3)))) {
      fail("invalidScoreAdjustment", `${path}.points`);
    }
    const statisticalTreatment = enumeration(
      raw.statisticalTreatment,
      `${path}.statisticalTreatment`,
      ["includedInPlayerCounters", "additiveToPlayerCounters"] as const,
    );
    if (statisticalTreatment !== "includedInPlayerCounters") {
      fail("invalidScoreAdjustment", `${path}.statisticalTreatment`);
    }
    const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
    if (periodNumber.state !== "known" || periodNumber.value === 0 ||
        periodNumber.value > periods.length) {
      fail("invalidScoreAdjustment", `${path}.periodNumber`);
    }
    const creditedParticipantId = fact(
      raw.creditedParticipantId,
      `${path}.creditedParticipantId`,
      identifier,
    );
    if (creditedParticipantId.state !== "known") {
      fail("invalidScoreAdjustment", `${path}.creditedParticipantId`);
    }
    const participant = participants.get(creditedParticipantId.value);
    if (!participant || !participant.enteredPlay || participant.teamEntryId !== teamEntryId) {
      fail("invalidScoreAdjustment", `${path}.creditedParticipantId`);
    }
    const evidenceRefs = evidenceFact(raw.evidenceRefs, `${path}.evidenceRefs`);
    if (evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
      fail("invalidScoreAdjustment", `${path}.evidenceRefs`);
    }
    const shotRequirement = requiredShots.get(creditedParticipantId.value) ?? {three: 0, two: 0};
    if (creditedShot === "twoPointMade") {
      shotRequirement.two = safeAdd(shotRequirement.two, 1, `${path}.creditedShot`);
    } else {
      shotRequirement.three = safeAdd(shotRequirement.three, 1, `${path}.creditedShot`);
    }
    requiredShots.set(creditedParticipantId.value, shotRequirement);
    return {
      adjustmentId,
      creditedParticipantId,
      creditedShot,
      evidenceRefs,
      kind,
      periodNumber,
      points,
      requiredCounterChanges: creditedShot === "twoPointMade" ?
        {threeAttempted: 0, threeMade: 0, twoAttempted: 1, twoMade: 1} :
        {threeAttempted: 1, threeMade: 1, twoAttempted: 0, twoMade: 0},
      statisticalTreatment,
      teamEntryId,
      violatingTeamEntryId,
    };
  });
  for (const [participantId, required] of requiredShots) {
    const participant = participants.get(participantId)!;
    if (participant.counts.twoMade < required.two ||
        participant.counts.twoAttempted < required.two ||
        participant.counts.threeMade < required.three ||
        participant.counts.threeAttempted < required.three) {
      fail("invalidScoreAdjustment", "$.playedScoreAdjustments");
    }
  }
  return adjustments;
}

function validateExceptionalPointsByPeriod(
  adjustments: readonly Record<string, unknown>[],
  periods: readonly Record<string, unknown>[],
  homeTeamId: string,
  awayTeamId: string,
): void {
  const totals = new Map<string, number>();
  for (const adjustment of adjustments) {
    const periodNumber = (adjustment.periodNumber as {state: "known"; value: number}).value;
    const teamEntryId = adjustment.teamEntryId as string;
    const key = `${periodNumber}:${teamEntryId}`;
    totals.set(key, safeAdd(totals.get(key) ?? 0, adjustment.points as number, "$.playedScoreAdjustments"));
  }
  for (const period of periods) {
    const number = period.number as number;
    const exceptional = period.exceptionalScoringPoints as ScorePair;
    if ((totals.get(`${number}:${homeTeamId}`) ?? 0) !== exceptional.home ||
        (totals.get(`${number}:${awayTeamId}`) ?? 0) !== exceptional.away) {
      fail("invalidScoreAdjustment", `$.periods[${number - 1}].exceptionalScoringPoints`);
    }
  }
}

function validateDiscipline(
  rawValue: unknown,
  teams: ReadonlySet<string>,
  participants: ReadonlyMap<string, ParticipantRef>,
  periods: readonly Record<string, unknown>[],
  penaltyPolicy: {groups: PenaltyGroup[]; groupByPeriod: Map<number, PenaltyGroup>},
): {
  incidents: Record<string, unknown>[];
  byParticipant: Map<string, Record<string, unknown>>;
  byTeam: Map<string, Record<string, unknown>>;
} {
  const rawIncidents = array(rawValue, "$.disciplineIncidents");
  if (rawIncidents.length > normalizedBoxScoreLimits.maxIncidents) {
    fail("resourceLimitExceeded", "$.disciplineIncidents");
  }
  const incidentIds = new Set<string>();
  const byParticipant = new Map<string, Record<string, unknown>>();
  const byTeam = new Map<string, Record<string, unknown>>();
  for (const participantId of participants.keys()) {
    byParticipant.set(participantId, {
      byType: {disqualifying: 0, personal: 0, technical: 0, unsportsmanlike: 0},
      chargedFouls: 0,
      playerDisqualificationCharges: 0,
      relatedIncidentIds: [],
    });
  }
  for (const teamEntryId of teams) {
    byTeam.set(teamEntryId, {
      byParty: {bench: 0, coach: 0, player: 0, team: 0},
      byType: {disqualifying: 0, personal: 0, technical: 0, unsportsmanlike: 0},
      chargedFouls: 0,
      playerDisqualificationCharges: 0,
      teamFoulsByPeriod: Object.fromEntries(periods.map((period) => [String(period.number), 0])),
    });
  }
  const incidents = rawIncidents.map((value, index) => {
    const path = `$.disciplineIncidents[${index}]`;
    const raw = record(value, path, [
      "chargedParticipantId", "chargedPartyKind", "clockRemainingMs", "context",
      "countsTowardPlayerDisqualification", "countsTowardTeamFoul", "evidenceRefs",
      "incidentId", "incidentType", "periodNumber", "relatedParticipantId",
      "scoresheetCode", "teamEntryId",
    ]);
    const incidentId = identifier(raw.incidentId, `${path}.incidentId`);
    if (incidentIds.has(incidentId)) fail("invalidDisciplineIncident", `${path}.incidentId`);
    incidentIds.add(incidentId);
    const teamEntryId = identifier(raw.teamEntryId, `${path}.teamEntryId`);
    if (!teams.has(teamEntryId)) fail("invalidDisciplineIncident", `${path}.teamEntryId`);
    const context = enumeration(raw.context, `${path}.context`, [
      "onCourt", "bench", "preGame", "interval",
    ] as const);
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
      if (context !== "onCourt" || chargedParticipantId.state !== "known") {
        fail("invalidDisciplineIncident", path);
      }
      const participant = participants.get(chargedParticipantId.value);
      if (!participant || participant.teamEntryId !== teamEntryId) {
        fail("invalidDisciplineIncident", `${path}.chargedParticipantId`);
      }
      if (!participant.enteredPlay) {
        fail("playerNotEnteredForIncident", `${path}.chargedParticipantId`);
      }
    } else {
      if (context === "onCourt" || !absentFact(chargedParticipantId, "not_player_charge")) {
        fail("invalidDisciplineIncident", `${path}.chargedParticipantId`);
      }
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
    if (chargedPartyKind !== "player" &&
        incidentType !== "technical" && incidentType !== "disqualifying") {
      fail("invalidDisciplineIncident", `${path}.incidentType`);
    }
    const scoresheetCode = textValue(raw.scoresheetCode, `${path}.scoresheetCode`, 64);
    const countsTowardTeamFoul = booleanValue(
      raw.countsTowardTeamFoul,
      `${path}.countsTowardTeamFoul`,
    );
    const countsTowardPlayerDisqualification = booleanValue(
      raw.countsTowardPlayerDisqualification,
      `${path}.countsTowardPlayerDisqualification`,
    );
    if ((countsTowardTeamFoul && (chargedPartyKind !== "player" || context !== "onCourt")) ||
        (countsTowardPlayerDisqualification && chargedPartyKind !== "player")) {
      fail("invalidDisciplineIncident", path);
    }
    const periodNumber = fact(raw.periodNumber, `${path}.periodNumber`, nonnegativeInteger);
    const clockRemainingMs = fact(
      raw.clockRemainingMs,
      `${path}.clockRemainingMs`,
      nonnegativeInteger,
    );
    if (context === "preGame") {
      if (!absentFact(periodNumber, "no_play_context") ||
          !absentFact(clockRemainingMs, "no_play_context")) {
        fail("invalidDisciplineIncident", `${path}.periodNumber`);
      }
    } else {
      if (periodNumber.state !== "known" || periodNumber.value === 0 ||
          periodNumber.value > periods.length) {
        fail("invalidDisciplineIncident", `${path}.periodNumber`);
      }
      const period = periods[periodNumber.value - 1];
      const nominal = period.nominalDurationMs as ExplicitFact<number>;
      const elapsed = period.elapsedDurationMs as ExplicitFact<number>;
      if (clockRemainingMs.state === "known") {
        if (nominal.state !== "known" || clockRemainingMs.value > nominal.value) {
          fail("eventClockOutsidePeriod", `${path}.clockRemainingMs`);
        }
        if (elapsed.state === "known" &&
            nominal.value - clockRemainingMs.value > elapsed.value) {
          fail("eventClockOutsidePeriod", `${path}.clockRemainingMs`);
        }
      } else if (clockRemainingMs.state === "notApplicable" &&
          !absentFact(clockRemainingMs, "interval_or_bench_context")) {
        fail("invalidDisciplineIncident", `${path}.clockRemainingMs`);
      }
    }
    const evidenceRefs = evidenceFact(raw.evidenceRefs, `${path}.evidenceRefs`);
    if (evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
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
      teamFouls[key] = safeAdd(teamFouls[key], 1, path);
    }
    return {
      chargedParticipantId,
      chargedPartyKind,
      clockRemainingMs,
      context,
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
    const penaltyGroups = penaltyPolicy.groups.map((group) => {
      let groupTeamFouls = 0;
      for (const periodNumber of group.periodNumbers) {
        groupTeamFouls = safeAdd(
          groupTeamFouls,
          teamFouls[String(periodNumber)] ?? 0,
          "$.disciplineIncidents",
        );
        const threshold = group.penaltyStartsAtFoul;
        penaltyStateByPeriod[String(periodNumber)] = {
          groupId: group.groupId,
          groupTeamFoulsThroughPeriod: groupTeamFouls,
          inPenalty: threshold.state === "known" ?
            {state: "known", value: groupTeamFouls >= threshold.value} : threshold,
          rawTeamFouls: teamFouls[String(periodNumber)] ?? 0,
          threshold,
        };
      }
      const threshold = group.penaltyStartsAtFoul;
      return {
        groupId: group.groupId,
        inPenalty: threshold.state === "known" ?
          {state: "known", value: groupTeamFouls >= threshold.value} : threshold,
        periodNumbers: group.periodNumbers,
        teamFouls: groupTeamFouls,
        threshold,
      };
    });
    summary.penaltyGroups = penaltyGroups;
    summary.penaltyStateByPeriod = penaltyStateByPeriod;
  }
  return {incidents, byParticipant, byTeam};
}

function validateAdministrativeResult(
  rawValue: unknown,
  disposition: "played" | "forfeit" | "default" | "annulled" | "otherAdjudicated",
  statisticsDisposition: "complete" | "resultOnly" | "excluded",
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
  const evidenceRefs = evidenceFact(
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
    if (statisticsDisposition !== "complete" ||
        !absentFact(awardedScore, "not_adjudicated") ||
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
    if (evidenceRefs.state !== "known" || evidenceRefs.value.length === 0 ||
        playerStatisticsTreatment === "policyPending") {
      fail("invalidAdministrativeResult", "$.administrativeResult");
    }
    if (statisticsDisposition === "complete" &&
        playerStatisticsTreatment !== "includePlayedStatistics") {
      fail("invalidAdministrativeResult", "$.administrativeResult.playerStatisticsTreatment");
    }
    if (statisticsDisposition !== "complete" && playerStatisticsTreatment !== "exclude") {
      fail("invalidAdministrativeResult", "$.administrativeResult.playerStatisticsTreatment");
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
  const evidenceRefs = evidenceFact(raw.evidenceRefs, "$.officialScore.evidenceRefs");
  const reconciliationStatus = enumeration(
    raw.reconciliationStatus,
    "$.officialScore.reconciliationStatus",
    ["reconciled", "unreconciled", "notAvailable"] as const,
  );
  if (reconciliationStatus !== "reconciled" || score.state !== "known" ||
      evidenceRefs.state !== "known" || evidenceRefs.value.length === 0) {
    fail("officialScoreEvidenceRequired", "$.officialScore");
  }
  if (score.value.home !== playedScore.home || score.value.away !== playedScore.away) {
    fail("officialScoreMismatch", "$.officialScore.score");
  }
  return {evidenceRefs, reconciliationStatus, score};
}

interface ParsedRoot {
  administrativeResult: unknown;
  disciplineIncidents: unknown;
  officialScore: unknown;
  periods: unknown;
  playedScore: unknown;
  playedScoreAdjustments: unknown;
  provenance: {
    captureMode: "liveCapture" | "officialSheet" | "historicalImport";
    rulesetVersion: string;
    sourceId: string;
    sourceLabel: string;
  };
  resultDisposition: "played" | "forfeit" | "default" | "annulled" | "otherAdjudicated";
  rules: ParsedRules;
  scope: Record<string, string>;
  statisticsDisposition: "complete" | "resultOnly" | "excluded";
  teams: unknown[];
}

function validateRoot(rawValue: unknown): ParsedRoot {
  const raw = record(rawValue, "$", [
    "administrativeResult", "calculatorVersion", "canonicalEncodingVersion",
    "disciplineIncidents", "officialScore", "periods", "playedScore",
    "playedScoreAdjustments", "provenance", "resultDisposition", "rules",
    "schemaVersion", "scope", "statisticsDisposition", "teams",
    "unicodeNormalizationVersion",
  ]);
  const schemaVersion = nonnegativeInteger(raw.schemaVersion, "$.schemaVersion");
  if (schemaVersion !== 2) fail("unsupportedSchemaVersion", "$.schemaVersion");
  if (raw.calculatorVersion !== normalizedBoxScoreCalculatorVersion) {
    fail("unsupportedCalculatorVersion", "$.calculatorVersion");
  }
  if (raw.canonicalEncodingVersion !== officialStatVersions.canonicalEncodingVersion) {
    fail("unsupportedCanonicalEncodingVersion", "$.canonicalEncodingVersion");
  }
  if (raw.unicodeNormalizationVersion !== normalizedBoxScoreUnicodeVersion) {
    fail("unsupportedUnicodeNormalizationVersion", "$.unicodeNormalizationVersion");
  }
  const scope = validateScope(raw.scope);
  const resultDisposition = enumeration(raw.resultDisposition, "$.resultDisposition", [
    "played", "forfeit", "default", "annulled", "otherAdjudicated",
  ] as const);
  const statisticsDisposition = enumeration(
    raw.statisticsDisposition,
    "$.statisticsDisposition",
    ["complete", "resultOnly", "excluded"] as const,
  );
  const provenanceRaw = record(raw.provenance, "$.provenance", [
    "captureMode", "rulesetVersion", "sourceId", "sourceLabel",
  ]);
  const provenance = {
    captureMode: enumeration(provenanceRaw.captureMode, "$.provenance.captureMode", [
      "liveCapture", "officialSheet", "historicalImport",
    ] as const),
    rulesetVersion: identifier(provenanceRaw.rulesetVersion, "$.provenance.rulesetVersion"),
    sourceId: identifier(provenanceRaw.sourceId, "$.provenance.sourceId"),
    sourceLabel: textValue(provenanceRaw.sourceLabel, "$.provenance.sourceLabel"),
  };
  const rules = validateRules(raw.rules);
  const teams = array(raw.teams, "$.teams");
  if (teams.length !== 2) fail("invalidTeamStructure", "$.teams");
  return {
    administrativeResult: raw.administrativeResult,
    disciplineIncidents: raw.disciplineIncidents,
    officialScore: raw.officialScore,
    periods: raw.periods,
    playedScore: raw.playedScore,
    playedScoreAdjustments: raw.playedScoreAdjustments,
    provenance,
    resultDisposition,
    rules,
    scope,
    statisticsDisposition,
    teams,
  };
}

function validateNoPlay(
  root: ParsedRoot,
  teamResults: readonly TeamResult[],
  periodResult: PeriodResult,
  playedScore: ScorePair,
  adjustments: readonly Record<string, unknown>[],
  incidents: readonly Record<string, unknown>[],
): void {
  if (root.statisticsDisposition === "complete") return;
  if (root.resultDisposition === "played" || periodResult.periods.length !== 0 ||
      playedScore.home !== 0 || playedScore.away !== 0 || adjustments.length !== 0) {
    fail("invalidNoPlayStatistics", "$");
  }
  for (const team of teamResults) {
    if (!isZeroCounts(team.counts)) fail("invalidNoPlayStatistics", "$.teams");
    const teamOnly = team.output.teamOnly as Record<string, number>;
    if (teamOnly.offensiveRebounds !== 0 || teamOnly.defensiveRebounds !== 0 ||
        teamOnly.turnovers !== 0) {
      fail("invalidNoPlayStatistics", "$.teams");
    }
    for (const player of team.output.players as Record<string, unknown>[]) {
      if (player.enteredPlay) {
        fail("invalidNoPlayStatistics", `$.participants.${player.participantId}.enteredPlay`);
      }
    }
  }
  for (const incident of incidents) {
    if (incident.context !== "preGame" || incident.chargedPartyKind === "player" ||
        incident.countsTowardTeamFoul || incident.countsTowardPlayerDisqualification) {
      fail("invalidNoPlayStatistics", "$.disciplineIncidents");
    }
  }
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const nested of Object.values(value as Record<string, unknown>)) deepFreeze(nested);
    Object.freeze(value);
  }
  return value;
}

function calculateAccepted(rawInput: unknown): CalculatorAccepted {
  const root = validateRoot(rawInput);
  const requiresCompletePlay = root.resultDisposition === "played";
  const periodResult = validatePeriods(root.periods, root.rules, requiresCompletePlay);
  const penaltyPolicy = validatePenaltyGroups(root.rules, periodResult.periods);
  const seenParticipants = new Set<string>();
  const seenPlayers = new Set<string>();
  const teamResults = root.teams.map((team, index) => validateTeam(
    team,
    `$.teams[${index}]`,
    seenParticipants,
    seenPlayers,
    root.rules.playingTimeRoundingProfile,
  ));
  if (teamResults[0].output.side === teamResults[1].output.side ||
      teamResults[0].output.teamEntryId === teamResults[1].output.teamEntryId) {
    fail("invalidTeamStructure", "$.teams");
  }
  teamResults.sort((left, right) => left.output.side === "home" ?
    -1 : right.output.side === "home" ? 1 : 0);
  const homeTeam = teamResults[0];
  const awayTeam = teamResults[1];
  validatePlayerTimeline(
    teamResults,
    periodResult.periods,
    periodResult.totalElapsedMs,
    root.rules,
  );
  const playedScore = scorePair(root.playedScore, "$.playedScore");
  if (periodResult.score.home !== playedScore.home ||
      periodResult.score.away !== playedScore.away) {
    fail("playedScorePeriodMismatch", "$.playedScore");
  }
  if (root.resultDisposition === "played" && !root.rules.completedTiesAllowed &&
      playedScore.home === playedScore.away) {
    fail("invalidPeriodSequence", "$.playedScore");
  }
  const homeTotals = homeTeam.output.totals as Record<string, number>;
  const awayTotals = awayTeam.output.totals as Record<string, number>;
  if (periodResult.counterPoints.home !== homeTotals.points ||
      periodResult.counterPoints.away !== awayTotals.points ||
      homeTotals.points !== playedScore.home || awayTotals.points !== playedScore.away) {
    fail("playedScoreAttributionMismatch", "$.playedScore");
  }
  const teamIds = new Set<string>([
    homeTeam.output.teamEntryId as string,
    awayTeam.output.teamEntryId as string,
  ]);
  const participants = new Map<string, ParticipantRef>();
  for (const team of teamResults) {
    for (const player of team.output.players as Record<string, unknown>[]) {
      participants.set(player.participantId as string, {
        counts: player.totals as Record<string, number>,
        enteredPlay: player.enteredPlay as boolean,
        output: player,
        teamEntryId: player.teamEntryId as string,
      });
    }
  }
  const adjustments = validateScoreAdjustments(
    root.playedScoreAdjustments,
    periodResult.periods,
    teamIds,
    participants,
  );
  validateExceptionalPointsByPeriod(
    adjustments,
    periodResult.periods,
    homeTeam.output.teamEntryId as string,
    awayTeam.output.teamEntryId as string,
  );
  const discipline = validateDiscipline(
    root.disciplineIncidents,
    teamIds,
    participants,
    periodResult.periods,
    penaltyPolicy,
  );
  for (const team of teamResults) {
    team.output.discipline = discipline.byTeam.get(team.output.teamEntryId as string)!;
    for (const player of team.output.players as Record<string, unknown>[]) {
      player.discipline = discipline.byParticipant.get(player.participantId as string)!;
    }
  }
  const administrativeResult = validateAdministrativeResult(
    root.administrativeResult,
    root.resultDisposition,
    root.statisticsDisposition,
    teamIds,
    homeTeam.output.teamEntryId as string,
  );
  const officialScore = validateOfficialScore(root.officialScore, playedScore);
  validateNoPlay(
    root,
    teamResults,
    periodResult,
    playedScore,
    adjustments,
    discipline.incidents,
  );
  const diagnostics: CalculatorDiagnostic[] = [];
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
  diagnostics.sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  const playedWinnerTeamEntryId: ExplicitFact<string> = playedScore.home === playedScore.away ?
    {state: "unknown", value: null, reasonCode: "tied_played_score"} : {
      state: "known",
      value: playedScore.home > playedScore.away ?
        homeTeam.output.teamEntryId as string : awayTeam.output.teamEntryId as string,
    };
  const teamPlayedTimeCapacityMs: ExplicitFact<number> =
    periodResult.totalElapsedMs.state === "known" &&
    root.rules.teamTimeCapacityMultiplier.state === "known" ? {
        state: "known",
        value: safeMultiply(
          periodResult.totalElapsedMs.value,
          root.rules.teamTimeCapacityMultiplier.value,
          "$.rules.teamTimeCapacityMultiplier",
        ),
      } : {
        state: "unknown",
        value: null,
        reasonCode: "capacity_input_unknown",
      };
  return deepFreeze({
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
      provenance: root.provenance,
      resultDisposition: root.resultDisposition,
      rules: {
        ...root.rules,
        teamPlayedTimeCapacityMs,
      },
      schemaVersion: 2,
      scope: root.scope,
      statisticsDisposition: root.statisticsDisposition,
      teams: teamResults.map((team) => team.output),
      totalElapsedPlayMs: periodResult.totalElapsedMs,
      unicodeNormalizationVersion: normalizedBoxScoreUnicodeVersion,
    },
    status: "accepted",
  });
}

function rejected(code: CalculatorErrorCode, path: string): CalculatorOutcome {
  return deepFreeze({
    calculatorVersion: normalizedBoxScoreCalculatorVersion,
    errors: [{code, path}],
    status: "rejected",
  });
}

/** Pure, deterministic, fail-closed normalized box-score calculator. */
export function calculateNormalizedBoxScore(input: unknown): CalculatorOutcome {
  try {
    preflight(input);
    return calculateAccepted(input);
  } catch (error) {
    if (error instanceof ValidationFailure) return rejected(error.code, error.path);
    return rejected("invalidCanonicalValue", "$");
  }
}

/**
 * Raw JSON boundary for untrusted transports. The byte limit is enforced before
 * JSON parsing; parsed values still pass the independent graph preflight.
 */
export function calculateNormalizedBoxScoreFromJson(rawJson: string): CalculatorOutcome {
  if (typeof rawJson !== "string" ||
      utf8Length(rawJson) > normalizedBoxScoreLimits.maxRawTransportBytes) {
    return rejected("resourceLimitExceeded", "$");
  }
  let input: unknown;
  try {
    input = JSON.parse(rawJson);
  } catch {
    return rejected("invalidCanonicalValue", "$");
  }
  return calculateNormalizedBoxScore(input);
}

export function assertCalculatorErrorVocabulary(): void {
  if (new Set(calculatorErrorCodes).size !== calculatorErrorCodes.length) {
    throw new Error("Calculator error codes must remain unique");
  }
  if (playerCounterSet.size !== playerCountFields.length) {
    throw new Error("Player counter fields must remain unique");
  }
}
