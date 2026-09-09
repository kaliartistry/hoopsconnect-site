import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/auth_incarnation/auth_incarnation_session_gate_v2.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'contracts/auth_incarnation/v2/contract_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  AuthIncarnationSessionEventV2 event(String value) => switch (value) {
    'authObserved' => AuthIncarnationSessionEventV2.authObserved,
    'proofReady' => AuthIncarnationSessionEventV2.proofReady,
    'refreshRequired' => AuthIncarnationSessionEventV2.refreshRequired,
    'proofLost' => AuthIncarnationSessionEventV2.proofLost,
    'lifecycleDeleting' => AuthIncarnationSessionEventV2.lifecycleDeleting,
    'lifecycleDeleted' => AuthIncarnationSessionEventV2.lifecycleDeleted,
    'accountSwitchStarted' =>
      AuthIncarnationSessionEventV2.accountSwitchStarted,
    'signedOut' => AuthIncarnationSessionEventV2.signedOut,
    _ => throw FormatException('Unknown session event $value'),
  };

  test(
    'shared session sequences permit protected work only in ready state',
    () {
      for (final raw in fixture['sessionSequences'] as List) {
        final sequence = Map<String, dynamic>.from(raw as Map);
        final events = List<String>.from(sequence['events'] as List);
        final states = List<String>.from(sequence['states'] as List);
        var gate = const AuthIncarnationSessionGateV2.signedOut();
        for (var index = 0; index < events.length; index += 1) {
          gate = gate.transition(event(events[index]));
          expect(
            gate.state.name,
            states[index],
            reason: '${sequence['name']}[$index]',
          );
          final expectedPermission = states[index] == 'ready';
          expect(gate.permitsProtectedListeners, expectedPermission);
          expect(gate.permitsCapabilities, expectedPermission);
          expect(gate.permitsFcmRegistration, expectedPermission);
        }
      }
    },
  );

  test(
    'ready cannot be injected from signed-out, deleted, or deleting state',
    () {
      for (final startEvent in const [
        AuthIncarnationSessionEventV2.proofReady,
        AuthIncarnationSessionEventV2.lifecycleDeleting,
        AuthIncarnationSessionEventV2.lifecycleDeleted,
      ]) {
        var gate = const AuthIncarnationSessionGateV2.signedOut().transition(
          startEvent,
        );
        if (startEvent != AuthIncarnationSessionEventV2.proofReady) {
          gate = gate.transition(AuthIncarnationSessionEventV2.proofReady);
        }
        expect(gate.state, AuthIncarnationSessionStateV2.blocked);
        expect(gate.permitsProtectedListeners, isFalse);
      }
    },
  );
}
