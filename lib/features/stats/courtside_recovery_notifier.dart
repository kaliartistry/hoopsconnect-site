import 'package:flutter/foundation.dart';

import '../../models/official_stats/domain_contracts.dart';
import '../../services/local_game_journal/courtside_recovery.dart';
import '../../services/local_game_journal/deletion_recovery_models.dart';
import '../../services/local_game_journal/journal_repository.dart';

/// Candidate notifier for a future assigned-game stat-entry provider.
/// It is intentionally not registered in the production provider graph.
final class CourtsideRecoveryNotifier extends ChangeNotifier {
  CourtsideRecoveryNotifier(this.orchestrator) {
    orchestrator.addSnapshotListener(_onSnapshot);
  }

  final CourtsideRecoveryOrchestrator orchestrator;

  CourtsideRecoverySnapshot get snapshot => orchestrator.snapshot;
  bool get productionActivationAllowed => false;

  Future<CourtsideRecoverySnapshot> initialize() => orchestrator.initialize();

  Future<LocalAppendResult> capture(CourtsideCaptureCommand command) =>
      orchestrator.capture(command);

  Future<CourtsideRecoverySnapshot> recoverForeground({DateTime? now}) =>
      orchestrator.recoverForeground(now: now);

  Future<CourtsideRecoverySnapshot> queueRevisionSubmission({
    required DateTime observedAt,
  }) => orchestrator.queueRevisionSubmission(observedAt: observedAt);

  Future<CourtsideRecoverySnapshot> retry(
    String operationId, {
    DateTime? now,
  }) => orchestrator.retryNeedsAttention(operationId, now: now);

  Future<CourtsideRecoverySnapshot> acceptRecoveredReceipt(
    OperationReceiptContract receipt,
  ) => orchestrator.acceptRecoveredReceipt(receipt);

  Future<CourtsideDeletionReconciliationPlan> reconcileDeletion(
    DeviceJournalDeletionManifest manifest,
    LocalDeletionConsent consent,
  ) => orchestrator.reconcileDeletion(manifest, consent);

  void _onSnapshot(CourtsideRecoverySnapshot _) => notifyListeners();

  @override
  void dispose() {
    orchestrator.removeSnapshotListener(_onSnapshot);
    super.dispose();
  }
}
