import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'artifact_downloader.dart';

abstract interface class BrandedShareActions {
  bool get canDownload;

  Future<ShareResult> shareImage({
    required String title,
    required String text,
    required String fileName,
    required Uint8List imageBytes,
    Rect? sharePositionOrigin,
  });

  Future<ShareResult> shareText({
    required String title,
    required String text,
    Rect? sharePositionOrigin,
  });

  Future<void> copyText(String text);

  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });
}

class PlatformBrandedShareActions implements BrandedShareActions {
  final SharePlus _share;
  final ArtifactDownloader _downloader;

  PlatformBrandedShareActions({
    SharePlus? share,
    ArtifactDownloader? downloader,
  }) : _share = share ?? SharePlus.instance,
       _downloader = downloader ?? createArtifactDownloader();

  @override
  bool get canDownload => _downloader.isSupported;

  @override
  Future<ShareResult> shareImage({
    required String title,
    required String text,
    required String fileName,
    required Uint8List imageBytes,
    Rect? sharePositionOrigin,
  }) {
    return _share.share(
      ShareParams(
        title: title,
        subject: title,
        text: text,
        files: [XFile.fromData(imageBytes, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
        downloadFallbackEnabled: false,
        mailToFallbackEnabled: false,
      ),
    );
  }

  @override
  Future<ShareResult> shareText({
    required String title,
    required String text,
    Rect? sharePositionOrigin,
  }) {
    return _share.share(
      ShareParams(
        title: title,
        subject: title,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
        downloadFallbackEnabled: false,
        mailToFallbackEnabled: false,
      ),
    );
  }

  @override
  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) => _downloader.download(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
