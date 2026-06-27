import 'package:cloud_firestore/cloud_firestore.dart';

class TeamStanding {
  final String teamId;
  final String teamName;
  final String? divisionId;
  final int wins;
  final int losses;
  final double pct;
  final double gb;
  final String streak;
  final String lastTen;
  final int pointsFor;
  final int pointsAgainst;

  const TeamStanding({
    required this.teamId,
    required this.teamName,
    this.divisionId,
    required this.wins,
    required this.losses,
    required this.pct,
    required this.gb,
    required this.streak,
    required this.lastTen,
    required this.pointsFor,
    required this.pointsAgainst,
  });

  factory TeamStanding.fromMap(Map<String, dynamic> map) {
    return TeamStanding(
      teamId: map['teamId'] as String,
      teamName: map['teamName'] as String,
      divisionId: map['divisionId'] as String?,
      wins: map['wins'] as int,
      losses: map['losses'] as int,
      pct: (map['pct'] as num).toDouble(),
      gb: (map['gb'] as num).toDouble(),
      streak: map['streak'] as String? ?? '-',
      lastTen: map['lastTen'] as String? ?? '-',
      pointsFor: map['pointsFor'] as int? ?? 0,
      pointsAgainst: map['pointsAgainst'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'teamId': teamId,
        'teamName': teamName,
        'divisionId': divisionId,
        'wins': wins,
        'losses': losses,
        'pct': pct,
        'gb': gb,
        'streak': streak,
        'lastTen': lastTen,
        'pointsFor': pointsFor,
        'pointsAgainst': pointsAgainst,
      };
}

class StandingsModel {
  final String id;
  final String seasonId;
  final String? divisionId;
  final DateTime updatedAt;
  final List<TeamStanding> standings;

  const StandingsModel({
    required this.id,
    required this.seasonId,
    this.divisionId,
    required this.updatedAt,
    this.standings = const [],
  });

  factory StandingsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final standingsRaw = data['standings'] as List<dynamic>? ?? [];

    return StandingsModel(
      id: doc.id,
      seasonId: data['seasonId'] as String,
      divisionId: data['divisionId'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      standings: standingsRaw
          .map((e) => TeamStanding.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'seasonId': seasonId,
      'divisionId': divisionId,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'standings': standings.map((e) => e.toMap()).toList(),
    };
  }
}
