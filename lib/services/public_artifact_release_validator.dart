import 'dart:convert';

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

  /// A failed server read is not evidence that the publication changed.
  final bool retryable;

  const PublicArtifactReleaseException(this.message, {this.retryable = false});

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
        'The current public release could not be verified with the server. Check your connection.',
        retryable: true,
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

/// Keeps legacy public-score sharing separate from verified publication
/// artifacts. This permits an honest preview of an already-public final score
/// without treating an old `certified` flag as a versioned result certificate.
class PublicLegacyGameShareValidator {
  const PublicLegacyGameShareValidator(this._reader);

  final PublicCurrentReleaseReader _reader;

  Future<ValidatedPublicArtifact> requireCurrent({
    required PublicLeagueSnapshot displayed,
    required PublicGame displayedGame,
  }) async {
    if (!_isLegacyPublicScore(displayed, displayedGame)) {
      throw const PublicArtifactReleaseException(
        'This score is not eligible for a legacy public preview.',
      );
    }
    final PublicLeagueSnapshot? current;
    try {
      current = await _reader.readCurrentRelease();
    } catch (_) {
      throw const PublicArtifactReleaseException(
        'The current public feed could not be checked with the server.',
        retryable: true,
      );
    }
    final game = current?.gameDetail(displayedGame.gameId)?.game;
    if (current == null ||
        game == null ||
        !_isLegacyPublicScore(current, game) ||
        current.associationId != displayed.associationId ||
        current.seasonId != displayed.seasonId ||
        current.generatedAt.toUtc() != displayed.generatedAt.toUtc() ||
        game.resultContentDigest != displayedGame.resultContentDigest) {
      throw const PublicArtifactReleaseException(
        'The public score changed or was withdrawn. Refresh before sharing.',
      );
    }
    return ValidatedPublicArtifact(snapshot: current, game: game);
  }
}

bool isLegacyPublicScoreShareEligible(
  PublicLeagueSnapshot snapshot,
  PublicGame game,
) => _isLegacyPublicScore(snapshot, game);

bool isLegacyPublicTeamStandingsShareEligible(PublicLeagueSnapshot snapshot) =>
    _isLegacyPublicSnapshot(snapshot) && snapshot.standings.isNotEmpty;

class PublicLegacyStandingsShareValidator {
  const PublicLegacyStandingsShareValidator(this._reader);

  final PublicCurrentReleaseReader _reader;

  Future<PublicLeagueSnapshot> requireCurrent(
    PublicLeagueSnapshot displayed,
  ) async {
    if (!isLegacyPublicTeamStandingsShareEligible(displayed)) {
      throw const PublicArtifactReleaseException(
        'These standings are not eligible for a legacy public preview.',
      );
    }
    final PublicLeagueSnapshot? current;
    try {
      current = await _reader.readCurrentRelease();
    } catch (_) {
      throw const PublicArtifactReleaseException(
        'The current public standings could not be checked with the server.',
        retryable: true,
      );
    }
    if (current == null ||
        !isLegacyPublicTeamStandingsShareEligible(current) ||
        current.associationId != displayed.associationId ||
        current.seasonId != displayed.seasonId ||
        current.generatedAt.toUtc() != displayed.generatedAt.toUtc() ||
        _standingContent(current.standings) !=
            _standingContent(displayed.standings)) {
      throw const PublicArtifactReleaseException(
        'The public standings changed or were withdrawn. Refresh before sharing.',
      );
    }
    return current;
  }
}

String _standingContent(List<PublicStanding> standings) => jsonEncode([
  for (final row in standings)
    {
      'teamId': row.teamId,
      'teamName': row.teamName,
      'divisionId': row.divisionId,
      'rank': row.rank,
      'rankStatus': row.rankStatus.name,
      'wins': row.wins,
      'losses': row.losses,
      'pct': row.pct,
      'pointsFor': row.pointsFor,
      'pointsAgainst': row.pointsAgainst,
    },
]);

bool _isLegacyPublicSnapshot(PublicLeagueSnapshot snapshot) =>
    snapshot.version.isPublished &&
    !snapshot.version.isVersioned &&
    snapshot.version.contractVersion == 'legacy-public-snapshot-v1' &&
    snapshot.version.verificationStatus == 'certified';

bool _isLegacyPublicScore(PublicLeagueSnapshot snapshot, PublicGame game) =>
    _isLegacyPublicSnapshot(snapshot) &&
    game.isFinal &&
    game.homeScore != null &&
    game.awayScore != null;
