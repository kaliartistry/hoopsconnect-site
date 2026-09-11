import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/app_form_controls.dart';
import '../../models/account_deletion/account_deletion_contract.dart';
import 'account_deletion_candidate_controller.dart';
import 'account_deletion_candidate_models.dart';

class AccountDeletionCandidateScreen extends StatefulWidget {
  const AccountDeletionCandidateScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.autoInitialize = true,
  });

  final AccountDeletionCandidateController controller;
  final VoidCallback? onExit;
  final bool autoInitialize;

  @override
  State<AccountDeletionCandidateScreen> createState() =>
      _AccountDeletionCandidateScreenState();
}

class _AccountDeletionCandidateScreenState
    extends State<AccountDeletionCandidateScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncSensitiveFields);
    if (widget.autoInitialize) {
      unawaited(widget.controller.initialize());
    }
  }

  @override
  void didUpdateWidget(covariant AccountDeletionCandidateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncSensitiveFields);
    widget.controller.addListener(_syncSensitiveFields);
  }

  void _syncSensitiveFields() {
    final state = widget.controller.state;
    if (_confirmationController.text != state.confirmationText) {
      _confirmationController.value = TextEditingValue(
        text: state.confirmationText,
        selection: TextSelection.collapsed(
          offset: state.confirmationText.length,
        ),
      );
    }
    if (state.phase == AccountDeletionJourneyPhase.impactReview &&
        _passwordController.text.isNotEmpty) {
      _passwordController.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSensitiveFields);
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onExit == null
            ? null
            : IconButton(
                tooltip: 'Back',
                onPressed: widget.onExit,
                icon: const Icon(Icons.arrow_back),
              ),
        title: const Text('Account deletion'),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final state = widget.controller.state;
          return AppFormFocusGroup(
            onCancel: widget.onExit,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _CandidateSafetyBanner(),
                        const SizedBox(height: 20),
                        if (state.errorCode != null)
                          _MessageBanner(
                            key: const Key('deletion-error-banner'),
                            icon: Icons.error_outline,
                            text: _errorText(state.errorCode!),
                            isError: true,
                          ),
                        if (state.errorCode != null && state.noticeCode != null)
                          const SizedBox(height: 12),
                        if (state.noticeCode != null)
                          _MessageBanner(
                            key: const Key('deletion-notice-banner'),
                            icon: Icons.info_outline,
                            text: _noticeText(state.noticeCode!),
                          ),
                        if (state.errorCode != null || state.noticeCode != null)
                          const SizedBox(height: 20),
                        _body(state),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(AccountDeletionCandidateState state) {
    return switch (state.phase) {
      AccountDeletionJourneyPhase.bootstrapping => const _ProgressPanel(
        title: 'Checking this device',
        message: 'Looking for a saved deletion receipt and local stat work.',
      ),
      AccountDeletionJourneyPhase.overview => _overview(state),
      AccountDeletionJourneyPhase.reauthenticating => _ProgressPanel(
        title: 'Confirming it’s you',
        message:
            'Finish the ${_providerName(state.selectedMethod)} sign-in step.',
      ),
      AccountDeletionJourneyPhase.preparingImpact => const _ProgressPanel(
        title: 'Preparing the exact impact',
        message:
            'Checking account ownership, provider handling and current consequences.',
      ),
      AccountDeletionJourneyPhase.impactReview => _impactReview(state),
      AccountDeletionJourneyPhase.submitting => const _ProgressPanel(
        title: 'Sending the deletion request',
        message:
            'The status receipt is saved first so a lost response can be recovered safely.',
      ),
      AccountDeletionJourneyPhase.resolvingSubmittedStatus =>
        const _ProgressPanel(
          title: 'Checking the saved request',
          message: 'Confirming status before any reauthentication or retry.',
        ),
      AccountDeletionJourneyPhase.acceptanceUnknown ||
      AccountDeletionJourneyPhase.processing ||
      AccountDeletionJourneyPhase.accountRemovedCleanupPending ||
      AccountDeletionJourneyPhase.attentionRequired ||
      AccountDeletionJourneyPhase.complete => _status(state),
      AccountDeletionJourneyPhase.unavailable => _unavailable(),
    };
  }

  Widget _overview(AccountDeletionCandidateState state) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Delete your HoopsConnect account',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This removes your sign-in account and starts separately verified cleanup. '
          'It does not delete teams, games, another person’s records or official sporting history.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        _SectionCard(
          icon: Icons.security_outlined,
          title: 'Confirm your identity',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a linked sign-in method. No provider window starts until you continue.',
              ),
              const SizedBox(height: 8),
              RadioGroup<AccountDeletionReauthenticationMethod>(
                groupValue: state.selectedMethod,
                onChanged: (value) {
                  if (value != null) {
                    widget.controller.selectReauthenticationMethod(value);
                  }
                },
                child: Column(
                  children: [
                    for (final method in state.providerProfile.methods)
                      RadioListTile<AccountDeletionReauthenticationMethod>(
                        key: Key('reauth-${method.name}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(_providerName(method)),
                        subtitle:
                            method ==
                                AccountDeletionReauthenticationMethod.apple
                            ? const Text(
                                'Also stages an opaque reference for Apple credential cleanup when available.',
                              )
                            : null,
                        value: method,
                      ),
                  ],
                ),
              ),
              if (state.selectedMethod ==
                  AccountDeletionReauthenticationMethod.password) ...[
                const SizedBox(height: 4),
                TextField(
                  key: const Key('deletion-password-field'),
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    helperText: 'Used only for this reauthentication step.',
                  ),
                  onSubmitted: (_) => _continue(state),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _localWorkCard(state.localWork),
        const SizedBox(height: 20),
        _CandidateAsyncActionButton(
          key: const Key('prepare-deletion-impact'),
          label: 'Review impact',
          icon: Icons.arrow_forward,
          onPressed: state.canPrepareImpact ? () => _continue(state) : null,
          disabledHint: _continueDisabledHint(state.localWork),
        ),
      ],
    );
  }

  void _continue(AccountDeletionCandidateState state) {
    if (!state.canPrepareImpact) return;
    unawaited(
      widget.controller.continueToImpact(
        password:
            state.selectedMethod ==
                AccountDeletionReauthenticationMethod.password
            ? _passwordController.text
            : null,
      ),
    );
  }

  Widget _localWorkCard(AccountDeletionLocalWorkSummary localWork) {
    final theme = Theme.of(context);
    final total =
        localWork.unacceptedOperationCount + localWork.acceptedOperationCount;
    return _SectionCard(
      key: const Key('local-work-card'),
      icon: Icons.sports_basketball_outlined,
      title: 'Stat work on this device',
      child: switch (localWork.state) {
        AccountDeletionLocalWorkState.checking => const Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Checking local work…')),
          ],
        ),
        AccountDeletionLocalWorkState.clear => const Text(
          'No local stat work needs attention on this device.',
        ),
        AccountDeletionLocalWorkState.readyWithDeviceConsent => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This device’s $total operation${total == 1 ? '' : 's'} are covered by an exact manifest and explicit device-only consent.',
            ),
            const SizedBox(height: 8),
            Text(
              'That consent does not apply to another phone, tablet or browser.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        AccountDeletionLocalWorkState.requiresReconciliation => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${localWork.workspaceCount} workspace${localWork.workspaceCount == 1 ? '' : 's'} contain $total operation${total == 1 ? '' : 's'}. '
              '${localWork.receiptUnknownOperationCount} have an unknown server receipt.',
            ),
            const SizedBox(height: 8),
            const Text(
              'A missing receipt does not prove the work was rejected. Resolve it before choosing discard.',
            ),
            const SizedBox(height: 12),
            _CandidateAsyncActionButton(
              key: const Key('resolve-local-work'),
              label: 'Resolve work',
              style: AppActionStyle.outlined,
              onPressed: () => widget.controller.resolveLocalWork(
                AccountDeletionLocalWorkAction.reconcileOrExport,
              ),
            ),
            const SizedBox(height: 8),
            _CandidateAsyncActionButton(
              key: const Key('discard-local-drafts'),
              label: 'Discard drafts',
              style: AppActionStyle.text,
              onPressed: localWork.permitsDiscardWithoutReconciliation
                  ? () => widget.controller.resolveLocalWork(
                      AccountDeletionLocalWorkAction.discardUnacceptedDrafts,
                    )
                  : null,
              disabledHint:
                  'Receipt-unknown work must be reconciled before discard.',
            ),
          ],
        ),
        AccountDeletionLocalWorkState.unavailable => const Text(
          'Local stat work could not be verified. Account deletion is not submitted from this device until that check is resolved.',
        ),
      },
    );
  }

  Widget _impactReview(AccountDeletionCandidateState state) {
    final impact = state.impact!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Review the current impact',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This impact is short-lived and bound to the account generation that just reauthenticated.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.delete_forever_outlined,
          title: 'What happens',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Consequence('Your account access is fenced before cleanup.'),
              _Consequence(
                'Firebase Auth removal and cleanup are tracked separately.',
              ),
              _Consequence(
                'Teams, games and unrelated people’s records are not deleted.',
              ),
              _Consequence(
                'Official sporting facts are not rewritten by account deletion.',
              ),
              _Consequence(
                'Each other device must handle its own local stat work.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          key: const Key('custody-impact-card'),
          icon: Icons.admin_panel_settings_outlined,
          title: 'Shared account responsibilities',
          child: Text(_custodyText(impact)),
        ),
        if (impact.needsOperationalCustodyResolution) ...[
          const SizedBox(height: 16),
          const _MessageBanner(
            key: Key('custody-blocker'),
            icon: Icons.lock_outline,
            text:
                'No named custody path is ready for this last-owner account. The candidate records operational attention, but production activation remains blocked.',
            isError: true,
          ),
        ],
        const SizedBox(height: 20),
        CheckboxListTile(
          key: const Key('deletion-consequence-checkbox'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: state.confirmedConsequences,
          title: const Text(
            'I understand that account access cannot be restored after the request is accepted.',
          ),
          onChanged: impact.needsOperationalCustodyResolution
              ? null
              : (value) =>
                    widget.controller.setConsequencesConfirmed(value ?? false),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('deletion-confirmation-field'),
          controller: _confirmationController,
          enabled: !impact.needsOperationalCustodyResolution,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Type DELETE to confirm',
          ),
          onChanged: widget.controller.setConfirmationText,
          onSubmitted: (_) => _submit(state),
        ),
        const SizedBox(height: 20),
        _CandidateAsyncActionButton(
          key: const Key('submit-account-deletion'),
          label: 'Delete my account',
          icon: Icons.delete_forever,
          onPressed: state.canSubmit ? () => _submit(state) : null,
          disabledHint: impact.needsOperationalCustodyResolution
              ? 'Shared-account custody must be resolved first.'
              : 'Confirm the consequences and type DELETE.',
        ),
        const SizedBox(height: 8),
        _CandidateAsyncActionButton(
          label: 'Start over',
          style: AppActionStyle.text,
          onPressed: widget.controller.restartImpactReview,
        ),
      ],
    );
  }

  void _submit(AccountDeletionCandidateState state) {
    if (!state.canSubmit) return;
    unawaited(widget.controller.submitDeletion());
  }

  Widget _status(AccountDeletionCandidateState state) {
    final theme = Theme.of(context);
    final presentation = _statusPresentation(state.phase);
    final status = state.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          presentation.icon,
          size: 56,
          color: presentation.color(Theme.of(context).colorScheme),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            presentation.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          presentation.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        if (status != null)
          _SectionCard(
            key: const Key('provider-status-card'),
            icon: Icons.verified_user_outlined,
            title: 'Provider status',
            child: Text(_providerOutcomeText(status.providerOutcome)),
          ),
        if (status != null) const SizedBox(height: 16),
        if (state.localCleanup != null)
          _SectionCard(
            key: const Key('device-cleanup-card'),
            icon: Icons.phone_iphone_outlined,
            title: 'This device',
            child: Text(
              state.localCleanup!.completeOnThisDevice
                  ? 'Protected listeners, notification registration, ordinary caches and local notifications were cleared on this device. Other devices clear when they next observe deletion.'
                  : 'Server deletion continues, but cleanup on this device is incomplete and needs another attempt.',
            ),
          ),
        if (state.localCleanup != null) const SizedBox(height: 16),
        if (status != null && status.retainedCategoryCodes.isNotEmpty)
          const _SectionCard(
            icon: Icons.inventory_2_outlined,
            title: 'Restricted or retained categories',
            child: Text(
              'The status service reports retained categories. Their exact treatment must match the approved policy and is not described as erased.',
            ),
          ),
        if (status != null && status.retainedCategoryCodes.isNotEmpty)
          const SizedBox(height: 16),
        if (state.phase != AccountDeletionJourneyPhase.complete)
          _CandidateAsyncActionButton(
            key: const Key('refresh-deletion-status'),
            label: 'Check status',
            icon: Icons.refresh,
            onPressed: widget.controller.refreshStatus,
          ),
        if (state.phase == AccountDeletionJourneyPhase.complete &&
            widget.onExit != null)
          _CandidateAsyncActionButton(
            key: const Key('finish-account-deletion'),
            label: 'Done',
            onPressed: widget.onExit,
          ),
      ],
    );
  }

  Widget _unavailable() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.lock_clock_outlined, size: 56),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(
          'Account deletion is unavailable',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'No account was deleted. Try the candidate check again or use the existing support path while activation remains closed.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      _CandidateAsyncActionButton(
        key: const Key('retry-deletion-initialize'),
        label: 'Try again',
        icon: Icons.refresh,
        onPressed: widget.controller.initialize,
      ),
    ],
  );

  static String _continueDisabledHint(AccountDeletionLocalWorkSummary work) =>
      switch (work.state) {
        AccountDeletionLocalWorkState.checking =>
          'Wait for the local-work check.',
        AccountDeletionLocalWorkState.requiresReconciliation =>
          'Resolve this device’s local stat work first.',
        AccountDeletionLocalWorkState.unavailable =>
          'Local stat work could not be verified.',
        AccountDeletionLocalWorkState.clear ||
        AccountDeletionLocalWorkState.readyWithDeviceConsent =>
          'Choose a valid reauthentication method.',
      };

  static String _providerName(AccountDeletionReauthenticationMethod method) =>
      switch (method) {
        AccountDeletionReauthenticationMethod.password => 'Email and password',
        AccountDeletionReauthenticationMethod.google => 'Google',
        AccountDeletionReauthenticationMethod.apple => 'Apple',
      };

  static String _custodyText(
    CandidateAccountDeletionImpact impact,
  ) => switch (impact.ownershipResolution) {
    AccountDeletionOwnershipResolution.ordinaryMember =>
      'You are not the last recoverable owner. Shared league records stay with the association.',
    AccountDeletionOwnershipResolution.transferVerified =>
      'A verified owner transfer is bound to this impact. The successor is installed before your account leaves.',
    AccountDeletionOwnershipResolution.custodySuspensionPrepared =>
      'The last-owner association is prepared to suspend to named custody while personal account deletion continues.',
    AccountDeletionOwnershipResolution.operationalResolutionRequired =>
      'You are the last recoverable owner and no named transfer or custody operation is ready.',
  };

  static String _providerOutcomeText(
    ProviderCheckpointState state,
  ) => switch (state) {
    ProviderCheckpointState.complete =>
      'Linked Apple credential revocation was verified.',
    ProviderCheckpointState.notApplicable =>
      'No Apple credential relationship applies to this request.',
    ProviderCheckpointState.manualActionGuidance =>
      'HoopsConnect account removal was recorded, but automatic Apple revocation was not verified. The approved provider guidance must be shown before activation.',
    ProviderCheckpointState.pending ||
    ProviderCheckpointState.retryRequired ||
    ProviderCheckpointState.unknown =>
      'Provider cleanup has not been verified complete.',
  };

  static _StatusPresentation _statusPresentation(
    AccountDeletionJourneyPhase phase,
  ) => switch (phase) {
    AccountDeletionJourneyPhase.acceptanceUnknown => const _StatusPresentation(
      icon: Icons.help_outline,
      title: 'Request status is not confirmed',
      message:
          'The request may already have been accepted. Do not create another request or reauthenticate yet. Check the saved read-only status receipt.',
      tone: _StatusTone.warning,
    ),
    AccountDeletionJourneyPhase.processing => const _StatusPresentation(
      icon: Icons.hourglass_top,
      title: 'Account removal is processing',
      message:
          'Account access is being fenced and provider removal is underway. Cleanup completion is verified separately.',
      tone: _StatusTone.info,
    ),
    AccountDeletionJourneyPhase.accountRemovedCleanupPending =>
      const _StatusPresentation(
        icon: Icons.manage_history,
        title: 'Account removed, cleanup still pending',
        message:
            'Your sign-in account is gone. Data, privacy, provider and restore checks are still running, so deletion is not complete yet.',
        tone: _StatusTone.warning,
      ),
    AccountDeletionJourneyPhase.attentionRequired => const _StatusPresentation(
      icon: Icons.support_agent,
      title: 'Cleanup needs staff attention',
      message:
          'The account stays fenced. A worker, policy or custody issue needs an authorized operator; starting another request will not fix it.',
      tone: _StatusTone.warning,
    ),
    AccountDeletionJourneyPhase.complete => const _StatusPresentation(
      icon: Icons.check_circle_outline,
      title: 'Account deletion complete',
      message:
          'The required provider outcome, cleanup, custody, privacy and restore checks are recorded complete for this request. Review any provider guidance below.',
      tone: _StatusTone.success,
    ),
    _ => throw StateError('This phase has no status presentation.'),
  };

  static String _errorText(String code) => switch (code) {
    'AD_PASSWORD_REQUIRED' => 'Enter your current password to continue.',
    'AD_LOCAL_RECEIPT_RECONCILIATION_REQUIRED' =>
      'Some local stat work has an unknown server receipt and cannot be discarded yet.',
    'AD_LOCAL_WORK_NOT_RESOLVED' || 'AD_LOCAL_WORK_UNAVAILABLE' =>
      'Local stat work could not be resolved on this device.',
    'AD_CUSTODY_OPERATIONAL_RESOLUTION_REQUIRED' =>
      'A safe shared-account custody path has not been resolved.',
    'AD_INTENT_EXPIRED' || 'AD_IMPACT_CHANGED' =>
      'The account impact expired or changed. Reauthenticate and review a fresh impact.',
    'AD_ACCEPTANCE_UNKNOWN' =>
      'We cannot confirm whether the request was accepted. Use Check status; do not submit a new request.',
    'AD_STATUS_UNAVAILABLE' =>
      'Current deletion status is temporarily unavailable. The saved receipt is still available for another check.',
    'AD_RECEIPT_STORAGE_UNAVAILABLE' =>
      'This device could not safely save a recovery receipt, so no deletion request was sent.',
    'AD_RECEIPT_CLEAR_FAILED' =>
      'This device could not update its saved receipt. Do not submit another request until recovery status is resolved.',
    'AD_DEVICE_CLEANUP_INCOMPLETE' =>
      'Server deletion continues, but this device has not finished local cleanup.',
    'AD_POLICY_NOT_READY' || 'AD_TRANSFER_NOT_READY' =>
      'A required policy or ownership step is not ready. No new request was accepted.',
    _ => 'Account deletion could not continue. No completion is being claimed.',
  };

  static String _noticeText(String code) => switch (code) {
    'AD_PROVIDER_REAUTH_CANCELLED' =>
      'Provider sign-in was cancelled. No deletion request was sent.',
    'AD_APPLE_REVOCATION_MATERIAL_UNAVAILABLE' =>
      'Apple revocation material was not staged. Any later provider result must say that truthfully.',
    'AD_LOCAL_DEVICE_CONSENT_RECORDED' =>
      'This device’s exact local-work decision was recorded. It does not cover another device.',
    'AD_ALREADY_ACCEPTED' =>
      'This device joined the existing request without changing its accepted scope.',
    'AD_DELETION_REQUESTED' =>
      'The request was accepted and its read-only status receipt was saved.',
    'AD_ACCEPTANCE_UNKNOWN' =>
      'Checking the saved status receipt before any retry.',
    _ => 'The account deletion state changed. Review the current status below.',
  };
}

class _CandidateSafetyBanner extends StatelessWidget {
  const _CandidateSafetyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          'Review-only candidate. Account deletion is not active in this build.',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Review-only candidate. Account deletion is not active in this build.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    super.key,
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Consequence extends StatelessWidget {
  const _Consequence(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '$title. $message',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// Candidate-local action layout that preserves large-text wrapping without
/// changing the shared button owned by the accessibility workstream.
class _CandidateAsyncActionButton extends StatelessWidget {
  const _CandidateAsyncActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.disabledHint,
    this.icon,
    this.style = AppActionStyle.filled,
  }) : assert(
         onPressed != null || disabledHint != null,
         'A disabled action must explain why it is unavailable.',
       );

  final String label;
  final FutureOr<void> Function()? onPressed;
  final String? disabledHint;
  final IconData? icon;
  final AppActionStyle style;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final content = Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(
          child: Text(label, textAlign: TextAlign.center, softWrap: true),
        ),
      ],
    );
    final callback = enabled
        ? () {
            onPressed!();
          }
        : null;
    final buttonContent = ExcludeSemantics(child: content);
    final Widget button = switch (style) {
      AppActionStyle.filled => ElevatedButton(
        onPressed: callback,
        child: buttonContent,
      ),
      AppActionStyle.outlined => OutlinedButton(
        onPressed: callback,
        child: buttonContent,
      ),
      AppActionStyle.text => TextButton(
        onPressed: callback,
        child: buttonContent,
      ),
    };

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        hint: enabled ? null : disabledHint,
        child: button,
      ),
    );
  }
}

enum _StatusTone { info, warning, success }

final class _StatusPresentation {
  const _StatusPresentation({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final _StatusTone tone;

  Color color(ColorScheme scheme) => switch (tone) {
    _StatusTone.info => scheme.primary,
    _StatusTone.warning => scheme.tertiary,
    _StatusTone.success => scheme.primary,
  };
}
