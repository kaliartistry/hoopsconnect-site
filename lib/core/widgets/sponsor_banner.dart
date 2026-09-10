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
    return Semantics(
      button: website != null,
      label: '${sponsor.label} ${sponsor.name}',
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
                  CachedNetworkImage(
                    imageUrl: sponsor.logoUrl!,
                    width: 34,
                    height: 24,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${sponsor.label} ',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        TextSpan(
                          text: sponsor.name,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
