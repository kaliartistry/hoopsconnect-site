import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/firestore_paths.dart';
import '../../firebase_options.dart';
import '../../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Stream<UserModel?> watchUser(String userId) {
    return _db.doc(FirestorePaths.user(userId)).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserModel.fromFirestore(snap);
    });
  }

  Future<UserModel?> getUser(String userId) async {
    final snap = await _db.doc(FirestorePaths.user(userId)).get();
    if (!snap.exists) return null;
    return UserModel.fromFirestore(snap);
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sign in with Google. Creates a user doc if one doesn't exist.
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      final userCred = await _auth.signInWithPopup(googleProvider);
      await _ensureUserDoc(userCred);
      return userCred;
    }

    final googleUser = await _googleSignIn().signIn();
    if (googleUser == null) return null; // User cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    await _ensureUserDoc(userCred);
    return userCred;
  }

  /// Sign in with Apple. Creates a user doc if one doesn't exist.
  Future<UserCredential> signInWithApple() async {
    if (kIsWeb) {
      final appleProvider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final userCred = await _auth.signInWithPopup(appleProvider);
      await _ensureUserDoc(userCred);
      return userCred;
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider(
      'apple.com',
    ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

    final userCred = await _auth.signInWithCredential(oauthCredential);

    // Apple only provides name on first sign-in
    if (appleCredential.givenName != null) {
      await userCred.user?.updateDisplayName(
        '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'
            .trim(),
      );
    }

    await _ensureUserDoc(userCred);
    return userCred;
  }

  /// Ensure a Firestore user document exists for this auth user.
  /// If not, create one with fan role (default for public self-signup).
  Future<void> _ensureUserDoc(UserCredential cred) async {
    final uid = cred.user!.uid;
    final snap = await _db.doc(FirestorePaths.user(uid)).get();
    if (snap.exists) return;

    final user = UserModel(
      id: uid,
      email: cred.user!.email ?? '',
      displayName: cred.user!.displayName ?? 'User',
      associationId: AppDefaults.defaultAssociationId,
      role: AppDefaults.defaultSignupRole,
    );
    await createUserDoc(user);
  }

  Future<void> createUserDoc(UserModel user) {
    return _db.doc(FirestorePaths.user(user.id)).set(user.toFirestore());
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) {
    return _db.doc(FirestorePaths.user(userId)).update(data);
  }

  /// Get all users (for admin user management).
  Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.collection(FirestorePaths.users()).get();
    return snap.docs.map((d) => UserModel.fromFirestore(d)).toList();
  }

  Future<void> signOut() => _auth.signOut();

  GoogleSignIn _googleSignIn() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return GoogleSignIn(clientId: DefaultFirebaseOptions.macos.iosClientId);
    }
    return GoogleSignIn();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
