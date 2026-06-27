import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String name;
  final String divisionId;
  final String seasonId;
  final String? logoUrl;
  final List<String> repIds;

  const TeamModel({
    required this.id,
    required this.name,
    required this.divisionId,
    required this.seasonId,
    this.logoUrl,
    this.repIds = const [],
  });

  factory TeamModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TeamModel(
      id: doc.id,
      name: data['name'] as String,
      divisionId: data['divisionId'] as String,
      seasonId: data['seasonId'] as String,
      logoUrl: data['logoUrl'] as String?,
      repIds: List<String>.from(data['repIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'divisionId': divisionId,
      'seasonId': seasonId,
      'logoUrl': logoUrl,
      'repIds': repIds,
    };
  }
}
