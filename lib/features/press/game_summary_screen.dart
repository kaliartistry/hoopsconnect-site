import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_state_message.dart';
import '../../features/public/public_game_detail_screen.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';

/// Media recap route backed by the same public result version used for shares
/// and CSV. It never falls back to a private gameStats document.
class GameSummaryScreen extends ConsumerWidget {
  final String eventId;

  const GameSummaryScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);
    final canExport =
        ref.watch(currentUserProvider).valueOrNull?.canExportStats ?? false;

    return snapshotAsync.when(
      loading: () => const _MediaResultState(
        child: AppLoadingState(label: 'Loading published result'),
      ),
      error: (_, _) => _MediaResultState(
        child: AppStateMessage(
          title: 'Published result could not be loaded',
          message:
              'The media view did not fall back to private stats. Check your connection and try again.',
          tone: AppStateTone.error,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(publicLeagueSnapshotProvider),
        ),
      ),
      data: (snapshot) {
        if (snapshot == null) {
          return _MediaResultState(
            child: AppStateMessage(
              title: 'Published result unavailable',
              message:
                  'There is no active public snapshot for this media result.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(publicLeagueSnapshotProvider),
            ),
          );
        }
        if (snapshot.version.state != PublicReleaseState.published) {
          return _MediaResultState(
            child: AppStateMessage(
              title: snapshot.version.state == PublicReleaseState.retracted
                  ? 'Published result withdrawn'
                  : 'Published result unavailable',
              message:
                  'Stale result details, recaps, shares, and exports are not shown.',
              tone: AppStateTone.warning,
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(publicLeagueSnapshotProvider),
            ),
          );
        }
        final detail = snapshot.gameDetail(eventId);
        if (detail == null) {
          return const _MediaResultState(
            child: AppStateMessage(
              title: 'Game not published',
              message:
                  'This game is not included in the current public result version.',
            ),
          );
        }
        return PublicGameDetailScreen(
          snapshot: snapshot,
          detail: detail,
          canExportStats: canExport,
        );
      },
    );
  }
}

class _MediaResultState extends StatelessWidget {
  final Widget child;

  const _MediaResultState({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Game summary')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: child,
      ),
    ),
  );
}
