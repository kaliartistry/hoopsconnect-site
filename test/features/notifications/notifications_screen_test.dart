import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/notifications/notifications_screen.dart';
import 'package:hoops_connect/models/inbox_notification.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/inbox_providers.dart';

void main() {
  testWidgets('bell opens the signed-in feed with an unread count', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: NotificationBell()),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    const fan = UserModel(
      id: 'fan',
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: UserRole.fan,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => const AsyncValue.data(fan)),
          inboxUnreadCountProvider.overrideWith((ref) => Stream.value(3)),
          inboxNotificationsProvider.overrideWith(
            (ref) => Stream.value(const [
              InboxNotification(
                id: 'final-g1',
                type: 'favorite_team_final',
                title: 'Final: St. George’s Players 81, Away 74',
                body: 'The final score is ready.',
                gameId: 'g1',
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notification-bell')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(
      find.text('Final: St. George’s Players 81, Away 74'),
      findsOneWidget,
    );
  });

  testWidgets('schedule digest opens the public games list', (tester) async {
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/public/games',
          builder: (_, _) => const Scaffold(body: Text('Public games')),
        ),
      ],
    );
    addTearDown(router.dispose);
    const fan = UserModel(
      id: 'fan',
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: UserRole.fan,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => const AsyncValue.data(fan)),
          inboxNotificationsProvider.overrideWith(
            (ref) => Stream.value([
              InboxNotification(
                id: 'schedule-digest',
                type: 'favorite_team_schedule',
                title: 'New games scheduled',
                body: 'Open the schedule for details.',
                readAt: DateTime.utc(2026),
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New games scheduled'));
    await tester.pumpAndSettle();
    expect(find.text('Public games'), findsOneWidget);
  });
}
