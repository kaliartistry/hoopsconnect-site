import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../models/game_stats_model.dart';

class MilestoneDetector {
  /// Detect notable achievements in a single game performance.
  static List<String> detectGameMilestones(PlayerStatLine line) {
    final milestones = <String>[];

    // Scoring milestones
    if (line.pts >= 30) {
      milestones.add('30+ PTS');
    } else if (line.pts >= 20) {
      milestones.add('20+ PTS');
    }

    // Rebound milestone
    if (line.reb >= 10) milestones.add('10+ REB');

    // Assist milestone
    if (line.ast >= 10) milestones.add('10+ AST');

    // Steal milestone
    if (line.stl >= 5) milestones.add('5+ STL');

    // Block milestone
    if (line.blk >= 5) milestones.add('5+ BLK');

    // Double/Triple-double detection
    int doubles = 0;
    if (line.pts >= 10) doubles++;
    if (line.reb >= 10) doubles++;
    if (line.ast >= 10) doubles++;
    if (line.stl >= 10) doubles++;
    if (line.blk >= 10) doubles++;

    if (doubles >= 3) {
      milestones.add('Triple-Double');
    } else if (doubles >= 2) {
      milestones.add('Double-Double');
    }

    return milestones;
  }

  /// Build a small colored chip / badge widget for a milestone.
  static Widget milestoneBadge(String milestone) {
    Color bgColor;
    Color textColor;

    if (milestone == 'Triple-Double') {
      bgColor = AppColors.accent;
      textColor = Colors.black87;
    } else if (milestone == 'Double-Double') {
      bgColor = AppColors.statHighlight;
      textColor = Colors.white;
    } else if (milestone.contains('PTS')) {
      bgColor = AppColors.primary;
      textColor = Colors.white;
    } else if (milestone.contains('REB')) {
      bgColor = AppColors.info;
      textColor = Colors.white;
    } else if (milestone.contains('AST')) {
      bgColor = AppColors.success;
      textColor = Colors.white;
    } else if (milestone.contains('STL')) {
      bgColor = AppColors.medalBronze;
      textColor = Colors.white;
    } else if (milestone.contains('BLK')) {
      bgColor = AppColors.urgent;
      textColor = Colors.white;
    } else {
      bgColor = AppColors.textMuted;
      textColor = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        milestone,
        style: TextStyle(
          color: textColor,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
