import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/schedule_generator_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';

void main() {
  test(
    'schedule capacity reports incomplete and complete previews honestly',
    () {
      final incomplete = assessSchedulePreviewCapacity(
        requestedGameCount: 12,
        feasibleGameCount: 8,
      );

      expect(incomplete.isComplete, isFalse);
      expect(incomplete.missingGameCount, 4);
      expect(incomplete.blockingMessage, contains('Requested 12 games'));
      expect(incomplete.blockingMessage, contains('only 8 fit'));
      expect(incomplete.blockingMessage, contains('Add game days'));

      final complete = assessSchedulePreviewCapacity(
        requestedGameCount: 8,
        feasibleGameCount: 8,
      );
      expect(complete.isComplete, isTrue);
      expect(complete.missingGameCount, 0);
    },
  );

  testWidgets('invalid custom rounds block advancement', (tester) async {
    await _pumpGenerator(tester, teamCount: 2);
    await _selectDivision(tester);
    await _tapControl(tester, 'Next');

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pumpAndSettle();

    expect(find.text('0 games will be generated'), findsOneWidget);
    await _tapControl(tester, 'Next');

    expect(find.text('Enter a whole number from 1 to 6.'), findsWidgets);
    expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 1);
  });

  testWidgets('incomplete preview shows counts and stays on venue step', (
    tester,
  ) async {
    await _pumpGenerator(tester, teamCount: 20);
    await _selectDivision(tester);
    await _tapControl(tester, 'Next');
    await _tapControl(tester, 'Next');
    await _tapControl(tester, 'Next');

    await _tapControl(tester, 'Preview');

    expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 3);
    expect(find.text('Schedule preview blocked'), findsOneWidget);
    expect(find.textContaining('Requested 380 games'), findsOneWidget);
    expect(find.textContaining('Add game days or time slots'), findsOneWidget);
  });
}

Future<void> _pumpGenerator(
  WidgetTester tester, {
  required int teamCount,
}) async {
  final teams = List<TeamModel>.generate(
    teamCount,
    (index) => TeamModel(
      id: 'team_$index',
      name: 'Team $index',
      divisionId: 'premier',
      seasonId: 'season_1',
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeSeasonIdProvider.overrideWith((ref) => Stream.value('season_1')),
        divisionsStreamProvider.overrideWith(
          (ref) => Stream.value(const [
            DivisionModel(id: 'premier', name: 'Premier', seasonId: 'season_1'),
          ]),
        ),
        teamsStreamProvider.overrideWith((ref) => Stream.value(teams)),
      ],
      child: const MaterialApp(home: ScheduleGeneratorScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDivision(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Premier').last);
  await tester.pumpAndSettle();
}

Future<void> _tapControl(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label).hitTestable();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
