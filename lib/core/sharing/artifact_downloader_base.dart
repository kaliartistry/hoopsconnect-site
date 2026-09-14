import 'dart:typed_data';

abstract interface class ArtifactDownloader {
  bool get isSupported;

  /// Returns a user-facing destination label after bytes are durably handed to
  /// the platform. Implementations throw when that cannot be confirmed.
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });
}
