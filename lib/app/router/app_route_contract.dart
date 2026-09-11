import '../../models/user_model.dart';

/// Public URL names owned by the fan/media workstream.
///
/// The access workstream pins the namespace so links can be shared before the
/// destination widgets are completed. Only [games] is mounted in this packet;
/// the remaining destinations are reserved for the public-data workstream.
abstract final class PublicRoutePaths {
  static const root = '/public';
  static const games = '/public/games';
  static const standings = '/public/standings';
  static const leaders = '/public/leaders';

  static String game(String eventId) => '/public/games/$eventId';
  static String team(String teamId) => '/public/teams/$teamId';
  static String player(String playerId) => '/public/players/$playerId';
}

/// Stable account-lifecycle URLs shared with the deletion workstream.
///
/// The status destination is intentionally reachable without an active Auth
/// session because the deletion contract can remove Auth before cleanup ends.
/// Its future status capability remains read-only and is not carried here.
abstract final class AccountLifecycleRoutePaths {
  static const requestDeletion = '/account/delete';
  static const deletionStatus = '/account/deletion/status';
  static const reconcileDeviceWork = '/account/deletion/reconcile-device';
}

enum AppRouteSession { public, authenticated, activeMembership }

class AppRouteRule {
  const AppRouteRule({
    required this.pattern,
    required this.session,
    this.prefix = false,
    this.anyCapabilities = const {},
    this.allCapabilities = const {},
  });

  final String pattern;
  final bool prefix;
  final AppRouteSession session;
  final Set<String> anyCapabilities;
  final Set<String> allCapabilities;

  bool matches(String path) {
    if (!prefix) return path == pattern;
    return path == pattern || path.startsWith('$pattern/');
  }

  bool permits(UserModel? user) {
    if (session != AppRouteSession.activeMembership) return true;
    if (user == null) return false;
    if (allCapabilities.any((value) => !user.hasCapability(value))) {
      return false;
    }
    return anyCapabilities.isEmpty || anyCapabilities.any(user.hasCapability);
  }
}

/// The single client-side route matrix used by navigation and redirect guards.
///
/// This is a usability boundary only. Firestore and callable Functions remain
/// the mutation authority. Every protected route is checked against the real
/// membership-backed [UserModel], never a role-preview identity.
abstract final class AppRouteContract {
  static const accessDenied = '/access-denied';
  static const passwordRecovery = '/recover-password';
  static const assignedStats = '/stats/assigned';

  static const List<AppRouteRule> rules = [
    AppRouteRule(pattern: '/loading', session: AppRouteSession.public),
    AppRouteRule(pattern: '/login', session: AppRouteSession.public),
    AppRouteRule(pattern: '/join', session: AppRouteSession.public),
    AppRouteRule(pattern: passwordRecovery, session: AppRouteSession.public),
    AppRouteRule(
      pattern: '/legal',
      prefix: true,
      session: AppRouteSession.public,
    ),
    AppRouteRule(pattern: '/about', session: AppRouteSession.public),
    AppRouteRule(
      pattern: PublicRoutePaths.root,
      prefix: true,
      session: AppRouteSession.public,
    ),
    AppRouteRule(
      pattern: AccountLifecycleRoutePaths.deletionStatus,
      session: AppRouteSession.public,
    ),
    AppRouteRule(
      pattern: AccountLifecycleRoutePaths.requestDeletion,
      session: AppRouteSession.authenticated,
    ),
    AppRouteRule(
      pattern: AccountLifecycleRoutePaths.reconcileDeviceWork,
      session: AppRouteSession.authenticated,
    ),
    AppRouteRule(
      pattern: '/access-blocked',
      session: AppRouteSession.authenticated,
    ),
    AppRouteRule(pattern: accessDenied, session: AppRouteSession.authenticated),
    AppRouteRule(
      pattern: '/admin/live-stats',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'stats.enter'},
    ),
    AppRouteRule(
      pattern: '/admin/stats',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'stats.enter'},
    ),
    AppRouteRule(
      pattern: assignedStats,
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'stats.enter'},
    ),
    AppRouteRule(
      pattern: '/live-stats',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'stats.enter'},
    ),
    AppRouteRule(
      pattern: '/admin/users',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'members.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/divisions',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/branding',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/invite-codes',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'invites.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/schedule',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'schedule.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/teams',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'teams.manage'},
    ),
    AppRouteRule(
      pattern: '/admin/ack-tracker',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'posts.manage'},
    ),
    AppRouteRule(
      pattern: '/admin',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {
        'association.manage',
        'teams.manage',
        'posts.manage',
        'stats.approve',
      },
    ),
    AppRouteRule(
      pattern: '/board/create',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'posts.create'},
    ),
    AppRouteRule(
      pattern: '/board/edit',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'posts.manage'},
    ),
    AppRouteRule(
      pattern: '/board',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'posts.internal.read'},
    ),
    AppRouteRule(
      pattern: '/press/summary',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'press.read', 'stats.approve'},
    ),
    AppRouteRule(
      pattern: '/press/head-to-head',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/press',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'press.read'},
    ),
    AppRouteRule(
      pattern: '/standings',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/leaderboard',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/calendar',
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/box-score',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/stats/player',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/team',
      prefix: true,
      session: AppRouteSession.activeMembership,
      anyCapabilities: {'association.read'},
    ),
    AppRouteRule(
      pattern: '/profile',
      session: AppRouteSession.activeMembership,
    ),
    AppRouteRule(
      pattern: '/settings',
      session: AppRouteSession.activeMembership,
    ),
  ];

  static AppRouteRule? ruleFor(String path) {
    for (final rule in rules) {
      if (rule.matches(path)) return rule;
    }
    return null;
  }

  static bool permits(String path, UserModel? user) {
    final rule = ruleFor(path);
    return rule != null && rule.permits(user);
  }

  static String landingFor(UserModel user) {
    if (user.canViewBoard) return '/board';
    return '/standings';
  }

  static String loginFor(Uri requested) {
    final requestedValue = requested.toString();
    if (requested.path == '/login') return '/login';
    return Uri(
      path: '/login',
      queryParameters: {'from': requestedValue},
    ).toString();
  }

  static String? safeRequestedLocation(String? value) {
    if (value == null || !value.startsWith('/') || value.startsWith('//')) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.hasAuthority || uri.fragment.isNotEmpty) return null;
    return ruleFor(uri.path) == null ? null : uri.toString();
  }

  static String deniedFor(Uri requested) => Uri(
    path: accessDenied,
    queryParameters: {'from': requested.toString()},
  ).toString();
}

/// Presentation-only capability expectations used by Super Admin role preview.
/// These values may hide or reveal navigation for a preview, but they are never
/// passed to route guards, repositories, rules, or Functions.
bool previewRoleShowsCapability(UserRole role, String capability) {
  final capabilities = switch (role) {
    UserRole.superAdmin => const {
      'association.read',
      'association.manage',
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
    UserRole.admin => const {
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
    UserRole.statistician => const {
      'association.read',
      'posts.internal.read',
      'stats.enter',
    },
    UserRole.rep => const {
      'association.read',
      'posts.create',
      'posts.internal.read',
    },
    UserRole.media || UserRole.press => const {
      'association.read',
      'posts.internal.read',
      'stats.export',
      'press.read',
    },
    UserRole.fan => const {'association.read'},
  };
  return capabilities.contains(capability);
}
