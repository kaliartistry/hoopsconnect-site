import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../models/division_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';

void _showDivisionDialog(BuildContext context, WidgetRef ref,
    {DivisionModel? existing}) {
  final nameController = TextEditingController(text: existing?.name);
  final descController = TextEditingController(text: existing?.description);
  final isEditing = existing != null;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isEditing ? 'Edit Division' : 'New Division'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Division Name',
              hintText: "e.g. Men's Open",
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descController,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'e.g. Open division for men 18+',
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final name = nameController.text.trim();
            if (name.isEmpty) return;

            final assocId = ref.read(currentAssociationIdProvider);
            if (assocId == null) return;

            final repo = ref.read(divisionRepositoryProvider);

            if (isEditing) {
              await repo.updateDivision(assocId, existing.id, {
                'name': name,
                'description': descController.text.trim(),
              });
            } else {
              await repo.createDivision(
                assocId,
                DivisionModel(
                  id: '',
                  name: name,
                  description: descController.text.trim(),
                ),
              );
            }

            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    ),
  );
}

class DivisionManagementScreen extends ConsumerWidget {
  const DivisionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final divisionsAsync = ref.watch(divisionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Divisions / Leagues'),
      ),
      body: divisionsAsync.when(
        data: (divisions) {
          if (divisions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined,
                      size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No divisions yet',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap + to create your first division',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: divisions.length,
            itemBuilder: (context, index) {
              final div = divisions[index];
              return _DivisionCard(division: div);
            },
          );
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDivisionDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DivisionCard extends ConsumerWidget {
  final DivisionModel division;
  const _DivisionCard({required this.division});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(Icons.category, color: AppColors.primary),
        ),
        title: Text(
          division.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: division.description != null &&
                division.description!.isNotEmpty
            ? Text(
                division.description!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              )
            : null,
        trailing: PopupMenuButton<String>(
          onSelected: (action) {
            if (action == 'edit') {
              _showDivisionDialog(context, ref, existing: division);
            } else if (action == 'delete') {
              _confirmDelete(context, ref);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: AppColors.urgent)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Division'),
        content: Text('Delete "${division.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.urgent),
            onPressed: () async {
              final assocId = ref.read(currentAssociationIdProvider);
              if (assocId == null) return;
              await ref
                  .read(divisionRepositoryProvider)
                  .deleteDivision(assocId, division.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
