import 'dart:math' as math;

import '../../models/official_stats/canonical_encoding.dart';
import '../../models/official_stats/command_contract.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../models/official_stats/fact.dart';
import 'deletion_recovery_models.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_migrations.dart';
import 'journal_models.dart';
import 'journal_store.dart';
import 'journal_validation.dart';
import 'recovery_models.dart';

final class LocalJournalCompatibility {
  final Set<String> acceptedReducerVersions;
  final Set<String> acceptedCalculatorVersions;
  final Set<String> acceptedRulesProfileIds;

  LocalJournalCompatibility({
    required Set<String> acceptedReducerVersions,
    required Set<String> acceptedCalculatorVersions,
    required Set<String> acceptedRulesProfileIds,
  }) : acceptedReducerVersions = Set.unmodifiable(acceptedReducerVersions),
       acceptedCalculatorVersions = Set.unmodifiable(
         acceptedCalculatorVersions,
       ),
       acceptedRulesProfileIds = Set.unmodifiable(acceptedRulesProfileIds) {
    if (acceptedReducerVersions.isEmpty ||
        acceptedCalculatorVersions.isEmpty ||
        acceptedRulesProfileIds.isEmpty) {
      throw ArgumentError('Journal compatibility sets must not be empty');
    }
  }
}

final class LocalJournalEntry {
  final LocalGameJournalOperation operation;
  final LocalJournalDelivery delivery;

  const LocalJournalEntry({required this.operation, required this.delivery});

  Map<String, Object?> toContractMap() => {
    'delivery': delivery.toContractMap(),
    'operation': operation.toContractMap(),
  };

  factory LocalJournalEntry.fromContractMap(Map<String, Object?> map) {
    final operation = map['operation'];
    final delivery = map['delivery'];
    if (map.length != 2 ||
        operation is! Map ||
        delivery is! Map ||
        !map.containsKey('operation') ||
        !map.containsKey('delivery')) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Stored journal entry has an invalid envelope',
      );
    }
    final decoded = LocalJournalEntry(
      operation: LocalGameJournalOperation.fromContractMap(
        Map<String, Object?>.from(operation),
      ),
      delivery: LocalJournalDelivery.fromContractMap(
        Map<String, Object?>.from(delivery),
      ),
    );
    if (decoded.operation.operationId != decoded.delivery.operationId) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation and delivery IDs do not match',
      );
    }
    final receipt = decoded.delivery.serverReceipt.valueOrNull;
    if (receipt != null) {
      _validateReceipt(decoded.operation, receipt);
    }
    return decoded;
  }
}

final class LocalAppendResult {
  final LocalJournalEntry? entry;
  final OperationReceiptContract? durableReceipt;
  final bool exactReplay;
  final bool wasPruned;

  const LocalAppendResult({
    required this.entry,
    required this.durableReceipt,
    required this.exactReplay,
    required this.wasPruned,
  });

  bool get savedOnDevice => entry != null || durableReceipt != null;
}

final class LocalJournalPage {
  final List<LocalJournalEntry> entries;
  final String? nextCursor;

  LocalJournalPage({required List<LocalJournalEntry> entries, this.nextCursor})
    : entries = List.unmodifiable(entries);
}

final class LocalJournalIntegrityReport {
  final JournalPartition partition;
  final int retainedOperations;
  final int verifiedBytes;
  final String terminalRequestHash;

  const LocalJournalIntegrityReport({
    required this.partition,
    required this.retainedOperations,
    required this.verifiedBytes,
    required this.terminalRequestHash,
  });
}

final class _VerifiedWorkspaceSnapshot {
  final PreparedGameRecoveryPackage preparedPackage;
  final LocalWorkspaceCheckpoint checkpoint;
  final List<LocalJournalEntry> retainedEntries;
  final List<PrunedReceiptEvidence> prunedEvidence;

  const _VerifiedWorkspaceSnapshot({
    required this.preparedPackage,
    required this.checkpoint,
    required this.retainedEntries,
    required this.prunedEvidence,
  });
}

enum _AccountWorkspaceRecordKind {
  package('package'),
  checkpoint('checkpoint'),
  entry('entry'),
  operationIndex('operationIndex'),
  commandIndex('commandIndex'),
  receipt('receipt'),
  recoveryExport('recoveryExport');

  final String namespace;

  const _AccountWorkspaceRecordKind(this.namespace);
}

/// Bounded retry arithmetic shared by delivery scheduling and contract tests.
abstract final class LocalJournalRetryMath {
  static int cappedExponentialDelay(int retryCount) {
    LocalJournalValidation.requireSafeInteger(
      'retryCount',
      retryCount,
      minimum: 1,
    );
    var delay = LocalGameJournalLimits.retryBaseDelayMs;
    var remainingDoublings = retryCount - 1;
    while (remainingDoublings > 0 &&
        delay < LocalGameJournalLimits.retryMaximumDelayMs) {
      delay = math.min(delay * 2, LocalGameJournalLimits.retryMaximumDelayMs);
      remainingDoublings--;
    }
    return delay;
  }

  static int get maximumDoublingSteps {
    var delay = LocalGameJournalLimits.retryBaseDelayMs;
    var steps = 0;
    while (delay < LocalGameJournalLimits.retryMaximumDelayMs) {
      delay = math.min(delay * 2, LocalGameJournalLimits.retryMaximumDelayMs);
      steps++;
    }
    return steps;
  }
}

/// Account-bound, feature-neutral journal repository.
///
/// Closing or replacing this object never deletes persisted records. A caller
/// must construct a distinct account-bound repository after account switching,
/// preventing accidental disclosure across sign-out/reauthentication.
final class LocalGameJournalRepository {
  static const String _callerErrorOrigin = 'callerInput';
  final LocalGameJournalStore store;
  final String activeActorAccountId;
  final LocalJournalCompatibility compatibility;
  bool _opened = false;
  bool _integrityFailed = false;
  final Set<String> _verifiedPartitions = {};
  Future<LocalStorageCapability>? _opening;
  int _lifecycleGeneration = 0;

  LocalGameJournalRepository({
    required this.store,
    required this.activeActorAccountId,
    required this.compatibility,
  }) {
    if (!OfficialStatIdentifiers.isValid(activeActorAccountId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        'activeActorAccountId is invalid',
      );
    }
  }

  Future<LocalStorageCapability> open() {
    final pending = _opening;
    if (pending != null) return pending;
    if (_opened) {
      // Reopening an already-live repository is idempotent, not recovery
      // authority. In particular it must never clear a corruption latch while
      // the same adapter still exposes the uncorrected bytes.
      return Future.sync(() {
        _requireReady();
        return store.capability;
      });
    }
    final generation = _lifecycleGeneration;
    late final Future<LocalStorageCapability> attempt;
    attempt = _openOnce(generation).whenComplete(() {
      if (identical(_opening, attempt)) _opening = null;
    });
    _opening = attempt;
    return attempt;
  }

  Future<LocalStorageCapability> _openOnce(int generation) async {
    final capability = await store.open();
    _requireCurrentOpen(generation, phase: 'storeOpened');
    if (!capability.captureEnabled) return capability;
    try {
      await LocalJournalMigrationRunner.ensureCurrent(
        store: store,
        targetVersion: LocalGameJournalLimits.localSchemaVersion,
        steps: LocalGameJournalMigrations.steps,
      );
    } catch (error, stackTrace) {
      _opened = false;
      if (generation == _lifecycleGeneration) {
        try {
          await store.close();
        } catch (_) {
          // Cleanup is secondary; preserve the migration failure and stack.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    _requireCurrentOpen(generation, phase: 'migrationCompleted');
    _integrityFailed = false;
    _verifiedPartitions.clear();
    _opened = true;
    return capability;
  }

  Future<void> close() async {
    _lifecycleGeneration++;
    _opened = false;
    _verifiedPartitions.clear();
    await store.close();
  }

  void _requireCurrentOpen(int generation, {required String phase}) {
    if (generation == _lifecycleGeneration) return;
    throw LocalJournalException(
      LocalJournalErrorCode.storageCapabilityUnproven,
      'Repository open was invalidated before readiness publication',
      {'phase': phase},
    );
  }

  Future<LocalWorkspaceCheckpoint> prepareGame(
    PreparedGameRecoveryPackage package,
  ) async {
    _requireReady();
    _requirePartitionAccess(package.partition);
    _requireCompatiblePackage(package);
    return _guardedTransaction(
      partition: package.partition,
      action: (transaction) async {
        final packageKey = _packageKey(package.partition);
        final existingPackageValue = await transaction.get(packageKey);
        if (existingPackageValue != null) {
          final existing = PreparedGameRecoveryPackage.fromContractMap(
            LocalJournalRecordCodec.decode(existingPackageValue),
          );
          if (existing.packageChecksum != package.packageChecksum) {
            throw LocalJournalException(
              LocalJournalErrorCode.payloadKeyConflict,
              'A different prepared package already exists for this workspace',
            );
          }
          final snapshot = await _requireVerifiedWorkspaceSnapshot(
            transaction,
            package.partition,
          );
          await _requireExactWorkspaceIndexForPackage(transaction, existing);
          return snapshot.checkpoint;
        }

        await _requireWorkspaceEmptyForPreparation(transaction, package);
        final checkpointKey = _checkpointKey(package.partition);
        final checkpoint = _copyCheckpoint(
          LocalWorkspaceCheckpoint.empty(
            partition: package.partition,
            writerEpoch: package.writerEpoch,
            now: package.preparedAt,
          ),
          preparationPackageChecksum: Fact.known(package.packageChecksum),
          updatedAt: package.preparedAt,
        );

        // Package and checkpoint commit atomically. No server record is fetched
        // or created by this method.
        await transaction.put(
          packageKey,
          LocalJournalRecordCodec.encode(package.toContractMap()),
        );
        await transaction.put(
          checkpointKey,
          LocalJournalRecordCodec.encode(checkpoint.toContractMap()),
        );
        await transaction.put(
          _workspaceIndexKey(package),
          LocalJournalRecordCodec.encode({
            'deviceSessionId': package.deviceSessionId,
            'packageChecksum': package.packageChecksum,
            'partition': package.partition.toContractMap(),
          }),
        );
        return LocalWorkspaceCheckpoint.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(checkpoint.toContractMap()),
          ),
        );
      },
    );
  }

  Future<LocalAppendResult> append(
    LocalGameJournalOperation incomingOperation, {
    DateTime? committedAt,
  }) async {
    _requireReady();
    // Normalize through the persisted decoder before any verification or
    // transaction. Caller-created values that Packet 07 cannot decode must
    // fail without writes and without being mistaken for stored corruption.
    final operation = LocalGameJournalOperation.fromContractMap(
      LocalJournalRecordCodec.decode(
        LocalJournalRecordCodec.encode(incomingOperation.toContractMap()),
      ),
    );
    _requirePartitionAccess(operation.partition);
    _requireCompatibleOperation(operation);
    if (!_verifiedPartitions.contains(operation.partition.key)) {
      await verifyIntegrity(operation.partition);
    }
    return _guardedTransaction(
      partition: operation.partition,
      missingRecordIsIntegrityFailure: true,
      action: (transaction) async {
        final checkpoint = await _requireCheckpoint(
          transaction,
          operation.partition,
        );
        final package = await _requirePackage(transaction, operation.partition);
        if (checkpoint.preparationPackageChecksum.valueOrNull !=
            package.packageChecksum) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Checkpoint does not bind the prepared package checksum',
          );
        }
        if (operation.deviceSessionId != package.deviceSessionId ||
            operation.writerEpoch != package.writerEpoch ||
            operation.writerEpoch != checkpoint.writerEpoch) {
          throw LocalJournalException(
            LocalJournalErrorCode.writerEpochConflict,
            'Operation does not match the prepared writer session',
          );
        }
        if (operation.reducerVersion != package.journalReducerVersion ||
            operation.rulesProfileId != package.rulesProfileId ||
            operation.operationSchemaVersion !=
                package.operationSchemaVersion) {
          throw LocalJournalException(
            LocalJournalErrorCode.unsupportedSchemaVersion,
            'Operation versions do not match the prepared package',
          );
        }

        final operationIndex = await _readIndex(
          transaction,
          _operationIndexKey(operation.partition, operation.operationId),
        );
        final commandIndex = await _readIndex(
          transaction,
          _commandIndexKey(operation.partition, operation.commandId),
        );
        if (operationIndex != null || commandIndex != null) {
          return _resolveExactReplay(
            transaction,
            operation,
            operationIndex,
            commandIndex,
          );
        }
        _requireCompatiblePackage(package);
        if (checkpoint.recoveryState != LocalWorkspaceRecoveryState.active) {
          throw LocalJournalException(
            LocalJournalErrorCode.writerEpochConflict,
            'Capture is paused on a preserved conflict branch',
          );
        }
        if (checkpoint.submissionState !=
            WorkspaceSubmissionState.captureOpen) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'New operations require an open capture workspace',
          );
        }

        final expectedPrevious = checkpoint.lastOperationHash;
        if (checkpoint.retainedOperationCount > 0) {
          final headSequence = checkpoint.lastLocalSequence.valueOrNull;
          if (headSequence == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Nonempty checkpoint is missing its local head sequence',
            );
          }
          final head = await _requireEntryBySequence(
            transaction,
            operation.partition,
            headSequence,
          );
          if (head.operation.requestHash != expectedPrevious.valueOrNull) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Persisted head operation does not match the checkpoint',
            );
          }
          _validateIndex(
            head.operation,
            _entryKey(operation.partition, headSequence),
            await _readIndex(
              transaction,
              _operationIndexKey(
                operation.partition,
                head.operation.operationId,
              ),
            ),
          );
        }
        if (operation.localSequence != checkpoint.nextLocalSequence) {
          await _requireVerifiedWorkspaceSnapshot(
            transaction,
            operation.partition,
          );
          throw LocalJournalException(
            operation.localSequence > checkpoint.nextLocalSequence
                ? LocalJournalErrorCode.sequenceGap
                : LocalJournalErrorCode.sequenceConflict,
            'Operation local sequence is not the next contiguous sequence',
            {
              'expected': checkpoint.nextLocalSequence,
              'actual': operation.localSequence,
              'errorOrigin': _callerErrorOrigin,
            },
          );
        }
        if (!_sameStringFact(
          operation.previousOperationHash,
          expectedPrevious,
        )) {
          await _requireVerifiedWorkspaceSnapshot(
            transaction,
            operation.partition,
          );
          throw LocalJournalException(
            LocalJournalErrorCode.hashMismatch,
            'Operation previous hash does not match the workspace head',
            const {'errorOrigin': _callerErrorOrigin},
          );
        }
        for (final referenceField in const [
          'amendsOperationId',
          'reversesOperationId',
        ]) {
          final referenceId = operation.payload[referenceField];
          if (referenceId == null) continue;
          final referencedSequence = await _validatedReferenceSequence(
            transaction,
            partition: operation.partition,
            referenceId: referenceId as String,
            preparedPackage: package,
            checkpoint: checkpoint,
          );
          if (referencedSequence == null ||
              referencedSequence >= operation.localSequence) {
            throw LocalJournalException(
              LocalJournalErrorCode.operationNotFound,
              '$referenceField must identify an earlier operation in this workspace',
              const {'errorOrigin': _callerErrorOrigin},
            );
          }
        }
        if (checkpoint.nextLocalSequence >=
            LocalGameJournalLimits.maxOperationsPerWorkspace) {
          throw LocalJournalException(
            LocalJournalErrorCode.resourceExhausted,
            'Workspace lifetime operation limit reached',
          );
        }
        final nextBytes =
            checkpoint.retainedOperationBytes + operation.byteCount;
        if (nextBytes > LocalGameJournalLimits.maxWorkspaceBytes) {
          throw LocalJournalException(
            LocalJournalErrorCode.resourceExhausted,
            'Workspace journal size limit reached',
          );
        }

        final delivery = LocalJournalDelivery.savedOnDevice(
          operation.operationId,
        );
        final entry = LocalJournalEntry(
          operation: operation,
          delivery: delivery,
        );
        final entryKey = _entryKey(
          operation.partition,
          operation.localSequence,
        );
        final index = _indexPayload(
          operation: operation,
          entryKey: entryKey,
          pruned: false,
        );
        final now = committedAt ?? operation.clientObservedAt;
        final updatedCheckpoint = _copyCheckpoint(
          checkpoint,
          nextLocalSequence: operation.localSequence + 1,
          lastLocalSequence: Fact.known(operation.localSequence),
          lastOperationHash: Fact.known(operation.requestHash),
          retainedOperationCount: checkpoint.retainedOperationCount + 1,
          retainedOperationBytes: nextBytes,
          updatedAt: now,
        );

        // This write order is deliberate: operation first, checkpoint second.
        // The adapter's transaction must commit both or neither before return.
        await transaction.put(
          entryKey,
          LocalJournalRecordCodec.encode(entry.toContractMap()),
        );
        await transaction.put(
          _operationIndexKey(operation.partition, operation.operationId),
          LocalJournalRecordCodec.encode(index),
        );
        await transaction.put(
          _commandIndexKey(operation.partition, operation.commandId),
          LocalJournalRecordCodec.encode(index),
        );
        await transaction.put(
          _checkpointKey(operation.partition),
          LocalJournalRecordCodec.encode(updatedCheckpoint.toContractMap()),
        );

        return LocalAppendResult(
          entry: _cloneEntry(entry),
          durableReceipt: null,
          exactReplay: false,
          wasPruned: false,
        );
      },
    );
  }

  Future<LocalJournalEntry> queue(
    JournalPartition partition,
    String operationId,
  ) => _updateDelivery(partition, operationId, (entry) {
    if (entry.delivery.state != JournalDeliveryState.savedOnDevice) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidStateTransition,
        'Only saved-on-device operations can enter the queue directly',
      );
    }
    return LocalJournalDelivery(
      operationId: operationId,
      state: JournalDeliveryState.queued,
      retryCount: entry.delivery.retryCount,
      nextAttemptAt: const Fact.notApplicable(reasonCode: 'ready_now'),
      lastErrorCode: const Fact.notApplicable(reasonCode: 'no_error'),
      pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
      serverReceipt: entry.delivery.serverReceipt,
      retryPolicy: entry.delivery.retryPolicy,
    );
  });

  Future<LocalJournalEntry> markSending(
    JournalPartition partition,
    String operationId,
  ) => _updateDelivery(partition, operationId, (entry) {
    if (entry.delivery.state != JournalDeliveryState.queued) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidStateTransition,
        'Only a queued operation can be marked sending',
      );
    }
    return LocalJournalDelivery(
      operationId: operationId,
      state: JournalDeliveryState.sending,
      retryCount: entry.delivery.retryCount,
      nextAttemptAt: const Fact.notApplicable(reasonCode: 'in_flight'),
      lastErrorCode: entry.delivery.lastErrorCode,
      pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
      serverReceipt: const Fact.unknown(reasonCode: 'response_pending'),
      retryPolicy: entry.delivery.retryPolicy,
    );
  });

  Future<LocalJournalEntry> recordDeliveryFailure(
    JournalPartition partition,
    String operationId,
    CommandErrorCode errorCode, {
    required DateTime observedAt,
  }) => _updateDelivery(
    partition,
    operationId,
    (entry) {
      if (entry.delivery.state == JournalDeliveryState.accepted) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidStateTransition,
          'An accepted operation cannot be returned to retry state',
        );
      }
      final policy = OfficialStatCommandErrors.policies[errorCode]!;
      final nextRetryCount =
          entry.delivery.retryCount >= LocalGameJournalLimits.maxSafeInteger
          ? LocalGameJournalLimits.maxSafeInteger
          : entry.delivery.retryCount + 1;
      if (policy.retry == RetryClassification.retrySameCommand) {
        final jitter = _jitterBasisPoints(
          entry.operation.commandId,
          nextRetryCount,
        );
        final exponential = LocalJournalRetryMath.cappedExponentialDelay(
          nextRetryCount,
        );
        final delay = math.min(
          LocalGameJournalLimits.retryMaximumDelayMs,
          (exponential * jitter) ~/ 10000,
        );
        return LocalJournalDelivery(
          operationId: operationId,
          state: JournalDeliveryState.queued,
          retryCount: nextRetryCount,
          nextAttemptAt: Fact.known(
            observedAt.toUtc().add(Duration(milliseconds: delay)),
          ),
          lastErrorCode: Fact.known(errorCode.name),
          pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
          serverReceipt: entry.delivery.serverReceipt,
          retryPolicy: RetryPolicyMetadata(jitterBasisPoints: jitter),
        );
      }
      return LocalJournalDelivery(
        operationId: operationId,
        state: JournalDeliveryState.needsAttention,
        retryCount: nextRetryCount,
        nextAttemptAt: const Fact.notApplicable(reasonCode: 'queue_paused'),
        lastErrorCode: Fact.known(errorCode.name),
        pauseReason: Fact.known(_pauseReason(errorCode).name),
        serverReceipt: entry.delivery.serverReceipt,
        retryPolicy: entry.delivery.retryPolicy,
      );
    },
    markConflictBranch: _isConflictBranchError(errorCode),
    observedAt: observedAt,
  );

  Future<LocalJournalEntry> resumePaused(
    JournalPartition partition,
    String operationId,
  ) => _updateDelivery(partition, operationId, (entry) {
    if (entry.delivery.state != JournalDeliveryState.needsAttention) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidStateTransition,
        'Only a paused operation can be resumed',
      );
    }
    return LocalJournalDelivery(
      operationId: operationId,
      state: JournalDeliveryState.queued,
      retryCount: entry.delivery.retryCount,
      nextAttemptAt: const Fact.notApplicable(reasonCode: 'ready_now'),
      lastErrorCode: entry.delivery.lastErrorCode,
      pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
      serverReceipt: entry.delivery.serverReceipt,
      retryPolicy: entry.delivery.retryPolicy,
    );
  });

  Future<LocalJournalEntry> storeServerReceipt(
    JournalPartition partition,
    OperationReceiptContract receipt,
  ) async {
    _requireReady();
    _requirePartitionAccess(partition);
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        // Receipt advancement can cross multiple already-accepted entries.
        // Verify the whole workspace before the first write so a cached caller
        // cannot amplify forged out-of-order delivery evidence.
        await _requireVerifiedWorkspaceSnapshot(transaction, partition);
        final entry = await _requireEntryByOperationId(
          transaction,
          partition,
          receipt.operationId,
        );
        try {
          _validateReceipt(entry.operation, receipt);
        } on LocalJournalException catch (error) {
          throw LocalJournalException(error.code, error.message, {
            ...error.details,
            'errorOrigin': _callerErrorOrigin,
          });
        }
        final priorReceipt = entry.delivery.serverReceipt.valueOrNull;
        if (priorReceipt != null) {
          if (OfficialStatCanonicalEncoding.encode(
                operationReceiptToMap(priorReceipt),
              ) !=
              OfficialStatCanonicalEncoding.encode(
                operationReceiptToMap(receipt),
              )) {
            throw LocalJournalException(
              LocalJournalErrorCode.receiptMismatch,
              'A different receipt is already stored for this operation',
              const {'errorOrigin': _callerErrorOrigin},
            );
          }
          return _cloneEntry(entry);
        }
        final delivery = LocalJournalDelivery(
          operationId: receipt.operationId,
          state: JournalDeliveryState.accepted,
          retryCount: entry.delivery.retryCount,
          nextAttemptAt: const Fact.notApplicable(reasonCode: 'accepted'),
          lastErrorCode: const Fact.notApplicable(reasonCode: 'accepted'),
          pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
          serverReceipt: Fact.known(receipt),
          retryPolicy: entry.delivery.retryPolicy,
        );
        final accepted = LocalJournalEntry(
          operation: entry.operation,
          delivery: delivery,
        );
        final receiptKey = _receiptKey(partition, receipt.operationId);

        // The receipt tombstone and accepted delivery state are one durable
        // transaction; pruning cannot proceed without this independent receipt.
        await transaction.put(
          receiptKey,
          LocalJournalRecordCodec.encode(operationReceiptToMap(receipt)),
        );
        await transaction.put(
          _entryKey(partition, entry.operation.localSequence),
          LocalJournalRecordCodec.encode(accepted.toContractMap()),
        );

        var checkpoint = await _requireCheckpoint(transaction, partition);
        final contiguous = await _contiguousAcceptedThrough(
          transaction,
          partition,
          checkpoint,
        );
        if (contiguous != null) {
          final contiguousEntry = await _requireEntryBySequence(
            transaction,
            partition,
            contiguous,
          );
          final contiguousReceipt =
              contiguousEntry.delivery.serverReceipt.valueOrNull!;
          checkpoint = _copyCheckpoint(
            checkpoint,
            acceptedThroughSequence: Fact.known(contiguous),
            acceptedJournalHead: Fact.known(
              contiguousReceipt.acceptedJournalHead,
            ),
            acceptedJournalHash: Fact.known(
              contiguousReceipt.acceptedJournalHash,
            ),
            updatedAt: receipt.acceptedAt,
          );
          await transaction.put(
            _checkpointKey(partition),
            LocalJournalRecordCodec.encode(checkpoint.toContractMap()),
          );
        }
        return _cloneEntry(accepted);
      },
    );
  }

  Future<LocalJournalPage> listOperations(
    JournalPartition partition, {
    int pageSize = LocalGameJournalLimits.defaultPageSize,
    String? cursor,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    if (pageSize < 1 || pageSize > LocalGameJournalLimits.maxPageSize) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Journal page size must be 1-${LocalGameJournalLimits.maxPageSize}',
      );
    }
    final prefix = _entryPrefix(partition);
    if (cursor != null && !cursor.startsWith(prefix)) {
      throw LocalJournalException(
        LocalJournalErrorCode.scopeMismatch,
        'Pagination cursor belongs to another workspace',
      );
    }
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final rows = await transaction.scanPrefix(
          prefix,
          startAfter: cursor,
          limit: pageSize + 1,
        );
        final hasMore = rows.length > pageSize;
        final pageRows = hasMore ? rows.sublist(0, pageSize) : rows;
        final entries = pageRows.map(_decodeEntryRow).toList(growable: false);
        for (var index = 0; index < entries.length; index++) {
          final row = pageRows[index];
          final entry = entries[index];
          _requireSamePartition(partition, entry.operation.partition);
          if (row.key != _entryKey(partition, entry.operation.localSequence)) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Listed journal operation does not bind its storage key',
            );
          }
          final operationIndexKey = _operationIndexKey(
            partition,
            entry.operation.operationId,
          );
          final operationIndex = await _readIndex(
            transaction,
            operationIndexKey,
          );
          if (operationIndex == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Listed journal operation is missing its operation index',
            );
          }
          _validateIndex(entry.operation, row.key, operationIndex);
          await _requireValidPersistedIndexBinding(
            transaction,
            partition,
            operationIndex,
            observedKey: operationIndexKey,
            observedAsOperationIndex: true,
          );
        }
        return LocalJournalPage(
          entries: entries.map(_cloneEntry).toList(growable: false),
          nextCursor: hasMore ? pageRows.last.key : null,
        );
      },
    );
  }

  /// Foreground/resume primitive only. Packet 07 performs no network work and
  /// makes no background-delivery claim after a PWA is closed.
  Future<List<LocalJournalEntry>> enumerateForegroundReady(
    JournalPartition partition, {
    required DateTime now,
  }) async {
    final checkpoint = await getCheckpoint(partition);
    if (checkpoint.recoveryState != LocalWorkspaceRecoveryState.active) {
      throw LocalJournalException(
        LocalJournalErrorCode.writerEpochConflict,
        'Delivery is paused on a preserved conflict branch',
      );
    }
    final result = <LocalJournalEntry>[];
    String? cursor;
    var bytes = 0;
    do {
      final page = await listOperations(
        partition,
        pageSize: LocalGameJournalLimits.maxPageSize,
        cursor: cursor,
      );
      for (final entry in page.entries) {
        final delivery = entry.delivery;
        final readyAt = delivery.nextAttemptAt.valueOrNull;
        final ready =
            delivery.state == JournalDeliveryState.savedOnDevice ||
            (delivery.state == JournalDeliveryState.queued &&
                (readyAt == null || !readyAt.isAfter(now)));
        if (!ready) continue;
        if (result.length >=
                LocalGameJournalLimits.futureServerBatchMaxOperations ||
            bytes + entry.operation.byteCount >
                LocalGameJournalLimits.futureServerBatchMaxBytes) {
          return List.unmodifiable(result);
        }
        result.add(entry);
        bytes += entry.operation.byteCount;
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(result);
  }

  Future<LocalWorkspaceCheckpoint> getCheckpoint(
    JournalPartition partition,
  ) async {
    _requireReady();
    _requirePartitionAccess(partition);
    return _guardedTransaction(
      partition: partition,
      action: (transaction) => _requireCheckpoint(transaction, partition),
    );
  }

  Future<LocalWorkspaceCheckpoint> setSubmissionState(
    JournalPartition partition,
    WorkspaceSubmissionState state, {
    required DateTime observedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        if (snapshot.preparedPackage.candidateRevision != null &&
            snapshot.checkpoint.submissionState != state) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Candidate revision workspaces require revision-bound submission evidence',
          );
        }
        final checkpoint = snapshot.checkpoint;
        final valid =
            checkpoint.submissionState == state ||
            (checkpoint.submissionState ==
                    WorkspaceSubmissionState.captureOpen &&
                state == WorkspaceSubmissionState.submissionQueued) ||
            (checkpoint.submissionState ==
                    WorkspaceSubmissionState.submissionQueued &&
                state == WorkspaceSubmissionState.submitted);
        if (!valid) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Workspace submission state transition is not allowed',
          );
        }
        if (state == WorkspaceSubmissionState.submitted &&
            (checkpoint.acceptedThroughSequence.valueOrNull !=
                    checkpoint.lastLocalSequence.valueOrNull ||
                checkpoint.recoveryState !=
                    LocalWorkspaceRecoveryState.active)) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Workspace cannot be submitted with unacknowledged operations',
          );
        }
        final updated = _copyCheckpoint(
          checkpoint,
          submissionState: state,
          updatedAt: observedAt,
        );
        await transaction.put(
          _checkpointKey(partition),
          LocalJournalRecordCodec.encode(updated.toContractMap()),
        );
        return LocalWorkspaceCheckpoint.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(updated.toContractMap()),
          ),
        );
      },
    );
  }

  /// Atomically seals the journal and records which exact candidate revision
  /// the immutable operation prefix represents.
  Future<LocalWorkspaceCheckpoint> queueCandidateRevisionSubmission(
    JournalPartition partition,
    LocalCandidateRevisionIdentity revision, {
    required DateTime observedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        final checkpoint = snapshot.checkpoint;
        final preparedRevision = snapshot.preparedPackage.candidateRevision;
        final lastSequence = checkpoint.lastLocalSequence.valueOrNull;
        final lastHash = checkpoint.lastOperationHash.valueOrNull;
        if (preparedRevision == null ||
            !preparedRevision.hasSameIdentity(revision) ||
            checkpoint.submissionState !=
                WorkspaceSubmissionState.captureOpen ||
            checkpoint.candidateRevisionSubmissionEvidence != null ||
            lastSequence == null ||
            lastHash == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Candidate submission requires the exact prepared revision and a nonempty open journal',
          );
        }
        final evidence = LocalCandidateRevisionSubmissionEvidence.queued(
          revision: revision,
          preparationPackageChecksum: snapshot.preparedPackage.packageChecksum,
          submittedThroughSequence: lastSequence,
          submittedThroughHash: lastHash,
          observedAt: observedAt,
        );
        final updated = _copyCheckpoint(
          checkpoint,
          submissionState: WorkspaceSubmissionState.submissionQueued,
          candidateRevisionSubmissionEvidence: evidence,
          updatedAt: observedAt,
        );
        await transaction.put(
          _checkpointKey(partition),
          LocalJournalRecordCodec.encode(updated.toContractMap()),
        );
        return LocalWorkspaceCheckpoint.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(updated.toContractMap()),
          ),
        );
      },
    );
  }

  /// Atomically turns queued revision evidence into durable accepted evidence.
  Future<LocalWorkspaceCheckpoint> finalizeCandidateRevisionSubmission(
    JournalPartition partition, {
    required DateTime observedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        final checkpoint = snapshot.checkpoint;
        final evidence = checkpoint.candidateRevisionSubmissionEvidence;
        final acceptedSequence = checkpoint.acceptedThroughSequence.valueOrNull;
        final acceptedHead = checkpoint.acceptedJournalHead.valueOrNull;
        final acceptedHash = checkpoint.acceptedJournalHash.valueOrNull;
        if (checkpoint.submissionState !=
                WorkspaceSubmissionState.submissionQueued ||
            evidence == null ||
            evidence.state != WorkspaceSubmissionState.submissionQueued ||
            snapshot.preparedPackage.candidateRevision == null ||
            !snapshot.preparedPackage.candidateRevision!.hasSameIdentity(
              evidence.revision,
            ) ||
            acceptedSequence != evidence.submittedThroughSequence ||
            acceptedSequence != checkpoint.lastLocalSequence.valueOrNull ||
            acceptedHead == null ||
            acceptedHash == null ||
            checkpoint.recoveryState != LocalWorkspaceRecoveryState.active) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Candidate revision cannot be finalized without exact contiguous receipt evidence',
          );
        }
        final acceptedEvidence = evidence.accepted(
          acceptedThroughSequence: acceptedSequence!,
          acceptedJournalHead: acceptedHead,
          acceptedJournalHash: acceptedHash,
          observedAt: observedAt,
        );
        final updated = _copyCheckpoint(
          checkpoint,
          submissionState: WorkspaceSubmissionState.submitted,
          candidateRevisionSubmissionEvidence: acceptedEvidence,
          updatedAt: observedAt,
        );
        await transaction.put(
          _checkpointKey(partition),
          LocalJournalRecordCodec.encode(updated.toContractMap()),
        );
        return LocalWorkspaceCheckpoint.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(updated.toContractMap()),
          ),
        );
      },
    );
  }

  Future<LocalJournalIntegrityReport> verifyIntegrity(
    JournalPartition partition,
  ) async {
    _requireReady();
    _requirePartitionAccess(partition);
    final snapshot = await _guardedTransaction(
      partition: partition,
      action: (transaction) =>
          _requireVerifiedWorkspaceSnapshot(transaction, partition),
    );
    _verifiedPartitions.add(partition.key);
    return LocalJournalIntegrityReport(
      partition: partition,
      retainedOperations: snapshot.retainedEntries.length,
      verifiedBytes: snapshot.checkpoint.retainedOperationBytes,
      terminalRequestHash:
          snapshot.checkpoint.lastOperationHash.valueOrNull ??
          List.filled(64, '0').join(),
    );
  }

  Future<DeviceJournalDeletionManifest> createDeletionRecoveryManifest({
    required String manifestId,
    required String deviceSessionId,
    required DateTime createdAt,
  }) async {
    _requireReady();
    if (!OfficialStatIdentifiers.isValid(manifestId) ||
        !OfficialStatIdentifiers.isValid(deviceSessionId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        'Deletion manifest and device IDs must be opaque IDs',
      );
    }
    return _guardedTransaction(
      action: (transaction) async {
        final snapshots = await _requireDeviceWorkspaceInventory(
          transaction,
          deviceSessionId,
        );
        final summaries = snapshots
            .map(_workspaceSummary)
            .toList(growable: false);
        final manifest = DeviceJournalDeletionManifest.create(
          manifestId: manifestId,
          actorAccountId: activeActorAccountId,
          deviceSessionId: deviceSessionId,
          createdAt: createdAt,
          workspaces: summaries,
        );
        await transaction.put(
          _deletionManifestKey(
            activeActorAccountId,
            deviceSessionId,
            manifestId,
          ),
          LocalJournalRecordCodec.encode(manifest.toContractMap()),
        );
        return DeviceJournalDeletionManifest.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(manifest.toContractMap()),
          ),
        );
      },
    );
  }

  Future<List<LocalReconciliationIdentity>> enumerateDeletionReconciliation(
    LocalDeletionConsent consent,
  ) async {
    _requireReady();
    return _guardedTransaction(
      action: (transaction) async {
        final value = await transaction.get(
          _deletionManifestKey(
            activeActorAccountId,
            consent.deviceSessionId,
            consent.manifestId,
          ),
        );
        if (value == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.operationNotFound,
            'The consented device manifest was not found',
          );
        }
        final manifestRecord = LocalJournalRecordCodec.decode(value);
        final manifestVersion = manifestRecord['manifestVersion'];
        if (manifestVersion == 1) {
          try {
            requireLegacyDeletionManifestForReconsent(manifestRecord);
          } on LocalJournalException catch (error) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Legacy deletion manifest is malformed',
              {'cause': error, 'causeCode': error.code.name},
            );
          }
          throw LocalJournalException(
            LocalJournalErrorCode.consentRequired,
            'Legacy deletion manifest must be recreated with fresh consent',
          );
        }
        if (manifestVersion is int &&
            manifestVersion > LocalGameJournalLimits.deletionManifestVersion) {
          throw LocalJournalException(
            LocalJournalErrorCode.unsupportedSchemaVersion,
            'Deletion manifest version is newer than this journal reader',
          );
        }
        if (manifestVersion != LocalGameJournalLimits.deletionManifestVersion) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Persisted deletion manifest version is malformed',
          );
        }
        late DeviceJournalDeletionManifest manifest;
        try {
          manifest = DeviceJournalDeletionManifest.fromContractMap(
            manifestRecord,
          );
        } on LocalJournalException catch (error) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Persisted deletion manifest is malformed',
            {'cause': error, 'causeCode': error.code.name},
          );
        }
        if (manifest.actorAccountId != activeActorAccountId ||
            manifest.manifestId != consent.manifestId ||
            manifest.deviceSessionId != consent.deviceSessionId ||
            manifest.checksum != consent.manifestChecksum ||
            consent.grantedAt.isBefore(manifest.createdAt)) {
          throw LocalJournalException(
            LocalJournalErrorCode.consentRequired,
            'Consent is not bound to this exact account/device manifest',
          );
        }
        late List<_VerifiedWorkspaceSnapshot> snapshots;
        try {
          snapshots = await _requireDeviceWorkspaceInventory(
            transaction,
            consent.deviceSessionId,
          );
        } on LocalJournalException catch (error, stackTrace) {
          _observePersistedFailure(error, partition: null);
          Error.throwWithStackTrace(
            LocalJournalException(
              LocalJournalErrorCode.manifestMismatch,
              'Canonical workspace inventory no longer matches the consented manifest',
              {'cause': error, 'causeCode': error.code.name},
            ),
            stackTrace,
          );
        }
        final currentSummaries = snapshots
            .map(_workspaceSummary)
            .toList(growable: false);
        if (currentSummaries.length != manifest.workspaces.length) {
          throw LocalJournalException(
            LocalJournalErrorCode.manifestMismatch,
            'The prepared workspace set changed after deletion consent',
          );
        }
        for (var index = 0; index < currentSummaries.length; index++) {
          if (OfficialStatCanonicalEncoding.encode(
                currentSummaries[index].toContractMap(),
              ) !=
              OfficialStatCanonicalEncoding.encode(
                manifest.workspaces[index].toContractMap(),
              )) {
            throw LocalJournalException(
              LocalJournalErrorCode.manifestMismatch,
              'The local workspace changed after deletion consent was granted',
            );
          }
        }

        final result = <LocalReconciliationIdentity>[];
        for (final snapshot in snapshots) {
          for (final evidence in snapshot.prunedEvidence) {
            final receipt = evidence.receipt;
            result.add(
              LocalReconciliationIdentity(
                partition: snapshot.checkpoint.partition,
                deviceSessionId: snapshot.preparedPackage.deviceSessionId,
                operationId: receipt.operationId,
                commandId: receipt.commandId,
                requestHash: receipt.requestHash,
                writerEpoch: receipt.writerEpoch,
                localSequence: evidence.localSequence,
                receiptKnowledge: LocalReceiptKnowledge.accepted,
              ),
            );
          }
          for (final entry in snapshot.retainedEntries) {
            result.add(
              LocalReconciliationIdentity(
                partition: snapshot.checkpoint.partition,
                deviceSessionId: entry.operation.deviceSessionId,
                operationId: entry.operation.operationId,
                commandId: entry.operation.commandId,
                requestHash: entry.operation.requestHash,
                writerEpoch: entry.operation.writerEpoch,
                localSequence: entry.operation.localSequence,
                receiptKnowledge: _receiptKnowledge(entry.delivery),
              ),
            );
          }
        }
        return List.unmodifiable(result);
      },
    );
  }

  /// Packet 07 cannot honestly provide cross-platform encrypted quarantine.
  /// This explicit API fails closed until a reviewed secure-storage provider is
  /// supplied; server-side account deletion must continue independently.
  Future<Never> quarantineDeletionManifest({
    required LocalDeletionConsent consent,
    required String namedCustodianId,
    required DateTime dispositionDeadline,
  }) async {
    _requireReady();
    if (!OfficialStatIdentifiers.isValid(namedCustodianId) ||
        !dispositionDeadline.isAfter(consent.grantedAt)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Quarantine requires a named custodian and future deadline',
      );
    }
    throw LocalJournalException(
      LocalJournalErrorCode.secureQuarantineUnavailable,
      'Encrypted local quarantine is unavailable on this adapter; preserve '
      'the exact manifest/export and continue server deletion independently',
      {
        'adapter': store.capability.adapter,
        'encryptedAtRestClaimed': store.capability.encryptedAtRestClaimed,
        'manifestId': consent.manifestId,
      },
    );
  }

  Future<LocalJournalRecoveryArchive> exportRecoveryArchive(
    JournalPartition partition, {
    required String archiveId,
    required String manifestId,
    required DateTime exportedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    if (!OfficialStatIdentifiers.isValid(archiveId) ||
        !OfficialStatIdentifiers.isValid(manifestId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        'archiveId and manifestId must be opaque IDs',
      );
    }
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        final archive = LocalJournalRecoveryArchive.create(
          archiveId: archiveId,
          manifestId: manifestId,
          partition: partition,
          preparedPackage: snapshot.preparedPackage,
          checkpoint: snapshot.checkpoint,
          entries: snapshot.retainedEntries,
          receiptTombstones: snapshot.prunedEvidence,
          exportedByAccountId: activeActorAccountId,
          exportedByDeviceSessionId: snapshot.preparedPackage.deviceSessionId,
          exportedAt: exportedAt,
        );
        await transaction.put(
          _exportKey(partition, archiveId),
          LocalJournalRecordCodec.encode(
            _recoveryExportAuditPayload(
              archive: archive,
              snapshot: snapshot,
              persistedConfirmation: false,
            ),
          ),
        );
        return LocalJournalRecoveryArchive.parse(
          archive.canonicalJson,
          expectedActorAccountId: activeActorAccountId,
          expectedPartition: partition,
        );
      },
    );
  }

  Future<LocalRecoveryImportRecord> importRecoveryArchive(
    String encoded, {
    JournalPartition? expectedPartition,
    required DateTime importedAt,
  }) async {
    _requireReady();
    if (expectedPartition != null) _requirePartitionAccess(expectedPartition);
    final archive = LocalJournalRecoveryArchive.parse(
      encoded,
      expectedActorAccountId: activeActorAccountId,
      expectedPartition: expectedPartition,
    );
    final record = LocalRecoveryImportRecord(
      archiveId: archive.archiveId,
      checksum: archive.checksum,
      partition: archive.partition,
      importedAt: importedAt,
    );
    return _guardedTransaction(
      partition: archive.partition,
      action: (transaction) async {
        final key = _importKey(activeActorAccountId, archive.archiveId);
        final prior = await transaction.get(key);
        if (prior != null) {
          final decoded = LocalJournalRecordCodec.decode(prior);
          if (decoded['checksum'] != archive.checksum) {
            throw LocalJournalException(
              LocalJournalErrorCode.payloadKeyConflict,
              'Archive ID was already imported with different content',
            );
          }
          return record;
        }
        // Imported bytes are isolated from active partitions. Packet 08 must
        // reconcile current authority and accepted receipts before any replay.
        await transaction.put(
          key,
          LocalJournalRecordCodec.encode({
            'archive': archive.toContractMap(),
            'archiveId': archive.archiveId,
            'checksum': archive.checksum,
            'import': record.toContractMap(),
            'trust': RecoveryArchiveTrust.importedUntrusted.name,
          }),
        );
        return record;
      },
    );
  }

  Future<void> confirmRecoveryArchivePersisted(
    JournalPartition partition, {
    required String archiveId,
    required String checksum,
    required String confirmation,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    if (confirmation != 'recoveryArchivePersisted') {
      throw LocalJournalException(
        LocalJournalErrorCode.consentRequired,
        'Exact recovery archive persistence confirmation is required',
      );
    }
    LocalJournalValidation.requireId('archiveId', archiveId);
    LocalJournalValidation.requireHash('checksum', checksum);
    await _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final key = _exportKey(partition, archiveId);
        final value = await transaction.get(key);
        if (value == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.operationNotFound,
            'Recovery archive export record was not found',
          );
        }
        final record = LocalJournalRecordCodec.decode(value);
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        _requireRecoveryExportAudit(
          record: record,
          partition: partition,
          snapshot: snapshot,
          archiveId: archiveId,
          checksum: checksum,
          requirePersistedConfirmation: false,
        );
        await transaction.put(
          key,
          LocalJournalRecordCodec.encode({
            ...record,
            'persistedConfirmation': true,
          }),
        );
      },
    );
  }

  Future<LocalWorkspaceCheckpoint> pruneAcknowledged(
    JournalPartition partition, {
    required int throughSequence,
    required String recoveryArchiveId,
    required String recoveryArchiveChecksum,
    required DateTime prunedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    LocalJournalValidation.requireSafeInteger(
      'throughSequence',
      throughSequence,
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
    );
    LocalJournalValidation.requireId('recoveryArchiveId', recoveryArchiveId);
    LocalJournalValidation.requireHash(
      'recoveryArchiveChecksum',
      recoveryArchiveChecksum,
    );
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        final checkpoint = snapshot.checkpoint;
        if (checkpoint.submissionState != WorkspaceSubmissionState.submitted ||
            (checkpoint.acceptedThroughSequence.valueOrNull ?? -1) <
                throughSequence) {
          throw LocalJournalException(
            LocalJournalErrorCode.invalidStateTransition,
            'Only submitted, durably acknowledged operations may be pruned',
          );
        }
        final exportValue = await transaction.get(
          _exportKey(partition, recoveryArchiveId),
        );
        if (exportValue == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.consentRequired,
            'A confirmed recovery archive is required before pruning',
          );
        }
        final export = LocalJournalRecordCodec.decode(exportValue);
        _requireRecoveryExportAudit(
          record: export,
          partition: partition,
          snapshot: snapshot,
          archiveId: recoveryArchiveId,
          checksum: recoveryArchiveChecksum,
          requirePersistedConfirmation: true,
        );

        var removedCount = 0;
        var removedBytes = 0;
        String? terminalHash;
        final pending = <LocalJournalEntry>[];
        final retainedBySequence = <int, LocalJournalEntry>{
          for (final entry in snapshot.retainedEntries)
            entry.operation.localSequence: entry,
        };
        for (
          var sequence =
              (checkpoint.prunedThroughSequence.valueOrNull ?? -1) + 1;
          sequence <= throughSequence;
          sequence++
        ) {
          final entry = retainedBySequence[sequence];
          if (entry == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.sequenceGap,
              'Prune boundary includes a missing retained operation',
            );
          }
          if (entry.delivery.state != JournalDeliveryState.accepted ||
              entry.delivery.serverReceipt.valueOrNull == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.receiptMismatch,
              'Every pruned operation requires a durable receipt tombstone',
            );
          }
          pending.add(entry);
          removedCount++;
          removedBytes += entry.operation.byteCount;
          terminalHash = entry.operation.requestHash;
        }

        // All package/checkpoint, prefix, receipt, entry, and secondary-index
        // evidence has been validated above. Only now may the transaction write.
        for (final entry in pending) {
          final sequence = entry.operation.localSequence;
          final index = _indexPayload(
            operation: entry.operation,
            entryKey: _entryKey(partition, sequence),
            pruned: true,
          );
          await transaction.put(
            _operationIndexKey(partition, entry.operation.operationId),
            LocalJournalRecordCodec.encode(index),
          );
          await transaction.put(
            _commandIndexKey(partition, entry.operation.commandId),
            LocalJournalRecordCodec.encode(index),
          );
          await transaction.delete(_entryKey(partition, sequence));
        }
        if (terminalHash == null) {
          return checkpoint;
        }
        final updated = _copyCheckpoint(
          checkpoint,
          prunedThroughSequence: Fact.known(throughSequence),
          prunedThroughHash: Fact.known(terminalHash),
          retainedOperationCount:
              checkpoint.retainedOperationCount - removedCount,
          retainedOperationBytes:
              checkpoint.retainedOperationBytes - removedBytes,
          updatedAt: prunedAt,
        );
        await transaction.put(
          _checkpointKey(partition),
          LocalJournalRecordCodec.encode(updated.toContractMap()),
        );
        return LocalWorkspaceCheckpoint.fromContractMap(
          LocalJournalRecordCodec.decode(
            LocalJournalRecordCodec.encode(updated.toContractMap()),
          ),
        );
      },
    );
  }

  Future<LocalJournalEntry> _updateDelivery(
    JournalPartition partition,
    String operationId,
    LocalJournalDelivery Function(LocalJournalEntry entry) update, {
    bool markConflictBranch = false,
    DateTime? observedAt,
  }) async {
    _requireReady();
    _requirePartitionAccess(partition);
    if (!OfficialStatIdentifiers.isValid(operationId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        'operationId is invalid',
      );
    }
    return _guardedTransaction(
      partition: partition,
      action: (transaction) async {
        final entry = await _requireEntryByOperationId(
          transaction,
          partition,
          operationId,
        );
        final checkpoint = await _requireCheckpoint(transaction, partition);
        if (checkpoint.recoveryState != LocalWorkspaceRecoveryState.active) {
          throw LocalJournalException(
            LocalJournalErrorCode.writerEpochConflict,
            'Delivery is paused on a preserved conflict branch',
          );
        }
        final updated = LocalJournalEntry(
          operation: entry.operation,
          delivery: update(entry),
        );
        await transaction.put(
          _entryKey(partition, entry.operation.localSequence),
          LocalJournalRecordCodec.encode(updated.toContractMap()),
        );
        if (markConflictBranch) {
          final conflicted = _copyCheckpoint(
            checkpoint,
            recoveryState: LocalWorkspaceRecoveryState.conflictBranch,
            updatedAt: observedAt ?? checkpoint.updatedAt,
          );
          await transaction.put(
            _checkpointKey(partition),
            LocalJournalRecordCodec.encode(conflicted.toContractMap()),
          );
        }
        return _cloneEntry(updated);
      },
    );
  }

  Future<LocalAppendResult> _resolveExactReplay(
    LocalJournalStoreTransaction transaction,
    LocalGameJournalOperation operation,
    Map<String, Object?>? operationIndex,
    Map<String, Object?>? commandIndex,
  ) async {
    if (operationIndex != null) {
      await _requireValidPersistedIndexBinding(
        transaction,
        operation.partition,
        operationIndex,
        observedKey: _operationIndexKey(
          operation.partition,
          operation.operationId,
        ),
        observedAsOperationIndex: true,
      );
    }
    if (commandIndex != null) {
      await _requireValidPersistedIndexBinding(
        transaction,
        operation.partition,
        commandIndex,
        observedKey: _commandIndexKey(operation.partition, operation.commandId),
        observedAsOperationIndex: false,
      );
    }
    if (operationIndex == null || commandIndex == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.payloadKeyConflict,
        'Operation or command ID is already bound to another request',
      );
    }
    if (OfficialStatCanonicalEncoding.encode(operationIndex) !=
        OfficialStatCanonicalEncoding.encode(commandIndex)) {
      throw LocalJournalException(
        LocalJournalErrorCode.payloadKeyConflict,
        'Operation and command IDs are bound to different requests',
      );
    }
    final operationRecordHash = OfficialStatCanonicalEncoding.sha256Hex(
      operation.toContractMap(),
    );
    final exact =
        operationIndex['operationRecordHash'] == operationRecordHash &&
        commandIndex['operationRecordHash'] == operationRecordHash &&
        operationIndex['entryKey'] == commandIndex['entryKey'];
    if (!exact) {
      throw LocalJournalException(
        LocalJournalErrorCode.payloadKeyConflict,
        'Operation or command ID was reused with changed immutable content',
      );
    }
    final pruned = operationIndex['pruned'] == true;
    if (pruned) {
      final receiptValue = await transaction.get(
        _receiptKey(operation.partition, operation.operationId),
      );
      if (receiptValue == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Pruned operation is missing its durable receipt tombstone',
        );
      }
      final receipt = operationReceiptFromMap(
        LocalJournalRecordCodec.decode(receiptValue),
      );
      _validateReceipt(operation, receipt);
      return LocalAppendResult(
        entry: null,
        durableReceipt: receipt,
        exactReplay: true,
        wasPruned: true,
      );
    }
    final entryValue = await transaction.get(
      operationIndex['entryKey'] as String,
    );
    if (entryValue == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Indexed operation record is missing',
      );
    }
    final entry = LocalJournalEntry.fromContractMap(
      LocalJournalRecordCodec.decode(entryValue),
    );
    _requireSamePartition(operation.partition, entry.operation.partition);
    _validateIndex(
      entry.operation,
      operationIndex['entryKey'] as String,
      operationIndex,
    );
    _validateIndex(
      entry.operation,
      commandIndex['entryKey'] as String,
      commandIndex,
    );
    return LocalAppendResult(
      entry: _cloneEntry(entry),
      durableReceipt: entry.delivery.serverReceipt.valueOrNull,
      exactReplay: true,
      wasPruned: false,
    );
  }

  Future<int?> _contiguousAcceptedThrough(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    LocalWorkspaceCheckpoint checkpoint,
  ) async {
    var sequence = (checkpoint.acceptedThroughSequence.valueOrNull ?? -1) + 1;
    int? last;
    while (sequence < checkpoint.nextLocalSequence) {
      final value = await transaction.get(_entryKey(partition, sequence));
      if (value == null) break;
      final entry = LocalJournalEntry.fromContractMap(
        LocalJournalRecordCodec.decode(value),
      );
      if (entry.delivery.state != JournalDeliveryState.accepted ||
          entry.delivery.serverReceipt.valueOrNull == null) {
        break;
      }
      last = sequence;
      sequence++;
    }
    return last ?? checkpoint.acceptedThroughSequence.valueOrNull;
  }

  Future<LocalJournalEntry> _requireEntryByOperationId(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    String operationId,
  ) async {
    if (!OfficialStatIdentifiers.isValid(operationId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidIdentifier,
        'operationId is invalid',
      );
    }
    final index = await _readIndex(
      transaction,
      _operationIndexKey(partition, operationId),
    );
    if (index == null) {
      // A missing caller-selected ID is normal. A deleted index for an
      // existing retained record is corruption and must defeat a stale
      // verified-partition cache before returning operationNotFound.
      await _requireVerifiedWorkspaceSnapshot(transaction, partition);
      throw LocalJournalException(
        LocalJournalErrorCode.operationNotFound,
        'Operation is not retained in this workspace',
      );
    }
    final operationIndexKey = _operationIndexKey(partition, operationId);
    await _requireValidPersistedIndexBinding(
      transaction,
      partition,
      index,
      observedKey: operationIndexKey,
      observedAsOperationIndex: true,
    );
    if (index['pruned'] == true) {
      throw LocalJournalException(
        LocalJournalErrorCode.operationNotFound,
        'Operation is not retained in this workspace',
      );
    }
    final sequence = index['localSequence']! as int;
    final entryKey = index['entryKey']! as String;
    if (index['operationId'] != operationId ||
        entryKey != _entryKey(partition, sequence)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation index identity does not match its storage key',
      );
    }
    final commandIndex = await _readIndex(
      transaction,
      _commandIndexKey(partition, index['commandId']! as String),
    );
    if (commandIndex == null ||
        OfficialStatCanonicalEncoding.encode(commandIndex) !=
            OfficialStatCanonicalEncoding.encode(index)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation and command indexes do not agree',
      );
    }
    final value = await transaction.get(entryKey);
    if (value == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Indexed operation record is missing',
      );
    }
    final entry = LocalJournalEntry.fromContractMap(
      LocalJournalRecordCodec.decode(value),
    );
    _requireSamePartition(partition, entry.operation.partition);
    _validateIndex(entry.operation, entryKey, index);
    return entry;
  }

  Future<LocalJournalEntry> _requireEntryBySequence(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    int sequence,
  ) async {
    final value = await transaction.get(_entryKey(partition, sequence));
    if (value == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.operationNotFound,
        'Operation sequence is not retained',
      );
    }
    return LocalJournalEntry.fromContractMap(
      LocalJournalRecordCodec.decode(value),
    );
  }

  Future<void> _requireWorkspaceEmptyForPreparation(
    LocalJournalStoreTransaction transaction,
    PreparedGameRecoveryPackage package,
  ) async {
    final partition = package.partition;
    if (await transaction.get(_checkpointKey(partition)) != null) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'A package cannot be recreated over an orphaned workspace checkpoint',
      );
    }
    for (final prefix in [
      _entryPrefix(partition),
      _operationIndexPrefix(partition),
      _commandIndexPrefix(partition),
      _receiptPrefix(partition),
      _recoveryExportPrefix(partition),
    ]) {
      if ((await transaction.scanPrefix(prefix, limit: 1)).isNotEmpty) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'A package cannot be recreated over orphaned workspace records',
          {'recordPrefix': prefix},
        );
      }
    }

    String? cursor;
    final prefix = _workspaceIndexAccountPrefix(partition.actorAccountId);
    do {
      final rows = await transaction.scanPrefix(
        prefix,
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        final index = LocalJournalRecordCodec.decode(row.value);
        LocalJournalValidation.exactKeys(index, const {
          'deviceSessionId',
          'packageChecksum',
          'partition',
        });
        final rawPartition = index['partition'];
        if (rawPartition is! Map) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Workspace index partition is malformed',
          );
        }
        final indexedPartition = JournalPartition.fromContractMap(
          Map<String, Object?>.from(rawPartition),
        );
        final indexedDeviceSessionId = LocalJournalValidation.requireId(
          'deviceSessionId',
          index['deviceSessionId'],
        );
        LocalJournalValidation.requireHash(
          'packageChecksum',
          index['packageChecksum'],
        );
        if (row.key !=
            _workspaceIndexKeyFor(
              indexedPartition,
              deviceSessionId: indexedDeviceSessionId,
            )) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Workspace index key does not bind its embedded identity',
          );
        }
        if (indexedPartition.key == partition.key) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'A package cannot be recreated over an orphaned workspace index',
          );
        }
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
  }

  Future<void> _requireExactWorkspaceIndexForPackage(
    LocalJournalStoreTransaction transaction,
    PreparedGameRecoveryPackage package,
  ) async {
    var matchingRows = 0;
    String? cursor;
    do {
      final rows = await transaction.scanPrefix(
        _workspaceIndexAccountPrefix(package.partition.actorAccountId),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        final index = LocalJournalRecordCodec.decode(row.value);
        LocalJournalValidation.exactKeys(index, const {
          'deviceSessionId',
          'packageChecksum',
          'partition',
        });
        final rawPartition = index['partition'];
        if (rawPartition is! Map) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Workspace index partition is malformed',
          );
        }
        final indexedPartition = JournalPartition.fromContractMap(
          Map<String, Object?>.from(rawPartition),
        );
        final deviceSessionId = LocalJournalValidation.requireId(
          'deviceSessionId',
          index['deviceSessionId'],
        );
        LocalJournalValidation.requireHash(
          'packageChecksum',
          index['packageChecksum'],
        );
        if (row.key !=
            _workspaceIndexKeyFor(
              indexedPartition,
              deviceSessionId: deviceSessionId,
            )) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Workspace index key does not bind its embedded identity',
          );
        }
        if (indexedPartition.key == package.partition.key) {
          matchingRows++;
          if (deviceSessionId != package.deviceSessionId ||
              index['packageChecksum'] != package.packageChecksum ||
              row.key != _workspaceIndexKey(package)) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Workspace index does not bind the prepared package',
            );
          }
        }
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
    if (matchingRows != 1) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Prepared workspace requires exactly one canonical workspace index',
      );
    }
  }

  Future<List<_VerifiedWorkspaceSnapshot>> _requireDeviceWorkspaceInventory(
    LocalJournalStoreTransaction transaction,
    String deviceSessionId,
  ) async {
    final discoveredPartitions = await _discoverAccountWorkspacePartitions(
      transaction,
    );
    final snapshots = <String, _VerifiedWorkspaceSnapshot>{};
    final orderedPartitions = discoveredPartitions.values.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final partition in orderedPartitions) {
      final packageValue = await transaction.get(_packageKey(partition));
      if (packageValue == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Account workspace evidence is orphaned from its prepared package',
        );
      }
      final package = PreparedGameRecoveryPackage.fromContractMap(
        LocalJournalRecordCodec.decode(packageValue),
      );
      if (package.partition.key != partition.key ||
          package.partition.actorAccountId != activeActorAccountId) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Prepared package storage identity is malformed',
        );
      }
      await _requireExactWorkspaceIndexForPackage(transaction, package);
      try {
        final snapshot = await _requireVerifiedWorkspaceSnapshot(
          transaction,
          partition,
        );
        if (package.deviceSessionId == deviceSessionId) {
          snapshots[partition.key] = snapshot;
        }
      } on LocalJournalException catch (error) {
        if (error.code != LocalJournalErrorCode.operationNotFound) rethrow;
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Prepared package is missing canonical workspace evidence',
          {'cause': error, 'causeCode': error.code.name},
        );
      }
    }
    final ordered = snapshots.values.toList()
      ..sort(
        (left, right) => left.checkpoint.partition.key.compareTo(
          right.checkpoint.partition.key,
        ),
      );
    return List.unmodifiable(ordered);
  }

  Future<Map<String, JournalPartition>> _discoverAccountWorkspacePartitions(
    LocalJournalStoreTransaction transaction,
  ) async {
    final discovered = <String, JournalPartition>{};
    for (final kind in _AccountWorkspaceRecordKind.values) {
      String? cursor;
      do {
        final rows = await transaction.scanPrefix(
          '${kind.namespace}/$activeActorAccountId/',
          startAfter: cursor,
          limit: LocalGameJournalLimits.integrityScanPageSize,
        );
        for (final row in rows) {
          final partition = _partitionFromCanonicalAccountRecordKey(
            row.key,
            kind,
          );
          if (kind == _AccountWorkspaceRecordKind.recoveryExport) {
            _requireInventoryRecoveryExportAudit(
              record: LocalJournalRecordCodec.decode(row.value),
              partition: partition,
              archiveId: row.key.split('/').last,
            );
          }
          discovered.putIfAbsent(partition.key, () => partition);
        }
        cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
            ? null
            : rows.last.key;
      } while (cursor != null);
    }

    String? cursor;
    do {
      final rows = await transaction.scanPrefix(
        _workspaceIndexAccountPrefix(activeActorAccountId),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        final partition = _partitionFromCanonicalWorkspaceIndexKey(row.key);
        discovered.putIfAbsent(partition.key, () => partition);
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
    return discovered;
  }

  JournalPartition _partitionFromCanonicalAccountRecordKey(
    String key,
    _AccountWorkspaceRecordKind kind,
  ) {
    final trailingSegments = switch (kind) {
      _AccountWorkspaceRecordKind.package ||
      _AccountWorkspaceRecordKind.checkpoint => 0,
      _ => 1,
    };
    final segments = key.split('/');
    if (segments.length != 9 + trailingSegments ||
        segments.first != kind.namespace ||
        segments[1] != activeActorAccountId) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Account workspace evidence has a noncanonical storage key',
      );
    }
    final partition = _partitionFromStorageSegments(segments, offset: 1);
    final expectedKey = switch (kind) {
      _AccountWorkspaceRecordKind.package => _packageKey(partition),
      _AccountWorkspaceRecordKind.checkpoint => _checkpointKey(partition),
      _AccountWorkspaceRecordKind.entry => () {
        final encodedSequence = segments[9];
        final sequence = int.tryParse(encodedSequence);
        if (encodedSequence.length != 16 ||
            !RegExp(r'^\d{16}$').hasMatch(encodedSequence) ||
            sequence == null ||
            sequence < 0 ||
            sequence >= LocalGameJournalLimits.maxOperationsPerWorkspace) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Journal entry has a noncanonical sequence storage key',
          );
        }
        return _entryKey(partition, sequence);
      }(),
      _AccountWorkspaceRecordKind.operationIndex => _operationIndexKey(
        partition,
        LocalJournalValidation.requireId('operationId', segments[9]),
      ),
      _AccountWorkspaceRecordKind.commandIndex => _commandIndexKey(
        partition,
        LocalJournalValidation.requireId('commandId', segments[9]),
      ),
      _AccountWorkspaceRecordKind.receipt => _receiptKey(
        partition,
        LocalJournalValidation.requireId('operationId', segments[9]),
      ),
      _AccountWorkspaceRecordKind.recoveryExport => _exportKey(
        partition,
        LocalJournalValidation.requireId('archiveId', segments[9]),
      ),
    };
    if (key != expectedKey) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Account workspace evidence has a noncanonical storage key',
      );
    }
    return partition;
  }

  JournalPartition _partitionFromCanonicalWorkspaceIndexKey(String key) {
    final segments = key.split('/');
    if (segments.length != 10 ||
        segments.first != 'workspaceIndex' ||
        segments[1] != activeActorAccountId) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Workspace index has a noncanonical storage key',
      );
    }
    final deviceSessionId = LocalJournalValidation.requireId(
      'deviceSessionId',
      segments[2],
    );
    final partition = JournalPartition(
      actorAccountId: LocalJournalValidation.requireId(
        'actorAccountId',
        segments[1],
      ),
      scope: GameScope(
        associationId: LocalJournalValidation.requireId(
          'associationId',
          segments[3],
        ),
        competitionId: LocalJournalValidation.requireId(
          'competitionId',
          segments[4],
        ),
        seasonId: LocalJournalValidation.requireId('seasonId', segments[5]),
        divisionId: LocalJournalValidation.requireId('divisionId', segments[6]),
        phaseId: LocalJournalValidation.requireId('phaseId', segments[7]),
        gameId: LocalJournalValidation.requireId('gameId', segments[8]),
      ),
      workspaceId: LocalJournalValidation.requireId('workspaceId', segments[9]),
    );
    if (key !=
        _workspaceIndexKeyFor(partition, deviceSessionId: deviceSessionId)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Workspace index has a noncanonical storage key',
      );
    }
    return partition;
  }

  JournalPartition _partitionFromStorageSegments(
    List<String> segments, {
    required int offset,
  }) => JournalPartition(
    actorAccountId: LocalJournalValidation.requireId(
      'actorAccountId',
      segments[offset],
    ),
    scope: GameScope(
      associationId: LocalJournalValidation.requireId(
        'associationId',
        segments[offset + 1],
      ),
      competitionId: LocalJournalValidation.requireId(
        'competitionId',
        segments[offset + 2],
      ),
      seasonId: LocalJournalValidation.requireId(
        'seasonId',
        segments[offset + 3],
      ),
      divisionId: LocalJournalValidation.requireId(
        'divisionId',
        segments[offset + 4],
      ),
      phaseId: LocalJournalValidation.requireId(
        'phaseId',
        segments[offset + 5],
      ),
      gameId: LocalJournalValidation.requireId('gameId', segments[offset + 6]),
    ),
    workspaceId: LocalJournalValidation.requireId(
      'workspaceId',
      segments[offset + 7],
    ),
  );

  static DeviceJournalWorkspaceSummary _workspaceSummary(
    _VerifiedWorkspaceSnapshot snapshot,
  ) {
    var accepted = snapshot.prunedEvidence.length;
    var unacknowledged = 0;
    var responseUnknown = 0;
    final reconciliationEvidence = <Map<String, Object?>>[];
    for (final item in snapshot.prunedEvidence) {
      reconciliationEvidence.add({
        'commandId': item.receipt.commandId,
        'localSequence': item.localSequence,
        'operationId': item.receipt.operationId,
        'receiptKnowledge': LocalReceiptKnowledge.accepted.name,
        'requestHash': item.receipt.requestHash,
        'writerEpoch': item.receipt.writerEpoch,
      });
    }
    for (final entry in snapshot.retainedEntries) {
      final knowledge = _receiptKnowledge(entry.delivery);
      reconciliationEvidence.add({
        'commandId': entry.operation.commandId,
        'localSequence': entry.operation.localSequence,
        'operationId': entry.operation.operationId,
        'receiptKnowledge': knowledge.name,
        'requestHash': entry.operation.requestHash,
        'writerEpoch': entry.operation.writerEpoch,
      });
      if (knowledge == LocalReceiptKnowledge.accepted) {
        accepted++;
      } else {
        unacknowledged++;
        if (knowledge == LocalReceiptKnowledge.responseUnknown) {
          responseUnknown++;
        }
      }
    }
    return DeviceJournalWorkspaceSummary(
      partition: snapshot.checkpoint.partition,
      packageChecksum: snapshot.preparedPackage.packageChecksum,
      deviceSessionId: snapshot.preparedPackage.deviceSessionId,
      writerEpoch: snapshot.checkpoint.writerEpoch,
      nextLocalSequence: snapshot.checkpoint.nextLocalSequence,
      unacknowledgedOperations: unacknowledged,
      receiptUnknownOperations: responseUnknown,
      acceptedOperations: accepted,
      reconciliationEvidenceChecksum: OfficialStatCanonicalEncoding.sha256Hex(
        reconciliationEvidence,
      ),
    );
  }

  Future<LocalWorkspaceCheckpoint> _requireCheckpoint(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
  ) async {
    final value = await transaction.get(_checkpointKey(partition));
    if (value == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.operationNotFound,
        'Workspace is not prepared on this device',
      );
    }
    final checkpoint = LocalWorkspaceCheckpoint.fromContractMap(
      LocalJournalRecordCodec.decode(value),
    );
    _requireSamePartition(partition, checkpoint.partition);
    final prunedCount =
        (checkpoint.prunedThroughSequence.valueOrNull ?? -1) + 1;
    if (checkpoint.retainedOperationCount + prunedCount !=
            checkpoint.nextLocalSequence ||
        (checkpoint.retainedOperationCount == 0) !=
            (checkpoint.retainedOperationBytes == 0)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Checkpoint lifetime and retained counters do not agree',
      );
    }
    return checkpoint;
  }

  Future<PreparedGameRecoveryPackage> _requirePackage(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
  ) async {
    final value = await transaction.get(_packageKey(partition));
    if (value == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.operationNotFound,
        'Prepared game recovery package is missing',
      );
    }
    final package = PreparedGameRecoveryPackage.fromContractMap(
      LocalJournalRecordCodec.decode(value),
    );
    _requireSamePartition(partition, package.partition);
    return package;
  }

  static LocalJournalEntry _decodeEntryRow(LocalKeyValue row) =>
      LocalJournalEntry.fromContractMap(
        LocalJournalRecordCodec.decode(row.value),
      );

  static LocalJournalEntry _cloneEntry(LocalJournalEntry entry) =>
      LocalJournalEntry.fromContractMap(
        LocalJournalRecordCodec.decode(
          LocalJournalRecordCodec.encode(entry.toContractMap()),
        ),
      );

  static Map<String, Object?> _indexPayload({
    required LocalGameJournalOperation operation,
    required String entryKey,
    required bool pruned,
  }) => {
    'commandId': operation.commandId,
    'entryKey': entryKey,
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

  static Future<Map<String, Object?>?> _readIndex(
    LocalJournalStoreTransaction transaction,
    String key,
  ) async {
    final value = await transaction.get(key);
    if (value == null) return null;
    final index = LocalJournalRecordCodec.decode(value);
    LocalJournalValidation.exactKeys(index, const {
      'commandId',
      'entryKey',
      'localSequence',
      'operationId',
      'operationRecordHash',
      'payloadHash',
      'pruned',
      'requestHash',
      'semanticHash',
    });
    LocalJournalValidation.requireId('operationId', index['operationId']);
    LocalJournalValidation.requireId('commandId', index['commandId']);
    LocalJournalValidation.requireSafeInteger(
      'localSequence',
      index['localSequence'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
    );
    for (final field in const [
      'operationRecordHash',
      'payloadHash',
      'requestHash',
      'semanticHash',
    ]) {
      LocalJournalValidation.requireHash(field, index[field]);
    }
    if (index['entryKey'] is! String || index['pruned'] is! bool) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Persisted operation index has malformed storage fields',
      );
    }
    return index;
  }

  Future<void> _requireValidPersistedIndexBinding(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    Map<String, Object?> index, {
    required String observedKey,
    required bool observedAsOperationIndex,
  }) async {
    final operationId = index['operationId']! as String;
    final commandId = index['commandId']! as String;
    final sequence = index['localSequence']! as int;
    final entryKey = index['entryKey']! as String;
    final operationKey = _operationIndexKey(partition, operationId);
    final commandKey = _commandIndexKey(partition, commandId);
    if (observedKey != (observedAsOperationIndex ? operationKey : commandKey) ||
        entryKey != _entryKey(partition, sequence)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation index key does not bind its embedded identity',
      );
    }
    final operationTwin = await _readIndex(transaction, operationKey);
    final commandTwin = await _readIndex(transaction, commandKey);
    final canonicalIndex = OfficialStatCanonicalEncoding.encode(index);
    if (operationTwin == null ||
        commandTwin == null ||
        OfficialStatCanonicalEncoding.encode(operationTwin) != canonicalIndex ||
        OfficialStatCanonicalEncoding.encode(commandTwin) != canonicalIndex) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation and command indexes do not agree',
      );
    }
    late LocalWorkspaceCheckpoint checkpoint;
    try {
      checkpoint = await _requireCheckpoint(transaction, partition);
    } on LocalJournalException catch (error) {
      if (error.code != LocalJournalErrorCode.operationNotFound) rethrow;
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Persisted operation index is missing its workspace checkpoint',
        {'cause': error, 'causeCode': error.code.name},
      );
    }
    late PreparedGameRecoveryPackage package;
    try {
      package = await _requirePackage(transaction, partition);
    } on LocalJournalException catch (error) {
      if (error.code != LocalJournalErrorCode.operationNotFound) rethrow;
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Persisted operation index is missing its recovery package',
        {'cause': error, 'causeCode': error.code.name},
      );
    }
    requireLocalJournalPackageCheckpointBinding(
      preparedPackage: package,
      checkpoint: checkpoint,
      errorCode: LocalJournalErrorCode.mutatedRecord,
    );
    final preparedRevision = package.candidateRevision;
    final submittedRevision = checkpoint.candidateRevisionSubmissionEvidence;
    if ((submittedRevision != null &&
            (preparedRevision == null ||
                !preparedRevision.hasSameIdentity(
                  submittedRevision.revision,
                ))) ||
        (preparedRevision != null &&
            checkpoint.submissionState !=
                WorkspaceSubmissionState.captureOpen &&
            submittedRevision == null)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Candidate revision package and submission evidence do not agree',
      );
    }
    final prunedThrough = checkpoint.prunedThroughSequence.valueOrNull ?? -1;
    final pruned = index['pruned']! as bool;
    if (sequence >= checkpoint.nextLocalSequence ||
        (sequence <= prunedThrough) != pruned) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation index pruning state or sequence is invalid',
      );
    }
    if (!pruned) {
      final entryValue = await transaction.get(entryKey);
      if (entryValue == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Indexed operation record is missing',
        );
      }
      final entry = LocalJournalEntry.fromContractMap(
        LocalJournalRecordCodec.decode(entryValue),
      );
      _requireSamePartition(partition, entry.operation.partition);
      _validateIndex(entry.operation, entryKey, index);
      requireLocalJournalOperationPackageBinding(
        operation: entry.operation,
        preparedPackage: package,
        checkpoint: checkpoint,
        errorCode: LocalJournalErrorCode.mutatedRecord,
      );
      final receiptValue = await transaction.get(
        _receiptKey(partition, operationId),
      );
      final embeddedReceipt = entry.delivery.serverReceipt.valueOrNull;
      if (embeddedReceipt == null && receiptValue != null) {
        throw LocalJournalException(
          LocalJournalErrorCode.receiptMismatch,
          'Unacknowledged operation has unexpected durable receipt evidence',
        );
      }
      if (embeddedReceipt != null) {
        if (receiptValue == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.receiptMismatch,
            'Accepted operation is missing durable receipt evidence',
          );
        }
        final durableReceipt = operationReceiptFromMap(
          LocalJournalRecordCodec.decode(receiptValue),
        );
        if (OfficialStatCanonicalEncoding.encode(
              operationReceiptToMap(embeddedReceipt),
            ) !=
            OfficialStatCanonicalEncoding.encode(
              operationReceiptToMap(durableReceipt),
            )) {
          throw LocalJournalException(
            LocalJournalErrorCode.receiptMismatch,
            'Accepted delivery and durable receipt evidence do not agree',
          );
        }
      }
      return;
    }
    if (await transaction.get(entryKey) != null) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Pruned operation still has a retained entry',
      );
    }
    final receiptValue = await transaction.get(
      _receiptKey(partition, operationId),
    );
    if (receiptValue == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Pruned operation is missing its durable receipt tombstone',
      );
    }
    final receipt = operationReceiptFromMap(
      LocalJournalRecordCodec.decode(receiptValue),
    );
    if (receipt.operationId != operationId ||
        receipt.commandId != commandId ||
        receipt.requestHash != index['requestHash'] ||
        receipt.actorAccountId != partition.actorAccountId ||
        receipt.scope.key != partition.scope.key ||
        receipt.workspaceId != partition.workspaceId ||
        receipt.writerEpoch != checkpoint.writerEpoch) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Pruned operation index does not bind its durable receipt',
      );
    }
  }

  Future<int?> _validatedReferenceSequence(
    LocalJournalStoreTransaction transaction, {
    required JournalPartition partition,
    required String referenceId,
    required PreparedGameRecoveryPackage preparedPackage,
    required LocalWorkspaceCheckpoint checkpoint,
  }) async {
    final index = await _readIndex(
      transaction,
      _operationIndexKey(partition, referenceId),
    );
    if (index == null) {
      await _requireVerifiedWorkspaceSnapshot(transaction, partition);
      return null;
    }
    final operationId = index['operationId']! as String;
    final commandId = index['commandId']! as String;
    final sequence = index['localSequence']! as int;
    final entryKey = index['entryKey']! as String;
    if (operationId != referenceId ||
        entryKey != _entryKey(partition, sequence) ||
        sequence >= checkpoint.nextLocalSequence ||
        ((checkpoint.prunedThroughSequence.valueOrNull ?? -1) >= sequence) !=
            (index['pruned']! as bool)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Referenced operation index identity is malformed',
      );
    }
    final commandIndex = await _readIndex(
      transaction,
      _commandIndexKey(partition, commandId),
    );
    if (commandIndex == null ||
        OfficialStatCanonicalEncoding.encode(commandIndex) !=
            OfficialStatCanonicalEncoding.encode(index)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Referenced operation and command indexes do not agree',
      );
    }
    if (index['pruned']! as bool) {
      final receiptValue = await transaction.get(
        _receiptKey(partition, operationId),
      );
      if (receiptValue == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.receiptMismatch,
          'Referenced pruned operation is missing its durable receipt',
        );
      }
      final receipt = operationReceiptFromMap(
        LocalJournalRecordCodec.decode(receiptValue),
      );
      if (receipt.operationId != operationId ||
          receipt.commandId != commandId ||
          receipt.requestHash != index['requestHash'] ||
          receipt.actorAccountId != partition.actorAccountId ||
          receipt.scope.key != partition.scope.key ||
          receipt.workspaceId != partition.workspaceId ||
          receipt.writerEpoch != checkpoint.writerEpoch) {
        throw LocalJournalException(
          LocalJournalErrorCode.receiptMismatch,
          'Referenced pruned receipt does not bind its operation index',
        );
      }
      return sequence;
    }
    final entryValue = await transaction.get(entryKey);
    if (entryValue == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Referenced retained operation is missing',
      );
    }
    final entry = LocalJournalEntry.fromContractMap(
      LocalJournalRecordCodec.decode(entryValue),
    );
    _requireSamePartition(partition, entry.operation.partition);
    requireLocalJournalOperationPackageBinding(
      operation: entry.operation,
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      errorCode: LocalJournalErrorCode.mutatedRecord,
    );
    _validateIndex(entry.operation, entryKey, index);
    return sequence;
  }

  Future<_VerifiedWorkspaceSnapshot> _requireVerifiedWorkspaceSnapshot(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
  ) async {
    late LocalWorkspaceCheckpoint checkpoint;
    try {
      checkpoint = await _requireCheckpoint(transaction, partition);
    } on LocalJournalException catch (error) {
      if (error.code != LocalJournalErrorCode.operationNotFound ||
          await transaction.get(_packageKey(partition)) == null) {
        rethrow;
      }
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Prepared package is missing its workspace checkpoint',
        {'cause': error, 'causeCode': error.code.name},
      );
    }
    late PreparedGameRecoveryPackage package;
    try {
      package = await _requirePackage(transaction, partition);
    } on LocalJournalException catch (error) {
      if (error.code != LocalJournalErrorCode.operationNotFound) rethrow;
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Prepared checkpoint is missing its recovery package',
        {'cause': error, 'causeCode': error.code.name},
      );
    }
    requireLocalJournalPackageCheckpointBinding(
      preparedPackage: package,
      checkpoint: checkpoint,
      errorCode: LocalJournalErrorCode.mutatedRecord,
    );
    final prunedEvidence = await _requireCompletePrunedReceiptEvidence(
      transaction,
      partition,
      checkpoint,
    );
    final expectedReceipts = <String, OperationReceiptContract>{
      for (final evidence in prunedEvidence)
        evidence.receipt.operationId: evidence.receipt,
    };
    final retainedEntries = <LocalJournalEntry>[];
    var expectedSequence =
        (checkpoint.prunedThroughSequence.valueOrNull ?? -1) + 1;
    var previousHash = checkpoint.prunedThroughHash.valueOrNull;
    var bytes = 0;
    String? cursor;
    do {
      final rows = await transaction.scanPrefix(
        _entryPrefix(partition),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        final entry = _decodeEntryRow(row);
        final operation = entry.operation;
        _requireSamePartition(partition, operation.partition);
        requireLocalJournalOperationPackageBinding(
          operation: operation,
          preparedPackage: package,
          checkpoint: checkpoint,
          errorCode: LocalJournalErrorCode.mutatedRecord,
        );
        if (operation.localSequence != expectedSequence ||
            row.key != _entryKey(partition, expectedSequence)) {
          throw LocalJournalException(
            LocalJournalErrorCode.sequenceGap,
            'Persisted operation sequence contains a gap',
            {'expected': expectedSequence, 'actual': operation.localSequence},
          );
        }
        if (expectedSequence == 0) {
          final isGenesis = switch (operation.previousOperationHash) {
            NotApplicableFact<String>(reasonCode: 'genesis') => true,
            _ => false,
          };
          if (!isGenesis) {
            throw LocalJournalException(
              LocalJournalErrorCode.hashMismatch,
              'Genesis operation has an invalid previous hash',
            );
          }
        } else if (operation.previousOperationHash.valueOrNull !=
            previousHash) {
          throw LocalJournalException(
            LocalJournalErrorCode.hashMismatch,
            'Persisted operation hash chain is broken',
          );
        }
        final operationIndex = await _readIndex(
          transaction,
          _operationIndexKey(partition, operation.operationId),
        );
        final commandIndex = await _readIndex(
          transaction,
          _commandIndexKey(partition, operation.commandId),
        );
        _validateIndex(operation, row.key, operationIndex);
        _validateIndex(operation, row.key, commandIndex);
        final retainedReceipt = entry.delivery.serverReceipt.valueOrNull;
        if (retainedReceipt != null) {
          if (expectedReceipts.containsKey(operation.operationId)) {
            throw LocalJournalException(
              LocalJournalErrorCode.receiptMismatch,
              'Retained and pruned receipt evidence overlaps',
            );
          }
          expectedReceipts[operation.operationId] = retainedReceipt;
        }
        retainedEntries.add(entry);
        previousHash = operation.requestHash;
        expectedSequence++;
        bytes += operation.byteCount;
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
    if (retainedEntries.length != checkpoint.retainedOperationCount ||
        bytes != checkpoint.retainedOperationBytes ||
        expectedSequence != checkpoint.nextLocalSequence ||
        previousHash != checkpoint.lastOperationHash.valueOrNull) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Checkpoint does not match persisted operation records',
      );
    }
    await _requireExactReceiptRows(transaction, partition, expectedReceipts);
    requireLocalJournalAcceptedCheckpointBinding(
      checkpoint: checkpoint,
      retainedEntries: retainedEntries,
      prunedEvidence: prunedEvidence,
      errorCode: LocalJournalErrorCode.mutatedRecord,
    );
    return _VerifiedWorkspaceSnapshot(
      preparedPackage: package,
      checkpoint: checkpoint,
      retainedEntries: List.unmodifiable(retainedEntries),
      prunedEvidence: prunedEvidence,
    );
  }

  static Future<List<PrunedReceiptEvidence>>
  _requireCompletePrunedReceiptEvidence(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    LocalWorkspaceCheckpoint checkpoint,
  ) async {
    final boundary = checkpoint.prunedThroughSequence.valueOrNull ?? -1;
    final terminalHash = checkpoint.prunedThroughHash.valueOrNull;
    if (boundary >= LocalGameJournalLimits.maxOperationsPerWorkspace ||
        (boundary < 0 && terminalHash != null) ||
        (boundary >= 0 && terminalHash == null)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Checkpoint pruned-prefix boundary is invalid',
      );
    }

    final evidenceBySequence = <int, PrunedReceiptEvidence>{};
    final operationIds = <String>{};
    final commandIds = <String>{};
    final indexedSequences = <int>{};
    final expectedCommandIndexes = <String, String>{};
    String? cursor;
    var indexCount = 0;
    do {
      final rows = await transaction.scanPrefix(
        _operationIndexPrefix(partition),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        indexCount++;
        if (indexCount > LocalGameJournalLimits.maxOperationsPerWorkspace) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Operation index count exceeds the workspace limit',
          );
        }
        final index = LocalJournalRecordCodec.decode(row.value);
        LocalJournalValidation.exactKeys(index, const {
          'commandId',
          'entryKey',
          'localSequence',
          'operationId',
          'operationRecordHash',
          'payloadHash',
          'pruned',
          'requestHash',
          'semanticHash',
        });
        final operationId = LocalJournalValidation.requireId(
          'operationId',
          index['operationId'],
        );
        final commandId = LocalJournalValidation.requireId(
          'commandId',
          index['commandId'],
        );
        final sequence = LocalJournalValidation.requireSafeInteger(
          'localSequence',
          index['localSequence'],
          maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
        );
        final requestHash = LocalJournalValidation.requireHash(
          'requestHash',
          index['requestHash'],
        );
        LocalJournalValidation.requireHash(
          'operationRecordHash',
          index['operationRecordHash'],
        );
        LocalJournalValidation.requireHash('payloadHash', index['payloadHash']);
        LocalJournalValidation.requireHash(
          'semanticHash',
          index['semanticHash'],
        );
        if (index['pruned'] is! bool ||
            index['entryKey'] != _entryKey(partition, sequence) ||
            row.key != _operationIndexKey(partition, operationId) ||
            sequence >= checkpoint.nextLocalSequence) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Operation index identity or bounds are invalid',
          );
        }
        final isPruned = index['pruned']! as bool;
        if ((sequence <= boundary) != isPruned) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Operation index pruning state does not match the checkpoint',
          );
        }
        if (!indexedSequences.add(sequence)) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Multiple operation indexes reuse one local sequence',
          );
        }
        final commandIndexKey = _commandIndexKey(partition, commandId);
        if (expectedCommandIndexes.containsKey(commandIndexKey)) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Multiple operation indexes reuse one command identifier',
          );
        }
        expectedCommandIndexes[commandIndexKey] =
            OfficialStatCanonicalEncoding.encode(index);
        if (!isPruned) {
          final entryValue = await transaction.get(
            _entryKey(partition, sequence),
          );
          if (entryValue == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.mutatedRecord,
              'Retained operation index points to a missing entry',
            );
          }
          final entry = LocalJournalEntry.fromContractMap(
            LocalJournalRecordCodec.decode(entryValue),
          );
          _requireSamePartition(partition, entry.operation.partition);
          _validateIndex(
            entry.operation,
            _entryKey(partition, sequence),
            index,
          );
          continue;
        }
        final receiptValue = await transaction.get(
          _receiptKey(partition, operationId),
        );
        if (receiptValue == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.receiptMismatch,
            'Pruned operation is missing durable receipt evidence',
          );
        }
        final receipt = operationReceiptFromMap(
          LocalJournalRecordCodec.decode(receiptValue),
        );
        if (receipt.operationId != operationId ||
            receipt.commandId != commandId ||
            receipt.requestHash != requestHash ||
            receipt.actorAccountId != partition.actorAccountId ||
            receipt.scope.key != partition.scope.key ||
            receipt.workspaceId != partition.workspaceId ||
            receipt.writerEpoch != checkpoint.writerEpoch ||
            !operationIds.add(operationId) ||
            !commandIds.add(commandId) ||
            evidenceBySequence.containsKey(sequence)) {
          throw LocalJournalException(
            LocalJournalErrorCode.receiptMismatch,
            'Pruned receipt evidence is duplicated or does not bind its index',
          );
        }
        evidenceBySequence[sequence] = PrunedReceiptEvidence(
          localSequence: sequence,
          receipt: receipt,
        );
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);

    cursor = null;
    var commandIndexCount = 0;
    do {
      final rows = await transaction.scanPrefix(
        _commandIndexPrefix(partition),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        commandIndexCount++;
        if (commandIndexCount >
            LocalGameJournalLimits.maxOperationsPerWorkspace) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Command index count exceeds the workspace limit',
          );
        }
        final expectedIndex = expectedCommandIndexes.remove(row.key);
        final actualIndex = OfficialStatCanonicalEncoding.encode(
          LocalJournalRecordCodec.decode(row.value),
        );
        if (expectedIndex == null || actualIndex != expectedIndex) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Operation and command index sets do not exactly agree',
          );
        }
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
    if (expectedCommandIndexes.isNotEmpty ||
        commandIndexCount != indexCount ||
        indexCount != checkpoint.nextLocalSequence ||
        indexedSequences.length != checkpoint.nextLocalSequence) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation and command indexes do not exactly cover the journal',
      );
    }

    final expectedCount = boundary + 1;
    if (evidenceBySequence.length != expectedCount) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Pruned receipt evidence count does not cover the complete prefix',
        {
          'expectedCount': expectedCount,
          'actualCount': evidenceBySequence.length,
        },
      );
    }
    final evidence = <PrunedReceiptEvidence>[];
    for (var sequence = 0; sequence < expectedCount; sequence++) {
      final item = evidenceBySequence[sequence];
      if (item == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.sequenceGap,
          'Pruned receipt evidence contains a sequence gap',
          {'missingSequence': sequence},
        );
      }
      evidence.add(item);
    }
    if (evidence.isNotEmpty &&
        evidence.last.receipt.requestHash != terminalHash) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Pruned receipt evidence terminal hash does not match the checkpoint',
      );
    }
    return List.unmodifiable(evidence);
  }

  static Future<void> _requireExactReceiptRows(
    LocalJournalStoreTransaction transaction,
    JournalPartition partition,
    Map<String, OperationReceiptContract> expected,
  ) async {
    final unmatched = Map<String, OperationReceiptContract>.from(expected);
    String? cursor;
    var count = 0;
    do {
      final rows = await transaction.scanPrefix(
        _receiptPrefix(partition),
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        count++;
        if (count > LocalGameJournalLimits.maxOperationsPerWorkspace) {
          throw LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Receipt evidence count exceeds the workspace limit',
          );
        }
        final receipt = operationReceiptFromMap(
          LocalJournalRecordCodec.decode(row.value),
        );
        final wanted = unmatched.remove(receipt.operationId);
        if (row.key != _receiptKey(partition, receipt.operationId) ||
            wanted == null ||
            OfficialStatCanonicalEncoding.encode(
                  operationReceiptToMap(wanted),
                ) !=
                OfficialStatCanonicalEncoding.encode(
                  operationReceiptToMap(receipt),
                )) {
          throw LocalJournalException(
            LocalJournalErrorCode.receiptMismatch,
            'Durable receipt rows are duplicated, unexpected, or mutated',
          );
        }
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
    if (unmatched.isNotEmpty || count != expected.length) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Durable receipt rows do not exactly cover accepted operations',
        {'missingCount': unmatched.length},
      );
    }
  }

  static void _validateIndex(
    LocalGameJournalOperation operation,
    String entryKey,
    Map<String, Object?>? index,
  ) {
    if (index == null ||
        index['entryKey'] != entryKey ||
        index['operationId'] != operation.operationId ||
        index['commandId'] != operation.commandId ||
        index['localSequence'] != operation.localSequence ||
        index['requestHash'] != operation.requestHash ||
        index['payloadHash'] != operation.payloadHash ||
        index['semanticHash'] != operation.semanticHash ||
        index['operationRecordHash'] !=
            OfficialStatCanonicalEncoding.sha256Hex(
              operation.toContractMap(),
            ) ||
        index['pruned'] != false) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Operation index does not match persisted evidence',
      );
    }
  }

  static int _jitterBasisPoints(String commandId, int retryCount) {
    final hash = OfficialStatCanonicalEncoding.sha256Hex({
      'commandId': commandId,
      'retryCount': retryCount,
      'retryPolicyVersion': LocalGameJournalLimits.retryPolicyVersion,
    });
    final sample = int.parse(hash.substring(0, 4), radix: 16);
    final width =
        LocalGameJournalLimits.retryMaximumJitterBasisPoints -
        LocalGameJournalLimits.retryMinimumJitterBasisPoints +
        1;
    return LocalGameJournalLimits.retryMinimumJitterBasisPoints +
        (sample % width);
  }

  static LocalPauseReason _pauseReason(CommandErrorCode code) => switch (code) {
    CommandErrorCode.unauthenticated => LocalPauseReason.authenticationRequired,
    CommandErrorCode.permissionDenied ||
    CommandErrorCode.scopeMismatch => LocalPauseReason.permissionDenied,
    CommandErrorCode.unsupportedSchemaVersion =>
      LocalPauseReason.unsupportedSchema,
    CommandErrorCode.staleWriterEpoch ||
    CommandErrorCode.writerTransferRequired =>
      LocalPauseReason.staleWriterEpoch,
    CommandErrorCode.resourceExhausted => LocalPauseReason.resourceExhausted,
    CommandErrorCode.staleAuthority ||
    CommandErrorCode.staleControlVersion ||
    CommandErrorCode.staleRevision ||
    CommandErrorCode.payloadKeyConflict ||
    CommandErrorCode.sequenceConflict ||
    CommandErrorCode.conflictBranchPreserved => LocalPauseReason.serverConflict,
    _ => LocalPauseReason.operatorResolutionRequired,
  };

  static bool _isConflictBranchError(CommandErrorCode code) => switch (code) {
    CommandErrorCode.staleAuthority ||
    CommandErrorCode.staleControlVersion ||
    CommandErrorCode.staleRevision ||
    CommandErrorCode.payloadKeyConflict ||
    CommandErrorCode.sequenceConflict ||
    CommandErrorCode.staleWriterEpoch ||
    CommandErrorCode.writerTransferRequired ||
    CommandErrorCode.conflictBranchPreserved => true,
    _ => false,
  };

  static LocalReceiptKnowledge _receiptKnowledge(
    LocalJournalDelivery delivery,
  ) {
    if (delivery.state == JournalDeliveryState.accepted) {
      return LocalReceiptKnowledge.accepted;
    }
    if (delivery.state == JournalDeliveryState.sending ||
        delivery.serverReceipt is UnknownFact<OperationReceiptContract>) {
      return LocalReceiptKnowledge.responseUnknown;
    }
    return LocalReceiptKnowledge.notSubmitted;
  }

  void _requireReady() {
    if (!_opened || !store.capability.captureEnabled || _integrityFailed) {
      throw LocalJournalException(
        _integrityFailed
            ? LocalJournalErrorCode.mutatedRecord
            : LocalJournalErrorCode.storageCapabilityUnproven,
        'Local capture is disabled until storage integrity is proven',
      );
    }
  }

  Future<T> _guardedTransaction<T>({
    JournalPartition? partition,
    bool missingRecordIsIntegrityFailure = false,
    required Future<T> Function(LocalJournalStoreTransaction transaction)
    action,
  }) async {
    try {
      return await store.transaction((transaction) async {
        // A call may have queued behind another storage transaction after its
        // public entry check. Recheck the global latch at callback entry so it
        // cannot commit after another observer disables capture.
        _requireReady();
        return action(transaction);
      });
    } on LocalJournalException catch (error, stackTrace) {
      if (error.details['errorOrigin'] == _callerErrorOrigin) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      _observePersistedFailure(
        error,
        partition: partition,
        missingRecordIsIntegrityFailure: missingRecordIsIntegrityFailure,
      );
      if (error.code == LocalJournalErrorCode.invalidArgument ||
          error.code == LocalJournalErrorCode.invalidIdentifier) {
        Error.throwWithStackTrace(
          LocalJournalException(
            LocalJournalErrorCode.mutatedRecord,
            'Persisted journal structure failed integrity validation',
            {'cause': error, 'causeCode': error.code.name},
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _observePersistedFailure(
    LocalJournalException error, {
    required JournalPartition? partition,
    bool missingRecordIsIntegrityFailure = false,
  }) {
    if (partition == null) {
      _verifiedPartitions.clear();
    } else {
      _verifiedPartitions.remove(partition.key);
    }
    final isIntegrityFailure = switch (error.code) {
      LocalJournalErrorCode.mutatedRecord ||
      LocalJournalErrorCode.scopeMismatch ||
      LocalJournalErrorCode.invalidArgument ||
      LocalJournalErrorCode.invalidIdentifier ||
      LocalJournalErrorCode.sequenceGap ||
      LocalJournalErrorCode.hashMismatch ||
      LocalJournalErrorCode.receiptMismatch => true,
      LocalJournalErrorCode.operationNotFound =>
        missingRecordIsIntegrityFailure,
      _ => false,
    };
    if (isIntegrityFailure) _integrityFailed = true;
  }

  void _requirePartitionAccess(JournalPartition partition) {
    if (partition.actorAccountId != activeActorAccountId) {
      throw LocalJournalException(
        LocalJournalErrorCode.accountAccessDenied,
        'Journal partition belongs to another account',
      );
    }
  }

  void _requireCompatiblePackage(PreparedGameRecoveryPackage package) {
    if (!compatibility.acceptedReducerVersions.contains(
      package.journalReducerVersion,
    )) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedReducerVersion,
        'Prepared reducer version is not supported',
      );
    }
    if (!compatibility.acceptedRulesProfileIds.contains(
      package.rulesProfileId,
    )) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedRulesProfile,
        'Prepared rules profile is not supported',
      );
    }
    if (!compatibility.acceptedCalculatorVersions.contains(
      package.calculatorVersion,
    )) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Prepared calculator version is not supported',
      );
    }
  }

  void _requireCompatibleOperation(LocalGameJournalOperation operation) {
    if (!compatibility.acceptedReducerVersions.contains(
      operation.reducerVersion,
    )) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedReducerVersion,
        'Operation reducer version is not supported',
      );
    }
    if (!compatibility.acceptedRulesProfileIds.contains(
      operation.rulesProfileId,
    )) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedRulesProfile,
        'Operation rules profile is not supported',
      );
    }
  }

  static void _requireSamePartition(
    JournalPartition expected,
    JournalPartition actual,
  ) {
    if (expected.key != actual.key) {
      throw LocalJournalException(
        LocalJournalErrorCode.scopeMismatch,
        'Journal record belongs to another account or game workspace',
      );
    }
  }

  static bool _sameStringFact(Fact<String> left, Fact<String> right) =>
      OfficialStatCanonicalEncoding.encode(
        left.toContractMap((value) => value),
      ) ==
      OfficialStatCanonicalEncoding.encode(
        right.toContractMap((value) => value),
      );

  static bool _sameIntFact(Fact<int> left, Fact<int> right) =>
      OfficialStatCanonicalEncoding.encode(
        left.toContractMap((value) => value),
      ) ==
      OfficialStatCanonicalEncoding.encode(
        right.toContractMap((value) => value),
      );

  static Map<String, Object?> _recoveryExportAuditPayload({
    required LocalJournalRecoveryArchive archive,
    required _VerifiedWorkspaceSnapshot snapshot,
    required bool persistedConfirmation,
  }) => {
    'archiveId': archive.archiveId,
    'acceptedThroughSequenceAtExport': snapshot
        .checkpoint
        .acceptedThroughSequence
        .toContractMap((value) => value),
    'auditVersion': LocalGameJournalLimits.recoveryExportAuditVersion,
    'capturedThroughSequence': snapshot.checkpoint.lastLocalSequence
        .toContractMap((value) => value),
    'checksum': archive.checksum,
    'coveredOperationCount': snapshot.checkpoint.nextLocalSequence,
    'coveredTerminalHash': snapshot.checkpoint.lastOperationHash.toContractMap(
      (value) => value,
    ),
    'deliveryEvidenceChecksum': _deliveryEvidenceChecksum(snapshot),
    'exportedAt': archive.exportedAt,
    'localSchemaVersion': LocalGameJournalLimits.localSchemaVersion,
    'manifestId': archive.manifestId,
    'partition': archive.partition.toContractMap(),
    'persistedConfirmation': persistedConfirmation,
    'preparationPackageChecksum': snapshot.preparedPackage.packageChecksum,
    'prunedReceiptCountAtExport': snapshot.prunedEvidence.length,
    'reexportRequired': false,
    'retainedEntryCountAtExport': snapshot.retainedEntries.length,
    'recoveryStateAtExport': snapshot.checkpoint.recoveryState.name,
    'submissionStateAtExport': snapshot.checkpoint.submissionState.name,
    'writerEpoch': snapshot.checkpoint.writerEpoch,
  };

  static void _requireRecoveryExportAudit({
    required Map<String, Object?> record,
    required JournalPartition partition,
    required _VerifiedWorkspaceSnapshot snapshot,
    required String archiveId,
    required String checksum,
    required bool requirePersistedConfirmation,
  }) {
    _requireCurrentRecoveryExport(record, archiveId: archiveId);
    LocalJournalValidation.exactKeys(record, const {
      'acceptedThroughSequenceAtExport',
      'archiveId',
      'auditVersion',
      'capturedThroughSequence',
      'checksum',
      'coveredOperationCount',
      'coveredTerminalHash',
      'deliveryEvidenceChecksum',
      'exportedAt',
      'localSchemaVersion',
      'manifestId',
      'partition',
      'persistedConfirmation',
      'preparationPackageChecksum',
      'prunedReceiptCountAtExport',
      'reexportRequired',
      'retainedEntryCountAtExport',
      'recoveryStateAtExport',
      'submissionStateAtExport',
      'writerEpoch',
    });
    final rawPartition = record['partition'];
    if (rawPartition is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Recovery export audit partition is malformed',
      );
    }
    final auditedPartition = JournalPartition.fromContractMap(
      Map<String, Object?>.from(rawPartition),
    );
    final captured = LocalJournalValidation.decodeIntFact(
      'capturedThroughSequence',
      record['capturedThroughSequence'],
    );
    final terminalHash = LocalJournalValidation.decodeStringFact(
      'coveredTerminalHash',
      record['coveredTerminalHash'],
      requireHash: true,
    );
    final acceptedThrough = LocalJournalValidation.decodeIntFact(
      'acceptedThroughSequenceAtExport',
      record['acceptedThroughSequenceAtExport'],
    );
    final operationCount = LocalJournalValidation.requireSafeInteger(
      'coveredOperationCount',
      record['coveredOperationCount'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final retainedCount = LocalJournalValidation.requireSafeInteger(
      'retainedEntryCountAtExport',
      record['retainedEntryCountAtExport'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final prunedCount = LocalJournalValidation.requireSafeInteger(
      'prunedReceiptCountAtExport',
      record['prunedReceiptCountAtExport'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final auditVersion = LocalJournalValidation.requireSafeInteger(
      'auditVersion',
      record['auditVersion'],
      minimum: 1,
    );
    final writerEpoch = LocalJournalValidation.requireSafeInteger(
      'writerEpoch',
      record['writerEpoch'],
    );
    final recoveryState = LocalWorkspaceRecoveryState.values
        .where((value) => value.name == record['recoveryStateAtExport'])
        .firstOrNull;
    final submissionState = WorkspaceSubmissionState.values
        .where((value) => value.name == record['submissionStateAtExport'])
        .firstOrNull;
    LocalJournalValidation.requireId('archiveId', record['archiveId']);
    LocalJournalValidation.requireId('manifestId', record['manifestId']);
    LocalJournalValidation.requireHash('checksum', record['checksum']);
    LocalJournalValidation.requireHash(
      'deliveryEvidenceChecksum',
      record['deliveryEvidenceChecksum'],
    );
    LocalJournalValidation.requireHash(
      'preparationPackageChecksum',
      record['preparationPackageChecksum'],
    );
    LocalJournalValidation.requireTimestamp('exportedAt', record['exportedAt']);
    final persistedConfirmation = record['persistedConfirmation'];
    final capturedSequence = captured.valueOrNull;
    final terminalHashValue = terminalHash.valueOrNull;
    if (auditVersion != LocalGameJournalLimits.recoveryExportAuditVersion ||
        auditedPartition.key != partition.key ||
        record['archiveId'] != archiveId ||
        record['preparationPackageChecksum'] !=
            snapshot.preparedPackage.packageChecksum ||
        writerEpoch != snapshot.checkpoint.writerEpoch ||
        recoveryState == null ||
        submissionState == null ||
        (operationCount == 0 &&
            (capturedSequence != null || terminalHashValue != null)) ||
        (operationCount > 0 &&
            (capturedSequence != operationCount - 1 ||
                terminalHashValue == null)) ||
        retainedCount + prunedCount != operationCount ||
        persistedConfirmation is! bool) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Recovery export audit does not bind the exact workspace evidence',
      );
    }
    if (record['checksum'] != checksum) {
      throw LocalJournalException(
        LocalJournalErrorCode.payloadKeyConflict,
        'Recovery archive checksum does not match the exported archive',
        const {'errorOrigin': _callerErrorOrigin},
      );
    }
    if (!_sameIntFact(
          acceptedThrough,
          snapshot.checkpoint.acceptedThroughSequence,
        ) ||
        !_sameIntFact(captured, snapshot.checkpoint.lastLocalSequence) ||
        !_sameStringFact(terminalHash, snapshot.checkpoint.lastOperationHash) ||
        operationCount != snapshot.checkpoint.nextLocalSequence ||
        record['deliveryEvidenceChecksum'] !=
            _deliveryEvidenceChecksum(snapshot) ||
        recoveryState != snapshot.checkpoint.recoveryState ||
        submissionState != snapshot.checkpoint.submissionState) {
      throw LocalJournalException(
        LocalJournalErrorCode.consentRequired,
        'Workspace delivery evidence changed after recovery export',
      );
    }
    if (requirePersistedConfirmation && persistedConfirmation != true) {
      throw LocalJournalException(
        LocalJournalErrorCode.consentRequired,
        'Recovery archive persistence is not confirmed',
      );
    }
  }

  static void _requireInventoryRecoveryExportAudit({
    required Map<String, Object?> record,
    required JournalPartition partition,
    required String archiveId,
  }) {
    final auditVersion = record['auditVersion'];
    if (record['reexportRequired'] == true ||
        record['localSchemaVersion'] == 1 ||
        auditVersion == null) {
      try {
        _requireLegacyRecoveryExportAudit(record, archiveId: archiveId);
      } on LocalJournalException catch (error) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Legacy recovery export audit is malformed',
          {'cause': error, 'causeCode': error.code.name},
        );
      }
      // Legacy audits did not persist a partition field. Their canonical key
      // remains a conservative workspace witness, but a valid stale audit is
      // not required to satisfy current freshness or prune authorization.
      return;
    }

    _requireCurrentRecoveryExport(record, archiveId: archiveId);
    LocalJournalValidation.exactKeys(record, const {
      'acceptedThroughSequenceAtExport',
      'archiveId',
      'auditVersion',
      'capturedThroughSequence',
      'checksum',
      'coveredOperationCount',
      'coveredTerminalHash',
      'deliveryEvidenceChecksum',
      'exportedAt',
      'localSchemaVersion',
      'manifestId',
      'partition',
      'persistedConfirmation',
      'preparationPackageChecksum',
      'prunedReceiptCountAtExport',
      'reexportRequired',
      'retainedEntryCountAtExport',
      'recoveryStateAtExport',
      'submissionStateAtExport',
      'writerEpoch',
    });
    final rawPartition = record['partition'];
    if (rawPartition is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Recovery export audit partition is malformed',
      );
    }
    final auditedPartition = JournalPartition.fromContractMap(
      Map<String, Object?>.from(rawPartition),
    );
    final captured = LocalJournalValidation.decodeIntFact(
      'capturedThroughSequence',
      record['capturedThroughSequence'],
    );
    final terminalHash = LocalJournalValidation.decodeStringFact(
      'coveredTerminalHash',
      record['coveredTerminalHash'],
      requireHash: true,
    );
    LocalJournalValidation.decodeIntFact(
      'acceptedThroughSequenceAtExport',
      record['acceptedThroughSequenceAtExport'],
    );
    final operationCount = LocalJournalValidation.requireSafeInteger(
      'coveredOperationCount',
      record['coveredOperationCount'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final retainedCount = LocalJournalValidation.requireSafeInteger(
      'retainedEntryCountAtExport',
      record['retainedEntryCountAtExport'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final prunedCount = LocalJournalValidation.requireSafeInteger(
      'prunedReceiptCountAtExport',
      record['prunedReceiptCountAtExport'],
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    final parsedAuditVersion = LocalJournalValidation.requireSafeInteger(
      'auditVersion',
      record['auditVersion'],
      minimum: 1,
    );
    LocalJournalValidation.requireSafeInteger(
      'writerEpoch',
      record['writerEpoch'],
    );
    LocalJournalValidation.requireId('archiveId', record['archiveId']);
    LocalJournalValidation.requireId('manifestId', record['manifestId']);
    LocalJournalValidation.requireHash('checksum', record['checksum']);
    LocalJournalValidation.requireHash(
      'deliveryEvidenceChecksum',
      record['deliveryEvidenceChecksum'],
    );
    LocalJournalValidation.requireHash(
      'preparationPackageChecksum',
      record['preparationPackageChecksum'],
    );
    LocalJournalValidation.requireTimestamp('exportedAt', record['exportedAt']);
    final recoveryState = LocalWorkspaceRecoveryState.values
        .where((value) => value.name == record['recoveryStateAtExport'])
        .firstOrNull;
    final submissionState = WorkspaceSubmissionState.values
        .where((value) => value.name == record['submissionStateAtExport'])
        .firstOrNull;
    final capturedSequence = captured.valueOrNull;
    final terminalHashValue = terminalHash.valueOrNull;
    if (parsedAuditVersion !=
            LocalGameJournalLimits.recoveryExportAuditVersion ||
        auditedPartition.key != partition.key ||
        record['archiveId'] != archiveId ||
        recoveryState == null ||
        submissionState == null ||
        (operationCount == 0 &&
            (capturedSequence != null || terminalHashValue != null)) ||
        (operationCount > 0 &&
            (capturedSequence != operationCount - 1 ||
                terminalHashValue == null)) ||
        retainedCount + prunedCount != operationCount ||
        record['persistedConfirmation'] is! bool) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Recovery export audit does not bind its canonical storage key',
      );
    }
  }

  static String _deliveryEvidenceChecksum(_VerifiedWorkspaceSnapshot snapshot) {
    final evidence = <Map<String, Object?>>[];
    for (final item in snapshot.prunedEvidence) {
      evidence.add({
        'localSequence': item.localSequence,
        'receipt': operationReceiptToMap(item.receipt),
      });
    }
    for (final entry in snapshot.retainedEntries) {
      final receipt = entry.delivery.serverReceipt.valueOrNull;
      evidence.add({
        if (receipt == null) 'delivery': entry.delivery.toContractMap(),
        'localSequence': entry.operation.localSequence,
        if (receipt != null) 'receipt': operationReceiptToMap(receipt),
      });
    }
    return OfficialStatCanonicalEncoding.sha256Hex(evidence);
  }

  static void _requireCurrentRecoveryExport(
    Map<String, Object?> record, {
    required String archiveId,
  }) {
    final auditVersion = record['auditVersion'];
    if (record['reexportRequired'] == true ||
        record['localSchemaVersion'] == 1 ||
        auditVersion == null) {
      try {
        _requireLegacyRecoveryExportAudit(record, archiveId: archiveId);
      } on LocalJournalException catch (error) {
        throw LocalJournalException(
          LocalJournalErrorCode.mutatedRecord,
          'Legacy recovery export audit is malformed',
          {'cause': error, 'causeCode': error.code.name},
        );
      }
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Legacy recovery export must be recreated before confirmation or prune',
      );
    }
    if (auditVersion is int &&
        auditVersion > LocalGameJournalLimits.recoveryExportAuditVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Recovery export audit version is newer than this journal reader',
      );
    }
    if (record['reexportRequired'] != false ||
        record['localSchemaVersion'] !=
            LocalGameJournalLimits.localSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Recovery export schema marker is missing or malformed',
      );
    }
  }

  static void _requireLegacyRecoveryExportAudit(
    Map<String, Object?> record, {
    required String archiveId,
  }) {
    LocalJournalValidation.exactKeys(record, const {
      'archiveId',
      'capturedThroughSequence',
      'checksum',
      'exportedAt',
      'localSchemaVersion',
      'manifestId',
      'persistedConfirmation',
      'reexportRequired',
    });
    final schemaVersion = LocalJournalValidation.requireSafeInteger(
      'localSchemaVersion',
      record['localSchemaVersion'],
      minimum: 1,
      maximum: LocalGameJournalLimits.localSchemaVersion,
    );
    LocalJournalValidation.requireId('archiveId', record['archiveId']);
    LocalJournalValidation.requireId('manifestId', record['manifestId']);
    LocalJournalValidation.requireHash('checksum', record['checksum']);
    LocalJournalValidation.requireTimestamp('exportedAt', record['exportedAt']);
    LocalJournalValidation.decodeIntFact(
      'capturedThroughSequence',
      record['capturedThroughSequence'],
    );
    final persistedConfirmation = record['persistedConfirmation'];
    final reexportRequired = record['reexportRequired'];
    if (record['archiveId'] != archiveId ||
        persistedConfirmation is! bool ||
        reexportRequired is! bool ||
        (schemaVersion == 1 &&
            (reexportRequired != true || persistedConfirmation != false)) ||
        (schemaVersion == LocalGameJournalLimits.localSchemaVersion &&
            reexportRequired != false)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Legacy recovery export audit invariants are invalid',
      );
    }
  }

  static LocalWorkspaceCheckpoint _copyCheckpoint(
    LocalWorkspaceCheckpoint source, {
    int? nextLocalSequence,
    Fact<int>? lastLocalSequence,
    Fact<String>? lastOperationHash,
    Fact<int>? prunedThroughSequence,
    Fact<String>? prunedThroughHash,
    Fact<int>? acceptedThroughSequence,
    Fact<String>? acceptedJournalHead,
    Fact<String>? acceptedJournalHash,
    int? retainedOperationCount,
    int? retainedOperationBytes,
    WorkspaceSubmissionState? submissionState,
    LocalWorkspaceRecoveryState? recoveryState,
    Fact<String>? preparationPackageChecksum,
    LocalCandidateRevisionSubmissionEvidence?
    candidateRevisionSubmissionEvidence,
    DateTime? updatedAt,
  }) => LocalWorkspaceCheckpoint(
    partition: source.partition,
    writerEpoch: source.writerEpoch,
    nextLocalSequence: nextLocalSequence ?? source.nextLocalSequence,
    lastLocalSequence: lastLocalSequence ?? source.lastLocalSequence,
    lastOperationHash: lastOperationHash ?? source.lastOperationHash,
    prunedThroughSequence:
        prunedThroughSequence ?? source.prunedThroughSequence,
    prunedThroughHash: prunedThroughHash ?? source.prunedThroughHash,
    acceptedThroughSequence:
        acceptedThroughSequence ?? source.acceptedThroughSequence,
    acceptedJournalHead: acceptedJournalHead ?? source.acceptedJournalHead,
    acceptedJournalHash: acceptedJournalHash ?? source.acceptedJournalHash,
    retainedOperationCount:
        retainedOperationCount ?? source.retainedOperationCount,
    retainedOperationBytes:
        retainedOperationBytes ?? source.retainedOperationBytes,
    submissionState: submissionState ?? source.submissionState,
    recoveryState: recoveryState ?? source.recoveryState,
    preparationPackageChecksum:
        preparationPackageChecksum ?? source.preparationPackageChecksum,
    candidateRevisionSubmissionEvidence:
        candidateRevisionSubmissionEvidence ??
        source.candidateRevisionSubmissionEvidence,
    updatedAt: updatedAt ?? source.updatedAt,
  );

  static String _entryPrefix(JournalPartition partition) =>
      'entry/${partition.key}/';

  static String _entryKey(JournalPartition partition, int sequence) =>
      '${_entryPrefix(partition)}${sequence.toString().padLeft(16, '0')}';

  static String _checkpointKey(JournalPartition partition) =>
      'checkpoint/${partition.key}';

  static String _packageKey(JournalPartition partition) =>
      'package/${partition.key}';

  static String _operationIndexKey(
    JournalPartition partition,
    String operationId,
  ) => 'operationIndex/${partition.key}/$operationId';

  static String _operationIndexPrefix(JournalPartition partition) =>
      'operationIndex/${partition.key}/';

  static String _commandIndexKey(
    JournalPartition partition,
    String commandId,
  ) => 'commandIndex/${partition.key}/$commandId';

  static String _commandIndexPrefix(JournalPartition partition) =>
      'commandIndex/${partition.key}/';

  static String _receiptKey(JournalPartition partition, String operationId) =>
      'receipt/${partition.key}/$operationId';

  static String _receiptPrefix(JournalPartition partition) =>
      'receipt/${partition.key}/';

  static String _exportKey(JournalPartition partition, String archiveId) =>
      'recoveryExport/${partition.key}/$archiveId';

  static String _recoveryExportPrefix(JournalPartition partition) =>
      'recoveryExport/${partition.key}/';

  static String _importKey(String actorAccountId, String archiveId) =>
      'untrustedImport/$actorAccountId/$archiveId';

  static String _workspaceIndexKey(PreparedGameRecoveryPackage package) =>
      _workspaceIndexKeyFor(
        package.partition,
        deviceSessionId: package.deviceSessionId,
      );

  static String _workspaceIndexKeyFor(
    JournalPartition partition, {
    required String deviceSessionId,
  }) =>
      'workspaceIndex/${partition.actorAccountId}/'
      '$deviceSessionId/${partition.scope.key}/${partition.workspaceId}';

  static String _workspaceIndexAccountPrefix(String actorAccountId) =>
      'workspaceIndex/$actorAccountId/';

  static String _deletionManifestKey(
    String actorAccountId,
    String deviceSessionId,
    String manifestId,
  ) => 'deletionManifest/$actorAccountId/$deviceSessionId/$manifestId';
}

void _validateReceipt(
  LocalGameJournalOperation operation,
  OperationReceiptContract receipt,
) {
  if (operation.operationId != receipt.operationId ||
      operation.commandId != receipt.commandId ||
      operation.partition.actorAccountId != receipt.actorAccountId ||
      operation.partition.workspaceId != receipt.workspaceId ||
      operation.partition.scope.key != receipt.scope.key ||
      operation.operationType != receipt.commandKind ||
      operation.requestHash != receipt.requestHash ||
      operation.writerEpoch != receipt.writerEpoch) {
    throw LocalJournalException(
      LocalJournalErrorCode.receiptMismatch,
      'Server receipt does not bind the exact local operation',
    );
  }
}
