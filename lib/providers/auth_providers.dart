import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/membership_model.dart';
import '../models/user_model.dart';
import '../services/repositories/auth_repository.dart';
import '../services/repositories/invite_code_repository.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository());
final inviteCodeRepositoryProvider = Provider((ref) => InviteCodeRepository());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) => user == null
        ? Stream.value(null)
        : ref.read(authRepositoryProvider).watchUser(user.uid),
    loading: () => Stream.value(null),
    error: (_, _) => Stream.value(null),
  );
});

final currentMembershipProvider = StreamProvider<MembershipModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) => user == null
        ? Stream.value(null)
        : ref.read(authRepositoryProvider).watchMembership(user.uid),
    loading: () => Stream.value(null),
    error: (_, _) => Stream.value(null),
  );
});

enum AccountAccessStatus {
  signedOut,
  loading,
  pendingProvisioning,
  active,
  blocked,
}

AccountAccessStatus resolveAccountAccess({
  required bool isAuthenticated,
  required UserModel? profile,
  required MembershipModel? membership,
  bool loading = false,
}) {
  if (loading) return AccountAccessStatus.loading;
  if (!isAuthenticated) return AccountAccessStatus.signedOut;
  if (profile == null && membership == null) {
    return AccountAccessStatus.pendingProvisioning;
  }
  if (profile == null ||
      membership == null ||
      !membership.matchesProfile(profile)) {
    return AccountAccessStatus.blocked;
  }
  return AccountAccessStatus.active;
}

final accountAccessStatusProvider = Provider<AccountAccessStatus>((ref) {
  final auth = ref.watch(authStateProvider);
  final profile = ref.watch(currentUserProfileProvider);
  final membership = ref.watch(currentMembershipProvider);
  if (auth.hasError || profile.hasError || membership.hasError) {
    return AccountAccessStatus.blocked;
  }
  return resolveAccountAccess(
    isAuthenticated: auth.value != null,
    profile: profile.value,
    membership: membership.value,
    loading: auth.isLoading || profile.isLoading || membership.isLoading,
  );
});

/// Effective UI identity. Profile fields remain display data; tenant, role and
/// every permission are replaced with the active server-owned membership.
final currentUserProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  final membership = ref.watch(currentMembershipProvider);
  if (profile.isLoading || membership.isLoading) {
    return const AsyncValue.loading();
  }
  if (profile.hasError) {
    return AsyncValue.error(profile.error!, profile.stackTrace!);
  }
  if (membership.hasError) {
    return AsyncValue.error(membership.error!, membership.stackTrace!);
  }
  final user = profile.value;
  final authority = membership.value;
  if (user == null || authority == null || !authority.matchesProfile(user)) {
    return const AsyncValue.data(null);
  }
  return AsyncValue.data(
    user.copyWith(
      associationId: authority.associationId,
      teamId: authority.teamId,
      divisionId: authority.divisionId,
      role: authority.role,
      capabilities: authority.capabilities,
    ),
  );
});

final currentAssociationIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).value?.associationId;
});
