enum LocalJournalErrorCode {
  invalidArgument,
  invalidIdentifier,
  unsupportedSchemaVersion,
  unsupportedReducerVersion,
  unsupportedRulesProfile,
  scopeMismatch,
  accountAccessDenied,
  operationNotFound,
  payloadKeyConflict,
  sequenceGap,
  sequenceConflict,
  writerEpochConflict,
  hashMismatch,
  mutatedRecord,
  receiptMismatch,
  invalidStateTransition,
  resourceExhausted,
  storageUnavailable,
  storageCapabilityUnproven,
  transactionAborted,
  migrationFailed,
  corruptRecordQuarantined,
  unsupportedArchiveVersion,
  archiveTampered,
  archivePartial,
  archiveTooLarge,
  untrustedImport,
  manifestMismatch,
  consentRequired,
  secureQuarantineUnavailable,
}

/// Stable, typed failure returned by the local journal boundary.
final class LocalJournalException implements Exception {
  final LocalJournalErrorCode code;
  final String message;
  final Map<String, Object?> details;

  LocalJournalException(
    this.code,
    this.message, [
    Map<String, Object?> details = const {},
  ]) : details = Map.unmodifiable(details);

  @override
  String toString() =>
      'LocalJournalException(${code.name}): $message'
      '${details.isEmpty ? '' : ' $details'}';
}

enum LocalCaptureAvailability {
  ready,
  disabledStorageUnavailable,
  disabledCapabilityUnproven,
  disabledUnsupportedSchema,
  disabledIntegrityFailure,
}

final class LocalStorageCapability {
  final LocalCaptureAvailability availability;
  final String adapter;
  final bool durable;
  final bool transactional;
  final bool encryptedAtRestClaimed;
  final int localSchemaVersion;
  final LocalJournalErrorCode? reasonCode;

  const LocalStorageCapability({
    required this.availability,
    required this.adapter,
    required this.durable,
    required this.transactional,
    required this.encryptedAtRestClaimed,
    required this.localSchemaVersion,
    this.reasonCode,
  });

  bool get captureEnabled =>
      availability == LocalCaptureAvailability.ready &&
      durable &&
      transactional;
}
