import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/auth/auth_error_message.dart';

void main() {
  test('credential failures use enumeration-safe generic copy', () {
    expect(
      friendlyAuthErrorMessage(
        Exception('[firebase_auth/user-not-found] internal provider text'),
      ),
      'The email or password was not recognized. Try again or reset your password.',
    );
    expect(
      friendlyAuthErrorMessage(
        Exception('[firebase_auth/wrong-password] internal provider text'),
      ),
      'The email or password was not recognized. Try again or reset your password.',
    );
  });

  test('provider mismatch gives provider-aware guidance', () {
    expect(
      friendlyAuthErrorMessage(
        Exception('[firebase_auth/account-exists-with-different-credential]'),
      ),
      contains('Google, Apple, or email'),
    );
  });

  test('cancellation is not presented as an error', () {
    expect(
      friendlyAuthErrorMessage(
        Exception('[firebase_auth/popup-closed-by-user]'),
      ),
      isNull,
    );
  });

  test('unknown provider details are never echoed', () {
    const privateDetail = 'project-secret-provider-detail';
    final message = friendlyAuthErrorMessage(Exception(privateDetail));
    expect(message, isNot(contains(privateDetail)));
    expect(message, contains('could not complete'));
  });
}
