import 'package:cloud_firestore/cloud_firestore.dart';

class InviteCodeModel {
  final String code;
  final String? teamId;
  final String role;
  final int usesRemaining;
  final String status;
  final DateTime expiresAt;
  final String associationId;

  const InviteCodeModel({
    required this.code,
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
      code: doc.id,
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
    if (expiresAt == null) {
      throw const FormatException('Invite response is missing expiresAt');
    }
    return InviteCodeModel(
      code: data['code']?.toString() ?? '',
      teamId: data['teamId']?.toString(),
      role: data['role'] as String,
      usesRemaining: (data['usesRemaining'] as num?)?.toInt() ?? 1,
      status: data['status']?.toString() ?? 'active',
      expiresAt: expiresAt,
      associationId: data['associationId'] as String,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamId': teamId,
      'role': role,
      'usesRemaining': usesRemaining,
      'status': status,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'associationId': associationId,
    };
  }

  bool get isValid =>
      status == 'active' &&
      usesRemaining == 1 &&
      DateTime.now().isBefore(expiresAt);
}
