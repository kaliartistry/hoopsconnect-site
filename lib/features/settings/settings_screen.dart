import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../app/app_version.dart';
import '../../app/router/app_route_contract.dart';
import '../../providers/auth_providers.dart';
import '../../providers/theme_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _ackReminders = true;
  bool _statReminders = true;
  bool _newPostNotifications = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Not signed in'));
          }

          // Initialize toggle state from Firestore on first load.
          // The notificationPrefs field may not exist yet, so we default to true.
          if (!_loaded) {
            final prefs = user.notificationPrefs;
            _ackReminders = prefs.ackReminders;
            _statReminders = prefs.statReminders;
            _newPostNotifications = prefs.newPosts;
            _loaded = true;
          }

          final themeMode = ref.watch(themeModeProvider);
          final version = ref.watch(appVersionInfoProvider);
          final cardColor =
              Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor;
          final borderColor = Theme.of(
            context,
          ).dividerColor.withValues(alpha: 0.3);

          return ListView(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            children: [
              // Appearance section
              _buildSectionHeader('Appearance'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    for (final entry in [
                      (ThemeMode.system, 'System', Icons.settings_brightness),
                      (ThemeMode.light, 'Light', Icons.light_mode),
                      (ThemeMode.dark, 'Dark', Icons.dark_mode),
                    ])
                      ListTile(
                        leading: Icon(entry.$3),
                        title: Text(entry.$2),
                        trailing: themeMode == entry.$1
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                        selected: themeMode == entry.$1,
                        selectedColor: AppColors.primary,
                        onTap: () {
                          ref
                              .read(themeModeProvider.notifier)
                              .setThemeMode(entry.$1);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Notifications section
              _buildSectionHeader('Notifications'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Acknowledgment Reminders'),
                      subtitle: const Text(
                        'Get reminded about pending acknowledgments',
                      ),
                      value: _ackReminders,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) => setState(() => _ackReminders = val),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('Stat Reminders'),
                      subtitle: const Text('Get reminded to enter game stats'),
                      value: _statReminders,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) => setState(() => _statReminders = val),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SwitchListTile(
                      title: const Text('New Post Notifications'),
                      subtitle: const Text(
                        'Get notified when new posts are published',
                      ),
                      value: _newPostNotifications,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) =>
                          setState(() => _newPostNotifications = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _savePrefs(user.id),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Preferences'),
                ),
              ),
              const SizedBox(height: 32),

              _buildSectionHeader('Account Access'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('settings-password-recovery'),
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('Password and sign-in help'),
                      subtitle: const Text(
                        'Reset an email password or choose your Google or Apple sign-in',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        Uri(
                          path: AppRouteContract.passwordRecovery,
                          queryParameters: {'email': user.email},
                        ).toString(),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      key: const Key('settings-delete-account'),
                      leading: const Icon(Icons.person_remove_outlined),
                      title: const Text('Delete account'),
                      subtitle: const Text(
                        'Review consequences and work saved on this device',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        AccountLifecycleRoutePaths.requestDeletion,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // App Info section
              _buildSectionHeader('App Info'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: Column(
                  children: [
                    ListTile(
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
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: const Text('Terms of Use'),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => context.push('/legal/terms'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => context.push('/legal/privacy'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(
                        Icons.tag,
                        color: AppColors.textSecondary,
                      ),
                      title: const Text('Version'),
                      trailing: Text(
                        version.when(
                          data: (value) => value.label,
                          loading: () => 'Loading…',
                          error: (_, _) => 'Unavailable',
                        ),
                        key: const Key('settings-version'),
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }

  Future<void> _savePrefs(String userId) async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateUser(userId, {
        'notificationPrefs': {
          'ackReminders': _ackReminders,
          'statReminders': _statReminders,
          'newPosts': _newPostNotifications,
        },
      });
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Preferences saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }
}
