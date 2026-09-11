import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/app/app_version.dart';
import 'package:hoops_connect/features/info/about_screen.dart';

void main() {
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
}

class _FakeLoader implements AppVersionLoader {
  const _FakeLoader(this.value);
  final AppVersionInfo value;

  @override
  Future<AppVersionInfo> load() async => value;
}
