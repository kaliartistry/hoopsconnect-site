import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/board/board_screen.dart';
import 'package:hoops_connect/models/post_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/post_providers.dart';
import 'package:hoops_connect/providers/role_preview_provider.dart';

void main() {
  Future<void> pumpBoard(WidgetTester tester, UserRole previewRole) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            AsyncValue<UserModel?>.data(_superAdmin()),
          ),
          rolePreviewProvider.overrideWith((ref) => previewRole),
          selectedDivisionNameProvider.overrideWithValue(null),
          postsStreamProvider(
            null,
          ).overrideWith((ref) => Stream<List<PostModel>>.value(_posts)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const BoardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Fan preview hides internal data and every Board mutation', (
    tester,
  ) async {
    await pumpBoard(tester, UserRole.fan);

    expect(find.text('Public update'), findsOneWidget);
    expect(find.text('Internal action'), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Tap to Acknowledge'), findsNothing);
    expect(find.text('FAN'), findsOneWidget);
  });

  testWidgets('Rep preview shows only rep presentation capabilities', (
    tester,
  ) async {
    await pumpBoard(tester, UserRole.rep);

    expect(find.text('Public update'), findsOneWidget);
    expect(find.text('Internal action'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.text('Tap to Acknowledge'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('REP'), findsOneWidget);
  });
}

final _posts = [
  PostModel(
    id: 'public',
    authorId: 'author',
    authorName: 'Association',
    authorRole: 'admin',
    type: PostType.announcement,
    title: 'Public update',
    body: 'Published information',
    visibility: PostVisibility.public,
    createdAt: DateTime.utc(2026, 9, 1),
  ),
  PostModel(
    id: 'internal',
    authorId: 'author',
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
  ),
];

UserModel _superAdmin() => const UserModel(
  id: 'owner',
  email: 'owner@example.com',
  displayName: 'Owner',
  associationId: 'jba',
  role: UserRole.superAdmin,
  capabilities: {
    'association.read',
    'association.manage',
    'members.manage',
    'posts.create',
    'posts.manage',
    'posts.internal.read',
    'posts.acknowledge',
  },
);
