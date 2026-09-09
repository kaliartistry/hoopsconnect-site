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
  proofReady,
  proofLost,
  lifecycleDeleting,
  lifecycleDeleted,
  signedOut,
}

final class AuthIncarnationSessionAttemptV2 {
  final String attemptId;
  final int sessionAttemptEpochV2;
  final Object sessionAttemptNonceV2;
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
         sessionAttemptNonceV2: Object(),
         scope: AuthIncarnationScopeV2.fromMap(scope.toMap()),
         accountGenerationV2: _validateGeneration(accountGenerationV2),
         accountLifecycleEpochV2: _validateLifecycleEpoch(
           accountLifecycleEpochV2,
         ),
       );

  const AuthIncarnationSessionAttemptV2._({
    required this.attemptId,
    required this.sessionAttemptEpochV2,
    required this.sessionAttemptNonceV2,
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

  static int _validateSessionAttemptEpoch(int value) {
    if (value <= 0 || value > AuthIncarnationV2.maxSafeInteger) {
      throw const FormatException(
        'Invalid Auth incarnation V2 session attempt epoch.',
      );
    }
    return value;
  }

  static String _validateGeneration(String value) {
    if (!AuthIncarnationV2.generationPattern.hasMatch(value)) {
      throw const FormatException('Invalid Auth incarnation V2 generation.');
    }
    return value;
  }

  static int _validateLifecycleEpoch(int value) {
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
      identical(sessionAttemptNonceV2, other.sessionAttemptNonceV2) &&
      sameSessionIdentity(other);

  bool sameSessionIdentity(AuthIncarnationSessionAttemptV2 other) =>
      scope.sameAs(other.scope) &&
      accountGenerationV2 == other.accountGenerationV2 &&
      accountLifecycleEpochV2 == other.accountLifecycleEpochV2;

  bool matchesBinding(ValidatedActiveAuthorityV2 binding) =>
      attemptId == binding.sessionAttemptIdV2 &&
      sessionAttemptEpochV2 == binding.sessionAttemptEpochV2 &&
      identical(sessionAttemptNonceV2, binding.sessionAttemptNonceV2) &&
      scope.sameAs(binding.scope) &&
      accountGenerationV2 == binding.accountGenerationV2 &&
      accountLifecycleEpochV2 == binding.accountLifecycleEpochV2;
}

final class AuthIncarnationSessionAdvanceV2 {
  final AuthIncarnationSessionGateV2 gate;
  final AuthIncarnationSessionAttemptV2 attempt;

  const AuthIncarnationSessionAdvanceV2._(this.gate, this.attempt);
}

final class AuthIncarnationSessionEventV2 {
  final AuthIncarnationSessionEventKindV2 kind;
  final AuthIncarnationSessionAttemptV2? attempt;
  final ValidatedActiveAuthorityV2? binding;

  const AuthIncarnationSessionEventV2._(this.kind, this.attempt, this.binding);

  const AuthIncarnationSessionEventV2.signedOut()
    : this._(AuthIncarnationSessionEventKindV2.signedOut, null, null);

  AuthIncarnationSessionEventV2.proofReady({
    required AuthIncarnationSessionAttemptV2 attempt,
    required ValidatedActiveAuthorityV2 binding,
  }) : this._(AuthIncarnationSessionEventKindV2.proofReady, attempt, binding);

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
  final int sessionAttemptHighWaterV2;

  const AuthIncarnationSessionGateV2._(
    this.state,
    this.attempt,
    this.sessionAttemptHighWaterV2,
  );

  const AuthIncarnationSessionGateV2.signedOut()
    : this._(AuthIncarnationSessionStateV2.signedOut, null, 0);

  AuthIncarnationSessionAdvanceV2 _advance({
    required AuthIncarnationSessionStateV2 nextState,
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) {
    if (sessionAttemptHighWaterV2 == AuthIncarnationV2.maxSafeInteger) {
      throw StateError('Auth incarnation V2 session attempt epoch exhausted.');
    }
    final issued = AuthIncarnationSessionAttemptV2._issued(
      attemptId: attemptId,
      sessionAttemptEpochV2: sessionAttemptHighWaterV2 + 1,
      scope: scope,
      accountGenerationV2: accountGenerationV2,
      accountLifecycleEpochV2: accountLifecycleEpochV2,
    );
    return AuthIncarnationSessionAdvanceV2._(
      AuthIncarnationSessionGateV2._(
        nextState,
        issued,
        issued.sessionAttemptEpochV2,
      ),
      issued,
    );
  }

  AuthIncarnationSessionAdvanceV2 observeAuth({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) {
    if (state != AuthIncarnationSessionStateV2.signedOut) {
      throw StateError('Auth can be observed only from signed-out state.');
    }
    return _advance(
      nextState: AuthIncarnationSessionStateV2.establishing,
      attemptId: attemptId,
      scope: scope,
      accountGenerationV2: accountGenerationV2,
      accountLifecycleEpochV2: accountLifecycleEpochV2,
    );
  }

  AuthIncarnationSessionAdvanceV2 startAccountSwitch({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) => _advance(
    nextState: AuthIncarnationSessionStateV2.establishing,
    attemptId: attemptId,
    scope: scope,
    accountGenerationV2: accountGenerationV2,
    accountLifecycleEpochV2: accountLifecycleEpochV2,
  );

  AuthIncarnationSessionAdvanceV2 requireRefresh({required String attemptId}) {
    final currentAttempt = attempt;
    final mayRefresh =
        state == AuthIncarnationSessionStateV2.establishing ||
        state == AuthIncarnationSessionStateV2.refreshRequired ||
        state == AuthIncarnationSessionStateV2.ready;
    if (!mayRefresh || currentAttempt == null) {
      throw StateError('Auth refresh is unavailable in the current state.');
    }
    return _advance(
      nextState: AuthIncarnationSessionStateV2.refreshRequired,
      attemptId: attemptId,
      scope: currentAttempt.scope,
      accountGenerationV2: currentAttempt.accountGenerationV2,
      accountLifecycleEpochV2: currentAttempt.accountLifecycleEpochV2,
    );
  }

  bool get permitsProtectedListeners =>
      state == AuthIncarnationSessionStateV2.ready;

  bool get permitsCapabilities => permitsProtectedListeners;

  bool get permitsFcmRegistration => permitsProtectedListeners;

  AuthIncarnationSessionGateV2 transition(AuthIncarnationSessionEventV2 event) {
    if (event.kind == AuthIncarnationSessionEventKindV2.signedOut) {
      return AuthIncarnationSessionGateV2._(
        AuthIncarnationSessionStateV2.signedOut,
        null,
        sessionAttemptHighWaterV2,
      );
    }

    final currentAttempt = attempt;
    final eventAttempt = event.attempt;
    if (currentAttempt == null ||
        eventAttempt == null ||
        !currentAttempt.sameAttempt(eventAttempt)) {
      return this;
    }
    if (state == AuthIncarnationSessionStateV2.deleted) {
      return this;
    }
    if (state == AuthIncarnationSessionStateV2.deleting) {
      return event.kind == AuthIncarnationSessionEventKindV2.lifecycleDeleted
          ? AuthIncarnationSessionGateV2._(
              AuthIncarnationSessionStateV2.deleted,
              currentAttempt,
              sessionAttemptHighWaterV2,
            )
          : this;
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
      AuthIncarnationSessionEventKindV2.proofLost =>
        AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventKindV2.lifecycleDeleting =>
        AuthIncarnationSessionStateV2.deleting,
      AuthIncarnationSessionEventKindV2.lifecycleDeleted =>
        AuthIncarnationSessionStateV2.deleted,
      AuthIncarnationSessionEventKindV2.signedOut => state,
    };
    return AuthIncarnationSessionGateV2._(
      next,
      currentAttempt,
      sessionAttemptHighWaterV2,
    );
  }
}
