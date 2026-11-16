# UX v3: plan (2026-11-15)

Branch `feature/ux-v3` in both repos, from production (back 8021907, front 3b3aa5c5). Decisions from D-1000. Migrations from 0091.

## Phase 0: the secretary bug (fixed: back 54059a9, front adee35eb)

**Cause.** The faculty council form (setup wizard and Settings → Councils) picks the secretary separately from the members and always sends `member_ids` without them. The roster is replaced by that list, the secretary is then "not a member", and the server answers 422 `council_settings_invalid`. The app shows that as "one of the council settings is not valid". The old test passed because it listed the secretary as a member, which the app never does.

**Fix.**
- The server adds the secretary to the roster.
- The app also sends the secretary inside the list, so it works before the deploy.
- The roster route now answers `secretary_not_member` with `field`, `fix` and `fix_action: add_member`.
- Test: `tests/org_v2/e2e_ux_v3_p0.py` (28 checks).

## Audit (confirmed in code)

| # | Gap | Evidence |
|---|---|---|
| E1 | Errors are `HTTPException(detail={code, message, message_en, field?})`, hand-built in each router. `field` and `fix` are rare, and nothing in the app reads `field`. | `org_council_router.py`, `ApiException` keeps `code` and `message` only |
| E2 | The 422 for a bad request body is a raw pydantic list. The app shows a generic text. | `main.py:243` |
| E3 | There is no handler for unexpected errors: a 500 is plain "Internal Server Error", with no reference id. | `main.py` (only the exam engine has `X-Request-Id`) |
| E4 | Errors don't say what kind they are (validation, permission, conflict, network, server). The app shows a toast of one sentence; there is no Retry and no fix action. | `orgErrorText` (77 files) |
| N1 | Notification rows have no typed action or reason; the reason is free text in the title. | `data/models.py:1332`, `notify.py:465` |
| N2 | **Bug:** every governance push carries `module: org_work`, so a delegation or form push opens a work item with the wrong id. Form taps look up the wrong table. | `notify.py:158`, `notifications.py:296` |
| N3 | Delegations and forms open lists. A grouped notice opens only one item. A deleted item shows "Could not load". | `gov_wiring.dart:148,152`, `gov_item_screen.dart:942` |
| N4 | The item screen has no banner saying why you were sent there. Tapping a push never marks the notification read. | `gov_item_screen.dart`, push data has no notification id |
| N5 | Governance badges are one row per organization that opens a tab, so a count of 1 never opens the item. "Needs my attention" exists (`/me/attention-flow`) but covers governance only, and no badge leads to it. `/me/attention` recounts every row on every call (polled every 60 s). | `attention_service.py:56,111`, `org_attention_flow.dart` |
| A1 | "Personal" is always in the context switcher: any org member can teach personal courses, and there is no setting for it. Leaving an organization keeps the `org-staff` role. | `context_switcher.dart`, `org_public_router.py:151` |

## Phases (each: server + app + targeted tests + a short report)

1. **Errors (D-1000 – D-1004).**
   - **Server:**
     - One helper, `api_error(status, code, ar, en, field=, fields=, fix=, fix_action=, kind=)`.
     - A handler for bad request bodies that keeps the old `detail` list and adds `error: {code: "validation", kind, fields: [{field, message, message_en}]}`.
     - A handler for unexpected errors that logs the request id and answers `{code: "server_error", ref}`.
     - A request-id middleware.
   - **App:**
     - `ApiException` gains `kind`, `field(s)`, `fix`, `fixAction` and `ref`.
     - One `AppErrorBox` (an icon per kind, Retry for network, a copyable reference for server errors).
     - A `FieldErrors` binder that marks the field, scrolls to it and writes the message under it.
   - **Audit:** every institution form (heads, councils, secretaries, members, departments, requests, complaints, votes).
   - **Tests:** the error contract.
2. **Deep links (D-1005 – D-1010).**
   - **Notifications:** every notification carries `action` (`edit`, `confirm`, `vote`, `reply`, `review`, `fill`, `view`) and a short reason. That needs migration 0091: an `action` and `meta` on each row.
   - **Push:** the push carries the notification id and the right module (this fixes N2).
   - **Item screen:** it opens with a top banner saying what to do and why, plus the main action. "Needs edit" shows the reviewer's note and highlights the fields.
   - **Stale links:** a deleted or already-handled item says "This item was already handled", with a link to the right list.
   - **Badges:** each badge opens a filtered "Needs my action" page, sorted by deadline. When the count is 1, it opens that item.
   - **Read:** opening an item marks its notification read.
   - **Tests:** every notification type resolves to a working link and the right banner.
3. **One account (D-1011 – D-1014).**
   - **Setting:** the user gets `personal_enabled` (migration 0092).
   - **Default for existing users:** on for anyone with personal courses, enrollments or a teacher role, so nobody loses anything. Off for new org members.
   - **When it's off:** org members land on their organization and never see "Personal" or teaching outside the organization. A Settings switch turns it on.
   - **Leaving an organization:** the user returns to personal mode with it switched on, and the org-staff role is dropped when they have no seat left.
   - **Invitations:** an existing account joins the organization; no new account is created.
4. **Homes by role (D-1015 – D-1020).**
   - **Built on what exists:** the home kit, My journey, Needs my attention and Institution health.
   - **Roles:**
     - **Student:** next steps.
     - **Teacher:** votes and assigned requests.
     - **Staff:** the department queue with quick replies.
     - **Head:** attention, team, council.
     - **Dean:** overview, decisions, escalations, health.
     - **Admin:** setup and health.
   - **More than one role:** a role switcher with a sensible default.
   - **Layout:** one primary action per screen.
5. **Speed (D-1021 – D-1024).**
   - **Badges:** a cached per-user attention counter, dropped when anything changes for that user.
   - **Slow queries:** measure the homes, the notification list, council results and queues; fix N+1 queries and add indexes.
   - **Long lists:** paginated.
   - **Numbers:** before and after.
6. **Polish:** a11y, RTL, empty and loading states, and `CHECKLIST.md`.

**Optional, not built unless asked:** a guided tour per role on first login; an admin "why did this fail" log page (the server log with the reference id is built in phase 1); undo for risky actions (archive already exists).

**Faster development loop (applied):**
- Only the e2e scripts around the change run on SQLite.
- `flutter analyze` runs on the changed paths only.
- `flutter test` runs per file.
- The full suites run once at the end, because phases 1 and 2 touch shared core code (errors, notifications).
