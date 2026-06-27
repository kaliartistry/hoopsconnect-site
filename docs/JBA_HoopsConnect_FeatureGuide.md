# JA HoopsConnect — Feature Guide

### A Complete Basketball League Management Platform for the Jamaica Basketball Association

---

## Introduction

HoopsConnect is a mobile and web application purpose-built for the Jamaica Basketball Association. It replaces spreadsheets, WhatsApp groups, and word-of-mouth with a single platform where everyone — administrators, team representatives, statisticians, media, and fans — has the tools they need.

**Who uses it and what they see:**

| Role | What They Can Do |
|------|-----------------|
| **Admin** | Manage the entire league — stats, schedules, users, divisions |
| **Team Rep** | Post team updates, acknowledge notices, view their team's stats |
| **Statistician** | Enter and manage game statistics |
| **Media / Press** | Access press tools, generate game summaries, export stats |
| **Fan** | Follow standings, leaderboards, schedules, and box scores |

---

## Section 1: Getting Started

**Download the app:**
- iPhone users: Tap the TestFlight link provided by the JBA
- Android users: Join via the Google Play internal testing link

**Create your account:**
- Sign up with your email, Google account, or Apple ID
- It takes less than 30 seconds

**Join with an invite code:**
- Team reps, statisticians, and media receive a 6-character invite code from the JBA
- Enter the code during signup to be assigned your role and team automatically
- No code needed to join as a fan — just sign up and start following the league

---

## Section 2: The Board — Your Communication Hub

The Board is where the JBA communicates with everyone in the league.

**What you'll find:**
- Season announcements and schedule updates
- Venue changes and referee assignments
- Urgent notices that require acknowledgment

**Acknowledgment tracking:**
- When the JBA posts a critical notice (e.g., "Roster lock deadline is March 31"), it can require every team rep to acknowledge they've seen it
- Admins can track exactly who has and hasn't acknowledged — no more chasing people on WhatsApp
- Automatic reminders are sent to anyone who hasn't acknowledged before the deadline

**Why it matters:**
- No more "I didn't see the message" — there's a clear record
- Saves hours of follow-up calls and messages
- Every team rep is accountable

---

## Section 3: Stats & Box Scores — The Game Changer

This is the heart of HoopsConnect. Every game gets a full statistical record.

**How stat entry works:**
1. After a game, the statistician opens the app and selects the game
2. A grid appears with every player on both teams
3. For each player, enter: Points, Rebounds (offensive + defensive), Assists, Steals, Blocks, Fouls, Minutes
4. The app automatically calculates team totals and validates the numbers
5. Save as a draft, then submit for approval
6. Once an admin approves, the stats go live — standings update, leaderboards recalculate, and the box score becomes available to everyone

**Live stats mode:**
- For games where a statistician is present courtside, there's a real-time recording mode
- Tap actions as they happen: 2-point make, 3-point miss, rebound, assist, foul
- The app tracks the clock, manages substitutions, and detects foul-outs
- At the end of the game, it generates the full box score automatically

**Why it matters:**
- Every game has a permanent, detailed record
- Players build a statistical profile over the season
- Coaches can review performance game by game
- Scouts can evaluate players with real data, not just word of mouth

---

## Section 4: Leaderboards & Player Cards

**League leaders at a glance:**
- Points Per Game (PPG)
- Rebounds Per Game (RPG)
- Assists Per Game (APG)
- Steals Per Game (SPG)
- Blocks Per Game (BPG)

Filter by division or view league-wide. Updated automatically after every approved game.

**Player cards:**
- Tap any player's name to see their full profile
- Season averages across all categories
- Game-by-game log showing performance in every game played
- Which team they play for, games played, and trends over time

**Why it matters:**
- This is exactly what college scouts and professional teams look for
- A player card is a digital resume — shareable, verifiable, always up to date
- For the first time, a Jamaican basketball player's stats are accessible to anyone in the world

---

## Section 5: Standings & Schedules

**Live standings:**
- Win-Loss record, win percentage, games behind the leader
- Current streak (W3, L2, etc.) and last 10 games record
- Points for and points against averages
- Top 4 teams highlighted as playoff contenders

**Season calendar:**
- Month view or list view — choose what works for you
- Tap any past game to view the box score
- Upcoming games show date, time, venue, and teams
- Navigate forward and backward through the entire season

**Schedule generation:**
- Admins can auto-generate a full round-robin schedule
- Choose single, double, or triple round-robin format
- Set game days (e.g., Tuesday, Thursday, Saturday) and time slots
- The app calculates all matchups and assigns them to available dates
- Individual games can also be added manually for playoffs or special events

---

## Section 6: Team Management

**For admins:**
- Create and manage divisions (Premier, Women's, etc.)
- Add teams to divisions
- Generate invite codes for team reps — each code is tied to a specific team and role
- Manage user roles across the league

**Invite code system:**
- Generate codes with specific roles: rep, media, admin, statistician, press
- Set usage limits (1 use, 5 uses, 25 uses) and expiration dates
- When someone signs up with a code, they're automatically assigned to the right team with the right permissions
- No manual user setup needed

**Why it matters:**
- Onboarding a new team rep takes seconds, not meetings
- Role-based access means everyone sees only what they need
- One admin can manage the entire league from their phone

---

## Section 7: Press & Media Tools

**Press credential card:**
- Accredited media members get a digital press credential in the app
- Shows their name, email, and season accreditation

**Game summaries:**
- Auto-generated narrative summaries for any completed game
- Includes final score, top performers, and key stats
- Copy to clipboard and paste into articles, social media, or reports

**Head-to-head comparison:**
- Compare any two teams or any two players side by side
- Stats comparison across all categories
- Recent matchup history

**Stats export:**
- Download or share statistical data for reporting

---

## Section 8: Push Notifications

The app sends automatic notifications so nobody misses what matters:

- **New announcements** — When the JBA posts to the board
- **Acknowledgment reminders** — If you haven't acknowledged a required notice
- **Stat entry reminders** — When a game needs stats entered
- **Game day alerts** — Upcoming game notifications

Notifications can be customized in Settings — turn on what you want, turn off what you don't.

---

## Section 9: What It Costs to Run

HoopsConnect is built on **Firebase**, Google's cloud platform. This means:

- **No servers to buy or maintain** — everything runs in Google's cloud
- **No software licenses** — the app is custom-built for the JBA
- **No IT staff needed** — the system manages itself
- **Automatic scaling** — handles 100 users or 10,000 users without any changes

**The only cost is the cloud database:**

| Users | Monthly Cost | What's Included |
|-------|-------------|----------------|
| Up to 1,000 | **Free** | 50,000 database reads/day, push notifications, cloud functions |
| 5,000 | **$0 - $5** | Well within free tier for a basketball league |
| 10,000 | **$2 - $15** | Still minimal — less than a referee's game fee |
| 50,000 | **$20 - $80** | Only if the league grows massively |

Budget alerts can be configured so the JBA is notified before any charges are incurred. At the scale of Jamaican basketball, the app runs effectively for free.

---

## Section 10: The Vision — Why This Matters

### The Problem

Jamaica produces exceptional basketball talent. Every year, players compete in the NBL, in high school leagues, and in pickup games across the island with skill, athleticism, and heart that rival anywhere in the Caribbean. But almost none of them are seen beyond Jamaica's borders.

There are no accessible stats. No player profiles. No way for a college coach in Florida or a professional team in Sao Paulo to look up a player's season averages and decide they want to take a closer look. The talent is there — the visibility is not.

### The Person Behind It

**Kali McCarthy** understands this problem intimately. As a former Jamaica national team player, NBL player, junior national team player, high school player, college basketball player in the United States, and professional overseas — Kali has lived every stage of the basketball journey from Kingston to the world.

That experience revealed a clear truth: the gap between Jamaican basketball and international recognition is not a talent gap. It's a systems gap. Countries with proper stats tracking, digital player profiles, and accessible league data produce more recruited players — not because they have better talent, but because their talent is visible.

### The Solution

HoopsConnect gives every Jamaican basketball player a digital footprint. When a player scores 25 points on a Saturday night in Kingston, that performance is recorded, calculated into their season averages, and accessible to anyone with the app or a web browser.

### The Opportunity

With HoopsConnect in place:

- **US and Canadian colleges** can follow a player's development over an entire season, not just a single showcase event. They can see consistency, improvement, and character through the numbers.

- **International professional teams** from Brazil, Argentina, Mexico, and across the Americas — leagues that actively recruit Caribbean talent — can identify and track players they want to sign.

- **Players themselves** have something to show. A link. A player card. Proof of what they've done.

### A Contribution, Not a Contract

This app is not a business proposal. It is a **contribution** from someone who loves Jamaica's basketball and believes in its potential. Kali McCarthy built HoopsConnect and is donating it to the JBA because proper systems create proper opportunities — and Jamaica's players deserve both.

---

## Get Started

The app is available now:

- **iPhone**: Download via TestFlight (link provided by JBA)
- **Android**: Download via Google Play internal testing (link provided by JBA)

For questions, feedback, or to request invite codes, contact the JBA administration.

---

*JA HoopsConnect — Built with love for Jamaica basketball.*
