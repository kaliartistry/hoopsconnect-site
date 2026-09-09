import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_store.dart';

/// Transactional SQLite key/value store used by native/mobile/desktop builds.
final class SqliteLocalGameJournalStore implements LocalGameJournalStore {
  static const String _table = 'journal_records';

  final String databaseName;
  final String? explicitPath;
  final Future<Directory> Function()? desktopSupportDirectoryProvider;
  final Future<void> Function(Database database)? _duringProbeForTesting;
  final Future<void> Function(Database database)? _afterProbeForTesting;
  Database? _database;
  Database? _initializingDatabase;
  LocalStorageCapability? _capability;
  Future<LocalStorageCapability>? _opening;
  Completer<void>? _openInvalidation;
  int _lifecycleGeneration = 0;

  SqliteLocalGameJournalStore({
    this.databaseName = 'hoopsconnect_local_game_journal.sqlite3',
    this.explicitPath,
    this.desktopSupportDirectoryProvider,
  }) : _duringProbeForTesting = null,
       _afterProbeForTesting = null;

  /// Uses real SQLite while allowing a native regression to constrain the
  /// opened database after the capability probe (for example SQLITE_FULL).
  SqliteLocalGameJournalStore.withOpenHookForTesting({
    required this.explicitPath,
    required Future<void> Function(Database database) afterProbe,
    this.databaseName = 'hoopsconnect_local_game_journal.sqlite3',
  }) : desktopSupportDirectoryProvider = null,
       _duringProbeForTesting = null,
       _afterProbeForTesting = afterProbe;

  /// Uses real SQLite while pausing inside the transactional capability probe.
  SqliteLocalGameJournalStore.withProbeHookForTesting({
    required this.explicitPath,
    required Future<void> Function(Database database) duringProbe,
    this.databaseName = 'hoopsconnect_local_game_journal.sqlite3',
  }) : desktopSupportDirectoryProvider = null,
       _duringProbeForTesting = duringProbe,
       _afterProbeForTesting = null;

  @override
  LocalStorageCapability get capability =>
      _capability ??
      const LocalStorageCapability(
        availability: LocalCaptureAvailability.disabledCapabilityUnproven,
        adapter: 'sqlite',
        durable: false,
        transactional: false,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
        reasonCode: LocalJournalErrorCode.storageCapabilityUnproven,
      );

  @override
  Future<LocalStorageCapability> open() {
    final pending = _opening;
    if (pending != null) return pending;
    if (_database != null) return Future.value(capability);
    final generation = _lifecycleGeneration;
    final invalidation = Completer<void>();
    late final Future<LocalStorageCapability> attempt;
    attempt = _openOnce(generation, invalidation.future).whenComplete(() {
      if (identical(_opening, attempt)) _opening = null;
      if (identical(_openInvalidation, invalidation)) {
        _openInvalidation = null;
      }
    });
    _openInvalidation = invalidation;
    _opening = attempt;
    return attempt;
  }

  Future<LocalStorageCapability> _openOnce(
    int generation,
    Future<void> invalidated,
  ) async {
    Database? openedDatabase;
    try {
      final factory = _selectFactory();
      final databasePath = await _resolveDatabasePath(factory, generation);
      _requireCurrentOpen(generation, phase: 'pathResolved');
      openedDatabase = await factory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: LocalGameJournalLimits.localSchemaVersion,
          // Each adapter owns its handle. A stale initializer must never close
          // a newer store instance's shared per-path handle during teardown.
          singleInstance: false,
          onConfigure: (database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (database, version) async {
            await database.execute(
              'CREATE TABLE IF NOT EXISTS $_table ('
              'record_key TEXT PRIMARY KEY NOT NULL, '
              'record_value TEXT NOT NULL)',
            );
          },
          onUpgrade: (database, oldVersion, newVersion) async {
            await _migrate(database, oldVersion, newVersion);
          },
        ),
      );
      _initializingDatabase = openedDatabase;
      _requireCurrentOpen(generation, phase: 'databaseOpened');
      final integrity = await openedDatabase.rawQuery('PRAGMA integrity_check');
      _requireCurrentOpen(generation, phase: 'integrityChecked');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'SQLite integrity check failed',
        );
      }
      await openedDatabase.transaction((transaction) async {
        const probeKey = '__capability_probe__';
        final priorRows = await transaction.query(
          _table,
          columns: const ['record_value'],
          where: 'record_key = ?',
          whereArgs: const [probeKey],
          limit: 1,
        );
        final priorRow = priorRows.singleOrNull;
        final priorValue = priorRow == null
            ? null
            : _SqliteTransaction._requirePersistedString(
                priorRow['record_value'],
                field: 'record_value',
                phase: 'capabilityProbe',
              );
        await transaction.insert(_table, {
          'record_key': probeKey,
          'record_value': 'probe',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (_duringProbeForTesting case final duringProbe?) {
          // The invalidation race belongs inside the transaction callback.
          // This lets sqflite roll back and release its per-path open/close
          // locks even if an asynchronous probe continuation is still held.
          await _awaitOpenHook(
            duringProbe(openedDatabase!),
            invalidated,
            generation,
            phase: 'capabilityProbe',
          );
        }
        final rows = await transaction.query(
          _table,
          where: 'record_key = ?',
          whereArgs: const [probeKey],
          limit: 1,
        );
        if (rows.singleOrNull?['record_value'] != 'probe') {
          throw LocalJournalException(
            LocalJournalErrorCode.storageCapabilityUnproven,
            'SQLite read/write capability probe failed',
          );
        }
        if (priorValue == null) {
          await transaction.delete(
            _table,
            where: 'record_key = ?',
            whereArgs: const [probeKey],
          );
        } else {
          await transaction.insert(_table, {
            'record_key': probeKey,
            'record_value': priorValue,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      _requireCurrentOpen(generation, phase: 'capabilityProven');
      if (_afterProbeForTesting case final afterProbe?) {
        await _awaitOpenHook(
          afterProbe(openedDatabase),
          invalidated,
          generation,
          phase: 'afterCapabilityProbe',
        );
      }
      _database = openedDatabase;
      _initializingDatabase = null;
      _capability = const LocalStorageCapability(
        availability: LocalCaptureAvailability.ready,
        adapter: 'sqlite',
        durable: true,
        transactional: true,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
      );
    } on LocalJournalException catch (error) {
      await _closeOwnedBestEffort(openedDatabase);
      _capability = LocalStorageCapability(
        availability: error.code == LocalJournalErrorCode.mutatedRecord
            ? LocalCaptureAvailability.disabledIntegrityFailure
            : LocalCaptureAvailability.disabledCapabilityUnproven,
        adapter: 'sqlite',
        durable: false,
        transactional: false,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
        reasonCode: error.code,
      );
      rethrow;
    } catch (error) {
      final failure = _storageFailure(
        error,
        'SQLite local journal could not be opened',
      );
      await _closeOwnedBestEffort(openedDatabase);
      _disableAfterStorageFailure(failure.code);
      throw failure;
    }
    return capability;
  }

  DatabaseFactory _selectFactory() {
    if (Platform.isAndroid || Platform.isIOS) {
      return mobile.databaseFactory;
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    throw LocalJournalException(
      LocalJournalErrorCode.storageUnavailable,
      'This native platform has no supported SQLite adapter',
      {'operatingSystem': Platform.operatingSystem},
    );
  }

  Future<String> _resolveDatabasePath(
    DatabaseFactory factory,
    int generation,
  ) async {
    if (explicitPath case final configuredPath?) {
      _requireCurrentOpen(generation, phase: 'explicitPath');
      return configuredPath;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final root = await factory.getDatabasesPath();
      _requireCurrentOpen(generation, phase: 'mobilePathResolved');
      return path.join(root, databaseName);
    }
    final supportDirectory =
        await (desktopSupportDirectoryProvider ??
            getApplicationSupportDirectory)();
    _requireCurrentOpen(generation, phase: 'supportPathResolved');
    final journalDirectory = Directory(
      path.join(supportDirectory.path, 'local_game_journal'),
    );
    await journalDirectory.create(recursive: true);
    _requireCurrentOpen(generation, phase: 'journalDirectoryCreated');
    return path.join(journalDirectory.path, databaseName);
  }

  static Future<void> _migrate(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion > newVersion ||
        newVersion > LocalGameJournalLimits.localSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'SQLite journal schema cannot be migrated by this build',
        {'oldVersion': oldVersion, 'newVersion': newVersion},
      );
    }
    // Every future step belongs here as an idempotent, restart-safe operation.
    // sqflite executes this callback inside the database upgrade transaction;
    // the version is not advanced if any step fails.
    if (oldVersion < 1 && newVersion >= 1) {
      await database.execute(
        'CREATE TABLE IF NOT EXISTS $_table ('
        'record_key TEXT PRIMARY KEY NOT NULL, '
        'record_value TEXT NOT NULL)',
      );
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) async {
    final database = _database;
    final generation = _lifecycleGeneration;
    if (database == null || !capability.captureEnabled) {
      throw LocalJournalException(
        LocalJournalErrorCode.storageCapabilityUnproven,
        'SQLite capture is disabled until storage capability is proven',
      );
    }
    try {
      return await database.transaction((transaction) async {
        _requireCurrentTransaction(database, generation);
        final result = await action(_SqliteTransaction(transaction));
        // If close raced an asynchronous callback, fail inside SQLite's
        // transaction so its writes roll back before the result is exposed.
        _requireCurrentTransaction(database, generation);
        return result;
      });
    } on LocalJournalException {
      rethrow;
    } catch (error) {
      final failure = _storageFailure(
        error,
        'SQLite journal transaction aborted',
      );
      if (failure.code == LocalJournalErrorCode.mutatedRecord ||
          failure.code == LocalJournalErrorCode.resourceExhausted) {
        _disableAfterStorageFailure(failure.code);
      }
      throw failure;
    }
  }

  @override
  Future<void> close() async {
    _lifecycleGeneration++;
    final invalidation = _openInvalidation;
    if (invalidation != null && !invalidation.isCompleted) {
      invalidation.complete();
    }
    if (identical(_openInvalidation, invalidation)) {
      _openInvalidation = null;
    }
    final database = _database;
    final initializingDatabase = _initializingDatabase;
    _database = null;
    _initializingDatabase = null;
    _capability = null;
    if (database != null) await _closeDatabaseBestEffort(database);
    if (initializingDatabase != null &&
        !identical(initializingDatabase, database)) {
      // Initialization may be suspended in a user-independent async path or
      // test probe. Do not make sign-out teardown wait on that continuation;
      // the owning open attempt also closes this exact handle when it resumes.
      unawaited(_closeDatabaseBestEffort(initializingDatabase));
    }
  }

  void _requireCurrentOpen(int generation, {required String phase}) {
    if (generation == _lifecycleGeneration) return;
    throw LocalJournalException(
      LocalJournalErrorCode.storageCapabilityUnproven,
      'SQLite open was invalidated before capability publication',
      {'phase': phase},
    );
  }

  Future<void> _awaitOpenHook(
    Future<void> hook,
    Future<void> invalidated,
    int generation, {
    required String phase,
  }) async {
    await Future.any<void>([
      hook,
      invalidated.then<void>((_) {
        _requireCurrentOpen(generation, phase: phase);
      }),
    ]);
    _requireCurrentOpen(generation, phase: phase);
  }

  void _requireCurrentTransaction(Database database, int generation) {
    if (generation == _lifecycleGeneration &&
        identical(_database, database) &&
        capability.captureEnabled) {
      return;
    }
    throw LocalJournalException(
      LocalJournalErrorCode.storageCapabilityUnproven,
      'SQLite transaction was invalidated before commit',
      const {'phase': 'transactionInvalidated'},
    );
  }

  static LocalJournalErrorCode _mapStorageError(Object error) {
    // Caller code can throw a cast error whose type name happens to contain a
    // storage-looking word (for example, "Malformed"). It is never evidence
    // about persisted bytes; adapter type violations are raised explicitly as
    // LocalJournalException.mutatedRecord before reaching this mapper.
    if (error is TypeError) {
      return LocalJournalErrorCode.transactionAborted;
    }
    if (error is DatabaseException) {
      final resultCode = error.getResultCode();
      final primaryCode = resultCode == null ? null : resultCode & 0xff;
      if (primaryCode == 11 || primaryCode == 26) {
        return LocalJournalErrorCode.mutatedRecord;
      }
      if (primaryCode == 13) {
        return LocalJournalErrorCode.resourceExhausted;
      }
      // A supplied result code is authoritative. DatabaseException.toString()
      // may include SQL arguments, which are untrusted journal bytes and must
      // never turn a LOCKED/IOERR failure into a false corruption finding.
      if (primaryCode != null) {
        return LocalJournalErrorCode.transactionAborted;
      }
    }
    final text = error.toString().toLowerCase();
    // Corruption phrases must precede generic capacity phrases: SQLite's
    // canonical corruption text is "database disk image is malformed".
    if (text.contains('corrupt') ||
        text.contains('malformed') ||
        text.contains('not a database')) {
      return LocalJournalErrorCode.mutatedRecord;
    }
    if (text.contains('database or disk is full') ||
        text.contains('disk full') ||
        text.contains('quota')) {
      return LocalJournalErrorCode.resourceExhausted;
    }
    return LocalJournalErrorCode.transactionAborted;
  }

  static LocalJournalException _storageFailure(Object error, String message) {
    final resultCode = error is DatabaseException
        ? error.getResultCode()
        : null;
    final details = <String, Object?>{
      'cause': error,
      'causeType': error.runtimeType.toString(),
      'causeText': error.toString(),
    };
    if (resultCode != null) details['sqliteResultCode'] = resultCode;
    return LocalJournalException(_mapStorageError(error), message, details);
  }

  void _disableAfterStorageFailure(LocalJournalErrorCode code) {
    final integrityFailure = code == LocalJournalErrorCode.mutatedRecord;
    _capability = LocalStorageCapability(
      availability: integrityFailure
          ? LocalCaptureAvailability.disabledIntegrityFailure
          : LocalCaptureAvailability.disabledStorageUnavailable,
      adapter: 'sqlite',
      durable: false,
      transactional: false,
      encryptedAtRestClaimed: false,
      localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
      reasonCode: code,
    );
  }

  Future<void> _closeOwnedBestEffort(Database? database) async {
    if (database == null) return;
    if (identical(_initializingDatabase, database)) {
      _initializingDatabase = null;
    }
    if (identical(_database, database)) _database = null;
    await _closeDatabaseBestEffort(database);
  }

  static Future<void> _closeDatabaseBestEffort(Database database) async {
    try {
      await database.close();
    } catch (_) {
      // Preserve the failure that caused cleanup; a corrupt handle may reject
      // close as well.
    }
  }
}

final class _SqliteTransaction implements LocalJournalStoreTransaction {
  final Transaction _transaction;

  _SqliteTransaction(this._transaction);

  @override
  Future<String?> get(String key) async {
    final rows = await _transaction.query(
      SqliteLocalGameJournalStore._table,
      columns: const ['record_value'],
      where: 'record_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    final row = rows.singleOrNull;
    if (row == null) return null;
    return _requirePersistedString(
      row['record_value'],
      field: 'record_value',
      phase: 'get',
    );
  }

  @override
  Future<void> put(String key, String value) async {
    await _transaction.insert(
      SqliteLocalGameJournalStore._table,
      {'record_key': key, 'record_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String key) async {
    await _transaction.delete(
      SqliteLocalGameJournalStore._table,
      where: 'record_key = ?',
      whereArgs: [key],
    );
  }

  @override
  Future<List<LocalKeyValue>> scanPrefix(
    String prefix, {
    String? startAfter,
    required int limit,
  }) async {
    if (limit < 1 || limit > LocalGameJournalLimits.integrityScanPageSize) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Storage scan page size is out of bounds',
      );
    }
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (startAfter != null) {
      clauses.add('record_key > ?');
      arguments.add(startAfter);
    } else if (prefix.isNotEmpty) {
      clauses.add('record_key >= ?');
      arguments.add(prefix);
    }
    if (prefix.isNotEmpty) {
      clauses.add('record_key < ?');
      arguments.add(localJournalPrefixExclusiveUpperBound(prefix));
    }
    final rows = await _transaction.query(
      SqliteLocalGameJournalStore._table,
      columns: const ['record_key', 'record_value'],
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'record_key ASC',
      limit: limit,
    );
    return List.unmodifiable(
      rows.map((row) {
        final key = _requirePersistedString(
          row['record_key'],
          field: 'record_key',
          phase: 'scan',
        );
        final value = _requirePersistedString(
          row['record_value'],
          field: 'record_value',
          phase: 'scan',
        );
        return LocalKeyValue(key, value);
      }),
    );
  }

  static String _requirePersistedString(
    Object? value, {
    required String field,
    required String phase,
  }) {
    if (value is String) return value;
    throw LocalJournalException(
      LocalJournalErrorCode.mutatedRecord,
      'SQLite journal record has a non-text storage field',
      {
        'actualType': value.runtimeType.toString(),
        'observedField': field,
        'phase': phase,
      },
    );
  }
}

extension _SingleOrNull<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
