import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/widgets/public_brand_context.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';
import 'public_team_identity.dart';

class PublicPlayerDetailScreen extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicPlayerDetail detail;
  final Uri? canonicalUri;

  const PublicPlayerDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
    this.canonicalUri,
  });

  @override
  ConsumerState<PublicPlayerDetailScreen> createState() =>
      _PublicPlayerDetailScreenState();
}

class _PublicPlayerDetailScreenState
    extends ConsumerState<PublicPlayerDetailScreen> {
  PublicLeagueSnapshot get snapshot => widget.snapshot;
  PublicPlayerDetail get detail => widget.detail;
  Uri? get canonicalUri => widget.canonicalUri;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isFollowing =
        user?.favoritePlayerIds.contains(widget.detail.playerId) ?? false;
    final divisionId = detail.categories.isEmpty
        ? null
        : detail.categories.first.divisionId;
    final league = snapshot.leagueForDivision(divisionId);
    final teamId = detail.categories.isEmpty
        ? null
        : detail.categories.first.value.teamId;
    return Scaffold(
      backgroundColor: publicSportsCanvas,
      appBar: AppBar(
        backgroundColor: const Color(0xFF234EBD),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: publicRoyalGradient),
        ),
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(PublicRoutePaths.leaders),
          tooltip: 'Back to public leaders',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Player details'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            key: const Key('follow-player-button'),
            onPressed: _saving
                ? null
                : () async {
                    if (user == null) {
                      context.go(
                        AppRouteContract.loginFor(
                          Uri.parse(
                            PublicRoutePaths.player(widget.detail.playerId),
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => _saving = true);
                    try {
                      await ref.read(authRepositoryProvider).updateUser(
                        user.id,
                        {
                          'favoritePlayerIds': isFollowing
                              ? FieldValue.arrayRemove([widget.detail.playerId])
                              : FieldValue.arrayUnion([widget.detail.playerId]),
                        },
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not update player follow. Try again.',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            icon: Icon(isFollowing ? Icons.check : Icons.person_add_alt_1),
            label: Text(isFollowing ? 'Following' : 'Follow'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.compare_arrows, size: 20),
            label: const Text('Compare'),
            onPressed: () => context.push(
              '/public/compare?player=${Uri.encodeComponent(detail.playerId)}',
            ),
          ),
          if (snapshot.canCreatePublishedArtifacts &&
              snapshot.version.privacyEpoch != null &&
              detail.categories.isNotEmpty)
            IconButton(
              onPressed: () => _share(context, ref, league),
              tooltip: 'Share player spotlight',
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
      body: Theme(
        data: publicSportsTheme(context),
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PublicBrandContext(
                      snapshot: snapshot,
                      league: league,
                      divisionName: snapshot.divisionName(divisionId),
                      showSponsorText: true,
                    ),
                    const SizedBox(height: 16),
                    _PlayerHero(
                      snapshot: snapshot,
                      detail: detail,
                      teamId: teamId,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      league.historicalStatistics
                          ? '${league.seasonLabel} · Per-game averages'
                          : 'Published season stats',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF0B1D3A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PlayerSectionCard(
                      child: Column(
                        children: detail.categories
                            .map(
                              (entry) => ListTile(
                                title: Text(_categoryLabel(entry.category)),
                                subtitle: Text(
                                  '${entry.value.cumulativeTotal == null ? snapshot.divisionName(entry.divisionId) : '${entry.value.cumulativeTotal} total'} · ${_gamesPlayed(entry.value.gamesPlayed)}',
                                ),
                                trailing: Text(
                                  _metric(entry.value.value),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: const Color(0xFF184A9E),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    if (detail.categories.any(
                      (entry) => entry.value.shootingMade.isNotEmpty,
                    )) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Shots made',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF0B1D3A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PlayerSectionCard(
                        child: Column(
                          children: [
                            for (final entry in const {
                              'twoMade': 'Two-pointers',
                              'threeMade': 'Three-pointers',
                              'ftMade': 'Free throws',
                            }.entries)
                              ListTile(
                                title: Text(entry.value),
                                trailing: Text(
                                  '${detail.categories.firstWhere((c) => c.value.shootingMade.isNotEmpty).value.shootingMade[entry.key] ?? '—'}',
                                  style: const TextStyle(
                                    color: Color(0xFF184A9E),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      league.historicalStatistics
                          ? '${league.description}. Cumulative statistics through the recorded date.'
                          : 'Only fields cleared for this public snapshot are shown. No profile, contact, school, guardian, or account data is loaded.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    PublicLeagueDefinition league,
  ) async {
    try {
      final binding = PublicArtifactBinding.snapshot(snapshot);
      final validator = ref.read(publicArtifactReleaseValidatorProvider);
      await validator.requireCurrent(binding);
      if (!context.mounted) return;
      final branding = publicShareBranding(snapshot, league);
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.publicPlayer(
          snapshot: snapshot,
          player: detail,
          branding: branding,
          canonicalUri: canonicalUri,
        ),
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
}

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({
    required this.snapshot,
    required this.detail,
    required this.teamId,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicPlayerDetail detail;
  final String? teamId;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: publicRoyalGradient,
      boxShadow: const [
        BoxShadow(
          color: Color(0x24102A70),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: Colors.white,
          child: Text(
            detail.displayName.trim().isEmpty
                ? '?'
                : detail.displayName.trim()[0].toUpperCase(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: const Color(0xFF184A9E),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail.teamName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        PublicTeamMark(
          snapshot: snapshot,
          teamId: teamId,
          name: detail.teamName,
          size: 58,
          onDarkSurface: true,
        ),
      ],
    ),
  );
}

class _PlayerSectionCard extends StatelessWidget {
  const _PlayerSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x100B1D3A),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

String _categoryLabel(String category) => switch (category.toLowerCase()) {
  'ppg' => 'Points per game',
  'rpg' => 'Rebounds per game',
  'apg' => 'Assists per game',
  'spg' => 'Steals per game',
  'bpg' => 'Blocks per game',
  _ => category.toUpperCase(),
};

String _gamesPlayed(int? count) => count == null
    ? 'Games played unavailable'
    : '$count ${count == 1 ? 'game' : 'games'} played';

String _metric(double? value) => value?.toStringAsFixed(1) ?? 'Unknown';
