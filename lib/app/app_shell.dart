import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_constants.dart';
import '../core/widgets/offline_banner.dart';
import '../core/widgets/responsive_layout.dart';
import '../core/widgets/sponsor_banner.dart';
import '../models/user_model.dart';
import '../providers/connectivity_providers.dart';
import '../providers/division_providers.dart';
import '../providers/role_preview_provider.dart';

/// Represents a tab entry with its branch index, icons, and label.
class _TabEntry {
  final int branchIndex;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _TabEntry({
    required this.branchIndex,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  /// Build the list of visible tabs based on user permissions.
  /// Branch indices: 0=Board, 1=Standings, 2=Stats, 3=Schedule, 4=Admin, 5=Press
  List<_TabEntry> _buildTabs({
    required bool showBoard,
    required bool showAdmin,
    required bool showPress,
  }) {
    final tabs = <_TabEntry>[];

    if (showBoard) {
      tabs.add(
        const _TabEntry(
          branchIndex: 0,
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Board',
        ),
      );
    }

    // Standings — always visible
    tabs.add(
      const _TabEntry(
        branchIndex: 1,
        icon: Icons.emoji_events_outlined,
        selectedIcon: Icons.emoji_events,
        label: 'Standings',
      ),
    );

    // Stats — always visible
    tabs.add(
      const _TabEntry(
        branchIndex: 2,
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard,
        label: 'Stats',
      ),
    );

    // Schedule — always visible
    tabs.add(
      const _TabEntry(
        branchIndex: 3,
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: 'Schedule',
      ),
    );

    if (showPress) {
      tabs.add(
        const _TabEntry(
          branchIndex: 5,
          icon: Icons.newspaper_outlined,
          selectedIcon: Icons.newspaper,
          label: 'Media',
        ),
      );
    }

    if (showAdmin) {
      tabs.add(
        const _TabEntry(
          branchIndex: 4,
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: 'Admin',
        ),
      );
    }

    return tabs;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveUser = ref.watch(effectiveUserProvider);
    final previewRole = ref.watch(rolePreviewProvider);
    final isPreviewActive = previewRole != null;
    final showAdmin = effectiveUser?.canAccessAdminPanel ?? false;
    final showPress = effectiveUser?.canAccessPressTools ?? false;
    final showBoard = effectiveUser?.canViewBoard ?? true;
    final wide = isWideScreen(context);
    final desktop = isDesktop(context);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    final tabs = _buildTabs(
      showBoard: showBoard,
      showAdmin: showAdmin,
      showPress: showPress,
    );

    // Map the current branch index back to the displayed tab index
    final currentBranch = navigationShell.currentIndex;
    int selectedIndex = 0;
    for (int i = 0; i < tabs.length; i++) {
      if (tabs[i].branchIndex == currentBranch) {
        selectedIndex = i;
        break;
      }
    }
    // Clamp to valid range
    selectedIndex = selectedIndex.clamp(0, tabs.length - 1);
    final showLeagueScope = currentBranch >= 0 && currentBranch <= 3;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              extended: desktop,
              minExtendedWidth: 200,
              onDestinationSelected: (index) {
                final branchIndex = tabs[index].branchIndex;
                navigationShell.goBranch(
                  branchIndex,
                  initialLocation: branchIndex == navigationShell.currentIndex,
                );
              },
              labelType: desktop
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              destinations: tabs
                  .map(
                    (tab) => NavigationRailDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: Text(tab.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OfflineBanner(isOffline: !isOnline),
                        if (isPreviewActive)
                          _RolePreviewBanner(role: previewRole, ref: ref),
                        if (showLeagueScope) const _LeagueScopeBar(),
                        const SponsorBanner(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: navigationShell,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile: bottom navigation bar (original layout)
    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OfflineBanner(isOffline: !isOnline),
                if (showLeagueScope) const _LeagueScopeBar(),
                const SponsorBanner(),
              ],
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: navigationShell,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final branchIndex = tabs[index].branchIndex;
          navigationShell.goBranch(
            branchIndex,
            initialLocation: branchIndex == navigationShell.currentIndex,
          );
        },
        destinations: tabs
            .map(
              (tab) => NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LeagueScopeBar extends ConsumerWidget {
  const _LeagueScopeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final divisions =
        ref.watch(divisionsStreamProvider).valueOrNull ?? const [];
    final selectedDivisionId = ref.watch(selectedDivisionIdProvider);
    final selectedDivision = ref.watch(selectedDivisionProvider);

    if (divisions.isEmpty) return const SizedBox.shrink();

    final accentColor = AppColors.divisionColor(selectedDivisionId);

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'League',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.divisionTint(selectedDivisionId),
                  border: Border.all(
                    color: AppColors.divisionBorder(selectedDivisionId),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedDivisionId,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: accentColor,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Leagues'),
                      ),
                      ...divisions.map(
                        (division) => DropdownMenuItem<String?>(
                          value: division.id,
                          child: Text(division.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      ref.read(selectedDivisionIdProvider.notifier).state =
                          value;
                    },
                  ),
                ),
              ),
            ),
            if (selectedDivision != null) ...[
              const SizedBox(width: 10),
              TextButton(
                onPressed: () {
                  ref.read(selectedDivisionIdProvider.notifier).state = null;
                },
                child: const Text('All'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RolePreviewBanner extends StatelessWidget {
  final UserRole role;
  final WidgetRef ref;

  const _RolePreviewBanner({required this.role, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.roleSuperAdmin.withValues(alpha: 0.9),
      child: Row(
        children: [
          const Icon(Icons.visibility, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            'Previewing as ${role == UserRole.superAdmin ? "SUPER ADMIN" : role.name.toUpperCase()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => ref.read(rolePreviewProvider.notifier).state = null,
            child: const Text(
              'EXIT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
