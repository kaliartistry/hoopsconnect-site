import 'dart:convert';

import 'canonical_encoding.dart';
import 'calculators/normalized_box_score.dart';
import 'contract_versions.dart';
import 'domain_contracts.dart';
import 'domain_enums.dart';
import 'fact.dart';
import 'unicode_normalization.dart';

/// Versions and stable reason codes for the read-only legacy evidence bridge.
///
/// This bridge deliberately produces a review candidate, not a normalized box
/// score or an official revision. Nothing in this file activates v2 authority.
abstract final class LegacyGameStatsV2AdapterContract {
  static const int candidateSchemaVersion = 1;
  static const String adapterVersion =
      'legacy-game-stats-to-official-v2-candidate-v1';
  static const String sourceSchemaVersion = 'legacy-game-stats-v1';
  static const String missingReasonCode = 'not_recorded_legacy_game_stats';
  static const String nullReasonCode = 'null_legacy_game_stats_value';
  static const String identityMappingReasonCode =
      'identity_mapping_not_reviewed';
}

/// A named immutable rules dependency supplied by the integration owner.
///
/// No duration, period count, overtime duration, or foul limit is inferred by
/// the adapter. Those interpretations belong to the referenced rules profile.
final class OfficialStatRulesProfilePin {
  final String rulesProfileId;
  final VersionReference rulesetVersion;

  OfficialStatRulesProfilePin({
    required this.rulesProfileId,
    required this.rulesetVersion,
  }) {
    OfficialStatIdentifiers.requireValid('rulesProfileId', rulesProfileId);
  }

  Map<String, Object?> toContractMap() => {
    'rulesProfileId': rulesProfileId,
    'rulesetVersion': rulesetVersion.toContractMap(),
  };
}

/// Immutable identity for the separately inventoried source document.
///
/// [sourcePayloadHash] must come from the read-only inventory/export boundary.
/// The adapter binds to that evidence but does not claim to hash Firestore
/// runtime values such as Timestamp objects itself.
final class LegacyGameStatsSourceReference {
  final String documentId;
  final String sourcePath;
  final String sourcePayloadHash;

  LegacyGameStatsSourceReference({
    required this.documentId,
    required this.sourcePath,
    required this.sourcePayloadHash,
  }) {
    if (documentId.isEmpty || sourcePath.isEmpty) {
      throw FormatException('Legacy source identity must not be empty');
    }
    if (sourcePath.split('/').last != documentId) {
      throw FormatException(
        'Legacy source path must terminate in the exact document ID',
      );
    }
    OfficialStatIdentifiers.requireSha256(
      'sourcePayloadHash',
      sourcePayloadHash,
    );
  }

  Map<String, Object?> toContractMap() => {
    'documentId': documentId,
    'sourcePath': sourcePath,
    'sourcePayloadHash': sourcePayloadHash,
    'sourceSchemaVersion': LegacyGameStatsV2AdapterContract.sourceSchemaVersion,
  };
}

enum LegacyGameStatsAdapterIssueCode {
  homeAwayTeamCollision,
  legacyApprovalIsNotCertification,
  playerTeamOutsideGame,
  reportedReboundMismatch,
  reportedScorePeriodMismatch,
}

final class LegacyGameStatsAdapterIssue {
  final LegacyGameStatsAdapterIssueCode code;
  final String path;

  const LegacyGameStatsAdapterIssue({required this.code, required this.path});

  Map<String, Object?> toContractMap() => {'code': code.name, 'path': path};
}

/// The legacy team identity and score exactly as recorded.
///
/// A legacy team ID is evidence, not a v2 season-team-entry ID. The mapping is
/// therefore explicit unknown until Workstream C supplies a reviewed mapping.
final class LegacyTeamStatEvidence {
  final String side;
  final String legacyTeamId;
  final String legacyTeamName;
  final Fact<String> teamEntryId;
  final Fact<int> reportedScore;

  const LegacyTeamStatEvidence({
    required this.side,
    required this.legacyTeamId,
    required this.legacyTeamName,
    required this.teamEntryId,
    required this.reportedScore,
  });

  Map<String, Object?> toContractMap() => {
    'legacyTeamId': legacyTeamId,
    'legacyTeamName': legacyTeamName,
    'reportedScore': reportedScore.toContractMap((value) => value),
    'side': side,
    'teamEntryId': teamEntryId.toContractMap((value) => value),
  };
}

/// One period-like legacy score pair without a playing-rules interpretation.
///
/// The old map calls these quarters, but the adapter does not decide whether a
/// key represents regulation, overtime, a partial period, or an invalid entry.
final class LegacyPeriodScoreEvidence {
  final int legacyPeriodNumber;
  final Fact<int> homeScore;
  final Fact<int> awayScore;

  const LegacyPeriodScoreEvidence({
    required this.legacyPeriodNumber,
    required this.homeScore,
    required this.awayScore,
  });

  Map<String, Object?> toContractMap() => {
    'awayScore': awayScore.toContractMap((value) => value),
    'homeScore': homeScore.toContractMap((value) => value),
    'legacyPeriodNumber': legacyPeriodNumber,
    'rulesInterpretation': const Fact<String>.unknown(
      reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
    ).toContractMap((value) => value),
  };
}

/// A player line as legacy evidence, with every missing fact kept unknown.
///
/// The old model stores total points but not their shooting composition. It
/// also does not prove participation, starter status, team-only counts, exact
/// playing time, or turnovers. Those facts cannot be reconstructed from zero
/// defaults or from a nonzero total.
final class LegacyPlayerStatEvidence {
  final String legacyPlayerKey;
  final Fact<String> legacyTeamId;
  final Fact<String> reportedName;
  final Fact<int> reportedPoints;
  final Fact<int> reportedOffensiveRebounds;
  final Fact<int> reportedDefensiveRebounds;
  final Fact<int> reportedTotalRebounds;
  final Fact<int> componentDerivedTotalRebounds;
  final Fact<int> reportedAssists;
  final Fact<int> reportedSteals;
  final Fact<int> reportedBlocks;
  final Fact<int> reportedFouls;
  final Fact<int> reportedMinutes;
  final List<String> unmappedSourcePaths;

  const LegacyPlayerStatEvidence({
    required this.legacyPlayerKey,
    required this.legacyTeamId,
    required this.reportedName,
    required this.reportedPoints,
    required this.reportedOffensiveRebounds,
    required this.reportedDefensiveRebounds,
    required this.reportedTotalRebounds,
    required this.componentDerivedTotalRebounds,
    required this.reportedAssists,
    required this.reportedSteals,
    required this.reportedBlocks,
    required this.reportedFouls,
    required this.reportedMinutes,
    required this.unmappedSourcePaths,
  });

  Map<String, Object?> toContractMap() => {
    'legacyPlayerKey': legacyPlayerKey,
    'legacyTeamId': legacyTeamId.toContractMap((value) => value),
    'mappedIdentity': {
      'participantId': const Fact<String>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
      ).toContractMap((value) => value),
      'playerId': const Fact<String>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
      ).toContractMap((value) => value),
      'rosterMembershipId': const Fact<String>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
      ).toContractMap((value) => value),
      'rosterMembershipVersionId': const Fact<String>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
      ).toContractMap((value) => value),
    },
    'normalizedInputFacts': {
      'assists': reportedAssists.toContractMap((value) => value),
      'blocks': reportedBlocks.toContractMap((value) => value),
      'defensiveRebounds': reportedDefensiveRebounds.toContractMap(
        (value) => value,
      ),
      'enteredPlay': const Fact<bool>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'freeAttempted': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'freeMade': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'offensiveRebounds': reportedOffensiveRebounds.toContractMap(
        (value) => value,
      ),
      'playedTimeMs': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'steals': reportedSteals.toContractMap((value) => value),
      'starter': const Fact<bool>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'threeAttempted': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'threeMade': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'turnovers': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'twoAttempted': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
      'twoMade': const Fact<int>.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      ).toContractMap((value) => value),
    },
    'reportedLegacyFacts': {
      'assists': reportedAssists.toContractMap((value) => value),
      'blocks': reportedBlocks.toContractMap((value) => value),
      'componentDerivedTotalRebounds': componentDerivedTotalRebounds
          .toContractMap((value) => value),
      'defensiveRebounds': reportedDefensiveRebounds.toContractMap(
        (value) => value,
      ),
      'fouls': reportedFouls.toContractMap((value) => value),
      'minutes': reportedMinutes.toContractMap((value) => value),
      'name': reportedName.toContractMap((value) => value),
      'offensiveRebounds': reportedOffensiveRebounds.toContractMap(
        (value) => value,
      ),
      'points': reportedPoints.toContractMap((value) => value),
      'steals': reportedSteals.toContractMap((value) => value),
      'totalRebounds': reportedTotalRebounds.toContractMap((value) => value),
    },
    'unmappedSourcePaths': unmappedSourcePaths,
  };
}

/// Deterministic, read-only evidence candidate for later reviewed integration.
final class LegacyGameStatsV2Candidate {
  final GameScope scope;
  final LegacyGameStatsSourceReference source;
  final OfficialStatRulesProfilePin rulesProfile;
  final Fact<String> legacyStatus;
  final Fact<String> legacyEntryMode;
  final LegacyEvidenceClassification evidenceClassification;
  final List<LegacyTeamStatEvidence> teams;
  final List<LegacyPeriodScoreEvidence> periods;
  final List<LegacyPlayerStatEvidence> playerLines;
  final List<LegacyGameStatsAdapterIssue> issues;
  final List<String> unmappedSourcePaths;

  const LegacyGameStatsV2Candidate({
    required this.scope,
    required this.source,
    required this.rulesProfile,
    required this.legacyStatus,
    required this.legacyEntryMode,
    required this.evidenceClassification,
    required this.teams,
    required this.periods,
    required this.playerLines,
    required this.issues,
    required this.unmappedSourcePaths,
  });

  /// A legacy adapter output is never directly accepted by the v2 calculator.
  bool get calculatorInputAllowed => false;

  /// Legacy approval/evidence always requires a reviewed v2 revision.
  bool get certificationAllowed => false;

  List<String> get calculatorBlockers => const [
    'official_score_evidence_not_bound',
    'participant_identity_mapping_required',
    'participation_and_starter_not_recorded',
    'period_rules_interpretation_required',
    'played_time_provenance_not_recorded',
    'shooting_breakdown_not_recorded',
    'team_only_counts_not_recorded',
    'turnovers_not_recorded',
  ];

  Map<String, Object?> toContractMap() => {
    'adapterVersion': LegacyGameStatsV2AdapterContract.adapterVersion,
    'calculatorBlockers': calculatorBlockers,
    'calculatorInputAllowed': calculatorInputAllowed,
    'candidateSchemaVersion':
        LegacyGameStatsV2AdapterContract.candidateSchemaVersion,
    'certificationAllowed': certificationAllowed,
    'evidenceClassification': evidenceClassification.name,
    'issues': [for (final issue in issues) issue.toContractMap()],
    'legacyEntryMode': legacyEntryMode.toContractMap((value) => value),
    'legacyStatus': legacyStatus.toContractMap((value) => value),
    'periods': [for (final period in periods) period.toContractMap()],
    'playerLines': [for (final player in playerLines) player.toContractMap()],
    'rulesProfile': rulesProfile.toContractMap(),
    'scope': scope.toContractMap(),
    'source': source.toContractMap(),
    'targetCalculatorVersion': normalizedBoxScoreCalculatorVersion,
    'teams': [for (final team in teams) team.toContractMap()],
    'unmappedSourcePaths': unmappedSourcePaths,
  };

  String get canonicalJson =>
      OfficialStatCanonicalEncoding.encode(toContractMap());

  String get candidateHash =>
      OfficialStatCanonicalEncoding.sha256Hex(toContractMap());

  int get canonicalByteLength => utf8.encode(canonicalJson).length;
}

abstract interface class LegacyGameStatsV2CandidateAdapter {
  LegacyGameStatsV2Candidate adapt({
    required LegacyGameStatsSourceReference source,
    required Map<String, Object?> legacyDocument,
    required GameScope scope,
    required OfficialStatRulesProfilePin rulesProfile,
  });
}

/// Default pure-Dart implementation. It performs no reads, writes, or routing.
final class ReadOnlyLegacyGameStatsV2Adapter
    implements LegacyGameStatsV2CandidateAdapter {
  static const _rootFields = <String>{
    'awayQuarterScores',
    'awayScore',
    'awayTeamId',
    'awayTeamName',
    'divisionId',
    'entryMode',
    'eventId',
    'homeQuarterScores',
    'homeScore',
    'homeTeamId',
    'homeTeamName',
    'playerLines',
    'seasonId',
    'status',
  };

  static const _playerFields = <String>{
    'ast',
    'blk',
    'dreb',
    'fls',
    'min',
    'name',
    'oreb',
    'pts',
    'reb',
    'stl',
    'teamId',
  };

  @override
  LegacyGameStatsV2Candidate adapt({
    required LegacyGameStatsSourceReference source,
    required Map<String, Object?> legacyDocument,
    required GameScope scope,
    required OfficialStatRulesProfilePin rulesProfile,
  }) {
    if (rulesProfile.rulesetVersion.associationId != scope.associationId) {
      throw ArgumentError(
        'Rules profile and game scope must share one association',
      );
    }
    _requireScopeMatch(
      legacyDocument,
      'eventId',
      scope.gameId,
      source.documentId,
    );
    _requireScopeMatch(legacyDocument, 'seasonId', scope.seasonId, null);
    _requireScopeMatch(legacyDocument, 'divisionId', scope.divisionId, null);

    final homeTeamId = _requiredText(legacyDocument, 'homeTeamId');
    final awayTeamId = _requiredText(legacyDocument, 'awayTeamId');
    final homeTeamName = _requiredText(legacyDocument, 'homeTeamName');
    final awayTeamName = _requiredText(legacyDocument, 'awayTeamName');
    final homeScore = _intFact(legacyDocument, 'homeScore', r'$.homeScore');
    final awayScore = _intFact(legacyDocument, 'awayScore', r'$.awayScore');
    final issues = <LegacyGameStatsAdapterIssue>[];
    if (homeTeamId == awayTeamId) {
      issues.add(
        const LegacyGameStatsAdapterIssue(
          code: LegacyGameStatsAdapterIssueCode.homeAwayTeamCollision,
          path: r'$.awayTeamId',
        ),
      );
    }

    final legacyStatus = _stringFact(legacyDocument, 'status', r'$.status');
    if (legacyStatus.valueOrNull == 'approved') {
      issues.add(
        const LegacyGameStatsAdapterIssue(
          code:
              LegacyGameStatsAdapterIssueCode.legacyApprovalIsNotCertification,
          path: r'$.status',
        ),
      );
    }
    final players = _parsePlayers(
      legacyDocument['playerLines'],
      homeTeamId,
      awayTeamId,
      issues,
    );
    final periods = _parsePeriods(
      legacyDocument['homeQuarterScores'],
      legacyDocument['awayQuarterScores'],
    );
    _checkScoreReconciliation(periods, homeScore, awayScore, issues);
    issues.sort((left, right) {
      final code = left.code.name.compareTo(right.code.name);
      return code == 0 ? left.path.compareTo(right.path) : code;
    });

    final unmappedSourcePaths =
        legacyDocument.keys
            .where((key) => !_rootFields.contains(key))
            .map((key) => r'$.' + key)
            .toList()
          ..sort();

    return LegacyGameStatsV2Candidate(
      scope: scope,
      source: source,
      rulesProfile: rulesProfile,
      legacyStatus: legacyStatus,
      legacyEntryMode: _stringFact(legacyDocument, 'entryMode', r'$.entryMode'),
      evidenceClassification:
          issues.any(
            (issue) =>
                issue.code !=
                LegacyGameStatsAdapterIssueCode
                    .legacyApprovalIsNotCertification,
          )
          ? LegacyEvidenceClassification.contradictory
          : LegacyEvidenceClassification.unverified,
      teams: [
        LegacyTeamStatEvidence(
          side: 'home',
          legacyTeamId: homeTeamId,
          legacyTeamName: homeTeamName,
          teamEntryId: const Fact.unknown(
            reasonCode:
                LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
          ),
          reportedScore: homeScore,
        ),
        LegacyTeamStatEvidence(
          side: 'away',
          legacyTeamId: awayTeamId,
          legacyTeamName: awayTeamName,
          teamEntryId: const Fact.unknown(
            reasonCode:
                LegacyGameStatsV2AdapterContract.identityMappingReasonCode,
          ),
          reportedScore: awayScore,
        ),
      ],
      periods: List.unmodifiable(periods),
      playerLines: List.unmodifiable(players),
      issues: List.unmodifiable(issues),
      unmappedSourcePaths: List.unmodifiable(unmappedSourcePaths),
    );
  }

  static void _requireScopeMatch(
    Map<String, Object?> source,
    String field,
    String expected,
    String? alternateExpected,
  ) {
    final value = source[field];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        r'$.'
        '$field must be a nonempty string',
      );
    }
    if (value != expected && value != alternateExpected) {
      throw FormatException(
        r'$.'
        '$field does not match the reviewed v2 scope',
      );
    }
  }

  static String _requiredText(Map<String, Object?> source, String field) {
    final value = source[field];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        r'$.'
        '$field must be a nonempty string',
      );
    }
    return value;
  }

  static Fact<String> _stringFact(
    Map<String, Object?> source,
    String field,
    String path,
  ) {
    if (!source.containsKey(field)) {
      return const Fact.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      );
    }
    final value = source[field];
    if (value == null) {
      return const Fact.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.nullReasonCode,
      );
    }
    if (value is! String || value.isEmpty) {
      throw FormatException('$path must be a nonempty string when present');
    }
    return Fact.known(value);
  }

  static Fact<int> _intFact(
    Map<String, Object?> source,
    String field,
    String path,
  ) {
    if (!source.containsKey(field)) {
      return const Fact.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      );
    }
    final value = source[field];
    if (value == null) {
      return const Fact.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.nullReasonCode,
      );
    }
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value > OfficialStatCanonicalEncoding.maxSafeInteger ||
        value != value.truncateToDouble()) {
      throw FormatException('$path must be a nonnegative safe integer');
    }
    return Fact.known(value.toInt());
  }

  static List<LegacyPlayerStatEvidence> _parsePlayers(
    Object? raw,
    String homeTeamId,
    String awayTeamId,
    List<LegacyGameStatsAdapterIssue> issues,
  ) {
    if (raw == null) return const [];
    if (raw is! Map) {
      throw FormatException(r'$.playerLines must be an object when present');
    }
    final entries = <MapEntry<String, Map<String, Object?>>>[];
    final normalizedKeys = <String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw FormatException(r'$.playerLines keys must be nonempty strings');
      }
      if (entry.value is! Map) {
        throw FormatException(r'$.playerLines values must be objects');
      }
      final normalizedKey = OfficialStatUnicodeNormalization.nfc(
        entry.key as String,
      );
      if (!normalizedKeys.add(normalizedKey)) {
        throw FormatException(
          r'$.playerLines keys must remain unique after Unicode NFC',
        );
      }
      entries.add(
        MapEntry(normalizedKey, Map<String, Object?>.from(entry.value as Map)),
      );
    }
    entries.sort((left, right) => left.key.compareTo(right.key));
    final result = <LegacyPlayerStatEvidence>[];
    for (final entry in entries) {
      final line = entry.value;
      final path = r'$.playerLines.' + entry.key;
      final teamId = _stringFact(line, 'teamId', '$path.teamId');
      if (teamId.valueOrNull case final String value
          when value != homeTeamId && value != awayTeamId) {
        issues.add(
          LegacyGameStatsAdapterIssue(
            code: LegacyGameStatsAdapterIssueCode.playerTeamOutsideGame,
            path: '$path.teamId',
          ),
        );
      }
      final offensive = _intFact(line, 'oreb', '$path.oreb');
      final defensive = _intFact(line, 'dreb', '$path.dreb');
      final explicitTotal = _intFact(line, 'reb', '$path.reb');
      Fact<int> componentTotal = const Fact.unknown(
        reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
      );
      if (offensive.valueOrNull != null && defensive.valueOrNull != null) {
        if (offensive.valueOrNull! >
            OfficialStatCanonicalEncoding.maxSafeInteger -
                defensive.valueOrNull!) {
          throw FormatException('$path rebounds exceed the safe integer range');
        }
        componentTotal = Fact.known(
          offensive.valueOrNull! + defensive.valueOrNull!,
        );
      }
      if (explicitTotal.valueOrNull != null &&
          offensive.valueOrNull != null &&
          defensive.valueOrNull != null &&
          explicitTotal.valueOrNull !=
              offensive.valueOrNull! + defensive.valueOrNull!) {
        issues.add(
          LegacyGameStatsAdapterIssue(
            code: LegacyGameStatsAdapterIssueCode.reportedReboundMismatch,
            path: '$path.reb',
          ),
        );
      }
      final unmapped =
          line.keys
              .where((key) => !_playerFields.contains(key))
              .map((key) => '$path.$key')
              .toList()
            ..sort();
      result.add(
        LegacyPlayerStatEvidence(
          legacyPlayerKey: entry.key,
          legacyTeamId: teamId,
          reportedName: _stringFact(line, 'name', '$path.name'),
          reportedPoints: _intFact(line, 'pts', '$path.pts'),
          reportedOffensiveRebounds: offensive,
          reportedDefensiveRebounds: defensive,
          reportedTotalRebounds: explicitTotal,
          componentDerivedTotalRebounds: componentTotal,
          reportedAssists: _intFact(line, 'ast', '$path.ast'),
          reportedSteals: _intFact(line, 'stl', '$path.stl'),
          reportedBlocks: _intFact(line, 'blk', '$path.blk'),
          reportedFouls: _intFact(line, 'fls', '$path.fls'),
          reportedMinutes: _intFact(line, 'min', '$path.min'),
          unmappedSourcePaths: List.unmodifiable(unmapped),
        ),
      );
    }
    return result;
  }

  static List<LegacyPeriodScoreEvidence> _parsePeriods(
    Object? rawHome,
    Object? rawAway,
  ) {
    final home = _parsePeriodMap(rawHome, r'$.homeQuarterScores');
    final away = _parsePeriodMap(rawAway, r'$.awayQuarterScores');
    final numbers = {...home.keys, ...away.keys}.toList()..sort();
    return [
      for (final number in numbers)
        LegacyPeriodScoreEvidence(
          legacyPeriodNumber: number,
          homeScore:
              home[number] ??
              const Fact.unknown(
                reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
              ),
          awayScore:
              away[number] ??
              const Fact.unknown(
                reasonCode: LegacyGameStatsV2AdapterContract.missingReasonCode,
              ),
        ),
    ];
  }

  static Map<int, Fact<int>> _parsePeriodMap(Object? raw, String path) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw FormatException('$path must be an object when present');
    }
    final result = <int, Fact<int>>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final number = key is int ? key : int.tryParse(key.toString());
      if (number == null || number <= 0 || result.containsKey(number)) {
        throw FormatException('$path keys must be unique positive integers');
      }
      result[number] = _intFact(
        <String, Object?>{'value': entry.value},
        'value',
        '$path.$key',
      );
    }
    return result;
  }

  static void _checkScoreReconciliation(
    List<LegacyPeriodScoreEvidence> periods,
    Fact<int> homeScore,
    Fact<int> awayScore,
    List<LegacyGameStatsAdapterIssue> issues,
  ) {
    void check(
      String side,
      Fact<int> finalScore,
      Fact<int> Function(LegacyPeriodScoreEvidence period) select,
    ) {
      if (periods.isEmpty || finalScore.valueOrNull == null) return;
      final facts = periods.map(select).toList();
      if (facts.any((fact) => fact.valueOrNull == null)) return;
      var sum = 0;
      for (final fact in facts) {
        if (sum >
            OfficialStatCanonicalEncoding.maxSafeInteger - fact.valueOrNull!) {
          throw FormatException(
            r'$.period scores exceed the safe integer range',
          );
        }
        sum += fact.valueOrNull!;
      }
      if (sum != finalScore.valueOrNull) {
        issues.add(
          LegacyGameStatsAdapterIssue(
            code: LegacyGameStatsAdapterIssueCode.reportedScorePeriodMismatch,
            path: '\$.${side}Score',
          ),
        );
      }
    }

    check('home', homeScore, (period) => period.homeScore);
    check('away', awayScore, (period) => period.awayScore);
  }
}
