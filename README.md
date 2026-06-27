# HoopsConnect

HoopsConnect is a Flutter/Firebase app for Jamaica basketball league operations.
It supports board posts, acknowledgments, schedule management, standings,
leaderboards, live stats entry, post-game stat entry, press tools, and role-based
admin workflows across iOS, Android, and web.

## Current Direction

GitHub should be the canonical source of truth for both local VS Code/Copilot
work and Codex handoff work. This workspace currently contains GitHub workflow
files, Firebase config, Fastlane lanes, and deploy docs, but may need to be
initialized or reconnected to the real GitHub remote before collaboration starts.

The web target is the planned admin/statistician PWA. Keep one Flutter codebase
and improve the existing web build for larger screens instead of creating a
separate admin app.

## Tech Stack

- Flutter / Dart
- Firebase Auth, Firestore, Cloud Functions, FCM, Storage, App Check, Crashlytics
- Riverpod for state management
- GoRouter with role-based route guards
- Fastlane for Firebase App Distribution, TestFlight, and Google Play internal testing

## Key Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter build web --release
npm --prefix functions run build
```

Run the web app locally with:

```bash
flutter run -d chrome
```

## Collaboration And Handoff

- Codex handoff guide: [docs/CODEX_HANDOFF.md](docs/CODEX_HANDOFF.md)
- Deployment guide: [DEPLOY.md](DEPLOY.md)
- Backlog: [BACKLOG.md](BACKLOG.md)
- Agent/project conventions: [AGENTS.md](AGENTS.md)

Before pushing this workspace to GitHub, audit tracked files for secrets. Local
signing keys, App Store Connect keys, Google Play service account JSON files,
and environment files must stay out of version control.
