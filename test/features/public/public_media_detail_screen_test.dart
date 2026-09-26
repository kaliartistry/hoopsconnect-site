import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/public/public_media_detail_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/public_artifact_release_validator.dart';

void main() {
  testWidgets('a published story opens its branded Share card', (tester) async {
    final snapshot = _snapshot();
    await _pump(tester, snapshot: snapshot, current: snapshot);

    final button = find.byKey(const Key('public-media-share-button'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Share this story'), findsWidgets);
    expect(find.text('League opening day'), findsWidgets);
    expect(find.text('Published league media'), findsOneWidget);
  });

  testWidgets('withdrawn public release blocks the media card', (tester) async {
    final snapshot = _snapshot();
    await _pump(
      tester,
      snapshot: snapshot,
      current: _snapshot(state: PublicReleaseState.retracted),
    );

    await tester.tap(find.byKey(const Key('public-media-share-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('withdrawn'), findsOneWidget);
    expect(find.byKey(const Key('close-share-sheet')), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required PublicLeagueSnapshot snapshot,
  required PublicLeagueSnapshot current,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: PublicMediaDetailScreen(
          snapshot: snapshot,
          item: snapshot.media.single,
          canonicalUri: Uri.parse('https://example.test/public/media/story-1'),
          releaseValidator: PublicArtifactReleaseValidator(
            _SingleReleaseReader(current),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PublicLeagueSnapshot _snapshot({
  PublicReleaseState state = PublicReleaseState.published,
}) => PublicLeagueSnapshot(
  leagueName: 'Jamaica Basketball Association',
  leagueShortName: 'JBA',
  seasonId: 'season-1',
  seasonName: '2026 NBL',
  version: PublicSnapshotVersion(
    schemaVersion: 1,
    contractVersion: 'legacy-public-snapshot-v1.1',
    snapshotVersion:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    verificationStatus: 'legacyApproved',
    state: state,
    privacyEpoch: 3,
    generatedAt: DateTime.utc(2026, 9, 10),
  ),
  schedule: const [],
  standings: const [],
  leaderboards: const [],
  media: [
    PublicMediaItem(
      mediaId: 'story-1',
      title: 'League opening day',
      summary: 'The season tips off on Saturday.',
      type: 'announcement',
      publishedAt: DateTime.utc(2026, 9, 10),
    ),
  ],
);

class _SingleReleaseReader implements PublicCurrentReleaseReader {
  const _SingleReleaseReader(this.current);

  final PublicLeagueSnapshot current;

  @override
  Future<PublicLeagueSnapshot?> readCurrentRelease() async => current;
}
