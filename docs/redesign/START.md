# Alfaheem redesign: start here

You are implementing a full redesign of the Alfaheem app: Flutter (this repository) and the backend (`../back`). The design was made and reviewed with the owner in a separate session. Everything you need is in this folder, so you can work without that conversation.

## What is in `docs/redesign/`

| File | What |
|---|---|
| `design/` | The approved design: 117 interactive HTML screens (`*.dc.html`), `kit.css` and a small runtime (`support.js`). Open `design/index.html` to browse every screen. |
| `SCREENS.md` | Every screen by role (about 570), with the URL that opens it. |
| `RULES.md` | Client decisions, Saudi market rules, and **international users** (any nationality, any country). These are binding. |
| `DESIGN_SYSTEM.md` | The 5-second rules for student screens, the privacy contract, the motion language (16 patterns with CSS and Flutter equivalents) and the colour system. |
| `BACKEND.md` | What the server must add or change: the child's code login, teacher demand numbers, privacy enforcement, groups and genders, international support. |
| `PARITY.md` | How to make sure no existing feature is lost and every new design feature is built. |
| `CAST.md` | The demo people, subjects and times. Use them in seed data and goldens. |

### How to view the design

```bash
cd docs/redesign/design && python -m http.server 8765
# open http://localhost:8765/index.html  (each screen has a "phone" link that shows it at 390 px)
```

A screen is one component file plus query props, for example `Stu1Auth.dc.html?screen=kidcode&state=found`. The same file responds to phone (390 px) and web (1360 px) widths. The HTML and CSS are a **visual and behavioural reference**: do not port the HTML. Rebuild the screens in Flutter with the repository's kit. The Arabic copy in the design is approved by the client; use it exactly, and add English for every string.

## Ground rules (from this repository; do not break them)

- Read the root `CLAUDE.md`, `lib/design/README.md` and `docs/guides/ui-kit.md` first. All their rules still apply:
  - tokens instead of raw numbers;
  - `context.colors`;
  - `appText`;
  - `AppTime`;
  - kill switches;
  - `translation.json` with both `ar` and `en`;
  - no `dart format` on existing files;
  - `expectNoLayoutErrors` on new widgets;
  - the home request budgets;
  - the contract snapshots.
- The theme is server-driven (`GET /api/v1/theme/{platform}`). Put the new palette in the theme defaults **and** in the backend theme seed, so the server and the app agree. Never hard-code colours in widgets.
- Motion goes through one small library in `lib/design/` (see phase 1). It respects Reduce motion (`syncMotionLoop`, display settings).
- **This repository is a fork synced from NextBrain** (`sync/README.md`). A redesign of `lib/` will conflict with every future sync. Before phase 1, write this down as decision A-0xx in `docs/DECISIONS_ALFAHEEM.md` and ask the owner to confirm one of:
  - (a) Alfaheem diverges from NextBrain's UI from now on, and the sync merges only non-UI work;
  - (b) the redesign is done upstream in NextBrain, then synced here;
  - (c) the new UI lives in Alfaheem-only files behind the `sync/hooks.py` mechanism.

  Default if the owner does not answer: (a).

## Branches

- Front: create `feature/redesign` from `production` (CI runs on `feature/**`). Work in small commits, one screen group per commit, and push after each phase.
- Back: create the branch with the same name in `../back`.
- Never push to `production` or `main`, and never merge. The owner reviews and merges.

## Phases

Keep a tracker in `docs/redesign/PROGRESS.md`: one line per task, marked `todo`, `doing`, `done` or `verified`. On a resume, continue from its first task that is not done. Each phase ends green:
- `flutter analyze --no-fatal-infos --fatal-warnings`;
- the CI test suites;
- `flutter build web --release --base-href /app/`;
- the backend tests;
- golden or screenshot review of the changed screens at 390 and 1360 px, in Arabic and English.

0. **Inventory.**
   - Build `PARITY_TABLE.md` (PARITY.md).
   - Map every design screen to its Flutter file and route.
   - Check the BACKEND.md items against `../back` and mark which already exist.
   - Write the sync decision above.
   - Commit; this phase changes no UI.
1. **Kit.**
   - Tokens: the colour system, area accents, subject colours, radii and type scale from DESIGN_SYSTEM.md and `design/kit.css`.
   - The motion library: M1–M16 as reusable widgets or extensions.
   - The new hero, cards, buttons (jelly press), segmented pill, bottom sheet and the shells (sidebar on web, bottom nav on phone).
   - Each piece gets a layout-harness test.
2. **Student** (top priority; the owner's goal is ease of use for Saudi school students):
   - home, sign-up and login (including the child code), discover, learn, the subject page and its book, the دفتر, the lesson player, live, prejoin and attendance;
   - exams and analysis, schedule, messages (privacy), teachers, money, store, games, Quran and Nahw, profile.
3. **Booking and subject flow**: `BookFlow` and `SubjectProfile`, with all the wording rules in RULES.md §1.
4. **Parent**:
   - registration;
   - creating the child and the kid code with WhatsApp sharing;
   - today, kids, reports, alerts, pay, shared, more.
5. **Teacher**: home, courses, wizard, course, class, live, schedule, analysis, account, money, certificates, exams, teaching profile wizard, chat.
6. **Admin and super admin**: every screen in the design, plus every existing tool kept and restyled.
7. **Landing** (`landing/`, Astro):
   - the student, parent and teacher personas from `LandingW` and `LandingM`;
   - the teacher demand card fed by the new public endpoint; remove the card if the endpoint is not ready.
8. **International pass** (RULES.md §3): country of residence, phone for any country, curriculum per country, time zones, currency and payment methods per country, teacher documents and payouts. Test with a user in Egypt, the UAE and the UK as well as KSA.
9. **Final check.**
   - Walk every design screen against the app.
   - Re-run PARITY_TABLE (no unexplained removals).
   - Update `../back/data/app_features_guide.json` and the help pages.
   - Write a short report for the owner in `docs/redesign/REPORT.md`: what is done, what differs from the design and why, and what is waiting on the owner.

## Decisions you can make alone, and ones you cannot

- **Alone:** anything the design, RULES.md or the repository rules already settle; layout details the design leaves open; how to split widgets and providers.
- **Ask the owner** (list in REPORT.md and continue with the default):
  - removing an existing feature;
  - a payment-provider change;
  - anything that touches real users' data in production;
  - the sync decision.
- **Never:** store or print credentials, push to `production`/`main`, deploy, or run destructive commands on a real database.
