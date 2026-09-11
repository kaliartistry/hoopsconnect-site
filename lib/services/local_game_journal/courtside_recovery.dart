import 'dart:async';

import '../../models/official_stats/assigned_game_bootstrap.dart';
import '../../models/official_stats/command_contract.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../models/official_stats/fact.dart';
import 'deletion_recovery_models.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_models.dart';
import 'journal_repository.dart';

/// Exact, minimized authority supplied by the future assigned-game callable.
///
/// This object deliberately contains references and hashes, not a second copy
/// of player or rules data. The integration owner must obtain every value from
/// the same authoritative bootstrap transaction before constructing it.
final class CourtsidePreparationMaterial {
  CourtsidePreparationMaterial({
    required this.bootstrap,
    required this.packageId,
    required this.workspaceId,
    required this.deviceSessionId,
    required this.assignmentId,
    required this.journalReducerVersion,
    required this.calculatorVersion,
    required this.rulesProfileId,
    required this.competitionPolicyVersion,
    required this.rosterSnapshotId,
    required this.rosterSnapshotHash,
    required this.acceptedServerSequence,
    required this.acceptedJournalHead,
    required this.acceptedJournalHash,
    required this.preparedAt,
  }) {
    if (!bootstrap.duties.contains('enter')) {
      throw const CourtsideRecoveryException(
        'assignmentMissingEnterDuty',
        'The exact assignment does not permit stat entry.',
      );
    }
    if (!bootstrap.acceptedCalculatorVersions.contains(calculatorVersion)) {
      throw const CourtsideRecoveryException(
        'calculatorNotAccepted',
        'The selected calculator is not accepted by this game bootstrap.',
      );
    }
  }

  final AssignedGameBootstrap bootstrap;
  final String packageId;
  final String workspaceId;
  final String deviceSessionId;
  final String assignmentId;
  final String journalReducerVersion;
  final String calculatorVersion;
  final String rulesProfileId;
  final String competitionPolicyVersion;
  final String rosterSnapshotId;
  final String rosterSnapshotHash;
  final Fact<int> acceptedServerSequence;
  final String acceptedJournalHead;
  final String acceptedJournalHash;
  final DateTime preparedAt;

  GameScope get scope => GameScope(
    associationId: bootstrap.scope['associationId']!,
    competitionId: bootstrap.scope['competitionId']!,
    seasonId: bootstrap.scope['seasonId']!,
    divisionId: bootstrap.scope['divisionId']!,
    phaseId: bootstrap.scope['phaseId']!,
    gameId: bootstrap.scope['gameId']!,
  );

  JournalPartition get partition => JournalPartition(
    actorAccountId: bootstrap.actorAccountId,
    scope: scope,
    workspaceId: workspaceId,
  );

  PreparedGameRecoveryPackage buildPackage() =>
      PreparedGameRecoveryPackage.create(
        packageId: packageId,
        partition: partition,
        deviceSessionId: deviceSessionId,
        writerEpoch: bootstrap.writerEpoch,
        journalReducerVersion: journalReducerVersion,
        calculatorVersion: calculatorVersion,
        rulesProfileId: rulesProfileId,
        competitionPolicyVersion: competitionPolicyVersion,
        assignmentId: assignmentId,
        assignmentVersion: bootstrap.assignmentVersion,
        rosterSnapshotId: rosterSnapshotId,
        rosterSnapshotHash: rosterSnapshotHash,
        acceptedServerSequence: acceptedServerSequence,
        acceptedJournalHead: acceptedJournalHead,
        acceptedJournalHash: acceptedJournalHash,
        preparedAt: preparedAt,
      );
}

final class CourtsideCaptureCommand {
  const CourtsideCaptureCommand({
    required this.operationId,
    required this.commandId,
    required this.operationType,
    required this.payload,
    required this.gamePeriod,
    required this.gameClockPosition,
    required this.logicalPlayOrder,
    required this.observedAt,
  });

  final String operationId;
  final String commandId;
  final JournalOperationType operationType;
  final Map<String, Object?> payload;
  final Fact<int> gamePeriod;
  final Fact<int> gameClockPosition;
  final int logicalPlayOrder;
  final DateTime observedAt;
}

/// The exact immutable request passed to a future server command adapter.
final class CourtsideDeliveryRequest {
  const CourtsideDeliveryRequest({
    required this.operation,
    required this.preparationPackageChecksum,
    required this.assignmentId,
    required this.assignmentVersion,
    required this.rosterSnapshotId,
    required this.rosterSnapshotHash,
  });

  final LocalGameJournalOperation operation;
  final String preparationPackageChecksum;
  final String assignmentId;
  final int assignmentVersion;
  final String rosterSnapshotId;
  final String rosterSnapshotHash;
}

sealed class CourtsideDeliveryResult {
  const CourtsideDeliveryResult();
}

final class CourtsideDeliveryAccepted extends CourtsideDeliveryResult {
  const CourtsideDeliveryAccepted(this.receipt);

  final OperationReceiptContract receipt;
}

final class CourtsideDeliveryRejected extends CourtsideDeliveryResult {
  const CourtsideDeliveryRejected(this.errorCode);

  final CommandErrorCode errorCode;
}

/// The command may have been accepted, but no exact receipt was observed.
/// Retrying must reuse the same command and request hashes.
final class CourtsideDeliveryResponseUnknown extends CourtsideDeliveryResult {
  const CourtsideDeliveryResponseUnknown({
    this.errorCode = CommandErrorCode.deadlineExceeded,
  });

  final CommandErrorCode errorCode;
}

abstract interface class CourtsideOperationServerAdapter {
  Future<CourtsideDeliveryResult> deliver(CourtsideDeliveryRequest request);
}

enum CourtsideRecoveryPhase {
  notReady,
  preparing,
  ready,
  delivering,
  needsAttention,
  captureDisabled,
  signedOut,
}

final class CourtsideOperationStatus {
  const CourtsideOperationStatus({
    required this.operationId,
    required this.commandId,
    required this.localSequence,
    required this.state,
    required this.responseUnknown,
    required this.lastErrorCode,
    required this.pauseReason,
  });

  final String operationId;
  final String commandId;
  final int localSequence;
  final JournalDeliveryState state;
  final bool responseUnknown;
  final String? lastErrorCode;
  final String? pauseReason;
}

final class CourtsideRecoverySnapshot {
  CourtsideRecoverySnapshot({
    required this.phase,
    required List<CourtsideOperationStatus> operations,
    required this.captureAvailability,
    required this.workspaceRecoveryState,
    required this.workspaceSubmissionState,
    required this.lastFailureCode,
  }) : operations = List.unmodifiable(operations);

  factory CourtsideRecoverySnapshot.initial() => CourtsideRecoverySnapshot(
    phase: CourtsideRecoveryPhase.notReady,
    operations: const [],
    captureAvailability: null,
    workspaceRecoveryState: null,
    workspaceSubmissionState: null,
    lastFailureCode: null,
  );

  final CourtsideRecoveryPhase phase;
  final List<CourtsideOperationStatus> operations;
  final LocalCaptureAvailability? captureAvailability;
  final LocalWorkspaceRecoveryState? workspaceRecoveryState;
  final WorkspaceSubmissionState? workspaceSubmissionState;
  final String? lastFailureCode;

  /// Web delivery is foreground/resume only. Closing the PWA stops it.
  bool get promisesBackgroundUploadAfterClose => false;

  int count(JournalDeliveryState state) =>
      operations.where((operation) => operation.state == state).length;

  int get responseUnknownCount =>
      operations.where((operation) => operation.responseUnknown).length;

  bool get allAccepted =>
      operations.isNotEmpty &&
      operations.every(
        (operation) => operation.state == JournalDeliveryState.accepted,
      );

  bool get revisionDeliveryAccepted =>
      workspaceSubmissionState == WorkspaceSubmissionState.submitted &&
      allAccepted;

  bool get canCapture =>
      phase == CourtsideRecoveryPhase.ready &&
      captureAvailability == LocalCaptureAvailability.ready &&
      workspaceRecoveryState == LocalWorkspaceRecoveryState.active &&
      workspaceSubmissionState == WorkspaceSubmissionState.captureOpen;

  CourtsideRecoverySnapshot copyWith({
    CourtsideRecoveryPhase? phase,
    List<CourtsideOperationStatus>? operations,
    LocalCaptureAvailability? captureAvailability,
    LocalWorkspaceRecoveryState? workspaceRecoveryState,
    WorkspaceSubmissionState? workspaceSubmissionState,
    String? lastFailureCode,
    bool clearLastFailureCode = false,
  }) => CourtsideRecoverySnapshot(
    phase: phase ?? this.phase,
    operations: operations ?? this.operations,
    captureAvailability: captureAvailability ?? this.captureAvailability,
    workspaceRecoveryState:
        workspaceRecoveryState ?? this.workspaceRecoveryState,
    workspaceSubmissionState:
        workspaceSubmissionState ?? this.workspaceSubmissionState,
    lastFailureCode: clearLastFailureCode
        ? null
        : (lastFailureCode ?? this.lastFailureCode),
  );
}

typedef CourtsideSnapshotListener =
    void Function(CourtsideRecoverySnapshot snapshot);

final class CourtsideDeletionReconciliationPlan {
  CourtsideDeletionReconciliationPlan({
    required this.manifest,
    required List<LocalReconciliationIdentity> identities,
  }) : identities = List.unmodifiable(identities);

  final DeviceJournalDeletionManifest manifest;
  final List<LocalReconciliationIdentity> identities;

  bool get consentAndManifestVerified => true;
  bool get containsUnsubmittedWork => identities.any(
    (identity) =>
        identity.receiptKnowledge == LocalReceiptKnowledge.notSubmitted,
  );
  bool get containsResponseUnknownWork => identities.any(
    (identity) =>
        identity.receiptKnowledge == LocalReceiptKnowledge.responseUnknown,
  );

  /// Reconciliation authority is not deletion authority. Packet 07 provides
  /// no silent purge and no portable encrypted quarantine.
  bool get localJournalDiscardPermitted => false;
}

final class CourtsideRecoveryException implements Exception {
  const CourtsideRecoveryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CourtsideRecoveryException($code): $message';
}

/// Candidate-only foreground orchestration over the durable Packet 07 journal.
///
/// This class has no Firebase dependency and is not imported by a production
/// entrypoint, route, or provider. A reviewed integration must supply the exact
/// authority material and a callable-backed [serverAdapter].
final class CourtsideRecoveryOrchestrator {
  CourtsideRecoveryOrchestrator({
    required this.repository,
    required this.material,
    required this.serverAdapter,
  }) : preparedPackage = material.buildPackage() {
    if (repository.activeActorAccountId != material.bootstrap.actorAccountId) {
      throw const CourtsideRecoveryException(
        'accountMismatch',
        'The journal repository and assigned-game bootstrap use different accounts.',
      );
    }
  }

  final LocalGameJournalRepository repository;
  final CourtsidePreparationMaterial material;
  final CourtsideOperationServerAdapter serverAdapter;
  final PreparedGameRecoveryPackage preparedPackage;
  final List<CourtsideSnapshotListener> _listeners = [];
  CourtsideRecoverySnapshot _snapshot = CourtsideRecoverySnapshot.initial();
  Future<void> _exclusiveTail = Future.value();
  bool _initialized = false;

  CourtsideRecoverySnapshot get snapshot => _snapshot;

  /// This candidate cannot activate itself or write a production feature flag.
  bool get productionActivationAllowed => false;

  void addSnapshotListener(CourtsideSnapshotListener listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeSnapshotListener(CourtsideSnapshotListener listener) {
    _listeners.remove(listener);
  }

  Future<CourtsideRecoverySnapshot> initialize() =>
      _exclusive(_initializeUnlocked);

  Future<CourtsideRecoverySnapshot> _initializeUnlocked() async {
    _publish(_snapshot.copyWith(phase: CourtsideRecoveryPhase.preparing));
    try {
      final capability = await repository.open();
      if (!capability.captureEnabled) {
        _publish(
          _snapshot.copyWith(
            phase: CourtsideRecoveryPhase.captureDisabled,
            captureAvailability: capability.availability,
            lastFailureCode:
                capability.reasonCode?.name ?? 'storageCapabilityUnproven',
          ),
        );
        return _snapshot;
      }
      await _prepareExactlyOnceAfterAmbiguousCommit();
      await repository.verifyIntegrity(material.partition);
      _initialized = true;
      await _recoverInterruptedSending(DateTime.now().toUtc());
      return _refreshUnlocked();
    } on LocalJournalException catch (error) {
      _publishLocalFailure(error);
      rethrow;
    }
  }

  Future<LocalAppendResult> capture(CourtsideCaptureCommand command) =>
      _exclusive(() => _captureUnlocked(command));

  Future<LocalAppendResult> _captureUnlocked(
    CourtsideCaptureCommand command,
  ) async {
    _requireInitializedAndWritable();
    final checkpoint = await repository.getCheckpoint(material.partition);
    final operation = LocalGameJournalOperation.create(
      partition: material.partition,
      operationId: command.operationId,
      commandId: command.commandId,
      deviceSessionId: preparedPackage.deviceSessionId,
      writerEpoch: preparedPackage.writerEpoch,
      localSequence: checkpoint.nextLocalSequence,
      previousOperationHash: checkpoint.lastOperationHash,
      expectedServerHead:
          checkpoint.acceptedJournalHead.valueOrNull ??
          preparedPackage.acceptedJournalHead,
      reducerVersion: preparedPackage.journalReducerVersion,
      rulesProfileId: preparedPackage.rulesProfileId,
      operationType: command.operationType,
      payload: command.payload,
      gamePeriod: command.gamePeriod,
      gameClockPosition: command.gameClockPosition,
      logicalPlayOrder: command.logicalPlayOrder,
      clientObservedAt: command.observedAt,
    );
    try {
      final result = await repository.append(operation);
      await _refreshUnlocked();
      return result;
    } on LocalJournalException catch (error) {
      if (error.code == LocalJournalErrorCode.transactionAborted) {
        // The commit may have succeeded while its response was lost. Exact
        // replay is the only safe way to determine whether the operation is
        // durable without creating a second command.
        try {
          final reconciled = await repository.append(operation);
          await _refreshUnlocked();
          return reconciled;
        } on LocalJournalException catch (replayError) {
          _publishLocalFailure(replayError);
          rethrow;
        }
      }
      _publishLocalFailure(error);
      rethrow;
    }
  }

  /// Runs only while the app is open or foregrounded. It deliberately makes
  /// no claim about upload after a browser or PWA has closed.
  Future<CourtsideRecoverySnapshot> recoverForeground({DateTime? now}) =>
      _exclusive(() => _recoverForegroundUnlocked(now ?? DateTime.now()));

  Future<CourtsideRecoverySnapshot> _recoverForegroundUnlocked(
    DateTime now,
  ) async {
    _requireInitialized();
    final observedAt = now.toUtc();
    await repository.verifyIntegrity(material.partition);
    await _recoverInterruptedSending(observedAt);
    await _refreshUnlocked();
    if (_snapshot.workspaceRecoveryState ==
        LocalWorkspaceRecoveryState.conflictBranch) {
      return _snapshot;
    }
    final ready = await repository.enumerateForegroundReady(
      material.partition,
      now: observedAt,
    );
    for (final original in ready) {
      var entry = original;
      if (entry.delivery.state == JournalDeliveryState.savedOnDevice) {
        entry = await repository.queue(
          material.partition,
          entry.operation.operationId,
        );
        await _refreshUnlocked();
      }
      if (entry.delivery.state != JournalDeliveryState.queued) continue;
      entry = await repository.markSending(
        material.partition,
        entry.operation.operationId,
      );
      await _refreshUnlocked(phase: CourtsideRecoveryPhase.delivering);
      final result = await _deliverPreservingUnknownResponse(entry.operation);
      if (result is CourtsideDeliveryAccepted) {
        await repository.storeServerReceipt(material.partition, result.receipt);
      } else if (result is CourtsideDeliveryRejected) {
        await repository.recordDeliveryFailure(
          material.partition,
          entry.operation.operationId,
          result.errorCode,
          observedAt: observedAt,
        );
      } else if (result is CourtsideDeliveryResponseUnknown) {
        await repository.recordDeliveryFailure(
          material.partition,
          entry.operation.operationId,
          result.errorCode,
          observedAt: observedAt,
        );
      }
      await _refreshUnlocked();
      if (_snapshot.workspaceRecoveryState ==
              LocalWorkspaceRecoveryState.conflictBranch ||
          _snapshot.phase == CourtsideRecoveryPhase.captureDisabled) {
        break;
      }
    }
    await _finalizeSubmittedWorkspaceIfReceipted(observedAt);
    return _refreshUnlocked();
  }

  Future<CourtsideDeliveryResult> _deliverPreservingUnknownResponse(
    LocalGameJournalOperation operation,
  ) async {
    final request = CourtsideDeliveryRequest(
      operation: operation,
      preparationPackageChecksum: preparedPackage.packageChecksum,
      assignmentId: preparedPackage.assignmentId,
      assignmentVersion: preparedPackage.assignmentVersion,
      rosterSnapshotId: preparedPackage.rosterSnapshotId,
      rosterSnapshotHash: preparedPackage.rosterSnapshotHash,
    );
    try {
      return await serverAdapter.deliver(request);
    } on Object {
      // Once sending is durable, an arbitrary transport exception cannot prove
      // rejection. Preserve the immutable command as response-unknown.
      return const CourtsideDeliveryResponseUnknown(
        errorCode: CommandErrorCode.transientUnavailable,
      );
    }
  }

  /// Accepts a receipt recovered by an exact status lookup. Receipts may
  /// arrive more than once or out of local sequence order; the repository
  /// validates every binding and advances only the contiguous accepted head.
  Future<CourtsideRecoverySnapshot> acceptRecoveredReceipt(
    OperationReceiptContract receipt,
  ) => _exclusive(() async {
    _requireInitialized();
    await repository.storeServerReceipt(material.partition, receipt);
    await _finalizeSubmittedWorkspaceIfReceipted(receipt.acceptedAt);
    return _refreshUnlocked();
  });

  /// Seals capture locally before delivery can represent a candidate revision.
  /// New operations are refused after this transition. The workspace becomes
  /// submitted only after every immutable operation has a durable receipt.
  Future<CourtsideRecoverySnapshot> queueRevisionSubmission({
    required DateTime observedAt,
  }) => _exclusive(() async {
    _requireInitializedAndWritable();
    if (_snapshot.operations.isEmpty) {
      throw const CourtsideRecoveryException(
        'emptyRevision',
        'A candidate revision cannot be submitted without journal evidence.',
      );
    }
    await repository.setSubmissionState(
      material.partition,
      WorkspaceSubmissionState.submissionQueued,
      observedAt: observedAt,
    );
    await _refreshUnlocked();
    return _recoverForegroundUnlocked(observedAt);
  });

  Future<CourtsideRecoverySnapshot> retryNeedsAttention(
    String operationId, {
    DateTime? now,
  }) => _exclusive(() async {
    _requireInitialized();
    if (_snapshot.captureAvailability != LocalCaptureAvailability.ready ||
        _snapshot.workspaceRecoveryState !=
            LocalWorkspaceRecoveryState.active) {
      throw const CourtsideRecoveryException(
        'retryUnavailable',
        'A preserved writer conflict or unavailable store cannot be retried automatically.',
      );
    }
    await repository.resumePaused(material.partition, operationId);
    await _refreshUnlocked();
    return _recoverForegroundUnlocked(now ?? DateTime.now());
  });

  Future<DeviceJournalDeletionManifest> createDeletionManifest({
    required String manifestId,
    required DateTime createdAt,
  }) => _exclusive(() async {
    _requireInitialized();
    return repository.createDeletionRecoveryManifest(
      manifestId: manifestId,
      deviceSessionId: preparedPackage.deviceSessionId,
      createdAt: createdAt,
    );
  });

  Future<CourtsideDeletionReconciliationPlan> reconcileDeletion(
    DeviceJournalDeletionManifest manifest,
    LocalDeletionConsent consent,
  ) => _exclusive(() async {
    _requireInitialized();
    if (manifest.actorAccountId != repository.activeActorAccountId ||
        manifest.deviceSessionId != preparedPackage.deviceSessionId ||
        consent.manifestId != manifest.manifestId ||
        consent.manifestChecksum != manifest.checksum ||
        consent.deviceSessionId != manifest.deviceSessionId) {
      throw LocalJournalException(
        LocalJournalErrorCode.consentRequired,
        'Deletion reconciliation requires the exact account, device, manifest, and checksum.',
      );
    }
    final identities = await repository.enumerateDeletionReconciliation(
      consent,
    );
    return CourtsideDeletionReconciliationPlan(
      manifest: manifest,
      identities: identities,
    );
  });

  /// Sign-out closes handles only. It never clears, rewrites, or transfers the
  /// account-bound journal.
  Future<void> closeForSignOut() => _exclusive(() async {
    await repository.close();
    _initialized = false;
    _publish(_snapshot.copyWith(phase: CourtsideRecoveryPhase.signedOut));
  });

  Future<void> _prepareExactlyOnceAfterAmbiguousCommit() async {
    try {
      await repository.prepareGame(preparedPackage);
    } on LocalJournalException catch (error) {
      if (error.code != LocalJournalErrorCode.transactionAborted) rethrow;
      await repository.prepareGame(preparedPackage);
    }
  }

  Future<void> _recoverInterruptedSending(DateTime observedAt) async {
    String? cursor;
    do {
      final page = await repository.listOperations(
        material.partition,
        pageSize: LocalGameJournalLimits.maxPageSize,
        cursor: cursor,
      );
      for (final entry in page.entries) {
        if (entry.delivery.state == JournalDeliveryState.sending) {
          await repository.recordDeliveryFailure(
            material.partition,
            entry.operation.operationId,
            CommandErrorCode.deadlineExceeded,
            observedAt: observedAt,
          );
        }
      }
      cursor = page.nextCursor;
    } while (cursor != null);
  }

  Future<void> _finalizeSubmittedWorkspaceIfReceipted(
    DateTime observedAt,
  ) async {
    final checkpoint = await repository.getCheckpoint(material.partition);
    if (checkpoint.submissionState !=
        WorkspaceSubmissionState.submissionQueued) {
      return;
    }
    final last = checkpoint.lastLocalSequence.valueOrNull;
    if (last == null ||
        checkpoint.acceptedThroughSequence.valueOrNull != last) {
      return;
    }
    await repository.setSubmissionState(
      material.partition,
      WorkspaceSubmissionState.submitted,
      observedAt: observedAt,
    );
  }

  Future<CourtsideRecoverySnapshot> _refreshUnlocked({
    CourtsideRecoveryPhase? phase,
  }) async {
    final checkpoint = await repository.getCheckpoint(material.partition);
    final operations = <CourtsideOperationStatus>[];
    String? cursor;
    do {
      final page = await repository.listOperations(
        material.partition,
        pageSize: LocalGameJournalLimits.maxPageSize,
        cursor: cursor,
      );
      for (final entry in page.entries) {
        operations.add(
          CourtsideOperationStatus(
            operationId: entry.operation.operationId,
            commandId: entry.operation.commandId,
            localSequence: entry.operation.localSequence,
            state: entry.delivery.state,
            responseUnknown:
                entry.delivery.serverReceipt
                    is UnknownFact<OperationReceiptContract>,
            lastErrorCode: entry.delivery.lastErrorCode.valueOrNull,
            pauseReason: entry.delivery.pauseReason.valueOrNull,
          ),
        );
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    final hasAttention =
        checkpoint.recoveryState ==
            LocalWorkspaceRecoveryState.conflictBranch ||
        operations.any(
          (operation) => operation.state == JournalDeliveryState.needsAttention,
        );
    _publish(
      CourtsideRecoverySnapshot(
        phase:
            phase ??
            (hasAttention
                ? CourtsideRecoveryPhase.needsAttention
                : CourtsideRecoveryPhase.ready),
        operations: operations,
        captureAvailability: repository.store.capability.availability,
        workspaceRecoveryState: checkpoint.recoveryState,
        workspaceSubmissionState: checkpoint.submissionState,
        lastFailureCode: hasAttention
            ? operations
                  .where(
                    (operation) =>
                        operation.state == JournalDeliveryState.needsAttention,
                  )
                  .map((operation) => operation.lastErrorCode)
                  .whereType<String>()
                  .firstOrNull
            : null,
      ),
    );
    return _snapshot;
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw const CourtsideRecoveryException(
        'notInitialized',
        'The exact game package must be prepared before recovery can run.',
      );
    }
  }

  void _requireInitializedAndWritable() {
    _requireInitialized();
    if (!_snapshot.canCapture) {
      throw const CourtsideRecoveryException(
        'captureUnavailable',
        'Capture is paused until the local storage or writer conflict is resolved.',
      );
    }
  }

  void _publishLocalFailure(LocalJournalException error) {
    final disablesCapture = switch (error.code) {
      LocalJournalErrorCode.resourceExhausted ||
      LocalJournalErrorCode.storageUnavailable ||
      LocalJournalErrorCode.storageCapabilityUnproven ||
      LocalJournalErrorCode.unsupportedSchemaVersion ||
      LocalJournalErrorCode.mutatedRecord ||
      LocalJournalErrorCode.hashMismatch => true,
      _ => false,
    };
    _publish(
      _snapshot.copyWith(
        phase: disablesCapture
            ? CourtsideRecoveryPhase.captureDisabled
            : CourtsideRecoveryPhase.needsAttention,
        captureAvailability: disablesCapture
            ? _availabilityFor(error.code)
            : _snapshot.captureAvailability,
        lastFailureCode: error.code.name,
      ),
    );
  }

  static LocalCaptureAvailability _availabilityFor(
    LocalJournalErrorCode code,
  ) => switch (code) {
    LocalJournalErrorCode.unsupportedSchemaVersion =>
      LocalCaptureAvailability.disabledUnsupportedSchema,
    LocalJournalErrorCode.mutatedRecord || LocalJournalErrorCode.hashMismatch =>
      LocalCaptureAvailability.disabledIntegrityFailure,
    LocalJournalErrorCode.storageCapabilityUnproven =>
      LocalCaptureAvailability.disabledCapabilityUnproven,
    _ => LocalCaptureAvailability.disabledStorageUnavailable,
  };

  void _publish(CourtsideRecoverySnapshot next) {
    _snapshot = next;
    for (final listener in [..._listeners]) {
      listener(next);
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _exclusiveTail;
    final released = Completer<void>();
    _exclusiveTail = released.future;
    await previous;
    try {
      return await action();
    } on LocalJournalException catch (error) {
      _publishLocalFailure(error);
      rethrow;
    } finally {
      released.complete();
    }
  }
}
