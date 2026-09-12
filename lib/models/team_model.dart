import 'package:cloud_firestore/cloud_firestore.dart';

const Object _absentTeamLifecycleField = Object();

class TeamModel {
  final String id;
  final String name;
  final String divisionId;
  final String seasonId;
  final String? logoUrl;
  final List<String> repIds;
  final String normalizedName;
  final bool hasStatus;
  final Object? status;
  final bool hasLegacyActive;
  final Object? active;

  TeamModel({
    required this.id,
    required this.name,
    required this.divisionId,
    required this.seasonId,
    this.logoUrl,
    this.repIds = const [],
    String? normalizedName,
    Object? status = _absentTeamLifecycleField,
    Object? active = _absentTeamLifecycleField,
  }) : normalizedName = normalizedName ?? normalizeTeamName(name),
       hasStatus = !identical(status, _absentTeamLifecycleField),
       status = identical(status, _absentTeamLifecycleField) ? null : status,
       hasLegacyActive = !identical(active, _absentTeamLifecycleField),
       active = identical(active, _absentTeamLifecycleField) ? null : active;

  factory TeamModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TeamModel.fromMap(id: doc.id, data: doc.data()!);
  }

  factory TeamModel.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return TeamModel(
      id: id,
      name: data['name'] as String,
      divisionId: data['divisionId'] as String,
      seasonId: data['seasonId'] as String,
      logoUrl: data['logoUrl'] as String?,
      repIds: List<String>.from(data['repIds'] ?? []),
      normalizedName: data['normalizedName'] as String?,
      status: data.containsKey('status')
          ? data['status']
          : _absentTeamLifecycleField,
      active: data.containsKey('active')
          ? data['active']
          : _absentTeamLifecycleField,
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
      if (hasStatus) 'status': status,
      if (hasLegacyActive) 'active': active,
    };
  }

  /// Mirrors the server's legacy-compatible eligibility contract exactly.
  /// `status` passes only when absent or exactly `active`; the legacy flag
  /// independently rejects only the literal boolean `false`.
  bool get acceptsNewReferences =>
      (!hasStatus || (status is String && status == 'active')) &&
      (!hasLegacyActive || !identical(active, false));

  TeamModel copyWith({
    String? id,
    String? name,
    String? divisionId,
    String? seasonId,
    String? logoUrl,
    List<String>? repIds,
    Object? status = _absentTeamLifecycleField,
    Object? active = _absentTeamLifecycleField,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      divisionId: divisionId ?? this.divisionId,
      seasonId: seasonId ?? this.seasonId,
      logoUrl: logoUrl ?? this.logoUrl,
      repIds: repIds ?? this.repIds,
      status: identical(status, _absentTeamLifecycleField)
          ? hasStatus
                ? this.status
                : _absentTeamLifecycleField
          : status,
      active: identical(active, _absentTeamLifecycleField)
          ? hasLegacyActive
                ? this.active
                : _absentTeamLifecycleField
          : active,
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
