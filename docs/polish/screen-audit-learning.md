# Screen audit — learning (Track A2, area 2 of 3, 2026-10-28)

Scope: `lib/features/student/**` except `student/home/**`, `lib/features/teacher/**` except `teacher/home/**`, `lib/features/shared/{session,course,exam_engine,live,guest,models}/**` (243 Dart files).
Checks per screen: (a) colours only from `context.colors` · (b) page / list spinners → `AppListSkeleton` / `AppShimmer` · (c) empty + error states (`AppEmpty`, `ErrorRetry`, `apiErrorText`), no raw exception text · (d) RTL · (e) overflow at 320×640 / textScaler 1.3 / ar + en · (f) 48 px targets, labels on icon-only buttons · (g) old widgets → kit · (h) times via `AppTime` · (i) pull-to-refresh via `AppRefresh`.
Behaviour and API calls are unchanged except where a row or the bug list says "bug". `RoomPage` / `VideoPlayerScreen` are covered through their presentational parts only.

## Totals

| check | before → after |
|---|---|
| (a) `Colors.*` + `Color(0x…)` in the area | 1071 → 213; without `Colors.transparent` 988 → 96. Of the 96: 29 are the two dark-surface palette definitions (`LivePalette` 15, `VodInk` 14); the rest are kept on purpose — card-network / file-type brand colours (Visa, Mastercard, Amex, mada, saved-card art, Word / Excel / CSV / PowerPoint / Python), `PdfColors` in the printed exam paper, the paper preview (a white page in dark mode too), user-chosen certificate colours and hex parsing, the 7 pastel participant colours, QR quiet zones (white, scanner contrast), the black letterbox behind full-screen images / reels, the reel player video chrome, and the legacy `kDeep / kDanger / kAmber / kViolet` consts in `exam_ui.dart` that teacher screens still import (student screens read the theme) |
| (b) page / list spinners | 43 page / list loaders → `AppListSkeleton` / `AppShimmer` (+ new `CourseDetailSkeleton`); skeleton usages 27 → 103. Remaining `CircularProgressIndicator`s are inside buttons, uploads, load-more rows, the video buffering state and the payment hand-off |
| (c) raw exception text shown to users | 54 → 0 (`apiErrorText` usages 0 → 49); error states with retry added on 6 lists |
| (d) RTL | `EdgeInsets.only(left/right)` 21 → 5 (the 5 left are deliberate: overlays pinned to a corner of the course image); ~25 asymmetric `fromLTRB` → `EdgeInsetsDirectional.fromSTEB`; `Positioned` / alignments / gradients made directional; 3 double-mirrored arrows fixed; course-code keypad no longer mirrored in Arabic |
| (e) overflows found by the harness | 9 widgets fixed (see bug 12) |
| (f) icon-only buttons / small targets | `tooltip:` 95 → 136 (+41), 3 `Semantics` labels on the player controls, ~30 targets raised to 48 px (room controls, chat / hands / reactions, player glass buttons, back / close / clear buttons). Left: the live mini box (≈160 px wide; the whole box is the target) |
| (g) old widgets | device-request SnackBars → `showAppNotice`; no `Switch` / `DropdownButton` in the area. The 11 `SnackBar`s left are in the live room (persistent "reconnecting" / iOS share hint, closed by code — an app notice would sit under the room) |
| (h) hand-formatted / un-zoned times | 9 → 0 on reachable screens (exam dates, schedule slots and picked times via `AppTime.clock` / `clockMinutes` with the API payload untouched, participant dialog, Data Lab `dlAgo`). Two hand-formatted times remain in files no route imports (`student_active_exam_screen.dart`, `attendance_screen.dart` — dead code, colours fixed only) |
| (i) `RefreshIndicator` by hand | 33 → 0 (`AppRefresh` 0 → 35) |

Colour roles used: `onHero`, `onHeroMuted`, `onHeroFaint`, `heroGlass`, `heroGlassBorder`, `heroShade`, `heroEnd`, `heroTint`, `cardBg`, `divider`, `textDark` / `textMedium` / `textLight`, `primary`, `success`, `warning`, `danger`, `purple`, `accent`, `accent2` and the `*Tint` roles. Two always-dark surfaces have their own documented ink palettes instead of `context.colors`: the live room (`LivePalette`, derived from the theme's primary; new tokens `textSoft`, `glassFaint`, `hairline`, `scrimLight`, `scrimHeavy`, `tooltipBg`, `shade(a)`, `ink(a)` — all const) and the course video player chrome over the picture (`VodInk` in `vod_player_parts.dart`; the black letterbox behind the video stays pure black on purpose).

Tests: `test/ui/polish_learning_layout_test.dart` (28 tests in four groups — student, teacher, live room / guest / video, course / materials / exams / Data Lab).

## Bugs found and fixed

1. **Raw exception text shown to users (54 places)** — `ApiException.toString()` prints `ApiException(500, server): …`, and several screens showed `e.toString()` / `'$e'`: student exam / analytics / flags / course detail / device security / payment / transfer providers (19), teacher exam / attendance providers and the read-flags screen (13), screen share "Screen share failed: {e}" in `room_screen_share.dart` (4, new `shareErrorText`), the private-course passcode sheet (`course_access.dart`), Exam Engine results / taking toasts, `exam_engine_api.dart` for non-API errors and the Data Lab toasts / gate (18). All go through `apiErrorText(ApiException.from(e))` now.
2. **Course "About" tab crashed for a course without a teacher or category** — `features/courses/student/details/components/about.dart` compared `c.teacher != Null` (the Type, always true), then used `c.teacher!` / `c.category!`.
3. **Device-blocked dialog forced right-to-left in English** — `features/courses/student/security/device_blocked_dialog.dart`.
4. **Every certificate notice looked like an error** — `my_certificates_screen.dart` `_toast` ignored its `error` flag.
5. **A failed first load said "nothing here yet"** — student my courses / course list, teacher courses, certificate requests, certificate designs, enrolled students: now `ErrorRetry`.
6. **Exam start time shown in UTC** — `teacher_exam_hub_screen.dart` `_fmtDate` read the server's naive UTC as local time; now `AppTime.dateTime`. Same for the participant profile dialog in `room.dart` (join / leave times).
7. **Room messages were invisible** — `room.dart` `_showSnack` and the guest-link errors used `showAppNotice`, which draws in the app navigator's overlay, under the full-screen room layer; they now show on the room's own Scaffold while the room is full-screen.
8. **Short sessions list could not be pulled to refresh on Android** — `features/sessions/teacher/sessions_screen.dart` (`BouncingScrollPhysics` without an always-scrollable parent; now `AppRefresh`).
9. **Titles invisible in dark mode** — `#1A1A2E` titles in `course_form_screen.dart` and `course_progress_status_card.dart` (now `textDark`).
10. **Arrows pointed the wrong way in Arabic** — `data_lab_history_sheet.dart:172`, `data_lab_import_sheet.dart:382, :576` flipped icons Flutter already mirrors.
11. **Back button tooltip said "share"** — `features/courses/topbar.dart`.
12. **Overflows at 320 / textScaler 1.3** (harness) — instructor card (`about.dart`, also ~1.5k px tall with a long name), teacher `course_details_section` schedule + certificate rows, read-only status pill, three roadmap rows in `studend_course_roadmap_section.dart` (up to 179 px), the `session_progress_section` label row, the `session_exam_tile` button row (106 px).

Not fixed:
- (outside this area) `lib/design/app_notice.dart`: `showAppNotice` / `appToast` from sheets opened inside the full-screen live room (lobby, share link) are still drawn under the room layer. Suggested fix: draw into the room navigator's overlay while `LiveRoomHost.isOpen && !LiveRoomHost.isMinimized`.
- (outside this area) `teacher/home/teacher_models.dart` adds 700 to `students_count` when it parses a course (inflated student counts).
- (this area, left) `room.dart` `_fmtDuration` ("joined X ago") compares `DateTime.now()` with naively parsed server times; left until the server's time format is confirmed.

## Per screen

## Student (`lib/features/student/**`, without `home/`)

| file | issues | fixed | left (reason) |
|---|---|---|---|
| `features/courses/student/details/course_detail_screen.dart` | 7 hard-coded colours (white ink on primary tab, black shadows/dividers); full-page branded spinner on first load; hand-written RefreshIndicator | colours -> onHero / heroShade; first load -> `CourseDetailSkeleton` (hero shape + `AppListSkeleton`); RefreshIndicator -> `AppRefresh` | — |
| `features/courses/student/details/components/about.dart` | 20 colours (instructor card, info-card pastels, certificate viewer black, gold language chip); `c.teacher != Null` (compares to the Type, always true, so `c.teacher!` / `c.category!` threw for a course without teacher / category); Arabic-only section titles; image spinner; close button without tooltip; instructor card overflowed 18 px at 320 / en / 1.3 and grew ~1.5k px with a long name | colours -> onHero / heroShade / accentTint / primaryTint / successTint / accent2 / charcoalDark; `!= null` + null-safe category; titles via `gt(ar, en)`; image loading -> shimmer; tooltip; name 2 lines / category 1 line, badge `Flexible`; card made public `CourseInstructorCard` and harness-tested | — |
| `features/courses/student/details/components/student_course_hero.dart` | 22 colours (white ink, black cinematic scrim); `_statsStrip` / `_fallback` had no theme access | colours -> onHero / heroShade alphas; helpers take `context` / the theme | hero not harness-tested (needs `CourseModel` + reel video player) |
| `features/courses/student/details/components/session.dart` | branded spinner while lessons load | -> `AppListSkeleton(items: 4)` | — |
| `features/courses/student/details/components/content.dart`, `stat_chip.dart`, `share_link.dart` | checked: theme colours, bilingual, tooltips present | — | — |
| `features/courses/student/details/course_access_sheet.dart` | own always-dark palette (13 hex colours); keypad mirrored in Arabic (3-2-1); icon-only cancel / delete keys unlabelled | palette -> theme roles (cardBg, accent2, divider, danger, textDark / textLight, inputBg, heroShade); keypad kept LTR; keys get `Semantics(button, label)`; harness-tested | — |
| `features/courses/student/details/course_link_loader.dart` | branded loader while opening a shared link | — | kept: one-off "opening the course" state, not a list |
| `features/courses/student/details/components/app_shell.dart` | 18 colours, `Border(left:)` | colours -> theme (heroShade / heroDivider / onHero), `BorderDirectional(end:)` | file is unused (no importer) — candidate for deletion |
| `features/courses/student/my_courses/my_courses_screen.dart` | 4 colours; branded spinner; a failed first load showed nothing | colours -> theme; `AppListSkeleton`; `ErrorRetry` when the first page fails | — |
| `features/courses/student/list/courses_list_screen.dart` | branded spinner; no error state | `AppListSkeleton`; `ErrorRetry` | — |
| `features/courses/student/my_courses/components/course_progress_bar.dart` | Arabic-only labels | — | unused (no importer) |
| `features/courses/student/security/device_blocked_dialog.dart` | forced `TextDirection.rtl` also in English; `Alignment.centerRight` | `pageDirection`; `AlignmentDirectional.centerStart` | — |
| `student/enrollment/enrollment_screen.dart` | 13 colours; branded spinners (page + methods) | colours -> theme ("new card" tile -> primary); spinners -> `AppListSkeleton` | Visa / Mastercard / Amex / mada tile colours are the networks' brand colours |
| `student/enrollment/enrollment_widgets.dart` | 5 colours | -> theme | in-button / processing loaders kept (not list loading) |
| `student/enrollment/saved_cards/student_saved_methods_screen.dart` | 26 colours; `Colors.amber[700]`; painter with no theme access; delete icon without tooltip | ink / badge / shadow colours -> theme; `_ArcPainter(ink)`; tooltip | card-art gradients per network and the EMV-chip gold are artwork of a physical card |
| `student/enrollment/checkout_pages.dart`, `checkout_web_impl.dart` | 2 colours; branded loader while payment opens | colours -> theme | loader kept (payment hand-off, not a list) |
| `student/enrollment/roadmap_enrollment_screen.dart` | branded spinner | `AppListSkeleton` | — |
| `student/enrollment/transfer/transfer_payment_screen.dart` (+ provider) | branded spinner; provider failure text hard-coded Arabic + raw `$e` | `AppListSkeleton`; new keys `transfer_submit_failed` / `transfer_proof_required` + `apiErrorText` | — |
| `student/enrollment/payment_flow_provider.dart` | `payment_open_failed: $e` (raw exception) | `apiErrorText(ApiException.from(e))` | — |
| `student/enrollment/payment_callback_page.dart` | 5 colours | -> theme | unused (no importer) |
| `features/exams/legacy/student/exam_ui.dart` | 28 colours; `GlassIcon` 40 px, no label; `ExamRing` default `Colors.white` | colours -> theme; `GlassIcon` 48 px target + `tooltip` (back gets the localized back tooltip); `ExamRing.color` nullable -> onHero; harness-tested | `kDeep / kDanger / kAmber / kViolet` consts kept for the teacher screens that import them (student screens no longer use them) |
| `features/exams/legacy/student/student_exam_detail_screen.dart` | 10 colours + k* palette; hand-rolled `d/m/y hh:mm` | theme roles; `AppTime.dateTime` | — |
| `features/exams/legacy/student/student_exam_quiz_screen.dart` | 9 colours + k* palette; page spinner | theme; `AppListSkeleton` | — |
| `features/exams/legacy/student/student_exam_result_screen.dart` | 17 colours; divider grey.shade100 | theme (divider -> `c.divider`) | — |
| `features/exams/legacy/student/student_exam_frozen_screen.dart` | 8 colours; hand-rolled deadline time; back IconButton without tooltip | theme; `AppTime.dateTime`; tooltip | — |
| `features/exams/legacy/student/student_exam_list_screen.dart` | 3 colours + k*; spinner; RefreshIndicator; refresh glass button unlabelled; end date `d/m` by hand | theme; skeleton; `AppRefresh`; tooltip; `AppTime.date(.., 'd/M')` | — |
| `features/exams/legacy/student/student_course_exams_widget.dart` | k* palette; spinner; end date `d/m` by hand | theme; skeleton; `AppTime.date` | — |
| `features/exams/legacy/student/student_exam_provider.dart` | 5 x `e.toString()` shown to the student | `apiErrorText(ApiException.from(e))` | — |
| `features/exams/legacy/student/student_active_exam_screen.dart`, `passcode_screen.dart` | 17 + 4 colours, raw `e.toString()` | colours -> theme, apiErrorText | both unused (no importer; the live quiz is `student_exam_quiz_screen.dart`, passcodes use `PasscodeSheet`) |
| `student/analysis/flags/student_flags_screen.dart` (+ provider) | 2 colours + k*; spinner; 2 RefreshIndicators; raw error | theme; skeleton; `AppRefresh`; tooltip; apiErrorText | — |
| `student/analysis/student_analytics_screen.dart` | 7 colours (white avatar on hero); spinner; RefreshIndicator; clear-search icon without tooltip | theme (avatar -> onHero); skeleton; `AppRefresh`; tooltip | — |
| `student/analysis/student_course_analytics_screen.dart` (+ provider) | 29 colours; 4 spinners; 5 RefreshIndicators; glass buttons 40 px unlabelled; 3 raw errors in provider | theme; skeletons; `AppRefresh`; 48 px + tooltips; apiErrorText | attendance dates are pre-converted with `toLocal()` (AppTime would shift twice) |
| `student/analysis/student_analytics_profile_screen.dart` | 4 colours; spinner; RefreshIndicator; raw `'$e'` | theme; skeleton; `AppRefresh`; apiErrorText | — |
| `student/certificates/my_certificates_screen.dart` | 8 colours; spinners (page + image); RefreshIndicator; `_toast` ignored its `error` flag (every success notice showed as an error); close button `Positioned(right:)` without tooltip | theme; skeleton + shimmer; `AppRefresh`; `error: error`; `PositionedDirectional(end:)` + tooltip | — |
| `features/courses/student/details/course_detail_provider.dart`, `courses/security/device_security_provider.dart` | raw `e.toString()` to the user | apiErrorText | — |
| `student/attendance/attendance_screen.dart` | 4 colours; hand-rolled hh:mm | colours -> theme | unused (no importer) |
| `student/reward/rewards_screen.dart` (+ provider) | 3 colours, Arabic-only, mock leaderboard data | colours -> theme | unused (no importer) — mock screen |
| `student/dashboard/component/student_exam_tab.dart` | 3 colours, spinner, RefreshIndicator, Arabic-only strings, raw error | colours -> theme, `AppRefresh`, apiErrorText | unused (no importer); Arabic-only strings left |
| `student/dashboard/component/student_schedule_tab.dart`, `student/dashboard/dashboard_screen.dart` | — | — | dashboard owned by the homes track |
| `student/models.dart` | hand-rolled `d/m hh:mm` session labels | — | values come from `toLocalSaTime` (already converted); AppTime needs the raw UTC, so the change belongs with the model |

## Teacher (`lib/features/teacher/**`, without `home/`, `sessions/live/`, `data_lab/`)

| file | issues | fixed | left (reason) |
|---|---|---|---|
| `features/courses/teacher/course_form_screen.dart` (course editor) | 32 hard-coded colours (white on hero, black shadows, #1A1A2E titles invisible in dark mode); spinner-free except upload; hand-rolled HH:MM in the add-schedule sheet and slot list; 38 px back button without label; `Alignment.centerLeft` | colours → theme roles (onHero, heroShade, textDark…); slot times + picked time via `AppTime.clock` / `clockMinutes` (payload `_fmt` untouched); back button 48 px target + semantic label; remove-discount button `AlignmentDirectional.centerEnd` | upload spinner on the image kept (it is an upload, not a page load) |
| `features/courses/teacher/courses_screen.dart` (my courses) | 19 colours; page spinners; hand-written RefreshIndicator; failed first page fell through to "no courses yet"; `EdgeInsets.only(left/right)`; 26 px search clear without label | colours → roles (`heroEnd` for the card gradient); `AppListSkeleton`; `AppRefresh`; `ErrorRetry` when the first page fails; directional paddings; clear button 40 px target + label; schedule times via `AppTime.clock` | — |
| `features/courses/teacher/course_privacy_card.dart` | gold `#C9A84C` | → `accent2` | — |
| `features/courses/teacher/component/certificate_manager_sheet.dart` | 18 colours (parchment preview, gold, white header); page spinner for students; close IconButton without tooltip; asymmetric LTRB | colours → accent / accentTint / accent2 / onHero / heroShade; `AppListSkeleton`; tooltip; `fromSTEB` | small preview spinner kept |
| `features/courses/teacher/component/course_progress_status_card.dart` | colours; read-only pill overflowed at 320 / 1.3 (harness) | roles; label `Flexible` + ellipsis | — |
| `features/courses/teacher/component/currency_selector.dart`, `gradient_button.dart`, `add_item_dialog.dart` | white / black colours | → onHero / cardBg / heroShade | — |
| `features/courses/teacher/component/section_card.dart` | 18 px close glyph as a GestureDetector (no label, tiny target); asymmetric LTRB | `IconButton` with tooltip (48 px); `fromSTEB` | — |
| `features/courses/teacher/component/recommended_courses_field.dart` | 14 px chip close without label; asymmetric LTRB | labelled, padded hit area; `fromSTEB` | — |
| `features/courses/teacher/component/next_courses_field.dart` | 3 icon-only buttons without tooltip | tooltips (move up / down / remove) | — |
| `teacher/certificates/certificate_requests_screen.dart` | page spinner; failed load showed "no requests"; hand-written empty state + RefreshIndicator | body factored to `CertificateRequestsBody` (plain values): skeleton · `ErrorRetry` · `AppEmpty` (pullable) · `AppRefresh` list; tested | — |
| `teacher/certificates/designer/certificate_designs_screen.dart` | page spinner; failed load showed "no designs"; RefreshIndicator; asymmetric LTRB | skeleton; `ErrorRetry`; `AppEmpty` (pullable); `AppRefresh`; `fromSTEB` | — |
| `teacher/certificates/designer/certificate_designer_screen.dart` | 19 colours; 7 icon-only buttons without tooltip | chrome colours → roles; tooltips (align / lines / show-hide / delete / close / remove) | signature ink palette (`_inks`), photo placeholder on the canvas, `hexToColor` fallback kept — certificate content, not UI chrome; ink swatches stay 30 px (wide-only side panel); designer loading spinner kept (canvas, not a list) |
| `teacher/analysis/analytics_hub_screen.dart` | 12 colours; page spinner; RefreshIndicator; close IconButton without tooltip | roles; skeleton; `AppRefresh`; tooltip; `fromSTEB` | per-course load failure still shows shortcuts only (by design: "the hub still works") |
| `teacher/analysis/attendance/teacher_attendance_screen.dart` (+ provider) | 10 colours; spinners; raw `e.toString()` errors; clear button without tooltip | roles (`heroTint` for hero stat); skeletons; `apiErrorText(ApiException.from(e))`; tooltip | — |
| `features/exams/legacy/teacher/teacher_exam_hub_screen.dart` (+ provider) | 32 colours; tab spinners; 10 raw `e.toString()`; exam start time shown in UTC; picked dates HH:MM by hand; popup items colour without context; asymmetric LTRB; remove-option button without tooltip | roles; skeletons; `apiErrorText`; `_fmtDate` reads naive UTC → `AppTime.dateTime`; picked times `clockMinutes`; `fromSTEB`; tooltip | — |
| `teacher/analysis/flags/teacher_read_flags_screen.dart` | 5 colours (+ const hero gradient); spinner; raw error; RefreshIndicator | roles (`heroEnd(kDanger)`); skeleton; `apiErrorText`; `AppRefresh` | `kDanger` / `examT` come from student `exam_ui.dart` (other area) |
| `teacher/schedules/schedules_screen.dart` | 32 colours (ring painter white); RefreshIndicator; slot times raw "HH:MM"; 38 / 40 px delete / add without labels; `only(left:)` | roles (painter takes the ink colour); `AppRefresh`; `AppTime.clock` for slots + delete prompt, picked time `clockMinutes`; 48 px targets + semantic labels; directional margin | decorative hero circles keep left/right |
| `teacher/profile/payout/teacher_payouts_screen.dart` | 5 colours; page spinner; RefreshIndicator | roles; skeleton; `AppRefresh` | — |
| `teacher/profile/switch_device_requests/teacher_device_requests_screen.dart` | spinner; RefreshIndicator; SnackBars (hidden under sheets) | skeleton; `AppRefresh`; `showAppNotice` | — |
| `features/sessions/teacher/sessions_screen.dart` | RefreshIndicator with `BouncingScrollPhysics` (short list could not be pulled on Android) | `AppRefresh` + always-scrollable physics | — |
| `features/sessions/teacher/components/sessions_section.dart` | colours; two spinners | roles; skeletons | session error state not added: the provider's `hasError` is shared by every action (unreliable as a load error) |
| `features/sessions/teacher/components/course_details_section.dart` | gold `#FFD700/#B8860B`; schedule row + certificate row overflowed at 320 / 1.3 (harness); slot times raw; settings icon unlabeled | → accent2; rows made flexible; `AppTime.clock`; semantic label | settings icon stays 25 px glyph |
| `features/sessions/teacher/components/course_hero.dart`, `course_stats_row.dart`, `session_form_sheet.dart`, `guest_link_sheet.dart` | colours; session form date HH:MM by hand; `only(left:)` error labels | roles; `clockMinutes`; directional | QR `backgroundColor: Colors.white` kept (scanner needs a light quiet zone) |
| `features/sessions/teacher/components/course_reel_player.dart` | 17 colours; 36 px glass buttons without labels | roles + theme import; buttons labelled (tooltip + semantics) with 48 px target | video chrome kept: gold progress line, dark poster gradient, black full-screen background |
| `features/sessions/teacher/students/course_student_screen.dart` | 25 colours (getter + const palette without context); spinner; RefreshIndicator; failed load showed "no students"; 36 px back + 28 px dialog close | roles (palette from theme roles); skeleton; `AppRefresh`; `ErrorRetry`; 48 px targets + labels | — |
| `teacher/certificates/certificate_requests_provider.dart`, `teacher/dashboard/*`, `switch_device_requests` provider, `sessions/model` | no UI issues | — | `teacher/dashboard` belongs to the homes/dashboards owner |

## Live room, lobby, guest, video player (`features/live/room/**`, `shared/{live,guest,session/video}/**`)

| file | issues | fixed | left (reason) |
|---|---|---|---|
| `features/live/room/widgets/live_palette.dart` | room ink tokens incomplete: screens used private white/black copies and raw `Colors.black.withValues` | added `textSoft`, `glassFaint`, `hairline`, `scrimLight`, `scrimHeavy`, `tooltipBg` and `shade(a)` / `ink(a)`, the one way to write room scrims / highlights | the token file itself holds the fixed white / black alphas (always-dark room, documented) |
| `features/live/room/room.dart` (RoomPage) | 61 hard-coded colours (private `_textHigh…` consts, `Colors.white/black…`, 3 dark hexes); `showAppNotice` hidden behind the full-screen room layer; participant dialog times by hand; 7 physical paddings / Positioned; close button without tooltip; 40 px compact button | all colours → `LivePalette` (const tokens, `shade`/`ink`, `surface`/`surfaceHi`/`bg`); `_showSnack(msg, error:)` draws on the room's own Scaffold while the room is full-screen (guest-link errors too); dialog times → `AppTime.dateTime`; `EdgeInsetsDirectional` / `PositionedDirectional` ×9; tooltip; compact density removed | 7 pastel avatar colours (participant identity palette); reconnecting / iOS share-hint SnackBars kept (persistent, closed by code; a notice would be hidden behind the room); spinners kept (inline connection / button states, not lists); `_fmtDuration` uses `DateTime.now()` against server join times (needs the server's time format confirmed) |
| `features/live/room/prejoin_layout.dart` (PreJoinLayout) | 8 hard-coded colours over the camera preview | → `LivePalette` | spinner in the avatar while the camera starts (inline state) |
| `features/live/room/widgets/live_control_bar.dart` (LiveControlBar) | 17 colours incl. private ink copies, tooltip bg hex; count badges pinned `right:`; menu chevron `left:` padding | → `LivePalette` tokens; badges `PositionedDirectional(end:)`; `EdgeInsetsDirectional` | button spinner (inline) |
| `features/live/room/widgets/room_screen_share.dart` (RecordingStatusBanner + share mixin) | 15 neon / dark hexes; **raw exception dump in "Screen share failed: {e}"** ×4 | → `LivePalette.warning/success/surface`; new `shareErrorText(e)` (platform message / `apiErrorText` / plain hint) | — |
| `features/live/room/widgets/live_chat.dart` | 10 colours (private ink copies, bubble hexes); 2 compact icon buttons | → `LivePalette`; 48 px targets | — |
| `features/live/room/widgets/live_hands.dart` | 7 colours; 3 compact icon buttons, 36 px busy slot | → `LivePalette`; 48 px targets + matching busy slot | spinner = per-row busy state |
| `features/live/room/widgets/live_reactions.dart` | 6 colours; compact close button | → `LivePalette`; 48 px | — |
| `features/live/room/widgets/participant_info.dart`, `participant.dart`, `participant_stats.dart`, `live_avatar.dart`, `text_field.dart` | 11 `Colors.black/white.withValues` scrims | → `LivePalette.shade/ink` | participant hues (`LivePalette.avatarColor`) untouched |
| `features/live/room/widgets/controls.dart`, `no_video.dart`, `recording_placeholder.dart`, `room_recorder.dart`, `recorder_*`, `record/*`, `live_quiz.dart`, `prejoin.dart`, `prejoin_mic_meter_*`, `local_debug_save.dart` | none found (0 colours, no raw errors, directional already) | — | — |
| `features/live/live_mini_box.dart` (LiveMiniBoxLayout) | 4 black scrims / hexes | → `LivePalette.scrimLight/scrimHeavy` | 26 px buttons: the box is ~160 px wide; three 48 px targets + LIVE pill do not fit (tap on the box expands it) |
| `features/live/live_lobby_sheets.dart` (LobbySheet, ShareLinkSheet, WaitingForHost, LobbyBanner) | banner drew room-dark hexes; white on success button; 2 refresh icon buttons without tooltip; 3 compact banner buttons; physical banner padding | banner → `LivePalette` (it sits on the room); `c.onHero`; tooltips; 48 px; `EdgeInsetsDirectional` | QR quiet zone stays `Colors.white` (scanner contrast, commented); `appToast` from sheets opened inside the full-screen room is drawn under the room layer (root cause in `lib/design/app_notice.dart`, outside this area) |
| `features/live/meeting_recording.dart`, `meeting_recording_sheets.dart`, `live_room.dart`, `live_room_host.dart` | none found (already kit, AppTime, skeletons) | — | — |
| `shared/guest/guest_state.dart` (GuestBanner, GuestPromoCard, GuestGate) | 9 `Colors.white` on the primary gradient | → `c.onHero` (+ alpha) | compact FilledButtons in the one-line banner kept (40 px, height of the banner) |
| `shared/guest/guest_live_page.dart`, `guest_live_api.dart` | none found (skeleton, error, AppTime, bilingual codes already) | — | — |
| `features/sessions/video/vod_player_parts.dart` | 19 white / black literals over the video; back button without tooltip | new documented `VodInk` palette (ink over video; `letterbox` = the pure black behind the picture, kept black on purpose); tooltip | — |
| `features/sessions/video/video_player_screen.dart` (VideoPlayerScreen chrome) | 73 colours; quality tier hexes; selected speed text white on primary; play / ±10 s buttons without semantics; 38 px glass buttons and 28 px mute / next / rotate targets; error-screen back button without tooltip | → `VodInk` / `c.warning` / `c.success` / `c.onHero`; `Semantics` labels on play/pause/replay and ±10 s; 48 px hit areas; tooltips (back ×2, auto-rotate) | chrome is forced LTR on purpose (seek bar / seek gestures follow the video timeline); buffering + download-progress spinners kept |
| `features/sessions/video/fullscreen_*.dart` | none | — | — |

## Course, materials, Exam Engine, Data Lab, models (`shared/{course,session,exam_engine,models}/**`, `teacher/data_lab/**`)

| file | issues | fixed | left (reason) |
|---|---|---|---|
| lib/features/courses/course_row.dart | 16 hard-coded colours (white ink on badges, black shadows) | colours -> onHero / heroShade / success / danger | private-flag / discount overlays stay physically positioned (left/right) on the card image by design |
| lib/features/courses/course_price_tag.dart | 12 hard-coded colours; white price on coloured chip | -> onHero / success / primary / danger / warning | - |
| lib/features/courses/course_details_section.dart | gold #FFD700 / #B8860B stars and badges, shadows | -> accent2 / heroShade | - |
| lib/features/courses/studend_course_roadmap_section.dart | 15 colours (gold consts, gradient lerp to Colors.black); 3 Row overflows at 320 / 1.3 (title, "explore more", enrol button) | gold -> accent2 / accent, gradient -> heroShade, onHero; texts in Expanded/Flexible with ellipsis | - |
| lib/features/courses/teacher_course_roadmap_section.dart | gold pick consts, #FFD700 | -> accent2 / accent tint | - |
| lib/features/courses/topbar.dart | white icon default; back button tooltip said "share" (bug) | GlassBtn ink -> onHero (nullable param, same API), back tooltip -> MaterialLocalizations backButtonTooltip | 40+2*5 px target already >= 48 |
| lib/features/courses/private_flag.dart | 4 colours | -> danger / onHero | - |
| lib/features/courses/course_access.dart | passcode sheet showed `e.toString()` ("ApiException(403, …): …") | -> apiErrorText(ApiException.from(e)) | - |
| lib/features/courses/home_course_list.dart | hand-written RefreshIndicator | -> AppRefresh | paging footer spinner kept (load-more indicator, not a page loader) |
| lib/features/sessions/material/components/session_material_grid.dart | 27 colours incl. const type-colour map; page spinner; empty-note Row could overflow; LTR-only padding | type colours -> theme switch (_typeColor), white/black -> onHero/heroShade, loader -> AppListSkeleton, empty note Flexible, EdgeInsetsDirectional | image viewer Dialog.fullscreen keeps Colors.black (media letterbox); upload/caption progress spinners kept (inline progress) |
| lib/features/sessions/material/components/add_material_sheet.dart | static const option list with hard-coded colours; left-only margins/paddings | options built from context.colors (getter), blue-grey -> textMedium; EdgeInsetsDirectional (end gap, start error text) | - |
| lib/features/sessions/material/components/session_progress_section.dart | 7 colours; label row overflowed 32 px at 320 / 1.3; LTR-only segment gap and gradients | colours -> success/onHero; badge Expanded+Align, pill texts Flexible/ellipsis; EdgeInsetsDirectional + AlignmentDirectional gradients | - |
| lib/features/sessions/material/components/session_exam_tile.dart | const #FF6D00; button row overflowed 106 px at 320 / 1.3 | attention -> c.warning (static fn), button Flexible + ellipsis, status maxLines 2 | - |
| lib/features/sessions/material/components/session_shared_widgets.dart | white text on filled button | -> onHero | - |
| lib/features/sessions/material/session_material_widget.dart | lerp to Colors.black, white ink | -> heroShade / onHero | - |
| lib/features/sessions/material/components/material_file_style.dart | 7 brand colours (Word/Excel/CSV/PowerPoint/Python) | - | left: file-type identity colours (Word blue, Excel green, …) must not follow the theme |
| lib/features/sessions/session_track_tabs.dart | only Colors.transparent | - | nothing to fix |
| lib/features/exams/exam_paper_pdf.dart | 7 `PdfColors.*` matches | - | left: package:pdf print colours, not Flutter UI colours |
| lib/features/exams/exam_paper_sheet.dart | 6 colours in PaperPreview | - | left: miniature of the printed (white) paper — must stay paper-white in dark mode |
| lib/features/exams/exam_taking_screen.dart | white spinner on button; download error toast showed raw `$e` | -> onHero; toast -> apiErrorText | chevron icons already auto-mirror |
| lib/features/exams/exam_results_screen.dart | 2 raw `$e` toasts; hand RefreshIndicator; asymmetric LTRB | apiErrorText; AppRefresh; fromSTEB | - |
| lib/features/exams/exam_engine_api.dart | non-Api errors became `'$e'` messages | -> ApiException.from(e).message (safe text) | - |
| lib/features/exams/exam_quick_screen.dart | 3 icon-only buttons without tooltip; asymmetric LTRB | tooltips (remove option / pick date / clear); fromSTEB | - |
| lib/features/exams/exam_authoring_screen.dart | hand RefreshIndicator; 5 asymmetric LTRB | AppRefresh; fromSTEB | - |
| lib/features/exams/exam_insights_screen.dart | 2 hand RefreshIndicators | AppRefresh | - |
| lib/features/exams/exam_review_screen.dart | hand RefreshIndicator; asymmetric LTRB | AppRefresh; fromSTEB | - |
| lib/features/exams/exam_scan_review.dart | hand RefreshIndicator | AppRefresh | OCR box Positioned(left:) is image coordinates — correct |
| lib/features/exams/offline/offline_exam_screen.dart | hand RefreshIndicator | AppRefresh | - |
| lib/features/exams/offline/offline_exam_teacher.dart | hand RefreshIndicator | AppRefresh | - |
| lib/features/exams/(generate, paper_flow, consent, policy, offline core/service, other sheets) | checked: kit colours, AppTime, skeletons already | - | nothing to fix |
| lib/features/teacher/data_lab/data_lab_widgets.dart (kit) | 19 colours; dlAgo printed device-local yyyy-mm-dd | white -> onHero (same alpha values: 0.70 / 0.12 kept so light mode is identical); dlAgo date -> AppTime.date (platform tz) | DlSwatches parses user hex (content colour) |
| lib/features/teacher/data_lab/data_lab_screen.dart | 35 colours; raw `$e` toast; search clear button no tooltip; asymmetric LTRB | -> theme roles; apiErrorText; tooltip; fromSTEB | inline row spinners kept |
| lib/features/teacher/data_lab/data_lab_history_sheet.dart | page spinner; old->new arrow double-mirrored in RTL (manual flip of an auto-mirrored icon) | AppListSkeleton; arrow fixed; apiErrorText | load-more spinner kept |
| lib/features/teacher/data_lab/data_lab_import_sheet.dart | page spinner; Back + mapping arrows double-mirrored in RTL; raw `$e` | skeleton; arrows fixed; apiErrorText | - |
| lib/features/teacher/data_lab/data_lab_certificates_sheet.dart | page spinner; 3 raw `$e`; +/- buttons without tooltip | skeleton; apiErrorText; tooltips | - |
| lib/features/teacher/data_lab/data_lab_requests.dart | page spinner; hand RefreshIndicator; 4 raw `$e`; 2 icon buttons without tooltip; colours | skeleton; AppRefresh; apiErrorText; tooltips; colours; fromSTEB | inline busy spinners kept |
| lib/features/teacher/data_lab/data_lab_export_sheet.dart | 3 raw `$e` toasts (save / share) | apiErrorText | - |
| lib/features/teacher/data_lab/data_lab_gate.dart | `_errText` returned `'$e'`; password eye button without tooltip | apiErrorText; show/hide tooltip | continue arrows auto-mirror |
| lib/features/teacher/data_lab/data_lab_provider.dart | `_msg` returned `'$e'` | apiErrorText | - |
| lib/features/teacher/data_lab/data_lab_style_sheet.dart | 5 colours; delete-rule button no tooltip | theme roles; tooltip | - |
| lib/features/teacher/data_lab/(column_sheet, columns_sheet, entry_cards) | white/black colours; asymmetric LTRB | theme roles; fromSTEB | - |
| lib/features/shared/models/** | none (data only) | - | - |
