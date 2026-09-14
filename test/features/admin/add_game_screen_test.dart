import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/add_game_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';

void main() {
  testWidgets('manual schedule commit stays visibly disabled', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeSeasonIdProvider.overrideWith(
            (ref) => Stream.value('season_1'),
          ),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(id: 'premier', name: 'Premier'),
            ]),
          ),
          teamsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: AddGameScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save unavailable'), findsOneWidget);
    expect(find.text('Scheduling save is not available yet'), findsOneWidget);
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save unavailable'),
    );
    expect(save.onPressed, isNull);
  });
}
