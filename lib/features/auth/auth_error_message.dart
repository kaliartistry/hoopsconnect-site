/// Converts provider error codes into safe, actionable account-access copy.
///
/// Unknown provider text is deliberately not echoed. It can contain internal
/// project/configuration details and is rarely useful to a member.
String? friendlyAuthErrorMessage(Object error) {
  final text = error.toString().toLowerCase();

  if (_containsAny(text, const [
    'popup-closed-by-user',
    'canceled',
    'cancelled',
    'authorizationerror code=1001',
  ])) {
    return null;
  }
  if (_containsAny(text, const [
    'user-not-found',
    'wrong-password',
    'invalid-credential',
  ])) {
    return 'The email or password was not recognized. Try again or reset your password.';
  }
  if (text.contains('email-already-in-use')) {
    return 'An account already uses this email. Sign in instead, or reset the password if this is an email account.';
  }
  if (text.contains('account-exists-with-different-credential')) {
    return 'This email already has an account. Sign in with its existing method, then connect Google or Apple from Profile.';
  }
  if (text.contains('weak-password')) {
    return 'Use a password with at least 6 characters.';
  }
  if (text.contains('invalid-email')) {
    return 'Enter a valid email address.';
  }
  if (text.contains('operation-not-allowed')) {
    return 'That sign-in method is not available right now. Try another option or contact the association.';
  }
  if (_containsAny(text, const [
    'network-request-failed',
    'unavailable',
    'timeout',
  ])) {
    return 'We could not reach the sign-in service. Check your connection and try again.';
  }
  if (text.contains('too-many-requests')) {
    return 'Too many attempts were made. Wait a little while, then try again.';
  }
  return 'We could not complete that sign-in. Try again, choose another sign-in method, or contact the association.';
}

/// Account linking errors never expose provider details or imply an automatic
/// merge of two accounts with different Firebase user IDs.
String? friendlyAccountLinkErrorMessage(Object error) {
  final text = error.toString().toLowerCase();
  if (_containsAny(text, const [
    'popup-closed-by-user',
    'canceled',
    'cancelled',
    'authorizationerror code=1001',
  ])) {
    return null;
  }
  if (_containsAny(text, const [
    'credential-already-in-use',
    'email-already-in-use',
    'account-exists-with-different-credential',
  ])) {
    return 'That Google or Apple account is already connected to another member. No accounts were merged. Contact the association for help.';
  }
  if (text.contains('provider-already-linked') ||
      text.contains('already connected')) {
    return 'That sign-in method is already connected to this account.';
  }
  if (text.contains('requires-recent-login')) {
    return 'For security, sign out and sign in again with your existing method before connecting this account.';
  }
  if (text.contains('popup-blocked')) {
    return 'Allow the sign-in popup in your browser, then try again.';
  }
  if (_containsAny(text, const [
    'network-request-failed',
    'unavailable',
    'timeout',
  ])) {
    return 'We could not reach the sign-in service. Check your connection and try again.';
  }
  return 'We could not connect that sign-in method. Your existing account is unchanged. Try again or contact the association.';
}

/// Password recovery never reveals whether an address has an account.
bool passwordResetShouldAppearSuccessful(Object error) {
  return error.toString().toLowerCase().contains('user-not-found');
}

bool _containsAny(String value, List<String> needles) {
  return needles.any(value.contains);
}
