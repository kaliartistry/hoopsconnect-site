import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/error_mapper.dart';
import '../../core/widgets/error_display.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../models/association_branding_model.dart';
import '../../providers/association_branding_providers.dart';

typedef BrandingSaveCallback =
    Future<void> Function(AssociationBrandingModel branding);

class AssociationBrandingScreen extends ConsumerStatefulWidget {
  final BrandingSaveCallback? saveBranding;

  const AssociationBrandingScreen({super.key, this.saveBranding});

  @override
  ConsumerState<AssociationBrandingScreen> createState() =>
      _AssociationBrandingScreenState();
}

class _AssociationBrandingScreenState
    extends ConsumerState<AssociationBrandingScreen> {
  static const _jbaPalette =
      <({String name, String primary, String secondary, String accent})>[
        (
          name: 'JBA green',
          primary: '#2E7D32',
          secondary: '#1B5E20',
          accent: '#F9A825',
        ),
        (
          name: 'Deep green',
          primary: '#146B3A',
          secondary: '#083D21',
          accent: '#FFB81C',
        ),
        (
          name: 'Night and gold',
          primary: '#153D2D',
          secondary: '#0B2119',
          accent: '#FFC72C',
        ),
      ];

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

  AssociationBrandingModel? _baseline;
  AssociationBrandingModel? _pendingRemote;
  String? _seenProviderFingerprint;
  bool _sponsorEnabled = false;
  bool _saving = false;
  bool _dirty = false;
  bool _hydrating = false;
  String? _saveError;

  List<TextEditingController> get _controllers => [
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
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_draftChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_draftChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _draftChanged() {
    if (_hydrating || _baseline == null) return;
    final dirty = _draftFingerprint() != _fingerprint(_baseline!);
    if (!mounted) return;
    setState(() {
      _dirty = dirty;
      _saveError = null;
    });
  }

  void _acceptProviderBranding(AssociationBrandingModel branding) {
    final fingerprint = _fingerprint(branding);
    if (_seenProviderFingerprint == fingerprint) return;
    _seenProviderFingerprint = fingerprint;

    if (_baseline == null || !_dirty) {
      _applyBranding(branding);
      return;
    }

    // Preserve the local draft. The user decides which version wins.
    _pendingRemote = branding;
  }

  void _applyBranding(AssociationBrandingModel branding) {
    _hydrating = true;
    _baseline = branding;
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
    _dirty = false;
    _pendingRemote = null;
    _saveError = null;
    _hydrating = false;
  }

  @override
  Widget build(BuildContext context) {
    final brandingAsync = ref.watch(associationBrandingProvider);
    return PopScope<Object?>(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        appBar: AppBar(title: const Text('Branding & Sponsor')),
        body: brandingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorDisplay(
            error: error,
            onRetry: () => ref.invalidate(associationBrandingProvider),
          ),
          data: (branding) {
            _acceptProviderBranding(branding);
            final baseline = _baseline ?? branding;
            final draft = _draftBranding(baseline, safeColors: true);

            return Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1100;
                  final horizontalPadding = constraints.maxWidth >= 700
                      ? 24.0
                      : 16.0;
                  final editor = _buildEditor(context);
                  final preview = _BrandingPreview(branding: draft);

                  return ListView(
                    key: const Key('branding-scroll-view'),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      36,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1360),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 6, child: editor),
                                    const SizedBox(width: 28),
                                    Expanded(flex: 4, child: preview),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    preview,
                                    const SizedBox(height: 20),
                                    editor,
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pendingRemote != null) _remoteUpdateNotice(context),
        if (_saveError != null) ...[
          Semantics(
            liveRegion: true,
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _sectionCard(
          context,
          title: 'League identity',
          description:
              'This identity leads the app, public pages, and share cards. Sponsor details always remain secondary.',
          children: [
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
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          context,
          title: 'Brand colors',
          description:
              'Use six-digit hex colors. The live preview reports the actual text contrast for every selection.',
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760
                    ? 3
                    : constraints.maxWidth >= 480
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 0,
                  children: [
                    SizedBox(
                      width: width,
                      child: _colorField(_primaryColor, 'Primary color'),
                    ),
                    SizedBox(
                      width: width,
                      child: _colorField(_secondaryColor, 'Dark color'),
                    ),
                    SizedBox(
                      width: width,
                      child: _colorField(_accentColor, 'Accent color'),
                    ),
                  ],
                );
              },
            ),
            Text('Preset palettes', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final palette in _jbaPalette)
                  OutlinedButton(
                    key: Key('branding-palette-${palette.name}'),
                    onPressed: _saving
                        ? null
                        : () => _applyPalette(
                            palette.primary,
                            palette.secondary,
                            palette.accent,
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniSwatches(
                          colors: [
                            AssociationBrandingModel.colorFromHex(
                              palette.primary,
                            ),
                            AssociationBrandingModel.colorFromHex(
                              palette.secondary,
                            ),
                            AssociationBrandingModel.colorFromHex(
                              palette.accent,
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(palette.name)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionCard(
          context,
          title: 'Title sponsor',
          description:
              'Optional sponsor recognition never replaces the league name, colors, or logo.',
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show title sponsor'),
              subtitle: const Text(
                'Display one optional sponsor below the league identity.',
              ),
              value: _sponsorEnabled,
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _sponsorEnabled = value;
                        _saveError = null;
                        _dirty =
                            _draftFingerprint() != _fingerprint(_baseline!);
                      });
                    },
            ),
            if (_sponsorEnabled) ...[
              _textField(
                controller: _sponsorName,
                label: 'Sponsor name',
                required: true,
              ),
              _textField(
                controller: _sponsorLabel,
                label: 'Sponsor label',
                hint: 'Presented by',
              ),
              _textField(
                controller: _sponsorLogoUrl,
                label: 'Sponsor logo HTTPS URL',
                url: true,
              ),
              _textField(
                controller: _sponsorWebsiteUrl,
                label: 'Sponsor website HTTPS URL',
                url: true,
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('save-branding-button'),
          onPressed: _saving || !_dirty || _pendingRemote != null
              ? null
              : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving branding…' : 'Save branding'),
        ),
        const SizedBox(height: 8),
        Text(
          _pendingRemote != null
              ? 'Resolve the saved-settings update before saving.'
              : _dirty
              ? 'You have unsaved changes.'
              : 'All branding changes are saved.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _remoteUpdateNotice(BuildContext context) {
    final theme = Theme.of(context);
    final associationChanged =
        _pendingRemote!.associationId != _baseline!.associationId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                associationChanged
                    ? 'Your association changed'
                    : 'Saved settings changed elsewhere',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                associationChanged
                    ? 'Your edits are still here, but they cannot be saved to a different association.'
                    : 'Your edits were not replaced. Choose which version you want to continue with.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!associationChanged)
                    TextButton(
                      key: const Key('keep-branding-edits'),
                      onPressed: () => setState(() => _pendingRemote = null),
                      child: const Text('Keep my edits'),
                    ),
                  FilledButton.tonal(
                    key: const Key('use-saved-branding'),
                    onPressed: () => setState(() {
                      final pending = _pendingRemote!;
                      _applyBranding(pending);
                    }),
                    child: const Text('Use saved version'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    bool url = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        keyboardType: url ? TextInputType.url : TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) return '$label is required';
          if (text.length > 120) return '$label is too long';
          if (url && text.isNotEmpty && _httpsUri(text) == null) {
            return 'Use a complete HTTPS URL';
          }
          return null;
        },
      ),
    );
  }

  Widget _colorField(TextEditingController controller, String label) {
    final valid = AssociationBrandingModel.isValidColorHex(controller.text);
    final color = valid
        ? AssociationBrandingModel.colorFromHex(controller.text)
        : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        textCapitalization: TextCapitalization.characters,
        maxLength: 7,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          prefixIcon: Padding(
            padding: const EdgeInsets.all(13),
            child: DecoratedBox(
              key: Key('color-swatch-$label'),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
        validator: (value) {
          if (!AssociationBrandingModel.isValidColorHex(value ?? '')) {
            return '$label must look like #2E7D32';
          }
          return null;
        },
      ),
    );
  }

  void _applyPalette(String primary, String secondary, String accent) {
    _hydrating = true;
    _primaryColor.text = primary;
    _secondaryColor.text = secondary;
    _accentColor.text = accent;
    _hydrating = false;
    setState(() {
      _dirty = _draftFingerprint() != _fingerprint(_baseline!);
      _saveError = null;
    });
  }

  AssociationBrandingModel _draftBranding(
    AssociationBrandingModel current, {
    required bool safeColors,
  }) {
    String safeColor(TextEditingController controller, String fallback) {
      final value = controller.text.trim();
      return !safeColors || AssociationBrandingModel.isValidColorHex(value)
          ? value
          : fallback;
    }

    return current.copyWith(
      leagueName: _leagueName.text.trim(),
      shortName: _shortName.text.trim(),
      logoUrl: _leagueLogoUrl.text.trim(),
      primaryColorHex: safeColor(_primaryColor, current.primaryColorHex),
      secondaryColorHex: safeColor(_secondaryColor, current.secondaryColorHex),
      accentColorHex: safeColor(_accentColor, current.accentColorHex),
      sponsor: SponsorBrandingModel(
        enabled: _sponsorEnabled,
        name: _sponsorName.text.trim(),
        label: _sponsorLabel.text.trim(),
        logoUrl: _sponsorLogoUrl.text.trim(),
        websiteUrl: _sponsorWebsiteUrl.text.trim(),
      ),
    );
  }

  String _draftFingerprint() =>
      _fingerprint(_draftBranding(_baseline!, safeColors: false));

  String _fingerprint(AssociationBrandingModel branding) => [
    branding.associationId,
    branding.leagueName.trim(),
    branding.shortName.trim(),
    branding.logoUrl?.trim() ?? '',
    branding.primaryColorHex.trim().toUpperCase(),
    branding.secondaryColorHex.trim().toUpperCase(),
    branding.accentColorHex.trim().toUpperCase(),
    branding.sponsor.enabled.toString(),
    branding.sponsor.name.trim(),
    branding.sponsor.label.trim(),
    branding.sponsor.logoUrl?.trim() ?? '',
    branding.sponsor.websiteUrl?.trim() ?? '',
  ].join('\u0001');

  Future<void> _save() async {
    if (_saving || !_dirty || _pendingRemote != null || _baseline == null) {
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final updated = _draftBranding(_baseline!, safeColors: false);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final callback = widget.saveBranding;
      if (callback != null) {
        await callback(updated);
      } else {
        await ref.read(associationRepositoryProvider).saveBranding(updated);
      }
      if (!mounted) return;
      setState(() {
        _baseline = updated;
        _dirty = false;
        _pendingRemote = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branding saved and confirmed')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Branding was not saved. ${ErrorMapper.map(error)}';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handlePop(bool didPop, Object? result) async {
    if (didPop) return;
    if (_saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for the save to finish.')),
      );
      return;
    }
    if (!_dirty) return;

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard branding changes?'),
        content: const Text(
          'Your unsaved league identity and sponsor edits will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(result);
    }
  }
}

class _BrandingPreview extends StatelessWidget {
  final AssociationBrandingModel branding;

  const _BrandingPreview({required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = branding.primaryColor;
    final primaryForeground = _highestContrastForeground(primary);

    return Card(
      key: const Key('branding-live-preview'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: primary,
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LogoPreview(
                  label: 'League logo',
                  url: branding.logoUrl,
                  compact: true,
                  foreground: primaryForeground,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branding.leagueName.isEmpty
                            ? 'League name preview'
                            : branding.leagueName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: primaryForeground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        branding.shortName.isEmpty
                            ? 'Short name'
                            : branding.shortName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: primaryForeground.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Live league preview', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'This is the primary identity people will see.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _LogoPreview(label: 'League logo', url: branding.logoUrl),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ColorToken(label: 'Primary', color: branding.primaryColor),
                    _ColorToken(label: 'Dark', color: branding.secondaryColor),
                    _ColorToken(label: 'Accent', color: branding.accentColor),
                  ],
                ),
                const SizedBox(height: 16),
                _ContrastGuidance(branding: branding),
                const SizedBox(height: 20),
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
                Text('Sponsor placement', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Secondary to the Jamaica Basketball identity',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (!branding.sponsor.enabled)
                  const _PreviewStatus(
                    icon: Icons.visibility_off_outlined,
                    message:
                        'Sponsor is off. The full league identity remains active.',
                  )
                else ...[
                  _LogoPreview(
                    label: 'Sponsor logo',
                    url: branding.sponsor.logoUrl,
                  ),
                  if (!branding.sponsor.isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: _PreviewStatus(
                        icon: Icons.info_outline,
                        message:
                            'Add a sponsor name to show sponsor recognition.',
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SponsorBanner(
                        branding: branding,
                        margin: EdgeInsets.zero,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  final String label;
  final String? url;
  final bool compact;
  final Color? foreground;

  const _LogoPreview({
    required this.label,
    required this.url,
    this.compact = false,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final value = url?.trim() ?? '';
    final uri = _httpsUri(value);
    final theme = Theme.of(context);
    final size = compact ? 56.0 : 84.0;
    final emptyForeground = foreground ?? theme.colorScheme.onSurfaceVariant;

    if (value.isEmpty) {
      return _LogoFrame(
        size: size,
        compact: compact,
        child: IconTheme(
          data: IconThemeData(color: emptyForeground),
          child: _LogoState(
            key: Key('${_keyPart(label)}-logo-empty'),
            icon: Icons.sports_basketball_outlined,
            message: 'No ${label.toLowerCase()} added.',
            compact: compact,
          ),
        ),
      );
    }
    if (uri == null) {
      return _LogoFrame(
        size: size,
        compact: compact,
        child: _LogoState(
          key: Key('${_keyPart(label)}-logo-invalid'),
          icon: Icons.link_off,
          message: 'Enter a valid HTTPS URL to preview $label.',
          compact: compact,
        ),
      );
    }

    return _LogoFrame(
      size: size,
      compact: compact,
      child: Image.network(
        uri.toString(),
        key: Key('${_keyPart(label)}-logo-image'),
        width: compact ? size : double.infinity,
        height: size,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _LogoState(
            key: Key('${_keyPart(label)}-logo-loading'),
            icon: Icons.downloading_outlined,
            message: 'Loading $label…',
            compact: compact,
          );
        },
        errorBuilder: (context, error, stackTrace) => _LogoState(
          key: Key('${_keyPart(label)}-logo-error'),
          icon: Icons.broken_image_outlined,
          message: '$label could not be loaded. Check the URL.',
          compact: compact,
        ),
      ),
    );
  }
}

class _LogoFrame extends StatelessWidget {
  final double size;
  final bool compact;
  final Widget child;

  const _LogoFrame({
    required this.size,
    required this.compact,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? size : double.infinity,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _LogoState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool compact;

  const _LogoState({
    super.key,
    required this.icon,
    required this.message,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(message: message, child: Icon(icon, size: 26));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ContrastGuidance extends StatelessWidget {
  final AssociationBrandingModel branding;

  const _ContrastGuidance({required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = <(String, Color)>[
      ('Primary', branding.primaryColor),
      ('Dark', branding.secondaryColor),
      ('Accent', branding.accentColor),
    ];
    final brandPairRatio = _contrastRatio(
      branding.primaryColor,
      branding.accentColor,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Readability check', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final entry in colors) ...[
            Builder(
              builder: (context) {
                final foreground = _highestContrastForeground(entry.$2);
                final ratio = _contrastRatio(foreground, entry.$2);
                final foregroundName = foreground == Colors.black
                    ? 'Black'
                    : 'White';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${entry.$1}: $foregroundName text ${ratio.toStringAsFixed(2)}:1 · ${ratio >= 4.5 ? 'AA readable' : 'large text only'}',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Primary + accent: ${brandPairRatio.toStringAsFixed(2)}:1 · ${brandPairRatio >= 3 ? 'clear for large graphics' : 'use as decorative colors, not text on text'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorToken extends StatelessWidget {
  final String label;
  final Color color;

  const _ColorToken({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final foreground = _highestContrastForeground(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniSwatches extends StatelessWidget {
  final List<Color> colors;

  const _MiniSwatches({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in colors)
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  final IconData icon;
  final String message;

  const _PreviewStatus({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

Uri? _httpsUri(String value) {
  if (value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

String _keyPart(String label) {
  final value = label.toLowerCase().replaceAll(' ', '-');
  return value.endsWith('-logo')
      ? value.substring(0, value.length - '-logo'.length)
      : value;
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _highestContrastForeground(Color background) {
  final blackContrast = _contrastRatio(Colors.black, background);
  final whiteContrast = _contrastRatio(Colors.white, background);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}
