import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../models/invite_code_model.dart';
import '../../providers/auth_providers.dart';
import '../../services/repositories/invite_code_repository.dart';

class InviteCodeManagementScreen extends ConsumerStatefulWidget {
  const InviteCodeManagementScreen({super.key});

  @override
  ConsumerState<InviteCodeManagementScreen> createState() =>
      _InviteCodeManagementScreenState();
}

class _InviteCodeManagementScreenState
    extends ConsumerState<InviteCodeManagementScreen> {
  List<InviteCodeModel>? _codes;
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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    String role = 'rep';
    int daysValid = AppDefaults.inviteCodeDefaultDaysValid;
    final teamIdController = TextEditingController();
    final operationId = newInviteOperationId();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generate Invite Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: teamIdController,
                decoration: const InputDecoration(
                  labelText: 'Team ID',
                  hintText: 'e.g. team-001',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'rep', child: Text('Rep')),
                  DropdownMenuItem(value: 'media', child: Text('Media')),
                  DropdownMenuItem(
                    value: 'statistician',
                    child: Text('Statistician'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: daysValid,
                decoration: const InputDecoration(labelText: 'Expires (days)'),
                items: AppDefaults.inviteCodeDaysValidOptions
                    .where((days) => days <= 30)
                    .map(
                      (days) => DropdownMenuItem(
                        value: days,
                        child: Text('$days days'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => daysValid = value!),
              ),
              const SizedBox(height: 8),
              const Text(
                'Each code is single-use. Role and team assignment are applied by the server when redeemed.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                final teamId = teamIdController.text.trim();
                if (role == 'rep' && teamId.isEmpty) return;

                final issued = await ref
                    .read(inviteCodeRepositoryProvider)
                    .createCode(
                      role: role,
                      teamId: teamId.isEmpty ? null : teamId,
                      daysValid: daysValid,
                      operationId: operationId,
                    );
                await Clipboard.setData(ClipboardData(text: issued.code));
                if (ctx.mounted) Navigator.pop(ctx);
                _loadCodes();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invite created and copied. It cannot be viewed again.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Invite Codes'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _codes == null || _codes!.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No invite codes',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap + to generate a code',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
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
                    onDelete: () async {
                      await ref
                          .read(inviteCodeRepositoryProvider)
                          .revokeCode(code.inviteId);
                      _loadCodes();
                    },
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final InviteCodeModel code;
  final VoidCallback onDelete;

  const _CodeCard({required this.code, required this.onDelete});

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
        title: Row(
          children: [
            Text(
              code.displayId,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
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
          '${code.role.toUpperCase()} · ${code.usesRemaining} uses left · Expires ${DateFormat('MMM d').format(code.expiresAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.urgent,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Revoke Code'),
                    content: Text(
                      'Revoke invite "${code.displayId}"? It cannot be used afterward.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.urgent,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onDelete();
                        },
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
