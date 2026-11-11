import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/auth/join_screen.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/services/repositories/auth_repository.dart';
import 'package:hoops_connect/services/repositories/invite_code_repository.dart';

class _SignedInUser implements User {
  bool verified = false;
  int verificationEmails = 0;
  int tokenRefreshes = 0;

  @override
  bool get emailVerified => verified;

  @override
  Future<void> reload() async {}

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    verificationEmails++;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    expect(forceRefresh, true);
    tokenRefreshes++;
    return null;
  }

  @override
  String get uid => 'team-rep';

  @override
  String get displayName => 'Team Representative';

  @override
  String get email => 'rep@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuth implements AuthRepository {
  _TestAuth({this.currentUser});

  @override
  User? currentUser;
  int signUps = 0;

  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    signUps++;
    final user = _SignedInUser();
    currentUser = user;
    return _TestCredential(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCredential implements UserCredential {
  _TestCredential(this.user);

  @override
  final User user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('invite redemption waits for review and confirmation', (
    tester,
  ) async {
    final redemptions = <Map<String, dynamic>>[];
    final invites = InviteCodeRepository(
      callable: (name, data) async {
        if (name == 'inspectPrivilegedInvite') {
          return {
            'inviteId': 'invite-1',
            'teamId': 'team-1',
            'teamName': 'Kingston Lions',
            'role': 'rep',
            'associationId': 'jba',
            'expiresAt': '2099-01-01T00:00:00.000Z',
          };
        }
        expect(name, 'redeemPrivilegedInvite');
        redemptions.add(data);
        return {};
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _TestAuth(currentUser: _SignedInUser()),
          ),
          inviteCodeRepositoryProvider.overrideWithValue(invites),
        ],
        child: const MaterialApp(home: JoinScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'test-invite');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();
    expect(find.text('Team Representative'), findsOneWidget);
    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();

    expect(find.text('Joining as team representative'), findsOneWidget);
    expect(find.text('Kingston Lions'), findsOneWidget);
    expect(find.text('rep@example.com'), findsOneWidget);
    expect(redemptions, isEmpty);

    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Updated Name');
    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join Team'));
    await tester.pumpAndSettle();

    expect(redemptions.single['code'], 'test-invite');
    expect(redemptions.single['displayName'], 'Updated Name');
  });

  testWidgets(
    'an existing lead verifies their email and reuses their account',
    (tester) async {
      final lead = _SignedInUser();
      final auth = _TestAuth(currentUser: lead);
      var redemptions = 0;
      final invites = InviteCodeRepository(
        callable: (name, data) async {
          if (name == 'inspectPrivilegedInvite') {
            return {
              'inviteId': 'invite-3',
              'teamId': 'team-1',
              'teamName': 'Kingston Lions',
              'role': 'rep',
              'associationId': 'jba',
              'requiresVerifiedEmail': true,
              'expiresAt': '2099-01-01T00:00:00.000Z',
            };
          }
          expect(name, 'redeemPrivilegedInvite');
          expect(lead.tokenRefreshes, 1);
          redemptions++;
          return {};
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            inviteCodeRepositoryProvider.overrideWithValue(invites),
          ],
          child: const MaterialApp(home: JoinScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'team-invite');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review details'));
      await tester.pumpAndSettle();
      expect(find.text('Kingston Lions'), findsOneWidget);

      final join = find.text('Join Team');
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(lead.verificationEmails, 1);
      expect(
        find.textContaining('Check your email for the verification link'),
        findsOneWidget,
      );
      expect(redemptions, 0);

      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(lead.verificationEmails, 1);
      expect(redemptions, 0);

      lead.verified = true;
      await tester.tap(join);
      await tester.pumpAndSettle();
      expect(redemptions, 1);
      expect(auth.signUps, 0);
      expect(auth.currentUser, same(lead));
    },
  );

  testWidgets('a new account is created only after the invite review', (
    tester,
  ) async {
    final auth = _TestAuth();
    var redeems = 0;
    final invites = InviteCodeRepository(
      callable: (name, data) async {
        if (name == 'inspectPrivilegedInvite') {
          return {
            'inviteId': 'invite-2',
            'teamId': 'team-1',
            'role': 'rep',
            'associationId': 'jba',
            'expiresAt': '2099-01-01T00:00:00.000Z',
          };
        }
        expect(name, 'redeemPrivilegedInvite');
        expect(auth.currentUser?.uid, 'team-rep');
        redeems++;
        return {};
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          inviteCodeRepositoryProvider.overrideWithValue(invites),
        ],
        child: const MaterialApp(home: JoinScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'test-invite');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Full Name'),
      'Team Representative',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rep@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'test-password',
    );
    final review = find.text('Review details');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('rep@example.com'), findsOneWidget);
    expect(find.text('test-password'), findsNothing);
    expect(auth.signUps, 0);
    expect(redeems, 0);

    await tester.tap(find.text('Join Team'));
    await tester.pumpAndSettle();
    expect(auth.signUps, 1);
    expect(redeems, 1);
  });
}
