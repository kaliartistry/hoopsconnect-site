import type {ExplicitFact, GameScope} from "../official_stats_contract";

export const normalizedBoxScoreCalculatorVersion =
  "hoopsconnect-normalized-box-score-v2" as const;
export const normalizedBoxScoreUnicodeVersion =
  "official-stat-unicode-nfc-v2" as const;

export const playerCountFields = [
  "twoMade", "twoAttempted", "threeMade", "threeAttempted",
  "freeMade", "freeAttempted", "offensiveRebounds", "defensiveRebounds",
  "assists", "steals", "blocks", "turnovers",
] as const;
export type PlayerCountField = typeof playerCountFields[number];

export type CountFacts = Readonly<Record<PlayerCountField, ExplicitFact<number>>>;

export interface CalculatorProvenance {
  captureMode: "liveCapture" | "officialSheet" | "historicalImport";
  sourceId: string;
  sourceLabel: string;
  rulesetVersion: string;
}

export type RulesProfileId = "generic-explicit-v2" | "fiba-2024-reference-v1";
export type PlayingTimeRoundingProfile =
  | "nearest-half-up-v1"
  | "fiba-2024-reference-sheet-v1";

export interface PenaltyAccumulationGroupInput {
  groupId: string;
  periodNumbers: number[];
  penaltyStartsAtFoul: ExplicitFact<number>;
}

export interface CalculatorRules {
  rulesProfileId: RulesProfileId;
  regulationPeriodCount: number;
  completedTiesAllowed: boolean;
  overtimePolicy: {
    allowed: boolean;
    nominalDurationMs: ExplicitFact<number>;
  };
  teamTimeCapacityMultiplier: ExplicitFact<number>;
  playingTimeRoundingProfile: PlayingTimeRoundingProfile;
  exceptionalScoringProfile: "fiba-2024-reference-attribution-v1";
  penaltyAccumulationGroups: PenaltyAccumulationGroupInput[];
}

export interface PlayerTimeInput {
  playedTimeMs: ExplicitFact<number>;
  timeSource:
    | "liveClock"
    | "officialSheetExact"
    | "officialSheetRounded"
    | "notRecorded"
    | "notApplicable";
  timePrecisionMs: ExplicitFact<number>;
  roundingMode: "nearestHalfUp" | "fiba2024ReferenceSheet" | "notApplicable";
}

export interface PlayerDepartureInput {
  kind: "none" | "fouledOut" | "ejected" | "injured" | "other";
  periodNumber: ExplicitFact<number>;
  clockRemainingMs: ExplicitFact<number>;
  evidenceRefs: ExplicitFact<string[]>;
}

export interface PlayerLineInput {
  participantId: string;
  playerId: string;
  rosterMembershipId: string;
  rosterMembershipVersionId: string;
  teamEntryId: string;
  participationStatus: "active" | "dnp" | "inactive";
  participationReasonCode: ExplicitFact<string>;
  enteredPlay: boolean;
  starter: ExplicitFact<boolean>;
  time: PlayerTimeInput;
  counts: CountFacts;
  departure: PlayerDepartureInput;
}

export interface TeamInput {
  teamEntryId: string;
  side: "home" | "away";
  players: PlayerLineInput[];
  teamOnly: Readonly<Pick<CountFacts,
    "offensiveRebounds" | "defensiveRebounds" | "turnovers">>;
  reportedTotals: CountFacts;
}

export type PeriodCompletionState =
  | "completed"
  | "partial"
  | "suspended"
  | "resumedCompleted"
  | "abandoned"
  | "adjudicated";

export interface ScorePair {
  home: number;
  away: number;
}

export interface PeriodInput {
  number: number;
  kind: "regulation" | "overtime";
  overtimeIndex: ExplicitFact<number>;
  nominalDurationMs: ExplicitFact<number>;
  elapsedDurationMs: ExplicitFact<number>;
  completionState: PeriodCompletionState;
  homeScore: number;
  awayScore: number;
  playerCounterPoints: ScorePair;
  exceptionalScoringPoints: ScorePair;
  source: "liveCounter" | "officialSheet" | "historicalEvidence";
}

export interface PlayedScoreAdjustmentInput {
  adjustmentId: string;
  teamEntryId: string;
  violatingTeamEntryId: string;
  kind: "accidentalOwnBasket" | "defensiveGoaltending";
  points: number;
  periodNumber: ExplicitFact<number>;
  creditedParticipantId: ExplicitFact<string>;
  creditedShot: "twoPointMade" | "threePointMade";
  statisticalTreatment: "includedInPlayerCounters" | "additiveToPlayerCounters";
  evidenceRefs: ExplicitFact<string[]>;
}

export interface AdministrativeResultInput {
  awardedScore: ExplicitFact<ScorePair>;
  winnerTeamEntryId: ExplicitFact<string>;
  evidenceRefs: ExplicitFact<string[]>;
  standingsTreatment: "playedResult" | "awardedResult" | "excluded" | "policyPending";
  playerStatisticsTreatment: "includePlayedStatistics" | "exclude" | "policyPending";
}

export interface OfficialScoreInput {
  score: ExplicitFact<ScorePair>;
  evidenceRefs: ExplicitFact<string[]>;
  reconciliationStatus: "reconciled" | "unreconciled" | "notAvailable";
}

export interface DisciplineIncidentInput {
  incidentId: string;
  teamEntryId: string;
  context: "onCourt" | "bench" | "preGame" | "interval";
  chargedPartyKind: "player" | "coach" | "bench" | "team";
  chargedParticipantId: ExplicitFact<string>;
  relatedParticipantId: ExplicitFact<string>;
  incidentType: "personal" | "technical" | "unsportsmanlike" | "disqualifying";
  scoresheetCode: string;
  countsTowardTeamFoul: boolean;
  countsTowardPlayerDisqualification: boolean;
  periodNumber: ExplicitFact<number>;
  clockRemainingMs: ExplicitFact<number>;
  evidenceRefs: ExplicitFact<string[]>;
}

export interface NormalizedBoxScoreInput {
  schemaVersion: 2;
  calculatorVersion: typeof normalizedBoxScoreCalculatorVersion;
  canonicalEncodingVersion: "official-stat-canonical-json-v1";
  unicodeNormalizationVersion: typeof normalizedBoxScoreUnicodeVersion;
  scope: GameScope;
  resultDisposition: "played" | "forfeit" | "default" | "annulled" | "otherAdjudicated";
  statisticsDisposition: "complete" | "resultOnly" | "excluded";
  provenance: CalculatorProvenance;
  rules: CalculatorRules;
  teams: [TeamInput, TeamInput];
  periods: PeriodInput[];
  playedScore: ScorePair;
  playedScoreAdjustments: PlayedScoreAdjustmentInput[];
  administrativeResult: AdministrativeResultInput;
  officialScore: OfficialScoreInput;
  disciplineIncidents: DisciplineIncidentInput[];
}

export const calculatorErrorCodes = [
  "invalidCanonicalValue", "resourceLimitExceeded", "invalidShape",
  "unsupportedSchemaVersion", "unsupportedCalculatorVersion",
  "unsupportedCanonicalEncodingVersion", "unsupportedUnicodeNormalizationVersion",
  "invalidIdentifier", "invalidString", "invalidNonnegativeSafeInteger",
  "arithmeticOverflow", "invalidFact", "requiredKnownCount",
  "invalidTeamStructure", "duplicateParticipant", "participantTeamMismatch",
  "invalidParticipation", "dnpOrdinaryStat", "invalidTimeProvenance",
  "timeOutsideGameDuration", "invalidDeparture", "departureTimeConflict",
  "eventClockOutsidePeriod", "makesExceedAttempts", "reportedTeamTotalMismatch",
  "invalidRulesProfile", "invalidPenaltyPolicy", "invalidPeriodSequence",
  "invalidPeriodState", "invalidOvertimeSequence", "playedScorePeriodMismatch",
  "playedScoreAttributionMismatch", "invalidScoreAdjustment",
  "invalidDisciplineIncident", "playerNotEnteredForIncident",
  "invalidAdministrativeResult", "invalidNoPlayStatistics",
  "officialScoreEvidenceRequired", "officialScoreMismatch",
] as const;
export type CalculatorErrorCode = typeof calculatorErrorCodes[number];

export interface CalculatorError {
  code: CalculatorErrorCode;
  path: string;
}

export interface CalculatorDiagnostic {
  code: "crossTeamStealsVsTurnoversNeedsReview";
  path: string;
  severity: "evidenceReview";
  steals: number;
  opponentTurnovers: number;
}

export type CalculatorRejected = Readonly<{
  calculatorVersion: typeof normalizedBoxScoreCalculatorVersion;
  errors: readonly [Readonly<CalculatorError>];
  status: "rejected";
}>;

export type CalculatorAccepted = Readonly<{
  calculatorVersion: typeof normalizedBoxScoreCalculatorVersion;
  normalizedBoxScore: Readonly<Record<string, unknown>>;
  status: "accepted";
}>;

export type CalculatorOutcome = CalculatorRejected | CalculatorAccepted;
