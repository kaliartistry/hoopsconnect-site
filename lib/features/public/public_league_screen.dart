import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/association_branding_model.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';
import 'historical_league_overview.dart';
import 'historical_league_standings.dart';
import 'public_stats_navigation.dart';
import 'public_team_identity.dart';

class PublicLeagueScreen extends ConsumerWidget {
  const PublicLeagueScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedInUser = ref.watch(currentUserProvider).valueOrNull;
    final snapshot = ref.watch(publicLeagueSnapshotProvider);
    final published = snapshot.valueOrNull;
    final associationLogo =
        published?.effectiveAssociationBrand.logoUrl ??
        'asset:assets/images/jba_logo.png';
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFF4F5F6)
            : Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: publicRoyalGradient),
          ),
          title: Semantics(
            button: true,
            label: 'Jamaica Basketball home',
            child: Tooltip(
              message: 'Back to Games',
              child: InkWell(
                key: const Key('public-association-home'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.go(PublicRoutePaths.games),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SponsorLogo(
                        key: const Key('public-association-logo'),
                        reference: associationLogo,
                        semanticLabel: 'Jamaica Basketball Association crest',
                        width: 28,
                        height: 28,
                        onPlate: false,
                      ),
                      const SizedBox(width: 10),
                      const Flexible(child: Text('Jamaica Basketball')),
                    ],
                  ),
                ),
              ),
            ),
          ),
          foregroundColor: Colors.white,
          actions: [
            if (signedInUser == null)
              TextButton(
                onPressed: () => context.go('/login'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Sign in'),
              )
            else
              TextButton(
                key: const Key('public-back-to-app'),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRouteContract.landingFor(signedInUser)),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Back to app'),
              ),
          ],
        ),
        body: snapshot.when(
          loading: () => const Center(
            child: AppLoadingState(label: 'Loading published league data'),
          ),
          error: (_, _) => _PublicState(
            title: 'Published data could not be loaded',
            message:
                'No private league records were used as a fallback. Check your connection and try again.',
            tone: AppStateTone.error,
            onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
          ),
          data: (data) {
            if (data == null) {
              return _PublicState(
                title: 'Published data unavailable',
                message:
                    'The league has not published a public snapshot yet. No private data is shown.',
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              );
            }
            return switch (data.version.state) {
              PublicReleaseState.retracted => _PublicState(
                title: 'This public release was withdrawn',
                message:
                    'Previously loaded scores and exports are not presented as current. Try again later for a new release.',
                tone: AppStateTone.warning,
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              ),
              PublicReleaseState.unavailable => _PublicState(
                title: 'Public league data unavailable',
                message:
                    'There is no active public release. No private source records were used.',
                onRetry: () => ref.invalidate(publicLeagueSnapshotProvider),
              ),
              PublicReleaseState.published => _PublishedLeague(
                snapshot: data,
                tabIndex: initialTab,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _PublishedLeague extends ConsumerWidget {
  final PublicLeagueSnapshot snapshot;
  final int tabIndex;

  const _PublishedLeague({required this.snapshot, required this.tabIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = snapshot.availableLeagues;
    final rememberedId = ref.watch(publicSelectedLeagueIdProvider);
    final selectedId =
        available.any((league) => league.leagueId == rememberedId)
        ? rememberedId!
        : available.first.leagueId;
    final selected = snapshot.leagueById(selectedId);

    return Column(
      children: [
        if (tabIndex == 0)
          _LeagueSwitcher(
            snapshot: snapshot,
            selected: selected,
            onChanged: (leagueId) =>
                ref.read(publicSelectedLeagueIdProvider.notifier).state =
                    leagueId,
          )
        else
          _LeagueContextBar(
            snapshot: snapshot,
            selected: selected,
            onChanged: (leagueId) =>
                ref.read(publicSelectedLeagueIdProvider.notifier).state =
                    leagueId,
          ),
        const _PublicTabBar(),
        Expanded(
          child: TabBarView(
            children: [
              _GamesTab(snapshot: snapshot, league: selected),
              _MediaTab(snapshot: snapshot, league: selected),
              _StandingsTab(snapshot: snapshot, league: selected),
              _LeadersTab(snapshot: snapshot, league: selected),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicTabBar extends StatelessWidget {
  const _PublicTabBar();

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Theme.of(context).colorScheme.surface,
    elevation: 1,
    shadowColor: const Color(0x24000000),
    child: TabBar(
      indicatorColor: AppColors.accent,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: (index) {
        final destination = switch (index) {
          1 => PublicRoutePaths.media,
          2 => PublicRoutePaths.standings,
          3 => PublicRoutePaths.leaders,
          _ => PublicRoutePaths.games,
        };
        if (GoRouterState.of(context).uri.path != destination) {
          context.go(destination);
        }
      },
      tabs: const [
        Tab(
          key: Key('public-games-home-tab'),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_rounded, size: 16),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Games',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Tab(
          key: Key('public-media-tab'),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.newspaper_rounded, size: 16),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Tab(text: 'Standings'),
        Tab(text: 'Stats'),
      ],
    ),
  );
}

class _LeagueSwitcher extends StatelessWidget {
  const _LeagueSwitcher({
    required this.snapshot,
    required this.selected,
    required this.onChanged,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 840;
    final narrow = viewportWidth < 480;
    final primary = _publicColor(
      selected.primaryColorHex,
      const Color(0xFF234EBD),
    );
    final sponsor = selected.sponsor;
    final divisions = snapshot.divisionsForLeague(selected.leagueId);

    Widget leaguePicker() => Container(
      width: 160,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const Key('public-league-dropdown'),
          value: selected.leagueId,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          menuWidth: MediaQuery.sizeOf(context).width < 600
              ? MediaQuery.sizeOf(context).width - 32
              : 360,
          dropdownColor: theme.colorScheme.surface,
          iconEnabledColor: Colors.white,
          selectedItemBuilder: (context) => [
            for (final _ in snapshot.availableLeagues)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Switch league',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          items: [
            for (final league in snapshot.availableLeagues)
              DropdownMenuItem(
                key: Key('public-league-${league.leagueId}'),
                value: league.leagueId,
                child: Row(
                  children: [
                    _LeagueDot(
                      color: _publicColor(
                        league.primaryColorHex,
                        const Color(0xFF234EBD),
                      ),
                      semanticLabel: '${league.name} mark',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        league.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );

    final leagueIdentity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LeagueMark(league: selected, color: primary, size: compact ? 56 : 76),
        SizedBox(width: compact ? 12 : 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    (narrow
                            ? theme.textTheme.titleMedium
                            : compact
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.headlineMedium)
                        ?.copyWith(
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
              ),
              const SizedBox(height: 4),
              Text(
                selected.seasonLabel ??
                    (compact
                        ? snapshot.seasonName
                        : '${snapshot.seasonName}${divisions.isEmpty ? '' : ' · ${divisions.map((division) => division.name).join(' · ')}'}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => context.go(
            Uri(
              path: '/settings',
              queryParameters: {'follow': selected.leagueId},
            ).toString(),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
            minimumSize: Size(0, compact ? 36 : 40),
            padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 15),
          ),
          icon: const Icon(Icons.star_border_rounded, size: 18),
          label: const Text('Follow'),
        ),
      ],
    );

    return Container(
      key: const Key('public-league-hero'),
      decoration: BoxDecoration(
        color: primary,
        gradient: ['nbl', 'jbl'].contains(selected.leagueId)
            ? publicRoyalGradient
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 36,
                vertical: compact ? 14 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      leaguePicker(),
                      const Spacer(),
                      Text(
                        '${snapshot.availableLeagues.indexWhere((league) => league.leagueId == selected.leagueId) + 1} of ${snapshot.availableLeagues.length} leagues',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  if (compact) ...[
                    leagueIdentity,
                    if (sponsor.isActive) ...[
                      const SizedBox(height: 16),
                      _LeagueSponsorIdentity(sponsor: sponsor, compact: true),
                    ],
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: leagueIdentity),
                        if (sponsor.isActive) ...[
                          const SizedBox(width: 32),
                          _LeagueSponsorIdentity(
                            sponsor: sponsor,
                            compact: false,
                          ),
                        ],
                      ],
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

class _LeagueContextBar extends StatelessWidget {
  const _LeagueContextBar({
    required this.snapshot,
    required this.selected,
    required this.onChanged,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _publicColor(
      selected.primaryColorHex,
      const Color(0xFF234EBD),
    );
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _LeagueMark(league: selected, color: color, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('public-league-dropdown'),
                      value: selected.leagueId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(12),
                      items: [
                        for (final league in snapshot.availableLeagues)
                          DropdownMenuItem(
                            key: Key('public-league-${league.leagueId}'),
                            value: league.leagueId,
                            child: Text(
                              league.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onChanged(value);
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Choose teams to follow in ${selected.name}',
                  onPressed: () => context.go(
                    Uri(
                      path: '/settings',
                      queryParameters: {'follow': selected.leagueId},
                    ).toString(),
                  ),
                  icon: const Icon(Icons.star_border_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeagueDot extends StatelessWidget {
  const _LeagueDot({required this.color, this.semanticLabel});

  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
    );
    if (semanticLabel == null) return dot;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: dot),
    );
  }
}

class _LeagueMark extends StatelessWidget {
  const _LeagueMark({
    required this.league,
    required this.color,
    required this.size,
  });

  final PublicLeagueDefinition league;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (league.logoUrl != null) {
      final isWidePresentationMark = league.logoUrl!.contains(
        'nbl_jamaica_logo.png',
      );
      if (isWidePresentationMark) {
        return SizedBox(
          width: size * 1.64,
          height: size,
          child: SponsorLogo(
            reference: league.logoUrl!,
            semanticLabel: '${league.name} logo',
            width: size * 1.64,
            height: size,
            onPlate: false,
          ),
        );
      }
      final radius = BorderRadius.circular(size <= 32 ? 8 : 12);
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Colors.white,
          border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x36000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SponsorLogo(
          reference: league.logoUrl!,
          semanticLabel: '${league.name} logo',
          width: size,
          height: size,
          onPlate: false,
        ),
      );
    }
    final abbreviation = league.shortName.trim().isEmpty
        ? league.name.trim()
        : league.shortName.trim();
    return Semantics(
      image: true,
      label: '${league.name} league mark',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(size <= 32 ? 8 : 12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          ),
          child: Text(
            abbreviation.length <= 3
                ? abbreviation.toUpperCase()
                : abbreviation.substring(0, 3).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: size <= 32 ? 9 : (size <= 56 ? 13 : 18),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeagueSponsorIdentity extends StatelessWidget {
  const _LeagueSponsorIdentity({required this.sponsor, required this.compact});

  final PublicSponsor sponsor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${sponsor.label}: ${sponsor.name}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (sponsor.logoUrl != null)
            SponsorLogo(
              key: const Key('public-league-sponsor-logo'),
              reference: sponsor.logoUrl!,
              semanticLabel: '${sponsor.name} logo',
              width: compact ? 160 : 240,
              height: compact ? 56 : 80,
            )
          else
            Container(
              width: compact ? 160 : 240,
              height: compact ? 56 : 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(compact ? 10 : 12),
              ),
              child: Text(
                sponsor.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF141A15),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sponsor.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              Text(
                sponsor.name,
                maxLines: 2,
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssociationFooter extends StatelessWidget {
  const _AssociationFooter({required this.snapshot, this.showPartner = true});

  final PublicLeagueSnapshot snapshot;
  final bool showPartner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = snapshot.effectiveAssociationBrand;
    final partner = brand.sponsor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final association = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SponsorLogo(
                reference: brand.logoUrl ?? 'asset:assets/images/jba_logo.png',
                semanticLabel: '${brand.name} crest',
                width: compact ? 28 : 40,
                height: compact ? 28 : 40,
                onPlate: false,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Parent association',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final publication = Text(
            'League coverage',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
          if (!showPartner || !partner.isActive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [association, const SizedBox(height: 12), publication],
            );
          }

          final partnerLockup = Semantics(
            container: true,
            excludeSemantics: true,
            label: 'Association partner: ${partner.name}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (partner.logoUrl != null) ...[
                  SponsorLogo(
                    key: const Key('public-association-sponsor-logo'),
                    reference: partner.logoUrl!,
                    semanticLabel: '${partner.name} logo',
                    width: 160,
                    height: 56,
                  ),
                  const SizedBox(width: 12),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ASSOCIATION PARTNER',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      partner.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                association,
                const SizedBox(height: 16),
                partnerLockup,
                const SizedBox(height: 12),
                publication,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: association),
                  const SizedBox(width: 24),
                  partnerLockup,
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: publication),
            ],
          );
        },
      ),
    );
  }
}

Color _publicColor(String value, Color fallback) {
  final normalized = value.trim();
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(normalized)) return fallback;
  return Color(int.parse('FF${normalized.substring(1)}', radix: 16));
}

enum _GamesViewMode { schedule, calendar }

class _GamesTab extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;

  const _GamesTab({required this.snapshot, required this.league});

  @override
  ConsumerState<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends ConsumerState<_GamesTab> {
  static const _pageSize = 25;
  String? _divisionId;
  int _visibleCount = _pageSize;
  _GamesViewMode _viewMode = _GamesViewMode.schedule;
  DateTime? _selectedDay;

  @override
  void didUpdateWidget(covariant _GamesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.league.leagueId != widget.league.leagueId) {
      _divisionId = null;
      _visibleCount = _pageSize;
      _selectedDay = null;
    }
    final leagueDivisions = widget.league.divisionIds.toSet();
    if (_divisionId != null && !leagueDivisions.contains(_divisionId)) {
      _divisionId = null;
      _visibleCount = _pageSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.league.historicalStatistics) {
      return HistoricalLeagueOverview(
        snapshot: widget.snapshot,
        league: widget.league,
      );
    }
    final filtered =
        widget.snapshot.schedule
            .where(
              (game) =>
                  widget.snapshot.gameBelongsToLeague(
                    game,
                    widget.league.leagueId,
                  ) &&
                  (_divisionId == null || game.divisionId == _divisionId),
            )
            .toList(growable: false)
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final visible = filtered.take(_visibleCount).toList(growable: false);
    final highlights = _publicGameHighlights(filtered);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(publicLeagueSnapshotProvider);
        await ref.read(publicLeagueSnapshotProvider.future);
      },
      child: ListView(
        key: const Key('public-games-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControls(context, filtered),
                    const SizedBox(height: 18),
                    _GameHighlights(
                      snapshot: widget.snapshot,
                      latestResult: highlights.latestResult,
                      nextGame: highlights.nextGame,
                    ),
                    if (widget.snapshot
                        .mediaForLeague(widget.league.leagueId)
                        .isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _FeaturedMediaCard(
                        item: widget.snapshot
                            .mediaForLeague(widget.league.leagueId)
                            .first,
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: AppStateMessage(
                          title: 'No games published',
                          message:
                              'There are no public games for this division in the current snapshot.',
                          icon: Icons.event_busy_outlined,
                        ),
                      )
                    else if (_viewMode == _GamesViewMode.calendar)
                      _buildCalendar(context, filtered)
                    else
                      _buildSchedule(context, filtered, visible),
                    const SizedBox(height: 28),
                    _AssociationFooter(snapshot: widget.snapshot),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, List<PublicGame> games) {
    final selector = SegmentedButton<_GamesViewMode>(
      key: const Key('public-games-view-selector'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _GamesViewMode.schedule, label: Text('Schedule')),
        ButtonSegment(value: _GamesViewMode.calendar, label: Text('Calendar')),
      ],
      selected: {_viewMode},
      onSelectionChanged: (selection) => setState(() {
        _viewMode = selection.first;
        if (_viewMode == _GamesViewMode.calendar) {
          _selectedDay ??= _defaultCalendarDay(games);
        }
      }),
    );
    final division = _DivisionFilter(
      divisions: widget.snapshot.divisionsForLeague(widget.league.leagueId),
      value: _divisionId,
      padding: EdgeInsets.zero,
      compact: true,
      onChanged: (value) => setState(() {
        _divisionId = value;
        _visibleCount = _pageSize;
        final scoped = widget.snapshot.schedule
            .where(
              (game) =>
                  widget.snapshot.gameBelongsToLeague(
                    game,
                    widget.league.leagueId,
                  ) &&
                  (value == null || game.divisionId == value),
            )
            .toList(growable: false);
        _selectedDay = _defaultCalendarDay(scoped);
      }),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              selector,
              SizedBox(width: 180, child: division),
            ],
          );
        }
        return Row(
          children: [
            selector,
            const SizedBox(width: 12),
            SizedBox(width: 240, child: division),
          ],
        );
      },
    );
  }

  Widget _buildSchedule(
    BuildContext context,
    List<PublicGame> filtered,
    List<PublicGame> visible,
  ) {
    final sections = _gamesByDay(visible);
    return Column(
      key: const Key('public-games-schedule-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections.entries) ...[
          _GameDateHeading(date: section.key, count: section.value.length),
          const SizedBox(height: 8),
          _ResponsiveGameCards(snapshot: widget.snapshot, games: section.value),
          const SizedBox(height: 20),
        ],
        if (visible.length < filtered.length)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _visibleCount += _pageSize),
              icon: const Icon(Icons.expand_more),
              label: Text(
                'Load ${(_pageSize).clamp(0, filtered.length - visible.length)} more games',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context, List<PublicGame> games) {
    final ascendingDays = _gamesByDay(games, ascending: true);
    final firstGameDay = ascendingDays.keys.first;
    final lastGameDay = ascendingDays.keys.last;
    final firstDate = DateTime(firstGameDay.year, firstGameDay.month);
    final lastDate = DateTime(lastGameDay.year, lastGameDay.month + 1, 0);
    final preferredDay = _selectedDay ?? _defaultCalendarDay(games)!;
    final selectedDay = _clampDay(preferredDay, firstDate, lastDate);
    final selectedGames =
        games
            .where(
              (game) =>
                  _sameDay(_jamaicaCalendarDay(game.startTime), selectedDay),
            )
            .toList(growable: false)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final calendar = Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      shadowColor: const Color(0x30000000),
      surfaceTintColor: Colors.transparent,
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Choose a date',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              key: const Key('public-games-calendar'),
              child: CalendarDatePicker(
                key: ValueKey(selectedDay),
                initialDate: selectedDay,
                firstDate: firstDate,
                lastDate: lastDate,
                currentDate: _currentJamaicaDay(),
                onDateChanged: (value) => setState(() {
                  _selectedDay = DateTime(value.year, value.month, value.day);
                }),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                'Game-day shortcuts',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final entry in ascendingDays.entries) ...[
                    ChoiceChip(
                      key: Key(_gameDayKey(entry.key)),
                      selected: _sameDay(entry.key, selectedDay),
                      label: Text(
                        '${DateFormat('MMM d').format(entry.key)} · ${entry.value.length}',
                      ),
                      onSelected: (_) => setState(() {
                        _selectedDay = entry.key;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final dayGames = Column(
      key: const Key('public-games-calendar-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GameDateHeading(date: selectedDay, count: selectedGames.length),
        const SizedBox(height: 8),
        if (selectedGames.isEmpty)
          const AppStateMessage(
            title: 'No games on this date',
            message:
                'Choose another date or use one of the game-day shortcuts.',
            icon: Icons.event_available_outlined,
          )
        else
          _ResponsiveGameCards(snapshot: widget.snapshot, games: selectedGames),
      ],
    );

    return LayoutBuilder(
      key: const Key('public-games-calendar-view'),
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [calendar, const SizedBox(height: 20), dayGames],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 400, child: calendar),
            const SizedBox(width: 24),
            Expanded(child: dayGames),
          ],
        );
      },
    );
  }
}

class _GameHighlights extends StatelessWidget {
  const _GameHighlights({
    required this.snapshot,
    required this.latestResult,
    required this.nextGame,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicGame? latestResult;
  final PublicGame? nextGame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final latest = _GameHighlightCard(
        key: const Key('public-latest-result-card'),
        kind: _GameHighlightKind.latestResult,
        game: latestResult,
        homeTeam: _publicTeam(snapshot, latestResult?.homeTeamId),
        awayTeam: _publicTeam(snapshot, latestResult?.awayTeamId),
      );
      final next = _GameHighlightCard(
        key: const Key('public-next-game-card'),
        kind: _GameHighlightKind.nextGame,
        game: nextGame,
        homeTeam: _publicTeam(snapshot, nextGame?.homeTeamId),
        awayTeam: _publicTeam(snapshot, nextGame?.awayTeamId),
      );
      if (constraints.maxWidth < 720) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [latest, const SizedBox(height: 12), next],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: latest),
            const SizedBox(width: 16),
            Expanded(child: next),
          ],
        ),
      );
    },
  );
}

enum _GameHighlightKind { latestResult, nextGame }

class _GameHighlightCard extends StatelessWidget {
  const _GameHighlightCard({
    super.key,
    required this.kind,
    required this.game,
    this.homeTeam,
    this.awayTeam,
  });

  final _GameHighlightKind kind;
  final PublicGame? game;
  final PublicTeam? homeTeam;
  final PublicTeam? awayTeam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResult = kind == _GameHighlightKind.latestResult;
    final label = isResult ? 'Latest result' : 'Next game';
    final icon = isResult
        ? Icons.sports_score_outlined
        : Icons.calendar_today_outlined;
    final accent = isResult ? theme.colorScheme.primary : AppColors.accent;
    final currentGame = game;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shadowColor: const Color(0x38000000),
      surfaceTintColor: Colors.transparent,
      color: Theme.of(context).brightness == Brightness.light
          ? (isResult ? AppColors.primaryLight : Colors.white)
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: currentGame == null
            ? null
            : () => context.push(PublicRoutePaths.game(currentGame.gameId)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (currentGame != null)
                        const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (currentGame == null)
                    Text(
                      isResult
                          ? 'No final score has been published yet.'
                          : 'No upcoming game has been published yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    Text(
                      '${LeagueTime.formatJamaicaDate(currentGame.startTime, pattern: 'EEE, MMM d')} · ${LeagueTime.formatJamaicaTime(currentGame.startTime)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _HighlightTeamRow(
                      team: homeTeam,
                      name: currentGame.homeTeamName ?? 'Home team unavailable',
                      score: isResult ? currentGame.homeScore : null,
                      winner: _homeWon(currentGame),
                    ),
                    const SizedBox(height: 8),
                    _HighlightTeamRow(
                      team: awayTeam,
                      name: currentGame.awayTeamName ?? 'Away team unavailable',
                      score: isResult ? currentGame.awayScore : null,
                      winner: _awayWon(currentGame),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            currentGame.venue ?? 'Venue not published',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightTeamRow extends StatelessWidget {
  const _HighlightTeamRow({
    required this.team,
    required this.name,
    required this.score,
    required this.winner,
  });

  final PublicTeam? team;
  final String name;
  final int? score;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: winner ? FontWeight.w800 : FontWeight.w600,
    );
    return Row(
      children: [
        _TeamMark(team: team, fallbackName: name, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        if (score != null) ...[
          const SizedBox(width: 12),
          Text('$score', style: textStyle?.copyWith(fontSize: 22)),
        ],
      ],
    );
  }
}

class _PublicGameHighlights {
  const _PublicGameHighlights({this.latestResult, this.nextGame});

  final PublicGame? latestResult;
  final PublicGame? nextGame;
}

_PublicGameHighlights _publicGameHighlights(
  List<PublicGame> games, {
  DateTime? utcNow,
}) {
  final now = (utcNow ?? DateTime.now()).toUtc();
  final finals =
      games
          .where(
            (game) =>
                game.status == PublicGameStatus.finalResult &&
                !game.startTime.toUtc().isAfter(now),
          )
          .toList(growable: false)
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
  final upcoming =
      games
          .where(
            (game) =>
                game.status == PublicGameStatus.scheduled &&
                !game.startTime.toUtc().isBefore(now),
          )
          .toList(growable: false)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
  return _PublicGameHighlights(
    latestResult: finals.isEmpty ? null : finals.first,
    nextGame: upcoming.isEmpty ? null : upcoming.first,
  );
}

bool _homeWon(PublicGame game) =>
    game.homeScore != null &&
    game.awayScore != null &&
    game.homeScore! > game.awayScore!;

bool _awayWon(PublicGame game) =>
    game.homeScore != null &&
    game.awayScore != null &&
    game.awayScore! > game.homeScore!;

class _GameDateHeading extends StatelessWidget {
  const _GameDateHeading({required this.date, required this.count});

  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, y').format(date),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              '$count ${count == 1 ? 'game' : 'games'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ResponsiveGameCards extends StatelessWidget {
  const _ResponsiveGameCards({required this.snapshot, required this.games});

  final PublicLeagueSnapshot snapshot;
  final List<PublicGame> games;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = games.length > 1 && constraints.maxWidth >= 760 ? 2 : 1;
      final cardWidth = columns == 2
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final game in games)
            SizedBox(
              width: cardWidth,
              child: _GameCard(snapshot: snapshot, game: game),
            ),
        ],
      );
    },
  );
}

Map<DateTime, List<PublicGame>> _gamesByDay(
  List<PublicGame> games, {
  bool ascending = false,
}) {
  final sorted = [...games]
    ..sort(
      (a, b) => ascending
          ? a.startTime.compareTo(b.startTime)
          : b.startTime.compareTo(a.startTime),
    );
  final result = <DateTime, List<PublicGame>>{};
  for (final game in sorted) {
    result.putIfAbsent(_jamaicaCalendarDay(game.startTime), () => []).add(game);
  }
  return result;
}

DateTime _jamaicaCalendarDay(DateTime instant) {
  final day = LeagueTime.jamaicaDate(instant);
  return DateTime(day.year, day.month, day.day);
}

DateTime _currentJamaicaDay() {
  final day = LeagueTime.nowJamaicaCivil();
  return DateTime(day.year, day.month, day.day);
}

DateTime? _defaultCalendarDay(List<PublicGame> games) {
  if (games.isEmpty) return null;
  final days = _gamesByDay(games, ascending: true).keys.toList(growable: false);
  final today = _currentJamaicaDay();
  return days.firstWhere(
    (day) => !day.isBefore(today),
    orElse: () => days.last,
  );
}

DateTime _clampDay(DateTime value, DateTime first, DateTime last) {
  if (value.isBefore(first)) return first;
  if (value.isAfter(last)) return last;
  return value;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _gameDayKey(DateTime date) =>
    'public-game-day-${DateFormat('yyyy-MM-dd').format(date)}';

class _GameCard extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGame game;

  const _GameCard({required this.snapshot, required this.game});

  @override
  Widget build(BuildContext context) {
    final home = game.homeTeamName ?? 'Home team unavailable';
    final away = game.awayTeamName ?? 'Away team unavailable';
    final homeTeam = _publicTeam(snapshot, game.homeTeamId);
    final awayTeam = _publicTeam(snapshot, game.awayTeamId);
    return Card(
      key: Key('public-game-card-${game.gameId}'),
      elevation: 2,
      shadowColor: const Color(0x2B000000),
      surfaceTintColor: Colors.transparent,
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        onTap: () => context.push(PublicRoutePaths.game(game.gameId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${LeagueTime.formatJamaicaDate(game.startTime, pattern: 'EEE, MMM d')} · ${LeagueTime.formatJamaicaTime(game.startTime)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _StatusChip(status: game.status),
                ],
              ),
              const SizedBox(height: 12),
              _ScoreRow(team: homeTeam, name: home, score: game.homeScore),
              const SizedBox(height: 6),
              _ScoreRow(team: awayTeam, name: away, score: game.awayScore),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      game.venue ?? 'Venue not published',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final PublicTeam? team;
  final String name;
  final int? score;

  const _ScoreRow({
    required this.team,
    required this.name,
    required this.score,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _TeamMark(team: team, fallbackName: name, size: 32),
      const SizedBox(width: 10),
      Expanded(child: Text(name, style: const TextStyle(fontSize: 16))),
      Text(
        score?.toString() ?? 'Not available',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

PublicTeam? _publicTeam(PublicLeagueSnapshot snapshot, String? teamId) {
  if (teamId == null) return null;
  for (final team in snapshot.teams) {
    if (team.teamId == teamId) return team;
  }
  return null;
}

class _TeamMark extends StatelessWidget {
  const _TeamMark({
    required this.team,
    required this.fallbackName,
    required this.size,
  });

  final PublicTeam? team;
  final String fallbackName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoUrl = team?.logoUrl;
    if (logoUrl != null) {
      return SponsorLogo(
        reference: logoUrl,
        semanticLabel: '${team?.name ?? fallbackName} team logo',
        width: size,
        height: size,
      );
    }
    final words = fallbackName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final initials = words.isEmpty
        ? 'T'
        : words.take(2).map((word) => word[0]).join().toUpperCase();
    return Semantics(
      image: true,
      label: '$fallbackName team mark',
      child: ExcludeSemantics(
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: size <= 28 ? 9 : 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final PublicGameStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isFinal = status == PublicGameStatus.finalResult;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isFinal
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _gameStatusLabel(status).toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _FeaturedMediaCard extends StatelessWidget {
  const _FeaturedMediaCard({required this.item});

  final PublicMediaItem item;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('public-featured-media-card'),
    elevation: 2,
    shadowColor: const Color(0x2B000000),
    surfaceTintColor: Colors.transparent,
    color: Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFFFFBEE)
        : Theme.of(context).colorScheme.surfaceContainerLow,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      onTap: () => context.go(PublicRoutePaths.mediaItem(item.mediaId)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.newspaper_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FROM MEDIA · ${item.typeLabel.toUpperCase()}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_rounded),
          ],
        ),
      ),
    ),
  );
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({required this.snapshot, required this.league});

  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;

  @override
  Widget build(BuildContext context) {
    final items = snapshot.mediaForLeague(league.leagueId);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          key: const Key('public-media-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Text(
              'Latest from ${league.shortName}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Published league news, announcements, and game-day updates.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const AppStateMessage(
                title: 'No media published',
                message:
                    'There are no public stories or announcements for this league yet.',
                icon: Icons.newspaper_outlined,
              )
            else
              for (final item in items) ...[
                _PublicMediaCard(item: item, snapshot: snapshot),
                const SizedBox(height: 14),
              ],
            const SizedBox(height: 14),
            _AssociationFooter(
              snapshot: snapshot,
              showPartner: !league.historicalStatistics,
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicMediaCard extends ConsumerWidget {
  const _PublicMediaCard({required this.item, required this.snapshot});

  final PublicMediaItem item;
  final PublicLeagueSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    key: Key('public-media-card-${item.mediaId}'),
    elevation: item.pinned ? 3 : 2,
    shadowColor: const Color(0x2B000000),
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.imageUrl != null)
          SizedBox(
            width: double.infinity,
            height: 210,
            child: Image.network(
              item.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, size: 42),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: item.pinned
                        ? const Icon(Icons.push_pin_rounded, size: 16)
                        : null,
                    label: Text(item.typeLabel),
                  ),
                  if (item.divisionId != null)
                    Text(
                      snapshot.divisionName(item.divisionId),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  Text(
                    DateFormat('MMM d, y').format(item.publishedAt.toLocal()),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(item.summary, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        context.push(PublicRoutePaths.mediaItem(item.mediaId)),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Open story'),
                  ),
                  if (snapshot.canCreatePublishedArtifacts)
                    OutlinedButton.icon(
                      key: Key('public-media-share-${item.mediaId}'),
                      onPressed: () async {
                        final league = snapshot.leagueForDivision(
                          item.divisionId,
                        );
                        final branding = publicShareBranding(snapshot, league);
                        await _showValidatedPublicShare(
                          context: context,
                          ref: ref,
                          snapshot: snapshot,
                          branding: branding,
                          payload: BrandedSharePayload.publicMedia(
                            snapshot: snapshot,
                            item: item,
                            branding: branding,
                            canonicalUri: _publicCanonicalUri(
                              PublicRoutePaths.mediaItem(item.mediaId),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StandingsTab extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;

  const _StandingsTab({required this.snapshot, required this.league});

  @override
  ConsumerState<_StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends ConsumerState<_StandingsTab> {
  String? _divisionId;

  @override
  void didUpdateWidget(covariant _StandingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.league.leagueId != widget.league.leagueId) {
      _divisionId = null;
    }
    if (_divisionId != null &&
        !widget.league.divisionIds.contains(_divisionId)) {
      _divisionId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.league.historicalStatistics) {
      return HistoricalLeagueStandings(
        snapshot: widget.snapshot,
        league: widget.league,
      );
    }
    final standings = widget.snapshot.standings
        .where(
          (standing) =>
              widget.league.divisionIds.contains(standing.divisionId) &&
              (_divisionId == null || standing.divisionId == _divisionId),
        )
        .toList(growable: false);
    final standingSections = <String?, List<PublicStanding>>{};
    for (final standing in standings) {
      standingSections
          .putIfAbsent(standing.divisionId, () => <PublicStanding>[])
          .add(standing);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DivisionFilter(
                    divisions: widget.snapshot.divisionsForLeague(
                      widget.league.leagueId,
                    ),
                    value: _divisionId,
                    onChanged: (value) => setState(() => _divisionId = value),
                  ),
                  if (standings.isNotEmpty &&
                      (widget.snapshot.canCreatePublishedArtifacts ||
                          isLegacyPublicTeamStandingsShareEligible(
                            widget.snapshot,
                          )))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          if (isLegacyPublicTeamStandingsShareEligible(
                            widget.snapshot,
                          )) {
                            await _showLegacyPublicStandingsShare(
                              context: context,
                              ref: ref,
                              snapshot: widget.snapshot,
                              league: widget.league,
                              divisionId: _divisionId,
                            );
                            return;
                          }
                          final branding = publicShareBranding(
                            widget.snapshot,
                            widget.league,
                          );
                          await _showValidatedPublicShare(
                            context: context,
                            ref: ref,
                            snapshot: widget.snapshot,
                            branding: branding,
                            payload: BrandedSharePayload.publicStandings(
                              snapshot: widget.snapshot,
                              standings: standings,
                              branding: branding,
                              divisionName: _divisionId == null
                                  ? null
                                  : widget.snapshot.divisionName(_divisionId),
                              canonicalUri: _publicCanonicalUri(
                                PublicRoutePaths.standings,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.ios_share_outlined, size: 18),
                        label: Text(
                          isLegacyPublicTeamStandingsShareEligible(
                                widget.snapshot,
                              )
                              ? 'Share standings'
                              : 'Share standings',
                        ),
                      ),
                    ),
                  if (widget.snapshot.standingsPolicyLabel == null) ...[
                    const AppStateMessage(
                      title: 'Ranking policy not published',
                      message:
                          'Rows stay in the league-published order. HoopsConnect does not use alphabetical order as a tie-breaker.',
                      tone: AppStateTone.warning,
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Text(
                      widget.snapshot.standingsPolicyLabel!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (standings.any(
                    (row) => row.rankStatus == PublicRankStatus.unresolved,
                  )) ...[
                    Text(
                      'Official ranks are not published yet. Records are grouped by division.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (standings.isEmpty)
                    const AppStateMessage(
                      title: 'No standings published',
                      message:
                          'There are no public standings for this division in the current snapshot.',
                    )
                  else
                    Card(
                      elevation: 2,
                      shadowColor: const Color(0x2B000000),
                      surfaceTintColor: Colors.transparent,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.white
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Column(
                        children: [
                          for (final section in standingSections.entries) ...[
                            if (_divisionId == null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  6,
                                ),
                                child: Text(
                                  widget.snapshot.divisionName(section.key),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            for (final row in section.value)
                              Builder(
                                builder: (context) {
                                  final recordDetails =
                                      '${_known(row.gamesPlayed)} GP · PF ${_known(row.pointsFor)} · PA ${_known(row.pointsAgainst)}';
                                  return ListTile(
                                    onTap: row.teamId == null
                                        ? null
                                        : () => context.push(
                                            PublicRoutePaths.team(row.teamId!),
                                          ),
                                    leading: CircleAvatar(
                                      child: Text(_rankLabel(row)),
                                    ),
                                    title: Text(
                                      row.teamName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(recordDetails),
                                    trailing: Text(
                                      _record(row.wins, row.losses),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeadersTab extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;

  const _LeadersTab({required this.snapshot, required this.league});

  @override
  ConsumerState<_LeadersTab> createState() => _LeadersTabState();
}

class _LeadersTabState extends ConsumerState<_LeadersTab> {
  String? _divisionId;
  int _selected = 0;

  @override
  void didUpdateWidget(covariant _LeadersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.league.leagueId != widget.league.leagueId) {
      _divisionId = null;
      _selected = 0;
    }
    if (_divisionId != null &&
        !widget.league.divisionIds.contains(_divisionId)) {
      _divisionId = null;
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boards = widget.snapshot.leaderboards
        .where(
          (board) =>
              widget.league.divisionIds.contains(board.divisionId) &&
              (_divisionId == null || board.divisionId == _divisionId),
        )
        .toList(growable: false);
    final safeIndex = boards.isEmpty
        ? 0
        : _selected.clamp(0, boards.length - 1);
    final board = boards.isEmpty ? null : boards[safeIndex];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            children: [
              const PublicStatsNavigation(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _DivisionFilter(
                  divisions: widget.snapshot.divisionsForLeague(
                    widget.league.leagueId,
                  ),
                  value: _divisionId,
                  onChanged: (value) => setState(() {
                    _divisionId = value;
                    _selected = 0;
                  }),
                ),
              ),
              if (boards.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < boards.length; i++)
                        ButtonSegment(
                          value: i,
                          label: Text(
                            _leaderboardSegmentLabel(
                              widget.snapshot,
                              boards[i],
                              includeDivision: _divisionId == null,
                            ),
                          ),
                        ),
                    ],
                    selected: {safeIndex},
                    onSelectionChanged: (value) =>
                        setState(() => _selected = value.first),
                  ),
                ),
              if (board != null &&
                  board.rankings.isNotEmpty &&
                  widget.snapshot.canCreatePublishedArtifacts &&
                  widget.snapshot.version.privacyEpoch != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextButton.icon(
                      onPressed: () async {
                        final branding = publicShareBranding(
                          widget.snapshot,
                          widget.league,
                        );
                        await _showValidatedPublicShare(
                          context: context,
                          ref: ref,
                          snapshot: widget.snapshot,
                          branding: branding,
                          payload: BrandedSharePayload.publicLeaderboard(
                            snapshot: widget.snapshot,
                            leaderboard: board,
                            branding: branding,
                            canonicalUri: _publicCanonicalUri(
                              PublicRoutePaths.leaders,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share_outlined, size: 18),
                      label: const Text('Share leaders'),
                    ),
                  ),
                ),
              Expanded(
                child: board == null
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: AppStateMessage(
                          title: 'No leaders published',
                          message:
                              'There are no cleared player leader rows for this division.',
                        ),
                      )
                    : ListView(
                        children: [
                          if (board.qualificationLabel == null)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: AppStateMessage(
                                title: 'Qualification criteria unavailable',
                                message:
                                    'The league has not published the minimum-games rule for this category.',
                                tone: AppStateTone.warning,
                                compact: true,
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Text(board.qualificationLabel!),
                            ),
                          if (board.rankings.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: AppStateMessage(
                                title: 'No cleared leaders published',
                                message:
                                    'No player identity rows are available for this category and division.',
                              ),
                            )
                          else
                            for (
                              var index = 0;
                              index < board.rankings.length;
                              index++
                            )
                              ListTile(
                                onTap: board.rankings[index].playerId == null
                                    ? null
                                    : () => context.push(
                                        PublicRoutePaths.player(
                                          board.rankings[index].playerId!,
                                        ),
                                      ),
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(board.rankings[index].displayName),
                                subtitle: Text(
                                  '${board.rankings[index].teamName} · ${_known(board.rankings[index].gamesPlayed)} GP',
                                ),
                                trailing: Text(
                                  _metric(board.rankings[index].value),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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

class _DivisionFilter extends StatelessWidget {
  final List<PublicDivision> divisions;
  final String? value;
  final ValueChanged<String?> onChanged;
  final EdgeInsetsGeometry padding;
  final bool compact;

  const _DivisionFilter({
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (divisions.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isDense: compact,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: compact ? null : 'Division',
          prefixIcon: compact ? null : const Icon(Icons.filter_list),
          border: compact
              ? const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                )
              : null,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
              : null,
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text(
              'All divisions',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...divisions.map(
            (division) => DropdownMenuItem<String?>(
              value: division.divisionId,
              child: Text(
                division.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

Future<void> _showValidatedPublicShare({
  required BuildContext context,
  required WidgetRef ref,
  required PublicLeagueSnapshot snapshot,
  required AssociationBrandingModel branding,
  required BrandedSharePayload payload,
}) async {
  try {
    final binding = PublicArtifactBinding.snapshot(snapshot);
    final validator = ref.read(publicArtifactReleaseValidatorProvider);
    await validator.requireCurrent(binding);
    if (!context.mounted) return;
    await showBrandedShareSheet(
      context: context,
      branding: branding,
      payload: payload,
      validateCurrent: () async {
        await validator.requireCurrent(binding);
      },
    );
  } on PublicArtifactReleaseException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${error.message} Refresh before sharing.')),
    );
  }
}

Future<void> _showLegacyPublicStandingsShare({
  required BuildContext context,
  required WidgetRef ref,
  required PublicLeagueSnapshot snapshot,
  required PublicLeagueDefinition league,
  required String? divisionId,
}) async {
  try {
    final validator = PublicLegacyStandingsShareValidator(
      ref.read(publicLeagueRepositoryProvider),
    );
    final current = await validator.requireCurrent(snapshot);
    if (!context.mounted) return;
    final currentRows = current.standings
        .where(
          (row) =>
              league.divisionIds.contains(row.divisionId) &&
              (divisionId == null || row.divisionId == divisionId),
        )
        .toList(growable: false);
    if (currentRows.isEmpty) return;
    final branding = publicShareBranding(current, league);
    await showBrandedShareSheet(
      context: context,
      branding: branding,
      payload: BrandedSharePayload.legacyPublicStandings(
        snapshot: current,
        standings: currentRows,
        branding: branding,
        divisionName: divisionId == null
            ? null
            : current.divisionName(divisionId),
      ),
      validateCurrent: () async {
        await validator.requireCurrent(snapshot);
      },
    );
  } on PublicArtifactReleaseException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}

Uri? _publicCanonicalUri(String path) {
  final base = Uri.base;
  if (base.scheme != 'http' && base.scheme != 'https') return null;
  return base.resolve(path);
}

class _PublicState extends StatelessWidget {
  final String title;
  final String message;
  final AppStateTone tone;
  final VoidCallback onRetry;

  const _PublicState({
    required this.title,
    required this.message,
    this.tone = AppStateTone.neutral,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AppStateMessage(
        title: title,
        message: message,
        tone: tone,
        actionLabel: 'Try again',
        onAction: onRetry,
      ),
    ),
  );
}

String _rankLabel(PublicStanding standing) => switch (standing.rankStatus) {
  PublicRankStatus.ranked => standing.rank?.toString() ?? '—',
  PublicRankStatus.tied => standing.rank == null ? '—' : 'T${standing.rank}',
  PublicRankStatus.unresolved => '—',
};

String _known(int? value) => value?.toString() ?? 'Unknown';

String _record(int? wins, int? losses) =>
    wins == null || losses == null ? 'Unknown' : '$wins-$losses';

String _metric(double? value) => value?.toStringAsFixed(1) ?? 'Unknown';

String _leaderboardSegmentLabel(
  PublicLeagueSnapshot snapshot,
  PublicLeaderboard board, {
  required bool includeDivision,
}) {
  if (!includeDivision || board.divisionId == null) {
    return board.categoryLabel;
  }
  return '${board.categoryLabel} · ${snapshot.divisionName(board.divisionId)}';
}

String _gameStatusLabel(PublicGameStatus status) => switch (status) {
  PublicGameStatus.finalResult => 'Final',
  PublicGameStatus.scheduled => 'Scheduled',
  PublicGameStatus.postponed => 'Postponed',
  PublicGameStatus.canceled => 'Canceled',
};
