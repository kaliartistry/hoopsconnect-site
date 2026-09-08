import 'domain_contracts.dart';
import 'fact.dart';

enum CommandErrorCode {
  invalidArgument,
  invalidIdentifier,
  unsupportedSchemaVersion,
  policyNotActivated,
  unauthenticated,
  permissionDenied,
  scopeMismatch,
  assignmentRequired,
  staleAuthority,
  staleControlVersion,
  staleRevision,
  payloadKeyConflict,
  sequenceGap,
  sequenceConflict,
  staleWriterEpoch,
  writerTransferRequired,
  lifecycleTransitionDenied,
  invariantViolation,
  evidenceRequired,
  conflictBranchPreserved,
  resourceExhausted,
  rateLimited,
  transientUnavailable,
  deadlineExceeded,
  internal,
}

enum RetryClassification {
  never,
  retrySameCommand,
  refreshAuthenticationThenRetrySameCommand,
  refreshStateThenCreateNewCommand,
  operatorResolutionRequired,
}

enum IdempotencyClassification {
  safeReplayReturnsOriginalResult,
  sameKeyDifferentPayloadRejected,
  notAccepted,
  conflictBranchPreserved,
}

class CommandErrorPolicy {
  final CommandErrorCode code;
  final RetryClassification retry;
  final IdempotencyClassification idempotency;
  final int? httpStatus;

  const CommandErrorPolicy({
    required this.code,
    required this.retry,
    required this.idempotency,
    this.httpStatus,
  });
}

abstract final class OfficialStatCommandErrors {
  static const Map<CommandErrorCode, CommandErrorPolicy> policies = {
    CommandErrorCode.invalidArgument: CommandErrorPolicy(
      code: CommandErrorCode.invalidArgument,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 400,
    ),
    CommandErrorCode.invalidIdentifier: CommandErrorPolicy(
      code: CommandErrorCode.invalidIdentifier,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 400,
    ),
    CommandErrorCode.unsupportedSchemaVersion: CommandErrorPolicy(
      code: CommandErrorCode.unsupportedSchemaVersion,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 426,
    ),
    CommandErrorCode.policyNotActivated: CommandErrorPolicy(
      code: CommandErrorCode.policyNotActivated,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.unauthenticated: CommandErrorPolicy(
      code: CommandErrorCode.unauthenticated,
      retry: RetryClassification.refreshAuthenticationThenRetrySameCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 401,
    ),
    CommandErrorCode.permissionDenied: CommandErrorPolicy(
      code: CommandErrorCode.permissionDenied,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 403,
    ),
    CommandErrorCode.scopeMismatch: CommandErrorPolicy(
      code: CommandErrorCode.scopeMismatch,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 403,
    ),
    CommandErrorCode.assignmentRequired: CommandErrorPolicy(
      code: CommandErrorCode.assignmentRequired,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 403,
    ),
    CommandErrorCode.staleAuthority: CommandErrorPolicy(
      code: CommandErrorCode.staleAuthority,
      retry: RetryClassification.refreshStateThenCreateNewCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.staleControlVersion: CommandErrorPolicy(
      code: CommandErrorCode.staleControlVersion,
      retry: RetryClassification.refreshStateThenCreateNewCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.staleRevision: CommandErrorPolicy(
      code: CommandErrorCode.staleRevision,
      retry: RetryClassification.refreshStateThenCreateNewCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.payloadKeyConflict: CommandErrorPolicy(
      code: CommandErrorCode.payloadKeyConflict,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.sameKeyDifferentPayloadRejected,
      httpStatus: 409,
    ),
    CommandErrorCode.sequenceGap: CommandErrorPolicy(
      code: CommandErrorCode.sequenceGap,
      retry: RetryClassification.retrySameCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.sequenceConflict: CommandErrorPolicy(
      code: CommandErrorCode.sequenceConflict,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.conflictBranchPreserved,
      httpStatus: 409,
    ),
    CommandErrorCode.staleWriterEpoch: CommandErrorPolicy(
      code: CommandErrorCode.staleWriterEpoch,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.conflictBranchPreserved,
      httpStatus: 409,
    ),
    CommandErrorCode.writerTransferRequired: CommandErrorPolicy(
      code: CommandErrorCode.writerTransferRequired,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.lifecycleTransitionDenied: CommandErrorPolicy(
      code: CommandErrorCode.lifecycleTransitionDenied,
      retry: RetryClassification.refreshStateThenCreateNewCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 409,
    ),
    CommandErrorCode.invariantViolation: CommandErrorPolicy(
      code: CommandErrorCode.invariantViolation,
      retry: RetryClassification.never,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 422,
    ),
    CommandErrorCode.evidenceRequired: CommandErrorPolicy(
      code: CommandErrorCode.evidenceRequired,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 422,
    ),
    CommandErrorCode.conflictBranchPreserved: CommandErrorPolicy(
      code: CommandErrorCode.conflictBranchPreserved,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.conflictBranchPreserved,
      httpStatus: 409,
    ),
    CommandErrorCode.resourceExhausted: CommandErrorPolicy(
      code: CommandErrorCode.resourceExhausted,
      retry: RetryClassification.operatorResolutionRequired,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 507,
    ),
    CommandErrorCode.rateLimited: CommandErrorPolicy(
      code: CommandErrorCode.rateLimited,
      retry: RetryClassification.retrySameCommand,
      idempotency: IdempotencyClassification.notAccepted,
      httpStatus: 429,
    ),
    CommandErrorCode.transientUnavailable: CommandErrorPolicy(
      code: CommandErrorCode.transientUnavailable,
      retry: RetryClassification.retrySameCommand,
      idempotency: IdempotencyClassification.safeReplayReturnsOriginalResult,
      httpStatus: 503,
    ),
    CommandErrorCode.deadlineExceeded: CommandErrorPolicy(
      code: CommandErrorCode.deadlineExceeded,
      retry: RetryClassification.retrySameCommand,
      idempotency: IdempotencyClassification.safeReplayReturnsOriginalResult,
      httpStatus: 504,
    ),
    CommandErrorCode.internal: CommandErrorPolicy(
      code: CommandErrorCode.internal,
      retry: RetryClassification.retrySameCommand,
      idempotency: IdempotencyClassification.safeReplayReturnsOriginalResult,
      httpStatus: 500,
    ),
  };
}

class OfficialStatCommandEnvelope {
  final String commandId;
  final int commandSchemaVersion;
  final int authorizationSchemaVersion;
  final int domainSchemaVersion;
  final GameScope scope;
  final int expectedControlVersion;
  final Fact<String> expectedRevisionId;
  final Fact<String> expectedRevisionHash;
  final Map<String, Object?> payload;
  final String payloadHash;

  const OfficialStatCommandEnvelope({
    required this.commandId,
    required this.commandSchemaVersion,
    required this.authorizationSchemaVersion,
    required this.domainSchemaVersion,
    required this.scope,
    required this.expectedControlVersion,
    required this.expectedRevisionId,
    required this.expectedRevisionHash,
    required this.payload,
    required this.payloadHash,
  });
}
