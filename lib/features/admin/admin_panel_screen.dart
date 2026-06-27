import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/firestore_paths.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../models/user_model.dart';
import '../../providers/ack_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/role_preview_provider.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';

class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final isSuperAdmin = currentUser?.isSuperAdmin ?? false;
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
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      _AdminMenuItem(
        icon: Icons.sports_score,
        title: 'Enter Game Stats',
        subtitle: '$gamesCount game${gamesCount == 1 ? '' : 's'} need stats',
        bgColor: AppColors.statBg,
        highlightColor: AppColors.statHighlight,
        onTap: () => context.push('/admin/stats'),
      ),
      _AdminMenuItem(
        icon: Icons.leaderboard,
        title: 'Season Leaderboard',
        subtitle: 'View & manage rankings',
        bgColor: AppColors.statBg,
        highlightColor: AppColors.statHighlight,
        onTap: () => context.go('/leaderboard'),
      ),
      _AdminMenuItem(
        icon: Icons.bolt,
        title: 'Acknowledgment Tracker',
        subtitle: '$ackCount post${ackCount == 1 ? '' : 's'} pending',
        bgColor: AppColors.ackBg,
        highlightColor: AppColors.ack,
        onTap: () => context.push('/admin/ack-tracker'),
      ),
    ];

    final superAdminItems = <_AdminMenuItem>[
      _AdminMenuItem(
        icon: Icons.groups,
        title: 'Teams & Rosters',
        subtitle: '$teamCount team${teamCount == 1 ? '' : 's'}',
        onTap: () => context.push('/admin/teams'),
      ),
      _AdminMenuItem(
        icon: Icons.people,
        title: 'User Management',
        subtitle: 'Manage roles & permissions',
        onTap: () => context.push('/admin/users'),
      ),
      _AdminMenuItem(
        icon: Icons.category,
        title: 'Divisions / Leagues',
        subtitle: 'Manage divisions',
        onTap: () => context.push('/admin/divisions'),
      ),
      _AdminMenuItem(
        icon: Icons.vpn_key,
        title: 'Invite Codes',
        subtitle: 'Generate & manage codes',
        onTap: () => context.push('/admin/invite-codes'),
      ),
      _AdminMenuItem(
        icon: Icons.schedule,
        title: 'Game Schedule',
        subtitle: 'Add games to calendar',
        onTap: () => context.push('/admin/schedule'),
      ),
      _AdminMenuItem(
        icon: Icons.campaign,
        title: 'Push Announcement',
        subtitle: 'Send to all teams',
        onTap: () => context.push('/board/create', extra: {
          'pinned': true,
          'urgent': true,
          'requiresAck': true,
        }),
      ),
    ];

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
                    const SizedBox(height: 16),
                    for (final item in sharedItems)
                      _sidebarItem(item),
                    if (isSuperAdmin) ...[
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
                      for (final item in superAdminItems)
                        _sidebarItem(item),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () =>
                            _showArchiveSeasonDialog(context, ref),
                        child: const Text('Archive Season'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () =>
                            _showNewSeasonDialog(context, ref),
                        child: const Text('New Season'),
                      ),
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
          if (isSuperAdmin) ...[
            const SizedBox(height: 12),
            _RolePreviewSelector(ref: ref),
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
          if (isSuperAdmin) ...[
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
            for (final item in superAdminItems)
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
          if (isSuperAdmin) ...[
            OutlinedButton(
              onPressed: () => _showArchiveSeasonDialog(context, ref),
              child: const Text('Archive Season'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showNewSeasonDialog(context, ref),
              child: const Text('New Season'),
            ),
          ],
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
        subtitle: Text(
          item.subtitle,
          style: const TextStyle(fontSize: 11),
        ),
        hoverColor: AppColors.primaryLight,
        onTap: item.onTap,
      ),
    );
  }

  void _showNewSeasonDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(AppDefaults.seasonEndOffset);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create New Season'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Season Name',
                  hintText: 'e.g. NBL 2026-27',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start Date'),
                subtitle: Text(
                  '${startDate.month}/${startDate.day}/${startDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: startDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() => startDate = picked);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End Date'),
                subtitle: Text(
                  '${endDate.month}/${endDate.day}/${endDate.year}',
                ),
                trailing: const Icon(Icons.calendar_today, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: endDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() => endDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final assocId = ref.read(currentAssociationIdProvider);
                if (assocId == null) return;

                final seasonId = name
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
                    .replaceAll(RegExp(r'^-|-$'), '');

                final db = FirebaseFirestore.instance;
                final batch = db.batch();

                batch.set(
                  db.doc(FirestorePaths.season(assocId, seasonId)),
                  {
                    'name': name,
                    'startDate': Timestamp.fromDate(startDate),
                    'endDate': Timestamp.fromDate(endDate),
                    'isActive': true,
                  },
                );

                batch.update(
                  db.doc(FirestorePaths.association(assocId)),
                  {'currentSeasonId': seasonId},
                );

                await batch.commit();

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Season "$name" created')),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showArchiveSeasonDialog(BuildContext context, WidgetRef ref) {
    final seasonName =
        ref.read(activeSeasonNameProvider).value ?? 'this season';
    final seasonId = ref.read(activeSeasonIdProvider).value;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Season'),
        content: Text(
          'Are you sure you want to archive "$seasonName"? '
          'This will mark the season as inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.urgent,
            ),
            onPressed: () async {
              final assocId = ref.read(currentAssociationIdProvider);
              if (assocId == null || seasonId == null) return;

              await FirebaseFirestore.instance
                  .doc(FirestorePaths.season(assocId, seasonId))
                  .update({'isActive': false});

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"$seasonName" archived')),
                );
              }
            },
            child: const Text('Archive'),
          ),
        ],
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
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
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

class _RolePreviewSelector extends StatelessWidget {
  final WidgetRef ref;

  const _RolePreviewSelector({required this.ref});

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.visibility, size: 18, color: AppColors.roleSuperAdmin),
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
                        .where((r) => r != UserRole.superAdmin)
                        .map((role) => DropdownMenuItem<UserRole?>(
                              value: role,
                              child: Text(role.name.toUpperCase()),
                            )),
                  ],
                  onChanged: (role) {
                    ref.read(rolePreviewProvider.notifier).state = role;
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
