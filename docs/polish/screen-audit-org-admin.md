# Screen audit — organizations · admin · ads (Track A2, area 3 of 3, 2026-10-28)

Scope: `lib/features/org/**` (without the org dashboard / department / member dashboards and `org_providers.dart`),
`lib/features/admin/**` (without the admin dashboard / overview / home and `admin_providers.dart`), `lib/features/ads/**`.
112 UI files (every file in the area with a `build`); pure model / API / export-writer files are not listed.

## Method

Every file was checked mechanically, then the frequently used screens by hand (members, join requests, departments,
courses, announcements, complaints, forms, governance lists / item, councils, registrar, schedule studio chrome,
admin users / courses / finance / payouts / organizations / features / theme):

| check | rule | how |
|---|---|---|
| a colours | only `context.colors` | `Colors.*` (not `transparent`) + `Color(0x…)` → on-hero roles (`onHero`, `onHeroMuted`, `heroGlassBorder`, `heroShade`, `heroEnd`, `heroTint`), status roles, `AppTheme` fallbacks |
| b loading | `AppListSkeleton`, not a spinner | page-level `Center(child: AppLoadingIndicator / CircularProgressIndicator)`; inline button / chip progress kept |
| c empty / error | `AppEmpty` / `ErrorRetry` / `orgErrorText`, no raw exception text | loaders that leave the page on a skeleton after a failure; no `'$e'` found anywhere in the area |
| d RTL | directional insets / alignment | asymmetric `EdgeInsets.fromLTRB`, `left:` / `right:`, `Alignment.centerLeft` (only gradients left: they are symmetric) |
| e overflow | 320×640 and 1400×900, ar + en, ×1.3 | heuristic scan of `Row`s with bare `Text`; presentational pieces pumped by `expectNoLayoutErrors` |
| f touch / semantics | icon-only buttons have a tooltip | every `IconButton` without `tooltip:` |
| g kit | `AppDropdown`, `AppSwitch`, `AppRefresh`, `showAppNotice` | raw `DropdownButtonFormField`, hand-made `RefreshIndicator` (no raw `Switch` was left in the area) |
| h time | `AppTime` + org timezone | raw `HH:MM` strings, device-date "today", `toLocal()` helpers |
| i refresh | `AppRefresh` on lists | lists without pull-to-refresh |
| org | `ContextExitButton` on every staff org screen | every `ScreenAppBar` in `lib/features/org` |

## Totals (area, before → after)

| measure | before | after |
|---|---|---|
| hard-coded colours (`Colors.*` without `transparent`, `Color(0x…)`) | 312 | 52 (all listed as "left" below: theme preset swatches 20 + the hex parser 1, camera viewfinder 16, photo viewers 9, QR quiet zones 4, printed-page preview 2) |
| `Colors.transparent` (not a colour choice) | 49 | 48 |
| page-level spinners | 46 | 2 (one image being rendered, one image loading) |
| hand-made `RefreshIndicator` | 61 | 0 (`AppRefresh` 5 → 71, incl. 5 lists that had none) |
| LTR-only `fromLTRB` insets | 12 | 0 |
| icon-only buttons without tooltip | 67 | 0 |
| raw `DropdownButtonFormField` | 2 | 0 |
| `ContextExitButton` on org app bars | 13 | 36 |
| `ErrorRetry` states | 21 | 27 |

## Bugs found and fixed

1. `org_availability_pages.dart` — the availability-request screen cannot be popped until submitted and swallowed its
   load error: offline, the person was trapped on an endless skeleton. Now `ErrorRetry`, and the screen may be left.
2. `org_access_joining.dart` — the "How people join" tab stayed on a skeleton forever when `/join/settings` failed.
3. `org_sharing_pages.dart` — the sharing overview stayed on a skeleton after any load error (a toast only).
4. `org_academic_pages.dart` — course archive and "My academic path" stayed on a skeleton when the load failed.
5. `org_home_tab.dart` — "today" extras / upcoming used the DEVICE date and weekday while the classes beside them used
   the organization's timezone (`appToday()`); now both use `AppTime`.
6. `admin_premium_widgets.dart` — `AdminPalette.teal` dereferenced `_t!` and threw when used before `attach()`.
7. Overflows found by the harness: `HeroPill` and `PremiumSaveBar` with a long label, `ErrorRetry` in a short slot
   (`OrgAsync` gives it 280 px), `OrgActionCard` with a wide trailing widget; plus 11 header / status rows that could
   not wrap (`Flexible` now).
8. `admin_common.dart` `shortDate` / `shortDateTime` showed UTC instants in the device zone and always 24 h; now the
   platform / organization zone and the 12 h / 24 h choice (`AppTime`). Raw `HH:MM` clocks in the member timetable,
   remedies and suggestions now go through `AppTime.clock` / `clockRange`.

No API call, request body or PUT payload was changed.

## Tests

`test/ui/polish_org_admin_layout_test.dart` (10 tests): `OrgMemberRowView` (new, factored out of the members list),
`OrgHero`, `PremiumHero` + `HeroPill`, `AdCard`, loading / failed / empty states (`AppListSkeleton`, `OrgAsync`,
`ErrorRetry`, `OrgEmpty`), `SheetHeader` + `PremiumSaveBar`, the shared org kit (section title, stat grid, action
cards, pills, info rows), the shared admin kit (`Section`, `KeyValue`, `EmptyState`, `FilterChips`, `SearchBox`, `Field`,
`RowCard`, chips), premium cards / select tiles / switch rows, `ComplaintBubble`, `AnnouncementCard`.

## Per screen

| file | issues | fixed | left (reason) |
|---|---|---|---|
| `admin/admin_admins_page.dart` | 2 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator` | colours 2->0; 1 spinner->`AppListSkeleton`; 1->`AppRefresh` | - |
| `admin/admin_auth_settings_page.dart` | 3 hard-coded colours; 1 page spinner(s) | colours 3->0; 1 spinner->`AppListSkeleton` | - |
| `admin/admin_categories_page.dart` | 2 hard-coded colours | colours 2->0 | - |
| `admin/admin_common.dart` | 4 hard-coded colours; 1 LTR-only inset(s); 2 icon-only button(s) without tooltip; `shortDate` / `shortDateTime` ignored the platform zone and 12h/24h; `ErrorRetry` overflowed in a short slot (harness); `toast` fallback ink hard-coded | colours 4->0; 1->`EdgeInsetsDirectional`; 2 tooltip(s); `shortDate*` read UTC instants through `AppTime` (zone + 12h/24h); `ErrorRetry` scrolls when short; toast ink = `AdminPalette.ink` | naive timestamps are still shown as sent: a naive server UTC string cannot be told apart from a locally picked date, and shifting those would move picked days |
| `admin/admin_content_page.dart` | 7 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator`; 1 LTR-only inset(s); mission header could overflow | colours 7->0; 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1->`EdgeInsetsDirectional`; `Flexible` | two inline 24 px spinners (image upload / avatar) |
| `admin/admin_courses_page.dart` | 2 hard-coded colours; 2 page spinner(s) | colours 2->0; 2 spinner->`AppListSkeleton` | - |
| `admin/admin_data_lab_page.dart` | 1 page spinner(s); 1 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip | 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 2 tooltip(s) | - |
| `admin/admin_datacenter_page.dart` | 6 hard-coded colours; 3 page spinner(s); 3 icon-only button(s) without tooltip | colours 6->0; 3 spinner->`AppListSkeleton`; 3 tooltip(s); brand-colour choices drawn from their hex value (data), list gets `AppRefresh` | template preview overlay spinner (over an image being rendered) |
| `admin/admin_devices_page.dart` | 1 page spinner(s) | 1 spinner->`AppListSkeleton` | - |
| `admin/admin_feature_guide.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `admin/admin_features_page.dart` | 1 hand-made `RefreshIndicator`; 1 LTR-only inset(s) | 1->`AppRefresh`; 1->`EdgeInsetsDirectional` | - |
| `admin/admin_fee_rates.dart` | 1 page spinner(s) | 1 spinner->`AppListSkeleton` | - |
| `admin/admin_feedback_settings.dart` | none found by the checks | - | - |
| `admin/admin_filters.dart` | 2 hard-coded colours; 1 page spinner(s); 2 icon-only button(s) without tooltip; results count line could overflow | colours 2->0; 1 spinner->`AppListSkeleton`; 2 tooltip(s); `Flexible` | - |
| `admin/admin_finance_page.dart` | 22 hard-coded colours; 2 page spinner(s); 2 hand-made `RefreshIndicator`; status colours were 6 `const Color(0x...)` | colours 22->5; 1 spinner->`AppListSkeleton`; 2->`AppRefresh`; status colours follow the theme (`AdminPalette`) | receipt photo viewer keeps a black backdrop / white ink (photo viewer convention, 5 refs); `showRequestSnack` is the shared swipe-card helper (outside the area) |
| `admin/admin_flags_settings_page.dart` | 3 hard-coded colours; 1 page spinner(s); card title could overflow | colours 3->0; 1 spinner->`AppListSkeleton`; `Flexible` | - |
| `admin/admin_income_breakdown.dart` | 1 page spinner(s); chart spinner | 1 spinner->`AppListSkeleton`; chart slot shows a skeleton | - |
| `admin/admin_list.dart` | 1 hard-coded colours; 2 page spinner(s); 4 hand-made `RefreshIndicator` | colours 1->0; 2 spinner->`AppListSkeleton`; 4->`AppRefresh`; `PagedList` / `AdminSimpleList` (every admin list) now skeleton + `AppRefresh` | - |
| `admin/admin_mfa_page.dart` | 2 hard-coded colours | - | QR code keeps a white quiet zone (scannability, 2 refs) |
| `admin/admin_money_p8.dart` | none found by the checks | - | - |
| `admin/admin_organizations_page.dart` | none found by the checks | - | - |
| `admin/admin_parent_link_settings_page.dart` | 1 page spinner(s); 1 icon-only button(s) without tooltip | 1 spinner->`AppListSkeleton`; 1 tooltip(s) | - |
| `admin/admin_parent_requests_page.dart` | 3 page spinner(s); 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip; status line could overflow | 3 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1 tooltip(s); `Flexible` | - |
| `admin/admin_payment_page.dart` | 13 hard-coded colours; 2 page spinner(s); 1 LTR-only inset(s) | colours 13->0; 2 spinner->`AppListSkeleton`; 1->`EdgeInsetsDirectional` | inline 18 px spinner in a switch row (action progress) |
| `admin/admin_payouts_page.dart` | 4 hard-coded colours; 1 page spinner(s) | colours 4->0; 1 spinner->`AppListSkeleton` | inline spinner in a button (action progress) |
| `admin/admin_platform_settings_page.dart` | 2 hand-made `RefreshIndicator` | 2->`AppRefresh` | - |
| `admin/admin_platform_widgets.dart` | none found by the checks | - | - |
| `admin/admin_premium_widgets.dart` | 22 hard-coded colours; `AdminPalette.teal` threw before `attach()` (`_t!`) - **bug**; fallbacks were hex literals; `HeroPill` / `PremiumSaveBar` overflowed with a long label (harness) | colours 22->0; null-safe `teal`; fallbacks are `AppTheme` constants; new `AdminPalette.ink`; labels ellipsize | - |
| `admin/admin_profile_page.dart` | 9 hard-coded colours; 1 page spinner(s); card title could overflow | colours 9->0; 1 spinner->`AppListSkeleton`; `Flexible` | - |
| `admin/admin_required_documents_page.dart` | 2 hard-coded colours; 1 page spinner(s); no pull-to-refresh | colours 2->0; 1 spinner->`AppListSkeleton`; `AppRefresh` on the list and the reorderable list | - |
| `admin/admin_send_message_page.dart` | 1 page spinner(s); 1 icon-only button(s) without tooltip | 1 spinner->`AppListSkeleton`; 1 tooltip(s) | - |
| `admin/admin_services_hub.dart` | 1 hard-coded colours | colours 1->0 | - |
| `admin/admin_subscriptions_page.dart` | 2 hard-coded colours; 1 icon-only button(s) without tooltip | colours 2->0; 1 tooltip(s) | - |
| `admin/admin_theme_page.dart` | 31 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip | colours 31->21; 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1 tooltip(s); unparsable swatch / preview fallbacks from the theme | 20 preset swatches + the hex parser are data (the palette the super admin picks) |
| `admin/admin_users_page.dart` | 2 hard-coded colours; 1 page spinner(s); 1 icon-only button(s) without tooltip | colours 2->0; 1 spinner->`AppListSkeleton`; 1 tooltip(s) | - |
| `admin/admin_versions_page.dart` | 2 hard-coded colours | colours 2->0 | - |
| `admin/admin_view_as_page.dart` | 5 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip; "view as" banner used a fixed amber hex | colours 5->0; 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1 tooltip(s); banner = `c.warning` | - |
| `features/payments/enrollment_request/teacher_transfers_screen.dart` | 8 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip | colours 8->4; 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1 tooltip(s); image caption scrim from `heroShade` | full-screen photo viewer keeps black / white (4 refs); `showRequestSnack` shared helper |
| `admin/receipt_viewer.dart` | 16 hard-coded colours; 1 page spinner(s); 1 LTR-only inset(s); a private light palette (`_muted`, `_line`, `_surface`, `_blue`, pinks) ignored dark mode | colours 16->0; 1->`EdgeInsetsDirectional`; every colour from `context.colors` | image-loading spinner inside the zoom viewer (progress of one image, not a page) |
| `ads/ads_pages.dart` | 15 hard-coded colours; 4 icon-only button(s) without tooltip | colours 15->0; 4 tooltip(s); image scrim from `heroShade` | reaction chips are ~28 px tall (glass overlay on the ad; a bigger target would cover the image) |
| `org/governance/gov_council_settings.dart` | 2 icon-only button(s) without tooltip | 2 tooltip(s) | - |
| `org/governance/gov_council_ui.dart` | none found by the checks | - | - |
| `org/governance/gov_councils_page.dart` | 1 hard-coded colours; 1 hand-made `RefreshIndicator` | colours 1->0; 1->`AppRefresh` | - |
| `org/governance/gov_dashboard.dart` | 1 icon-only button(s) without tooltip | 1 tooltip(s) | - |
| `org/governance/gov_delegations_page.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/governance/gov_entities_page.dart` | 2 hand-made `RefreshIndicator` | 2->`AppRefresh` | - |
| `org/governance/gov_filter.dart` | 1 hard-coded colours; 1 icon-only button(s) without tooltip | colours 1->0; 1 tooltip(s) | - |
| `org/governance/gov_forms_assign.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/governance/gov_item_screen.dart` | 4 hard-coded colours; 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip | colours 4->0; 1->`AppRefresh`; 1 tooltip(s) | - |
| `org/governance/gov_items_page.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/governance/gov_member_pages.dart` | 2 hand-made `RefreshIndicator` | 2->`AppRefresh` | member pages: no exit button by design (`if (!widget.member)` convention); upload chip spinner is inline |
| `org/governance/gov_my_votes.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/governance/gov_route_sheet.dart` | none found by the checks | - | - |
| `org/governance/gov_session_screen.dart` | 2 hard-coded colours; 1 hand-made `RefreshIndicator` | colours 2->0; 1->`AppRefresh` | - |
| `org/governance/gov_settings_page.dart` | none found by the checks | - | - |
| `org/governance/gov_ui.dart` | 1 hard-coded colours; 2 icon-only button(s) without tooltip; chip-group label could overflow | colours 1->0; 2 tooltip(s); `Flexible` label | - |
| `org/home_org_mix.dart` | none found by the checks | - | - |
| `org/org_academic_pages.dart` | 10 hard-coded colours; 3 page spinner(s); 1 hand-made `RefreshIndicator`; 4 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton`; course archive and "my path" stayed on a skeleton when `getMap` returned null - **bug** | colours 10->0; 3 spinner->`AppListSkeleton`; 1->`AppRefresh`; 4 tooltip(s); `ContextExitButton` on 1 app bar(s); 2 `ErrorRetry`; `ErrorRetry` on both | - |
| `org/org_access_joining.dart` | 4 hard-coded colours; 3 hand-made `RefreshIndicator`; 1 LTR-only inset(s); 1 staff app bar(s) without `ContextExitButton`; join-settings tab stayed on a skeleton forever when `/join/settings` failed - **bug** | colours 4->2; 3->`AppRefresh`; 1->`EdgeInsetsDirectional`; `ContextExitButton` on 1 app bar(s); 1 `ErrorRetry`; `ErrorRetry` with the server reason (`orgErrorText`) | QR card keeps a white background (scannability, 2 refs) |
| `org/org_access_page.dart` | 3 hard-coded colours; 1 page spinner(s); 1 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip; 2 staff app bar(s) without `ContextExitButton` | colours 3->0; 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 2 tooltip(s); `ContextExitButton` on 2 app bar(s) | - |
| `org/org_announcements.dart` | 8 hard-coded colours; 2 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton` | colours 8->0; 2->`AppRefresh`; 1 tooltip(s); `ContextExitButton` on 1 app bar(s) | - |
| `org/org_application_screen.dart` | none found by the checks | - | personal context (registering a new institution): no exit button |
| `org/org_availability_pages.dart` | 7 hard-coded colours; 1 page spinner(s); availability request screen cannot be popped until submitted and swallowed load errors: the person was trapped on an endless skeleton offline - **bug** | colours 7->0; 1 spinner->`AppListSkeleton`; 1 `ErrorRetry`; `ErrorRetry`; the screen may be left when it could not load | - |
| `org/org_common.dart` | 5 hard-coded colours; 1 LTR-only inset(s) | colours 5->0; 1->`EdgeInsetsDirectional`; hero gradient end via `heroEnd` | - |
| `org/org_courses_page.dart` | 2 hard-coded colours | colours 2->0 | - |
| `org/org_creation_fee.dart` | none found by the checks | - | - |
| `org/org_departments_page.dart` | 11 hard-coded colours; 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton` | colours 11->0; 1->`AppRefresh`; 1 tooltip(s); `ContextExitButton` on 1 app bar(s) | - |
| `org/org_dynamic_form.dart` | none found by the checks | - | - |
| `org/org_feedback_risk.dart` | no pull-to-refresh on the risk list | `AppRefresh` | - |
| `org/org_home_tab.dart` | 8 hard-coded colours; 1 hand-made `RefreshIndicator`; "today" extras compared the DEVICE date while the classes used the org timezone; weekday from the device - **bug** | colours 8->0; 1->`AppRefresh`; both from `appToday()` (AppTime) | - |
| `org/org_join_pages.dart` | 4 hard-coded colours; 3 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton` | colours 4->0; 3->`AppRefresh`; 1 tooltip(s); `ContextExitButton` on 1 app bar(s) | the unit join page opened from outside the org has no exit button (personal context) |
| `org/org_join_scan.dart` | 16 hard-coded colours | - | camera viewfinder keeps black / white over the camera feed (16 refs) |
| `org/org_levels_pages.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/org_member_changes.dart` | none found by the checks | - | - |
| `org/org_member_form.dart` | none found by the checks | - | - |
| `org/org_member_pages.dart` | 9 hard-coded colours; 2 page spinner(s); 2 hand-made `RefreshIndicator`; timetable rows printed raw "HH:MM:SS" | colours 9->0; 2 spinner->`AppListSkeleton`; 2->`AppRefresh`; `AppTime.clock` (12h/24h) | member screen: no exit button (member convention, the member dashboard adds it) |
| `org/org_member_space.dart` | 3 hard-coded colours; 2 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip; star rating buttons had no labels | colours 3->0; 2->`AppRefresh`; 2 tooltip(s); "n of 5" tooltips | member screens: no exit button (member convention) |
| `org/org_member_today.dart` | 1 LTR-only inset(s) | 1->`EdgeInsetsDirectional` | - |
| `org/org_my_exams.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | member screen: no exit button (member convention) |
| `org/org_people_page.dart` | 3 hard-coded colours; 2 icon-only button(s) without tooltip; member row inline in a provider widget (not testable) | colours 3->0; 2 tooltip(s); `OrgMemberRowView` (plain values) factored out and harness-tested | - |
| `org/org_platform_settings_page.dart` | 1 hand-made `RefreshIndicator` | 1->`AppRefresh` | - |
| `org/org_program_form.dart` | section title could overflow | `Flexible` title | - |
| `org/org_registrar_member.dart` | 2 hand-made `RefreshIndicator` | 2->`AppRefresh` | member screens: no exit button (member convention); inline spinner while a registration job runs |
| `org/org_registrar_staff.dart` | 3 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip | 3->`AppRefresh`; 2 tooltip(s) | - |
| `org/org_reports/report_page.dart` | 2 hard-coded colours; 2 hand-made `RefreshIndicator`; 1 LTR-only inset(s); 2 staff app bar(s) without `ContextExitButton` | 2->`AppRefresh`; 1->`EdgeInsetsDirectional`; `ContextExitButton` on 2 app bar(s) | page preview keeps `_paper` / `_ink` (WYSIWYG of the printed page); designer canvas uses absolute `left` like the PDF renderer |
| `org/org_schedule_autopilot.dart` | none found by the checks | - | - |
| `org/org_schedule_board.dart` | none found by the checks | - | board is wide by design (`AppHScroll`); "why here" `LinearProgressIndicator` is inline progress |
| `org/org_schedule_copies.dart` | 2 page spinner(s); 1 hand-made `RefreshIndicator`; 1 raw `DropdownButtonFormField`; 2 staff app bar(s) without `ContextExitButton` | 2 spinner->`AppListSkeleton`; 1->`AppRefresh`; `ContextExitButton` on 2 app bar(s); `AppDropdown`; `AppDropdown` for the member picker | - |
| `org/org_schedule_exams.dart` | 1 hand-made `RefreshIndicator`; 2 staff app bar(s) without `ContextExitButton` | 1->`AppRefresh`; `ContextExitButton` on 2 app bar(s) | - |
| `org/org_schedule_export.dart` | 1 raw `DropdownButtonFormField` | `AppDropdown`; `AppDropdown` for the member picker | PDF / Excel colours (`PdfColors`, hex fills) belong to the file, not the theme |
| `org/org_schedule_generate.dart` | none found by the checks | - | - |
| `org/org_schedule_grid.dart` | none found by the checks | - | compact `DropdownButton` inside the filter bar (`AppDropdown` is a full-width field); the grid itself is wide by design (`AppHScroll`) |
| `org/org_schedule_groups.dart` | 1 staff app bar(s) without `ContextExitButton` | `ContextExitButton` on 1 app bar(s) | - |
| `org/org_schedule_hub.dart` | none found by the checks | - | - |
| `org/org_schedule_insights.dart` | 1 hard-coded colours | colours 1->0 | - |
| `org/org_schedule_ladder_ui.dart` | 1 LTR-only inset(s); 2 icon-only button(s) without tooltip | 1->`EdgeInsetsDirectional`; 2 tooltip(s) | - |
| `org/org_schedule_pages.dart` | 5 hard-coded colours; 1 page spinner(s); 9 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton` | colours 5->0; 1 spinner->`AppListSkeleton`; 9 tooltip(s); `ContextExitButton` on 1 app bar(s) | - |
| `org/org_schedule_planning.dart` | 1 page spinner(s); 1 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip; 1 staff app bar(s) without `ContextExitButton`; error state was a bare red text + text button | 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 2 tooltip(s); `ContextExitButton` on 1 app bar(s); 1 `ErrorRetry`; `ErrorRetry` | - |
| `org/org_schedule_preview.dart` | 1 hard-coded colours | colours 1->0 | - |
| `org/org_schedule_reassign.dart` | 1 hard-coded colours | colours 1->0 | - |
| `org/org_schedule_remedies.dart` | conflict time printed raw | `AppTime.clockRange` (period ranges follow the platform / org 12h / 24h choice like every displayed time; `test/org/org_reassign_test.dart` now expects `P1 (8:00 – 9:30 AM)` in 12h and `P1 (08:00 – 09:30)` in 24h instead of the raw `08:00–09:30`) | - |
| `org/org_sections_page.dart` | 1 page spinner(s); 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip | 1 spinner->`AppListSkeleton`; 1->`AppRefresh`; 1 tooltip(s) | section time picker works in the device zone (sent as UTC, unchanged behaviour) |
| `org/org_services_pages.dart` | 6 hard-coded colours; 1 hand-made `RefreshIndicator`; 2 icon-only button(s) without tooltip; 4 staff app bar(s) without `ContextExitButton`; complaint bubble sender name could overflow | colours 6->0; 1->`AppRefresh`; 2 tooltip(s); `ContextExitButton` on 4 app bar(s); name wraps (`Flexible`) | - |
| `org/org_sharing_pages.dart` | overview stayed on a skeleton forever after a load error (only a toast) - **bug**; no pull-to-refresh | 1 `ErrorRetry`; `ErrorRetry` with `orgErrorText`; `AppRefresh` on requests | - |
| `org/org_status_screen.dart` | 2 hard-coded colours; 1 hand-made `RefreshIndicator` | colours 2->0; 1->`AppRefresh` | - |
| `org/org_suggestions.dart` | periods printed raw | `AppTime.clockRange` | - |
| `org/org_terms_pages.dart` | 1 hand-made `RefreshIndicator`; 1 icon-only button(s) without tooltip | 1->`AppRefresh`; 1 tooltip(s) | - |
| `org/org_timetable_parts.dart` | 1 hard-coded colours; 5 icon-only button(s) without tooltip; section / lab header could overflow | colours 1->0; 5 tooltip(s); `Flexible` header | - |
| `org/org_timetable_wizard.dart` | 2 hard-coded colours; 2 icon-only button(s) without tooltip; 2 staff app bar(s) without `ContextExitButton` | colours 2->0; 2 tooltip(s); `ContextExitButton` on 2 app bar(s) | - |
| `org/org_ui.dart` | 1 hard-coded colours; 1 page spinner(s); 2 LTR-only inset(s); `OrgAsync` spinner; `OrgActionCard` trailing could overflow (harness) | colours 1->0; 1 spinner->`AppListSkeleton`; 2->`EdgeInsetsDirectional`; `OrgAsync` loading = skeleton (every org section using it); trailing capped at 150 px | - |
| `org/org_workspace.dart` | 1 staff app bar(s) without `ContextExitButton` | `ContextExitButton` on 1 app bar(s) | - |
| `org/orgs_unavailable_gate.dart` | none found by the checks | - | - |
