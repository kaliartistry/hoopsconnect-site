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
    final delivery = _deliveryPresentation(workflow.deliveryState);
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
_deliveryPresentation(JournalDeliveryState state) => switch (state) {
  JournalDeliveryState.savedOnDevice => (
    title: 'Saved on this device',
    message: 'This work is not uploaded yet. Keep it on this device.',
    tone: AppStateTone.warning,
    icon: Icons.phone_android_outlined,
  ),
  JournalDeliveryState.queued => (
    title: 'Queued for upload',
    message: 'Keep the app open while the server accepts the saved work.',
    tone: AppStateTone.info,
    icon: Icons.cloud_upload_outlined,
  ),
  JournalDeliveryState.sending => (
    title: 'Uploading saved work',
    message: 'Waiting for an exact server receipt. Do not submit twice.',
    tone: AppStateTone.info,
    icon: Icons.sync,
  ),
  JournalDeliveryState.accepted => (
    title: 'Accepted by the server',
    message: 'The saved journal head has a durable server receipt.',
    tone: AppStateTone.success,
    icon: Icons.cloud_done_outlined,
  ),
  JournalDeliveryState.needsAttention => (
    title: 'Upload needs attention',
    message: 'Your work is still preserved on this device. Review the issue.',
    tone: AppStateTone.error,
    icon: Icons.cloud_off_outlined,
  ),
};

({String title, String message, AppStateTone tone, IconData icon})
_reviewPresentation(CandidateStatsWorkflow workflow) {
  final revision = workflow.submittedRevision ?? workflow.activeRevision;
  final revisionLabel = revision == null
      ? 'No revision has been sealed.'
      : 'Revision ${revision.revisionNumber} is the exact review target.';
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
      message: _latestChangeReason(workflow) ?? revisionLabel,
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

String? _latestChangeReason(CandidateStatsWorkflow workflow) {
  for (final event in workflow.events.reversed) {
    if (event.commandType == CandidateReviewCommandType.requestChanges) {
      return event.reason;
    }
  }
  return null;
}
