import 'package:cloud_firestore/cloud_firestore.dart';

class TeamModel {
  final String id;
  final String name;
  final String divisionId;
  final String seasonId;
  final String? logoUrl;
  final List<String> repIds;
  final String normalizedName;

  TeamModel({
    required this.id,
    required this.name,
    required this.divisionId,
    required this.seasonId,
    this.logoUrl,
    this.repIds = const [],
    String? normalizedName,
  }) : normalizedName = normalizedName ?? normalizeTeamName(name);

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
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'divisionId': divisionId,
      'seasonId': seasonId,
      'logoUrl': logoUrl,
      'repIds': repIds,
      'normalizedName': normalizedName,
    };
  }

  TeamModel copyWith({
    String? id,
    String? name,
    String? divisionId,
    String? seasonId,
    String? logoUrl,
    List<String>? repIds,
  }) {
    return TeamModel(
      id: id ?? this.id,
      name: name ?? this.name,
      divisionId: divisionId ?? this.divisionId,
      seasonId: seasonId ?? this.seasonId,
      logoUrl: logoUrl ?? this.logoUrl,
      repIds: repIds ?? this.repIds,
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
