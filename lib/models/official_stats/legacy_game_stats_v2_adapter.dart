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
  static const String sourceIdentityEncodingVersion = 'utf8-hex-v1';
  static const String missingReasonCode = 'not_recorded_legacy_game_stats';
  static const String nullReasonCode = 'null_legacy_game_stats_value';
  static const String identityMappingReasonCode =
      'identity_mapping_not_reviewed';
}

String _requireRawLegacyKey(String field, String value) {
  if (value.isEmpty) {
    throw FormatException('$field must not be empty');
  }
  return value;
}

String _legacyComparisonKey(String value) =>
    OfficialStatUnicodeNormalization.nfc(value);

String _utf8Hex(String value) => utf8
    .encode(value)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

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
    required String documentId,
    required String sourcePath,
    required this.sourcePayloadHash,
  }) : documentId = _requireRawLegacyKey('documentId', documentId),
       sourcePath = _requireRawLegacyKey('sourcePath', sourcePath) {
    final segments = this.sourcePath.split('/');
    if (segments.length != 4 ||
        segments[0] != 'associations' ||
        segments[1].isEmpty ||
        segments[2] != 'gameStats' ||
        segments[3].isEmpty) {
      throw FormatException(
        'Legacy source path must be associations/{associationId}/gameStats/{documentId}',
      );
    }
    if (segments[3] != this.documentId) {
      throw FormatException(
        'Legacy source path must terminate in the exact document ID',
      );
    }
    OfficialStatIdentifiers.requireSha256(
      'sourcePayloadHash',
      sourcePayloadHash,
    );
  }

  String get associationId => sourcePath.split('/')[1];

  Map<String, Object?> toContractMap() => {
    'documentId': documentId,
    'documentIdUtf8Hex': _utf8Hex(documentId),
    'sourcePath': sourcePath,
    'sourcePathUtf8Hex': _utf8Hex(sourcePath),
    'sourcePayloadHash': sourcePayloadHash,
    'sourceSchemaVersion': LegacyGameStatsV2AdapterContract.sourceSchemaVersion,
  };
}

enum LegacyGameStatsScopeBindingKind { exact, reviewedMapping }

/// A reviewed one-direction source-game to v2-game mapping.
///
/// Association identity is never remapped: the source path association must
/// still equal the v2 [GameScope.associationId]. The mapping exists only for a
/// legacy document/event identifier that differs from the reviewed v2 game ID.
final class LegacyGameStatsReviewedScopeMapping {
  final String sourceDocumentId;
  final String sourceEventId;
  final String targetGameId;
  final String mappingVersion;
  final String evidenceHash;

  LegacyGameStatsReviewedScopeMapping({
    required String sourceDocumentId,
    required String sourceEventId,
    required String targetGameId,
    required this.mappingVersion,
    required this.evidenceHash,
  }) : sourceDocumentId = _requireRawLegacyKey(
         'sourceDocumentId',
         sourceDocumentId,
       ),
       sourceEventId = _requireRawLegacyKey('sourceEventId', sourceEventId),
       targetGameId = _requireRawLegacyKey('targetGameId', targetGameId) {
    OfficialStatIdentifiers.requireValid('mappingVersion', mappingVersion);
    OfficialStatIdentifiers.requireSha256('evidenceHash', evidenceHash);
  }

  Map<String, Object?> toContractMap() => {
    'evidenceHash': evidenceHash,
    'mappingVersion': mappingVersion,
    'sourceDocumentId': sourceDocumentId,
    'sourceDocumentIdUtf8Hex': _utf8Hex(sourceDocumentId),
    'sourceEventId': sourceEventId,
    'sourceEventIdUtf8Hex': _utf8Hex(sourceEventId),
    'targetGameId': targetGameId,
  };
}

/// The exact source association/document/event binding included in candidate
/// content identity. Differing game IDs require a reviewed mapping and hash.
final class LegacyGameStatsScopeBinding {
  final LegacyGameStatsScopeBindingKind kind;
  final String sourceAssociationId;
  final String sourceDocumentId;
  final String sourceEventId;
  final String targetGameId;
  final LegacyGameStatsReviewedScopeMapping? reviewedMapping;

  const LegacyGameStatsScopeBinding._({
    required this.kind,
    required this.sourceAssociationId,
    required this.sourceDocumentId,
    required this.sourceEventId,
    required this.targetGameId,
    required this.reviewedMapping,
  });

  Map<String, Object?> toContractMap() => {
    'kind': kind.name,
    'reviewedMapping': reviewedMapping == null
        ? const Fact<String>.notApplicable(
            reasonCode: 'exact_source_game_identity',
          ).toContractMap((value) => value)
        : {'state': 'known', 'value': reviewedMapping!.toContractMap()},
    'sourceAssociationId': sourceAssociationId,
    'sourceAssociationIdUtf8Hex': _utf8Hex(sourceAssociationId),
    'sourceDocumentId': sourceDocumentId,
    'sourceDocumentIdUtf8Hex': _utf8Hex(sourceDocumentId),
    'sourceEventId': sourceEventId,
    'sourceEventIdUtf8Hex': _utf8Hex(sourceEventId),
    'targetGameId': targetGameId,
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
    'legacyTeamIdUtf8Hex': _utf8Hex(legacyTeamId),
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
    'legacyPlayerKeyUtf8Hex': _utf8Hex(legacyPlayerKey),
    'legacyTeamId': legacyTeamId.toContractMap((value) => value),
    'legacyTeamIdUtf8Hex': legacyTeamId.toContractMap(_utf8Hex),
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
  final LegacyGameStatsScopeBinding scopeBinding;
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
    required this.scopeBinding,
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
    'canonicalEncodingVersion': OfficialStatContractVersions.canonicalEncoding,
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
    'scopeBinding': scopeBinding.toContractMap(),
    'source': source.toContractMap(),
    'sourceIdentityEncodingVersion':
        LegacyGameStatsV2AdapterContract.sourceIdentityEncodingVersion,
    'targetCalculatorVersion': normalizedBoxScoreCalculatorVersion,
    'teams': [for (final team in teams) team.toContractMap()],
    'unicodeNormalizationImplementationVersion':
        OfficialStatUnicodeNormalization.implementationVersion,
    'unicodeNormalizationVersion': normalizedBoxScoreUnicodeVersion,
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
    LegacyGameStatsReviewedScopeMapping? reviewedScopeMapping,
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
    LegacyGameStatsReviewedScopeMapping? reviewedScopeMapping,
  }) {
    if (rulesProfile.rulesetVersion.associationId != scope.associationId) {
      throw ArgumentError(
        'Rules profile and game scope must share one association',
      );
    }
    final sourceEventId = _requiredText(legacyDocument, 'eventId');
    final scopeBinding = _bindScope(
      source: source,
      sourceEventId: sourceEventId,
      scope: scope,
      reviewedScopeMapping: reviewedScopeMapping,
    );
    _requireScopeMatch(legacyDocument, 'seasonId', scope.seasonId);
    _requireScopeMatch(legacyDocument, 'divisionId', scope.divisionId);

    final homeTeamId = _requiredText(legacyDocument, 'homeTeamId');
    final awayTeamId = _requiredText(legacyDocument, 'awayTeamId');
    final homeTeamName = _requiredText(legacyDocument, 'homeTeamName');
    final awayTeamName = _requiredText(legacyDocument, 'awayTeamName');
    final homeScore = _intFact(legacyDocument, 'homeScore', r'$.homeScore');
    final awayScore = _intFact(legacyDocument, 'awayScore', r'$.awayScore');
    final issues = <LegacyGameStatsAdapterIssue>[];
    if (_legacyComparisonKey(homeTeamId) == _legacyComparisonKey(awayTeamId)) {
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
      scopeBinding: scopeBinding,
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
  ) {
    final value = source[field];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        r'$.'
        '$field must be a nonempty string',
      );
    }
    if (value != expected) {
      throw FormatException(
        r'$.'
        '$field does not match the reviewed v2 scope',
      );
    }
  }

  static LegacyGameStatsScopeBinding _bindScope({
    required LegacyGameStatsSourceReference source,
    required String sourceEventId,
    required GameScope scope,
    required LegacyGameStatsReviewedScopeMapping? reviewedScopeMapping,
  }) {
    if (source.associationId != scope.associationId) {
      throw FormatException(
        'Legacy source association does not match the reviewed v2 scope',
      );
    }
    final hasExactSourceGameIdentity =
        source.documentId == scope.gameId && sourceEventId == scope.gameId;
    if (reviewedScopeMapping != null && hasExactSourceGameIdentity) {
      throw FormatException(
        'Reviewed scope mapping is redundant for exact source game identity',
      );
    }
    if (reviewedScopeMapping == null) {
      if (!hasExactSourceGameIdentity) {
        throw FormatException(
          'Legacy document and event IDs must match the v2 game or use a reviewed mapping',
        );
      }
      return LegacyGameStatsScopeBinding._(
        kind: LegacyGameStatsScopeBindingKind.exact,
        sourceAssociationId: source.associationId,
        sourceDocumentId: source.documentId,
        sourceEventId: sourceEventId,
        targetGameId: scope.gameId,
        reviewedMapping: null,
      );
    }
    if (reviewedScopeMapping.sourceDocumentId != source.documentId ||
        reviewedScopeMapping.sourceEventId != sourceEventId ||
        reviewedScopeMapping.targetGameId != scope.gameId) {
      throw FormatException(
        'Reviewed scope mapping does not bind the exact source and target game',
      );
    }
    return LegacyGameStatsScopeBinding._(
      kind: LegacyGameStatsScopeBindingKind.reviewedMapping,
      sourceAssociationId: source.associationId,
      sourceDocumentId: source.documentId,
      sourceEventId: sourceEventId,
      targetGameId: scope.gameId,
      reviewedMapping: reviewedScopeMapping,
    );
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

  static Fact<String> _identityFact(
    Map<String, Object?> source,
    String field,
    String path,
  ) {
    final fact = _stringFact(source, field, path);
    final value = fact.valueOrNull;
    return value == null
        ? fact
        : Fact.known(_requireRawLegacyKey(field, value));
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
    for (final entry in raw.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw FormatException(r'$.playerLines keys must be nonempty strings');
      }
      if (entry.value is! Map) {
        throw FormatException(r'$.playerLines values must be objects');
      }
      entries.add(
        MapEntry(
          entry.key as String,
          Map<String, Object?>.from(entry.value as Map),
        ),
      );
    }
    entries.sort(
      (left, right) => _utf8Hex(left.key).compareTo(_utf8Hex(right.key)),
    );
    final result = <LegacyPlayerStatEvidence>[];
    for (final entry in entries) {
      final line = entry.value;
      final path = r'$.playerLines.' + entry.key;
      final teamId = _identityFact(line, 'teamId', '$path.teamId');
      if (teamId.valueOrNull case final String value
          when _legacyComparisonKey(value) !=
                  _legacyComparisonKey(homeTeamId) &&
              _legacyComparisonKey(value) != _legacyComparisonKey(awayTeamId)) {
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
      if (number == null ||
          number <= 0 ||
          number > OfficialStatCanonicalEncoding.maxSafeInteger ||
          result.containsKey(number)) {
        throw FormatException(
          '$path keys must be unique positive canonical safe integers',
        );
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
