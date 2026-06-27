import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/event_model.dart';
import '../../../models/game_stats_model.dart';
import '../../../models/team_model.dart';

class GameCard extends StatelessWidget {
  final EventModel event;
  final List<TeamModel> teams;
  final GameStatsModel? gameStats;
  final VoidCallback? onTap;
  final ValueChanged<String>? onTeamTap;

  const GameCard({
    super.key,
    required this.event,
    required this.teams,
    this.gameStats,
    this.onTap,
    this.onTeamTap,
  });

  String _teamName(String teamId) {
    final team = teams.where((t) => t.id == teamId).firstOrNull;
    return team?.name ?? 'TBD';
  }

  String _divisionLabel(String divisionId) {
    return divisionId
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Widget _buildTeamName(
    String teamId,
    String teamName, {
    TextAlign textAlign = TextAlign.start,
  }) {
    final text = Text(
      teamName,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: onTeamTap != null ? AppColors.primaryDark : AppColors.textPrimary,
        decoration: onTeamTap != null ? TextDecoration.underline : TextDecoration.none,
        decorationColor:
            onTeamTap != null ? AppColors.primaryDark : Colors.transparent,
      ),
    );

    if (onTeamTap == null || teamId.isEmpty) return text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTeamTap!(teamId),
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!event.isGame) {
      return _NonGameCard(event: event, onTap: onTap);
    }

    final homeTeamId =
        gameStats?.homeTeamId ?? (event.teamIds.isNotEmpty ? event.teamIds[0] : '');
    final awayTeamId =
        gameStats?.awayTeamId ?? (event.teamIds.length > 1 ? event.teamIds[1] : '');

    final homeName = gameStats?.homeTeamName ?? _teamName(homeTeamId);
    final awayName = gameStats?.awayTeamName ?? _teamName(awayTeamId);

    final isCompleted = event.statsStatus == StatsStatus.approved ||
        (gameStats != null && gameStats!.status == GameStatsStatus.approved);
    final isLive = gameStats != null &&
        gameStats!.status == GameStatsStatus.submitted &&
        event.statsStatus != StatsStatus.approved;

    final statusText = isCompleted
        ? 'FINAL'
        : isLive
            ? 'LIVE'
            : DateFormat('h:mm a').format(event.startTime);

    final statusColor = isCompleted
        ? AppColors.success
        : isLive
            ? AppColors.ack
            : Colors.white.withValues(alpha: 0.7);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Dark header with status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppColors.darkBg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (event.divisionId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.divisionTint(event.divisionId),
                        border: Border.all(
                          color: AppColors.divisionBorder(event.divisionId),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _divisionLabel(event.divisionId!),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.divisionColor(event.divisionId),
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppColors.success.withValues(alpha: 0.15)
                          : isLive
                              ? AppColors.ack.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Teams and score
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Home team
                  Expanded(
                    child: _buildTeamName(
                      homeTeamId,
                      homeName,
                    ),
                  ),

                  // Score or VS
                  if (isCompleted || isLive)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${gameStats?.homeScore ?? 0}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? AppColors.textPrimary
                                : AppColors.ack,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '-',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        Text(
                          '${gameStats?.awayScore ?? 0}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isCompleted
                                ? AppColors.textPrimary
                                : AppColors.ack,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),

                  // Away team
                  Expanded(
                    child: _buildTeamName(
                      awayTeamId,
                      awayName,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),

            // Location row
            if (event.location != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.location!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card for non-game events (deadlines, meetings, etc.)
class _NonGameCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback? onTap;

  const _NonGameCard({required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(event.startTime);
    final isDeadline = event.type == 'deadline';

    final Color accentColor;
    if (isDeadline) {
      accentColor = AppColors.urgent;
    } else {
      accentColor = AppColors.textMuted;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (event.location != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.location!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDeadline ? AppColors.urgentBg : AppColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.type.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
