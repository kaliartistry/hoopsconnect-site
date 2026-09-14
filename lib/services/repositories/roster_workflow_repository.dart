import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../../models/roster_workflow_model.dart';
import '../../models/user_model.dart';

typedef RosterCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> data,
    );

enum RosterClientAuthority { manage, propose, denied }

RosterClientAuthority rosterClientAuthority({
  required UserModel user,
  required String teamId,
}) {
  if (user.hasCapability('teams.manage') ||
      user.hasCapability('rosters.manage')) {
    return RosterClientAuthority.manage;
  }
  // V2 grant scope is intentionally server-private. The membership-level
  // capability may expose the action, but only the callable resolves and
  // authorizes the exact canonical team entry. Legacy representatives retain
  // their explicit team-ID precheck for a clearer local denial.
  if (user.hasCapability('rosters.assert') ||
      (user.hasCapability('teams.represent') && user.teamId == teamId)) {
    return RosterClientAuthority.propose;
  }
  return RosterClientAuthority.denied;
}

class RosterWorkflowException implements Exception {
  final String code;
  final String message;

  const RosterWorkflowException(this.code, this.message);

  @override
  String toString() => message;
}

class RosterWorkflowRepository {
  final FirebaseFunctions? _functions;
  final RosterCallable? _callable;
  final Random _random;

  RosterWorkflowRepository({
    FirebaseFunctions? functions,
    RosterCallable? callable,
    Random? random,
  }) : _functions = functions,
       _callable = callable,
       _random = random ?? Random.secure();

  String newOperationId({DateTime? now}) {
    final entropy = List.generate(
      12,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'roster_${(now ?? DateTime.now()).toUtc().microsecondsSinceEpoch}_$entropy';
  }

  Future<RosterWorkspace> loadWorkspace({
    required UserModel user,
    required String teamId,
    required String seasonId,
  }) async {
    _requireClientAccess(user: user, teamId: teamId);
    final data = await _invoke('getRosterWorkspace', {
      'schemaVersion': RosterChangeRequest.schemaVersion,
      'teamId': teamId,
      'seasonId': seasonId,
    });
    return RosterWorkspace.fromMap(data);
  }

  Future<RosterChangeReceipt> submitChange({
    required UserModel user,
    required RosterChangeRequest request,
  }) async {
    final authority = rosterClientAuthority(user: user, teamId: request.teamId);
    if (authority == RosterClientAuthority.denied) {
      throw const RosterWorkflowException(
        'client-permission-denied',
        'You can only request roster changes for your assigned team.',
      );
    }
    final data = await _invoke(
      'submitRosterChange',
      request.toMap(
        requestedOutcome: authority == RosterClientAuthority.manage
            ? 'apply'
            : 'propose',
      ),
    );
    return RosterChangeReceipt.fromMap(data);
  }

  Future<RosterChangeReceipt> reviewProposal({
    required UserModel user,
    required RosterProposalReviewRequest request,
  }) async {
    if (rosterClientAuthority(user: user, teamId: request.teamId) !=
        RosterClientAuthority.manage) {
      throw const RosterWorkflowException(
        'client-permission-denied',
        'Only a roster administrator can approve or reject this request.',
      );
    }
    final data = await _invoke('reviewRosterProposal', request.toMap());
    return RosterChangeReceipt.fromMap(data);
  }

  void _requireClientAccess({required UserModel user, required String teamId}) {
    if (rosterClientAuthority(user: user, teamId: teamId) ==
        RosterClientAuthority.denied) {
      throw const RosterWorkflowException(
        'client-permission-denied',
        'This roster workspace is outside your assigned team.',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      if (_callable != null) return await _callable(name, data);
      final result = await (_functions ?? FirebaseFunctions.instance)
          .httpsCallable(name)
          .call<Map<Object?, Object?>>(data);
      return result.data.map((key, value) => MapEntry(key.toString(), value));
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        throw const RosterWorkflowException(
          'workflow-unavailable',
          'Roster changes are temporarily unavailable. No change was submitted.',
        );
      }
      if (error.code == 'permission-denied') {
        throw const RosterWorkflowException(
          'permission-denied',
          'Your current league access does not allow this roster change.',
        );
      }
      if (error.code == 'aborted' || error.code == 'failed-precondition') {
        throw const RosterWorkflowException(
          'stale-roster',
          'The roster changed while you were working. Reload it before trying again.',
        );
      }
      throw RosterWorkflowException(
        error.code,
        error.message ?? 'The roster service could not complete this request.',
      );
    }
  }
}
