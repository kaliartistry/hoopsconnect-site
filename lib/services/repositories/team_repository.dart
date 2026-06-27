import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/team_model.dart';

class TeamRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<TeamModel> _teamsRef(String assocId) {
    return _db
        .collection(FirestorePaths.teams(assocId))
        .withConverter<TeamModel>(
          fromFirestore: (snap, _) => TeamModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  Stream<List<TeamModel>> watchTeams(String assocId, {String? seasonId}) {
    Query<TeamModel> query = _teamsRef(assocId);
    if (seasonId != null) {
      query = query.where('seasonId', isEqualTo: seasonId);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map((d) => d.data()).toList(),
        );
  }

  Future<TeamModel?> getTeam(String assocId, String teamId) async {
    final snap = await _teamsRef(assocId).doc(teamId).get();
    return snap.exists ? snap.data() : null;
  }

  Stream<TeamModel?> watchTeam(String assocId, String teamId) {
    return _teamsRef(assocId).doc(teamId).snapshots().map(
          (snap) => snap.exists ? snap.data() : null,
        );
  }

  Future<void> createTeam(String assocId, TeamModel team) {
    return _teamsRef(assocId).doc(team.id).set(team);
  }

  Future<void> updateTeam(
    String assocId,
    String teamId,
    Map<String, dynamic> data,
  ) {
    return _db.doc(FirestorePaths.team(assocId, teamId)).update(data);
  }
}
