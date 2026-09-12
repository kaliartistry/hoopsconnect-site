import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/artifact_downloader.dart';
import 'package:hoops_connect/features/public/public_game_detail_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/public_artifact_release_validator.dart';

const _snapshotHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _changedSnapshotHash =
    'cccccccccccccccccccccccccccccccc'
    'cccccccccccccccccccccccccccccccc';

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
    expect(csv, contains(_snapshot().schedule.single.resultVersion!));
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

  testWidgets('media game CSV disables duplicate taps while pending', (
    tester,
  ) async {
    final downloader = _PendingDownloader();
    await _pumpDetail(tester, downloader: downloader);

    await tester.tap(find.text('Download game CSV'));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Saving CSV…'),
    );
    expect(button.onPressed, isNull);
    expect(downloader.calls, 1);

    downloader.complete('verified.csv');
    await tester.pumpAndSettle();
    expect(downloader.calls, 1);
    expect(find.textContaining('CSV download started for'), findsOneWidget);
  });

  testWidgets('retraction before an action cancels and disables artifacts', (
    tester,
  ) async {
    final downloader = _RecordingDownloader();
    await _pumpDetail(
      tester,
      downloader: downloader,
      currentReleases: [_snapshot(state: PublicReleaseState.retracted)],
    );

    await tester.tap(find.text('Download game CSV'));
    await tester.pumpAndSettle();

    expect(downloader.calls, 0);
    expect(find.textContaining('withdrawn'), findsOneWidget);
    expect(find.text('Download game CSV'), findsNothing);
  });

  testWidgets('version change during download never reports stale success', (
    tester,
  ) async {
    final downloader = _PendingDownloader();
    await _pumpDetail(
      tester,
      downloader: downloader,
      currentReleases: [
        _snapshot(),
        _snapshot(),
        _snapshot(snapshotVersion: _changedSnapshotHash, homeScore: 83),
      ],
    );

    await tester.tap(find.text('Download game CSV'));
    await tester.pump();
    expect(downloader.calls, 1);
    downloader.complete('older.csv');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('downloaded file may be outdated'),
      findsOneWidget,
    );
    expect(find.textContaining('CSV download started for'), findsNothing);
  });

  testWidgets('version change during copy warns that clipboard may be stale', (
    tester,
  ) async {
    final writer = _PendingClipboardWriter();
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(),
      clipboardWriter: writer.call,
      currentReleases: [
        _snapshot(),
        _snapshot(snapshotVersion: _changedSnapshotHash, homeScore: 83),
      ],
    );

    await tester.tap(find.text('Copy published summary'));
    await tester.pump();
    expect(writer.calls, 1);
    writer.complete();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('clipboard may contain an older result'),
      findsOneWidget,
    );
    expect(find.text('Copied to clipboard'), findsNothing);
  });
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required ArtifactDownloader downloader,
  List<PublicLeagueSnapshot?>? currentReleases,
  Future<void> Function(String text)? clipboardWriter,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final snapshot = _snapshot();
  final reader = _QueueReleaseReader(currentReleases ?? [snapshot]);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: PublicGameDetailScreen(
          snapshot: snapshot,
          detail: snapshot.gameDetail('game-1')!,
          canExportStats: true,
          downloader: downloader,
          releaseValidator: PublicArtifactReleaseValidator(reader),
          clipboardWriter: clipboardWriter,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PublicLeagueSnapshot _snapshot({
  String snapshotVersion = _snapshotHash,
  int homeScore = 82,
  PublicReleaseState state = PublicReleaseState.published,
}) => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion: snapshotVersion,
    verificationStatus: 'legacyApproved',
    state: state,
    privacyEpoch: 8,
    generatedAt: DateTime.utc(2026, 9, 10, 21),
  ),
  schedule: state == PublicReleaseState.published
      ? [
          PublicGame(
            gameId: 'game-1',
            title: 'Public Home vs Public Away',
            startTime: DateTime.utc(2026, 9, 10, 20),
            homeTeamId: 'home',
            homeTeamName: 'Public Home',
            awayTeamId: 'away',
            awayTeamName: 'Public Away',
            homeScore: homeScore,
            awayScore: 79,
            status: PublicGameStatus.finalResult,
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
          ).withComputedResultVersion(),
        ]
      : const [],
  standings: const [],
  leaderboards: const [],
);

class _RecordingDownloader implements ArtifactDownloader {
  final bool shouldFail;
  Uint8List? bytes;
  String? fileName;
  String? mimeType;
  int calls = 0;

  _RecordingDownloader({this.shouldFail = false});

  @override
  bool get isSupported => true;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    calls++;
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

class _PendingDownloader implements ArtifactDownloader {
  final _pending = Completer<String>();
  int calls = 0;

  @override
  bool get isSupported => true;

  void complete(String destination) => _pending.complete(destination);

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    calls++;
    return _pending.future;
  }
}

class _QueueReleaseReader implements PublicCurrentReleaseReader {
  final List<PublicLeagueSnapshot?> releases;
  int _index = 0;

  _QueueReleaseReader(this.releases);

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async {
    final index = _index < releases.length ? _index++ : releases.length - 1;
    return releases[index];
  }
}

class _PendingClipboardWriter {
  final _pending = Completer<void>();
  int calls = 0;

  Future<void> call(String text) {
    calls++;
    return _pending.future;
  }

  void complete() => _pending.complete();
}
