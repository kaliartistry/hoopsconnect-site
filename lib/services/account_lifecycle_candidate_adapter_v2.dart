import 'dart:async';

import '../models/auth_incarnation/auth_incarnation_session_gate_v2.dart';
import '../models/auth_incarnation/auth_incarnation_v2.dart';

typedef CandidateListenerDisposerV2 = void Function();
typedef CandidateListenerStartV2 = CandidateListenerDisposerV2 Function();

final class CandidateFcmOwnerV2 {
  final AuthIncarnationSessionAttemptV2 attempt;
  final String token;

  const CandidateFcmOwnerV2({required this.attempt, required this.token});
}

final class CandidateDetachResultV2 {
  final bool ownerBindingRemoved;
  final bool installationTokenRotated;

  const CandidateDetachResultV2({
    required this.ownerBindingRemoved,
    required this.installationTokenRotated,
  });

  bool get permitsAuthChange => ownerBindingRemoved || installationTokenRotated;
}

/// Fake-adapter integration of the actual Auth Incarnation V2 gate.
///
/// This class is deliberately absent from production providers and roots. It
/// proves the ordering contract a future activation packet must preserve.
final class AccountLifecycleCandidateClientAdapterV2 {
  AuthIncarnationSessionGateV2 _gate =
      const AuthIncarnationSessionGateV2.signedOut();
  final Set<CandidateListenerDisposerV2> _listenerDisposers = {};
  Future<void> _tokenMutationTail = Future<void>.value();
  CandidateFcmOwnerV2? _fcmOwner;
  bool _authChangeLatch = false;

  AuthIncarnationSessionGateV2 get gate => _authChangeLatch
      ? _gate.transition(const AuthIncarnationSessionEventV2.signedOut())
      : _gate;
  CandidateFcmOwnerV2? get fcmOwner => _fcmOwner;
  int get protectedListenerCount => _listenerDisposers.length;
  bool get permitsProtectedListeners =>
      !_authChangeLatch && _gate.permitsProtectedListeners;
  bool get permitsCapabilities =>
      !_authChangeLatch && _gate.permitsCapabilities;
  bool get permitsFcmRegistration =>
      !_authChangeLatch && _gate.permitsFcmRegistration;

  AuthIncarnationSessionAttemptV2 observeAuth({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) {
    _ensureAuthTransitionAvailable();
    _retireProtectedConsumers();
    final advance = _gate.observeAuth(
      attemptId: attemptId,
      scope: scope,
      accountGenerationV2: accountGenerationV2,
      accountLifecycleEpochV2: accountLifecycleEpochV2,
    );
    _gate = advance.gate;
    return advance.attempt;
  }

  AuthIncarnationSessionAttemptV2 startAccountSwitch({
    required String attemptId,
    required AuthIncarnationScopeV2 scope,
    required String accountGenerationV2,
    required int accountLifecycleEpochV2,
  }) {
    _ensureAuthTransitionAvailable();
    _retireProtectedConsumers();
    final advance = _gate.startAccountSwitch(
      attemptId: attemptId,
      scope: scope,
      accountGenerationV2: accountGenerationV2,
      accountLifecycleEpochV2: accountLifecycleEpochV2,
    );
    _gate = advance.gate;
    return advance.attempt;
  }

  AuthIncarnationSessionAttemptV2 requireRefresh({required String attemptId}) {
    _ensureAuthTransitionAvailable();
    _retireProtectedConsumers();
    final advance = _gate.requireRefresh(attemptId: attemptId);
    _gate = advance.gate;
    return advance.attempt;
  }

  void acceptProof({
    required AuthIncarnationSessionAttemptV2 attempt,
    required ValidatedActiveAuthorityV2 binding,
  }) {
    if (_authChangeLatch) return;
    _gate = _gate.transition(
      AuthIncarnationSessionEventV2.proofReady(
        attempt: attempt,
        binding: binding,
      ),
    );
    if (_gate.state != AuthIncarnationSessionStateV2.ready) {
      _retireProtectedConsumers();
    }
  }

  void loseProof(AuthIncarnationSessionAttemptV2 attempt) {
    final previous = _gate;
    final next = _gate.transition(
      AuthIncarnationSessionEventV2.proofLost(attempt),
    );
    _gate = next;
    if (!identical(previous, next)) _retireProtectedConsumers();
  }

  void markDeleting(AuthIncarnationSessionAttemptV2 attempt) {
    final previous = _gate;
    final next = _gate.transition(
      AuthIncarnationSessionEventV2.lifecycleDeleting(attempt),
    );
    _gate = next;
    if (!identical(previous, next)) _retireProtectedConsumers();
  }

  void markDeleted(AuthIncarnationSessionAttemptV2 attempt) {
    final previous = _gate;
    final next = _gate.transition(
      AuthIncarnationSessionEventV2.lifecycleDeleted(attempt),
    );
    _gate = next;
    if (!identical(previous, next)) _retireProtectedConsumers();
  }

  bool attachProtectedListener({
    required AuthIncarnationSessionAttemptV2 attempt,
    required CandidateListenerStartV2 start,
  }) {
    if (!_currentReadyAttempt(attempt)) return false;
    final disposer = start();
    if (!_currentReadyAttempt(attempt)) {
      disposer();
      return false;
    }
    _listenerDisposers.add(disposer);
    return true;
  }

  Future<bool> registerFcmToken({
    required AuthIncarnationSessionAttemptV2 attempt,
    required String token,
    required Future<void> Function() writeRegistration,
    required Future<void> Function() removeStaleRegistration,
  }) {
    return _serializeTokenMutation(() async {
      if (token.isEmpty || !_currentReadyAttempt(attempt)) return false;
      await writeRegistration();
      if (!_currentReadyAttempt(attempt)) {
        await removeStaleRegistration();
        return false;
      }
      _fcmOwner = CandidateFcmOwnerV2(attempt: attempt, token: token);
      return true;
    });
  }

  /// Closes every grant before detachment starts. Auth change may proceed when
  /// either the owner binding is removed or the installation token is rotated.
  /// If both controls fail, the previous gate is restored and Auth is untouched.
  Future<CandidateDetachResultV2> detachAndSignOut({
    required Future<void> Function() removeOwnerBinding,
    required Future<void> Function() rotateInstallationToken,
    required Future<void> Function() signOut,
    required Future<void> Function() restoreRegistration,
  }) {
    return _serializeTokenMutation(() async {
      _ensureAuthTransitionAvailable();
      final previousGate = _gate;
      final previousOwner = _fcmOwner;
      _authChangeLatch = true;
      _retireProtectedConsumers();

      var removed = false;
      var rotated = false;
      Object? removeError;
      StackTrace? removeStack;
      Object? rotateError;
      StackTrace? rotateStack;
      try {
        await removeOwnerBinding();
        removed = true;
      } catch (error, stack) {
        removeError = error;
        removeStack = stack;
      }
      try {
        await rotateInstallationToken();
        rotated = true;
      } catch (error, stack) {
        rotateError = error;
        rotateStack = stack;
      }

      final detach = CandidateDetachResultV2(
        ownerBindingRemoved: removed,
        installationTokenRotated: rotated,
      );
      if (!detach.permitsAuthChange) {
        if (identical(_gate, previousGate)) {
          _fcmOwner = previousOwner;
        }
        _authChangeLatch = false;
        if (removeError != null) {
          Error.throwWithStackTrace(removeError, removeStack!);
        }
        Error.throwWithStackTrace(rotateError!, rotateStack!);
      }

      try {
        await signOut();
        _gate = _gate.transition(
          const AuthIncarnationSessionEventV2.signedOut(),
        );
        _fcmOwner = null;
        _authChangeLatch = false;
        return detach;
      } catch (error, stack) {
        var registrationRestored = false;
        if (identical(_gate, previousGate)) {
          try {
            await restoreRegistration();
            registrationRestored = true;
          } catch (_) {
            // The original Auth transition error is the actionable failure.
          }
        }
        _fcmOwner = registrationRestored ? previousOwner : null;
        _authChangeLatch =
            identical(_gate, previousGate) && !registrationRestored;
        Error.throwWithStackTrace(error, stack);
      }
    });
  }

  bool _currentReadyAttempt(AuthIncarnationSessionAttemptV2 attempt) {
    final current = _gate.attempt;
    return !_authChangeLatch &&
        _gate.state == AuthIncarnationSessionStateV2.ready &&
        current != null &&
        current.sameAttempt(attempt);
  }

  void _ensureAuthTransitionAvailable() {
    if (_authChangeLatch) {
      throw StateError('Auth change is already in progress.');
    }
  }

  void _retireProtectedConsumers() {
    final disposers = [..._listenerDisposers];
    _listenerDisposers.clear();
    _fcmOwner = null;
    for (final dispose in disposers) {
      try {
        dispose();
      } catch (_) {
        // A faulty consumer cannot keep the authorization gate open or prevent
        // the remaining protected consumers from being retired.
      }
    }
  }

  Future<T> _serializeTokenMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tokenMutationTail = _tokenMutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
