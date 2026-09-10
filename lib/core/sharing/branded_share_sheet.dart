import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/association_branding_model.dart';
import '../constants/app_constants.dart';
import 'branded_share_payload.dart';

Future<void> showBrandedShareSheet({
  required BuildContext context,
  required AssociationBrandingModel branding,
  required BrandedSharePayload payload,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BrandedShareSheet(branding: branding, payload: payload),
  );
}

class BrandedShareSheet extends StatefulWidget {
  final AssociationBrandingModel branding;
  final BrandedSharePayload payload;

  const BrandedShareSheet({
    super.key,
    required this.branding,
    required this.payload,
  });

  @override
  State<BrandedShareSheet> createState() => _BrandedShareSheetState();
}

class _BrandedShareSheetState extends State<BrandedShareSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

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
                  'Share this result',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Share to WhatsApp, Instagram, X, and more.',
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                  label: Text(_sharing ? 'Preparing card…' : 'Share'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy text'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      if (boundary == null) {
        await _shareText(origin);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        await _shareText(origin);
        return;
      }

      await SharePlus.instance.share(
        ShareParams(
          title: widget.payload.title,
          subject: widget.payload.title,
          text: widget.payload.shareText,
          files: [
            XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: [widget.payload.fileName],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      await _shareText(null);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText(Rect? origin) {
    return SharePlus.instance.share(
      ShareParams(
        title: widget.payload.title,
        subject: widget.payload.title,
        text: widget.payload.shareText,
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.payload.shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Share text copied')));
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
                    const Text(
                      'FINAL',
                      style: TextStyle(
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
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'HOOPSCONNECT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Official league result',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
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
