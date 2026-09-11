import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/app_version.dart';
import 'package:hoops_connect/features/info/about_screen.dart';
import 'package:hoops_connect/features/settings/settings_screen.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('production provider reads installed package metadata', () async {
    PackageInfo.setMockInitialValues(
      appName: 'HoopsConnect',
      packageName: 'com.example.hoops_connect',
      version: '4.5.6',
      buildNumber: '789',
      buildSignature: '',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(appVersionLoaderProvider),
      isA<PackageInfoAppVersionLoader>(),
    );
    final metadata = await container.read(appVersionInfoProvider.future);
    expect(metadata.version, '4.5.6');
    expect(metadata.buildNumber, '789');
  });

  test('version label includes installed build number', () async {
    final container = ProviderContainer(
      overrides: [
        appVersionLoaderProvider.overrideWithValue(
          const _FakeLoader(
            AppVersionInfo(version: '1.2.3', buildNumber: '45'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final version = await container.read(appVersionInfoProvider.future);
    expect(version.label, '1.2.3 (45)');
  });

  testWidgets('About renders injected package metadata, not a fixed version', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionLoaderProvider.overrideWithValue(
            const _FakeLoader(
              AppVersionInfo(version: '9.8.7', buildNumber: '654'),
            ),
          ),
        ],
        child: const MaterialApp(home: AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7 (654)'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsNothing);
    expect(find.text('Version 1.0.3'), findsNothing);
  });

  testWidgets('Settings renders the same injected package metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AsyncValue<UserModel?>.data(
              UserModel(
                id: 'fan',
                email: 'fan@example.com',
                displayName: 'Fan',
                associationId: 'jba',
                role: UserRole.fan,
                capabilities: {'association.read'},
              ),
            ),
          ),
          appVersionLoaderProvider.overrideWithValue(
            const _FakeLoader(
              AppVersionInfo(version: '9.8.7', buildNumber: '654'),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-version')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('9.8.7 (654)'), findsOneWidget);
    expect(find.text('1.0.3'), findsNothing);
  });
}

class _FakeLoader implements AppVersionLoader {
  const _FakeLoader(this.value);
  final AppVersionInfo value;

  @override
  Future<AppVersionInfo> load() async => value;
}
