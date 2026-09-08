import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
