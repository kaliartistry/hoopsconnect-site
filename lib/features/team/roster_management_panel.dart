import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/roster_workflow_model.dart';
import '../../models/team_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/roster_workflow_providers.dart';
import '../../providers/team_providers.dart';
import '../../services/repositories/roster_workflow_repository.dart';

class TeamRosterManagementPanel extends ConsumerWidget {
  const TeamRosterManagementPanel({
    super.key,
    required this.team,
    required this.seasonId,
    required this.legacyRoster,
  });

  final TeamModel team;
  final String? seasonId;
  final AsyncValue<List<PlayerSeasonStatsModel>> legacyRoster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final authority = user == null
        ? RosterClientAuthority.denied
        : rosterClientAuthority(user: user, teamId: team.id);
    final target = seasonId == null
        ? null
        : (teamId: team.id, seasonId: seasonId!);
    final workspace =
        target == null || authority == RosterClientAuthority.denied
        ? null
        : ref.watch(rosterWorkspaceProvider(target));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ROSTER',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (workspace?.valueOrNull case final RosterWorkspace value)
              TextButton.icon(
                onPressed: () => _openChangeDialog(
                  context,
                  ref,
                  user: user!,
                  target: target!,
                  workspace: value,
                ),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: Text(
                  authority == RosterClientAuthority.manage
                      ? 'Add player'
                      : 'Propose player',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (seasonId == null)
          const AppStateMessage(
            title: 'No active season',
            message: 'Activate a season before changing a roster.',
            tone: AppStateTone.warning,
            compact: true,
          )
        else if (user?.hasCapability('teams.represent') == true &&
            authority == RosterClientAuthority.denied)
          AppStateMessage(
            title: 'View only',
            message:
                'You can propose roster changes only for your assigned team (${user?.teamId ?? 'none assigned'}).',
            tone: AppStateTone.info,
            compact: true,
          )
        else if (workspace != null)
          workspace.when(
            data: (value) => _WorkspaceStatus(
              workspace: value,
              user: user!,
              target: target!,
            ),
            loading: () => const AppLoadingState(
              label: 'Loading roster controls',
              compact: true,
            ),
            error: (error, _) => AppStateMessage(
              title: 'Roster changes unavailable',
              message: _messageFor(error),
              tone: AppStateTone.warning,
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(rosterWorkspaceProvider(target!)),
              compact: true,
            ),
          ),
        const SizedBox(height: 10),
        _buildRosterProjection(
          ref: ref,
          legacyRoster: legacyRoster,
          workspace: workspace?.valueOrNull,
          user: user,
          authority: authority,
          target: target,
          teamId: team.id,
        ),
      ],
    );
  }

  Widget _buildRosterProjection({
    required WidgetRef ref,
    required AsyncValue<List<PlayerSeasonStatsModel>> legacyRoster,
    required RosterWorkspace? workspace,
    required UserModel? user,
    required RosterClientAuthority authority,
    required ({String teamId, String seasonId})? target,
    required String teamId,
  }) {
    final canonicalAvailable = workspace != null;
    return legacyRoster.when(
      data: (players) => _RosterList(
        players: players,
        workspace: workspace,
        user: user,
        authority: authority,
        target: target,
      ),
      loading: () => canonicalAvailable
          ? Column(
              children: [
                _RosterList(
                  players: const [],
                  workspace: workspace,
                  user: user,
                  authority: authority,
                  target: target,
                ),
                const AppLoadingState(
                  label: 'Loading season statistics',
                  compact: true,
                ),
              ],
            )
          : const AppLoadingState(label: 'Loading roster', compact: true),
      error: (error, _) => canonicalAvailable
          ? Column(
              children: [
                _RosterList(
                  players: const [],
                  workspace: workspace,
                  user: user,
                  authority: authority,
                  target: target,
                ),
                AppStateMessage(
                  title: 'Season statistics unavailable',
                  message:
                      'Canonical registrations are shown. Historical aggregates could not be loaded: ${ErrorMapper.map(error)}',
                  tone: AppStateTone.warning,
                  actionLabel: 'Retry statistics',
                  onAction: () => ref.invalidate(teamRosterProvider(teamId)),
                  compact: true,
                ),
              ],
            )
          : AppStateMessage(
              title: 'Roster could not be loaded',
              message: ErrorMapper.map(error),
              tone: AppStateTone.error,
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(teamRosterProvider(teamId)),
              compact: true,
            ),
    );
  }

  Future<void> _openChangeDialog(
    BuildContext context,
    WidgetRef ref, {
    required UserModel user,
    required ({String teamId, String seasonId}) target,
    required RosterWorkspace workspace,
  }) async {
    final receipt = await showDialog<RosterChangeReceipt>(
      context: context,
      builder: (_) => _RosterChangeDialog(
        user: user,
        target: target,
        rosterVersion: workspace.rosterVersion,
      ),
    );
    if (receipt == null || !context.mounted) return;
    _refresh(ref, target);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptMessage(receipt))));
  }
}

class _WorkspaceStatus extends ConsumerStatefulWidget {
  const _WorkspaceStatus({
    required this.workspace,
    required this.user,
    required this.target,
  });

  final RosterWorkspace workspace;
  final UserModel user;
  final ({String teamId, String seasonId}) target;

  @override
  ConsumerState<_WorkspaceStatus> createState() => _WorkspaceStatusState();
}

class _WorkspaceStatusState extends ConsumerState<_WorkspaceStatus> {
  final Set<String> _reviewing = {};
  final Map<String, String> _operationIds = {};

  @override
  Widget build(BuildContext context) {
    final canReview =
        rosterClientAuthority(
          user: widget.user,
          teamId: widget.target.teamId,
        ) ==
        RosterClientAuthority.manage;
    final pending = widget.workspace.proposals
        .where((proposal) => proposal.status == RosterApprovalStatus.pending)
        .toList(growable: false);
    if (pending.isEmpty) {
      return AppStateMessage(
        title: 'Roster controls ready',
        message: canReview
            ? 'Admin changes apply after server validation.'
            : 'Your changes are proposals until a roster administrator approves them.',
        tone: AppStateTone.info,
        compact: true,
      );
    }

    return Column(
      children: [
        AppStateMessage(
          title:
              '${pending.length} pending roster request${pending.length == 1 ? '' : 's'}',
          message: canReview
              ? 'Review each request. Approval applies it to the current roster version.'
              : 'An administrator must approve these requests before the roster changes.',
          tone: AppStateTone.warning,
          compact: true,
        ),
        const SizedBox(height: 8),
        ...pending.map(
          (proposal) => Card(
            child: ListTile(
              leading: const Icon(Icons.pending_actions_outlined),
              title: Text(_proposalLabel(proposal.kind)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Requested by ${proposal.requestedByName} • Pending admin approval',
                  ),
                  const SizedBox(height: 6),
                  if (proposal.before != null)
                    Text('Before: ${_formatFacts(proposal.before!)}'),
                  if (proposal.after != null)
                    Text('After: ${_formatFacts(proposal.after!)}'),
                  Text('Reason: ${proposal.reason}'),
                ],
              ),
              trailing: _reviewing.contains(proposal.proposalId)
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : canReview
                  ? Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: _reviewing.contains(proposal.proposalId)
                              ? null
                              : () => _review(
                                  context,
                                  ref,
                                  proposal: proposal,
                                  decision: RosterProposalDecision.reject,
                                ),
                          child: const Text('Reject'),
                        ),
                        FilledButton(
                          onPressed: _reviewing.contains(proposal.proposalId)
                              ? null
                              : () => _review(
                                  context,
                                  ref,
                                  proposal: proposal,
                                  decision: RosterProposalDecision.approve,
                                ),
                          child: const Text('Approve'),
                        ),
                      ],
                    )
                  : const Chip(label: Text('Pending')),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref, {
    required RosterProposalSummary proposal,
    required RosterProposalDecision decision,
  }) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          decision == RosterProposalDecision.approve
              ? 'Approve roster request?'
              : 'Reject roster request?',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (proposal.before != null)
                  Text('Before: ${_formatFacts(proposal.before!)}'),
                if (proposal.after != null)
                  Text('After: ${_formatFacts(proposal.after!)}'),
                const SizedBox(height: 8),
                Text('Requested reason: ${proposal.reason}'),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: decision == RosterProposalDecision.reject
                        ? 'Reason for rejection'
                        : 'Review note (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (decision == RosterProposalDecision.reject &&
                  noteController.text.trim().isEmpty) {
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: Text(
              decision == RosterProposalDecision.approve ? 'Approve' : 'Reject',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      noteController.dispose();
      return;
    }
    setState(() => _reviewing.add(proposal.proposalId));
    try {
      final repository = ref.read(rosterWorkflowRepositoryProvider);
      final reviewNote = noteController.text.trim();
      final semanticRetryKey =
          '${proposal.proposalId}|${decision.name}|$reviewNote';
      final operationId = _operationIds.putIfAbsent(
        semanticRetryKey,
        repository.newOperationId,
      );
      final receipt = await repository.reviewProposal(
        user: widget.user,
        request: RosterProposalReviewRequest(
          operationId: operationId,
          proposalId: proposal.proposalId,
          teamId: widget.target.teamId,
          seasonId: widget.target.seasonId,
          expectedRosterVersion: widget.workspace.rosterVersion,
          decision: decision,
          note: reviewNote.isEmpty ? null : reviewNote,
        ),
      );
      if (context.mounted) {
        _refresh(ref, widget.target);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_receiptMessage(receipt))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      noteController.dispose();
      if (mounted) setState(() => _reviewing.remove(proposal.proposalId));
    }
  }
}

class _RosterList extends ConsumerWidget {
  const _RosterList({
    required this.players,
    required this.workspace,
    required this.user,
    required this.authority,
    required this.target,
  });

  final List<PlayerSeasonStatsModel> players;
  final RosterWorkspace? workspace;
  final UserModel? user;
  final RosterClientAuthority authority;
  final ({String teamId, String seasonId})? target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registrations =
        workspace?.registrations ?? const <RosterRegistration>[];
    if ((workspace == null && players.isEmpty) ||
        (workspace != null && registrations.isEmpty)) {
      return const AppStateMessage(
        title: 'No registered players',
        message: 'This team does not have a roster for the active season yet.',
        icon: Icons.person_off_outlined,
      );
    }

    final registrationsByPlayer = {
      for (final registration in registrations)
        registration.playerId: registration,
    };
    final statsByPlayer = {
      for (final player in players) player.playerId: player,
    };
    final playerIds = workspace == null
        ? statsByPlayer.keys.toSet()
        : registrationsByPlayer.keys.toSet();
    final ordered =
        playerIds
            .map(
              (playerId) => (
                playerId: playerId,
                stats: statsByPlayer[playerId],
                registration: registrationsByPlayer[playerId],
              ),
            )
            .toList()
          ..sort(
            (a, b) => (a.registration?.displayName ?? a.stats?.playerName ?? '')
                .toLowerCase()
                .compareTo(
                  (b.registration?.displayName ?? b.stats?.playerName ?? '')
                      .toLowerCase(),
                ),
          );
    return Column(
      children: ordered
          .map((entry) {
            final player = entry.stats;
            final registration = entry.registration;
            final playerName =
                registration?.displayName ??
                player?.playerName ??
                'Player identity unavailable';
            final jersey = registration?.jerseyNumber ?? player?.jerseyNumber;
            final position = registration?.position ?? player?.position;
            final canChange =
                workspace != null &&
                user != null &&
                authority != RosterClientAuthority.denied &&
                registration != null;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(jersey ?? '—')),
                title: Text(
                  playerName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    if (position?.trim().isNotEmpty == true) position!,
                    if (player?.hasAggregateData == true)
                      '${player!.gamesPlayed} GP • ${player.ppg.toStringAsFixed(1)} PPG'
                    else
                      'Season stats not calculated',
                  ].join(' • '),
                ),
                onTap: () => context.push('/stats/player/${entry.playerId}'),
                trailing: canChange
                    ? PopupMenuButton<String>(
                        tooltip: 'Roster actions for $playerName',
                        onSelected: (action) {
                          if (action == 'edit') {
                            _edit(context, ref, registration);
                          } else if (action == 'remove') {
                            _remove(context, ref, registration);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit registration'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove from roster'),
                          ),
                        ],
                      )
                    : const Icon(Icons.chevron_right),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    RosterRegistration registration,
  ) async {
    final receipt = await showDialog<RosterChangeReceipt>(
      context: context,
      builder: (_) => _RosterChangeDialog(
        user: user!,
        target: target!,
        rosterVersion: workspace!.rosterVersion,
        player: registration,
      ),
    );
    if (receipt == null || !context.mounted) return;
    _refresh(ref, target!);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptMessage(receipt))));
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    RosterRegistration registration,
  ) async {
    final receipt = await showDialog<RosterChangeReceipt>(
      context: context,
      builder: (_) => _RosterChangeDialog(
        user: user!,
        target: target!,
        rosterVersion: workspace!.rosterVersion,
        player: registration,
        removing: true,
      ),
    );
    if (receipt == null || !context.mounted) return;
    _refresh(ref, target!);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptMessage(receipt))));
  }
}

class _RosterChangeDialog extends ConsumerStatefulWidget {
  const _RosterChangeDialog({
    required this.user,
    required this.target,
    required this.rosterVersion,
    this.player,
    this.removing = false,
  }) : assert(!removing || player != null);

  final UserModel user;
  final ({String teamId, String seasonId}) target;
  final int rosterVersion;
  final RosterRegistration? player;
  final bool removing;

  @override
  ConsumerState<_RosterChangeDialog> createState() =>
      _RosterChangeDialogState();
}

class _RosterChangeDialogState extends ConsumerState<_RosterChangeDialog> {
  static const _apparelSizes = ['XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _jerseyController;
  late final TextEditingController _positionController;
  late final TextEditingController _reasonController;
  late final TextEditingController _shortsController;
  late final TextEditingController _vestController;
  late final TextEditingController _shoeController;
  late final String _operationId;
  RosterChangeRequest? _reviewRequest;
  bool _attempted = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player?.displayName);
    _jerseyController = TextEditingController(
      text: widget.player?.jerseyNumber,
    );
    _positionController = TextEditingController(text: widget.player?.position);
    final sizes = widget.player?.uniformSizes;
    _shortsController = TextEditingController(text: sizes?.shorts);
    _vestController = TextEditingController(text: sizes?.vest);
    _shoeController = TextEditingController(text: sizes?.shoe);
    _reasonController = TextEditingController(
      text: widget.removing
          ? ''
          : widget.player == null
          ? 'New registration'
          : 'Registration update',
    );
    _operationId = ref.read(rosterWorkflowRepositoryProvider).newOperationId();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyController.dispose();
    _positionController.dispose();
    _reasonController.dispose();
    _shortsController.dispose();
    _vestController.dispose();
    _shoeController.dispose();
    super.dispose();
  }

  void _review() {
    if (!_formKey.currentState!.validate()) return;
    final sizes = RosterUniformSizes(
      shorts: _shortsController.text,
      vest: _vestController.text,
      shoe: _shoeController.text,
    );
    final hasSizes =
        sizes.toMap().isNotEmpty ||
        widget.player?.uniformSizes?.toMap().isNotEmpty == true;
    setState(() {
      _reviewRequest = RosterChangeRequest(
        operationId: _operationId,
        teamId: widget.target.teamId,
        seasonId: widget.target.seasonId,
        expectedRosterVersion: widget.rosterVersion,
        kind: widget.removing
            ? RosterChangeKind.removePlayer
            : widget.player == null
            ? RosterChangeKind.addPlayer
            : RosterChangeKind.updatePlayer,
        playerId: widget.player?.playerId,
        registrationId: widget.player?.registrationId,
        displayName: widget.removing ? null : _nameController.text.trim(),
        jerseyNumber: widget.removing ? null : _jerseyController.text,
        position: widget.removing ? null : _positionController.text.trim(),
        uniformSizes: !widget.removing && hasSizes ? sizes : null,
        reason: _reasonController.text.trim(),
      );
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final request = _reviewRequest!;
    setState(() {
      _saving = true;
      _attempted = true;
      _error = null;
    });
    try {
      final receipt = await ref
          .read(rosterWorkflowRepositoryProvider)
          .submitChange(user: widget.user, request: request);
      if (mounted) Navigator.of(context).pop(receipt);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposes =
        rosterClientAuthority(
          user: widget.user,
          teamId: widget.target.teamId,
        ) ==
        RosterClientAuthority.propose;
    final review = _reviewRequest;
    return AlertDialog(
      title: Text(
        review != null
            ? 'Review roster change'
            : widget.removing
            ? 'Remove ${widget.player!.displayName}?'
            : widget.player == null
            ? 'Add roster player'
            : 'Edit registration',
      ),
      content: AppFormFocusGroup(
        onCancel: () => Navigator.of(context).pop(),
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (proposes) ...[
                    const AppStateMessage(
                      title: 'Admin approval required',
                      message:
                          'Submitting this form creates a pending proposal. It does not change the roster yet.',
                      tone: AppStateTone.info,
                      compact: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (review != null) ...[
                    Text(
                      widget.removing
                          ? 'Remove ${widget.player!.displayName}'
                          : review.displayName!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (!widget.removing) ...[
                      Text('Jersey number: ${review.jerseyNumber}'),
                      if (review.position?.isNotEmpty == true)
                        Text('Position: ${review.position}'),
                      Text(
                        _uniformSizeSummary(review.uniformSizes) ??
                            'Uniform sizes: Not provided',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('Reason: ${review.reason}'),
                  ] else ...[
                    if (widget.removing)
                      const AppStateMessage(
                        title: 'Historical records are preserved',
                        message:
                            'This changes the current roster registration only. Approved game and season statistics remain.',
                        tone: AppStateTone.warning,
                        compact: true,
                      )
                    else ...[
                      TextFormField(
                        controller: _nameController,
                        autofocus: true,
                        readOnly: widget.player != null,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Player name',
                        ),
                        validator: (value) =>
                            _required(value) ??
                            (value!.trim().length > 120
                                ? 'Use up to 120 characters'
                                : null),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _jerseyController,
                        decoration: const InputDecoration(
                          labelText: 'Jersey number',
                          helperText:
                              'Stored as entered, so 0 and 00 remain different.',
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) return 'Enter a jersey number';
                          if (text.trim() != text ||
                              text.length > 8 ||
                              RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
                            return 'Use 1-8 characters without outside spaces';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _positionController,
                        decoration: const InputDecoration(
                          labelText: 'Position (optional)',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) > 40
                            ? 'Use up to 40 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _sizeField(
                        _shortsController,
                        'Shorts size',
                        apparel: true,
                      ),
                      const SizedBox(height: 12),
                      _sizeField(_vestController, 'Vest size', apparel: true),
                      const SizedBox(height: 12),
                      _sizeField(
                        _shoeController,
                        'Shoe size',
                        hint: 'e.g. US 10.5',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      maxLines: 2,
                      validator: (value) =>
                          _required(value) ??
                          (value!.trim().length > 500
                              ? 'Use up to 500 characters'
                              : null),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    AppStateMessage(
                      title: 'Roster change could not be confirmed',
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
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (review != null && !_attempted)
          TextButton(
            onPressed: () => setState(() => _reviewRequest = null),
            child: const Text('Edit'),
          ),
        AppAsyncActionButton(
          label: review == null
              ? 'Review'
              : proposes
              ? 'Submit proposal'
              : widget.removing
              ? 'Remove player'
              : 'Save roster change',
          busyLabel: 'Submitting roster change',
          isBusy: _saving,
          onPressed: review == null ? _review : _submit,
        ),
      ],
    );
  }

  Widget _sizeField(
    TextEditingController controller,
    String label, {
    bool apparel = false,
    String? hint,
  }) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.characters,
    decoration: InputDecoration(
      labelText: '$label (optional)',
      hintText: hint,
      suffixIcon: apparel
          ? PopupMenuButton<String>(
              tooltip: 'Choose $label',
              onSelected: (value) => controller.text = value,
              itemBuilder: (context) => [
                for (final size in _apparelSizes)
                  PopupMenuItem(value: size, child: Text(size)),
              ],
            )
          : null,
    ),
    validator: (value) => RosterUniformSizes.isValid(value ?? '')
        ? null
        : 'Use up to 24 characters without line breaks',
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;
}

void _refresh(WidgetRef ref, ({String teamId, String seasonId}) target) {
  ref.invalidate(rosterWorkspaceProvider(target));
  ref.invalidate(teamRosterProvider(target.teamId));
}

String _proposalLabel(RosterChangeKind kind) => switch (kind) {
  RosterChangeKind.addPlayer => 'Add player',
  RosterChangeKind.updatePlayer => 'Update registration',
  RosterChangeKind.removePlayer => 'Remove player',
};

String _formatFacts(RosterPlayerFacts facts) => [
  facts.displayName,
  '#${facts.jerseyNumber}',
  ?facts.position,
  if (facts.uniformSizes != null)
    _uniformSizeSummary(facts.uniformSizes) ?? 'Uniform sizes: None',
].join(' • ');

String? _uniformSizeSummary(RosterUniformSizes? sizes) {
  final values = sizes?.toMap() ?? const <String, String>{};
  if (values.isEmpty) return null;
  return [
    if (values['shorts'] case final value?) 'Shorts: $value',
    if (values['vest'] case final value?) 'Vest: $value',
    if (values['shoe'] case final value?) 'Shoe: $value',
  ].join(' • ');
}

String _receiptMessage(RosterChangeReceipt receipt) => switch (receipt.status) {
  RosterApprovalStatus.pending =>
    'Proposal submitted. The roster will not change until an administrator approves it.',
  RosterApprovalStatus.approved => 'Roster change approved and applied.',
  RosterApprovalStatus.rejected => 'Roster request rejected.',
};

String _messageFor(Object error) =>
    error is RosterWorkflowException ? error.message : ErrorMapper.map(error);
