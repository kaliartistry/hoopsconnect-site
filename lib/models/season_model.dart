import 'package:cloud_firestore/cloud_firestore.dart';

enum SeasonStatus { prepared, active, inactive, archived }

class SeasonModel {
  final String id;
  final String associationId;
  final String name;
  final String startDate;
  final String endDate;
  final SeasonStatus status;
  final int version;

  const SeasonModel({
    required this.id,
    required this.associationId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.version,
  });

  bool get isCurrent => status == SeasonStatus.active;
  bool get canActivate => status == SeasonStatus.prepared;
  bool get canArchive =>
      status != SeasonStatus.active && status != SeasonStatus.archived;
  bool get canRestore => status == SeasonStatus.archived;

  factory SeasonModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? _,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    String dateOnly(Object? value) {
      if (value is String && _dateOnlyPattern.hasMatch(value)) return value;
      if (value is Timestamp) {
        final date = value.toDate();
        return '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      }
      return '';
    }

    final rawStatus = data['status'];
    final legacyActive = data['isActive'] == true || data['active'] == true;
    final status = switch (rawStatus) {
      'prepared' => SeasonStatus.prepared,
      'active' => SeasonStatus.active,
      'inactive' => SeasonStatus.inactive,
      'archived' => SeasonStatus.archived,
      _ => legacyActive ? SeasonStatus.active : SeasonStatus.inactive,
    };
    return SeasonModel(
      id: snapshot.id,
      associationId: data['associationId'] is String
          ? data['associationId'] as String
          : snapshot.reference.parent.parent?.id ?? '',
      name: data['name'] is String ? data['name'] as String : snapshot.id,
      startDate: dateOnly(data['startDate']),
      endDate: dateOnly(data['endDate']),
      status: status,
      version: data['version'] is int ? data['version'] as int : 0,
    );
  }
}

final _dateOnlyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
