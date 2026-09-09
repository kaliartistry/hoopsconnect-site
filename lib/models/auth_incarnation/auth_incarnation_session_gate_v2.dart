enum AuthIncarnationSessionStateV2 {
  signedOut,
  establishing,
  refreshRequired,
  ready,
  blocked,
  deleting,
  deleted,
}

enum AuthIncarnationSessionEventV2 {
  authObserved,
  proofReady,
  refreshRequired,
  proofLost,
  lifecycleDeleting,
  lifecycleDeleted,
  accountSwitchStarted,
  signedOut,
}

class AuthIncarnationSessionGateV2 {
  final AuthIncarnationSessionStateV2 state;

  const AuthIncarnationSessionGateV2._(this.state);

  const AuthIncarnationSessionGateV2.signedOut()
    : this._(AuthIncarnationSessionStateV2.signedOut);

  bool get permitsProtectedListeners =>
      state == AuthIncarnationSessionStateV2.ready;

  bool get permitsCapabilities => permitsProtectedListeners;

  bool get permitsFcmRegistration => permitsProtectedListeners;

  AuthIncarnationSessionGateV2 transition(AuthIncarnationSessionEventV2 event) {
    final next = switch (event) {
      AuthIncarnationSessionEventV2.signedOut =>
        AuthIncarnationSessionStateV2.signedOut,
      AuthIncarnationSessionEventV2.accountSwitchStarted =>
        AuthIncarnationSessionStateV2.establishing,
      AuthIncarnationSessionEventV2.authObserved =>
        state == AuthIncarnationSessionStateV2.signedOut
            ? AuthIncarnationSessionStateV2.establishing
            : state,
      AuthIncarnationSessionEventV2.proofReady =>
        state == AuthIncarnationSessionStateV2.establishing ||
                state == AuthIncarnationSessionStateV2.refreshRequired
            ? AuthIncarnationSessionStateV2.ready
            : AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventV2.refreshRequired =>
        state == AuthIncarnationSessionStateV2.establishing
            ? AuthIncarnationSessionStateV2.refreshRequired
            : AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventV2.proofLost =>
        AuthIncarnationSessionStateV2.blocked,
      AuthIncarnationSessionEventV2.lifecycleDeleting =>
        AuthIncarnationSessionStateV2.deleting,
      AuthIncarnationSessionEventV2.lifecycleDeleted =>
        AuthIncarnationSessionStateV2.deleted,
    };
    return AuthIncarnationSessionGateV2._(next);
  }
}
