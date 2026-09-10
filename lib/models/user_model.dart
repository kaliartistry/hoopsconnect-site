import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { superAdmin, admin, rep, media, statistician, press, fan }

/// User notification preference flags.
/// All default to true so new users receive everything.
class NotificationPrefs {
  final bool ackReminders;
  final bool statReminders;
  final bool newPosts;

  const NotificationPrefs({
    this.ackReminders = true,
    this.statReminders = true,
    this.newPosts = true,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPrefs();
    return NotificationPrefs(
      ackReminders: map['ackReminders'] as bool? ?? true,
      statReminders: map['statReminders'] as bool? ?? true,
      newPosts:
          (map['newPosts'] as bool?) ??
          (map['newPostNotifications'] as bool?) ??
          true,
    );
  }

  Map<String, dynamic> toMap() => {
    'ackReminders': ackReminders,
    'statReminders': statReminders,
    'newPosts': newPosts,
  };

  NotificationPrefs copyWith({
    bool? ackReminders,
    bool? statReminders,
    bool? newPosts,
  }) {
    return NotificationPrefs(
      ackReminders: ackReminders ?? this.ackReminders,
      statReminders: statReminders ?? this.statReminders,
      newPosts: newPosts ?? this.newPosts,
    );
  }
}

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? phone;
  final String associationId;
  final String? teamId;
  final UserRole role;
  final String? divisionId;
  final List<String> fcmTokens;
  final NotificationPrefs notificationPrefs;
  final Set<String> capabilities;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.phone,
    required this.associationId,
    this.teamId,
    required this.role,
    this.divisionId,
    this.fcmTokens = const [],
    this.notificationPrefs = const NotificationPrefs(),
    this.capabilities = const {},
  });

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      id: doc.id,
      email: data['email'] as String,
      displayName: data['displayName'] as String,
      phone: data['phone'] as String?,
      associationId: data['associationId'] as String,
      teamId: data['teamId'] as String?,
      role: UserRole.values.byName(data['role'] as String),
      divisionId: data['divisionId'] as String?,
      fcmTokens: List<String>.from(data['fcmTokens'] ?? []),
      notificationPrefs: NotificationPrefs.fromMap(
        data['notificationPrefs'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'phone': phone,
      'associationId': associationId,
      'teamId': teamId,
      'role': role.name,
      'divisionId': divisionId,
      'fcmTokens': fcmTokens,
      'notificationPrefs': notificationPrefs.toMap(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? phone,
    String? associationId,
    String? teamId,
    UserRole? role,
    String? divisionId,
    List<String>? fcmTokens,
    NotificationPrefs? notificationPrefs,
    Set<String>? capabilities,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      associationId: associationId ?? this.associationId,
      teamId: teamId ?? this.teamId,
      role: role ?? this.role,
      divisionId: divisionId ?? this.divisionId,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  bool hasCapability(String capability) => capabilities.contains(capability);

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;
  bool get isRep => role == UserRole.rep;

  /// True for both media and press roles (merged into one "Media" role).
  bool get isMedia => role == UserRole.media || role == UserRole.press;
  bool get isStatistician => role == UserRole.statistician;

  /// Alias for [isMedia] — press and media are the same role.
  bool get isPress => isMedia;
  bool get isFan => role == UserRole.fan;

  // Composite permission getters
  bool get canAccessAdminPanel =>
      hasCapability('association.manage') ||
      hasCapability('teams.manage') ||
      hasCapability('posts.manage') ||
      hasCapability('stats.approve');
  bool get canManageUsers => hasCapability('members.manage');
  bool get canManageAssociation => hasCapability('association.manage');
  bool get canManageDivisions => hasCapability('association.manage');
  bool get canManageSchedule => hasCapability('schedule.manage');
  bool get canManageInviteCodes => hasCapability('invites.manage');
  bool get canEnterStats => hasCapability('stats.enter');
  bool get canApproveStats => hasCapability('stats.approve');
  bool get canCreatePost => hasCapability('posts.create');
  bool get canEditAnyPost => hasCapability('posts.manage');
  bool get canPinUrgentAck => hasCapability('posts.manage');
  bool get canViewBoard => hasCapability('posts.internal.read');
  bool get canExportStats => hasCapability('stats.export');
  bool get canAccessPressTools => hasCapability('press.read');
  bool get canCompareHeadToHead => hasCapability('posts.internal.read');
}
