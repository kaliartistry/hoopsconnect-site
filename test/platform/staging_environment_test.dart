import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/platform/staging_environment.dart';

void main() {
  test('staging web options stay isolated from production', () {
    expect(StagingEnvironment.web.projectId, 'hoopsconnect-jba-staging');
    expect(StagingEnvironment.web.projectId, isNot('hoops-connect-jm'));
    expect(
      StagingEnvironment.web.authDomain,
      'hoopsconnect-jba-staging.firebaseapp.com',
    );
  });

  test('native staging app IDs stay in the same isolated project', () {
    expect(StagingEnvironment.ios.projectId, StagingEnvironment.web.projectId);
    expect(StagingEnvironment.android.projectId, StagingEnvironment.web.projectId);
    expect(StagingEnvironment.ios.appId, startsWith('1:842064766966:ios:'));
    expect(StagingEnvironment.android.appId, startsWith('1:842064766966:android:'));
    expect(
      StagingEnvironment.ios.iosBundleId,
      'com.hoopsconnect.hoopsConnect',
    );
  });
}
