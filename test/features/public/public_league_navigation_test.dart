import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/features/public/public_league_screen.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

void main() {
  testWidgets('public Sign in goes explicitly to the login route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/public/games',
      routes: [
        GoRoute(
          path: '/public/games',
          builder: (_, _) => const PublicLeagueScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicLeagueSnapshotProvider.overrideWith(
            (ref) => Stream<PublicLeagueSnapshot?>.value(null),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login destination'), findsOneWidget);
  });
}
