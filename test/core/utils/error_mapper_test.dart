import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/utils/error_mapper.dart';

void main() {
  group('ErrorMapper', () {
    // ──── Firebase permission errors ────

    test('maps permission-denied', () {
      expect(
        ErrorMapper.map(Exception('permission-denied')),
        "You don't have permission to access this",
      );
    });

    test('maps PERMISSION_DENIED (uppercase)', () {
      expect(
        ErrorMapper.map('PERMISSION_DENIED'),
        "You don't have permission to access this",
      );
    });

    test('maps not-found', () {
      expect(
        ErrorMapper.map(Exception('not-found')),
        'The requested item was not found',
      );
    });

    test('maps NOT_FOUND (uppercase)', () {
      expect(
        ErrorMapper.map('NOT_FOUND'),
        'The requested item was not found',
      );
    });

    test('maps unavailable', () {
      expect(
        ErrorMapper.map(Exception('unavailable')),
        'Service temporarily unavailable. Please try again',
      );
    });

    test('maps UNAVAILABLE (uppercase)', () {
      expect(
        ErrorMapper.map('UNAVAILABLE'),
        'Service temporarily unavailable. Please try again',
      );
    });

    test('maps unauthenticated', () {
      expect(
        ErrorMapper.map(Exception('unauthenticated')),
        'Please sign in to continue',
      );
    });

    test('maps UNAUTHENTICATED (uppercase)', () {
      expect(
        ErrorMapper.map('UNAUTHENTICATED'),
        'Please sign in to continue',
      );
    });

    // ──── Network errors ────

    test('maps SocketException', () {
      expect(
        ErrorMapper.map('SocketException: Failed to connect'),
        'Check your internet connection',
      );
    });

    test('maps NetworkError', () {
      expect(
        ErrorMapper.map('NetworkError occurred'),
        'Check your internet connection',
      );
    });

    test('maps Failed host lookup', () {
      expect(
        ErrorMapper.map('Failed host lookup: example.com'),
        'Check your internet connection',
      );
    });

    test('maps Connection refused', () {
      expect(
        ErrorMapper.map('Connection refused'),
        'Check your internet connection',
      );
    });

    test('maps HandshakeException', () {
      expect(
        ErrorMapper.map('HandshakeException: certificate error'),
        'Check your internet connection',
      );
    });

    test('maps generic network error', () {
      expect(
        ErrorMapper.map('network failure'),
        'Check your internet connection',
      );
    });

    // ──── Timeout errors ────

    test('maps TimeoutException', () {
      expect(
        ErrorMapper.map('TimeoutException after 30s'),
        'Request timed out. Please try again',
      );
    });

    test('maps deadline-exceeded', () {
      expect(
        ErrorMapper.map('deadline-exceeded'),
        'Request timed out. Please try again',
      );
    });

    // ──── Fallback ────

    test('returns generic message for unknown error', () {
      expect(
        ErrorMapper.map('some random error xyz'),
        'An unexpected error occurred. Please try again',
      );
    });

    test('returns generic message for empty string error', () {
      expect(
        ErrorMapper.map(''),
        'An unexpected error occurred. Please try again',
      );
    });

    // ──── Priority order ────

    test('permission-denied takes priority over network-like strings', () {
      // This error contains 'permission-denied' which should match first
      expect(
        ErrorMapper.map('permission-denied on network call'),
        "You don't have permission to access this",
      );
    });
  });
}
