import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/ack/ack_detail_screen.dart';
import 'package:hoops_connect/models/post_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/post_providers.dart';
import 'package:hoops_connect/providers/role_preview_provider.dart';
import 'package:hoops_connect/services/repositories/post_repository.dart';

void main() {
  testWidgets(
    'direct internal URL hides content and action after Fan preview',
    (tester) async {
      final repository = _RecordingPostRepository();
      final router = GoRouter(
        initialLocation: '/board/post/internal',
        routes: [
          GoRoute(
            path: '/board/post/:postId',
            builder: (_, state) =>
                AckDetailScreen(postId: state.pathParameters['postId']!),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AsyncValue<UserModel?>.data(_superAdmin),
            ),
            rolePreviewProvider.overrideWith((ref) => null),
            postRepositoryProvider.overrideWithValue(repository),
            postDetailProvider.overrideWith(
              (ref, _) => Stream<PostModel?>.value(_internalPost),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Internal action'), findsOneWidget);
      expect(find.text('Staff action required'), findsOneWidget);
      expect(find.text('Acknowledge This Post'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AckDetailScreen)),
      );
      container.read(rolePreviewProvider.notifier).state = UserRole.fan;
      await tester.pumpAndSettle();

      expect(find.text('Post hidden in this role preview'), findsOneWidget);
      expect(find.text('Internal action'), findsNothing);
      expect(find.text('Staff action required'), findsNothing);
      expect(find.text('Acknowledgment Progress'), findsNothing);
      expect(find.text('Acknowledge This Post'), findsNothing);
      expect(repository.acknowledgeCalls, 0);
    },
  );
}

const _superAdmin = UserModel(
  id: 'owner',
  email: 'owner@example.com',
  displayName: 'Owner',
  associationId: 'jba',
  role: UserRole.superAdmin,
  capabilities: {
    'association.read',
    'members.manage',
    'posts.internal.read',
    'posts.acknowledge',
  },
);

final _internalPost = PostModel(
  id: 'internal',
  authorId: 'admin',
  authorName: 'Association',
  authorRole: 'admin',
  type: PostType.announcement,
  title: 'Internal action',
  body: 'Staff action required',
  visibility: PostVisibility.internal,
  requiresAck: true,
  expectedAcks: const {
    'owner': AckExpectedEntry(name: 'Owner', teamName: 'JBA'),
  },
  createdAt: DateTime.utc(2026, 9, 1),
);

class _RecordingPostRepository implements PostRepository {
  int acknowledgeCalls = 0;

  @override
  Future<void> acknowledge(String assocId, String postId) async {
    acknowledgeCalls += 1;
  }

  @override
  Future<void> createPost(String assocId, PostModel post) async {}

  @override
  Future<void> deletePost(String assocId, String postId) async {}

  @override
  Future<void> requestManualAckReminder(String assocId, String postId) async {}

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
  Stream<PostModel?> watchPost(String assocId, String postId) {
    return Stream.value(_internalPost);
  }

  @override
  Stream<List<PostModel>> watchPosts(
    String assocId, {
    String? divisionFilter,
    int limit = 20,
    bool includeInternal = true,
  }) {
    return Stream.value([_internalPost]);
  }
}
