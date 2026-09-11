import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/artifact_downloader.dart';
import 'package:hoops_connect/features/public/public_game_detail_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

const _snapshotHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _resultHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  testWidgets('media game CSV confirms one version-bound download', (
    tester,
  ) async {
    final downloader = _RecordingDownloader();
    await _pumpDetail(tester, downloader: downloader);

    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('OREB'), findsOneWidget);
    expect(find.text('DREB'), findsOneWidget);
    expect(find.text('TOV'), findsOneWidget);
    expect(find.text('FLS'), findsOneWidget);
    await tester.tap(find.text('Download game CSV'));
    await tester.pumpAndSettle();

    expect(downloader.fileName, contains('aaaaaaaaaaaa.csv'));
    expect(downloader.mimeType, 'text/csv;charset=utf-8');
    final csv = utf8.decode(downloader.bytes!);
    expect(csv, contains(_snapshotHash));
    expect(csv, contains(_resultHash));
    expect(csv, contains('Public Player'));
    expect(find.textContaining('CSV download started for'), findsOneWidget);
  });

  testWidgets('media game CSV failure never reports success', (tester) async {
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(shouldFail: true),
    );

    await tester.tap(find.text('Download game CSV'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save the CSV. No file was downloaded.'),
      findsOneWidget,
    );
    expect(find.textContaining('CSV download started for'), findsNothing);
  });

  testWidgets('media game CSV is disabled on an unsupported platform', (
    tester,
  ) async {
    await _pumpDetail(tester, downloader: _UnsupportedDownloader());

    final button = find.widgetWithText(OutlinedButton, 'Download game CSV');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      find.textContaining('CSV downloads are not supported on this platform'),
      findsOneWidget,
    );
    expect(find.text('Copy published summary'), findsOneWidget);
  });
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required ArtifactDownloader downloader,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final snapshot = _snapshot();
  await tester.pumpWidget(
    MaterialApp(
      home: PublicGameDetailScreen(
        snapshot: snapshot,
        detail: snapshot.gameDetail('game-1')!,
        canExportStats: true,
        downloader: downloader,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PublicLeagueSnapshot _snapshot() => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion: _snapshotHash,
    verificationStatus: 'legacyApproved',
    state: PublicReleaseState.published,
    privacyEpoch: 8,
    generatedAt: DateTime.utc(2026, 9, 10, 21),
  ),
  schedule: [
    PublicGame(
      gameId: 'game-1',
      title: 'Public Home vs Public Away',
      startTime: DateTime.utc(2026, 9, 10, 20),
      homeTeamId: 'home',
      homeTeamName: 'Public Home',
      awayTeamId: 'away',
      awayTeamName: 'Public Away',
      homeScore: 82,
      awayScore: 79,
      status: PublicGameStatus.finalResult,
      resultVersion: _resultHash,
      playerLines: const [
        PublicPlayerGameLine(
          playerId: 'player-1',
          displayName: 'Public Player',
          teamId: 'home',
          minutes: 30,
          points: 20,
          twoPointMade: 5,
          twoPointAttempted: 8,
          threePointMade: 2,
          threePointAttempted: 5,
          freeThrowMade: 4,
          freeThrowAttempted: 5,
          offensiveRebounds: 1,
          defensiveRebounds: 4,
          assists: 3,
          steals: 2,
          blocks: 1,
          turnovers: 2,
          fouls: 3,
        ),
      ],
    ),
  ],
  standings: const [],
  leaderboards: const [],
);

class _RecordingDownloader implements ArtifactDownloader {
  final bool shouldFail;
  Uint8List? bytes;
  String? fileName;
  String? mimeType;

  _RecordingDownloader({this.shouldFail = false});

  @override
  bool get isSupported => true;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (shouldFail) throw StateError('synthetic download failure');
    this.bytes = bytes;
    this.fileName = fileName;
    this.mimeType = mimeType;
    return fileName;
  }
}

class _UnsupportedDownloader implements ArtifactDownloader {
  @override
  bool get isSupported => false;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    throw UnsupportedError('synthetic unsupported platform');
  }
}
