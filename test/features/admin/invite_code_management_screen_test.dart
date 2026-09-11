import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/admin/invite_code_management_screen.dart';
import 'package:hoops_connect/models/invite_code_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';
import 'package:hoops_connect/services/repositories/invite_code_repository.dart';

void main() {
  testWidgets('uses an association-scoped team picker instead of a raw ID', (
    tester,
  ) async {
    final repository = _FakeInviteCodeRepository();
    final store = _MemoryAttemptStore();
    await _pumpScreen(tester, repository: repository, attemptStore: store);

    await tester.tap(find.text('Generate invite'));
    await tester.pumpAndSettle();

    expect(find.text('Team ID'), findsNothing);
    expect(find.text('Team (required)'), findsOneWidget);
    expect(find.text('Select a team'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invite-team-rep-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Mountains • Season season-1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-invite-submit')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, hasLength(1));
    expect(repository.createCalls.single.teamId, 'team-blue');
    expect(find.byKey(const Key('issued-invite-secret')), findsOneWidget);
    expect(store.attempt, isNotNull);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(store.attempt, isNull);
    expect(find.byKey(const Key('issued-invite-secret')), findsNothing);
  });

  testWidgets(
    'lost response retries the same request and clipboard failure keeps secret visible',
    (tester) async {
      final repository = _FakeInviteCodeRepository(
        createResults: [
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'response lost after commit',
          ),
          _issuedInvite,
        ],
      );
      var copyCalls = 0;
      await _pumpScreen(
        tester,
        repository: repository,
        copySecret: (secret) async {
          copyCalls += 1;
          if (copyCalls == 1) throw StateError('clipboard denied');
        },
      );
      await _openAndSelectBlueTeam(tester);

      await tester.tap(find.byKey(const Key('generate-invite-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Retry same request'), findsOneWidget);
      expect(find.textContaining('response was lost'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);

      await tester.tap(find.byKey(const Key('generate-invite-submit')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(2));
      expect(repository.createCalls.map((call) => call.operationId).toSet(), {
        'fixed_create_operation_0001',
      });
      expect(find.text(_issuedInvite.code), findsOneWidget);
      expect(find.byKey(const Key('invite-copy-error')), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);

      await tester.tap(find.text('Copy code'));
      await tester.pumpAndSettle();

      expect(copyCalls, 2);
      expect(find.text('Copied'), findsOneWidget);
      expect(find.byKey(const Key('invite-copy-error')), findsNothing);
    },
  );

  testWidgets(
    'restart recovers the persisted logical request without a duplicate',
    (tester) async {
      final store = _MemoryAttemptStore();
      final repository = _FakeInviteCodeRepository(
        createResults: [
          FirebaseFunctionsException(
            code: 'unavailable',
            message: 'response lost after commit',
          ),
          _issuedInvite,
        ],
      );
      await _pumpScreen(tester, repository: repository, attemptStore: store);
      await _openAndSelectBlueTeam(tester);
      await tester.tap(find.byKey(const Key('generate-invite-submit')));
      await tester.pumpAndSettle();
      expect(store.attempt, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpScreen(tester, repository: repository, attemptStore: store);
      await tester.tap(find.text('Generate invite'));
      await tester.pumpAndSettle();

      expect(find.text('Recover invite'), findsOneWidget);
      expect(find.textContaining('unfinished invite request'), findsOneWidget);
      await tester.tap(find.byKey(const Key('generate-invite-submit')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(2));
      expect(repository.createCalls.map((call) => call.operationId).toSet(), {
        'fixed_create_operation_0001',
      });
      expect(find.text(_issuedInvite.code), findsOneWidget);
    },
  );

  testWidgets('blocks duplicate submits while creation is in flight', (
    tester,
  ) async {
    final pending = Completer<IssuedInviteCode>();
    final repository = _FakeInviteCodeRepository(pendingCreate: pending);
    await _pumpScreen(tester, repository: repository);
    await _openAndSelectBlueTeam(tester);

    final submit = find.byKey(const Key('generate-invite-submit'));
    await tester.tap(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();

    expect(repository.createCalls, hasLength(1));
    pending.complete(_issuedInvite);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('issued-invite-secret')), findsOneWidget);
  });

  testWidgets('revoke requires confirmation and reports a confirmed outcome', (
    tester,
  ) async {
    final active = InviteCodeModel(
      inviteId: 'v2_${'d' * 64}',
      teamId: 'team-blue',
      role: 'rep',
      usesRemaining: 1,
      status: 'active',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      associationId: 'jba',
    );
    final repository = _FakeInviteCodeRepository(codes: [active]);
    await _pumpScreen(tester, repository: repository);
    final revokeButton = find.byTooltip('Revoke ${active.displayId}');

    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    expect(find.text('Revoke invite?'), findsOneWidget);
    await tester.tap(find.text('Keep active'));
    await tester.pumpAndSettle();
    expect(repository.revokedIds, isEmpty);

    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke invite'));
    await tester.pump();
    await tester.pump();

    expect(repository.revokedIds, [active.inviteId]);
    expect(
      find.text('Invite ${active.displayId} was revoked.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'terminal creation errors are actionable and do not leak details',
    (tester) async {
      final repository = _FakeInviteCodeRepository(
        createResults: [
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'internal actor and association details',
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);
      await _openAndSelectBlueTeam(tester);

      await tester.tap(find.byKey(const Key('generate-invite-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('invite permissions changed'), findsOneWidget);
      expect(find.textContaining('internal actor'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets('revoke rejection is safe and offers a refresh action', (
    tester,
  ) async {
    final active = InviteCodeModel(
      inviteId: 'v2_${'e' * 64}',
      teamId: null,
      role: 'media',
      usesRemaining: 1,
      status: 'active',
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      associationId: 'jba',
    );
    final repository = _FakeInviteCodeRepository(
      codes: [active],
      revokeError: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'internal receipt and actor details',
      ),
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byTooltip('Revoke ${active.displayId}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke invite'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('no longer active'), findsOneWidget);
    expect(find.textContaining('internal receipt'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeInviteCodeRepository repository,
  InviteSecretCopier? copySecret,
  InviteCreationAttemptStore? attemptStore,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          const AsyncValue.data(
            UserModel(
              id: 'admin-1',
              email: 'admin@example.com',
              displayName: 'Admin',
              associationId: 'jba',
              role: UserRole.superAdmin,
              capabilities: {'invites.manage', 'association.read'},
            ),
          ),
        ),
        currentAssociationIdProvider.overrideWithValue('jba'),
        inviteCodeRepositoryProvider.overrideWithValue(repository),
        teamsStreamProvider.overrideWith(
          (ref) => Stream.value([
            TeamModel(
              id: 'team-blue',
              name: 'Blue Mountains',
              divisionId: 'division-1',
              seasonId: 'season-1',
            ),
            TeamModel(
              id: 'team-kingston',
              name: 'Kingston Lions',
              divisionId: 'division-1',
              seasonId: 'season-1',
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: InviteCodeManagementScreen(
          copySecret: copySecret ?? (_) async {},
          operationIdFactory: () => 'fixed_create_operation_0001',
          attemptStore: attemptStore ?? _MemoryAttemptStore(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAndSelectBlueTeam(WidgetTester tester) async {
  await tester.tap(find.text('Generate invite'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('invite-team-rep-null')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Blue Mountains • Season season-1').last);
  await tester.pumpAndSettle();
}

final _issuedInvite = IssuedInviteCode(
  invite: InviteCodeModel(
    inviteId: 'v2_${'c' * 64}',
    teamId: 'team-blue',
    role: 'rep',
    usesRemaining: 1,
    status: 'active',
    expiresAt: DateTime(2030),
    associationId: 'jba',
  ),
  code: 'S' * 43,
);

class _CreateCall {
  final String role;
  final String? teamId;
  final int daysValid;
  final String operationId;

  const _CreateCall({
    required this.role,
    required this.teamId,
    required this.daysValid,
    required this.operationId,
  });
}

class _FakeInviteCodeRepository extends InviteCodeRepository {
  final List<InviteCodeModel> codes;
  final List<Object> createResults;
  final Completer<IssuedInviteCode>? pendingCreate;
  final Object? revokeError;
  final List<_CreateCall> createCalls = [];
  final List<String> revokedIds = [];

  _FakeInviteCodeRepository({
    List<InviteCodeModel>? codes,
    List<Object>? createResults,
    this.pendingCreate,
    this.revokeError,
  }) : codes = codes ?? [],
       createResults = createResults ?? [_issuedInvite];

  @override
  Future<List<InviteCodeModel>> getAllCodes(String associationId) async {
    expect(associationId, 'jba');
    return List.of(codes);
  }

  @override
  Future<IssuedInviteCode> createCode({
    required String role,
    String? teamId,
    required int daysValid,
    required String operationId,
  }) async {
    createCalls.add(
      _CreateCall(
        role: role,
        teamId: teamId,
        daysValid: daysValid,
        operationId: operationId,
      ),
    );
    if (pendingCreate != null) return pendingCreate!.future;
    final result = createResults[createCalls.length - 1];
    if (result is Error || result is Exception) throw result;
    return result as IssuedInviteCode;
  }

  @override
  Future<void> revokeCode(String inviteId) async {
    if (revokeError != null) throw revokeError!;
    revokedIds.add(inviteId);
    codes.removeWhere((code) => code.inviteId == inviteId);
  }
}

class _MemoryAttemptStore implements InviteCreationAttemptStore {
  InviteCreationAttempt? attempt;

  @override
  Future<void> clear({
    required String actorId,
    required String associationId,
  }) async {
    expect(actorId, 'admin-1');
    expect(associationId, 'jba');
    attempt = null;
  }

  @override
  Future<InviteCreationAttempt?> load({
    required String actorId,
    required String associationId,
  }) async {
    expect(actorId, 'admin-1');
    expect(associationId, 'jba');
    return attempt;
  }

  @override
  Future<void> save({
    required String actorId,
    required String associationId,
    required InviteCreationAttempt attempt,
  }) async {
    expect(actorId, 'admin-1');
    expect(associationId, 'jba');
    this.attempt = attempt;
  }
}
