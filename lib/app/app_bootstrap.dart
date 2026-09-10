import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

/// Draws a real Flutter frame while release-only services initialize.
///
/// Startup services are bounded so a provider outage or device-attestation
/// problem cannot strand the user on Android's native gray window.
class AppBootstrap extends StatefulWidget {
  final Future<void> Function() initialize;
  final Widget child;
  final Duration timeout;

  const AppBootstrap({
    super.key,
    required this.initialize,
    required this.child,
    this.timeout = const Duration(seconds: 8),
  });

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = Future<void>.sync(
      widget.initialize,
    ).timeout(widget.timeout, onTimeout: () {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return widget.child;
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 18),
                    Text(
                      'Starting HoopsConnect',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
