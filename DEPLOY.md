# HoopsConnect Deployment Guide

## Prerequisites

- **Firebase CLI** >= 13.x (`npm install -g firebase-tools`)
- **Flutter** >= 3.x (`flutter --version`)
- **Node.js** >= 18 (for Cloud Functions)
- Firebase project created at https://console.firebase.google.com
- Billing enabled (Blaze plan required for Cloud Functions)

---

## 1. Firebase Project Setup

### Initial Configuration

```bash
# Login to Firebase
firebase login

# Initialize project (if not already done)
firebase init

# Select: Firestore, Functions, Hosting (optional)
# Use existing project or create new one
```

### Enable Services in Firebase Console

1. **Authentication** -> Enable Email/Password, Google, Apple sign-in providers
2. **Firestore Database** -> Create database (production mode)
3. **Cloud Messaging** -> Enabled by default
4. **App Check** -> Enable and register apps (debug tokens for development)

### Register Apps

```bash
# Android
firebase apps:create android com.hoopsconnect.app --project YOUR_PROJECT_ID

# iOS
firebase apps:create ios com.hoopsconnect.app --project YOUR_PROJECT_ID

# Web
firebase apps:create web "HoopsConnect Web" --project YOUR_PROJECT_ID
```

Download and place config files:
- `google-services.json` -> `android/app/`
- `GoogleService-Info.plist` -> `ios/Runner/`
- Web config is set in `lib/firebase_options.dart` (via `flutterfire configure`)

---

## 2. Environment Configuration

### Flutter Firebase Config

```bash
# Auto-generate firebase_options.dart
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_PROJECT_ID
```

### Cloud Functions Environment

```bash
cd functions
npm install
```

No environment variables are required -- all configuration is read from Firestore.

### Create Initial Data

After deploying rules and functions, create the initial association document in Firestore Console:

```
associations/jba -> { name: "Jamaica Basketball Association", createdAt: ... }
```

Create a superAdmin invite code or directly set a user's role to `superAdmin` in the Firestore Console.

---

## 3. Deploy

### Deploy Order (first time)

Deploy in this order to avoid permission issues:

```bash
# 1. Security rules first
firebase deploy --only firestore:rules

# 2. Composite indexes
firebase deploy --only firestore:indexes

# 3. Cloud Functions
firebase deploy --only functions

# 4. (Optional) Hosting for web
firebase deploy --only hosting
```

### Deploy Everything

```bash
firebase deploy
```

### Deploy Individual Components

```bash
# Firestore rules only
firebase deploy --only firestore:rules

# Firestore indexes only
firebase deploy --only firestore:indexes

# All Cloud Functions
firebase deploy --only functions

# Single Cloud Function
firebase deploy --only functions:onGameStatsApproved
firebase deploy --only functions:onPostCreatedWithAck
firebase deploy --only functions:ackDeadlineChecker
firebase deploy --only functions:statDeadlineReminder
```

---

## 4. Build Apps

### Web

```bash
flutter build web --release
# Output: build/web/

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

### Android (APK)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Android (App Bundle for Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### iOS

```bash
flutter build ios --release
# Then open in Xcode for archive & upload:
open ios/Runner.xcworkspace
# Xcode -> Product -> Archive -> Distribute App
```

---

## 5. Verification Checklist

After deployment, verify:

- [ ] Firestore rules deployed (`firebase deploy --only firestore:rules` shows success)
- [ ] Indexes building (check Firebase Console -> Firestore -> Indexes)
- [ ] Cloud Functions deployed (check Firebase Console -> Functions)
- [ ] Scheduled functions registered (ackDeadlineChecker at 8AM, statDeadlineReminder at 9AM Jamaica time)
- [ ] App Check enforcement active (Firebase Console -> App Check)
- [ ] Auth providers enabled (Email, Google, Apple)
- [ ] Test sign-up flow with invite code
- [ ] Test post creation + ack notification
- [ ] Test stat entry + approval -> verify leaderboard/standings update
- [ ] Test role-based access (media user cannot create posts, rep cannot approve stats)

---

## 6. Monitoring

### Cloud Functions Logs

```bash
# All functions
firebase functions:log

# Specific function
firebase functions:log --only onGameStatsApproved

# Follow mode
firebase functions:log --follow
```

### Firestore Usage

Monitor in Firebase Console -> Firestore -> Usage tab. Stay within free tier limits:
- 50K reads/day, 20K writes/day, 20K deletes/day
- 1 GiB storage

---

## 7. Rollback Procedures

### Firestore Rules Rollback

Rules are versioned in git. To roll back:

```bash
# Revert to previous commit's rules
git checkout HEAD~1 -- firestore.rules
firebase deploy --only firestore:rules
```

### Cloud Functions Rollback

```bash
# Revert function code
git checkout HEAD~1 -- functions/src/
cd functions && npm run build
firebase deploy --only functions
```

### Emergency: Disable a Function

```bash
# Delete a specific function without redeploying
firebase functions:delete onGameStatsApproved --region us-central1

# Or disable from Firebase Console -> Functions -> kebab menu -> Disable
```

### App Rollback

- **Web:** Revert hosting to previous version in Firebase Console -> Hosting -> Release History -> Rollback
- **Android/iOS:** Publish a new build with the reverted code (no instant rollback for native apps). Consider staged rollouts on Play Store / TestFlight.

### Database Rollback

Firestore has no built-in rollback. For critical data:
1. Use Firestore scheduled exports: Firebase Console -> Firestore -> Export
2. Restore from export: `gcloud firestore import gs://YOUR_BUCKET/export-name`

---

## 8. Useful Commands Reference

```bash
# Check deployed rules
firebase firestore:rules:get

# Run functions locally (emulator)
firebase emulators:start --only functions,firestore

# Run Flutter with verbose logging
flutter run --verbose

# Clean Flutter build cache
flutter clean && flutter pub get

# Check Firebase project config
firebase projects:list
firebase use --list
```
