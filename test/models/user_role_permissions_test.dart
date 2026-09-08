import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/user_model.dart';

void main() {
  /// Helper to create a UserModel with the given role.
  UserModel userWith(UserRole role) {
    final capabilities = switch (role) {
      UserRole.superAdmin => {
        'association.manage',
        'members.manage',
        'schedule.manage',
        'invites.manage',
        'stats.enter',
        'stats.approve',
        'posts.create',
        'posts.manage',
        'posts.internal.read',
        'stats.export',
        'press.read',
      },
      UserRole.admin => {
        'teams.manage',
        'stats.enter',
        'stats.approve',
        'posts.create',
        'posts.manage',
        'posts.internal.read',
        'stats.export',
        'press.read',
      },
      UserRole.statistician => {'stats.enter', 'posts.internal.read'},
      UserRole.rep => {'posts.create', 'posts.internal.read'},
      UserRole.media ||
      UserRole.press => {'posts.internal.read', 'stats.export', 'press.read'},
      UserRole.fan => <String>{},
    };
    return UserModel(
      id: 'test-${role.name}',
      email: '${role.name}@example.com',
      displayName: 'Test ${role.name}',
      associationId: 'jba',
      role: role,
      capabilities: capabilities,
    );
  }

  // ─────────────────────── superAdmin ───────────────────────

  group('superAdmin permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.superAdmin));

    test('identity getters', () {
      expect(user.isSuperAdmin, true);
      expect(user.isAdmin, true); // superAdmin implies admin
      expect(user.isStatistician, false);
      expect(user.isRep, false);
      expect(user.isPress, false);
      expect(user.isFan, false);
    });

    test('admin panel & management', () {
      expect(user.canAccessAdminPanel, true);
      expect(user.canManageUsers, true);
      expect(user.canManageDivisions, true);
      expect(user.canManageSchedule, true);
      expect(user.canManageInviteCodes, true);
    });

    test('stats permissions', () {
      expect(user.canEnterStats, true);
      expect(user.canApproveStats, true);
    });

    test('post permissions', () {
      expect(user.canCreatePost, true);
      expect(user.canEditAnyPost, true);
      expect(user.canPinUrgentAck, true);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canExportStats, true);
      expect(user.canCompareHeadToHead, true);
    });

    test('press tools available (admin tier oversees press features)', () {
      expect(user.canAccessPressTools, true);
    });
  });

  // ─────────────────────── admin ───────────────────────

  group('admin permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.admin));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, true);
      expect(user.isStatistician, false);
      expect(user.isRep, false);
      expect(user.isPress, false);
      expect(user.isFan, false);
    });

    test('admin panel access but no user management', () {
      expect(user.canAccessAdminPanel, true);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
    });

    test('stats permissions', () {
      expect(user.canEnterStats, true);
      expect(user.canApproveStats, true);
    });

    test('post permissions', () {
      expect(user.canCreatePost, true);
      expect(user.canEditAnyPost, true);
      expect(user.canPinUrgentAck, true);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canExportStats, true);
      expect(user.canCompareHeadToHead, true);
    });

    test('press tools available (admin tier oversees press features)', () {
      expect(user.canAccessPressTools, true);
    });
  });

  // ─────────────────────── statistician ───────────────────────

  group('statistician permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.statistician));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, false);
      expect(user.isStatistician, true);
      expect(user.isRep, false);
      expect(user.isPress, false);
      expect(user.isFan, false);
    });

    test('can enter stats but not approve', () {
      expect(user.canEnterStats, true);
      expect(user.canApproveStats, false);
    });

    test('no admin panel access', () {
      expect(user.canAccessAdminPanel, false);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
    });

    test('no post editing permissions', () {
      expect(user.canCreatePost, false);
      expect(user.canEditAnyPost, false);
      expect(user.canPinUrgentAck, false);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canExportStats, false);
      expect(user.canCompareHeadToHead, true);
    });

    test('no press tools', () {
      expect(user.canAccessPressTools, false);
    });
  });

  // ─────────────────────── rep ───────────────────────

  group('rep permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.rep));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, false);
      expect(user.isStatistician, false);
      expect(user.isRep, true);
      expect(user.isPress, false);
      expect(user.isFan, false);
    });

    test('can create posts but not enter stats', () {
      expect(user.canCreatePost, true);
      expect(user.canEnterStats, false);
    });

    test('no admin or approval permissions', () {
      expect(user.canAccessAdminPanel, false);
      expect(user.canApproveStats, false);
      expect(user.canEditAnyPost, false);
      expect(user.canPinUrgentAck, false);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canExportStats, false);
      expect(user.canCompareHeadToHead, true);
    });

    test('no press tools', () {
      expect(user.canAccessPressTools, false);
    });
  });

  // ─────────────────────── press ───────────────────────

  group('press permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.press));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, false);
      expect(user.isStatistician, false);
      expect(user.isRep, false);
      expect(user.isPress, true);
      expect(user.isFan, false);
    });

    test('press tools and export available', () {
      expect(user.canAccessPressTools, true);
      expect(user.canExportStats, true);
    });

    test('no stat entry or admin', () {
      expect(user.canEnterStats, false);
      expect(user.canApproveStats, false);
      expect(user.canAccessAdminPanel, false);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
    });

    test('no post editing', () {
      expect(user.canCreatePost, false);
      expect(user.canEditAnyPost, false);
      expect(user.canPinUrgentAck, false);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canCompareHeadToHead, true);
    });
  });

  // ─────────────────────── media (backward compat) ───────────────────────

  group('media permissions (backward compatibility)', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.media));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, false);
      expect(user.isStatistician, false);
      expect(user.isRep, false);
      expect(user.isMedia, true);
      expect(user.isPress, true); // backward compat: media implies press
      expect(user.isFan, false);
    });

    test('press tools available via backward compat', () {
      expect(user.canAccessPressTools, true);
      expect(user.canExportStats, true);
    });

    test('no stat entry or admin', () {
      expect(user.canEnterStats, false);
      expect(user.canApproveStats, false);
      expect(user.canAccessAdminPanel, false);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
    });

    test('no post editing', () {
      expect(user.canCreatePost, false);
      expect(user.canEditAnyPost, false);
      expect(user.canPinUrgentAck, false);
    });

    test('viewing permissions', () {
      expect(user.canViewBoard, true);
      expect(user.canCompareHeadToHead, true);
    });
  });

  // ─────────────────────── fan ───────────────────────

  group('fan permissions', () {
    late UserModel user;
    setUp(() => user = userWith(UserRole.fan));

    test('identity getters', () {
      expect(user.isSuperAdmin, false);
      expect(user.isAdmin, false);
      expect(user.isStatistician, false);
      expect(user.isRep, false);
      expect(user.isPress, false);
      expect(user.isFan, true);
    });

    test('cannot view board', () {
      expect(user.canViewBoard, false);
    });

    test('cannot compare head to head', () {
      expect(user.canCompareHeadToHead, false);
    });

    test('no admin, stats, or post permissions', () {
      expect(user.canAccessAdminPanel, false);
      expect(user.canManageUsers, false);
      expect(user.canManageDivisions, false);
      expect(user.canManageSchedule, false);
      expect(user.canManageInviteCodes, false);
      expect(user.canEnterStats, false);
      expect(user.canApproveStats, false);
      expect(user.canCreatePost, false);
      expect(user.canEditAnyPost, false);
      expect(user.canPinUrgentAck, false);
    });

    test('no export or press tools', () {
      expect(user.canExportStats, false);
      expect(user.canAccessPressTools, false);
    });
  });
}
