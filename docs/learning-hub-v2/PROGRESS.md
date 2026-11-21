# Learning Hub v2: progress

The plan is in `PLAN.md` and the API in `CONTRACT.md`. The integration branch is
`feature/learning-hub-v2` in both repos (worktrees `_wt/lh2-front`, `_wt/lh2-back`), cut from
production (front 173b6f02, back 44edd0b5).

Owner decisions (2026-11-21):
- Packages are a new table that reuses the checkout and the meeting series.
- Quran programs stay courses.
- Built in NextBrain, then synced to Alfaheem.

| Stream | Worktree / branch | Scope | Decisions | Status |
|---|---|---|---|---|
| S1 live | `_wt/lh2-live-front` feature/lh2-live | A1 annotate, A2 camera, A3 recording (front) | D-1500.. | running |
| back-core | `_wt/lh2-core-back` feature/lh2-core | teachers 0116, packages 0117 | D-1510.. | running |
| back-learn | `_wt/lh2-learn-back` feature/lh2-learn | games 0118, self-learning 0119 | D-1530.. | running |
| back-cal | `_wt/lh2-cal-back` feature/lh2-cal | series 0120, recording 0115, `_parse_hhmm` | D-1550.. | running |
| S5 recur | `_wt/lh2-recur-front` feature/lh2-recur | recurrence picker, meeting form, course entry | D-1570.. | running |
| S6 games | `_wt/lh2-games-front` feature/lh2-games | GameShell, 3 engines, editor, leaderboard | D-1580.. | running |
| S3 learn | `_wt/lh2-learn-front` feature/lh2-learn | self-learning UI, Nahw lift, admin content | D-1600.. | running |
| S4 teach | `_wt/lh2-teach-front` feature/lh2-teach | onboarding, review queue, packages, discovery | D-1620.. | running |

## Integration (S7), still to do
1. Back merge order: cal, core, learn.
   - Wire `create_series_for_package` (core stub → cal `calendar_series_api.py`).
   - Check the migration chain 0114→0115→…→0120.
   - Resolve the appended blocks in `feature_catalog.py`, `module_settings.py`, `scheduler_service.py` and `main.py`.
2. Regenerate the contract snapshots (`export_api_paths.py --front`) and drop the temporary `knownMissing` entries.
3. Front merge order: live, recur, teach (wire `RecurrencePicker` into the package wizard's schedule slot), learn, games.
   - Resolve `translation.json` and `DECISIONS.md`.
4. Gates:
   - analyzer;
   - the touched front suites + contract;
   - backend tests on PostgreSQL (nb-pg);
   - alembic on a copy of the production dump;
   - a walk in the real web app (ar/en, phone width).
5. One final review, then `FINAL_REPORT.md`. No push or deploy until the owner says so; then the Alfaheem sync.
