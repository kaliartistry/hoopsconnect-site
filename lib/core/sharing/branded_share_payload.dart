import '../../models/association_branding_model.dart';
import '../../models/game_stats_model.dart';
import '../../services/game_summary_generator.dart';

/// Presentation-ready content shared from a league result or stat view.
class BrandedSharePayload {
  final String title;
  final String headline;
  final String detail;
  final String shareText;
  final String fileName;

  const BrandedSharePayload({
    required this.title,
    required this.headline,
    required this.detail,
    required this.shareText,
    required this.fileName,
  });

  factory BrandedSharePayload.gameSummary({
    required GameStatsModel stats,
    required AssociationBrandingModel branding,
  }) {
    final headline = GameSummaryGenerator.generateHeadline(stats);
    final detail = GameSummaryGenerator.generateNarrative(stats);
    final sponsor = branding.sponsor;
    final sponsorLine = sponsor.isActive
        ? '${sponsor.label.trim().isEmpty ? 'Presented by' : sponsor.label.trim()} ${sponsor.name.trim()}'
        : null;
    final lines = <String>[
      headline,
      if (detail.isNotEmpty && detail != headline) '',
      if (detail.isNotEmpty && detail != headline) detail,
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} game result',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-game-result.png',
    );
  }
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'hoopsconnect' : slug;
}
