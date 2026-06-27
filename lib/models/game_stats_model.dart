import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerStatLine {
  final String name;
  final String teamId;
  final int pts;
  final int oreb;
  final int dreb;
  final int ast;
  final int stl;
  final int blk;
  final int fls;
  final int min;

  /// Total rebounds (oreb + dreb).
  int get reb => oreb + dreb;

  const PlayerStatLine({
    required this.name,
    required this.teamId,
    this.pts = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.fls = 0,
    this.min = 0,
  });

  factory PlayerStatLine.fromMap(Map<String, dynamic> map) {
    return PlayerStatLine(
      name: map['name'] as String,
      teamId: map['teamId'] as String,
      pts: map['pts'] as int? ?? 0,
      oreb: map['oreb'] as int? ?? 0,
      dreb: map['dreb'] as int? ?? 0,
      ast: map['ast'] as int? ?? 0,
      stl: map['stl'] as int? ?? 0,
      blk: map['blk'] as int? ?? 0,
      fls: map['fls'] as int? ?? 0,
      min: map['min'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'teamId': teamId,
    'pts': pts,
    'oreb': oreb,
    'dreb': dreb,
    'reb': reb,
    'ast': ast,
    'stl': stl,
    'blk': blk,
    'fls': fls,
    'min': min,
  };

  PlayerStatLine copyWith({
    String? name,
    String? teamId,
    int? pts,
    int? oreb,
    int? dreb,
    int? ast,
    int? stl,
    int? blk,
    int? fls,
    int? min,
  }) {
    return PlayerStatLine(
      name: name ?? this.name,
      teamId: teamId ?? this.teamId,
      pts: pts ?? this.pts,
      oreb: oreb ?? this.oreb,
      dreb: dreb ?? this.dreb,
      ast: ast ?? this.ast,
      stl: stl ?? this.stl,
      blk: blk ?? this.blk,
      fls: fls ?? this.fls,
      min: min ?? this.min,
    );
  }
}

enum GameStatsStatus { notStarted, inProgress, submitted, approved, rejected }

extension GameStatsStatusX on GameStatsStatus {
  /// Editable by statistician (not yet submitted, or sent back).
  bool get isEditable =>
      this == GameStatsStatus.notStarted ||
      this == GameStatsStatus.inProgress ||
      this == GameStatsStatus.rejected;

  /// Locked — no further edits allowed except by admin re-open.
  bool get isLocked => this == GameStatsStatus.approved;

  /// Awaiting admin action.
  bool get awaitingApproval => this == GameStatsStatus.submitted;
}

/// Parse a status from a stored Firestore string. Maps the legacy `draft`
/// value (pre-v1 schema) onto `inProgress` so existing docs continue to load.
GameStatsStatus _statusFromString(String raw) {
  switch (raw) {
    case 'draft':
      return GameStatsStatus.inProgress;
    default:
      return GameStatsStatus.values.byName(raw);
  }
}

enum GameStatsEntryMode { live, postGame }

class GameStatsModel {
  final String id; // same as eventId
  final String eventId;
  final String seasonId;
  final String divisionId;
  final String homeTeamId;
  final String awayTeamId;
  final String homeTeamName;
  final String awayTeamName;
  final int homeScore;
  final int awayScore;
  final GameStatsStatus status;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  /// Note from admin shown to the statistician when stats are sent back.
  /// Cleared on resubmission.
  final String? rejectionNote;
  final GameStatsEntryMode? entryMode;
  final Map<String, PlayerStatLine> playerLines;

  /// Per-quarter team scores, e.g. {1: 25, 2: 18, 3: 22, 4: 20}.
  final Map<int, int> homeQuarterScores;
  final Map<int, int> awayQuarterScores;

  /// Optional per-quarter player stats.
  /// playerId -> quarter -> {'pts': 8, 'reb': 3, 'ast': 2, ...}
  final Map<String, Map<int, Map<String, int>>>? playerQuarterStats;

  const GameStatsModel({
    required this.id,
    required this.eventId,
    required this.seasonId,
    required this.divisionId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.homeTeamName,
    required this.awayTeamName,
    this.homeScore = 0,
    this.awayScore = 0,
    this.status = GameStatsStatus.notStarted,
    this.submittedBy,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectionNote,
    this.entryMode,
    this.playerLines = const {},
    this.homeQuarterScores = const {},
    this.awayQuarterScores = const {},
    this.playerQuarterStats,
  });

  factory GameStatsModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final linesRaw = data['playerLines'] as Map<String, dynamic>? ?? {};

    return GameStatsModel(
      id: doc.id,
      eventId: data['eventId'] as String,
      seasonId: data['seasonId'] as String,
      divisionId: data['divisionId'] as String,
      homeTeamId: data['homeTeamId'] as String,
      awayTeamId: data['awayTeamId'] as String,
      homeTeamName: data['homeTeamName'] as String,
      awayTeamName: data['awayTeamName'] as String,
      homeScore: data['homeScore'] as int? ?? 0,
      awayScore: data['awayScore'] as int? ?? 0,
      status: _statusFromString(data['status'] as String),
      submittedBy: data['submittedBy'] as String?,
      submittedAt: data['submittedAt'] != null
          ? (data['submittedAt'] as Timestamp).toDate()
          : null,
      approvedBy: data['approvedBy'] as String?,
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      rejectedBy: data['rejectedBy'] as String?,
      rejectedAt: data['rejectedAt'] != null
          ? (data['rejectedAt'] as Timestamp).toDate()
          : null,
      rejectionNote: data['rejectionNote'] as String?,
      entryMode: data['entryMode'] != null
          ? GameStatsEntryMode.values.byName(data['entryMode'] as String)
          : null,
      playerLines: linesRaw.map(
        (k, v) =>
            MapEntry(k, PlayerStatLine.fromMap(v as Map<String, dynamic>)),
      ),
      homeQuarterScores: _parseQuarterScores(data['homeQuarterScores']),
      awayQuarterScores: _parseQuarterScores(data['awayQuarterScores']),
      playerQuarterStats: _parsePlayerQuarterStats(data['playerQuarterStats']),
    );
  }

  /// Parse quarter scores from Firestore (string keys) to `Map<int, int>`.
  static Map<int, int> _parseQuarterScores(dynamic raw) {
    if (raw == null || raw is! Map) return const {};
    return (raw as Map<String, dynamic>).map(
      (k, v) => MapEntry(int.parse(k), (v as num).toInt()),
    );
  }

  /// Parse player quarter stats from Firestore.
  /// Firestore shape: { playerId: { "1": { "pts": 8, ... }, ... }, ... }
  static Map<String, Map<int, Map<String, int>>>? _parsePlayerQuarterStats(
    dynamic raw,
  ) {
    if (raw == null || raw is! Map) return null;
    final outerMap = raw as Map<String, dynamic>;
    return outerMap.map((playerId, quarters) {
      final qMap = (quarters as Map<String, dynamic>).map((qStr, stats) {
        final statMap = (stats as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
        return MapEntry(int.parse(qStr), statMap);
      });
      return MapEntry(playerId, qMap);
    });
  }

  Map<String, dynamic> toFirestore() {
    return {
      'eventId': eventId,
      'seasonId': seasonId,
      'divisionId': divisionId,
      'homeTeamId': homeTeamId,
      'awayTeamId': awayTeamId,
      'homeTeamName': homeTeamName,
      'awayTeamName': awayTeamName,
      'homeScore': homeScore,
      'awayScore': awayScore,
      'status': status.name,
      'submittedBy': submittedBy,
      'submittedAt': submittedAt != null
          ? Timestamp.fromDate(submittedAt!)
          : null,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'rejectedBy': rejectedBy,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
      'rejectionNote': rejectionNote,
      if (entryMode != null) 'entryMode': entryMode!.name,
      'playerLines': playerLines.map((k, v) => MapEntry(k, v.toMap())),
      if (homeQuarterScores.isNotEmpty)
        'homeQuarterScores': homeQuarterScores.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      if (awayQuarterScores.isNotEmpty)
        'awayQuarterScores': awayQuarterScores.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      if (playerQuarterStats != null)
        'playerQuarterStats': playerQuarterStats!.map(
          (playerId, quarters) => MapEntry(
            playerId,
            quarters.map((q, stats) => MapEntry(q.toString(), stats)),
          ),
        ),
    };
  }

  String get winnerTeamId => homeScore >= awayScore ? homeTeamId : awayTeamId;
}
