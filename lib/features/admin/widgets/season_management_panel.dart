import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/season_model.dart';
import '../../../providers/auth_providers.dart';
import '../../../providers/league_workflow_providers.dart';
import '../../../providers/season_providers.dart';
import '../../../services/repositories/season_repository.dart';

class SeasonManagementLauncher extends ConsumerWidget {
  const SeasonManagementLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      key: const Key('manage-seasons'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const SeasonManagementDialog(),
      ),
      icon: const Icon(Icons.event_repeat),
      label: const Text('Manage seasons'),
    );
  }
}

class SeasonManagementDialog extends ConsumerStatefulWidget {
  const SeasonManagementDialog({super.key});

  @override
  ConsumerState<SeasonManagementDialog> createState() =>
      _SeasonManagementDialogState();
}

class _SeasonManagementDialogState
    extends ConsumerState<SeasonManagementDialog> {
  String? _busySeasonId;
  String? _message;
  String? _error;
  bool _canRetry = false;
  Future<void> Function()? _retry;
  bool _canDiscard = false;
  Future<void> Function()? _discard;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final associationId = ref.watch(currentAssociationIdProvider);
    final currentSeasonId = ref.watch(activeSeasonIdProvider).valueOrNull;
    final seasons = ref.watch(seasonsStreamProvider);
    final workflow = ref.watch(leagueWorkflowCapabilityProvider);
    final enabled = workflow.valueOrNull?.seasonLifecycleEnabled == true;
    final loading = seasons.isLoading || workflow.isLoading;
    final error = seasons.hasError
        ? 'Seasons could not be loaded. Close this window and try again.'
        : workflow.hasError
        ? 'Season controls could not be verified. Close this window and try again.'
        : _error;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Season management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close season management',
                    onPressed: _busySeasonId == null
                        ? () => Navigator.pop(context)
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SeasonManagementView(
                  seasons: seasons.valueOrNull ?? const [],
                  currentSeasonId: currentSeasonId,
                  workflowEnabled: enabled,
                  loading: loading,
                  busySeasonId: _busySeasonId,
                  message: _message,
                  error: error,
                  canRetry: _canRetry,
                  onRetry: _retry,
                  canDiscard: _canDiscard,
                  onDiscard: _discard,
                  onPrepare: enabled && user != null && associationId != null
                      ? () => _showPrepareDialog(
                          actorId: user.id,
                          associationId: associationId,
                        )
                      : null,
                  onActivate:
                      enabled &&
                          user != null &&
                          associationId != null &&
                          currentSeasonId != null
                      ? (season) => _confirmActivate(
                          actorId: user.id,
                          associationId: associationId,
                          currentSeasonId: currentSeasonId,
                          seasons: seasons.valueOrNull ?? const [],
                          season: season,
                        )
                      : null,
                  onArchive:
                      enabled &&
                          user != null &&
                          associationId != null &&
                          currentSeasonId != null
                      ? (season) => _confirmArchive(
                          actorId: user.id,
                          associationId: associationId,
                          currentSeasonId: currentSeasonId,
                          season: season,
                        )
                      : null,
                  onRestore:
                      enabled &&
                          user != null &&
                          associationId != null &&
                          currentSeasonId != null
                      ? (season) => _confirmRestore(
                          actorId: user.id,
                          associationId: associationId,
                          currentSeasonId: currentSeasonId,
                          season: season,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPrepareDialog({
    required String actorId,
    required String associationId,
  }) async {
    final nameController = TextEditingController();
    var startDate = DateTime.now();
    var endDate = DateTime.now().add(const Duration(days: 180));
    String? validationError;
    final draft = await showDialog<_SeasonDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Prepare a season'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preparation creates an inactive season. It does not change the current season.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('season-name'),
                  controller: nameController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Season name',
                    hintText: 'e.g. NBL 2027',
                  ),
                ),
                _DateRow(
                  label: 'Start date',
                  value: startDate,
                  onChanged: (date) => setDialogState(() => startDate = date),
                ),
                _DateRow(
                  label: 'End date',
                  value: endDate,
                  onChanged: (date) => setDialogState(() => endDate = date),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-prepare-season'),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(
                    () => validationError = 'Enter a season name.',
                  );
                  return;
                }
                if (startDate.isAfter(endDate)) {
                  setDialogState(
                    () => validationError =
                        'The start date must be on or before the end date.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _SeasonDraft(name, startDate, endDate),
                );
              },
              child: const Text('Prepare season'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (draft == null || !mounted) return;
    final seasonId = SeasonRepository.stableSeasonId(draft.name);
    await _run(
      seasonId,
      () => ref
          .read(seasonRepositoryProvider)
          .prepareSeason(
            actorId: actorId,
            associationId: associationId,
            name: draft.name,
            startDate: draft.startDate,
            endDate: draft.endDate,
          ),
      success: 'Season "${draft.name}" is prepared and still inactive.',
    );
  }

  Future<void> _confirmActivate({
    required String actorId,
    required String associationId,
    required String currentSeasonId,
    required List<SeasonModel> seasons,
    required SeasonModel season,
  }) async {
    final current = seasons
        .where((item) => item.id == currentSeasonId)
        .firstOrNull;
    final approved = await _confirmation(
      title: 'Activate ${season.name}?',
      body:
          'The current season will change from "${current?.name ?? currentSeasonId}" '
          '($currentSeasonId) to "${season.name}" (${season.id}). '
          'The previous season, games, results, and routes stay in history.',
      action: 'Activate season',
    );
    if (!approved || !mounted) return;
    await _run(
      season.id,
      () => ref
          .read(seasonRepositoryProvider)
          .activateSeason(
            actorId: actorId,
            associationId: associationId,
            season: season,
            currentSeasonId: currentSeasonId,
          ),
      success: '"${season.name}" is now the current season.',
    );
  }

  Future<void> _confirmArchive({
    required String actorId,
    required String associationId,
    required String currentSeasonId,
    required SeasonModel season,
  }) async {
    final approved = await _confirmation(
      title: 'Archive ${season.name}?',
      body:
          'This hides the season from active setup choices. Historical games, results, and routes remain available. You can restore it later.',
      action: 'Archive season',
      destructive: true,
    );
    if (!approved || !mounted) return;
    await _run(
      season.id,
      () => ref
          .read(seasonRepositoryProvider)
          .archiveSeason(
            actorId: actorId,
            associationId: associationId,
            season: season,
            currentSeasonId: currentSeasonId,
          ),
      success: '"${season.name}" is archived. Its history is unchanged.',
    );
  }

  Future<void> _confirmRestore({
    required String actorId,
    required String associationId,
    required String currentSeasonId,
    required SeasonModel season,
  }) async {
    final approved = await _confirmation(
      title: 'Restore ${season.name}?',
      body:
          'This returns the season to the inactive list. It will not replace the current season.',
      action: 'Restore season',
    );
    if (!approved || !mounted) return;
    await _run(
      season.id,
      () => ref
          .read(seasonRepositoryProvider)
          .restoreSeason(
            actorId: actorId,
            associationId: associationId,
            season: season,
            currentSeasonId: currentSeasonId,
          ),
      success: '"${season.name}" is restored and remains inactive.',
    );
  }

  Future<bool> _confirmation({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run(
    String seasonId,
    Future<SeasonOperationReceipt> Function() operation, {
    required String success,
  }) async {
    setState(() {
      _busySeasonId = seasonId;
      _message = null;
      _error = null;
      _canRetry = false;
      _retry = null;
      _canDiscard = false;
      _discard = null;
    });
    try {
      await operation();
      if (!mounted) return;
      setState(() => _message = success);
    } on SeasonPendingRequestConflict catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _canRetry = true;
        _retry = () => _run(
          seasonId,
          () => ref
              .read(seasonRepositoryProvider)
              .retryPendingOperation(error.recovery),
          success: 'The earlier season request was safely reconciled.',
        );
        _canDiscard = true;
        _discard = () => _confirmDiscardPending(error.recovery);
      });
    } on SeasonWorkflowException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _canRetry = error.retryable;
        _retry = error.retryable
            ? () => _run(seasonId, operation, success: success)
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ArgumentError
            ? error.message?.toString() ?? 'Check the season details.'
            : 'The season operation could not be completed.';
      });
    } finally {
      if (mounted) setState(() => _busySeasonId = null);
    }
  }

  Future<void> _confirmDiscardPending(SeasonPendingRecovery recovery) async {
    final approved = await _confirmation(
      title: 'Discard the saved retry?',
      body:
          'This removes only this device’s saved retry. It does not undo a season change that may already have reached the server. The latest season list will still be used before another change.',
      action: 'Discard saved retry',
      destructive: true,
    );
    if (!approved || !mounted) return;
    setState(() => _busySeasonId = recovery.seasonId);
    try {
      await ref
          .read(seasonRepositoryProvider)
          .discardPendingOperation(recovery);
      if (!mounted) return;
      setState(() {
        _message =
            'The saved retry was discarded. Review the latest season state before trying again.';
        _error = null;
        _canRetry = false;
        _retry = null;
        _canDiscard = false;
        _discard = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The saved retry could not be discarded on this device.';
        _canRetry = false;
      });
    } finally {
      if (mounted) setState(() => _busySeasonId = null);
    }
  }
}

class SeasonManagementView extends StatelessWidget {
  final List<SeasonModel> seasons;
  final String? currentSeasonId;
  final bool workflowEnabled;
  final bool loading;
  final String? busySeasonId;
  final String? message;
  final String? error;
  final bool canRetry;
  final VoidCallback? onRetry;
  final bool canDiscard;
  final VoidCallback? onDiscard;
  final VoidCallback? onPrepare;
  final ValueChanged<SeasonModel>? onActivate;
  final ValueChanged<SeasonModel>? onArchive;
  final ValueChanged<SeasonModel>? onRestore;

  const SeasonManagementView({
    super.key,
    required this.seasons,
    required this.currentSeasonId,
    required this.workflowEnabled,
    required this.loading,
    required this.busySeasonId,
    required this.message,
    required this.error,
    required this.canRetry,
    required this.onRetry,
    required this.canDiscard,
    required this.onDiscard,
    required this.onPrepare,
    required this.onActivate,
    required this.onArchive,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!workflowEnabled && !loading)
          _Notice(
            key: const Key('season-workflow-closed'),
            icon: Icons.lock_clock_outlined,
            text:
                'Season changes are safely locked until the server readiness checks are activated.',
            error: false,
          ),
        if (message != null)
          _Notice(
            icon: Icons.check_circle_outline,
            text: message!,
            error: false,
          ),
        if (error != null)
          _Notice(
            icon: Icons.error_outline,
            text: error!,
            error: true,
            action:
                (canRetry && onRetry != null) ||
                    (canDiscard && onDiscard != null)
                ? Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (canRetry && onRetry != null)
                        TextButton(
                          onPressed: busySeasonId == null ? onRetry : null,
                          child: const Text('Retry safely'),
                        ),
                      if (canDiscard && onDiscard != null)
                        TextButton(
                          onPressed: busySeasonId == null ? onDiscard : null,
                          child: const Text('Discard saved retry'),
                        ),
                    ],
                  )
                : null,
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const guidance = Text(
              'Prepare first, then activate when the league is ready.',
              style: TextStyle(fontWeight: FontWeight.w600),
            );
            final button = FilledButton.icon(
              key: const Key('prepare-season'),
              onPressed: busySeasonId == null ? onPrepare : null,
              icon: const Icon(Icons.add),
              label: const Text('Prepare season'),
            );
            if (constraints.maxWidth < 520 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [guidance, const SizedBox(height: 10), button],
              );
            }
            return Row(
              children: [
                const Expanded(child: guidance),
                const SizedBox(width: 12),
                button,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (seasons.isEmpty)
          const Text('No seasons are available yet.')
        else if (wide)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final season in seasons)
                SizedBox(
                  width: 340,
                  child: _SeasonCard(
                    season: season,
                    currentSeasonId: currentSeasonId,
                    busy: busySeasonId == season.id,
                    workflowEnabled: workflowEnabled && busySeasonId == null,
                    onActivate: onActivate,
                    onArchive: onArchive,
                    onRestore: onRestore,
                  ),
                ),
            ],
          )
        else
          Column(
            children: [
              for (final season in seasons) ...[
                _SeasonCard(
                  season: season,
                  currentSeasonId: currentSeasonId,
                  busy: busySeasonId == season.id,
                  workflowEnabled: workflowEnabled && busySeasonId == null,
                  onActivate: onActivate,
                  onArchive: onArchive,
                  onRestore: onRestore,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        const SizedBox(height: 12),
        const Text(
          'Leaderboards are view-only here. Rankings change only through governed stats and publication workflows.',
          key: Key('leaderboard-view-only'),
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _SeasonCard extends StatelessWidget {
  final SeasonModel season;
  final String? currentSeasonId;
  final bool busy;
  final bool workflowEnabled;
  final ValueChanged<SeasonModel>? onActivate;
  final ValueChanged<SeasonModel>? onArchive;
  final ValueChanged<SeasonModel>? onRestore;

  const _SeasonCard({
    required this.season,
    required this.currentSeasonId,
    required this.busy,
    required this.workflowEnabled,
    required this.onActivate,
    required this.onArchive,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final current = season.id == currentSeasonId;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: Key('season-${season.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    season.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusBadge(
                  status: current ? SeasonStatus.active : season.status,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              season.startDate.isEmpty || season.endDate.isEmpty
                  ? 'Dates unavailable'
                  : '${season.startDate} to ${season.endDate}',
            ),
            const SizedBox(height: 10),
            if (busy)
              const LinearProgressIndicator(
                key: Key('season-operation-pending'),
              )
            else if (current)
              Text(
                'Current active season. Activate another prepared season before archiving this one.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (season.canActivate)
                    FilledButton.tonal(
                      onPressed: workflowEnabled && onActivate != null
                          ? () => onActivate!(season)
                          : null,
                      child: const Text('Activate'),
                    ),
                  if (season.canArchive)
                    OutlinedButton(
                      onPressed: workflowEnabled && onArchive != null
                          ? () => onArchive!(season)
                          : null,
                      child: const Text('Archive'),
                    ),
                  if (season.canRestore)
                    OutlinedButton.icon(
                      onPressed: workflowEnabled && onRestore != null
                          ? () => onRestore!(season)
                          : null,
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SeasonStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SeasonStatus.active => ('CURRENT', AppColors.success),
      SeasonStatus.prepared => (
        'PREPARED',
        Theme.of(context).colorScheme.primary,
      ),
      SeasonStatus.inactive => (
        'INACTIVE',
        Theme.of(context).colorScheme.outline,
      ),
      SeasonStatus.archived => (
        'ARCHIVED',
        Theme.of(context).colorScheme.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;
  final Widget? action;

  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    required this.error,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          );
          if (action == null) return content;
          if (constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: action!),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              action!,
            ],
          );
        },
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(SeasonRepository.dateOnly(value)),
      trailing: const Icon(Icons.calendar_today, size: 20),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _SeasonDraft {
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  const _SeasonDraft(this.name, this.startDate, this.endDate);
}
