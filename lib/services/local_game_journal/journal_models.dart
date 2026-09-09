import 'dart:convert';

import '../../models/official_stats/canonical_encoding.dart';
import '../../models/official_stats/command_contract.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../models/official_stats/fact.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_validation.dart';

final class JournalPartition {
  final String actorAccountId;
  final GameScope scope;
  final String workspaceId;

  JournalPartition({
    required this.actorAccountId,
    required this.scope,
    required this.workspaceId,
  }) {
    LocalJournalValidation.requireId('actorAccountId', actorAccountId);
    LocalJournalValidation.requireId('workspaceId', workspaceId);
  }

  String get key => '$actorAccountId/${scope.key}/$workspaceId';

  Map<String, Object?> toContractMap() => {
    'actorAccountId': actorAccountId,
    'scope': scope.toContractMap(),
    'workspaceId': workspaceId,
  };

  factory JournalPartition.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {
      'actorAccountId',
      'scope',
      'workspaceId',
    });
    return JournalPartition(
      actorAccountId: LocalJournalValidation.requireId(
        'actorAccountId',
        map['actorAccountId'],
      ),
      scope: LocalJournalValidation.decodeScope(map['scope']),
      workspaceId: LocalJournalValidation.requireId(
        'workspaceId',
        map['workspaceId'],
      ),
    );
  }
}

/// Immutable operation evidence. Delivery state is deliberately stored in a
/// separate [LocalJournalDelivery] record, as required by Packet 01.
final class LocalGameJournalOperation {
  final JournalPartition partition;
  final String operationId;
  final String commandId;
  final String deviceSessionId;
  final int writerEpoch;
  final int localSequence;
  final Fact<String> previousOperationHash;
  final String expectedServerHead;
  final int operationSchemaVersion;
  final String reducerVersion;
  final String rulesProfileId;
  final JournalOperationType operationType;
  final Map<String, Object?> payload;
  final String payloadHash;
  final Fact<int> gamePeriod;
  final Fact<int> gameClockPosition;
  final int logicalPlayOrder;
  final DateTime clientObservedAt;
  final String semanticHash;
  final String requestHash;

  LocalGameJournalOperation._({
    required this.partition,
    required this.operationId,
    required this.commandId,
    required this.deviceSessionId,
    required this.writerEpoch,
    required this.localSequence,
    required this.previousOperationHash,
    required this.expectedServerHead,
    required this.operationSchemaVersion,
    required this.reducerVersion,
    required this.rulesProfileId,
    required this.operationType,
    required this.payload,
    required this.payloadHash,
    required this.gamePeriod,
    required this.gameClockPosition,
    required this.logicalPlayOrder,
    required this.clientObservedAt,
    required this.semanticHash,
    required this.requestHash,
  });

  factory LocalGameJournalOperation.create({
    required JournalPartition partition,
    required String operationId,
    required String commandId,
    required String deviceSessionId,
    required int writerEpoch,
    required int localSequence,
    required Fact<String> previousOperationHash,
    required String expectedServerHead,
    int operationSchemaVersion = LocalGameJournalLimits.operationSchemaVersion,
    required String reducerVersion,
    required String rulesProfileId,
    required JournalOperationType operationType,
    required Map<String, Object?> payload,
    required Fact<int> gamePeriod,
    required Fact<int> gameClockPosition,
    required int logicalPlayOrder,
    required DateTime clientObservedAt,
  }) {
    final frozenPayload = LocalJournalValidation.freezePayload(payload);
    LocalJournalValidation.validateOperationPayload(
      operationType,
      frozenPayload,
    );
    _validateJournalOrderingFacts(gamePeriod, gameClockPosition);
    final normalizedObservedAt = LocalJournalValidation.normalizeTimestamp(
      clientObservedAt,
    );
    final semanticInput = <String, Object?>{
      // These keys intentionally match Packet 01's canonical hash contract.
      'clockRemainingMs': gameClockPosition.toContractMap((value) => value),
      'logicalPlayOrder': logicalPlayOrder,
      'operationSchemaVersion': operationSchemaVersion,
      'operationType': operationType.name,
      'payload': frozenPayload,
      'periodNumber': gamePeriod.toContractMap((value) => value),
      'reducerVersion': reducerVersion,
      'rulesetVersion': rulesProfileId,
      'scope': partition.scope.toContractMap(),
      'workspaceId': partition.workspaceId,
    };
    final semanticHash = OfficialStatCanonicalEncoding.sha256Hex(semanticInput);
    final requestInput = <String, Object?>{
      'actorAccountId': partition.actorAccountId,
      'deviceSessionId': deviceSessionId,
      'expectedServerHead': expectedServerHead,
      'localSequence': localSequence,
      'operationId': operationId,
      'previousOperationHash': previousOperationHash.toContractMap(
        (value) => value,
      ),
      'semanticHash': semanticHash,
      'writerEpoch': writerEpoch,
    };
    final operation = LocalGameJournalOperation._(
      partition: partition,
      operationId: operationId,
      commandId: commandId,
      deviceSessionId: deviceSessionId,
      writerEpoch: writerEpoch,
      localSequence: localSequence,
      previousOperationHash: previousOperationHash,
      expectedServerHead: expectedServerHead,
      operationSchemaVersion: operationSchemaVersion,
      reducerVersion: reducerVersion,
      rulesProfileId: rulesProfileId,
      operationType: operationType,
      payload: frozenPayload,
      payloadHash: OfficialStatCanonicalEncoding.sha256Hex(frozenPayload),
      gamePeriod: gamePeriod,
      gameClockPosition: gameClockPosition,
      logicalPlayOrder: logicalPlayOrder,
      clientObservedAt: normalizedObservedAt,
      semanticHash: semanticHash,
      requestHash: OfficialStatCanonicalEncoding.sha256Hex(requestInput),
    );
    operation._validate();
    return operation;
  }

  factory LocalGameJournalOperation.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {
      'partition',
      'operationId',
      'commandId',
      'deviceSessionId',
      'writerEpoch',
      'localSequence',
      'previousOperationHash',
      'expectedServerHead',
      'operationSchemaVersion',
      'reducerVersion',
      'rulesProfileId',
      'operationType',
      'payload',
      'payloadHash',
      'gamePeriod',
      'gameClockPosition',
      'logicalPlayOrder',
      'clientObservedAt',
      'semanticHash',
      'requestHash',
    });
    final rawPartition = map['partition'];
    final rawPayload = map['payload'];
    if (rawPartition is! Map || rawPayload is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'partition and payload must be objects',
      );
    }
    final typeName = map['operationType'];
    final operationType = JournalOperationType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (operationType == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Unknown journal operation type',
        {'operationType': typeName},
      );
    }
    final operation = LocalGameJournalOperation._(
      partition: JournalPartition.fromContractMap(
        Map<String, Object?>.from(rawPartition),
      ),
      operationId: LocalJournalValidation.requireId(
        'operationId',
        map['operationId'],
      ),
      commandId: LocalJournalValidation.requireId(
        'commandId',
        map['commandId'],
      ),
      deviceSessionId: LocalJournalValidation.requireId(
        'deviceSessionId',
        map['deviceSessionId'],
      ),
      writerEpoch: LocalJournalValidation.requireSafeInteger(
        'writerEpoch',
        map['writerEpoch'],
      ),
      localSequence: LocalJournalValidation.requireSafeInteger(
        'localSequence',
        map['localSequence'],
      ),
      previousOperationHash: LocalJournalValidation.decodeStringFact(
        'previousOperationHash',
        map['previousOperationHash'],
        requireHash: true,
      ),
      expectedServerHead: LocalJournalValidation.requireId(
        'expectedServerHead',
        map['expectedServerHead'],
      ),
      operationSchemaVersion: LocalJournalValidation.requireSafeInteger(
        'operationSchemaVersion',
        map['operationSchemaVersion'],
        minimum: 1,
      ),
      reducerVersion: LocalJournalValidation.requireId(
        'reducerVersion',
        map['reducerVersion'],
      ),
      rulesProfileId: LocalJournalValidation.requireId(
        'rulesProfileId',
        map['rulesProfileId'],
      ),
      operationType: operationType,
      payload: LocalJournalValidation.freezePayload(
        Map<String, Object?>.from(rawPayload),
      ),
      payloadHash: LocalJournalValidation.requireHash(
        'payloadHash',
        map['payloadHash'],
      ),
      gamePeriod: LocalJournalValidation.decodeIntFact(
        'gamePeriod',
        map['gamePeriod'],
        minimum: 1,
        maximum: LocalGameJournalLimits.maxPeriodNumber,
      ),
      gameClockPosition: LocalJournalValidation.decodeIntFact(
        'gameClockPosition',
        map['gameClockPosition'],
        maximum: LocalGameJournalLimits.maxClockRemainingMs,
      ),
      logicalPlayOrder: LocalJournalValidation.requireSafeInteger(
        'logicalPlayOrder',
        map['logicalPlayOrder'],
      ),
      clientObservedAt: LocalJournalValidation.requireTimestamp(
        'clientObservedAt',
        map['clientObservedAt'],
      ),
      semanticHash: LocalJournalValidation.requireHash(
        'semanticHash',
        map['semanticHash'],
      ),
      requestHash: LocalJournalValidation.requireHash(
        'requestHash',
        map['requestHash'],
      ),
    );
    operation._validate();
    return operation;
  }

  void _validate() {
    if (operationSchemaVersion !=
        LocalGameJournalLimits.operationSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Unsupported operation schema version',
        {'operationSchemaVersion': operationSchemaVersion},
      );
    }
    // The Packet 01 command contract intentionally permits a wider ordering
    // domain. Packet 07 persists a narrower bounded representation, so its
    // factory and decoder must share these exact limits and reason-code rules.
    _validateJournalOrderingFacts(gamePeriod, gameClockPosition);
    final payloadDigest = OfficialStatCanonicalEncoding.sha256Hex(payload);
    if (payloadDigest != payloadHash) {
      throw LocalJournalException(
        LocalJournalErrorCode.hashMismatch,
        'payloadHash does not match the canonical payload',
      );
    }
    LocalJournalValidation.validateOperationPayload(operationType, payload);
    try {
      JournalOperationContract(
        scope: partition.scope,
        workspaceId: partition.workspaceId,
        operationId: operationId,
        commandId: commandId,
        actorAccountId: partition.actorAccountId,
        deviceSessionId: deviceSessionId,
        writerEpoch: writerEpoch,
        localSequence: localSequence,
        previousOperationHash: previousOperationHash,
        expectedServerHead: expectedServerHead,
        operationSchemaVersion: operationSchemaVersion,
        reducerVersion: reducerVersion,
        rulesetVersion: rulesProfileId,
        operationType: operationType,
        periodNumber: gamePeriod,
        clockRemainingMs: gameClockPosition,
        logicalPlayOrder: logicalPlayOrder,
        payload: payload,
        semanticHash: semanticHash,
        requestHash: requestHash,
        clientObservedAt: clientObservedAt,
      );
    } on FormatException catch (error) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        error.message,
      );
    } on ArgumentError catch (error) {
      throw LocalJournalException(
        LocalJournalErrorCode.hashMismatch,
        error.message?.toString() ?? 'Operation contract validation failed',
      );
    }
    final byteCount = utf8.encode(canonicalJson).length;
    if (byteCount > LocalGameJournalLimits.maxOperationBytes) {
      throw LocalJournalException(
        LocalJournalErrorCode.resourceExhausted,
        'Canonical operation exceeds the supported size',
        {'actualBytes': byteCount},
      );
    }
  }

  static void _validateJournalOrderingFacts(
    Fact<int> gamePeriod,
    Fact<int> gameClockPosition,
  ) {
    LocalJournalValidation.decodeIntFact(
      'gamePeriod',
      gamePeriod.toContractMap((value) => value),
      minimum: 1,
      maximum: LocalGameJournalLimits.maxPeriodNumber,
    );
    LocalJournalValidation.decodeIntFact(
      'gameClockPosition',
      gameClockPosition.toContractMap((value) => value),
      maximum: LocalGameJournalLimits.maxClockRemainingMs,
    );
  }

  Map<String, Object?> toContractMap() => {
    'clientObservedAt': clientObservedAt,
    'commandId': commandId,
    'deviceSessionId': deviceSessionId,
    'expectedServerHead': expectedServerHead,
    'gameClockPosition': gameClockPosition.toContractMap((value) => value),
    'gamePeriod': gamePeriod.toContractMap((value) => value),
    'localSequence': localSequence,
    'logicalPlayOrder': logicalPlayOrder,
    'operationId': operationId,
    'operationSchemaVersion': operationSchemaVersion,
    'operationType': operationType.name,
    'partition': partition.toContractMap(),
    'payload': payload,
    'payloadHash': payloadHash,
    'previousOperationHash': previousOperationHash.toContractMap(
      (value) => value,
    ),
    'reducerVersion': reducerVersion,
    'requestHash': requestHash,
    'rulesProfileId': rulesProfileId,
    'semanticHash': semanticHash,
    'writerEpoch': writerEpoch,
  };

  String get canonicalJson =>
      OfficialStatCanonicalEncoding.encode(toContractMap());

  int get byteCount => utf8.encode(canonicalJson).length;
}

enum LocalPauseReason {
  authenticationRequired,
  permissionDenied,
  unsupportedSchema,
  serverConflict,
  staleWriterEpoch,
  resourceExhausted,
  operatorResolutionRequired,
}

final class RetryPolicyMetadata {
  final int policyVersion;
  final int baseDelayMs;
  final int maximumDelayMs;
  final int jitterBasisPoints;

  const RetryPolicyMetadata({
    this.policyVersion = LocalGameJournalLimits.retryPolicyVersion,
    this.baseDelayMs = LocalGameJournalLimits.retryBaseDelayMs,
    this.maximumDelayMs = LocalGameJournalLimits.retryMaximumDelayMs,
    required this.jitterBasisPoints,
  });

  Map<String, Object?> toContractMap() => {
    'baseDelayMs': baseDelayMs,
    'jitterBasisPoints': jitterBasisPoints,
    'maximumDelayMs': maximumDelayMs,
    'policyVersion': policyVersion,
  };

  factory RetryPolicyMetadata.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {
      'policyVersion',
      'baseDelayMs',
      'maximumDelayMs',
      'jitterBasisPoints',
    });
    final value = RetryPolicyMetadata(
      policyVersion: LocalJournalValidation.requireSafeInteger(
        'policyVersion',
        map['policyVersion'],
        minimum: 1,
      ),
      baseDelayMs: LocalJournalValidation.requireSafeInteger(
        'baseDelayMs',
        map['baseDelayMs'],
        minimum: 1,
        maximum: LocalGameJournalLimits.retryMaximumDelayMs,
      ),
      maximumDelayMs: LocalJournalValidation.requireSafeInteger(
        'maximumDelayMs',
        map['maximumDelayMs'],
        minimum: 1,
        maximum: LocalGameJournalLimits.retryMaximumDelayMs,
      ),
      jitterBasisPoints: LocalJournalValidation.requireSafeInteger(
        'jitterBasisPoints',
        map['jitterBasisPoints'],
        minimum: LocalGameJournalLimits.retryMinimumJitterBasisPoints,
        maximum: LocalGameJournalLimits.retryMaximumJitterBasisPoints,
      ),
    );
    if (value.policyVersion != LocalGameJournalLimits.retryPolicyVersion ||
        value.maximumDelayMs < value.baseDelayMs) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Unsupported retry policy metadata',
      );
    }
    return value;
  }
}

final class LocalJournalDelivery {
  final String operationId;
  final JournalDeliveryState state;
  final int retryCount;
  final Fact<DateTime> nextAttemptAt;
  final Fact<String> lastErrorCode;
  final Fact<String> pauseReason;
  final Fact<OperationReceiptContract> serverReceipt;
  final RetryPolicyMetadata retryPolicy;

  LocalJournalDelivery({
    required this.operationId,
    required this.state,
    required this.retryCount,
    required this.nextAttemptAt,
    required this.lastErrorCode,
    required this.pauseReason,
    required this.serverReceipt,
    required this.retryPolicy,
  }) {
    LocalJournalValidation.requireId('operationId', operationId);
    LocalJournalValidation.requireSafeInteger('retryCount', retryCount);
    if (state == JournalDeliveryState.accepted &&
        serverReceipt is! KnownFact<OperationReceiptContract>) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'Accepted delivery requires a durable server receipt',
      );
    }
    if (state != JournalDeliveryState.accepted &&
        serverReceipt is KnownFact<OperationReceiptContract>) {
      throw LocalJournalException(
        LocalJournalErrorCode.receiptMismatch,
        'A durable server receipt requires accepted delivery state',
      );
    }
    if (state == JournalDeliveryState.needsAttention &&
        pauseReason is! KnownFact<String>) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidStateTransition,
        'Needs-attention delivery requires a typed pause reason',
      );
    }
    for (final entry in <String, Fact<Object?>>{
      'nextAttemptAt': nextAttemptAt,
      'lastErrorCode': lastErrorCode,
      'pauseReason': pauseReason,
      'serverReceipt': serverReceipt,
    }.entries) {
      LocalJournalValidation.requireReasonCode(
        '${entry.key}.reasonCode',
        entry.value.reasonCode,
      );
    }
    final error = lastErrorCode.valueOrNull;
    if (error != null &&
        !CommandErrorCode.values.any((value) => value.name == error)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Delivery last-error code is unsupported',
      );
    }
    final pause = pauseReason.valueOrNull;
    if (pause != null &&
        !LocalPauseReason.values.any((value) => value.name == pause)) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Delivery pause reason is unsupported',
      );
    }
    final receipt = serverReceipt.valueOrNull;
    if (receipt != null) operationReceiptToMap(receipt);
  }

  factory LocalJournalDelivery.savedOnDevice(String operationId) =>
      LocalJournalDelivery(
        operationId: operationId,
        state: JournalDeliveryState.savedOnDevice,
        retryCount: 0,
        nextAttemptAt: const Fact.notApplicable(reasonCode: 'not_scheduled'),
        lastErrorCode: const Fact.notApplicable(reasonCode: 'no_error'),
        pauseReason: const Fact.notApplicable(reasonCode: 'not_paused'),
        serverReceipt: const Fact.notApplicable(reasonCode: 'not_accepted'),
        retryPolicy: const RetryPolicyMetadata(jitterBasisPoints: 10000),
      );

  Map<String, Object?> toContractMap() => {
    'lastErrorCode': lastErrorCode.toContractMap((value) => value),
    'nextAttemptAt': nextAttemptAt.toContractMap((value) => value),
    'operationId': operationId,
    'pauseReason': pauseReason.toContractMap((value) => value),
    'retryCount': retryCount,
    'retryPolicy': retryPolicy.toContractMap(),
    'serverReceipt': serverReceipt.toContractMap(
      (value) => operationReceiptToMap(value),
    ),
    'state': state.name,
  };

  factory LocalJournalDelivery.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {
      'operationId',
      'state',
      'retryCount',
      'nextAttemptAt',
      'lastErrorCode',
      'pauseReason',
      'serverReceipt',
      'retryPolicy',
    });
    final state = JournalDeliveryState.values
        .where((value) => value.name == map['state'])
        .firstOrNull;
    final retry = map['retryPolicy'];
    if (state == null || retry is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Delivery state or retry policy is invalid',
      );
    }
    return LocalJournalDelivery(
      operationId: LocalJournalValidation.requireId(
        'operationId',
        map['operationId'],
      ),
      state: state,
      retryCount: LocalJournalValidation.requireSafeInteger(
        'retryCount',
        map['retryCount'],
      ),
      nextAttemptAt: _decodeDateFact('nextAttemptAt', map['nextAttemptAt']),
      lastErrorCode: LocalJournalValidation.decodeStringFact(
        'lastErrorCode',
        map['lastErrorCode'],
      ),
      pauseReason: LocalJournalValidation.decodeStringFact(
        'pauseReason',
        map['pauseReason'],
      ),
      serverReceipt: _decodeReceiptFact(map['serverReceipt']),
      retryPolicy: RetryPolicyMetadata.fromContractMap(
        Map<String, Object?>.from(retry),
      ),
    );
  }
}

enum WorkspaceSubmissionState { captureOpen, submissionQueued, submitted }

/// Persisted local recovery posture. This is deliberately separate from the
/// server-owned workspace lifecycle in Packet 01.
enum LocalWorkspaceRecoveryState { active, conflictBranch }

final class LocalWorkspaceCheckpoint {
  final int localSchemaVersion;
  final JournalPartition partition;
  final int writerEpoch;
  final int nextLocalSequence;
  final Fact<int> lastLocalSequence;
  final Fact<String> lastOperationHash;
  final Fact<int> prunedThroughSequence;
  final Fact<String> prunedThroughHash;
  final Fact<int> acceptedThroughSequence;
  final Fact<String> acceptedJournalHead;
  final Fact<String> acceptedJournalHash;
  final int retainedOperationCount;
  final int retainedOperationBytes;
  final WorkspaceSubmissionState submissionState;
  final LocalWorkspaceRecoveryState recoveryState;
  final Fact<String> preparationPackageChecksum;
  final DateTime updatedAt;

  LocalWorkspaceCheckpoint({
    this.localSchemaVersion = LocalGameJournalLimits.localSchemaVersion,
    required this.partition,
    required this.writerEpoch,
    required this.nextLocalSequence,
    required this.lastLocalSequence,
    required this.lastOperationHash,
    required this.prunedThroughSequence,
    required this.prunedThroughHash,
    required this.acceptedThroughSequence,
    required this.acceptedJournalHead,
    required this.acceptedJournalHash,
    required this.retainedOperationCount,
    required this.retainedOperationBytes,
    required this.submissionState,
    this.recoveryState = LocalWorkspaceRecoveryState.active,
    required this.preparationPackageChecksum,
    required DateTime updatedAt,
  }) : updatedAt = LocalJournalValidation.normalizeTimestamp(updatedAt) {
    if (localSchemaVersion != LocalGameJournalLimits.localSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Unsupported local checkpoint schema',
      );
    }
    LocalJournalValidation.requireSafeInteger('writerEpoch', writerEpoch);
    LocalJournalValidation.requireSafeInteger(
      'nextLocalSequence',
      nextLocalSequence,
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    LocalJournalValidation.requireSafeInteger(
      'retainedOperationCount',
      retainedOperationCount,
      maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
    );
    LocalJournalValidation.requireSafeInteger(
      'retainedOperationBytes',
      retainedOperationBytes,
      maximum: LocalGameJournalLimits.maxWorkspaceBytes,
    );
    if (lastLocalSequence.valueOrNull case final last?) {
      LocalJournalValidation.requireSafeInteger(
        'lastLocalSequence',
        last,
        maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
      );
      if (nextLocalSequence != last + 1) {
        throw LocalJournalException(
          LocalJournalErrorCode.sequenceGap,
          'Checkpoint next sequence is not contiguous',
        );
      }
    } else if (nextLocalSequence != 0) {
      throw LocalJournalException(
        LocalJournalErrorCode.sequenceGap,
        'Empty checkpoint must begin at sequence zero',
      );
    }
    final pruned = prunedThroughSequence.valueOrNull;
    final accepted = acceptedThroughSequence.valueOrNull;
    if ((pruned == null) != (prunedThroughHash.valueOrNull == null) ||
        (accepted == null) != (acceptedJournalHead.valueOrNull == null) ||
        (accepted == null) != (acceptedJournalHash.valueOrNull == null)) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Checkpoint sequence facts and hash/head facts do not agree',
      );
    }
    if (pruned != null) {
      LocalJournalValidation.requireSafeInteger(
        'prunedThroughSequence',
        pruned,
        maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
      );
      if (lastLocalSequence.valueOrNull == null ||
          pruned > lastLocalSequence.valueOrNull!) {
        throw LocalJournalException(
          LocalJournalErrorCode.sequenceGap,
          'Checkpoint prune boundary exceeds the journal head',
        );
      }
    }
    if (accepted != null) {
      LocalJournalValidation.requireSafeInteger(
        'acceptedThroughSequence',
        accepted,
        maximum: LocalGameJournalLimits.maxOperationsPerWorkspace - 1,
      );
      if (lastLocalSequence.valueOrNull == null ||
          accepted > lastLocalSequence.valueOrNull! ||
          (pruned != null && pruned > accepted)) {
        throw LocalJournalException(
          LocalJournalErrorCode.sequenceGap,
          'Checkpoint accepted boundary is inconsistent with journal evidence',
        );
      }
    }
  }

  factory LocalWorkspaceCheckpoint.empty({
    required JournalPartition partition,
    required int writerEpoch,
    required DateTime now,
  }) => LocalWorkspaceCheckpoint(
    partition: partition,
    writerEpoch: writerEpoch,
    nextLocalSequence: 0,
    lastLocalSequence: const Fact.notApplicable(reasonCode: 'no_operations'),
    lastOperationHash: const Fact.notApplicable(reasonCode: 'genesis'),
    prunedThroughSequence: const Fact.notApplicable(reasonCode: 'not_pruned'),
    prunedThroughHash: const Fact.notApplicable(reasonCode: 'not_pruned'),
    acceptedThroughSequence: const Fact.notApplicable(
      reasonCode: 'not_accepted',
    ),
    acceptedJournalHead: const Fact.notApplicable(reasonCode: 'not_accepted'),
    acceptedJournalHash: const Fact.notApplicable(reasonCode: 'not_accepted'),
    retainedOperationCount: 0,
    retainedOperationBytes: 0,
    submissionState: WorkspaceSubmissionState.captureOpen,
    preparationPackageChecksum: const Fact.notApplicable(
      reasonCode: 'not_prepared',
    ),
    updatedAt: now,
  );

  Map<String, Object?> toContractMap() => {
    'acceptedJournalHash': acceptedJournalHash.toContractMap((value) => value),
    'acceptedJournalHead': acceptedJournalHead.toContractMap((value) => value),
    'acceptedThroughSequence': acceptedThroughSequence.toContractMap(
      (value) => value,
    ),
    'lastLocalSequence': lastLocalSequence.toContractMap((value) => value),
    'lastOperationHash': lastOperationHash.toContractMap((value) => value),
    'localSchemaVersion': localSchemaVersion,
    'nextLocalSequence': nextLocalSequence,
    'partition': partition.toContractMap(),
    'preparationPackageChecksum': preparationPackageChecksum.toContractMap(
      (value) => value,
    ),
    'prunedThroughHash': prunedThroughHash.toContractMap((value) => value),
    'prunedThroughSequence': prunedThroughSequence.toContractMap(
      (value) => value,
    ),
    'retainedOperationBytes': retainedOperationBytes,
    'retainedOperationCount': retainedOperationCount,
    'recoveryState': recoveryState.name,
    'submissionState': submissionState.name,
    'updatedAt': updatedAt,
    'writerEpoch': writerEpoch,
  };

  factory LocalWorkspaceCheckpoint.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {
      'localSchemaVersion',
      'partition',
      'writerEpoch',
      'nextLocalSequence',
      'lastLocalSequence',
      'lastOperationHash',
      'prunedThroughSequence',
      'prunedThroughHash',
      'acceptedThroughSequence',
      'acceptedJournalHead',
      'acceptedJournalHash',
      'retainedOperationCount',
      'retainedOperationBytes',
      'recoveryState',
      'submissionState',
      'preparationPackageChecksum',
      'updatedAt',
    });
    final rawPartition = map['partition'];
    final submissionState = WorkspaceSubmissionState.values
        .where((value) => value.name == map['submissionState'])
        .firstOrNull;
    final recoveryState = LocalWorkspaceRecoveryState.values
        .where((value) => value.name == map['recoveryState'])
        .firstOrNull;
    if (rawPartition is! Map ||
        submissionState == null ||
        recoveryState == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Checkpoint partition or submission state is invalid',
      );
    }
    return LocalWorkspaceCheckpoint(
      localSchemaVersion: LocalJournalValidation.requireSafeInteger(
        'localSchemaVersion',
        map['localSchemaVersion'],
        minimum: 1,
      ),
      partition: JournalPartition.fromContractMap(
        Map<String, Object?>.from(rawPartition),
      ),
      writerEpoch: LocalJournalValidation.requireSafeInteger(
        'writerEpoch',
        map['writerEpoch'],
      ),
      nextLocalSequence: LocalJournalValidation.requireSafeInteger(
        'nextLocalSequence',
        map['nextLocalSequence'],
      ),
      lastLocalSequence: LocalJournalValidation.decodeIntFact(
        'lastLocalSequence',
        map['lastLocalSequence'],
      ),
      lastOperationHash: LocalJournalValidation.decodeStringFact(
        'lastOperationHash',
        map['lastOperationHash'],
        requireHash: true,
      ),
      prunedThroughSequence: LocalJournalValidation.decodeIntFact(
        'prunedThroughSequence',
        map['prunedThroughSequence'],
      ),
      prunedThroughHash: LocalJournalValidation.decodeStringFact(
        'prunedThroughHash',
        map['prunedThroughHash'],
        requireHash: true,
      ),
      acceptedThroughSequence: LocalJournalValidation.decodeIntFact(
        'acceptedThroughSequence',
        map['acceptedThroughSequence'],
      ),
      acceptedJournalHead: LocalJournalValidation.decodeStringFact(
        'acceptedJournalHead',
        map['acceptedJournalHead'],
        requireIdentifier: true,
      ),
      acceptedJournalHash: LocalJournalValidation.decodeStringFact(
        'acceptedJournalHash',
        map['acceptedJournalHash'],
        requireHash: true,
      ),
      retainedOperationCount: LocalJournalValidation.requireSafeInteger(
        'retainedOperationCount',
        map['retainedOperationCount'],
        maximum: LocalGameJournalLimits.maxOperationsPerWorkspace,
      ),
      retainedOperationBytes: LocalJournalValidation.requireSafeInteger(
        'retainedOperationBytes',
        map['retainedOperationBytes'],
        maximum: LocalGameJournalLimits.maxWorkspaceBytes,
      ),
      submissionState: submissionState,
      recoveryState: recoveryState,
      preparationPackageChecksum: LocalJournalValidation.decodeStringFact(
        'preparationPackageChecksum',
        map['preparationPackageChecksum'],
        requireHash: true,
      ),
      updatedAt: LocalJournalValidation.requireTimestamp(
        'updatedAt',
        map['updatedAt'],
      ),
    );
  }
}

final class PreparedGameRecoveryPackage {
  final int packageVersion;
  final int localSchemaVersion;
  final String packageId;
  final JournalPartition partition;
  final String deviceSessionId;
  final int writerEpoch;
  final int operationSchemaVersion;
  final String journalReducerVersion;
  final String calculatorVersion;
  final String rulesProfileId;
  final String competitionPolicyVersion;
  final String assignmentId;
  final int assignmentVersion;
  final String rosterSnapshotId;
  final String rosterSnapshotHash;
  final Fact<int> acceptedServerSequence;
  final String acceptedJournalHead;
  final String acceptedJournalHash;
  final DateTime preparedAt;
  final String packageChecksum;

  PreparedGameRecoveryPackage._({
    required this.packageVersion,
    required this.localSchemaVersion,
    required this.packageId,
    required this.partition,
    required this.deviceSessionId,
    required this.writerEpoch,
    required this.operationSchemaVersion,
    required this.journalReducerVersion,
    required this.calculatorVersion,
    required this.rulesProfileId,
    required this.competitionPolicyVersion,
    required this.assignmentId,
    required this.assignmentVersion,
    required this.rosterSnapshotId,
    required this.rosterSnapshotHash,
    required this.acceptedServerSequence,
    required this.acceptedJournalHead,
    required this.acceptedJournalHash,
    required this.preparedAt,
    required this.packageChecksum,
  });

  factory PreparedGameRecoveryPackage.create({
    required String packageId,
    required JournalPartition partition,
    required String deviceSessionId,
    required int writerEpoch,
    int operationSchemaVersion = LocalGameJournalLimits.operationSchemaVersion,
    required String journalReducerVersion,
    required String calculatorVersion,
    required String rulesProfileId,
    required String competitionPolicyVersion,
    required String assignmentId,
    required int assignmentVersion,
    required String rosterSnapshotId,
    required String rosterSnapshotHash,
    required Fact<int> acceptedServerSequence,
    required String acceptedJournalHead,
    required String acceptedJournalHash,
    required DateTime preparedAt,
  }) {
    final normalized = LocalJournalValidation.normalizeTimestamp(preparedAt);
    final withoutChecksum = _packageMap(
      packageVersion: LocalGameJournalLimits.preparedGamePackageVersion,
      localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
      packageId: packageId,
      partition: partition,
      deviceSessionId: deviceSessionId,
      writerEpoch: writerEpoch,
      operationSchemaVersion: operationSchemaVersion,
      journalReducerVersion: journalReducerVersion,
      calculatorVersion: calculatorVersion,
      rulesProfileId: rulesProfileId,
      competitionPolicyVersion: competitionPolicyVersion,
      assignmentId: assignmentId,
      assignmentVersion: assignmentVersion,
      rosterSnapshotId: rosterSnapshotId,
      rosterSnapshotHash: rosterSnapshotHash,
      acceptedServerSequence: acceptedServerSequence,
      acceptedJournalHead: acceptedJournalHead,
      acceptedJournalHash: acceptedJournalHash,
      preparedAt: normalized,
    );
    final package = PreparedGameRecoveryPackage._(
      packageVersion: LocalGameJournalLimits.preparedGamePackageVersion,
      localSchemaVersion: LocalGameJournalLimits.localSchemaVersion,
      packageId: packageId,
      partition: partition,
      deviceSessionId: deviceSessionId,
      writerEpoch: writerEpoch,
      operationSchemaVersion: operationSchemaVersion,
      journalReducerVersion: journalReducerVersion,
      calculatorVersion: calculatorVersion,
      rulesProfileId: rulesProfileId,
      competitionPolicyVersion: competitionPolicyVersion,
      assignmentId: assignmentId,
      assignmentVersion: assignmentVersion,
      rosterSnapshotId: rosterSnapshotId,
      rosterSnapshotHash: rosterSnapshotHash,
      acceptedServerSequence: acceptedServerSequence,
      acceptedJournalHead: acceptedJournalHead,
      acceptedJournalHash: acceptedJournalHash,
      preparedAt: normalized,
      packageChecksum: OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum),
    );
    package._validate();
    return package;
  }

  void _validate() {
    for (final entry in {
      'packageId': packageId,
      'deviceSessionId': deviceSessionId,
      'journalReducerVersion': journalReducerVersion,
      'calculatorVersion': calculatorVersion,
      'rulesProfileId': rulesProfileId,
      'competitionPolicyVersion': competitionPolicyVersion,
      'assignmentId': assignmentId,
      'rosterSnapshotId': rosterSnapshotId,
      'acceptedJournalHead': acceptedJournalHead,
    }.entries) {
      LocalJournalValidation.requireId(entry.key, entry.value);
    }
    LocalJournalValidation.requireSafeInteger('writerEpoch', writerEpoch);
    LocalJournalValidation.requireSafeInteger(
      'assignmentVersion',
      assignmentVersion,
      minimum: 1,
    );
    LocalJournalValidation.decodeIntFact(
      'acceptedServerSequence',
      acceptedServerSequence.toContractMap((value) => value),
    );
    if (packageVersion != LocalGameJournalLimits.preparedGamePackageVersion ||
        localSchemaVersion != LocalGameJournalLimits.localSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Prepared package contract version is unsupported',
        {
          'packageVersion': packageVersion,
          'localSchemaVersion': localSchemaVersion,
        },
      );
    }
    if (operationSchemaVersion !=
        LocalGameJournalLimits.operationSchemaVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedSchemaVersion,
        'Prepared package operation schema is unsupported',
      );
    }
    LocalJournalValidation.requireHash(
      'rosterSnapshotHash',
      rosterSnapshotHash,
    );
    LocalJournalValidation.requireHash(
      'acceptedJournalHash',
      acceptedJournalHash,
    );
    LocalJournalValidation.requireHash('packageChecksum', packageChecksum);
    final expected = OfficialStatCanonicalEncoding.sha256Hex(
      _packageMap(
        packageVersion: packageVersion,
        localSchemaVersion: localSchemaVersion,
        packageId: packageId,
        partition: partition,
        deviceSessionId: deviceSessionId,
        writerEpoch: writerEpoch,
        operationSchemaVersion: operationSchemaVersion,
        journalReducerVersion: journalReducerVersion,
        calculatorVersion: calculatorVersion,
        rulesProfileId: rulesProfileId,
        competitionPolicyVersion: competitionPolicyVersion,
        assignmentId: assignmentId,
        assignmentVersion: assignmentVersion,
        rosterSnapshotId: rosterSnapshotId,
        rosterSnapshotHash: rosterSnapshotHash,
        acceptedServerSequence: acceptedServerSequence,
        acceptedJournalHead: acceptedJournalHead,
        acceptedJournalHash: acceptedJournalHash,
        preparedAt: preparedAt,
      ),
    );
    if (expected != packageChecksum) {
      throw LocalJournalException(
        LocalJournalErrorCode.hashMismatch,
        'Prepared package checksum does not match its contents',
      );
    }
    final bytes = utf8
        .encode(OfficialStatCanonicalEncoding.encode(toContractMap()))
        .length;
    if (bytes > LocalGameJournalLimits.maxPreparationPackageBytes) {
      throw LocalJournalException(
        LocalJournalErrorCode.resourceExhausted,
        'Prepared game package exceeds the supported size',
      );
    }
  }

  Map<String, Object?> toContractMap() => {
    ..._packageMap(
      packageVersion: packageVersion,
      localSchemaVersion: localSchemaVersion,
      packageId: packageId,
      partition: partition,
      deviceSessionId: deviceSessionId,
      writerEpoch: writerEpoch,
      operationSchemaVersion: operationSchemaVersion,
      journalReducerVersion: journalReducerVersion,
      calculatorVersion: calculatorVersion,
      rulesProfileId: rulesProfileId,
      competitionPolicyVersion: competitionPolicyVersion,
      assignmentId: assignmentId,
      assignmentVersion: assignmentVersion,
      rosterSnapshotId: rosterSnapshotId,
      rosterSnapshotHash: rosterSnapshotHash,
      acceptedServerSequence: acceptedServerSequence,
      acceptedJournalHead: acceptedJournalHead,
      acceptedJournalHash: acceptedJournalHash,
      preparedAt: preparedAt,
    ),
    'packageChecksum': packageChecksum,
  };

  factory PreparedGameRecoveryPackage.fromContractMap(
    Map<String, Object?> map,
  ) {
    LocalJournalValidation.exactKeys(map, const {
      'packageVersion',
      'localSchemaVersion',
      'packageId',
      'partition',
      'deviceSessionId',
      'writerEpoch',
      'operationSchemaVersion',
      'journalReducerVersion',
      'calculatorVersion',
      'rulesProfileId',
      'competitionPolicyVersion',
      'assignmentId',
      'assignmentVersion',
      'rosterSnapshotId',
      'rosterSnapshotHash',
      'acceptedServerSequence',
      'acceptedJournalHead',
      'acceptedJournalHash',
      'preparedAt',
      'packageChecksum',
    });
    final rawPartition = map['partition'];
    if (rawPartition is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'Prepared package partition must be an object',
      );
    }
    final package = PreparedGameRecoveryPackage._(
      packageVersion: LocalJournalValidation.requireSafeInteger(
        'packageVersion',
        map['packageVersion'],
        minimum: 1,
      ),
      localSchemaVersion: LocalJournalValidation.requireSafeInteger(
        'localSchemaVersion',
        map['localSchemaVersion'],
        minimum: 1,
      ),
      packageId: LocalJournalValidation.requireId(
        'packageId',
        map['packageId'],
      ),
      partition: JournalPartition.fromContractMap(
        Map<String, Object?>.from(rawPartition),
      ),
      deviceSessionId: LocalJournalValidation.requireId(
        'deviceSessionId',
        map['deviceSessionId'],
      ),
      writerEpoch: LocalJournalValidation.requireSafeInteger(
        'writerEpoch',
        map['writerEpoch'],
      ),
      operationSchemaVersion: LocalJournalValidation.requireSafeInteger(
        'operationSchemaVersion',
        map['operationSchemaVersion'],
        minimum: 1,
      ),
      journalReducerVersion: LocalJournalValidation.requireId(
        'journalReducerVersion',
        map['journalReducerVersion'],
      ),
      calculatorVersion: LocalJournalValidation.requireId(
        'calculatorVersion',
        map['calculatorVersion'],
      ),
      rulesProfileId: LocalJournalValidation.requireId(
        'rulesProfileId',
        map['rulesProfileId'],
      ),
      competitionPolicyVersion: LocalJournalValidation.requireId(
        'competitionPolicyVersion',
        map['competitionPolicyVersion'],
      ),
      assignmentId: LocalJournalValidation.requireId(
        'assignmentId',
        map['assignmentId'],
      ),
      assignmentVersion: LocalJournalValidation.requireSafeInteger(
        'assignmentVersion',
        map['assignmentVersion'],
        minimum: 1,
      ),
      rosterSnapshotId: LocalJournalValidation.requireId(
        'rosterSnapshotId',
        map['rosterSnapshotId'],
      ),
      rosterSnapshotHash: LocalJournalValidation.requireHash(
        'rosterSnapshotHash',
        map['rosterSnapshotHash'],
      ),
      acceptedServerSequence: LocalJournalValidation.decodeIntFact(
        'acceptedServerSequence',
        map['acceptedServerSequence'],
      ),
      acceptedJournalHead: LocalJournalValidation.requireId(
        'acceptedJournalHead',
        map['acceptedJournalHead'],
      ),
      acceptedJournalHash: LocalJournalValidation.requireHash(
        'acceptedJournalHash',
        map['acceptedJournalHash'],
      ),
      preparedAt: LocalJournalValidation.requireTimestamp(
        'preparedAt',
        map['preparedAt'],
      ),
      packageChecksum: LocalJournalValidation.requireHash(
        'packageChecksum',
        map['packageChecksum'],
      ),
    );
    package._validate();
    return package;
  }
}

Map<String, Object?> _packageMap({
  required int packageVersion,
  required int localSchemaVersion,
  required String packageId,
  required JournalPartition partition,
  required String deviceSessionId,
  required int writerEpoch,
  required int operationSchemaVersion,
  required String journalReducerVersion,
  required String calculatorVersion,
  required String rulesProfileId,
  required String competitionPolicyVersion,
  required String assignmentId,
  required int assignmentVersion,
  required String rosterSnapshotId,
  required String rosterSnapshotHash,
  required Fact<int> acceptedServerSequence,
  required String acceptedJournalHead,
  required String acceptedJournalHash,
  required DateTime preparedAt,
}) => {
  'acceptedJournalHash': acceptedJournalHash,
  'acceptedJournalHead': acceptedJournalHead,
  'acceptedServerSequence': acceptedServerSequence.toContractMap(
    (value) => value,
  ),
  'assignmentId': assignmentId,
  'assignmentVersion': assignmentVersion,
  'calculatorVersion': calculatorVersion,
  'competitionPolicyVersion': competitionPolicyVersion,
  'deviceSessionId': deviceSessionId,
  'localSchemaVersion': localSchemaVersion,
  'operationSchemaVersion': operationSchemaVersion,
  'packageVersion': packageVersion,
  'packageId': packageId,
  'partition': partition.toContractMap(),
  'preparedAt': preparedAt,
  'journalReducerVersion': journalReducerVersion,
  'rosterSnapshotHash': rosterSnapshotHash,
  'rosterSnapshotId': rosterSnapshotId,
  'rulesProfileId': rulesProfileId,
  'writerEpoch': writerEpoch,
};

Map<String, Object?> operationReceiptToMap(OperationReceiptContract receipt) {
  final map = <String, Object?>{
    'acceptedAt': OfficialStatCanonicalEncoding.normalizeTimestamp(
      receipt.acceptedAt,
    ),
    'acceptedJournalHash': receipt.acceptedJournalHash,
    'acceptedJournalHead': receipt.acceptedJournalHead,
    'actorAccountId': receipt.actorAccountId,
    'commandId': receipt.commandId,
    'commandKind': receipt.commandKind.name,
    'operationId': receipt.operationId,
    'receiptId': receipt.receiptId,
    'requestHash': receipt.requestHash,
    'scope': receipt.scope.toContractMap(),
    'serverSequence': receipt.serverSequence,
    'workspaceId': receipt.workspaceId,
    'writerEpoch': receipt.writerEpoch,
  };
  final bytes = utf8.encode(OfficialStatCanonicalEncoding.encode(map)).length;
  if (bytes > LocalGameJournalLimits.maxReceiptBytes) {
    throw LocalJournalException(
      LocalJournalErrorCode.resourceExhausted,
      'Canonical operation receipt exceeds the supported size',
      {'actualBytes': bytes},
    );
  }
  return map;
}

OperationReceiptContract operationReceiptFromMap(Map<String, Object?> map) {
  LocalJournalValidation.exactKeys(map, const {
    'receiptId',
    'scope',
    'workspaceId',
    'operationId',
    'commandId',
    'actorAccountId',
    'commandKind',
    'requestHash',
    'serverSequence',
    'acceptedJournalHead',
    'acceptedJournalHash',
    'writerEpoch',
    'acceptedAt',
  });
  final commandKind = JournalOperationType.values
      .where((value) => value.name == map['commandKind'])
      .firstOrNull;
  if (commandKind == null) {
    throw LocalJournalException(
      LocalJournalErrorCode.unsupportedSchemaVersion,
      'Unknown receipt command kind',
    );
  }
  final receipt = OperationReceiptContract(
    receiptId: LocalJournalValidation.requireId('receiptId', map['receiptId']),
    scope: LocalJournalValidation.decodeScope(map['scope']),
    workspaceId: LocalJournalValidation.requireId(
      'workspaceId',
      map['workspaceId'],
    ),
    operationId: LocalJournalValidation.requireId(
      'operationId',
      map['operationId'],
    ),
    commandId: LocalJournalValidation.requireId('commandId', map['commandId']),
    actorAccountId: LocalJournalValidation.requireId(
      'actorAccountId',
      map['actorAccountId'],
    ),
    commandKind: commandKind,
    requestHash: LocalJournalValidation.requireHash(
      'requestHash',
      map['requestHash'],
    ),
    serverSequence: LocalJournalValidation.requireSafeInteger(
      'serverSequence',
      map['serverSequence'],
    ),
    acceptedJournalHead: LocalJournalValidation.requireId(
      'acceptedJournalHead',
      map['acceptedJournalHead'],
    ),
    acceptedJournalHash: LocalJournalValidation.requireHash(
      'acceptedJournalHash',
      map['acceptedJournalHash'],
    ),
    writerEpoch: LocalJournalValidation.requireSafeInteger(
      'writerEpoch',
      map['writerEpoch'],
    ),
    acceptedAt: LocalJournalValidation.requireTimestamp(
      'acceptedAt',
      map['acceptedAt'],
    ),
  );
  operationReceiptToMap(receipt);
  return receipt;
}

Fact<DateTime> _decodeDateFact(String field, Object? value) {
  if (value is! Map) {
    throw LocalJournalException(
      LocalJournalErrorCode.invalidArgument,
      '$field must be an explicit fact',
    );
  }
  final map = Map<String, Object?>.from(value);
  switch (map['state']) {
    case 'known':
      LocalJournalValidation.exactKeys(map, const {'state', 'value'});
      return Fact.known(
        LocalJournalValidation.requireTimestamp(field, map['value']),
      );
    case 'unknown':
      LocalJournalValidation.exactKeys(map, const {
        'state',
        'value',
        'reasonCode',
      });
      if (map['value'] != null) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          '$field unknown fact must have a null value',
        );
      }
      return Fact.unknown(
        reasonCode: LocalJournalValidation.requireReasonCode(
          '$field.reasonCode',
          map['reasonCode'],
        ),
      );
    case 'notApplicable':
      LocalJournalValidation.exactKeys(map, const {
        'state',
        'value',
        'reasonCode',
      });
      if (map['value'] != null) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          '$field notApplicable fact requires a reason and null value',
        );
      }
      return Fact.notApplicable(
        reasonCode: LocalJournalValidation.requireReasonCode(
          '$field.reasonCode',
          map['reasonCode'],
          required: true,
        )!,
      );
    default:
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        '$field has an unknown fact state',
      );
  }
}

Fact<OperationReceiptContract> _decodeReceiptFact(Object? value) {
  if (value is! Map) {
    throw LocalJournalException(
      LocalJournalErrorCode.invalidArgument,
      'serverReceipt must be an explicit fact',
    );
  }
  final map = Map<String, Object?>.from(value);
  switch (map['state']) {
    case 'known':
      LocalJournalValidation.exactKeys(map, const {'state', 'value'});
      final raw = map['value'];
      if (raw is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          'Known serverReceipt must contain an object',
        );
      }
      return Fact.known(
        operationReceiptFromMap(Map<String, Object?>.from(raw)),
      );
    case 'unknown':
      LocalJournalValidation.exactKeys(map, const {
        'state',
        'value',
        'reasonCode',
      });
      if (map['value'] != null) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          'Unknown serverReceipt must have a null value',
        );
      }
      return Fact.unknown(
        reasonCode: LocalJournalValidation.requireReasonCode(
          'serverReceipt.reasonCode',
          map['reasonCode'],
        ),
      );
    case 'notApplicable':
      LocalJournalValidation.exactKeys(map, const {
        'state',
        'value',
        'reasonCode',
      });
      if (map['value'] != null) {
        throw LocalJournalException(
          LocalJournalErrorCode.invalidArgument,
          'Not-applicable serverReceipt requires a reason and null value',
        );
      }
      return Fact.notApplicable(
        reasonCode: LocalJournalValidation.requireReasonCode(
          'serverReceipt.reasonCode',
          map['reasonCode'],
          required: true,
        )!,
      );
    default:
      throw LocalJournalException(
        LocalJournalErrorCode.invalidArgument,
        'serverReceipt has an unknown fact state',
      );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
