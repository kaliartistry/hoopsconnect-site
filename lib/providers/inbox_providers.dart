import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/inbox_notification.dart';
import '../services/repositories/inbox_repository.dart';
import 'auth_providers.dart';

final inboxRepositoryProvider = Provider<InboxRepository>(
  (ref) => InboxRepository(),
);

final inboxNotificationsProvider =
    StreamProvider.autoDispose<List<InboxNotification>>((ref) {
      final user = ref.watch(currentUserProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      return ref.watch(inboxRepositoryProvider).watchRecent(user.id);
    });

final inboxUnreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(0);
  return ref.watch(inboxRepositoryProvider).watchUnreadCount(user.id);
});
