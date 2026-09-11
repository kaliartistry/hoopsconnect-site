import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/router/app_route_contract.dart';
import 'package:hoops_connect/app/router/app_router.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';

void main() {
  group('role and route matrix', () {
    final users = <UserRole, UserModel>{
      for (final role in UserRole.values) role: _user(role),
    };

    test('guest routes preserve safe requested locations through sign-in', () {
      final requested = Uri.parse('/calendar?division=women');
      expect(
        resolveAppRedirect(
          location: requested,
          matchedLocation: '/calendar',
          accessStatus: AccountAccessStatus.signedOut,
          isLoggedIn: false,
          user: null,
        ),
        '/login?from=%2Fcalendar%3Fdivision%3Dwomen',
      );
      expect(
        resolveAppRedirect(
          location: Uri.parse(PublicRoutePaths.games),
          matchedLocation: PublicRoutePaths.games,
          accessStatus: AccountAccessStatus.signedOut,
          isLoggedIn: false,
          user: null,
        ),
        isNull,
      );
      expect(
        AppRouteContract.safeRequestedLocation('//evil.example/path'),
        isNull,
      );
      expect(
        AppRouteContract.safeRequestedLocation('https://evil.example/path'),
        isNull,
      );
      expect(
        AppRouteContract.safeRequestedLocation('/calendar?division=women'),
        '/calendar?division=women',
      );
      expect(PublicRoutePaths.game('game 1'), '/public/games/game%201');
      expect(PublicRoutePaths.team('team/1'), '/public/teams/team%2F1');
      expect(PublicRoutePaths.player('player 1'), '/public/players/player%201');
      expect(
        AppRouteContract.permits(PublicRoutePaths.game('game 1'), null),
        isTrue,
      );
    });

    test(
      'fan lands on visible Standings and preserves a permitted deep link',
      () {
        final fan = users[UserRole.fan]!;
        expect(AppRouteContract.landingFor(fan), '/standings');
        expect(AppRouteContract.permits('/board', fan), isFalse);
        expect(AppRouteContract.permits('/standings', fan), isTrue);
        expect(
          resolveAppRedirect(
            location: Uri.parse('/login?from=%2Fcalendar%3Fdivision%3Dwomen'),
            matchedLocation: '/login',
            accessStatus: AccountAccessStatus.active,
            isLoggedIn: true,
            user: fan,
          ),
          '/calendar?division=women',
        );
        expect(
          resolveAppRedirect(
            location: Uri.parse('/login?from=%2Fboard'),
            matchedLocation: '/login',
            accessStatus: AccountAccessStatus.active,
            isLoggedIn: true,
            user: fan,
          ),
          '/standings',
        );
        expect(
          resolvePendingRequestedLocation(
            pendingLocation: '/calendar?division=women',
            currentLocation: Uri.parse('/board'),
            user: fan,
          ),
          '/calendar?division=women',
        );
        expect(
          resolvePendingRequestedLocation(
            pendingLocation: '/board',
            currentLocation: Uri.parse('/board'),
            user: fan,
          ),
          '/standings',
        );
      },
    );

    test('staff board, media alias, and capability destinations agree', () {
      for (final role in const [
        UserRole.rep,
        UserRole.statistician,
        UserRole.media,
        UserRole.press,
        UserRole.admin,
        UserRole.superAdmin,
      ]) {
        expect(
          AppRouteContract.permits('/board', users[role]),
          isTrue,
          reason: role.name,
        );
      }
      for (final role in const [UserRole.media, UserRole.press]) {
        expect(AppRouteContract.permits('/press', users[role]), isTrue);
        expect(
          AppRouteContract.permits('/press/summary/game-1', users[role]),
          isTrue,
        );
      }
      expect(AppRouteContract.permits('/press', users[UserRole.rep]), isFalse);
    });

    test(
      'statistician can reach assigned entry and revision but not admin',
      () {
        final statistician = users[UserRole.statistician]!;
        for (final path in const [
          '/stats/assigned',
          '/stats/assigned/game-1',
          '/stats/assigned/game-1/revision',
          '/admin/stats',
          '/admin/stats/game-1',
          '/live-stats',
        ]) {
          expect(
            AppRouteContract.permits(path, statistician),
            isTrue,
            reason: path,
          );
        }
        expect(AppRouteContract.permits('/admin', statistician), isFalse);
        expect(AppRouteContract.permits('/admin/users', statistician), isFalse);
      },
    );

    test('each administrative destination requires its actual capability', () {
      final admin = users[UserRole.admin]!;
      final superAdmin = users[UserRole.superAdmin]!;
      final expectations = <String, bool>{
        '/admin': true,
        '/admin/stats': true,
        '/admin/ack-tracker': true,
        '/admin/teams': true,
        '/admin/users': false,
        '/admin/divisions': false,
        '/admin/branding': false,
        '/admin/invite-codes': false,
        '/admin/schedule': false,
      };
      for (final entry in expectations.entries) {
        expect(
          AppRouteContract.permits(entry.key, admin),
          entry.value,
          reason: entry.key,
        );
        expect(
          AppRouteContract.permits(entry.key, superAdmin),
          isTrue,
          reason: entry.key,
        );
      }
    });

    test('manual URL denial is explicit and role preview grants nothing', () {
      final fan = users[UserRole.fan]!;
      expect(
        resolveAppRedirect(
          location: Uri.parse('/admin/users'),
          matchedLocation: '/admin/users',
          accessStatus: AccountAccessStatus.active,
          isLoggedIn: true,
          user: fan,
        ),
        '/access-denied?from=%2Fadmin%2Fusers',
      );
      expect(
        previewRoleShowsCapability(UserRole.superAdmin, 'members.manage'),
        isTrue,
      );
      expect(fan.hasCapability('members.manage'), isFalse);
      expect(AppRouteContract.permits('/admin/users', fan), isFalse);
    });

    test(
      'account lifecycle paths avoid membership and Auth redirect loops',
      () {
        for (final status in const [
          AccountAccessStatus.pendingProvisioning,
          AccountAccessStatus.blocked,
        ]) {
          expect(
            resolveAppRedirect(
              location: Uri.parse(AccountLifecycleRoutePaths.requestDeletion),
              matchedLocation: AccountLifecycleRoutePaths.requestDeletion,
              accessStatus: status,
              isLoggedIn: true,
              user: null,
            ),
            isNull,
            reason: status.name,
          );
        }
        expect(
          resolveAppRedirect(
            location: Uri.parse(AccountLifecycleRoutePaths.deletionStatus),
            matchedLocation: AccountLifecycleRoutePaths.deletionStatus,
            accessStatus: AccountAccessStatus.signedOut,
            isLoggedIn: false,
            user: null,
          ),
          isNull,
        );
        expect(
          resolveAppRedirect(
            location: Uri.parse(AccountLifecycleRoutePaths.requestDeletion),
            matchedLocation: AccountLifecycleRoutePaths.requestDeletion,
            accessStatus: AccountAccessStatus.signedOut,
            isLoggedIn: false,
            user: null,
          ),
          '/login?from=%2Faccount%2Fdelete',
        );
      },
    );

    test('loading exits cover every resolved account state and cold start', () {
      final fan = users[UserRole.fan]!;
      final cases =
          <
            ({
              String name,
              AccountAccessStatus status,
              bool signedIn,
              String? pending,
              UserModel? user,
              String expected,
            })
          >[
            (
              name: 'signed out protected deep link',
              status: AccountAccessStatus.signedOut,
              signedIn: false,
              pending: '/calendar?division=women',
              user: null,
              expected: '/login?from=%2Fcalendar%3Fdivision%3Dwomen',
            ),
            (
              name: 'pending provisioning protected deep link',
              status: AccountAccessStatus.pendingProvisioning,
              signedIn: true,
              pending: '/calendar',
              user: null,
              expected: '/join',
            ),
            (
              name: 'pending provisioning lifecycle cold start',
              status: AccountAccessStatus.pendingProvisioning,
              signedIn: true,
              pending: AccountLifecycleRoutePaths.requestDeletion,
              user: null,
              expected: AccountLifecycleRoutePaths.requestDeletion,
            ),
            (
              name: 'blocked protected deep link',
              status: AccountAccessStatus.blocked,
              signedIn: true,
              pending: '/calendar',
              user: null,
              expected: '/access-blocked',
            ),
            (
              name: 'blocked lifecycle cold start',
              status: AccountAccessStatus.blocked,
              signedIn: true,
              pending: AccountLifecycleRoutePaths.reconcileDeviceWork,
              user: null,
              expected: AccountLifecycleRoutePaths.reconcileDeviceWork,
            ),
            (
              name: 'active permitted deep link',
              status: AccountAccessStatus.active,
              signedIn: true,
              pending: '/calendar?division=women',
              user: fan,
              expected: '/calendar?division=women',
            ),
            (
              name: 'active unauthorized old landing',
              status: AccountAccessStatus.active,
              signedIn: true,
              pending: '/board',
              user: fan,
              expected: '/standings',
            ),
            (
              name: 'active no pending route',
              status: AccountAccessStatus.active,
              signedIn: true,
              pending: null,
              user: fan,
              expected: '/standings',
            ),
          ];

      for (final value in cases) {
        expect(
          resolveLoadingExit(
            accessStatus: value.status,
            isLoggedIn: value.signedIn,
            pendingLocation: value.pending,
            user: value.user,
          ),
          value.expected,
          reason: value.name,
        );
      }
      expect(
        resolveLoadingExit(
          accessStatus: AccountAccessStatus.loading,
          isLoggedIn: false,
          pendingLocation: '/calendar',
          user: null,
        ),
        isNull,
      );
    });
  });
}

UserModel _user(UserRole role) {
  final capabilities = switch (role) {
    UserRole.superAdmin => {
      'association.read',
      'association.manage',
      'members.read',
      'members.manage',
      'invites.manage',
      'schedule.manage',
      'teams.manage',
      'teams.represent',
      'posts.create',
      'posts.manage',
      'posts.internal.read',
      'posts.acknowledge',
      'stats.enter',
      'stats.approve',
      'stats.export',
      'press.read',
    },
    UserRole.admin => {
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
    UserRole.statistician => {
      'association.read',
      'posts.internal.read',
      'stats.enter',
    },
    UserRole.rep => {
      'association.read',
      'teams.represent',
      'posts.create',
      'posts.internal.read',
      'posts.acknowledge',
    },
    UserRole.media || UserRole.press => {
      'association.read',
      'posts.internal.read',
      'stats.export',
      'press.read',
    },
    UserRole.fan => {'association.read'},
  };
  return UserModel(
    id: role.name,
    email: '${role.name}@example.com',
    displayName: role.name,
    associationId: 'jba',
    role: role,
    capabilities: capabilities,
  );
}
