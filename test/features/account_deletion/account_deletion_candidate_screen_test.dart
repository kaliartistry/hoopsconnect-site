import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/theme/app_theme.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_controller.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_screen.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AccountDeletionCandidateController controller, {
    Size size = const Size(375, 812),
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: AccountDeletionCandidateScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone overview and impact tolerate 200 percent text', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      controller,
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const Key('deletion-password-field')),
      'correct horse',
    );
    await tester.ensureVisible(
      find.byKey(const Key('prepare-deletion-impact')),
    );
    await tester.tap(find.byKey(const Key('prepare-deletion-impact')));
    await tester.pumpAndSettle();

    expect(find.text('Review the current impact'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets('overview renders without overflow at ${size.width}', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);

      await pumpScreen(tester, controller, size: size);

      expect(
        find.text(
          'Review-only candidate. Account deletion is not active in this build.',
        ),
        findsOneWidget,
      );
      expect(find.text('Delete your HoopsConnect account'), findsOneWidget);
      expect(find.byKey(const Key('local-work-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('password journey requires the final explicit confirmation', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = _controller(gateway: gateway);
    addTearDown(controller.dispose);
    await pumpScreen(tester, controller, size: const Size(768, 1024));

    await tester.enterText(
      find.byKey(const Key('deletion-password-field')),
      'correct horse',
    );
    await tester.ensureVisible(
      find.byKey(const Key('prepare-deletion-impact')),
    );
    await tester.tap(find.byKey(const Key('prepare-deletion-impact')));
    await tester.pumpAndSettle();

    expect(find.text('Review the current impact'), findsOneWidget);
    expect(find.byKey(const Key('custody-impact-card')), findsOneWidget);
    ElevatedButton submitButton() => tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('submit-account-deletion')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(submitButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('deletion-consequence-checkbox')));
    await tester.enterText(
      find.byKey(const Key('deletion-confirmation-field')),
      'DELETE',
    );
    await tester.pump();
    expect(submitButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('submit-account-deletion')));
    await tester.pumpAndSettle();

    expect(find.text('Account removal is processing'), findsOneWidget);
    expect(
      find.textContaining('cleanup completion is separately verified'),
      findsNothing,
    );
    expect(find.byKey(const Key('provider-status-card')), findsOneWidget);
    expect(find.byKey(const Key('device-cleanup-card')), findsOneWidget);
    expect(gateway.requestCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider cancellation stays on the reachable screen', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = _controller(
      gateway: gateway,
      profile: AccountDeletionProviderProfile(
        methods: const [AccountDeletionReauthenticationMethod.google],
        appleRelationship: AppleAccountRelationship.notLinked,
      ),
      reauthentication: AccountDeletionReauthenticationResult(
        method: AccountDeletionReauthenticationMethod.google,
        outcome: AccountDeletionReauthenticationOutcome.cancelled,
        appleRevocationMaterialState:
            AppleRevocationMaterialState.notApplicable,
      ),
    );
    addTearDown(controller.dispose);
    await pumpScreen(tester, controller);

    await tester.ensureVisible(
      find.byKey(const Key('prepare-deletion-impact')),
    );
    await tester.tap(find.byKey(const Key('prepare-deletion-impact')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Provider sign-in was cancelled. No deletion request was sent.',
      ),
      findsOneWidget,
    );
    expect(find.text('Delete your HoopsConnect account'), findsOneWidget);
    expect(gateway.prepareCalls, 0);
    expect(gateway.requestCalls, 0);
  });

  testWidgets('receipt-unknown work disables local discard', (tester) async {
    final controller = _controller(
      localWork: AccountDeletionLocalWorkSummary(
        binding: _deviceBinding,
        state: AccountDeletionLocalWorkState.requiresReconciliation,
        workspaceCount: 2,
        unacceptedOperationCount: 3,
        receiptUnknownOperationCount: 1,
        acceptedOperationCount: 4,
      ),
    );
    addTearDown(controller.dispose);
    await pumpScreen(tester, controller, theme: AppTheme.dark);

    final discard = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const Key('discard-local-drafts')),
        matching: find.byType(TextButton),
      ),
    );
    expect(discard.onPressed, isNull);
    expect(
      find.textContaining('missing receipt does not prove'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('last-owner custody conflict allows personal deletion', (
    tester,
  ) async {
    final gateway = _Gateway(
      statusPhase: DeletionStatusPhase.attentionRequired,
      messageCode: 'CUSTODY_CONFLICT',
      impact: CandidateAccountDeletionImpact(
        intentId: 'intent_1',
        policyVersion: 'policy_1',
        impactVersion: 'impact_1',
        expiresAt: DateTime.utc(2099),
        custodyChoice: CustodyChoice.suspendToCustody,
        ownershipResolution:
            AccountDeletionOwnershipResolution.operationalResolutionRequired,
        isLastRecoverableOwner: true,
        associationId: 'jba',
        serverDeletionContinuesIndependently: true,
        sportingHistoryIsNotAccountData: true,
      ),
    );
    final controller = _controller(gateway: gateway);
    addTearDown(controller.dispose);
    await pumpScreen(tester, controller);

    await tester.enterText(
      find.byKey(const Key('deletion-password-field')),
      'correct horse',
    );
    await tester.ensureVisible(
      find.byKey(const Key('prepare-deletion-impact')),
    );
    await tester.tap(find.byKey(const Key('prepare-deletion-impact')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custody-blocker')), findsOneWidget);
    expect(
      find.textContaining('Your personal deletion may continue'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('deletion-consequence-checkbox')),
    );
    await tester.tap(find.byKey(const Key('deletion-consequence-checkbox')));
    await tester.enterText(
      find.byKey(const Key('deletion-confirmation-field')),
      'DELETE',
    );
    await tester.ensureVisible(
      find.byKey(const Key('submit-account-deletion')),
    );
    await tester.pump();
    final submit = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('submit-account-deletion')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(submit.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('submit-account-deletion')));
    await tester.pumpAndSettle();
    expect(gateway.requestCalls, 1);
    expect(find.text('Cleanup needs staff attention'), findsOneWidget);
  });

  for (final statusCase
      in <
        ({
          DeletionStatusPhase phase,
          ProviderCheckpointState providerOutcome,
          String title,
        })
      >[
        (
          phase: DeletionStatusPhase.accountRemovedCleanupPending,
          providerOutcome: ProviderCheckpointState.pending,
          title: 'Account removed, cleanup still pending',
        ),
        (
          phase: DeletionStatusPhase.attentionRequired,
          providerOutcome: ProviderCheckpointState.pending,
          title: 'Cleanup needs staff attention',
        ),
        (
          phase: DeletionStatusPhase.complete,
          providerOutcome: ProviderCheckpointState.manualActionGuidance,
          title: 'Account deletion complete',
        ),
      ]) {
    testWidgets('${statusCase.phase.name} has truthful recovery copy', (
      tester,
    ) async {
      final gateway = _Gateway(
        statusPhase: statusCase.phase,
        providerOutcome: statusCase.providerOutcome,
      );
      final controller = _controller(
        gateway: gateway,
        savedReceipt: _savedReceipt(),
      );
      addTearDown(controller.dispose);

      await pumpScreen(tester, controller, size: const Size(768, 1024));

      expect(find.text(statusCase.title), findsOneWidget);
      if (statusCase.phase == DeletionStatusPhase.complete) {
        expect(
          find.textContaining('automatic Apple revocation was not verified'),
          findsOneWidget,
        );
        expect(find.textContaining('Provider removal,'), findsNothing);
      } else {
        expect(find.text('Account deletion complete'), findsNothing);
        expect(
          find.byKey(const Key('refresh-deletion-status')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unknown acceptance keeps one saved request and no reauth loop', (
    tester,
  ) async {
    final gateway = _Gateway(statusFails: true);
    final controller = _controller(
      gateway: gateway,
      savedReceipt: _savedReceipt(),
    );
    addTearDown(controller.dispose);

    await pumpScreen(tester, controller);

    expect(find.text('Request status is not confirmed'), findsOneWidget);
    expect(
      find.textContaining('Do not create another request'),
      findsOneWidget,
    );
    expect(gateway.prepareCalls, 0);
    expect(gateway.requestCalls, 0);
    expect(gateway.statusCalls, 1);
  });

  testWidgets('receipt-store failure reports deletion status as unknown', (
    tester,
  ) async {
    final controller = _controller(receiptReadFails: true);
    addTearDown(controller.dispose);

    await pumpScreen(tester, controller);

    expect(find.text('Account deletion is unavailable'), findsOneWidget);
    expect(find.textContaining('deletion status is unknown'), findsOneWidget);
    expect(find.textContaining('No account was deleted'), findsNothing);
  });

  testWidgets('receipt write failure never claims deletion was not accepted', (
    tester,
  ) async {
    final controller = _controller(receiptWriteFails: true);
    addTearDown(controller.dispose);
    await pumpScreen(tester, controller, size: const Size(768, 1024));

    await tester.enterText(
      find.byKey(const Key('deletion-password-field')),
      'correct horse',
    );
    await tester.tap(find.byKey(const Key('prepare-deletion-impact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deletion-consequence-checkbox')));
    await tester.enterText(
      find.byKey(const Key('deletion-confirmation-field')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-account-deletion')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Deletion status is unknown'), findsOneWidget);
    expect(find.textContaining('no deletion request was sent'), findsNothing);
  });
}

final _statusSecret = base64Url
    .encode(Uint8List.fromList(List<int>.filled(32, 7)))
    .replaceAll('=', '');
final _deviceBinding = AccountDeletionDeviceBinding(
  accountId: 'account_1',
  accountGeneration: 'generation_1',
  deviceSessionId: 'device_session_1',
);

AccountDeletionCandidateController _controller({
  _Gateway? gateway,
  AccountDeletionProviderProfile? profile,
  AccountDeletionReauthenticationResult? reauthentication,
  AccountDeletionLocalWorkSummary? localWork,
  CandidateAccountDeletionReceipt? savedReceipt,
  bool receiptReadFails = false,
  bool receiptWriteFails = false,
}) {
  final effectiveGateway = gateway ?? _Gateway();
  return AccountDeletionCandidateController(
    providerProfile:
        profile ??
        AccountDeletionProviderProfile(
          methods: const [AccountDeletionReauthenticationMethod.password],
          appleRelationship: AppleAccountRelationship.notLinked,
        ),
    deviceBinding: _deviceBinding,
    gateway: effectiveGateway,
    reauthenticator: _Reauthenticator(
      reauthentication ??
          AccountDeletionReauthenticationResult(
            method: AccountDeletionReauthenticationMethod.password,
            outcome: AccountDeletionReauthenticationOutcome.verified,
            appleRevocationMaterialState:
                AppleRevocationMaterialState.notApplicable,
          ),
    ),
    deviceCleanup: _Cleanup(
      localWork ?? AccountDeletionLocalWorkSummary.clear(_deviceBinding),
    ),
    receiptStore: _Store(
      savedReceipt,
      failRead: receiptReadFails,
      failWrite: receiptWriteFails,
    ),
    clock: const _Clock(),
    operationFactory: const _Operations(),
  );
}

final class _Gateway implements CandidateAccountDeletionGateway {
  _Gateway({
    CandidateAccountDeletionImpact? impact,
    this.statusPhase = DeletionStatusPhase.processing,
    this.providerOutcome = ProviderCheckpointState.pending,
    this.statusFails = false,
    this.messageCode,
  }) : impact =
           impact ??
           CandidateAccountDeletionImpact(
             intentId: 'intent_1',
             policyVersion: 'policy_1',
             impactVersion: 'impact_1',
             expiresAt: DateTime.utc(2099),
             custodyChoice: CustodyChoice.ordinary,
             ownershipResolution:
                 AccountDeletionOwnershipResolution.ordinaryMember,
             isLastRecoverableOwner: false,
             associationId: 'jba',
             serverDeletionContinuesIndependently: true,
             sportingHistoryIsNotAccountData: true,
           );

  final CandidateAccountDeletionImpact impact;
  final DeletionStatusPhase statusPhase;
  final ProviderCheckpointState providerOutcome;
  final bool statusFails;
  final String? messageCode;
  int prepareCalls = 0;
  int requestCalls = 0;
  int statusCalls = 0;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<CandidateAccountDeletionImpact> prepareDeletion() async {
    prepareCalls++;
    return impact;
  }

  @override
  Future<AcceptedAccountDeletionRequest> requestDeletion(
    RequestDeletionContract request,
  ) async {
    requestCalls++;
    return AcceptedAccountDeletionRequest(
      requestId: request.requestId,
      internalJobId: 'job_1',
      acceptedAt: DateTime.utc(2026, 9, 11, 16),
      nextPollAfter: const Duration(seconds: 5),
      sameGenerationConvergence: false,
    );
  }

  @override
  Future<AccountDeletionStatusSnapshot> deletionStatus({
    required String requestId,
    required String statusSecret,
  }) async {
    statusCalls++;
    if (statusFails) {
      throw const AccountDeletionCandidateFailure('AD_STATUS_UNAVAILABLE');
    }
    return AccountDeletionStatusSnapshot(
      requestId: requestId,
      phase: statusPhase,
      acceptedAt: DateTime.utc(2026, 9, 11, 16),
      completedAt: statusPhase == DeletionStatusPhase.complete
          ? DateTime.utc(2026, 9, 11, 16, 20)
          : null,
      nextPollAfter: statusPhase == DeletionStatusPhase.complete
          ? null
          : const Duration(seconds: 15),
      providerOutcome: providerOutcome,
      messageCode:
          messageCode ??
          (statusPhase == DeletionStatusPhase.complete
              ? 'AD_ACCOUNT_DELETION_COMPLETE'
              : 'AD_DELETION_REQUESTED'),
      retainedCategoryCodes: const [],
    );
  }
}

final class _Reauthenticator
    implements CandidateAccountDeletionReauthenticator {
  const _Reauthenticator(this.result);

  final AccountDeletionReauthenticationResult result;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionReauthenticationResult> reauthenticate({
    required AccountDeletionReauthenticationMethod method,
    String? password,
  }) async => result;
}

final class _Cleanup implements CandidateAccountDeletionDeviceCleanup {
  const _Cleanup(this.localWork);

  final AccountDeletionLocalWorkSummary localWork;

  @override
  bool get isSyntheticCandidate => true;

  @override
  Future<AccountDeletionLocalWorkSummary> inspectLocalOfficialWork(
    AccountDeletionDeviceBinding binding,
  ) async => localWork;

  @override
  Future<AccountDeletionLocalWorkSummary> resolveLocalOfficialWork(
    AccountDeletionLocalWorkAction action,
    AccountDeletionDeviceBinding binding,
  ) async => localWork;

  @override
  Future<AccountDeletionLocalCleanupResult> clearAfterServerFence(
    AccountDeletionLocalCleanupRequest request,
  ) async => AccountDeletionLocalCleanupResult(
    listenersStopped: true,
    notificationRegistrationDetached: true,
    ordinaryCachesCleared: true,
    localNotificationsCancelled: true,
    localOfficialWorkPreservedOrConsented: true,
  );
}

final class _Store implements CandidateAccountDeletionReceiptStore {
  _Store(this.receipt, {this.failRead = false, this.failWrite = false});

  CandidateAccountDeletionReceipt? receipt;
  final bool failRead;
  final bool failWrite;

  @override
  Future<CandidateAccountDeletionReceipt?> read() async {
    if (failRead) throw StateError('synthetic receipt read failure');
    return receipt;
  }

  @override
  Future<void> write(CandidateAccountDeletionReceipt receipt) async {
    if (failWrite) throw StateError('synthetic receipt write failure');
    this.receipt = receipt;
  }

  @override
  Future<void> clearProvenNotAccepted(
    CandidateAccountDeletionReceipt receipt,
  ) async {
    this.receipt = null;
  }
}

CandidateAccountDeletionReceipt _savedReceipt() {
  final request = RequestDeletionContract(
    intentId: 'intent_1',
    policyVersion: 'policy_1',
    impactVersion: 'impact_1',
    operationId: 'operation_1',
    requestId: 'request_1',
    statusSecretHash: AccountDeletionContract.statusSecretHash(_statusSecret),
    custodyChoice: CustodyChoice.ordinary,
  );
  return CandidateAccountDeletionReceipt(
    binding: _deviceBinding,
    request: request,
    statusSecret: _statusSecret,
    state: AccountDeletionReceiptState.acceptanceUnknown,
    recordedAt: DateTime.utc(2026, 9, 11, 16),
    requiresInitialCustodyConflict: false,
  );
}

final class _Clock implements AccountDeletionCandidateClock {
  const _Clock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 11, 16);
}

final class _Operations implements CandidateDeletionOperationFactory {
  const _Operations();

  @override
  CandidateDeletionOperationMaterial create() =>
      CandidateDeletionOperationMaterial(
        operationId: 'operation_1',
        requestId: 'request_1',
        statusSecret: _statusSecret,
      );
}
