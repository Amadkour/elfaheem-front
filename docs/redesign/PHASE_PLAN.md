# Phase plan for the lead

Short and practical. Read with `SCREEN_MAP.md` (every screen has its phase and group), `PARITY_TABLE.md` (what must not be lost) and `BACKEND_STATUS.md` (work packages WP1 to WP12). Paths are under `lib/features/` unless they start with `lib/`.

## 1. Order

| Step | What | Runs in parallel with |
|---|---|---|
| Phase 1 | Kit (section 3). Nothing else touches `lib/design/` after it without the lead. | Backend WP1 to WP4 (privacy), landing L |
| Phase 2 | Student: groups S-A, S-B, S-C, S-D, four agents side by side | Backend WP5, WP7, WP10, WP11 |
| Phase 3 | BK: booking and the subject flow. Needs S-B merged (the subject page) and WP6 | Parent P can start on its own folder |
| Phase 4 | P: parent. Needs S-A merged (join flow) and WP7 | |
| Phase 5 | T1 and T2, two agents | A1 and A2 may start: folders do not overlap |
| Phase 6 | A1 and A2, two agents | |
| Phase 7 | L: landing (`landing/` only; can run any time after phase 1 colours are fixed) | everything |
| Phase 8 | International pass over what phases 2 to 6 built (WP5, WP8, WP12) | |
| Phase 9 | Final walk, parity re-run, features guide, `REPORT.md` | |

Groups in one phase own disjoint files. A later phase may edit files of an earlier one only after that phase is merged.

## 2. Groups: what each one owns

Screens per group are counted in `SCREEN_MAP.md` ("Counts").

| Group | Design files | Owns (only this group edits them in its phase) | Backend it depends on |
|---|---|---|---|
| S-A auth, home, discover (41 screens) | `Stu1Auth`, `Stu1Public`, `StuHome`, `Stu1Discover` | `auth/`, `onboarding/`, `guest/`, `share/`, `home/student/` except `record/`, `courses/student/my_courses/`, `courses/student/list/`, `courses/category/`, `courses/roadmap/` except `roadmap_editor.dart`, `courses/course_list_card.dart`, `course_filters.dart`, `course_scope*.dart`, `profile/student_favorite_screen.dart`, `profile/about/`. New: `auth/kid_code/` | WP7 (child code: build on `FakeApi`, ship behind a kill switch), WP5 (country, phone) |
| S-B learn, subject, دفتر, live (32) | `Stu1Learn`, `SubjectProfile` rows 3-10, 17-18, 23-30 | `courses/course_space/`, `courses/course_profile/`, `courses/student/details/`, `sessions/material/`, `sessions/video/`, `learn_kit/`, `attendance/` (student files: `attendance_course_entry.dart`, `student_checkin_provider.dart`, `offline_attendance_tab.dart`, `relay_*`), `live/room/prejoin*.dart` and the student mode of `live/room/`, `records/`. New: `notebook/` | WP1 (live privacy), WP2 (payload sweep), WP10 (notebook) |
| S-C exams, analysis, schedule, messages (50) | `Stu2Exams`, `Stu2Analysis`, `Stu2Schedule`, `Stu1Comm` | `exams/exam_taking*.dart`, `exam_consent_screen.dart`, `exam_result_screen.dart`, `exam_notice.dart`, `exam_open_key*.dart`, `exam_integrity*.dart`, `exams/legacy/student/`, `exams/offline/` (student screen), `analytics/student/`, `attendance/analysis/student/`, `calendar/`, `live/meeting_links*.dart`, `messaging/`, `profile/compalints/`, `rag/` chat screens (`rag_chat_screen.dart`, `rag_chat_sessions.dart`, `app_assistant.dart`) | WP3 (announce-only course thread, no student to student), WP2 (calendar invitees), WP11 (invite by username or phone); a cross-course "saved and wrong questions" route (small, new) |
| S-D money, store, games, Quran, Nahw, teachers, profile (106) | `Stu2Money`, `Stu2Store`, `Stu2Games`, `Stu2Quran`, `Stu2Nahw`, `Stu2Teachers`, `Stu2Profile` | `payments/`, `store/` except `manage/`, `games/` except `admin/`, `quran/` except `quran_teacher_hub.dart`, `nahw/` (student files), `self_learning/` except `admin/`, `teachers/teacher_discovery.dart`, `teachers_parts.dart`, `rewards/`, `profile/` except `compalints/`, `about/`, `teacher/`, `student_favorite_screen.dart`, `downloads/`, `certificates/student/`, `certificates/issue/cert_verify_*.dart`, `parent/student_link_code_screen.dart`, `home/student/record/` | WP4 (nicknames, boards), WP8 (methods by country), WP6 ("group is full"), a device or session list route for the student (new) |
| BK booking and subject flow (32) | `BookFlow`, `SubjectProfile` rows 1-2, 11-16, 19-22 | New: `booking/`. After S-B is merged: the pre-enrol page in `courses/student/details/` and the chat, bot and schedule panels of the subject page (it embeds S-C's chat and schedule widgets, it does not edit them) | WP6 (groups, gender, 50 minutes, individual bookings, UTC), WP12 (centres), WP8, WP11 (subject bot) |
| P parent (39) | `Pa2*` | `parent/` except `student_link_code_screen.dart`. New: `parent/signup/` (child creation step, plugged into the join flow), `parent/pay/` | WP7; a parent payments and invoice route (new, call it WP13) |
| T1 teacher: home, courses, wizard, course, class, live (49) | `Tea1*` | `home/teacher/`, `courses/teacher/`, `courses/course_setup*.dart`, `courses/roadmap/roadmap_editor.dart`, `sessions/teacher/`, `upload/`, `attendance/` teacher files, the teacher mode of `live/` (room, lobby, ended), `courses/course_profile/` teacher tabs | WP1 ("bring on stage"), WP3 |
| T2 teacher: schedule, analysis, account, money, certificates, exams, teaching, chat (56) | `Tea2*` | `analytics/teacher/`, `attendance/analysis/teacher/`, `data_lab/`, `profile/teacher/`, `certificates/` except `student/` and `cert_verify_*`, `exams/hub/`, `exams/paper/`, the other teacher files of `exams/`, `ads/`, `store/manage/`, `teachers/teacher_onboarding.dart`, `package_wizard.dart`, `quran/quran_teacher_hub.dart` | WP6 (package size and gender), WP8 (IBAN, documents) |
| A1 admin (52) | `Adm*` | `admin/`: `admin_dashboard_screen.dart`, `admin_overview_page.dart`, `admin_home_*`, `admin_global_search.dart`, `admin_services_hub.dart`, `admin_users_page.dart`, `admin_student_manage.dart`, `admin_entity_manage.dart`, `admin_filters*`, `admin_bulk.dart`, `admin_courses_page.dart`, `admin_categories_page.dart`, `admin_parent_*`, `admin_send_message_page.dart`, `admin_account_approval.dart`, `admin_devices_page.dart`, `admin_required_documents_page.dart`, `admin_datacenter_page.dart`, `admin/help/`; `exports/`, `courses/admin/course_students/`, `teachers/teacher_review_admin.dart`. New: `admin/approvals/`, `admin/audit/` | audit log route, publish-approval queue (new, owner to confirm) |
| A2 super admin (107) | `Sup*` | every other file of `admin/` (finance, payouts, payments, fees, subscriptions, points, `rewards/`, admins, MFA, view-as, platform, auth settings, `modules/`, features, AI controls, `edu/`, `live_settings/`, exam policy, `models/`, `landing/`, theme, legal, content, `app_releases/`, versions, update policy), `courses/admin/course_trash/`. A2 asks A1 for any change in `admin_services_hub.dart` | roles and permissions (new, owner to confirm), WP5 seed, WP8 |
| L landing (6) | `Landing*` | `landing/` | WP9 (demand numbers; remove the card if it is not ready) |

### Files no group edits (lead or the phase 1 owner only)

- `lib/main.dart`, `lib/core/**` (routing registry `app_routes.dart`, `deferred_screens.dart`, `providers.dart`, `api_client.dart`), `lib/config/**`, `lib/design/**`, `lib/utils/**`.
- `assets/translation.json`: each group writes its strings in a sidecar file (`assets/redesign/<group>.json`, same shape) and the lead folds them in at merge. Both `ar` and `en` for every key.
- `pubspec.yaml`, `pubspec.lock`, `test/contract/*.json`, `test/support/fake_api.dart`, the `homeBudgets`, `AttentionTabs`.
- `lib/features/org/**`: never rebuilt. It only receives the new tokens through the kit.
- `sync/`, `docs/redesign/ref/`, `tool/redesign/`, `.gitignore` (another agent's work).
- A group that needs a new route, provider, kit piece or shared-file change writes the request in its report; the lead applies it.

Known overlaps to watch:
- `live/room/` is touched by S-B (student privacy mode) and later T1 (teacher chrome). S-B adds the student mode as new presentational widgets and does not restyle the host tools.
- `courses/course_space/` and `course_profile/` belong to S-B in phase 2, BK in phase 3, T1 in phase 5: serial, one after the other.
- `ads/ads_pages.dart` holds the slider, the teacher page and the super admin page in one file: T2 first, then A2.
- `exams/` has 195 files: S-C takes only the student files listed above; everything else is T2.
- `auth/` and `onboarding/join/` serve parents and teachers too: S-A restyles the shared flow, P adds only the parent steps in its own folder.

## 3. Phase 1: the kit

One owner (two agents at most: tokens and motion; components and shells). Every piece gets a layout-harness test (`expectNoLayoutErrors`, 320×640 and 1400×900, ar and en, text scale 1.3) and a Reduce-motion test.

### 3.1 Files that change

| File | Change |
|---|---|
| `lib/design/app_tokens.dart` | Radii and type scale of `design/kit.css`; `AppArea` and subject colour roles (below) |
| `lib/config/theme/theme_config_model.dart`, `app_theme.dart`, `theme_config_provider.dart` + the backend theme seed | The new palette as theme defaults AND in the server seed, so both agree. Widgets keep reading `context.colors` only |
| `lib/design/app_gradients.dart` | Hero gradient per area with precomputed stops (no `color-mix` at run time; the resolved hex table is in `kit.css`) |
| `lib/design/app_motion_kit.dart` (+ new `lib/design/motion/`) | M1 to M16 (3.3). `AppOdometer`, `AppCountUp`, `AppPopIn`, `AppPressScale`, `AppDrawIn` already exist and are reused |
| `lib/design/app_buttons.dart` | Jelly press (M9); the `hot` apricot-to-coral button for the one forward action |
| `lib/design/app_kit.dart`, `app_page_header.dart`, `home_kit.dart` | New `AppHero` (area gradient, three drifting shapes, phone hero at most 190 px), cards, tiles, chips, stat tiles (web only on student screens), empty state |
| `lib/design/app_tabs.dart` | Segmented pill with the morphing background (M13) |
| `lib/design/app_overlays.dart`, `app_side_sheet.dart`, `app_sheet_header.dart` | Peek sheet (M14): phone bottom sheet, web drawer |
| `lib/design/app_shell.dart`, `app_shell_nav.dart` | Sidebar on web (`k-side`), bottom nav on phone (`k-bnav`) with the active blob. `DashboardItem`, `LazyTabStack`, `ShellBadge`, pins and the focus mode stay as they are |
| `lib/design/README.md`, `docs/guides/ui-kit.md` | The new pieces and the motion budget |
| New `lib/design/app_area.dart` | `enum AppArea { home, learn, exam, games, store, quran, nahw, sched, chat, money, me }` and `AppAreaScope` (an `InheritedWidget` a page sets once; hero, selected states and icons read it) |
| New `lib/design/app_subject_colors.dart` | `subjectColors(context, subjectKey)` giving colour, tint and ink; the same subject has the same colour everywhere |

### 3.2 Token additions (DESIGN_SYSTEM 1.4 and `design/kit.css`)

- Accents, each with a tint and an ink: sun `#FFC53D`, mint `#19C29B`, grape `#7A4DF0`, pink `#FF5FA2`, lime `#9BD728`, sky `#3DA5FF`; tints and inks for the existing blue, cyan, apricot and coral. In the theme model they are new roles (for example `c.accentSun`, `c.accentSunTint`, `c.accentSunInk`), with the defaults above and a dark-mode value each.
- Area pairs (`--k-acc`, `--k-acc2`): home blue to cyan, learn apricot to coral, exam grape to blue, games grape to pink, store sun to apricot, quran mint to `#0F6E6D`, nahw lime to mint, sched sky to cyan, chat pink to apricot, money sun to mint, me blue to grape.
- Status colours that never follow the area: live `#F2545B`, success `#19C29B`, warning `#FFC53D`, locked `#C9D6E6`, error `#C2410C`.
- Subject colours (10): math `#FF7A59`, physics `#7A4DF0`, chemistry `#19C29B`, biology `#2FB5A8`, English `#07B8EE`, Arabic `#0F6E6D`, qudurat and tahsili `#FFB020`, code `#1979C1`, Quran `#1D9A63`, Islamic studies `#B7791F`, each with tint and ink. Keyed by the server subject, with a fallback for an unknown subject.
- Other roles keep one accent: teacher purple, parent teal, admin blue and amber, super gold.
- Check every new pair in `test/ui/a11y_guidelines_test.dart` (AA for bold text of 14 px and more).

### 3.3 Motion library M1 to M16 (API sketch)

| # | Dart | Notes |
|---|---|---|
| M1 flip-in | `AppFlipIn({index, child})`, `.mFlip(i)` | Spine on the start edge (right in RTL) |
| M2 ink draw | `AppInkPath({path, color})`, `AppInkRing({value})`, `AppInkCheck()` | Ring then `AppCountUp`. Extends `AppDrawIn` |
| M3 pop | `AppPopIn` (exists) with a small rotate, `.mPop()` | |
| M4 slap | `AppSlap({child, delay})` | Tags "مباشر", stamps |
| M5 deal | `AppDeal({index, child})`, `.mDeal(i)` | Even items mirror |
| M6 wipe | `AppWipe({child})`, `AppWipeSwitcher` for tab and step changes | `ClipPath`, direction follows `Directionality` |
| M7 squiggle | `AppSquiggle({child})` | One word per hero; M2 painter |
| M8 breathe | `AppBreathe({child, color})` | LOOP |
| M9 jelly | `AppJelly({child, onTap})`; built into `AppButton` and option tiles | On top of `AppPressScale` |
| M10 roll | `AppOdometer` (exists) | Prices, points, countdown, score |
| M11 burst | `AppBurst.fire(context, BurstMoment m, {at})`, `enum BurstMoment { bookingConfirmed, examPassed, levelUp, attendanceDone }` | The enum is the allow-list: no other place can fire it |
| M12 wobble | `AppWobble({index, child})`, `.mWobble(i)` | |
| M13 pill | `AppMorphPill` inside `AppTabs` (the segmented style) and the bottom nav | |
| M14 sheet | `showAppSheet` gets the overshoot curve and the blurred backdrop | No API change for callers |
| M15 shake, nod | `AppFeedbackController.shake()` / `.nod()` + `AppFeedback({controller, child})` | PIN, login, answers |
| M16 drift | `AppDriftShapes({area})` inside `AppHero`, optional `ScrollController` for parallax | LOOP |

Reduce motion (`AppDisplayScope`, the `app.animations` kill switch, the system setting):
- One-shot moves (M1 to M7, M12 to M15) read `MediaQuery.disableAnimationsOf(context)` (already set from the person's preference in `app_display.dart`) and draw the end state at once.
- Loops (M8, M16) call `syncMotionLoop(context, controller)` in `didChangeDependencies`, so they park at rest. No other loop is allowed.
- M9 falls back to the plain press, M10 shows the final number, M11 does nothing.
- Budget, enforced by an `AppEntranceBudget` scope: one hero move per screen, at most 12 animated items on entry on a phone (later items appear without motion), at most 3 looping elements.
- Parent, teacher, admin and super admin use only M9, M10, M13 and M14.

## 4. Backend track (from BACKEND_STATUS work packages)

| Needed before | Packages |
|---|---|
| Phase 2 ships | WP1 live-room privacy (L), WP2 payload sweep (M), WP3 course chat (S), WP4 nicknames and boards (M) |
| Phase 2, S-A and S-B | WP7 child code (L), WP5 country and time zone (M), WP10 notebook (M), WP11 invites, subject bot, stickers (S-M) |
| Phase 3 | WP6 groups and booking (L), WP12 centres (S), WP8 methods by country (M) |
| Phase 4 | WP7, plus the parent payments route (new) |
| Phase 7 | WP9 demand numbers (M) |

Each new route: contract snapshots regenerated, a features-guide entry, a kill-switch key, an Alembic revision after `0129`. The UI is built against `FakeApi` when the package is not merged yet, behind its kill switch.

Not in BACKEND_STATUS and found here: parent payments and invoices; a device or session list for the student; a cross-course list of saved and wrong questions; the admin audit log; the publish-approval queue; the roles and permissions editor; an "all users" broadcast audience.

## 5. Open risks

1. **Live-room privacy on the server (WP1).** Hidden participants, subscribe to the teacher only, no data channel for students, hands and chat through server routes, "bring on stage". It changes LiveKit tokens for every room kind, guests and meetings included. Hiding it in the UI alone does not meet RULES 1.7. Needs a real two-device test.
2. **`courses/teacher/course_form_screen.dart` is 2012 lines** in one form with one provider. The 7-step wizard must keep every field, the edit mode and the rule that a personal course never sends `next_course_ids`. Split it first with no behaviour change, then restyle.
3. **Booking has no server model** (groups of 5 to 10 with a gender, 50-minute classes, individual slots, propose times). Phase 3 cannot ship before WP6, the largest package.
4. **The sync with NextBrain (A-008, owner answer pending, default a).** Every `lib/` file a group rebuilds will conflict with later syncs; the list of redesign-owned paths must be kept as groups go.
5. **`assets/translation.json` and the shared kit under parallel agents.** Four student agents at once: sidecar strings and "no group edits `lib/design/`" are what keep the merges clean. The home request budgets and the contract snapshots are gates in every phase.
6. **Screens marked `exists` from file names.** About 380 `exists` rows of `SCREEN_MAP.md` were not opened; 46 spot checks (97 rows) changed 18 statuses, most of them from partial or missing to exists. Each group confirms its rows before it starts.
7. **Scope the design implies but nobody decided:** publish approval for courses, roles and permissions, 2-step verification for students, the privacy contract inside organizations.
