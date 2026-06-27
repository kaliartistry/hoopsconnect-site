import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/live_stats_providers.dart';

/// Center column action buttons for the live stat-taking screen (340px wide).
class ActionPanel extends ConsumerWidget {
  final void Function(String message)? onAlert;
  final bool showKeyHints;

  const ActionPanel({super.key, this.onAlert, this.showKeyHints = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(liveGameProvider);
    final notifier = ref.read(liveGameProvider.notifier);

    final selected = gameState.selectedPlayer;
    final hasSelection = selected != null;
    final isOnCourt = selected?.onCourt ?? false;
    final isFouledOut = selected?.isFouledOut ?? false;

    // Stat buttons are enabled only when an on-court, non-fouled-out player
    // is selected.
    final canAct = hasSelection && isOnCourt && !isFouledOut;
    // Fouled-out on-court players can only SUB.
    final canSub = hasSelection && isOnCourt;
    final canUndo = gameState.plays.isNotEmpty;

    void record(String action) {
      final result = notifier.recordStat(action);
      if (result != null) {
        onAlert?.call(result);
      }
    }

    // Use intrinsic width when placed inside Expanded (mobile layout),
    // fixed 340px when in the 3-column Row (tablet/desktop).
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Container(
      width: isMobile ? null : 340,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border.symmetric(
          vertical: BorderSide(color: AppColors.border),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Selected player indicator
            _SelectedIndicator(gameState: gameState),
            const SizedBox(height: 6),

            // ── Scoring ──
            _SectionLabel('Scoring'),
            const SizedBox(height: 4),
            // 2PT row
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: '2PT',
                    subLabel: '\u2713 make +2',
                    tier: 1,
                    isMake: true,
                    enabled: canAct,
                    onTap: () => record('2PT_MAKE'),
                    keyHint: showKeyHints ? '[2]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: '2PT',
                    subLabel: '\u2717 miss',
                    tier: 1,
                    isMake: false,
                    enabled: canAct,
                    onTap: () => record('2PT_MISS'),
                    keyHint: showKeyHints ? '[\u21e72]' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 3PT row
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: '3PT',
                    subLabel: '\u2713 make +3',
                    tier: 1,
                    isMake: true,
                    enabled: canAct,
                    onTap: () => record('3PT_MAKE'),
                    keyHint: showKeyHints ? '[3]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: '3PT',
                    subLabel: '\u2717 miss',
                    tier: 1,
                    isMake: false,
                    enabled: canAct,
                    onTap: () => record('3PT_MISS'),
                    keyHint: showKeyHints ? '[\u21e73]' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // FT row
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'FT',
                    subLabel: '\u2713 make +1',
                    tier: 1,
                    isMake: true,
                    enabled: canAct,
                    onTap: () => record('FT_MAKE'),
                    height: 48,
                    keyHint: showKeyHints ? '[F]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: 'FT',
                    subLabel: '\u2717 miss',
                    tier: 1,
                    isMake: false,
                    enabled: canAct,
                    onTap: () => record('FT_MISS'),
                    height: 48,
                    keyHint: showKeyHints ? '[\u21e7F]' : null,
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.border),
            ),

            // ── Rebounds ──
            _SectionLabel('Rebounds'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'OREB',
                    tier: 2,
                    isReb: true,
                    enabled: canAct,
                    onTap: () => record('OREB'),
                    keyHint: showKeyHints ? '[\u21e7R]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: 'DREB',
                    tier: 2,
                    isReb: true,
                    enabled: canAct,
                    onTap: () => record('DREB'),
                    keyHint: showKeyHints ? '[R]' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Stats ──
            _SectionLabel('Stats'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'AST',
                    tier: 2,
                    enabled: canAct,
                    onTap: () => record('AST'),
                    keyHint: showKeyHints ? '[A]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: 'TO',
                    tier: 2,
                    enabled: canAct,
                    onTap: () => record('TO'),
                    keyHint: showKeyHints ? '[T]' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Tier 3 ──
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'FLS',
                    tier: 3,
                    enabled: canAct,
                    onTap: () => record('FLS'),
                    keyHint: showKeyHints ? '[X]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: 'STL',
                    tier: 3,
                    enabled: canAct,
                    onTap: () => record('STL'),
                    keyHint: showKeyHints ? '[S]' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    label: 'BLK',
                    tier: 3,
                    enabled: canAct,
                    onTap: () => record('BLK'),
                    keyHint: showKeyHints ? '[B]' : null,
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.border),
            ),

            // ── Control ──
            Row(
              children: [
                Expanded(
                  child: _ControlButton(
                    label: 'SUB',
                    isSub: true,
                    isActive: gameState.subMode,
                    enabled: canSub,
                    onTap: () {
                      if (gameState.subMode) {
                        notifier.cancelSub();
                      } else {
                        notifier.startSub();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ControlButton(
                    label: 'UNDO',
                    isSub: false,
                    enabled: canUndo,
                    onTap: () => notifier.undo(),
                    keyHint: showKeyHints ? '[Z]' : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedIndicator extends StatelessWidget {
  final dynamic gameState;
  const _SelectedIndicator({required this.gameState});

  @override
  Widget build(BuildContext context) {
    final isSubMode = gameState.subMode && gameState.subOutPlayerId != null;
    final selected = gameState.selectedPlayer;

    Widget content;
    if (isSubMode) {
      final outPlayer = gameState.players[gameState.subOutPlayerId];
      content = RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          children: [
            const TextSpan(text: 'Sub out '),
            TextSpan(
              text: outPlayer?.name ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFFEA580C),
              ),
            ),
            const TextSpan(text: ' — tap bench player'),
          ],
        ),
      );
    } else if (selected != null) {
      final isHome = selected.teamId == gameState.homeTeamId;
      content = Text(
        '#${selected.num} ${selected.name}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: isHome ? const Color(0xFFEA580C) : const Color(0xFF2563EB),
        ),
        textAlign: TextAlign.center,
      );
    } else {
      content = const Text(
        'Tap a player to begin',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        textAlign: TextAlign.center,
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String? subLabel;
  final int tier; // 1, 2, 3
  final bool isMake;
  final bool isReb;
  final bool enabled;
  final VoidCallback onTap;
  final double? height;
  final String? keyHint;

  const _ActionButton({
    required this.label,
    this.subLabel,
    required this.tier,
    this.isMake = false,
    this.isReb = false,
    required this.enabled,
    required this.onTap,
    this.height,
    this.keyHint,
  });

  @override
  Widget build(BuildContext context) {
    final double minHeight;
    final double fontSize;

    switch (tier) {
      case 1:
        minHeight = height ?? 56;
        fontSize = 15;
      case 2:
        minHeight = 48;
        fontSize = 14;
      default:
        minHeight = 38;
        fontSize = 13;
    }

    Color bg;
    Color fg;
    Color border;

    if (tier == 1 && isMake) {
      bg = const Color(0xFFEA580C);
      fg = Colors.white;
      border = const Color(0xFFC2410C);
    } else if (tier == 1 && !isMake) {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      border = const Color(0xFFFECACA);
    } else if (tier == 2 && isReb) {
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFC2410C);
      border = const Color(0xFFFDBA74);
    } else if (tier == 2) {
      bg = const Color(0xFFF8FAFC);
      fg = AppColors.textPrimary;
      border = const Color(0xFFCBD5E1);
    } else {
      bg = const Color(0xFFFAFAFA);
      fg = AppColors.textSecondary;
      border = const Color(0xFFE5E5E5);
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.3,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
            boxShadow: tier == 1 && isMake
                ? [
                    BoxShadow(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  if (subLabel != null)
                    Text(
                      subLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
              if (keyHint != null)
                Positioned(
                  top: 2,
                  right: 4,
                  child: Text(
                    keyHint!,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final bool isSub;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;
  final String? keyHint;

  const _ControlButton({
    required this.label,
    required this.isSub,
    this.isActive = false,
    required this.enabled,
    required this.onTap,
    this.keyHint,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    if (isSub) {
      if (isActive) {
        bg = const Color(0xFF16A34A);
        fg = Colors.white;
        border = const Color(0xFF16A34A);
      } else {
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF15803D);
        border = const Color(0xFF86EFAC);
      }
    } else {
      // Undo
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      border = const Color(0xFFFECACA);
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.3,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (keyHint != null)
                Positioned(
                  top: 2,
                  right: 4,
                  child: Text(
                    keyHint!,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
