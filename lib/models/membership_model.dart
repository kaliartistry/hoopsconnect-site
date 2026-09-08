import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

class MembershipModel {
  static const authorizationSchemaVersion = 1;

  final String userId;
  final String associationId;
  final UserRole role;
  final Set<String> capabilities;
  final String status;
  final int schemaVersion;
  final String? teamId;
  final String? divisionId;

  const MembershipModel({
    required this.userId,
    required this.associationId,
    required this.role,
    required this.capabilities,
    required this.status,
    required this.schemaVersion,
    this.teamId,
    this.divisionId,
  });

  factory MembershipModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MembershipModel(
      userId: doc.id,
      associationId: data['associationId'] as String? ?? '',
      role: UserRole.values.byName(data['role'] as String? ?? 'fan'),
      capabilities: Set<String>.from(data['capabilities'] as List? ?? const []),
      status: data['status'] as String? ?? 'legacy',
      schemaVersion: data['authorizationSchemaVersion'] as int? ?? 0,
      teamId: data['teamId'] as String?,
      divisionId: data['divisionId'] as String?,
    );
  }

  bool get isActive =>
      status == 'active' &&
      schemaVersion == authorizationSchemaVersion &&
      associationId.isNotEmpty;

  bool matchesProfile(UserModel profile) =>
      isActive &&
      userId == profile.id &&
      associationId == profile.associationId;
}
