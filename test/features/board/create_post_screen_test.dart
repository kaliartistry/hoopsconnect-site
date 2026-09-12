import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/board/create_post_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/post_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/post_providers.dart';
import 'package:hoops_connect/services/repositories/post_repository.dart';

void main() {
  testWidgets('recommended acknowledgment deadline is explicit Jamaica time', (
    tester,
  ) async {
    final repository = _RecordingPostRepository();
    await _pumpCreate(tester, repository: repository);

    expect(find.text('Create board post'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Schedule update');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Please review the updated schedule.',
    );
    await tester.scrollUntilVisible(
      find.text('Deadline'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Deadline'), findsOneWidget);
    expect(find.text('No deadline'), findsOneWidget);
    expect(find.textContaining(' JA'), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createdPosts, hasLength(1));
    final created = repository.createdPosts.single;
    expect(created.requiresAck, isTrue);
    expect(created.ackDeadline, isNotNull);
    expect(created.ackDeadline!.isUtc, isTrue);
    expect(created.createdAt.isUtc, isTrue);
    expect(
      find.text(
        'Acknowledgment request published. Notification delivery is tracked separately.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no-deadline publication requires a deliberate visible choice', (
    tester,
  ) async {
    final repository = _RecordingPostRepository();
    await _pumpCreate(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField).at(0), 'Open request');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Please review this board update.',
    );
    await tester.scrollUntilVisible(
      find.text('No deadline'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('No deadline'));
    await tester.pumpAndSettle();

    expect(find.text('No acknowledgment deadline'), findsOneWidget);
    expect(find.textContaining('request will stay open'), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repository.createdPosts.single.ackDeadline, isNull);
  });

  testWidgets('publishing blocks duplicate taps while the write is pending', (
    tester,
  ) async {
    final repository = _RecordingPostRepository(waitForCompletion: true);
    await _pumpCreate(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField).at(0), 'Pending post');
    await tester.enterText(find.byType(TextFormField).at(1), 'One write only.');
    await tester.tap(find.text('Publish'));
    await tester.pump();

    expect(repository.createdPosts, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Publish'), findsNothing);

    repository.complete();
    await tester.pumpAndSettle();
    expect(repository.createdPosts, hasLength(1));
  });

  testWidgets('acknowledgment controls fit a phone with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    await _pumpCreate(
      tester,
      repository: _RecordingPostRepository(),
      textScaler: const TextScaler.linear(1.5),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Acknowledgment timing'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('No deadline'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No deadline'), findsOneWidget);
  });
}

Future<void> _pumpCreate(
  WidgetTester tester, {
  required _RecordingPostRepository repository,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/create',
        builder: (_, _) => const CreatePostScreen(initialRequiresAck: true),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          const AsyncValue<UserModel?>.data(_admin),
        ),
        divisionsStreamProvider.overrideWith(
          (ref) => Stream.value(const [
            DivisionModel(id: 'premier', name: 'Premier'),
          ]),
        ),
        postRepositoryProvider.overrideWithValue(repository),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  router.push('/create');
  await tester.pumpAndSettle();
}

const _admin = UserModel(
  id: 'admin',
  email: 'admin@example.com',
  displayName: 'Admin',
  associationId: 'jba',
  role: UserRole.admin,
  capabilities: {'posts.create', 'posts.manage'},
);

class _RecordingPostRepository implements PostRepository {
  _RecordingPostRepository({this.waitForCompletion = false});

  final bool waitForCompletion;
  final List<PostModel> createdPosts = [];
  final Completer<void> _completion = Completer<void>();

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  Future<void> createPost(String assocId, PostModel post) async {
    createdPosts.add(post);
    if (waitForCompletion) await _completion.future;
  }

  @override
  Future<void> acknowledge(String assocId, String postId) async {}

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
  Stream<PostModel?> watchPost(String assocId, String postId) =>
      const Stream.empty();

  @override
  Stream<List<PostModel>> watchPosts(
    String assocId, {
    String? divisionFilter,
    int limit = 20,
    bool includeInternal = true,
  }) => const Stream.empty();
}
