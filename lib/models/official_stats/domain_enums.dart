enum PlayState {
  scheduled,
  postponed,
  inProgress,
  suspended,
  completed,
  cancelled,
  administrativelyTerminated,
}

enum ReviewState { draft, submitted, underReview, changesRequested, certified }

enum PublicationState { absent, published, superseded, retracted }

enum SeasonStatus { planned, registration, active, completed, archived }

enum CompetitionStatus { planned, active, completed, archived }

enum TeamIdentityStatus { active, inactive, merged, archived }

enum TeamEntryRegistrationStatus { proposed, pending, approved, withdrawn }

enum PersonIdentityStatus {
  provisional,
  verified,
  restricted,
  merged,
  archived,
}

enum PlayerIdentityStatus { provisional, verified, merged, suspended, archived }

enum EligibilityStatus {
  unknown,
  provisional,
  eligible,
  ineligible,
  suspended,
  released,
}

enum RosterAssertionStatus {
  submitted,
  underReview,
  approved,
  rejected,
  superseded,
}

enum WorkspaceStatus {
  preparing,
  open,
  suspended,
  sealed,
  submitted,
  conflictBranch,
  abandoned,
}

enum CaptureMode { liveCapture, officialSheet, historicalImport }

/// Stable v2 journal vocabulary. Adding or reinterpreting a value requires a
/// new operation-schema version.
enum JournalOperationType {
  setParticipantStatus,
  setPlayerCounter,
  setTeamOnlyCounter,
  setPeriodScore,
  setClock,
  recordDiscipline,
  setLineup,
  attachEvidence,
}

/// Fixed revision-part schemas. Multiple chunks of one kind are permitted and
/// are ordered by part ID inside this enum order.
enum BoxScorePartKind {
  playerInputs,
  teamOnlyInputs,
  periods,
  discipline,
  lineups,
}

enum JournalDeliveryState {
  savedOnDevice,
  queued,
  sending,
  accepted,
  needsAttention,
}

enum ResultDisposition {
  played,
  forfeit,
  defaulted,
  annulled,
  otherAdjudicated,
}

enum StatisticsDisposition { complete, resultOnly, excluded }

enum ParticipantStatus { active, dnp, inactive, provisional }

enum TimeSource {
  liveClock,
  officialSheetExact,
  officialSheetRounded,
  unavailable,
}

enum ProjectionBuildState { building, validating, sealed, failed, abandoned }

enum ReleaseHeadState { absent, active, retracted }

enum PrivacyPermissionState { unknown, permitted, denied, revoked }

enum LegacyEvidenceClassification {
  evidenced,
  unverified,
  synthetic,
  orphaned,
  contradictory,
  duplicateCandidate,
  privacyRestricted,
}

extension LegacyEvidenceCertification on LegacyEvidenceClassification {
  /// Migration evidence always requires deliberate review and a new v2
  /// certificate, including records classified as evidenced.
  bool get permitsAutomaticCertification => false;
}

extension ResultDispositionWireName on ResultDisposition {
  String get wireName => this == ResultDisposition.defaulted ? 'default' : name;
}

/// Explicit lifecycle graph. All transitions not present here fail closed.
abstract final class OfficialStatLifecycle {
  static const Map<PlayState, Set<PlayState>> playTransitions = {
    PlayState.scheduled: {
      PlayState.postponed,
      PlayState.inProgress,
      PlayState.cancelled,
      PlayState.administrativelyTerminated,
    },
    PlayState.postponed: {PlayState.scheduled},
    PlayState.inProgress: {
      PlayState.suspended,
      PlayState.completed,
      PlayState.administrativelyTerminated,
    },
    PlayState.suspended: {
      PlayState.inProgress,
      PlayState.administrativelyTerminated,
    },
    PlayState.completed: {PlayState.administrativelyTerminated},
    PlayState.cancelled: {},
    PlayState.administrativelyTerminated: {},
  };

  static const Map<ReviewState, Set<ReviewState>> reviewTransitions = {
    ReviewState.draft: {ReviewState.submitted},
    ReviewState.submitted: {
      ReviewState.underReview,
      ReviewState.changesRequested,
    },
    ReviewState.underReview: {
      ReviewState.changesRequested,
      ReviewState.certified,
    },
    ReviewState.changesRequested: {ReviewState.submitted},
    ReviewState.certified: {},
  };

  static const Map<PublicationState, Set<PublicationState>>
  publicationTransitions = {
    PublicationState.absent: {PublicationState.published},
    PublicationState.published: {
      PublicationState.superseded,
      PublicationState.retracted,
    },
    PublicationState.superseded: {},
    PublicationState.retracted: {},
  };

  static bool permitsPlay(PlayState from, PlayState to) =>
      playTransitions[from]!.contains(to);

  static bool permitsReview(ReviewState from, ReviewState to) =>
      reviewTransitions[from]!.contains(to);

  static bool permitsPublication(PublicationState from, PublicationState to) =>
      publicationTransitions[from]!.contains(to);
}
