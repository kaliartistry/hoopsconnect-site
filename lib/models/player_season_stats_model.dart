import 'package:cloud_firestore/cloud_firestore.dart';

class GameLogEntry {
  final String eventId;
  final DateTime date;
  final String vs;
  final int pts;
  final int reb;
  final int ast;
  final int stl;
  final int blk;
  final String result; // "W" or "L"

  const GameLogEntry({
    required this.eventId,
    required this.date,
    required this.vs,
    required this.pts,
    required this.reb,
    required this.ast,
    required this.stl,
    required this.blk,
    required this.result,
  });

  factory GameLogEntry.fromMap(Map<String, dynamic> map) {
    return GameLogEntry(
      eventId: map['eventId'] as String,
      date: (map['date'] as Timestamp).toDate(),
      vs: map['vs'] as String,
      pts: map['pts'] as int? ?? 0,
      reb: map['reb'] as int? ?? 0,
      ast: map['ast'] as int? ?? 0,
      stl: map['stl'] as int? ?? 0,
      blk: map['blk'] as int? ?? 0,
      result: map['result'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'eventId': eventId,
    'date': Timestamp.fromDate(date),
    'vs': vs,
    'pts': pts,
    'reb': reb,
    'ast': ast,
    'stl': stl,
    'blk': blk,
    'result': result,
  };
}

class PlayerSeasonStatsModel {
  final String id; // playerId_seasonId
  final String playerId;
  final String playerName;
  final String teamId;
  final String? teamName;
  final String seasonId;
  final String? divisionId;
  final int gamesPlayed;
  final Map<String, int> totals;
  final Map<String, double> averages;
  final List<GameLogEntry> gameLog;
  final String? registrationId;
  final String? jerseyNumber;
  final String? position;
  final bool hasAggregateData;

  const PlayerSeasonStatsModel({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.teamId,
    this.teamName,
    required this.seasonId,
    this.divisionId,
    this.gamesPlayed = 0,
    this.totals = const {},
    this.averages = const {},
    this.gameLog = const [],
    this.registrationId,
    this.jerseyNumber,
    this.position,
    this.hasAggregateData = true,
  });

  factory PlayerSeasonStatsModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return PlayerSeasonStatsModel.fromMap(id: doc.id, data: doc.data()!);
  }

  factory PlayerSeasonStatsModel.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final logRaw = data['gameLog'] as List<dynamic>? ?? [];
    final jerseyRaw = data['jerseyNumber'] ?? data['jersey'];

    return PlayerSeasonStatsModel(
      id: id,
      playerId: data['playerId'] as String,
      playerName: data['playerName'] as String,
      teamId: data['teamId'] as String,
      teamName: data['teamName'] as String?,
      seasonId: data['seasonId'] as String,
      divisionId: data['divisionId'] as String?,
      gamesPlayed: data['gamesPlayed'] as int? ?? 0,
      totals: Map<String, int>.from(data['totals'] ?? {}),
      averages: (data['averages'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      gameLog: logRaw
          .map((e) => GameLogEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
      registrationId: data['registrationId'] as String?,
      jerseyNumber: jerseyRaw?.toString(),
      position: data['position'] as String?,
      hasAggregateData:
          data.containsKey('gamesPlayed') ||
          data.containsKey('totals') ||
          data.containsKey('averages') ||
          data.containsKey('gameLog'),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'playerId': playerId,
      'playerName': playerName,
      'teamId': teamId,
      'teamName': teamName,
      'seasonId': seasonId,
      'divisionId': divisionId,
      if (hasAggregateData) ...{
        'gamesPlayed': gamesPlayed,
        'totals': totals,
        'averages': averages,
        'gameLog': gameLog.map((e) => e.toMap()).toList(),
      },
      if (registrationId != null) 'registrationId': registrationId,
      if (jerseyNumber != null) 'jerseyNumber': jerseyNumber,
      if (position != null) 'position': position,
    };
  }

  double get ppg => averages['ppg'] ?? averages['pts'] ?? 0;
  double get rpg => averages['rpg'] ?? averages['reb'] ?? 0;
  double get apg => averages['apg'] ?? averages['ast'] ?? 0;
  double get spg => averages['spg'] ?? averages['stl'] ?? 0;
  double get bpg => averages['bpg'] ?? averages['blk'] ?? 0;
}
