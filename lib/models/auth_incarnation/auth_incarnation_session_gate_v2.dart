import 'auth_incarnation_v2.dart';

enum AuthIncarnationSessionStateV2 {
  signedOut,
  establishing,
  refreshRequired,
  ready,
  blocked,
  deleting,
  deleted,
}

enum AuthIncarnationSessionEventKindV2 {
  authObserved,
  proofReady,
  refreshRequired,
  proofLost,
  lifecycleDeleting,
  lifecycleDeleted,
  accountSwitchStarted,
  signedOut,
}

final class AuthIncarnationSessionAttemptV2 {
  final String attemptId;
  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;

  AuthIncarnationSessionAttemptV2({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) : this._(
         attemptId: _validateAttemptId(attemptId),
         scope: AuthIncarnationScopeV2.fromMap(scope.toMap()),
         accountGenerationV2: _validateGeneration(accountGenerationV2),
         accountLifecycleEpochV2: _validateEpoch(accountLifecycleEpochV2),
       );

  const AuthIncarnationSessionAttemptV2._({
    required this.attemptId,
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
  });

  static String _validateAttemptId(String value) {
    if (value.isEmpty ||
        value.length > 128 ||
        value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const FormatException('Invalid Auth incarnation V2 attempt ID.');
    }
    return value;
  }

  static String _validateGeneration(String value) {
    if (!AuthIncarnationV2.generationPattern.hasMatch(value)) {
      throw const FormatException('Invalid Auth incarnation V2 generation.');
    }
    return value;
  }

  static int _validateEpoch(int value) {
    if (value < 0 || value > AuthIncarnationV2.maxSafeInteger) {
      throw const FormatException(
        'Invalid Auth incarnation V2 lifecycle epoch.',
      );
    }
    return value;
  }

  bool sameAttempt(AuthIncarnationSessionAttemptV2 other) =>
      attemptId == other.attemptId &&
      scope.sameAs(other.scope) &&
      accountGenerationV2 == other.accountGenerationV2 &&
      accountLifecycleEpochV2 == other.accountLifecycleEpochV2;

  bool matchesBinding(ValidatedActiveAuthorityV2 binding) =>
      scope.sameAs(binding.scope) &&
      accountGenerationV2 == binding.accountGenerationV2 &&
      accountLifecycleEpochV2 == binding.accountLifecycleEpochV2;
}

final class AuthIncarnationSessionEventV2 {
  final AuthIncarnationSessionEventKindV2 kind;
  final AuthIncarnationSessionAttemptV2? attempt;
  final ValidatedActiveAuthorityV2? binding;

  const AuthIncarnationSessionEventV2._(this.kind, this.attempt, this.binding);

  const AuthIncarnationSessionEventV2.signedOut()
    : this._(AuthIncarnationSessionEventKindV2.signedOut, null, null);

  AuthIncarnationSessionEventV2.authObserved(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(AuthIncarnationSessionEventKindV2.authObserved, attempt, null);

  AuthIncarnationSessionEventV2.accountSwitchStarted(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.accountSwitchStarted,
        attempt,
        null,
      );

  AuthIncarnationSessionEventV2.proofReady({
    required AuthIncarnationSessionAttemptV2 attempt,
    required ValidatedActiveAuthorityV2 binding,
  }) : this._(AuthIncarnationSessionEventKindV2.proofReady, attempt, binding);

  AuthIncarnationSessionEventV2.refreshRequired(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(AuthIncarnationSessionEventKindV2.refreshRequired, attempt, null);

  AuthIncarnationSessionEventV2.proofLost(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(AuthIncarnationSessionEventKindV2.proofLost, attempt, null);

  AuthIncarnationSessionEventV2.lifecycleDeleting(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.lifecycleDeleting,
        attempt,
        null,
      );

  AuthIncarnationSessionEventV2.lifecycleDeleted(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(AuthIncarnationSessionEventKindV2.lifecycleDeleted, attempt, null);
}

final class AuthIncarnationSessionGateV2 {
  final AuthIncarnationSessionStateV2 state;
  final AuthIncarnationSessionAttemptV2? attempt;

  const AuthIncarnationSessionGateV2._(this.state, this.attempt);

  const AuthIncarnationSessionGateV2.signedOut()
    : this._(AuthIncarnationSessionStateV2.signedOut, null);

  bool get permitsProtectedListeners =>
      state == AuthIncarnationSessionStateV2.ready;

  bool get permitsCapabilities => permitsProtectedListeners;

  bool get permitsFcmRegistration => permitsProtectedListeners;

  AuthIncarnationSessionGateV2 transition(AuthIncarnationSessionEventV2 event) {
    if (event.kind == AuthIncarnationSessionEventKindV2.signedOut) {
      return const AuthIncarnationSessionGateV2.signedOut();
    }
    if (event.kind == AuthIncarnationSessionEventKindV2.accountSwitchStarted) {
      return AuthIncarnationSessionGateV2._(
        AuthIncarnationSessionStateV2.establishing,
        event.attempt,
      );
    }
    if (event.kind == AuthIncarnationSessionEventKindV2.authObserved) {
      return state == AuthIncarnationSessionStateV2.signedOut
          ? AuthIncarnationSessionGateV2._(
              AuthIncarnationSessionStateV2.establishing,
              event.attempt,
            )
          : this;
    }

    final currentAttempt = attempt;
    final eventAttempt = event.attempt;
    if (currentAttempt == null ||
        eventAttempt == null ||
        !currentAttempt.sameAttempt(eventAttempt)) {
      // Obsolete asynchronous completions cannot affect the current attempt.
      return this;
    }
    if (state == AuthIncarnationSessionStateV2.deleting ||
        state == AuthIncarnationSessionStateV2.deleted) {
      return this;
    }

    final next = switch (event.kind) {
      AuthIncarnationSessionEventKindV2.proofReady =>
        (state == AuthIncarnationSessionStateV2.establishing ||
                    state == AuthIncarnationSessionStateV2.ready ||
                    state == AuthIncarnationSessionStateV2.refreshRequired) &&
                event.binding != null &&
                currentAttempt.matchesBinding(event.binding!)
            ? AuthIncarnationSessionStateV2.ready
            : AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventKindV2.refreshRequired =>
        state == AuthIncarnationSessionStateV2.establishing ||
                state == AuthIncarnationSessionStateV2.refreshRequired ||
                state == AuthIncarnationSessionStateV2.ready
            ? AuthIncarnationSessionStateV2.refreshRequired
            : state,
      AuthIncarnationSessionEventKindV2.proofLost =>
        AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventKindV2.lifecycleDeleting =>
        AuthIncarnationSessionStateV2.deleting,
      AuthIncarnationSessionEventKindV2.lifecycleDeleted =>
        AuthIncarnationSessionStateV2.deleted,
      AuthIncarnationSessionEventKindV2.authObserved ||
      AuthIncarnationSessionEventKindV2.accountSwitchStarted ||
      AuthIncarnationSessionEventKindV2.signedOut => state,
    };
    return AuthIncarnationSessionGateV2._(next, currentAttempt);
  }
}
