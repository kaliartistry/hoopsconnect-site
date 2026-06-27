import 'package:cloud_firestore/cloud_firestore.dart';

class DivisionModel {
  final String id;
  final String name;
  final String? seasonId;
  final String? description;

  const DivisionModel({
    required this.id,
    required this.name,
    this.seasonId,
    this.description,
  });

  factory DivisionModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DivisionModel(
      id: doc.id,
      name: data['name'] as String,
      seasonId: data['seasonId'] as String?,
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'seasonId': seasonId,
      'description': description,
    };
  }
}
