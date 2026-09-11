import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/artifact_downloader.dart';
import 'package:hoops_connect/features/press/press_dashboard_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

const _snapshotHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _resultHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  testWidgets('media results and leaders come from one public snapshot', (
    tester,
  ) async {
    await _pumpDashboard(tester, downloader: _RecordingDownloader());

    expect(find.text('Public Home'), findsWidgets);
    expect(find.text('Public Away'), findsWidgets);
    expect(find.text('Public Leader'), findsOneWidget);
    await tester.ensureVisible(find.text('Media Export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('publication aaaaaaaaaaaa'), findsOneWidget);
  });

  testWidgets('media season CSV confirms a version-bound download', (
    tester,
  ) async {
    final downloader = _RecordingDownloader();
    await _pumpDashboard(tester, downloader: downloader);

    final button = find.widgetWithText(OutlinedButton, 'Download season CSV');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(downloader.fileName, contains('aaaaaaaaaaaa.csv'));
    expect(downloader.mimeType, 'text/csv;charset=utf-8');
    final csv = utf8.decode(downloader.bytes!);
    expect(csv, contains(_snapshotHash));
    expect(csv, contains(_resultHash));
    expect(csv, contains('Public Leader'));
    expect(
      find.textContaining('Season CSV download started for'),
      findsOneWidget,
    );
  });

  testWidgets('media season CSV reports a failed handoff without success', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      downloader: _RecordingDownloader(shouldFail: true),
    );

    final button = find.widgetWithText(OutlinedButton, 'Download season CSV');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save the season CSV. No file was downloaded.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Season CSV download started for'),
      findsNothing,
    );
  });

  testWidgets('media season CSV is feature-detected before interaction', (
    tester,
  ) async {
    await _pumpDashboard(tester, downloader: _UnsupportedDownloader());

    final button = find.widgetWithText(OutlinedButton, 'Download season CSV');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(
      find.textContaining('Downloads are not supported on this platform'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required ArtifactDownloader downloader,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const user = UserModel(
    id: 'media-1',
    email: 'media@example.test',
    displayName: 'Media Tester',
    associationId: 'jba',
    role: UserRole.media,
    capabilities: {'stats.export', 'press.read'},
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(const AsyncValue.data(user)),
        publicLeagueSnapshotProvider.overrideWith(
          (ref) => Stream.value(_snapshot()),
        ),
      ],
      child: MaterialApp(home: PressDashboardScreen(downloader: downloader)),
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
    ),
  ],
  standings: const [],
  leaderboards: const [
    PublicLeaderboard(
      category: 'ppg',
      rankings: [
        PublicLeader(
          playerId: 'player-1',
          displayName: 'Public Leader',
          teamId: 'home',
          teamName: 'Public Home',
          value: 21.5,
          gamesPlayed: 4,
        ),
      ],
    ),
  ],
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
