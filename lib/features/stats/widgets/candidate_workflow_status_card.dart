import 'package:flutter/material.dart';

import '../../../core/widgets/app_state_message.dart';
import '../../../models/official_stats/candidate_review_workflow.dart';
import '../../../models/official_stats/domain_enums.dart';

/// Candidate-side status surface for the future v2 stat-entry route.
///
/// It intentionally shows local delivery and human review separately. This
/// widget is not wired into the production router while the server contract is
/// dormant.
class CandidateWorkflowStatusCard extends StatelessWidget {
  const CandidateWorkflowStatusCard({
    super.key,
    required this.workflow,
    this.onRetryDelivery,
  });

  final CandidateStatsWorkflow workflow;
  final VoidCallback? onRetryDelivery;

  @override
  Widget build(BuildContext context) {
    final delivery = _deliveryPresentation(workflow);
    final review = _reviewPresentation(workflow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStateMessage(
          title: delivery.title,
          message: delivery.message,
          tone: delivery.tone,
          icon: delivery.icon,
          compact: true,
          actionLabel:
              workflow.deliveryState == JournalDeliveryState.needsAttention &&
                  onRetryDelivery != null
              ? 'Try upload again'
              : null,
          onAction:
              workflow.deliveryState == JournalDeliveryState.needsAttention
              ? onRetryDelivery
              : null,
        ),
        const SizedBox(height: 8),
        AppStateMessage(
          title: review.title,
          message: review.message,
          tone: review.tone,
          icon: review.icon,
          compact: true,
        ),
      ],
    );
  }
}

({String title, String message, AppStateTone tone, IconData icon})
_deliveryPresentation(CandidateStatsWorkflow workflow) {
  final identity = _revisionIdentity(workflow.activeRevision);
  return switch (workflow.deliveryState) {
    JournalDeliveryState.savedOnDevice => (
      title: 'Saved on this device',
      message: '$identity is not uploaded yet. Keep it on this device.',
      tone: AppStateTone.warning,
      icon: Icons.phone_android_outlined,
    ),
    JournalDeliveryState.queued => (
      title: 'Queued for upload',
      message: 'Keep the app open while the server accepts $identity.',
      tone: AppStateTone.info,
      icon: Icons.cloud_upload_outlined,
    ),
    JournalDeliveryState.sending => (
      title: 'Uploading saved work',
      message: 'Waiting for an exact server receipt for $identity.',
      tone: AppStateTone.info,
      icon: Icons.sync,
    ),
    JournalDeliveryState.accepted => (
      title: 'Accepted by the server',
      message: '$identity has a durable server receipt.',
      tone: AppStateTone.success,
      icon: Icons.cloud_done_outlined,
    ),
    JournalDeliveryState.needsAttention => (
      title: 'Upload needs attention',
      message: '$identity is preserved on this device. Review the issue.',
      tone: AppStateTone.error,
      icon: Icons.cloud_off_outlined,
    ),
  };
}

({String title, String message, AppStateTone tone, IconData icon})
_reviewPresentation(CandidateStatsWorkflow workflow) {
  final revision = workflow.submittedRevision ?? workflow.activeRevision;
  final revisionLabel = '${_revisionIdentity(revision)} is the review target.';
  return switch (workflow.reviewState) {
    CandidateReviewState.draft => (
      title: 'Draft, not submitted',
      message: revisionLabel,
      tone: AppStateTone.neutral,
      icon: Icons.edit_note_outlined,
    ),
    CandidateReviewState.submitted => (
      title: 'Submitted for review',
      message: revisionLabel,
      tone: AppStateTone.info,
      icon: Icons.outbox_outlined,
    ),
    CandidateReviewState.underReview => (
      title: 'Under review',
      message: revisionLabel,
      tone: AppStateTone.info,
      icon: Icons.fact_check_outlined,
    ),
    CandidateReviewState.changesRequested => (
      title: 'Changes requested',
      message: _changesRequestedMessage(workflow),
      tone: AppStateTone.warning,
      icon: Icons.rate_review_outlined,
    ),
    CandidateReviewState.resubmitted => (
      title: 'Correction resubmitted',
      message: revisionLabel,
      tone: AppStateTone.info,
      icon: Icons.replay_outlined,
    ),
    CandidateReviewState.approved => (
      title: 'Revision approved',
      message: '$revisionLabel Certification and publication are separate.',
      tone: AppStateTone.success,
      icon: Icons.task_alt_outlined,
    ),
  };
}

String _changesRequestedMessage(CandidateStatsWorkflow workflow) {
  final reviewed = _revisionIdentity(workflow.submittedRevision);
  final active = _revisionIdentity(workflow.activeRevision);
  final reason = _latestChangeReason(workflow);
  final correction =
      workflow.submittedRevision != null &&
          workflow.activeRevision != null &&
          !workflow.submittedRevision!.hasSameIdentity(workflow.activeRevision!)
      ? ' Correction delivery tracks $active.'
      : '';
  return 'Feedback targets $reviewed.$correction'
      '${reason == null ? '' : ' Reason: $reason'}';
}

String _revisionIdentity(CandidateRevisionReference? revision) {
  if (revision == null) return 'No sealed revision';
  final shortHash = revision.revisionHash.substring(0, 8);
  return 'Revision ${revision.revisionNumber} · ${revision.revisionId} · '
      '$shortHash…';
}

String? _latestChangeReason(CandidateStatsWorkflow workflow) {
  for (final event in workflow.events.reversed) {
    if (event.commandType == CandidateReviewCommandType.requestChanges) {
      return event.reason;
    }
  }
  return null;
}
