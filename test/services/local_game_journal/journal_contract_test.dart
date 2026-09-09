import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/command_contract.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/deletion_recovery_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_limits.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:hoops_connect/services/local_game_journal/journal_store.dart';
import 'package:hoops_connect/services/local_game_journal/recovery_models.dart';

import 'journal_test_support.dart';

void main() {
  late FaultInjectingMemoryStore store;
  late LocalGameJournalRepository repository;
  late JournalPartition partition;

  setUp(() async {
    store = FaultInjectingMemoryStore();
    repository = LocalGameJournalRepository(
      store: store,
      activeActorAccountId: 'account_1',
      compatibility: testCompatibility(),
    );
    await repository.open();
    partition = testPartition();
    await repository.prepareGame(testPackage(partition));
  });

  tearDown(() => repository.close());

  test('operation hashes use Packet 01 canonical fields', () {
    final packetOnePartition = JournalPartition(
      actorAccountId: 'statistician_1',
      scope: testPartition().scope,
      workspaceId: 'workspace_1',
    );
    final operation = LocalGameJournalOperation.create(
      partition: packetOnePartition,
      operationId: 'operation_7',
      commandId: 'command_7',
      deviceSessionId: 'device_1',
      writerEpoch: 3,
      localSequence: 7,
      previousOperationHash: const Fact.known(hashA),
      expectedServerHead: 'head_6',
      reducerVersion: 'reducer_v1',
      rulesProfileId: 'rules_v1',
      operationType: JournalOperationType.setPlayerCounter,
      payload: const {
        'delta': 1,
        'participantId': 'participant_7',
        'stat': 'twoPointMade',
      },
      gamePeriod: const Fact.known(1),
      gameClockPosition: const Fact.known(345000),
      logicalPlayOrder: 42,
      clientObservedAt: DateTime.utc(2026, 9, 8),
    );
    expect(
      operation.semanticHash,
      '4ddf4df3a3b705f6f50ffa0d10498c79aa7467786eba44bc68b57289f2ab543c',
    );
    expect(
      operation.requestHash,
      '53122558d6303548bcbc367681669bd902a838884bc0e071aa2313e79f12106f',
    );
  });

  test(
    'caller mutation cannot alter operation or returned snapshots',
    () async {
      final nested = <String, Object?>{
        'participantIds': <Object?>['participant_1', 'participant_2'],
        'teamEntryId': 'team_1',
      };
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        operationType: JournalOperationType.setLineup,
        payload: nested,
      );
      final originalHash = operation.payloadHash;
      (nested['participantIds']! as List<Object?>).add('participant_3');
      nested['other'] = true;

      final result = await repository.append(operation);
      expect(result.entry!.operation.payloadHash, originalHash);
      expect(result.entry!.operation.payload, {
        'participantIds': ['participant_1', 'participant_2'],
        'teamEntryId': 'team_1',
      });
      expect(
        () =>
            (result.entry!.operation.payload['participantIds']! as List).add(4),
        throwsUnsupportedError,
      );
      expect(
        OfficialStatCanonicalEncoding.sha256Hex(
          result.entry!.operation.payload,
        ),
        originalHash,
      );
    },
  );

  test('append and checkpoint are atomic before success is returned', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    store.failAtPut = 4;
    await expectLater(
      repository.append(operation),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.transactionAborted,
        ),
      ),
    );
    final checkpoint = await repository.getCheckpoint(partition);
    expect(checkpoint.nextLocalSequence, 0);
    expect((await repository.listOperations(partition)).entries, isEmpty);
  });

  test(
    'lost success after commit recovers both operation and checkpoint',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      store.failAfterCommitOnce = true;
      await expectLater(
        repository.append(operation),
        throwsA(isA<LocalJournalException>()),
      );
      final replay = await repository.append(operation);
      expect(replay.exactReplay, isTrue);
      expect(replay.entry!.operation.requestHash, operation.requestHash);
      expect((await repository.getCheckpoint(partition)).nextLocalSequence, 1);
    },
  );

  test('gaps and changed duplicate IDs fail closed in stable order', () async {
    final gap = testOperation(
      partition: partition,
      sequence: 1,
      previousHash: const Fact.known(hashA),
    );
    await expectLater(
      repository.append(gap),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.sequenceGap,
        ),
      ),
    );
    final first = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(first);
    expect((await repository.append(first)).exactReplay, isTrue);
    final changed = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      payload: const {
        'delta': 2,
        'participantId': 'participant_7',
        'stat': 'twoPointMade',
      },
    );
    await expectLater(
      repository.append(changed),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.payloadKeyConflict,
        ),
      ),
    );
  });

  test('versions, writer epoch, and complete scope are pinned', () async {
    final wrongReducer = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      reducerVersion: 'unknown_reducer',
    );
    await expectLater(
      repository.append(wrongReducer),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.unsupportedReducerVersion,
        ),
      ),
    );
    final wrongEpoch = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      writerEpoch: 2,
    );
    await expectLater(
      repository.append(wrongEpoch),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.writerEpochConflict,
        ),
      ),
    );
  });

  test('prepared packages reject negative accepted server sequences', () {
    expect(
      () =>
          testPackage(partition, acceptedServerSequence: const Fact.known(-1)),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.invalidArgument,
        ),
      ),
    );
  });

  test('persisted package compatibility is rechecked before capture', () async {
    await repository.close();
    final reopened = LocalGameJournalRepository(
      store: store,
      activeActorAccountId: partition.actorAccountId,
      compatibility: LocalJournalCompatibility(
        acceptedReducerVersions: const {'reducer_v1'},
        acceptedCalculatorVersions: const {'calculator_v2'},
        acceptedRulesProfileIds: const {'rules_v1'},
      ),
    );
    await reopened.open();
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await expectLater(
      reopened.append(operation),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.unsupportedSchemaVersion,
        ),
      ),
    );
  });

  test(
    'operation payload schemas reject fractions, extra fields, and contacts',
    () {
      expect(
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          payload: const {
            'delta': 0.5,
            'participantId': 'participant_7',
            'stat': 'twoPointMade',
          },
        ),
        throwsA(isA<LocalJournalException>()),
      );
      expect(
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          payload: const {
            'delta': 1,
            'guardianPhone': '555-0100',
            'participantId': 'participant_7',
            'stat': 'twoPointMade',
          },
        ),
        throwsA(isA<LocalJournalException>()),
      );
    },
  );

  test(
    'amendments reference earlier evidence and clock order stays separate',
    () async {
      final original = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(original);
      final amendment = LocalGameJournalOperation.create(
        partition: partition,
        operationId: 'operation_1',
        commandId: 'command_1',
        deviceSessionId: 'device_1',
        writerEpoch: 1,
        localSequence: 1,
        previousOperationHash: Fact.known(original.requestHash),
        expectedServerHead: 'head_0',
        reducerVersion: 'reducer_v1',
        rulesProfileId: 'rules_v1',
        operationType: JournalOperationType.setPlayerCounter,
        payload: {
          'amendsOperationId': original.operationId,
          'delta': -1,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
        gamePeriod: const Fact.known(1),
        gameClockPosition: const Fact.known(500000),
        logicalPlayOrder: 0,
        clientObservedAt: DateTime.utc(2026, 9, 8, 12, 5),
      );
      await repository.append(amendment);
      expect(amendment.gameClockPosition.valueOrNull, greaterThan(345000));
      expect(amendment.localSequence, 1);

      final missingReference = LocalGameJournalOperation.create(
        partition: partition,
        operationId: 'operation_2',
        commandId: 'command_2',
        deviceSessionId: 'device_1',
        writerEpoch: 1,
        localSequence: 2,
        previousOperationHash: Fact.known(amendment.requestHash),
        expectedServerHead: 'head_0',
        reducerVersion: 'reducer_v1',
        rulesProfileId: 'rules_v1',
        operationType: JournalOperationType.setClock,
        payload: const {
          'clockState': 'stopped',
          'reversesOperationId': 'missing_operation',
        },
        gamePeriod: const Fact.known(1),
        gameClockPosition: const Fact.known(400000),
        logicalPlayOrder: 2,
        clientObservedAt: DateTime.utc(2026, 9, 8, 12, 6),
      );
      await expectLater(
        repository.append(missingReference),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.operationNotFound,
          ),
        ),
      );
    },
  );

  test(
    'transient retry persists capped jitter metadata; auth pauses',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.queue(partition, operation.operationId);
      final retry = await repository.recordDeliveryFailure(
        partition,
        operation.operationId,
        CommandErrorCode.transientUnavailable,
        observedAt: DateTime.utc(2026, 9, 8, 13),
      );
      expect(retry.delivery.state, JournalDeliveryState.queued);
      expect(retry.delivery.retryCount, 1);
      expect(
        retry.delivery.nextAttemptAt.valueOrNull!
            .difference(DateTime.utc(2026, 9, 8, 13))
            .inMilliseconds,
        inInclusiveRange(500, 1000),
      );
      final paused = await repository.recordDeliveryFailure(
        partition,
        operation.operationId,
        CommandErrorCode.unauthenticated,
        observedAt: DateTime.utc(2026, 9, 8, 13, 1),
      );
      expect(paused.delivery.state, JournalDeliveryState.needsAttention);
      expect(
        paused.delivery.pauseReason.valueOrNull,
        LocalPauseReason.authenticationRequired.name,
      );
    },
  );

  test(
    'maximum safe retry count uses bounded deterministic arithmetic',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.queue(partition, operation.operationId);
      final entryKey = 'entry/${partition.key}/0000000000000000';
      final persisted = LocalJournalRecordCodec.decode(
        store.unsafeRead(entryKey)!,
      );
      final delivery = Map<String, Object?>.from(persisted['delivery']! as Map)
        ..['retryCount'] = LocalGameJournalLimits.maxSafeInteger;
      store.unsafeWrite(
        entryKey,
        LocalJournalRecordCodec.encode({...persisted, 'delivery': delivery}),
      );

      expect(
        LocalJournalRetryMath.cappedExponentialDelay(
          LocalGameJournalLimits.maxSafeInteger,
        ),
        LocalGameJournalLimits.retryMaximumDelayMs,
      );
      expect(LocalJournalRetryMath.maximumDoublingSteps, lessThanOrEqualTo(7));
      final observedAt = DateTime.utc(2026, 9, 8, 13, 30);
      final retry = await repository.recordDeliveryFailure(
        partition,
        operation.operationId,
        CommandErrorCode.transientUnavailable,
        observedAt: observedAt,
      );
      expect(retry.delivery.retryCount, LocalGameJournalLimits.maxSafeInteger);
      expect(
        retry.delivery.nextAttemptAt.valueOrNull!
            .difference(observedAt)
            .inMilliseconds,
        inInclusiveRange(
          LocalGameJournalLimits.retryMaximumDelayMs ~/ 2,
          LocalGameJournalLimits.retryMaximumDelayMs,
        ),
      );
    },
  );

  test('receipt is durable before submitted/prunable state', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    await expectLater(
      repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submissionQueued,
        observedAt: DateTime.utc(2026, 9, 8, 14),
      ),
      completes,
    );
    await expectLater(
      repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submitted,
        observedAt: DateTime.utc(2026, 9, 8, 14),
      ),
      throwsA(isA<LocalJournalException>()),
    );
    final accepted = await repository.storeServerReceipt(
      partition,
      testReceipt(operation),
    );
    expect(accepted.delivery.state, JournalDeliveryState.accepted);
    expect(accepted.delivery.serverReceipt.valueOrNull, isNotNull);
    final submitted = await repository.setSubmissionState(
      partition,
      WorkspaceSubmissionState.submitted,
      observedAt: DateTime.utc(2026, 9, 8, 14, 1),
    );
    expect(submitted.submissionState, WorkspaceSubmissionState.submitted);
  });

  test(
    'prune requires confirmed archive and preserves exact-replay receipt',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submissionQueued,
        observedAt: DateTime.utc(2026, 9, 8, 14),
      );
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submitted,
        observedAt: DateTime.utc(2026, 9, 8, 14, 1),
      );
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_for_prune',
        manifestId: 'manifest_for_prune',
        exportedAt: DateTime.utc(2026, 9, 8, 14, 2),
      );
      await expectLater(
        repository.pruneAcknowledged(
          partition,
          throughSequence: 0,
          recoveryArchiveId: archive.archiveId,
          recoveryArchiveChecksum: archive.checksum,
          prunedAt: DateTime.utc(2026, 9, 8, 14, 3),
        ),
        throwsA(isA<LocalJournalException>()),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archive.archiveId,
        checksum: archive.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      final checkpoint = await repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: archive.archiveId,
        recoveryArchiveChecksum: archive.checksum,
        prunedAt: DateTime.utc(2026, 9, 8, 14, 3),
      );
      expect(checkpoint.retainedOperationCount, 0);
      expect((await repository.listOperations(partition)).entries, isEmpty);
      final replay = await repository.append(operation);
      expect(replay.exactReplay, isTrue);
      expect(replay.wasPruned, isTrue);
      expect(replay.durableReceipt!.requestHash, operation.requestHash);
      expect(
        (await repository.verifyIntegrity(partition)).retainedOperations,
        0,
      );
    },
  );

  test(
    'pruned prefix requires exact receipt coverage for integrity and export',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submissionQueued,
        observedAt: DateTime.utc(2026, 9, 8, 14, 10),
      );
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submitted,
        observedAt: DateTime.utc(2026, 9, 8, 14, 11),
      );
      final beforePrune = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_before_receipt_loss',
        manifestId: 'manifest_before_receipt_loss',
        exportedAt: DateTime.utc(2026, 9, 8, 14, 12),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: beforePrune.archiveId,
        checksum: beforePrune.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      await repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: beforePrune.archiveId,
        recoveryArchiveChecksum: beforePrune.checksum,
        prunedAt: DateTime.utc(2026, 9, 8, 14, 13),
      );

      final complete = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_complete_pruned_prefix',
        manifestId: 'manifest_complete_pruned_prefix',
        exportedAt: DateTime.utc(2026, 9, 8, 14, 14),
      );
      expect(complete.receiptTombstones, hasLength(1));
      expect(complete.receiptTombstones.single.localSequence, 0);
      expect(
        complete.receiptTombstones.single.receipt.operationId,
        operation.operationId,
      );

      final incomplete =
          jsonDecode(complete.canonicalJson) as Map<String, dynamic>;
      incomplete['receiptTombstones'] = <Object?>[];
      final withoutChecksum = Map<String, Object?>.from(incomplete)
        ..remove('checksum');
      incomplete['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        withoutChecksum,
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          OfficialStatCanonicalEncoding.encode(incomplete),
          expectedActorAccountId: partition.actorAccountId,
          expectedPartition: partition,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.archivePartial,
          ),
        ),
      );

      final gapped = jsonDecode(complete.canonicalJson) as Map<String, dynamic>;
      final gappedTombstone = Map<String, dynamic>.from(
        (gapped['receiptTombstones'] as List).single as Map,
      )..['localSequence'] = 1;
      gapped['receiptTombstones'] = <Object?>[gappedTombstone];
      final gappedWithoutChecksum = Map<String, Object?>.from(gapped)
        ..remove('checksum');
      gapped['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        gappedWithoutChecksum,
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          OfficialStatCanonicalEncoding.encode(gapped),
          expectedActorAccountId: partition.actorAccountId,
          expectedPartition: partition,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.archivePartial,
          ),
        ),
      );

      final duplicated =
          jsonDecode(complete.canonicalJson) as Map<String, dynamic>;
      duplicated['receiptTombstones'] = <Object?>[
        ...(duplicated['receiptTombstones'] as List),
        ...(duplicated['receiptTombstones'] as List),
      ];
      final duplicatedWithoutChecksum = Map<String, Object?>.from(duplicated)
        ..remove('checksum');
      duplicated['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        duplicatedWithoutChecksum,
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          OfficialStatCanonicalEncoding.encode(duplicated),
          expectedActorAccountId: partition.actorAccountId,
          expectedPartition: partition,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.archivePartial,
          ),
        ),
      );

      final wrongEpoch =
          jsonDecode(complete.canonicalJson) as Map<String, dynamic>;
      final wrongEpochTombstone = Map<String, dynamic>.from(
        (wrongEpoch['receiptTombstones'] as List).single as Map,
      );
      final wrongEpochReceipt = Map<String, dynamic>.from(
        wrongEpochTombstone['receipt']! as Map,
      )..['writerEpoch'] = 2;
      wrongEpochTombstone['receipt'] = wrongEpochReceipt;
      wrongEpoch['receiptTombstones'] = <Object?>[wrongEpochTombstone];
      final wrongEpochCheckpoint = Map<String, dynamic>.from(
        wrongEpoch['checkpoint']! as Map,
      )..['writerEpoch'] = 2;
      wrongEpoch['checkpoint'] = wrongEpochCheckpoint;
      final wrongEpochWithoutChecksum = Map<String, Object?>.from(wrongEpoch)
        ..remove('checksum');
      wrongEpoch['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        wrongEpochWithoutChecksum,
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          OfficialStatCanonicalEncoding.encode(wrongEpoch),
          expectedActorAccountId: partition.actorAccountId,
          expectedPartition: partition,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.archiveTampered,
          ),
        ),
      );

      final wrongPackageBinding =
          jsonDecode(complete.canonicalJson) as Map<String, dynamic>;
      final wrongPackageCheckpoint =
          Map<String, dynamic>.from(wrongPackageBinding['checkpoint']! as Map)
            ..['preparationPackageChecksum'] = const Fact<String>.known(
              hashA,
            ).toContractMap((value) => value);
      wrongPackageBinding['checkpoint'] = wrongPackageCheckpoint;
      final wrongPackageWithoutChecksum = Map<String, Object?>.from(
        wrongPackageBinding,
      )..remove('checksum');
      wrongPackageBinding['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        wrongPackageWithoutChecksum,
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          OfficialStatCanonicalEncoding.encode(wrongPackageBinding),
          expectedActorAccountId: partition.actorAccountId,
          expectedPartition: partition,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.archiveTampered,
          ),
        ),
      );

      final receiptKey = 'receipt/${partition.key}/${operation.operationId}';
      store.unsafeDelete(receiptKey);
      await expectLater(
        repository.exportRecoveryArchive(
          partition,
          archiveId: 'archive_after_receipt_loss',
          manifestId: 'manifest_after_receipt_loss',
          exportedAt: DateTime.utc(2026, 9, 8, 14, 15),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.receiptMismatch,
          ),
        ),
      );
      expect(
        store.unsafeRead(
          'recoveryExport/${partition.key}/archive_after_receipt_loss',
        ),
        isNull,
      );
      await expectLater(
        repository.verifyIntegrity(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      await expectLater(
        repository.append(operation),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'pruned receipt evidence must retain the checkpoint writer epoch',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submissionQueued,
        observedAt: DateTime.utc(2026, 9, 8, 14, 20),
      );
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submitted,
        observedAt: DateTime.utc(2026, 9, 8, 14, 21),
      );
      final beforePrune = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_before_epoch_mutation',
        manifestId: 'manifest_before_epoch_mutation',
        exportedAt: DateTime.utc(2026, 9, 8, 14, 22),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: beforePrune.archiveId,
        checksum: beforePrune.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      await repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: beforePrune.archiveId,
        recoveryArchiveChecksum: beforePrune.checksum,
        prunedAt: DateTime.utc(2026, 9, 8, 14, 23),
      );

      final receiptKey = 'receipt/${partition.key}/${operation.operationId}';
      final receipt = LocalJournalRecordCodec.decode(
        store.unsafeRead(receiptKey)!,
      )..['writerEpoch'] = 2;
      store.unsafeWrite(receiptKey, LocalJournalRecordCodec.encode(receipt));

      await expectLater(
        repository.exportRecoveryArchive(
          partition,
          archiveId: 'archive_after_epoch_mutation',
          manifestId: 'manifest_after_epoch_mutation',
          exportedAt: DateTime.utc(2026, 9, 8, 14, 24),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.receiptMismatch,
          ),
        ),
      );
      expect(
        store.unsafeRead(
          'recoveryExport/${partition.key}/archive_after_epoch_mutation',
        ),
        isNull,
      );
    },
  );

  test('recovery export rejects missing retained index pairs', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    store.unsafeDelete(
      'operationIndex/${partition.key}/${operation.operationId}',
    );
    store.unsafeDelete('commandIndex/${partition.key}/${operation.commandId}');

    await expectLater(
      repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_missing_retained_indexes',
        manifestId: 'manifest_missing_retained_indexes',
        exportedAt: DateTime.utc(2026, 9, 8, 14, 30),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(
      store.unsafeRead(
        'recoveryExport/${partition.key}/archive_missing_retained_indexes',
      ),
      isNull,
    );
  });

  test(
    'integrity and export reject checkpoint prepared-package divergence',
    () async {
      final checkpointKey = 'checkpoint/${partition.key}';
      final checkpoint =
          LocalJournalRecordCodec.decode(store.unsafeRead(checkpointKey)!)
            ..['preparationPackageChecksum'] = Fact<String>.known(
              List<String>.filled(64, 'c').join(),
            ).toContractMap((value) => value);
      store.unsafeWrite(
        checkpointKey,
        LocalJournalRecordCodec.encode(checkpoint),
      );

      await expectLater(
        repository.exportRecoveryArchive(
          partition,
          archiveId: 'archive_wrong_package_binding',
          manifestId: 'manifest_wrong_package_binding',
          exportedAt: DateTime.utc(2026, 9, 8, 14, 31),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(
        store.unsafeRead(
          'recoveryExport/${partition.key}/archive_wrong_package_binding',
        ),
        isNull,
      );
      await expectLater(
        repository.verifyIntegrity(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'integrity rejects a matched orphan beyond the old Unicode sentinel',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      final source = LocalJournalRecordCodec.decode(
        store.unsafeRead(
          'operationIndex/${partition.key}/${operation.operationId}',
        )!,
      );
      final orphan = <String, Object?>{
        ...source,
        'operationId': 'orphan_operation',
        'commandId': 'orphan_command',
      };
      final encoded = LocalJournalRecordCodec.encode(orphan);
      store.unsafeWrite('operationIndex/${partition.key}/\uffffx', encoded);
      store.unsafeWrite('commandIndex/${partition.key}/\uffffx', encoded);

      await expectLater(
        repository.verifyIntegrity(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'recovery archive is deterministic, tamper-evident, and untrusted',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'archive_1',
        manifestId: 'manifest_1',
        exportedAt: DateTime.utc(2026, 9, 8, 15),
      );
      final parsed = LocalJournalRecoveryArchive.parse(
        archive.canonicalJson,
        expectedActorAccountId: 'account_1',
        expectedPartition: partition,
      );
      expect(parsed.canonicalJson, archive.canonicalJson);
      expect(parsed.checksum, archive.checksum);
      final imported = await repository.importRecoveryArchive(
        archive.canonicalJson,
        expectedPartition: partition,
        importedAt: DateTime.utc(2026, 9, 8, 15, 1),
      );
      expect(imported.trust, RecoveryArchiveTrust.importedUntrusted);
      expect((await repository.listOperations(partition)).entries.length, 1);

      final tampered = archive.canonicalJson.replaceFirst(
        '"delta":1',
        '"delta":2',
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          tampered,
          expectedActorAccountId: 'account_1',
        ),
        throwsA(isA<LocalJournalException>()),
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          archive.canonicalJson,
          expectedActorAccountId: 'account_2',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.scopeMismatch,
          ),
        ),
      );
    },
  );

  test('account and current-season substitution are never implicit', () async {
    final otherAccountRepository = LocalGameJournalRepository(
      store: store,
      activeActorAccountId: 'account_2',
      compatibility: testCompatibility(),
    );
    await otherAccountRepository.open();
    await expectLater(
      otherAccountRepository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.accountAccessDenied,
        ),
      ),
    );
    final currentSeason = testPartition(seasonId: 'season_current');
    await expectLater(
      repository.getCheckpoint(currentSeason),
      throwsA(isA<LocalJournalException>()),
    );
  });

  test(
    'deletion manifest is per-device, consent-bound, and never purges',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.queue(partition, operation.operationId);
      await repository.markSending(partition, operation.operationId);
      await repository.recordDeliveryFailure(
        partition,
        operation.operationId,
        CommandErrorCode.transientUnavailable,
        observedAt: DateTime.utc(2026, 9, 8, 15, 59),
      );
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'manifest_device_1',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 8, 16),
      );
      expect(manifest.serverDeletionContinuesIndependently, isTrue);
      expect(manifest.consentInheritedAcrossDevices, isFalse);
      expect(manifest.workspaces.single.receiptUnknownOperations, 1);
      final consent = LocalDeletionConsent(
        consentId: 'consent_1',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: 'device_1',
        grantedAt: DateTime.utc(2026, 9, 8, 16, 1),
      );
      final identities = await repository.enumerateDeletionReconciliation(
        consent,
      );
      expect(identities.single.commandId, operation.commandId);
      expect(
        identities.single.receiptKnowledge,
        LocalReceiptKnowledge.responseUnknown,
      );
      final later = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(operation.requestHash),
      );
      await repository.append(later);
      await expectLater(
        repository.enumerateDeletionReconciliation(consent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.manifestMismatch,
          ),
        ),
      );
      await expectLater(
        repository.quarantineDeletionManifest(
          consent: consent,
          namedCustodianId: 'custodian_1',
          dispositionDeadline: DateTime.utc(2026, 10, 8),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.secureQuarantineUnavailable,
          ),
        ),
      );
      expect((await repository.listOperations(partition)).entries.length, 2);
    },
  );

  test(
    'submitted workspace rejects fresh append but preserves replay',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submissionQueued,
        observedAt: DateTime.utc(2026, 9, 8, 17),
      );
      await repository.setSubmissionState(
        partition,
        WorkspaceSubmissionState.submitted,
        observedAt: DateTime.utc(2026, 9, 8, 17, 1),
      );
      final next = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(operation.requestHash),
      );
      await expectLater(
        repository.append(next),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.invalidStateTransition,
          ),
        ),
      );
      expect((await repository.append(operation)).exactReplay, isTrue);
    },
  );

  test(
    'server conflict preserves branch and blocks delivery and fresh append',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.queue(partition, operation.operationId);
      await repository.markSending(partition, operation.operationId);
      final second = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(operation.requestHash),
      );
      await repository.append(second);
      await repository.queue(partition, second.operationId);
      await repository.recordDeliveryFailure(
        partition,
        operation.operationId,
        CommandErrorCode.sequenceConflict,
        observedAt: DateTime.utc(2026, 9, 8, 17, 30),
      );
      expect(
        (await repository.getCheckpoint(partition)).recoveryState,
        LocalWorkspaceRecoveryState.conflictBranch,
      );
      await expectLater(
        repository.resumePaused(partition, operation.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.writerEpochConflict,
          ),
        ),
      );
      await expectLater(
        repository.markSending(partition, second.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.writerEpochConflict,
          ),
        ),
      );
      await expectLater(
        repository.enumerateForegroundReady(
          partition,
          now: DateTime.utc(2026, 9, 8, 17, 31),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.writerEpochConflict,
          ),
        ),
      );
      final next = testOperation(
        partition: partition,
        sequence: 2,
        previousHash: Fact.known(second.requestHash),
      );
      await expectLater(
        repository.append(next),
        throwsA(isA<LocalJournalException>()),
      );
      expect((await repository.append(operation)).exactReplay, isTrue);
      expect(
        (await repository.storeServerReceipt(
          partition,
          testReceipt(operation),
        )).delivery.state,
        JournalDeliveryState.accepted,
      );
    },
  );

  test('prune rejects a mismatched durable receipt tombstone', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    await repository.storeServerReceipt(partition, testReceipt(operation));
    await repository.setSubmissionState(
      partition,
      WorkspaceSubmissionState.submissionQueued,
      observedAt: DateTime.utc(2026, 9, 8, 18),
    );
    await repository.setSubmissionState(
      partition,
      WorkspaceSubmissionState.submitted,
      observedAt: DateTime.utc(2026, 9, 8, 18, 1),
    );
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'archive_receipt_guard',
      manifestId: 'manifest_receipt_guard',
      exportedAt: DateTime.utc(2026, 9, 8, 18, 2),
    );
    await repository.confirmRecoveryArchivePersisted(
      partition,
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      confirmation: 'recoveryArchivePersisted',
    );
    final receiptKey = 'receipt/${partition.key}/${operation.operationId}';
    final changedReceipt = OperationReceiptContract(
      receiptId: 'different_receipt',
      scope: operation.partition.scope,
      workspaceId: operation.partition.workspaceId,
      operationId: operation.operationId,
      commandId: operation.commandId,
      actorAccountId: operation.partition.actorAccountId,
      commandKind: operation.operationType,
      requestHash: operation.requestHash,
      serverSequence: operation.localSequence,
      acceptedJournalHead: 'different_head',
      acceptedJournalHash: operation.requestHash,
      writerEpoch: operation.writerEpoch,
      acceptedAt: DateTime.utc(2026, 9, 8, 18, 3),
    );
    store.unsafeWrite(
      receiptKey,
      LocalJournalRecordCodec.encode(operationReceiptToMap(changedReceipt)),
    );
    await expectLater(
      repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: archive.archiveId,
        recoveryArchiveChecksum: archive.checksum,
        prunedAt: DateTime.utc(2026, 9, 8, 18, 4),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.receiptMismatch,
        ),
      ),
    );
    await expectLater(
      repository.listOperations(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(
      store.unsafeRead('entry/${partition.key}/0000000000000000'),
      isNotNull,
    );
  });

  test('truncated JSON latches integrity failure', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final key = 'entry/${partition.key}/0000000000000000';
    store.unsafeWrite(key, '{');
    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test('malformed persisted envelope latches integrity failure', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final key = 'entry/${partition.key}/0000000000000000';
    store.unsafeWrite(key, '{}');
    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test('fractional persisted payload latches integrity failure', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final key = 'entry/${partition.key}/0000000000000000';
    store.unsafeWrite(
      key,
      jsonEncode({
        'checksum': hashA,
        'localSchemaVersion': LocalGameJournalLimits.localSchemaVersion,
        'payload': {'fractionalCorruption': 1.1},
      }),
    );
    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'exact replay validates the retained entry against its indexes',
    () async {
      final first = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      final second = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(first.requestHash),
      );
      await repository.append(first);
      await repository.append(second);
      final firstKey = 'entry/${partition.key}/0000000000000000';
      final secondKey = 'entry/${partition.key}/0000000000000001';
      store.unsafeWrite(firstKey, store.unsafeRead(secondKey)!);
      await expectLater(
        repository.append(first),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test('persisted corruption disables further capture visibly', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final key = 'entry/${partition.key}/0000000000000000';
    final raw = store.unsafeRead(key)!;
    store.unsafeWrite(key, raw.replaceFirst('participant_7', 'participant_8'));
    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    final next = testOperation(
      partition: partition,
      sequence: 1,
      previousHash: Fact.known(operation.requestHash),
    );
    await expectLater(
      repository.append(next),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'malformed persisted index invalidates cached verification and latches',
    () async {
      final first = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      final second = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(first.requestHash),
      );
      await repository.append(first);
      await repository.append(second);
      await repository.verifyIntegrity(partition);

      final indexKey = 'operationIndex/${partition.key}/${first.operationId}';
      final malformed = LocalJournalRecordCodec.decode(
        store.unsafeRead(indexKey)!,
      )..['localSequence'] = -1;
      store.unsafeWrite(indexKey, LocalJournalRecordCodec.encode(malformed));
      await expectLater(
        repository.verifyIntegrity(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );

      final third = testOperation(
        partition: partition,
        sequence: 2,
        previousHash: Fact.known(second.requestHash),
      );
      await expectLater(
        repository.append(third),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'unprepared workspace does not poison healthy repository state',
    () async {
      final unprepared = testPartition(workspaceId: 'workspace_unprepared');
      await expectLater(
        repository.verifyIntegrity(unprepared),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.operationNotFound,
          ),
        ),
      );

      expect((await repository.getCheckpoint(partition)).nextLocalSequence, 0);
      final prepared = await repository.prepareGame(testPackage(unprepared));
      expect(prepared.partition.key, unprepared.key);
    },
  );

  test(
    'state-machine sequence preserves append and acknowledge invariants',
    () async {
      var previous = const Fact<String>.notApplicable(reasonCode: 'genesis');
      final operations = <LocalGameJournalOperation>[];
      for (var sequence = 0; sequence < 40; sequence++) {
        final type = JournalOperationType
            .values[sequence % JournalOperationType.values.length];
        final operation = testOperation(
          partition: partition,
          sequence: sequence,
          previousHash: previous,
          operationType: type,
          payload: payloadForOperationType(type, sequence),
        );
        await repository.append(operation);
        operations.add(operation);
        previous = Fact.known(operation.requestHash);
      }
      for (final operation in operations.reversed) {
        await repository.storeServerReceipt(partition, testReceipt(operation));
      }
      final checkpoint = await repository.getCheckpoint(partition);
      expect(checkpoint.nextLocalSequence, 40);
      expect(checkpoint.acceptedThroughSequence.valueOrNull, 39);
      final integrity = await repository.verifyIntegrity(partition);
      expect(integrity.retainedOperations, 40);
      expect(integrity.terminalRequestHash, operations.last.requestHash);
    },
  );
}
