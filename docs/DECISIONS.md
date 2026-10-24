# Decisions — platform refactor

Format: **D-nnn — title** · date · status. Context, decision, consequences. Where the brief conflicts with the real code, the deviation and reason are recorded here (the brief asks for this).

## D-001 — Keep `provider` + `BaseProvider`, no state-management migration · 2026-10-24 · accepted
The brief says "follow what the repo uses unless clearly flawed". The app has ~215k lines on `provider`/`ChangeNotifier` with `BaseProvider.run()` handling loading/error/retry uniformly. It is not flawed; a migration would be pure churn. New features use the same pattern.

## D-002 — Static-analysis gate for Dart is "0 errors, 0 warnings"; `info` lints are reduced opportunistically · 2026-10-24 · accepted
Baseline: 292 `info`-level lints, 0 warnings, 0 errors. The brief's definition of done is zero errors and zero warnings. `info` items in files we touch are fixed; a repo-wide sweep of `avoid_print` / `use_build_context_synchronously` in untouched files would bury the real diff (CLAUDE.md's rule against mass re-formatting applies).

## D-003 — Do not run `dart format` · 2026-10-24 · accepted
The brief lists `dart format` in the baseline. CLAUDE.md forbids it because the code base is unformatted and a run would rewrite every file. Recorded as a known deviation; new files are written formatted by hand.
