import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connectivity_providers.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';
import '../utils/error_mapper.dart';

/// Reusable error widget with icon, user-friendly message, and retry button.
///
/// Automatically detects offline state via [isOnlineProvider] and shows a
/// friendlier "You're offline" message for network-related errors.
class ErrorDisplay extends ConsumerWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorDisplay({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final showOffline = !isOnline || _isNetworkRelated(error);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final containerColor = showOffline
        ? semantic.warningContainer
        : colorScheme.errorContainer;
    final foregroundColor = showOffline
        ? semantic.onWarningContainer
        : colorScheme.onErrorContainer;
    final title = showOffline ? "You're offline" : 'Something went wrong';
    final message = showOffline
        ? 'Check your internet connection and try again'
        : ErrorMapper.map(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              label: '$title. $message',
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: containerColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        showOffline ? Icons.cloud_off : Icons.error_outline,
                        size: 40,
                        color: foregroundColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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

  static bool _isNetworkRelated(Object error) {
    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('network') ||
        message.contains('NetworkError') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('HandshakeException') ||
        message.contains('unavailable') ||
        message.contains('UNAVAILABLE') ||
        message.contains('TimeoutException') ||
        message.contains('deadline-exceeded');
  }
}
