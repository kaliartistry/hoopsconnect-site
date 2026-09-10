import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_league_snapshot.dart';

final publicLeagueSnapshotProvider = StreamProvider<PublicLeagueSnapshot?>((
  ref,
) {
  return FirebaseFirestore.instance
      .doc('publicData/jba/snapshots/current')
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? PublicLeagueSnapshot.fromMap(snapshot.data()!)
            : null,
      );
});
