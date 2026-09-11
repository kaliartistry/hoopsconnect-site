import '../models/public_league_snapshot.dart';

abstract interface class PublicCurrentReleaseReader {
  Future<PublicLeagueSnapshot?> readCurrentRelease();
}

class PublicArtifactBinding {
  final String associationId;
  final String seasonId;
  final String snapshotVersion;
  final String? releaseId;
  final DateTime generatedAt;
  final int? privacyEpoch;
  final String? gameId;
  final String? resultVersion;

  const PublicArtifactBinding({
    required this.associationId,
    required this.seasonId,
    required this.snapshotVersion,
    required this.releaseId,
    required this.generatedAt,
    required this.privacyEpoch,
    this.gameId,
    this.resultVersion,
  });

  factory PublicArtifactBinding.snapshot(PublicLeagueSnapshot snapshot) {
    final snapshotVersion = snapshot.version.snapshotVersion;
    if (!snapshot.canCreatePublishedArtifacts || snapshotVersion == null) {
      throw const PublicArtifactReleaseException(
        'The displayed public release is not eligible for artifacts.',
      );
    }
    return PublicArtifactBinding(
      associationId: snapshot.associationId,
      seasonId: snapshot.seasonId,
      snapshotVersion: snapshotVersion,
      releaseId: snapshot.version.releaseId,
      generatedAt: snapshot.generatedAt.toUtc(),
      privacyEpoch: snapshot.version.privacyEpoch,
    );
  }

  factory PublicArtifactBinding.game(
    PublicLeagueSnapshot snapshot,
    PublicGame game,
  ) {
    final base = PublicArtifactBinding.snapshot(snapshot);
    if (!game.hasVersionedResult) {
      throw const PublicArtifactReleaseException(
        'The displayed game is not bound to its result content.',
      );
    }
    return PublicArtifactBinding(
      associationId: base.associationId,
      seasonId: base.seasonId,
      snapshotVersion: base.snapshotVersion,
      releaseId: base.releaseId,
      generatedAt: base.generatedAt,
      privacyEpoch: base.privacyEpoch,
      gameId: game.gameId,
      resultVersion: game.resultVersion,
    );
  }
}

class ValidatedPublicArtifact {
  final PublicLeagueSnapshot snapshot;
  final PublicGame? game;

  const ValidatedPublicArtifact({required this.snapshot, this.game});
}

class PublicArtifactReleaseException implements Exception {
  final String message;

  const PublicArtifactReleaseException(this.message);

  @override
  String toString() => message;
}

/// Performs an authoritative, uncached read before an artifact action. The
/// injected reader is the legacy Firestore document today and can be replaced
/// by the dormant v2 pointer/manifest/page reader during the atomic cutover.
class PublicArtifactReleaseValidator {
  final PublicCurrentReleaseReader _reader;

  const PublicArtifactReleaseValidator(this._reader);

  Future<ValidatedPublicArtifact> requireCurrent(
    PublicArtifactBinding expected,
  ) async {
    final PublicLeagueSnapshot? current;
    try {
      current = await _reader.readCurrentRelease();
    } catch (_) {
      throw const PublicArtifactReleaseException(
        'The current public release could not be verified.',
      );
    }
    if (current == null || !current.canCreatePublishedArtifacts) {
      throw const PublicArtifactReleaseException(
        'The public release is unavailable or has been withdrawn.',
      );
    }
    if (current.associationId != expected.associationId ||
        current.seasonId != expected.seasonId ||
        current.version.snapshotVersion != expected.snapshotVersion ||
        current.version.releaseId != expected.releaseId ||
        current.generatedAt.toUtc() != expected.generatedAt ||
        current.version.privacyEpoch != expected.privacyEpoch) {
      throw const PublicArtifactReleaseException(
        'The public release changed after this view was opened.',
      );
    }
    if (expected.gameId == null) {
      return ValidatedPublicArtifact(snapshot: current);
    }
    final game = current.gameDetail(expected.gameId!)?.game;
    if (game == null ||
        !game.hasVersionedResult ||
        game.resultVersion != expected.resultVersion) {
      throw const PublicArtifactReleaseException(
        'The published game result changed after this view was opened.',
      );
    }
    return ValidatedPublicArtifact(snapshot: current, game: game);
  }
}
