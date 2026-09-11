import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/association_branding_model.dart';
import '../constants/app_constants.dart';
import '../widgets/app_state_message.dart';
import 'branded_share_actions.dart';
import 'branded_share_payload.dart';

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
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSizes.paddingMd,
          12,
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
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share this published result',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose Share, copy the text, or save the image.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  label: Text(
                    _busy == _ShareBusy.share ? 'Preparing card…' : 'Share',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy == null && !_validationFailed ? _copy : null,
                  icon: _busy == _ShareBusy.copy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _busy == _ShareBusy.download
                          ? 'Saving image…'
                          : 'Download image',
                    ),
                  ),
                ],
              ],
            ),
          ),
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
              'Neither the image nor text could be shared. Copy the text or download the image instead.',
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
        message: 'The published result text is on your clipboard.',
        tone: AppStateTone.success,
      );
    } catch (_) {
      _setMessage(
        title: 'Could not copy',
        message: 'Clipboard access was denied. Try Share or Download image.',
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
        title: 'Image download started',
        message: 'The platform accepted $destination.',
        tone: AppStateTone.success,
      );
    } catch (_) {
      _setMessage(
        title: 'Could not download',
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
    } catch (_) {
      if (!mounted) return false;
      setState(() => _validationFailed = true);
      _setMessage(
        title: actionMayHaveCompleted
            ? 'Publication changed during action'
            : 'Publication changed',
        message: actionMayHaveCompleted
            ? 'The platform may already contain the older artifact. Do not distribute it. Refresh this view for the current public release.'
            : 'This action was canceled because the current public release could not be verified or changed. Refresh this view before sharing.',
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
              ? 'The image was unavailable, so HoopsConnect shared the published text instead.'
              : 'The platform reported that the published result was shared.',
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
              : 'The platform did not confirm whether the result was sent. Use Copy or Download if you need a confirmed artifact.',
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
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [branding.primaryColor, branding.secondaryColor],
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          child: Stack(
            children: [
              Positioned(
                right: -44,
                top: -34,
                child: _AccentCircle(
                  diameter: 180,
                  color: branding.accentColor.withValues(alpha: 0.22),
                ),
              ),
              Positioned(
                left: -58,
                bottom: -70,
                child: _AccentCircle(
                  diameter: 210,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sponsor.isActive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '${sponsor.label} ${sponsor.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      branding.leagueName.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: branding.accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      payload.eyebrow,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      payload.headline,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (payload.detail.isNotEmpty &&
                        payload.detail != payload.headline) ...[
                      const SizedBox(height: 14),
                      Text(
                        payload.detail,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 28,
                          decoration: BoxDecoration(
                            color: branding.accentColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'HOOPSCONNECT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              payload.sourceLabel,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                              ),
                            ),
                            if (payload.versionLabel != null)
                              Text(
                                payload.versionLabel!,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentCircle extends StatelessWidget {
  final double diameter;
  final Color color;

  const _AccentCircle({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
