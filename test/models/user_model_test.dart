import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/constants/app_constants.dart';
import 'package:hoops_connect/models/user_model.dart';

void main() {
  // ─────────────────────── NotificationPrefs ───────────────────────

  group('NotificationPrefs', () {
    test('defaults all to true', () {
      const prefs = NotificationPrefs();
      expect(prefs.ackReminders, true);
      expect(prefs.statReminders, true);
      expect(prefs.newPosts, true);
    });

    test('fromMap with null returns defaults', () {
      final prefs = NotificationPrefs.fromMap(null);
      expect(prefs.ackReminders, true);
      expect(prefs.statReminders, true);
      expect(prefs.newPosts, true);
    });

    test('fromMap parses explicit false values', () {
      final prefs = NotificationPrefs.fromMap({
        'ackReminders': false,
        'statReminders': false,
        'newPosts': false,
      });
      expect(prefs.ackReminders, false);
      expect(prefs.statReminders, false);
      expect(prefs.newPosts, false);
    });

    test('fromMap supports legacy newPostNotifications key', () {
      final prefs = NotificationPrefs.fromMap({'newPostNotifications': false});
      expect(prefs.newPosts, false);
    });

    test('fromMap uses true for missing keys', () {
      final prefs = NotificationPrefs.fromMap({});
      expect(prefs.ackReminders, true);
      expect(prefs.statReminders, true);
      expect(prefs.newPosts, true);
    });

    test('toMap round-trips through fromMap', () {
      const prefs = NotificationPrefs(
        ackReminders: false,
        statReminders: true,
        newPosts: false,
      );
      final restored = NotificationPrefs.fromMap(prefs.toMap());
      expect(restored.ackReminders, false);
      expect(restored.statReminders, true);
      expect(restored.newPosts, false);
    });

    test('copyWith overrides specified fields', () {
      const prefs = NotificationPrefs();
      final updated = prefs.copyWith(ackReminders: false);
      expect(updated.ackReminders, false);
      expect(updated.statReminders, true);
      expect(updated.newPosts, true);
    });
  });

  // ─────────────────────── UserRole ───────────────────────

  group('UserRole', () {
    test('public self-signup defaults to fan', () {
      expect(AppDefaults.defaultSignupRole, UserRole.fan);
    });

    test('has expected enum values', () {
      expect(UserRole.values.length, 7);
      expect(UserRole.values, contains(UserRole.superAdmin));
      expect(UserRole.values, contains(UserRole.admin));
      expect(UserRole.values, contains(UserRole.statistician));
      expect(UserRole.values, contains(UserRole.rep));
      expect(UserRole.values, contains(UserRole.press));
      expect(UserRole.values, contains(UserRole.media));
      expect(UserRole.values, contains(UserRole.fan));
    });

    test('byName parses role strings correctly', () {
      expect(UserRole.values.byName('admin'), UserRole.admin);
      expect(UserRole.values.byName('rep'), UserRole.rep);
      expect(UserRole.values.byName('media'), UserRole.media);
      expect(UserRole.values.byName('superAdmin'), UserRole.superAdmin);
    });

    test('byName throws on invalid role', () {
      expect(
        () => UserRole.values.byName('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─────────────────────── UserModel ───────────────────────

  group('UserModel', () {
    UserModel createTestUser({UserRole role = UserRole.admin, String? teamId}) {
      return UserModel(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Test User',
        associationId: 'jba',
        role: role,
        teamId: teamId,
      );
    }

    test('toFirestore produces correct map', () {
      final user = createTestUser(teamId: 'team1');
      final map = user.toFirestore();

      expect(map['email'], 'test@example.com');
      expect(map['displayName'], 'Test User');
      expect(map['associationId'], 'jba');
      expect(map['role'], 'admin');
      expect(map['teamId'], 'team1');
      expect(map['fcmTokens'], isEmpty);
      expect(map['notificationPrefs'], isA<Map<String, dynamic>>());
    });

    test('toFirestore does not include id field', () {
      final user = createTestUser();
      final map = user.toFirestore();
      expect(map.containsKey('id'), false);
    });

    test('toFirestore encodes notificationPrefs correctly', () {
      final user = UserModel(
        id: 'u1',
        email: 'a@b.com',
        displayName: 'A',
        associationId: 'jba',
        role: UserRole.rep,
        notificationPrefs: const NotificationPrefs(
          ackReminders: false,
          statReminders: true,
          newPosts: false,
        ),
      );

      final map = user.toFirestore();
      final prefs = map['notificationPrefs'] as Map<String, dynamic>;
      expect(prefs['ackReminders'], false);
      expect(prefs['statReminders'], true);
      expect(prefs['newPosts'], false);
    });

    test('default fcmTokens is empty list', () {
      final user = createTestUser();
      expect(user.fcmTokens, isEmpty);
    });

    test('default notificationPrefs has all true', () {
      final user = createTestUser();
      expect(user.notificationPrefs.ackReminders, true);
      expect(user.notificationPrefs.statReminders, true);
      expect(user.notificationPrefs.newPosts, true);
    });

    // ──── Permission getters ────

    group('permission getters', () {
      test('superAdmin has all permissions', () {
        final user = createTestUser(role: UserRole.superAdmin);
        expect(user.isSuperAdmin, true);
        expect(user.isAdmin, true);
        expect(user.canAccessAdminPanel, true);
        expect(user.canManageUsers, true);
        expect(user.canManageDivisions, true);
        expect(user.canManageSchedule, true);
        expect(user.canManageInviteCodes, true);
        expect(user.canEnterStats, true);
        expect(user.canCreatePost, true);
        expect(user.canEditAnyPost, true);
        expect(user.canPinUrgentAck, true);
      });

      test('admin has admin-level but not superAdmin-level permissions', () {
        final user = createTestUser(role: UserRole.admin);
        expect(user.isSuperAdmin, false);
        expect(user.isAdmin, true);
        expect(user.canAccessAdminPanel, true);
        expect(user.canManageUsers, false);
        expect(user.canManageDivisions, false);
        expect(user.canManageSchedule, false);
        expect(user.canManageInviteCodes, false);
        expect(user.canEnterStats, true);
        expect(user.canCreatePost, true);
        expect(user.canEditAnyPost, true);
        expect(user.canPinUrgentAck, true);
      });

      test('rep can create posts but not access admin panel', () {
        final user = createTestUser(role: UserRole.rep);
        expect(user.isRep, true);
        expect(user.isAdmin, false);
        expect(user.canAccessAdminPanel, false);
        expect(user.canCreatePost, true);
        expect(user.canEnterStats, false);
        expect(user.canEditAnyPost, false);
        expect(user.canPinUrgentAck, false);
      });

      test('media has read-only permissions', () {
        final user = createTestUser(role: UserRole.media);
        expect(user.isMedia, true);
        expect(user.isAdmin, false);
        expect(user.isRep, false);
        expect(user.canAccessAdminPanel, false);
        expect(user.canCreatePost, false);
        expect(user.canEnterStats, false);
        expect(user.canEditAnyPost, false);
        expect(user.canManageUsers, false);
      });
    });

    // ──── copyWith ────

    test('copyWith overrides specified fields', () {
      final user = createTestUser(role: UserRole.media);
      final updated = user.copyWith(role: UserRole.admin, teamId: 'team2');

      expect(updated.role, UserRole.admin);
      expect(updated.teamId, 'team2');
      expect(updated.email, user.email);
      expect(updated.id, user.id);
    });

    test('copyWith with no args returns equivalent user', () {
      final user = createTestUser();
      final copy = user.copyWith();

      expect(copy.id, user.id);
      expect(copy.email, user.email);
      expect(copy.role, user.role);
    });
  });
}
