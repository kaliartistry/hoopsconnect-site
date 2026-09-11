import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_constrained_content.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/division_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';

class DivisionManagementScreen extends ConsumerWidget {
  const DivisionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final canManage =
        ref.watch(currentUserProvider).valueOrNull?.canManageDivisions ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Divisions'),
      ),
      body: divisionsAsync.when(
        data: (divisions) {
          if (divisions.isEmpty) {
            return AppConstrainedContent(
              child: AppStateMessage(
                title: 'No divisions yet',
                message: canManage
                    ? 'Create the first division before adding teams or games.'
                    : 'A league administrator has not created a division yet.',
                icon: Icons.category_outlined,
                actionLabel: canManage ? 'Create division' : null,
                onAction: canManage
                    ? () => _showDivisionDialog(context, ref)
                    : null,
              ),
            );
          }
          final ordered = [...divisions]
            ..sort((a, b) {
              final status = a.status.index.compareTo(b.status.index);
              return status != 0
                  ? status
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: ordered.length,
            itemBuilder: (context, index) =>
                _DivisionCard(division: ordered[index], canManage: canManage),
          );
        },
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
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showDivisionDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New division'),
            )
          : null,
    );
  }
}

class _DivisionCard extends ConsumerStatefulWidget {
  const _DivisionCard({required this.division, required this.canManage});

  final DivisionModel division;
  final bool canManage;

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
          division.description?.trim().isNotEmpty == true
              ? division.description!
              : division.isArchived
              ? 'Hidden from new team and schedule forms'
              : 'Available for teams and scheduling',
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
                    onPressed: () =>
                        _showDivisionDialog(context, ref, existing: division),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More actions for ${division.name}',
                    onSelected: (action) {
                      if (action == 'archive') {
                        _setArchived(!division.isArchived);
                      } else if (action == 'delete') {
                        _inspectAndConfirmDelete();
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
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete permanently'),
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

  Future<void> _inspectAndConfirmDelete() async {
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;
    setState(() => _updating = true);
    try {
      final report = await ref
          .read(divisionRepositoryProvider)
          .inspectDependencies(assocId, widget.division.id);
      if (!mounted) return;
      if (!report.canDelete) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Division cannot be deleted'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.division.name} is still used by ${report.summary}. Move those records to another division first, or archive this division.',
                  ),
                  if (report.teamNames.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Teams',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...report.teamNames.take(5).map((name) => Text('• $name')),
                  ],
                  if (report.eventTitles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Scheduled events',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...report.eventTitles
                        .take(5)
                        .map((title) => Text('• $title')),
                  ],
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
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete division permanently?'),
          content: Text(
            '${widget.division.name} has no teams or scheduled events linked to it. Deleting it cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete permanently'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final secondReport = await ref
          .read(divisionRepositoryProvider)
          .deleteIfUnreferenced(assocId, widget.division.id);
      if (!mounted) return;
      if (!secondReport.canDelete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deletion stopped because ${secondReport.summary} was linked while you were reviewing.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.division.name} deleted.')),
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
}

Future<void> _showDivisionDialog(
  BuildContext context,
  WidgetRef ref, {
  DivisionModel? existing,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _DivisionEditorDialog(existing: existing),
  );
}

class _DivisionEditorDialog extends ConsumerStatefulWidget {
  const _DivisionEditorDialog({this.existing});

  final DivisionModel? existing;

  @override
  ConsumerState<_DivisionEditorDialog> createState() =>
      _DivisionEditorDialogState();
}

class _DivisionEditorDialogState extends ConsumerState<_DivisionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name);
    _descriptionController = TextEditingController(
      text: widget.existing?.description,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
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
      final repository = ref.read(divisionRepositoryProvider);
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      if (widget.existing == null) {
        await repository.createDivision(
          assocId,
          DivisionModel(
            id: '',
            name: name,
            description: description.isEmpty ? null : description,
          ),
        );
      } else {
        await repository.updateDivision(assocId, widget.existing!.id, {
          'name': name,
          'description': description.isEmpty ? null : description,
        });
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
