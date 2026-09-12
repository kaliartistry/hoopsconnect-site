import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../models/public_league_snapshot.dart';

class PublicPlayerDetailScreen extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicPlayerDetail detail;

  const PublicPlayerDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(PublicRoutePaths.leaders),
          tooltip: 'Back to public leaders',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Player details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          CircleAvatar(
            radius: 34,
            child: Text(
              detail.displayName.trim().isEmpty
                  ? '?'
                  : detail.displayName.trim()[0].toUpperCase(),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            detail.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            detail.teamName,
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
              children: detail.categories
                  .map(
                    (entry) => ListTile(
                      title: Text(_categoryLabel(entry.category)),
                      subtitle: Text(
                        '${snapshot.divisionName(entry.divisionId)} · ${_gamesPlayed(entry.value.gamesPlayed)}',
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
