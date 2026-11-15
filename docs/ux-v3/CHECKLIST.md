# UX v3: requirement checklist (2026-11-15)

Branch `feature/ux-v3` in both repos. Decisions D-1000, D-1011, D-1021. Migrations 0091 (notification action + link), 0092 (`users.personal_enabled`), 0093 (two indexes). Server tests: `tests/org_v2/e2e_ux_v3_p0 … p5.py`. App tests: `test/org/ux_v3_p1 … p6_test.dart`.

| Spec | Requirement | Server | App |
|---|---|---|---|
| 3.2 | Faculty council secretary bug: root cause, fix, regression test | `councils_setup.apply` adds the secretary to the roster; `secretary_not_member` + fix (e2e p0) | the secretary is sent in `member_ids` (`gov_councils_setup.dart`) |
| 5 | Structured errors: code, message, field(s), safe value, fix | `helpers/error_handling/api_errors.py` (`api_error`, `install_error_handlers`); about 230 institution errors bilingual, with field and fix where known | `ApiException.kind/field/fields/fix/fixAction/ref` |
| 5 | Validation, permission, conflict, network and server errors told apart | `kind` on every coded error; a bad body adds `error.fields`; a 500 gives `server_error` + `ref` = `X-Request-Id` | `AppErrorBox` / `showAppError`: an icon and wording per kind, Retry (network), a copyable reference (server) |
| 5 | Field highlighted, scrolled to, message beside it; summary for several | `field` / `fields` | `FieldErrors` in the council roster, councils setup, department / program / entity head pickers, the setup wizard |
| 5 | One-tap fix | `fix_action`: add_member, pick_head, pick_reassign, open_members, open_agenda, setup_councils, enable_personal | `AppFixActions` / `AppFixScope`, `org_fix_actions.dart` ("Add as member and continue", …) |
| 5 | Errors logged server-side, no stack or secrets in answers | the 500 handler logs the traceback with the ref | — |
| 6 | Every notification carries a typed deep link with the action needed | `notifications.action` + `link` (0091), set for every org notice (`notify.py`); push carries `notification_id` | `NotifLink` (`lib/core/notif_link.dart`) |
| 6 | Opens the item, scrolled to the right part, with a banner and the main action; the note and fields to change | `link.focus`, `note`, `fields` | `ActionBanner` on `GovItemScreen` / `GovSessionScreen`, delegation and form pages |
| 6 | Badge opens a filtered "Needs my action" view; a count of 1 opens the item | `GET /me/action-inbox`; `/me/attention` `target` | `NeedsMyActionPage` (search, urgent / overdue, lazy, load more); `AttentionBadge` |
| 6 | Marked read on open; stale links handled | `/notifications/{id}/target` marks read, `stale` + `fallback` | `StaleLinkView`; push tap marks read (optimistic) |
| 6 | Push, in-app and cold start; wrong-module bug fixed | delegation / form pushes carry their own module | `AppNavigator.openLink`, the cold-start queue |
| 7 | Homes by role, one primary action, the rest under More | `dashboard.head_unit_ids` | `orgHomePersona` (admin, dean, head, staff, teacher, student), sections per persona, quick replies |
| 7 | Role switcher with a sensible default | — | "View as" chips, the highest role by default, remembered per user and organization |
| 8 | One account, one email; an existing account joins by invitation | no duplicate on invite; removed staff can be invited again | — |
| 8 | Lands directly in the institution | — | `PersonalAccess.homeFor` |
| 8 | Optional "Personal account" switch; hidden without it; contexts separate | `personal_enabled` (0092, careful backfill), `GET\|PUT /me/personal`, 403 `personal_off` | `PersonalAccountTile`, switcher and course / profile entries hidden, the `enable_personal` fix |
| 8 | Leaving keeps the personal account, ends institution access | leave / remove / suspend / expiry: role back, personal on | re-read `/auth/me`, route to the new home |
| 9 | Slow queries fixed, measured | readiness 57/77 → 26/26, health 63/83 → 32/32 queries; budgets in `e2e_ux_v3_p5` | — |
| 9 | Cheap cached badge counter | `attention_cache.py` (30 s, per-user version, reset on any change for that user) | the poll stops in the background; badges rebuild at the leaf |
| 9 | Indexes, pagination, lazy lists, optimistic updates, split bundles | 0093 indexes; `/notifications` limit clamped | lazy lists, one shared request in flight, optimistic mark-read / quick reply / vote, deferred pages |
| 9 | Idempotent, efficient jobs | reviewed; health is flat per organization | — |
| 10 | Searchable "Needs my action" inbox; health check for stale items | action inbox; institution health (v2) | `NeedsMyActionPage` |
| 11 | Arabic + English, RTL, accessibility | bilingual texts | layout harness, a11y, RTL tests; banners and error boxes announce once |

## Not done

- **PostgreSQL:** migrations 0091 – 0093 have only been checked on SQLite.
- **Real web app:** no check against real data yet.
- **"Needs your edit":** the server has no "returned for edit" status, so only the caller's own refused requests in the inbox use it.
- **Inbox length:** the action inbox shows at most 200 items (no offset yet).
- **Student home:** unchanged (it already has My journey).
- **Optional, not built:**
  - a guided tour per role on first login;
  - an admin "why did this fail" log page (the server log with the reference id exists);
  - undo for risky actions.
