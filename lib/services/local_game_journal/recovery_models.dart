import 'dart:convert';

import '../../models/official_stats/canonical_encoding.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../models/official_stats/fact.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_models.dart';
import 'journal_repository.dart';
import 'journal_validation.dart';

void requireLocalJournalPackageCheckpointBinding({
  required PreparedGameRecoveryPackage preparedPackage,
  required LocalWorkspaceCheckpoint checkpoint,
  required LocalJournalErrorCode errorCode,
}) {
  if (checkpoint.partition.key != preparedPackage.partition.key ||
      checkpoint.preparationPackageChecksum.valueOrNull !=
          preparedPackage.packageChecksum ||
      checkpoint.writerEpoch != preparedPackage.writerEpoch) {
    throw LocalJournalException(
      errorCode,
      'Prepared package and checkpoint binding do not agree',
    );
  }
}

void requireLocalJournalOperationPackageBinding({
  required LocalGameJournalOperation operation,
  required PreparedGameRecoveryPackage preparedPackage,
  required LocalWorkspaceCheckpoint checkpoint,
  required LocalJournalErrorCode errorCode,
}) {
  if (operation.partition.key != preparedPackage.partition.key ||
      operation.deviceSessionId != preparedPackage.deviceSessionId ||
      operation.writerEpoch != preparedPackage.writerEpoch ||
      operation.writerEpoch != checkpoint.writerEpoch ||
      operation.operationSchemaVersion !=
          preparedPackage.operationSchemaVersion ||
      operation.reducerVersion != preparedPackage.journalReducerVersion ||
      operation.rulesProfileId != preparedPackage.rulesProfileId) {
    throw LocalJournalException(
      errorCode,
      'Operation does not bind the prepared package and checkpoint',
    );
  }
}

void requireLocalJournalAcceptedCheckpointBinding({
  required LocalWorkspaceCheckpoint checkpoint,
  required List<LocalJournalEntry> retainedEntries,
  required List<PrunedReceiptEvidence> prunedEvidence,
  required LocalJournalErrorCode errorCode,
}) {
  var acceptedThrough = -1;
  OperationReceiptContract? boundaryReceipt;
  for (final evidence in prunedEvidence) {
    if (evidence.localSequence != acceptedThrough + 1) {
      throw LocalJournalException(
        errorCode,
        'Accepted pruned receipt evidence is not contiguous',
      );
    }
    acceptedThrough = evidence.localSequence;
    boundaryReceipt = evidence.receipt;
  }
  for (final entry in retainedEntries) {
    if (entry.operation.localSequence != acceptedThrough + 1 ||
        entry.delivery.state != JournalDeliveryState.accepted) {
      break;
    }
    final receipt = entry.delivery.serverReceipt.valueOrNull;
    if (receipt == null) {
      throw LocalJournalException(
        errorCode,
        'Accepted retained operation is missing its durable receipt',
      );
    }
    acceptedThrough = entry.operation.localSequence;
    boundaryReceipt = receipt;
  }
  final checkpointAccepted =
      checkpoint.acceptedThroughSequence.valueOrNull ?? -1;
  if (checkpointAccepted != acceptedThrough ||
      (acceptedThrough >= 0 &&
          (boundaryReceipt == null ||
              checkpoint.acceptedJournalHead.valueOrNull !=
                  boundaryReceipt.acceptedJournalHead ||
              checkpoint.acceptedJournalHash.valueOrNull !=
                  boundaryReceipt.acceptedJournalHash)) ||
      (acceptedThrough < 0 &&
          (checkpoint.acceptedJournalHead.valueOrNull != null ||
              checkpoint.acceptedJournalHash.valueOrNull != null))) {
    throw LocalJournalException(
      errorCode,
      'Checkpoint accepted boundary does not match durable receipt evidence',
    );
  }
}

enum RecoveryArchiveTrust { localOriginal, importedUntrusted }

/// Minimal durable evidence for one operation removed from the active journal.
/// The sequence makes complete prefix coverage independently verifiable; the
/// receipt binds the operation, command, request hash, writer, and scope.
final class PrunedReceiptEvidence {
  final int localSequence;
  final OperationReceiptContract receipt;

  PrunedReceiptEvidence({required this.localSequence, required this.receipt}) {
    LocalJournalValidation.requireSafeInteger('localSequence', localSequence);
    operationReceiptToMap(receipt);
  }

  factory PrunedReceiptEvidence.fromContractMap(Map<String, Object?> map) {
    LocalJournalValidation.exactKeys(map, const {'localSequence', 'receipt'});
    final rawReceipt = map['receipt'];
    if (rawReceipt is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Pruned receipt evidence is missing its receipt',
      );
    }
    return PrunedReceiptEvidence(
      localSequence: LocalJournalValidation.requireSafeInteger(
        'localSequence',
        map['localSequence'],
      ),
      receipt: operationReceiptFromMap(Map<String, Object?>.from(rawReceipt)),
    );
  }

  Map<String, Object?> toContractMap() => {
    'localSequence': localSequence,
    'receipt': operationReceiptToMap(receipt),
  };
}

final class LocalJournalRecoveryArchive {
  final int archiveVersion;
  final String archiveId;
  final String manifestId;
  final JournalPartition partition;
  final PreparedGameRecoveryPackage preparedPackage;
  final LocalWorkspaceCheckpoint checkpoint;
  final List<LocalJournalEntry> entries;
  final List<PrunedReceiptEvidence> receiptTombstones;
  final String exportedByAccountId;
  final String exportedByDeviceSessionId;
  final DateTime exportedAt;
  final RecoveryArchiveTrust trust;
  final String checksum;

  LocalJournalRecoveryArchive._({
    required this.archiveVersion,
    required this.archiveId,
    required this.manifestId,
    required this.partition,
    required this.preparedPackage,
    required this.checkpoint,
    required this.entries,
    required this.receiptTombstones,
    required this.exportedByAccountId,
    required this.exportedByDeviceSessionId,
    required this.exportedAt,
    required this.trust,
    required this.checksum,
  });

  factory LocalJournalRecoveryArchive.create({
    required String archiveId,
    required String manifestId,
    required JournalPartition partition,
    required PreparedGameRecoveryPackage preparedPackage,
    required LocalWorkspaceCheckpoint checkpoint,
    required List<LocalJournalEntry> entries,
    required List<PrunedReceiptEvidence> receiptTombstones,
    required String exportedByAccountId,
    required String exportedByDeviceSessionId,
    required DateTime exportedAt,
  }) {
    final normalizedAt = LocalJournalValidation.normalizeTimestamp(exportedAt);
    final frozenTombstones = receiptTombstones
        .map(
          (value) =>
              PrunedReceiptEvidence.fromContractMap(value.toContractMap()),
        )
        .toList(growable: false);
    final withoutChecksum = _archiveMap(
      archiveVersion: LocalGameJournalLimits.recoveryArchiveVersion,
      archiveId: archiveId,
      manifestId: manifestId,
      partition: partition,
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      entries: entries,
      receiptTombstones: frozenTombstones,
      exportedByAccountId: exportedByAccountId,
      exportedByDeviceSessionId: exportedByDeviceSessionId,
      exportedAt: normalizedAt,
      trust: RecoveryArchiveTrust.localOriginal,
    );
    final archive = LocalJournalRecoveryArchive._(
      archiveVersion: LocalGameJournalLimits.recoveryArchiveVersion,
      archiveId: archiveId,
      manifestId: manifestId,
      partition: partition,
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      entries: List.unmodifiable(entries),
      receiptTombstones: List.unmodifiable(frozenTombstones),
      exportedByAccountId: exportedByAccountId,
      exportedByDeviceSessionId: exportedByDeviceSessionId,
      exportedAt: normalizedAt,
      trust: RecoveryArchiveTrust.localOriginal,
      checksum: OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum),
    );
    archive._validate();
    return archive;
  }

  factory LocalJournalRecoveryArchive.parse(
    String encoded, {
    required String expectedActorAccountId,
    JournalPartition? expectedPartition,
  }) {
    if (utf8.encode(encoded).length >
        LocalGameJournalLimits.maxRecoveryArchiveBytes) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTooLarge,
        'Recovery archive exceeds the supported size',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (_) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive is truncated or invalid JSON',
      );
    }
    _requireBoundedRecoveryArchiveShape(decoded);
    if (decoded is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive root must be an object',
      );
    }
    late String canonical;
    try {
      canonical = OfficialStatCanonicalEncoding.encode(decoded);
    } on FormatException {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive contains a non-canonical JSON value',
      );
    }
    if (canonical != encoded) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTampered,
        'Recovery archive must use canonical encoding',
      );
    }
    final map = Map<String, Object?>.from(decoded);
    LocalJournalValidation.exactKeys(map, const {
      'archiveVersion',
      'archiveId',
      'manifestId',
      'partition',
      'preparedPackage',
      'checkpoint',
      'entries',
      'receiptTombstones',
      'provenance',
      'checksum',
    });
    final version = map['archiveVersion'];
    if (version != LocalGameJournalLimits.recoveryArchiveVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedArchiveVersion,
        'Recovery archive version is unsupported',
        {'archiveVersion': version},
      );
    }
    final rawPartition = map['partition'];
    final rawPackage = map['preparedPackage'];
    final rawCheckpoint = map['checkpoint'];
    final rawEntries = map['entries'];
    final rawTombstones = map['receiptTombstones'];
    final rawProvenance = map['provenance'];
    if (rawPartition is! Map ||
        rawPackage is! Map ||
        rawCheckpoint is! Map ||
        rawEntries is! List ||
        rawTombstones is! List ||
        rawProvenance is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive contains malformed sections',
      );
    }
    final provenance = Map<String, Object?>.from(rawProvenance);
    LocalJournalValidation.exactKeys(provenance, const {
      'exportedAt',
      'exportedByAccountId',
      'exportedByDeviceSessionId',
      'source',
      'trust',
    });
    if (provenance['source'] != 'deviceLocalJournal' ||
        provenance['trust'] != RecoveryArchiveTrust.localOriginal.name) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTampered,
        'Recovery archive provenance is invalid',
      );
    }
    final partition = JournalPartition.fromContractMap(
      Map<String, Object?>.from(rawPartition),
    );
    if (partition.actorAccountId != expectedActorAccountId ||
        (expectedPartition != null && partition.key != expectedPartition.key)) {
      throw LocalJournalException(
        LocalJournalErrorCode.scopeMismatch,
        'Recovery archive belongs to another account or workspace',
      );
    }
    if (rawEntries.length > LocalGameJournalLimits.maxOperationsPerWorkspace ||
        rawTombstones.length >
            LocalGameJournalLimits.maxOperationsPerWorkspace ||
        rawEntries.length + rawTombstones.length >
            LocalGameJournalLimits.maxOperationsPerWorkspace) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTooLarge,
        'Recovery archive operation evidence exceeds the workspace limit',
      );
    }
    final entries = <LocalJournalEntry>[];
    for (final raw in rawEntries) {
      if (raw is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.archivePartial,
          'Recovery archive operation entry is malformed',
        );
      }
      entries.add(
        LocalJournalEntry.fromContractMap(Map<String, Object?>.from(raw)),
      );
    }
    final tombstones = <PrunedReceiptEvidence>[];
    for (final raw in rawTombstones) {
      if (raw is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.archivePartial,
          'Recovery archive receipt tombstone is malformed',
        );
      }
      tombstones.add(
        PrunedReceiptEvidence.fromContractMap(Map<String, Object?>.from(raw)),
      );
    }
    final trust = RecoveryArchiveTrust.values
        .where((value) => value.name == provenance['trust'])
        .firstOrNull;
    if (trust == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTampered,
        'Recovery archive trust value is invalid',
      );
    }
    final archive = LocalJournalRecoveryArchive._(
      archiveVersion: version as int,
      archiveId: LocalJournalValidation.requireId(
        'archiveId',
        map['archiveId'],
      ),
      manifestId: LocalJournalValidation.requireId(
        'manifestId',
        map['manifestId'],
      ),
      partition: partition,
      preparedPackage: PreparedGameRecoveryPackage.fromContractMap(
        Map<String, Object?>.from(rawPackage),
      ),
      checkpoint: LocalWorkspaceCheckpoint.fromContractMap(
        Map<String, Object?>.from(rawCheckpoint),
      ),
      entries: List.unmodifiable(entries),
      receiptTombstones: List.unmodifiable(tombstones),
      exportedByAccountId: LocalJournalValidation.requireId(
        'exportedByAccountId',
        provenance['exportedByAccountId'],
      ),
      exportedByDeviceSessionId: LocalJournalValidation.requireId(
        'exportedByDeviceSessionId',
        provenance['exportedByDeviceSessionId'],
      ),
      exportedAt: LocalJournalValidation.requireTimestamp(
        'exportedAt',
        provenance['exportedAt'],
      ),
      trust: trust,
      checksum: LocalJournalValidation.requireHash('checksum', map['checksum']),
    );
    archive._validate();
    return archive;
  }

  String get canonicalJson =>
      OfficialStatCanonicalEncoding.encode(toContractMap());

  Map<String, Object?> toContractMap() => {
    ..._archiveMap(
      archiveVersion: archiveVersion,
      archiveId: archiveId,
      manifestId: manifestId,
      partition: partition,
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      entries: entries,
      receiptTombstones: receiptTombstones,
      exportedByAccountId: exportedByAccountId,
      exportedByDeviceSessionId: exportedByDeviceSessionId,
      exportedAt: exportedAt,
      trust: trust,
    ),
    'checksum': checksum,
  };

  void _validate() {
    for (final entry in {
      'archiveId': archiveId,
      'manifestId': manifestId,
      'exportedByAccountId': exportedByAccountId,
      'exportedByDeviceSessionId': exportedByDeviceSessionId,
    }.entries) {
      LocalJournalValidation.requireId(entry.key, entry.value);
    }
    if (archiveVersion != LocalGameJournalLimits.recoveryArchiveVersion) {
      throw LocalJournalException(
        LocalJournalErrorCode.unsupportedArchiveVersion,
        'Recovery archive version is unsupported',
      );
    }
    if (partition.actorAccountId != exportedByAccountId ||
        partition.key != preparedPackage.partition.key ||
        partition.key != checkpoint.partition.key ||
        preparedPackage.deviceSessionId != exportedByDeviceSessionId) {
      throw LocalJournalException(
        LocalJournalErrorCode.scopeMismatch,
        'Recovery archive identity or scope sections do not agree',
      );
    }
    requireLocalJournalPackageCheckpointBinding(
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      errorCode: LocalJournalErrorCode.archiveTampered,
    );
    var expectedSequence =
        (checkpoint.prunedThroughSequence.valueOrNull ?? -1) + 1;
    var previousHash = checkpoint.prunedThroughHash.valueOrNull;
    var operationBytes = 0;
    final prunedThroughSequence =
        checkpoint.prunedThroughSequence.valueOrNull ?? -1;
    final prunedOperationIds = <String>{};
    final prunedCommandIds = <String>{};
    for (var sequence = 0; sequence <= prunedThroughSequence; sequence++) {
      if (sequence >= receiptTombstones.length ||
          receiptTombstones[sequence].localSequence != sequence) {
        throw LocalJournalException(
          LocalJournalErrorCode.archivePartial,
          'Recovery archive pruned receipt coverage contains a gap',
          {'expectedSequence': sequence},
        );
      }
      final receipt = receiptTombstones[sequence].receipt;
      if (receipt.actorAccountId != partition.actorAccountId ||
          receipt.scope.key != partition.scope.key ||
          receipt.workspaceId != partition.workspaceId ||
          receipt.writerEpoch != checkpoint.writerEpoch ||
          !prunedOperationIds.add(receipt.operationId) ||
          !prunedCommandIds.add(receipt.commandId)) {
        throw LocalJournalException(
          LocalJournalErrorCode.archiveTampered,
          'Recovery archive receipt tombstones are duplicated or out of scope',
        );
      }
    }
    if (receiptTombstones.length != prunedThroughSequence + 1) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive pruned receipt count does not match its checkpoint',
      );
    }
    if (receiptTombstones.isNotEmpty &&
        receiptTombstones.last.receipt.requestHash !=
            checkpoint.prunedThroughHash.valueOrNull) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTampered,
        'Recovery archive pruned terminal hash does not match its checkpoint',
      );
    }
    final operationIds = <String>{...prunedOperationIds};
    final commandIds = <String>{...prunedCommandIds};
    for (final entry in entries) {
      final operation = entry.operation;
      requireLocalJournalOperationPackageBinding(
        operation: operation,
        preparedPackage: preparedPackage,
        checkpoint: checkpoint,
        errorCode: LocalJournalErrorCode.archiveTampered,
      );
      if (operation.partition.key != partition.key ||
          operation.localSequence != expectedSequence) {
        throw LocalJournalException(
          LocalJournalErrorCode.archivePartial,
          'Recovery archive operation sequence is incomplete',
        );
      }
      if (expectedSequence == 0) {
        final genesis = switch (operation.previousOperationHash) {
          NotApplicableFact<String>(reasonCode: 'genesis') => true,
          _ => false,
        };
        if (!genesis) {
          throw LocalJournalException(
            LocalJournalErrorCode.archiveTampered,
            'Recovery archive genesis hash is invalid',
          );
        }
      } else if (operation.previousOperationHash.valueOrNull != previousHash) {
        throw LocalJournalException(
          LocalJournalErrorCode.archiveTampered,
          'Recovery archive operation hash chain is invalid',
        );
      }
      previousHash = operation.requestHash;
      if (!operationIds.add(operation.operationId) ||
          !commandIds.add(operation.commandId)) {
        throw LocalJournalException(
          LocalJournalErrorCode.archiveTampered,
          'Recovery archive operation or command IDs are duplicated',
        );
      }
      expectedSequence++;
      operationBytes += operation.byteCount;
    }
    if (entries.length != checkpoint.retainedOperationCount ||
        operationBytes != checkpoint.retainedOperationBytes ||
        expectedSequence != checkpoint.nextLocalSequence ||
        previousHash != checkpoint.lastOperationHash.valueOrNull) {
      throw LocalJournalException(
        LocalJournalErrorCode.archivePartial,
        'Recovery archive checkpoint does not match its operations',
      );
    }
    requireLocalJournalAcceptedCheckpointBinding(
      checkpoint: checkpoint,
      retainedEntries: entries,
      prunedEvidence: receiptTombstones,
      errorCode: LocalJournalErrorCode.archiveTampered,
    );
    final withoutChecksum = _archiveMap(
      archiveVersion: archiveVersion,
      archiveId: archiveId,
      manifestId: manifestId,
      partition: partition,
      preparedPackage: preparedPackage,
      checkpoint: checkpoint,
      entries: entries,
      receiptTombstones: receiptTombstones,
      exportedByAccountId: exportedByAccountId,
      exportedByDeviceSessionId: exportedByDeviceSessionId,
      exportedAt: exportedAt,
      trust: trust,
    );
    if (OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum) != checksum) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTampered,
        'Recovery archive checksum does not match its content',
      );
    }
    if (utf8.encode(canonicalJson).length >
        LocalGameJournalLimits.maxRecoveryArchiveBytes) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTooLarge,
        'Recovery archive exceeds the supported size',
      );
    }
  }
}

final class _RecoveryArchiveShapeNode {
  final Object? value;
  final int depth;

  const _RecoveryArchiveShapeNode(this.value, this.depth);
}

/// Protects the recursive canonical encoder from adversarial JSON shapes.
///
/// `jsonDecode` itself is iterative on supported Dart runtimes, but canonical
/// normalization is recursive. This depth-first work list therefore runs
/// before any normalization or typed model construction.
void _requireBoundedRecoveryArchiveShape(Object? root) {
  final pending = <_RecoveryArchiveShapeNode>[
    _RecoveryArchiveShapeNode(root, 0),
  ];
  var visited = 0;
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    visited++;
    if (visited > LocalGameJournalLimits.maxRecoveryArchiveNodes ||
        node.depth > LocalGameJournalLimits.maxRecoveryArchiveDepth) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTooLarge,
        'Recovery archive structure exceeds the supported bounds',
      );
    }
    final value = node.value;
    if (value is List) {
      if (value.length >
          LocalGameJournalLimits.maxRecoveryArchiveContainerElements) {
        throw LocalJournalException(
          LocalJournalErrorCode.archiveTooLarge,
          'Recovery archive list exceeds the supported bound',
        );
      }
      for (final child in value) {
        pending.add(_RecoveryArchiveShapeNode(child, node.depth + 1));
      }
    } else if (value is Map) {
      if (value.length >
          LocalGameJournalLimits.maxRecoveryArchiveContainerElements) {
        throw LocalJournalException(
          LocalJournalErrorCode.archiveTooLarge,
          'Recovery archive object exceeds the supported bound',
        );
      }
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String ||
            key.length > LocalGameJournalLimits.maxStringLength) {
          throw LocalJournalException(
            LocalJournalErrorCode.archiveTooLarge,
            'Recovery archive object key exceeds the supported bound',
          );
        }
        pending.add(_RecoveryArchiveShapeNode(entry.value, node.depth + 1));
      }
    } else if (value is String &&
        value.length > LocalGameJournalLimits.maxStringLength) {
      throw LocalJournalException(
        LocalJournalErrorCode.archiveTooLarge,
        'Recovery archive string exceeds the supported bound',
      );
    }
  }
}

Map<String, Object?> _archiveMap({
  required int archiveVersion,
  required String archiveId,
  required String manifestId,
  required JournalPartition partition,
  required PreparedGameRecoveryPackage preparedPackage,
  required LocalWorkspaceCheckpoint checkpoint,
  required List<LocalJournalEntry> entries,
  required List<PrunedReceiptEvidence> receiptTombstones,
  required String exportedByAccountId,
  required String exportedByDeviceSessionId,
  required DateTime exportedAt,
  required RecoveryArchiveTrust trust,
}) => {
  'archiveId': archiveId,
  'archiveVersion': archiveVersion,
  'checkpoint': checkpoint.toContractMap(),
  'entries': entries.map((entry) => entry.toContractMap()).toList(),
  'manifestId': manifestId,
  'partition': partition.toContractMap(),
  'preparedPackage': preparedPackage.toContractMap(),
  'provenance': {
    'exportedAt': exportedAt,
    'exportedByAccountId': exportedByAccountId,
    'exportedByDeviceSessionId': exportedByDeviceSessionId,
    'source': 'deviceLocalJournal',
    'trust': trust.name,
  },
  'receiptTombstones': receiptTombstones
      .map((value) => value.toContractMap())
      .toList(growable: false),
};

final class LocalRecoveryImportRecord {
  final String archiveId;
  final String checksum;
  final JournalPartition partition;
  final DateTime importedAt;
  final RecoveryArchiveTrust trust;

  LocalRecoveryImportRecord({
    required this.archiveId,
    required this.checksum,
    required this.partition,
    required DateTime importedAt,
    this.trust = RecoveryArchiveTrust.importedUntrusted,
  }) : importedAt = LocalJournalValidation.normalizeTimestamp(importedAt) {
    if (trust != RecoveryArchiveTrust.importedUntrusted) {
      throw LocalJournalException(
        LocalJournalErrorCode.untrustedImport,
        'Imported recovery content must remain untrusted',
      );
    }
  }

  Map<String, Object?> toContractMap() => {
    'archiveId': archiveId,
    'checksum': checksum,
    'importedAt': importedAt,
    'partition': partition.toContractMap(),
    'trust': trust.name,
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
