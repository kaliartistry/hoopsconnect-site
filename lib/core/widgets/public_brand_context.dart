import 'package:flutter/material.dart';

import '../../models/public_league_snapshot.dart';
import 'sponsor_banner.dart';

class PublicBrandContext extends StatelessWidget {
  const PublicBrandContext({
    super.key,
    required this.snapshot,
    required this.league,
    this.divisionName,
    this.showSponsorText = false,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;
  final String? divisionName;
  final bool showSponsorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sponsor = league.sponsor;
    final leagueColor = _color(
      league.primaryColorHex,
      theme.colorScheme.primary,
    );
    return Card(
      key: const Key('public-brand-context'),
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: const Color(0x2B000000),
      surfaceTintColor: Colors.transparent,
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: leagueColor, width: 4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _LeagueBadge(league: league, color: leagueColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    league.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF0B1D3A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (league.seasonLabel != null || divisionName != null)
                    Text(
                      league.seasonLabel ?? divisionName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5F6F86),
                      ),
                    ),
                ],
              ),
            ),
            if (showSponsorText && sponsor.isActive) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${sponsor.label} · ${sponsor.name}',
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF5F6F86),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeagueBadge extends StatelessWidget {
  const _LeagueBadge({required this.league, required this.color});

  final PublicLeagueDefinition league;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (league.logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SponsorLogo(
          reference: league.logoUrl!,
          semanticLabel: '${league.name} logo',
          width: 34,
          height: 34,
          onPlate: false,
        ),
      );
    }
    final source = league.shortName.trim().isEmpty
        ? league.name.trim()
        : league.shortName.trim();
    final label = source.length <= 3
        ? source.toUpperCase()
        : source.substring(0, 3).toUpperCase();
    return Semantics(
      image: true,
      label: '${league.name} league mark',
      child: ExcludeSemantics(
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE3E6E2)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

Color _color(String value, Color fallback) {
  final normalized = value.trim();
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(normalized)) return fallback;
  return Color(int.parse('FF${normalized.substring(1)}', radix: 16));
}
