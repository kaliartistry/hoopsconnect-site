import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_constrained_content.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/association_branding_model.dart';
import '../../models/division_model.dart';
import '../../models/league_catalog_model.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/league_workflow_providers.dart';
import '../../services/repositories/division_repository.dart';

class DivisionManagementScreen extends ConsumerWidget {
  const DivisionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final catalogAsync = ref.watch(leagueCatalogProvider);
    final canManage =
        ref.watch(currentUserProvider).valueOrNull?.canManageDivisions ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('League divisions'),
      ),
      body: catalogAsync.when(
        loading: () =>
            const Center(child: AppLoadingState(label: 'Loading leagues')),
        error: (error, _) => AppConstrainedContent(
          child: AppStateMessage(
            title: 'Leagues could not be loaded',
            message: ErrorMapper.map(error),
            tone: AppStateTone.error,
          ),
        ),
        data: (catalog) => divisionsAsync.when(
          data: (divisions) => _DivisionHierarchy(
            catalog: catalog,
            divisions: divisions,
            canManage: canManage,
            onCreate: (leagueId) => _showDivisionDialog(
              context,
              ref,
              catalog,
              initialLeagueId: leagueId,
            ),
          ),
          loading: () =>
              const Center(child: AppLoadingState(label: 'Loading divisions')),
          error: (error, _) => AppConstrainedContent(
            child: AppStateMessage(
              title: 'Divisions could not be loaded',
              message: ErrorMapper.map(error),
              tone: AppStateTone.error,
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(divisionsStreamProvider),
            ),
          ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed:
                  catalogAsync.valueOrNull?.orderedActive.isEmpty != false
                  ? null
                  : () => _showDivisionDialog(
                      context,
                      ref,
                      catalogAsync.requireValue,
                    ),
              icon: const Icon(Icons.add),
              label: const Text('Add division to league'),
            )
          : null,
    );
  }
}

class _DivisionHierarchy extends StatelessWidget {
  const _DivisionHierarchy({
    required this.catalog,
    required this.divisions,
    required this.canManage,
    required this.onCreate,
  });

  final LeagueCatalogModel catalog;
  final List<DivisionModel> divisions;
  final bool canManage;
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final leagues = catalog.orderedActive;
    if (leagues.isEmpty) {
      return AppConstrainedContent(
        child: AppStateMessage(
          title: 'Create a league first',
          message:
              'Divisions cannot stand on their own. Create the parent league, then add its divisions beneath it.',
          icon: Icons.account_tree_outlined,
          actionLabel: canManage ? 'Go to leagues' : null,
          onAction: canManage ? () => context.go('/admin/leagues') : null,
        ),
      );
    }

    final byId = {for (final division in divisions) division.id: division};
    final assignedIds = <String>{};
    for (final league in catalog.leagues) {
      assignedIds.addAll(league.divisionIds);
    }
    final unassigned = divisions
        .where((division) => !assignedIds.contains(division.id))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        const AppStateMessage(
          title: 'League → division hierarchy',
          message:
              'Every division belongs to one parent league. Teams, schedules, standings, and leaders inherit that league context.',
          icon: Icons.account_tree_outlined,
          compact: true,
        ),
        const SizedBox(height: 12),
        for (final league in leagues) ...[
          Builder(
            builder: (context) {
              final leagueColor = AssociationBrandingModel.colorFromHex(
                league.primaryColorHex,
              );
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: leagueColor.withValues(alpha: 0.16),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sports_basketball_outlined,
                              color: leagueColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    league.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    '${league.divisionIds.length} ${league.divisionIds.length == 1 ? 'division' : 'divisions'} beneath this league',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (canManage)
                              TextButton.icon(
                                onPressed: () => onCreate(league.id),
                                icon: const Icon(Icons.add),
                                label: const Text('Add division'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (league.divisionIds.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No divisions have been added under this league.',
                        ),
                      )
                    else
                      for (final divisionId in league.divisionIds)
                        if (byId[divisionId] case final division?)
                          _DivisionCard(
                            division: division,
                            parentLeagueId: league.id,
                            parentLeagueName: league.name,
                            canManage: canManage,
                          )
                        else
                          ListTile(
                            leading: const Icon(Icons.warning_amber_rounded),
                            title: Text('Missing division record: $divisionId'),
                            subtitle: const Text(
                              'Repair this league before scheduling teams or games.',
                            ),
                          ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (unassigned.isNotEmpty) ...[
          AppStateMessage(
            title: 'Legacy divisions need a parent league',
            message:
                '${unassigned.length} older division records are not attached to a league. Edit each one to complete the migration.',
            tone: AppStateTone.warning,
            icon: Icons.warning_amber_rounded,
            compact: true,
          ),
          const SizedBox(height: 8),
          for (final division in unassigned)
            _DivisionCard(
              division: division,
              parentLeagueName: 'Parent league required',
              canManage: canManage,
            ),
        ],
      ],
    );
  }
}

class _DivisionCard extends ConsumerStatefulWidget {
  const _DivisionCard({
    required this.division,
    required this.canManage,
    required this.parentLeagueName,
    this.parentLeagueId,
  });

  final DivisionModel division;
  final bool canManage;
  final String parentLeagueName;
  final String? parentLeagueId;

  @override
  ConsumerState<_DivisionCard> createState() => _DivisionCardState();
}

class _DivisionCardState extends ConsumerState<_DivisionCard> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final division = widget.division;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            division.isArchived ? Icons.archive_outlined : Icons.category,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                division.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (division.isArchived)
              const Chip(
                label: Text('Archived'),
                avatar: Icon(Icons.archive_outlined, size: 16),
              ),
          ],
        ),
        subtitle: Text(
          '${widget.parentLeagueId == null ? '${widget.parentLeagueName} · ' : ''}${division.description?.trim().isNotEmpty == true
              ? division.description!
              : division.isArchived
              ? 'Hidden from new team and schedule forms'
              : 'Available for teams and scheduling'}',
        ),
        trailing: !widget.canManage
            ? null
            : _updating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit ${division.name}',
                    onPressed: () {
                      final catalog = ref
                          .read(leagueCatalogProvider)
                          .valueOrNull;
                      if (catalog == null) return;
                      _showDivisionDialog(
                        context,
                        ref,
                        catalog,
                        existing: division,
                        initialLeagueId: widget.parentLeagueId,
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More actions for ${division.name}',
                    onSelected: (action) {
                      if (action == 'archive') {
                        _setArchived(!division.isArchived);
                      } else if (action == 'dependencies') {
                        _showDependencies();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'archive',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            division.isArchived
                                ? Icons.unarchive_outlined
                                : Icons.archive_outlined,
                          ),
                          title: Text(
                            division.isArchived ? 'Restore' : 'Archive',
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'dependencies',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.account_tree_outlined),
                          title: Text('Review dependencies'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _setArchived(bool archived) async {
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;
    if (archived) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Archive ${widget.division.name}?'),
          content: Text(
            'This hides the division from new teams and schedules inside ${widget.parentLeagueName}. Existing records stay intact.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive division'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _updating = true);
    try {
      await ref
          .read(divisionRepositoryProvider)
          .setArchived(assocId, widget.division.id, archived: archived);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              archived
                  ? '${widget.division.name} archived. Existing teams and games are unchanged.'
                  : '${widget.division.name} restored.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(error))));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _showDependencies() async {
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;
    setState(() => _updating = true);
    try {
      final report = await ref
          .read(divisionRepositoryProvider)
          .inspectDependencies(assocId, widget.division.id);
      if (!mounted) return;
      final deleteReady =
          ref
              .read(leagueWorkflowCapabilityProvider)
              .valueOrNull
              ?.divisionDeletionEnabled ==
          true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Division dependencies'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  report.hasReferences
                      ? '${widget.division.name} is still used by ${report.summary}. Move those records first, or archive the division.'
                      : '${widget.division.name} has no legacy team or scheduled-event references in this check.',
                ),
                if (report.teamReferences.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Teams',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...report.teamReferences
                      .take(10)
                      .map((reference) => Text('• ${reference.displayName}')),
                ],
                if (report.eventReferences.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Scheduled events',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...report.eventReferences
                      .take(10)
                      .map((reference) => Text('• ${reference.displayName}')),
                ],
                const SizedBox(height: 16),
                AppStateMessage(
                  title: deleteReady
                      ? 'Protected deletion is ready'
                      : 'Permanent deletion is unavailable',
                  message: deleteReady
                      ? 'The server will fence this division, inspect legacy and canonical dependencies, and delete only if every reference check is empty.'
                      : 'The server capability has not confirmed the callable, lifecycle fences, and direct-write deny rules. Archive is available now.',
                  tone: AppStateTone.warning,
                  compact: true,
                ),
              ],
            ),
          ),
          actions: [
            if (deleteReady)
              TextButton(
                onPressed: () => _deletePermanently(ctx),
                child: const Text('Permanently delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(error))));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _deletePermanently(BuildContext dialogContext) async {
    final actorId = ref.read(authStateProvider).valueOrNull?.uid;
    final associationId = ref.read(currentAssociationIdProvider);
    if (actorId == null || associationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your current league account could not be confirmed.'),
        ),
      );
      return;
    }
    try {
      final receipt = await ref
          .read(divisionRepositoryProvider)
          .deleteIfUnreferenced(
            actorId: actorId,
            associationId: associationId,
            divisionId: widget.division.id,
            expectedDivisionVersion: widget.division.version,
          );
      if (!mounted || !dialogContext.mounted) return;
      if (receipt.deleted) {
        Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.division.name} permanently deleted.'),
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Division is still in use'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nothing was deleted. Move or retain these records, or archive the division.',
                ),
                const SizedBox(height: 12),
                ...receipt.references
                    .take(20)
                    .map(
                      (reference) => Text(
                        '• ${reference.displayName ?? reference.id} (${reference.kind})',
                      ),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on DivisionDeleteStaleVersionException catch (error) {
      try {
        await ref
            .read(divisionRepositoryProvider)
            .rebaseDefinitiveStaleVersion(
              actorId: actorId,
              associationId: associationId,
              divisionId: widget.division.id,
              currentDivisionVersion: error.currentDivisionVersion,
            );
        if (!mounted) return;
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The division changed. Review the latest details, then confirm deletion again.',
            ),
          ),
        );
      } catch (rebaseError) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(rebaseError))));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(error))));
    }
  }
}

Future<void> _showDivisionDialog(
  BuildContext context,
  WidgetRef ref,
  LeagueCatalogModel catalog, {
  DivisionModel? existing,
  String? initialLeagueId,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _DivisionEditorDialog(
      catalog: catalog,
      existing: existing,
      initialLeagueId: initialLeagueId,
    ),
  );
}

class _DivisionEditorDialog extends ConsumerStatefulWidget {
  const _DivisionEditorDialog({
    required this.catalog,
    this.existing,
    this.initialLeagueId,
  });

  final LeagueCatalogModel catalog;
  final DivisionModel? existing;
  final String? initialLeagueId;

  @override
  ConsumerState<_DivisionEditorDialog> createState() =>
      _DivisionEditorDialogState();
}

class _DivisionEditorDialogState extends ConsumerState<_DivisionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  String? _leagueId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name);
    _descriptionController = TextEditingController(
      text: widget.existing?.description,
    );
    _leagueId = widget.existing?.leagueId ?? widget.initialLeagueId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_leagueId == null) {
      setState(() => _error = 'Choose the parent league.');
      return;
    }
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) {
      setState(() => _error = 'Your association could not be confirmed.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      if (widget.existing == null) {
        await ref
            .read(associationRepositoryProvider)
            .createDivisionUnderLeague(
              associationId: assocId,
              leagueId: _leagueId!,
              name: name,
              description: description.isEmpty ? null : description,
            );
      } else {
        await ref
            .read(associationRepositoryProvider)
            .updateDivisionUnderLeague(
              associationId: assocId,
              divisionId: widget.existing!.id,
              leagueId: _leagueId!,
              name: name,
              description: description.isEmpty ? null : description,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ErrorMapper.map(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Create division' : 'Edit division',
      ),
      content: AppFormFocusGroup(
        onCancel: () => Navigator.of(context).pop(),
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('division-parent-league-field'),
                  initialValue:
                      widget.catalog.leagues.any(
                        (league) =>
                            league.id == _leagueId && !league.isArchived,
                      )
                      ? _leagueId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Parent league',
                    helperText: 'Every division must live under one league.',
                  ),
                  items: [
                    for (final league in widget.catalog.orderedActive)
                      DropdownMenuItem(
                        value: league.id,
                        child: Text(league.name),
                      ),
                  ],
                  onChanged: widget.existing?.hasParentLeague == true
                      ? null
                      : (value) => setState(() => _leagueId = value),
                  validator: (value) =>
                      value == null ? 'Choose the parent league' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Division name',
                    hintText: "e.g. Men's Open",
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a division name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AppStateMessage(
                    title: 'Division not saved',
                    message: _error!,
                    tone: AppStateTone.error,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppAsyncActionButton(
          label: widget.existing == null ? 'Create division' : 'Save changes',
          busyLabel: 'Saving division',
          isBusy: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
