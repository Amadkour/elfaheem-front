# Learning Hub: final report

Date: 2026-11-21. Branch `feature/learning-hub` in both repositories (front 3dee4241, back 46ee092). Nothing is pushed and nothing is deployed. The Windows installer (branch `feature/lh-win`) is the one piece still being built.

## Where it stands

The features are built, reviewed and pass their tests on PostgreSQL. Two things stop me calling the job finished:

1. **The Downloads page does not yet offer every platform.** Android is built and signed but not published. Windows is still in progress. Linux AppImage, macOS and iOS are not built (reasons below).
2. **A few checks need a real device or your accounts**: a real card payment, the offline mode on a real phone, and Apple.

The list of fixes before the merge to production is at the end of `PROGRESS.md` ("Final gate").

## What was built

| Part | What you get |
|---|---|
| The add-student error | Fixed and already live: the identity type column was too short on the server database (migration 0101). |
| Education levels | Each country has its own stages, grades, tracks and subjects, edited by the super admin. Egypt and Saudi Arabia are loaded; nothing is fixed to one country. Registration, courses, filters, the store and games all read from these tables. |
| Course setup | A course names its country, levels, subject, online or in-person, and an area. The street address shows only after enrolment. |
| Landing page flow | A guest picks country, level and subject, sees matching courses, signs in and lands on the same course. |
| Store | Books, summaries and notes with VAT per country, card, points or free checkout, a personal library and protected downloads (a single-use link, a daily limit, files encrypted on the device). |
| Games | Three game types (match, order, quiz), stars, badges, optional point rewards with a daily cap, and a parent's view. |
| Quran | Teachers listed by gender, goal and session type. A program is a normal course, so booking, payment and sessions work as courses do. Progress by surah and juz. No Quran text is stored, only names and counts. |
| Arabic grammar | Levels, lessons and exercises with instant feedback, and an editor for the super admin. |
| Switches | Every new tab can be switched off for the platform, one country or one organization. The store, games and Quran rules (verification, review, gender matching, self-logging, download limit, point rewards) are switches with the same three levels. |
| Phone layout | The phone bar shows five places: Home, My courses, Learn, Schedule, Profile. "Learn" opens Store, Games, Quran, Grammar and Analysis. |
| Offline | A game play, a grammar attempt, a Quran progress entry and a study-profile edit made offline are kept on the device and sent when the connection returns. The lists the student already opened show while offline. Money is never taken offline. A small indicator shows offline, syncing and "needs attention". |
| Native apps | Android APKs and an AAB, signed with the same certificate as the app people already have. A Linux AppImage script, macOS and iOS build workflows, and a Windows installer in progress. A Downloads page on the landing site with version, size, date and checksum. |
| Privacy | A parent's consent for a minor is per parent and child, can be withdrawn, and is recorded. A parent sees only a linked child. Sensitive actions leave an audit row. Identity numbers are never kept on the device. Sign-out removes everything kept offline, after asking when unsent work remains. |
| Demo data | One command loads demo data and one removes it; it refuses to run on production. |

## What was installed

- App packages: `sqflite` and `sqflite_common_ffi` (the device database; they bring `sqlite3`).
- On this PC: Inno Setup, for the Windows installer (when that work finishes).
- Server database: migrations 0101 to 0108. 0101 is live; 0102 to 0108 run at the next backend deploy.

## Key decisions

- **A Quran program is a course.** Nothing about payment or sessions was built twice. Its rules are checked whoever enrols the student, staff included.
- **Tabs hide, flags change rules.** Both resolve platform, then country, then organization, and only the super admin sets them. A super-admin OFF always wins.
- **Game points are off by default**, because points buy services. When on, they are capped per day.
- **Game and grammar answers are checked on the device**, so they work offline. Exams keep server-side checking.
- **Offline covers four low-risk actions only.** The same action sent twice counts once. A refused action is dropped and the student is told once.
- **The device database is not encrypted**; paid files are. Identity numbers are stripped before anything is kept.
- **The Android signing key was not recreated.** It is at `~/.nextbrain-keys/nextbrain-release.jks` (with `key.properties` beside it), outside both repositories. Keep a backup of that folder: losing it means no update can ever replace the installed app.
- **The Windows installer is unsigned**, so Windows shows a SmartScreen warning; the page explains the steps.
- **The card form now charges in the course's currency.** Before, it could fall back to SAR under an EGP total. This is safe: the server already refuses a checkout whose gateway currency differs from the course's, and checks the charged currency again when it confirms the payment.

## What needs you

1. **Apple.** macOS and iOS need your Apple Developer account: the team id, certificates and an App Store Connect key, entered in Codemagic. `docs/release/APPLE.md` lists each item and where it goes. Until then there is no Mac or iPhone build.
2. **The old Android app.** The APK published today (1.0.0+1) was built under the old app id, so the new one installs beside it instead of replacing it. The plan: the old app's update message and the Downloads page tell people to install the new app, sign in, then remove the old one. Please confirm that wording. The version number is raised before publishing.
3. **Moyasar and EGP.** Moyasar is used for an EGP course only if you set its currency to EGP in the payment settings, and only if your Moyasar account accepts EGP. If it does not, leave EGP on Paymob.
4. **The server and new file types.** The server must accept and serve `.dmg` and `.AppImage` files (upload size and file type) before those can be published. The Linux AppImage itself has to be built on the server.
5. **The Firebase copy of the landing site.** Its Downloads page reads the release list from `nextbrain.site`, so the server must allow that origin (CORS), or the page shows no files there.
6. **One offline check on a real phone.** Turn on airplane mode, play a game, log a Quran entry, turn it off, and see both arrive. The test walk could not cut a real connection.
7. **One real card payment** for a course and for a store item after the deploy. No gateway keys exist on the test machine.
8. **A code-signing certificate for Windows** is optional and paid. Without it the SmartScreen warning stays.

## Known gaps

- Linux AppImage, macOS and iOS builds do not exist yet (items 1 and 4).
- The older parent pages (report, profile, overview) do not check consent. Adding the check now would lock out parents whose children have no date of birth. The new pages (games, Quran, grammar) do check it.
- A tab switched off for one country or one organization is hidden in the app, but the server refuses it only when it is off for the whole platform.
- Games have no editor screen; they are loaded from a file. Grammar has an editor.
- The "order" grammar exercise type is not shown by the app.
- Teacher earnings from store sales are not built; the store sells platform and organization items.
- On the web the app stays online-only.
- Not walked by hand: opening an owned store file offline, and a real loss of Wi-Fi.
- GitHub's automatic checks have not run since the billing limit; the checks were run on this PC.
