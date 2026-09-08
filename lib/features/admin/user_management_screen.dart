import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';

/// Provider to fetch all users.
final allUsersProvider = FutureProvider<List<UserModel>>((ref) {
  final associationId = ref.watch(currentAssociationIdProvider);
  if (associationId == null) return Future.value([]);
  return ref.read(authRepositoryProvider).getAllUsers(associationId);
});

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: usersAsync.when(
          data: (users) => Text('User Management (${users.length})'),
          loading: () => const Text('User Management'),
          error: (_, _) => const Text('User Management'),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),

          // User list
          Expanded(
            child: usersAsync.when(
              data: (users) {
                final filtered = _searchQuery.isEmpty
                    ? users
                    : users
                          .where(
                            (u) =>
                                u.displayName.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                u.email.toLowerCase().contains(_searchQuery) ||
                                u.role.name.contains(_searchQuery),
                          )
                          .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 48,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No users found'
                              : 'No users match "$_searchQuery"',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    return _UserCard(user: user);
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  final UserModel user;
  const _UserCard({required this.user});

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

  String _roleLabel(UserRole role) {
    return role == UserRole.superAdmin
        ? 'SUPER ADMIN'
        : role.name.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).value;
    final canChangeRoles = currentUser?.canManageUsers ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _roleBadgeColor(user.role).withValues(alpha: 0.1),
          child: Icon(Icons.person, color: _roleBadgeColor(user.role)),
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          user.email,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: canChangeRoles && user.email != AppDefaults.ownerEmail
            ? _RoleDropdown(user: user)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user.email == AppDefaults.ownerEmail)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.lock,
                        size: 14,
                        color: AppColors.roleSuperAdmin,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _roleBadgeColor(user.role).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      user.email == AppDefaults.ownerEmail
                          ? 'OWNER'
                          : _roleLabel(user.role),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _roleBadgeColor(user.role),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RoleDropdown extends ConsumerStatefulWidget {
  final UserModel user;
  const _RoleDropdown({required this.user});

  @override
  ConsumerState<_RoleDropdown> createState() => _RoleDropdownState();
}

class _RoleDropdownState extends ConsumerState<_RoleDropdown> {
  late UserRole _currentRole;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.user.role;
  }

  Future<void> _confirmAndUpdateRole(UserRole newRole) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Role'),
        content: Text(
          'Change ${widget.user.displayName} from '
          '${_currentRole.name.toUpperCase()} to ${newRole.name.toUpperCase()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .setMemberRole(widget.user.id, newRole);
      setState(() => _currentRole = newRole);
      ref.invalidate(allUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.user.displayName} is now ${newRole.name}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saving) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<UserRole>(
        value: _currentRole,
        underline: const SizedBox(),
        isDense: true,
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        items: UserRole.values.map((role) {
          final label = role == UserRole.superAdmin
              ? 'SUPER ADMIN'
              : role.name.toUpperCase();
          return DropdownMenuItem(
            value: role,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          );
        }).toList(),
        onChanged: (role) {
          if (role != null && role != _currentRole) {
            _confirmAndUpdateRole(role);
          }
        },
      ),
    );
  }
}
