# Games v4: the owner's request (2026-11-23, verbatim in substance)

Build an Islamic & general educational games module for the existing Flutter app and its Admin Dashboard. Read the
project first, produce a detailed plan, wait for approval before coding.

## Execution rules
- Plan with Fable, execute with smaller models (Sonnet, Haiku for simple tasks).
- Parallel agents for independent tasks, narrow self-contained briefs.
- Save tokens: no re-reading unchanged files, no large dumps, short replies.
- Test only what changed; one full check at the very end.
- Install skills / tools / packages freely (Flame, Rive, Lottie, flutter_animate).
- Proceed automatically on project-scoped work; ask only before destructive actions outside the project
  (deleting data, force-push, production databases).
- Speed first: shared template interface first, then games on top of it in parallel. Small commits per feature.

## Goal
Highly attractive, animated, interactive games for learners aged 6–30, fully data-driven. Each game is a reusable
template (mechanics only); all content comes from the backend, managed by the Super Admin.

## Subjects
Quran (memorization, verse ordering, completion), Tafsir & Balagha, Fiqh, Hadith, Arabic Grammar (Nahw), I'rab, Math,
Science, General knowledge, Culture & fun. Admin can add subjects anytime.

## Required templates (all)
1. Car Race: lanes show answers, the right lane boosts speed. Quran: the verse plays, the car reaches a fork, each road
   holds a word, pick the correct next word.
2. Word Fishing: fish carry letters / words; catch in the right order to build a word, verse or hadith.
3. Map Adventure: stations with questions; right answers open treasure chests.
4. Science Lab: drag-and-mix experiments with colourful reactions; cause / effect questions.
5. Fractions Farm: divide pizza / land, plant and harvest by the required fraction.
6. Body Puzzle / Drag-to-Place: drag items to slots (organs, or grammar roles).
7. Robot Coding: arrange arrow commands to guide a robot on a grid.
8. Challenge Quiz: timed, points, leaderboard, badges.
9. I'rab Hunter: drag each word of a sentence into its basket (fa'il, maf'ul, mubtada, khabar…) and set its case ending.
10. Verse Builder: hear the recitation, arrange the shuffled words of the ayah; plus "Complete the Ayah".
11. Space Rocket: fly through the planet holding the right answer.
12. Platform Jumper: jump on word platforms in the correct order.
13. Balloon Pop: pop only the balloons with right answers.
14. Word Train: collect wagons carrying words in sequence (verses, hadith).
15. Growing Tree: calm mode for older learners; the tree grows and bears fruit with each right answer.
Plus 1–2 brand-new original templates, proposed in the plan.

## Quran respect rules
Music and SFX stop automatically during recitation. Calm, respectful visuals and sounds. No harsh penalties: on a wrong
answer replay the ayah and let the learner retry. Penalty behaviour configurable per game.

## Super Admin dashboard (inside the existing one, simple for non-technical users)
- Enable / disable any game; show / hide per subject or age group.
- Template settings: timer, lives, speed, penalty on/off, theme.
- Levels per game: difficulty, age range, order, unlock rules.
- Content per level: questions, answers, ayat with audio, hadith text, grammar sentences, images. Bulk import CSV / JSON / Excel.
- Preview a game with its data before publishing.
- Analytics: plays, completion, average score, hardest questions.
- Rewards: points, stars, coins, badges, unlockable character outfits.

## Technical
- Flutter + Flame for real-time games; widgets for quiz / drag-drop; Rive or Lottie for characters.
- ONE shared content JSON schema any template can consume from any subject (define it in the plan).
- Reuse the existing backend.
- Full RTL / Arabic with correct tashkeel rendering.
- Clean architecture: each template an isolated module behind a common interface (load data, start, score, finish).
- Offline caching of downloaded levels.
- Age-based UI: cartoon for kids, cleaner mature theme for adults.

## Seeding
- A seed system so games work from day one.
- Hadith: only Sahih from verified sources (Bukhari, Muslim datasets / APIs): text, book, number, grading. Never
  generate or paraphrase hadith with AI.
- Quran: ayat text (Uthmani) and recitation audio from a trusted API / dataset. Never typed or generated.
- Fiqh, Nahw, I'rab, Math: question banks with levels; religious answers "pending review" until a qualified reviewer
  approves them in the dashboard.
- Culture & fun: sports, famous people, science facts, geography, inventions, fun facts; admin toggle.
- Randomization: each session draws a random subset, avoiding items the learner saw recently.
- Every seeded item gets difficulty + age range; split automatically across levels per game.
- Admin can re-run the seed, add, edit, delete any seeded item.

## Parent
Parents do NOT control games. At most a light summary (time played, games finished), Super Admin on/off.

## Extras
- Spaced repetition: wrong questions come back after a few days.
- Class-vs-class / friends challenges with a weekly leaderboard.

## Smart breaks
- Levels tagged with subject / topic. While studying a subject, a "Play now" button opens a random game of that subject.
- Break reminders after an admin-set study period (in-app / push), suggesting a game of the current subject.
- Admin: button and reminders on/off, study duration before a reminder, max break length.

## Daily winner and rewards (admin-controlled)
- Daily winner from game points; one overall or one per age group (recommended per age group).
- Celebratory trophy animation on next app open; public winners board.
- Reward: discount on ONE course of the winner's choice; admin sets %, validity (e.g. 24 h), any / selected courses.
- Unlock by sharing: active only after the winner's referral link brings N new students (admin sets N).
- A referral counts only when the new account is verified and active; block duplicate devices / accounts and self-referrals.
- Winner sees progress (2 of 5 friends joined) and an expiry countdown.
- Dashboard: history of winners, referrals, discounts issued and used.

## When unsure
Research competitors (Duolingo, Kahoot, Prodigy, Quizlet, Islamic learning apps), adopt the proven pattern, note it in one line.

## UI/UX bar
Premium, Duolingo-level polish; rich smooth animations everywhere (transitions, micro-interactions, feedback, rewards,
trophies); consistent illustrated style with depth, lighting, shadows, gradients (elegant for older, vivid cartoon for
kids); drag, swipe, tilt, haptics, SFX (muted during recitation); 60 fps on mid-range devices; one shared design system
(colours, excellent Arabic typography, components) across games and dashboard.

## Plan deliverables
1. Architecture and folders. 2. DB schema + shared content JSON schema. 3. Templates with mechanics, inputs, scoring.
4. The 1–2 new games. 5. Admin screens and flows. 6. Ordered small task list for cheap models.
