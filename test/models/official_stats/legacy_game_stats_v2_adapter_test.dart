import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/calculators/normalized_box_score.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/models/official_stats/legacy_game_stats_v2_adapter.dart';
import 'package:hoops_connect/models/official_stats/unicode_normalization.dart';

Map<String, dynamic> _loadFixture() =>
    jsonDecode(
          File(
            'contracts/official_stats/v2/'
            'legacy_game_stats_adapter_fixtures.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

GameScope _scope(Map<String, dynamic> raw) => GameScope(
  associationId: raw['associationId'] as String,
  competitionId: raw['competitionId'] as String,
  seasonId: raw['seasonId'] as String,
  divisionId: raw['divisionId'] as String,
  phaseId: raw['phaseId'] as String,
  gameId: raw['gameId'] as String,
);

LegacyGameStatsSourceReference _source(Map<String, dynamic> raw) =>
    LegacyGameStatsSourceReference(
      documentId: raw['documentId'] as String,
      sourcePath: raw['sourcePath'] as String,
      sourcePayloadHash: raw['sourcePayloadHash'] as String,
    );

OfficialStatRulesProfilePin _rulesProfile(Map<String, dynamic> raw) {
  final version = raw['rulesetVersion'] as Map<String, dynamic>;
  return OfficialStatRulesProfilePin(
    rulesProfileId: raw['rulesProfileId'] as String,
    rulesetVersion: VersionReference(
      associationId: version['associationId'] as String,
      versionId: version['versionId'] as String,
      sha256: version['sha256'] as String,
    ),
  );
}

LegacyGameStatsV2Candidate _adaptCase(Map<String, dynamic> fixtureCase) =>
    ReadOnlyLegacyGameStatsV2Adapter().adapt(
      source: _source(fixtureCase['source'] as Map<String, dynamic>),
      legacyDocument: Map<String, Object?>.from(
        fixtureCase['legacyDocument'] as Map,
      ),
      scope: _scope(fixtureCase['scope'] as Map<String, dynamic>),
      rulesProfile: _rulesProfile(
        fixtureCase['rulesProfile'] as Map<String, dynamic>,
      ),
    );

Map<String, Object?> _baseLegacyDocument() => {
  'eventId': 'game_1',
  'seasonId': 'season_2026',
  'divisionId': 'division_1',
  'homeTeamId': 'legacy_home',
  'awayTeamId': 'legacy_away',
  'homeTeamName': 'Home',
  'awayTeamName': 'Away',
};

GameScope _baseScope() => GameScope(
  associationId: 'jba',
  competitionId: 'nbl',
  seasonId: 'season_2026',
  divisionId: 'division_1',
  phaseId: 'regular',
  gameId: 'game_1',
);

LegacyGameStatsSourceReference _baseSource() => LegacyGameStatsSourceReference(
  documentId: 'game_1',
  sourcePath: 'associations/jba/gameStats/game_1',
  sourcePayloadHash: List.filled(64, 'a').join(),
);

OfficialStatRulesProfilePin _baseRules({
  String profileId = 'rules_profile_fixture_v1',
}) => OfficialStatRulesProfilePin(
  rulesProfileId: profileId,
  rulesetVersion: VersionReference(
    associationId: 'jba',
    versionId: 'rules_fixture_v1',
    sha256: List.filled(64, 'b').join(),
  ),
);

Set<String> _reachableLocalDartFiles(Iterable<String> entrypoints) {
  final libRoot = Directory('lib').absolute.path;
  final pending = <String>[
    for (final entrypoint in entrypoints) File(entrypoint).absolute.path,
  ];
  final visited = <String>{};
  final directivePattern = RegExp(
    r'''(?:^|\n)\s*(?:import|export|part)\s+([^;]+);''',
  );
  final uriPattern = RegExp(r'''["']([^"']+)["']''');

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!visited.add(current)) continue;
    final file = File(current);
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    for (final directive in directivePattern.allMatches(source)) {
      final body = directive.group(1)!;
      for (final uriMatch in uriPattern.allMatches(body)) {
        final importUri = uriMatch.group(1)!;
        String? resolved;
        const packagePrefix = 'package:hoops_connect/';
        if (importUri.startsWith(packagePrefix)) {
          resolved = File(
            'lib/${importUri.substring(packagePrefix.length)}',
          ).absolute.path;
        } else if (!Uri.parse(importUri).hasScheme) {
          resolved = File.fromUri(file.absolute.uri.resolve(importUri)).path;
        }
        if (resolved != null &&
            resolved.startsWith('$libRoot${Platform.pathSeparator}') &&
            resolved.endsWith('.dart') &&
            File(resolved).existsSync()) {
          pending.add(resolved);
        }
      }
    }
  }
  return visited;
}

void main() {
  final fixture = _loadFixture();

  group('legacy game-stats v2 candidate contract', () {
    test('fixture pins adapter and candidate schema versions', () {
      expect(
        fixture['adapterVersion'],
        LegacyGameStatsV2AdapterContract.adapterVersion,
      );
      expect(
        fixture['candidateSchemaVersion'],
        LegacyGameStatsV2AdapterContract.candidateSchemaVersion,
      );
      expect(
        fixture['canonicalEncodingVersion'],
        OfficialStatContractVersions.canonicalEncoding,
      );
      expect(
        fixture['unicodeNormalizationVersion'],
        normalizedBoxScoreUnicodeVersion,
      );
      expect(
        fixture['unicodeNormalizationImplementationVersion'],
        OfficialStatUnicodeNormalization.implementationVersion,
      );
    });

    test('canonical candidate is deterministic and source ordered', () {
      final fixtureCase =
          (fixture['cases'] as List).single as Map<String, dynamic>;
      final expected = fixtureCase['expected'] as Map<String, dynamic>;
      final first = _adaptCase(fixtureCase);
      final second = _adaptCase(fixtureCase);

      expect(first.canonicalJson, second.canonicalJson);
      expect(first.scopeBinding.kind, LegacyGameStatsScopeBindingKind.exact);
      expect(
        first.toContractMap()['canonicalEncodingVersion'],
        fixture['canonicalEncodingVersion'],
      );
      expect(
        first.toContractMap()['unicodeNormalizationVersion'],
        fixture['unicodeNormalizationVersion'],
      );
      expect(first.candidateHash, expected['candidateHash']);
      expect(first.canonicalByteLength, expected['canonicalByteLength']);
      expect(
        first.evidenceClassification.name,
        expected['evidenceClassification'],
      );
      expect(
        first.issues.map((issue) => issue.code.name),
        expected['issueCodes'],
      );
      expect(
        first.playerLines.map((player) => player.legacyPlayerKey),
        expected['playerOrder'],
      );
      expect(first.unmappedSourcePaths, expected['rootUnmappedSourcePaths']);
    });

    test('explicit zero remains known while absent facts remain unknown', () {
      final fixtureCase =
          (fixture['cases'] as List).single as Map<String, dynamic>;
      final candidate = _adaptCase(fixtureCase);
      final zeroLine = candidate.playerLines.singleWhere(
        (player) => player.legacyPlayerKey == 'legacy_player_2',
      );
      final sparseLine = candidate.playerLines.singleWhere(
        (player) => player.legacyPlayerKey == 'legacy_player_1',
      );

      expect(zeroLine.reportedPoints.state, FactState.known);
      expect(zeroLine.reportedPoints.valueOrNull, 0);
      expect(sparseLine.reportedTotalRebounds.state, FactState.unknown);
      expect(sparseLine.componentDerivedTotalRebounds.valueOrNull, 7);
      expect(
        (sparseLine.toContractMap()['normalizedInputFacts'] as Map)['twoMade'],
        {
          'reasonCode': LegacyGameStatsV2AdapterContract.missingReasonCode,
          'state': 'unknown',
          'value': null,
        },
      );
      expect(
        (sparseLine.toContractMap()['normalizedInputFacts']
            as Map)['turnovers'],
        isNot({'state': 'known', 'value': 0}),
      );
      expect(
        (sparseLine.toContractMap()['normalizedInputFacts'] as Map)['assists'],
        {'state': 'known', 'value': 4},
      );
      expect(zeroLine.unmappedSourcePaths, [
        r'$.playerLines.legacy_player_2.legacyExtension',
      ]);
    });

    test(
      'legacy approval cannot become a v2 certification or calculator input',
      () {
        final fixtureCase =
            (fixture['cases'] as List).single as Map<String, dynamic>;
        final candidate = _adaptCase(fixtureCase);

        expect(candidate.legacyStatus.valueOrNull, 'approved');
        expect(candidate.certificationAllowed, isFalse);
        expect(candidate.calculatorInputAllowed, isFalse);
        expect(
          candidate.calculatorBlockers,
          contains('shooting_breakdown_not_recorded'),
        );
        expect(
          candidate.calculatorBlockers,
          contains('turnovers_not_recorded'),
        );
      },
    );

    test(
      'rules are an explicit versioned dependency, never inferred from periods',
      () {
        final source = _baseLegacyDocument()
          ..addAll({
            'homeQuarterScores': {'1': 1, '2': 1, '3': 1, '4': 1, '5': 1},
            'awayQuarterScores': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
            'homeScore': 5,
            'awayScore': 0,
          });
        final first = ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: source,
          scope: _baseScope(),
          rulesProfile: _baseRules(profileId: 'explicit_profile_a'),
        );
        final second = ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: source,
          scope: _baseScope(),
          rulesProfile: _baseRules(profileId: 'explicit_profile_b'),
        );

        expect(first.periods, hasLength(5));
        expect(first.rulesProfile.rulesProfileId, 'explicit_profile_a');
        expect(first.candidateHash, isNot(second.candidateHash));
        expect(first.canonicalJson, isNot(contains('nominalDurationMs')));
        expect(first.canonicalJson, isNot(contains('regulationPeriodCount')));
      },
    );

    test(
      'scope mismatch fails closed instead of guessing a season or game',
      () {
        final source = _baseLegacyDocument()..['seasonId'] = 'another_season';

        expect(
          () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
            source: _baseSource(),
            legacyDocument: source,
            scope: _baseScope(),
            rulesProfile: _baseRules(),
          ),
          throwsFormatException,
        );
      },
    );

    test('source association mismatch fails closed', () {
      final source = LegacyGameStatsSourceReference(
        documentId: 'game_1',
        sourcePath: 'associations/another/gameStats/game_1',
        sourcePayloadHash: List.filled(64, 'a').join(),
      );

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: source,
          legacyDocument: _baseLegacyDocument(),
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test('source document mismatch requires an explicit reviewed mapping', () {
      final source = LegacyGameStatsSourceReference(
        documentId: 'legacy_document',
        sourcePath: 'associations/jba/gameStats/legacy_document',
        sourcePayloadHash: List.filled(64, 'a').join(),
      );

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: source,
          legacyDocument: _baseLegacyDocument(),
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test('source event mismatch requires an explicit reviewed mapping', () {
      final legacy = _baseLegacyDocument()..['eventId'] = 'legacy_event';

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: legacy,
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test(
      'hash-bound reviewed mapping permits differing document and event IDs',
      () {
        final source = LegacyGameStatsSourceReference(
          documentId: 'legacy_document',
          sourcePath: 'associations/jba/gameStats/legacy_document',
          sourcePayloadHash: List.filled(64, 'a').join(),
        );
        final legacy = _baseLegacyDocument()..['eventId'] = 'legacy_event';
        final mapping = LegacyGameStatsReviewedScopeMapping(
          sourceDocumentId: 'legacy_document',
          sourceEventId: 'legacy_event',
          targetGameId: 'game_1',
          mappingVersion: 'legacy_game_mapping_v1',
          evidenceHash: List.filled(64, 'c').join(),
        );
        final candidate = ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: source,
          legacyDocument: legacy,
          scope: _baseScope(),
          rulesProfile: _baseRules(),
          reviewedScopeMapping: mapping,
        );
        final differentEvidenceCandidate = ReadOnlyLegacyGameStatsV2Adapter()
            .adapt(
              source: source,
              legacyDocument: legacy,
              scope: _baseScope(),
              rulesProfile: _baseRules(),
              reviewedScopeMapping: LegacyGameStatsReviewedScopeMapping(
                sourceDocumentId: 'legacy_document',
                sourceEventId: 'legacy_event',
                targetGameId: 'game_1',
                mappingVersion: 'legacy_game_mapping_v1',
                evidenceHash: List.filled(64, 'd').join(),
              ),
            );

        expect(
          candidate.scopeBinding.kind,
          LegacyGameStatsScopeBindingKind.reviewedMapping,
        );
        expect(
          candidate.scopeBinding.reviewedMapping?.evidenceHash,
          mapping.evidenceHash,
        );
        expect(candidate.toContractMap()['scopeBinding'], isNotNull);
        expect(
          candidate.candidateHash,
          isNot(differentEvidenceCandidate.candidateHash),
        );
      },
    );

    test('source path is bound to the exact source document ID', () {
      expect(
        () => LegacyGameStatsSourceReference(
          documentId: 'game_1',
          sourcePath: 'associations/jba/gameStats/game_2',
          sourcePayloadHash: List.filled(64, 'a').join(),
        ),
        throwsFormatException,
      );
    });

    test('contradictions remain visible and cannot be certified', () {
      final source = _baseLegacyDocument()
        ..addAll({
          'homeScore': 3,
          'awayScore': 0,
          'homeQuarterScores': {'1': 2},
          'awayQuarterScores': {'1': 0},
          'playerLines': {
            'legacy_player': {
              'name': 'Player',
              'teamId': 'third_team',
              'oreb': 1,
              'dreb': 2,
              'reb': 9,
            },
          },
        });
      final candidate = ReadOnlyLegacyGameStatsV2Adapter().adapt(
        source: _baseSource(),
        legacyDocument: source,
        scope: _baseScope(),
        rulesProfile: _baseRules(),
      );

      expect(candidate.evidenceClassification.name, 'contradictory');
      expect(
        candidate.issues.map((issue) => issue.code.name),
        containsAll([
          'playerTeamOutsideGame',
          'reportedReboundMismatch',
          'reportedScorePeriodMismatch',
        ]),
      );
      expect(candidate.certificationAllowed, isFalse);
    });

    test('malformed legacy counters reject instead of coercing', () {
      final source = _baseLegacyDocument()
        ..['playerLines'] = {
          'legacy_player': {'name': 'Player', 'pts': -1},
        };

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: source,
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test('source player keys cannot collide after canonical Unicode NFC', () {
      final source = _baseLegacyDocument()
        ..['playerLines'] = {
          'Cafe\u0301': {'name': 'First'},
          'Café': {'name': 'Second'},
        };

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: source,
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test('canonically equivalent home and away team IDs collide', () {
      final legacy = _baseLegacyDocument()
        ..['homeTeamId'] = 'Cafe\u0301'
        ..['awayTeamId'] = 'Café';
      final candidate = ReadOnlyLegacyGameStatsV2Adapter().adapt(
        source: _baseSource(),
        legacyDocument: legacy,
        scope: _baseScope(),
        rulesProfile: _baseRules(),
      );

      expect(candidate.teams[0].legacyTeamId, 'Café');
      expect(candidate.teams[1].legacyTeamId, 'Café');
      expect(
        candidate.issues.map((issue) => issue.code),
        contains(LegacyGameStatsAdapterIssueCode.homeAwayTeamCollision),
      );
    });

    test('canonically equivalent player and game team IDs match', () {
      final legacy = _baseLegacyDocument()
        ..['homeTeamId'] = 'Café'
        ..['playerLines'] = {
          'player_1': {'name': 'Player', 'teamId': 'Cafe\u0301'},
        };
      final candidate = ReadOnlyLegacyGameStatsV2Adapter().adapt(
        source: _baseSource(),
        legacyDocument: legacy,
        scope: _baseScope(),
        rulesProfile: _baseRules(),
      );

      expect(candidate.playerLines.single.legacyTeamId.valueOrNull, 'Café');
      expect(
        candidate.issues.map((issue) => issue.code),
        isNot(contains(LegacyGameStatsAdapterIssueCode.playerTeamOutsideGame)),
      );
    });

    test('maximum canonical-safe period number is preserved', () {
      final maximum = OfficialStatCanonicalEncoding.maxSafeInteger;
      final legacy = _baseLegacyDocument()
        ..['homeQuarterScores'] = {'$maximum': 0}
        ..['awayQuarterScores'] = {'$maximum': 0};
      final candidate = ReadOnlyLegacyGameStatsV2Adapter().adapt(
        source: _baseSource(),
        legacyDocument: legacy,
        scope: _baseScope(),
        rulesProfile: _baseRules(),
      );

      expect(candidate.periods.single.legacyPeriodNumber, maximum);
    });

    test('period number above canonical-safe range fails during adapt', () {
      final aboveMaximum = OfficialStatCanonicalEncoding.maxSafeInteger + 1;
      final legacy = _baseLegacyDocument()
        ..['homeQuarterScores'] = {'$aboveMaximum': 0};

      expect(
        () => ReadOnlyLegacyGameStatsV2Adapter().adapt(
          source: _baseSource(),
          legacyDocument: legacy,
          scope: _baseScope(),
          rulesProfile: _baseRules(),
        ),
        throwsFormatException,
      );
    });

    test('candidate module remains outside production import roots', () {
      final productionEntrypoints = Directory('lib')
          .listSync()
          .whereType<File>()
          .where(
            (file) => RegExp(
              r'^main[^/]*\.dart$',
            ).hasMatch(file.uri.pathSegments.last),
          )
          .map((file) => file.path)
          .toList();
      final reachable = _reachableLocalDartFiles(productionEntrypoints);
      final candidatePath = File(
        'lib/models/official_stats/legacy_game_stats_v2_adapter.dart',
      ).absolute.path;

      expect(productionEntrypoints, isNotEmpty);
      expect(reachable.length, greaterThan(10));
      expect(reachable, isNot(contains(candidatePath)));
    });
  });
}
