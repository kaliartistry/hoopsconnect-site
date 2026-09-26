import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/public/complete_game_example.dart';

void main() {
  test('illustrative player lines reconcile to both team totals', () {
    const expected = [
      [82, 44, 22, 8, 5],
      [76, 38, 18, 6, 3],
    ];
    for (var team = 0; team < 2; team++) {
      for (var stat = 1; stat <= 5; stat++) {
        expect(
          CompleteGameExample.lines
              .skip(team * 5)
              .take(5)
              .fold<int>(0, (sum, line) => sum + (line[stat] as int)),
          expected[team][stat - 1],
        );
      }
    }
  });
  testWidgets('presentation example remains visibly separate from records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CompleteGameExample()));
    expect(find.textContaining('Not a recorded game'), findsOneWidget);
    expect(find.text('Team comparison'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
