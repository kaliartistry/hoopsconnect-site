import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Keeps single-column tasks readable on large screens without taking useful
/// responsive layouts away from feature screens.
class AppConstrainedContent extends StatelessWidget {
  const AppConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(AppSizes.paddingLg),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}
