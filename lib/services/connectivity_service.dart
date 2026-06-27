import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors device connectivity and exposes a simple online/offline API.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Stream that emits `true` when online and `false` when offline.
  late final Stream<bool> onConnectivityChanged = _connectivity.onConnectivityChanged
      .map(_isConnected)
      .distinct();

  /// Check current connectivity synchronously after an initial async check.
  bool _lastKnown = true;

  ConnectivityService() {
    // Keep _lastKnown up to date.
    onConnectivityChanged.listen((online) => _lastKnown = online);
  }

  /// Best-effort getter based on the last known value.
  bool get isOnline => _lastKnown;

  /// One-shot async check of current connectivity.
  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _lastKnown = _isConnected(result);
    return _lastKnown;
  }

  static bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
