import 'package:flutter/material.dart';

import '../../../models/official_stats/command_contract.dart';
import '../../../models/official_stats/domain_enums.dart';
import '../../../services/local_game_journal/courtside_recovery.dart';
import '../../../services/local_game_journal/journal_models.dart';

/// Honest foreground-only delivery status for a future courtside route.
///
/// Actions use standard focusable Material buttons. No global key handler is
/// installed, so typing in a stat field or dialog cannot trigger recovery.
class CourtsideRecoveryStatusCard extends StatelessWidget {
  const CourtsideRecoveryStatusCard({
    super.key,
    required this.snapshot,
    this.onRecoverForeground,
    this.onRetryOperation,
    this.onReauthenticateAndRetryOperation,
  });

  final CourtsideRecoverySnapshot snapshot;
  final VoidCallback? onRecoverForeground;
  final ValueChanged<String>? onRetryOperation;
  final ValueChanged<String>? onReauthenticateAndRetryOperation;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(snapshot);
    final attentionOperations = snapshot.operations
        .where(
          (operation) => operation.state == JournalDeliveryState.needsAttention,
        )
        .toList(growable: false);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${presentation.title}. ${presentation.message}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(presentation.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            presentation.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(presentation.message),
                        ],
                      ),
                    ),
                  ],
                ),
                if (snapshot.operations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: JournalDeliveryState.values
                        .map(
                          (state) => Chip(
                            label: Text(
                              '${_label(state)}: ${snapshot.count(state)}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (snapshot.responseUnknownCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.responseUnknownCount} operation response '
                    'unknown. The saved command will be retried unchanged.',
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Uploads run only while this app is open or returns to the '
                  'foreground. Closing the web app stops delivery.',
                ),
                if (onRecoverForeground != null &&
                    snapshot.phase != CourtsideRecoveryPhase.delivering &&
                    snapshot.phase != CourtsideRecoveryPhase.signedOut &&
                    snapshot.phase != CourtsideRecoveryPhase.captureDisabled)
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('courtside-recover-foreground'),
                        onPressed: onRecoverForeground,
                        icon: const Icon(Icons.sync),
                        label: const Text('Check queued delivery'),
                      ),
                    ),
                  ),
                for (final (index, operation)
                    in attentionOperations.indexed) ...[
                  const SizedBox(height: 8),
                  _RecoveryOperationRow(
                    operation: operation,
                    focusOrder: 2 + index.toDouble(),
                    actionsEnabled:
                        snapshot.workspaceRecoveryState !=
                        LocalWorkspaceRecoveryState.conflictBranch,
                    onRetryOperation: onRetryOperation,
                    onReauthenticateAndRetryOperation:
                        onReauthenticateAndRetryOperation,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryOperationRow extends StatelessWidget {
  const _RecoveryOperationRow({
    required this.operation,
    required this.focusOrder,
    required this.actionsEnabled,
    required this.onRetryOperation,
    required this.onReauthenticateAndRetryOperation,
  });

  final CourtsideOperationStatus operation;
  final double focusOrder;
  final bool actionsEnabled;
  final ValueChanged<String>? onRetryOperation;
  final ValueChanged<String>? onReauthenticateAndRetryOperation;

  @override
  Widget build(BuildContext context) {
    final disposition = _disposition(operation.retryClassification);
    final canRetry =
        actionsEnabled &&
        operation.retryClassification == RetryClassification.retrySameCommand &&
        onRetryOperation != null;
    final canReauthenticate =
        actionsEnabled &&
        operation.retryClassification ==
            RetryClassification.refreshAuthenticationThenRetrySameCommand &&
        onReauthenticateAndRetryOperation != null;
    return Semantics(
      container: true,
      label:
          'Saved operation ${operation.localSequence + 1}. '
          '${disposition.title}. ${disposition.message}',
      child: DecoratedBox(
        key: ValueKey('courtside-recovery-operation-${operation.operationId}'),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Saved operation ${operation.localSequence + 1}: '
                '${disposition.title}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(disposition.message),
              if (canRetry) ...[
                const SizedBox(height: 8),
                FocusTraversalOrder(
                  order: NumericFocusOrder(focusOrder),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: ValueKey(
                        'courtside-retry-operation-${operation.operationId}',
                      ),
                      onPressed: () => onRetryOperation!(operation.operationId),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry preserved operation'),
                    ),
                  ),
                ),
              ],
              if (canReauthenticate) ...[
                const SizedBox(height: 8),
                FocusTraversalOrder(
                  order: NumericFocusOrder(focusOrder),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: ValueKey(
                        'courtside-reauthenticate-operation-'
                        '${operation.operationId}',
                      ),
                      onPressed: () => onReauthenticateAndRetryOperation!(
                        operation.operationId,
                      ),
                      icon: const Icon(Icons.lock_reset_outlined),
                      label: const Text('Sign in again, then retry'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({String title, String message}) _disposition(
  RetryClassification? classification,
) => switch (classification) {
  RetryClassification.retrySameCommand => (
    title: 'Safe unchanged retry',
    message: 'This exact saved command can be sent again unchanged.',
  ),
  RetryClassification.refreshAuthenticationThenRetrySameCommand => (
    title: 'Account verification required',
    message:
        'Sign in again and verify this account before retrying the unchanged saved command.',
  ),
  RetryClassification.refreshStateThenCreateNewCommand => (
    title: 'Refresh game state',
    message:
        'Refresh assignment and revision state, then create a new command. This saved command will not be resent.',
  ),
  RetryClassification.operatorResolutionRequired => (
    title: 'Operator resolution required',
    message:
        'Assignment or conflict ownership must be resolved. This saved command will not be resent directly.',
  ),
  RetryClassification.never => (
    title: 'Permanent rejection',
    message:
        'This saved command cannot be retried. It remains available for review.',
  ),
  null => (
    title: 'Review required',
    message:
        'No safe retry policy was recorded. This saved command remains on this device.',
  ),
};

({String title, String message, IconData icon}) _presentation(
  CourtsideRecoverySnapshot snapshot,
) {
  if (snapshot.phase == CourtsideRecoveryPhase.signedOut) {
    return (
      title: 'Saved work stays on this device',
      message:
          'You are signed out. Nothing was discarded or sent under another account.',
      icon: Icons.lock_outline,
    );
  }
  if (snapshot.phase == CourtsideRecoveryPhase.captureDisabled) {
    return (
      title: 'Stat capture is paused',
      message:
          'Durable storage could not be proven. Existing work is not being discarded.',
      icon: Icons.phonelink_erase_outlined,
    );
  }
  if (snapshot.workspaceRecoveryState ==
      LocalWorkspaceRecoveryState.conflictBranch) {
    return (
      title: 'Writer conflict needs attention',
      message:
          'This device’s branch is preserved. A reviewer must resolve assignment ownership.',
      icon: Icons.call_split_outlined,
    );
  }
  if (snapshot.phase == CourtsideRecoveryPhase.preparing) {
    return (
      title: 'Preparing this game',
      message: 'Checking the exact assignment, rules, roster, and local store.',
      icon: Icons.inventory_2_outlined,
    );
  }
  if (snapshot.revisionDeliveryAccepted) {
    return (
      title: 'Revision delivery accepted',
      message:
          'Capture is closed and every saved operation has an exact durable receipt.',
      icon: Icons.cloud_done_outlined,
    );
  }
  if (snapshot.submittedWithoutProvableRevision) {
    return (
      title: 'Submitted revision needs recovery',
      message:
          'The workspace is closed, but exact accepted-revision evidence could not be proven.',
      icon: Icons.report_problem_outlined,
    );
  }
  if (snapshot.operations.isEmpty) {
    return (
      title: 'Ready for stat entry',
      message: 'No plays have been saved for this workspace yet.',
      icon: Icons.sports_basketball_outlined,
    );
  }
  if (snapshot.allAccepted) {
    if (snapshot.workspaceSubmissionState ==
        WorkspaceSubmissionState.submissionQueued) {
      return (
        title: 'Finalizing revision delivery',
        message:
            'Every operation has a receipt. Waiting for the submitted workspace checkpoint.',
        icon: Icons.sync,
      );
    }
    return (
      title: 'Saved plays accepted; draft still open',
      message:
          'Current operations have receipts, but this revision is not submitted yet.',
      icon: Icons.cloud_done_outlined,
    );
  }
  if (snapshot.phase == CourtsideRecoveryPhase.delivering) {
    return (
      title: 'Sending saved work',
      message: 'Keep this app open while the server returns exact receipts.',
      icon: Icons.cloud_upload_outlined,
    );
  }
  if (snapshot.phase == CourtsideRecoveryPhase.needsAttention) {
    final attention = snapshot.operations
        .where(
          (operation) => operation.state == JournalDeliveryState.needsAttention,
        )
        .toList(growable: false);
    if (attention.length > 1) {
      return (
        title: '${attention.length} saved operations need attention',
        message:
            'Review every operation below. Each preserved command has its own safe disposition.',
        icon: Icons.cloud_off_outlined,
      );
    }
    final policy = attention.firstOrNull?.retryClassification;
    if (policy ==
        RetryClassification.refreshAuthenticationThenRetrySameCommand) {
      return (
        title: 'Sign in again to retry',
        message:
            'The preserved command can be retried unchanged only after this account is verified again.',
        icon: Icons.lock_reset_outlined,
      );
    }
    if (policy == RetryClassification.refreshStateThenCreateNewCommand) {
      return (
        title: 'Game state changed',
        message:
            'Refresh assignment and revision state, then create a new command. This preserved command will not be resent.',
        icon: Icons.update_outlined,
      );
    }
    if (policy == RetryClassification.operatorResolutionRequired) {
      return (
        title: 'Operator resolution required',
        message:
            'The preserved command will not be resent until assignment or conflict ownership is resolved.',
        icon: Icons.support_agent_outlined,
      );
    }
    if (policy == RetryClassification.never) {
      return (
        title: 'This command cannot be retried',
        message:
            'The server rejected the preserved command permanently. It remains available for review.',
        icon: Icons.block_outlined,
      );
    }
    return (
      title: 'Saved work needs attention',
      message: 'The operations remain on this device and were not discarded.',
      icon: Icons.cloud_off_outlined,
    );
  }
  return (
    title: 'Saved on this device',
    message: 'Some operations are still queued or waiting for a receipt.',
    icon: Icons.phone_android_outlined,
  );
}

String _label(JournalDeliveryState state) => switch (state) {
  JournalDeliveryState.savedOnDevice => 'On device',
  JournalDeliveryState.queued => 'Queued',
  JournalDeliveryState.sending => 'Sending',
  JournalDeliveryState.accepted => 'Accepted',
  JournalDeliveryState.needsAttention => 'Needs attention',
};
