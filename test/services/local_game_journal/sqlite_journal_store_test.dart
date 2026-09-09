import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:hoops_connect/services/local_game_journal/sqlite_journal_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'journal_test_support.dart';

void main() {
  late Directory directory;
  late String databasePath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hoops_journal_test_');
    databasePath = path.join(directory.path, 'journal.sqlite3');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'real SQLite transaction rolls back every write on callback failure',
    () async {
      final store = SqliteLocalGameJournalStore(explicitPath: databasePath);
      await store.open();
      await expectLater(
        store.transaction<void>((transaction) async {
          await transaction.put('probe/a', 'first');
          throw StateError('abort');
        }),
        throwsException,
      );
      final value = await store.transaction(
        (transaction) => transaction.get('probe/a'),
      );
      expect(value, isNull);
      await store.close();
    },
  );

  test(
    'real SQLite survives close and process-style repository reopen',
    () async {
      final partition = testPartition();
      final firstStore = SqliteLocalGameJournalStore(
        explicitPath: databasePath,
      );
      final first = LocalGameJournalRepository(
        store: firstStore,
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      final capability = await first.open();
      expect(capability.captureEnabled, isTrue);
      expect(capability.adapter, 'sqlite');
      expect(capability.encryptedAtRestClaimed, isFalse);
      await first.prepareGame(testPackage(partition));
      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      await first.append(operation);
      await first.storeServerReceipt(partition, testReceipt(operation));
      await first.close();

      final reopenedStore = SqliteLocalGameJournalStore(
        explicitPath: databasePath,
      );
      final reopened = LocalGameJournalRepository(
        store: reopenedStore,
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );
      await reopened.open();
      final page = await reopened.listOperations(partition);
      expect(page.entries.single.operation.requestHash, operation.requestHash);
      expect(page.entries.single.delivery.serverReceipt.valueOrNull, isNotNull);
      expect((await reopened.verifyIntegrity(partition)).retainedOperations, 1);
      await reopened.close();
    },
  );

  test(
    'capability probe restores a preexisting markerless record exactly',
    () async {
      const probeKey = '__capability_probe__';
      const opaqueValue = 'opaque-preexisting-probe-bytes';
      final seedStore = SqliteLocalGameJournalStore(explicitPath: databasePath);
      await seedStore.open();
      await seedStore.close();
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.insert('journal_records', {
        'record_key': probeKey,
        'record_value': opaqueValue,
      });
      await database.close();

      final repository = LocalGameJournalRepository(
        store: SqliteLocalGameJournalStore(explicitPath: databasePath),
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

      final reopened = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await reopened.query(
        'journal_records',
        columns: const ['record_value'],
        where: 'record_key = ?',
        whereArgs: const [probeKey],
      );
      expect(rows.single['record_value'], opaqueValue);
      await reopened.close();
    },
  );

  for (final unknownKey in ['', '\u{10ffff}/opaque']) {
    test('missing schema marker rejects and preserves boundary key '
        '${unknownKey.isEmpty ? '<empty>' : '<max-unicode>'}', () async {
      const opaqueValue = 'opaque-boundary-value';
      final seedStore = SqliteLocalGameJournalStore(explicitPath: databasePath);
      await seedStore.open();
      await seedStore.transaction<void>(
        (transaction) => transaction.put(unknownKey, opaqueValue),
      );
      await seedStore.close();

      final repository = LocalGameJournalRepository(
        store: SqliteLocalGameJournalStore(explicitPath: databasePath),
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

      final reopened = await databaseFactoryFfi.openDatabase(databasePath);
      final rows = await reopened.query(
        'journal_records',
        columns: const ['record_value'],
        where: 'record_key = ?',
        whereArgs: [unknownKey],
      );
      expect(rows.single['record_value'], opaqueValue);
      await reopened.close();
    });
  }

  test(
    'desktop default route uses stable application support storage',
    () async {
      final supportDirectory = Directory(
        path.join(directory.path, 'application-support'),
      );
      final store = SqliteLocalGameJournalStore(
        databaseName: 'stable-journal.sqlite3',
        desktopSupportDirectoryProvider: () async => supportDirectory,
      );
      await store.open();
      await store.transaction<void>(
        (transaction) => transaction.put('probe/stable', 'present'),
      );
      await store.close();

      final expected = File(
        path.join(
          supportDirectory.path,
          'local_game_journal',
          'stable-journal.sqlite3',
        ),
      );
      expect(await expected.exists(), isTrue);
      expect(expected.path, isNot(contains('.dart_tool')));
    },
  );

  test('close during delayed path resolution cannot publish ready', () async {
    final partition = testPartition();
    final supportDirectory = Directory(
      path.join(directory.path, 'delayed-application-support'),
    );
    const databaseName = 'delayed-journal.sqlite3';
    final resolvedPath = path.join(
      supportDirectory.path,
      'local_game_journal',
      databaseName,
    );
    final seedRepository = LocalGameJournalRepository(
      store: SqliteLocalGameJournalStore(explicitPath: resolvedPath),
      activeActorAccountId: partition.actorAccountId,
      compatibility: testCompatibility(),
    );
    await seedRepository.open();
    await seedRepository.prepareGame(testPackage(partition));
    final operation = testOperation(
      partition: partition,
      sequence: 0,
      previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
    );
    await seedRepository.append(operation);
    await seedRepository.close();
    final before = await _readRawRows(resolvedPath);

    final providerEntered = Completer<void>();
    final releaseProvider = Completer<Directory>();
    var providerCalls = 0;
    final store = SqliteLocalGameJournalStore(
      databaseName: databaseName,
      desktopSupportDirectoryProvider: () {
        providerCalls++;
        if (!providerEntered.isCompleted) providerEntered.complete();
        return releaseProvider.future;
      },
    );
    final repository = LocalGameJournalRepository(
      store: store,
      activeActorAccountId: partition.actorAccountId,
      compatibility: testCompatibility(),
    );
    final firstOpen = repository.open();
    final concurrentOpen = repository.open();
    expect(identical(firstOpen, concurrentOpen), isTrue);
    final staleResult = firstOpen.then<Object?>(
      (value) => value,
      onError: (Object error, StackTrace _) => error,
    );
    await providerEntered.future.timeout(const Duration(seconds: 2));
    expect(providerCalls, 1);
    await repository.close().timeout(const Duration(milliseconds: 250));
    expect(store.capability.captureEnabled, isFalse);
    await expectLater(
      repository.getCheckpoint(partition),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.storageCapabilityUnproven,
        ),
      ),
    );

    releaseProvider.complete(supportDirectory);
    expect(
      await staleResult.timeout(const Duration(seconds: 2)),
      isA<LocalJournalException>().having(
        (error) => error.code,
        'code',
        LocalJournalErrorCode.storageCapabilityUnproven,
      ),
    );
    expect(store.capability.captureEnabled, isFalse);

    await repository.open();
    expect((await repository.verifyIntegrity(partition)).retainedOperations, 1);
    expect(
      (await repository.listOperations(
        partition,
      )).entries.single.operation.requestHash,
      operation.requestHash,
    );
    await repository.close();
    expect(await _readRawRows(resolvedPath), before);
  });

  for (final phase in ['probe', 'afterProbe']) {
    test(
      'close during SQLite $phase cannot republish ready or change bytes',
      () async {
        final partition = testPartition();
        final seedRepository = LocalGameJournalRepository(
          store: SqliteLocalGameJournalStore(explicitPath: databasePath),
          activeActorAccountId: partition.actorAccountId,
          compatibility: testCompatibility(),
        );
        await seedRepository.open();
        await seedRepository.prepareGame(testPackage(partition));
        final operation = testOperation(
          partition: partition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        );
        await seedRepository.append(operation);
        await seedRepository.close();
        await _writeRawRow(
          databasePath,
          key: '__capability_probe__',
          value: 'preexisting-probe-value',
        );
        final before = await _readRawRows(databasePath);

        final hookEntered = Completer<void>();
        final releaseHook = Completer<void>();
        Future<void> hook(Database _) async {
          if (!hookEntered.isCompleted) hookEntered.complete();
          await releaseHook.future;
        }

        final store = phase == 'probe'
            ? SqliteLocalGameJournalStore.withProbeHookForTesting(
                explicitPath: databasePath,
                duringProbe: hook,
              )
            : SqliteLocalGameJournalStore.withOpenHookForTesting(
                explicitPath: databasePath,
                afterProbe: hook,
              );
        final repository = LocalGameJournalRepository(
          store: store,
          activeActorAccountId: partition.actorAccountId,
          compatibility: testCompatibility(),
        );
        final staleResult = repository.open().then<Object?>(
          (value) => value,
          onError: (Object error, StackTrace _) => error,
        );
        await hookEntered.future.timeout(const Duration(seconds: 2));
        await repository.close().timeout(const Duration(milliseconds: 250));
        expect(store.capability.captureEnabled, isFalse);
        expect(
          await staleResult.timeout(const Duration(seconds: 2)),
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.storageCapabilityUnproven,
          ),
        );
        expect(store.capability.captureEnabled, isFalse);

        // Keep the old external hook unresolved. Its invalidated transaction
        // must already have rolled back and released sqflite's per-path lock,
        // allowing an independently owned handle to open the same file.
        final freshRepository = LocalGameJournalRepository(
          store: SqliteLocalGameJournalStore(explicitPath: databasePath),
          activeActorAccountId: partition.actorAccountId,
          compatibility: testCompatibility(),
        );
        await freshRepository.open().timeout(const Duration(seconds: 2));
        expect(
          (await freshRepository.verifyIntegrity(partition)).retainedOperations,
          1,
        );
        expect(await _readRawRows(databasePath), before);

        releaseHook.complete();
        await Future<void>.delayed(Duration.zero);
        expect(store.capability.captureEnabled, isFalse);
        await freshRepository.close();

        await repository.open();
        expect(
          (await repository.verifyIntegrity(partition)).retainedOperations,
          1,
        );
        await repository.close();
        expect(await _readRawRows(databasePath), before);
      },
    );
  }

  test(
    'real SQLite corruption is typed as integrity failure and disables capture',
    () async {
      final partition = testPartition();
      final initialStore = SqliteLocalGameJournalStore(
        explicitPath: databasePath,
      );
      final initialRepository = LocalGameJournalRepository(
        store: initialStore,
        activeActorAccountId: partition.actorAccountId,
        compatibility: testCompatibility(),
      );
      await initialRepository.open();
      await initialRepository.prepareGame(testPackage(partition));
      await initialRepository.close();

      await File(
        databasePath,
      ).writeAsBytes(List<int>.filled(512, 0x41), flush: true);
      final corruptedStore = SqliteLocalGameJournalStore(
        explicitPath: databasePath,
      );
      final repository = LocalGameJournalRepository(
        store: corruptedStore,
        activeActorAccountId: partition.actorAccountId,
        compatibility: testCompatibility(),
      );
      late LocalJournalException failure;
      try {
        await repository.open();
        fail('corrupt SQLite database unexpectedly opened');
      } on LocalJournalException catch (error) {
        failure = error;
      }
      expect(failure.code, LocalJournalErrorCode.mutatedRecord);
      expect(failure.details['cause'], isA<DatabaseException>());
      expect(failure.details['sqliteResultCode'], isNotNull);
      expect(
        corruptedStore.capability.availability,
        LocalCaptureAvailability.disabledIntegrityFailure,
      );
      expect(corruptedStore.capability.captureEnabled, isFalse);
      await expectLater(
        repository.prepareGame(testPackage(partition)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.storageCapabilityUnproven,
          ),
        ),
      );
    },
  );

  test('real SQLite malformed B-tree page fails integrity closed', () async {
    final store = SqliteLocalGameJournalStore(explicitPath: databasePath);
    await store.open();
    await store.transaction<void>((transaction) async {
      await transaction.put('probe/malformed-page', 'durable-value');
    });
    await store.close();

    final database = await databaseFactoryFfi.openDatabase(databasePath);
    final pageSize =
        (await database.rawQuery('PRAGMA page_size')).single.values.single!
            as int;
    final rootPage =
        (await database.rawQuery(
              "SELECT rootpage FROM sqlite_master WHERE name = 'journal_records'",
            )).single['rootpage']
            as int;
    expect(rootPage, greaterThan(1));
    await database.close();

    final file = await File(databasePath).open(mode: FileMode.writeOnly);
    await file.setPosition((rootPage - 1) * pageSize);
    await file.writeByte(0);
    await file.flush();
    await file.close();

    final corruptedStore = SqliteLocalGameJournalStore(
      explicitPath: databasePath,
    );
    await expectLater(
      corruptedStore.open(),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.mutatedRecord,
        ),
      ),
    );
    expect(
      corruptedStore.capability.availability,
      LocalCaptureAvailability.disabledIntegrityFailure,
    );
  });

  test('real SQLite full database is not classified as corruption', () async {
    final store = SqliteLocalGameJournalStore.withOpenHookForTesting(
      explicitPath: databasePath,
      afterProbe: (database) async {
        final pageCountRows = await database.rawQuery('PRAGMA page_count');
        final pageCount = pageCountRows.single.values.single! as int;
        await database.rawQuery('PRAGMA max_page_count = $pageCount');
      },
    );
    LocalJournalException? failure;
    try {
      await store.open();
      await store.transaction<void>(
        (transaction) => transaction.put(
          'probe/full',
          List<String>.filled(1024 * 1024, 'x').join(),
        ),
      );
    } on LocalJournalException catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    expect(failure!.code, LocalJournalErrorCode.resourceExhausted);
    expect(failure.code, isNot(LocalJournalErrorCode.mutatedRecord));
    expect(failure.details['cause'], isA<DatabaseException>());
    expect(
      store.capability.reasonCode,
      LocalJournalErrorCode.resourceExhausted,
    );
    expect(store.capability.captureEnabled, isFalse);
    await store.close();
  });

  test(
    'authoritative non-corrupt SQLite code ignores corrupt-looking payload',
    () async {
      final store = SqliteLocalGameJournalStore(explicitPath: databasePath);
      await store.open();
      late LocalJournalException failure;
      try {
        await store.transaction<void>((_) async {
          throw _SyntheticDatabaseException(
            'database locked; args [malformed, corrupt]',
            resultCode: 5,
          );
        });
        fail('synthetic locked transaction unexpectedly completed');
      } on LocalJournalException catch (error) {
        failure = error;
      }
      expect(failure.code, LocalJournalErrorCode.transactionAborted);
      expect(failure.details['cause'], isA<DatabaseException>());
      expect(failure.details['sqliteResultCode'], 5);
      expect(store.capability.captureEnabled, isTrue);
      await store.close();
    },
  );

  test('caller TypeError remains a non-corruption transaction abort', () async {
    final store = SqliteLocalGameJournalStore(explicitPath: databasePath);
    await store.open();
    late LocalJournalException failure;
    try {
      await store.transaction<void>((_) async {
        final dynamic wrongType = _MalformedCallbackValue();
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
  });

  for (final readPath in ['get', 'scan']) {
    test(
      'real SQLite BLOB $readPath is typed corruption and globally latches',
      () async {
        late Database rawDatabase;
        final store = SqliteLocalGameJournalStore.withOpenHookForTesting(
          explicitPath: databasePath,
          afterProbe: (database) async => rawDatabase = database,
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
        final corruptedOperation = testOperation(
          partition: corruptedPartition,
          sequence: 0,
          previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
        );
        await repository.append(corruptedOperation);
        final corruptedKey = readPath == 'get'
            ? 'checkpoint/${corruptedPartition.key}'
            : 'entry/${corruptedPartition.key}/0000000000000000';
        await rawDatabase.rawUpdate(
          'UPDATE journal_records SET record_value = ? WHERE record_key = ?',
          [
            Uint8List.fromList([0, 1, 2, 3]),
            corruptedKey,
          ],
        );
        final before = await rawDatabase.query(
          'journal_records',
          orderBy: 'record_key ASC',
        );

        late LocalJournalException observed;
        try {
          if (readPath == 'get') {
            await repository.getCheckpoint(corruptedPartition);
          } else {
            await repository.listOperations(corruptedPartition);
          }
          fail('BLOB journal value was accepted');
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
        expect(
          await rawDatabase.query('journal_records', orderBy: 'record_key ASC'),
          before,
        );
        await repository.close();
      },
    );
  }

  test(
    'real SQLite BLOB key scan is typed and rolls back pending writes',
    () async {
      late Database rawDatabase;
      final store = SqliteLocalGameJournalStore.withOpenHookForTesting(
        explicitPath: databasePath,
        afterProbe: (database) async => rawDatabase = database,
      );
      await store.open();
      await rawDatabase.rawInsert(
        'INSERT INTO journal_records(record_key, record_value) VALUES(?, ?)',
        [
          Uint8List.fromList([7, 8, 9]),
          'opaque',
        ],
      );
      late LocalJournalException observed;
      try {
        await store.transaction<void>((transaction) async {
          await transaction.put('probe/pending', 'must-roll-back');
          await transaction.scanPrefix('', limit: 250);
        });
        fail('BLOB journal key was accepted');
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
  );
}

final class _MalformedCallbackValue {}

Future<Map<String, String>> _readRawRows(String databasePath) async {
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    final rows = await database.query(
      'journal_records',
      orderBy: 'record_key ASC',
    );
    return {
      for (final row in rows)
        row['record_key']! as String: row['record_value']! as String,
    };
  } finally {
    await database.close();
  }
}

Future<void> _writeRawRow(
  String databasePath, {
  required String key,
  required String value,
}) async {
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await database.insert('journal_records', {
      'record_key': key,
      'record_value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } finally {
    await database.close();
  }
}

final class _SyntheticDatabaseException extends DatabaseException {
  final int resultCode;

  _SyntheticDatabaseException(super.message, {required this.resultCode});

  @override
  int? getResultCode() => resultCode;

  @override
  Object? get result => null;
}
