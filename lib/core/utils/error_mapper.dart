/// Maps common Firebase and network exception messages to user-friendly strings.
class ErrorMapper {
  ErrorMapper._();

  /// Returns a user-friendly message for the given [error].
  static String map(Object error) {
    final msg = error.toString();

    // Firebase permission errors
    if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
      return "You don't have permission to access this";
    }
    if (msg.contains('not-found') || msg.contains('NOT_FOUND')) {
      return 'The requested item was not found';
    }
    if (msg.contains('unavailable') || msg.contains('UNAVAILABLE')) {
      return 'Service temporarily unavailable. Please try again';
    }
    if (msg.contains('unauthenticated') || msg.contains('UNAUTHENTICATED')) {
      return 'Please sign in to continue';
    }

    // Network errors
    if (msg.contains('SocketException') ||
        msg.contains('network') ||
        msg.contains('NetworkError') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('HandshakeException')) {
      return 'Check your internet connection';
    }

    // Timeout
    if (msg.contains('TimeoutException') || msg.contains('deadline-exceeded')) {
      return 'Request timed out. Please try again';
    }

    // Fallback
    return 'An unexpected error occurred. Please try again';
  }
}
