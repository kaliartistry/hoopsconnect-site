import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../models/standings_model.dart';
import '../../providers/association_branding_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/standings_providers.dart';

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({super.key});

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final seasonId = ref.watch(activeSeasonIdProvider).value;
    final selectedDivision = ref.watch(selectedDivisionProvider);
    final selectedDivisionId = ref.watch(selectedDivisionIdProvider);
    final standingsAsync = seasonId == null
        ? null
        : ref.watch(
            standingsStreamProvider((
              seasonId: seasonId,
              divisionId: selectedDivisionId,
            )),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Standings'),
        actions: [
          _StandingsShareButton(
            standings: standingsAsync?.valueOrNull?.standings ?? const [],
            divisionName: selectedDivision?.name,
          ),
        ],
      ),
      body: standingsAsync == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : standingsAsync.when(
              data: (standings) {
                if (standings == null || standings.standings.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 48,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No standings data',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedDivision == null
                              ? 'Standings will appear after games are played'
                              : 'Standings for ${selectedDivision.name} will appear after games are played',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return _StandingsTable(standings: standings.standings);
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
    );
  }
}

class _StandingsShareButton extends ConsumerWidget {
  final List<TeamStanding> standings;
  final String? divisionName;

  const _StandingsShareButton({
    required this.standings,
    required this.divisionName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (standings.isEmpty) return const SizedBox.shrink();
    final branding = ref.watch(effectiveAssociationBrandingProvider);
    return IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: 'Share standings',
      onPressed: () => showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.standings(
          standings: standings,
          branding: branding,
          divisionName: divisionName,
        ),
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  final List<TeamStanding> standings;

  const _StandingsTable({required this.standings});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Table header
          Container(
            color: AppColors.darkBg,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: const Row(
              children: [
                // Rank
                SizedBox(
                  width: 28,
                  child: Text(
                    '#',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Team name
                Expanded(
                  child: Text(
                    'TEAM',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // W
                SizedBox(
                  width: 32,
                  child: Text(
                    'W',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // L
                SizedBox(
                  width: 32,
                  child: Text(
                    'L',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // PCT
                SizedBox(
                  width: 44,
                  child: Text(
                    'PCT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // GB
                SizedBox(
                  width: 36,
                  child: Text(
                    'GB',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // STRK
                SizedBox(
                  width: 38,
                  child: Text(
                    'STRK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // L5
                SizedBox(
                  width: 38,
                  child: Text(
                    'L5',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Team rows
          ...standings.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final team = entry.value;
            final isEven = rank.isEven;

            return GestureDetector(
              onTap: () => context.push('/team/${team.teamId}'),
              child: Container(
                color: isEven ? AppColors.surface : Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    // Rank
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: rank <= 3
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Team name
                    Expanded(
                      child: Text(
                        team.teamName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // W
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${team.wins}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // L
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${team.losses}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // PCT
                    SizedBox(
                      width: 44,
                      child: Text(
                        team.pct.toStringAsFixed(3).replaceFirst('0.', '.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // GB
                    SizedBox(
                      width: 36,
                      child: Text(
                        team.gb == 0 ? '-' : team.gb.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // STRK
                    SizedBox(
                      width: 38,
                      child: Text(
                        team.streak,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: team.streak.startsWith('W')
                              ? AppColors.success
                              : team.streak.startsWith('L')
                              ? AppColors.urgent
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                    // L10
                    SizedBox(
                      width: 38,
                      child: Text(
                        team.lastTen,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Point differential footer
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
                SizedBox(width: 6),
                Text(
                  'Tap a team for roster & details',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
