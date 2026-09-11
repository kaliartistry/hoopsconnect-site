import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'artifact_downloader_base.dart';

ArtifactDownloader createArtifactDownloader() => NativeArtifactDownloader();

class NativeArtifactDownloader implements ArtifactDownloader {
  @override
  bool get isSupported => true;

  @override
  Future<String> download({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeName.isEmpty) throw const FileSystemException('Invalid file name.');
    final directory = await getApplicationDocumentsDirectory();
    final separator = Platform.pathSeparator;
    final file = File('${directory.path}$separator$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
