import 'package:cloud_firestore/cloud_firestore.dart';

class InviteCodeModel {
  final String code;
  final String teamId;
  final String role; // 'rep' or 'media'
  final int usesRemaining;
  final DateTime expiresAt;
  final String associationId;

  const InviteCodeModel({
    required this.code,
    required this.teamId,
    required this.role,
    required this.usesRemaining,
    required this.expiresAt,
    required this.associationId,
  });

  factory InviteCodeModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return InviteCodeModel(
      code: doc.id,
      teamId: data['teamId']?.toString() ?? '',
      role: data['role']?.toString() ?? 'media',
      usesRemaining: data['usesRemaining'] as int,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      associationId: data['associationId']?.toString() ?? 'jba',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamId': teamId,
      'role': role,
      'usesRemaining': usesRemaining,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'associationId': associationId,
    };
  }

  bool get isValid =>
      usesRemaining > 0 && DateTime.now().isBefore(expiresAt);
}
