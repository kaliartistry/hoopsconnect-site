import '../../models/official_stats/candidate_review_workflow.dart';
import '../../models/official_stats/domain_contracts.dart';
import '../../models/official_stats/domain_enums.dart';
import '../../services/local_game_journal/courtside_recovery.dart';
import '../../services/local_game_journal/journal_models.dart';

/// Binds one immutable candidate revision to one prepared courtside workspace.
/// A correction must construct a new bridge for the exact N+1 revision.
final class CourtsideCandidateBridge {
  const CourtsideCandidateBridge({required this.revision});

  final CandidateRevisionReference revision;

  CandidateStatsWorkflow synchronize(
    CandidateStatsWorkflow workflow,
    CourtsideRecoverySnapshot recovery,
  ) {
    final active = workflow.activeRevision;
    final recoveryRevision = recovery.boundRevision;
    if (active == null ||
        !active.hasSameIdentity(revision) ||
        !_sameScope(workflow.scope, revision.scope) ||
        recoveryRevision.revisionId != revision.revisionId ||
        recoveryRevision.revisionNumber != revision.revisionNumber ||
        recoveryRevision.revisionHash != revision.revisionHash ||
        !_sameScope(recoveryRevision.scope, revision.scope)) {
      throw const CandidateWorkflowException(
        'courtsideRevisionMismatch',
        'Courtside delivery and recovery must bind the exact active candidate revision.',
      );
    }
    final acceptedEvidence = recovery.submissionEvidence;
    if (acceptedEvidence != null &&
        (acceptedEvidence.revision.revisionId != revision.revisionId ||
            acceptedEvidence.revision.revisionNumber !=
                revision.revisionNumber ||
            acceptedEvidence.revision.revisionHash != revision.revisionHash ||
            !_sameScope(acceptedEvidence.revision.scope, revision.scope))) {
      throw const CandidateWorkflowException(
        'courtsideRevisionMismatch',
        'Accepted courtside evidence belongs to a different candidate revision.',
      );
    }
    if (recovery.operations.isEmpty && !recovery.revisionDeliveryAccepted) {
      return workflow;
    }
    final target = _aggregateDeliveryState(recovery);
    var current = workflow;
    for (final step in _transitionPath(current.deliveryState, target)) {
      current = current.withDeliveryState(step);
    }
    return current;
  }

  static JournalDeliveryState _aggregateDeliveryState(
    CourtsideRecoverySnapshot recovery,
  ) {
    if (recovery.phase == CourtsideRecoveryPhase.captureDisabled ||
        recovery.phase == CourtsideRecoveryPhase.needsAttention ||
        recovery.workspaceRecoveryState ==
            LocalWorkspaceRecoveryState.conflictBranch ||
        recovery.operations.any(
          (operation) => operation.state == JournalDeliveryState.needsAttention,
        )) {
      return JournalDeliveryState.needsAttention;
    }
    if (recovery.operations.any(
      (operation) => operation.state == JournalDeliveryState.sending,
    )) {
      return JournalDeliveryState.sending;
    }
    if (recovery.revisionDeliveryAccepted) {
      return JournalDeliveryState.accepted;
    }
    if (recovery.workspaceSubmissionState ==
        WorkspaceSubmissionState.captureOpen) {
      return JournalDeliveryState.savedOnDevice;
    }
    if (recovery.operations.any(
      (operation) => operation.state == JournalDeliveryState.queued,
    )) {
      return JournalDeliveryState.queued;
    }
    return JournalDeliveryState.savedOnDevice;
  }

  static List<JournalDeliveryState> _transitionPath(
    JournalDeliveryState current,
    JournalDeliveryState target,
  ) {
    if (current == target || current == JournalDeliveryState.accepted) {
      return const [];
    }
    if (target == JournalDeliveryState.needsAttention) {
      return [JournalDeliveryState.needsAttention];
    }
    if (current == JournalDeliveryState.needsAttention) {
      return [
        JournalDeliveryState.queued,
        if (target == JournalDeliveryState.sending ||
            target == JournalDeliveryState.accepted)
          JournalDeliveryState.sending,
        if (target == JournalDeliveryState.accepted)
          JournalDeliveryState.accepted,
      ];
    }
    if (current == JournalDeliveryState.savedOnDevice) {
      return [
        JournalDeliveryState.queued,
        if (target == JournalDeliveryState.sending ||
            target == JournalDeliveryState.accepted)
          JournalDeliveryState.sending,
        if (target == JournalDeliveryState.accepted)
          JournalDeliveryState.accepted,
      ];
    }
    if (current == JournalDeliveryState.queued) {
      return [
        if (target == JournalDeliveryState.sending ||
            target == JournalDeliveryState.accepted)
          JournalDeliveryState.sending,
        if (target == JournalDeliveryState.accepted)
          JournalDeliveryState.accepted,
      ];
    }
    if (current == JournalDeliveryState.sending) {
      return [
        if (target == JournalDeliveryState.queued) JournalDeliveryState.queued,
        if (target == JournalDeliveryState.accepted)
          JournalDeliveryState.accepted,
      ];
    }
    return const [];
  }
}

bool _sameScope(GameScope left, GameScope right) =>
    left.associationId == right.associationId &&
    left.competitionId == right.competitionId &&
    left.seasonId == right.seasonId &&
    left.divisionId == right.divisionId &&
    left.phaseId == right.phaseId &&
    left.gameId == right.gameId;
