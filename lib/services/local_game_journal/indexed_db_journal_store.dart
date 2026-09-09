import 'dart:async';

import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart' show idbFactoryNative;

import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_store.dart';

/// Real browser IndexedDB adapter. It never selects idb_shim's in-memory
/// fallback; lack of a durable native factory disables capture visibly.
final class IndexedDbLocalGameJournalStore implements LocalGameJournalStore {
  static const String _objectStore = 'journal_records';

  final String databaseName;
  final IdbFactory? _testingFactoryOverride;
  final void Function(Database database)? _beforeTransactionCreationForTesting;
  final void Function(Transaction transaction)?
  _beforeTransactionCompletionForTesting;
  final Future<void> Function()? _beforeOpenProbeForTesting;
  final Duration blockedUpgradeTimeout;
  Database? _database;
  LocalStorageCapability? _capability;
  StreamSubscription<VersionChangeEvent>? _versionChangeSubscription;
  Future<LocalStorageCapability>? _opening;
  int _lifecycleGeneration = 0;

  IndexedDbLocalGameJournalStore({
    this.databaseName = 'hoopsconnect_local_game_journal',
    this.blockedUpgradeTimeout = const Duration(seconds: 2),
  }) : _testingFactoryOverride = null,
       _beforeTransactionCreationForTesting = null,
       _beforeTransactionCompletionForTesting = null,
       _beforeOpenProbeForTesting = null;

  /// Allows browser tests to prove that a non-persistent factory is rejected.
  /// Production construction never accepts a fallback factory.
  IndexedDbLocalGameJournalStore.withFactoryForTesting({
    required IdbFactory factory,
    this.databaseName = 'hoopsconnect_local_game_journal_test',
    this.blockedUpgradeTimeout = const Duration(seconds: 2),
  }) : _testingFactoryOverride = factory,
       _beforeTransactionCreationForTesting = null,
       _beforeTransactionCompletionForTesting = null,
       _beforeOpenProbeForTesting = null;

  /// Allows a browser regression to close the real database immediately
  /// before transaction creation and verify that the native cause survives.
  IndexedDbLocalGameJournalStore.withTransactionCreationHookForTesting({
    required this.databaseName,
    required void Function(Database database) beforeTransactionCreation,
    this.blockedUpgradeTimeout = const Duration(seconds: 2),
  }) : _testingFactoryOverride = null,
       _beforeTransactionCreationForTesting = beforeTransactionCreation,
       _beforeTransactionCompletionForTesting = null,
       _beforeOpenProbeForTesting = null;

  /// Keeps the native IndexedDB factory while allowing a browser regression
  /// to force the real transaction-completion future down its abort path.
  IndexedDbLocalGameJournalStore.withCompletionHookForTesting({
    required this.databaseName,
    required void Function(Transaction transaction) beforeCompletion,
    this.blockedUpgradeTimeout = const Duration(seconds: 2),
  }) : _testingFactoryOverride = null,
       _beforeTransactionCreationForTesting = null,
       _beforeTransactionCompletionForTesting = beforeCompletion,
       _beforeOpenProbeForTesting = null;

  IndexedDbLocalGameJournalStore.withOpenProbeHookForTesting({
    required this.databaseName,
    required Future<void> Function() beforeProbe,
    this.blockedUpgradeTimeout = const Duration(seconds: 2),
  }) : _testingFactoryOverride = null,
       _beforeTransactionCreationForTesting = null,
       _beforeTransactionCompletionForTesting = null,
       _beforeOpenProbeForTesting = beforeProbe;

  @override
  LocalStorageCapability get capability =>
      _capability ??
      const LocalStorageCapability(
        availability: LocalCaptureAvailability.disabledCapabilityUnproven,
        adapter: 'indexeddb',
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
    late final Future<LocalStorageCapability> attempt;
    attempt = _openOnce(generation).whenComplete(() {
      if (identical(_opening, attempt)) _opening = null;
    });
    _opening = attempt;
    return attempt;
  }

  Future<LocalStorageCapability> _openOnce(int generation) async {
    try {
      final factory = _testingFactoryOverride ?? idbFactoryNative;
      if (!factory.persistent) {
        throw LocalJournalException(
          LocalJournalErrorCode.storageCapabilityUnproven,
          'Browser IndexedDB factory is not persistent',
        );
      }
      final openedDatabase = await _openDatabaseBounded(factory);
      if (generation != _lifecycleGeneration) {
        openedDatabase.close();
        throw LocalJournalException(
          LocalJournalErrorCode.storageCapabilityUnproven,
          'IndexedDB open was invalidated before capability verification',
          const {'phase': 'openInvalidated'},
        );
      }
      _database = openedDatabase;
      late final StreamSubscription<VersionChangeEvent> versionSubscription;
      versionSubscription = openedDatabase.onVersionChange.listen((_) {
        // A different tab or a newer build is requesting a schema change.
        // Close promptly so its upgrade is not blocked and invalidate this
        // adapter until the caller explicitly reopens it.
        _lifecycleGeneration++;
        openedDatabase.close();
        if (identical(_versionChangeSubscription, versionSubscription)) {
          _versionChangeSubscription = null;
          unawaited(versionSubscription.cancel());
        }
        if (identical(_database, openedDatabase)) {
          _database = null;
          _capability = const LocalStorageCapability(
            availability: LocalCaptureAvailability.disabledCapabilityUnproven,
            adapter: 'indexeddb',
            durable: false,
            transactional: false,
            encryptedAtRestClaimed: false,
            localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
            reasonCode: LocalJournalErrorCode.storageCapabilityUnproven,
          );
        }
      });
      _versionChangeSubscription = versionSubscription;
      await _beforeOpenProbeForTesting?.call();
      final transaction = _database!.transaction(
        _objectStore,
        idbModeReadWrite,
      );
      final objectStore = transaction.objectStore(_objectStore);
      const probeKey = '__capability_probe__';
      try {
        final priorKey = await objectStore.getKey(probeKey);
        final priorValue = priorKey == null
            ? null
            : await objectStore.getObject(probeKey);
        final priorText = priorKey == null
            ? null
            : _IndexedDbTransaction._requirePersistedString(
                priorValue,
                field: 'record_value',
                phase: 'capabilityProbe',
              );
        if (priorKey != null) {
          final persistedProbeKey =
              _IndexedDbTransaction._requirePersistedString(
                priorKey,
                field: 'record_key',
                phase: 'capabilityProbe',
              );
          if (persistedProbeKey != probeKey) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'IndexedDB capability probe key identity is malformed',
            );
          }
        }
        await objectStore.put('probe', probeKey);
        if (await objectStore.getObject(probeKey) != 'probe') {
          throw LocalJournalException(
            LocalJournalErrorCode.storageCapabilityUnproven,
            'IndexedDB read/write capability probe failed',
          );
        }
        if (priorKey == null) {
          await objectStore.delete(probeKey);
        } else {
          await objectStore.put(priorText!, probeKey);
        }
        await transaction.completed;
      } catch (_) {
        _abortBestEffort(transaction);
        rethrow;
      }
      if (generation != _lifecycleGeneration ||
          !identical(_database, openedDatabase)) {
        throw LocalJournalException(
          LocalJournalErrorCode.storageCapabilityUnproven,
          'IndexedDB capability verification was invalidated',
          const {'phase': 'capabilityInvalidated'},
        );
      }
      _capability = const LocalStorageCapability(
        availability: LocalCaptureAvailability.ready,
        adapter: 'indexeddb',
        durable: true,
        transactional: true,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
      );
    } on LocalJournalException catch (error) {
      await _versionChangeSubscription?.cancel();
      _versionChangeSubscription = null;
      _database?.close();
      _database = null;
      _capability = LocalStorageCapability(
        availability: error.code == LocalJournalErrorCode.mutatedRecord
            ? LocalCaptureAvailability.disabledIntegrityFailure
            : LocalCaptureAvailability.disabledCapabilityUnproven,
        adapter: 'indexeddb',
        durable: false,
        transactional: false,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
        reasonCode: error.code,
      );
      rethrow;
    } catch (error) {
      await _versionChangeSubscription?.cancel();
      _versionChangeSubscription = null;
      _database?.close();
      _database = null;
      final code = _mapStorageError(error);
      _capability = const LocalStorageCapability(
        availability: LocalCaptureAvailability.disabledStorageUnavailable,
        adapter: 'indexeddb',
        durable: false,
        transactional: false,
        encryptedAtRestClaimed: false,
        localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
        reasonCode: LocalJournalErrorCode.storageUnavailable,
      );
      throw LocalJournalException(
        code,
        'Browser IndexedDB is unavailable; local capture is disabled',
        {
          'cause': error,
          'causeType': error.runtimeType.toString(),
          'causeText': error.toString(),
          'phase': 'open',
        },
      );
    }
    return capability;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) async {
    final database = _database;
    if (database == null || !capability.captureEnabled) {
      throw LocalJournalException(
        LocalJournalErrorCode.storageCapabilityUnproven,
        'IndexedDB capture is disabled until storage capability is proven',
      );
    }
    Transaction? transaction;
    var phase = 'transactionCreation';
    try {
      _beforeTransactionCreationForTesting?.call(database);
      transaction = database.transaction(_objectStore, idbModeReadWrite);
      phase = 'callback';
      final result = await action(
        _IndexedDbTransaction(transaction.objectStore(_objectStore)),
      );
      phase = 'beforeCompletion';
      _beforeTransactionCompletionForTesting?.call(transaction);
      phase = 'completion';
      await transaction.completed;
      return result;
    } on LocalJournalException catch (error, stackTrace) {
      _abortBestEffort(transaction);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      _abortBestEffort(transaction);
      final failure = LocalJournalException(
        _mapStorageError(error),
        'IndexedDB journal transaction aborted',
        {
          'cause': error,
          'causeType': error.runtimeType.toString(),
          'causeText': error.toString(),
          'phase': phase,
        },
      );
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    _lifecycleGeneration++;
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Closing invalidates an in-flight open. Its original failure is
        // observable by the open caller; cleanup proceeds independently.
      }
    }
    await _versionChangeSubscription?.cancel();
    _versionChangeSubscription = null;
    _database?.close();
    _database = null;
    _capability = null;
  }

  static LocalJournalErrorCode _mapStorageError(Object error) {
    // A caller cast can mention Quota, Full, Security, or Unsupported in its
    // type name. That text is not storage evidence; persisted adapter type
    // violations are raised explicitly before this mapper is consulted.
    if (error is TypeError) {
      return LocalJournalErrorCode.transactionAborted;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('quota') || text.contains('full')) {
      return LocalJournalErrorCode.resourceExhausted;
    }
    if (text.contains('security') ||
        text.contains('private') ||
        text.contains('unsupported')) {
      return LocalJournalErrorCode.storageCapabilityUnproven;
    }
    return LocalJournalErrorCode.transactionAborted;
  }

  Future<Database> _openDatabaseBounded(IdbFactory factory) {
    if (blockedUpgradeTimeout <= Duration.zero) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'IndexedDB blocked-upgrade timeout must be positive',
      );
    }
    final result = Completer<Database>();
    var observedBlocked = false;
    // This is an absolute per-attempt watchdog. A retry queued behind an older
    // timed-out native request may receive no blocked/success/error event, so
    // starting a timer only from onBlocked leaves both open and close hanging.
    final attemptTimer = Timer(blockedUpgradeTimeout, () {
      if (!result.isCompleted) {
        result.completeError(
          LocalJournalException(
            LocalJournalErrorCode.storageCapabilityUnproven,
            observedBlocked
                ? 'IndexedDB schema upgrade is blocked by another open connection'
                : 'IndexedDB open attempt did not settle before its deadline',
            {'phase': observedBlocked ? 'blockedUpgrade' : 'openTimeout'},
          ),
        );
      }
    });
    late final Future<Database> nativeOpen;
    try {
      nativeOpen = factory.open(
        databaseName,
        version: LocalGameJournalLimits.localSchemaVersion,
        onUpgradeNeeded: (event) {
          final database = (event.target as OpenDBRequest).result;
          if (!database.objectStoreNames.contains(_objectStore)) {
            database.createObjectStore(_objectStore);
          }
        },
        onBlocked: (_) => observedBlocked = true,
      );
    } catch (_) {
      attemptTimer.cancel();
      rethrow;
    }
    nativeOpen.then(
      (database) {
        attemptTimer.cancel();
        if (result.isCompleted) {
          // A timed-out native request can still complete after the blocking
          // tab closes. Never publish or leak that late connection.
          database.close();
          return;
        }
        result.complete(database);
      },
      onError: (Object error, StackTrace stackTrace) {
        attemptTimer.cancel();
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
    );
    return result.future;
  }

  static void _abortBestEffort(Transaction? transaction) {
    if (transaction == null) return;
    try {
      transaction.abort();
    } catch (_) {
      // A native transaction can already be committed or aborted. Cleanup is
      // deliberately secondary and must not replace the original failure.
    }
  }
}

final class _IndexedDbTransaction implements LocalJournalStoreTransaction {
  final ObjectStore _store;

  _IndexedDbTransaction(this._store);

  @override
  Future<String?> get(String key) async {
    final value = await _store.getObject(key);
    if (value == null) {
      final persistedKey = await _store.getKey(key);
      if (persistedKey == null) return null;
      _requirePersistedString(
        persistedKey,
        field: 'record_key',
        phase: 'getPresence',
      );
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'IndexedDB journal record has a null persisted value',
        const {
          'actualType': 'Null',
          'observedField': 'record_value',
          'phase': 'get',
        },
      );
    }
    return _requirePersistedString(value, field: 'record_value', phase: 'get');
  }

  @override
  Future<void> put(String key, String value) async {
    await _store.put(value, key);
  }

  @override
  Future<void> delete(String key) => _store.delete(key);

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
    final KeyRange? range;
    if (prefix.isEmpty) {
      range = startAfter == null ? null : KeyRange.lowerBound(startAfter, true);
    } else {
      final lowerBound = startAfter ?? prefix;
      range = KeyRange.bound(
        lowerBound,
        localJournalPrefixExclusiveUpperBound(prefix),
        startAfter != null,
        true,
      );
    }
    final rows = await _store
        .openCursor(range: range, autoAdvance: true)
        .map((cursor) {
          final key = _requirePersistedString(
            cursor.key,
            field: 'record_key',
            phase: 'scan',
          );
          final value = _requirePersistedString(
            cursor.value,
            field: 'record_value',
            phase: 'scan',
          );
          return LocalKeyValue(key, value);
        })
        .take(limit)
        .toList();
    return List.unmodifiable(rows);
  }

  static String _requirePersistedString(
    Object? value, {
    required String field,
    required String phase,
  }) {
    if (value is String) return value;
    throw LocalJournalException(
      LocalJournalErrorCode.mutatedRecord,
      'IndexedDB journal record has a non-text storage field',
      {
        'actualType': value.runtimeType.toString(),
        'observedField': field,
        'phase': phase,
      },
    );
  }
}
