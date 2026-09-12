import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import 'public_game_detail_screen.dart';
import 'public_player_detail_screen.dart';
import 'public_team_detail_screen.dart';

enum PublicDetailRouteKind { game, team, player }

/// Resolves public detail URLs exclusively from the published public snapshot.
///
/// This keeps refresh/deep-link behavior on the same privacy boundary as taps
/// from the public league screen. A missing ID is a public unavailable state;
/// it never falls through to a similarly named private route.
class PublicDetailRouteScreen extends ConsumerWidget {
  const PublicDetailRouteScreen({
    super.key,
    required this.kind,
    required this.id,
    this.canonicalUri,
  });

  final PublicDetailRouteKind kind;
  final String id;
  final Uri? canonicalUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);
    return snapshotAsync.when(
      loading: () => _RouteState(
        title: _title,
        backLocation: _backLocation,
        child: const AppLoadingState(label: 'Loading published details'),
      ),
      error: (_, _) => _RouteState(
        title: _title,
        backLocation: _backLocation,
        child: AppStateMessage(
          title: 'Published details unavailable',
          message:
              'The public release could not be loaded. No private records were used. Check your connection and try again.',
          tone: AppStateTone.error,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(publicLeagueSnapshotProvider),
        ),
      ),
      data: (snapshot) {
        if (snapshot == null || !snapshot.version.isPublished) {
          return _RouteState(
            title: _title,
            backLocation: _backLocation,
            child: AppStateMessage(
              title: 'Published details unavailable',
              message:
                  'There is no active public release for this link. Previously loaded private or withdrawn data is not shown.',
              tone: AppStateTone.warning,
              actionLabel: 'Open public games',
              onAction: () => context.go(PublicRoutePaths.games),
            ),
          );
        }

        return switch (kind) {
          PublicDetailRouteKind.game => _game(context, snapshot),
          PublicDetailRouteKind.team => _team(context, snapshot),
          PublicDetailRouteKind.player => _player(context, snapshot),
        };
      },
    );
  }

  Widget _game(BuildContext context, PublicLeagueSnapshot snapshot) {
    final detail = snapshot.gameDetail(id);
    if (detail == null) return _missing(context);
    return PublicGameDetailScreen(
      snapshot: snapshot,
      detail: detail,
      canonicalUri: canonicalUri,
    );
  }

  Widget _team(BuildContext context, PublicLeagueSnapshot snapshot) {
    final detail = snapshot.teamDetail(id);
    if (detail == null) return _missing(context);
    return PublicTeamDetailScreen(snapshot: snapshot, detail: detail);
  }

  Widget _player(BuildContext context, PublicLeagueSnapshot snapshot) {
    final detail = snapshot.playerDetail(id);
    if (detail == null) return _missing(context);
    return PublicPlayerDetailScreen(snapshot: snapshot, detail: detail);
  }

  Widget _missing(BuildContext context) => _RouteState(
    title: _title,
    backLocation: _backLocation,
    child: AppStateMessage(
      title: 'Published ${_noun.toLowerCase()} not found',
      message:
          'This link is not part of the current public release. It may be outdated, withdrawn, or unavailable.',
      actionLabel: 'Open public games',
      onAction: () => context.go(PublicRoutePaths.games),
    ),
  );

  String get _title => '$_noun details';

  String get _backLocation => switch (kind) {
    PublicDetailRouteKind.game => PublicRoutePaths.games,
    PublicDetailRouteKind.team => PublicRoutePaths.standings,
    PublicDetailRouteKind.player => PublicRoutePaths.leaders,
  };

  String get _noun => switch (kind) {
    PublicDetailRouteKind.game => 'Game',
    PublicDetailRouteKind.team => 'Team',
    PublicDetailRouteKind.player => 'Player',
  };
}

class _RouteState extends StatelessWidget {
  const _RouteState({
    required this.title,
    required this.backLocation,
    required this.child,
  });

  final String title;
  final String backLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => context.go(backLocation),
        tooltip: 'Back to public league',
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(title),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          child: child,
        ),
      ),
    ),
  );
}
