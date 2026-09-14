import 'package:flutter/material.dart';

/// Branded loading screen shown while routing and account authority resolve.
class NavigationLoadingScreen extends StatelessWidget {
  const NavigationLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/jba_logo.png',
              width: 120,
              height: 120,
              semanticLabel: 'Jamaica Basketball Association logo',
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                'HoopsConnect',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Jamaica Basketball Association',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Semantics(
              container: true,
              liveRegion: true,
              label: 'Loading your account',
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
