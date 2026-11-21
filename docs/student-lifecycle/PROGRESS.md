# Student lifecycle job: progress

Branch `feature/student-lifecycle` in `D:/platform/nextbrain/_wt/sl-back` and
`D:/platform/nextbrain/_wt/sl-front` (from origin/production: back e2c804f,
front 72c211c4). Never touch `_wt/lh-*` or `feature/learning-hub`.
Migrations from 0110 (first down_revision "0101"); decisions D-1400+.

On resume: read this file and continue from the first step that is not `done`.

| # | Step | Status | Notes |
|---|------|--------|-------|
| 0 | Worktrees created | done | 2026-11-21 (first created under back/_wt by a path slip, moved with `git worktree move`) |
| A | Inspect the current system → INVENTORY.md + status table | done | INVENTORY.md; status table goes in PLAN.md |
| B | Research → RESEARCH.md | done | 24 sources; unverified items listed in it |
| C | PLAN.md + grouped questions, STOP for approval | done | PLAN.md (Fable). Owner 2026-11-21: approved, the DEFAULT answer for all 16 questions in §7 |
| P0 | Contract: CONTRACT.md + D-1400..D-1412 in DECISIONS.md | done | front 25d3ee03 (docs); back d21994b (catalog: module, 4 roles, 6 kill switches; rbac + roles e2e pass) |
| P1 | Students section, unified file, timeline, open logging (0110) | done | built + real-app check + Fable review + fix rounds (back 9d9fd8a 18d0241, front f1e07fc4 d07ad195) |
| (old P1 note) | | | wave: B (back), F1 (list + api), F2 (file page). Lead after: main.py check, navigator/dashboard wiring, help + guide, FLUTTER_API_CHANGES, contract snapshots, real-app check, Fable review |
| P2 | Statuses, decisions, undo, decision matrix | done | back 0c4296e bdbfdb8; front 2215e9d4 4f61fa96 |
| P3 | Add Student completed (0112) | done | back 8d5db93 e1b0b72; front 377ec521 4da9f368 b8cc3fc2 b730a9e6 |
| P4 | Ask the student, meetings, complaint flow (0111) | done | back 589a8ff; front 1a68a890 ee4917b5 5638331d |
| P5 | Rules and automatic movement | done | back f381e58 7f8aed0; front b3fa7981 |
| P6 | Lifecycle requests via Governance, transfer credit (0114) | done | back e6cd257 717467d 38c2707; front 0aff84bb |
| P7 | Export, status report (cohort rule sets deferred: Q6 default) | done | back 6b5a9c7; front 4882554c. Wiring 043d52a2 bb094b23. Fable review P4-7 back + front → fixes back b4748b6 (CRITICAL forged lifecycle item, promotion once per year, …), front 1ca534fa |

Each phase: build (Opus agents, ≤3, disjoint files) → targeted tests + analyzer → real-app check (web profile build + local back + Playwright, 360 px + desktop, Arabic) → Fable review → one fix round → commit with --only.

## Integration to-do (lead, after P5 F1 + P6 front land)
- HomeAsksCard(items: homeAsksOf(home.raw), onOpen: …) on the student home (and teacher home if it shows asks).
- Complaint thread "Request a meeting" → showStudentAskSheet(kind meeting, source complaint) (ee4917b5 is in).
- LiveEvents.studentLifecycle = 'student_lifecycle' in lib/utils/live_events.dart; replace the local constants.
- AppNavigator: module `student_ask` → openMyAsk(nav, id); `org_student` focus `asks` → file / requests inbox.
- Wire: OrgStudentRequestsPage (Students page / dashboard), student_request_detail, transfer credits sheet (file page), MyRequestsPage (student home / org member dashboard), openStudentRules + settings chooser.
- Back: ask payload lacks document labels (asks.py).
- Regenerate: help_index.json, test/fixtures/help_page_ids.json (org.students.status, org.students.rules, org.students.requests, me.status, me.asks, me.requests), contract snapshots; run contract + help tests.
- Then: real-app check + Fable review for P4–P6, P7.

## Final (2026-11-21)
- Final real-app check of all phases: running (sl-check-* at front 1ca534fa / back 666519e).
- e2e_query_budgets fails on origin/production too; our deltas were added to its budgets (b4748b6).
- Known pre-existing failure: test/ui/rtl_icons_test.dart (onboarding_applicant.dart:282, from production).
- Not pushed, not deployed (owner rule).
