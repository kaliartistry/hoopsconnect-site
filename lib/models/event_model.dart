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
  bool get needsStats =>
      isGame && statsStatus == StatsStatus.pending;
}
