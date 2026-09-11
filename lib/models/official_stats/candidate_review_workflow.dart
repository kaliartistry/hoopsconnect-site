import 'dart:collection';

import 'canonical_encoding.dart';
import 'domain_contracts.dart';
import 'domain_enums.dart';

/// Candidate-only review state used while v2 server commands remain dormant.
///
/// [approved] is a review outcome, not an official-stat certificate. Production
/// certification still requires the authority, evidence, and activation gates
/// in `official-stat-contract.md`.
enum CandidateReviewState {
  draft,
  submitted,
  underReview,
  changesRequested,
  resubmitted,
  approved,
}

enum CandidateCaptureStage { preparation, liveDraft, postGameDraft, sealed }

enum CandidateReviewCommandType {
  submit,
  beginReview,
  requestChanges,
  resubmit,
  approve,
}

enum StatsWorkQueueSection {
  preparation,
  liveCapture,
  needsStats,
  changesRequested,
  awaitingReview,
  complete,
  notActionable,
}

final class CandidateWorkflowException implements Exception {
  const CandidateWorkflowException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

final class CandidateRevisionReference {
  CandidateRevisionReference({
    required this.revisionId,
    required this.revisionNumber,
    required this.revisionHash,
  }) {
    OfficialStatIdentifiers.requireValid('revisionId', revisionId);
    if (revisionNumber <= 0) {
      throw ArgumentError.value(
        revisionNumber,
        'revisionNumber',
        'must be a positive integer',
      );
    }
    OfficialStatIdentifiers.requireSha256('revisionHash', revisionHash);
  }

  final String revisionId;
  final int revisionNumber;
  final String revisionHash;

  Map<String, Object?> toContractMap() => {
    'revisionHash': revisionHash,
    'revisionId': revisionId,
    'revisionNumber': revisionNumber,
  };

  bool hasSameIdentity(CandidateRevisionReference other) =>
      revisionId == other.revisionId &&
      revisionNumber == other.revisionNumber &&
      revisionHash == other.revisionHash;
}

/// Exact, retryable command envelope for one candidate review transition.
///
/// A resubmission binds both the changes-requested revision and its immutable
/// successor. Other commands bind only [targetRevision].
final class CandidateReviewCommand {
  CandidateReviewCommand({
    required this.commandId,
    required this.type,
    required this.actorAccountId,
    required this.expectedWorkflowVersion,
    required this.targetRevision,
    this.successorRevision,
    this.reasonCode,
    this.reason,
  }) {
    OfficialStatIdentifiers.requireValid('commandId', commandId);
    OfficialStatIdentifiers.requireValid('actorAccountId', actorAccountId);
    if (expectedWorkflowVersion < 0) {
      throw ArgumentError.value(
        expectedWorkflowVersion,
        'expectedWorkflowVersion',
        'must be nonnegative',
      );
    }
    final requiresSuccessor = type == CandidateReviewCommandType.resubmit;
    if (requiresSuccessor != (successorRevision != null)) {
      throw ArgumentError(
        'Only resubmit commands require a successor revision',
      );
    }
    final requiresReason =
        type == CandidateReviewCommandType.requestChanges ||
        type == CandidateReviewCommandType.resubmit;
    if (requiresReason) {
      _requireReasonCode(reasonCode);
      _requireReason(reason);
    } else if (reasonCode != null || reason != null) {
      throw ArgumentError('This command type does not accept a reason');
    }
  }

  final String commandId;
  final CandidateReviewCommandType type;
  final String actorAccountId;
  final int expectedWorkflowVersion;
  final CandidateRevisionReference targetRevision;
  final CandidateRevisionReference? successorRevision;
  final String? reasonCode;
  final String? reason;

  Map<String, Object?> toContractMap() => {
    'actorAccountId': actorAccountId,
    'commandId': commandId,
    'commandType': type.name,
    'expectedWorkflowVersion': expectedWorkflowVersion,
    'reason': reason,
    'reasonCode': reasonCode,
    'successorRevision': successorRevision?.toContractMap(),
    'targetRevision': targetRevision.toContractMap(),
  };

  String get requestHash =>
      OfficialStatCanonicalEncoding.sha256Hex(toContractMap());
}

final class CandidateReviewEvent {
  const CandidateReviewEvent({
    required this.commandId,
    required this.commandType,
    required this.actorAccountId,
    required this.targetRevision,
    required this.resultingReviewState,
    required this.resultingWorkflowVersion,
    this.successorRevision,
    this.reasonCode,
    this.reason,
  });

  final String commandId;
  final CandidateReviewCommandType commandType;
  final String actorAccountId;
  final CandidateRevisionReference targetRevision;
  final CandidateRevisionReference? successorRevision;
  final CandidateReviewState resultingReviewState;
  final int resultingWorkflowVersion;
  final String? reasonCode;
  final String? reason;
}

/// Immutable candidate state. Play, capture, review, and delivery are kept as
/// independent dimensions so no timestamp or pending-write flag can impersonate
/// a completed game, an accepted upload, or an approved revision.
final class CandidateStatsWorkflow {
  CandidateStatsWorkflow._({
    required this.scope,
    required this.playState,
    required this.captureStage,
    required this.reviewState,
    required this.deliveryState,
    required this.workflowVersion,
    required this.activeRevision,
    required this.submittedRevision,
    required this.acceptedDeliveryRevision,
    required List<CandidateReviewEvent> events,
    required Map<String, String> processedCommandHashes,
  }) : events = List.unmodifiable(events),
       processedCommandHashes = UnmodifiableMapView(
         Map<String, String>.from(processedCommandHashes),
       );

  factory CandidateStatsWorkflow.preparing({
    required GameScope scope,
    PlayState playState = PlayState.scheduled,
  }) => CandidateStatsWorkflow._(
    scope: scope,
    playState: playState,
    captureStage: CandidateCaptureStage.preparation,
    reviewState: CandidateReviewState.draft,
    deliveryState: JournalDeliveryState.savedOnDevice,
    workflowVersion: 0,
    activeRevision: null,
    submittedRevision: null,
    acceptedDeliveryRevision: null,
    events: const [],
    processedCommandHashes: const {},
  );

  final GameScope scope;
  final PlayState playState;
  final CandidateCaptureStage captureStage;
  final CandidateReviewState reviewState;
  final JournalDeliveryState deliveryState;
  final int workflowVersion;
  final CandidateRevisionReference? activeRevision;
  final CandidateRevisionReference? submittedRevision;
  final CandidateRevisionReference? acceptedDeliveryRevision;
  final List<CandidateReviewEvent> events;
  final Map<String, String> processedCommandHashes;

  CandidateStatsWorkflow openDraft({
    required CandidateRevisionReference revision,
    required CaptureMode captureMode,
  }) {
    if (captureStage != CandidateCaptureStage.preparation ||
        activeRevision != null) {
      throw const CandidateWorkflowException(
        'lifecycleDenied',
        'A draft can only be opened from preparation',
      );
    }
    final isLive = captureMode == CaptureMode.liveCapture;
    if (captureMode == CaptureMode.historicalImport) {
      throw const CandidateWorkflowException(
        'unsupportedCaptureMode',
        'Historical import remains a separate reviewed migration workflow',
      );
    }
    final canOpen = isLive
        ? const {
            PlayState.inProgress,
            PlayState.suspended,
            PlayState.completed,
            PlayState.administrativelyTerminated,
          }.contains(playState)
        : const {
            PlayState.completed,
            PlayState.administrativelyTerminated,
          }.contains(playState);
    if (!canOpen) {
      throw CandidateWorkflowException(
        'playStateMismatch',
        '${captureMode.name} cannot open while play is ${playState.name}',
      );
    }
    return _copyWith(
      captureStage: isLive
          ? CandidateCaptureStage.liveDraft
          : CandidateCaptureStage.postGameDraft,
      activeRevision: revision,
      setActiveRevision: true,
      acceptedDeliveryRevision: null,
      setAcceptedDeliveryRevision: true,
    );
  }

  /// Opens the exact successor requested by the reviewer without mutating the
  /// already-submitted revision. Local delivery starts over for N+1.
  CandidateStatsWorkflow openSuccessorDraft(
    CandidateRevisionReference successor,
  ) {
    if (reviewState != CandidateReviewState.changesRequested ||
        submittedRevision == null) {
      throw const CandidateWorkflowException(
        'lifecycleDenied',
        'A successor can only open after changes are requested',
      );
    }
    final predecessor = submittedRevision!;
    if (successor.revisionNumber != predecessor.revisionNumber + 1 ||
        successor.revisionId == predecessor.revisionId ||
        successor.revisionHash == predecessor.revisionHash) {
      throw const CandidateWorkflowException(
        'invalidSuccessorRevision',
        'Correction work requires a distinct immutable N+1 revision',
      );
    }
    return _copyWith(
      captureStage: CandidateCaptureStage.postGameDraft,
      deliveryState: JournalDeliveryState.savedOnDevice,
      workflowVersion: workflowVersion + 1,
      activeRevision: successor,
      setActiveRevision: true,
      acceptedDeliveryRevision: null,
      setAcceptedDeliveryRevision: true,
    );
  }

  CandidateStatsWorkflow withPlayState(PlayState next) {
    if (!OfficialStatLifecycle.permitsPlay(playState, next)) {
      throw CandidateWorkflowException(
        'lifecycleDenied',
        'Play cannot transition from ${playState.name} to ${next.name}',
      );
    }
    return _copyWith(playState: next);
  }

  CandidateStatsWorkflow withDeliveryState(JournalDeliveryState next) {
    const transitions = <JournalDeliveryState, Set<JournalDeliveryState>>{
      JournalDeliveryState.savedOnDevice: {
        JournalDeliveryState.queued,
        JournalDeliveryState.needsAttention,
      },
      JournalDeliveryState.queued: {
        JournalDeliveryState.sending,
        JournalDeliveryState.needsAttention,
      },
      JournalDeliveryState.sending: {
        JournalDeliveryState.accepted,
        JournalDeliveryState.queued,
        JournalDeliveryState.needsAttention,
      },
      JournalDeliveryState.accepted: {},
      JournalDeliveryState.needsAttention: {JournalDeliveryState.queued},
    };
    if (!transitions[deliveryState]!.contains(next)) {
      throw CandidateWorkflowException(
        'deliveryTransitionDenied',
        'Delivery cannot transition from ${deliveryState.name} to ${next.name}',
      );
    }
    return _copyWith(
      deliveryState: next,
      acceptedDeliveryRevision: next == JournalDeliveryState.accepted
          ? activeRevision
          : acceptedDeliveryRevision,
      setAcceptedDeliveryRevision: next == JournalDeliveryState.accepted,
    );
  }

  CandidateStatsWorkflow apply(CandidateReviewCommand command) {
    final priorHash = processedCommandHashes[command.commandId];
    if (priorHash != null) {
      if (priorHash != command.requestHash) {
        throw const CandidateWorkflowException(
          'payloadKeyConflict',
          'The command ID was already used with different immutable content',
        );
      }
      return this;
    }
    if (command.expectedWorkflowVersion != workflowVersion) {
      throw CandidateWorkflowException(
        'staleWorkflowVersion',
        'Expected workflow version ${command.expectedWorkflowVersion}, '
            'current version is $workflowVersion',
      );
    }
    final active = activeRevision;
    if (active == null) {
      throw const CandidateWorkflowException(
        'revisionUnavailable',
        'No immutable candidate revision is open',
      );
    }

    late final CandidateReviewState nextState;
    CandidateRevisionReference nextActive = active;
    CandidateRevisionReference? nextSubmitted = submittedRevision;
    switch (command.type) {
      case CandidateReviewCommandType.submit:
        _requireState({CandidateReviewState.draft});
        _requireExactRevision(command.targetRevision, active);
        _requireCompletedPlay();
        if (deliveryState != JournalDeliveryState.accepted ||
            acceptedDeliveryRevision == null ||
            !acceptedDeliveryRevision!.hasSameIdentity(active)) {
          throw const CandidateWorkflowException(
            'unacceptedJournalHead',
            'Submission requires durable receipts for the sealed journal head',
          );
        }
        nextState = CandidateReviewState.submitted;
        nextSubmitted = active;
      case CandidateReviewCommandType.beginReview:
        _requireState({
          CandidateReviewState.submitted,
          CandidateReviewState.resubmitted,
        });
        _requireExactRevision(command.targetRevision, submittedRevision!);
        nextState = CandidateReviewState.underReview;
      case CandidateReviewCommandType.requestChanges:
        _requireState({
          CandidateReviewState.submitted,
          CandidateReviewState.underReview,
        });
        _requireExactRevision(command.targetRevision, submittedRevision!);
        nextState = CandidateReviewState.changesRequested;
      case CandidateReviewCommandType.resubmit:
        _requireState({CandidateReviewState.changesRequested});
        _requireExactRevision(command.targetRevision, submittedRevision!);
        _requireCompletedPlay();
        final successor = command.successorRevision!;
        if (successor.revisionNumber !=
                command.targetRevision.revisionNumber + 1 ||
            successor.revisionId == command.targetRevision.revisionId ||
            successor.revisionHash == command.targetRevision.revisionHash) {
          throw const CandidateWorkflowException(
            'invalidSuccessorRevision',
            'Resubmission requires a distinct immutable N+1 revision',
          );
        }
        if (!successor.hasSameIdentity(active)) {
          throw const CandidateWorkflowException(
            'successorRevisionNotOpen',
            'The N+1 revision must be opened and preserved before resubmission',
          );
        }
        if (deliveryState != JournalDeliveryState.accepted ||
            acceptedDeliveryRevision == null ||
            !acceptedDeliveryRevision!.hasSameIdentity(successor)) {
          throw const CandidateWorkflowException(
            'unacceptedJournalHead',
            'Resubmission requires durable receipts for the successor head',
          );
        }
        nextState = CandidateReviewState.resubmitted;
        nextActive = successor;
        nextSubmitted = successor;
      case CandidateReviewCommandType.approve:
        _requireState({CandidateReviewState.underReview});
        _requireExactRevision(command.targetRevision, submittedRevision!);
        final submitter = _latestSubmissionActor();
        if (submitter == command.actorAccountId) {
          throw const CandidateWorkflowException(
            'separationOfDutiesDenied',
            'A submitter cannot approve the same candidate revision',
          );
        }
        nextState = CandidateReviewState.approved;
    }

    final nextVersion = workflowVersion + 1;
    final event = CandidateReviewEvent(
      commandId: command.commandId,
      commandType: command.type,
      actorAccountId: command.actorAccountId,
      targetRevision: command.targetRevision,
      successorRevision: command.successorRevision,
      resultingReviewState: nextState,
      resultingWorkflowVersion: nextVersion,
      reasonCode: command.reasonCode,
      reason: command.reason,
    );
    return _copyWith(
      captureStage: CandidateCaptureStage.sealed,
      reviewState: nextState,
      workflowVersion: nextVersion,
      activeRevision: nextActive,
      setActiveRevision: true,
      submittedRevision: nextSubmitted,
      setSubmittedRevision: true,
      events: [...events, event],
      processedCommandHashes: {
        ...processedCommandHashes,
        command.commandId: command.requestHash,
      },
    );
  }

  void _requireState(Set<CandidateReviewState> allowed) {
    if (!allowed.contains(reviewState)) {
      throw CandidateWorkflowException(
        'lifecycleDenied',
        'Command is not allowed while review is ${reviewState.name}',
      );
    }
  }

  void _requireCompletedPlay() {
    if (playState != PlayState.completed &&
        playState != PlayState.administrativelyTerminated) {
      throw const CandidateWorkflowException(
        'playNotComplete',
        'Final submission requires explicit completion or adjudication',
      );
    }
  }

  String? _latestSubmissionActor() {
    for (final event in events.reversed) {
      if (event.commandType == CandidateReviewCommandType.submit ||
          event.commandType == CandidateReviewCommandType.resubmit) {
        return event.actorAccountId;
      }
    }
    return null;
  }

  static void _requireExactRevision(
    CandidateRevisionReference actual,
    CandidateRevisionReference expected,
  ) {
    if (!actual.hasSameIdentity(expected)) {
      throw const CandidateWorkflowException(
        'staleRevision',
        'The command does not target the current immutable revision',
      );
    }
  }

  CandidateStatsWorkflow _copyWith({
    PlayState? playState,
    CandidateCaptureStage? captureStage,
    CandidateReviewState? reviewState,
    JournalDeliveryState? deliveryState,
    int? workflowVersion,
    CandidateRevisionReference? activeRevision,
    bool setActiveRevision = false,
    CandidateRevisionReference? submittedRevision,
    bool setSubmittedRevision = false,
    CandidateRevisionReference? acceptedDeliveryRevision,
    bool setAcceptedDeliveryRevision = false,
    List<CandidateReviewEvent>? events,
    Map<String, String>? processedCommandHashes,
  }) => CandidateStatsWorkflow._(
    scope: scope,
    playState: playState ?? this.playState,
    captureStage: captureStage ?? this.captureStage,
    reviewState: reviewState ?? this.reviewState,
    deliveryState: deliveryState ?? this.deliveryState,
    workflowVersion: workflowVersion ?? this.workflowVersion,
    activeRevision: setActiveRevision ? activeRevision : this.activeRevision,
    submittedRevision: setSubmittedRevision
        ? submittedRevision
        : this.submittedRevision,
    acceptedDeliveryRevision: setAcceptedDeliveryRevision
        ? acceptedDeliveryRevision
        : this.acceptedDeliveryRevision,
    events: events ?? this.events,
    processedCommandHashes:
        processedCommandHashes ?? this.processedCommandHashes,
  );
}

/// A queue input deliberately has no scheduled timestamp. Work placement is
/// derived from explicit play/review/assignment state only.
final class StatsWorkItem {
  const StatsWorkItem({
    required this.gameId,
    required this.isAssigned,
    required this.playState,
    required this.captureStage,
    required this.reviewState,
  });

  final String gameId;
  final bool isAssigned;
  final PlayState playState;
  final CandidateCaptureStage captureStage;
  final CandidateReviewState reviewState;

  StatsWorkQueueSection get queueSection {
    if (!isAssigned ||
        playState == PlayState.cancelled ||
        playState == PlayState.postponed) {
      return StatsWorkQueueSection.notActionable;
    }
    if (reviewState == CandidateReviewState.approved) {
      return StatsWorkQueueSection.complete;
    }
    if (reviewState == CandidateReviewState.changesRequested) {
      return StatsWorkQueueSection.changesRequested;
    }
    if (const {
      CandidateReviewState.submitted,
      CandidateReviewState.underReview,
      CandidateReviewState.resubmitted,
    }.contains(reviewState)) {
      return StatsWorkQueueSection.awaitingReview;
    }
    if (playState == PlayState.inProgress || playState == PlayState.suspended) {
      return StatsWorkQueueSection.liveCapture;
    }
    if (playState == PlayState.completed ||
        playState == PlayState.administrativelyTerminated) {
      return StatsWorkQueueSection.needsStats;
    }
    return StatsWorkQueueSection.preparation;
  }
}

void _requireReasonCode(String? value) {
  if (value == null || !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)) {
    throw ArgumentError('reasonCode must use stable lower_snake_case');
  }
}

void _requireReason(String? value) {
  if (value == null || value.trim().isEmpty || value.length > 1000) {
    throw ArgumentError('reason must contain 1 through 1000 characters');
  }
}
