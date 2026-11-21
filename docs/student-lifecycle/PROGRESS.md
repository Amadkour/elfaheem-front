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
| P1 | Students section, unified file, timeline, open logging (0110) | built, check pending | back dcdc48e d35b10c ffc4e57 939f12e; front 00ce6ea6 0cffa20f 7424186d e8be8663 ff591874. Deep link org_student deferred to P2 (staff notices use module org_student focus status). Real-app check + Fable review combined for P1–P3 after the current wave (owner asked for speed) |
| (old P1 note) | | | wave: B (back), F1 (list + api), F2 (file page). Lead after: main.py check, navigator/dashboard wiring, help + guide, FLUTTER_API_CHANGES, contract snapshots, real-app check, Fable review |
| P2 | Statuses, decisions, undo, decision matrix | in progress | owner asked for more parallel agents (2026-11-21): B + F1 started while P1 F2 finishes; P2 F2 (file page header actions, undo row, settings/matrix pages) waits for P1 F2 |
| P3 | Add Student completed (types, entry policy, inline import fix, missing-data sheet, student number; 0112) | in progress | B (back, 0112 → 0110) started in parallel; F1/F2 after |
| P4 | Ask the student, meetings, complaint flow (0111) | todo | |
| P5 | Rules and automatic movement | todo | |
| P6 | Lifecycle requests through Governance, transfer credit (0114) | todo | |
| P7 | Exports, reports, cohort rule sets, real-app check | todo | |

Each phase: build (Opus agents, ≤3, disjoint files) → targeted tests + analyzer → real-app check (web profile build + local back + Playwright, 360 px + desktop, Arabic) → Fable review → one fix round → commit with --only.
