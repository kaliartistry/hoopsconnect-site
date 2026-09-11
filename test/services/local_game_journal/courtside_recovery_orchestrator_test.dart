import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/assigned_game_bootstrap.dart';
import 'package:hoops_connect/models/official_stats/command_contract.dart';
import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/courtside_recovery.dart';
import 'package:hoops_connect/services/local_game_journal/deletion_recovery_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:hoops_connect/services/local_game_journal/journal_store.dart';

import 'journal_test_support.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

AssignedGameBootstrap _bootstrap({
  int assignmentVersion = 3,
  int writerEpoch = 7,
  List<String> duties = const ['enter', 'submit'],
}) => AssignedGameBootstrap.tryParse(<String, Object?>{
  'readSchemaVersion': 2,
  'kind': 'assignedGameBootstrap',
  'actorAccountId': 'statistician_1',
  'scope': <String, Object?>{
    'associationId': 'jba',
    'competitionId': 'nbl',
    'seasonId': 'season_2026',
    'divisionId': 'division_1',
    'phaseId': 'regular',
    'gameId': 'game_1',
  },
  'homeTeamEntryId': 'team_home',
  'awayTeamEntryId': 'team_away',
  'gameControlVersion': 11,
  'assignment': <String, Object?>{
    'assignmentVersion': assignmentVersion,
    'writerEpoch': writerEpoch,
    'duties': duties,
  },
  'controlVersions': <String, Object?>{'association': 2, 'season': 9},
  'compatibility': <String, Object?>{
    'authorizationSchemaVersion': 2,
    'domainSchemaVersion': 2,
    'commandSchemaVersion': 2,
    'acceptedCalculatorVersions': <String>['calculator_v1'],
  },
  'evaluatedAt': '2026-09-11T14:00:00.000Z',
})!;

CourtsidePreparationMaterial _material({AssignedGameBootstrap? bootstrap}) =>
    CourtsidePreparationMaterial(
      bootstrap: bootstrap ?? _bootstrap(),
      packageId: 'package_1',
      workspaceId: 'workspace_1',
      deviceSessionId: 'device_1',
      assignmentId: 'assignment_1',
      journalReducerVersion: 'reducer_v1',
      calculatorVersion: 'calculator_v1',
      rulesProfileId: 'rules_v1',
      competitionPolicyVersion: 'policy_v1',
      rosterSnapshotId: 'roster_snapshot_1',
      rosterSnapshotHash: _hashA,
      acceptedServerSequence: const Fact.notApplicable(
        reasonCode: 'no_server_operations',
      ),
      acceptedJournalHead: 'head_0',
      acceptedJournalHash: _hashB,
      preparedAt: DateTime.utc(2026, 9, 11, 14),
    );

LocalGameJournalRepository _repository(LocalGameJournalStore store) =>
    LocalGameJournalRepository(
      store: store,
      activeActorAccountId: 'statistician_1',
      compatibility: LocalJournalCompatibility(
        acceptedReducerVersions: const {'reducer_v1'},
        acceptedCalculatorVersions: const {'calculator_v1'},
        acceptedRulesProfileIds: const {'rules_v1'},
      ),
    );

CourtsideCaptureCommand _command(int value) => CourtsideCaptureCommand(
  operationId: 'operation_$value',
  commandId: 'command_$value',
  operationType: JournalOperationType.setPlayerCounter,
  payload: <String, Object?>{
    'delta': 1,
    'participantId': 'participant_7',
    'stat': 'twoPointMade',
  },
  gamePeriod: const Fact.known(1),
  gameClockPosition: Fact.known(500000 - value),
  logicalPlayOrder: value,
  observedAt: DateTime.utc(2026, 9, 11, 14, 0, value),
);

OperationReceiptContract _receipt(CourtsideDeliveryRequest request) =>
    OperationReceiptContract(
      receiptId: 'receipt_${request.operation.localSequence}',
      scope: request.operation.partition.scope,
      workspaceId: request.operation.partition.workspaceId,
      operationId: request.operation.operationId,
      commandId: request.operation.commandId,
      actorAccountId: request.operation.partition.actorAccountId,
      commandKind: request.operation.operationType,
      requestHash: request.operation.requestHash,
      serverSequence: request.operation.localSequence,
      acceptedJournalHead: 'head_${request.operation.localSequence + 1}',
      acceptedJournalHash: request.operation.requestHash,
      writerEpoch: request.operation.writerEpoch,
      acceptedAt: DateTime.utc(
        2026,
        9,
        11,
        14,
        30,
        request.operation.localSequence,
      ),
    );

final class _ServerAdapter implements CourtsideOperationServerAdapter {
  _ServerAdapter(this.respond);

  final FutureOr<CourtsideDeliveryResult> Function(
    CourtsideDeliveryRequest request,
  )
  respond;
  final List<CourtsideDeliveryRequest> requests = [];

  @override
  Future<CourtsideDeliveryResult> deliver(
    CourtsideDeliveryRequest request,
  ) async {
    requests.add(request);
    return respond(request);
  }
}

final class _SwitchableFailureStore implements LocalGameJournalStore {
  _SwitchableFailureStore(this.inner);

  final FaultInjectingMemoryStore inner;
  LocalJournalErrorCode? transactionFailure;

  @override
  LocalStorageCapability get capability => inner.capability;

  @override
  Future<LocalStorageCapability> open() => inner.open();

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) {
    final failure = transactionFailure;
    if (failure != null) {
      throw LocalJournalException(failure, 'injected storage failure');
    }
    return inner.transaction(action);
  }

  @override
  Future<void> close() => inner.close();
}

final class _DisabledStore implements LocalGameJournalStore {
  @override
  LocalStorageCapability get capability => const LocalStorageCapability(
    availability: LocalCaptureAvailability.disabledStorageUnavailable,
    adapter: 'unavailable-test',
    durable: false,
    transactional: false,
    encryptedAtRestClaimed: false,
    localSchemaVersion: 2,
    reasonCode: LocalJournalErrorCode.storageUnavailable,
  );

  @override
  Future<LocalStorageCapability> open() async => capability;

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) => throw LocalJournalException(
    LocalJournalErrorCode.storageUnavailable,
    'unavailable',
  );

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'preparation binds exact account, assignment, writer, rules, and roster',
    () async {
      final store = FaultInjectingMemoryStore();
      final adapter = _ServerAdapter(
        (request) => CourtsideDeliveryAccepted(_receipt(request)),
      );
      final material = _material();
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: material,
        serverAdapter: adapter,
      );

      final snapshot = await orchestrator.initialize();

      expect(snapshot.phase, CourtsideRecoveryPhase.ready);
      expect(snapshot.operations, isEmpty);
      expect(orchestrator.productionActivationAllowed, isFalse);
      expect(orchestrator.preparedPackage.assignmentVersion, 3);
      expect(orchestrator.preparedPackage.writerEpoch, 7);
      expect(orchestrator.preparedPackage.rulesProfileId, 'rules_v1');
      expect(orchestrator.preparedPackage.rosterSnapshotHash, _hashA);
      expect(snapshot.promisesBackgroundUploadAfterClose, isFalse);
    },
  );

  test(
    'capture never claims saved before the local transaction commits',
    () async {
      final store = FaultInjectingMemoryStore();
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      final gate = Completer<void>();
      store.waitBeforeNextTransactionAction = gate.future;

      final pending = orchestrator.capture(_command(0));
      await Future<void>.delayed(Duration.zero);
      expect(orchestrator.snapshot.operations, isEmpty);

      gate.complete();
      final result = await pending;
      expect(result.savedOnDevice, isTrue);
      expect(
        orchestrator.snapshot.operations.single.state,
        JournalDeliveryState.savedOnDevice,
      );
    },
  );

  test(
    'ambiguous local commit replays the same command and finds durable work',
    () async {
      final store = FaultInjectingMemoryStore();
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      store.failAfterCommitOnce = true;

      final result = await orchestrator.capture(_command(0));

      expect(result.exactReplay, isTrue);
      expect(orchestrator.snapshot.operations, hasLength(1));
      expect(orchestrator.snapshot.operations.single.commandId, 'command_0');
    },
  );

  test(
    'loss before local commit retries without duplicating the operation',
    () async {
      final store = FaultInjectingMemoryStore();
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      store.failAtPut = 1;

      final result = await orchestrator.capture(_command(0));

      expect(result.exactReplay, isFalse);
      expect(orchestrator.snapshot.operations, hasLength(1));
      expect(
        orchestrator.snapshot.operations.single.operationId,
        'operation_0',
      );
    },
  );

  test(
    'foreground delivery publishes every honest state before acceptance',
    () async {
      final states = <JournalDeliveryState>[];
      final adapter = _ServerAdapter(
        (request) => CourtsideDeliveryAccepted(_receipt(request)),
      );
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: adapter,
      );
      orchestrator.addSnapshotListener((snapshot) {
        if (snapshot.operations.length == 1) {
          states.add(snapshot.operations.single.state);
        }
      });
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));

      await orchestrator.recoverForeground(
        now: DateTime.utc(2026, 9, 11, 14, 1),
      );

      expect(
        states,
        containsAllInOrder(<JournalDeliveryState>[
          JournalDeliveryState.savedOnDevice,
          JournalDeliveryState.queued,
          JournalDeliveryState.sending,
          JournalDeliveryState.accepted,
        ]),
      );
      expect(adapter.requests.single.assignmentVersion, 3);
      expect(adapter.requests.single.rosterSnapshotHash, _hashA);
      expect(orchestrator.snapshot.allAccepted, isTrue);
      expect(orchestrator.snapshot.revisionDeliveryAccepted, isFalse);
    },
  );

  test(
    'lost response keeps unknown work and exact retry is idempotent',
    () async {
      var attempts = 0;
      final adapter = _ServerAdapter((request) {
        attempts++;
        if (attempts == 1) {
          return const CourtsideDeliveryResponseUnknown();
        }
        return CourtsideDeliveryAccepted(_receipt(request));
      });
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: adapter,
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));
      await orchestrator.queueRevisionSubmission(
        observedAt: DateTime.utc(2026, 9, 11, 14, 1),
      );

      expect(orchestrator.snapshot.responseUnknownCount, 1);
      expect(
        orchestrator.snapshot.operations.single.state,
        JournalDeliveryState.queued,
      );

      await orchestrator.recoverForeground(
        now: DateTime.utc(2026, 9, 11, 14, 3),
      );
      expect(orchestrator.snapshot.allAccepted, isTrue);
      expect(orchestrator.snapshot.revisionDeliveryAccepted, isTrue);
      expect(
        orchestrator.snapshot.workspaceSubmissionState,
        WorkspaceSubmissionState.submitted,
      );
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests[0].operation.requestHash,
        adapter.requests[1].operation.requestHash,
      );
      expect(
        adapter.requests[0].operation.commandId,
        adapter.requests[1].operation.commandId,
      );
    },
  );

  test(
    'explicit submission closes capture and requires every durable receipt',
    () async {
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));

      final submitted = await orchestrator.queueRevisionSubmission(
        observedAt: DateTime.utc(2026, 9, 11, 14, 1),
      );

      expect(
        submitted.workspaceSubmissionState,
        WorkspaceSubmissionState.submitted,
      );
      expect(submitted.revisionDeliveryAccepted, isTrue);
      expect(submitted.canCapture, isFalse);
      await expectLater(
        orchestrator.capture(_command(1)),
        throwsA(isA<CourtsideRecoveryException>()),
      );
    },
  );

  test(
    'restart recovers a stranded sending operation without losing it',
    () async {
      final store = FaultInjectingMemoryStore();
      final firstRepository = _repository(store);
      final first = CourtsideRecoveryOrchestrator(
        repository: firstRepository,
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await first.initialize();
      await first.capture(_command(0));
      await firstRepository.queue(_material().partition, 'operation_0');
      await firstRepository.markSending(_material().partition, 'operation_0');
      await first.closeForSignOut();

      final restarted = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await restarted.initialize();

      expect(restarted.snapshot.operations, hasLength(1));
      expect(
        restarted.snapshot.operations.single.state,
        JournalDeliveryState.queued,
      );
      expect(restarted.snapshot.responseUnknownCount, 1);
    },
  );

  test(
    'duplicate and out-of-order recovered receipts advance only exact evidence',
    () async {
      final store = FaultInjectingMemoryStore();
      final repository = _repository(store);
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: repository,
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      await Future.wait([
        orchestrator.capture(_command(0)),
        orchestrator.capture(_command(1)),
      ]);
      final entries = (await repository.listOperations(
        _material().partition,
      )).entries;
      final requests = entries
          .map(
            (entry) => CourtsideDeliveryRequest(
              operation: entry.operation,
              preparationPackageChecksum:
                  orchestrator.preparedPackage.packageChecksum,
              assignmentId: orchestrator.preparedPackage.assignmentId,
              assignmentVersion: orchestrator.preparedPackage.assignmentVersion,
              rosterSnapshotId: orchestrator.preparedPackage.rosterSnapshotId,
              rosterSnapshotHash:
                  orchestrator.preparedPackage.rosterSnapshotHash,
            ),
          )
          .toList();

      await orchestrator.acceptRecoveredReceipt(_receipt(requests[1]));
      var checkpoint = await repository.getCheckpoint(_material().partition);
      expect(checkpoint.acceptedThroughSequence.valueOrNull, isNull);
      await orchestrator.acceptRecoveredReceipt(_receipt(requests[1]));
      await orchestrator.acceptRecoveredReceipt(_receipt(requests[0]));

      checkpoint = await repository.getCheckpoint(_material().partition);
      expect(checkpoint.acceptedThroughSequence.valueOrNull, 1);
      expect(orchestrator.snapshot.allAccepted, isTrue);
      expect(
        orchestrator.snapshot.operations.map(
          (operation) => operation.localSequence,
        ),
        <int>[0, 1],
      );
    },
  );

  test(
    'second-device conflict preserves a branch and prevents more capture',
    () async {
      final adapter = _ServerAdapter(
        (_) =>
            const CourtsideDeliveryRejected(CommandErrorCode.staleWriterEpoch),
      );
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: adapter,
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));
      await orchestrator.recoverForeground(
        now: DateTime.utc(2026, 9, 11, 14, 1),
      );

      expect(
        orchestrator.snapshot.workspaceRecoveryState,
        LocalWorkspaceRecoveryState.conflictBranch,
      );
      expect(
        orchestrator.snapshot.phase,
        CourtsideRecoveryPhase.needsAttention,
      );
      expect(orchestrator.snapshot.operations, hasLength(1));
      await expectLater(
        orchestrator.capture(_command(1)),
        throwsA(isA<CourtsideRecoveryException>()),
      );
    },
  );

  test(
    'assignment revocation pauses delivery but preserves retryable evidence',
    () async {
      var revoked = true;
      final adapter = _ServerAdapter((request) {
        if (revoked) {
          return const CourtsideDeliveryRejected(
            CommandErrorCode.assignmentRequired,
          );
        }
        return CourtsideDeliveryAccepted(_receipt(request));
      });
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: adapter,
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));
      await orchestrator.recoverForeground(
        now: DateTime.utc(2026, 9, 11, 14, 1),
      );

      expect(
        orchestrator.snapshot.operations.single.state,
        JournalDeliveryState.needsAttention,
      );
      expect(
        orchestrator.snapshot.workspaceRecoveryState,
        LocalWorkspaceRecoveryState.active,
      );

      revoked = false;
      await orchestrator.retryNeedsAttention(
        'operation_0',
        now: DateTime.utc(2026, 9, 11, 14, 2),
      );
      expect(orchestrator.snapshot.allAccepted, isTrue);
    },
  );

  test(
    'unavailable and quota-constrained storage disable capture honestly',
    () async {
      final unavailable = CourtsideRecoveryOrchestrator(
        repository: _repository(_DisabledStore()),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      final disabled = await unavailable.initialize();
      expect(disabled.phase, CourtsideRecoveryPhase.captureDisabled);
      expect(
        disabled.captureAvailability,
        LocalCaptureAvailability.disabledStorageUnavailable,
      );

      final wrapped = _SwitchableFailureStore(FaultInjectingMemoryStore());
      final quota = CourtsideRecoveryOrchestrator(
        repository: _repository(wrapped),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await quota.initialize();
      wrapped.transactionFailure = LocalJournalErrorCode.resourceExhausted;
      await expectLater(
        quota.capture(_command(0)),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.resourceExhausted,
          ),
        ),
      );
      expect(quota.snapshot.phase, CourtsideRecoveryPhase.captureDisabled);
      expect(quota.snapshot.operations, isEmpty);
    },
  );

  test(
    'persisted corruption disables capture and never invents a saved state',
    () async {
      final store = FaultInjectingMemoryStore();
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));
      final entryKey = store.unsafeSnapshot().keys.singleWhere(
        (key) => key.startsWith('entry/'),
      );
      store.unsafeWrite(entryKey, '{');

      await expectLater(
        orchestrator.recoverForeground(now: DateTime.utc(2026, 9, 11, 14, 1)),
        throwsA(isA<LocalJournalException>()),
      );

      expect(
        orchestrator.snapshot.phase,
        CourtsideRecoveryPhase.captureDisabled,
      );
      expect(
        orchestrator.snapshot.captureAvailability,
        LocalCaptureAvailability.disabledIntegrityFailure,
      );
    },
  );

  test(
    'sign-out preserves unsent work for the same exact account and package',
    () async {
      final store = FaultInjectingMemoryStore();
      final first = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await first.initialize();
      await first.capture(_command(0));
      await first.closeForSignOut();
      expect(first.snapshot.phase, CourtsideRecoveryPhase.signedOut);

      final second = CourtsideRecoveryOrchestrator(
        repository: _repository(store),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (request) => CourtsideDeliveryAccepted(_receipt(request)),
        ),
      );
      await second.initialize();
      expect(second.snapshot.operations.single.commandId, 'command_0');
      expect(
        second.snapshot.operations.single.state,
        JournalDeliveryState.savedOnDevice,
      );
    },
  );

  test(
    'deletion requires exact manifest consent and never silently discards',
    () async {
      final orchestrator = CourtsideRecoveryOrchestrator(
        repository: _repository(FaultInjectingMemoryStore()),
        material: _material(),
        serverAdapter: _ServerAdapter(
          (_) => const CourtsideDeliveryResponseUnknown(),
        ),
      );
      await orchestrator.initialize();
      await orchestrator.capture(_command(0));
      await orchestrator.recoverForeground(
        now: DateTime.utc(2026, 9, 11, 14, 1),
      );
      final manifest = await orchestrator.createDeletionManifest(
        manifestId: 'manifest_1',
        createdAt: DateTime.utc(2026, 9, 11, 14, 2),
      );
      final consent = LocalDeletionConsent(
        consentId: 'consent_1',
        manifestId: manifest.manifestId,
        manifestChecksum: manifest.checksum,
        deviceSessionId: manifest.deviceSessionId,
        grantedAt: DateTime.utc(2026, 9, 11, 14, 3),
      );

      final plan = await orchestrator.reconcileDeletion(manifest, consent);
      expect(plan.consentAndManifestVerified, isTrue);
      expect(plan.containsResponseUnknownWork, isTrue);
      expect(plan.localJournalDiscardPermitted, isFalse);
      expect(plan.identities.single.commandId, 'command_0');

      final wrongConsent = LocalDeletionConsent(
        consentId: 'consent_2',
        manifestId: manifest.manifestId,
        manifestChecksum: _hashB,
        deviceSessionId: manifest.deviceSessionId,
        grantedAt: DateTime.utc(2026, 9, 11, 14, 3),
      );
      await expectLater(
        orchestrator.reconcileDeletion(manifest, wrongConsent),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.consentRequired,
          ),
        ),
      );
      expect(orchestrator.snapshot.operations, hasLength(1));
    },
  );

  test('preparation refuses an unaccepted calculator', () {
    expect(
      () => CourtsidePreparationMaterial(
        bootstrap: _bootstrap(),
        packageId: 'package_1',
        workspaceId: 'workspace_1',
        deviceSessionId: 'device_1',
        assignmentId: 'assignment_1',
        journalReducerVersion: 'reducer_v1',
        calculatorVersion: 'calculator_v2',
        rulesProfileId: 'rules_v1',
        competitionPolicyVersion: 'policy_v1',
        rosterSnapshotId: 'roster_snapshot_1',
        rosterSnapshotHash: _hashA,
        acceptedServerSequence: const Fact.notApplicable(
          reasonCode: 'no_server_operations',
        ),
        acceptedJournalHead: 'head_0',
        acceptedJournalHash: _hashB,
        preparedAt: DateTime.utc(2026, 9, 11, 14),
      ),
      throwsA(isA<CourtsideRecoveryException>()),
    );
  });
}
