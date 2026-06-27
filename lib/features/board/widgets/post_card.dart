import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/post_model.dart';
import 'package:intl/intl.dart';

class PostCard extends StatelessWidget {
  final PostModel post;
  final String? currentUserId;
  final bool canEditDelete;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const PostCard({
    super.key,
    required this.post,
    this.currentUserId,
    this.canEditDelete = false,
    this.onAcknowledge,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool userAcked =
        currentUserId != null && post.hasUserAcked(currentUserId!);
    final bool needsAck = post.requiresAck && !userAcked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: post.urgent
              ? AppColors.urgentBg
              : needsAck
                  ? AppColors.ackBg
                  : Theme.of(context).cardColor,
          border: Border.all(
            color: post.urgent
                ? AppColors.urgent
                : needsAck
                    ? AppColors.ack
                    : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badges row + edit/delete menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (post.pinned) _badge('PINNED', AppColors.primary, AppColors.primaryLight),
                        if (post.urgent) _badge('URGENT', Colors.white, AppColors.urgent),
                        if (needsAck)
                          _badge('ACK REQUIRED', Colors.white, AppColors.ack),
                        if (userAcked)
                          _badge('ACKNOWLEDGED', Colors.white, AppColors.success),
                        _badge(
                          post.isAssociationPost ? 'ASSOCIATION' : 'TEAM',
                          post.isAssociationPost
                              ? AppColors.primary
                              : AppColors.info,
                          post.isAssociationPost
                              ? AppColors.primaryLight
                              : AppColors.infoLight,
                        ),
                      ],
                    ),
                  ),
                  if (canEditDelete)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (action) {
                          if (action == 'edit') onEdit?.call();
                          if (action == 'delete') onDelete?.call();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete',
                                style: TextStyle(color: AppColors.urgent)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                post.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),

              // Body
              Text(
                post.body,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // Live countdown for ack-required posts that aren't yet ack'd.
              if (needsAck && post.ackDeadline != null) ...[
                const SizedBox(height: 8),
                _AckCountdown(deadline: post.ackDeadline!),
              ],

              // Acknowledge button
              if (needsAck && onAcknowledge != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAcknowledge,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ack,
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Tap to Acknowledge'),
                  ),
                ),
              ],

              if (userAcked) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: AppColors.success),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Acknowledged · admin notified',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Footer
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${post.authorName} · ${post.teamName ?? "Association"} · ${_timeAgo(post.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (post.requiresAck)
                      Text(
                        '${post.ackCount}/${post.expectedAckCount} confirmed',
                        style: const TextStyle(
                          color: AppColors.ack,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(date);
  }
}

/// Live ticking countdown to an ack deadline. Re-paints once per second
/// while above 1 hour, every second when under (high precision when it
/// matters). Wireframe §02 A1.
class _AckCountdown extends StatefulWidget {
  final DateTime deadline;
  const _AckCountdown({required this.deadline});

  @override
  State<_AckCountdown> createState() => _AckCountdownState();
}

class _AckCountdownState extends State<_AckCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final remaining = widget.deadline.difference(now);
    final overdue = remaining.isNegative;
    final magnitude = remaining.abs();

    final color = overdue
        ? AppColors.urgent
        : magnitude.inHours < 6
            ? AppColors.urgent
            : magnitude.inHours < 24
                ? AppColors.ack
                : AppColors.textSecondary;
    final bg = overdue || magnitude.inHours < 6
        ? AppColors.urgentBg
        : AppColors.ackBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.schedule,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            overdue
                ? 'Overdue by ${_format(magnitude)}'
                : 'Due in ${_format(magnitude)}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            DateFormat('MMM d, h:mm a').format(widget.deadline),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    if (d.inDays >= 1) {
      final hours = d.inHours - d.inDays * 24;
      return '${d.inDays}d ${hours}h';
    }
    if (d.inHours >= 1) {
      final mins = d.inMinutes - d.inHours * 60;
      return '${d.inHours}h ${mins}m';
    }
    if (d.inMinutes >= 1) {
      final secs = d.inSeconds - d.inMinutes * 60;
      return '${d.inMinutes}m ${secs}s';
    }
    return '${d.inSeconds}s';
  }
}
