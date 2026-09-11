import 'package:cloud_firestore/cloud_firestore.dart';

enum DivisionStatus { active, archived }

class DivisionModel {
  final String id;
  final String name;
  final String? seasonId;
  final String? description;
  final DivisionStatus status;
  final int version;

  const DivisionModel({
    required this.id,
    required this.name,
    this.seasonId,
    this.description,
    this.status = DivisionStatus.active,
    this.version = 0,
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
    final statusValue = data['status'];
    final status = switch (statusValue) {
      null => DivisionStatus.active,
      String value when DivisionStatus.values.asNameMap().containsKey(value) =>
        DivisionStatus.values.byName(value),
      _ => throw FormatException(
        'Division $id has an unsupported explicit status: $statusValue',
      ),
    };
    return DivisionModel(
      id: id,
      name: data['name'] as String,
      seasonId: data['seasonId'] as String?,
      description: data['description'] as String?,
      status: status,
      version: data['version'] is int ? data['version'] as int : 0,
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

class DivisionDeleteReference {
  final String kind;
  final String id;
  final String? displayName;

  const DivisionDeleteReference({
    required this.kind,
    required this.id,
    required this.displayName,
  });
}

class DivisionDeleteReceipt {
  final String operationId;
  final String status;
  final int divisionVersion;
  final List<DivisionDeleteReference> references;

  const DivisionDeleteReceipt({
    required this.operationId,
    required this.status,
    required this.divisionVersion,
    this.references = const [],
  });

  bool get deleted => status == 'deleted';

  factory DivisionDeleteReceipt.fromMap(Map<String, dynamic> map) {
    final operationId = map['operationId'];
    final status = map['status'];
    final version = map['divisionVersion'];
    final rawReferences = map['references'];
    if (operationId is! String ||
        status is! String ||
        !{'deleted', 'blocked'}.contains(status) ||
        version is! int ||
        version < 0 ||
        (rawReferences != null && rawReferences is! List)) {
      throw const FormatException('Invalid division deletion receipt');
    }
    return DivisionDeleteReceipt(
      operationId: operationId,
      status: status,
      divisionVersion: version,
      references: (rawReferences as List? ?? const [])
          .map((raw) {
            final value = Map<String, dynamic>.from(raw as Map);
            if (value['kind'] is! String || value['id'] is! String) {
              throw const FormatException('Invalid division reference');
            }
            return DivisionDeleteReference(
              kind: value['kind'] as String,
              id: value['id'] as String,
              displayName: value['displayName'] as String?,
            );
          })
          .toList(growable: false),
    );
  }
}
