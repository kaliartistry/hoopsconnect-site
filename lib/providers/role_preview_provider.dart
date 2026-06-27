import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'auth_providers.dart';

/// When non-null, super admins see the app as if they had this role.
/// Set to null to exit preview mode.
final rolePreviewProvider = StateProvider<UserRole?>((ref) => null);

/// Returns the user with the preview role applied (if active).
/// Only super admins can use preview mode. Identity (id, email, etc.)
/// is preserved — only the role changes for permission checks.
final effectiveUserProvider = Provider<UserModel?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  final previewRole = ref.watch(rolePreviewProvider);

  if (user == null || previewRole == null || !user.isSuperAdmin) return user;

  return user.copyWith(role: previewRole);
});
