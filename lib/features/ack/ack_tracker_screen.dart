import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/ack_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../models/post_model.dart';

class AckTrackerScreen extends ConsumerWidget {
  const AckTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ackPostsAsync = ref.watch(postsRequiringAckProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Ack Tracker'),
      ),
      body: ackPostsAsync.when(
        data: (posts) {
          if (posts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No posts requiring acknowledgment',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.paddingMd),
            itemCount: posts.length,
            itemBuilder: (context, i) => _AckPostCard(post: posts[i]),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _AckPostCard extends ConsumerStatefulWidget {
  final PostModel post;
  const _AckPostCard({required this.post});

  @override
  ConsumerState<_AckPostCard> createState() => _AckPostCardState();
}

class _AckPostCardState extends ConsumerState<_AckPostCard> {
  bool _expanded = false;
  bool _sendingReminder = false;

  Future<void> _remindAllPending() async {
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;
    setState(() => _sendingReminder = true);
    try {
      await ref
          .read(postRepositoryProvider)
          .requestManualAckReminder(assocId, widget.post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder queued — pending reps will be pinged.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reminder failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingReminder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isOverdue = post.isAckOverdue();
    final allAcked = post.ackCount >= post.expectedAckCount && post.expectedAckCount > 0;

    // Separate acked from pending
    final ackedUserIds = post.ackStatus.keys.toSet();
    final pendingEntries = post.expectedAcks.entries
        .where((e) => !ackedUserIds.contains(e.key))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: allAcked
              ? AppColors.success
              : isOverdue
                  ? AppColors.urgent
                  : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          post.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: post.ackProgress,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              allAcked ? AppColors.success : AppColors.ack,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${post.ackCount}/${post.expectedAckCount}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: allAcked ? AppColors.success : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (post.ackDeadline != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Deadline: ${DateFormat('MMM d, h:mm a').format(post.ackDeadline!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? AppColors.urgent : AppColors.textMuted,
                        fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expanded details
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Acknowledged section
                  if (post.ackStatus.isNotEmpty) ...[
                    const Text(
                      'Acknowledged',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...post.ackStatus.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.value.name} (${e.value.teamName})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              DateFormat('MMM d, h:mm a').format(e.value.ackedAt),
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Pending section
                  if (pendingEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Pending',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isOverdue ? AppColors.urgent : AppColors.ack,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...pendingEntries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.pending_outlined,
                              size: 16,
                              color: isOverdue ? AppColors.urgent : AppColors.ack,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.value.name} (${e.value.teamName})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (e.value.phone != null) ...[
                              IconButton(
                                icon: const Icon(Icons.sms_outlined, size: 16),
                                tooltip: 'Send SMS',
                                onPressed: () => launchUrl(
                                  Uri.parse(
                                    'sms:${e.value.phone}'
                                    '?body=${Uri.encodeComponent('Reminder — please ack: ${post.title}')}',
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                color: AppColors.info,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.phone, size: 16),
                                tooltip: 'Call',
                                onPressed: () => launchUrl(
                                  Uri.parse('tel:${e.value.phone}'),
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                color: AppColors.primary,
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _sendingReminder ? null : _remindAllPending,
                        icon: _sendingReminder
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.notifications_active_outlined,
                                size: 16),
                        label: Text(
                          _sendingReminder
                              ? 'Sending…'
                              : 'Remind all pending (${pendingEntries.length})',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.ack,
                          side: const BorderSide(color: AppColors.ack),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
