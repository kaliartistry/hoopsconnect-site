import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/app_shell.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/admin/admin_panel_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/event_model.dart';
import 'package:hoops_connect/models/post_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/ack_providers.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/role_preview_provider.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/stats_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';

void main() {
  Future<void> pumpAdmin(
    WidgetTester tester, {
    required UserModel user,
    UserRole? previewRole,
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(user)),
          rolePreviewProvider.overrideWith((ref) => previewRole),
          teamsStreamProvider.overrideWith(
            (ref) => Stream<List<TeamModel>>.value(const []),
          ),
          postsRequiringAckProvider.overrideWith(
            (ref) => Stream<List<PostModel>>.value(const []),
          ),
          gamesNeedingStatsProvider.overrideWith(
            (ref) => Stream<List<EventModel>>.value(const []),
          ),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream<List<DivisionModel>>.value(const []),
          ),
          activeSeasonNameProvider.overrideWith(
            (ref) => Stream<String?>.value('Test Season'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminPanelScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ordinary admin sees only tools backed by its capabilities', (
    tester,
  ) async {
    // A forged local preview value must be ignored for a user who lacks the
    // real members.manage capability.
    await pumpAdmin(
      tester,
      user: _admin(),
      previewRole: UserRole.superAdmin,
    );

    expect(find.text('Enter Game Stats'), findsOneWidget);
    expect(find.text('Acknowledgment Tracker'), findsOneWidget);
    expect(find.text('Teams & Rosters'), findsOneWidget);
    expect(find.text('Create Announcement'), findsOneWidget);
    expect(find.text('User Management'), findsNothing);
    expect(find.text('Invite Codes'), findsNothing);
    expect(find.text('Game Schedule'), findsNothing);
    expect(find.text('Branding & Sponsor'), findsNothing);
    expect(find.byKey(const Key('role-preview-selector')), findsNothing);
  });

  testWidgets('Super Admin preview changes presentation without adding tools', (
    tester,
  ) async {
    await pumpAdmin(tester, user: _superAdmin(), previewRole: UserRole.fan);

    expect(find.byKey(const Key('role-preview-selector')), findsOneWidget);
    expect(find.text('Season Leaderboard'), findsOneWidget);
    expect(find.text('Enter Game Stats'), findsNothing);
    expect(find.text('User Management'), findsNothing);
    expect(find.text('Invite Codes'), findsNothing);
    expect(find.text('Archive Season'), findsNothing);
  });

  testWidgets('preview control renders at phone and wide widths', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1440, 1000)]) {
      await pumpAdmin(tester, user: _superAdmin(), size: size);
      expect(
        find.byKey(const Key('role-preview-selector')),
        findsOneWidget,
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('preview banner is a keyboard-accessible exit surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: RolePreviewBanner(role: UserRole.media)),
        ),
      ),
    );
    expect(find.text('Previewing as MEDIA'), findsOneWidget);
    final button = find.byKey(const Key('exit-role-preview'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(40));
  });
}

UserModel _admin() => UserModel(
  id: 'admin',
  email: 'admin@example.com',
  displayName: 'Admin',
  associationId: 'jba',
  role: UserRole.admin,
  capabilities: const {
    'association.read',
    'teams.manage',
    'posts.create',
    'posts.manage',
    'posts.internal.read',
    'stats.enter',
    'stats.approve',
    'stats.export',
    'press.read',
  },
);

UserModel _superAdmin() => UserModel(
  id: 'owner',
  email: 'owner@example.com',
  displayName: 'Owner',
  associationId: 'jba',
  role: UserRole.superAdmin,
  capabilities: const {
    'association.read',
    'association.manage',
    'members.read',
    'members.manage',
    'invites.manage',
    'schedule.manage',
    'teams.manage',
    'posts.create',
    'posts.manage',
    'posts.internal.read',
    'stats.enter',
    'stats.approve',
    'stats.export',
    'press.read',
  },
);
