import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/indexed_db_journal_store.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_limits.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart'
    show idbFactoryMemory, idbFactoryNative;

import 'journal_test_support.dart';

const _isWeb = bool.fromEnvironment('dart.library.js_interop');

void main() {
  late String databaseName;

  setUp(() {
    databaseName =
        'hoopsconnect_journal_browser_test_${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    if (_isWeb) {
      await idbFactoryNative
          .deleteDatabase(databaseName)
          .timeout(const Duration(seconds: 5));
    }
  });

  test('real IndexedDB read-write transaction aborts atomically', () async {
    final store = IndexedDbLocalGameJournalStore(databaseName: databaseName);
    final capability = await store.open();
    expect(capability.captureEnabled, isTrue);
    expect(capability.adapter, 'indexeddb');
    expect(capability.encryptedAtRestClaimed, isFalse);
    final originalCause = StateError('callback abort sentinel');
    late LocalJournalException failure;
    try {
      await store.transaction<void>((transaction) async {
        await transaction.put('probe/a', 'first');
        throw originalCause;
      });
      fail('callback failure unexpectedly committed');
    } on LocalJournalException catch (error) {
      failure = error;
    }
    expect(failure.code, LocalJournalErrorCode.transactionAborted);
    expect(failure.details['cause'], same(originalCause));
    expect(failure.details['causeType'], 'StateError');
    expect(failure.details['phase'], 'callback');
    final value = await store.transaction(
      (transaction) => transaction.get('probe/a'),
    );
    expect(value, isNull);
    await store.close();
  }, skip: !_isWeb);

  test(
    'real IndexedDB completion rejection preserves the native abort cause',
    () async {
      final store = IndexedDbLocalGameJournalStore.withCompletionHookForTesting(
        databaseName: databaseName,
        beforeCompletion: (transaction) => transaction.abort(),
      );
      await store.open();
      late LocalJournalException failure;
      try {
        await store.transaction<void>(
          (transaction) => transaction.put('probe/completion', 'pending'),
        );
        fail('aborted native transaction unexpectedly completed');
      } on LocalJournalException catch (error) {
        failure = error;
      }
      final originalCause = failure.details['cause'];
      expect(failure.code, LocalJournalErrorCode.transactionAborted);
      expect(originalCause.runtimeType.toString(), 'DatabaseErrorNative');
      expect(failure.details['causeType'], 'DatabaseErrorNative');
      expect(originalCause.toString(), contains('was aborted'));
      expect(originalCause.toString(), isNot(contains('InvalidState')));
      expect(failure.details['phase'], 'completion');
      await store.close();
    },
    skip: !_isWeb,
  );

  test(
    'real IndexedDB transaction creation preserves the native closed cause',
    () async {
      final store =
          IndexedDbLocalGameJournalStore.withTransactionCreationHookForTesting(
            databaseName: databaseName,
            beforeTransactionCreation: (database) => database.close(),
          );
      await store.open();
      late LocalJournalException failure;
      try {
        await store.transaction<void>(
          (transaction) => transaction.put('probe/creation', 'pending'),
        );
        fail('closed native database unexpectedly created a transaction');
      } on LocalJournalException catch (error) {
        failure = error;
      }
      expect(failure.code, LocalJournalErrorCode.transactionAborted);
      expect(failure.details['cause'], isNotNull);
      expect(failure.details['causeType'], isNot('LocalJournalException'));
      expect(failure.details['phase'], 'transactionCreation');
      await store.close();
    },
    skip: !_isWeb,
  );

  test('caller TypeError remains a non-corruption transaction abort', () async {
    final store = IndexedDbLocalGameJournalStore(databaseName: databaseName);
    await store.open();
    late LocalJournalException failure;
    try {
      await store.transaction<void>((_) async {
        final dynamic wrongType = _QuotaCallbackValue();
        wrongType as String;
      });
      fail('caller TypeError unexpectedly completed');
    } on LocalJournalException catch (error) {
      failure = error;
    }
    expect(failure.code, LocalJournalErrorCode.transactionAborted);
    expect(failure.details['cause'], isA<TypeError>());
    expect(store.capability.captureEnabled, isTrue);
    await store.close();
  }, skip: !_isWeb);

  test('real IndexedDB survives refresh-style close and reopen', () async {
    final partition = testPartition();
    final firstStore = IndexedDbLocalGameJournalStore(
      databaseName: databaseName,
    );
    final first = LocalGameJournalRepository(
      store: firstStore,
      activeActorAccountId: 'account_1',
      compatibility: testCompatibility(),
    );
    await first.open();
    await first.prepareGame(testPackage(partition));
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await first.append(operation);
    await first.close();

    final reopenedStore = IndexedDbLocalGameJournalStore(
      databaseName: databaseName,
    );
    final reopened = LocalGameJournalRepository(
      store: reopenedStore,
      activeActorAccountId: 'account_1',
      compatibility: testCompatibility(),
    );
    await reopened.open();
    final entries = (await reopened.listOperations(partition)).entries;
    expect(entries.single.operation.requestHash, operation.requestHash);
    expect((await reopened.getCheckpoint(partition)).nextLocalSequence, 1);
    expect((await reopened.verifyIntegrity(partition)).retainedOperations, 1);
    await reopened.close();
  }, skip: !_isWeb);

  test(
    'capability probe restores a preexisting markerless record exactly',
    () async {
      const probeKey = '__capability_probe__';
      const opaqueValue = 'opaque-preexisting-probe-bytes';
      await _seedNativeRecord(databaseName, probeKey, opaqueValue);
      final repository = LocalGameJournalRepository(
        store: IndexedDbLocalGameJournalStore(databaseName: databaseName),
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      await expectLater(
        repository.open(),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.migrationFailed,
          ),
        ),
      );
      expect(await _readNativeRecord(databaseName, probeKey), opaqueValue);
    },
    skip: !_isWeb,
  );

  for (final unknownKey in ['', '\u{10ffff}/opaque']) {
    test('missing schema marker rejects and preserves boundary key '
        '${unknownKey.isEmpty ? '<empty>' : '<max-unicode>'}', () async {
      const opaqueValue = 'opaque-boundary-value';
      await _seedNativeRecord(databaseName, unknownKey, opaqueValue);
      final repository = LocalGameJournalRepository(
        store: IndexedDbLocalGameJournalStore(databaseName: databaseName),
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      await expectLater(
        repository.open(),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.migrationFailed,
          ),
        ),
      );
      expect(await _readNativeRecord(databaseName, unknownKey), opaqueValue);
    }, skip: !_isWeb);
  }

  test('non-persistent/private-mode-like factory disables capture', () async {
    final store = IndexedDbLocalGameJournalStore.withFactoryForTesting(
      factory: idbFactoryMemory,
      databaseName: databaseName,
    );
    await expectLater(
      store.open(),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.storageCapabilityUnproven,
        ),
      ),
    );
    expect(store.capability.captureEnabled, isFalse);
  }, skip: !_isWeb);

  for (final readPath in ['get', 'scan']) {
    test(
      'real IndexedDB object $readPath is typed corruption and globally latches',
      () async {
        final store = IndexedDbLocalGameJournalStore(
          databaseName: databaseName,
        );
        final repository = LocalGameJournalRepository(
          store: store,
          activeActorAccountId: 'account_1',
          compatibility: testCompatibility(),
        );
        final corruptedPartition = testPartition();
        final healthyPartition = testPartition(
          workspaceId: 'workspace_healthy',
        );
        await repository.open();
        await repository.prepareGame(testPackage(corruptedPartition));
        await repository.prepareGame(testPackage(healthyPartition));
        await repository.verifyIntegrity(corruptedPartition);
        await repository.verifyIntegrity(healthyPartition);
        final operation = testOperation(
          partition: corruptedPartition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        );
        await repository.append(operation);
        final corruptedKey = readPath == 'get'
            ? 'checkpoint/${corruptedPartition.key}'
            : 'entry/${corruptedPartition.key}/0000000000000000';
        final rawObject = <String, Object?>{'not': 'journal text'};
        await _seedNativeRecord(databaseName, corruptedKey, rawObject);

        late LocalJournalException observed;
        try {
          if (readPath == 'get') {
            await repository.getCheckpoint(corruptedPartition);
          } else {
            await repository.listOperations(corruptedPartition);
          }
          fail('object journal value was accepted');
        } on LocalJournalException catch (error) {
          observed = error;
        }
        expect(observed.code, LocalJournalErrorCode.mutatedRecord);
        expect(observed.details['observedField'], 'record_value');
        expect(observed.details['phase'], readPath);

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
        expect(await _readNativeRecord(databaseName, corruptedKey), rawObject);
        expect(
          await _readNativeRecord(
            databaseName,
            'entry/${healthyPartition.key}/0000000000000000',
          ),
          isNull,
        );
        await repository.close();
      },
      skip: !_isWeb,
    );
  }

  test(
    'real IndexedDB non-string key scan is typed and rolls back pending writes',
    () async {
      final store = IndexedDbLocalGameJournalStore(databaseName: databaseName);
      await store.open();
      await _seedNativeRecord(databaseName, 7, 'opaque');
      late LocalJournalException observed;
      try {
        await store.transaction<void>((transaction) async {
          await transaction.put('probe/pending', 'must-roll-back');
          await transaction.scanPrefix('', limit: 250);
        });
        fail('non-string IndexedDB key was accepted');
      } on LocalJournalException catch (error) {
        observed = error;
      }
      expect(observed.code, LocalJournalErrorCode.mutatedRecord);
      expect(observed.details['observedField'], 'record_key');
      expect(
        await store.transaction(
          (transaction) => transaction.get('probe/pending'),
        ),
        isNull,
      );
      await store.close();
    },
    skip: !_isWeb,
  );

  test(
    'blocked retry and close are bounded before intact deliberate reopen',
    () async {
      final memoryStore = FaultInjectingMemoryStore();
      final memoryRepository = LocalGameJournalRepository(
        store: memoryStore,
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      final partition = testPartition();
      await memoryRepository.open();
      await memoryRepository.prepareGame(testPackage(partition));
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await memoryRepository.append(operation);
      final expectedRecords = memoryStore.unsafeSnapshot();
      await memoryRepository.close();

      final blockingDatabase = await _openNativeDatabase(
        databaseName,
        version: 1,
        records: expectedRecords,
      );
      final store = IndexedDbLocalGameJournalStore(
        databaseName: databaseName,
        blockedUpgradeTimeout: const Duration(milliseconds: 200),
      );
      final repository = LocalGameJournalRepository(
        store: store,
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      try {
        final stopwatch = Stopwatch()..start();
        late LocalJournalException blocked;
        try {
          await repository.open();
          fail('blocked IndexedDB upgrade unexpectedly opened');
        } on LocalJournalException catch (error) {
          blocked = error;
        }
        stopwatch.stop();
        expect(blocked.code, LocalJournalErrorCode.storageCapabilityUnproven);
        expect(blocked.details['phase'], 'blockedUpgrade');
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(
          store.capability.availability,
          LocalCaptureAvailability.disabledCapabilityUnproven,
        );

        // Keep v1 open. The first timed-out native request remains queued, so
        // Chrome may give this retry no blocked/success/error event at all.
        final secondResult = repository.open().then<Object?>(
          (value) => value,
          onError: (Object error, StackTrace _) => error,
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final closing = repository.close();
        final settled = await Future.wait<Object?>([
          secondResult.timeout(const Duration(seconds: 2)),
          closing.timeout(const Duration(seconds: 2)).then((_) => null),
        ]);
        final secondFailure = settled.first;
        expect(secondFailure, isA<LocalJournalException>());
        final typedSecondFailure = secondFailure! as LocalJournalException;
        expect(
          typedSecondFailure.code,
          LocalJournalErrorCode.storageCapabilityUnproven,
        );
        expect(
          typedSecondFailure.details['phase'],
          anyOf('blockedUpgrade', 'openTimeout'),
        );
        expect(store.capability.captureEnabled, isFalse);

        blockingDatabase.close();
        await repository.open().timeout(const Duration(seconds: 2));
        final retainedRows = await store.transaction(
          (transaction) => transaction.scanPrefix('', limit: 250),
        );
        expect({
          for (final row in retainedRows) row.key: row.value,
        }, expectedRecords);
        final report = await repository.verifyIntegrity(partition);
        expect(report.retainedOperations, 1);
        expect(
          (await repository.listOperations(
            partition,
          )).entries.single.operation.requestHash,
          operation.requestHash,
        );
        await repository.close().timeout(const Duration(seconds: 2));

        final upgraded = await idbFactoryNative
            .open(databaseName, version: 3)
            .timeout(const Duration(seconds: 2));
        upgraded.close();
      } finally {
        blockingDatabase.close();
        await store.close().timeout(const Duration(seconds: 2));
      }
    },
    skip: !_isWeb,
  );

  test(
    'concurrent opens share one connection and version change closes it',
    () async {
      final store = IndexedDbLocalGameJournalStore(databaseName: databaseName);
      final capabilities = await Future.wait([store.open(), store.open()]);
      expect(capabilities.every((value) => value.captureEnabled), isTrue);

      final upgraded = await idbFactoryNative
          .open(databaseName, version: 3)
          .timeout(const Duration(seconds: 2));
      expect(store.capability.captureEnabled, isFalse);
      expect(
        store.capability.reasonCode,
        LocalJournalErrorCode.storageCapabilityUnproven,
      );
      upgraded.close();
      await store.close();
    },
    skip: !_isWeb,
  );

  test(
    'open during an in-flight capability probe joins the same attempt',
    () async {
      final probeEntered = Completer<void>();
      final releaseProbe = Completer<void>();
      final store = IndexedDbLocalGameJournalStore.withOpenProbeHookForTesting(
        databaseName: databaseName,
        beforeProbe: () async {
          if (!probeEntered.isCompleted) probeEntered.complete();
          await releaseProbe.future;
        },
      );
      final firstOpen = store.open();
      await probeEntered.future.timeout(const Duration(seconds: 2));
      final secondOpen = store.open();
      expect(identical(firstOpen, secondOpen), isTrue);
      var secondCompleted = false;
      unawaited(secondOpen.then((_) => secondCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);

      releaseProbe.complete();
      final capabilities = await Future.wait([firstOpen, secondOpen]);
      expect(capabilities.every((value) => value.captureEnabled), isTrue);
      await store.close();
    },
    skip: !_isWeb,
  );

  test(
    'close invalidates a blocked open and late completion cannot republish',
    () async {
      final blockingDatabase = await _openNativeDatabase(
        databaseName,
        version: 1,
        records: const {},
      );
      final store = IndexedDbLocalGameJournalStore(
        databaseName: databaseName,
        blockedUpgradeTimeout: const Duration(milliseconds: 200),
      );
      final opening = store.open();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await store.close();
      await expectLater(
        opening,
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.storageCapabilityUnproven,
          ),
        ),
      );
      blockingDatabase.close();

      final upgraded = await idbFactoryNative
          .open(databaseName, version: 3)
          .timeout(const Duration(seconds: 2));
      expect(store.capability.captureEnabled, isFalse);
      upgraded.close();
      await store.close();
    },
    skip: !_isWeb,
  );
}

final class _QuotaCallbackValue {}

Future<void> _seedNativeRecord(
  String databaseName,
  Object key,
  Object value,
) async {
  final database = await idbFactoryNative.open(
    databaseName,
    version: LocalGameJournalLimits.localSchemaVersion,
    onUpgradeNeeded: (event) {
      final database = (event.target as OpenDBRequest).result;
      if (!database.objectStoreNames.contains('journal_records')) {
        database.createObjectStore('journal_records');
      }
    },
  );
  final transaction = database.transaction('journal_records', idbModeReadWrite);
  await transaction.objectStore('journal_records').put(value, key);
  await transaction.completed;
  database.close();
}

Future<Object?> _readNativeRecord(String databaseName, Object key) async {
  final database = await idbFactoryNative.open(
    databaseName,
    version: LocalGameJournalLimits.localSchemaVersion,
  );
  final transaction = database.transaction('journal_records', idbModeReadOnly);
  final value = await transaction.objectStore('journal_records').getObject(key);
  await transaction.completed;
  database.close();
  return value;
}

Future<Database> _openNativeDatabase(
  String databaseName, {
  required int version,
  required Map<String, String> records,
}) async {
  final database = await idbFactoryNative.open(
    databaseName,
    version: version,
    onUpgradeNeeded: (event) {
      final database = (event.target as OpenDBRequest).result;
      if (!database.objectStoreNames.contains('journal_records')) {
        database.createObjectStore('journal_records');
      }
    },
  );
  final transaction = database.transaction('journal_records', idbModeReadWrite);
  final store = transaction.objectStore('journal_records');
  for (final entry in records.entries) {
    await store.put(entry.value, entry.key);
  }
  await transaction.completed;
  return database;
}
