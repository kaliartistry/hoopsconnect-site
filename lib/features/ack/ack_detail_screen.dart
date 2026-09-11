import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/empty_state.dart';
import '../board/board_post_visibility.dart';
import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/role_preview_provider.dart';

class AckDetailScreen extends ConsumerWidget {
  final String postId;

  const AckDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(postDetailProvider(postId));
    final presentationUser = ref.watch(effectiveUserProvider);
    final realUser = ref.watch(currentUserProvider).valueOrNull;
    final assocId = ref.watch(currentAssociationIdProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Acknowledgment'),
      ),
      body: postAsync.when(
        data: (post) {
          if (post == null) {
            return const Center(child: Text('Post not found'));
          }
          if (!postIsVisibleInBoardPresentation(post, presentationUser)) {
            return const EmptyState(
              icon: Icons.visibility_off_outlined,
              title: 'Post hidden in this role preview',
              subtitle: 'Return to the Board to choose a visible post.',
            );
          }

          final userAcked = realUser != null && post.hasUserAcked(realUser.id);
          final previewShowsAcknowledge =
              presentationUser?.hasCapability('posts.acknowledge') ?? false;
          final realUserCanAcknowledge =
              realUser?.hasCapability('posts.acknowledge') ?? false;
          final isOverdue = post.isAckOverdue();

          return ListView(
            padding: const EdgeInsets.all(AppSizes.paddingMd),
            children: [
              // Post content card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: post.urgent ? AppColors.urgentBg : Colors.white,
                  border: Border.all(
                    color: post.urgent ? AppColors.urgent : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badges
                    Wrap(
                      spacing: 4,
                      children: [
                        if (post.urgent) _badge('URGENT', Colors.white, AppColors.urgent),
                        if (isOverdue) _badge('OVERDUE', Colors.white, AppColors.urgent),
                        _badge('ACK REQUIRED', Colors.white, AppColors.ack),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      post.body,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Metadata
                    Text(
                      'Posted by ${post.authorName} on ${DateFormat('MMM d, yyyy').format(post.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (post.ackDeadline != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Deadline: ${DateFormat('MMM d, yyyy h:mm a').format(post.ackDeadline!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isOverdue ? AppColors.urgent : AppColors.ack,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Ack progress
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Acknowledgment Progress',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${post.ackCount}/${post.expectedAckCount}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: post.ackProgress,
                        minHeight: 8,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          post.ackProgress >= 1.0
                              ? AppColors.success
                              : AppColors.ack,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Acknowledge button
              if (!userAcked &&
                  previewShowsAcknowledge &&
                  realUserCanAcknowledge) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final actingUser = ref
                          .read(currentUserProvider)
                          .valueOrNull;
                      if (assocId != null &&
                          actingUser?.hasCapability('posts.acknowledge') ==
                              true) {
                        ref
                            .read(postRepositoryProvider)
                            .acknowledge(assocId, post.id);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ack,
                    ),
                    icon: const Icon(Icons.check_circle, size: 20),
                    label: const Text(
                      'Acknowledge This Post',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],

              if (userAcked) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    border: Border.all(color: AppColors.success),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.success),
                      SizedBox(width: 12),
                      Text(
                        'You have acknowledged this post',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
