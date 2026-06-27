import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/repositories/auth_repository.dart';
import '../services/repositories/invite_code_repository.dart';

/// Singleton repository providers.
final authRepositoryProvider = Provider((ref) => AuthRepository());
final inviteCodeRepositoryProvider = Provider((ref) => InviteCodeRepository());

/// Firebase auth state stream.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Current user document from Firestore (with role, team, etc.).
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return ref.read(authRepositoryProvider).watchUser(user.uid);
    },
    loading: () => Stream.value(null),
    error: (_, _) => Stream.value(null),
  );
});

/// The association ID for the current user.
/// Most queries require this.
final currentAssociationIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider).value?.associationId;
});
