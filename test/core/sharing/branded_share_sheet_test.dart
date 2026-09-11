import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_actions.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/branded_share_sheet.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  testWidgets('share card keeps league, sponsor, and app identity visible', (
    tester,
  ) async {
    final branding = AssociationBrandingModel.jba().copyWith(
      sponsor: const SponsorBrandingModel(enabled: true, name: 'KFC'),
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
    expect(find.text('Presented by KFC'), findsOneWidget);
    expect(find.text('HOOPSCONNECT'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.textContaining('87-72'), findsOneWidget);
    expect(find.text('League result'), findsOneWidget);
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

  testWidgets('reports copy and download failures without false success', (
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download image'));
    await tester.pumpAndSettle();
    expect(find.text('Could not download'), findsOneWidget);
    expect(find.text('Image download started'), findsNothing);
  });

  testWidgets('reports only a platform-accepted image download', (
    tester,
  ) async {
    final actions = _FakeShareActions();
    await _pumpSheet(tester, actions);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download image'));
    await tester.pumpAndSettle();

    expect(find.text('Image download started'), findsOneWidget);
    expect(find.text('The platform accepted result.png.'), findsOneWidget);
  });

  testWidgets('feature-detects an unsupported download platform', (
    tester,
  ) async {
    await _pumpSheet(tester, _FakeShareActions(downloadSupported: false));

    expect(find.widgetWithText(OutlinedButton, 'Download image'), findsNothing);
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
    expect(find.textContaining('may already contain the older artifact'), findsOneWidget);
  });
}

Future<void> _pumpSheet(
  WidgetTester tester,
  BrandedShareActions actions, {
  Future<void> Function()? validateCurrent,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const payload = BrandedSharePayload(
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
          payload: payload,
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
    return fileName;
  }
}
