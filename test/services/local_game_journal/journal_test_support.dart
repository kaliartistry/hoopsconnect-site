import 'package:hoops_connect/models/official_stats/domain_contracts.dart';
import 'package:hoops_connect/models/official_stats/domain_enums.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_limits.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:hoops_connect/services/local_game_journal/journal_store.dart';

const hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

JournalPartition testPartition({
  String accountId = 'account_1',
  String seasonId = 'season_2026',
  String workspaceId = 'workspace_1',
}) => JournalPartition(
  actorAccountId: accountId,
  scope: GameScope(
    associationId: 'jba',
    competitionId: 'nbl',
    seasonId: seasonId,
    divisionId: 'division_1',
    phaseId: 'regular',
    gameId: 'game_1',
  ),
  workspaceId: workspaceId,
);

PreparedGameRecoveryPackage testPackage(
  JournalPartition partition, {
  String deviceSessionId = 'device_1',
  int writerEpoch = 1,
  Fact<int> acceptedServerSequence = const Fact.notApplicable(
    reasonCode: 'no_server_operations',
  ),
}) => PreparedGameRecoveryPackage.create(
  packageId: 'package_1',
  partition: partition,
  deviceSessionId: deviceSessionId,
  writerEpoch: writerEpoch,
  journalReducerVersion: 'reducer_v1',
  calculatorVersion: 'calculator_v1',
  rulesProfileId: 'rules_v1',
  competitionPolicyVersion: 'policy_v1',
  assignmentId: 'assignment_1',
  assignmentVersion: 1,
  rosterSnapshotId: 'roster_snapshot_1',
  rosterSnapshotHash: hashA,
  acceptedServerSequence: acceptedServerSequence,
  acceptedJournalHead: 'head_0',
  acceptedJournalHash: hashB,
  preparedAt: DateTime.utc(2026, 9, 8, 12),
);

LocalGameJournalOperation testOperation({
  required JournalPartition partition,
  required int sequence,
  required Fact<String> previousHash,
  String? operationId,
  String? commandId,
  String deviceSessionId = 'device_1',
  int writerEpoch = 1,
  String reducerVersion = 'reducer_v1',
  String rulesProfileId = 'rules_v1',
  Map<String, Object?>? payload,
  JournalOperationType operationType = JournalOperationType.setPlayerCounter,
  Fact<int> gamePeriod = const Fact.known(1),
  Fact<int> gameClockPosition = const Fact.known(345000),
}) => LocalGameJournalOperation.create(
  partition: partition,
  operationId: operationId ?? 'operation_$sequence',
  commandId: commandId ?? 'command_$sequence',
  deviceSessionId: deviceSessionId,
  writerEpoch: writerEpoch,
  localSequence: sequence,
  previousOperationHash: previousHash,
  expectedServerHead: 'head_0',
  reducerVersion: reducerVersion,
  rulesProfileId: rulesProfileId,
  operationType: operationType,
  payload:
      payload ??
      <String, Object?>{
        'delta': 1,
        'participantId': 'participant_7',
        'stat': 'twoPointMade',
      },
  gamePeriod: gamePeriod,
  gameClockPosition: gameClockPosition,
  logicalPlayOrder: sequence,
  clientObservedAt: DateTime.utc(2026, 9, 8, 12, 0, sequence),
);

Map<String, Object?> payloadForOperationType(
  JournalOperationType type,
  int sequence,
) => switch (type) {
  JournalOperationType.setParticipantStatus => {
    'participantId': 'participant_7',
    'status': 'active',
  },
  JournalOperationType.setPlayerCounter => {
    'delta': 1,
    'participantId': 'participant_7',
    'stat': 'twoPointMade',
  },
  JournalOperationType.setTeamOnlyCounter => {
    'delta': 1,
    'stat': 'turnovers',
    'teamEntryId': 'team_1',
  },
  JournalOperationType.setPeriodScore => {
    'score': sequence,
    'teamEntryId': 'team_1',
  },
  JournalOperationType.setClock => {'clockState': 'stopped'},
  JournalOperationType.recordDiscipline => {
    'chargedPartyId': 'participant_7',
    'chargedPartyType': 'player',
    'incidentId': 'incident_$sequence',
    'scoresheetCode': 'P',
  },
  JournalOperationType.setLineup => {
    'participantIds': ['participant_7'],
    'teamEntryId': 'team_1',
  },
  JournalOperationType.attachEvidence => {
    'evidenceKind': 'scoreboard',
    'evidenceRef': 'evidence_$sequence',
  },
};

OperationReceiptContract testReceipt(LocalGameJournalOperation operation) =>
    OperationReceiptContract(
      receiptId: 'receipt_${operation.localSequence}',
      scope: operation.partition.scope,
      workspaceId: operation.partition.workspaceId,
      operationId: operation.operationId,
      commandId: operation.commandId,
      actorAccountId: operation.partition.actorAccountId,
      commandKind: operation.operationType,
      requestHash: operation.requestHash,
      serverSequence: operation.localSequence,
      acceptedJournalHead: 'head_${operation.localSequence + 1}',
      acceptedJournalHash: operation.requestHash,
      writerEpoch: operation.writerEpoch,
      acceptedAt: DateTime.utc(2026, 9, 8, 12, 30, operation.localSequence),
    );

LocalJournalCompatibility testCompatibility() => LocalJournalCompatibility(
  acceptedReducerVersions: const {'reducer_v1'},
  acceptedCalculatorVersions: const {'calculator_v1'},
  acceptedRulesProfileIds: const {'rules_v1'},
);

final class FaultInjectingMemoryStore implements LocalGameJournalStore {
  Map<String, String> _records = {};
  bool _open = false;
  int? failAtPut;
  bool failAfterCommitOnce = false;
  Future<void>? waitBeforeNextTransactionAction;
  void Function()? onBeforeNextTransactionWait;

  @override
  LocalStorageCapability get capability => LocalStorageCapability(
    availability: _open
        ? LocalCaptureAvailability.ready
        : LocalCaptureAvailability.disabledCapabilityUnproven,
    adapter: 'test-memory',
    durable: _open,
    transactional: _open,
    encryptedAtRestClaimed: false,
    localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
    reasonCode: _open ? null : LocalJournalErrorCode.storageCapabilityUnproven,
  );

  @override
  Future<LocalStorageCapability> open() async {
    _open = true;
    return capability;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(LocalJournalStoreTransaction transaction) action,
  ) async {
    if (!_open) {
      throw LocalJournalException(
        LocalJournalErrorCode.storageUnavailable,
        'test store is closed',
      );
    }
    final waitBeforeAction = waitBeforeNextTransactionAction;
    waitBeforeNextTransactionAction = null;
    if (waitBeforeAction != null) {
      final onBeforeWait = onBeforeNextTransactionWait;
      onBeforeNextTransactionWait = null;
      onBeforeWait?.call();
      await waitBeforeAction;
    }
    final working = Map<String, String>.from(_records);
    final transaction = _MemoryTransaction(working, failAtPut);
    late T result;
    try {
      result = await action(transaction);
    } catch (_) {
      if (transaction.putCount > 0) failAtPut = null;
      rethrow;
    }
    _records = working;
    if (transaction.putCount > 0) failAtPut = null;
    if (failAfterCommitOnce && transaction.putCount > 0) {
      failAfterCommitOnce = false;
      throw LocalJournalException(
        LocalJournalErrorCode.transactionAborted,
        'injected lost success response after commit',
      );
    }
    return result;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  String? unsafeRead(String key) => _records[key];

  Map<String, String> unsafeSnapshot() =>
      Map.unmodifiable(Map<String, String>.from(_records));

  void unsafeWrite(String key, String value) => _records[key] = value;

  void unsafeDelete(String key) => _records.remove(key);
}

final class _MemoryTransaction implements LocalJournalStoreTransaction {
  final Map<String, String> records;
  final int? failAtPut;
  int _putCount = 0;

  _MemoryTransaction(this.records, this.failAtPut);

  int get putCount => _putCount;

  @override
  Future<String?> get(String key) async => records[key];

  @override
  Future<void> put(String key, String value) async {
    _putCount++;
    if (_putCount == failAtPut) {
      throw LocalJournalException(
        LocalJournalErrorCode.transactionAborted,
        'injected put failure',
      );
    }
    records[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    records.remove(key);
  }

  @override
  Future<List<LocalKeyValue>> scanPrefix(
    String prefix, {
    String? startAfter,
    required int limit,
  }) async {
    final keys =
        records.keys
            .where(
              (key) =>
                  key.startsWith(prefix) &&
                  (startAfter == null || key.compareTo(startAfter) > 0),
            )
            .toList()
          ..sort();
    return keys
        .take(limit)
        .map((key) => LocalKeyValue(key, records[key]!))
        .toList(growable: false);
  }
}
