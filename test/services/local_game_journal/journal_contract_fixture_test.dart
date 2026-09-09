import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/contract_versions.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/journal_limits.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'contracts/local_game_journal/v1/contract.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('machine-readable journal versions and bounds match runtime', () {
    expect(
      fixture['canonicalEncodingVersion'],
      OfficialStatContractVersions.canonicalEncoding,
    );
    expect(
      fixture['localSchemaVersion'],
      LocalGameJournalLimits.localSchemaVersion,
    );
    expect(
      fixture['archiveVersion'],
      LocalGameJournalLimits.recoveryArchiveVersion,
    );
    expect(
      fixture['operationSchemaVersion'],
      LocalGameJournalLimits.operationSchemaVersion,
    );
    expect(
      fixture['preparedGamePackageVersion'],
      LocalGameJournalLimits.preparedGamePackageVersion,
    );
    final packageFields = (fixture['preparedGamePackageFields'] as List)
        .cast<String>();
    expect(packageFields, contains('journalReducerVersion'));
    expect(packageFields, contains('calculatorVersion'));
    expect(packageFields, contains('assignmentVersion'));
    expect(packageFields, isNot(contains('reducerVersion')));
    expect(
      fixture['localSchemaMigrations'],
      contains('local_game_journal_v1_to_v2'),
    );
    final integration = fixture['integrationBoundary'] as Map<String, dynamic>;
    expect(integration['readBootstrapAllocatesWriterSession'], isFalse);
    expect(integration['reconnectImplemented'], isFalse);
    expect(integration['oldEpochConflictBranchPreserved'], isTrue);
    expect(
      fixture['deliveryStates'],
      JournalDeliveryState.values.map((value) => value.name).toList(),
    );
    expect(
      fixture['submissionStates'],
      WorkspaceSubmissionState.values.map((value) => value.name).toList(),
    );
    expect(
      fixture['recoveryStates'],
      LocalWorkspaceRecoveryState.values.map((value) => value.name).toList(),
    );
    expect(fixture['receiptTombstoneFields'], ['localSequence', 'receipt']);
    final limits = fixture['resourceLimits'] as Map<String, dynamic>;
    expect(limits['maxPayloadBytes'], LocalGameJournalLimits.maxPayloadBytes);
    expect(limits['maxReceiptBytes'], LocalGameJournalLimits.maxReceiptBytes);
    expect(
      limits['maxOperationsPerWorkspace'],
      LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    expect(
      limits['maxRecoveryArchiveBytes'],
      LocalGameJournalLimits.maxRecoveryArchiveBytes,
    );
    expect(
      LocalGameJournalLimits.maxRecoveryArchiveBytes,
      LocalGameJournalLimits.maxWorkspaceBytes +
          LocalGameJournalLimits.maxOperationsPerWorkspace *
              LocalGameJournalLimits.maxRecoveryPerOperationOverheadBytes +
          LocalGameJournalLimits.maxPreparationPackageBytes +
          LocalGameJournalLimits.maxRecoveryEnvelopeBytes,
    );
    expect(limits['maxPageSize'], LocalGameJournalLimits.maxPageSize);
    expect(
      (fixture['futureServerIngress'] as Map<String, dynamic>)['implemented'],
      isFalse,
    );
  });

  test('every Packet 01 journal operation has one exact payload schema', () {
    final payloads = fixture['operationPayloads'] as Map<String, dynamic>;
    expect(
      payloads.keys.toSet(),
      JournalOperationType.values.map((value) => value.name).toSet(),
    );
    for (final value in payloads.values) {
      final schema = value as Map<String, dynamic>;
      expect(schema.keys, containsAll(['required', 'optional']));
      expect(schema['required'], isNotEmpty);
    }
  });

  test('recovery overhead budget covers maximum-width receipt schema', () {
    final maxId = List.filled(LocalGameJournalLimits.maxIdLength, 'a').join();
    final partition = JournalPartition(
      actorAccountId: maxId,
      scope: GameScope(
        associationId: maxId,
        competitionId: maxId,
        seasonId: maxId,
        divisionId: maxId,
        phaseId: maxId,
        gameId: maxId,
      ),
      workspaceId: maxId,
    );
    final operation = LocalGameJournalOperation.create(
      partition: partition,
      operationId: maxId,
      commandId: maxId,
      deviceSessionId: maxId,
      writerEpoch: OfficialStatCanonicalEncoding.maxSafeInteger,
      localSequence: 0,
      previousOperationHash: const Fact.notApplicable(reasonCode: 'genesis'),
      expectedServerHead: maxId,
      reducerVersion: maxId,
      rulesProfileId: maxId,
      operationType: JournalOperationType.setParticipantStatus,
      payload: {'participantId': maxId, 'status': 'provisional'},
      gamePeriod: const Fact.known(1),
      gameClockPosition: const Fact.known(0),
      logicalPlayOrder: OfficialStatCanonicalEncoding.maxSafeInteger,
      clientObservedAt: DateTime.utc(9999, 12, 31, 23, 59, 59, 999),
    );
    final receipt = OperationReceiptContract(
      receiptId: maxId,
      scope: partition.scope,
      workspaceId: maxId,
      operationId: maxId,
      commandId: maxId,
      actorAccountId: maxId,
      commandKind: JournalOperationType.setParticipantStatus,
      requestHash: List.filled(64, 'a').join(),
      serverSequence: OfficialStatCanonicalEncoding.maxSafeInteger,
      acceptedJournalHead: maxId,
      acceptedJournalHash: List.filled(64, 'b').join(),
      writerEpoch: OfficialStatCanonicalEncoding.maxSafeInteger,
      acceptedAt: DateTime.utc(9999, 12, 31, 23, 59, 59, 999),
    );
    final delivery = LocalJournalDelivery(
      operationId: maxId,
      state: JournalDeliveryState.accepted,
      retryCount: OfficialStatCanonicalEncoding.maxSafeInteger,
      nextAttemptAt: const Fact.notApplicable(reasonCode: 'accepted'),
      lastErrorCode: const Fact.notApplicable(reasonCode: 'accepted'),
      pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
      serverReceipt: Fact.known(receipt),
      retryPolicy: const RetryPolicyMetadata(jitterBasisPoints: 10000),
    );
    final entryBytes = utf8
        .encode(
          OfficialStatCanonicalEncoding.encode(
            LocalJournalEntry(
              operation: operation,
              delivery: delivery,
            ).toContractMap(),
          ),
        )
        .length;
    expect(
      entryBytes - operation.byteCount,
      lessThanOrEqualTo(
        LocalGameJournalLimits.maxRecoveryPerOperationOverheadBytes,
      ),
    );
  });
}
