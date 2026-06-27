import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';

/// Singleton connectivity service instance.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Stream provider that emits the current online status.
/// Returns `true` when the device has network connectivity.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  // Emit the current state first.
  yield await service.checkConnectivity();
  // Then stream subsequent changes.
  yield* service.onConnectivityChanged;
});
