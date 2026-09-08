import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/membership_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';

void main() {
  const profile = UserModel(
    id: 'u1',
    email: 'u@example.com',
    displayName: 'User',
    associationId: 'jba',
    role: UserRole.superAdmin,
  );

  MembershipModel membership({
    String associationId = 'jba',
    String status = 'active',
    int schemaVersion = 1,
  }) => MembershipModel(
    userId: 'u1',
    associationId: associationId,
    role: UserRole.fan,
    capabilities: const {'association.read'},
    status: status,
    schemaVersion: schemaVersion,
  );

  test('only a matching active current membership unlocks the app', () {
    expect(
      resolveAccountAccess(
        isAuthenticated: true,
        profile: profile,
        membership: membership(),
      ),
      AccountAccessStatus.active,
    );
    for (final blocked in [
      membership(status: 'suspended'),
      membership(status: 'revoked'),
      membership(schemaVersion: 0),
      membership(associationId: 'other'),
    ]) {
      expect(
        resolveAccountAccess(
          isAuthenticated: true,
          profile: profile,
          membership: blocked,
        ),
        AccountAccessStatus.blocked,
      );
    }
  });

  test('fresh auth can join while split legacy records are blocked', () {
    expect(
      resolveAccountAccess(
        isAuthenticated: true,
        profile: null,
        membership: null,
      ),
      AccountAccessStatus.pendingProvisioning,
    );
    expect(
      resolveAccountAccess(
        isAuthenticated: true,
        profile: profile,
        membership: null,
      ),
      AccountAccessStatus.blocked,
    );
    expect(
      resolveAccountAccess(
        isAuthenticated: true,
        profile: null,
        membership: membership(),
      ),
      AccountAccessStatus.blocked,
    );
  });
}
