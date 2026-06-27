# HoopsConnect Backlog

> Living checklist for future features, audits, and builds.
> Check items when completed. Add new ideas at the bottom of the relevant section.
> Last reviewed: 2026-03-13

---

## Production Blockers

- [ ] Cloud Functions: `onGameStatsApproved` (recompute player averages + rebuild leaderboards)
- [ ] Cloud Functions: `onPostCreatedWithAck` (populate expectedAcks + send FCM push)
- [ ] Cloud Functions: `ackDeadlineChecker` (scheduled — check overdue acks, send reminders)
- [ ] Cloud Functions: `statDeadlineReminder` (scheduled — remind admin of missing stats)
- [ ] Enable Firestore offline persistence in `main.dart`
- [ ] Add Crashlytics / Sentry error logging
- [ ] Separate Firebase projects (dev / staging / prod)
- [ ] Firebase App Check (prevent API abuse)

## Testing

- [ ] Unit tests for repositories (AuthRepository, StatsRepository, PostRepository)
- [ ] Widget tests for critical flows (login, stat entry, post creation)
- [ ] Integration tests for auth + onboarding flow
- [ ] CI/CD pipeline (GitHub Actions: analyze, test, build)
- [ ] Test coverage target (minimum 70%)

## Validation & Security

- [ ] Email regex validation on login / join screens
- [ ] Password strength requirements on signup
- [ ] Stat range validation on stat entry grid (e.g. max 100 pts, max 48 min)
- [ ] Max-length constraints on text inputs (title, body, player names)
- [ ] Server-side validation in Cloud Functions
- [ ] Firestore security rules audit (field-level access, rate limiting)
- [ ] Penetration test on security rules

## Missing Screens

- [ ] User Profile screen (view/edit own profile, change display name)
- [ ] Settings / Preferences screen (notification prefs, theme, about/legal links)

## Feature Ideas

- [ ] Dark mode toggle
- [ ] Season archive / history browsing
- [ ] Export stats to CSV from leaderboard
- [ ] Photo upload for posts (Firebase Storage)
- [ ] Team logo upload
- [ ] Player photo upload
- [ ] Deep linking to specific posts / games
- [ ] Offline stat entry with sync queue
- [ ] Multi-association support (remove hardcoded 'jba')
- [ ] Localization (English + Patois?)
- [ ] Web admin dashboard (separate Flutter web target)
- [ ] Accessibility audit (semantics, contrast ratios)
- [ ] Performance: pagination on board feed
- [ ] Performance: lazy-load leaderboard tabs
- [ ] Reaction system on posts (like, fire, etc.)

## Code Quality

- [x] Centralize all hardcoded values into `AppDefaults` / `AppColors`
- [ ] Add `dart_code_metrics` or `custom_lint` rules
- [ ] Add pre-commit hooks (analyze + format)
- [ ] Reusable error/loading state widgets
- [ ] Consistent error handling pattern across repositories (custom `AppException`)

## Infrastructure

- [ ] Rate limiting on Cloud Functions
- [ ] Firestore composite indexes audit
- [ ] Backup strategy for Firestore data
- [ ] Firebase Analytics events for key actions
- [ ] Monitoring & alerting in Firebase Console
- [ ] Document deployment and rollback procedures
