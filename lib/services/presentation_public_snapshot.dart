import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/public_league_snapshot.dart';
import 'public_artifact_release_validator.dart';

/// Read-only presentation bundle, including historical JBL aggregates and
/// unrelated example leagues, used only by an explicitly flagged presentation
/// build. Normal web, iOS, and Android builds continue to read the
/// server-published public snapshot.
class PresentationPublicSnapshotReader implements PublicCurrentReleaseReader {
  static const assetPath = 'assets/demo/presentation_public_snapshot.json';
  static Future<PublicLeagueSnapshot>? _cachedSnapshot;

  Future<PublicLeagueSnapshot> load() => _cachedSnapshot ??= _loadFromBundle();

  Stream<PublicLeagueSnapshot?> watchCurrentSnapshot() => load().asStream();

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() => load();

  static Future<PublicLeagueSnapshot> _loadFromBundle() async {
    final encoded = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException(
        'The presentation public snapshot must be a JSON object.',
      );
    }
    return PublicLeagueSnapshot.fromMap(Map<String, dynamic>.from(decoded));
  }
}
