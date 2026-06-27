# HoopsConnect - Jamaica Basketball App

## Tech Stack
- **Framework:** Flutter (Dart)
- **Backend:** Firebase (Firestore, Auth, Cloud Functions, FCM, Storage)
- **State Management:** flutter_riverpod
- **Routing:** go_router with role-based guards
- **Platforms:** iOS, Android, Web

## Project Structure
Feature-first folder organization under `lib/`:
- `app/` - App shell, router
- `core/` - Constants, theme, utils
- `models/` - Data models (Firestore serialization)
- `providers/` - Riverpod providers
- `services/repositories/` - Firestore repository classes
- `features/` - Screen groups (auth, board, ack, stats, calendar, team, admin)

## Key Conventions
- Repository pattern for all Firestore access (use `withConverter`)
- Provider dependency tree rooted at `authStateProvider`
- All Firestore paths centralized in `firestore_paths.dart`
- Green theme (#2E7D32 primary, #1B5E20 dark) throughout — Jamaican national colors
- 6 user roles: superAdmin, admin, statistician, rep, media/press, fan

## Reference Documents
- Full design spec: `~/.Codex/projects/-Users-kaliartistry-mac-Jamaica-Basketball-App/memory/hoops-connect-plan-v3-reference.jsx`
- Contains: Wireframes (13 screens), Firestore data model, Cloud Functions, user flows, 8-phase roadmap
- Codex handoff guide: `docs/CODEX_HANDOFF.md`

## Source Of Truth
- GitHub should be the canonical source of truth for Codex, Copilot, and local development.
- This workspace may need to be initialized or reconnected to the GitHub remote before collaborative work starts.
- Keep local signing keys, App Store Connect keys, Google Play/Firebase service account JSON, and `.env` files out of version control.
- Use feature branches / pull requests; CI must pass before merging to `main`.

## PWA Direction
- Use the existing Flutter web target as the admin/statistician PWA.
- Do not split admin/stat workflows into a separate web app unless the single-codebase PWA proves insufficient.
- Prioritize large-screen stat entry, acknowledgment tracking, and admin table workflows.

## Commands
- `flutter run` - Run on connected device
- `flutter run -d chrome` - Run on web
- `flutter test` - Run tests
- `flutter build web` - Build for web
- `npm --prefix functions run build` - Build Cloud Functions
- `firebase deploy --only functions` - Deploy Cloud Functions
- `firebase deploy --only firestore:rules` - Deploy security rules
