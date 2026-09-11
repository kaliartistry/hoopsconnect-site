import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_league_snapshot.dart';
import '../services/repositories/public_league_repository.dart';

final publicLeagueRepositoryProvider = Provider<PublicLeagueRepository>((ref) {
  return PublicLeagueRepository();
});

final publicLeagueSnapshotProvider = StreamProvider<PublicLeagueSnapshot?>((
  ref,
) {
  return ref.watch(publicLeagueRepositoryProvider).watchCurrentSnapshot();
});
