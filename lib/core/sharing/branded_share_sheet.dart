import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/association_branding_model.dart';
import '../../services/public_artifact_release_validator.dart';
import '../constants/app_constants.dart';
import '../widgets/app_state_message.dart';
import '../widgets/sponsor_banner.dart';
import 'branded_share_actions.dart';
import 'branded_share_payload.dart';
import 'player_spotlight_layout.dart';

const _shareDisplayFontFamily = 'BarlowCondensed';

const _shareSilverGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFFFFFFF),
    Color(0xFFF4F7FC),
    Color(0xFFBFCBDF),
    Color(0xFFF9FBFF),
    Color(0xFFA6B4CB),
  ],
  stops: [0, 0.24, 0.49, 0.57, 1],
);

Future<void> showBrandedShareSheet({
  required BuildContext context,
  required AssociationBrandingModel branding,
  required BrandedSharePayload payload,
  Future<void> Function()? validateCurrent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BrandedShareSheet(
      branding: branding,
      payload: payload,
      validateCurrent: validateCurrent,
    ),
  );
}

class BrandedShareSheet extends StatefulWidget {
  final AssociationBrandingModel branding;
  final BrandedSharePayload payload;
  final BrandedShareActions? actions;
  final Future<Uint8List> Function()? captureImage;
  final Future<void> Function()? validateCurrent;

  const BrandedShareSheet({
    super.key,
    required this.branding,
    required this.payload,
    this.actions,
    this.captureImage,
    this.validateCurrent,
  });

  @override
  State<BrandedShareSheet> createState() => _BrandedShareSheetState();
}

enum _ShareBusy { share, copy, download }

class _BrandedShareSheetState extends State<BrandedShareSheet> {
  final _cardKey = GlobalKey();
  late final BrandedShareActions _actions;
  _ShareBusy? _busy;
  String? _messageTitle;
  String? _message;
  AppStateTone _messageTone = AppStateTone.neutral;
  bool _validationFailed = false;

  @override
  void initState() {
    super.initState();
    _actions = widget.actions ?? PlatformBrandedShareActions();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSizes.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.payload.sheetTitle,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('close-share-sheet'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close share options',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF0F3F8),
                      foregroundColor: const Color(0xFF10264B),
                    ),
                    icon: const Icon(Icons.close, color: Color(0xFF10264B)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.paddingMd,
                  4,
                  AppSizes.paddingMd,
                  AppSizes.paddingMd + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Choose Share, copy the text, or save the image.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        RepaintBoundary(
                          key: _cardKey,
                          child: BrandedShareCard(
                            branding: widget.branding,
                            payload: widget.payload,
                          ),
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          AppStateMessage(
                            title: _messageTitle!,
                            message: _message!,
                            tone: _messageTone,
                            compact: true,
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy == null && !_validationFailed
                              ? _share
                              : null,
                          icon: _busy == _ShareBusy.share
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.ios_share),
                          label: Text(
                            _busy == _ShareBusy.share
                                ? 'Preparing card…'
                                : 'Share',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy == null && !_validationFailed
                              ? _copy
                              : null,
                          icon: _busy == _ShareBusy.copy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.copy_outlined),
                          label: Text(
                            _busy == _ShareBusy.copy ? 'Copying…' : 'Copy text',
                          ),
                        ),
                        if (_actions.canDownload) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy == null && !_validationFailed
                                ? _download
                                : null,
                            icon: _busy == _ShareBusy.download
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_alt_outlined),
                            label: Text(
                              _busy == _ShareBusy.download
                                  ? 'Saving image…'
                                  : 'Save image',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() {
      _busy = _ShareBusy.share;
      _message = null;
    });
    Object? imageFailure;
    try {
      if (!await _validateCurrent()) return;
      final origin = _shareOrigin;
      Uint8List? imageBytes;
      try {
        imageBytes = await _capturePng();
      } catch (error) {
        imageFailure = error;
      }

      if (imageBytes != null) {
        if (!await _validateCurrent()) return;
        try {
          final result = await _actions.shareImage(
            title: widget.payload.title,
            text: widget.payload.shareText,
            fileName: widget.payload.fileName,
            imageBytes: imageBytes,
            sharePositionOrigin: origin,
          );
          if (!await _validateCurrent(actionMayHaveCompleted: true)) return;
          _reportShareResult(result, textFallback: false);
          return;
        } catch (error) {
          imageFailure = error;
        }
      }

      try {
        if (!await _validateCurrent()) return;
        final result = await _actions.shareText(
          title: widget.payload.title,
          text: widget.payload.shareText,
          sharePositionOrigin: origin,
        );
        if (!await _validateCurrent(actionMayHaveCompleted: true)) return;
        _reportShareResult(result, textFallback: imageFailure != null);
        return;
      } catch (_) {
        _setMessage(
          title: 'Could not share',
          message:
              'Neither the image nor text could be shared. Copy the text or save the image instead.',
          tone: AppStateTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Rect? get _shareOrigin {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _copy() async {
    setState(() {
      _busy = _ShareBusy.copy;
      _message = null;
    });
    try {
      if (!await _validateCurrent()) return;
      await _actions.copyText(widget.payload.shareText);
      if (!await _validateCurrent(actionMayHaveCompleted: true)) return;
      _setMessage(
        title: 'Text copied',
        message: 'The share text is on your clipboard.',
        tone: AppStateTone.success,
      );
    } catch (_) {
      _setMessage(
        title: 'Could not copy',
        message: 'Clipboard access was denied. Try Share or Save image.',
        tone: AppStateTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = _ShareBusy.download;
      _message = null;
    });
    try {
      if (!await _validateCurrent()) return;
      final bytes = await _capturePng();
      if (!await _validateCurrent()) return;
      final destination = await _actions.download(
        bytes: bytes,
        fileName: widget.payload.fileName,
        mimeType: 'image/png',
      );
      if (!await _validateCurrent(actionMayHaveCompleted: true)) return;
      _setMessage(
        title: destination == 'Photos' || destination == 'Gallery'
            ? 'Image saved'
            : 'Image save started',
        message: destination == 'Photos' || destination == 'Gallery'
            ? 'Saved to $destination.'
            : 'The platform accepted $destination.',
        tone: AppStateTone.success,
      );
    } catch (_) {
      _setMessage(
        title: 'Could not save',
        message: 'The image was not saved. Try again or use Copy text.',
        tone: AppStateTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<Uint8List> _capturePng() async {
    if (widget.captureImage != null) return widget.captureImage!();
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Share card is not ready.');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Share card image could not be encoded.');
    }
    return bytes.buffer.asUint8List();
  }

  Future<bool> _validateCurrent({bool actionMayHaveCompleted = false}) async {
    final validator = widget.validateCurrent;
    if (validator == null) return true;
    try {
      await validator();
      return true;
    } catch (error) {
      if (!mounted) return false;
      final canRetry =
          error is PublicArtifactReleaseException && error.retryable;
      if (!canRetry) setState(() => _validationFailed = true);
      _setMessage(
        title: canRetry
            ? 'Connection needed'
            : actionMayHaveCompleted
            ? 'Publication changed during action'
            : 'Publication changed',
        message: canRetry
            ? actionMayHaveCompleted
                  ? 'The platform may have received the card, but its current publication could not be checked. Do not distribute it yet. Reconnect and try again.'
                  : 'The current public data could not be checked. Reconnect and try again; this card has not been shared.'
            : actionMayHaveCompleted
            ? 'The platform may already contain the older artifact. Do not distribute it. Refresh this view for the current public release.'
            : 'This action was canceled because the current public release could not be verified with the server or changed. Check your connection and refresh this view before sharing.',
        tone: AppStateTone.error,
      );
      return false;
    }
  }

  void _reportShareResult(ShareResult result, {required bool textFallback}) {
    switch (result.status) {
      case ShareResultStatus.success:
        _setMessage(
          title: textFallback ? 'Text shared' : 'Share completed',
          message: textFallback
              ? 'The image was unavailable, so HoopsConnect shared the text instead.'
              : 'The platform reported that the share card was shared.',
          tone: AppStateTone.success,
        );
      case ShareResultStatus.dismissed:
        _setMessage(
          title: 'Share canceled',
          message: 'Nothing was reported as shared.',
          tone: AppStateTone.neutral,
        );
      case ShareResultStatus.unavailable:
        _setMessage(
          title: 'Share outcome unknown',
          message: textFallback
              ? 'The image was unavailable and the platform did not confirm whether the text was sent.'
              : 'The platform did not confirm whether the card was sent. Use Copy or Save image if you need a confirmed artifact.',
          tone: AppStateTone.info,
        );
    }
  }

  void _setMessage({
    required String title,
    required String message,
    required AppStateTone tone,
  }) {
    if (!mounted) return;
    setState(() {
      _messageTitle = title;
      _message = message;
      _messageTone = tone;
    });
  }
}

class BrandedShareCard extends StatelessWidget {
  final AssociationBrandingModel branding;
  final BrandedSharePayload payload;

  const BrandedShareCard({
    super.key,
    required this.branding,
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    final sponsor = branding.sponsor;
    final isBoxScore = payload.eyebrow.toUpperCase().contains('BOX SCORE');
    final isMedia = payload.sourceLabel == 'Published league media';
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: 360,
          height: 450,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(branding.secondaryColor, Colors.black, 0.48)!,
                  Color.lerp(branding.primaryColor, Colors.black, 0.14)!,
                  Color.lerp(branding.primaryColor, Colors.black, 0.52)!,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66030B1C),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/share_arena_background.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xB3081733),
                            Color(0x6B071A3A),
                            Color(0x94030E22),
                          ],
                          stops: [0, 0.52, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BroadcastBackdropPainter(
                        accentColor: branding.accentColor,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 3,
                      color: branding.accentColor.withValues(alpha: 0.9),
                    ),
                  ),
                  if (payload.isPlayerSpotlight)
                    Positioned(
                      left: 17,
                      right: 17,
                      top: 8,
                      bottom: 76,
                      child: PlayerSpotlightLayout(
                        branding: branding,
                        payload: payload,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(17, 13, 17, 71),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShareBrandHeader(
                            key: const Key('share-card-brand-header'),
                            branding: branding,
                            divisionLabel: payload.divisionLabel,
                          ),
                          const SizedBox(height: 9),
                          Expanded(
                            child: _SharePayloadBody(
                              key: const Key('share-card-content-panel'),
                              branding: branding,
                              payload: payload,
                              isBoxScore: isBoxScore,
                              isMedia: isMedia,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 67,
                    child: _ShareSponsorRail(
                      key: const Key('share-card-footer'),
                      branding: branding,
                      sponsor: sponsor,
                      sourceLabel: payload.sourceLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareBrandHeader extends StatelessWidget {
  const _ShareBrandHeader({
    super.key,
    required this.branding,
    required this.divisionLabel,
  });

  final AssociationBrandingModel branding;
  final String? divisionLabel;

  @override
  Widget build(BuildContext context) {
    final showsLeague =
        branding.leagueName.trim().toLowerCase() !=
        'jamaica basketball association';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SponsorLogo(
              reference: 'asset:assets/images/jba_logo.png',
              semanticLabel: 'Jamaica Basketball Association crest',
              width: 32,
              height: 32,
              onPlate: false,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'JAMAICA BASKETBALL ASSOCIATION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFDCE5F5),
                  fontSize: 9.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.55,
                ),
              ),
            ),
          ],
        ),
        if (showsLeague) ...[
          const SizedBox(height: 8),
          _ShareLeagueLockup(branding: branding, divisionLabel: divisionLabel),
        ],
      ],
    );
  }
}

class _SharePayloadBody extends StatelessWidget {
  const _SharePayloadBody({
    super.key,
    required this.branding,
    required this.payload,
    required this.isBoxScore,
    required this.isMedia,
  });

  final AssociationBrandingModel branding;
  final BrandedSharePayload payload;
  final bool isBoxScore;
  final bool isMedia;

  @override
  Widget build(BuildContext context) {
    if (isMedia) {
      return _ShareMediaBody(
        payload: payload,
        accentColor: branding.accentColor,
      );
    }
    if (payload.comparisonRows.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShareTitleRule(
            title: payload.eyebrow,
            accentColor: branding.accentColor,
            compact: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final player in payload.teams)
                Expanded(
                  child: Column(
                    children: [
                      if (player.logoUrl != null)
                        SponsorLogo(
                          reference: player.logoUrl!,
                          semanticLabel: '${player.name} team logo',
                          width: 40,
                          height: 40,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        player.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            payload.detail,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                for (final row in payload.comparisonRows)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xB305152D),
                        border: Border(
                          bottom: BorderSide(
                            color: branding.accentColor.withValues(alpha: 0.25),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.$2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              row.$1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: branding.accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.$3,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    if (payload.tableRows.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShareTitleRule(
            title: payload.eyebrow,
            accentColor: branding.accentColor,
            compact: true,
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'TEAM',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  'W',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 8),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  'L',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 8),
                ),
              ),
              SizedBox(
                width: 49,
                child: Text(
                  'LEAGUE PTS',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                for (final row in payload.tableRows)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x9905152D),
                        border: Border(
                          bottom: BorderSide(
                            color: branding.accentColor.withValues(alpha: 0.24),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (row.logoUrl != null) ...[
                            SponsorLogo(
                              reference: row.logoUrl!,
                              semanticLabel: '${row.name} logo',
                              width: 18,
                              height: 18,
                            ),
                            const SizedBox(width: 7),
                          ],
                          Expanded(
                            child: Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final record in [row.wins, row.losses])
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${record ?? '—'}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              row.value,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: branding.accentColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            payload.tableRows.any(
                  (row) => row.wins == null || row.losses == null,
                )
                ? 'Equal points remain tied · — Not supplied'
                : 'Equal points remain tied',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 8),
          ),
        ],
      );
    }
    final hasDetail =
        payload.detail.isNotEmpty && payload.detail != payload.headline;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShareTitleRule(
          title: payload.eyebrow,
          accentColor: branding.accentColor,
          compact: isBoxScore,
        ),
        SizedBox(height: isBoxScore ? 5 : 7),
        if (payload.teams.length >= 2)
          _ShareMatchup(
            teams: payload.teams.take(2).toList(),
            accentColor: branding.accentColor,
            compact: isBoxScore,
            dense: isBoxScore && payload.isDemonstration,
          )
        else if (payload.teams.length == 1)
          _ShareSpotlightIdentity(
            team: payload.teams.single,
            headline: payload.headline,
          )
        else
          Text(
            payload.headline,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontFamily: _shareDisplayFontFamily,
              fontSize: 29,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        if (isBoxScore) ...[
          const SizedBox(height: 7),
          _ShareStatPanel(
            periodScoreLine: payload.periodScoreLine,
            performerLines: payload.performerLines,
            detail: payload.detail,
            accentColor: branding.accentColor,
          ),
        ] else if (hasDetail) ...[
          SizedBox(height: payload.teams.length >= 2 ? 3 : 7),
          if (payload.teams.length >= 2)
            _ShareResultNote(
              detail: payload.detail,
              versionLabel: payload.versionLabel,
              accentColor: branding.accentColor,
            )
          else if (payload.isDemonstration &&
              (payload.teams.length == 1 ||
                  payload.eyebrow.toUpperCase().contains('LEADERS')))
            _ShareDemoStatsPanel(
              detail: payload.detail,
              accentColor: branding.accentColor,
              isPlayer: payload.teams.length == 1,
            )
          else if (payload.teams.length < 2)
            _ShareDetailDeck(
              detail: payload.detail,
              accentColor: branding.accentColor,
              splitBullets: payload.teams.length == 1,
            ),
        ],
      ],
    );
  }
}

class _ShareMediaBody extends StatelessWidget {
  const _ShareMediaBody({required this.payload, required this.accentColor});

  final BrandedSharePayload payload;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      _ShareTitleRule(
        title: payload.eyebrow,
        accentColor: accentColor,
        compact: false,
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(17, 12, 17, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xD6091933), Color(0xD20B2141)],
            ),
            border: Border.all(color: accentColor.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payload.headline,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: _shareDisplayFontFamily,
                  fontSize: 26,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 11),
              Container(height: 2, width: 50, color: accentColor),
              const SizedBox(height: 11),
              Text(
                payload.detail,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE4EBF8),
                  fontSize: 11.7,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(Icons.article_outlined, color: accentColor, size: 15),
                  const SizedBox(width: 6),
                  const Text(
                    'READ THE STORY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

class _ShareDemoStatsPanel extends StatelessWidget {
  const _ShareDemoStatsPanel({
    required this.detail,
    required this.accentColor,
    required this.isPlayer,
  });

  final String detail;
  final Color accentColor;
  final bool isPlayer;

  @override
  Widget build(BuildContext context) {
    final lines = detail
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final playerMetrics = lines.isEmpty
        ? <String>[]
        : lines.first.split(RegExp(r'\s*·\s*'));
    final leaderRows = lines.where((line) => line.contains(' · ')).take(2);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
      decoration: BoxDecoration(
        color: const Color(0xBD071832),
        border: Border(
          top: BorderSide(color: accentColor, width: 1.4),
          bottom: const BorderSide(color: Color(0x664180BF)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlayer)
            Row(
              children: [
                for (final metric in playerMetrics.take(3))
                  Expanded(child: _ShareDemoMetric(metric, accentColor)),
              ],
            )
          else
            for (final row in leaderRows) _ShareDemoLeaderRow(row, accentColor),
        ],
      ),
    );
  }
}

class _ShareDemoMetric extends StatelessWidget {
  const _ShareDemoMetric(this.metric, this.accentColor);

  final String metric;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final parts = metric.trim().split(RegExp(r'\s+'));
    final value = parts.isEmpty ? '—' : parts.first;
    final label = parts.skip(1).join(' ').toUpperCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: _shareSilverGradient.createShader,
          blendMode: BlendMode.srcIn,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: _shareDisplayFontFamily,
              fontSize: 35,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accentColor,
            fontSize: 8.2,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _ShareDemoLeaderRow extends StatelessWidget {
  const _ShareDemoLeaderRow(this.row, this.accentColor);

  final String row;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final parts = row.split(RegExp(r'\s*·\s*'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              parts.isEmpty ? '—' : parts.first,
              style: TextStyle(
                color: accentColor,
                fontFamily: _shareDisplayFontFamily,
                fontSize: 25,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              parts.length < 2 ? row : parts[1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: _shareDisplayFontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (parts.length > 2)
            Text(
              parts[2],
              style: const TextStyle(
                color: Color(0xFFF3F7FF),
                fontFamily: _shareDisplayFontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareDetailDeck extends StatelessWidget {
  const _ShareDetailDeck({
    required this.detail,
    required this.accentColor,
    required this.splitBullets,
  });

  final String detail;
  final Color accentColor;
  final bool splitBullets;

  @override
  Widget build(BuildContext context) {
    final normalized = splitBullets
        ? detail.replaceAll(RegExp(r'\s*·\s*'), '\n')
        : detail;
    final entries = normalized
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .take(8)
        .toList();
    final usesGrid = splitBullets && entries.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x9E08162F),
        border: Border(
          top: BorderSide(
            color: accentColor.withValues(alpha: 0.9),
            width: 1.3,
          ),
          bottom: const BorderSide(color: Color(0x3D5F87C8)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final entryWidth = usesGrid
              ? (constraints.maxWidth - 6) / 2
              : constraints.maxWidth;
          return Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            spacing: usesGrid ? 6 : 0,
            runSpacing: 3,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: entryWidth,
                  height: usesGrid ? 20 : 18,
                  child: Center(
                    child: Text(
                      entry,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: usesGrid ? 8.2 : 9,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ShareTitleRule extends StatelessWidget {
  const _ShareTitleRule({
    required this.title,
    required this.accentColor,
    required this.compact,
  });

  final String title;
  final Color accentColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final usesLongTitle = title.length > 11;
    Widget line() => Expanded(
      child: Container(height: 1.5, color: accentColor.withValues(alpha: 0.9)),
    );
    return Row(
      children: [
        line(),
        const SizedBox(width: 10),
        Flexible(
          fit: FlexFit.loose,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              shaderCallback: _shareSilverGradient.createShader,
              blendMode: BlendMode.srcIn,
              child: Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: _shareDisplayFontFamily,
                  fontSize: compact ? 45 : (usesLongTitle ? 25 : 43),
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? 1.6 : (usesLongTitle ? 1.1 : 2.5),
                  shadows: const [
                    Shadow(
                      color: Color(0x77000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        line(),
      ],
    );
  }
}

class _ShareResultNote extends StatelessWidget {
  const _ShareResultNote({
    required this.detail,
    required this.versionLabel,
    required this.accentColor,
  });

  final String detail;
  final String? versionLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(height: 2, width: 76, color: accentColor),
      const SizedBox(height: 6),
      Text(
        detail,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFEEF3FC),
          fontSize: 8.8,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      ),
      if (versionLabel != null) ...[
        const SizedBox(height: 3),
        Text(
          versionLabel!.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFB6C4DC),
            fontSize: 7.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
      ],
    ],
  );
}

class _ShareStatPanel extends StatelessWidget {
  const _ShareStatPanel({
    required this.detail,
    required this.accentColor,
    required this.periodScoreLine,
    required this.performerLines,
  });

  final String detail;
  final Color accentColor;
  final String? periodScoreLine;
  final List<String> performerLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xB20A1833),
        border: Border(
          top: BorderSide(
            color: accentColor.withValues(alpha: 0.95),
            width: 1.4,
          ),
          bottom: const BorderSide(color: Color(0x332D6EDB)),
          left: const BorderSide(color: Color(0x332D6EDB)),
          right: const BorderSide(color: Color(0x332D6EDB)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (periodScoreLine != null) ...[
            _ShareStatHeading('QUARTER SCORES', accentColor: accentColor),
            const SizedBox(height: 2),
            Text(
              periodScoreLine!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF1F5FC),
                fontSize: 10.2,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (performerLines.isNotEmpty) ...[
            if (periodScoreLine != null) ...[
              const SizedBox(height: 6),
              Container(height: 1, color: accentColor.withValues(alpha: 0.55)),
              const SizedBox(height: 6),
            ],
            _ShareStatHeading('TOP PERFORMERS', accentColor: accentColor),
            const SizedBox(height: 2),
            for (final line in performerLines.take(2))
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF1F5FC),
                  fontSize: 10.4,
                  height: 1.18,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
          if (periodScoreLine == null && performerLines.isEmpty)
            Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFF1F5FC),
                fontSize: 10.2,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareStatHeading extends StatelessWidget {
  const _ShareStatHeading(this.title, {required this.accentColor});

  final String title;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: accentColor,
      fontFamily: _shareDisplayFontFamily,
      fontSize: 12.5,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    ),
  );
}

class _ShareSponsorRail extends StatelessWidget {
  const _ShareSponsorRail({
    super.key,
    required this.branding,
    required this.sponsor,
    required this.sourceLabel,
  });

  final AssociationBrandingModel branding;
  final SponsorBrandingModel sponsor;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xE608142B),
        border: Border(top: BorderSide(color: branding.accentColor, width: 2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 35,
            decoration: BoxDecoration(
              color: branding.accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'HOOPSCONNECT',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: _shareDisplayFontFamily,
                      fontSize: 16,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.65,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9EACC4),
                    fontSize: 8.2,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (sponsor.isActive) ...[
            Container(width: 1, height: 35, color: const Color(0x52FFFFFF)),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  sponsor.label == 'Association partner'
                      ? 'ASSOCIATION PARTNER'
                      : sponsor.label == 'Main Sponsor'
                      ? 'MAIN SPONSOR'
                      : 'TITLE SPONSOR',
                  style: const TextStyle(
                    color: Color(0xFFC9D2E2),
                    fontSize: 7.4,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 3),
                if (sponsor.logoUrl != null)
                  SponsorLogo(
                    reference: sponsor.logoUrl!,
                    semanticLabel: '${sponsor.name} logo',
                    width: sponsorPlateWidth(sponsor.logoUrl!, compact: true),
                    height: 36,
                  )
                else
                  Text(
                    sponsor.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareMatchup extends StatelessWidget {
  const _ShareMatchup({
    required this.teams,
    required this.accentColor,
    required this.compact,
    this.dense = false,
  });

  final List<BrandedShareTeam> teams;
  final Color accentColor;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final firstScore = teams[0].score;
    final secondScore = teams[1].score;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _ShareTeamIdentity(
            team: teams[0],
            compact: compact,
            dense: dense,
            scoreEmphasis:
                firstScore == null ||
                secondScore == null ||
                firstScore >= secondScore,
          ),
        ),
        SizedBox(
          width: 28,
          height: dense ? 103 : (compact ? 123 : 173),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: 1.5,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: accentColor,
                    fontFamily: _shareDisplayFontFamily,
                    fontSize: compact ? 13 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: 1.5,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ShareTeamIdentity(
            team: teams[1],
            compact: compact,
            dense: dense,
            scoreEmphasis:
                firstScore == null ||
                secondScore == null ||
                secondScore >= firstScore,
          ),
        ),
      ],
    );
  }
}

class _ShareTeamIdentity extends StatelessWidget {
  const _ShareTeamIdentity({
    required this.team,
    required this.scoreEmphasis,
    required this.compact,
    this.dense = false,
  });

  final BrandedShareTeam team;
  final bool scoreEmphasis;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ShareTeamMark(team: team, size: dense ? 42 : (compact ? 49 : 64)),
        SizedBox(height: dense ? 2 : (compact ? 4 : 6)),
        SizedBox(
          height: dense ? 21 : (compact ? 25 : 30),
          child: Text(
            team.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontFamily: _shareDisplayFontFamily,
              fontSize: compact ? 13 : 15.2,
              height: 1.02,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.1,
              shadows: const [
                Shadow(
                  color: Color(0x80000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        if (team.score != null) ...[
          const SizedBox(height: 1),
          Transform.scale(
            scale: compact ? 1 : 1.16,
            child: ShaderMask(
              shaderCallback: _shareSilverGradient.createShader,
              blendMode: BlendMode.srcIn,
              child: Text(
                '${team.score}',
                style: TextStyle(
                  color: scoreEmphasis
                      ? const Color(0xFFF7F9FD)
                      : const Color(0xFFB5C0D2),
                  fontFamily: _shareDisplayFontFamily,
                  fontSize: dense ? 43 : (compact ? 49 : 78),
                  height: 0.88,
                  fontWeight: FontWeight.w900,
                  letterSpacing: compact ? -2 : -3.5,
                  shadows: const [
                    Shadow(
                      color: Color(0x99000000),
                      blurRadius: 7,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ShareSpotlightIdentity extends StatelessWidget {
  const _ShareSpotlightIdentity({required this.team, required this.headline});

  final BrandedShareTeam team;
  final String headline;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ShareTeamMark(team: team),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            headline,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: _shareDisplayFontFamily,
              fontSize: 25,
              height: 1.06,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShareTeamMark extends StatelessWidget {
  const _ShareTeamMark({required this.team, this.size = 53});

  final BrandedShareTeam team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoUrl = team.logoUrl;
    if (logoUrl != null) {
      return SponsorLogo(
        reference: logoUrl,
        semanticLabel: '${team.name} team logo',
        width: size,
        height: size,
        platePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      );
    }
    return Semantics(
      image: true,
      label: '${team.name} team mark',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFE4E8F0)],
            ),
            border: Border.all(color: const Color(0x99FFFFFF)),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 9,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            _shareInitials(team.name),
            style: TextStyle(
              color: Color(0xFF173A8C),
              fontFamily: _shareDisplayFontFamily,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareLeagueLockup extends StatelessWidget {
  const _ShareLeagueLockup({
    required this.branding,
    required this.divisionLabel,
  });

  final AssociationBrandingModel branding;
  final String? divisionLabel;

  @override
  Widget build(BuildContext context) {
    final logoUrl = branding.logoUrl;
    return Column(
      children: [
        Row(
          children: [
            if (logoUrl != null) ...[
              SponsorLogo(
                reference: logoUrl,
                semanticLabel: '${branding.leagueName} logo',
                width: 66,
                height: 54,
                platePadding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 2,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 23,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        branding.leagueName.toUpperCase(),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: _shareDisplayFontFamily,
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.25,
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 5,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (divisionLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      divisionLabel!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: branding.accentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                branding.accentColor.withValues(alpha: 0.95),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _shareInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2);
  final initials = words.map((word) => word[0]).join().toUpperCase();
  return initials.isEmpty ? 'T' : initials;
}

class _BroadcastBackdropPainter extends CustomPainter {
  const _BroadcastBackdropPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF2E6FFF).withValues(alpha: 0.34),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.88, size.height * 0.12),
              radius: size.width * 0.52,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);

    final beam = Path()
      ..moveTo(size.width * 0.72, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.78, size.height)
      ..lineTo(size.width * 0.58, size.height)
      ..close();
    canvas.drawPath(
      beam,
      Paint()..color = Colors.white.withValues(alpha: 0.035),
    );

    final courtPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF8EB5F2).withValues(alpha: 0.1);
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.76),
      size.width * 0.34,
      courtPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.66,
        size.height * 0.18,
        size.width * 0.52,
        size.height * 0.48,
      ),
      1.45,
      3.15,
      false,
      courtPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.82, size.height * 0.2),
      Offset(size.width * 0.82, size.height * 0.64),
      courtPaint,
    );

    final texturePaint = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var y = 18.0; y < size.height - 58; y += 12) {
      for (var x = 14.0; x < size.width; x += 12) {
        final offset = ((y ~/ 12).isEven ? 0.0 : 4.0);
        canvas.drawCircle(Offset(x + offset, y), 0.65, texturePaint);
      }
    }

    final accentPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      const Offset(10, 0),
      Offset(size.width * 0.22, 0),
      accentPaint,
    );
    canvas.drawLine(
      Offset(size.width - 42, 0),
      Offset(size.width, 28),
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BroadcastBackdropPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
}
