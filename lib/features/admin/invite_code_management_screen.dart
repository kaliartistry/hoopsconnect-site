import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_constrained_content.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/division_model.dart';
import '../../models/invite_code_model.dart';
import '../../models/team_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/team_providers.dart';
import '../../services/repositories/invite_code_repository.dart';

typedef InviteSecretCopier = Future<void> Function(String secret);
typedef InviteOperationIdFactory = String Function();

Future<void> _copyInviteSecret(String secret) {
  return Clipboard.setData(ClipboardData(text: secret));
}

class InviteCodeManagementScreen extends ConsumerStatefulWidget {
  final InviteSecretCopier? copySecret;
  final InviteOperationIdFactory? operationIdFactory;
  final InviteCreationAttemptStore? attemptStore;

  const InviteCodeManagementScreen({
    super.key,
    this.copySecret,
    this.operationIdFactory,
    this.attemptStore,
  });

  @override
  ConsumerState<InviteCodeManagementScreen> createState() =>
      _InviteCodeManagementScreenState();
}

class _InviteCodeManagementScreenState
    extends ConsumerState<InviteCodeManagementScreen> {
  List<InviteCodeModel>? _codes;
  final Set<String> _revokingIds = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final associationId = ref.read(currentAssociationIdProvider);
      if (associationId == null) {
        throw StateError('No association is available for this account.');
      }
      final codes = await ref
          .read(inviteCodeRepositoryProvider)
          .getAllCodes(associationId);
      if (mounted) setState(() => _codes = codes);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyInviteError(
            error,
            fallback: 'Invite codes could not be loaded. Try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final actorId = ref.read(currentUserProvider).valueOrNull?.id;
    final associationId = ref.read(currentAssociationIdProvider);
    if (actorId == null || associationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session is not ready. Sign in again and retry.'),
        ),
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreateInviteDialog(
        repository: ref.read(inviteCodeRepositoryProvider),
        copySecret: widget.copySecret ?? _copyInviteSecret,
        operationIdFactory: widget.operationIdFactory ?? newInviteOperationId,
        attemptStore:
            widget.attemptStore ??
            SharedPreferencesInviteCreationAttemptStore(),
        actorId: actorId,
        associationId: associationId,
      ),
    );
    if (created == true && mounted) await _loadCodes();
  }

  Future<void> _confirmAndRevoke(InviteCodeModel code) async {
    if (_revokingIds.contains(code.inviteId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invite?'),
        content: Text(
          'Revoke invite "${code.displayId}"? Anyone holding it will no longer be able to join.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep active'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.urgent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke invite'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingIds.add(code.inviteId));
    try {
      await ref.read(inviteCodeRepositoryProvider).revokeCode(code.inviteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite ${code.displayId} was revoked.')),
      );
      await _loadCodes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyInviteError(
              error,
              fallback:
                  'This invite could not be revoked. Refresh the list and try again.',
            ),
          ),
          action: SnackBarAction(label: 'Refresh', onPressed: _loadCodes),
        ),
      );
    } finally {
      if (mounted) setState(() => _revokingIds.remove(code.inviteId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamNames = {
      for (final team
          in ref.watch(teamsStreamProvider).valueOrNull ?? const <TeamModel>[])
        team.id: team.name,
    };

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Invite Codes'),
      ),
      body: _loading
          ? const Center(child: AppLoadingState(label: 'Loading invite codes'))
          : _error != null
          ? AppConstrainedContent(
              child: AppStateMessage(
                title: 'Invite codes could not be loaded',
                message: _error!,
                tone: AppStateTone.error,
                actionLabel: 'Try again',
                onAction: _loadCodes,
              ),
            )
          : _codes == null || _codes!.isEmpty
          ? const AppConstrainedContent(
              child: AppStateMessage(
                title: 'No invite codes',
                message:
                    'Generate a single-use code when someone needs access.',
                icon: Icons.vpn_key_outlined,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadCodes,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _codes!.length,
                itemBuilder: (context, index) {
                  final code = _codes![index];
                  return _CodeCard(
                    code: code,
                    teamName: code.teamId == null
                        ? null
                        : teamNames[code.teamId],
                    isRevoking: _revokingIds.contains(code.inviteId),
                    onRevoke: () => _confirmAndRevoke(code),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Generate invite'),
      ),
    );
  }
}

class _CreateInviteDialog extends ConsumerStatefulWidget {
  final InviteCodeRepository repository;
  final InviteSecretCopier copySecret;
  final InviteOperationIdFactory operationIdFactory;
  final InviteCreationAttemptStore attemptStore;
  final String actorId;
  final String associationId;

  const _CreateInviteDialog({
    required this.repository,
    required this.copySecret,
    required this.operationIdFactory,
    required this.attemptStore,
    required this.actorId,
    required this.associationId,
  });

  @override
  ConsumerState<_CreateInviteDialog> createState() =>
      _CreateInviteDialogState();
}

class _CreateInviteDialogState extends ConsumerState<_CreateInviteDialog> {
  String _role = 'rep';
  String? _teamId;
  int _daysValid = AppDefaults.inviteCodeDefaultDaysValid;
  InviteCreationAttempt? _attempt;
  IssuedInviteCode? _pendingVerification;
  IssuedInviteCode? _issued;
  bool _submitting = false;
  bool _ambiguous = false;
  bool _copying = false;
  bool _copied = false;
  bool _restoring = true;
  bool _verifying = false;
  String? _error;
  String? _copyError;
  String? _verificationError;
  String? _nonSendableOutcome;

  bool get _requestLocked => _attempt != null;

  @override
  void initState() {
    super.initState();
    _restoreAttempt();
  }

  Future<void> _restoreAttempt() async {
    try {
      final attempt = await widget.attemptStore.load(
        actorId: widget.actorId,
        associationId: widget.associationId,
      );
      if (!mounted) return;
      setState(() {
        _restoring = false;
        if (attempt != null) {
          _attempt = attempt;
          _role = attempt.role;
          _teamId = attempt.teamId;
          _daysValid = attempt.daysValid;
          _ambiguous = true;
          _error =
              'An unfinished invite request was found. Recover the same request to reconcile it safely. Its current status will be checked before any code is shown.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error =
            'A saved invite request could not be restored. Close this window and try again.';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || _issued != null) return;
    if (_role == 'rep' && _teamId == null) {
      setState(() => _error = 'Choose the team this representative manages.');
      return;
    }

    final attempt =
        _attempt ??
        InviteCreationAttempt(
          role: _role,
          teamId: _teamId,
          daysValid: _daysValid,
          operationId: widget.operationIdFactory(),
        );
    setState(() {
      _attempt = attempt;
      _submitting = true;
      _error = null;
    });

    try {
      await widget.attemptStore.save(
        actorId: widget.actorId,
        associationId: widget.associationId,
        attempt: attempt,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _ambiguous = true;
        _error =
            'This request could not be saved for safe recovery. Retry the same request before continuing.';
      });
      return;
    }

    try {
      final issued = await attempt.submit(
        widget.repository,
        expectedAssociationId: widget.associationId,
      );
      if (!mounted) return;
      await _clearRecoveryAndVerify(issued);
    } catch (error) {
      if (!mounted) return;
      final ambiguous =
          inviteFailureDisposition(error) == InviteFailureDisposition.ambiguous;
      if (!ambiguous) {
        try {
          await widget.attemptStore.clear(
            actorId: widget.actorId,
            associationId: widget.associationId,
          );
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _submitting = false;
            _ambiguous = true;
            _error =
                'The request was rejected, but its recovery record could not be cleared. Retry this same request before continuing.';
          });
          return;
        }
      }
      setState(() {
        _submitting = false;
        _ambiguous = ambiguous;
        if (!ambiguous) _attempt = null;
        _error = ambiguous
            ? 'The server may have created this invite, but the response was lost. Retry the same request to recover it safely.'
            : _friendlyInviteError(
                error,
                fallback:
                    'The invite could not be created. Review the selections and try again.',
              );
      });
    }
  }

  Future<void> _clearRecoveryAndVerify(IssuedInviteCode issued) async {
    setState(() {
      _pendingVerification = issued;
      _submitting = false;
      _verifying = true;
      _verificationError = null;
    });
    try {
      await widget.attemptStore.clear(
        actorId: widget.actorId,
        associationId: widget.associationId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verificationError =
            'The invite was created, but local recovery material could not be cleared. Keep this window open and retry secure cleanup.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _attempt = null;
      _ambiguous = false;
      _verifying = false;
    });
    await _verifyPendingInvite();
  }

  Future<void> _verifyPendingInvite() async {
    final pending = _pendingVerification;
    if (pending == null || _verifying) return;
    setState(() {
      _verifying = true;
      _verificationError = null;
    });
    try {
      final usability = await widget.repository.verifyIssuedCode(pending);
      if (!mounted) return;
      if (usability == IssuedInviteUsability.inactive) {
        setState(() {
          _pendingVerification = null;
          _verifying = false;
          _nonSendableOutcome =
              'This recovered invite is no longer active. It may have been revoked, redeemed, or expired, so no sendable code will be shown.';
        });
        return;
      }
      setState(() {
        _pendingVerification = null;
        _issued = pending;
        _verifying = false;
      });
      await _copy();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verificationError =
            'The invite was created, but its current status could not be verified. Check again before sending it.';
      });
    }
  }

  Future<void> _retryPendingSafetyCheck() async {
    final pending = _pendingVerification;
    if (pending == null || _verifying) return;
    if (_attempt != null) {
      await _clearRecoveryAndVerify(pending);
    } else {
      await _verifyPendingInvite();
    }
  }

  Future<void> _copy() async {
    final issued = _issued;
    if (issued == null || _copying) return;
    setState(() {
      _copying = true;
      _copyError = null;
    });
    try {
      await widget.copySecret(issued.code);
      if (!mounted) return;
      setState(() => _copied = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copied = false;
        _copyError =
            'Automatic copy failed. The code is still shown above. Copy it manually or try again.';
      });
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsStreamProvider);
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final activeSeasonAsync = ref.watch(activeSeasonIdProvider);
    final activeSeasonId = activeSeasonAsync.valueOrNull;
    final activeDivisionIds = {
      for (final division
          in divisionsAsync.valueOrNull ?? const <DivisionModel>[])
        if (!division.isArchived &&
            (division.seasonId == null || division.seasonId == activeSeasonId))
          division.id,
    };
    final activeDivisionNames = {
      for (final division
          in divisionsAsync.valueOrNull ?? const <DivisionModel>[])
        if (activeDivisionIds.contains(division.id)) division.id: division.name,
    };
    final teams = [
      ...?teamsAsync.valueOrNull?.where(
        (team) =>
            team.seasonId == activeSeasonId &&
            activeDivisionIds.contains(team.divisionId),
      ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selectedTeamUnavailable =
        _teamId != null && teams.every((team) => team.id != _teamId);
    final teamsReady =
        teamsAsync.hasValue &&
        divisionsAsync.hasValue &&
        activeSeasonAsync.hasValue &&
        activeSeasonId != null;
    final canSubmit =
        teamsReady &&
        !_restoring &&
        !_submitting &&
        (_role != 'rep' || _teamId != null) &&
        _pendingVerification == null &&
        _issued == null;

    return PopScope(
      canPop: !_restoring && _attempt == null && _pendingVerification == null,
      child: AlertDialog(
        title: Text(
          _issued != null
              ? 'Invite ready'
              : _nonSendableOutcome != null
              ? 'Invite unavailable'
              : 'Generate invite code',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: _restoring
                ? const AppLoadingState(
                    label: 'Checking for an unfinished invite',
                  )
                : _pendingVerification != null
                ? AppStateMessage(
                    title: _verifying
                        ? 'Checking invite status'
                        : 'Invite not ready to send',
                    message:
                        _verificationError ??
                        'Confirming that this invite is still active.',
                    tone: _verificationError == null
                        ? AppStateTone.info
                        : AppStateTone.warning,
                    icon: _verifying ? Icons.sync : Icons.warning_amber_rounded,
                  )
                : _nonSendableOutcome != null
                ? AppStateMessage(
                    title: 'No code shown',
                    message: _nonSendableOutcome!,
                    tone: AppStateTone.warning,
                    icon: Icons.block_outlined,
                  )
                : _issued == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('invite-role-$_role'),
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: 'rep',
                            child: Text('Representative'),
                          ),
                          DropdownMenuItem(
                            value: 'media',
                            child: Text('Media / Press'),
                          ),
                          DropdownMenuItem(
                            value: 'statistician',
                            child: Text('Statistician'),
                          ),
                        ],
                        onChanged: _requestLocked
                            ? null
                            : (value) => setState(() {
                                _role = value!;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      if (teamsAsync.isLoading ||
                          divisionsAsync.isLoading ||
                          activeSeasonAsync.isLoading)
                        const AppLoadingState(
                          label: 'Loading active-season teams',
                        )
                      else if (teamsAsync.hasError ||
                          divisionsAsync.hasError ||
                          activeSeasonAsync.hasError)
                        AppStateMessage(
                          title: 'Active-season teams could not be loaded',
                          message:
                              'Refresh the team list before creating an invite.',
                          tone: AppStateTone.error,
                          actionLabel: 'Try again',
                          onAction: () {
                            ref.invalidate(teamsStreamProvider);
                            ref.invalidate(divisionsStreamProvider);
                            ref.invalidate(activeSeasonIdProvider);
                          },
                        )
                      else if (activeSeasonId == null)
                        AppStateMessage(
                          title: 'No active season',
                          message:
                              'Set the active season before creating a team-scoped invite.',
                          tone: AppStateTone.warning,
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey('invite-team-$_role-$_teamId'),
                          initialValue: _teamId ?? (_role == 'rep' ? null : ''),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: _role == 'rep'
                                ? 'Team (required)'
                                : 'Team (optional)',
                            helperText: _role == 'rep'
                                ? 'Only teams in the active season are available.'
                                : 'Optional teams are limited to the active season.',
                          ),
                          hint: const Text('Select a team'),
                          items: [
                            if (_role != 'rep')
                              const DropdownMenuItem(
                                value: '',
                                child: Text('No team • association-wide'),
                              ),
                            if (selectedTeamUnavailable)
                              DropdownMenuItem(
                                value: _teamId,
                                child: const Text(
                                  'Previously selected team • unavailable',
                                ),
                              ),
                            ...teams.map(
                              (team) => DropdownMenuItem(
                                value: team.id,
                                child: Text(
                                  '${team.name} • '
                                  '${activeDivisionNames[team.divisionId] ?? 'Active division'}',
                                ),
                              ),
                            ),
                          ],
                          onChanged: _requestLocked
                              ? null
                              : (value) => setState(() {
                                  _teamId = value == null || value.isEmpty
                                      ? null
                                      : value;
                                  _error = null;
                                }),
                        ),
                      if (teamsReady && teams.isEmpty && _role == 'rep') ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Create a team before issuing representative access.',
                          style: TextStyle(color: AppColors.urgent),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _daysValid,
                        decoration: const InputDecoration(
                          labelText: 'Expires in',
                        ),
                        items: AppDefaults.inviteCodeDaysValidOptions
                            .where((days) => days <= 30)
                            .map(
                              (days) => DropdownMenuItem(
                                value: days,
                                child: Text('$days days'),
                              ),
                            )
                            .toList(),
                        onChanged: _requestLocked
                            ? null
                            : (value) => setState(() {
                                _daysValid = value!;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Each code works once. The server applies the selected role and team when the invite is redeemed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: const Key('invite-create-error'),
                            style: const TextStyle(color: AppColors.urgent),
                          ),
                        ),
                      ],
                    ],
                  )
                : _IssuedInviteContent(
                    issued: _issued!,
                    copied: _copied,
                    copying: _copying,
                    copyError: _copyError,
                    onCopy: _copy,
                  ),
          ),
        ),
        actions: _restoring || _verifying
            ? const <Widget>[]
            : _pendingVerification != null
            ? [
                FilledButton.icon(
                  onPressed: _retryPendingSafetyCheck,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _attempt == null ? 'Check again' : 'Retry secure cleanup',
                  ),
                ),
              ]
            : _nonSendableOutcome != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Close'),
                ),
              ]
            : _issued != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ]
            : [
                if (_attempt == null)
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                FilledButton.icon(
                  key: const Key('generate-invite-submit'),
                  onPressed: canSubmit ? _submit : null,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _ambiguous ? Icons.refresh : Icons.vpn_key_outlined,
                        ),
                  label: Text(
                    _ambiguous
                        ? (_error?.startsWith('An unfinished') ?? false)
                              ? 'Recover invite'
                              : 'Retry same request'
                        : 'Generate code',
                  ),
                ),
              ],
      ),
    );
  }
}

class _IssuedInviteContent extends StatelessWidget {
  final IssuedInviteCode issued;
  final bool copied;
  final bool copying;
  final String? copyError;
  final VoidCallback onCopy;

  const _IssuedInviteContent({
    required this.issued,
    required this.copied,
    required this.copying,
    required this.copyError,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Send this code now. It exists only in this window. Closing this window or the app will not recover or show it again.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            border: Border.all(color: AppColors.primary),
          ),
          child: SelectableText(
            issued.code,
            key: const Key('issued-invite-secret'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: copying ? null : onCopy,
          icon: copying
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(copied ? Icons.check : Icons.copy),
          label: Text(copied ? 'Copied' : 'Copy code'),
        ),
        if (copyError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              copyError!,
              key: const Key('invite-copy-error'),
              style: const TextStyle(color: AppColors.urgent),
            ),
          ),
        ] else if (copied) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: const Text(
              'Copied to clipboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  final InviteCodeModel code;
  final String? teamName;
  final bool isRevoking;
  final VoidCallback onRevoke;

  const _CodeCard({
    required this.code,
    required this.teamName,
    required this.isRevoking,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final expired = !code.isValid;
    final statusColor = expired ? AppColors.urgent : AppColors.success;
    final statusText = switch (code.status) {
      'revoked' => 'REVOKED',
      'redeemed' => 'REDEEMED',
      _ when code.usesRemaining <= 0 => 'USED UP',
      _ when DateTime.now().isAfter(code.expiresAt) => 'EXPIRED',
      _ when code.isValid => 'ACTIVE',
      _ => 'INVALID',
    };
    final teamLabel = code.teamId == null
        ? 'Association-wide'
        : teamName ?? 'Assigned team unavailable';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: expired ? Theme.of(context).dividerColor : statusColor,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(Icons.vpn_key, color: statusColor, size: 20),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              code.displayId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${code.role.toUpperCase()} • $teamLabel • Expires ${DateFormat('MMM d').format(code.expiresAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: isRevoking
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Revoke ${code.displayId}',
                icon: const Icon(
                  Icons.block_outlined,
                  size: 20,
                  color: AppColors.urgent,
                ),
                onPressed: code.isValid ? onRevoke : null,
              ),
      ),
    );
  }
}

String _friendlyInviteError(Object error, {required String fallback}) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'permission-denied' =>
        'Your invite permissions changed. Refresh your session or contact a Super Admin.',
      'unauthenticated' => 'Your session expired. Sign in again and retry.',
      'invalid-argument' =>
        'A selected team or invite setting is no longer valid. Refresh and try again.',
      'failed-precondition' =>
        'This invite is no longer active or the request state changed. Refresh and try again.',
      'not-found' =>
        'This invite or team is no longer available. Refresh and try again.',
      _ => fallback,
    };
  }
  final mapped = ErrorMapper.map(error);
  return mapped == 'An unexpected error occurred. Please try again'
      ? fallback
      : mapped;
}
