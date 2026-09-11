import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/league_workflow_capability.dart';
import 'auth_providers.dart';

final leagueWorkflowCapabilityProvider =
    StreamProvider<LeagueWorkflowCapability?>((ref) {
      final associationId = ref.watch(currentAssociationIdProvider);
      if (associationId == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .doc('associations/$associationId/leagueWorkflowControl/current')
          .snapshots()
          .map((snapshot) {
            final data = snapshot.data();
            if (!snapshot.exists || data == null) return null;
            return LeagueWorkflowCapability.fromMap(
              data,
              expectedAssociationId: associationId,
            );
          });
    });
