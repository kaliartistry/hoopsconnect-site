import 'dart:typed_data';

import 'artifact_downloader_base.dart';

ArtifactDownloader createArtifactDownloader() =>
    const UnsupportedArtifactDownloader();

class UnsupportedArtifactDownloader implements ArtifactDownloader {
  const UnsupportedArtifactDownloader();

  @override
  bool get isSupported => false;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    throw UnsupportedError('Downloads are not supported on this platform.');
  }
}
