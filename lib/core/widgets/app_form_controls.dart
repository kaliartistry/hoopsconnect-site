import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppActionStyle { filled, outlined, text }

/// A keyboard-traversable form boundary with an optional Escape action.
///
/// Standard Flutter fields and buttons retain their framework semantics. The
/// wrapper only establishes predictable reading-order traversal and a shared
/// cancel convention for dialogs and multi-step forms.
class AppFormFocusGroup extends StatelessWidget {
  const AppFormFocusGroup({super.key, required this.child, this.onCancel});

  final Widget child;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    Widget result = FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: child,
    );

    if (onCancel != null) {
      result = CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): onCancel!,
        },
        child: result,
      );
    }

    return result;
  }
}

/// A primary/action button that gives pending and disabled states an explicit
/// accessible explanation while preventing duplicate activation.
class AppAsyncActionButton extends StatelessWidget {
  const AppAsyncActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
    this.busyLabel = 'Working',
    this.disabledHint,
    this.icon,
    this.style = AppActionStyle.filled,
  }) : assert(
         onPressed != null || isBusy || disabledHint != null,
         'A disabled action must explain why it is unavailable.',
       );

  final String label;
  final FutureOr<void> Function()? onPressed;
  final bool isBusy;
  final String busyLabel;
  final String? disabledHint;
  final IconData? icon;
  final AppActionStyle style;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isBusy;
    final semanticsLabel = isBusy ? busyLabel : label;
    final semanticsHint = isBusy
        ? 'Please wait'
        : enabled
        ? null
        : disabledHint;
    final spinnerColor = style == AppActionStyle.filled
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.primary;
    final content = isBusy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor,
                ),
              ),
              const SizedBox(width: 10),
              Text(busyLabel),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );
    final callback = enabled
        ? () {
            onPressed!();
          }
        : null;

    final buttonContent = ExcludeSemantics(child: content);
    final Widget button = switch (style) {
      AppActionStyle.filled => ElevatedButton(
        onPressed: callback,
        child: buttonContent,
      ),
      AppActionStyle.outlined => OutlinedButton(
        onPressed: callback,
        child: buttonContent,
      ),
      AppActionStyle.text => TextButton(
        onPressed: callback,
        child: buttonContent,
      ),
    };

    return MergeSemantics(
      child: Semantics(
        label: semanticsLabel,
        hint: semanticsHint,
        liveRegion: isBusy,
        child: button,
      ),
    );
  }
}
