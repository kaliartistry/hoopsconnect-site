import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../models/user_model.dart';
import '../../providers/ack_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/role_preview_provider.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';
import '../../app/router/app_route_contract.dart';
import 'widgets/season_management_panel.dart';

class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final canUseRolePreview = currentUser?.canManageUsers ?? false;
    final previewRole = ref.watch(activeRolePreviewProvider);
    bool displayAllows(String capability) => previewRole == null
        ? currentUser?.hasCapability(capability) ?? false
        : previewRoleShowsCapability(previewRole, capability);
    final canManageAssociation = displayAllows('association.manage');
    final teamsAsync = ref.watch(teamsStreamProvider);
    final ackPostsAsync = ref.watch(postsRequiringAckProvider);
    final gamesAsync = ref.watch(gamesNeedingStatsProvider);
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final seasonName = ref.watch(activeSeasonNameProvider).value;

    final teamCount = teamsAsync.valueOrNull?.length ?? 0;
    final ackCount = ackPostsAsync.valueOrNull?.length ?? 0;
    final gamesCount = gamesAsync.valueOrNull?.length ?? 0;
    final divisionCount = divisionsAsync.valueOrNull?.length ?? 0;
    final desktop = isDesktop(context);

    // Season info card (shared between both layouts)
    final seasonCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seasonName ?? 'Loading...',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '$teamCount team${teamCount == 1 ? '' : 's'} · $divisionCount division${divisionCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'ACTIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    // Build menu item data for reuse in both layouts
    final sharedItems = <_AdminMenuItem>[
      if (displayAllows('stats.enter'))
        _AdminMenuItem(
          icon: Icons.sports_score,
          title: 'Enter Game Stats',
          subtitle: '$gamesCount game${gamesCount == 1 ? '' : 's'} need stats',
          bgColor: AppColors.statBg,
          highlightColor: AppColors.statHighlight,
          onTap: () => context.push('/admin/stats'),
        ),
      if (displayAllows('association.read'))
        _AdminMenuItem(
          icon: Icons.leaderboard,
          title: 'Season Leaderboard',
          subtitle: 'View-only published rankings',
          bgColor: AppColors.statBg,
          highlightColor: AppColors.statHighlight,
          onTap: () => context.go('/leaderboard'),
        ),
      if (displayAllows('posts.manage'))
        _AdminMenuItem(
          icon: Icons.bolt,
          title: 'Acknowledgment Tracker',
          subtitle: '$ackCount post${ackCount == 1 ? '' : 's'} pending',
          bgColor: AppColors.ackBg,
          highlightColor: AppColors.ack,
          onTap: () => context.push('/admin/ack-tracker'),
        ),
    ];

    final managementItems = <_AdminMenuItem>[
      if (canManageAssociation)
        _AdminMenuItem(
          icon: Icons.palette_outlined,
          title: 'Branding & Sponsor',
          subtitle: 'League identity and title sponsor',
          onTap: () => context.push('/admin/branding'),
        ),
      if (displayAllows('teams.manage'))
        _AdminMenuItem(
          icon: Icons.groups,
          title: 'Teams & Rosters',
          subtitle: '$teamCount team${teamCount == 1 ? '' : 's'}',
          onTap: () => context.push('/admin/teams'),
        ),
      if (displayAllows('members.manage'))
        _AdminMenuItem(
          icon: Icons.people,
          title: 'User Management',
          subtitle: 'Manage roles & permissions',
          onTap: () => context.push('/admin/users'),
        ),
      if (displayAllows('association.manage'))
        _AdminMenuItem(
          icon: Icons.category,
          title: 'Divisions / Leagues',
          subtitle: 'Manage divisions',
          onTap: () => context.push('/admin/divisions'),
        ),
      if (displayAllows('invites.manage'))
        _AdminMenuItem(
          icon: Icons.vpn_key,
          title: 'Invite Codes',
          subtitle: 'Generate & manage codes',
          onTap: () => context.push('/admin/invite-codes'),
        ),
      if (displayAllows('schedule.manage'))
        _AdminMenuItem(
          icon: Icons.schedule,
          title: 'Game Schedule',
          subtitle: 'Add games to calendar',
          onTap: () => context.push('/admin/schedule'),
        ),
      if (displayAllows('posts.manage'))
        _AdminMenuItem(
          icon: Icons.campaign,
          title: 'Create board post',
          subtitle: 'Publish an announcement or league update',
          onTap: () => context.push(
            '/board/create',
            extra: {'pinned': true, 'urgent': true, 'requiresAck': true},
          ),
        ),
    ];
    final showManagementSection = managementItems.isNotEmpty;

    // Desktop: sidebar + main content area
    if (desktop) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: Row(
          children: [
            // Sidebar
            SizedBox(
              width: 300,
              child: Container(
                color: AppColors.surface,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    seasonCard,
                    if (canUseRolePreview) ...[
                      const SizedBox(height: 12),
                      const RolePreviewSelector(),
                    ],
                    const SizedBox(height: 16),
                    for (final item in sharedItems) _sidebarItem(item),
                    if (showManagementSection) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 8, left: 4),
                        child: Text(
                          'LEAGUE MANAGEMENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textMuted,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      for (final item in managementItems) _sidebarItem(item),
                    ],
                    if (canManageAssociation) ...[
                      const SizedBox(height: 16),
                      const SeasonManagementLauncher(),
                    ],
                  ],
                ),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            // Main content area -- welcome / instructions
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      size: 64,
                      color: AppColors.primary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin Panel',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select an option from the sidebar to get started',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile / tablet: original list layout
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          seasonCard,
          if (canUseRolePreview) ...[
            const SizedBox(height: 12),
            const RolePreviewSelector(),
          ],
          const SizedBox(height: 16),

          // --- Shared items (superAdmin + admin) ---
          for (final item in sharedItems)
            _menuItem(
              context,
              item.icon,
              item.title,
              item.subtitle,
              item.bgColor,
              item.highlightColor,
              item.onTap,
            ),

          // --- superAdmin-only items ---
          if (showManagementSection) ...[
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Text(
                'LEAGUE MANAGEMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                  letterSpacing: 1,
                ),
              ),
            ),
            for (final item in managementItems)
              _menuItem(
                context,
                item.icon,
                item.title,
                item.subtitle,
                item.bgColor,
                item.highlightColor,
                item.onTap,
              ),
          ],

          const SizedBox(height: 16),
          if (canManageAssociation) ...[const SeasonManagementLauncher()],
        ],
      ),
    );
  }

  Widget _sidebarItem(_AdminMenuItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        leading: Icon(
          item.icon,
          size: 20,
          color: item.highlightColor ?? AppColors.textSecondary,
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: item.highlightColor ?? AppColors.textPrimary,
          ),
        ),
        subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 11)),
        hoverColor: AppColors.primaryLight,
        onTap: item.onTap,
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color? bgColor,
    Color? highlightColor,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor ?? AppColors.surface,
        border: Border.all(
          color: highlightColor?.withValues(alpha: 0.3) ?? AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        leading: Icon(icon, color: highlightColor ?? AppColors.textSecondary),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: highlightColor ?? AppColors.textPrimary,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}

/// Simple data holder for admin menu items so they can be shared between
/// the mobile list layout and the desktop sidebar layout.
class _AdminMenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? bgColor;
  final Color? highlightColor;
  final VoidCallback onTap;

  const _AdminMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.bgColor,
    this.highlightColor,
    required this.onTap,
  });
}

class RolePreviewSelector extends ConsumerWidget {
  const RolePreviewSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewRole = ref.watch(rolePreviewProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.roleSuperAdmin.withValues(alpha: 0.08),
        border: Border.all(
          color: AppColors.roleSuperAdmin.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility,
            size: 18,
            color: AppColors.roleSuperAdmin,
          ),
          const SizedBox(width: 8),
          const Text(
            'Preview as:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.roleSuperAdmin,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<UserRole?>(
                  key: const Key('role-preview-selector'),
                  value: previewRole,
                  isExpanded: true,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: [
                    const DropdownMenuItem<UserRole?>(
                      value: null,
                      child: Text('Your Role (Super Admin)'),
                    ),
                    ...UserRole.values
                        .where(
                          (r) =>
                              r != UserRole.superAdmin && r != UserRole.press,
                        )
                        .map(
                          (role) => DropdownMenuItem<UserRole?>(
                            value: role,
                            child: Text(
                              role == UserRole.media
                                  ? 'MEDIA'
                                  : role.name.toUpperCase(),
                            ),
                          ),
                        ),
                  ],
                  onChanged: (role) {
                    ref.read(rolePreviewProvider.notifier).state = role;
                    if (role != null) {
                      context.go(
                        role == UserRole.fan ? '/standings' : '/board',
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
