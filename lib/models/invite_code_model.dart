import 'package:cloud_firestore/cloud_firestore.dart';

/// Persisted or inspected invite metadata. It deliberately cannot hold the
/// bearer credential.
class InviteCodeModel {
  final String inviteId;
  final String? teamId;
  final String role;
  final int usesRemaining;
  final String status;
  final DateTime expiresAt;
  final String associationId;

  const InviteCodeModel({
    required this.inviteId,
    required this.teamId,
    required this.role,
    required this.usesRemaining,
    required this.status,
    required this.expiresAt,
    required this.associationId,
  });

  factory InviteCodeModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return InviteCodeModel(
      inviteId: doc.id,
      teamId: data['teamId']?.toString(),
      role: data['role'] as String,
      usesRemaining: data['usesRemaining'] as int,
      status: data['status']?.toString() ?? 'legacy',
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      associationId: data['associationId'] as String,
    );
  }

  factory InviteCodeModel.fromCallable(Map<Object?, Object?> data) {
    final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    final inviteId = data['inviteId']?.toString();
    if (expiresAt == null || inviteId == null || inviteId.isEmpty) {
      throw const FormatException('Invite response is missing metadata');
    }
    return InviteCodeModel(
      inviteId: inviteId,
      teamId: data['teamId']?.toString(),
      role: data['role'] as String,
      usesRemaining: (data['usesRemaining'] as num?)?.toInt() ?? 1,
      status: data['status']?.toString() ?? 'active',
      expiresAt: expiresAt,
      associationId: data['associationId'] as String,
    );
  }

  String get displayId => inviteId.length > 11
      ? '${inviteId.substring(0, 7)}...${inviteId.substring(inviteId.length - 4)}'
      : inviteId;

  bool get isValid =>
      status == 'active' &&
      usesRemaining == 1 &&
      DateTime.now().isBefore(expiresAt);
}

/// One-time issuer response. This object is never created from Firestore.
class IssuedInviteCode {
  final InviteCodeModel invite;
  final String code;

  const IssuedInviteCode({required this.invite, required this.code});

  factory IssuedInviteCode.fromCallable(Map<Object?, Object?> data) {
    final code = data['code']?.toString();
    if (code == null || code.isEmpty) {
      throw const FormatException('Invite issuance response is missing code');
    }
    return IssuedInviteCode(
      invite: InviteCodeModel.fromCallable(data),
      code: code,
    );
  }
}
