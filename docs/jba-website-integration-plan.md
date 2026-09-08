# JBA Website Integration Plan

Date: 2026-06-30

Status: PASS with NEEDS-DECISION items for website platform, access, and public data policy.

## Recommendation

HoopsConnect/Firebase should be the source of truth for league operations. The JBA website should be a public read-only display of approved HoopsConnect data.

Do not iframe the private PWA into the JBA website. Current hosting headers block iframe embedding, and that is appropriate for a private admin/statistician portal.

Do not open private Firestore collections to the public website.

## Option A - Simple Portal Link

Add a link from the JBA website to the private portal.

Possible labels:

- `Admin Portal`
- `Stats Portal`
- `League Operations Login`

Recommended for first launch because it is low-risk and does not require public data architecture.

## Option B - Public Read-Only API

Create Cloud Function HTTP endpoints that return approved public data only.

Possible endpoints:

- `GET /public/jba/schedule`
- `GET /public/jba/standings`
- `GET /public/jba/leaderboards`
- `GET /public/jba/games/{gameId}/boxscore`
- `GET /public/jba/teams`
- `GET /public/jba/teams/{teamId}`
- `GET /public/jba/players/{playerId}`
- `GET /public/jba/posts`

Rules:

- Return only approved public data.
- Do not require public users to authenticate.
- Do not expose private fields.
- Add cache headers.
- Add CORS intentionally, ideally limited to approved JBA domains.
- Version the response shape.

## Option C - Scheduled Static JSON Export

Export approved public data to static JSON files.

Possible files:

- `/public-data/jba/schedule.json`
- `/public-data/jba/standings.json`
- `/public-data/jba/leaderboards.json`
- `/public-data/jba/teams.json`
- `/public-data/jba/posts.json`

Good for:

- Lower Firestore read cost.
- Lower abuse risk.
- Fast public website loading.
- Simple integration with WordPress, Wix, Squarespace, or a static/custom site.

Recommended first public data approach if the JBA website platform is limited or unknown.

## Option D - Website-Native Widgets/Pages

Once public data exists, build widgets/pages based on their actual website platform:

- WordPress plugin/shortcodes.
- Wix custom embed.
- Squarespace code block.
- Custom JavaScript widgets.
- React/Vue/Next pages.

## Option E - Bidirectional Sync

Not recommended unless JBA already has another authoritative website/CMS data system.

Reasons:

- Creates conflict resolution problems.
- Risks stale or duplicate official data.
- Makes game-day operations harder to reason about.

## Website Platform Questions

- What platform powers the current JBA website?
- Who controls DNS and hosting?
- Who can add scripts/widgets/pages?
- Can the site fetch external JSON/API data?
- Are there CSP restrictions on the current website?
- What public pages do they want first: schedules, standings, leaderboards, box scores, teams, players, posts?
- How often should public data update?
- Are player photos, ages, bios, or schools public?
- Are any players minors?

## Timeline Estimate

- Simple portal link: same day once URL exists.
- Public JSON/API first version: 3-7 dev days after public fields and website access are known.
- Website-native widgets/pages: 1-2 additional weeks depending on platform.
- Deep CMS/plugin integration or bidirectional sync: 2-6 weeks.

## What Not To Promise

- Do not promise the public website integration is already complete.
- Do not promise the website can safely read private Firestore collections directly.
- Do not promise iframe embedding is recommended.
- Do not promise bidirectional sync without reviewing the existing website/CMS data model.

