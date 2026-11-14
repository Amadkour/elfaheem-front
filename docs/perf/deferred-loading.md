# Deferred loading of the web build

`main.dart.js` (release) was 18.2 MB with no deferred parts; the browser needs about 6 s to parse and start it.
dump-info of that build: app code 10.1 MB, of which `features/org` 2.0 MB (+ governance 451 KB, org_reports 107 KB,
insights 39 KB), `exam_engine` 1.16 MB, `features/admin` 820 KB (+ app_releases 139, models 96), `teacher/sessions`
607 KB (the live room), `shared/rag` 331, `design/export_hub` 308, `features/data_lab` 291, `export_layout` 196,
`features/certificates` 183, `certificates_issue` 143; packages: `timezone` 836 KB, `flutter_localizations` 492,
`image` 337, `livekit_client` 288, `archive` 116, `pdf` 106.

## How the graph was read

A script (import / export / part directives of `lib/`, every branch of a conditional import) gave the eager closure
of `main.dart` and, for a set of candidate roots, which eager files still import a root. dart2js splits by element
(class / function / constant), not by library, so an eager `import 'x.dart' show Enum, helper;` costs only those
elements; what pulls a screen into the main unit is an eager file that **builds** it (a constructor call or a
function that reaches it). The script over-counts library-level edges, so the list of cuts was driven by the
call sites that construct a heavy screen, then measured with `--dump-info`.

Eager edges found (apart from the intended entry point):

| module | eager call sites that built it |
| --- | --- |
| admin / teacher / parent / org / org-member homes | `main.dart` `_router` only (the other imports are `show` of small helpers) |
| teacher sessions screen (course studio) | course_profile_hub / _parts, courses_screen, teacher home, queue_work_items |
| `TeacherExamHubScreen` (123 KB + authoring) | course_profile_actions, session_material_widget, analytics_hub, sessions_screen |
| `DataLabScreen` | org_departments_page, analytics_hub, data_lab_entry_cards, sessions_screen |
| `CourseFormScreen` (93 KB) | courses_screen, teacher home, sessions_screen |
| certificate designer / requests | profile_screen, course_form, 3 org pages, certificate_manager_sheet |
| org reports page (70 KB) | org_member_dashboard, app_navigator |
| Export Studio flow (`export_flow`, 54 KB + hub + layout + writers) | `showAppExportSheet` in `app_table_export.dart` |
| app releases, governance links, RAG admin links, exam identifiers | `app_navigator.dart` deep-link switch |
| `timezone` data | `app_time.dart`, `notification_service.dart` (`data/latest.dart`) |

## Cuts

Deferred (`lib/core/routing/deferred_screens.dart`, one `DeferredPage` per library, retry on failure, nothing drawn
for 150 ms on an inner page, the boot splash for a role home): the five role homes, teacher sessions screen,
course form, exam hub, data lab, certificate designs / requests, org received reports, app releases (+ detail).
`app_navigator.dart` loads governance / RAG-admin / exam-identifier deep links on demand; `showAppExportSheet`
loads `export_flow`. Not cut (too many eager builders, risk): the live room / pre-join (16 sites), `org_my_exams`
(8), exam taking, `DataLabGate` (student shell).

Timezone: on the web `data/latest.dart` is no longer imported; the identical `latest.tzf` is an asset
(`assets/tz/latest.tzf`) read through `AppTime.loadDatabase()` (kicked off by `AppTime.useLatinDigits()` at
start-up). Zones set before the data lands are accepted unchecked and validated when it arrives, and every
`AppTime.version` listener is redrawn. Phone, desktop and tests still compile the data in (unchanged).
`test/perf/tz_asset_test.dart` fails when the asset differs from the package's file.

Also deferred in the second round: the pre-join page (`PreJoinPage`, LiveKit + the room + the whiteboard; `JoinArgs`
moved to `live/join_args.dart` so the six eager callers can build it without the room), the organization member
home block (`OrgMemberHome`, inline skeleton identical to its own loading state), the member space / form fill /
availability / academic path / my exams pages opened from the inbox, and `openOrgApproval`.

## Measured (release, `--dump-info`, dart2js minified)

| | before | after |
| --- | --- | --- |
| `main.dart.js` | 18.2 MB | 9.03 MB |
| deferred parts | none | 175 files, 10.8 MB (largest: 1.30, 1.11, 0.89, 0.88, 0.79, 0.79, 0.60, 0.46 MB) |
| timezone data in the script | 836 KB | 0 (asset, 254 KB, read on start-up) |

Main-unit size by folder (dump-info units, KB): features/org 2370 -> 478, exam_engine 1829 -> 198,
teacher/sessions 965 -> 73, org/governance 412 -> gone, org_reports, export_hub 281 -> deferred, admin 172.

Still eager on purpose: the student shell, auth, the course page, the assistant (`shared/rag` 370 KB, a floating
host on every page), `flutter_localizations` (900 KB, needed for the app locale), profile screens (433 KB), calendar
(273 KB), exam TAKING.

Real run (profile build, local stack, Chrome, service worker off): a signed-in student downloads only
`main.dart.js`; a teacher home adds 14 parts (0.37 MB profile-size); an org admin home 13 parts (0.04 MB); the
super admin home 45 parts (3.4 MB). All five homes and the teacher's course studio (a deferred page) opened.
