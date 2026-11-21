# Learning Hub v2: QA fixes, part B (games, self-learning, Nahw, admin hub)

The findings of `QA_WALK.md` in the games, the game shell, the leaderboard, self-learning, Nahw and the admin
services hub. Teachers, packages, the recurrence picker, the calendar and the course sessions are part A (another
agent). Decisions: front D-1670..D-1676, back D-1710..D-1712.

Checked in a real web build (profile, `--base-href /`) against a local stack (compose project `lh2fixb`, gateway
`:46080`, the demo seed and `load_learn_seed.py`), driven with playwright-core. Before / after screenshots:
`screenshots/lh2/fix/` (`before-*` are the walk's own shots).

## must

| # | Status | What changed |
|---|---|---|
| M1 | fixed | Word puzzle (D-1670): square slots (`AppTouch.min`) and square tiles (`AppTouch.primary`) in wrapping rows, five tiles to a row at 320 px. The word built so far is one `Text` above them, so Arabic letters join ("فاعل"); once checked only the joined word stays, green or red. Slots and tiles still take taps. Rows and word follow the word's own direction (RTL in the English interface too). The admin's live preview is the same engine. Shots: `after-word-*`. |

## should

| # | Status | What changed |
|---|---|---|
| S7 | fixed (my files) | `countText` for the word puzzle hint (N17), the streak (N4), the Nahw admin's exercise count and the game card's points badge ("+1 point"). The two plurals the walk names (teachers list, review queue) are in `lib/features/teachers/`: part A. |
| S12 | fixed | "In the student's organization's time zone, else the platform's." |
| S13 | fixed (my files) | `AutoDirText` in the learn kit prompt, caption and options, the game card and admin list titles and the self-learning admin rows (D-1671). The teacher files are part A. |
| S15 | fixed (my files) | Game editor: `AppWidth.wide`, the fields at the form width and the live preview beside them in its own scroll from 960 px (D-1674). The review detail and My packages chips are part A. |
| S16 | fixed | The self-learning item form pins its "what is missing", the server error and Cancel / Save under the scrolling fields. |
| S20 | fixed | Back D-1711: `GET /me/self-learning` leaves out today's lessons already marked "Got it". |
| S21 | fixed | The subject line says "1 of 2 learned · 1 to review" (the bar is learned of the subject's lessons, `lessons` from the server); the due part shows only when there is one. |
| S22 | fixed | One name per type everywhere (D-1673 / back D-1710): the type menu takes the app's names, the server catalog and the features guide use the same ones. |
| S25 | fixed | The editor marks the field itself once it holds text (D-1672); the preview no longer invents a blank for a sentence without `___`. The summary above Save stays. |
| S27 | fixed | New "Learning content" group / sidebar tab (D-1675) with education levels, module switches, Quran teachers, teacher review, grammar, games and self-learning. |

## nice

| # | Status | Note |
|---|---|---|
| N4 | fixed | Streak at 0 reads "0 أيام"; the ring's screen-reader label uses the same plural. |
| N7 | skipped | The Filters button is the shared `CourseFilterBar` (its sheet holds the level); folding category and difficulty into it means changing that shared widget for every list that uses it. Not cheap. |
| N8 | fixed | The leaderboard switch shows the closed eye when hidden. |
| N11 | fixed | A new item starts published, and goes last in its subject (back D-1712; the app sends no `sort` for a new item). |
| N12 | skipped | The wrapping title is the shared page header (`AppPageHeader`) on every admin page; not a change to make inside this round. |
| N13 | fixed | Below 420 px a games admin row moves its publish switch into the row menu (Publish / Hide from students). |
| N16 | fixed | The review section has no count subtitle any more (the runner's "Review 1 of 2" is the count). |
| N17 | fixed | See S7. |
| N18 | fixed (word puzzle) | The "See result / Next word" button under a wrong answer is its own semantics node. The onboarding half is part A. |
| N20 | fixed | Lining figures in the game header counter, the result score and the editor's row labels ("0 of 2", "Pair 1"). |

N1–N3, N5, N6, N9, N10, N14, N15, N19, N21 are in the teacher, package or calendar files: part A.

## Found in the fix walk

| # | Status | What changed |
|---|---|---|
| B1 | fixed | The seeded "Fill in the right ending" (العلمُ / العلمَ / العلمِ) showed ONE option, and any ending counted right: options were de-duplicated and compared after the Arabic normalization. Options are now kept and compared as written; a typed answer is still normalized (D-1676). Seen in `after-game-edit-fill-ar-1400.png` (the preview's single option, before this fix). |

## Walk notes

- The web build was made from a clean checkout of the branch (`git worktree`) because part A's work in progress in the shared tree did not compile for the web at the time (`case final when?` in `teachers_parts.dart` / `package_wizard.dart`: `when` is a reserved pattern name for dart2js). Part A should check it.
- Shots: `after-games-tab-ar-390` (one name per type), `after-word-partial-ar-390`, `after-word-solved-ar-390` (إظهار joined), `after-word-wrong-ar-390` (دإمغا joined, red), `after-word-play-en-390` (the Arabic word fills right to left in English; "0 of 5" in lining figures), `after-learning-hub-ar-1400`, `after-game-edit-fill-ar-1400` (two panes), `after-game-fill-noblank-ar-1400` (the field marked, no invented blank), `after-sl-add-ar-1400` (pinned actions, published by default).

## Tests

- front: `test/ui/games_*`, `test/ui/self_learning_test.dart`, `test/ui/nahw_*`, `test/admin/admin_modules_test.dart`, `test/ui/admin_ds/shell_hub_test.dart` (now lays out the new group), `test/contract/`; new: the built word joins and keeps its spaces, slots and tiles are squares, the solved word is one Text, a sentence without a blank stays as written.
- back: `tests/learning_hub/e2e_self_learning.py` (a seen lesson leaves today's list; a new item without `sort` goes last).
