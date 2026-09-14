import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_state_message.dart';
import '../../models/association_branding_model.dart';
import '../../models/division_model.dart';
import '../../models/league_catalog_model.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';

class LeagueManagementScreen extends ConsumerWidget {
  const LeagueManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(leagueCatalogProvider);
    final divisions = ref.watch(activeDivisionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Leagues & Sponsors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editLeague(context, ref, null, divisions),
        icon: const Icon(Icons.add),
        label: const Text('Add league'),
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: AppStateMessage(
            title: 'Leagues could not be loaded',
            message: '$error',
            tone: AppStateTone.error,
          ),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const AppStateMessage(
              title: 'Set up a league in 3 steps',
              message:
                  '1. Create the divisions you need.\n2. Add a league.\n3. Assign its divisions, colors, and optional title sponsor.\n\nAssociation-wide branding and the mega sponsor are managed separately.',
              icon: Icons.account_tree_outlined,
              compact: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/admin/divisions'),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Manage divisions'),
                ),
                Text(
                  '${value.leagues.length} of ${LeagueCatalogModel.maxLeagues} leagues configured',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (value.leagues.isEmpty)
              const AppStateMessage(
                title: 'No leagues configured',
                message:
                    'No leagues are created automatically. Use Add league to create the competitions this association actually operates.',
                icon: Icons.sports_basketball_outlined,
              )
            else
              for (final league in value.leagues) ...[
                _LeagueCard(
                  league: league,
                  divisions: divisions,
                  onEdit: () => _editLeague(context, ref, league, divisions),
                  onDelete: () => _deleteLeague(context, ref, league, value),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLeague(
    BuildContext context,
    WidgetRef ref,
    LeagueProfileModel league,
    LeagueCatalogModel catalog,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${league.name}?'),
        content: const Text(
          'This removes the league grouping and branding. It does not delete its divisions, teams, games, or scores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove league'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _save(
      context,
      ref,
      LeagueCatalogModel(
        leagues: catalog.leagues
            .where((candidate) => candidate.id != league.id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editLeague(
    BuildContext context,
    WidgetRef ref,
    LeagueProfileModel? existing,
    List<DivisionModel> divisions,
  ) async {
    final currentCatalog =
        ref.read(leagueCatalogProvider).valueOrNull ??
        const LeagueCatalogModel();
    if (existing == null &&
        currentCatalog.leagues.length >= LeagueCatalogModel.maxLeagues) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This association has reached the 100-league catalog limit.',
          ),
        ),
      );
      return;
    }
    final assignedLeagueByDivision = <String, String>{
      for (final league in currentCatalog.leagues)
        if (league.id != existing?.id)
          for (final divisionId in league.divisionIds) divisionId: league.name,
    };
    final name = TextEditingController(text: existing?.name);
    final shortName = TextEditingController(text: existing?.shortName);
    final description = TextEditingController(text: existing?.description);
    final sponsorName = TextEditingController(text: existing?.sponsor.name);
    final sponsorLabel = TextEditingController(
      text: existing?.sponsor.label ?? 'Title sponsor',
    );
    final primaryColor = TextEditingController(
      text: existing?.primaryColorHex ?? '#2E7D32',
    );
    final selectedDivisions = <String>{...existing?.divisionIds ?? const []};
    var sponsorEnabled = existing?.sponsor.enabled ?? false;
    final saved = await showDialog<LeagueProfileModel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add league' : 'Edit league'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'League name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: shortName,
                    decoration: const InputDecoration(labelText: 'Short name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: primaryColor,
                    decoration: const InputDecoration(
                      labelText: 'Primary color',
                      hintText: '#2E7D32',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Divisions',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final division in divisions)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(division.name),
                      subtitle: assignedLeagueByDivision[division.id] == null
                          ? null
                          : Text(
                              'Already assigned to ${assignedLeagueByDivision[division.id]}',
                            ),
                      value: selectedDivisions.contains(division.id),
                      onChanged: assignedLeagueByDivision[division.id] != null
                          ? null
                          : (selected) => setDialogState(() {
                              if (selected == true) {
                                selectedDivisions.add(division.id);
                              } else {
                                selectedDivisions.remove(division.id);
                              }
                            }),
                    ),
                  if (divisions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No active divisions are available. Create divisions first, then return here to assign them.',
                      ),
                    ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show a league title sponsor'),
                    value: sponsorEnabled,
                    onChanged: (value) =>
                        setDialogState(() => sponsorEnabled = value),
                  ),
                  if (sponsorEnabled) ...[
                    TextField(
                      controller: sponsorName,
                      decoration: const InputDecoration(
                        labelText: 'Sponsor name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sponsorLabel,
                      decoration: const InputDecoration(
                        labelText: 'Sponsor label',
                        hintText: 'Title sponsor',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmedName = name.text.trim();
                final color = primaryColor.text.trim();
                if (trimmedName.isEmpty ||
                    !AssociationBrandingModel.isValidColorHex(color) ||
                    (sponsorEnabled && sponsorName.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Add a league name, valid color, and sponsor name when enabled.',
                      ),
                    ),
                  );
                  return;
                }
                final id =
                    existing?.id ?? LeagueProfileModel.stableId(trimmedName);
                if (id.isEmpty) return;
                final duplicate = currentCatalog.leagues.any(
                  (league) => league.id == id && league.id != existing?.id,
                );
                if (duplicate) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'A league with this name already exists. Edit that league or use a different name.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  LeagueProfileModel(
                    id: id,
                    name: trimmedName,
                    shortName: shortName.text.trim().isEmpty
                        ? trimmedName
                        : shortName.text.trim(),
                    description: description.text.trim().isEmpty
                        ? null
                        : description.text.trim(),
                    divisionIds: selectedDivisions.toList(growable: false),
                    primaryColorHex: color,
                    secondaryColorHex: existing?.secondaryColorHex ?? '#1B5E20',
                    accentColorHex: existing?.accentColorHex ?? '#F9A825',
                    sponsor: SponsorBrandingModel(
                      enabled: sponsorEnabled,
                      name: sponsorName.text.trim(),
                      label: sponsorLabel.text.trim().isEmpty
                          ? 'Title sponsor'
                          : sponsorLabel.text.trim(),
                    ),
                    sortOrder: existing?.sortOrder ?? 0,
                  ),
                );
              },
              child: const Text('Save league'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    shortName.dispose();
    description.dispose();
    sponsorName.dispose();
    sponsorLabel.dispose();
    primaryColor.dispose();
    if (saved == null || !context.mounted) return;
    final current =
        ref.read(leagueCatalogProvider).valueOrNull ??
        const LeagueCatalogModel();
    final retained =
        current.leagues
            .where((league) => league.id != saved.id)
            .toList(growable: true)
          ..add(saved);
    await _save(context, ref, LeagueCatalogModel(leagues: retained));
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    LeagueCatalogModel catalog,
  ) async {
    try {
      final associationId = ref.read(currentAssociationIdProvider);
      if (associationId == null) throw StateError('No active association.');
      await ref
          .read(associationRepositoryProvider)
          .saveLeagueCatalog(associationId: associationId, catalog: catalog);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('League catalog saved.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('League catalog was not saved: $error')),
        );
      }
    }
  }
}

class _LeagueCard extends StatelessWidget {
  const _LeagueCard({
    required this.league,
    required this.divisions,
    required this.onEdit,
    required this.onDelete,
  });

  final LeagueProfileModel league;
  final List<DivisionModel> divisions;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final names = divisions
        .where((division) => league.divisionIds.contains(division.id))
        .map((division) => division.name)
        .join(', ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        leading: CircleAvatar(
          backgroundColor: AssociationBrandingModel.colorFromHex(
            league.primaryColorHex,
          ),
          foregroundColor: Colors.white,
          child: Text(league.shortName.characters.first.toUpperCase()),
        ),
        title: Text(league.name),
        subtitle: Text(
          '${names.isEmpty ? 'No divisions assigned' : names}\n${league.sponsor.isActive ? '${league.sponsor.label}: ${league.sponsor.name}' : 'No league sponsor shown'}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
