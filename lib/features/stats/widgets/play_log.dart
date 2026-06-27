import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/live_stats_providers.dart';
import '../live_stats_state.dart';

/// All editable stat actions (excludes SUB which can only be deleted).
const _editableActions = <String, String>{
  '2PT_MAKE': '2PT Made',
  '2PT_MISS': '2PT Missed',
  '3PT_MAKE': '3PT Made',
  '3PT_MISS': '3PT Missed',
  'FT_MAKE': 'FT Made',
  'FT_MISS': 'FT Missed',
  'OREB': 'Off. Rebound',
  'DREB': 'Def. Rebound',
  'AST': 'Assist',
  'STL': 'Steal',
  'BLK': 'Block',
  'TO': 'Turnover',
  'FLS': 'Foul',
};

/// Play-by-play log list, newest at top.
/// Each play is tappable to edit or delete it.
class PlayLog extends ConsumerWidget {
  const PlayLog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(liveGameProvider);
    final plays = gameState.plays;

    if (plays.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Game events will appear here',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: plays.length,
      itemBuilder: (context, index) {
        final play = plays[index];
        final isHome = play.teamId == gameState.homeTeamId;

        Color ptsColor;
        String ptsLabel;
        if (play.isMiss) {
          ptsColor = AppColors.textMuted;
          ptsLabel = 'MISS';
        } else if ((play.pointsScored ?? 0) > 0) {
          ptsColor = isHome ? const Color(0xFFEA580C) : const Color(0xFF2563EB);
          final teamName =
              isHome ? gameState.homeTeamName : gameState.awayTeamName;
          ptsLabel = '$teamName +${play.pointsScored}';
        } else if (play.type == 'sub') {
          ptsColor = const Color(0xFF16A34A);
          ptsLabel = isHome ? gameState.homeTeamName : gameState.awayTeamName;
        } else {
          ptsLabel = '';
          ptsColor = AppColors.textMuted;
        }

        final isSub = play.type == 'sub';
        final textColor = play.isMiss
            ? AppColors.textMuted
            : (isSub ? const Color(0xFF16A34A) : AppColors.textPrimary);

        return InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _showPlayOptions(context, ref, index, play),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                // Time + quarter
                SizedBox(
                  width: 70,
                  child: Text(
                    '${play.clockFormatted} \u00b7 Q${play.quarter}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),

                // Play detail
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: textColor),
                      children: [
                        TextSpan(
                          text: '#${play.playerNum} ${play.playerName}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontStyle: isSub ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        TextSpan(
                          text: ' \u2014 ${play.description}',
                          style: TextStyle(
                            fontStyle: isSub ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Points label
                if (ptsLabel.isNotEmpty)
                  SizedBox(
                    width: 90,
                    child: Text(
                      ptsLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: ptsColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // Edit hint icon
                const SizedBox(width: 4),
                const Icon(
                  Icons.more_vert,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────── Bottom Sheet ─────────────────────────────

  void _showPlayOptions(
    BuildContext context,
    WidgetRef ref,
    int index,
    GamePlay play,
  ) {
    final isSub = play.type == 'sub';
    final playerLabel = '#${play.playerNum} ${play.playerName}';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '$playerLabel \u2014 ${play.description}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Divider(),

                // Delete option
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete This Play',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDelete(context, ref, index, play);
                  },
                ),

                // Change-to option (only for non-SUB plays)
                if (!isSub)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined,
                        color: Color(0xFFEA580C)),
                    title: const Text('Change To...'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showChangeToSheet(context, ref, index, play);
                    },
                  ),

                // Cancel
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────── Delete Confirmation ──────────────────────

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int index,
    GamePlay play,
  ) {
    final playerLabel = '#${play.playerNum} ${play.playerName}';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Play?'),
        content: Text('Remove $playerLabel \u2014 ${play.description}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(liveGameProvider.notifier).deletePlay(index);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted: $playerLabel \u2014 ${play.description}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────── Change To Sheet ─────────────────────────

  void _showChangeToSheet(
    BuildContext context,
    WidgetRef ref,
    int index,
    GamePlay play,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.7,
            builder: (_, controller) {
              // Build list excluding the current action so you don't
              // "change" to the same thing.
              final actions = _editableActions.entries
                  .where((e) => e.key != play.action)
                  .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Change "#${play.playerNum} ${play.playerName} \u2014 ${play.description}" to:',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      itemCount: actions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final entry = actions[i];
                        return ListTile(
                          title: Text(entry.value),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            final alert = ref
                                .read(liveGameProvider.notifier)
                                .editPlay(index, entry.key);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Changed to: ${entry.value}',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            // Handle foul alerts from edit
                            if (alert != null &&
                                alert.startsWith('FOUL_OUT:')) {
                              final pid = alert.substring(9);
                              final name = ref
                                      .read(liveGameProvider)
                                      .players[pid]
                                      ?.name ??
                                  '';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$name has fouled out!',
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } else if (alert != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(alert),
                                  backgroundColor: Colors.orange,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
