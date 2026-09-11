import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/join_screen.dart';
import '../../features/auth/access_blocked_screen.dart';
import '../../features/auth/access_denied_screen.dart';
import '../../features/auth/account_lifecycle_route_screen.dart';
import '../../features/auth/password_recovery_screen.dart';
import '../../features/public/public_league_screen.dart';
import '../../features/board/board_screen.dart';
import '../../features/board/create_post_screen.dart';
import '../../features/stats/leaderboard_screen.dart';
import '../../features/stats/player_card_screen.dart';
import '../../features/stats/stat_game_select_screen.dart';
import '../../features/stats/stat_entry_screen.dart';
import '../../features/stats/live_stats_screen.dart';
import '../../features/stats/box_score_screen.dart';
import '../../features/stats/standings_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/team/team_view_screen.dart';
import '../../features/admin/admin_panel_screen.dart';
import '../../features/admin/team_list_screen.dart';
import '../../features/admin/user_management_screen.dart';
import '../../features/admin/division_management_screen.dart';
import '../../features/admin/add_game_screen.dart';
import '../../features/admin/schedule_hub_screen.dart';
import '../../features/admin/schedule_generator_screen.dart';
import '../../features/admin/invite_code_management_screen.dart';
import '../../features/admin/association_branding_screen.dart';
import '../../features/board/edit_post_screen.dart';
import '../../features/ack/ack_tracker_screen.dart';
import '../../features/ack/ack_detail_screen.dart';
import '../../features/info/about_screen.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/press/press_dashboard_screen.dart';
import '../../features/press/game_summary_screen.dart';
import '../../features/press/head_to_head_screen.dart';
import '../../core/widgets/navigation_loading.dart';
import '../app_shell.dart';
import 'app_route_contract.dart';

// Navigator keys — one per StatefulShellBranch to preserve tab state
final _boardNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'board');
final _standingsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'standings',
);
final _statsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'stats');
final _scheduleNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'schedule');
final _adminNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'admin');
final _pressNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'press');
final _assignedStatsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'assigned-stats',
);

/// Survives the provider-driven GoRouter rebuild that occurs when Auth changes.
/// The value is same-app only and is rechecked against the active membership
/// before it can be restored.
final pendingRequestedLocationProvider = StateProvider<String?>((ref) => null);

String? resolvePendingRequestedLocation({
  required String? pendingLocation,
  required Uri currentLocation,
  required UserModel user,
}) {
  final safe = AppRouteContract.safeRequestedLocation(pendingLocation);
  if (safe == null) return null;
  final safeUri = Uri.parse(safe);
  if (!AppRouteContract.permits(safeUri.path, user)) {
    return AppRouteContract.landingFor(user);
  }
  return safeUri.toString() == currentLocation.toString() ? null : safe;
}

String? resolveAppRedirect({
  required Uri location,
  required String matchedLocation,
  required AccountAccessStatus accessStatus,
  required bool isLoggedIn,
  required UserModel? user,
}) {
  final rule = AppRouteContract.ruleFor(matchedLocation);
  final isPublic = rule?.session == AppRouteSession.public;
  final isLifecycleRoute =
      matchedLocation == AccountLifecycleRoutePaths.requestDeletion ||
      matchedLocation == AccountLifecycleRoutePaths.deletionStatus ||
      matchedLocation == AccountLifecycleRoutePaths.reconcileDeviceWork;

  if (accessStatus == AccountAccessStatus.loading) {
    if (isPublic) return null;
    return matchedLocation == '/loading' ? null : '/loading';
  }

  if (!isLoggedIn) {
    return isPublic ? null : AppRouteContract.loginFor(location);
  }

  if (accessStatus == AccountAccessStatus.pendingProvisioning) {
    if (isPublic || isLifecycleRoute || matchedLocation == '/join') return null;
    return '/join';
  }

  if (accessStatus == AccountAccessStatus.blocked) {
    if (isPublic || isLifecycleRoute || matchedLocation == '/access-blocked') {
      return null;
    }
    return '/access-blocked';
  }

  if (user == null) return '/access-blocked';

  if (matchedLocation == '/login' ||
      matchedLocation == '/join' ||
      matchedLocation == '/loading' ||
      matchedLocation == '/access-blocked') {
    final requested = matchedLocation == '/login'
        ? AppRouteContract.safeRequestedLocation(
            location.queryParameters['from'],
          )
        : null;
    if (requested != null &&
        AppRouteContract.permits(Uri.parse(requested).path, user)) {
      return requested;
    }
    return AppRouteContract.landingFor(user);
  }

  if (rule != null && !rule.permits(user)) {
    if (matchedLocation == AppRouteContract.accessDenied) return null;
    return AppRouteContract.deniedFor(location);
  }

  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);
  final accessStatus = ref.watch(accountAccessStatusProvider);

  return GoRouter(
    initialLocation: '/board',
    redirect: (context, state) {
      final matchedRule = AppRouteContract.ruleFor(state.matchedLocation);
      final isPublic = matchedRule?.session == AppRouteSession.public;
      final isLoggedIn = authState.valueOrNull != null;
      if (!isLoggedIn &&
          accessStatus != AccountAccessStatus.loading &&
          !isPublic &&
          state.matchedLocation != '/login') {
        ref.read(pendingRequestedLocationProvider.notifier).state = state.uri
            .toString();
      }

      final activeUser = currentUser.valueOrNull;
      if (accessStatus == AccountAccessStatus.active &&
          isLoggedIn &&
          activeUser != null) {
        final pending = ref.read(pendingRequestedLocationProvider);
        if (pending != null) {
          ref.read(pendingRequestedLocationProvider.notifier).state = null;
          final restored = resolvePendingRequestedLocation(
            pendingLocation: pending,
            currentLocation: state.uri,
            user: activeUser,
          );
          if (restored != null) return restored;
        }
      }

      return resolveAppRedirect(
        location: state.uri,
        matchedLocation: state.matchedLocation,
        accessStatus: accessStatus,
        isLoggedIn: isLoggedIn,
        user: currentUser.valueOrNull,
      );
    },
    routes: [
      // Loading / splash screen
      GoRoute(
        path: '/loading',
        builder: (context, state) => const NavigationLoadingScreen(),
      ),

      // Auth routes (no shell)
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/join', builder: (context, state) => const JoinScreen()),
      GoRoute(
        path: '/access-blocked',
        builder: (context, state) => const AccessBlockedScreen(),
      ),
      GoRoute(
        path: AppRouteContract.accessDenied,
        builder: (context, state) {
          final user = ref.read(currentUserProvider).valueOrNull;
          return AccessDeniedScreen(
            startLocation: user == null
                ? '/login'
                : AppRouteContract.landingFor(user),
          );
        },
      ),
      GoRoute(
        path: AppRouteContract.passwordRecovery,
        builder: (context, state) => PasswordRecoveryScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),

      GoRoute(
        path: PublicRoutePaths.root,
        redirect: (_, _) => PublicRoutePaths.games,
      ),
      GoRoute(
        path: PublicRoutePaths.games,
        builder: (context, state) => const PublicLeagueScreen(),
      ),

      GoRoute(
        path: AccountLifecycleRoutePaths.requestDeletion,
        builder: (context, state) => AccountLifecycleRouteScreen(
          destination: AccountLifecycleDestination.request,
          isSignedIn: authState.valueOrNull != null,
        ),
      ),
      GoRoute(
        path: AccountLifecycleRoutePaths.deletionStatus,
        builder: (context, state) => AccountLifecycleRouteScreen(
          destination: AccountLifecycleDestination.status,
          isSignedIn: authState.valueOrNull != null,
        ),
      ),
      GoRoute(
        path: AccountLifecycleRoutePaths.reconcileDeviceWork,
        builder: (context, state) => AccountLifecycleRouteScreen(
          destination: AccountLifecycleDestination.reconcileDeviceWork,
          isSignedIn: authState.valueOrNull != null,
        ),
      ),

      // Info & Legal (no auth required for legal from login screen)
      GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
      GoRoute(
        path: '/legal/:type',
        builder: (context, state) =>
            LegalScreen(type: state.pathParameters['type']!),
      ),

      // Main app with bottom nav — StatefulShellRoute preserves tab state
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Tab 0: Board
          StatefulShellBranch(
            navigatorKey: _boardNavigatorKey,
            routes: [
              GoRoute(
                path: '/board',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: BoardScreen()),
              ),
            ],
          ),

          // Tab 1: Standings
          StatefulShellBranch(
            navigatorKey: _standingsNavigatorKey,
            routes: [
              GoRoute(
                path: '/standings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: StandingsScreen()),
              ),
            ],
          ),

          // Tab 2: Stats (Leaderboard)
          StatefulShellBranch(
            navigatorKey: _statsNavigatorKey,
            routes: [
              GoRoute(
                path: '/leaderboard',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: LeaderboardScreen()),
              ),
            ],
          ),

          // Tab 3: Schedule (Calendar)
          StatefulShellBranch(
            navigatorKey: _scheduleNavigatorKey,
            routes: [
              GoRoute(
                path: '/calendar',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: CalendarScreen()),
              ),
            ],
          ),

          // Tab 4: Admin
          StatefulShellBranch(
            navigatorKey: _adminNavigatorKey,
            routes: [
              GoRoute(
                path: '/admin',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: AdminPanelScreen()),
              ),
            ],
          ),

          // Tab 5: Press
          StatefulShellBranch(
            navigatorKey: _pressNavigatorKey,
            routes: [
              GoRoute(
                path: '/press',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PressDashboardScreen()),
              ),
            ],
          ),

          // Tab 6: assigned statistician work. This remains separate from the
          // administrative panel so a statistician can reach assigned games
          // without receiving any admin presentation or capability.
          StatefulShellBranch(
            navigatorKey: _assignedStatsNavigatorKey,
            routes: [
              GoRoute(
                path: AppRouteContract.assignedStats,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: StatGameSelectScreen()),
                routes: [
                  GoRoute(
                    path: ':eventId',
                    builder: (context, state) => StatEntryScreen(
                      eventId: state.pathParameters['eventId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':eventId/revision',
                    builder: (context, state) => StatEntryScreen(
                      eventId: state.pathParameters['eventId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Standalone routes (pushed on top, no bottom nav)

      // Board / Post
      GoRoute(
        path: '/board/create',
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>?;
          return CreatePostScreen(
            initialPinned: extras?['pinned'] as bool? ?? false,
            initialUrgent: extras?['urgent'] as bool? ?? false,
            initialRequiresAck: extras?['requiresAck'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/board/post/:postId',
        builder: (context, state) =>
            AckDetailScreen(postId: state.pathParameters['postId']!),
      ),

      // Admin sub-screens
      GoRoute(
        path: '/admin/live-stats',
        builder: (context, state) {
          final eventId = state.uri.queryParameters['eventId'];
          return LiveStatsScreen(eventId: eventId);
        },
      ),
      GoRoute(
        path: '/admin/stats',
        builder: (context, state) => const StatGameSelectScreen(),
      ),
      GoRoute(
        path: '/admin/stats/:eventId',
        builder: (context, state) =>
            StatEntryScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/admin/ack-tracker',
        builder: (context, state) => const AckTrackerScreen(),
      ),
      GoRoute(
        path: '/admin/teams',
        builder: (context, state) => const TeamListScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const UserManagementScreen(),
      ),
      GoRoute(
        path: '/admin/divisions',
        builder: (context, state) => const DivisionManagementScreen(),
      ),
      GoRoute(
        path: '/admin/schedule',
        builder: (context, state) => const ScheduleHubScreen(),
      ),
      GoRoute(
        path: '/admin/schedule/add-game',
        builder: (context, state) => const AddGameScreen(),
      ),
      GoRoute(
        path: '/admin/schedule/generate',
        builder: (context, state) => const ScheduleGeneratorScreen(),
      ),
      GoRoute(
        path: '/admin/invite-codes',
        builder: (context, state) => const InviteCodeManagementScreen(),
      ),
      GoRoute(
        path: '/admin/branding',
        builder: (context, state) => const AssociationBrandingScreen(),
      ),

      // Press sub-screens (pushed on top, no bottom nav)
      GoRoute(
        path: '/press/summary/:eventId',
        builder: (context, state) =>
            GameSummaryScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/press/head-to-head',
        builder: (context, state) => HeadToHeadScreen(
          initialTeamAId: state.uri.queryParameters['teamA'],
        ),
      ),

      // Board edit
      GoRoute(
        path: '/board/edit/:postId',
        builder: (context, state) =>
            EditPostScreen(postId: state.pathParameters['postId']!),
      ),

      // Live stats (accessible to anyone with canEnterStats)
      GoRoute(
        path: '/live-stats',
        builder: (context, state) {
          final eventId = state.uri.queryParameters['eventId'];
          return LiveStatsScreen(eventId: eventId);
        },
      ),

      // Stats detail screens
      GoRoute(
        path: '/box-score/:eventId',
        builder: (context, state) =>
            BoxScoreScreen(eventId: state.pathParameters['eventId']!),
      ),
      GoRoute(
        path: '/stats/player/:playerId',
        builder: (context, state) =>
            PlayerCardScreen(playerId: state.pathParameters['playerId']!),
      ),

      // Profile & Settings
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // Team detail
      GoRoute(
        path: '/team/:teamId',
        builder: (context, state) =>
            TeamViewScreen(teamId: state.pathParameters['teamId']!),
      ),
    ],
  );
});
