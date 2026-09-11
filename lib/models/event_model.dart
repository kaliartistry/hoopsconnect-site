import 'package:cloud_firestore/cloud_firestore.dart';

enum StatsStatus { pending, submitted, approved }

class EventModel {
  final String id;
  final String title;
  final String type; // game, deadline, meeting, etc.
  final DateTime startTime;
  final DateTime? endTime;
  final String? location;
  final String? divisionId;
  final List<String> teamIds;
  final String? description;
  final String createdBy;
  final StatsStatus statsStatus;

  const EventModel({
    required this.id,
    required this.title,
    required this.type,
    required this.startTime,
    this.endTime,
    this.location,
    this.divisionId,
    this.teamIds = const [],
    this.description,
    required this.createdBy,
    this.statsStatus = StatsStatus.pending,
  });

  factory EventModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return EventModel(
      id: doc.id,
      title: data['title'] as String,
      type: data['type'] as String,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: data['endTime'] != null
          ? (data['endTime'] as Timestamp).toDate()
          : null,
      location: data['location'] as String?,
      divisionId: data['divisionId'] as String?,
      teamIds: List<String>.from(data['teamIds'] ?? []),
      description: data['description'] as String?,
      createdBy: data['createdBy'] as String,
      statsStatus: StatsStatus.values.byName(
        data['statsStatus'] as String? ?? 'pending',
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'type': type,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'location': location,
      'divisionId': divisionId,
      'teamIds': teamIds,
      'description': description,
      'createdBy': createdBy,
      'statsStatus': statsStatus.name,
    };
  }

  bool get isGame => type == 'game';
  bool get needsStats => isGame && statsStatus == StatsStatus.pending;
}

enum ManualScheduleConflictKind { duplicate, teamOverlap }

class ManualScheduleConflict {
  final ManualScheduleConflictKind kind;
  final String eventId;
  final String eventTitle;

  const ManualScheduleConflict({
    required this.kind,
    required this.eventId,
    required this.eventTitle,
  });
}

class ManualGameScheduleRequest {
  static const schemaVersion = 1;

  final String operationId;
  final String seasonId;
  final String divisionId;
  final String homeTeamId;
  final String awayTeamId;
  final DateTime startTimeUtc;
  final DateTime endTimeUtc;
  final String? location;

  ManualGameScheduleRequest({
    required this.operationId,
    required this.seasonId,
    required this.divisionId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.startTimeUtc,
    required this.endTimeUtc,
    this.location,
  }) {
    for (final entry in {
      'operationId': operationId,
      'seasonId': seasonId,
      'divisionId': divisionId,
      'homeTeamId': homeTeamId,
      'awayTeamId': awayTeamId,
    }.entries) {
      if (!_scheduleIdPattern.hasMatch(entry.value)) {
        throw ArgumentError.value(entry.value, entry.key, 'invalid opaque ID');
      }
    }
    if (homeTeamId == awayTeamId) {
      throw ArgumentError('Home and away teams must be different');
    }
    if (!startTimeUtc.isUtc || !endTimeUtc.isUtc) {
      throw ArgumentError('Schedule instants must be explicit UTC values');
    }
    if (!endTimeUtc.isAfter(startTimeUtc)) {
      throw ArgumentError('Game end must be after its start');
    }
    if ((location?.trim().length ?? 0) > 200) {
      throw ArgumentError.value(
        location,
        'location',
        'must be at most 200 characters',
      );
    }
  }

  Map<String, Object?> toMap() => {
    'schemaVersion': schemaVersion,
    'operationId': operationId,
    'seasonId': seasonId,
    'divisionId': divisionId,
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
    'startTimeUtc': startTimeUtc.toIso8601String(),
    'endTimeUtc': endTimeUtc.toIso8601String(),
    if (location?.trim().isNotEmpty == true) 'location': location!.trim(),
  };
}

List<ManualScheduleConflict> findManualScheduleConflicts({
  required Iterable<EventModel> existingEvents,
  required String homeTeamId,
  required String awayTeamId,
  required DateTime startTimeUtc,
  required DateTime endTimeUtc,
}) {
  final proposedTeams = {homeTeamId, awayTeamId};
  final conflicts = <ManualScheduleConflict>[];
  for (final event in existingEvents.where((event) => event.isGame)) {
    final existingTeams = event.teamIds.toSet();
    final samePair =
        existingTeams.length == 2 &&
        existingTeams.containsAll(proposedTeams) &&
        proposedTeams.containsAll(existingTeams);
    if (samePair && event.startTime.toUtc() == startTimeUtc) {
      conflicts.add(
        ManualScheduleConflict(
          kind: ManualScheduleConflictKind.duplicate,
          eventId: event.id,
          eventTitle: event.title,
        ),
      );
      continue;
    }
    if (existingTeams.intersection(proposedTeams).isEmpty) continue;
    final existingStart = event.startTime.toUtc();
    final existingEnd =
        event.endTime?.toUtc() ?? existingStart.add(const Duration(hours: 2));
    if (startTimeUtc.isBefore(existingEnd) &&
        endTimeUtc.isAfter(existingStart)) {
      conflicts.add(
        ManualScheduleConflict(
          kind: ManualScheduleConflictKind.teamOverlap,
          eventId: event.id,
          eventTitle: event.title,
        ),
      );
    }
  }
  return conflicts;
}

final _scheduleIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
