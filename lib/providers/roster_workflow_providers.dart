import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/roster_workflow_model.dart';
import '../services/repositories/roster_workflow_repository.dart';
import 'auth_providers.dart';
import 'league_workflow_providers.dart';

final rosterWorkflowRepositoryProvider = Provider(
  (ref) => RosterWorkflowRepository(),
);

final rosterWorkspaceProvider =
    FutureProvider.family<RosterWorkspace, ({String teamId, String seasonId})>((
      ref,
      target,
    ) async {
      final user = ref.watch(currentUserProvider).valueOrNull;
      if (user == null) {
        throw const RosterWorkflowException(
          'unauthenticated',
          'Sign in again to manage this roster.',
        );
      }
      final workflow = ref.watch(leagueWorkflowCapabilityProvider).valueOrNull;
      if (workflow?.rosterEnabled != true ||
          workflow?.activeSeasonId != target.seasonId) {
        throw const RosterWorkflowException(
          'workflow-unavailable',
          'Roster changes are not active yet. No change was submitted.',
        );
      }
      return ref
          .watch(rosterWorkflowRepositoryProvider)
          .loadWorkspace(
            user: user,
            teamId: target.teamId,
            seasonId: target.seasonId,
          );
    });
