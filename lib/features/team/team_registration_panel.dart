import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/repositories/team_registration_repository.dart';

class TeamRegistrationPanel extends ConsumerStatefulWidget {
  const TeamRegistrationPanel({super.key, required this.target});

  final TeamRegistrationTarget target;

  @override
  ConsumerState<TeamRegistrationPanel> createState() =>
      _TeamRegistrationPanelState();
}

class _TeamRegistrationPanelState extends ConsumerState<TeamRegistrationPanel> {
  bool _saving = false;

  Future<void> _action(
    TeamRegistration registration,
    String action,
    String title, {
    String? playerId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: action == 'submit'
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final player in registration.players)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${player.name}\n${player.summary.join(' · ')}',
                      ),
                    ),
                ],
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(switch (action) {
              'submit' => 'Submit roster',
              'removePlayer' => 'Remove',
              'review' => 'Mark reviewed',
              _ => 'Return to team',
            }),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(teamRegistrationRepositoryProvider)
          .save(
            widget.target,
            action,
            registration.revision,
            operationId: TeamRegistrationRepository.newId(),
            playerId: playerId,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_registrationError(error))));
      }
    } finally {
      if (mounted) {
        ref.invalidate(teamRegistrationProvider(widget.target));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _edit(
    TeamRegistration registration,
    RegistrationPlayer? player,
  ) async {
    final repository = ref.read(teamRegistrationRepositoryProvider);
    final target = widget.target;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlayerRegistrationDialog(
        player: player,
        onSave: (entry, operationId) async {
          await repository.save(
            target,
            'savePlayer',
            registration.revision,
            operationId: operationId,
            player: entry,
          );
        },
      ),
    );
    if (mounted && saved == true) {
      ref.invalidate(teamRegistrationProvider(target));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player saved to the roster draft.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(teamRegistrationProvider(widget.target));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team registration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            registration.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_registrationError(error)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(teamRegistrationProvider(widget.target)),
                    child: const Text('Reload registration'),
                  ),
                ],
              ),
              data: (value) => _registrationContents(value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registrationContents(TeamRegistration value) {
    final draft = value.status == TeamRegistrationStatus.draft;
    final editable = draft && value.canEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (value.status) {
          TeamRegistrationStatus.draft =>
            value.canEdit
                ? '${value.players.length} saved · Draft'
                : 'Awaiting team submission',
          TeamRegistrationStatus.submitted => 'Submitted for league review',
          TeamRegistrationStatus.reviewed => 'Reviewed by league staff',
        }),
        if (editable)
          const Text(
            'Save each player as you go. You can return to this draft after signing in again.',
          ),
        for (final player in value.players)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(player.name),
            subtitle: Text(player.summary.join(' · ')),
            trailing: editable
                ? PopupMenuButton<String>(
                    enabled: !_saving,
                    tooltip: 'Actions for ${player.name}',
                    onSelected: (choice) => choice == 'edit'
                        ? _edit(value, player)
                        : _action(
                            value,
                            'removePlayer',
                            'Remove ${player.name}?',
                            playerId: player.id,
                          ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  )
                : null,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (editable) ...[
              FilledButton(
                onPressed: _saving ? null : () => _edit(value, null),
                child: const Text('Add player'),
              ),
              OutlinedButton(
                onPressed: _saving || value.players.isEmpty
                    ? null
                    : () => _action(value, 'submit', 'Review roster'),
                child: const Text('Review roster'),
              ),
            ],
            if (value.canReview && !draft) ...[
              if (value.status == TeamRegistrationStatus.submitted)
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _action(
                          value,
                          'review',
                          'Mark registration reviewed?',
                        ),
                  child: const Text('Mark reviewed'),
                ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => _action(
                        value,
                        'return',
                        'Return registration to the team?',
                      ),
                child: const Text('Return to team'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PlayerRegistrationDialog extends StatefulWidget {
  const _PlayerRegistrationDialog({required this.player, required this.onSave});

  final RegistrationPlayer? player;
  final Future<void> Function(RegistrationPlayer, String) onSave;

  @override
  State<_PlayerRegistrationDialog> createState() =>
      _PlayerRegistrationDialogState();
}

enum _PlayerStep { essentials, optional, review }

class _PlayerRegistrationDialogState extends State<_PlayerRegistrationDialog> {
  final _form = GlobalKey<FormState>();
  final _entryId = TeamRegistrationRepository.newId();
  late final _name = TextEditingController(text: widget.player?.name);
  late final _jersey = TextEditingController(text: widget.player?.jersey);
  late final _height = TextEditingController(
    text: widget.player?.heightCm?.toString(),
  );
  late final _weight = TextEditingController(
    text: widget.player?.weightKg?.toString(),
  );
  late final _shorts = TextEditingController(text: widget.player?.shortsSize);
  late final _vest = TextEditingController(text: widget.player?.vestSize);
  late final _shoe = TextEditingController(text: widget.player?.shoeSize);
  late String? _position = widget.player?.position;
  _PlayerStep _step = _PlayerStep.essentials;
  RegistrationPlayer? _review;
  String? _operationId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _jersey,
      _height,
      _weight,
      _shorts,
      _vest,
      _shoe,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (!_form.currentState!.validate()) return;
    if (_step == _PlayerStep.essentials) {
      setState(() => _step = _PlayerStep.optional);
    } else {
      _showReview(includeOptional: true);
    }
  }

  void _showReview({required bool includeOptional}) {
    final prior = widget.player;
    String? optional(TextEditingController controller) {
      final text = controller.text.trim();
      return text.isEmpty ? null : text;
    }

    setState(() {
      _review = RegistrationPlayer(
        id: prior?.id ?? _entryId,
        name: _name.text.trim(),
        jersey: _jersey.text,
        position: includeOptional ? _position : prior?.position,
        heightCm: includeOptional
            ? num.tryParse(_height.text.trim())
            : prior?.heightCm,
        weightKg: includeOptional
            ? num.tryParse(_weight.text.trim())
            : prior?.weightKg,
        shortsSize: includeOptional ? optional(_shorts) : prior?.shortsSize,
        vestSize: includeOptional ? optional(_vest) : prior?.vestSize,
        shoeSize: includeOptional ? optional(_shoe) : prior?.shoeSize,
      );
      _operationId = TeamRegistrationRepository.newId();
      _step = _PlayerStep.review;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_review!, _operationId!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _registrationError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(switch (_step) {
        _PlayerStep.essentials =>
          widget.player == null ? 'Add player' : 'Edit player',
        _PlayerStep.optional => 'Optional details',
        _PlayerStep.review => 'Review player',
      }),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == _PlayerStep.essentials) ...[
                TextFormField(
                  controller: _name,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Player name'),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : 'Enter a player name',
                ),
                TextFormField(
                  controller: _jersey,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Jersey number'),
                  validator: (value) =>
                      value != null && value.isNotEmpty && value == value.trim()
                      ? null
                      : 'Enter the jersey number without outside spaces',
                ),
              ],
              if (_step == _PlayerStep.optional) ...[
                DropdownButtonFormField<String>(
                  initialValue: _position ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Playing position',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Choose a position'),
                    ),
                    DropdownMenuItem(value: 'Guard', child: Text('Guard')),
                    DropdownMenuItem(value: 'Forward', child: Text('Forward')),
                    DropdownMenuItem(value: 'Center', child: Text('Center')),
                  ],
                  onChanged: (value) =>
                      setState(() => _position = value == '' ? null : value),
                ),
                _measurement(_height, 'Height (cm)'),
                _measurement(_weight, 'Weight (kg)'),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Uniform sizes'),
                  children: [
                    for (final (label, controller) in [
                      ('Shorts size', _shorts),
                      ('Vest size', _vest),
                      ('Shoe size', _shoe),
                    ])
                      TextFormField(
                        controller: controller,
                        maxLength: 24,
                        decoration: InputDecoration(labelText: label),
                      ),
                  ],
                ),
              ],
              if (_step == _PlayerStep.review) ...[
                Text(
                  _review!.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(_review!.summary.join(' · ')),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  if (_step == _PlayerStep.essentials) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _step = _PlayerStep.essentials);
                  }
                },
          child: Text(_step == _PlayerStep.essentials ? 'Cancel' : 'Back'),
        ),
        if (_step == _PlayerStep.optional)
          TextButton(
            onPressed: () => _showReview(includeOptional: false),
            child: Text(widget.player == null ? 'Skip' : 'Keep saved details'),
          ),
        FilledButton(
          onPressed: _saving
              ? null
              : _step == _PlayerStep.review
              ? _save
              : _next,
          child: Text(
            _saving
                ? 'Saving…'
                : switch (_step) {
                    _PlayerStep.essentials => 'Continue',
                    _PlayerStep.optional => 'Review',
                    _PlayerStep.review => 'Save player',
                  },
          ),
        ),
      ],
    ),
  );

  Widget _measurement(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return null;
          final number = num.tryParse(text);
          return number != null &&
                  number.isFinite &&
                  number > 0 &&
                  number <= 999
              ? null
              : 'Enter a positive measurement';
        },
      );
}

String _registrationError(Object error) => error is FirebaseFunctionsException
    ? error.message ?? 'Team registration is unavailable.'
    : 'Team registration is unavailable. Try again.';
