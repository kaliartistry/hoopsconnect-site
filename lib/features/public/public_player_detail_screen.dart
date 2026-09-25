import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';

class PublicPlayerDetailScreen extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicPlayerDetail detail;

  const PublicPlayerDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
  });

  @override
  ConsumerState<PublicPlayerDetailScreen> createState() =>
      _PublicPlayerDetailScreenState();
}

class _PublicPlayerDetailScreenState
    extends ConsumerState<PublicPlayerDetailScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isFollowing =
        user?.favoritePlayerIds.contains(widget.detail.playerId) ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(PublicRoutePaths.leaders),
          tooltip: 'Back to public leaders',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Player details'),
        actions: [
          TextButton.icon(
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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          CircleAvatar(
            radius: 34,
            child: Text(
              widget.detail.displayName.trim().isEmpty
                  ? '?'
                  : widget.detail.displayName.trim()[0].toUpperCase(),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.detail.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            widget.detail.teamName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Published season stats',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: widget.detail.categories
                  .map(
                    (entry) => ListTile(
                      title: Text(_categoryLabel(entry.category)),
                      subtitle: Text(
                        '${widget.snapshot.divisionName(entry.divisionId)} · ${_gamesPlayed(entry.value.gamesPlayed)}',
                      ),
                      trailing: Text(
                        _metric(entry.value.value),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Only fields cleared for this public snapshot are shown. No profile, contact, school, guardian, or account data is loaded.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
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
