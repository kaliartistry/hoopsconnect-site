import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../services/repositories/auth_repository.dart';

/// The authentication operations available to the login presentation.
///
/// Keeping this narrow interface behind a provider lets widget tests exercise
/// the same production method selection without adding a callback that can
/// intercept plaintext credentials through the login screen's public API.
abstract interface class LoginAuthActions {
  Future<void> signIn({required String email, required String password});

  Future<void> signUpFan({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();
}

final loginAuthActionsProvider = Provider<LoginAuthActions>((ref) {
  return RepositoryLoginAuthActions(ref.watch(authRepositoryProvider));
});

class RepositoryLoginAuthActions implements LoginAuthActions {
  const RepositoryLoginAuthActions(this._repository);

  final AuthRepository _repository;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _repository.signIn(email: email, password: password);
  }

  @override
  Future<void> signUpFan({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _repository.signUpFan(
      email: email,
      password: password,
      displayName: displayName,
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    await _repository.signInWithGoogle();
  }

  @override
  Future<void> signInWithApple() async {
    await _repository.signInWithApple();
  }
}
