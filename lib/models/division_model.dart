import 'package:cloud_firestore/cloud_firestore.dart';

enum DivisionStatus { active, archived }

class DivisionModel {
  final String id;
  final String name;
  final String? seasonId;
  final String? description;
  final DivisionStatus status;

  const DivisionModel({
    required this.id,
    required this.name,
    this.seasonId,
    this.description,
    this.status = DivisionStatus.active,
  });

  factory DivisionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return DivisionModel.fromMap(id: doc.id, data: doc.data()!);
  }

  factory DivisionModel.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return DivisionModel(
      id: id,
      name: data['name'] as String,
      seasonId: data['seasonId'] as String?,
      description: data['description'] as String?,
      status:
          DivisionStatus.values.asNameMap()[data['status']] ??
          DivisionStatus.active,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'seasonId': seasonId,
      'description': description,
      'status': status.name,
    };
  }

  bool get isArchived => status == DivisionStatus.archived;
}
