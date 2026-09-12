import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label => buildNumber.isEmpty ? version : '$version ($buildNumber)';
}

abstract interface class AppVersionLoader {
  Future<AppVersionInfo> load();
}

class PackageInfoAppVersionLoader implements AppVersionLoader {
  const PackageInfoAppVersionLoader();

  @override
  Future<AppVersionInfo> load() async {
    final package = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: package.version,
      buildNumber: package.buildNumber,
    );
  }
}

final appVersionLoaderProvider = Provider<AppVersionLoader>((ref) {
  return const PackageInfoAppVersionLoader();
});

final appVersionInfoProvider = FutureProvider<AppVersionInfo>((ref) {
  return ref.watch(appVersionLoaderProvider).load();
});
