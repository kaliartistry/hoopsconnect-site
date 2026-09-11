enum RosterChangeKind { addPlayer, updatePlayer, removePlayer }

enum RosterApprovalStatus { pending, approved, rejected }

enum RosterProposalDecision { approve, reject }

class RosterRegistration {
  final String registrationId;
  final String playerId;
  final String displayName;
  final String teamId;
  final String seasonId;
  final String jerseyNumber;
  final String? position;
  final String status;

  const RosterRegistration({
    required this.registrationId,
    required this.playerId,
    required this.displayName,
    required this.teamId,
    required this.seasonId,
    required this.jerseyNumber,
    this.position,
    required this.status,
  });

  factory RosterRegistration.fromMap(Map<String, dynamic> map) {
    return RosterRegistration(
      registrationId: _requiredText(map, 'registrationId'),
      playerId: _requiredText(map, 'playerId'),
      displayName: _requiredText(map, 'displayName'),
      teamId: _requiredText(map, 'teamId'),
      seasonId: _requiredText(map, 'seasonId'),
      jerseyNumber: _requiredJersey(map['jerseyNumber']),
      position: _optionalText(map['position']),
      status: _requiredText(map, 'status'),
    );
  }
}

class RosterProposalSummary {
  final String proposalId;
  final RosterChangeKind kind;
  final RosterApprovalStatus status;
  final String teamId;
  final String seasonId;
  final String? playerId;
  final String requestedByName;
  final DateTime? requestedAt;
  final String? reviewNote;

  const RosterProposalSummary({
    required this.proposalId,
    required this.kind,
    required this.status,
    required this.teamId,
    required this.seasonId,
    this.playerId,
    required this.requestedByName,
    this.requestedAt,
    this.reviewNote,
  });

  factory RosterProposalSummary.fromMap(Map<String, dynamic> map) {
    return RosterProposalSummary(
      proposalId: _requiredText(map, 'proposalId'),
      kind: RosterChangeKind.values.byName(_requiredText(map, 'kind')),
      status: RosterApprovalStatus.values.byName(_requiredText(map, 'status')),
      teamId: _requiredText(map, 'teamId'),
      seasonId: _requiredText(map, 'seasonId'),
      playerId: _optionalText(map['playerId']),
      requestedByName: _requiredText(map, 'requestedByName'),
      requestedAt: _optionalUtcDateTime(map['requestedAt']),
      reviewNote: _optionalText(map['reviewNote']),
    );
  }
}

class RosterWorkspace {
  final int rosterVersion;
  final List<RosterRegistration> registrations;
  final List<RosterProposalSummary> proposals;

  const RosterWorkspace({
    required this.rosterVersion,
    this.registrations = const [],
    this.proposals = const [],
  });

  factory RosterWorkspace.fromMap(Map<String, dynamic> map) {
    final version = map['rosterVersion'];
    if (version is! int || version < 0) {
      throw const FormatException(
        'rosterVersion must be a nonnegative integer',
      );
    }
    return RosterWorkspace(
      rosterVersion: version,
      registrations: _mapList(
        map['registrations'],
      ).map(RosterRegistration.fromMap).toList(growable: false),
      proposals: _mapList(
        map['proposals'],
      ).map(RosterProposalSummary.fromMap).toList(growable: false),
    );
  }
}

class RosterChangeRequest {
  static const schemaVersion = 1;

  final String operationId;
  final String teamId;
  final String seasonId;
  final int expectedRosterVersion;
  final RosterChangeKind kind;
  final String? playerId;
  final String? registrationId;
  final String? displayName;
  final String? jerseyNumber;
  final String? position;
  final String reason;

  RosterChangeRequest({
    required this.operationId,
    required this.teamId,
    required this.seasonId,
    required this.expectedRosterVersion,
    required this.kind,
    this.playerId,
    this.registrationId,
    this.displayName,
    this.jerseyNumber,
    this.position,
    required this.reason,
  }) {
    _requireId('operationId', operationId);
    _requireId('teamId', teamId);
    _requireId('seasonId', seasonId);
    if (expectedRosterVersion < 0) {
      throw ArgumentError.value(
        expectedRosterVersion,
        'expectedRosterVersion',
        'must be nonnegative',
      );
    }
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw ArgumentError.value(reason, 'reason', 'must be 1-500 characters');
    }
    if (kind == RosterChangeKind.addPlayer) {
      if (playerId != null || registrationId != null) {
        throw ArgumentError('New players receive stable IDs from the server');
      }
      _requiredDisplayName(displayName);
      _requiredJersey(jerseyNumber);
    } else {
      _requireId('playerId', playerId);
      _requireId('registrationId', registrationId);
      if (kind == RosterChangeKind.updatePlayer) {
        _requiredDisplayName(displayName);
        _requiredJersey(jerseyNumber);
      } else if (displayName != null ||
          jerseyNumber != null ||
          position != null) {
        throw ArgumentError('Remove requests do not replace player facts');
      }
    }
    if (position != null && position!.trim().length > 40) {
      throw ArgumentError.value(
        position,
        'position',
        'must be at most 40 characters',
      );
    }
  }

  Map<String, Object?> toMap({required String requestedOutcome}) => {
    'schemaVersion': schemaVersion,
    'operationId': operationId,
    'teamId': teamId,
    'seasonId': seasonId,
    'expectedRosterVersion': expectedRosterVersion,
    'kind': kind.name,
    'requestedOutcome': requestedOutcome,
    if (playerId != null) 'playerId': playerId,
    if (registrationId != null) 'registrationId': registrationId,
    if (displayName != null) 'displayName': displayName!.trim(),
    if (jerseyNumber != null) 'jerseyNumber': jerseyNumber,
    if (position?.trim().isNotEmpty == true) 'position': position!.trim(),
    'reason': reason.trim(),
  };
}

class RosterChangeReceipt {
  final String operationId;
  final String? proposalId;
  final String? playerId;
  final String? registrationId;
  final RosterApprovalStatus status;
  final int rosterVersion;

  const RosterChangeReceipt({
    required this.operationId,
    this.proposalId,
    this.playerId,
    this.registrationId,
    required this.status,
    required this.rosterVersion,
  });

  factory RosterChangeReceipt.fromMap(Map<String, dynamic> map) {
    final version = map['rosterVersion'];
    if (version is! int || version < 0) {
      throw const FormatException(
        'rosterVersion must be a nonnegative integer',
      );
    }
    return RosterChangeReceipt(
      operationId: _requiredText(map, 'operationId'),
      proposalId: _optionalText(map['proposalId']),
      playerId: _optionalText(map['playerId']),
      registrationId: _optionalText(map['registrationId']),
      status: RosterApprovalStatus.values.byName(_requiredText(map, 'status')),
      rosterVersion: version,
    );
  }
}

class RosterProposalReviewRequest {
  final String operationId;
  final String proposalId;
  final String teamId;
  final String seasonId;
  final int expectedRosterVersion;
  final RosterProposalDecision decision;
  final String? note;

  RosterProposalReviewRequest({
    required this.operationId,
    required this.proposalId,
    required this.teamId,
    required this.seasonId,
    required this.expectedRosterVersion,
    required this.decision,
    this.note,
  }) {
    _requireId('operationId', operationId);
    _requireId('proposalId', proposalId);
    _requireId('teamId', teamId);
    _requireId('seasonId', seasonId);
    if (expectedRosterVersion < 0) {
      throw ArgumentError.value(
        expectedRosterVersion,
        'expectedRosterVersion',
        'must be nonnegative',
      );
    }
    if (decision == RosterProposalDecision.reject &&
        (note == null || note!.trim().isEmpty)) {
      throw ArgumentError.value(note, 'note', 'is required when rejecting');
    }
    if ((note?.trim().length ?? 0) > 500) {
      throw ArgumentError.value(note, 'note', 'must be at most 500 characters');
    }
  }

  Map<String, Object?> toMap() => {
    'schemaVersion': RosterChangeRequest.schemaVersion,
    'operationId': operationId,
    'proposalId': proposalId,
    'teamId': teamId,
    'seasonId': seasonId,
    'expectedRosterVersion': expectedRosterVersion,
    'decision': decision.name,
    if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
  };
}

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');

void _requireId(String field, Object? value) {
  if (value is! String || !_idPattern.hasMatch(value)) {
    throw ArgumentError.value(value, field, 'must be a valid opaque ID');
  }
}

String _requiredText(Map<String, dynamic> map, String field) {
  final value = map[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be nonempty text');
  }
  return value;
}

String _requiredDisplayName(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty || text.length > 120) {
    throw ArgumentError.value(value, 'displayName', 'must be 1-120 characters');
  }
  return text;
}

String _requiredJersey(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 8 ||
      value.trim() != value) {
    throw ArgumentError.value(
      value,
      'jerseyNumber',
      'must be a 1-8 character string',
    );
  }
  return value;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected optional text');
  final text = value.trim();
  return text.isEmpty ? null : text;
}

DateTime? _optionalUtcDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.parse(value).toUtc();
  throw const FormatException('Expected an ISO timestamp');
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Expected a list');
  return value
      .map((entry) {
        if (entry is! Map) throw const FormatException('Expected an object');
        return Map<String, dynamic>.from(entry);
      })
      .toList(growable: false);
}
