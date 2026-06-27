import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardEntry {
  final String playerId;
  final String name;
  final String teamName;
  final double value;
  final int gp;

  const LeaderboardEntry({
    required this.playerId,
    required this.name,
    required this.teamName,
    required this.value,
    required this.gp,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return LeaderboardEntry(
      playerId: map['playerId'] as String,
      name: map['name'] as String,
      teamName: map['teamName'] as String,
      value: (map['value'] as num).toDouble(),
      gp: map['gp'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'name': name,
        'teamName': teamName,
        'value': value,
        'gp': gp,
      };
}

class LeaderboardModel {
  final String id; // seasonId_divisionId_category
  final String seasonId;
  final String? divisionId;
  final String category; // ppg, rpg, apg, spg, bpg
  final DateTime updatedAt;
  final List<LeaderboardEntry> rankings;

  const LeaderboardModel({
    required this.id,
    required this.seasonId,
    this.divisionId,
    required this.category,
    required this.updatedAt,
    this.rankings = const [],
  });

  factory LeaderboardModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rankingsRaw = data['rankings'] as List<dynamic>? ?? [];

    return LeaderboardModel(
      id: doc.id,
      seasonId: data['seasonId'] as String,
      divisionId: data['divisionId'] as String?,
      category: data['category'] as String,
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      rankings: rankingsRaw
          .map((e) => LeaderboardEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'seasonId': seasonId,
      'divisionId': divisionId,
      'category': category,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'rankings': rankings.map((e) => e.toMap()).toList(),
    };
  }
}
