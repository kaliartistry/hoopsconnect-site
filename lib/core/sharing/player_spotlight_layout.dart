import 'package:flutter/material.dart';

import '../../models/association_branding_model.dart';
import '../widgets/sponsor_banner.dart';
import 'branded_share_payload.dart';

/// Fixed zones on the existing 360 x 450 design canvas. Preview and export
/// uniformly scale this canvas; no content-dependent reflow of the composition.
class PlayerSpotlightLayout extends StatelessWidget {
  const PlayerSpotlightLayout({
    super.key,
    required this.branding,
    required this.payload,
  });
  final AssociationBrandingModel branding;
  final BrandedSharePayload payload;

  @override
  Widget build(BuildContext context) {
    final team = payload.teams.isEmpty ? null : payload.teams.first;
    final values = payload.resolvedSpotlightStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const Key('spotlight-masthead'),
          height: 28,
          child: Row(
            children: [
              const SponsorLogo(
                reference: 'asset:assets/images/jba_logo.png',
                width: 25,
                height: 25,
                semanticLabel: 'Jamaica Basketball Association crest',
                onPlate: false,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'JAMAICA BASKETBALL ASSOCIATION',
                    style: TextStyle(
                      color: Color(0xFFDCE5F5),
                      fontSize: 9.3,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          key: const Key('spotlight-league'),
          height: 56,
          child: Row(
            children: [
              if (branding.logoUrl != null) ...[
                SponsorLogo(
                  reference: branding.logoUrl!,
                  width: 54,
                  height: 50,
                  semanticLabel: '${branding.leagueName} logo',
                  platePadding: const EdgeInsets.all(3),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _BoundedName(
                        text: branding.leagueName.toUpperCase(),
                        size: 23,
                        lines: 2,
                      ),
                    ),
                    if (payload.divisionLabel != null) ...[
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 12,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            payload.divisionLabel!.toUpperCase(),
                            style: TextStyle(
                              color: branding.accentColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          key: const Key('spotlight-title'),
          height: 20,
          child: Row(
            children: [
              Expanded(
                child: Divider(color: branding.accentColor, thickness: 1),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'PLAYER SPOTLIGHT',
                  style: TextStyle(
                    color: Color(0xFFE1E8F4),
                    fontFamily: 'BarlowCondensed',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: branding.accentColor, thickness: 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          key: const Key('spotlight-identity'),
          height: 60,
          child: Row(
            children: [
              if (team?.logoUrl != null) ...[
                SponsorLogo(
                  reference: team!.logoUrl!,
                  width: 52,
                  height: 52,
                  semanticLabel: '${team.name} team logo',
                ),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _BoundedName(
                        text: payload.headline,
                        size: 29,
                        lines: 2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      flex: 1,
                      child: _BoundedName(
                        text:
                            team?.name ??
                            payload.detail
                                .split('\n')
                                .first
                                .split('·')
                                .first
                                .trim(),
                        size: 12,
                        lines: 1,
                        color: const Color(0xFFBCCCDF),
                        display: false,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 6.0;
              final width = (constraints.maxWidth - gap) / 2;
              final height = (constraints.maxHeight - 2 * gap) / 3;
              return SizedBox(
                key: const Key('spotlight-stat-grid'),
                child: Column(
                  children: [
                    for (var row = 0; row < 3; row++) ...[
                      if (row > 0) const SizedBox(height: gap),
                      Row(
                        children: [
                          for (var col = 0; col < 2; col++) ...[
                            if (col > 0) const SizedBox(width: gap),
                            SizedBox(
                              width: width,
                              height: height,
                              child: _StatTile(
                                label: values.keys.elementAt(row * 2 + col),
                                value: values.values.elementAt(row * 2 + col),
                                accent: branding.accentColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.accent,
  });
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('spotlight-tile-$label'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xEE19365B), Color(0xDF07152D)],
      ),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.7),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: FittedBox(
            key: Key('spotlight-value-fit-$label'),
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(
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
              ).createShader(bounds),
              child: Text(
                value,
                key: Key('spotlight-value-$label'),
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: 10,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              key: Key('spotlight-label-$label'),
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shrink only the text inside this zone. Names never move the stat grid/footer.
class _BoundedName extends StatelessWidget {
  const _BoundedName({
    required this.text,
    required this.size,
    required this.lines,
    this.color = Colors.white,
    this.display = true,
  });
  final String text;
  final double size;
  final int lines;
  final Color color;
  final bool display;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final base = TextStyle(
        color: color,
        fontFamily: display ? 'BarlowCondensed' : null,
        fontSize: size,
        fontWeight: display ? FontWeight.w900 : FontWeight.w600,
        height: 1.05,
      );
      var chosen = size;
      while (chosen > 7) {
        final measure = TextPainter(
          text: TextSpan(
            text: text,
            style: base.copyWith(fontSize: chosen),
          ),
          textDirection: Directionality.of(context),
          maxLines: lines,
        );
        measure.layout(maxWidth: constraints.maxWidth);
        final fits =
            !measure.didExceedMaxLines &&
            measure.height <= constraints.maxHeight;
        measure.dispose();
        if (fits) break;
        chosen -= 0.5;
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(fontSize: chosen),
          textScaler: TextScaler.noScaling,
        ),
      );
    },
  );
}
