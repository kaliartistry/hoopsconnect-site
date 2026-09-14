import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

enum AppStateTone { neutral, info, success, warning, error }

/// A consistent message for empty, success, warning and recoverable error
/// states. The message is announced when it changes, while its optional action
/// remains a normal framework button with independent semantics.
class AppStateMessage extends StatelessWidget {
  const AppStateMessage({
    super.key,
    required this.title,
    required this.message,
    this.tone = AppStateTone.neutral,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'An action needs both a label and a callback.',
       );

  final String title;
  final String message;
  final AppStateTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final resolvedIcon = icon ?? _defaultIcon;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : AppSizes.paddingMd),
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            liveRegion: tone != AppStateTone.neutral,
            label: '$title. $message',
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(resolvedIcon, color: colors.foreground, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colors.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.foreground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.foreground),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _defaultIcon => switch (tone) {
    AppStateTone.neutral => Icons.inbox_outlined,
    AppStateTone.info => Icons.info_outline,
    AppStateTone.success => Icons.check_circle_outline,
    AppStateTone.warning => Icons.warning_amber_rounded,
    AppStateTone.error => Icons.error_outline,
  };

  ({Color container, Color foreground}) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    return switch (tone) {
      AppStateTone.neutral => (
        container: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
      AppStateTone.info => (
        container: semantic.infoContainer,
        foreground: semantic.onInfoContainer,
      ),
      AppStateTone.success => (
        container: semantic.successContainer,
        foreground: semantic.onSuccessContainer,
      ),
      AppStateTone.warning => (
        container: semantic.warningContainer,
        foreground: semantic.onWarningContainer,
      ),
      AppStateTone.error => (
        container: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
    };
  }
}

/// A named progress state for full panels or inline task transitions.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.label = 'Loading',
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSizes.paddingSm : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
