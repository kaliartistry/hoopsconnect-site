import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The same discoverable entry points for guests and signed-in fans.
class PublicStatsNavigation extends StatelessWidget {
  const PublicStatsNavigation({super.key, this.selected = 'players'});
  final String selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'players', label: Text('Players')),
          ButtonSegment(value: 'teams', label: Text('Teams')),
          ButtonSegment(value: 'compare', label: Text('Compare')),
        ],
        selected: {selected},
        onSelectionChanged: (value) {
          final path = switch (value.first) {
            'teams' => '/public/team-stats',
            'compare' => '/public/compare',
            _ => '/public/leaders',
          };
          context.push(path);
        },
      ),
    ),
  );
}
