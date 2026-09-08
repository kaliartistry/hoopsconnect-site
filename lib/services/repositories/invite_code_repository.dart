import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
