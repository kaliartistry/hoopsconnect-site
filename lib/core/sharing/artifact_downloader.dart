import 'artifact_downloader_base.dart';
import 'artifact_downloader_stub.dart'
    if (dart.library.io) 'artifact_downloader_native.dart'
    if (dart.library.html) 'artifact_downloader_web.dart'
    as implementation;

export 'artifact_downloader_base.dart';

ArtifactDownloader createArtifactDownloader() =>
    implementation.createArtifactDownloader();
