import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/user_management_screen.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';

void main() {
  testWidgets('administrators can filter users by every visible role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allUsersProvider.overrideWith((ref) async => _users),
          currentUserProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: const MaterialApp(home: UserManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All (7)'), findsOneWidget);
    expect(find.text('Super Admins (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('Statisticians (1)'));
    await tester.tap(find.text('Statisticians (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Stats User'), findsOneWidget);
    expect(find.text('Admin User'), findsNothing);

    await tester.ensureVisible(find.text('Media (2)'));
    await tester.tap(find.text('Media (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Media User'), findsOneWidget);
    expect(find.text('Legacy Press User'), findsOneWidget);
    expect(find.text('Stats User'), findsNothing);

    await tester.ensureVisible(find.text('Fans (1)'));
    await tester.tap(find.text('Fans (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Fan User'), findsOneWidget);
    expect(find.text('Media User'), findsNothing);
  });
}

const _users = <UserModel>[
  UserModel(
    id: 'super',
    email: 'super@example.com',
    displayName: 'Super User',
    associationId: 'jba',
    role: UserRole.superAdmin,
  ),
  UserModel(
    id: 'admin',
    email: 'admin@example.com',
    displayName: 'Admin User',
    associationId: 'jba',
    role: UserRole.admin,
  ),
  UserModel(
    id: 'stats',
    email: 'stats@example.com',
    displayName: 'Stats User',
    associationId: 'jba',
    role: UserRole.statistician,
  ),
  UserModel(
    id: 'rep',
    email: 'rep@example.com',
    displayName: 'Rep User',
    associationId: 'jba',
    role: UserRole.rep,
  ),
  UserModel(
    id: 'media',
    email: 'media@example.com',
    displayName: 'Media User',
    associationId: 'jba',
    role: UserRole.media,
  ),
  UserModel(
    id: 'press',
    email: 'press@example.com',
    displayName: 'Legacy Press User',
    associationId: 'jba',
    role: UserRole.press,
  ),
  UserModel(
    id: 'fan',
    email: 'fan@example.com',
    displayName: 'Fan User',
    associationId: 'jba',
    role: UserRole.fan,
  ),
];
