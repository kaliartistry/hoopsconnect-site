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
    return 'This email is linked to another sign-in method. Use the Google, Apple, or email option you originally chose.';
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

bool _containsAny(String value, List<String> needles) {
  return needles.any(value.contains);
}
