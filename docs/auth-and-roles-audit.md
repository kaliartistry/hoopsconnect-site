# Auth And Roles Audit

Date: 2026-06-30

Status: PASS

## Summary

Auth and route guards are present and suitable for the private admin/statistician PWA path. One confirmed issue was fixed: ordinary public self-signup now defaults to `fan`, not `media`.

## Current Roles

Defined in `lib/models/user_model.dart`:

- `superAdmin`
- `admin`
- `rep`
- `media`
- `statistician`
- `press`
- `fan`

The app currently treats `media` and `press` as aliases:

- `UserModel.isMedia` returns true for `media` and `press`.
- `UserModel.isPress` is an alias of `isMedia`.
- `canAccessPressTools` is true for media/press users and admins.
- Firestore rules include `isPress()` for both `press` and `media`.

## Signup Default Fix

Fixed:

- `AppDefaults.defaultSignupRole` changed from `UserRole.media` to `UserRole.fan`.
- Login/signup comments updated to describe public self-signup.
- Added test coverage asserting public self-signup defaults to `fan`.

Files changed:

- `lib/core/constants/app_constants.dart`
- `lib/services/repositories/auth_repository.dart`
- `lib/features/auth/login_screen.dart`
- `test/models/user_model_test.dart`

This matters because public signup must not grant media/press tools by default.

## Role Guard Findings

Verified in `lib/app/router/app_router.dart`:

- Unauthenticated users are redirected to `/login`.
- `/admin*` routes require `canAccessAdminPanel`.
- Super-admin-only screens redirect non-super-admin admins back to `/admin`.
- `/live-stats` requires `canEnterStats`.
- `/press` requires `canAccessPressTools`.
- Press summary routes are available to media/press users and admins who can approve stats.

Admin/statistician PWA implication:

- Admins can access the admin panel and stats approval/entry flows.
- Statisticians can access live stats and stat entry, but cannot approve stats.
- Fans do not receive admin/stat/press permissions.

## Firestore Rules Findings

Verified in `firestore.rules`:

- Users cannot self-assign `admin` or `superAdmin` at create time.
- Self-updates cannot change `role` or `associationId`.
- Admins can update users, but only super admins can assign `superAdmin`.
- Stats creation/update is limited to admins and statisticians.
- Stats approval/rejection is limited to admins.
- Admin-only collections and write paths are guarded.

Risk:

- Rules allow authenticated self-create with `media`, `press`, `rep`, `statistician`, or `fan` if a malicious client writes directly to Firestore. The app UI now defaults to `fan`, but the rule still trusts the requested non-admin role on direct create. Before public launch, tighten self-create to require `fan` unless the role is assigned through an invite-code flow or a trusted backend.

## Canonical Media/Press Recommendation

Recommended canonical stored role going forward: `media`.

Reason:

- The UI labels the tab and invite role as `Media`.
- Invite-code management currently creates `media` role codes.
- Existing `press` users can remain supported as a legacy alias.

Backward compatibility plan:

1. Keep `press` in the enum for now.
2. Keep `isMedia`/`isPress` treating both values as equivalent.
3. Generate new invite codes with `media`.
4. Optionally run a reviewed Firestore migration later to convert `press` user docs to `media`.
5. Only remove `press` after production data has been audited and migrated.

## Permission Risks

- Direct Firestore self-create can still request elevated non-admin roles such as `statistician` or `rep`; this should be tightened before public launch.
- User reads are currently allowed for any authenticated user. This may expose emails/phones/display names to fans unless UI/API boundaries prevent it. Review before public launch.
- The `media`/`press` alias is safe for not locking out existing users, but it should be standardized before long-term production use.

## Tests Added Or Updated

- Added `UserRole` test asserting `AppDefaults.defaultSignupRole == UserRole.fan`.

## Verification

- `flutter analyze`: PASS
- `flutter test`: PASS, 254 tests
- `flutter build web --release`: PASS

