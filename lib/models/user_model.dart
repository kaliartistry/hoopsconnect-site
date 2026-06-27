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
    );
  }

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
  bool get canAccessAdminPanel => isSuperAdmin || role == UserRole.admin;
  bool get canManageUsers => isSuperAdmin;
  bool get canManageDivisions => isSuperAdmin;
  bool get canManageSchedule => isSuperAdmin;
  bool get canManageInviteCodes => isSuperAdmin;
  bool get canEnterStats =>
      isSuperAdmin || role == UserRole.admin || role == UserRole.statistician;
  bool get canApproveStats => isSuperAdmin || role == UserRole.admin;
  bool get canCreatePost => isSuperAdmin || role == UserRole.admin || isRep;
  bool get canEditAnyPost => isSuperAdmin || role == UserRole.admin;
  bool get canPinUrgentAck => isSuperAdmin || role == UserRole.admin;
  bool get canViewBoard => !isFan;
  bool get canExportStats => isSuperAdmin || role == UserRole.admin || isMedia;
  bool get canAccessPressTools => isMedia || isAdmin;
  bool get canCompareHeadToHead => !isFan;
}
