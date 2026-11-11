import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_constrained_content.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/division_model.dart';
import '../../models/league_catalog_model.dart';
import '../../models/team_model.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/team_providers.dart';

String _divisionLabel(DivisionModel division, LeagueCatalogModel? catalog) {
  final league = catalog?.leagues
      .where(
        (league) => division.leagueId == null
            ? league.divisionIds.contains(division.id)
            : league.id == division.leagueId,
      )
      .firstOrNull;
  if (league == null || league.name == division.name) return division.name;
  return '${league.name} · ${division.name}';
}

class TeamListScreen extends ConsumerWidget {
  const TeamListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsStreamProvider);
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final seasonAsync = ref.watch(activeSeasonIdProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final canManage = currentUser?.hasCapability('teams.manage') ?? false;
    final catalog = ref.watch(leagueCatalogProvider).valueOrNull;
    final divisionNames = {
      for (final division
          in divisionsAsync.valueOrNull ?? const <DivisionModel>[])
        division.id: _divisionLabel(division, catalog),
    };

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Teams & Rosters'),
      ),
      body: teamsAsync.when(
        data: (teams) {
          if (teams.isEmpty) {
            return AppConstrainedContent(
              child: AppStateMessage(
                title: 'No teams yet',
                message: canManage
                    ? 'Create the first team for the active season.'
                    : 'Teams will appear after a league administrator creates them.',
                icon: Icons.groups_outlined,
                actionLabel: canManage && seasonAsync.valueOrNull != null
                    ? 'Create team'
                    : null,
                onAction: canManage && seasonAsync.valueOrNull != null
                    ? () => _openTeamEditor(
                        context,
                        ref,
                        teams: teams,
                        seasonId: seasonAsync.valueOrNull!,
                      )
                    : null,
              ),
            );
          }

          final ordered = [...teams]
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              final team = ordered[index];
              final divisionName = divisionNames[team.divisionId];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: team.logoUrl == null
                      ? const CircleAvatar(child: Icon(Icons.groups))
                      : SponsorLogo(
                          reference: team.logoUrl!,
                          semanticLabel: '${team.name} logo',
                          width: 44,
                          height: 44,
                        ),
                  title: Text(
                    team.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${divisionName ?? 'Division unavailable (${team.divisionId})'} • Season ${team.seasonId}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${team.repIds.length} rep${team.repIds.length == 1 ? '' : 's'}',
                      ),
                      if (canManage)
                        IconButton(
                          tooltip: 'Edit ${team.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openTeamEditor(
                            context,
                            ref,
                            teams: teams,
                            seasonId: team.seasonId,
                            existing: team,
                          ),
                        )
                      else
                        const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => context.push('/team/${team.id}'),
                ),
              );
            },
          );
        },
        loading: () =>
            const Center(child: AppLoadingState(label: 'Loading teams')),
        error: (error, _) => AppConstrainedContent(
          child: AppStateMessage(
            title: 'Teams could not be loaded',
            message: ErrorMapper.map(error),
            tone: AppStateTone.error,
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(teamsStreamProvider),
          ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: seasonAsync.valueOrNull == null
                  ? null
                  : () => _openTeamEditor(
                      context,
                      ref,
                      teams: teamsAsync.valueOrNull ?? const [],
                      seasonId: seasonAsync.valueOrNull!,
                    ),
              tooltip: seasonAsync.valueOrNull == null
                  ? 'Activate a season before creating a team'
                  : 'Create team',
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('New team'),
            )
          : null,
    );
  }

  Future<void> _openTeamEditor(
    BuildContext context,
    WidgetRef ref, {
    required List<TeamModel> teams,
    required String seasonId,
    TeamModel? existing,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TeamEditorDialog(
        teams: teams,
        seasonId: seasonId,
        existing: existing,
      ),
    );
  }
}

class _TeamEditorDialog extends ConsumerStatefulWidget {
  const _TeamEditorDialog({
    required this.teams,
    required this.seasonId,
    this.existing,
  });

  final List<TeamModel> teams;
  final String seasonId;
  final TeamModel? existing;

  @override
  ConsumerState<_TeamEditorDialog> createState() => _TeamEditorDialogState();
}

class _TeamEditorDialogState extends ConsumerState<_TeamEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _divisionId;
  Uint8List? _selectedLogoBytes;
  String? _selectedLogoName;
  String? _createdTeamId;
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name);
    _divisionId = widget.existing?.divisionId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _chooseLogo() async {
    const images = XTypeGroup(
      label: 'Team logo',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
      uniformTypeIdentifiers: [
        'public.png',
        'public.jpeg',
        'org.webmproject.webp',
      ],
      webWildCards: ['image/*'],
    );
    final file = await openFile(acceptedTypeGroups: const [images]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes > 2 * 1024 * 1024) {
      if (mounted) {
        setState(() {
          _formError = 'Choose a PNG, JPG, or WebP logo smaller than 2 MB.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _selectedLogoBytes = bytes;
        _selectedLogoName = file.name;
        _formError = null;
      });
    }
  }

  Future<void> _reviewAndSave(
    List<DivisionModel> divisions,
    String? divisionId,
  ) async {
    if (_saving || !_formKey.currentState!.validate() || divisionId == null) {
      return;
    }
    final division = divisions.firstWhere(
      (division) => division.id == divisionId,
    );
    final catalog = ref.read(leagueCatalogProvider).valueOrNull;
    final name = _nameController.text.trim();
    final conflicts = teamNameConflicts(
      teams: widget.teams,
      candidateName: name,
      seasonId: widget.seasonId,
      excludingTeamId: widget.existing?.id ?? _createdTeamId,
    );
    if (conflicts.isNotEmpty) {
      final divisionNames = {
        for (final division
            in ref.read(divisionsStreamProvider).valueOrNull ??
                const <DivisionModel>[])
          division.id: _divisionLabel(division, catalog),
      };
      final conflict = conflicts.first;
      setState(() {
        _formError =
            'A team named ${conflict.name} already exists in ${divisionNames[conflict.divisionId] ?? 'this season'}. Edit that team or use a distinct official name.';
      });
      return;
    }

    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) {
      setState(() => _formError = 'Your association could not be confirmed.');
      return;
    }
    final logoBytes = _selectedLogoBytes;
    final logoName = _selectedLogoName;
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Review team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            Text(_divisionLabel(division, catalog)),
            Text(
              logoName != null
                  ? 'Logo: $logoName'
                  : widget.existing?.logoUrl == null
                  ? 'No logo selected'
                  : 'Current team logo',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Edit details'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              widget.existing == null ? 'Create team' : 'Save changes',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (ref.read(currentAssociationIdProvider) != assocId) {
      setState(
        () => _formError = 'Your association changed. Review the team again.',
      );
      return;
    }
    await _save(
      assocId: assocId,
      name: name,
      divisionId: divisionId,
      logoBytes: logoBytes,
      logoName: logoName,
    );
  }

  Future<void> _save({
    required String assocId,
    required String name,
    required String divisionId,
    required Uint8List? logoBytes,
    required String? logoName,
  }) async {
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final repository = ref.read(teamRepositoryProvider);
      var teamId = widget.existing?.id ?? _createdTeamId;
      if (teamId == null) {
        teamId = await repository.createTeam(
          assocId,
          TeamModel(
            id: '',
            name: name,
            divisionId: divisionId,
            seasonId: widget.seasonId,
          ),
        );
        _createdTeamId = teamId;
      }
      var logoUrl = widget.existing?.logoUrl;
      if (logoBytes != null && logoName != null) {
        logoUrl = await ref
            .read(teamLogoStorageProvider)
            .upload(
              associationId: assocId,
              teamId: teamId,
              bytes: logoBytes,
              fileName: logoName,
            );
      }
      await repository.updateTeamIdentity(
        assocId: assocId,
        teamId: teamId,
        name: name,
        divisionId: divisionId,
        logoUrl: logoUrl,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = ErrorMapper.map(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(leagueCatalogProvider).valueOrNull;
    final allDivisions =
        ref.watch(divisionsStreamProvider).valueOrNull ??
        const <DivisionModel>[];
    final divisions = allDivisions
        .where(
          (division) =>
              !division.isArchived ||
              division.id == widget.existing?.divisionId,
        )
        .toList(growable: false);
    final divisionId = divisions.any((division) => division.id == _divisionId)
        ? _divisionId
        : divisions.length == 1
        ? divisions.single.id
        : null;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.existing == null ? 'Create team' : 'Edit team'),
      content: AppFormFocusGroup(
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        child: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Official team name',
                    hintText: 'e.g. Kingston Lions',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the official team name'
                      : null,
                  onChanged: (_) {
                    if (_formError != null) setState(() => _formError = null);
                  },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Team logo',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: _selectedLogoBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.memory(
                                _selectedLogoBytes!,
                                width: 70,
                                height: 70,
                                fit: BoxFit.contain,
                              ),
                            )
                          : widget.existing?.logoUrl != null
                          ? SponsorLogo(
                              reference: widget.existing!.logoUrl!,
                              semanticLabel: '${widget.existing!.name} logo',
                              width: 70,
                              height: 70,
                            )
                          : const Icon(Icons.shield_outlined, size: 34),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('choose-team-logo'),
                            onPressed: _saving ? null : _chooseLogo,
                            icon: const Icon(Icons.upload_outlined),
                            label: Text(
                              _selectedLogoBytes == null
                                  ? 'Choose logo'
                                  : 'Choose another',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedLogoName ??
                                'PNG, JPG, or WebP. Maximum 2 MB.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: divisionId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'League and division',
                  ),
                  items: divisions.map((division) {
                    final label = _divisionLabel(division, catalog);
                    return DropdownMenuItem(
                      value: division.id,
                      child: Text(
                        division.isArchived ? '$label (Archived)' : label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _divisionId = value),
                  validator: (value) =>
                      value == null ? 'Choose an active division' : null,
                ),
                if (divisions.isEmpty) ...[
                  const SizedBox(height: 12),
                  const AppStateMessage(
                    title: 'No active division',
                    message:
                        'Create or restore a division before saving this team.',
                    tone: AppStateTone.warning,
                    compact: true,
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 12),
                  AppStateMessage(
                    title: 'Team not saved',
                    message: _formError!,
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
          label: 'Review team',
          busyLabel: 'Saving team',
          isBusy: _saving,
          disabledHint: divisions.isEmpty
              ? 'Create or restore an active division first'
              : null,
          onPressed: divisions.isEmpty
              ? null
              : () => _reviewAndSave(divisions, divisionId),
        ),
      ],
    );
  }
}
