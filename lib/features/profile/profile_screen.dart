import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/team_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  bool _hasEdited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Color _roleBadgeColor(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return AppColors.roleSuperAdmin;
      case UserRole.admin:
        return AppColors.primary;
      case UserRole.statistician:
        return Colors.teal;
      case UserRole.rep:
        return AppColors.roleRep;
      case UserRole.press:
      case UserRole.media:
        return AppColors.accent;
      case UserRole.fan:
        return Colors.grey;
    }
  }

  String _roleLabel(UserModel user) {
    switch (user.role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.rep:
        return 'Team Rep';
      case UserRole.media:
      case UserRole.press:
        return 'Media';
      case UserRole.statistician:
        return 'Statistician';
      case UserRole.fan:
        return 'Fan';
      case UserRole.superAdmin:
        return 'Super Admin';
    }
  }

  Future<void> _saveName(UserModel user) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == user.displayName) return;

    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateUser(user.id, {
        'displayName': newName,
      });
      if (mounted) {
        setState(() {
          _hasEdited = false;
          _saving = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Name updated')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update name: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.urgent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final teams = ref.watch(teamsStreamProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Not signed in'));
          }

          // Initialize controller text on first load or when user changes
          if (!_hasEdited) {
            _nameController.text = user.displayName;
          }

          final teamName = user.teamId != null
              ? teams
                    .where((t) => t.id == user.teamId)
                    .map((t) => t.name)
                    .firstOrNull
              : null;

          return ListView(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            children: [
              // Avatar + name header
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Chip(
                  label: Text(
                    _roleLabel(user),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: _roleBadgeColor(user.role),
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(height: 24),

              // Name field (editable)
              _SectionCard(
                title: 'Display Name',
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'Enter your name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _hasEdited = val.trim() != user.displayName;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _hasEdited && !_saving
                          ? () => _saveName(user)
                          : null,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Email (read-only)
              _SectionCard(
                title: 'Email',
                child: Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.email,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Team (read-only)
              if (teamName != null) ...[
                _SectionCard(
                  title: 'Team',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        teamName,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Navigation links
              _SectionCard(
                title: 'App',
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.settings_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: const Text('Settings'),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => context.push('/settings'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.info_outline,
                        color: AppColors.textSecondary,
                      ),
                      title: const Text('About'),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => context.push('/about'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Sign out
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.urgent,
                    side: const BorderSide(color: AppColors.urgent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Reusable card wrapper for profile sections.
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.paddingMd),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
