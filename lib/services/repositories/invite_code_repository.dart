import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/invite_code_model.dart';

class InviteCodeRepository {
  static const int authorizationSchemaVersion = 1;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<InviteCodeModel?> validateCode(String code) async {
    try {
      final result = await _functions
          .httpsCallable('inspectPrivilegedInvite')
          .call<Map<String, dynamic>>({
            'code': code,
            'authorizationSchemaVersion': authorizationSchemaVersion,
          });
      return InviteCodeModel.fromCallable(result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'invalid-argument') {
        return null;
      }
      rethrow;
    }
  }

  Future<void> redeemCode(String code, String displayName) async {
    await _functions.httpsCallable('redeemPrivilegedInvite').call<void>({
      'code': code,
      'displayName': displayName,
      'authorizationSchemaVersion': authorizationSchemaVersion,
    });
  }

  Future<InviteCodeModel> createCode({
    required String role,
    String? teamId,
    required int daysValid,
  }) async {
    final result = await _functions
        .httpsCallable('createPrivilegedInvite')
        .call<Map<String, dynamic>>({
          'role': role,
          'teamId': teamId,
          'daysValid': daysValid,
          'authorizationSchemaVersion': authorizationSchemaVersion,
        });
    return InviteCodeModel.fromCallable(result.data);
  }

  Future<List<InviteCodeModel>> getAllCodes(String associationId) async {
    final snap = await _db
        .collection(FirestorePaths.inviteCodes())
        .where('associationId', isEqualTo: associationId)
        .get();
    return snap.docs.map((doc) => InviteCodeModel.fromFirestore(doc)).toList();
  }

  Future<void> deleteCode(String code) async {
    await _functions.httpsCallable('revokePrivilegedInvite').call<void>({
      'code': code,
      'authorizationSchemaVersion': authorizationSchemaVersion,
    });
  }
}
