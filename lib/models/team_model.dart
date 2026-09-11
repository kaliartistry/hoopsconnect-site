import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  static const supportedStatuses = {'active', 'inactive', 'archived'};

  final String id;
  final String name;
  final String divisionId;
  final String seasonId;
  final String? logoUrl;
  final List<String> repIds;
  final String normalizedName;
  final String? status;
  final bool? active;

  TeamModel({
    required this.id,
    required this.name,
    required this.divisionId,
    required this.seasonId,
    this.logoUrl,
    this.repIds = const [],
    String? normalizedName,
    this.status,
    this.active,
  }) : normalizedName = normalizedName ?? normalizeTeamName(name);

  factory TeamModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TeamModel.fromMap(id: doc.id, data: doc.data()!);
  }

  factory TeamModel.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final statusValue = data['status'];
    final activeValue = data['active'];
    if (statusValue != null &&
        (statusValue is! String || !supportedStatuses.contains(statusValue))) {
      throw FormatException(
        'Team $id has an unsupported explicit status: $statusValue',
      );
    }
    if (activeValue != null && activeValue is! bool) {
      throw FormatException(
        'Team $id has an invalid legacy active flag: $activeValue',
      );
    }
    return TeamModel(
      id: id,
      name: data['name'] as String,
      divisionId: data['divisionId'] as String,
      seasonId: data['seasonId'] as String,
      logoUrl: data['logoUrl'] as String?,
      repIds: List<String>.from(data['repIds'] ?? []),
      normalizedName: data['normalizedName'] as String?,
      status: statusValue as String?,
      active: activeValue as bool?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'name': name,
      'divisionId': divisionId,
      'seasonId': seasonId,
      'logoUrl': logoUrl,
      'repIds': repIds,
      'normalizedName': normalizedName,
      if (status != null) 'status': status,
      if (active != null) 'active': active,
    };
  }

  /// Mirrors the server's legacy-compatible eligibility contract exactly.
  /// An explicit non-active status always wins over the older boolean flag.
  bool get acceptsNewReferences =>
      (status == null || status == 'active') && active != false;

  TeamModel copyWith({
    String? id,
    String? name,
    String? divisionId,
    String? seasonId,
    String? logoUrl,
    List<String>? repIds,
    String? status,
    bool? active,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      divisionId: divisionId ?? this.divisionId,
      seasonId: seasonId ?? this.seasonId,
      logoUrl: logoUrl ?? this.logoUrl,
      repIds: repIds ?? this.repIds,
      status: status ?? this.status,
      active: active ?? this.active,
    );
  }
}

String normalizeTeamName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<TeamModel> teamNameConflicts({
  required Iterable<TeamModel> teams,
  required String candidateName,
  required String seasonId,
  String? excludingTeamId,
}) {
  final normalized = normalizeTeamName(candidateName);
  return teams
      .where(
        (team) =>
            team.id != excludingTeamId &&
            team.seasonId == seasonId &&
            team.normalizedName == normalized,
      )
      .toList(growable: false);
}

List<TeamModel> teamsEligibleForSchedule({
  required Iterable<TeamModel> teams,
  required String seasonId,
  required String divisionId,
}) => teams
    .where((team) => team.seasonId == seasonId && team.divisionId == divisionId)
    .toList(growable: false);
