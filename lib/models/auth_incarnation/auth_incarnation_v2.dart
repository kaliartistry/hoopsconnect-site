import 'dart:collection';

abstract final class AuthIncarnationV2 {
  static const int schemaVersion = 2;
  static const String generationClaim = 'accountGenerationV2';
  static const String lifecycleEpochClaim = 'accountLifecycleEpochV2';
  static const int maxSafeInteger = 9007199254740991;
  static const Set<String> capabilities = {
    'association.read',
    'association.manage',
    'members.read',
    'members.manage',
    'invites.manage',
    'schedule.manage',
    'teams.manage',
    'teams.represent',
    'posts.create',
    'posts.manage',
    'posts.internal.read',
    'posts.acknowledge',
    'stats.enter',
    'stats.approve',
    'stats.export',
    'press.read',
    'players.manage',
    'players.private.read',
    'rosters.assert',
    'rosters.manage',
    'games.schedule',
    'stats.submit',
    'stats.review',
    'stats.correct',
    'stats.certify',
    'results.publish',
    'results.retract',
    'official.override',
  };
  static final RegExp generationPattern = RegExp(r'^[a-f0-9]{64}$');
}

enum AccountLifecycleStateV2 { pending, active, deleting, deleted }

enum MembershipStatusV2 { active, suspended, revoked }

enum AuthIncarnationDenialCodeV2 {
  missingTokenProof,
  invalidTokenProof,
  invalidLifecycle,
  lifecycleInactive,
  invalidMembership,
  membershipInactive,
  invalidProjection,
  scopeMismatch,
  generationMismatch,
  epochMismatch,
  reauthenticationRequired,
  capabilityDenied,
}

Never _invalid(String label) =>
    throw FormatException('Invalid Auth incarnation V2 $label.');

bool _exactKeys(Map<String, Object?> data, Set<String> keys) =>
    data.keys.toSet().containsAll(keys) && keys.containsAll(data.keys);

String _identifier(Object? value, String label) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    _invalid(label);
  }
  return value;
}

String? _tenant(Object? value) =>
    value == null ? null : _identifier(value, 'tenant ID');

int _counter(Object? value, String label) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > AuthIncarnationV2.maxSafeInteger ||
      value.truncateToDouble() != value.toDouble()) {
    _invalid(label);
  }
  return value.toInt();
}

String _generation(Object? value) {
  if (value is! String ||
      !AuthIncarnationV2.generationPattern.hasMatch(value)) {
    _invalid('generation');
  }
  return value;
}

void _schema(Object? value) {
  if (value != AuthIncarnationV2.schemaVersion) _invalid('schema version');
}

List<String> _capabilities(Object? value) {
  if (value is! List || value.length > 64) _invalid('capabilities');
  final result = <String>[];
  for (final entry in value) {
    final parsed = _identifier(entry, 'capability');
    if (!AuthIncarnationV2.capabilities.contains(parsed)) {
      _invalid('capability');
    }
    result.add(parsed);
  }
  if (result.toSet().length != result.length) _invalid('capabilities');
  return List.unmodifiable(result);
}

class AuthIncarnationScopeV2 {
  static const keys = {'authProjectIdV2', 'authTenantIdV2', 'authUidV2'};

  final String authProjectIdV2;
  final String? authTenantIdV2;
  final String authUidV2;

  const AuthIncarnationScopeV2({
    required this.authProjectIdV2,
    required this.authTenantIdV2,
    required this.authUidV2,
  });

  factory AuthIncarnationScopeV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('scope keys');
    return AuthIncarnationScopeV2._fromFields(data);
  }

  factory AuthIncarnationScopeV2._fromFields(Map<String, Object?> data) =>
      AuthIncarnationScopeV2(
        authProjectIdV2: _identifier(data['authProjectIdV2'], 'project ID'),
        authTenantIdV2: _tenant(data['authTenantIdV2']),
        authUidV2: _identifier(data['authUidV2'], 'UID'),
      );

  Map<String, Object?> toMap() => {
    'authProjectIdV2': authProjectIdV2,
    'authTenantIdV2': authTenantIdV2,
    'authUidV2': authUidV2,
  };

  bool sameAs(AuthIncarnationScopeV2 other) =>
      authProjectIdV2 == other.authProjectIdV2 &&
      authTenantIdV2 == other.authTenantIdV2 &&
      authUidV2 == other.authUidV2;
}

class AuthIncarnationTokenProofV2 {
  static const keys = {
    'authIncarnationSchemaVersionV2',
    ...AuthIncarnationScopeV2.keys,
    'accountGenerationV2',
    'accountLifecycleEpochV2',
    'authTimeSec',
  };

  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final int authTimeSec;

  const AuthIncarnationTokenProofV2({
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.authTimeSec,
  });

  factory AuthIncarnationTokenProofV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('token proof keys');
    _schema(data['authIncarnationSchemaVersionV2']);
    return AuthIncarnationTokenProofV2(
      scope: AuthIncarnationScopeV2._fromFields(data),
      accountGenerationV2: _generation(data['accountGenerationV2']),
      accountLifecycleEpochV2: _counter(
        data['accountLifecycleEpochV2'],
        'lifecycle epoch',
      ),
      authTimeSec: _counter(data['authTimeSec'], 'authentication time'),
    );
  }

  Map<String, Object?> toMap() => {
    'authIncarnationSchemaVersionV2': AuthIncarnationV2.schemaVersion,
    ...scope.toMap(),
    'accountGenerationV2': accountGenerationV2,
    'accountLifecycleEpochV2': accountLifecycleEpochV2,
    'authTimeSec': authTimeSec,
  };
}

class AccountLifecycleAuthorityV2 {
  static const keys = {
    'authIncarnationSchemaVersionV2',
    ...AuthIncarnationScopeV2.keys,
    'accountGenerationV2',
    'accountLifecycleEpochV2',
    'lifecycleStateV2',
    'reauthAfterSecV2',
  };

  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final AccountLifecycleStateV2 lifecycleStateV2;
  final int reauthAfterSecV2;

  const AccountLifecycleAuthorityV2({
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.lifecycleStateV2,
    required this.reauthAfterSecV2,
  });

  factory AccountLifecycleAuthorityV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('lifecycle keys');
    _schema(data['authIncarnationSchemaVersionV2']);
    final state = switch (data['lifecycleStateV2']) {
      'pending' => AccountLifecycleStateV2.pending,
      'active' => AccountLifecycleStateV2.active,
      'deleting' => AccountLifecycleStateV2.deleting,
      'deleted' => AccountLifecycleStateV2.deleted,
      _ => _invalid('lifecycle state'),
    };
    return AccountLifecycleAuthorityV2(
      scope: AuthIncarnationScopeV2._fromFields(data),
      accountGenerationV2: _generation(data['accountGenerationV2']),
      accountLifecycleEpochV2: _counter(
        data['accountLifecycleEpochV2'],
        'lifecycle epoch',
      ),
      lifecycleStateV2: state,
      reauthAfterSecV2: _counter(
        data['reauthAfterSecV2'],
        'reauthentication boundary',
      ),
    );
  }
}

class MembershipAuthorityV2 {
  static const keys = {
    'authIncarnationSchemaVersionV2',
    ...AuthIncarnationScopeV2.keys,
    'accountGenerationV2',
    'accountLifecycleEpochV2',
    'membershipStatusV2',
    'associationId',
    'capabilities',
  };

  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final MembershipStatusV2 membershipStatusV2;
  final String associationId;
  final List<String> capabilities;

  const MembershipAuthorityV2({
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.membershipStatusV2,
    required this.associationId,
    required this.capabilities,
  });

  factory MembershipAuthorityV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('membership keys');
    _schema(data['authIncarnationSchemaVersionV2']);
    final status = switch (data['membershipStatusV2']) {
      'active' => MembershipStatusV2.active,
      'suspended' => MembershipStatusV2.suspended,
      'revoked' => MembershipStatusV2.revoked,
      _ => _invalid('membership status'),
    };
    return MembershipAuthorityV2(
      scope: AuthIncarnationScopeV2._fromFields(data),
      accountGenerationV2: _generation(data['accountGenerationV2']),
      accountLifecycleEpochV2: _counter(
        data['accountLifecycleEpochV2'],
        'lifecycle epoch',
      ),
      membershipStatusV2: status,
      associationId: _identifier(data['associationId'], 'association ID'),
      capabilities: _capabilities(data['capabilities']),
    );
  }
}

class PendingAuthIncarnationBindingV2 {
  static const keys = {
    'authIncarnationSchemaVersionV2',
    ...AuthIncarnationScopeV2.keys,
    'accountGenerationV2',
    'accountLifecycleEpochV2',
    'bindingStateV2',
    'reauthAfterSecV2',
  };

  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final int reauthAfterSecV2;

  const PendingAuthIncarnationBindingV2({
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.reauthAfterSecV2,
  });

  factory PendingAuthIncarnationBindingV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('pending binding keys');
    _schema(data['authIncarnationSchemaVersionV2']);
    if (data['bindingStateV2'] != 'pending') {
      _invalid('pending binding state');
    }
    return PendingAuthIncarnationBindingV2(
      scope: AuthIncarnationScopeV2._fromFields(data),
      accountGenerationV2: _generation(data['accountGenerationV2']),
      accountLifecycleEpochV2: _counter(
        data['accountLifecycleEpochV2'],
        'lifecycle epoch',
      ),
      reauthAfterSecV2: _counter(
        data['reauthAfterSecV2'],
        'reauthentication boundary',
      ),
    );
  }

  Map<String, Object?> toMap() => {
    'authIncarnationSchemaVersionV2': AuthIncarnationV2.schemaVersion,
    ...scope.toMap(),
    'accountGenerationV2': accountGenerationV2,
    'accountLifecycleEpochV2': accountLifecycleEpochV2,
    'bindingStateV2': 'pending',
    'reauthAfterSecV2': reauthAfterSecV2,
  };
}

class StorageAuthorizationProjectionV2 {
  static const keys = {
    'authIncarnationSchemaVersionV2',
    ...AuthIncarnationScopeV2.keys,
    'accountGenerationV2',
    'accountLifecycleEpochV2',
    'lifecycleStateV2',
    'membershipStatusV2',
    'reauthAfterSecV2',
    'associationId',
    'capabilities',
  };

  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final AccountLifecycleStateV2 lifecycleStateV2;
  final MembershipStatusV2 membershipStatusV2;
  final int reauthAfterSecV2;
  final String associationId;
  final List<String> capabilities;

  const StorageAuthorizationProjectionV2({
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.lifecycleStateV2,
    required this.membershipStatusV2,
    required this.reauthAfterSecV2,
    required this.associationId,
    required this.capabilities,
  });

  factory StorageAuthorizationProjectionV2.fromMap(Map<String, Object?> data) {
    if (!_exactKeys(data, keys)) _invalid('Storage projection keys');
    _schema(data['authIncarnationSchemaVersionV2']);
    final lifecycle = AccountLifecycleAuthorityV2.fromMap({
      for (final key in AccountLifecycleAuthorityV2.keys) key: data[key],
    });
    final membership = MembershipAuthorityV2.fromMap({
      for (final key in MembershipAuthorityV2.keys) key: data[key],
    });
    return StorageAuthorizationProjectionV2(
      scope: lifecycle.scope,
      accountGenerationV2: lifecycle.accountGenerationV2,
      accountLifecycleEpochV2: lifecycle.accountLifecycleEpochV2,
      lifecycleStateV2: lifecycle.lifecycleStateV2,
      membershipStatusV2: membership.membershipStatusV2,
      reauthAfterSecV2: lifecycle.reauthAfterSecV2,
      associationId: membership.associationId,
      capabilities: membership.capabilities,
    );
  }

  factory StorageAuthorizationProjectionV2.fromValidated(
    ValidatedActiveAuthorityV2 binding,
  ) => StorageAuthorizationProjectionV2(
    scope: binding.scope,
    accountGenerationV2: binding.accountGenerationV2,
    accountLifecycleEpochV2: binding.accountLifecycleEpochV2,
    lifecycleStateV2: AccountLifecycleStateV2.active,
    membershipStatusV2: MembershipStatusV2.active,
    reauthAfterSecV2: binding.reauthAfterSecV2,
    associationId: binding.associationId,
    capabilities: List.unmodifiable(binding.capabilities),
  );

  Map<String, Object?> toMap() => {
    'authIncarnationSchemaVersionV2': AuthIncarnationV2.schemaVersion,
    ...scope.toMap(),
    'accountGenerationV2': accountGenerationV2,
    'accountLifecycleEpochV2': accountLifecycleEpochV2,
    'lifecycleStateV2': lifecycleStateV2.name,
    'membershipStatusV2': membershipStatusV2.name,
    'reauthAfterSecV2': reauthAfterSecV2,
    'associationId': associationId,
    'capabilities': capabilities,
  };
}

final class ValidatedActiveAuthorityV2 {
  final String sessionAttemptIdV2;
  final int sessionAttemptEpochV2;
  final Object sessionAttemptNonceV2;
  final AuthIncarnationScopeV2 scope;
  final String accountGenerationV2;
  final int accountLifecycleEpochV2;
  final int reauthAfterSecV2;
  final String associationId;
  final List<String> capabilities;

  ValidatedActiveAuthorityV2._({
    required this.sessionAttemptIdV2,
    required this.sessionAttemptEpochV2,
    required this.sessionAttemptNonceV2,
    required this.scope,
    required this.accountGenerationV2,
    required this.accountLifecycleEpochV2,
    required this.reauthAfterSecV2,
    required this.associationId,
    required List<String> capabilities,
  }) : capabilities = UnmodifiableListView(capabilities);
}

final class AuthIncarnationAuthorizationDecisionV2 {
  final bool authorized;
  final AuthIncarnationDenialCodeV2? code;
  final ValidatedActiveAuthorityV2? binding;

  const AuthIncarnationAuthorizationDecisionV2._({
    required this.authorized,
    this.code,
    this.binding,
  });

  const AuthIncarnationAuthorizationDecisionV2.denied(
    AuthIncarnationDenialCodeV2 denial,
  ) : this._(authorized: false, code: denial);

  AuthIncarnationAuthorizationDecisionV2._allowed(
    ValidatedActiveAuthorityV2 authority,
  ) : this._(authorized: true, binding: authority);
}

AuthIncarnationAuthorizationDecisionV2 evaluateAccountAuthorizationV2({
  required String sessionAttemptIdV2,
  required Object? sessionAttemptEpochV2,
  required Object sessionAttemptNonceV2,
  required Object? expectedScope,
  required Object? tokenProof,
  required Object? lifecycle,
  required Object? membership,
  required String requiredCapability,
}) {
  late String parsedSessionAttemptIdV2;
  late int parsedSessionAttemptEpochV2;
  try {
    parsedSessionAttemptIdV2 = _identifier(
      sessionAttemptIdV2,
      'session attempt ID',
    );
    parsedSessionAttemptEpochV2 = _counter(
      sessionAttemptEpochV2,
      'session attempt epoch',
    );
    if (parsedSessionAttemptEpochV2 == 0) {
      _invalid('session attempt epoch');
    }
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidTokenProof,
    );
  }
  AuthIncarnationScopeV2 scope;
  try {
    scope = AuthIncarnationScopeV2.fromMap(
      Map<String, Object?>.from(expectedScope! as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.scopeMismatch,
    );
  }
  if (tokenProof == null) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.missingTokenProof,
    );
  }
  AuthIncarnationTokenProofV2 token;
  AccountLifecycleAuthorityV2 parsedLifecycle;
  MembershipAuthorityV2 parsedMembership;
  try {
    token = AuthIncarnationTokenProofV2.fromMap(
      Map<String, Object?>.from(tokenProof as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidTokenProof,
    );
  }
  try {
    parsedLifecycle = AccountLifecycleAuthorityV2.fromMap(
      Map<String, Object?>.from(lifecycle! as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidLifecycle,
    );
  }
  if (parsedLifecycle.lifecycleStateV2 != AccountLifecycleStateV2.active) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.lifecycleInactive,
    );
  }
  try {
    parsedMembership = MembershipAuthorityV2.fromMap(
      Map<String, Object?>.from(membership! as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidMembership,
    );
  }
  if (parsedMembership.membershipStatusV2 != MembershipStatusV2.active) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.membershipInactive,
    );
  }
  if (!token.scope.sameAs(scope) ||
      !parsedLifecycle.scope.sameAs(scope) ||
      !parsedMembership.scope.sameAs(scope)) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.scopeMismatch,
    );
  }
  if (token.accountGenerationV2 != parsedLifecycle.accountGenerationV2 ||
      token.accountGenerationV2 != parsedMembership.accountGenerationV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.generationMismatch,
    );
  }
  if (token.accountLifecycleEpochV2 !=
          parsedLifecycle.accountLifecycleEpochV2 ||
      token.accountLifecycleEpochV2 !=
          parsedMembership.accountLifecycleEpochV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.epochMismatch,
    );
  }
  if (token.authTimeSec <= parsedLifecycle.reauthAfterSecV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.reauthenticationRequired,
    );
  }
  if (!parsedMembership.capabilities.contains(requiredCapability)) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.capabilityDenied,
    );
  }
  return AuthIncarnationAuthorizationDecisionV2._allowed(
    ValidatedActiveAuthorityV2._(
      sessionAttemptIdV2: parsedSessionAttemptIdV2,
      sessionAttemptEpochV2: parsedSessionAttemptEpochV2,
      sessionAttemptNonceV2: sessionAttemptNonceV2,
      scope: scope,
      accountGenerationV2: token.accountGenerationV2,
      accountLifecycleEpochV2: token.accountLifecycleEpochV2,
      reauthAfterSecV2: parsedLifecycle.reauthAfterSecV2,
      associationId: parsedMembership.associationId,
      capabilities: parsedMembership.capabilities,
    ),
  );
}

AuthIncarnationAuthorizationDecisionV2 evaluateStorageAuthorizationV2({
  required String sessionAttemptIdV2,
  required Object? sessionAttemptEpochV2,
  required Object sessionAttemptNonceV2,
  required Object? expectedScope,
  required Object? tokenProof,
  required Object? projection,
  required String requiredCapability,
}) {
  late String parsedSessionAttemptIdV2;
  late int parsedSessionAttemptEpochV2;
  try {
    parsedSessionAttemptIdV2 = _identifier(
      sessionAttemptIdV2,
      'session attempt ID',
    );
    parsedSessionAttemptEpochV2 = _counter(
      sessionAttemptEpochV2,
      'session attempt epoch',
    );
    if (parsedSessionAttemptEpochV2 == 0) {
      _invalid('session attempt epoch');
    }
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidTokenProof,
    );
  }
  AuthIncarnationScopeV2 scope;
  try {
    scope = AuthIncarnationScopeV2.fromMap(
      Map<String, Object?>.from(expectedScope! as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.scopeMismatch,
    );
  }
  if (tokenProof == null) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.missingTokenProof,
    );
  }
  AuthIncarnationTokenProofV2 token;
  StorageAuthorizationProjectionV2 parsedProjection;
  try {
    token = AuthIncarnationTokenProofV2.fromMap(
      Map<String, Object?>.from(tokenProof as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidTokenProof,
    );
  }
  try {
    parsedProjection = StorageAuthorizationProjectionV2.fromMap(
      Map<String, Object?>.from(projection! as Map),
    );
  } catch (_) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.invalidProjection,
    );
  }
  if (parsedProjection.lifecycleStateV2 != AccountLifecycleStateV2.active) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.lifecycleInactive,
    );
  }
  if (parsedProjection.membershipStatusV2 != MembershipStatusV2.active) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.membershipInactive,
    );
  }
  if (!token.scope.sameAs(scope) || !parsedProjection.scope.sameAs(scope)) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.scopeMismatch,
    );
  }
  if (token.accountGenerationV2 != parsedProjection.accountGenerationV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.generationMismatch,
    );
  }
  if (token.accountLifecycleEpochV2 !=
      parsedProjection.accountLifecycleEpochV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.epochMismatch,
    );
  }
  if (token.authTimeSec <= parsedProjection.reauthAfterSecV2) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.reauthenticationRequired,
    );
  }
  if (!parsedProjection.capabilities.contains(requiredCapability)) {
    return const AuthIncarnationAuthorizationDecisionV2.denied(
      AuthIncarnationDenialCodeV2.capabilityDenied,
    );
  }
  return AuthIncarnationAuthorizationDecisionV2._allowed(
    ValidatedActiveAuthorityV2._(
      sessionAttemptIdV2: parsedSessionAttemptIdV2,
      sessionAttemptEpochV2: parsedSessionAttemptEpochV2,
      sessionAttemptNonceV2: sessionAttemptNonceV2,
      scope: scope,
      accountGenerationV2: token.accountGenerationV2,
      accountLifecycleEpochV2: token.accountLifecycleEpochV2,
      reauthAfterSecV2: parsedProjection.reauthAfterSecV2,
      associationId: parsedProjection.associationId,
      capabilities: parsedProjection.capabilities,
    ),
  );
}
