import '../../models/official_stats/canonical_encoding.dart';
import '../../models/official_stats/contract_versions.dart';

/// Versioned, cross-platform bounds for the dormant local journal.
///
/// These are denial-of-service and storage-safety limits, not basketball rules.
/// Changing a persisted bound or wire interpretation requires a reviewed local
/// schema migration.
abstract final class LocalGameJournalLimits {
  static const int localSchemaVersion = 2;
  static const int preparedGamePackageVersion = 2;
  static const int recoveryArchiveVersion = 1;
  static const int recoveryExportAuditVersion = 2;
  static const int deletionManifestVersion = 2;
  static const int retryPolicyVersion = 1;

  static const int operationSchemaVersion =
      OfficialStatContractVersions.dataSchema;

  static const int maxIdLength = 128;
  static const int maxStringLength = 2048;
  static const int maxPayloadBytes = 16 * 1024;
  static const int maxOperationBytes = 32 * 1024;
  static const int maxReceiptBytes = 4 * 1024;
  static const int maxCheckpointBytes = 16 * 1024;
  static const int maxPreparationPackageBytes = 128 * 1024;
  // Must accommodate every valid maximum-size workspace plus a bounded
  // manifest/envelope. Archives are canonical JSON, never compressed, so the
  // decoder has no zip-bomb expansion surface.
  static const int maxWorkspaceBytes = 32 * 1024 * 1024;
  static const int maxOperationsPerWorkspace = 20000;
  // An archive contains at most one recovery representation per lifetime
  // operation: a retained entry (including delivery/receipt) or a pruned
  // receipt tombstone. The fixed-schema overhead is conservatively budgeted
  // at 6 KiB per operation, in addition to the bounded immutable operations.
  static const int maxRecoveryPerOperationOverheadBytes = 6 * 1024;
  static const int maxRecoveryEnvelopeBytes = 1024 * 1024;
  static const int maxRecoveryArchiveBytes =
      maxWorkspaceBytes +
      maxOperationsPerWorkspace * maxRecoveryPerOperationOverheadBytes +
      maxPreparationPackageBytes +
      maxRecoveryEnvelopeBytes;
  // Archive parsing performs this iterative preflight before canonical
  // encoding, whose normalizer is recursive. The depth budget is deliberately
  // larger than a maximum-depth operation payload plus every fixed archive
  // envelope. Container width permits the full workspace operation bound.
  static const int maxRecoveryArchiveDepth = maxPayloadDepth + 16;
  static const int maxRecoveryArchiveContainerElements =
      maxOperationsPerWorkspace;
  // A smallest JSON scalar plus delimiter consumes at least two workspace
  // bytes. Add 256 fixed-envelope/delivery nodes per lifetime operation and a
  // full payload-node reserve for the prepared package.
  static const int maxRecoveryArchiveNodes =
      maxWorkspaceBytes ~/ 2 +
      maxOperationsPerWorkspace * 256 +
      maxPayloadNodes;
  static const int maxPayloadDepth = 12;
  static const int maxMapKeys = 64;
  static const int maxListElements = 512;
  static const int maxPayloadNodes = 4096;
  static const int defaultPageSize = 25;
  static const int maxPageSize = 100;
  static const int integrityScanPageSize = 250;

  /// Reserved for Packet 08 compatibility; Packet 07 performs no ingress.
  static const int futureServerBatchMaxOperations = 25;
  static const int futureServerBatchMaxBytes = 128 * 1024;

  static const int retryBaseDelayMs = 1000;
  static const int retryMaximumDelayMs = 60000;
  static const int retryMinimumJitterBasisPoints = 5000;
  static const int retryMaximumJitterBasisPoints = 10000;

  static const int maxSafeInteger =
      OfficialStatCanonicalEncoding.maxSafeInteger;
  static const int maxPeriodNumber = 1000;
  static const int maxClockRemainingMs = 24 * 60 * 60 * 1000;
}
