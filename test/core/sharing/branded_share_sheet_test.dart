import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_actions.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/branded_share_sheet.dart';
import 'package:hoops_connect/core/sharing/share_demo_samples.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/services/public_artifact_release_validator.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  testWidgets('comparison card fits a phone and retains sponsor identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(
                branding: ShareDemoSamples.branding,
                payload: const BrandedSharePayload(
                  title: 'Comparison',
                  headline: 'Comparison',
                  detail: 'St George’s Slayers · UWI Running Rebels',
                  shareText: 'Comparison',
                  fileName: 'compare.png',
                  eyebrow: 'PLAYER COMPARISON',
                  teams: [
                    BrandedShareTeam(name: 'Christopher Alexander Williams'),
                    BrandedShareTeam(name: 'Nathaniel Michael Thompson'),
                  ],
                  comparisonRows: [
                    ('GP', '9', '9'),
                    ('PPG', '24.5', '21.6'),
                    ('RPG', '9.0', '8.2'),
                    ('APG', '5.1', '6.7'),
                    ('SPG', '2.1', '1.4'),
                    ('BPG', '1.0', '0.8'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PLAYER COMPARISON'), findsOneWidget);
    expect(find.text('TITLE SPONSOR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'evaluation box-score card looks like the real share design without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BrandedShareCard(
                  branding: ShareDemoSamples.branding,
                  payload: ShareDemoSamples.boxScore,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('BOX SCORE'), findsOneWidget);
      expect(ShareDemoSamples.boxScore.isDemonstration, isTrue);
      expect(find.text('DEMONSTRATION · NOT OFFICIAL'), findsNothing);
      expect(ShareDemoSamples.boxScore.versionLabel, isNull);
      expect(find.text('League box score'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
      expect(find.text('76'), findsOneWidget);
      expect(
        ShareDemoSamples.boxScore.shareText,
        contains('Shared from HoopsConnect'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('player and leaders evaluation cards fit a phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final payload in [
      ShareDemoSamples.player,
      ShareDemoSamples.leaderboard,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BrandedShareCard(
                  branding: ShareDemoSamples.branding,
                  payload: payload,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(payload.eyebrow), findsOneWidget);
      expect(payload.isDemonstration, isTrue);
      expect(find.text('DEMONSTRATION · NOT OFFICIAL'), findsNothing);
      expect(payload.shareText, isNot(contains('DEMONSTRATION CARD')));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('share sheet has an always-visible close control', (
    tester,
  ) async {
    await _pumpSheet(tester, _FakeShareActions());

    expect(find.byKey(const Key('close-share-sheet')), findsOneWidget);
    expect(find.byTooltip('Close share options'), findsOneWidget);
    final closeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('close-share-sheet')),
        matching: find.byIcon(Icons.close),
      ),
    );
    expect(closeIcon.color, const Color(0xFF10264B));
    expect(tester.takeException(), isNull);
  });

  testWidgets('share card keeps league, sponsor, and app identity visible', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      leagueName: 'National Basketball League',
      logoUrl: 'asset:assets/images/nbl_jamaica_logo.png',
      sponsor: const SponsorBrandingModel(
        enabled: true,
        name: 'ShipSafe SDK',
        logoUrl: 'asset:assets/images/sponsor_shipsafe.png',
      ),
    );
    const payload = BrandedSharePayload(
      title: 'Game result',
      headline: 'Kingston Titans defeat Montego Bay Storm 87-72',
      detail: 'A complete game summary.',
      shareText: 'Share text',
      fileName: 'result.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(branding: branding, payload: payload),
            ),
          ),
        ),
      ),
    );

    expect(find.text('JAMAICA BASKETBALL ASSOCIATION'), findsOneWidget);
    expect(find.text('TITLE SPONSOR'), findsOneWidget);
    expect(find.bySemanticsLabel('ShipSafe SDK logo'), findsOneWidget);
    expect(find.text('HOOPSCONNECT'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.textContaining('87-72'), findsOneWidget);
    expect(find.text('League result'), findsOneWidget);
  });

  testWidgets('association partner uses its own sponsor relationship', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      sponsor: const SponsorBrandingModel(
        enabled: true,
        name: 'Kingston Flame Kitchen',
        label: 'Association partner',
        logoUrl: 'asset:assets/images/sponsor_kingston_flame.png',
      ),
    );
    const payload = BrandedSharePayload(
      title: 'Standings',
      headline: 'League standings',
      detail: 'Across leagues',
      shareText: 'League standings',
      fileName: 'standings.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: BrandedShareCard(branding: branding, payload: payload),
          ),
        ),
      ),
    );

    expect(find.text('ASSOCIATION PARTNER'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Kingston Flame Kitchen logo'),
      findsOneWidget,
    );
  });

  testWidgets('published score card renders team logos and scores', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      leagueName: 'National Basketball League',
      logoUrl: 'asset:assets/images/nbl_jamaica_logo.png',
      sponsor: const SponsorBrandingModel(
        enabled: true,
        name: 'ShipSafe SDK',
        logoUrl: 'asset:assets/images/sponsor_shipsafe.png',
      ),
    );
    const payload = BrandedSharePayload(
      title: 'Game result',
      headline: 'Kingston Lions defeats Montego Bay Waves 82-76',
      detail: 'Synthetic 2026 Season published result',
      shareText: 'Share text',
      fileName: 'result.png',
      divisionLabel: 'Premier',
      versionLabel: 'Publication c2ee523ae737',
      teams: [
        BrandedShareTeam(
          name: 'Kingston Lions',
          logoUrl: 'asset:assets/images/jba_logo.png',
          score: 82,
        ),
        BrandedShareTeam(name: 'Montego Bay Waves', score: 76),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(branding: branding, payload: payload),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Kingston Lions team logo'), findsOneWidget);
    expect(
      find.bySemanticsLabel('National Basketball League logo'),
      findsOneWidget,
    );
    expect(find.text('NATIONAL BASKETBALL LEAGUE'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Montego Bay Waves team mark'),
      findsOneWidget,
    );
    expect(find.text('Kingston Lions'), findsOneWidget);
    expect(find.text('Montego Bay Waves'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('76'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share card keeps a compact structure across content types', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      leagueName: 'National Basketball League',
      logoUrl: 'asset:assets/images/nbl_jamaica_logo.png',
      sponsor: const SponsorBrandingModel(
        enabled: true,
        name: 'ShipSafe SDK',
        logoUrl: 'asset:assets/images/sponsor_shipsafe.png',
      ),
    );
    const payloads = [
      BrandedSharePayload(
        title: 'Final score',
        eyebrow: 'FINAL',
        headline: 'St George’s Slayers defeat UWI Running Rebels 82-76',
        detail: 'A complete published result.',
        shareText: 'Share text',
        fileName: 'score.png',
        teams: [
          BrandedShareTeam(name: 'St George’s Slayers', score: 82),
          BrandedShareTeam(name: 'UWI Running Rebels', score: 76),
        ],
      ),
      BrandedSharePayload(
        title: 'Box score',
        eyebrow: 'BOX SCORE',
        headline: 'Jordan Brown leads all scorers with 28 PTS',
        detail:
            'Q1: 21-17 · Q2: 40-35\nJordan Brown · 28 PTS · 8 REB\nAndre King · 24 PTS · 6 AST',
        divisionLabel: 'Premier',
        periodScoreLine: 'Q1: 21-17 · Q2: 40-35',
        performerLines: [
          'Jordan Brown · 28 PTS · 8 REB',
          'Andre King · 24 PTS · 6 AST',
        ],
        shareText: 'Share text',
        fileName: 'box-score.png',
        teams: [
          BrandedShareTeam(name: 'St George’s Slayers', score: 82),
          BrandedShareTeam(name: 'UWI Running Rebels', score: 76),
        ],
      ),
      BrandedSharePayload(
        title: 'Player spotlight',
        eyebrow: 'PLAYER SPOTLIGHT',
        headline: 'Jordan Brown owns the night',
        detail: '28 PTS · 8 REB · 6 AST',
        shareText: 'Share text',
        fileName: 'player.png',
        teams: [BrandedShareTeam(name: 'St George’s Slayers')],
      ),
      BrandedSharePayload(
        title: 'Team stats',
        eyebrow: 'TEAM FORM',
        headline: 'The Slayers have won four straight',
        detail: 'League-leading defense · 84.2 points per game',
        shareText: 'Share text',
        fileName: 'team.png',
        teams: [BrandedShareTeam(name: 'St George’s Slayers')],
      ),
      BrandedSharePayload(
        title: 'Standings',
        eyebrow: 'STANDINGS',
        headline: 'St George’s Slayers lead the National Basketball League',
        detail: '#1 Slayers · 8-1\n#2 Raptors · 7-2\n#3 Rebels · 6-3',
        shareText: 'Share text',
        fileName: 'standings.png',
      ),
      BrandedSharePayload(
        title: 'League leaders',
        eyebrow: 'SCORING LEADERS',
        headline: 'Jordan Brown sets the pace',
        detail: '#1 Brown · 24.8\n#2 King · 22.4\n#3 Grant · 20.1',
        shareText: 'Share text',
        fileName: 'leaders.png',
      ),
    ];

    for (final payload in payloads) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BrandedShareCard(branding: branding, payload: payload),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      if (payload.isPlayerSpotlight) {
        final gridBottom = tester
            .getBottomLeft(find.byKey(const Key('spotlight-stat-grid')))
            .dy;
        final footerTop = tester
            .getTopLeft(find.byKey(const Key('share-card-footer')))
            .dy;
        expect(footerTop - gridBottom, closeTo(9, 0.1));
        expect(tester.takeException(), isNull);
        continue;
      }
      final headerBottom = tester
          .getBottomLeft(find.byKey(const Key('share-card-brand-header')))
          .dy;
      final panelTop = tester
          .getTopLeft(find.byKey(const Key('share-card-content-panel')))
          .dy;
      final panelBottom = tester
          .getBottomLeft(find.byKey(const Key('share-card-content-panel')))
          .dy;
      final footerTop = tester
          .getTopLeft(find.byKey(const Key('share-card-footer')))
          .dy;

      expect(panelTop - headerBottom, inInclusiveRange(8.5, 9.5));
      expect(footerTop - panelBottom, inInclusiveRange(3.5, 4.5));
      expect(tester.takeException(), isNull, reason: payload.title);
    }
  });

  testWidgets('box score separates real periods and performers', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      leagueName: 'National Basketball League',
      logoUrl: 'asset:assets/images/nbl_jamaica_logo.png',
    );
    const payload = BrandedSharePayload(
      title: 'Box score',
      eyebrow: 'BOX SCORE',
      headline: 'Andre Blake leads',
      detail: '1: 21-18 · 2: 19-20\nAndre Blake · 40 PTS',
      shareText: 'Published result',
      fileName: 'box.png',
      divisionLabel: 'Premier',
      periodScoreLine: '1: 21-18 · 2: 19-20',
      performerLines: ['Andre Blake · 40 PTS'],
      teams: [
        BrandedShareTeam(name: 'St George’s Slayers', score: 82),
        BrandedShareTeam(name: 'UWI Running Rebels', score: 76),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(branding: branding, payload: payload),
            ),
          ),
        ),
      ),
    );
    expect(find.text('PREMIER'), findsOneWidget);
    expect(find.text('QUARTER SCORES'), findsOneWidget);
    expect(find.text('TOP PERFORMERS'), findsOneWidget);
    expect(find.text('1: 21-18 · 2: 19-20'), findsOneWidget);
    expect(find.text('Andre Blake · 40 PTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('media card keeps the story hook and action visible', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      leagueName: 'National Basketball League',
    );
    const payload = BrandedSharePayload(
      title: 'Opening night story',
      eyebrow: 'NEWS',
      headline: 'NBL opening night sets the tone',
      detail:
          'St George’s Slayers and UWI Running Rebels delivered a close presentation matchup at the National Indoor Sports Centre. Open the published game to review the score, quarter totals, and player box score.',
      shareText: 'Story and public link',
      fileName: 'story.png',
      sourceLabel: 'Published league media',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(branding: branding, payload: payload),
            ),
          ),
        ),
      ),
    );
    expect(find.text('NBL opening night sets the tone'), findsOneWidget);
    expect(find.text('READ THE STORY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports confirmed image share success', (tester) async {
    final actions = _FakeShareActions();
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();

    expect(actions.imageCalls, 1);
    expect(actions.textCalls, 0);
    expect(find.text('Share completed'), findsOneWidget);
  });

  testWidgets('falls back to text when image sharing fails', (tester) async {
    final actions = _FakeShareActions(imageError: StateError('image denied'));
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();

    expect(actions.imageCalls, 1);
    expect(actions.textCalls, 1);
    expect(find.text('Text shared'), findsOneWidget);
    expect(find.textContaining('image was unavailable'), findsOneWidget);
  });

  testWidgets('does not claim success when both share attempts fail', (
    tester,
  ) async {
    final actions = _FakeShareActions(
      imageError: StateError('image denied'),
      textError: StateError('text denied'),
    );
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();

    expect(find.text('Could not share'), findsOneWidget);
    expect(find.text('Share completed'), findsNothing);
    expect(find.text('Text shared'), findsNothing);
  });

  testWidgets('distinguishes canceled and unconfirmed share outcomes', (
    tester,
  ) async {
    final dismissed = _FakeShareActions(
      imageResult: const ShareResult('', ShareResultStatus.dismissed),
    );
    await _pumpSheet(tester, dismissed);
    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share canceled'), findsOneWidget);
    expect(find.text('Share completed'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    final unknown = _FakeShareActions(imageResult: ShareResult.unavailable);
    await _pumpSheet(tester, unknown);
    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();
    expect(find.text('Share outcome unknown'), findsOneWidget);
    expect(find.text('Share completed'), findsNothing);
  });

  testWidgets('reports copy and image-save failures without false success', (
    tester,
  ) async {
    final actions = _FakeShareActions(
      copyError: StateError('clipboard denied'),
      downloadError: StateError('download denied'),
    );
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy text'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy'), findsOneWidget);
    expect(find.text('Text copied'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save image'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.text('Image save started'), findsNothing);
  });

  testWidgets('reports only a platform-accepted image save', (tester) async {
    final actions = _FakeShareActions();
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save image'));
    await tester.pumpAndSettle();

    expect(find.text('Image save started'), findsOneWidget);
    expect(find.text('The platform accepted result.png.'), findsOneWidget);
  });

  testWidgets('reports mobile image saved to the visible Gallery', (
    tester,
  ) async {
    await _pumpSheet(tester, _FakeShareActions(downloadDestination: 'Gallery'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save image'));
    await tester.pumpAndSettle();

    expect(find.text('Image saved'), findsOneWidget);
    expect(find.text('Saved to Gallery.'), findsOneWidget);
  });

  testWidgets('copy confirmation stays neutral about publication status', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      _FakeShareActions(),
      payload: ShareDemoSamples.boxScore,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy text'));
    await tester.pumpAndSettle();

    expect(find.text('The share text is on your clipboard.'), findsOneWidget);
    expect(find.textContaining('published result text'), findsNothing);
  });

  testWidgets('feature-detects an unsupported download platform', (
    tester,
  ) async {
    await _pumpSheet(tester, _FakeShareActions(downloadSupported: false));

    expect(find.widgetWithText(OutlinedButton, 'Save image'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Copy text'), findsOneWidget);
  });

  testWidgets('disables duplicate actions while a share is pending', (
    tester,
  ) async {
    final pending = Completer<ShareResult>();
    final actions = _FakeShareActions(imageFuture: pending.future);
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pump();

    final shareButton = tester.widget<FilledButton>(find.byType(FilledButton));
    final copyButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Copy text'),
    );
    expect(shareButton.onPressed, isNull);
    expect(copyButton.onPressed, isNull);
    expect(actions.imageCalls, 1);

    pending.complete(const ShareResult('completed', ShareResultStatus.success));
    await tester.pumpAndSettle();
    expect(actions.imageCalls, 1);
  });

  testWidgets('retraction before an action cancels and disables the sheet', (
    tester,
  ) async {
    final actions = _FakeShareActions();
    await _pumpSheet(
      tester,
      actions,
      validateCurrent: () async => throw StateError('retracted'),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy text'));
    await tester.pumpAndSettle();

    expect(actions.copyCalls, 0);
    expect(find.text('Publication changed'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Copy text'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('offline validation cancels with connection guidance', (
    tester,
  ) async {
    final actions = _FakeShareActions();
    await _pumpSheet(
      tester,
      actions,
      validateCurrent: () async => throw StateError('server unavailable'),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy text'));
    await tester.pumpAndSettle();

    expect(actions.copyCalls, 0);
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });

  testWidgets('retryable server failure does not permanently gray the sheet', (
    tester,
  ) async {
    var validations = 0;
    final actions = _FakeShareActions();
    await _pumpSheet(
      tester,
      actions,
      validateCurrent: () async {
        if (++validations == 1) {
          throw const PublicArtifactReleaseException(
            'Server unavailable',
            retryable: true,
          );
        }
      },
    );

    final copyButton = find.widgetWithText(OutlinedButton, 'Copy text');
    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(actions.copyCalls, 0);
    expect(find.text('Connection needed'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);

    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(actions.copyCalls, 1);
    expect(find.text('Text copied'), findsOneWidget);
  });

  testWidgets('version change during share suppresses a stale success claim', (
    tester,
  ) async {
    var validations = 0;
    final actions = _FakeShareActions();
    await _pumpSheet(
      tester,
      actions,
      validateCurrent: () async {
        validations++;
        if (validations == 3) throw StateError('changed');
      },
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();

    expect(actions.imageCalls, 1);
    expect(find.text('Publication changed during action'), findsOneWidget);
    expect(find.text('Share completed'), findsNothing);
    expect(
      find.textContaining('may already contain the older artifact'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BrandedShareActions actions, {
  Future<void> Function()? validateCurrent,
  BrandedSharePayload? payload,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const defaultPayload = BrandedSharePayload(
    title: 'Published result',
    headline: 'Home defeats Away 82-79',
    detail: 'A close game.',
    shareText: 'Published text',
    fileName: 'result.png',
    sourceLabel: 'Published league result',
    versionLabel: 'Publication abc123',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BrandedShareSheet(
          branding: AssociationBrandingModel.jba(),
          payload: payload ?? defaultPayload,
          actions: actions,
          validateCurrent: validateCurrent,
          captureImage: () async => Uint8List.fromList([1, 2, 3]),
        ),
      ),
    ),
  );
}

class _FakeShareActions implements BrandedShareActions {
  final ShareResult imageResult;
  final Object? imageError;
  final Object? textError;
  final Object? copyError;
  final Object? downloadError;
  final Future<ShareResult>? imageFuture;
  final bool downloadSupported;
  final String? downloadDestination;

  int imageCalls = 0;
  int textCalls = 0;
  int copyCalls = 0;
  int downloadCalls = 0;

  _FakeShareActions({
    this.imageResult = const ShareResult(
      'completed',
      ShareResultStatus.success,
    ),
    this.imageError,
    this.textError,
    this.copyError,
    this.downloadError,
    this.imageFuture,
    this.downloadSupported = true,
    this.downloadDestination,
  });

  @override
  bool get canDownload => downloadSupported;

  @override
  Future<ShareResult> shareImage({
    required String title,
    required String text,
    required String fileName,
    required Uint8List imageBytes,
    Rect? sharePositionOrigin,
  }) async {
    imageCalls++;
    if (imageError != null) throw imageError!;
    if (imageFuture != null) return imageFuture!;
    return imageResult;
  }

  @override
  Future<ShareResult> shareText({
    required String title,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    textCalls++;
    if (textError != null) throw textError!;
    return const ShareResult('completed', ShareResultStatus.success);
  }

  @override
  Future<void> copyText(String text) async {
    copyCalls++;
    if (copyError != null) throw copyError!;
  }

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    downloadCalls++;
    if (downloadError != null) throw downloadError!;
    return downloadDestination ?? fileName;
  }
}
