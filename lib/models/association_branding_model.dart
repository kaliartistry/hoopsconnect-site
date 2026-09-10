import 'package:flutter/material.dart';

class SponsorBrandingModel {
  final bool enabled;
  final String name;
  final String label;
  final String? logoUrl;
  final String? websiteUrl;

  const SponsorBrandingModel({
    this.enabled = false,
    this.name = '',
    this.label = 'Presented by',
    this.logoUrl,
    this.websiteUrl,
  });

  factory SponsorBrandingModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SponsorBrandingModel();
    return SponsorBrandingModel(
      enabled: data['enabled'] as bool? ?? false,
      name: (data['name'] as String? ?? '').trim(),
      label: (data['label'] as String? ?? 'Presented by').trim(),
      logoUrl: _httpsUrlOrNull(data['logoUrl']),
      websiteUrl: _httpsUrlOrNull(data['websiteUrl']),
    );
  }

  bool get isActive => enabled && name.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'name': name.trim(),
    'label': label.trim().isEmpty ? 'Presented by' : label.trim(),
    'logoUrl': _httpsUrlOrNull(logoUrl),
    'websiteUrl': _httpsUrlOrNull(websiteUrl),
  };

  SponsorBrandingModel copyWith({
    bool? enabled,
    String? name,
    String? label,
    String? logoUrl,
    String? websiteUrl,
  }) {
    return SponsorBrandingModel(
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      label: label ?? this.label,
      logoUrl: logoUrl ?? this.logoUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
    );
  }
}

class AssociationBrandingModel {
  final String associationId;
  final String leagueName;
  final String shortName;
  final String? logoUrl;
  final String primaryColorHex;
  final String secondaryColorHex;
  final String accentColorHex;
  final SponsorBrandingModel sponsor;

  const AssociationBrandingModel({
    required this.associationId,
    required this.leagueName,
    required this.shortName,
    this.logoUrl,
    required this.primaryColorHex,
    required this.secondaryColorHex,
    required this.accentColorHex,
    this.sponsor = const SponsorBrandingModel(),
  });

  factory AssociationBrandingModel.jba({String associationId = 'jba'}) {
    return AssociationBrandingModel(
      associationId: associationId,
      leagueName: 'Jamaica Basketball Association',
      shortName: 'Jamaica Basketball',
      logoUrl: null,
      primaryColorHex: '#2E7D32',
      secondaryColorHex: '#1B5E20',
      accentColorHex: '#F9A825',
    );
  }

  factory AssociationBrandingModel.fromMap({
    required String associationId,
    required Map<String, dynamic> data,
  }) {
    final defaults = AssociationBrandingModel.jba(associationId: associationId);
    final branding = data['brandingV1'] is Map
        ? Map<String, dynamic>.from(data['brandingV1'] as Map)
        : const <String, dynamic>{};
    final sponsor = branding['sponsor'] is Map
        ? Map<String, dynamic>.from(branding['sponsor'] as Map)
        : null;

    return AssociationBrandingModel(
      associationId: associationId,
      leagueName: _textOrFallback(
        branding['leagueName'] ?? data['name'],
        defaults.leagueName,
      ),
      shortName: _textOrFallback(
        branding['shortName'] ?? data['shortName'],
        defaults.shortName,
      ),
      logoUrl: _httpsUrlOrNull(branding['logoUrl'] ?? data['logoUrl']),
      primaryColorHex: _colorOrFallback(
        branding['primaryColorHex'],
        defaults.primaryColorHex,
      ),
      secondaryColorHex: _colorOrFallback(
        branding['secondaryColorHex'],
        defaults.secondaryColorHex,
      ),
      accentColorHex: _colorOrFallback(
        branding['accentColorHex'],
        defaults.accentColorHex,
      ),
      sponsor: SponsorBrandingModel.fromMap(sponsor),
    );
  }

  Map<String, dynamic> toBrandingMap() => {
    'schemaVersion': 1,
    'leagueName': leagueName.trim(),
    'shortName': shortName.trim(),
    'logoUrl': _httpsUrlOrNull(logoUrl),
    'primaryColorHex': _colorOrFallback(primaryColorHex, '#2E7D32'),
    'secondaryColorHex': _colorOrFallback(secondaryColorHex, '#1B5E20'),
    'accentColorHex': _colorOrFallback(accentColorHex, '#F9A825'),
    'sponsor': sponsor.toMap(),
  };

  Color get primaryColor => colorFromHex(primaryColorHex);
  Color get secondaryColor => colorFromHex(secondaryColorHex);
  Color get accentColor => colorFromHex(accentColorHex);

  AssociationBrandingModel copyWith({
    String? leagueName,
    String? shortName,
    String? logoUrl,
    String? primaryColorHex,
    String? secondaryColorHex,
    String? accentColorHex,
    SponsorBrandingModel? sponsor,
  }) {
    return AssociationBrandingModel(
      associationId: associationId,
      leagueName: leagueName ?? this.leagueName,
      shortName: shortName ?? this.shortName,
      logoUrl: logoUrl ?? this.logoUrl,
      primaryColorHex: primaryColorHex ?? this.primaryColorHex,
      secondaryColorHex: secondaryColorHex ?? this.secondaryColorHex,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      sponsor: sponsor ?? this.sponsor,
    );
  }

  static bool isValidColorHex(String value) =>
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim());

  static Color colorFromHex(String value) {
    final normalized = _colorOrFallback(value, '#2E7D32').substring(1);
    return Color(int.parse('FF$normalized', radix: 16));
  }
}

String _textOrFallback(Object? value, String fallback) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? fallback : text;
}

String _colorOrFallback(Object? value, String fallback) {
  final text = value is String ? value.trim() : '';
  return AssociationBrandingModel.isValidColorHex(text)
      ? text.toUpperCase()
      : fallback;
}

String? _httpsUrlOrNull(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.toString();
}
