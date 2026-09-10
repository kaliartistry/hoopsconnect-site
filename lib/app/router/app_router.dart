import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/join_screen.dart';
import '../../features/auth/access_blocked_screen.dart';
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

// Navigator keys — one per StatefulShellBranch to preserve tab state
final _boardNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'board');
final _standingsNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'standings',
);
final _statsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'stats');
final _scheduleNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'schedule');
final _adminNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'admin');
final _pressNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'press');

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);
  final accessStatus = ref.watch(accountAccessStatusProvider);

  return GoRouter(
    initialLocation: '/board',
    redirect: (context, state) {
      // While auth is still loading, show the branded loading screen
      if (accessStatus == AccountAccessStatus.loading) {
        return state.matchedLocation == '/loading' ? null : '/loading';
      }

      final isLoggedIn = authState.valueOrNull != null;
      final userDoc = currentUser.valueOrNull;
      final isAuthRoute =
          state.matchedLocation == '/login' || state.matchedLocation == '/join';
      final isPublicRoute =
          state.matchedLocation.startsWith('/legal') ||
          state.matchedLocation == '/about';
      final isLoadingRoute = state.matchedLocation == '/loading';
      final isBlockedRoute = state.matchedLocation == '/access-blocked';

      // Not logged in? Go to login (unless already on auth/public page)
      if (!isLoggedIn) {
        return (isAuthRoute || isPublicRoute) ? null : '/login';
      }

      // An authenticated invitee may not have a profile until the callable
      // redemption transaction succeeds. Keep that recovery path reachable.
      if (accessStatus == AccountAccessStatus.pendingProvisioning) {
        return state.matchedLocation == '/join' ? null : '/join';
      }

      if (accessStatus == AccountAccessStatus.blocked) {
        return isBlockedRoute ? null : '/access-blocked';
      }

      // Logged in with a profile but on auth or loading page? Go to board
      if (isLoggedIn && (isAuthRoute || isLoadingRoute)) {
        return '/board';
      }

      // Role-based guards
      if (userDoc != null) {
        final loc = state.matchedLocation;
        final isAdminRoute = loc.startsWith('/admin');

        if (isAdminRoute && !userDoc.canAccessAdminPanel) {
          return '/board';
        }

        if (loc == '/admin/users' && !userDoc.canManageUsers) {
          return '/admin';
        }
        if (loc == '/admin/divisions' && !userDoc.canManageDivisions) {
          return '/admin';
        }
        if (loc == '/admin/invite-codes' && !userDoc.canManageInviteCodes) {
          return '/admin';
        }
        if (loc.startsWith('/admin/schedule') && !userDoc.canManageSchedule) {
          return '/admin';
        }

        // Stats entry routes require canEnterStats permission
        if (loc == '/live-stats' && !userDoc.canEnterStats) {
          return '/board';
        }

        // Press routes
        if (loc == '/press' && !userDoc.canAccessPressTools) {
          return '/board';
        }

        // Press summary: accessible to press users and admins who can approve stats
        if (loc.startsWith('/press/summary/') &&
            !userDoc.canAccessPressTools &&
            !userDoc.canApproveStats) {
          return '/board';
        }

        // Head-to-head: accessible to all signed-in users
        // (was previously restricted to !isFan via canCompareHeadToHead)
      }

      return null;
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
