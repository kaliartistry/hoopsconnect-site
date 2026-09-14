// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'artifact_downloader_base.dart';

ArtifactDownloader createArtifactDownloader() => WebArtifactDownloader();

class WebArtifactDownloader implements ArtifactDownloader {
  @override
  bool get isSupported => true;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      final anchor = html.AnchorElement(href: url)
        ..download = fileName
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      return fileName;
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }
}
