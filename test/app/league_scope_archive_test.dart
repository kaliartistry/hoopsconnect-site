import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoops_connect/app/app_shell.dart';
import 'package:hoops_connect/app/router/app_route_contract.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';
import 'package:hoops_connect/providers/association_branding_providers.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/connectivity_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/inbox_providers.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';

void main() {
  testWidgets('a signed-in league scope opens its historical season', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const archive = '2025 NBL season';
    const league = LeagueProfileModel(
      id: 'jbl',
      name: 'Jamaica Basketball League',
      shortName: 'JBL',
      divisionIds: ['jbl-2025'],
      historicalStatistics: true,
      seasonLabel: archive,
    );
    final router = GoRouter(
      initialLocation: '/standings',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final path in ['/board', '/standings', '/stats', '/calendar'])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: path,
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
        GoRoute(
          path: PublicRoutePaths.standings,
          builder: (_, _) => const Scaffold(body: Text('Historical standings')),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(const AsyncValue.data(null)),
        isOnlineProvider.overrideWith((_) => Stream.value(true)),
        inboxUnreadCountProvider.overrideWith((_) => Stream.value(0)),
        effectiveAssociationBrandingProvider.overrideWithValue(
          AssociationBrandingModel.jba(),
        ),
        leagueCatalogProvider.overrideWith(
          (_) => Stream.value(const LeagueCatalogModel(leagues: [league])),
        ),
        divisionsStreamProvider.overrideWith(
          (_) => Stream.value(const [
            DivisionModel(id: 'jbl-2025', name: archive, leagueId: 'jbl'),
            DivisionModel(
              id: 'sample',
              name: 'Premier Division',
              status: DivisionStatus.archived,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(league.name), findsOneWidget);
    expect(find.text('All leagues'), findsNothing);
    expect(find.text('Premier Division'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, archive));
    await tester.pumpAndSettle();

    expect(container.read(publicSelectedLeagueIdProvider), 'jbl');
    expect(find.text('Historical standings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
