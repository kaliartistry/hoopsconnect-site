import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_league_snapshot.dart';
import '../platform/presentation_preview_environment.dart';
import '../services/public_artifact_release_validator.dart';
import '../services/presentation_public_snapshot.dart';
import '../services/repositories/public_league_repository.dart';

final presentationPublicSnapshotProvider =
    Provider<PresentationPublicSnapshotReader>((ref) {
      return PresentationPublicSnapshotReader();
    });

final publicLeagueRepositoryProvider = Provider<PublicLeagueRepository>((ref) {
  return PublicLeagueRepository();
});

final publicLeagueSnapshotProvider = StreamProvider<PublicLeagueSnapshot?>((
  ref,
) {
  if (PresentationPreviewEnvironment.enabled) {
    return ref.watch(presentationPublicSnapshotProvider).watchCurrentSnapshot();
  }
  return ref.watch(publicLeagueRepositoryProvider).watchCurrentSnapshot();
});

/// Keeps the fan's league choice stable while the four public tabs rebuild.
///
/// Detail routes use normal navigation history, so returning from a game, team,
/// or player also restores the exact public list state that was underneath it.
final publicSelectedLeagueIdProvider = StateProvider<String?>((ref) => null);

final publicArtifactReleaseValidatorProvider =
    Provider<PublicArtifactReleaseValidator>((ref) {
      if (PresentationPreviewEnvironment.enabled) {
        return PublicArtifactReleaseValidator(
          ref.watch(presentationPublicSnapshotProvider),
        );
      }
      return PublicArtifactReleaseValidator(
        ref.watch(publicLeagueRepositoryProvider),
      );
    });
