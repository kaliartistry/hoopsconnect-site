import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/invite_code_model.dart';

typedef InviteCallable =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, dynamic> data,
    );

enum InviteFailureDisposition { ambiguous, terminal }

InviteFailureDisposition inviteFailureDisposition(Object error) {
  if (error is FirebaseFunctionsException) {
    const ambiguousCodes = {
      'aborted',
      'cancelled',
      'data-loss',
      'deadline-exceeded',
      'internal',
      'resource-exhausted',
      'unavailable',
      'unknown',
    };
    if (ambiguousCodes.contains(error.code)) {
      return InviteFailureDisposition.ambiguous;
    }
  }
  if (error is FirebaseAuthException) {
    const ambiguousCodes = {
      'network-request-failed',
      'too-many-requests',
      'web-context-cancelled',
    };
    if (ambiguousCodes.contains(error.code)) {
      return InviteFailureDisposition.ambiguous;
    }
  }
  if (error is TimeoutException) {
    return InviteFailureDisposition.ambiguous;
  }
  return InviteFailureDisposition.terminal;
}

bool shouldDeletePendingAuthIdentity({
  required bool ownsPendingIdentity,
  required Object error,
}) =>
    ownsPendingIdentity &&
    inviteFailureDisposition(error) == InviteFailureDisposition.terminal;

String newInviteOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// One logical invite-creation request.
///
/// Keep this object after an ambiguous transport failure and submit it again.
/// The fixed operation ID lets the server return the original result instead
/// of issuing a second invite. Create a new attempt only after a terminal
/// rejection, before any request was accepted, or for intentionally different
/// request parameters.
class InviteCreationAttempt {
  final String role;
  final String? teamId;
  final int daysValid;
  final String operationId;

  const InviteCreationAttempt({
    required this.role,
    required this.teamId,
    required this.daysValid,
    required this.operationId,
  });

  Future<IssuedInviteCode> submit(InviteCodeRepository repository) {
    return repository.createCode(
      role: role,
      teamId: teamId,
      daysValid: daysValid,
      operationId: operationId,
    );
  }

  Map<String, Object?> toJson({
    required String actorId,
    required String associationId,
  }) => {
    'schemaVersion': 1,
    'actorId': actorId,
    'associationId': associationId,
    'role': role,
    'teamId': teamId,
    'daysValid': daysValid,
    'operationId': operationId,
  };

  static InviteCreationAttempt? fromJson(
    Object? value, {
    required String actorId,
    required String associationId,
  }) {
    if (value is! Map<Object?, Object?> ||
        value['schemaVersion'] != 1 ||
        value['actorId'] != actorId ||
        value['associationId'] != associationId) {
      return null;
    }
    final role = value['role'];
    final teamId = value['teamId'];
    final daysValid = value['daysValid'];
    final operationId = value['operationId'];
    final hasValidRepTeam =
        role != 'rep' || (teamId is String && teamId.isNotEmpty);
    final hasValidTeamId =
        teamId == null ||
        (teamId is String &&
            RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(teamId));
    final hasValidOperationId =
        operationId is String &&
        RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(operationId);
    if (role is! String ||
        !const {'rep', 'media', 'statistician'}.contains(role) ||
        (teamId != null && teamId is! String) ||
        daysValid is! int ||
        daysValid < 1 ||
        daysValid > 30 ||
        !hasValidTeamId ||
        !hasValidOperationId ||
        !hasValidRepTeam) {
      return null;
    }
    return InviteCreationAttempt(
      role: role,
      teamId: teamId as String?,
      daysValid: daysValid,
      operationId: operationId,
    );
  }
}

/// Stores only the logical request and idempotency ID, never the invite bearer.
abstract class InviteCreationAttemptStore {
  Future<InviteCreationAttempt?> load({
    required String actorId,
    required String associationId,
  });

  Future<void> save({
    required String actorId,
    required String associationId,
    required InviteCreationAttempt attempt,
  });

  Future<void> clear({required String actorId, required String associationId});
}

class SharedPreferencesInviteCreationAttemptStore
    implements InviteCreationAttemptStore {
  static const _keyPrefix = 'invite_creation_attempt_v1';

  String _key(String actorId, String associationId) {
    final scope = base64Url.encode(utf8.encode('$actorId\u0000$associationId'));
    return '$_keyPrefix:$scope';
  }

  @override
  Future<InviteCreationAttempt?> load({
    required String actorId,
    required String associationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(actorId, associationId);
    final encoded = preferences.getString(key);
    if (encoded == null) return null;
    try {
      final attempt = InviteCreationAttempt.fromJson(
        jsonDecode(encoded),
        actorId: actorId,
        associationId: associationId,
      );
      if (attempt != null) return attempt;
    } on FormatException {
      // Invalid local recovery data is discarded and never sent to the server.
    }
    await preferences.remove(key);
    return null;
  }

  @override
  Future<void> save({
    required String actorId,
    required String associationId,
    required InviteCreationAttempt attempt,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key(actorId, associationId),
      jsonEncode(
        attempt.toJson(actorId: actorId, associationId: associationId),
      ),
    );
    if (!saved) {
      throw StateError('The invite recovery request could not be saved.');
    }
  }

  @override
  Future<void> clear({
    required String actorId,
    required String associationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final cleared = await preferences.remove(_key(actorId, associationId));
    if (!cleared && preferences.containsKey(_key(actorId, associationId))) {
      throw StateError('The invite recovery request could not be cleared.');
    }
  }
}

class InviteCodeRepository {
  static const int authorizationSchemaVersion = 1;
  final FirebaseFirestore? _db;
  final FirebaseFunctions? _functions;
  final InviteCallable? _callable;

  InviteCodeRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    InviteCallable? callable,
  }) : _db = firestore,
       _functions = functions,
       _callable = callable;

  Future<Map<Object?, Object?>> _invoke(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (_callable != null) return _callable(name, data);
    final result = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(data);
    return result.data;
  }

  Future<InviteCodeModel?> validateCode(String code) async {
    try {
      final data = await _invoke('inspectPrivilegedInvite', {
        'code': code,
        'authorizationSchemaVersion': authorizationSchemaVersion,
      });
      return InviteCodeModel.fromCallable(data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'invalid-argument') {
        return null;
      }
      rethrow;
    }
  }

  Future<void> redeemCode({
    required String code,
    required String displayName,
    required String operationId,
  }) async {
    await _invoke('redeemPrivilegedInvite', {
      'code': code,
      'displayName': displayName,
      'operationId': operationId,
      'authorizationSchemaVersion': authorizationSchemaVersion,
    });
  }

  Future<IssuedInviteCode> createCode({
    required String role,
    String? teamId,
    required int daysValid,
    required String operationId,
  }) async {
    final data = await _invoke('createPrivilegedInvite', {
      'role': role,
      'teamId': teamId,
      'daysValid': daysValid,
      'operationId': operationId,
      'authorizationSchemaVersion': authorizationSchemaVersion,
    });
    return IssuedInviteCode.fromCallable(data);
  }

  Future<List<InviteCodeModel>> getAllCodes(String associationId) async {
    final snap = await (_db ?? FirebaseFirestore.instance)
        .collection(FirestorePaths.inviteCodes())
        .where('associationId', isEqualTo: associationId)
        .where('credentialVersion', isEqualTo: 2)
        .get();
    return snap.docs.map(InviteCodeModel.fromFirestore).toList();
  }

  Future<void> revokeCode(String inviteId) async {
    await _invoke('revokePrivilegedInvite', {
      'inviteId': inviteId,
      'authorizationSchemaVersion': authorizationSchemaVersion,
    });
  }
}
