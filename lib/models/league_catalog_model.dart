import 'association_branding_model.dart';

enum LeagueProfileStatus { active, archived }

class LeagueProfileModel {
  const LeagueProfileModel({
    required this.id,
    required this.name,
    required this.shortName,
    this.description,
    this.divisionIds = const [],
    this.logoUrl,
    this.primaryColorHex = '#2E7D32',
    this.secondaryColorHex = '#1B5E20',
    this.accentColorHex = '#F9A825',
    this.sponsor = const SponsorBrandingModel(),
    this.status = LeagueProfileStatus.active,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String shortName;
  final String? description;
  final List<String> divisionIds;
  final String? logoUrl;
  final String primaryColorHex;
  final String secondaryColorHex;
  final String accentColorHex;
  final SponsorBrandingModel sponsor;
  final LeagueProfileStatus status;
  final int sortOrder;

  bool get isArchived => status == LeagueProfileStatus.archived;

  AssociationBrandingModel asBranding(String associationId) =>
      AssociationBrandingModel(
        associationId: associationId,
        leagueName: name,
        shortName: shortName,
        logoUrl: logoUrl,
        primaryColorHex: primaryColorHex,
        secondaryColorHex: secondaryColorHex,
        accentColorHex: accentColorHex,
        sponsor: sponsor,
      );

  factory LeagueProfileModel.fromMap(Map<String, dynamic> data) {
    final id = _requiredText(data['leagueId'], 'leagueId');
    final name = _requiredText(data['name'], 'league name');
    final rawStatus = data['status'];
    final status = switch (rawStatus) {
      null || 'active' => LeagueProfileStatus.active,
      'archived' => LeagueProfileStatus.archived,
      _ => throw FormatException('Unsupported league status: $rawStatus'),
    };
    final rawDivisions = data['divisionIds'];
    if (rawDivisions != null && rawDivisions is! List) {
      throw const FormatException('League divisionIds must be a list.');
    }
    final divisionIds = <String>[];
    for (final value in rawDivisions as List? ?? const []) {
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('League division IDs must be strings.');
      }
      final normalized = value.trim();
      if (!divisionIds.contains(normalized)) divisionIds.add(normalized);
    }
    final branding = data['branding'] is Map
        ? Map<String, dynamic>.from(data['branding'] as Map)
        : const <String, dynamic>{};
    return LeagueProfileModel(
      id: id,
      name: name,
      shortName: _text(data['shortName']) ?? name,
      description: _text(data['description']),
      divisionIds: List.unmodifiable(divisionIds),
      logoUrl: _safeHttpsUrl(branding['logoUrl']),
      primaryColorHex: _safeColor(branding['primaryColorHex'], '#2E7D32'),
      secondaryColorHex: _safeColor(branding['secondaryColorHex'], '#1B5E20'),
      accentColorHex: _safeColor(branding['accentColorHex'], '#F9A825'),
      sponsor: SponsorBrandingModel.fromMap(
        branding['sponsor'] is Map
            ? Map<String, dynamic>.from(branding['sponsor'] as Map)
            : null,
      ),
      status: status,
      sortOrder: data['sortOrder'] is int ? data['sortOrder'] as int : 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'leagueId': id,
    'name': name.trim(),
    'shortName': shortName.trim(),
    'description': _text(description),
    'divisionIds': divisionIds,
    'status': status.name,
    'sortOrder': sortOrder,
    'branding': {
      'schemaVersion': 1,
      'logoUrl': _safeHttpsUrl(logoUrl),
      'primaryColorHex': _safeColor(primaryColorHex, '#2E7D32'),
      'secondaryColorHex': _safeColor(secondaryColorHex, '#1B5E20'),
      'accentColorHex': _safeColor(accentColorHex, '#F9A825'),
      'sponsor': sponsor.toMap(),
    },
  };

  LeagueProfileModel copyWith({
    String? id,
    String? name,
    String? shortName,
    String? description,
    List<String>? divisionIds,
    String? logoUrl,
    String? primaryColorHex,
    String? secondaryColorHex,
    String? accentColorHex,
    SponsorBrandingModel? sponsor,
    LeagueProfileStatus? status,
    int? sortOrder,
  }) => LeagueProfileModel(
    id: id ?? this.id,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    description: description ?? this.description,
    divisionIds: divisionIds ?? this.divisionIds,
    logoUrl: logoUrl ?? this.logoUrl,
    primaryColorHex: primaryColorHex ?? this.primaryColorHex,
    secondaryColorHex: secondaryColorHex ?? this.secondaryColorHex,
    accentColorHex: accentColorHex ?? this.accentColorHex,
    sponsor: sponsor ?? this.sponsor,
    status: status ?? this.status,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  static String stableId(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class LeagueCatalogModel {
  const LeagueCatalogModel({this.leagues = const []});

  static const maxLeagues = 100;

  final List<LeagueProfileModel> leagues;

  List<LeagueProfileModel> get orderedActive {
    final result = leagues.where((league) => !league.isArchived).toList();
    result.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
    return List.unmodifiable(result);
  }

  factory LeagueCatalogModel.fromAssociationMap(Map<String, dynamic> data) {
    final raw = data['leagueCatalogV1'];
    if (raw == null) return const LeagueCatalogModel();
    if (raw is! Map) {
      throw const FormatException('leagueCatalogV1 must be a map.');
    }
    final catalog = Map<String, dynamic>.from(raw);
    if (catalog['schemaVersion'] != 1 || catalog['leagues'] is! List) {
      throw const FormatException('Unsupported league catalog.');
    }
    final leagues = (catalog['leagues'] as List)
        .map(
          (value) => LeagueProfileModel.fromMap(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false);
    if (leagues.length > maxLeagues) {
      throw const FormatException(
        'A league catalog may contain at most 100 leagues.',
      );
    }
    final ids = <String>{};
    final assignedDivisions = <String>{};
    for (final league in leagues) {
      if (!ids.add(league.id)) {
        throw FormatException('Duplicate league ID ${league.id}.');
      }
      for (final divisionId in league.divisionIds) {
        if (!assignedDivisions.add(divisionId)) {
          throw FormatException(
            'Division $divisionId is assigned to more than one league.',
          );
        }
      }
    }
    return LeagueCatalogModel(leagues: List.unmodifiable(leagues));
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'leagues': leagues.map((league) => league.toMap()).toList(growable: false),
  };
}

String _requiredText(Object? value, String field) {
  final text = _text(value);
  if (text == null) throw FormatException('$field is required.');
  return text;
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

String _safeColor(Object? value, String fallback) {
  final text = _text(value);
  return text != null && AssociationBrandingModel.isValidColorHex(text)
      ? text.toUpperCase()
      : fallback;
}

String? _safeHttpsUrl(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? uri.toString()
      : null;
}
