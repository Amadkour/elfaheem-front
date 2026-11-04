# Super Admin dashboard — audit (Phase 0, 2026-11-04)

Read-only walk through every Super Admin page on `organizations` d6d6668: the code (4 parallel audits, every
"broken" item checked in the source) and the real web app on the local stack (screenshots in `screenshots/audit/`,
git-ignored). Pages owned by other sessions are listed once at the end.

Legend: **B** bug · **UX** usability · **M** missing · **R** redundant (→ the approval list at the end).

## Cross-cutting

| # | Issue | Where |
|---|---|---|
| X1 | **B** the filter bar, search box, chips and filter sheet hard-code the `tajawal` font (D-072: the person's font choice is ignored there) | `admin_filters.dart:21` (10 uses) |
| X2 | **B** raw exception text shown to the user (`'$e'`, `toast('$e')`) instead of `ApiException.from(e).message` | auth settings, required documents, content, income breakdown, data lab |
| X3 | **B** a failed load looks like "empty" (no error, no retry): data center, requirements, parent request detail (endless skeleton), auth settings (worse: see S2) | |
| X4 | **B** a refresh wipes good data and flashes a skeleton (admins list, payouts after every action, data lab, platform fee list) | `admin_providers.dart:1186`, `admin_admins_page.dart:200` |
| X5 | **UX** 4 different page headers (ScreenAppBar, PremiumHero, AppHero, custom heroes) and 4 save patterns (floating button, action bar, inline button, save-on-tap) | every config page |
| X6 | **UX** no unsaved-changes guard on any settings page (back silently discards) | platform, live, recommendations, flags, theme editor, parent-link settings |
| X7 | **UX** irreversible / platform-wide switches without a confirm: automatic payout transfer, allow-all-teachers payouts, disabling a payment method, default gateway, fee policy and fee rates, Data Lab master switch, hiding a feature for everyone, approving an ad (hard-coded `paid: true`) | finance, config |
| X8 | **UX** ±1 steppers for values up to 1 000 – 100 000 (999 taps), 28–38 px touch targets | devices, flags, data lab, required documents pills |
| X9 | **M** no global search; the web hubs (38 services) have no search while the phone "More" page does | shell, hubs |
| X10 | **M** hub tabs have no Refresh in the top bar; pull-to-refresh is invisible with a mouse | `admin_dashboard_screen.dart:216` |
| X11 | code: 3 search boxes, 3 chip widgets, 2 steppers, 2 money formatters (one without thousands separators), 4 "trim .0" helpers, 3 hand-rolled paged lists, ~100 raw spacing / radius numbers per page | see Part A |

## Shell, Overview, people

| Page | Purpose | Main findings |
|---|---|---|
| Shell | 9 tabs wide / 5 on phone | **B** pull-refresh on Students/Teachers re-creates the page (filters, search and scroll lost) · **UX** Finance + Support (the badge-bearing areas) are behind More on phones · **M** X9, X10 |
| Overview | KPIs, needs-you, charts, health | **B** "Users" tile counts students+teachers but opens Students only · **B** duplicate money formatter · **UX** failed-jobs alert ends in a read-only sheet · live-event reloads not debounced · **M** no period selector, no teachers KPI |
| Students / Teachers | paged list, filters, detail sheet | **B** "Activate" drawn red · `null` shown for missing experience years, raw server codes for teaching/payment type · count chip without `countText` · 1 s search debounce · **UX** status filtered 3 ways at once, the header (search + chips + 2 chip rows) does not scroll and eats a small phone · Delete sits next to Edit with the same weight |
| Admins | super-admin CRUD of admins | **B** `loadingMore` stays true after a search during a page load → pagination dead until reopened · failed refresh wipes the list and hides the error |
| View as | pick a user to view as | third hand-rolled paged list, raw `'$e'`, no filters (**R1**) |
| My account | own profile / password | **B** controllers touched / `setState` after dispose when leaving mid-load or mid-save · **M** no current-password check, no sessions list |
| MFA | two-step sign-in | fine (minor: unawaited clipboard) |
| Data center | browse / export any dataset | **B** switching dataset keeps the old header over an empty body; no request token (slow answer lands in the wrong dataset); failure = "no data"; cancelling the date picker clears the filter; export double-tap · plaintext passwords after import with no copy-all |
| Requirements | ack/info items users must accept | **B** failure shows the empty state; no validation; controllers leak; double submit |
| Ads | approve / reject ads, teacher-ads rules | **B** approve sends `paid: true` with no choice or confirm; price typo silently becomes 0 (= free) · emoji used as icons |
| Send message | broadcast email / push / dialog | **B** title field uses the `video_title` label · picker capped at 30 people, no paging · **M** "will reach N" before sending |
| Categories | CRUD | **B** deleting a category that has courses gives the generic confirm · **M** no parent picker (sub-categories can't be created here) |
| Parent requests | review link requests | **B** a failed detail load = endless skeleton · hard casts on optional keys |
| Parent-link settings | verification mode | **B** controllers disposed while the dialog animates out; empty/duplicate keys accepted; delete without confirm |

## Finance

| Page | Main findings |
|---|---|
| Payouts | **B** the currency is never shown, also in the "approve and send" confirm that moves real money (`payout_currency` is ignored) · every action clears the list (skeleton, scroll lost) · no request guard on the status filter · `double.tryParse` rejects Arabic digits for the minimum · **UX** auto-transfer switch saves instantly with no confirm · **M** search by teacher, total of pending money |
| Points & wallets | cleanest page · **B** Arabic digits accepted by the point-price field but parsed as 0 → misleading error · grant/deduct without confirm, deduct not styled as danger |
| Payment methods | **B** titled "Payments" — the same name as the payment-history tile · method switch without busy guard (double fire), disabling a live method / changing the gateway without confirm |
| Payment history | **B** approve/reject failure shows "Action failed" — the server's reason is stored but never shown · `money()` has no thousands separator · failed load-more gives no retry · **M** export |
| Fee policy / ledger | **B** fee-policy save without confirm · ledger currency filter only on the ✓ icon · wide DataTable on phones |
| Fee rates | **B** a failed save says "could not load" · Arabic digits rejected |

## Support & security

| Page | Main findings |
|---|---|
| Help center | **B** closing from the card's status menu skips the confirm the swipe path has (closing blocks replies) · SnackBar instead of `showAppNotice` |
| Devices | **B** hard-coded English "Min … • Max …" and "days" in the Arabic UI · ±1 stepper for monthly views (up to 1000) |
| Auth settings | **B (serious)** a failed load shows the form with DEFAULTS and a live Save bar — one tap overwrites the real sign-in settings · raw `'$e'` · no confirm when changing login identifiers (can lock people out) |
| Usernames | good · plurals by interpolation |
| Required documents | **B** raw `'$e'` everywhere · 28 px toggle pills · mutates the response map in place |

## Configuration

| Page | Main findings |
|---|---|
| Theme | possible overflow of the action row at 320 px · no unsaved guard in the editor |
| Platform settings | **B** an invalid fee amount silently becomes 0 = free organization creation · leaked controller · the Feedback store is reachable only from here |
| Live settings | 1 347-line single page, no jump list · 7 one-off controls |
| Recommendations | **B** switching 7/30/90 days throws away unsaved weight edits · Save looks enabled and does nothing when every weight is 0 |
| Features | **B** org/access toggles can double-fire · a refresh error drops the loaded list · hiding a feature for everyone has no confirm |
| Data Lab (admin) | **B** search / load-more failure is an unhandled exception · the master switch turns it off for everyone without a confirm · refresh swaps the page for a skeleton |
| "Flags" | it is the student review/read bookmarks, not feature flags · **B** wrong "exam rules saved" toast · ±1 steppers up to 100 000 · 38 px buttons |
| App versions | best-built page · polls every loaded page every 10 s while a build runs |
| Update prompt | raw platform codes · switch without busy state (**R2**) |
| "Terms & conditions" | actually edits About + team + contacts + Terms · **B** raw `'$e'` everywhere, unguarded image picker, two sequential loads |

## Redundant features — proposals, nothing removed (awaiting your approval)

| # | What | Why | Proposal |
|---|---|---|---|
| R1 | **View as** page (People hub) | the same action is on every user row (eye icon) and in the user sheet; the page is a weaker third list without filters | keep the row/sheet action; remove the hub tile and page |
| R2 | **Update prompt** vs **App versions (build & publish)** | publishing a version fills the update prompt automatically | fold the update prompt into App versions as an "Update prompt (manual override)" tab; one tile |
| R3 | **Teachers** in the People hub | the same list is a top-level tab | remove the hub tile (Students has none either) |
| R4 | **Payouts tab** inside Payment history | a read-only copy of the Payouts page, which it links to | replace the tab with a link card to Payouts |
| R5 | **Parent requests** + **Parent-link settings** | two tiles for one workflow | one "Parent linking" page with Requests / Settings tabs |
| R6 | Fee editing in two places (Payment methods → Fees tab, and Fee policy behind an icon in Payment history) | one mental job, two places | one "Fees" page in the Finance hub with Rates / Policy tabs |
| R7 | **Feature guide "App" toggle** vs **Features** switches | the same kill-switch keys can be switched in two places | keep Features as the only switch; the guide shows the state read-only |
| R8 | Overview "hubs" block | re-lists the sidebar / hub tabs | replace with the global search + "recent" services |

Renames that are not removals (will do unless you object): "Flags" → "Student bookmarks (review/read)",
"Terms & conditions" → "About & terms", the payment-methods page title → "Payment methods", Send message gets its
own icon (it shares the campaign icon with Ads), Requirements → "Notices to acknowledge".

## Owned by other sessions (audited lightly, not changed here)

Courses tab and Subscriptions / Enrollment requests (subscriptions session) · Organizations (organizations session)
· AI assistant console, AI models (RAG session) · Bubble sheet types, Export center (exams / studio sessions) · the
student ↔ course parts of the Students tab (`_enrollDialog`, `_grantDialog`, `_studentSections`).

## What the real app shows (screenshots, 1440×900 and 390×844, Arabic)

- **The title is said 2–3 times**: the shell's top bar, the page's own app bar under it, and on the hub tabs a hero
  with the same title again. Pushed service pages show an EMPTY top bar plus their own back row.
- **Hub tabs**: a lime-green hero (the old `AdminPalette.green`) that does not belong to the teal brand; six cards in a
  narrow centred column on a 1440 screen, most of the page empty; no search.
- **Overview**: a lone calendar button floating at the start of the page; three KPI tiles in a 3 + gap grid; "Needs
  you" shows "Nothing waiting" directly above a red "1 required from you" card; a 14-day chart that is mostly empty
  space; small, unequal cards; the phone's floating Refresh pill covers the page title.
- **Students / Teachers on desktop**: phone cards stretched to 1200 px (name at one edge, actions at the other), the
  export pill and the floating "Add student" button over the rows — a table is the right form here.
- **Pushed pages**: the doodle-pattern page background behind lists and forms (busy behind dense content); empty
  states centred in an empty 1200 px page.
- **More real-app defects**: raw English enum values (`course_content`, `low`) and a blank header cell in the Arabic
  Data center table · raw env-var names (`TELEGRAM_BOT_USERNAME`, `WHATSAPP_BUSINESS_NUMBER`, `OTP_PROVIDER`) shown as
  copy on Verification & login · two "Add document" buttons on Required documents (empty state + FAB) · a stray back
  arrow inside the View-as search field · "1 devices" in English · hub descriptions cut with "…", Export's description
  is just "الإدارة" · "Terms" opens a page titled "محتوى التطبيق" · Parent-link settings' hero is near-black next to
  the pale heroes elsewhere · pushed pages use two header styles, two back icons (→ vs chevron) and widths from 820 to
  1220 px · phone: the bottom tab bar stays on pushed pages, Payouts' filter chips are clipped, the platform timezone
  stat wraps to three lines · English sidebar labels are cut ("Finance & requ…").
- **Network**: every page loads without 4xx/5xx except routes this local stack's backend checkout does not have yet
  (recommendations, AI models, OMR, app releases): those pages say "loading, try again" or "connection failed" for a
  404 — the error state should say the server needs an update (D-180's `AppErrorState` takes the message).
