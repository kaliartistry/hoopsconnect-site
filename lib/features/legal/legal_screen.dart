import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class LegalScreen extends StatelessWidget {
  final String type; // 'terms' or 'privacy'

  const LegalScreen({super.key, required this.type});

  bool get isTerms => type == 'terms';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isTerms ? 'Terms of Use' : 'Privacy Policy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          Text(
            isTerms ? 'Terms of Use' : 'Privacy Policy',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Last updated: February 2026',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),

          if (isTerms) ..._termsContent() else ..._privacyContent(),
        ],
      ),
    );
  }

  List<Widget> _termsContent() {
    return [
      _section('1. Acceptance of Terms',
          'By accessing and using Jamaica HoopsConnect ("the App"), you agree to be bound by these Terms of Use. '
              'If you do not agree to these terms, please do not use the App.'),
      _section('2. Description of Service',
          'Jamaica HoopsConnect is a basketball league management application provided for the Jamaica Basketball Association. '
              'The App provides league announcements, game schedules, statistics tracking, and team management features.'),
      _section('3. User Accounts',
          'You are responsible for maintaining the confidentiality of your account credentials. '
              'You agree to provide accurate information when creating your account. '
              'You must not share your account with others or allow unauthorized access.'),
      _section('4. User Conduct',
          'You agree not to:\n'
              '- Post false or misleading information\n'
              '- Harass, abuse, or threaten other users\n'
              '- Attempt to gain unauthorized access to other accounts\n'
              '- Use the App for any illegal purpose\n'
              '- Interfere with the proper functioning of the App'),
      _section('5. Content',
          'Users may post content including announcements, comments, and statistics. '
              'You are responsible for any content you post. '
              'The Jamaica Basketball Association reserves the right to remove any content that violates these terms.'),
      _section('6. Disclaimer',
          'The App is provided "as is" without warranties of any kind. '
              'We do not guarantee that the App will be error-free or uninterrupted.'),
      _section('7. Changes to Terms',
          'We reserve the right to modify these terms at any time. '
              'Continued use of the App after changes constitutes acceptance of the new terms.'),
      _section('8. Contact',
          'For questions about these Terms of Use, please contact the Jamaica Basketball Association.'),
    ];
  }

  List<Widget> _privacyContent() {
    return [
      _section('1. Information We Collect',
          'We collect information you provide when creating an account, including:\n'
              '- Name and email address\n'
              '- Team and role information\n'
              '- Device tokens for push notifications\n\n'
              'We also collect usage data such as app interactions and game statistics you enter.'),
      _section('2. How We Use Your Information',
          'Your information is used to:\n'
              '- Provide and maintain the App\n'
              '- Send league announcements and notifications\n'
              '- Display team rosters and statistics\n'
              '- Improve the App experience'),
      _section('3. Information Sharing',
          'Your name, team, and role are visible to other authenticated users of the App. '
              'Game statistics you enter are visible to all league participants. '
              'We do not sell your personal information to third parties.'),
      _section('4. Data Storage',
          'Your data is stored securely using Google Firebase services. '
              'Data is protected by Firebase security rules that restrict access based on user roles.'),
      _section('5. Push Notifications',
          'With your permission, we send push notifications for league announcements, '
              'game reminders, and acknowledgment requests. '
              'You can disable notifications in your device settings.'),
      _section('6. Data Retention',
          'Your account data is retained as long as your account is active. '
              'You may request account deletion by contacting the Jamaica Basketball Association.'),
      _section('7. Children\'s Privacy',
          'The App is not intended for children under 13. '
              'We do not knowingly collect information from children under 13.'),
      _section('8. Changes to Privacy Policy',
          'We may update this Privacy Policy from time to time. '
              'We will notify you of significant changes through the App.'),
      _section('9. Contact',
          'For questions about this Privacy Policy, please contact the Jamaica Basketball Association.'),
    ];
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
