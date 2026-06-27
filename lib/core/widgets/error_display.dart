import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connectivity_providers.dart';
import '../constants/app_constants.dart';

/// Reusable error widget with icon, user-friendly message, and retry button.
///
/// Automatically detects offline state via [isOnlineProvider] and shows a
/// friendlier "You're offline" message for network-related errors.
class ErrorDisplay extends ConsumerWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorDisplay({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final isNetworkError = _isNetworkRelated(error);

    // Show offline-specific UI when offline or the error is network-related.
    final showOffline = !isOnline || isNetworkError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: showOffline ? AppColors.ackBg : AppColors.urgentBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                showOffline ? Icons.cloud_off : Icons.error_outline,
                size: 40,
                color: showOffline ? AppColors.ack : AppColors.urgent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              showOffline ? "You're offline" : 'Something went wrong',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showOffline
                  ? 'Check your internet connection and try again'
                  : _mapError(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns `true` if the error looks network-related based on its message.
  static bool _isNetworkRelated(Object error) {
    final msg = error.toString();
    return msg.contains('SocketException') ||
        msg.contains('network') ||
        msg.contains('NetworkError') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('HandshakeException') ||
        msg.contains('unavailable') ||
        msg.contains('UNAVAILABLE') ||
        msg.contains('TimeoutException') ||
        msg.contains('deadline-exceeded');
  }

  static String _mapError(Object error) {
    final msg = error.toString();

    // Firebase permission errors
    if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
      return "You don't have permission to access this";
    }
    if (msg.contains('not-found') || msg.contains('NOT_FOUND')) {
      return 'The requested item was not found';
    }
    if (msg.contains('unauthenticated') || msg.contains('UNAUTHENTICATED')) {
      return 'Please sign in to continue';
    }

    // Fallback — don't show raw error text to the user
    return 'An unexpected error occurred. Please try again';
  }
}
