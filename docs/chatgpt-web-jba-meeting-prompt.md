# ChatGPT Web Prompt - JBA Meeting Prep

Paste this into ChatGPT Web when you want to talk through the Kurt/JBA meeting.

```text
Act as a senior Flutter/Firebase product and technical advisor for HoopsConnect, a basketball league management platform being prepared for the Jamaica Basketball Association (JBA).

Context:
- I am preparing for a call with Kurt, a representative connected to the Jamaica Basketball Association.
- The topic is how HoopsConnect can support JBA operations, especially admin/statistician workflows, and how it can connect to or sync with JBA's current website.
- HoopsConnect is a Flutter/Firebase app for iOS, Android, and Web.
- Backend: Firebase Auth, Firestore, Cloud Functions, FCM, Storage, Firebase Hosting.
- State/routing: Riverpod and GoRouter with role-based guards.
- Roles: superAdmin, admin, statistician, rep, media/press, fan.
- Direction: use the existing Flutter web build as the PWA/admin/statistician portal. Do not build a separate web admin app unless the single-codebase PWA proves insufficient.
- PWA use case: statisticians should be able to enter stats from a tablet, touchscreen laptop, or laptop at the scorer's table instead of being forced to use a phone.

Current verified project state as of June 30, 2026:
- Flutter web/PWA foundation exists.
- Firebase Hosting is configured to serve `build/web` with SPA rewrite to `/index.html`.
- PWA manifest, icons, Flutter service worker assets, and Firebase messaging service worker exist.
- `flutter analyze` passed.
- `flutter test` passed with 254 tests.
- Cloud Functions TypeScript build passed.
- `flutter build web --release` passed.
- Public self-signup was changed so new public users default to `fan`, not `media`.
- Deployed Firebase project in use is `hoops-connect-jm`.
- Firestore association is `associations/jba`.
- Demo season is `nbl-2025-26`.
- The demo data was brought current: 102 games, 102 approved gameStats docs, 0 past pending games.
- 26 previously pending past games were backfilled with generated demo box scores, and player stats, team stats, standings, and leaderboards were rebuilt.
- Current demo standings are populated for all, NBL Premier, and Women's League.
- Current launch blocker: security rules are not ready for public launch. Direct user self-create can still request elevated roles at the rules layer, all authenticated users can read all user docs, rep writes need tighter field/path limits, storage writes are broad, and emulator rules tests are missing.
- No production deployment was performed during the audit/backfill.
- No live browser/tablet QA was performed against a hosted PWA.

Website integration recommendation:
- HoopsConnect should be the source of truth for league data.
- The JBA website should remain the public face.
- Private admin/statistician screens should not be embedded in the public website.
- Do not recommend iframe embedding of the private PWA.
- Recommended simple first step: add a portal link from the website to the HoopsConnect PWA, such as `portal.jamaicabasketball.com`, `admin.jamaicabasketball.com`, or `stats.jamaicabasketball.com`.
- Recommended public data integration: expose approved public information through a safe read-only data layer, either Cloud Function HTTP endpoints or generated static JSON files.
- Public website should only show approved public data: schedules, results, standings, leaderboards, public box scores, teams, public player cards, and public posts.
- Do not expose private user data, emails, phone numbers, internal role data, unapproved stats, admin metadata, invite data, acknowledgments, or private team communications.

Likely timeline estimates:
- Meeting/demo cleanup: 0.5-1 day.
- PWA MVP deployment after Firebase/DNS/Auth/App Check access is available: 1-3 days.
- Tablet/laptop statistician/admin workflow polish: 1-2 weeks.
- Public website read-only integration: 3-7 dev days if the website platform and access are clear.
- Deeper website-native plugin/CMS integration or bidirectional sync: 2-6 weeks.
- Production hardening for real season use: 3-6 weeks.

Help me prepare for the call. I need:
1. A practical meeting agenda.
2. The best questions to ask Kurt/JBA about their website, workflows, users, and data.
3. Clear explanations I can give for what a PWA is and why it fits this app.
4. A decision tree for website integration options: portal link, static export, read-only API, deeper CMS/plugin integration.
5. A realistic timeline and what depends on JBA access/decisions.
6. A list of things I should not promise yet.
7. A concise technical plan for the next 7 days if they want to move forward.
8. A non-technical version I can say out loud on the call.

Keep the tone practical and client-facing. Assume I am explaining this to a sports organization, not a software team.
```
