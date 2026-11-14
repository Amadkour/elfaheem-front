# Screen audit — auth + shared (Track A2, area 1 of 3, 2026-10-28)

Scope: `lib/features/auth/**`, `lib/features/shared/{profile,notification,inbox,calendar,subscription,downloads,upload,passcode,attendance,category,course_profile,analytics}/**`.
Checks per screen: (a) colours only from `context.colors` · (b) list spinners → `AppListSkeleton` · (c) empty + error states, no raw exception text · (d) RTL · (e) overflow at 320×640 / textScaler 1.3 / ar + en · (f) 48 px targets, labels on icon-only buttons · (g) old widgets → kit · (h) times via `AppTime` · (i) pull-to-refresh via `AppRefresh`.
Behaviour and API calls are unchanged except where a row says "bug".

## Totals

| check | before → after |
|---|---|
| (a) `Colors.*` + `Color(0x…)` in the area | 379 → 55 (31 `Colors.transparent`, 24 Google / Telegram / WhatsApp brand hexes) — 324 replaced by theme tokens (`onHero`, `onHeroMuted`, `heroGlassBorder`, `heroShade`, `heroEnd`, `heroTint`, `primary`, `success`, `warning`, `danger`, `divider`, `textLight` …) |
| (b) list / page spinners | 10 → 0 (remaining `CircularProgressIndicator` / `AppLoadingIndicator` are inside buttons, a status strip, small inline sections, or progress rings) |
| (c) raw exception text shown | 7 → 0; error states added on 4 lists, real empty states on 4 |
| (d) physical `EdgeInsets.only(left/right)` · `Positioned(left/right)` with meaning · physical gradient / align | 4 · 6 · 12 → 0 · 0 · 0; 3 double-mirrored chevrons fixed |
| (e) overflows found by the harness | 4 widgets + 1 title row fixed |
| (f) icon-only buttons without a label | 11 → 0; 2 targets raised to 48 px |
| (g) `SettingsGroup` / `SettingsTile` / `ProfileHeader` · `SnackBar` | 29 · 6 → 0 · 0 |
| (h) hand-formatted times / dates | 6 → 0 |
| (i) `RefreshIndicator` by hand · lists without pull-to-refresh | 10 · 4 → 0 · 0 |

Tests: `test/ui/polish_auth_shared_layout_test.dart` (20 tests: `NotificationsStateBody`, `FavouritesStateBody`, `PasscodeSheet`, auth header / banner / step bar, the verification-way widgets, the analytics pieces, the chevron direction, `complaintUtc`).

## Bugs found and fixed

1. **Chevrons pointed backwards in Arabic** — `calendar_screen.dart` (prev / next) and `profile/components/setting_title.dart` (`SettingsTile`) swapped `chevron_left` / `chevron_right` by hand for RTL, but those icons have `matchTextDirection: true`, so Flutter mirrored them a second time. Now the plain icon.
   *Not in this area, same bug:* `lib/design/app_settings.dart` `AppSettingsTile` (the trailing chevron) — left for the owner of `lib/design/`.
2. **Notifications: only the first 30 were reachable** — `NotificationsProvider.loadMore()` existed but the screen never called it. `NotificationsStateBody` asks for the next page near the end of the list (never while a page is loading).
3. **Complaint times** — the model shifted every timestamp to UTC+3 but kept the UTC flag: "x min ago" read 0 for three hours and every time ignored the platform timezone. `complaintUtc()` keeps the real instant; screens show it with `AppTime.date / dateTime / time`; optimistic updates use `DateTime.now().toUtc()`.
4. **Complaints: a failed load showed "no complaints"** (help center list and the history tab), and the provider stored `e.toString()`. Now `ApiException.from(e).message` + `ErrorRetry`.
5. **Edit account: failed saves looked like successes** — `_showSnack(msg, color)` ignored the colour; now `showAppNotice(msg, error: …)`; raw `e.toString()` → API message.
6. **Attendance sheets: confirmations were invisible** — three `SnackBar`s (radios hint, location shared) were drawn behind the open bottom sheet; now `showAppNotice` (root overlay).
7. **Auth fields in dark mode** — `auth_widgets.dart` hard-coded light-only border / muted / brand-light colours (`0xFFE5E7EB`, `0xFF6B7280`, `0xFFEBF1FD`, `0xFF9CA3AF`); now `divider` / `textMedium` / `primaryTint` / `textLight`.
8. **Categories screen was Arabic-only** — 9 hard-coded Arabic strings (search hint, titles, empty texts, "Free") also showed in English; now bilingual.
9. **Calendar day / week grid in RTL** — overlapping events and the hour labels used physical `left`; now `PositionedDirectional`.
10. **Course profile attendance tab** showed raw `'$e'`; now `cpErrorMessage(e)`.

## Per screen

| file | issues found | fixed | left (reason) |
|---|---|---|---|
| auth/login_screen.dart | 6 colours (dark pill gradient hex, `Colors.indigo/orange`) | theme tokens | pill switch alignment is physical on purpose (EN left / AR right) |
| auth/register_screen.dart | 6 colours | theme tokens | terms-loading spinner inside the form step (not a list) |
| auth/forget_screen.dart | — | — | — |
| auth/verified_screen.dart | 3 colours; `SnackBar` | theme; `showAppNotice` | link-section inline spinner (one row) |
| auth/additional_register_screen.dart | 6 colours; `EdgeInsets.only(right)` | theme; `EdgeInsetsDirectional` | inline spinners in buttons / one section |
| auth/google_auth_flow.dart | 37 colours | 17 white / black → `onHero` / `heroShade` | 20 Google brand hexes (the Google mark) |
| auth/mfa_verify_screen.dart · reauth_sheet.dart · mfa.dart | — | — | already kit-based and tested |
| auth/mfa_entry.dart | `SettingsGroup` / `SettingsTile` | `AppSettingsGroup` / `AppSettingsTile` (key `mfa.entry` kept) | — |
| auth/auth_shell.dart | 4 colours, dark gradient hex | theme (`heroShade` → `heroTint`) | physical pill alignment (by design) |
| auth/auth_widgets.dart | 26 colours incl. light-only constants (bug 7); 2 physical margins | theme; directional | — |
| auth/verify_way.dart | 19 colours; 3 physical gradients; `VerifyWayStatusPill` and `VerifyStepTracker` overflow at 320 / 1.3 | theme; directional; `Flexible` + ellipsis | 4 channel colours (`VerifyWay.brand` is a context-free enum getter; Telegram / WhatsApp are brand colours) |
| features/profile/profile_screen.dart | 22 `SettingsTile`, 4 `SettingsGroup`, `ProfileHeader`; 11 colours | `AppSettingsTile` / `AppSettingsGroup(danger:)` / `AppSettingsHeader`; old `ProfileHeader` removed | page not moved to `AppSettingsPage` (the MFA / cloud-drive entries are standalone widgets, not groups); `TileCountOverlay` badges kept |
| features/profile/components/setting_title.dart | chevron double-mirrored (bug 1) | plain `chevron_right_rounded` | widget kept for other callers outside the area |
| features/profile/change_language_screen.dart | — | — | — |
| features/profile/change_password_widget.dart | 1 colour | theme | — |
| features/profile/update_account_widget.dart | 6 colours; back button physically top-right, 42 px, no label; error notice (bug 5); raw `e.toString()` | theme; `AlignmentDirectional.topStart`, 48 px target + semantics; notice `error:`; API message | inline section spinners (small) |
| features/profile/about/about_and_terms_screen.dart | 12 colours; 2 page spinners; 2 hand `RefreshIndicator`; 2 unlabelled close buttons | theme; `AppListSkeleton`; `AppRefresh`; tooltips | — |
| features/profile/privacy_export.dart | — | — | already kit-based, tested |
| features/profile/student_favorite_screen.dart | no loading / empty / error state, no pull-to-refresh | `FavouritesStateBody` (skeleton · `ErrorRetry` · empty / "nothing matches" · `AppRefresh`) | — |
| features/profile/course_instractor_profile.dart | 26 colours (stat / badge hexes); `d/m/y` date | theme; `AppTime.date` | courses section inline spinner |
| features/profile/compalints/complaints_screen.dart | 34 colours; list + detail spinners; 2 `RefreshIndicator`; no error state (bug 4); hand times (bug 3); `EdgeInsets.only(left)` | theme (status / priority → `warning/primary/success/textLight`, `danger`); skeletons; `AppRefresh`; `ErrorRetry`; `AppTime`; directional | send-button spinner (button) |
| features/profile/compalints/new_complaint_screen.dart | 24 colours; `SnackBar`; history spinner, no error / refresh on empty; `d/m/y` | theme; `showAppNotice`; skeleton, `ErrorRetry`, `AppRefresh`; `AppTime.date` | — |
| features/profile/compalints/complaint_attachement_widgets.dart | 14 colours; 3 physical `Positioned`; physical gradient | theme; `PositionedDirectional`; directional | — |
| features/profile/compalints/complaint_provider.dart · complaint_model.dart | `e.toString()`; UTC+3 shift (bug 3) | API message; `complaintUtc` | — |
| features/messaging/notification/notifications_screen.dart | spinner replaced the app bar; bare-icon empty; no error state; empty group drew its header; 20 px "mark all read"; no paging (bug 2) | `NotificationsStateBody`; empty group hidden; `TextButton` 48 px; title `Expanded` | "NEW" badge text is English in both languages (server icon kind; cosmetic) |
| features/messaging/notification/admin_message_dialogs.dart | — | — | — |
| features/messaging/inbox/unified_inbox.dart | 6 colours; hand `RefreshIndicator` | theme; `AppRefresh` | — (skeleton / empty / retry already there) |
| features/calendar/calendar_screen.dart | chevrons (bug 1); 2 colours | plain chevrons | header refresh spinner (16 px status, not a list) |
| features/calendar/calendar_views.dart | physical `Positioned` (bug 9); 5 colours | `PositionedDirectional`; theme | — |
| features/calendar/calendar_models.dart | 2 timetable hexes | `accent2` / `lerp(primary, accent2)` | — |
| features/calendar/calendar_meeting.dart | — | — | already themed; errors via `calErrorText` |
| features/payments/subscription/subscription_screen.dart · _provider.dart | page spinner; provider returned `'$e'` | `AppListSkeleton`; `ApiException.from(e).message` | — |
| features/downloads/downloads_screen.dart | 4 colours; spinner; hand `RefreshIndicator`; home / delete icon buttons unlabelled; physical gradient | theme; skeleton; `AppRefresh`; tooltips; directional | — |
| features/upload/upload_progress_footer.dart · upload_queue_manager.dart | 1 colour; failure text is the raw server body | theme | `task.errorMessage` is logged only, never shown |
| features/profile/passcode/passcode_screen.dart | fixed dark / gold palette (17 hexes) ignored theme and light mode; icon-only delete / close keys | live theme tokens; `Semantics` labels | status-strip spinner (fixed 44 px strip) |
| features/attendance/attendance_widgets.dart (student + teacher sheets) | 16 colours; 3 `SnackBar` (bug 6); teacher sheet without pull-to-refresh; nested scroll view; unlabelled close buttons; hand time | theme; `showAppNotice`; `_SheetFrame(onRefresh:)` + `TeacherAttendanceController.refresh()` (same code read as the ticker), inner scroll view dropped; tooltips; `AppTime.time` | button / stage spinners; student sheet refresh (it polls live) |
| features/attendance/attendance_live_screen.dart | 16 colours | `onHero` / `heroShade` tokens | countdown ring (progress, not loading) |
| features/attendance/attendance_course_entry.dart | 20 colours incl. amber gradient hexes | `warning` / `heroEnd(warning)` | share-button spinner |
| features/attendance/attendance_teacher_banner.dart | 11 colours + 2 hexes; stop button unlabelled | theme (`heroEnd(warning/success)`); `Semantics` label | no tooltip on purpose: the bar sits above the Navigator (no Overlay) |
| features/attendance/attendance_premium.dart | 6 colours; physical gradient | theme; directional | — |
| features/attendance/teacher_attendance_launcher.dart | `Colors.grey` ×2 | theme | no pull-to-refresh: the session list is handed in by the caller |
| features/attendance/offline_attendance_tab.dart | spinner; hand empty state | skeleton; `AppEmpty` | local cache, no refresh source |
| features/attendance/admin_data_lab_page.dart | spinner; hand `RefreshIndicator`; `'$e'`; ± buttons unlabelled | skeleton; `AppRefresh`; API message; tooltips | — |
| features/courses/category/categories_screen.dart · _provider.dart | Arabic-only strings (bug 8); no pull-to-refresh; 5 colours; physical badge; clear-search unlabelled | bilingual `_tx`; `AppRefresh` on both layouts + `CategoriesProvider.refresh()`; theme; directional; tooltip | own shimmer widgets kept (already skeletons) |
| features/courses/course_profile/course_profile_screen.dart | 7 colours; hand `RefreshIndicator` | theme; `AppRefresh` | — |
| features/courses/course_profile/course_profile_parts.dart | hand `RefreshIndicator`; raw `'$e'` | `AppRefresh`; `cpErrorMessage` | — |
| features/courses/course_profile/course_profile_actions.dart · _announcements.dart · _models.dart | — | — | already kit-based |
| features/analytics/analytics_ui.dart | 21 colours; `AnGlassPill` / `AnChip` overflow on long labels | theme; `Flexible` + ellipsis | — |

## Process note

The scratchpad is shared with the other polish agents. One `unused.py` run read another agent's analyzer output and removed
imports reported unused there from files outside this area (`app_loading_indicator.dart` in admin / org pages, `base_page.dart` in
`features/home/student/dashboard/dashboard_screen.dart`). Those imports were unused at that moment (the removal only clears a warning), but the
owners of those folders should know.
