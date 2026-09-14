import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../app/router/app_route_contract.dart';
import 'auth_providers.dart';

/// When non-null, super admins see the app as if they had this role.
/// Set to null to exit preview mode.
final rolePreviewProvider = StateProvider<UserRole?>((ref) => null);

/// A preview is active only for a membership that really holds members.manage.
final activeRolePreviewProvider = Provider<UserRole?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final requested = ref.watch(rolePreviewProvider);
  return user?.canManageUsers == true ? requested : null;
});

/// Returns the user with the preview role applied (if active).
/// Only super admins can use preview mode. Identity (id, email, etc.)
/// is preserved, and the real currentUserProvider value is never changed.
/// The returned copy has the preview role's presentation capabilities only;
/// route and action gates continue to use the real membership.
final effectiveUserProvider = Provider<UserModel?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final previewRole = ref.watch(activeRolePreviewProvider);

  if (user == null || previewRole == null) return user;

  return user.copyWith(
    role: previewRole,
    capabilities: previewCapabilitiesForRole(previewRole),
  );
});
