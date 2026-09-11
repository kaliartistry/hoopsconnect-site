import 'package:flutter/material.dart';

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
  });

  final CourtsideRecoverySnapshot snapshot;
  final VoidCallback? onRecoverForeground;
  final ValueChanged<String>? onRetryOperation;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(snapshot);
    final retryable = snapshot.operations
        .where(
          (operation) => operation.state == JournalDeliveryState.needsAttention,
        )
        .firstOrNull;
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
                        label: const Text('Retry while app is open'),
                      ),
                    ),
                  ),
                if (retryable != null &&
                    onRetryOperation != null &&
                    snapshot.workspaceRecoveryState !=
                        LocalWorkspaceRecoveryState.conflictBranch)
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey('courtside-retry-operation'),
                        onPressed: () =>
                            onRetryOperation!(retryable.operationId),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry preserved operation'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

({String title, String message, IconData icon}) _presentation(
  CourtsideRecoverySnapshot snapshot,
) {
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
  if (snapshot.operations.isEmpty) {
    return (
      title: 'Ready for stat entry',
      message: 'No plays have been saved for this workspace yet.',
      icon: Icons.sports_basketball_outlined,
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
