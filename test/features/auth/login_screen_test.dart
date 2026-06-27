import 'package:flutter_test/flutter_test.dart';

/// Tests for the login screen's email validation logic.
///
/// Because the actual LoginScreen depends on Riverpod, go_router, and Firebase,
/// we extract and test the validation logic in isolation to avoid heavy mocking.
/// The email regex and validator below are copied directly from login_screen.dart.

// Extracted validator matching login_screen.dart line 199-205.
String? emailValidator(String? v) {
  if (v == null || v.trim().isEmpty) return 'Enter your email';
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(v.trim())) {
    return 'Enter a valid email address';
  }
  return null;
}

String? passwordValidator(String? v) {
  return v == null || v.isEmpty ? 'Enter your password' : null;
}

String? nameValidator(String? v, {required bool isSignUp}) {
  return isSignUp && (v == null || v.trim().isEmpty) ? 'Enter your name' : null;
}

// Extracted from LoginScreen._friendlyError (lines 98-106).
String friendlyError(String error) {
  if (error.contains('user-not-found')) return 'No account found with that email';
  if (error.contains('wrong-password')) return 'Incorrect password';
  if (error.contains('email-already-in-use')) {
    return 'An account already exists with that email';
  }
  if (error.contains('weak-password')) {
    return 'Password must be at least 6 characters';
  }
  if (error.contains('invalid-email')) {
    return 'Please enter a valid email address';
  }
  if (error.contains('invalid-credential')) return 'Invalid email or password';
  return error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
}

void main() {
  group('Email validation', () {
    test('rejects null', () {
      expect(emailValidator(null), 'Enter your email');
    });

    test('rejects empty string', () {
      expect(emailValidator(''), 'Enter your email');
    });

    test('rejects whitespace-only string', () {
      expect(emailValidator('   '), 'Enter your email');
    });

    test('rejects missing @ sign', () {
      expect(emailValidator('userexample.com'), 'Enter a valid email address');
    });

    test('rejects missing domain', () {
      expect(emailValidator('user@'), 'Enter a valid email address');
    });

    test('rejects missing TLD', () {
      expect(emailValidator('user@example'), 'Enter a valid email address');
    });

    test('accepts valid email', () {
      expect(emailValidator('user@example.com'), isNull);
    });

    test('accepts email with subdomain', () {
      expect(emailValidator('user@mail.example.co.uk'), isNull);
    });

    test('trims leading/trailing whitespace before validating', () {
      expect(emailValidator('  user@example.com  '), isNull);
    });

    test('rejects email with spaces in local part', () {
      expect(
        emailValidator('us er@example.com'),
        'Enter a valid email address',
      );
    });
  });

  group('Password validation', () {
    test('rejects null', () {
      expect(passwordValidator(null), 'Enter your password');
    });

    test('rejects empty string', () {
      expect(passwordValidator(''), 'Enter your password');
    });

    test('accepts any non-empty string', () {
      expect(passwordValidator('p'), isNull);
    });
  });

  group('Name validation (sign up mode)', () {
    test('rejects empty name during sign up', () {
      expect(nameValidator('', isSignUp: true), 'Enter your name');
    });

    test('accepts empty name during sign in', () {
      expect(nameValidator('', isSignUp: false), isNull);
    });

    test('accepts valid name during sign up', () {
      expect(nameValidator('John Doe', isSignUp: true), isNull);
    });
  });

  group('friendlyError mapping', () {
    test('maps user-not-found', () {
      expect(
        friendlyError('[firebase_auth/user-not-found] No user.'),
        'No account found with that email',
      );
    });

    test('maps wrong-password', () {
      expect(
        friendlyError('[firebase_auth/wrong-password] Bad password.'),
        'Incorrect password',
      );
    });

    test('maps email-already-in-use', () {
      expect(
        friendlyError('[firebase_auth/email-already-in-use] Dup.'),
        'An account already exists with that email',
      );
    });

    test('maps weak-password', () {
      expect(
        friendlyError('[firebase_auth/weak-password] Weak.'),
        'Password must be at least 6 characters',
      );
    });

    test('maps invalid-email', () {
      expect(
        friendlyError('[firebase_auth/invalid-email] Bad email.'),
        'Please enter a valid email address',
      );
    });

    test('maps invalid-credential', () {
      expect(
        friendlyError('[firebase_auth/invalid-credential] Fail.'),
        'Invalid email or password',
      );
    });

    test('fallback strips bracket tags', () {
      expect(
        friendlyError('[firebase_auth/something] Some error message'),
        'Some error message',
      );
    });
  });
}
