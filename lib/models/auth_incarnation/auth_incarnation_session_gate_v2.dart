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
  final int sessionAttemptEpochV2;
  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;

  AuthIncarnationSessionAttemptV2._issued({
    required String attemptId,
    required int sessionAttemptEpochV2,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) : this._(
         attemptId: _validateAttemptId(attemptId),
         sessionAttemptEpochV2: _validateSessionAttemptEpoch(
           sessionAttemptEpochV2,
         ),
         scope: AuthIncarnationScopeV2.fromMap(scope.toMap()),
         accountGenerationV2: _validateGeneration(accountGenerationV2),
         accountLifecycleEpochV2: _validateEpoch(accountLifecycleEpochV2),
       );

  const AuthIncarnationSessionAttemptV2._({
    required this.attemptId,
    required this.sessionAttemptEpochV2,
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

  static int _validateSessionAttemptEpoch(int value) {
    if (value <= 0 || value > AuthIncarnationV2.maxSafeInteger) {
      throw const FormatException(
        'Invalid Auth incarnation V2 session attempt epoch.',
      );
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
      sessionAttemptEpochV2 == other.sessionAttemptEpochV2 &&
      sameSessionIdentity(other);

  bool sameSessionIdentity(AuthIncarnationSessionAttemptV2 other) =>
      scope.sameAs(other.scope) &&
      accountGenerationV2 == other.accountGenerationV2 &&
      accountLifecycleEpochV2 == other.accountLifecycleEpochV2;

  bool matchesBinding(ValidatedActiveAuthorityV2 binding) =>
      attemptId == binding.sessionAttemptIdV2 &&
      sessionAttemptEpochV2 == binding.sessionAttemptEpochV2 &&
      scope.sameAs(binding.scope) &&
      accountGenerationV2 == binding.accountGenerationV2 &&
      accountLifecycleEpochV2 == binding.accountLifecycleEpochV2;
}

final class AuthIncarnationSessionEventV2 {
  final AuthIncarnationSessionEventKindV2 kind;
  final AuthIncarnationSessionAttemptV2? attempt;
  final ValidatedActiveAuthorityV2? binding;
  final AuthIncarnationSessionAttemptV2? nextAttempt;

  const AuthIncarnationSessionEventV2._(
    this.kind,
    this.attempt,
    this.binding,
    this.nextAttempt,
  );

  const AuthIncarnationSessionEventV2.signedOut()
    : this._(AuthIncarnationSessionEventKindV2.signedOut, null, null, null);

  AuthIncarnationSessionEventV2.authObserved(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.authObserved,
        attempt,
        null,
        null,
      );

  AuthIncarnationSessionEventV2.accountSwitchStarted(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.accountSwitchStarted,
        attempt,
        null,
        null,
      );

  AuthIncarnationSessionEventV2.proofReady({
    required AuthIncarnationSessionAttemptV2 attempt,
    required ValidatedActiveAuthorityV2 binding,
  }) : this._(
         AuthIncarnationSessionEventKindV2.proofReady,
         attempt,
         binding,
         null,
       );

  AuthIncarnationSessionEventV2.refreshRequired({
    required AuthIncarnationSessionAttemptV2 currentAttempt,
    required AuthIncarnationSessionAttemptV2 refreshedAttempt,
  }) : this._(
         AuthIncarnationSessionEventKindV2.refreshRequired,
         currentAttempt,
         null,
         refreshedAttempt,
       );

  AuthIncarnationSessionEventV2.proofLost(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(AuthIncarnationSessionEventKindV2.proofLost, attempt, null, null);

  AuthIncarnationSessionEventV2.lifecycleDeleting(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.lifecycleDeleting,
        attempt,
        null,
        null,
      );

  AuthIncarnationSessionEventV2.lifecycleDeleted(
    AuthIncarnationSessionAttemptV2 attempt,
  ) : this._(
        AuthIncarnationSessionEventKindV2.lifecycleDeleted,
        attempt,
        null,
        null,
      );
}

final class AuthIncarnationSessionGateV2 {
  final AuthIncarnationSessionStateV2 state;
  final AuthIncarnationSessionAttemptV2? attempt;
  final int sessionAttemptHighWaterV2;

  const AuthIncarnationSessionGateV2._(
    this.state,
    this.attempt,
    this.sessionAttemptHighWaterV2,
  );

  const AuthIncarnationSessionGateV2.signedOut()
    : this._(AuthIncarnationSessionStateV2.signedOut, null, 0);

  AuthIncarnationSessionAttemptV2 issueAttempt({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) {
    if (sessionAttemptHighWaterV2 == AuthIncarnationV2.maxSafeInteger) {
      throw StateError('Auth incarnation V2 session attempt epoch exhausted.');
    }
    return AuthIncarnationSessionAttemptV2._issued(
      attemptId: attemptId,
      sessionAttemptEpochV2: sessionAttemptHighWaterV2 + 1,
      scope: scope,
      accountGenerationV2: accountGenerationV2,
      accountLifecycleEpochV2: accountLifecycleEpochV2,
    );
  }

  bool get permitsProtectedListeners =>
      state == AuthIncarnationSessionStateV2.ready;

  bool get permitsCapabilities => permitsProtectedListeners;

  bool get permitsFcmRegistration => permitsProtectedListeners;

  bool _acceptsNextAttempt(AuthIncarnationSessionAttemptV2 nextAttempt) =>
      sessionAttemptHighWaterV2 < AuthIncarnationV2.maxSafeInteger &&
      nextAttempt.sessionAttemptEpochV2 == sessionAttemptHighWaterV2 + 1;

  AuthIncarnationSessionGateV2 transition(AuthIncarnationSessionEventV2 event) {
    if (event.kind == AuthIncarnationSessionEventKindV2.signedOut) {
      return AuthIncarnationSessionGateV2._(
        AuthIncarnationSessionStateV2.signedOut,
        null,
        sessionAttemptHighWaterV2,
      );
    }
    if (event.kind == AuthIncarnationSessionEventKindV2.accountSwitchStarted) {
      final nextAttempt = event.attempt;
      if (nextAttempt == null || !_acceptsNextAttempt(nextAttempt)) {
        return this;
      }
      return AuthIncarnationSessionGateV2._(
        AuthIncarnationSessionStateV2.establishing,
        nextAttempt,
        nextAttempt.sessionAttemptEpochV2,
      );
    }
    if (event.kind == AuthIncarnationSessionEventKindV2.authObserved) {
      final nextAttempt = event.attempt;
      return state == AuthIncarnationSessionStateV2.signedOut &&
              nextAttempt != null &&
              _acceptsNextAttempt(nextAttempt)
          ? AuthIncarnationSessionGateV2._(
              AuthIncarnationSessionStateV2.establishing,
              nextAttempt,
              nextAttempt.sessionAttemptEpochV2,
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
    if (event.kind == AuthIncarnationSessionEventKindV2.refreshRequired) {
      final refreshedAttempt = event.nextAttempt;
      final mayRefresh =
          state == AuthIncarnationSessionStateV2.establishing ||
          state == AuthIncarnationSessionStateV2.refreshRequired ||
          state == AuthIncarnationSessionStateV2.ready;
      if (!mayRefresh ||
          refreshedAttempt == null ||
          currentAttempt.sameAttempt(refreshedAttempt) ||
          !currentAttempt.sameSessionIdentity(refreshedAttempt)) {
        return AuthIncarnationSessionGateV2._(
          AuthIncarnationSessionStateV2.blocked,
          currentAttempt,
          sessionAttemptHighWaterV2,
        );
      }
      if (!_acceptsNextAttempt(refreshedAttempt)) {
        return this;
      }
      return AuthIncarnationSessionGateV2._(
        AuthIncarnationSessionStateV2.refreshRequired,
        refreshedAttempt,
        refreshedAttempt.sessionAttemptEpochV2,
      );
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
      AuthIncarnationSessionEventKindV2.refreshRequired => state,
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
    return AuthIncarnationSessionGateV2._(
      next,
      currentAttempt,
      sessionAttemptHighWaterV2,
    );
  }
}
