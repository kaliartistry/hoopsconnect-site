import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
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
    repository = _repository(store);
    await repository.open();
    partition = testPartition();
    await repository.prepareGame(testPackage(partition));
  });

  tearDown(() => repository.close());

  test(
    'observing non-head corruption through list latches capture and preserves cause',
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
      store.unsafeWrite(
        firstKey,
        store
            .unsafeRead(firstKey)!
            .replaceFirst('participant_7', 'participant_8'),
      );

      LocalJournalException? observed;
      try {
        await repository.listOperations(partition);
      } on LocalJournalException catch (error) {
        observed = error;
      }
      expect(observed, isNotNull);
      expect(observed!.code, LocalJournalErrorCode.mutatedRecord);
      expect(observed.message, 'Stored journal record checksum mismatch');

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
      expect(
        store.unsafeRead('entry/${partition.key}/0000000000000002'),
        isNull,
      );
    },
  );

  test(
    'listing validates coherently encoded entries against both indexes',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.verifyIntegrity(partition);
      final changedOperation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        payload: const {
          'delta': 2,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
      );
      final entryKey = 'entry/${partition.key}/0000000000000000';
      store.unsafeWrite(
        entryKey,
        LocalJournalRecordCodec.encode(
          LocalJournalEntry(
            operation: changedOperation,
            delivery: LocalJournalDelivery.savedOnDevice(
              changedOperation.operationId,
            ),
          ).toContractMap(),
        ),
      );

      await expectLater(
        repository.listOperations(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'entry/index mismatch',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      await expectLater(
        repository.getCheckpoint(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test('listing binds each decoded entry to its scanned storage key', () async {
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
    final firstKey = 'entry/${partition.key}/0000000000000000';
    final secondKey = 'entry/${partition.key}/0000000000000001';
    store.unsafeWrite(firstKey, store.unsafeRead(secondKey)!);

    await expectLater(
      repository.listOperations(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'copied row',
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
          'latched capture',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(store.unsafeRead('entry/${partition.key}/0000000000000002'), isNull);
  });

  test(
    'fresh preparation rejects every orphaned workspace record class byte-exactly',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await repository.exportRecoveryArchive(
        partition,
        archiveId: 'orphan_seed_archive',
        manifestId: 'orphan_seed_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 1),
      );
      final seed = store.unsafeSnapshot();
      final cases = <String, MapEntry<String, String>>{
        'checkpoint': MapEntry(
          'checkpoint/${partition.key}',
          seed['checkpoint/${partition.key}']!,
        ),
        'entry': MapEntry(
          'entry/${partition.key}/0000000000000000',
          seed['entry/${partition.key}/0000000000000000']!,
        ),
        'operation index': MapEntry(
          'operationIndex/${partition.key}/${operation.operationId}',
          seed['operationIndex/${partition.key}/${operation.operationId}']!,
        ),
        'command index': MapEntry(
          'commandIndex/${partition.key}/${operation.commandId}',
          seed['commandIndex/${partition.key}/${operation.commandId}']!,
        ),
        'receipt': MapEntry(
          'receipt/${partition.key}/${operation.operationId}',
          seed['receipt/${partition.key}/${operation.operationId}']!,
        ),
        'recovery export audit': MapEntry(
          'recoveryExport/${partition.key}/orphan_seed_archive',
          seed['recoveryExport/${partition.key}/orphan_seed_archive']!,
        ),
        'workspace index': MapEntry(
          'workspaceIndex/${partition.actorAccountId}/device_1/'
          '${partition.scope.key}/${partition.workspaceId}',
          seed['workspaceIndex/${partition.actorAccountId}/device_1/'
              '${partition.scope.key}/${partition.workspaceId}']!,
        ),
      };

      for (final scenario in cases.entries) {
        final isolatedStore = FaultInjectingMemoryStore();
        final isolated = _repository(isolatedStore);
        await isolated.open();
        isolatedStore.unsafeWrite(scenario.value.key, scenario.value.value);
        final before = isolatedStore.unsafeSnapshot();
        await expectLater(
          isolated.prepareGame(_changedPackage(partition)),
          throwsA(
            isA<LocalJournalException>().having(
              (error) => error.code,
              scenario.key,
              LocalJournalErrorCode.mutatedRecord,
            ),
          ),
          reason: scenario.key,
        );
        expect(isolatedStore.unsafeSnapshot(), before, reason: scenario.key);
        await isolated.close();
      }

      final swappedStore = FaultInjectingMemoryStore();
      final swappedRepository = _repository(swappedStore);
      await swappedRepository.open();
      final targetIndex =
          'workspaceIndex/${partition.actorAccountId}/device_1/'
          '${partition.scope.key}/${partition.workspaceId}';
      final otherPartition = testPartition(workspaceId: 'workspace_other');
      swappedStore.unsafeWrite(
        targetIndex,
        LocalJournalRecordCodec.encode({
          'deviceSessionId': 'device_1',
          'packageChecksum': hashA,
          'partition': otherPartition.toContractMap(),
        }),
      );
      final beforeSwapped = swappedStore.unsafeSnapshot();
      await expectLater(
        swappedRepository.prepareGame(_changedPackage(partition)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'swapped embedded identity',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(swappedStore.unsafeSnapshot(), beforeSwapped);
      await swappedRepository.close();
    },
  );

  test(
    'matching preparation rejects package-only and missing-index orphans',
    () async {
      final packageOnlyStore = FaultInjectingMemoryStore();
      final packageOnlyRepository = _repository(packageOnlyStore);
      await packageOnlyRepository.open();
      packageOnlyStore.unsafeWrite(
        'package/${partition.key}',
        LocalJournalRecordCodec.encode(testPackage(partition).toContractMap()),
      );
      final packageOnlyBefore = packageOnlyStore.unsafeSnapshot();
      await expectLater(
        packageOnlyRepository.prepareGame(testPackage(partition)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'package-only orphan',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(packageOnlyStore.unsafeSnapshot(), packageOnlyBefore);
      await packageOnlyRepository.close();

      store.unsafeDelete(
        'workspaceIndex/${partition.actorAccountId}/device_1/'
        '${partition.scope.key}/${partition.workspaceId}',
      );
      final missingIndexBefore = store.unsafeSnapshot();
      await expectLater(
        repository.prepareGame(testPackage(partition)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'missing index',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), missingIndexBefore);
    },
  );

  test('caller validation errors do not poison healthy capture', () async {
    await expectLater(
      repository.queue(partition, 'not/a/valid/id'),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'operation id',
          LocalJournalErrorCode.invalidIdentifier,
        ),
      ),
    );
    await expectLater(
      repository.listOperations(
        partition,
        cursor: 'entry/${testPartition(workspaceId: 'foreign').key}/0000',
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'cursor',
          LocalJournalErrorCode.scopeMismatch,
        ),
      ),
    );
    final missingReference = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      payload: const {
        'amendsOperationId': 'missing_operation',
        'delta': 1,
        'participantId': 'participant_7',
        'stat': 'twoPointMade',
      },
    );
    await expectLater(
      repository.append(missingReference),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'missing reference',
          LocalJournalErrorCode.operationNotFound,
        ),
      ),
    );
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    expect((await repository.append(operation)).savedOnDevice, isTrue);
  });

  test(
    'queued mutation rechecks a corruption latch at transaction entry',
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
      store.unsafeWrite(
        firstKey,
        store
            .unsafeRead(firstKey)!
            .replaceFirst('participant_7', 'participant_8'),
      );

      final gate = Completer<void>();
      store.waitBeforeNextTransactionAction = gate.future;
      final third = testOperation(
        partition: partition,
        sequence: 2,
        previousHash: Fact.known(second.requestHash),
      );
      final queuedAppend = repository.append(third);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        repository.listOperations(partition),
        throwsA(isA<LocalJournalException>()),
      );
      gate.complete();
      await expectLater(
        queuedAppend,
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'queued append',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(
        store.unsafeRead('entry/${partition.key}/0000000000000002'),
        isNull,
      );
    },
  );

  test(
    'retained operations remain bound to the prepared writer package',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      final replacement = _changedPackage(partition, writerEpoch: 2);
      store.unsafeWrite(
        'package/${partition.key}',
        LocalJournalRecordCodec.encode(replacement.toContractMap()),
      );
      final checkpointKey = 'checkpoint/${partition.key}';
      final checkpoint =
          LocalJournalRecordCodec.decode(store.unsafeRead(checkpointKey)!)
            ..['writerEpoch'] = 2
            ..['preparationPackageChecksum'] = Fact<String>.known(
              replacement.packageChecksum,
            ).toContractMap((value) => value);
      store.unsafeWrite(
        checkpointKey,
        LocalJournalRecordCodec.encode(checkpoint),
      );

      await expectLater(
        repository.verifyIntegrity(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'operation binding',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'malformed stored reference index is corruption rather than caller input',
    () async {
      final first = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(first);
      await repository.verifyIntegrity(partition);
      final indexKey = 'operationIndex/${partition.key}/${first.operationId}';
      final malformed = LocalJournalRecordCodec.decode(
        store.unsafeRead(indexKey)!,
      )..['localSequence'] = 'not-an-integer';
      store.unsafeWrite(indexKey, LocalJournalRecordCodec.encode(malformed));
      final amendment = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(first.requestHash),
        payload: {
          'amendsOperationId': first.operationId,
          'delta': 1,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
      );

      await expectLater(
        repository.append(amendment),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'malformed stored reference',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      await expectLater(
        repository.append(
          testOperation(
            partition: partition,
            sequence: 1,
            previousHash: Fact.known(first.requestHash),
          ),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'delivery lookup validates retained entry against both indexes',
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
      final changedFirst = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        payload: const {
          'delta': 2,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
      );
      final firstKey = 'entry/${partition.key}/0000000000000000';
      store.unsafeWrite(
        firstKey,
        LocalJournalRecordCodec.encode(
          LocalJournalEntry(
            operation: changedFirst,
            delivery: LocalJournalDelivery.savedOnDevice(
              changedFirst.operationId,
            ),
          ).toContractMap(),
        ),
      );
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.queue(partition, first.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'entry/index mismatch',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      await expectLater(
        repository.append(
          testOperation(
            partition: partition,
            sequence: 2,
            previousHash: Fact.known(second.requestHash),
          ),
        ),
        throwsA(isA<LocalJournalException>()),
      );
    },
  );

  test(
    'delivery updates validate package binding before the first write',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.verifyIntegrity(partition);
      final forged = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        operationId: operation.operationId,
        commandId: operation.commandId,
        writerEpoch: 2,
      );
      final forgedIndex = _testIndexPayload(forged, pruned: false);
      store.unsafeWrite(
        'entry/${partition.key}/0000000000000000',
        LocalJournalRecordCodec.encode(
          LocalJournalEntry(
            operation: forged,
            delivery: LocalJournalDelivery.savedOnDevice(forged.operationId),
          ).toContractMap(),
        ),
      );
      store.unsafeWrite(
        'operationIndex/${partition.key}/${forged.operationId}',
        LocalJournalRecordCodec.encode(forgedIndex),
      );
      store.unsafeWrite(
        'commandIndex/${partition.key}/${forged.commandId}',
        LocalJournalRecordCodec.encode(forgedIndex),
      );
      store.failAtPut = 1;
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.queue(partition, operation.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'package binding',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      expect(store.failAtPut, 1, reason: 'failure must precede first write');
      await expectLater(
        repository.getCheckpoint(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'delivery updates reject package checkpoint divergence before a write',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      await repository.verifyIntegrity(partition);
      store.unsafeWrite(
        'package/${partition.key}',
        LocalJournalRecordCodec.encode(
          _changedPackage(partition).toContractMap(),
        ),
      );
      store.failAtPut = 1;
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.queue(partition, operation.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'package/checkpoint divergence',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      expect(store.failAtPut, 1, reason: 'failure must precede first write');
      await expectLater(
        repository.getCheckpoint(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'delivery updates treat an indexed missing checkpoint as corruption',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      store.unsafeDelete('checkpoint/${partition.key}');
      store.failAtPut = 1;
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.queue(partition, operation.operationId),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'orphan index',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      expect(store.failAtPut, 1, reason: 'failure must precede first write');
    },
  );

  test('malformed index entry key is typed corruption and latches', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    await repository.verifyIntegrity(partition);
    final indexKey = 'operationIndex/${partition.key}/${operation.operationId}';
    final malformed = LocalJournalRecordCodec.decode(
      store.unsafeRead(indexKey)!,
    )..['entryKey'] = 42;
    store.unsafeWrite(indexKey, LocalJournalRecordCodec.encode(malformed));

    await expectLater(
      repository.queue(partition, operation.operationId),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'typed corruption',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'latched',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'exact replay validates persisted index pair before conflicts',
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
      final operationIndexKey =
          'operationIndex/${partition.key}/${first.operationId}';
      final corrupted = LocalJournalRecordCodec.decode(
        store.unsafeRead(operationIndexKey)!,
      )..['operationRecordHash'] = hashA;
      store.unsafeWrite(
        operationIndexKey,
        LocalJournalRecordCodec.encode(corrupted),
      );

      await expectLater(
        repository.append(first),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'persisted index pair',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      await expectLater(
        repository.append(
          testOperation(
            partition: partition,
            sequence: 2,
            previousHash: Fact.known(second.requestHash),
          ),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test('pruned exact replay rejects a corrupted command index', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    await repository.storeServerReceipt(partition, testReceipt(operation));
    await _submit(repository, partition);
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'pruned_replay_archive',
      manifestId: 'pruned_replay_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 1, 20),
    );
    await repository.confirmRecoveryArchivePersisted(
      partition,
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      confirmation: 'recoveryArchivePersisted',
    );
    await repository.pruneAcknowledged(
      partition,
      throughSequence: 0,
      recoveryArchiveId: archive.archiveId,
      recoveryArchiveChecksum: archive.checksum,
      prunedAt: DateTime.utc(2026, 9, 9, 1, 21),
    );
    final commandIndexKey =
        'commandIndex/${partition.key}/${operation.commandId}';
    final corrupted = LocalJournalRecordCodec.decode(
      store.unsafeRead(commandIndexKey)!,
    )..['semanticHash'] = hashA;
    store.unsafeWrite(
      commandIndexKey,
      LocalJournalRecordCodec.encode(corrupted),
    );

    await expectLater(
      repository.append(operation),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'pruned index pair',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'receipt advancement rejects forged out-of-order acceptance before writes',
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
      final forgedReceipt = testReceipt(second);
      final secondKey = 'entry/${partition.key}/0000000000000001';
      store.unsafeWrite(
        secondKey,
        LocalJournalRecordCodec.encode(
          LocalJournalEntry(
            operation: second,
            delivery: LocalJournalDelivery(
              operationId: second.operationId,
              state: JournalDeliveryState.accepted,
              retryCount: 0,
              nextAttemptAt: const Fact.notApplicable(reasonCode: 'accepted'),
              lastErrorCode: const Fact.notApplicable(reasonCode: 'accepted'),
              pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
              serverReceipt: Fact.known(forgedReceipt),
              retryPolicy: const RetryPolicyMetadata(jitterBasisPoints: 10000),
            ),
          ).toContractMap(),
        ),
      );
      store.failAtPut = 1;
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.storeServerReceipt(partition, testReceipt(first)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'missing durable receipt row',
            LocalJournalErrorCode.receiptMismatch,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      expect(store.failAtPut, 1, reason: 'failure must precede first write');
    },
  );

  test('accepted exact replay requires its durable receipt row', () async {
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
    await repository.storeServerReceipt(partition, testReceipt(first));
    await repository.verifyIntegrity(partition);
    store.unsafeDelete('receipt/${partition.key}/${first.operationId}');

    await expectLater(
      repository.append(first),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'missing durable row',
          LocalJournalErrorCode.receiptMismatch,
        ),
      ),
    );
    await expectLater(
      repository.append(
        testOperation(
          partition: partition,
          sequence: 2,
          previousHash: Fact.known(second.requestHash),
        ),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'latched capture',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test('known receipt requires accepted persisted delivery state', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final receipt = testReceipt(operation);
    final entryKey = 'entry/${partition.key}/0000000000000000';
    final entry = LocalJournalRecordCodec.decode(store.unsafeRead(entryKey)!);
    final delivery = Map<String, Object?>.from(entry['delivery']! as Map)
      ..['serverReceipt'] = Fact<OperationReceiptContract>.known(
        receipt,
      ).toContractMap((value) => operationReceiptToMap(value));
    entry['delivery'] = delivery;
    store.unsafeWrite(entryKey, LocalJournalRecordCodec.encode(entry));
    store.unsafeWrite(
      'receipt/${partition.key}/${operation.operationId}',
      LocalJournalRecordCodec.encode(operationReceiptToMap(receipt)),
    );

    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'contradictory delivery',
          LocalJournalErrorCode.receiptMismatch,
        ),
      ),
    );
  });

  test('unprepared prune does not poison a prepared workspace', () async {
    final unprepared = testPartition(workspaceId: 'workspace_unprepared');
    await expectLater(
      repository.pruneAcknowledged(
        unprepared,
        throughSequence: 0,
        recoveryArchiveId: 'missing_archive',
        recoveryArchiveChecksum: hashA,
        prunedAt: DateTime.utc(2026, 9, 9, 1, 30),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'unprepared workspace',
          LocalJournalErrorCode.operationNotFound,
        ),
      ),
    );
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    expect((await repository.append(operation)).savedOnDevice, isTrue);
  });

  test('accepted checkpoint must match contiguous durable receipts', () async {
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await repository.append(operation);
    final checkpointKey = 'checkpoint/${partition.key}';
    final corrupted =
        LocalJournalRecordCodec.decode(store.unsafeRead(checkpointKey)!)
          ..['acceptedThroughSequence'] = const Fact<int>.known(
            0,
          ).toContractMap((value) => value)
          ..['acceptedJournalHead'] = const Fact<String>.known(
            'forged_head',
          ).toContractMap((value) => value)
          ..['acceptedJournalHash'] = const Fact<String>.known(
            hashA,
          ).toContractMap((value) => value);
    store.unsafeWrite(checkpointKey, LocalJournalRecordCodec.encode(corrupted));

    await expectLater(
      repository.verifyIntegrity(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'accepted boundary',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test('staged prune validates the complete already-pruned prefix', () async {
    final operations = await _appendTwoAccepted(repository, partition);
    await _submit(repository, partition);
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'staged_prune_archive',
      manifestId: 'staged_prune_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 2),
    );
    await repository.confirmRecoveryArchivePersisted(
      partition,
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      confirmation: 'recoveryArchivePersisted',
    );
    await repository.pruneAcknowledged(
      partition,
      throughSequence: 0,
      recoveryArchiveId: archive.archiveId,
      recoveryArchiveChecksum: archive.checksum,
      prunedAt: DateTime.utc(2026, 9, 9, 2, 1),
    );
    store.unsafeDelete(
      'receipt/${partition.key}/${operations.first.operationId}',
    );
    final before = store.unsafeSnapshot();

    await expectLater(
      repository.pruneAcknowledged(
        partition,
        throughSequence: 1,
        recoveryArchiveId: archive.archiveId,
        recoveryArchiveChecksum: archive.checksum,
        prunedAt: DateTime.utc(2026, 9, 9, 2, 2),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.receiptMismatch,
        ),
      ),
    );
    expect(store.unsafeSnapshot(), before);
    expect(
      store.unsafeRead('entry/${partition.key}/0000000000000001'),
      isNotNull,
    );
  });

  test('prune rejects corrupted secondary indexes before any write', () async {
    final operations = await _appendTwoAccepted(repository, partition);
    await _submit(repository, partition);
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'index_guard_archive',
      manifestId: 'index_guard_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 3),
    );
    await repository.confirmRecoveryArchivePersisted(
      partition,
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      confirmation: 'recoveryArchivePersisted',
    );
    final commandKey =
        'commandIndex/${partition.key}/${operations.first.commandId}';
    final changed = LocalJournalRecordCodec.decode(
      store.unsafeRead(commandKey)!,
    )..['requestHash'] = hashA;
    store.unsafeWrite(commandKey, LocalJournalRecordCodec.encode(changed));
    store.failAtPut = 1;
    final before = store.unsafeSnapshot();

    await expectLater(
      repository.pruneAcknowledged(
        partition,
        throughSequence: 1,
        recoveryArchiveId: archive.archiveId,
        recoveryArchiveChecksum: archive.checksum,
        prunedAt: DateTime.utc(2026, 9, 9, 3, 1),
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(store.unsafeSnapshot(), before);
    expect(store.failAtPut, 1, reason: 'validation must precede first write');
  });

  test(
    'recovery export becomes stale when durable receipt evidence changes',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      final stale = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'pre_receipt_archive',
        manifestId: 'pre_receipt_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 3, 30),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: stale.archiveId,
        checksum: stale.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      await repository.storeServerReceipt(partition, testReceipt(operation));
      await _submit(repository, partition);
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.pruneAcknowledged(
          partition,
          throughSequence: 0,
          recoveryArchiveId: stale.archiveId,
          recoveryArchiveChecksum: stale.checksum,
          prunedAt: DateTime.utc(2026, 9, 9, 3, 31),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'stale export',
            LocalJournalErrorCode.consentRequired,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);

      final current = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'post_receipt_archive',
        manifestId: 'post_receipt_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 3, 32),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: current.archiveId,
        checksum: current.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      final checkpoint = await repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: current.archiveId,
        recoveryArchiveChecksum: current.checksum,
        prunedAt: DateTime.utc(2026, 9, 9, 3, 33),
      );
      expect(checkpoint.prunedThroughSequence.valueOrNull, 0);
    },
  );

  test('caller checksum conflict does not poison a valid export', () async {
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'checksum_conflict_archive',
      manifestId: 'checksum_conflict_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 3, 40),
    );
    final wrongChecksum = archive.checksum == hashA ? hashB : hashA;
    await expectLater(
      repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archive.archiveId,
        checksum: wrongChecksum,
        confirmation: 'recoveryArchivePersisted',
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'caller checksum',
          LocalJournalErrorCode.payloadKeyConflict,
        ),
      ),
    );
    await repository.confirmRecoveryArchivePersisted(
      partition,
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      confirmation: 'recoveryArchivePersisted',
    );
    expect(await repository.getCheckpoint(partition), isNotNull);
  });

  test(
    'workspace growth makes an export stale without poisoning capture',
    () async {
      final first = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(first);
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'growth_stale_archive',
        manifestId: 'growth_stale_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 3, 45),
      );
      final second = testOperation(
        partition: partition,
        sequence: 1,
        previousHash: Fact.known(first.requestHash),
      );
      await repository.append(second);
      await expectLater(
        repository.confirmRecoveryArchivePersisted(
          partition,
          archiveId: archive.archiveId,
          checksum: archive.checksum,
          confirmation: 'recoveryArchivePersisted',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'stale export',
            LocalJournalErrorCode.consentRequired,
          ),
        ),
      );
      final third = testOperation(
        partition: partition,
        sequence: 2,
        previousHash: Fact.known(second.requestHash),
      );
      expect((await repository.append(third)).savedOnDevice, isTrue);
    },
  );

  test(
    'legacy local-v2 export audit requires re-export without latching',
    () async {
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'legacy_v2_archive',
        manifestId: 'legacy_v2_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 3, 50),
      );
      store.unsafeWrite(
        'recoveryExport/${partition.key}/${archive.archiveId}',
        LocalJournalRecordCodec.encode({
          'archiveId': archive.archiveId,
          'capturedThroughSequence': const Fact<int>.notApplicable(
            reasonCode: 'no_operations',
          ).toContractMap((value) => value),
          'checksum': archive.checksum,
          'exportedAt': archive.exportedAt,
          'localSchemaVersion': 2,
          'manifestId': archive.manifestId,
          'persistedConfirmation': false,
          'reexportRequired': false,
        }),
      );
      await expectLater(
        repository.confirmRecoveryArchivePersisted(
          partition,
          archiveId: archive.archiveId,
          checksum: archive.checksum,
          confirmation: 'recoveryArchivePersisted',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'legacy audit',
            LocalJournalErrorCode.unsupportedSchemaVersion,
          ),
        ),
      );
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      expect((await repository.append(operation)).savedOnDevice, isTrue);
    },
  );

  test('malformed recovery audit version latches before any write', () async {
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'malformed_audit_version_archive',
      manifestId: 'malformed_audit_version_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 3, 55),
    );
    final auditKey = 'recoveryExport/${partition.key}/${archive.archiveId}';
    final malformed = LocalJournalRecordCodec.decode(
      store.unsafeRead(auditKey)!,
    )..['auditVersion'] = 0;
    store.unsafeWrite(auditKey, LocalJournalRecordCodec.encode(malformed));
    store.failAtPut = 1;
    final before = store.unsafeSnapshot();

    await expectLater(
      repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archive.archiveId,
        checksum: archive.checksum,
        confirmation: 'recoveryArchivePersisted',
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'malformed audit version',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(store.unsafeSnapshot(), before);
    expect(store.failAtPut, 1, reason: 'failure must precede first write');
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'latched capture',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test('current recovery audit missing its version latches capture', () async {
    final archive = await repository.exportRecoveryArchive(
      partition,
      archiveId: 'missing_audit_version_archive',
      manifestId: 'missing_audit_version_manifest',
      exportedAt: DateTime.utc(2026, 9, 9, 3, 58),
    );
    final auditKey = 'recoveryExport/${partition.key}/${archive.archiveId}';
    final malformed = LocalJournalRecordCodec.decode(
      store.unsafeRead(auditKey)!,
    )..remove('auditVersion');
    store.unsafeWrite(auditKey, LocalJournalRecordCodec.encode(malformed));
    store.failAtPut = 1;
    final before = store.unsafeSnapshot();

    await expectLater(
      repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archive.archiveId,
        checksum: archive.checksum,
        confirmation: 'recoveryArchivePersisted',
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'missing discriminator',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(store.unsafeSnapshot(), before);
    expect(store.failAtPut, 1, reason: 'failure must precede first write');
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'latched capture',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'workspace-bound export audit cannot be copied to authorize prune',
    () async {
      final operationA = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operationA);
      await repository.storeServerReceipt(partition, testReceipt(operationA));
      await _submit(repository, partition);
      final archiveA = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'cross_workspace_archive',
        manifestId: 'cross_workspace_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 4),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archiveA.archiveId,
        checksum: archiveA.checksum,
        confirmation: 'recoveryArchivePersisted',
      );

      final partitionB = testPartition(workspaceId: 'workspace_2');
      await repository.prepareGame(testPackage(partitionB));
      final operationB = testOperation(
        partition: partitionB,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operationB);
      await repository.storeServerReceipt(partitionB, testReceipt(operationB));
      await _submit(repository, partitionB);

      final auditA = store.unsafeRead(
        'recoveryExport/${partition.key}/${archiveA.archiveId}',
      )!;
      store.unsafeWrite(
        'recoveryExport/${partitionB.key}/${archiveA.archiveId}',
        auditA,
      );
      final before = store.unsafeSnapshot();
      await expectLater(
        repository.pruneAcknowledged(
          partitionB,
          throughSequence: 0,
          recoveryArchiveId: archiveA.archiveId,
          recoveryArchiveChecksum: archiveA.checksum,
          prunedAt: DateTime.utc(2026, 9, 9, 4, 1),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      expect(
        store.unsafeRead('entry/${partitionB.key}/0000000000000000'),
        isNotNull,
      );
    },
  );

  test(
    'archive parsing rejects deep and broad shapes before canonicalization',
    () {
      final deep =
          '${List.filled(50000, '{"x":').join()}0'
          '${List.filled(50000, '}').join()}';
      expect(
        () => LocalJournalRecoveryArchive.parse(
          deep,
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'deep code',
            LocalJournalErrorCode.archiveTooLarge,
          ),
        ),
      );

      final broad =
          '{"x":[${List.filled(LocalGameJournalLimits.maxOperationsPerWorkspace + 1, '0').join(',')}]}';
      expect(
        () => LocalJournalRecoveryArchive.parse(
          broad,
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'broad code',
            LocalJournalErrorCode.archiveTooLarge,
          ),
        ),
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          '0',
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'scalar code',
            LocalJournalErrorCode.archivePartial,
          ),
        ),
      );
      expect(
        () => LocalJournalRecoveryArchive.parse(
          '{"x":"é"}',
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'unicode code',
            LocalJournalErrorCode.archiveTampered,
          ),
        ),
      );
      final longString = OfficialStatCanonicalEncoding.encode({
        'x': 'a' * (LocalGameJournalLimits.maxStringLength + 1),
      });
      expect(
        () => LocalJournalRecoveryArchive.parse(
          longString,
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'long scalar code',
            LocalJournalErrorCode.archiveTooLarge,
          ),
        ),
      );
      final longKey = OfficialStatCanonicalEncoding.encode({
        'k' * (LocalGameJournalLimits.maxStringLength + 1): 0,
      });
      expect(
        () => LocalJournalRecoveryArchive.parse(
          longKey,
          expectedActorAccountId: 'account_1',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'long key code',
            LocalJournalErrorCode.archiveTooLarge,
          ),
        ),
      );
    },
  );

  test(
    'archive parsing rejects duplicate retained operation and command IDs',
    () {
      for (final duplicateOperationId in [true, false]) {
        final encoded = _archiveWithDuplicateRetainedId(
          partition,
          duplicateOperationId: duplicateOperationId,
        );
        expect(
          () => LocalJournalRecoveryArchive.parse(
            encoded,
            expectedActorAccountId: partition.actorAccountId,
            expectedPartition: partition,
          ),
          throwsA(
            isA<LocalJournalException>().having(
              (error) => error.code,
              duplicateOperationId ? 'operation ID' : 'command ID',
              LocalJournalErrorCode.archiveTampered,
            ),
          ),
        );
      }
    },
  );

  test('archive parsing rejects a forged accepted checkpoint boundary', () {
    final package = testPackage(partition);
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    final archive = LocalJournalRecoveryArchive.create(
      archiveId: 'forged_accepted_archive',
      manifestId: 'forged_accepted_manifest',
      partition: partition,
      preparedPackage: package,
      checkpoint: _checkpointFor(package, [operation]),
      entries: [
        LocalJournalEntry(
          operation: operation,
          delivery: LocalJournalDelivery.savedOnDevice(operation.operationId),
        ),
      ],
      receiptTombstones: const [],
      exportedByAccountId: partition.actorAccountId,
      exportedByDeviceSessionId: package.deviceSessionId,
      exportedAt: DateTime.utc(2026, 9, 9, 7, 10),
    );
    final map = Map<String, Object?>.from(archive.toContractMap());
    final checkpoint = Map<String, Object?>.from(map['checkpoint']! as Map)
      ..['acceptedThroughSequence'] = const Fact<int>.known(
        0,
      ).toContractMap((value) => value)
      ..['acceptedJournalHead'] = const Fact<String>.known(
        'forged_head',
      ).toContractMap((value) => value)
      ..['acceptedJournalHash'] = const Fact<String>.known(
        hashA,
      ).toContractMap((value) => value);
    map['checkpoint'] = checkpoint;
    map.remove('checksum');
    map['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(map);
    final encoded = OfficialStatCanonicalEncoding.encode(map);

    expect(
      () => LocalJournalRecoveryArchive.parse(
        encoded,
        expectedActorAccountId: partition.actorAccountId,
        expectedPartition: partition,
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'accepted boundary',
          LocalJournalErrorCode.archiveTampered,
        ),
      ),
    );
  });

  test(
    'deletion consent rejects coherent retained identity substitution',
    () async {
      final original = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(original);
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'retained_substitution_manifest',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 7, 20),
      );
      final consent = LocalDeletionConsent(
        consentId: 'retained_substitution_consent',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: manifest.deviceSessionId,
        grantedAt: DateTime.utc(2026, 9, 9, 7, 21),
      );
      final replacement = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        operationId: 'replacement_operation',
        commandId: 'replacement_command',
        payload: const {
          'delta': 2,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
      );
      store.unsafeWrite(
        'entry/${partition.key}/0000000000000000',
        LocalJournalRecordCodec.encode(
          LocalJournalEntry(
            operation: replacement,
            delivery: LocalJournalDelivery.savedOnDevice(
              replacement.operationId,
            ),
          ).toContractMap(),
        ),
      );
      store.unsafeDelete(
        'operationIndex/${partition.key}/${original.operationId}',
      );
      store.unsafeDelete('commandIndex/${partition.key}/${original.commandId}');
      final replacementIndex = _testIndexPayload(replacement, pruned: false);
      store.unsafeWrite(
        'operationIndex/${partition.key}/${replacement.operationId}',
        LocalJournalRecordCodec.encode(replacementIndex),
      );
      store.unsafeWrite(
        'commandIndex/${partition.key}/${replacement.commandId}',
        LocalJournalRecordCodec.encode(replacementIndex),
      );
      final checkpointKey = 'checkpoint/${partition.key}';
      final checkpoint =
          LocalJournalRecordCodec.decode(store.unsafeRead(checkpointKey)!)
            ..['lastOperationHash'] = Fact<String>.known(
              replacement.requestHash,
            ).toContractMap((value) => value)
            ..['retainedOperationBytes'] = replacement.byteCount;
      store.unsafeWrite(
        checkpointKey,
        LocalJournalRecordCodec.encode(checkpoint),
      );

      await expectLater(
        repository.enumerateDeletionReconciliation(consent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'retained substitution',
            LocalJournalErrorCode.manifestMismatch,
          ),
        ),
      );
    },
  );

  test(
    'deletion consent rejects coherent pruned identity substitution',
    () async {
      final original = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(original);
      await repository.storeServerReceipt(partition, testReceipt(original));
      await _submit(repository, partition);
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'pruned_substitution_archive',
        manifestId: 'pruned_substitution_export_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 7, 30),
      );
      await repository.confirmRecoveryArchivePersisted(
        partition,
        archiveId: archive.archiveId,
        checksum: archive.checksum,
        confirmation: 'recoveryArchivePersisted',
      );
      await repository.pruneAcknowledged(
        partition,
        throughSequence: 0,
        recoveryArchiveId: archive.archiveId,
        recoveryArchiveChecksum: archive.checksum,
        prunedAt: DateTime.utc(2026, 9, 9, 7, 31),
      );
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'pruned_substitution_manifest',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 7, 32),
      );
      final consent = LocalDeletionConsent(
        consentId: 'pruned_substitution_consent',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: manifest.deviceSessionId,
        grantedAt: DateTime.utc(2026, 9, 9, 7, 33),
      );
      final replacement = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        operationId: 'replacement_pruned_operation',
        commandId: 'replacement_pruned_command',
        payload: const {
          'delta': 2,
          'participantId': 'participant_7',
          'stat': 'twoPointMade',
        },
      );
      final replacementReceipt = testReceipt(replacement);
      store.unsafeDelete(
        'operationIndex/${partition.key}/${original.operationId}',
      );
      store.unsafeDelete('commandIndex/${partition.key}/${original.commandId}');
      store.unsafeDelete('receipt/${partition.key}/${original.operationId}');
      final replacementIndex = _testIndexPayload(replacement, pruned: true);
      store.unsafeWrite(
        'operationIndex/${partition.key}/${replacement.operationId}',
        LocalJournalRecordCodec.encode(replacementIndex),
      );
      store.unsafeWrite(
        'commandIndex/${partition.key}/${replacement.commandId}',
        LocalJournalRecordCodec.encode(replacementIndex),
      );
      store.unsafeWrite(
        'receipt/${partition.key}/${replacement.operationId}',
        LocalJournalRecordCodec.encode(
          operationReceiptToMap(replacementReceipt),
        ),
      );
      final checkpointKey = 'checkpoint/${partition.key}';
      final checkpoint =
          LocalJournalRecordCodec.decode(store.unsafeRead(checkpointKey)!)
            ..['lastOperationHash'] = Fact<String>.known(
              replacement.requestHash,
            ).toContractMap((value) => value)
            ..['prunedThroughHash'] = Fact<String>.known(
              replacement.requestHash,
            ).toContractMap((value) => value)
            ..['acceptedJournalHash'] = Fact<String>.known(
              replacementReceipt.acceptedJournalHash,
            ).toContractMap((value) => value)
            ..['acceptedJournalHead'] = Fact<String>.known(
              replacementReceipt.acceptedJournalHead,
            ).toContractMap((value) => value);
      store.unsafeWrite(
        checkpointKey,
        LocalJournalRecordCodec.encode(checkpoint),
      );

      await expectLater(
        repository.enumerateDeletionReconciliation(consent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'pruned substitution',
            LocalJournalErrorCode.manifestMismatch,
          ),
        ),
      );
    },
  );

  test(
    'legacy deletion manifest requires fresh consent without poisoning',
    () async {
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'legacy_deletion_manifest',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 7, 40),
      );
      final legacy = Map<String, Object?>.from(manifest.toContractMap());
      final workspaces = (legacy['workspaces']! as List)
          .map((raw) {
            return Map<String, Object?>.from(raw as Map)
              ..remove('reconciliationEvidenceChecksum')
              // V1 counted only retained rows; this is a valid fully pruned
              // legacy summary even though its lifetime sequence is nonzero.
              ..['nextLocalSequence'] = 1;
          })
          .toList(growable: false);
      legacy['manifestVersion'] = 1;
      legacy['workspaces'] = workspaces;
      legacy.remove('checksum');
      legacy['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(legacy);
      store.unsafeWrite(
        'deletionManifest/${partition.actorAccountId}/device_1/'
        '${manifest.manifestId}',
        LocalJournalRecordCodec.encode(legacy),
      );
      final consent = LocalDeletionConsent(
        consentId: 'legacy_deletion_consent',
        manifestId: manifest.manifestId,
        manifestChecksum: legacy['checksum']! as String,
        deviceSessionId: 'device_1',
        grantedAt: DateTime.utc(2026, 9, 9, 7, 41),
      );

      await expectLater(
        repository.enumerateDeletionReconciliation(consent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'fresh consent',
            LocalJournalErrorCode.consentRequired,
          ),
        ),
      );
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      expect((await repository.append(operation)).savedOnDevice, isTrue);
    },
  );

  test('malformed deletion manifest version latches capture', () async {
    final manifest = await repository.createDeletionRecoveryManifest(
      manifestId: 'malformed_version_manifest',
      deviceSessionId: 'device_1',
      createdAt: DateTime.utc(2026, 9, 9, 7, 50),
    );
    final malformed = Map<String, Object?>.from(manifest.toContractMap())
      ..['manifestVersion'] = 'two'
      ..remove('checksum');
    malformed['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(malformed);
    store.unsafeWrite(
      'deletionManifest/${partition.actorAccountId}/device_1/'
      '${manifest.manifestId}',
      LocalJournalRecordCodec.encode(malformed),
    );
    final consent = LocalDeletionConsent(
      consentId: 'malformed_version_consent',
      manifestId: manifest.manifestId,
      manifestChecksum: malformed['checksum']! as String,
      deviceSessionId: 'device_1',
      grantedAt: DateTime.utc(2026, 9, 9, 7, 51),
    );

    await expectLater(
      repository.enumerateDeletionReconciliation(consent),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'malformed version',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'latched capture',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
  });

  test(
    'invalid persisted deletion manifest checksum latches capture',
    () async {
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'bad_checksum_manifest',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 7, 55),
      );
      final manifestKey =
          'deletionManifest/${partition.actorAccountId}/device_1/'
          '${manifest.manifestId}';
      final malformed = LocalJournalRecordCodec.decode(
        store.unsafeRead(manifestKey)!,
      )..['checksum'] = hashA;
      store.unsafeWrite(manifestKey, LocalJournalRecordCodec.encode(malformed));
      final consent = LocalDeletionConsent(
        consentId: 'bad_checksum_consent',
        manifestId: manifest.manifestId,
        manifestChecksum: hashA,
        deviceSessionId: 'device_1',
        grantedAt: DateTime.utc(2026, 9, 9, 7, 56),
      );

      await expectLater(
        repository.enumerateDeletionReconciliation(consent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'bad checksum',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      await expectLater(
        repository.getCheckpoint(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'manifest creation rejects a missing canonical workspace index',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      store.unsafeDelete(
        'workspaceIndex/${partition.actorAccountId}/device_1/'
        '${partition.scope.key}/${partition.workspaceId}',
      );
      final before = store.unsafeSnapshot();
      await expectLater(
        repository.createDeletionRecoveryManifest(
          manifestId: 'missing_index_manifest',
          deviceSessionId: 'device_1',
          createdAt: DateTime.utc(2026, 9, 9, 5),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
    },
  );

  test(
    'manifest creation rejects extra and swapped workspace indexes',
    () async {
      final partitionB = testPartition(workspaceId: 'workspace_2');
      await repository.prepareGame(testPackage(partitionB));
      final indexA =
          'workspaceIndex/${partition.actorAccountId}/device_1/'
          '${partition.scope.key}/${partition.workspaceId}';
      final indexB =
          'workspaceIndex/${partitionB.actorAccountId}/device_1/'
          '${partitionB.scope.key}/${partitionB.workspaceId}';
      final valueA = store.unsafeRead(indexA)!;
      final valueB = store.unsafeRead(indexB)!;
      store.unsafeWrite(indexA, valueB);
      store.unsafeWrite(indexB, valueA);
      final beforeSwap = store.unsafeSnapshot();
      await expectLater(
        repository.createDeletionRecoveryManifest(
          manifestId: 'swapped_index_manifest',
          deviceSessionId: 'device_1',
          createdAt: DateTime.utc(2026, 9, 9, 5, 1),
        ),
        throwsA(isA<LocalJournalException>()),
      );
      expect(store.unsafeSnapshot(), beforeSwap);

      final extraStore = FaultInjectingMemoryStore();
      final extraRepository = _repository(extraStore);
      await extraRepository.open();
      await extraRepository.prepareGame(testPackage(partition));
      await extraRepository.prepareGame(testPackage(partitionB));
      final extraPartition = testPartition(workspaceId: 'workspace_extra');
      extraStore.unsafeWrite(
        'workspaceIndex/${extraPartition.actorAccountId}/device_1/'
        '${extraPartition.scope.key}/${extraPartition.workspaceId}',
        LocalJournalRecordCodec.encode({
          'deviceSessionId': 'device_1',
          'packageChecksum': hashA,
          'partition': extraPartition.toContractMap(),
        }),
      );
      final beforeExtra = extraStore.unsafeSnapshot();
      await expectLater(
        extraRepository.createDeletionRecoveryManifest(
          manifestId: 'extra_index_manifest',
          deviceSessionId: 'device_1',
          createdAt: DateTime.utc(2026, 9, 9, 5, 2),
        ),
        throwsA(isA<LocalJournalException>()),
      );
      expect(extraStore.unsafeSnapshot(), beforeExtra);
      await extraRepository.close();
    },
  );

  test(
    'consented reconciliation revalidates canonical index coverage',
    () async {
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(operation);
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'reconciliation_index_manifest',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 6),
      );
      final consent = LocalDeletionConsent(
        consentId: 'reconciliation_index_consent',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: 'device_1',
        grantedAt: DateTime.utc(2026, 9, 9, 6, 1),
      );
      store.unsafeDelete(
        'workspaceIndex/${partition.actorAccountId}/device_1/'
        '${partition.scope.key}/${partition.workspaceId}',
      );
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
    },
  );

  test(
    'deletion inventory detects package and workspace-index double loss',
    () async {
      final healthyPartition = testPartition(workspaceId: 'workspace_healthy');
      await repository.prepareGame(testPackage(healthyPartition));
      await repository.verifyIntegrity(healthyPartition);
      final orphanedOperation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await repository.append(orphanedOperation);
      store.unsafeDelete('package/${partition.key}');
      store.unsafeDelete(
        'workspaceIndex/${partition.actorAccountId}/device_1/'
        '${partition.scope.key}/${partition.workspaceId}',
      );
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.createDeletionRecoveryManifest(
          manifestId: 'double_loss_manifest',
          deviceSessionId: 'device_1',
          createdAt: DateTime.utc(2026, 9, 9, 6, 2),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);

      // Idempotent open is not repair authority and cannot clear the latch.
      await expectLater(
        repository.open(),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      final healthyOperation = testOperation(
        partition: healthyPartition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await expectLater(
        repository.append(healthyOperation),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(
        store.unsafeRead('entry/${healthyPartition.key}/0000000000000000'),
        isNull,
      );
    },
  );

  test(
    'consent cannot omit a later workspace after package and index double loss',
    () async {
      final manifest = await repository.createDeletionRecoveryManifest(
        manifestId: 'manifest_before_double_loss',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 9, 6, 3),
      );
      final consent = LocalDeletionConsent(
        consentId: 'consent_before_double_loss',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: manifest.deviceSessionId,
        grantedAt: DateTime.utc(2026, 9, 9, 6, 4),
      );
      final laterPartition = testPartition(workspaceId: 'workspace_later');
      await repository.prepareGame(testPackage(laterPartition));
      await repository.append(
        testOperation(
          partition: laterPartition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        ),
      );
      store.unsafeDelete('package/${laterPartition.key}');
      store.unsafeDelete(
        'workspaceIndex/${laterPartition.actorAccountId}/device_1/'
        '${laterPartition.scope.key}/${laterPartition.workspaceId}',
      );
      final before = store.unsafeSnapshot();

      late LocalJournalException failure;
      try {
        await repository.enumerateDeletionReconciliation(consent);
        fail('double-loss orphan was omitted from consent reconciliation');
      } on LocalJournalException catch (error) {
        failure = error;
      }
      expect(failure.code, LocalJournalErrorCode.manifestMismatch);
      expect(failure.details['causeCode'], 'mutatedRecord');
      expect(store.unsafeSnapshot(), before);
    },
  );

  test(
    'deletion inventory rejects an export audit copied across workspaces',
    () async {
      final archive = await repository.exportRecoveryArchive(
        partition,
        archiveId: 'inventory_bound_archive',
        manifestId: 'inventory_bound_manifest',
        exportedAt: DateTime.utc(2026, 9, 9, 6, 5),
      );
      final otherPartition = testPartition(workspaceId: 'workspace_other');
      await repository.prepareGame(testPackage(otherPartition));
      final sourceKey = 'recoveryExport/${partition.key}/${archive.archiveId}';
      final copiedKey =
          'recoveryExport/${otherPartition.key}/${archive.archiveId}';
      store.unsafeWrite(copiedKey, store.unsafeRead(sourceKey)!);
      final before = store.unsafeSnapshot();

      await expectLater(
        repository.createDeletionRecoveryManifest(
          manifestId: 'copied_export_manifest',
          deviceSessionId: 'device_1',
          createdAt: DateTime.utc(2026, 9, 9, 6, 6),
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
      expect(store.unsafeSnapshot(), before);
      await expectLater(
        repository.getCheckpoint(partition),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'latched capture',
            LocalJournalErrorCode.mutatedRecord,
          ),
        ),
      );
    },
  );

  test(
    'Packet 07 ordering bounds reject caller input before writes or latch',
    () async {
      final before = store.unsafeSnapshot();
      final invalidFactories = <LocalGameJournalOperation Function()>[
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          gamePeriod: const Fact.known(
            LocalGameJournalLimits.maxPeriodNumber + 1,
          ),
        ),
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          gameClockPosition: const Fact.known(
            LocalGameJournalLimits.maxClockRemainingMs + 1,
          ),
        ),
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          gamePeriod: const Fact.unknown(reasonCode: 'not recorded'),
        ),
        () => testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
          gameClockPosition: const Fact.notApplicable(
            reasonCode: 'not recorded',
          ),
        ),
      ];
      for (final factory in invalidFactories) {
        expect(
          factory,
          throwsA(
            isA<LocalJournalException>().having(
              (error) => error.code,
              'code',
              LocalJournalErrorCode.invalidArgument,
            ),
          ),
        );
      }
      expect(store.unsafeSnapshot(), before);

      final maximum = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        gamePeriod: const Fact.known(LocalGameJournalLimits.maxPeriodNumber),
        gameClockPosition: const Fact.known(
          LocalGameJournalLimits.maxClockRemainingMs,
        ),
      );
      final roundTripped = LocalGameJournalOperation.fromContractMap(
        LocalJournalRecordCodec.decode(
          LocalJournalRecordCodec.encode(maximum.toContractMap()),
        ),
      );
      expect(roundTripped.canonicalJson, maximum.canonicalJson);
      expect(roundTripped.requestHash, maximum.requestHash);
      expect((await repository.append(maximum)).savedOnDevice, isTrue);
    },
  );

  test(
    'close during repository migration cannot rearm stale readiness',
    () async {
      final lifecycleStore = FaultInjectingMemoryStore();
      final oldRepository = _repository(lifecycleStore);
      final migrationEntered = Completer<void>();
      final releaseMigration = Completer<void>();
      lifecycleStore.waitBeforeNextTransactionAction = releaseMigration.future;
      lifecycleStore.onBeforeNextTransactionWait = migrationEntered.complete;
      final staleResult = oldRepository.open().then<Object?>(
        (value) => value,
        onError: (Object error, StackTrace _) => error,
      );
      await migrationEntered.future.timeout(const Duration(seconds: 2));
      await oldRepository.close().timeout(const Duration(milliseconds: 250));

      final freshRepository = _repository(lifecycleStore);
      await freshRepository.open();
      releaseMigration.complete();
      expect(
        await staleResult.timeout(const Duration(seconds: 2)),
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.storageCapabilityUnproven,
        ),
      );
      final freshPartition = testPartition(workspaceId: 'fresh_workspace');
      await freshRepository.prepareGame(testPackage(freshPartition));
      expect(
        (await freshRepository.verifyIntegrity(
          freshPartition,
        )).retainedOperations,
        0,
      );
      await freshRepository.close();

      await oldRepository.open();
      expect(
        (await oldRepository.verifyIntegrity(
          freshPartition,
        )).retainedOperations,
        0,
      );
      await oldRepository.close();
    },
  );
}

LocalGameJournalRepository _repository(FaultInjectingMemoryStore store) =>
    LocalGameJournalRepository(
      store: store,
      activeActorAccountId: 'account_1',
      compatibility: testCompatibility(),
    );

PreparedGameRecoveryPackage _changedPackage(
  JournalPartition partition, {
  int writerEpoch = 1,
}) => PreparedGameRecoveryPackage.create(
  packageId: 'package_changed',
  partition: partition,
  deviceSessionId: 'device_1',
  writerEpoch: writerEpoch,
  journalReducerVersion: 'reducer_v1',
  calculatorVersion: 'calculator_v1',
  rulesProfileId: 'rules_v1',
  competitionPolicyVersion: 'policy_v2',
  assignmentId: 'assignment_changed',
  assignmentVersion: 2,
  rosterSnapshotId: 'roster_snapshot_changed',
  rosterSnapshotHash: hashB,
  acceptedServerSequence: const Fact.notApplicable(
    reasonCode: 'no_server_operations',
  ),
  acceptedJournalHead: 'head_0',
  acceptedJournalHash: hashA,
  preparedAt: DateTime.utc(2026, 9, 9),
);

Future<List<LocalGameJournalOperation>> _appendTwoAccepted(
  LocalGameJournalRepository repository,
  JournalPartition partition,
) async {
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
  await repository.storeServerReceipt(partition, testReceipt(first));
  await repository.storeServerReceipt(partition, testReceipt(second));
  return [first, second];
}

Future<void> _submit(
  LocalGameJournalRepository repository,
  JournalPartition partition,
) async {
  await repository.setSubmissionState(
    partition,
    WorkspaceSubmissionState.submissionQueued,
    observedAt: DateTime.utc(2026, 9, 9, 10),
  );
  await repository.setSubmissionState(
    partition,
    WorkspaceSubmissionState.submitted,
    observedAt: DateTime.utc(2026, 9, 9, 10, 1),
  );
}

String _archiveWithDuplicateRetainedId(
  JournalPartition partition, {
  required bool duplicateOperationId,
}) {
  final package = testPackage(partition);
  final first = testOperation(
    partition: partition,
    sequence: 0,
    previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
  );
  final validSecond = testOperation(
    partition: partition,
    sequence: 1,
    previousHash: Fact.known(first.requestHash),
  );
  final validEntries = [
    LocalJournalEntry(
      operation: first,
      delivery: LocalJournalDelivery.savedOnDevice(first.operationId),
    ),
    LocalJournalEntry(
      operation: validSecond,
      delivery: LocalJournalDelivery.savedOnDevice(validSecond.operationId),
    ),
  ];
  final validArchive = LocalJournalRecoveryArchive.create(
    archiveId: 'duplicate_id_archive',
    manifestId: 'duplicate_id_manifest',
    partition: partition,
    preparedPackage: package,
    checkpoint: _checkpointFor(package, [first, validSecond]),
    entries: validEntries,
    receiptTombstones: const [],
    exportedByAccountId: partition.actorAccountId,
    exportedByDeviceSessionId: package.deviceSessionId,
    exportedAt: DateTime.utc(2026, 9, 9, 7),
  );
  final duplicateSecond = testOperation(
    partition: partition,
    sequence: 1,
    previousHash: Fact.known(first.requestHash),
    operationId: duplicateOperationId ? first.operationId : null,
    commandId: duplicateOperationId ? null : first.commandId,
  );
  final map = Map<String, Object?>.from(validArchive.toContractMap());
  final entries = List<Object?>.from(map['entries']! as List)
    ..[1] = LocalJournalEntry(
      operation: duplicateSecond,
      delivery: LocalJournalDelivery.savedOnDevice(duplicateSecond.operationId),
    ).toContractMap();
  map['entries'] = entries;
  map['checkpoint'] = _checkpointFor(package, [
    first,
    duplicateSecond,
  ]).toContractMap();
  map.remove('checksum');
  map['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(map);
  return OfficialStatCanonicalEncoding.encode(map);
}

LocalWorkspaceCheckpoint _checkpointFor(
  PreparedGameRecoveryPackage package,
  List<LocalGameJournalOperation> operations,
) => LocalWorkspaceCheckpoint(
  partition: package.partition,
  writerEpoch: package.writerEpoch,
  nextLocalSequence: operations.length,
  lastLocalSequence: Fact.known(operations.length - 1),
  lastOperationHash: Fact.known(operations.last.requestHash),
  prunedThroughSequence: const Fact.notApplicable(reasonCode: 'not_pruned'),
  prunedThroughHash: const Fact.notApplicable(reasonCode: 'not_pruned'),
  acceptedThroughSequence: const Fact.notApplicable(reasonCode: 'not_accepted'),
  acceptedJournalHead: const Fact.notApplicable(reasonCode: 'not_accepted'),
  acceptedJournalHash: const Fact.notApplicable(reasonCode: 'not_accepted'),
  retainedOperationCount: operations.length,
  retainedOperationBytes: operations.fold(
    0,
    (total, operation) => total + operation.byteCount,
  ),
  submissionState: WorkspaceSubmissionState.captureOpen,
  preparationPackageChecksum: Fact.known(package.packageChecksum),
  updatedAt: DateTime.utc(2026, 9, 9, 7),
);

Map<String, Object?> _testIndexPayload(
  LocalGameJournalOperation operation, {
  required bool pruned,
}) => {
  'commandId': operation.commandId,
  'entryKey':
      'entry/${operation.partition.key}/'
      '${operation.localSequence.toString().padLeft(16, '0')}',
  'localSequence': operation.localSequence,
  'operationId': operation.operationId,
  'operationRecordHash': OfficialStatCanonicalEncoding.sha256Hex(
    operation.toContractMap(),
  ),
  'payloadHash': operation.payloadHash,
  'pruned': pruned,
  'requestHash': operation.requestHash,
  'semanticHash': operation.semanticHash,
};
