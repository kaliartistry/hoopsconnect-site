import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/ack/ack_tracker_screen.dart';
import 'package:hoops_connect/models/post_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/ack_providers.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/post_providers.dart';
import 'package:hoops_connect/services/repositories/post_repository.dart';

void main() {
  testWidgets('reminder requires confirmation and reports only the request', (
    tester,
  ) async {
    final repository = _RecordingPostRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AsyncValue<UserModel?>.data(_admin),
          ),
          postsRequiringAckProvider.overrideWithValue(AsyncValue.data([_post])),
          postRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const AckTrackerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind all pending (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Request acknowledgment reminders?'), findsOneWidget);
    expect(find.textContaining('Actual delivery depends'), findsOneWidget);
    expect(repository.reminderCalls, 0);

    await tester.tap(find.text('Request reminders'));
    await tester.pumpAndSettle();

    expect(repository.reminderCalls, 1);
    expect(
      find.text('Reminder request recorded for 1 pending representative.'),
      findsOneWidget,
    );
    expect(find.textContaining('will be pinged'), findsNothing);
  });

  testWidgets('stream failure is not presented as an empty inbox', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          postsRequiringAckProvider.overrideWithValue(
            AsyncValue.error(StateError('permission-denied'), StackTrace.empty),
          ),
        ],
        child: const MaterialApp(home: AckTrackerScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.text("You don't have permission to access this"),
      findsOneWidget,
    );
    expect(find.text('No posts requiring acknowledgment'), findsNothing);
  });
}

const _admin = UserModel(
  id: 'admin',
  email: 'admin@example.com',
  displayName: 'Admin',
  associationId: 'jba',
  role: UserRole.admin,
  capabilities: {'posts.manage'},
);

final _post = PostModel(
  id: 'post-1',
  authorId: 'admin',
  authorName: 'Admin',
  authorRole: 'admin',
  type: PostType.announcement,
  title: 'Schedule update',
  body: 'Please acknowledge the new schedule.',
  visibility: PostVisibility.internal,
  requiresAck: true,
  expectedAcks: const {
    'rep': AckExpectedEntry(name: 'Team Representative', teamName: 'Kingston'),
  },
  createdAt: DateTime.utc(2026, 9, 11, 14),
  ackDeadline: DateTime.utc(2026, 9, 12, 1),
);

class _RecordingPostRepository implements PostRepository {
  int reminderCalls = 0;

  @override
  Future<void> requestManualAckReminder(String assocId, String postId) async {
    reminderCalls += 1;
  }

  @override
  Future<void> acknowledge(String assocId, String postId) async {}

  @override
  Future<void> createPost(String assocId, PostModel post) async {}

  @override
  Future<void> deletePost(String assocId, String postId) async {}

  @override
  Future<void> toggleReaction(
    String assocId,
    String postId,
    String emoji,
    int delta,
  ) async {}

  @override
  Future<void> updatePost(
    String assocId,
    String postId,
    Map<String, dynamic> data,
  ) async {}

  @override
  Stream<PostModel?> watchPost(String assocId, String postId) =>
      Stream.value(_post);

  @override
  Stream<List<PostModel>> watchPosts(
    String assocId, {
    String? divisionFilter,
    int limit = 20,
    bool includeInternal = true,
  }) => Stream.value([_post]);
}
