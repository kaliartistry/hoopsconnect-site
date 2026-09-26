import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  testWidgets(
    'current public score can be shared without unavailable box stats',
    (tester) async {
      final snapshot = _legacySnapshot();
      await _pumpDetail(
        tester,
        downloader: _RecordingDownloader(),
        snapshotOverride: snapshot,
      );

      final button = find.widgetWithText(FilledButton, 'Share final score');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.text('Share box score'), findsNothing);
      expect(find.text('Download game CSV'), findsNothing);
      expect(find.textContaining('Legacy public score'), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Share final score'), findsWidgets);
      expect(find.text('League result'), findsOneWidget);
    },
  );

  testWidgets('temporary server failure leaves the score Share retry enabled', (
    tester,
  ) async {
    final snapshot = _legacySnapshot();
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(),
      snapshotOverride: snapshot,
      currentReleases: [StateError('offline'), snapshot],
    );

    final button = find.widgetWithText(FilledButton, 'Share final score');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Reconnect and try Share again'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Share final score'), findsWidgets);
  });

  testWidgets('published scheduled game opens a share card without a score', (
    tester,
  ) async {
    final snapshot = _scheduledSnapshot();
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(),
      snapshotOverride: snapshot,
    );

    final button = find.widgetWithText(FilledButton, 'Share upcoming game');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Share this game'), findsOneWidget);
    expect(find.text('UPCOMING GAME'), findsWidgets);
    expect(find.text('Copy game summary'), findsNothing);
  });

  testWidgets('published score uses association partner when league has none', (
    tester,
  ) async {
    final snapshot = _snapshot(associationPartner: true);
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(),
      snapshotOverride: snapshot,
    );

    await tester.tap(
      find.widgetWithText(FilledButton, 'Share published result'),
    );
    await tester.pumpAndSettle();
    expect(find.text('ASSOCIATION PARTNER'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Kingston Flame Kitchen logo'),
      findsOneWidget,
    );
  });

  testWidgets('media game CSV confirms one version-bound download', (
    tester,
  ) async {
    final downloader = _RecordingDownloader();
    await _pumpDetail(tester, downloader: downloader);

    expect(find.text('MIN'), findsNWidgets(2));
    expect(find.text('REB'), findsWidgets);
    expect(find.text('TO'), findsWidgets);
    expect(find.text('PF'), findsWidgets);
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

  testWidgets('box score links only players with an available public profile', (
    tester,
  ) async {
    final snapshot = _snapshot(includePlayerProfile: true);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PublicGameDetailScreen(
            snapshot: snapshot,
            detail: snapshot.gameDetail('game-1')!,
          ),
        ),
        GoRoute(
          path: '/public/players/:playerId',
          builder: (_, state) => Scaffold(
            body: Text('Profile ${state.pathParameters['playerId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Public Player'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(find.text('Public Player').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Profile player-1'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Game details'), findsOneWidget);
    expect(find.text('Public Player'), findsOneWidget);
  });

  testWidgets('box score team header opens its team profile and returns', (
    tester,
  ) async {
    final snapshot = _snapshot(includeTeams: true);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PublicGameDetailScreen(
            snapshot: snapshot,
            detail: snapshot.gameDetail('game-1')!,
          ),
        ),
        GoRoute(
          path: '/public/teams/:teamId',
          builder: (_, state) => Scaffold(
            body: Text('Team profile ${state.pathParameters['teamId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final teamLink = find.byKey(const Key('box-score-team-home'));
    await tester.dragUntilVisible(
      teamLink,
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(teamLink);
    await tester.pumpAndSettle();
    expect(find.text('Team profile home'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Game details'), findsOneWidget);
    expect(teamLink, findsOneWidget);
  });

  testWidgets('box score separates teams and keeps player names pinned', (
    tester,
  ) async {
    await _pumpDetail(tester, downloader: _RecordingDownloader());

    expect(find.text('PUBLIC HOME'), findsOneWidget);
    expect(find.text('PUBLIC AWAY'), findsOneWidget);
    expect(find.text('TOTALS'), findsNWidgets(2));
    expect(find.textContaining('player names stay visible'), findsOneWidget);
    expect(find.text('Public Player'), findsOneWidget);
    expect(find.text('Away Player'), findsOneWidget);
  });

  testWidgets('box score stat headings sort highest first and then reverse', (
    tester,
  ) async {
    await _pumpDetail(tester, downloader: _RecordingDownloader());

    double playerTop(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(playerTop('Public Player'), lessThan(playerTop('Home Bench')));

    await tester.tap(find.byKey(const ValueKey('box-score-sort-PTS')).first);
    await tester.pumpAndSettle();
    expect(playerTop('Home Bench'), lessThan(playerTop('Public Player')));
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('box-score-sort-REB')).first);
    await tester.pumpAndSettle();
    expect(playerTop('Public Player'), lessThan(playerTop('Home Bench')));

    await tester.tap(find.byKey(const ValueKey('box-score-sort-REB')).first);
    await tester.pumpAndSettle();
    expect(playerTop('Home Bench'), lessThan(playerTop('Public Player')));
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('box score remains usable at phone width without overflow', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      downloader: _RecordingDownloader(),
      viewSize: const Size(390, 844),
    );

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Box score'), findsOneWidget);
    expect(find.text('Team stats'), findsOneWidget);
    expect(find.text('PUBLIC HOME'), findsOneWidget);
    expect(find.text('Public Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmatched box score player does not open a broken profile', (
    tester,
  ) async {
    final snapshot = _snapshot();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PublicGameDetailScreen(
            snapshot: snapshot,
            detail: snapshot.gameDetail('game-1')!,
          ),
        ),
        GoRoute(
          path: '/public/players/:playerId',
          builder: (_, state) => Scaffold(
            body: Text('Profile ${state.pathParameters['playerId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Public Player'),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(find.text('Public Player').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Profile player-1'), findsNothing);
    expect(find.text('Public Player'), findsOneWidget);
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
    expect(find.text('Copy game summary'), findsOneWidget);
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

    await tester.tap(find.text('Copy game summary'));
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
  PublicLeagueSnapshot? snapshotOverride,
  List<Object?>? currentReleases,
  Future<void> Function(String text)? clipboardWriter,
  Size viewSize = const Size(900, 1800),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final snapshot = snapshotOverride ?? _snapshot();
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
          legacyShareValidator: PublicLegacyGameShareValidator(reader),
          clipboardWriter: clipboardWriter,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PublicLeagueSnapshot _legacySnapshot() => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1',
    snapshotVersion: null,
    verificationStatus: 'certified',
    state: PublicReleaseState.published,
    privacyEpoch: null,
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
    ),
  ],
  standings: const [],
  leaderboards: const [],
);

PublicLeagueSnapshot _scheduledSnapshot() => PublicLeagueSnapshot(
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
      startTime: DateTime.utc(2026, 9, 20, 20),
      homeTeamName: 'Public Home',
      awayTeamName: 'Public Away',
      status: PublicGameStatus.scheduled,
    ),
  ],
  standings: const [],
  leaderboards: const [],
);

PublicLeagueSnapshot _snapshot({
  String snapshotVersion = _snapshotHash,
  int homeScore = 82,
  PublicReleaseState state = PublicReleaseState.published,
  bool associationPartner = false,
  bool includePlayerProfile = false,
  bool includeTeams = false,
}) => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  associationBrand: associationPartner
      ? const PublicBrandIdentity(
          name: 'Jamaica Basketball Association',
          shortName: 'JBA',
          sponsor: PublicSponsor(
            enabled: true,
            name: 'Kingston Flame Kitchen',
            logoUrl: 'asset:assets/images/sponsor_kingston_flame.png',
          ),
        )
      : null,
  leagues: associationPartner
      ? const [
          PublicLeagueDefinition(
            leagueId: 'schools',
            name: 'Schoolboy League',
            shortName: 'Schools',
          ),
        ]
      : const [],
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
              PublicPlayerGameLine(
                playerId: 'player-2',
                displayName: 'Away Player',
                teamId: 'away',
                minutes: 28,
                points: 18,
                twoPointMade: 4,
                twoPointAttempted: 7,
                threePointMade: 2,
                threePointAttempted: 6,
                freeThrowMade: 4,
                freeThrowAttempted: 4,
                offensiveRebounds: 2,
                defensiveRebounds: 5,
                assists: 4,
                steals: 1,
                blocks: 0,
                turnovers: 3,
                fouls: 2,
              ),
              PublicPlayerGameLine(
                playerId: 'player-3',
                displayName: 'Home Bench',
                teamId: 'home',
                minutes: 22,
                points: 25,
                twoPointMade: 8,
                twoPointAttempted: 12,
                threePointMade: 2,
                threePointAttempted: 5,
                freeThrowMade: 3,
                freeThrowAttempted: 4,
                offensiveRebounds: 1,
                defensiveRebounds: 1,
                assists: 8,
                steals: 1,
                blocks: 0,
                turnovers: 1,
                fouls: 2,
              ),
            ],
          ).withComputedResultVersion(),
        ]
      : const [],
  teams: includeTeams
      ? const [
          PublicTeam(teamId: 'home', name: 'Public Home'),
          PublicTeam(teamId: 'away', name: 'Public Away'),
        ]
      : const [],
  standings: const [],
  leaderboards: includePlayerProfile
      ? const [
          PublicLeaderboard(
            category: 'ppg',
            rankings: [
              PublicLeader(
                playerId: 'player-1',
                displayName: 'Public Player',
                teamId: 'home',
                teamName: 'Public Home',
                value: 20,
                gamesPlayed: 1,
              ),
            ],
          ),
        ]
      : const [],
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
  final List<Object?> releases;
  int _index = 0;

  _QueueReleaseReader(this.releases);

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async {
    final index = _index < releases.length ? _index++ : releases.length - 1;
    final release = releases[index];
    if (release is Exception) throw release;
    return release as PublicLeagueSnapshot?;
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
