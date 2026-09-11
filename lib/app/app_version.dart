import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label => buildNumber.isEmpty ? version : '$version ($buildNumber)';
}

abstract interface class AppVersionLoader {
  Future<AppVersionInfo> load();
}

/// Temporary dependency-free adapter.
///
/// The integration owner replaces this with the package_info_plus adapter when
/// adding the manifest/lock dependency. Build pipelines may supply these two
/// defines meanwhile; missing values are reported honestly, never guessed.
class BuildEnvironmentAppVersionLoader implements AppVersionLoader {
  const BuildEnvironmentAppVersionLoader();

  @override
  Future<AppVersionInfo> load() async {
    const version = String.fromEnvironment('FLUTTER_BUILD_NAME');
    const build = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
    if (version.isEmpty) {
      throw StateError('Installed package metadata is unavailable.');
    }
    return const AppVersionInfo(version: version, buildNumber: build);
  }
}

final appVersionLoaderProvider = Provider<AppVersionLoader>((ref) {
  return const BuildEnvironmentAppVersionLoader();
});

final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) {
  return ref.watch(appVersionLoaderProvider).load();
});
