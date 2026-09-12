import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/admin/widgets/season_management_panel.dart';
import 'package:hoops_connect/models/league_workflow_capability.dart';
import 'package:hoops_connect/models/season_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/league_workflow_providers.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/services/repositories/season_repository.dart';

void main() {
  testWidgets('season cards render at phone and wide sizes', (tester) async {
    for (final size in const [
      Size(375, 812),
      Size(768, 1024),
      Size(1440, 1000),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(_viewApp());
      await tester.pumpAndSettle();

      expect(find.text('NBL 2026'), findsOneWidget, reason: '$size');
      expect(find.text('NBL 2027'), findsOneWidget, reason: '$size');
      expect(find.text('CURRENT'), findsOneWidget, reason: '$size');
      expect(find.text('Activate'), findsOneWidget, reason: '$size');
      expect(find.byKey(const Key('leaderboard-view-only')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
      tester.view.reset();
    }
  });

  testWidgets('dark mode keeps lifecycle guidance and actions visible', (
    tester,
  ) async {
    await tester.pumpWidget(_viewApp(dark: true));
    await tester.pumpAndSettle();
    expect(find.text('Prepare season'), findsOneWidget);
    expect(find.text('ARCHIVED'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text at narrow width has no overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2),
        ),
        child: _viewApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prepare season'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed readiness gate disables every mutation', (tester) async {
    await tester.pumpWidget(_viewApp(enabled: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('season-workflow-closed')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prepare-season')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Activate'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('pending operation disables every mutation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeasonManagementView(
              seasons: _seasons,
              currentSeasonId: 'nbl-2026',
              workflowEnabled: true,
              loading: false,
              busySeasonId: 'nbl-2027',
              message: null,
              error: null,
              canRetry: false,
              onRetry: null,
              canDiscard: false,
              onDiscard: null,
              onPrepare: () {},
              onActivate: (_) {},
              onArchive: (_) {},
              onRestore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('season-operation-pending')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('prepare-season')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Archive'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Restore'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('retry and explicit discard recovery states are usable', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeasonManagementView(
              seasons: _seasons,
              currentSeasonId: 'nbl-2026',
              workflowEnabled: true,
              loading: false,
              busySeasonId: null,
              message: null,
              error: 'The result is uncertain.',
              canRetry: true,
              onRetry: () => retries++,
              canDiscard: true,
              onDiscard: () => discards++,
              onPrepare: () {},
              onActivate: (_) {},
              onArchive: (_) {},
              onRestore: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('The result is uncertain.'), findsOneWidget);
    await tester.tap(find.text('Retry safely'));
    expect(retries, 1);
    await tester.tap(find.text('Discard saved retry'));
    expect(discards, 1);
  });

  testWidgets('cancelling archive confirmation performs no callable write', (
    tester,
  ) async {
    final repository = _RecordingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(const AsyncValue.data(_admin)),
          activeSeasonIdProvider.overrideWith(
            (ref) => Stream.value('nbl-2026'),
          ),
          seasonsStreamProvider.overrideWith((ref) => Stream.value(_seasons)),
          leagueWorkflowCapabilityProvider.overrideWith(
            (ref) => Stream.value(_workflow),
          ),
          seasonRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SeasonManagementDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('season-nbl-2025')),
        matching: find.widgetWithText(OutlinedButton, 'Archive'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archive NBL 2025?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);
  });
}

Widget _viewApp({bool dark = false, bool enabled = true}) {
  return MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SeasonManagementView(
          seasons: _seasons,
          currentSeasonId: 'nbl-2026',
          workflowEnabled: enabled,
          loading: false,
          busySeasonId: null,
          message: null,
          error: null,
          canRetry: false,
          onRetry: null,
          canDiscard: false,
          onDiscard: null,
          onPrepare: enabled ? () {} : null,
          onActivate: enabled ? (_) {} : null,
          onArchive: enabled ? (_) {} : null,
          onRestore: enabled ? (_) {} : null,
        ),
      ),
    ),
  );
}

const _seasons = [
  SeasonModel(
    id: 'nbl-2026',
    associationId: 'jba',
    name: 'NBL 2026',
    startDate: '2026-01-01',
    endDate: '2026-09-01',
    status: SeasonStatus.active,
    version: 2,
  ),
  SeasonModel(
    id: 'nbl-2027',
    associationId: 'jba',
    name: 'NBL 2027',
    startDate: '2027-01-01',
    endDate: '2027-09-01',
    status: SeasonStatus.prepared,
    version: 1,
  ),
  SeasonModel(
    id: 'nbl-2025',
    associationId: 'jba',
    name: 'NBL 2025',
    startDate: '2025-01-01',
    endDate: '2025-09-01',
    status: SeasonStatus.inactive,
    version: 4,
  ),
  SeasonModel(
    id: 'nbl-2024',
    associationId: 'jba',
    name: 'NBL 2024',
    startDate: '2024-01-01',
    endDate: '2024-09-01',
    status: SeasonStatus.archived,
    version: 7,
  ),
];

const _admin = UserModel(
  id: 'admin',
  email: 'admin@example.com',
  displayName: 'Admin',
  associationId: 'jba',
  role: UserRole.superAdmin,
  capabilities: {'association.read', 'association.manage'},
);

const _workflow = LeagueWorkflowCapability(
  associationId: 'jba',
  competitionId: 'nbl',
  activeSeasonId: 'nbl-2026',
  defaultPhaseId: 'regular',
  authorityMode: 'legacyV1',
  callablesReady: true,
  directWritesDenied: true,
  lifecycleAuthorityReady: true,
  custodyAuthorityReady: true,
  actorAuthorityReady: true,
  identityAuthorityReady: true,
  privacyAuthorityReady: true,
  custodyPolicyVersionV2: 1,
  privacyEpochV2: 1,
  clientAuthorizationSchemaVersion: 1,
  rosters: true,
  divisionDeletion: true,
  scheduling: true,
  seasonLifecycle: true,
);

class _RecordingRepository extends SeasonRepository {
  int calls = 0;

  _RecordingRepository()
    : super(
        operationStore: _NoopStore(),
        callable: (_, _) async => throw StateError('unexpected call'),
      );

  @override
  Future<SeasonOperationReceipt> archiveSeason({
    required String actorId,
    required String associationId,
    required SeasonModel season,
    required String currentSeasonId,
  }) async {
    calls++;
    throw StateError('unexpected call');
  }
}

class _NoopStore implements SeasonOperationStore {
  @override
  Future<void> clear(String key) async {}

  @override
  Future<SeasonPendingOperation?> load(String key) async => null;

  @override
  Future<void> save(SeasonPendingOperation operation) async {}
}
