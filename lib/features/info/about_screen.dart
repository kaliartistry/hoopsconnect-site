import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingLg),
        children: [
          const SizedBox(height: 20),

          // App logo
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              child: Image.asset(
                'assets/images/jba_logo.png',
                width: 100,
                height: 100,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'HoopsConnect',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Jamaica HoopsConnect',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Donation credit
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: const Column(
              children: [
                Icon(Icons.favorite, color: AppColors.accent, size: 28),
                SizedBox(height: 10),
                Text(
                  'Donated to the Jamaica Basketball Association',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'by Kali McCarthy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Description
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: const Text(
              'Jamaica HoopsConnect is a league management app built for the Jamaica Basketball Association. '
              'It helps administrators, team representatives, and media stay connected with league announcements, '
              'game schedules, stats, and leaderboards.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Legal links
          ListTile(
            leading: const Icon(Icons.description_outlined, color: AppColors.textSecondary),
            title: const Text('Terms of Use'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => context.push('/legal/terms'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.textSecondary),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => context.push('/legal/privacy'),
          ),
        ],
      ),
    );
  }
}
