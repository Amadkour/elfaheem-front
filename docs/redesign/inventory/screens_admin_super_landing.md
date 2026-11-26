# Inventory: landing, admin and super admin screens vs today's code

Source: `docs/redesign/SCREENS.md` (landing 1-6, admin 1-52, super 1-107). Paths are relative to the repo root.
Abbreviations: `HUB` = `lib/features/admin/admin_services_hub.dart` (service groups people / finance / learning / support / config; `visible: isSuper` marks super-only). `DASH` = `lib/features/admin/admin_dashboard_screen.dart` (phone: 4 tabs + More; web: 9 tabs). Route: `/admin_dashboard` in `lib/main.dart` is the only admin route; every other page is pushed from `HUB` or a tab. `/exports` is a named route.
Status: exists = restyle only; partial = part is missing; missing = new; replace = design changes behaviour. "verify" = could not confirm from file names alone.

## Landing (Astro, `landing/`)

Today: ONE audience-neutral page `landing/src/components/Landing.astro` (hero with course finder, trust stats, how, features, preview, testimonials, entry cards student/teacher/org, FAQ, sticky CTA, footer); copy in `landing/src/i18n/ar.ts|en.ts`; routes `landing/src/pages/{ar,en}/index.astro`, `download.astro` (`DownloadPage.astro`), `privacy|terms.astro` (`LegalPage.astro`); theme `landing/src/theme/*`; testimonials `landing/src/content/testimonials.json`; remote data `landing/src/data/remote.ts`.

| # | Design screen | URL | Existing file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1-2 | Students landing (phone + web) | `LandingStudentM/W.dc.html` | `landing/src/components/Landing.astro`, `i18n/ar.ts`, `pages/ar/index.astro` | `/ar/`, `/en/` | replace | Today generic page with a course finder; design is audience-specific. Reuse finder and testimonials data; new copy and sections. |
| 3-4 | Parents landing (phone + web) | `LandingM/W.dc.html` | none (only a `parent` join link in hero and FAQ) | none | missing | New page + route (e.g. `/ar/parents/`), copy ar+en, link to the child code login. Note `LandingW` headings read like a teacher/parent mix: open to confirm which audience it is. |
| 5-6 | Teachers landing (phone + web) | `LandingTeacherM/W.dc.html` | none (entry card "teacher" in `Landing.astro`) | none | missing | New page + route; hero already has `join.teacher` CTA. |

Also touch: `landing/src/layouts/*`, `styles/*`, `theme/theme-default.json`, and the admin landing editor `lib/features/admin/landing/*` (super 75-79) so it knows the three pages.

## Admin

| # | Design screen | URL | Existing file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1 | Overview | `AdmHome ?screen=overview` | `admin_overview_page.dart`, `admin_home_body.dart`, `admin_home_data.dart`, `admin_income_breakdown.dart` | DASH tab 0 | exists (needs restyle) | One `/me/home` call; keep the request budget. |
| 2 | Global search (Ctrl K) | `AdmHome ?screen=search` | `admin_global_search.dart`, `admin_recents.dart` | Ctrl+K in DASH | exists (needs restyle) | |
| 3 | All services (More) | `AdmHome ?screen=more` | `admin_services_hub.dart` (`_MorePage`) | DASH phone More tab | exists (needs restyle) | |
| 4 | My account + 2-step | `AdmHome ?screen=account` | `admin_profile_page.dart`, `admin_mfa_page.dart` | DASH My account | exists (needs restyle) | |
| 5, 10 | Students table + bulk select; filters | `AdmStudents ?screen=list/filters` | `admin_users_page.dart`, `admin_list.dart`, `admin_bulk.dart`, `admin_filters.dart`, `admin_filter_models.dart`, `admin_table_export.dart` | DASH tab 1 | exists (needs restyle) | |
| 6-9 | Student detail: overview, courses, subscription and payments, account and devices | `AdmStudents ?screen=detail&tab=..` | `admin_student_manage.dart`, `admin_entity_manage.dart`, `admin_subscriptions_page.dart`, `admin_devices_page.dart`, `admin_username_field.dart` | row in users list | partial | Verify one detail page with 4 tabs (today likely a manage sheet). |
| 11 | Add account | `AdmStudents ?screen=add` | `admin_users_page.dart` (create), `admin_account_fee_widgets.dart` | users page action | exists (needs restyle) | |
| 12 | Enroll student in course | `AdmStudents ?screen=enroll` | `lib/features/courses/admin/course_students/*`, `admin_student_manage.dart` | course students / student | exists (needs restyle) | |
| 13 | Grant subscription | `AdmStudents ?screen=grant` | `admin_subscriptions_page.dart` | HUB `subscriptions` | exists (needs restyle) | |
| 14 | Teachers table | `AdmTeachers ?screen=list` | `admin_users_page.dart` (role teacher) | DASH tab 3 | exists (needs restyle) | |
| 15-18 | Teacher profile, pending, courses, documents | `AdmTeachers ?screen=detail&tab/who` | `admin_entity_manage.dart`, `lib/features/teachers/teacher_review_admin.dart`, `admin_required_documents_page.dart` | users list -> detail | partial | Documents tab: verify an admin sees a teacher's uploaded documents inside the detail. |
| 19 | Teacher review | `AdmTeachers ?screen=review` | `lib/features/teachers/teacher_review_admin.dart` | HUB `admin_teacher_review` | exists (needs restyle) | Today super-only (`visible: isSuper`); design is admin-level: permission change. |
| 20 | Required teacher documents | `AdmTeachers ?screen=docs` | `admin_required_documents_page.dart` | HUB `required_documents_title` | exists (needs restyle) | |
| 21 | Courses table | `AdmCourses ?screen=list` | `admin_courses_page.dart` | DASH tab 2 | exists (needs restyle) | |
| 22-24 | Course detail: overview, students, management + access code | `AdmCourses ?screen=detail&tab` | `admin_courses_page.dart`, `lib/features/courses/admin/course_students/*`, shared course page (`CourseSpace`) | course row | partial | Verify the management / access code tab. |
| 25 | Add / edit course | `AdmCourses ?screen=form` | course form (teacher/shared course form) | admin_courses_page -> form | exists (needs restyle) | |
| 26 | People and messages hub | `AdmPeople ?screen=hub` | HUB group `people` | web tab People | exists (needs restyle) | |
| 27-28 | Parents list + parent detail | `AdmPeople ?screen=parents/parent` | `admin_parent_linking_page.dart` | HUB `admin_parent_linking` | partial | Parent detail page to verify. |
| 29 | Parent link requests | `AdmPeople ?screen=links` | `admin_parent_requests_page.dart` | HUB parent linking | exists (needs restyle) | |
| 30 | Send message | `AdmPeople ?screen=message` | `admin_send_message_page.dart` | HUB `send_message` | exists (needs restyle) | |
| 31 | Notices requiring acknowledgement | `AdmPeople ?screen=notices` | `AdminRequirementsPage` | HUB `svc_requirements` | exists (needs restyle) | |
| 32 | Requests and approvals inbox | `AdmApprovals ?screen=inbox` | none single (pieces: `admin_account_approval.dart`, `teacher_transfers_screen.dart`, `admin_devices_page.dart`, `certificate_requests_screen.dart`) | none | missing | New aggregate page; counts from `/me/attention` plus per-queue lists (backend). |
| 33-34 | Bank transfer review + reject with reason | `AdmApprovals ?screen=transfer/reject` | `lib/features/payments/enrollment_request/teacher_transfers_screen.dart`, `receipt_viewer.dart`, `admin_payment_page.dart` | HUB `enrollment_requests` | exists (needs restyle) | |
| 35 | Accounts awaiting approval | `AdmApprovals ?screen=accounts` | `admin_account_approval.dart` | HUB `svc_pending_accounts` | exists (needs restyle) | |
| 36 | Device requests | `AdmApprovals ?screen=devices` | `admin_devices_page.dart` | HUB `admin_devices` | exists (needs restyle) | |
| 37 | Certificate requests | `AdmApprovals ?screen=certs` | `lib/features/certificates/certificate_requests_screen.dart` | no HUB entry found | partial | Verify the admin entry point. |
| 38 | Course awaiting publish | `AdmApprovals ?screen=courses` | none found | none | missing | Publish-approval queue + backend. |
| 39 | Educational content hub | `AdmContent ?screen=hub` | HUB group `learning` | web tab Learning | exists (needs restyle) | |
| 40 | Categories | `AdmContent ?open=1&screen=cats` | `admin_categories_page.dart` | HUB `categories` | exists (needs restyle) | |
| 41 | Quran teachers | `AdmContent ?screen=quran` | `lib/features/quran/*` admin page | HUB `admin_quran` | exists (needs restyle) | |
| 42 | Educational games | `AdmContent ?screen=games` | `lib/features/games/admin/*` | HUB `admin_games` | exists (needs restyle) | |
| 43 | Store review | `AdmContent ?screen=store` | `lib/features/store/manage/store_manage_pages.dart` (`StoreAdminHubPage`) | HUB `admin_store` | exists (needs restyle) | |
| 44 | Help management | `AdmContent ?screen=help` | `lib/features/admin/help/*` | HUB `help_center` | exists (needs restyle) | |
| 45 | Support and security hub | `AdmSupport ?screen=hub` | HUB group `support` | web tab Support | exists (needs restyle) | |
| 46 | Complaints and support | `AdmSupport ?screen=tickets` | `lib/features/profile/compalints/complaints_hub_page.dart` | HUB support | exists (needs restyle) | |
| 47 | Sessions and devices | `AdmSupport ?screen=sessions` | `admin_devices_page.dart` | HUB `admin_devices` | partial | Active-session list with revoke: verify. |
| 48 | Audit log | `AdmSupport ?screen=audit` | none in admin | none | missing | New page + endpoint if absent. |
| 49 | Data center | `AdmData ?screen=datacenter` | `admin_datacenter_page.dart` | HUB `svc_datacenter` | exists (needs restyle) | |
| 50 | Export Excel / Word / PDF | `AdmData ?screen=export` | `lib/features/exports/exports_center_page.dart`, `showAppExportSheet` | `/exports` | exists (needs restyle) | |
| 51 | Import parents | `AdmData ?screen=import` | `lib/features/data_lab/data_lab_import_sheet.dart`, `admin_datacenter_page.dart` | data center | partial | Parents-specific importer: verify. |
| 52 | Scheduled exports, links, log | `AdmData ?screen=exports` | `lib/features/exports/export_schedules_page.dart`, `export_links_page.dart`, `export_log_page.dart` | `/exports` (arguments: true) | exists (needs restyle) | |

## Super admin

| # | Design screen | URL | Existing file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1-4 | Home; income detail; platform search; failed jobs | `SupHome ?screen=home` + `sheet=income/search/jobs` | `admin_overview_page.dart`, `admin_home_body.dart`, `admin_income_breakdown.dart`, `admin_global_search.dart` | DASH tab 0 | partial | Failed-jobs sheet: no counterpart found. |
| 5-7 | Analytics: growth, money, usage | `SupHome ?screen=analytics&tab` | `admin_overview_page.dart`, `lib/features/analytics/*`, `admin_money_p8.dart` | none dedicated | partial | No dedicated 3-tab analytics page. |
| 8 | Recommendation weights | `SupHome ...sheet=recs` | `admin_recs_page.dart` | HUB `admin_recommendations` | exists (needs restyle) | |
| 9-10 | Revenue and ledger; refund | `SupFinance ?screen=money` | `admin_finance_page.dart`, `admin_finance_provider.dart`, `admin_money_p8.dart` | HUB `admin_payments` | exists (needs restyle) | Refund sheet: verify. |
| 11-16 | Payouts: requests, approve, manual paid, resolve uncertain, per-teacher eligibility, settings | `SupFinance ?screen=payouts` | `admin_payouts_page.dart`, `lib/features/profile/teacher/payout/*` | HUB `payout` | partial | Resolve-uncertain and eligibility tab: verify. |
| 17-20 | Transfers pending, reject, receipt, history | `SupFinance ?screen=payments` | `admin_payment_page.dart`, `teacher_transfers_screen.dart`, `receipt_viewer.dart` | HUB `apm_title`, `enrollment_requests` | exists (needs restyle) | |
| 21-23 | Store requests; item review; reject item | `SupFinance ?screen=store` | `lib/features/store/manage/store_manage_pages.dart` | HUB `admin_store` | exists (needs restyle) | |
| 24-27 | Fees: rates, gateway fee, policy, confirm | `SupPricing ?screen=fees` | `admin_fees_page.dart`, `admin_fee_rates.dart`, `admin_account_fee_widgets.dart` | HUB `admin_fees` | exists (needs restyle) | |
| 28-29 | Payment methods + confirm disable | `SupPricing ?screen=methods` | `admin_payment_page.dart` | HUB `apm_title` | exists (needs restyle) | |
| 30-31 | Subscriptions + confirm force | `SupPricing ?tab=subs` | `admin_subscriptions_page.dart` | HUB `subscriptions` | exists (needs restyle) | |
| 32-37 | Rewards: rules, edit rule, coupons, champions, invites, points and balances | `SupPricing ?screen=rewards` | `lib/features/admin/rewards/*`, `admin_points_page.dart`, `lib/features/rewards`, `lib/features/payments/points` | HUB `admin_rewards`, `admin_points` | exists (needs restyle) | Two pages today; design is one with tabs. |
| 38-41 | Admins; invite; delete by typing name; reset MFA | `SupAdmins ?screen=admins` | `admin_admins_page.dart`, `admin_mfa_page.dart` | HUB `admin_admins` | exists (needs restyle) | |
| 42-43 | Roles and permissions; edit role | `SupAdmins ?screen=roles` | none found | none | missing | New roles/permissions editor + backend. |
| 44-45 | View as user; confirm | `SupAdmins ?screen=viewas` | `admin_view_as_page.dart` | HUB view-as | exists (needs restyle) | |
| 46-47 | Settings: open accounts; confirm save | `SupPlatform ?screen=settings` | `admin_platform_settings_page.dart`, `admin_platform_widgets.dart`, `cfg_common.dart` | HUB `svc_platform_settings` | exists (needs restyle) | |
| 48 | Settings: time and region | `SupPlatform ?tab=region` | `admin_platform_settings_page.dart` | same | exists (needs restyle) | |
| 49 | Settings: devices | `SupPlatform ?tab=dev` | `admin_platform_settings_page.dart`, `admin_devices_page.dart` | same | exists (needs restyle) | |
| 50 | Settings: parent linking | `SupPlatform ?tab=parents` | `admin_parent_link_settings_page.dart` | same | exists (needs restyle) | |
| 51 | Settings: study profile | `SupPlatform ?tab=study` | `admin_study_profile_settings_page.dart` | HUB `svc_study_profile` | exists (needs restyle) | |
| 52-54 | Modules; features; feature details | `SupPlatform ?screen=modules&tab=feats` | `modules/admin_modules_page.dart`, `admin_features_page.dart`, `admin_feature_guide.dart` | HUB `admin_modules`, `features` | exists (needs restyle) | |
| 55-56 | Emergency stop; confirm | `SupPlatform ?tab=kill` | `admin_features_page.dart` (kill-switch list) | HUB `features` | partial | Dedicated emergency tab with confirm: verify. |
| 57 | AI control | `SupPlatform ?tab=ai` | `admin_ai_controls.dart` | HUB (AI) | exists (needs restyle) | |
| 58-60 | Login and notifications; test message; confirm login-method change | `SupPlatform ?screen=auth` | `admin_auth_settings_page.dart` | HUB `auth_settings_title` | exists (needs restyle) | |
| 61-64 | Levels, subjects, areas, currency and tax | `SupPlatform ?screen=levels` | `lib/features/admin/edu/edu_levels_page.dart`, `admin_platform_settings_page.dart` | HUB `admin_edu_levels` | partial | Areas and currency/tax tabs: verify. |
| 65 | Live | `SupSystems ?screen=live` | `live_settings/live_settings_page.dart` | HUB `admin_live_settings` | exists (needs restyle) | |
| 66-69 | Exams: defaults, limits, methods, parents-papers-data | `SupSystems ?screen=exams` | `admin_exam_policy_page.dart`, `admin_feedback_settings.dart`, parent grade visibility (HUB `svc_parent_grades`) | HUB `svc_exam_policy` | exists (needs restyle) | One page with 4 tabs vs several pages today. |
| 70-74 | AI models: list, confirm activate, add by name, history | `SupSystems ?screen=ai` | `lib/features/admin/models/*` | HUB `svc_ai_models` | exists (needs restyle) | |
| 75-79 | Landing: sections, confirm publish, reviews, protection, theme | `SupSite ?screen=landing` | `lib/features/admin/landing/*`, `admin_theme_page.dart` | HUB `admin_landing`, `theme` | partial | "Protection" tab: verify. |
| 80-83 | About; privacy and terms; confirm publish; old versions | `SupSite ?screen=legal` | `admin_legal_page.dart`, `admin_content_page.dart` | HUB `terms_and_conditions` | exists (needs restyle) | Versioning: verify. |
| 84-86 | App versions; update message; confirm force | `SupReleases ?screen=versions/prompt` | `admin_app_versions_page.dart`, `admin_versions_page.dart`, `admin_update_policy.dart` | HUB `svc_app_releases` | exists (needs restyle) | |
| 87-90 | Build new release; password confirm; build detail; rollback | `SupReleases ?screen=build/detail` | `lib/features/admin/app_releases/*` | HUB `svc_app_releases` | exists (needs restyle) | |
| 91-94 | Ads; approve and pay; teacher ad settings; editor | `SupAds ?screen=ads/editor` | `lib/features/ads/ads_pages.dart` | HUB `svc_ads` | exists (needs restyle) | |
| 95-96 | Broadcast to all users; confirm | `SupAds ?screen=broadcast` | `admin_send_message_page.dart` | HUB `send_message` | partial | "All users" audience + confirm step: verify. |
| 97-98 | Data center; export design | `SupData ?screen=datacenter` | `admin_datacenter_page.dart`, Export Studio | HUB `svc_datacenter` | exists (needs restyle) | |
| 99-101 | Export log, scheduled, share links | `SupData ?screen=exports` | `lib/features/exports/*` | `/exports` | exists (needs restyle) | |
| 102-105 | Course trash; restore; purge; permanently deleted | `SupData ?screen=trash` | `lib/features/courses/admin/course_trash/*` | HUB `admin_course_trash` | exists (needs restyle) | |
| 106 | My account | `SupAccount ?screen=account` | `admin_profile_page.dart` | DASH account | exists (needs restyle) | |
| 107 | All services (More) | `SupAccount ?screen=more` | `admin_services_hub.dart` | DASH More | exists (needs restyle) | |

## Existing admin / super admin tools the design does NOT draw (keep and restyle)

All are `AdminService` entries in `HUB`:
1. Organizations: `admin_organizations_page.dart` (`svc_organizations`).
2. Self-learning admin: `lib/features/self_learning/admin/sl_admin_page.dart`.
3. Grammar (Nahw) content admin (`admin_nahw`).
4. Games hub with content bank and import wizard (`admin_games_hub`, `lib/features/games/admin/v4/`) beyond the single games screen.
5. AI assistant console (`svc_app_assistant`, `lib/features/rag/`).
6. Exams hub (`svc_exam_hub`) and bubble-sheet types library (`svc_omr_templates`).
7. What parents see of grades (`svc_parent_grades`).
8. Grading feedback store (`admin_feedback_settings.dart`).
9. Student review and read flags (`admin_flags_settings_page.dart`).
10. Data Lab (`dl_admin_title`, `lib/features/data_lab/*`).
11. Username statistics (`admin_username_stats.dart`).
12. Courses and students manager (`admin_course_students`) as its own page.
13. Points and wallets (`admin_points_page.dart`) if rewards are merged (sup 32-37).
14. Theme editor details (`admin_theme_page.dart`) beyond sup 79.
15. Help flows and help export (`admin/help/admin_help_flows.dart`, `admin_help_export.dart`).
16. Feature guide editor (`admin_feature_guide.dart`).
17. Recents (`admin_recents.dart`).

Undrawn tools: 17.

## New features (no counterpart)

- Landing: parents page, teachers page (landing 3-6); student page replaces the generic one.
- Admin: unified requests and approvals inbox (adm 32); course publish-approval queue (adm 38); audit log (adm 48); parent detail and parents import (adm 28, 51; partial).
- Super: roles and permissions editor (sup 42-43); dedicated analytics page with money and usage (sup 5-7); failed-jobs sheet (sup 4); emergency stop tab (sup 55-56, partial); payout eligibility and uncertain-transfer resolution (sup 14-15, verify); areas and currency/tax settings (sup 63-64, verify); landing protection tab (sup 78, verify).

## Per design file -> main existing files

| Design file | Main existing files |
|---|---|
| `Landing*.dc.html` (6) | `landing/src/components/Landing.astro`, `landing/src/i18n/*.ts`, `landing/src/pages/{ar,en}/index.astro`, `landing/src/theme/*` |
| `AdmHome` | `admin_dashboard_screen.dart`, `admin_overview_page.dart`, `admin_home_body.dart`, `admin_global_search.dart`, `admin_services_hub.dart`, `admin_profile_page.dart`, `admin_mfa_page.dart` |
| `AdmStudents` / `AdmTeachers` | `admin_users_page.dart`, `admin_student_manage.dart`, `admin_entity_manage.dart`, `admin_filters.dart`, `admin_bulk.dart`, `admin_subscriptions_page.dart`, `lib/features/teachers/teacher_review_admin.dart`, `admin_required_documents_page.dart` |
| `AdmCourses` | `admin_courses_page.dart`, `lib/features/courses/admin/course_students/*` |
| `AdmPeople` | `admin_parent_linking_page.dart`, `admin_parent_requests_page.dart`, `admin_send_message_page.dart`, `AdminRequirementsPage` |
| `AdmApprovals` | `admin_account_approval.dart`, `payments/enrollment_request/teacher_transfers_screen.dart`, `admin_devices_page.dart`, `certificates/certificate_requests_screen.dart` |
| `AdmContent` | `admin_categories_page.dart`, `features/quran`, `features/games/admin`, `features/store/manage`, `admin/help/*` |
| `AdmSupport` | `profile/compalints/complaints_hub_page.dart`, `admin_devices_page.dart` |
| `AdmData` / `SupData` | `admin_datacenter_page.dart`, `features/exports/*`, `features/data_lab/*`, `courses/admin/course_trash/*` |
| `SupHome` | `admin_overview_page.dart`, `admin_income_breakdown.dart`, `admin_recs_page.dart`, `features/analytics/*` |
| `SupFinance` | `admin_finance_page.dart`, `admin_payouts_page.dart`, `admin_payment_page.dart`, `receipt_viewer.dart`, `features/store/manage` |
| `SupPricing` | `admin_fees_page.dart`, `admin_fee_rates.dart`, `admin_payment_page.dart`, `admin_subscriptions_page.dart`, `admin/rewards/*`, `admin_points_page.dart` |
| `SupAdmins` | `admin_admins_page.dart`, `admin_mfa_page.dart`, `admin_view_as_page.dart` |
| `SupPlatform` | `admin_platform_settings_page.dart`, `admin_auth_settings_page.dart`, `admin/modules/*`, `admin_features_page.dart`, `admin_ai_controls.dart`, `admin/edu/*`, `admin_study_profile_settings_page.dart`, `admin_parent_link_settings_page.dart` |
| `SupSystems` | `admin/live_settings/*`, `admin_exam_policy_page.dart`, `admin_feedback_settings.dart`, `admin/models/*` |
| `SupSite` | `admin/landing/*`, `admin_theme_page.dart`, `admin_legal_page.dart`, `admin_content_page.dart` |
| `SupReleases` | `admin/app_releases/*`, `admin_app_versions_page.dart`, `admin_update_policy.dart` |
| `SupAds` | `features/ads/ads_pages.dart`, `admin_send_message_page.dart` |
| `SupAccount` | `admin_profile_page.dart`, `admin_services_hub.dart` |
