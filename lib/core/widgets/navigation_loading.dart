import 'package:flutter/material.dart';

/// Branded loading/splash screen shown while [authStateProvider] resolves on
/// cold start.  Uses the app's orange/green primary theme, displays the app
/// name and a basketball icon together with a progress indicator.
class NavigationLoadingScreen extends StatelessWidget {
  const NavigationLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFEA580C); // matches AppColors.primary (orange)

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), // AppColors.surface
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // JBA Logo
            Image.asset(
              'assets/images/jba_logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),

            // App name
            const Text(
              'HoopsConnect',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827), // AppColors.textPrimary
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),

            const Text(
              'Jamaica Basketball Association',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280), // AppColors.textSecondary
              ),
            ),
            const SizedBox(height: 32),

            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
