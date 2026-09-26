import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/association_branding_model.dart';
import '../../models/division_model.dart';
import '../../models/league_catalog_model.dart';
import '../../platform/qa_environment.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';

class LeagueManagementScreen extends ConsumerWidget {
  const LeagueManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(leagueCatalogProvider);
    final divisions = ref.watch(activeDivisionsProvider);
    final compact = MediaQuery.sizeOf(context).width < 700;
    void addLeague() => _editLeague(context, ref, null);

    return Scaffold(
      appBar: AppBar(title: const Text('Leagues & Sponsors')),
      floatingActionButton: compact
          ? null
          : FloatingActionButton.extended(
              onPressed: addLeague,
              icon: const Icon(Icons.add),
              label: const Text('Add league'),
            ),
      bottomNavigationBar: compact
          ? SafeArea(
              minimum: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                QaEnvironment.enabled ? 48 : 12,
              ),
              child: FilledButton.icon(
                key: const Key('add-league-mobile-button'),
                onPressed: addLeague,
                icon: const Icon(Icons.add),
                label: const Text('Add league'),
              ),
            )
          : null,
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
          padding: EdgeInsets.fromLTRB(16, 16, 16, compact ? 24 : 96),
          children: [
            const AppStateMessage(
              title: 'Set up the league hierarchy in 3 steps',
              message:
                  '1. Create the parent league.\n2. Add divisions beneath that league.\n3. Add its colors and optional title sponsor.\n\nA division can belong to only one league. Association-wide branding and the mega sponsor are managed separately.',
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
                  label: const Text('View league hierarchy'),
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
                  onEdit: () => _editLeague(context, ref, league),
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
    if (league.divisionIds.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${league.name} still owns divisions'),
          content: Text(
            'A parent league cannot be removed while ${league.divisionIds.length} ${league.divisionIds.length == 1 ? 'division is' : 'divisions are'} beneath it. Permanently delete those child divisions first.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${league.name}?'),
        content: const Text(
          'This removes the empty league grouping and its branding.',
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
    final name = TextEditingController(text: existing?.name);
    final shortName = TextEditingController(text: existing?.shortName);
    final description = TextEditingController(text: existing?.description);
    final sponsorName = TextEditingController(text: existing?.sponsor.name);
    final sponsorLabel = TextEditingController(
      text: existing?.sponsor.label ?? 'Title sponsor',
    );
    final sponsorLogoUrl = TextEditingController(
      text: existing?.sponsor.logoUrl,
    );
    final sponsorWebsiteUrl = TextEditingController(
      text: existing?.sponsor.websiteUrl,
    );
    final primaryColor = TextEditingController(
      text: existing?.primaryColorHex ?? '#2E7D32',
    );
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
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_tree_outlined),
                      title: Text(
                        existing == null
                            ? 'Divisions come after the league'
                            : '${existing.divisionIds.length} ${existing.divisionIds.length == 1 ? 'division' : 'divisions'} beneath this league',
                      ),
                      subtitle: Text(
                        existing == null
                            ? 'Save the parent league, then open the league hierarchy to add Division A, Premier, Community League, or any other child division.'
                            : 'Use View league hierarchy to add or manage child divisions. Divisions cannot be assigned at the association level.',
                      ),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: sponsorLogoUrl,
                      decoration: const InputDecoration(
                        labelText: 'Sponsor logo (HTTPS URL or bundled asset)',
                        hintText: 'https://… or asset:assets/images/…',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (sponsorLogoUrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _SponsorLogoPreview(
                        name: sponsorName.text.trim().isEmpty
                            ? 'Sponsor'
                            : sponsorName.text.trim(),
                        reference: sponsorLogoUrl.text.trim(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: sponsorWebsiteUrl,
                      decoration: const InputDecoration(
                        labelText: 'Sponsor website (optional)',
                        hintText: 'https://…',
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
                    (sponsorEnabled && sponsorName.text.trim().isEmpty) ||
                    !_validImageReferenceOrEmpty(sponsorLogoUrl.text) ||
                    !_validHttpsOrEmpty(sponsorWebsiteUrl.text)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Add a league name, valid color, sponsor name when enabled, and valid logo or website references.',
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
                    divisionIds: existing?.divisionIds ?? const [],
                    primaryColorHex: color,
                    secondaryColorHex: existing?.secondaryColorHex ?? '#1B5E20',
                    accentColorHex: existing?.accentColorHex ?? '#F9A825',
                    sponsor: SponsorBrandingModel(
                      enabled: sponsorEnabled,
                      name: sponsorName.text.trim(),
                      label: sponsorLabel.text.trim().isEmpty
                          ? 'Title sponsor'
                          : sponsorLabel.text.trim(),
                      logoUrl: sponsorLogoUrl.text.trim().isEmpty
                          ? null
                          : sponsorLogoUrl.text.trim(),
                      websiteUrl: sponsorWebsiteUrl.text.trim().isEmpty
                          ? null
                          : sponsorWebsiteUrl.text.trim(),
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
    sponsorLogoUrl.dispose();
    sponsorWebsiteUrl.dispose();
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(names.isEmpty ? 'No divisions assigned' : names),
            const SizedBox(height: 5),
            if (league.sponsor.isActive)
              Row(
                children: [
                  if (league.sponsor.logoUrl != null) ...[
                    SponsorLogo(
                      reference: league.sponsor.logoUrl!,
                      semanticLabel: '${league.sponsor.name} logo',
                      width: 72,
                      height: 32,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      'TITLE SPONSOR · ${league.sponsor.name}',
                      maxLines: 2,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              )
            else
              const Text('No league sponsor shown'),
          ],
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

class _SponsorLogoPreview extends StatelessWidget {
  const _SponsorLogoPreview({required this.name, required this.reference});

  final String name;
  final String reference;

  @override
  Widget build(BuildContext context) {
    if (!_validImageReferenceOrEmpty(reference)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Use a complete HTTPS URL or a bundled asset reference.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          SponsorLogo(
            reference: reference,
            semanticLabel: '$name logo preview',
            width: 112,
            height: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PUBLIC HEADER PREVIEW',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(name.isEmpty ? 'Sponsor name' : name),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _validHttpsOrEmpty(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  final uri = Uri.tryParse(trimmed);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

bool _validImageReferenceOrEmpty(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  if (_validHttpsOrEmpty(trimmed)) return true;
  if (!trimmed.startsWith('asset:assets/images/')) return false;
  final path = trimmed.substring('asset:'.length);
  return !path.contains('..') &&
      RegExp(r'^assets/images/[A-Za-z0-9._/-]+$').hasMatch(path);
}
