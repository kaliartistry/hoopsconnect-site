import 'package:cloud_firestore/cloud_firestore.dart';

class TeamStatTotals {
  final int pts;
  final int oreb;
  final int dreb;
  final int reb;
  final int ast;
  final int stl;
  final int blk;
  final int to;
  final int fls;
  final int min;

  const TeamStatTotals({
    this.pts = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.reb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.to = 0,
    this.fls = 0,
    this.min = 0,
  });

  factory TeamStatTotals.fromMap(Map<String, dynamic> map) {
    return TeamStatTotals(
      pts: map['pts'] as int? ?? 0,
      oreb: map['oreb'] as int? ?? 0,
      dreb: map['dreb'] as int? ?? 0,
      reb: map['reb'] as int? ?? 0,
      ast: map['ast'] as int? ?? 0,
      stl: map['stl'] as int? ?? 0,
      blk: map['blk'] as int? ?? 0,
      to: map['to'] as int? ?? 0,
      fls: map['fls'] as int? ?? 0,
      min: map['min'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'pts': pts,
        'oreb': oreb,
        'dreb': dreb,
        'reb': reb,
        'ast': ast,
        'stl': stl,
        'blk': blk,
        'to': to,
        'fls': fls,
        'min': min,
      };

  TeamStatTotals copyWith({
    int? pts,
    int? oreb,
    int? dreb,
    int? reb,
    int? ast,
    int? stl,
    int? blk,
    int? to,
    int? fls,
    int? min,
  }) {
    return TeamStatTotals(
      pts: pts ?? this.pts,
      oreb: oreb ?? this.oreb,
      dreb: dreb ?? this.dreb,
      reb: reb ?? this.reb,
      ast: ast ?? this.ast,
      stl: stl ?? this.stl,
      blk: blk ?? this.blk,
      to: to ?? this.to,
      fls: fls ?? this.fls,
      min: min ?? this.min,
    );
  }
}

class TeamStatAverages {
  final double ppg;
  final double rpg;
  final double apg;
  final double spg;
  final double bpg;
  final double topg;
  final double fpg;

  const TeamStatAverages({
    this.ppg = 0,
    this.rpg = 0,
    this.apg = 0,
    this.spg = 0,
    this.bpg = 0,
    this.topg = 0,
    this.fpg = 0,
  });

  factory TeamStatAverages.fromMap(Map<String, dynamic> map) {
    return TeamStatAverages(
      ppg: (map['ppg'] as num?)?.toDouble() ?? 0,
      rpg: (map['rpg'] as num?)?.toDouble() ?? 0,
      apg: (map['apg'] as num?)?.toDouble() ?? 0,
      spg: (map['spg'] as num?)?.toDouble() ?? 0,
      bpg: (map['bpg'] as num?)?.toDouble() ?? 0,
      topg: (map['topg'] as num?)?.toDouble() ?? 0,
      fpg: (map['fpg'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'ppg': ppg,
        'rpg': rpg,
        'apg': apg,
        'spg': spg,
        'bpg': bpg,
        'topg': topg,
        'fpg': fpg,
      };

  TeamStatAverages copyWith({
    double? ppg,
    double? rpg,
    double? apg,
    double? spg,
    double? bpg,
    double? topg,
    double? fpg,
  }) {
    return TeamStatAverages(
      ppg: ppg ?? this.ppg,
      rpg: rpg ?? this.rpg,
      apg: apg ?? this.apg,
      spg: spg ?? this.spg,
      bpg: bpg ?? this.bpg,
      topg: topg ?? this.topg,
      fpg: fpg ?? this.fpg,
    );
  }
}

class TeamGameLog {
  final String eventId;
  final String opponentName;
  final String? opponentTeamId;
  final DateTime date;
  final int pts;
  final int oreb;
  final int dreb;
  final int reb;
  final int ast;
  final int stl;
  final int blk;
  final int to;
  final int fls;
  final String result; // "W" or "L"

  const TeamGameLog({
    required this.eventId,
    required this.opponentName,
    this.opponentTeamId,
    required this.date,
    this.pts = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.reb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.to = 0,
    this.fls = 0,
    required this.result,
  });

  factory TeamGameLog.fromMap(Map<String, dynamic> map) {
    return TeamGameLog(
      eventId: map['eventId'] as String,
      opponentName: map['opponentName'] as String,
      opponentTeamId: map['opponentTeamId'] as String?,
      date: (map['date'] as Timestamp).toDate(),
      pts: map['pts'] as int? ?? 0,
      oreb: map['oreb'] as int? ?? 0,
      dreb: map['dreb'] as int? ?? 0,
      reb: map['reb'] as int? ?? 0,
      ast: map['ast'] as int? ?? 0,
      stl: map['stl'] as int? ?? 0,
      blk: map['blk'] as int? ?? 0,
      to: map['to'] as int? ?? 0,
      fls: map['fls'] as int? ?? 0,
      result: map['result'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'eventId': eventId,
        'opponentName': opponentName,
        if (opponentTeamId != null) 'opponentTeamId': opponentTeamId,
        'date': Timestamp.fromDate(date),
        'pts': pts,
        'oreb': oreb,
        'dreb': dreb,
        'reb': reb,
        'ast': ast,
        'stl': stl,
        'blk': blk,
        'to': to,
        'fls': fls,
        'result': result,
      };

  TeamGameLog copyWith({
    String? eventId,
    String? opponentName,
    String? opponentTeamId,
    DateTime? date,
    int? pts,
    int? oreb,
    int? dreb,
    int? reb,
    int? ast,
    int? stl,
    int? blk,
    int? to,
    int? fls,
    String? result,
  }) {
    return TeamGameLog(
      eventId: eventId ?? this.eventId,
      opponentName: opponentName ?? this.opponentName,
      opponentTeamId: opponentTeamId ?? this.opponentTeamId,
      date: date ?? this.date,
      pts: pts ?? this.pts,
      oreb: oreb ?? this.oreb,
      dreb: dreb ?? this.dreb,
      reb: reb ?? this.reb,
      ast: ast ?? this.ast,
      stl: stl ?? this.stl,
      blk: blk ?? this.blk,
      to: to ?? this.to,
      fls: fls ?? this.fls,
      result: result ?? this.result,
    );
  }
}

class TeamSeasonStats {
  final String id; // teamId_seasonId
  final String teamId;
  final String teamName;
  final String seasonId;
  final String? divisionId;
  final int gamesPlayed;
  final TeamStatTotals totals;
  final TeamStatAverages averages;
  final List<TeamGameLog> gameLog;

  const TeamSeasonStats({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.seasonId,
    this.divisionId,
    this.gamesPlayed = 0,
    this.totals = const TeamStatTotals(),
    this.averages = const TeamStatAverages(),
    this.gameLog = const [],
  });

  factory TeamSeasonStats.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final logRaw = data['gameLog'] as List<dynamic>? ?? [];

    return TeamSeasonStats(
      id: doc.id,
      teamId: data['teamId'] as String,
      teamName: data['teamName'] as String,
      seasonId: data['seasonId'] as String,
      divisionId: data['divisionId'] as String?,
      gamesPlayed: data['gamesPlayed'] as int? ?? 0,
      totals: TeamStatTotals.fromMap(
          data['totals'] as Map<String, dynamic>? ?? {}),
      averages: TeamStatAverages.fromMap(
          data['averages'] as Map<String, dynamic>? ?? {}),
      gameLog: logRaw
          .map((e) => TeamGameLog.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamId': teamId,
      'teamName': teamName,
      'seasonId': seasonId,
      'divisionId': divisionId,
      'gamesPlayed': gamesPlayed,
      'totals': totals.toMap(),
      'averages': averages.toMap(),
      'gameLog': gameLog.map((e) => e.toMap()).toList(),
    };
  }

  TeamSeasonStats copyWith({
    String? id,
    String? teamId,
    String? teamName,
    String? seasonId,
    String? divisionId,
    int? gamesPlayed,
    TeamStatTotals? totals,
    TeamStatAverages? averages,
    List<TeamGameLog>? gameLog,
  }) {
    return TeamSeasonStats(
      id: id ?? this.id,
      teamId: teamId ?? this.teamId,
      teamName: teamName ?? this.teamName,
      seasonId: seasonId ?? this.seasonId,
      divisionId: divisionId ?? this.divisionId,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      totals: totals ?? this.totals,
      averages: averages ?? this.averages,
      gameLog: gameLog ?? this.gameLog,
    );
  }
}
