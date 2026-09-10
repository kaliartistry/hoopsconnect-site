import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/association_branding_model.dart';
import '../../providers/association_branding_providers.dart';

class AssociationBrandingScreen extends ConsumerStatefulWidget {
  const AssociationBrandingScreen({super.key});

  @override
  ConsumerState<AssociationBrandingScreen> createState() =>
      _AssociationBrandingScreenState();
}

class _AssociationBrandingScreenState
    extends ConsumerState<AssociationBrandingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _leagueName = TextEditingController();
  final _shortName = TextEditingController();
  final _leagueLogoUrl = TextEditingController();
  final _primaryColor = TextEditingController();
  final _secondaryColor = TextEditingController();
  final _accentColor = TextEditingController();
  final _sponsorName = TextEditingController();
  final _sponsorLabel = TextEditingController();
  final _sponsorLogoUrl = TextEditingController();
  final _sponsorWebsiteUrl = TextEditingController();

  String? _loadedAssociationId;
  bool _sponsorEnabled = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _leagueName,
      _shortName,
      _leagueLogoUrl,
      _primaryColor,
      _secondaryColor,
      _accentColor,
      _sponsorName,
      _sponsorLabel,
      _sponsorLogoUrl,
      _sponsorWebsiteUrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(AssociationBrandingModel branding) {
    if (_loadedAssociationId == branding.associationId) return;
    _loadedAssociationId = branding.associationId;
    _leagueName.text = branding.leagueName;
    _shortName.text = branding.shortName;
    _leagueLogoUrl.text = branding.logoUrl ?? '';
    _primaryColor.text = branding.primaryColorHex;
    _secondaryColor.text = branding.secondaryColorHex;
    _accentColor.text = branding.accentColorHex;
    _sponsorEnabled = branding.sponsor.enabled;
    _sponsorName.text = branding.sponsor.name;
    _sponsorLabel.text = branding.sponsor.label;
    _sponsorLogoUrl.text = branding.sponsor.logoUrl ?? '';
    _sponsorWebsiteUrl.text = branding.sponsor.websiteUrl ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final brandingAsync = ref.watch(associationBrandingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Branding & Sponsor')),
      body: brandingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Branding could not be loaded: $error'),
          ),
        ),
        data: (branding) {
          _load(branding);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'League identity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'These details will become the shared identity for the app, public pages, and future share cards.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                _textField(
                  controller: _leagueName,
                  label: 'Full league or association name',
                  required: true,
                ),
                _textField(
                  controller: _shortName,
                  label: 'Short display name',
                  required: true,
                ),
                _textField(
                  controller: _leagueLogoUrl,
                  label: 'League logo HTTPS URL',
                  url: true,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _colorField(_primaryColor, 'Primary color'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _colorField(_secondaryColor, 'Dark color')),
                    const SizedBox(width: 10),
                    Expanded(child: _colorField(_accentColor, 'Accent color')),
                  ],
                ),
                const SizedBox(height: 24),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show title sponsor'),
                  subtitle: const Text(
                    'Display one optional sponsor without replacing the league identity.',
                  ),
                  value: _sponsorEnabled,
                  onChanged: (value) => setState(() => _sponsorEnabled = value),
                ),
                if (_sponsorEnabled) ...[
                  _textField(
                    controller: _sponsorName,
                    label: 'Sponsor name',
                    required: true,
                    refreshPreview: true,
                  ),
                  _textField(
                    controller: _sponsorLabel,
                    label: 'Sponsor label',
                    hint: 'Presented by',
                    refreshPreview: true,
                  ),
                  _textField(
                    controller: _sponsorLogoUrl,
                    label: 'Sponsor logo HTTPS URL',
                    url: true,
                    refreshPreview: true,
                  ),
                  _textField(
                    controller: _sponsorWebsiteUrl,
                    label: 'Sponsor website HTTPS URL',
                    url: true,
                    refreshPreview: true,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SponsorBanner(branding: _draftBranding(branding)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(branding),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save branding'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    bool url = false,
    bool refreshPreview = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        onChanged: refreshPreview ? (_) => setState(() {}) : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) return '$label is required';
          if (text.length > 120) return '$label is too long';
          if (url && text.isNotEmpty) {
            final uri = Uri.tryParse(text);
            if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
              return 'Use a complete HTTPS URL';
            }
          }
          return null;
        },
      ),
    );
  }

  AssociationBrandingModel _draftBranding(AssociationBrandingModel current) {
    return current.copyWith(
      leagueName: _leagueName.text.trim(),
      shortName: _shortName.text.trim(),
      logoUrl: _leagueLogoUrl.text.trim(),
      primaryColorHex: _primaryColor.text.trim(),
      secondaryColorHex: _secondaryColor.text.trim(),
      accentColorHex: _accentColor.text.trim(),
      sponsor: SponsorBrandingModel(
        enabled: _sponsorEnabled,
        name: _sponsorName.text.trim(),
        label: _sponsorLabel.text.trim(),
        logoUrl: _sponsorLogoUrl.text.trim(),
        websiteUrl: _sponsorWebsiteUrl.text.trim(),
      ),
    );
  }

  Widget _colorField(TextEditingController controller, String label) {
    return _textField(controller: controller, label: label, required: true);
  }

  Future<void> _save(AssociationBrandingModel current) async {
    if (!_formKey.currentState!.validate()) return;
    for (final entry in {
      'Primary color': _primaryColor.text,
      'Dark color': _secondaryColor.text,
      'Accent color': _accentColor.text,
    }.entries) {
      if (!AssociationBrandingModel.isValidColorHex(entry.value)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry.key} must look like #2E7D32')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final updated = current.copyWith(
        leagueName: _leagueName.text.trim(),
        shortName: _shortName.text.trim(),
        logoUrl: _leagueLogoUrl.text.trim(),
        primaryColorHex: _primaryColor.text.trim(),
        secondaryColorHex: _secondaryColor.text.trim(),
        accentColorHex: _accentColor.text.trim(),
        sponsor: SponsorBrandingModel(
          enabled: _sponsorEnabled,
          name: _sponsorName.text.trim(),
          label: _sponsorLabel.text.trim(),
          logoUrl: _sponsorLogoUrl.text.trim(),
          websiteUrl: _sponsorWebsiteUrl.text.trim(),
        ),
      );
      await ref.read(associationRepositoryProvider).saveBranding(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Branding saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Branding was not saved: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
