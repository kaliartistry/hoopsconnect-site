import '../auth_incarnation/auth_incarnation_session_gate_v2.dart';

const bool accountLifecycleAd02ActivationAllowedV2 = false;
const int accountDirectorySchemaVersionV2 = 2;

enum AccountLifecycleRouteIntentV2 { ordinary, accountDeletion }

final class ActiveMemberDirectoryEntryV2 {
  final String uid;
  final String displayName;
  final String? teamId;
  final String? divisionId;

  const ActiveMemberDirectoryEntryV2._({
    required this.uid,
    required this.displayName,
    required this.teamId,
    required this.divisionId,
  });

  factory ActiveMemberDirectoryEntryV2.fromMap(Map<String, Object?> data) {
    const keys = {
      'accountDirectorySchemaVersionV2',
      'uid',
      'displayName',
      'teamId',
      'divisionId',
    };
    if (!_exactKeys(data, keys) ||
        data['accountDirectorySchemaVersionV2'] !=
            accountDirectorySchemaVersionV2 ||
        !_validIdentifier(data['uid']) ||
        data['displayName'] is! String ||
        (data['displayName']! as String).trim().isEmpty ||
        (data['displayName']! as String).length > 160 ||
        _controlPattern.hasMatch(data['displayName']! as String) ||
        !(data['teamId'] == null || _validIdentifier(data['teamId'])) ||
        !(data['divisionId'] == null || _validIdentifier(data['divisionId']))) {
      throw const FormatException('Invalid AD02 V2 directory entry.');
    }
    return ActiveMemberDirectoryEntryV2._(
      uid: data['uid']! as String,
      displayName: (data['displayName']! as String).trim(),
      teamId: data['teamId'] as String?,
      divisionId: data['divisionId'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'accountDirectorySchemaVersionV2': accountDirectorySchemaVersionV2,
    'uid': uid,
    'displayName': displayName,
    'teamId': teamId,
    'divisionId': divisionId,
  };
}

final class ActiveMemberDirectoryV2 {
  final List<ActiveMemberDirectoryEntryV2> users;
  final bool truncated;

  const ActiveMemberDirectoryV2._({
    required this.users,
    required this.truncated,
  });

  factory ActiveMemberDirectoryV2.fromMap(Map<String, Object?> data) {
    const keys = {'accountDirectorySchemaVersionV2', 'users', 'truncated'};
    final rawUsers = data['users'];
    if (!_exactKeys(data, keys) ||
        data['accountDirectorySchemaVersionV2'] !=
            accountDirectorySchemaVersionV2 ||
        rawUsers is! List ||
        rawUsers.length > 200 ||
        data['truncated'] is! bool) {
      throw const FormatException('Invalid AD02 V2 member directory.');
    }
    final parsed = rawUsers
        .map((value) {
          if (value is! Map || value.keys.any((key) => key is! String)) {
            throw const FormatException('Invalid AD02 V2 directory entry.');
          }
          return ActiveMemberDirectoryEntryV2.fromMap(
            value.map((key, entry) => MapEntry(key.toString(), entry)),
          );
        })
        .toList(growable: false);
    if (parsed.map((entry) => entry.uid).toSet().length != parsed.length) {
      throw const FormatException('Duplicate AD02 V2 directory member.');
    }
    return ActiveMemberDirectoryV2._(
      users: List.unmodifiable(parsed),
      truncated: data['truncated']! as bool,
    );
  }

  Map<String, Object?> toMap() => {
    'accountDirectorySchemaVersionV2': accountDirectorySchemaVersionV2,
    'users': users.map((entry) => entry.toMap()).toList(growable: false),
    'truncated': truncated,
  };
}

String candidateRouteForAccountLifecycleV2({
  required AuthIncarnationSessionStateV2 state,
  required String requestedLocation,
  AccountLifecycleRouteIntentV2 intent = AccountLifecycleRouteIntentV2.ordinary,
}) {
  if (requestedLocation == '/delete-account' ||
      intent == AccountLifecycleRouteIntentV2.accountDeletion ||
      state == AuthIncarnationSessionStateV2.deleting ||
      state == AuthIncarnationSessionStateV2.deleted) {
    return '/delete-account';
  }
  return switch (state) {
    AuthIncarnationSessionStateV2.signedOut => '/login',
    AuthIncarnationSessionStateV2.establishing ||
    AuthIncarnationSessionStateV2.refreshRequired => '/loading',
    AuthIncarnationSessionStateV2.ready => requestedLocation,
    AuthIncarnationSessionStateV2.blocked => '/access-blocked',
    AuthIncarnationSessionStateV2.deleting ||
    AuthIncarnationSessionStateV2.deleted => '/delete-account',
  };
}

bool _exactKeys(Map<String, Object?> data, Set<String> expected) =>
    data.keys.toSet().containsAll(expected) && expected.containsAll(data.keys);

final RegExp _identifierPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
final RegExp _controlPattern = RegExp(r'[\u0000-\u001f\u007f]');

bool _validIdentifier(Object? value) =>
    value is String && _identifierPattern.hasMatch(value);
