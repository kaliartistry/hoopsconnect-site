import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_route_contract.dart';
import '../../models/inbox_notification.dart';
import '../../providers/auth_providers.dart';
import '../../providers/inbox_providers.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(inboxUnreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: count == 0 ? 'Notifications' : '$count unread notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count >= 100 ? '99+' : '$count'),
        child: Icon(Icons.notifications_outlined, color: color),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(inboxNotificationsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(inboxNotificationsProvider),
            child: const Text('Could not load notifications. Tap to retry.'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text(
                  'No team updates yet. Follow a team to see final scores here.',
                ),
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    key: Key('notification-${item.id}'),
                    leading: Icon(
                      item.readAt == null
                          ? Icons.circle_notifications
                          : Icons.notifications_none,
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: item.readAt == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(item.body),
                    trailing: item.createdAt == null
                        ? null
                        : Text(DateFormat.MMMd().format(item.createdAt!)),
                    onTap: () =>
                        _openNotification(context, ref, user?.id, item),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    String? userId,
    InboxNotification item,
  ) async {
    if (userId == null) return;
    if (item.readAt == null) {
      try {
        await ref.read(inboxRepositoryProvider).markRead(userId, item.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not mark notification as read.'),
            ),
          );
        }
        return;
      }
    }
    if (context.mounted &&
        (item.type == 'favorite_team_final' ||
            item.type == 'favorite_team_schedule')) {
      context.push(
        item.gameId == null
            ? PublicRoutePaths.games
            : PublicRoutePaths.game(item.gameId!),
      );
    }
  }
}
