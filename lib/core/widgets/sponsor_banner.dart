import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/association_branding_model.dart';
import '../../providers/association_branding_providers.dart';

class SponsorBanner extends ConsumerWidget {
  final EdgeInsetsGeometry margin;
  final AssociationBrandingModel? branding;

  const SponsorBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(12, 6, 12, 0),
    this.branding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrideBranding = branding;
    final AssociationBrandingModel effectiveBranding =
        overrideBranding ?? ref.watch(effectiveAssociationBrandingProvider);
    final sponsor = effectiveBranding.sponsor;
    if (!sponsor.isActive) return const SizedBox.shrink();

    final website = sponsor.websiteUrl == null
        ? null
        : Uri.tryParse(sponsor.websiteUrl!);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Semantics(
      button: website != null,
      label: 'Association partner: ${sponsor.name}',
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: effectiveBranding.primaryColor.withValues(alpha: 0.08),
          border: Border.all(
            color: effectiveBranding.primaryColor.withValues(alpha: 0.22),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: website == null
              ? null
              : () => launchUrl(website, mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (sponsor.logoUrl != null) ...[
                  SponsorLogo(
                    reference: sponsor.logoUrl!,
                    semanticLabel: '${sponsor.name} logo',
                    width: sponsorPlateWidth(
                      sponsor.logoUrl!,
                      compact: compact,
                    ),
                    height: compact ? 36 : 44,
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ASSOCIATION PARTNER',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        sponsor.name,
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (website != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new, size: 15),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double sponsorPlateWidth(String reference, {required bool compact}) {
  final normalized = reference.toLowerCase();
  if (normalized.contains('bank_of_kingston')) return compact ? 116 : 148;
  if (normalized.contains('yardcourt')) return compact ? 107 : 137;
  if (normalized.contains('kingston_flame')) return compact ? 91 : 116;
  if (normalized.contains('shipsafe')) return compact ? 102 : 130;
  return compact ? 104 : 132;
}

class SponsorLogo extends StatelessWidget {
  const SponsorLogo({
    super.key,
    required this.reference,
    required this.width,
    required this.height,
    this.semanticLabel,
    this.onPlate = true,
    this.platePadding,
  });

  final String reference;
  final double width;
  final double height;
  final String? semanticLabel;
  final bool onPlate;
  final EdgeInsetsGeometry? platePadding;

  @override
  Widget build(BuildContext context) {
    final fallback = _LogoFallback(label: semanticLabel);
    final Widget image;
    if (reference.startsWith('asset:')) {
      image = Image.asset(
        reference.substring('asset:'.length),
        excludeFromSemantics: true,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: reference,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      );
    }

    final content = SizedBox(
      width: width,
      height: height,
      child: onPlate
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.14)
                      : const Color(0xFFC2C9BD),
                ),
              ),
              child: Padding(
                padding:
                    platePadding ??
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: image,
              ),
            )
          : image,
    );
    return Semantics(
      image: true,
      label: semanticLabel ?? 'Sponsor logo',
      child: ExcludeSemantics(child: content),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final initials = _logoInitials(label);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF184A9E),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFE7BC5A),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }
}

String _logoInitials(String? label) {
  final words = (label ?? 'HoopsConnect')
      .replaceAll(RegExp(r"[^A-Za-z0-9’']+"), ' ')
      .split(' ')
      .where((word) {
        final normalized = word.toLowerCase();
        return word.isNotEmpty &&
            normalized != 'logo' &&
            normalized != 'team' &&
            normalized != 'sponsor' &&
            normalized != 'main';
      })
      .toList(growable: false);
  if (words.isEmpty) return 'HC';
  return words.take(3).map((word) => word[0].toUpperCase()).join();
}
