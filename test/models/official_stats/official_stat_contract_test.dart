import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/command_contract.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/models/official_stats/schema_registry.dart';

Map<String, dynamic> loadFixture() =>
    jsonDecode(
          File(
            'contracts/official_stats/v2/contract_fixtures.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<String> names<T extends Enum>(Iterable<T> values) =>
    values.map((value) => value.name).toList();

void main() {
  final fixture = loadFixture();

  group('version contract', () {
    test('runtime constants match the machine-readable fixture', () {
      final versions = fixture['versions'] as Map<String, dynamic>;
      expect(
        OfficialStatContractVersions.dataSchema,
        versions['dataSchemaVersion'],
      );
      expect(
        OfficialStatContractVersions.domainSchema,
        versions['domainSchemaVersion'],
      );
      expect(
        OfficialStatContractVersions.commandSchema,
        versions['commandSchemaVersion'],
      );
      expect(
        OfficialStatContractVersions.authorizationSchema,
        versions['authorizationSchemaVersion'],
      );
      expect(
        OfficialStatContractVersions.projectionSchema,
        versions['projectionSchemaVersion'],
      );
      expect(
        OfficialStatContractVersions.canonicalEncoding,
        versions['canonicalEncodingVersion'],
      );
    });

    test('every interpretation dependency is pinned', () {
      final fields =
          (fixture['versions']
                  as Map<String, dynamic>)['requiredPinnedVersions']
              as List<dynamic>;
      final version = VersionReference(
        associationId: 'jba',
        versionId: 'v1',
        sha256: List.filled(64, 'a').join(),
      );
      final map = OfficialStatVersionSet(
        rulesetVersion: version,
        policyVersion: version,
        calculatorVersion: version,
        projectionVersion: version,
        identityResolutionVersion: version,
        privacyPolicyVersion: version,
        brandingVersion: version,
      ).toContractMap();
      expect(fields.every(map.containsKey), isTrue);
    });
  });

  group('scope and identifiers', () {
    test('GameScope is complete and stable', () {
      final scope = GameScope(
        associationId: 'jba',
        competitionId: 'nbl',
        seasonId: 'season_2026',
        divisionId: 'division_1',
        phaseId: 'regular',
        gameId: 'game_1',
      );
      expect(scope.key, 'jba/nbl/season_2026/division_1/regular/game_1');
      expect(scope.toContractMap().values, everyElement(isNotEmpty));
    });

    test('scope rejects path separators and empty IDs', () {
      expect(
        () => GameScope(
          associationId: 'jba/other',
          competitionId: 'nbl',
          seasonId: 's',
          divisionId: 'd',
          phaseId: 'p',
          gameId: 'g',
        ),
        throwsFormatException,
      );
    });

    test('jerseys remain strings and preserve 0 versus 00', () {
      final scope = GameScope(
        associationId: 'jba',
        competitionId: 'nbl',
        seasonId: 's',
        divisionId: 'd',
        phaseId: 'p',
        gameId: 'g',
      );
      GameParticipantSnapshotContract participant(String id, String jersey) =>
          GameParticipantSnapshotContract(
            scope: scope,
            snapshotId: 'snapshot',
            snapshotHash: List.filled(64, 'a').join(),
            participantId: id,
            playerId: 'player_$id',
            rosterMembershipId: 'membership_$id',
            rosterMembershipVersionId: 'membership_version_$id',
            teamEntryId: 'entry',
            jersey: jersey,
            displayNameVersionId: 'display_v1',
            eligibilityStatus: EligibilityStatus.eligible,
          );
      expect(
        participant('one', '0').jersey,
        isNot(participant('two', '00').jersey),
      );
    });
  });

  group('explicit fact semantics', () {
    test('known zero is distinct from unknown and not-applicable', () {
      const Fact<int> zero = Fact.known(0);
      const Fact<int> unknown = Fact.unknown(reasonCode: 'not_recorded');
      const Fact<int> notApplicable = Fact.notApplicable(
        reasonCode: 'result_only',
      );
      expect(zero.valueOrNull, 0);
      expect(unknown.valueOrNull, isNull);
      expect(notApplicable.valueOrNull, isNull);
      expect(zero.state, isNot(unknown.state));
      expect(unknown.state, isNot(notApplicable.state));
      expect(
        unknown.toContractMap((value) => value),
        fixture['factSemantics']['unknown'],
      );
    });

    test('time may remain explicitly unknown; no default minutes exist', () {
      const Fact<int> playedTimeMs = Fact.unknown(reasonCode: 'no_time_source');
      expect(playedTimeMs.valueOrNull, isNull);
      expect(playedTimeMs.toContractMap((value) => value)['value'], isNull);
    });
  });

  group('strict lifecycle', () {
    test('enum wire values match fixtures', () {
      final states = fixture['states'] as Map<String, dynamic>;
      expect(names(PlayState.values), states['play']);
      expect(names(ReviewState.values), states['review']);
      expect(names(PublicationState.values), states['publication']);
      expect(
        ResultDisposition.values.map((value) => value.wireName),
        states['resultDisposition'],
      );
      expect(
        names(StatisticsDisposition.values),
        states['statisticsDisposition'],
      );
      expect(names(PrivacyPermissionState.values), states['privacy']);
      expect(names(JournalOperationType.values), states['journalOperation']);
      expect(names(JournalDeliveryState.values), states['journalDelivery']);
      expect(names(BoxScorePartKind.values), states['boxScorePartKind']);
      expect(
        names(LegacyEvidenceClassification.values),
        states['legacyClassification'],
      );
      expect(
        LegacyEvidenceClassification.values,
        everyElement(
          predicate<LegacyEvidenceClassification>(
            (classification) => !classification.permitsAutomaticCertification,
          ),
        ),
        reason: 'legacy approved/evidenced records require deliberate review',
      );
    });

    test('only fixture-listed transitions are allowed', () {
      final transitions = fixture['transitions'] as Map<String, dynamic>;
      final allowedPlay = {
        for (final pair in transitions['play'] as List<dynamic>)
          '${pair[0]}>${pair[1]}',
      };
      for (final from in PlayState.values) {
        for (final to in PlayState.values) {
          expect(
            OfficialStatLifecycle.permitsPlay(from, to),
            allowedPlay.contains('${from.name}>${to.name}'),
            reason: '${from.name} -> ${to.name}',
          );
        }
      }

      final allowedReview = {
        for (final pair in transitions['review'] as List<dynamic>)
          '${pair[0]}>${pair[1]}',
      };
      for (final from in ReviewState.values) {
        for (final to in ReviewState.values) {
          expect(
            OfficialStatLifecycle.permitsReview(from, to),
            allowedReview.contains('${from.name}>${to.name}'),
            reason: '${from.name} -> ${to.name}',
          );
        }
      }

      final allowedPublication = {
        for (final pair in transitions['publication'] as List<dynamic>)
          '${pair[0]}>${pair[1]}',
      };
      for (final from in PublicationState.values) {
        for (final to in PublicationState.values) {
          expect(
            OfficialStatLifecycle.permitsPublication(from, to),
            allowedPublication.contains('${from.name}>${to.name}'),
            reason: '${from.name} -> ${to.name}',
          );
        }
      }
    });

    test('certified revisions and retracted releases cannot reopen', () {
      expect(
        OfficialStatLifecycle.permitsReview(
          ReviewState.certified,
          ReviewState.draft,
        ),
        isFalse,
      );
      expect(
        OfficialStatLifecycle.permitsPublication(
          PublicationState.retracted,
          PublicationState.published,
        ),
        isFalse,
      );
    });
  });

  group('schema registry and command errors', () {
    test('machine-readable entity inventory equals typed registry', () {
      expect(
        OfficialStatSchemaRegistry.entities.map((entity) => entity.name),
        fixture['entities'],
      );
      expect(
        OfficialStatSchemaRegistry.entities,
        everyElement(
          predicate<EntitySchemaContract>(
            (entity) => entity.requiredFields.contains('dataSchemaVersion'),
          ),
        ),
      );
    });

    test(
      'release head and stat revision registry fields match wire schema',
      () {
        final releaseHead = OfficialStatSchemaRegistry.named(
          'publicationReleaseHead',
        );
        final fixtureFields = {
          ...(fixture['publicationReleaseHeads']['requiredFields']
                  as List<dynamic>)
              .cast<String>(),
          'dataSchemaVersion',
        };
        expect(releaseHead.requiredFields, fixtureFields);
        expect(releaseHead.explicitFactFields, {'activeReleaseId'});

        final statRevision = OfficialStatSchemaRegistry.named('statRevision');
        expect(
          statRevision.requiredFields,
          containsAll({'inputParts', 'createdBy', 'createdAt'}),
        );
        final receipt = OfficialStatSchemaRegistry.named('operationReceipt');
        final receiptFields =
            (fixture['journalContract']['receiptRequiredFields']
                    as List<dynamic>)
                .cast<String>()
                .where((field) => field != 'scope');
        expect(
          receipt.requiredFields,
          containsAll({
            ...receiptFields,
            'associationId',
            'competitionId',
            'seasonId',
            'divisionId',
            'phaseId',
            'gameId',
          }),
        );
      },
    );

    test('every stable command error has one retry classification', () {
      final expected = fixture['commandErrors'] as Map<String, dynamic>;
      expect(
        OfficialStatCommandErrors.policies.length,
        CommandErrorCode.values.length,
      );
      for (final code in CommandErrorCode.values) {
        final policy = OfficialStatCommandErrors.policies[code];
        expect(policy, isNotNull, reason: code.name);
        expect(policy!.retry.name, expected[code.name], reason: code.name);
        expect(
          policy.idempotency.name,
          (fixture['commandErrorIdempotency']
              as Map<String, dynamic>)[code.name],
          reason: code.name,
        );
      }
    });

    test('same id with different payload is never retryable', () {
      final policy = OfficialStatCommandErrors
          .policies[CommandErrorCode.payloadKeyConflict]!;
      expect(policy.retry, RetryClassification.never);
      expect(
        policy.idempotency,
        IdempotencyClassification.sameKeyDifferentPayloadRejected,
      );
    });

    test('all activation gates are explicit and closed', () {
      final activation =
          jsonDecode(
                File(
                  'contracts/official_stats/v2/activation_gates.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(activation['activationAllowed'], isFalse);
      final gates = activation['gates'] as List<dynamic>;
      final ids = gates
          .map((gate) => (gate as Map<String, dynamic>)['id'])
          .toList();
      expect(ids, fixture['activationGates']);
      expect(
        gates,
        everyElement(
          predicate<Map<String, dynamic>>(
            (gate) =>
                gate['status'].toString().startsWith('pending') &&
                gate['owner'] == null &&
                (gate['requiredEvidence'] as String).isNotEmpty,
          ),
        ),
      );
    });
  });

  group('temporal and privacy semantics', () {
    test('effective intervals are half-open', () {
      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 2, 1);
      final interval = TemporalInterval(
        effectiveFrom: from,
        effectiveTo: Fact.known(to),
        recordedAt: from,
      );
      expect(interval.contains(from), isTrue);
      expect(interval.contains(to), isFalse);
    });

    test('only notApplicable(open_ended) creates an unbounded interval', () {
      final from = DateTime.utc(2026, 1, 1);
      final interval = TemporalInterval(
        effectiveFrom: from,
        effectiveTo: const Fact.notApplicable(reasonCode: 'open_ended'),
        recordedAt: from,
      );
      expect(interval.contains(DateTime.utc(2050)), isTrue);
      for (final reason in ['', 'released']) {
        expect(
          () => TemporalInterval(
            effectiveFrom: from,
            effectiveTo: Fact.notApplicable(reasonCode: reason),
            recordedAt: from,
          ),
          throwsArgumentError,
        );
      }
    });

    test('unknown interval end remains indeterminate after effectiveFrom', () {
      final from = DateTime.utc(2026, 1, 1);
      final interval = TemporalInterval(
        effectiveFrom: from,
        effectiveTo: const Fact.unknown(reasonCode: 'not_recorded'),
        recordedAt: from,
      );
      expect(interval.contains(DateTime.utc(2025)), isFalse);
      expect(interval.contains(DateTime.utc(2027)), isNull);
    });

    test('unknown publication fields default closed', () {
      const policy = PrivacyReleaseContract(
        associationId: 'jba',
        playerId: 'player',
        privacyPolicyVersion: 'privacy_v1',
        privacyEpoch: 1,
        isMinor: true,
        fieldPermissions: {'name': PrivacyPermissionState.unknown},
        authorityEvidenceRefs: [],
      );
      expect(policy.permits('name'), isFalse);
      expect(policy.permits('photo'), isFalse);
    });
  });

  group('release head, revision parts, and journal contracts', () {
    Fact<String> releaseFact(Map<String, dynamic> raw) =>
        switch (raw['state'] as String) {
          'known' => Fact.known(raw['value'] as String),
          'unknown' => Fact.unknown(reasonCode: raw['reasonCode'] as String?),
          'notApplicable' => Fact.notApplicable(
            reasonCode: raw['reasonCode'] as String,
          ),
          final state => throw StateError('unexpected fact state $state'),
        };

    PublicationReleaseHeadContract releaseHead(Map<String, dynamic> raw) =>
        PublicationReleaseHeadContract(
          associationId: raw['associationId'] as String,
          competitionId: raw['competitionId'] as String,
          seasonId: raw['seasonId'] as String,
          state: ReleaseHeadState.values.byName(raw['state'] as String),
          activeReleaseId: releaseFact(
            raw['activeReleaseId'] as Map<String, dynamic>,
          ),
          certificateEpoch: raw['certificateEpoch'] as int,
          publicationEpoch: raw['publicationEpoch'] as int,
          privacyEpoch: raw['privacyEpoch'] as int,
        );

    test('release-head valid and invalid fixtures enforce one wire schema', () {
      final cases = fixture['publicationReleaseHeads'] as Map<String, dynamic>;
      for (final raw in cases['valid'] as List<dynamic>) {
        final testCase = raw as Map<String, dynamic>;
        expect(
          () => releaseHead(testCase),
          returnsNormally,
          reason: testCase['name'] as String,
        );
      }
      for (final raw in cases['invalid'] as List<dynamic>) {
        final testCase = raw as Map<String, dynamic>;
        expect(
          () => releaseHead(testCase),
          throwsA(anything),
          reason: testCase['name'] as String,
        );
      }
    });

    List<BoxScoreInputPartDescriptor> validParts() =>
        (fixture['boxScoreInputParts']['validComplete'] as List<dynamic>).map((
          raw,
        ) {
          final part = raw as Map<String, dynamic>;
          return BoxScoreInputPartDescriptor(
            partId: part['partId'] as String,
            kind: BoxScorePartKind.values.byName(part['kind'] as String),
            count: part['count'] as int,
            sha256: part['sha256'] as String,
          );
        }).toList();

    test('box-score input parts are complete, ordered, and hash-bound', () {
      final parts = validParts();
      expect(
        () => BoxScoreRevisionContract.validateInputParts(
          parts,
          StatisticsDisposition.complete,
        ),
        returnsNormally,
      );
      expect(
        OfficialStatCanonicalEncoding.sha256Hex(
          parts.map((part) => part.toContractMap()).toList(),
        ),
        fixture['boxScoreInputParts']['validCompleteInputHash'],
      );
      expect(
        () => BoxScoreRevisionContract.validateInputParts(
          parts
              .where((part) => part.kind != BoxScorePartKind.teamOnlyInputs)
              .toList(),
          StatisticsDisposition.complete,
        ),
        throwsArgumentError,
      );
      expect(
        () => BoxScoreRevisionContract.validateInputParts([
          parts[1],
          parts[0],
          ...parts.skip(2),
        ], StatisticsDisposition.complete),
        throwsArgumentError,
      );
      expect(
        () => BoxScoreInputPartDescriptor(
          partId: 'empty',
          kind: BoxScorePartKind.playerInputs,
          count: 0,
          sha256: List.filled(64, 'a').join(),
        ),
        throwsArgumentError,
      );
    });

    test('journal semantic and request inputs match shared hash fixtures', () {
      final journal = fixture['journalContract'] as Map<String, dynamic>;
      expect(
        OfficialStatCanonicalEncoding.sha256Hex(journal['semanticInput']),
        journal['semanticHash'],
      );
      expect(
        OfficialStatCanonicalEncoding.sha256Hex(journal['requestInput']),
        journal['requestHash'],
      );

      final operation = JournalOperationContract(
        scope: GameScope(
          associationId: 'jba',
          competitionId: 'nbl',
          seasonId: 'season_2026',
          divisionId: 'division_1',
          phaseId: 'regular',
          gameId: 'game_1',
        ),
        workspaceId: 'workspace_1',
        operationId: 'operation_7',
        commandId: 'command_7',
        actorAccountId: 'statistician_1',
        deviceSessionId: 'device_1',
        writerEpoch: 3,
        localSequence: 7,
        previousOperationHash: Fact.known(List.filled(64, 'a').join()),
        expectedServerHead: 'head_6',
        operationSchemaVersion: 2,
        reducerVersion: 'reducer_v1',
        rulesetVersion: 'rules_v1',
        operationType: JournalOperationType.setPlayerCounter,
        periodNumber: const Fact.known(1),
        clockRemainingMs: const Fact.known(345000),
        logicalPlayOrder: 42,
        payload: const {
          'delta': 1,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
        semanticHash: journal['semanticHash'] as String,
        requestHash: journal['requestHash'] as String,
        clientObservedAt: DateTime.utc(2026),
      );
      expect(operation.semanticHashInput(), journal['semanticInput']);
      expect(operation.requestHashInput(), journal['requestInput']);
    });
  });
}
