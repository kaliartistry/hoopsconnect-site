import '../../models/association_branding_model.dart';
import '../../models/game_stats_model.dart';
import '../../models/leaderboard_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/standings_model.dart';
import '../../services/game_summary_generator.dart';

/// Presentation-ready content shared from a league result or stat view.
class BrandedSharePayload {
  final String title;
  final String eyebrow;
  final String headline;
  final String detail;
  final String shareText;
  final String fileName;

  const BrandedSharePayload({
    required this.title,
    this.eyebrow = 'FINAL',
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
    final sponsorLine = _sponsorLine(branding);
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
      eyebrow: 'FINAL',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-game-result.png',
    );
  }

  factory BrandedSharePayload.leaderboard({
    required List<LeaderboardEntry> rankings,
    required String category,
    required AssociationBrandingModel branding,
  }) {
    if (rankings.isEmpty) {
      throw ArgumentError.value(
        rankings,
        'rankings',
        'A leaderboard share requires at least one ranking.',
      );
    }
    final label = _categoryLabel(category);
    final topRankings = rankings.take(3).toList(growable: false);
    final leader = topRankings.first;
    final detail = topRankings.indexed
        .map(
          (item) =>
              '#${item.$1 + 1} ${item.$2.name} · ${item.$2.teamName} · ${item.$2.value.toStringAsFixed(1)}',
        )
        .join('\n');
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      '$label Leaders',
      '',
      ...rankings.indexed.map(
        (item) =>
            '${item.$1 + 1}. ${item.$2.name} (${item.$2.teamName}) - ${item.$2.value.toStringAsFixed(1)}',
      ),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} $label leaders',
      eyebrow: 'SEASON LEADERS',
      headline:
          '${leader.name} leads with ${leader.value.toStringAsFixed(1)} $label',
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-${_slug(category)}-leaders.png',
    );
  }

  factory BrandedSharePayload.playerStats({
    required PlayerSeasonStatsModel stats,
    required AssociationBrandingModel branding,
  }) {
    final teamName = stats.teamName?.trim().isNotEmpty == true
        ? stats.teamName!.trim()
        : 'Independent player';
    final statLine = [
      '${stats.ppg.toStringAsFixed(1)} PPG',
      '${stats.rpg.toStringAsFixed(1)} RPG',
      '${stats.apg.toStringAsFixed(1)} APG',
      '${stats.spg.toStringAsFixed(1)} SPG',
      '${stats.bpg.toStringAsFixed(1)} BPG',
    ];
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      stats.playerName,
      '$teamName · ${stats.gamesPlayed} GP',
      '',
      statLine.join(' · '),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} player stats',
      eyebrow: 'PLAYER SPOTLIGHT',
      headline: stats.playerName,
      detail: '$teamName · ${stats.gamesPlayed} GP\n${statLine.join(' · ')}',
      shareText: lines.join('\n'),
      fileName:
          '${_slug(branding.shortName)}-${_slug(stats.playerName)}-stats.png',
    );
  }

  factory BrandedSharePayload.standings({
    required List<TeamStanding> standings,
    required AssociationBrandingModel branding,
    String? divisionName,
  }) {
    if (standings.isEmpty) {
      throw ArgumentError.value(
        standings,
        'standings',
        'A standings share requires at least one team.',
      );
    }
    final leaders = standings.take(3).toList(growable: false);
    final detail = leaders.indexed
        .map(
          (item) =>
              '#${item.$1 + 1} ${item.$2.teamName} · ${item.$2.wins}-${item.$2.losses}',
        )
        .join('\n');
    final scope = divisionName?.trim().isNotEmpty == true
        ? divisionName!.trim()
        : branding.shortName;
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      '$scope Standings',
      '',
      ...standings.indexed.map(
        (item) =>
            '${item.$1 + 1}. ${item.$2.teamName} ${item.$2.wins}-${item.$2.losses} (${item.$2.pct.toStringAsFixed(3)})',
      ),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '$scope standings',
      eyebrow: 'LEAGUE STANDINGS',
      headline: '${standings.first.teamName} leads $scope',
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-${_slug(scope)}-standings.png',
    );
  }
}

String? _sponsorLine(AssociationBrandingModel branding) {
  final sponsor = branding.sponsor;
  if (!sponsor.isActive) return null;
  final label = sponsor.label.trim().isEmpty
      ? 'Presented by'
      : sponsor.label.trim();
  return '$label ${sponsor.name.trim()}';
}

String _categoryLabel(String category) {
  switch (category) {
    case 'ppg':
      return 'PPG';
    case 'rpg':
      return 'RPG';
    case 'apg':
      return 'APG';
    case 'spg':
      return 'SPG';
    case 'bpg':
      return 'BPG';
    default:
      return category.trim().toUpperCase();
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
