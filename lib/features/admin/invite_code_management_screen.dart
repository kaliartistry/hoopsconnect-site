import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../models/invite_code_model.dart';
import '../../providers/auth_providers.dart';

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
      final codes =
          await ref.read(inviteCodeRepositoryProvider).getAllCodes();
      if (mounted) setState(() => _codes = codes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _generateCode() {
    const chars = AppDefaults.inviteCodeCharset;
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _showCreateDialog() {
    String role = 'rep';
    int uses = AppDefaults.inviteCodeDefaultMaxUses;
    int daysValid = AppDefaults.inviteCodeDefaultDaysValid;
    final teamIdController = TextEditingController();

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
                  DropdownMenuItem(value: 'statistician', child: Text('Statistician')),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: uses,
                      decoration: const InputDecoration(labelText: 'Max Uses'),
                      items: AppDefaults.inviteCodeMaxUsesOptions
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (v) => setDialogState(() => uses = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: daysValid,
                      decoration:
                          const InputDecoration(labelText: 'Expires (days)'),
                      items: AppDefaults.inviteCodeDaysValidOptions
                          .map((n) => DropdownMenuItem(
                              value: n, child: Text('$n days')))
                          .toList(),
                      onChanged: (v) => setDialogState(() => daysValid = v!),
                    ),
                  ),
                ],
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
                if (teamId.isEmpty) return;

                final assocId =
                    ref.read(currentAssociationIdProvider) ?? AppDefaults.defaultAssociationId;
                final code = InviteCodeModel(
                  code: _generateCode(),
                  teamId: teamId,
                  role: role,
                  usesRemaining: uses,
                  expiresAt:
                      DateTime.now().add(Duration(days: daysValid)),
                  associationId: assocId,
                );

                await ref
                    .read(inviteCodeRepositoryProvider)
                    .createCode(code);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadCodes();
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
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _codes == null || _codes!.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.vpn_key_outlined,
                              size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text(
                            'No invite codes',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap + to generate a code',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13),
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
                                  .deleteCode(code.code);
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
    final statusText = expired
        ? (code.usesRemaining <= 0 ? 'USED UP' : 'EXPIRED')
        : 'ACTIVE';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: expired ? Theme.of(context).dividerColor : statusColor),
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
              code.code,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          style:
              const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.urgent),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Code'),
                    content:
                        Text('Delete invite code "${code.code}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.urgent),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onDelete();
                        },
                        child: const Text('Delete'),
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
