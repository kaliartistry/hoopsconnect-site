import 'package:flutter/material.dart';
import '../../models/user_model.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2E7D32); // green-800
  static const Color primaryLight = Color(0xFFE8F5E9); // green-50
  static const Color primaryDark = Color(0xFF1B5E20); // green-900

  static const Color accent = Color(0xFFF9A825); // gold (yellow-800)
  static const Color accentLight = Color(0xFFFFF8E1); // yellow-50

  static const Color urgent = Color(0xFFEF4444); // red-500
  static const Color urgentBg = Color(0xFFFEF2F2); // red-50
  static const Color ack = Color(0xFFF59E0B); // amber-500
  static const Color ackBg = Color(0xFFFFFBEB); // amber-50
  static const Color success = Color(0xFF22C55E); // green-500
  static const Color successBg = Color(0xFFF0FDF4); // green-50

  static const Color statHighlight = Color(0xFF059669); // emerald-600
  static const Color statBg = Color(0xFFECFDF5); // emerald-50

  static const Color darkBg = Color(0xFF111827); // gray-900
  static const Color textPrimary = Color(0xFF111827); // gray-900
  static const Color textSecondary = Color(0xFF6B7280); // gray-500
  static const Color textMuted = Color(0xFF9CA3AF); // gray-400
  static const Color border = Color(0xFFE5E7EB); // gray-200
  static const Color surface = Color(0xFFF9FAFB); // gray-50

  // Medals (leaderboard)
  static const Color medalGold = Color(0xFFD97706);
  static const Color medalSilver = Color(0xFF6B7280);
  static const Color medalBronze = Color(0xFFB45309);

  // Brand
  static const Color google = Color(0xFF4285F4);

  // Info / blue tones
  static const Color info = Color(0xFF2563EB);
  static const Color infoDark = Color(0xFF1E40AF);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color infoBorder = Color(0xFFBFDBFE);

  // Role badges
  static const Color roleSuperAdmin = Color(0xFF7C3AED);
  static const Color roleRep = Color(0xFF2563EB);

  static Color divisionColor(String? divisionId) {
    final normalized = (divisionId ?? '').toLowerCase();
    if (normalized.contains('women')) return info;
    if (normalized.contains('premier') || normalized.contains('nbl')) {
      return accent;
    }
    return primary;
  }

  static Color divisionTint(String? divisionId) =>
      divisionColor(divisionId).withValues(alpha: 0.12);

  static Color divisionBorder(String? divisionId) =>
      divisionColor(divisionId).withValues(alpha: 0.28);
}

class AppSizes {
  AppSizes._();

  static const double paddingSm = 8.0;
  static const double paddingMd = 16.0;
  static const double paddingLg = 24.0;
  static const double paddingXl = 32.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  static const double iconSm = 16.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
}

class AppDefaults {
  AppDefaults._();

  // Association
  static const String defaultAssociationId = 'jba';
  static const UserRole defaultSignupRole = UserRole.fan;
  static const String ownerEmail = 'kalimccarthy@gmail.com';

  // Event / ack types
  static const String eventTypeGame = 'game';
  static const String ackScopeAll = 'all';

  // Schedule
  static const String byeTeamId = '__BYE__';
  static const int defaultRounds = 2;
  static const Set<int> defaultGameDays = {2, 4, 6}; // Tue, Thu, Sat
  static const TimeOfDay defaultGameTime = TimeOfDay(hour: 19, minute: 0);
  static const TimeOfDay defaultAckDeadlineTime = TimeOfDay(
    hour: 18,
    minute: 0,
  );
  static const TimeOfDay altGameTimeSlot = TimeOfDay(hour: 21, minute: 0);

  // Durations
  static const Duration ackDeadlineDefault = Duration(days: 3);
  static const Duration ackPickerMaxFuture = Duration(days: 90);
  static const Duration datePickerMaxFuture = Duration(days: 365);
  static const Duration scheduleStartOffset = Duration(days: 7);
  static const Duration scheduleEndOffset = Duration(days: 120);
  static const Duration seasonEndOffset = Duration(days: 150);
  static const Duration addGameDateOffset = Duration(days: 1);
  static const Duration defaultGameDuration = Duration(hours: 2);

  // Invite codes
  static const int inviteCodeDefaultDaysValid = 30;
  static const List<int> inviteCodeDaysValidOptions = [7, 14, 30, 60, 90];
}
