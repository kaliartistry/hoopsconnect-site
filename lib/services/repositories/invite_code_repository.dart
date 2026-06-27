import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/invite_code_model.dart';

class InviteCodeRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<InviteCodeModel?> validateCode(String code) async {
    final snap = await _db
        .doc(FirestorePaths.inviteCode(code.toUpperCase()))
        .get();
    if (!snap.exists) return null;

    final model = InviteCodeModel.fromFirestore(snap);
    if (!model.isValid) return null;

    return model;
  }

  Future<void> consumeCode(String code) {
    return _db.doc(FirestorePaths.inviteCode(code.toUpperCase())).update({
      'usesRemaining': FieldValue.increment(-1),
    });
  }

  Future<void> createCode(InviteCodeModel code) {
    return _db
        .doc(FirestorePaths.inviteCode(code.code))
        .set(code.toFirestore());
  }

  Future<List<InviteCodeModel>> getAllCodes() async {
    final snap = await _db.collection(FirestorePaths.inviteCodes()).get();
    return snap.docs
        .map((doc) => InviteCodeModel.fromFirestore(doc))
        .toList();
  }

  Future<void> deleteCode(String code) {
    return _db.doc(FirestorePaths.inviteCode(code)).delete();
  }
}
