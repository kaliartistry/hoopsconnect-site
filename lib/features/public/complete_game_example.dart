import 'package:flutter/material.dart';
import '../../models/public_league_snapshot.dart';

/// Explicit presentation adjustments. Original workbooks and published period
/// records are not changed. Each proposed split must reconcile to its final.
List<PublicPeriodScore> presentationQuarterScores(PublicGame game) {
  final List<List<int>>? scores = switch (game.gameId) {
    'jbl-2025-02-13-rae-town-raptors-vs-st-georges-slayers' => [
      [15, 11],
      [18, 19],
      [20, 13],
      [18, 17],
    ],
    'jbl-2025-04-22-rae-town-raptors-vs-tivoli-wizards' => [
      [10, 10],
      [9, 13],
      [15, 26],
      [13, 13],
    ],
    _ => null,
  };
  if (scores == null ||
      scores.fold<int>(0, (sum, row) => sum + row[0]) != game.homeScore ||
      scores.fold<int>(0, (sum, row) => sum + row[1]) != game.awayScore) {
    return const [];
  }
  return [
    for (var i = 0; i < scores.length; i++)
      PublicPeriodScore(
        period: i + 1,
        homeScore: scores[i][0],
        awayScore: scores[i][1],
      ),
  ];
}

Future<void> showPresentationQuarters(
  BuildContext context,
  PublicGame game,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Quarter scores'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${game.homeTeamName} ${game.homeScore} · ${game.awayScore} ${game.awayTeamName}',
          ),
          const SizedBox(height: 16),
          for (final quarter in presentationQuarterScores(game))
            ListTile(
              title: Text('Quarter ${quarter.period}'),
              trailing: Text('${quarter.homeScore} – ${quarter.awayScore}'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Presentation breakdown · Adjusted to match the supplied final score. Original source figures are retained separately.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

/// Presentation-only, never written to league records or included in rankings.
class CompleteGameExample extends StatelessWidget {
  const CompleteGameExample({super.key});

  static const teams = ['Harbour Kings', 'Hillside Raiders'];
  // Name, points, rebounds, assists, steals, blocks. Fictional identities.
  static const lines = [
    ['A. Grant', 24, 9, 6, 2, 1],
    ['B. Reid', 18, 8, 5, 2, 0],
    ['C. Davis', 16, 12, 3, 1, 3],
    ['D. Campbell', 14, 7, 4, 2, 1],
    ['E. James', 10, 8, 4, 1, 0],
    ['F. Lewis', 22, 8, 5, 2, 0],
    ['G. Brown', 18, 7, 4, 1, 1],
    ['H. Clarke', 14, 10, 2, 1, 2],
    ['I. Thompson', 12, 6, 4, 1, 0],
    ['J. Wilson', 10, 7, 3, 1, 0],
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Game statistics')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Illustrative example · Not a recorded game\n'
              'These fictional teams and statistics show the detail that can be retained when every player’s statistics are entered. They do not affect JBL standings or player totals.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Harbour Kings 82 — 76 Hillside Raiders',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Quarter scores: 21–18 · 19–20 · 20–19 · 22–19'),
        const SizedBox(height: 20),
        Text('Team comparison', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final item in const [
          ['Points', '82', '76'],
          ['Rebounds', '44', '38'],
          ['Assists', '22', '18'],
          ['Steals', '8', '6'],
          ['Blocks', '5', '3'],
        ])
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      item[1],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(child: Text(item[0], textAlign: TextAlign.center)),
                  SizedBox(
                    width: 36,
                    child: Text(
                      item[2],
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (var team = 0; team < 2; team++) ...[
          const SizedBox(height: 20),
          Text(teams[team], style: Theme.of(context).textTheme.titleLarge),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 8,
              columns: [
                for (final label in [
                  'Player',
                  'PTS',
                  'REB',
                  'AST',
                  'STL',
                  'BLK',
                ])
                  DataColumn(label: Text(label), numeric: label != 'Player'),
              ],
              rows: [
                for (final line in lines.skip(team * 5).take(5))
                  DataRow(
                    cells: [for (final value in line) DataCell(Text('$value'))],
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'The uploaded historical reports contain selected performers, not complete player lists. Those partial records stay separate from this example.',
        ),
      ],
    ),
  );
}
