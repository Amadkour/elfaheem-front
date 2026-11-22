// lib/features/learn_kit/learn_kit.dart — the shared question / result / progress widgets of the Learning Hub
// (D-1346). The educational games (`lib/features/games/`) and the nahw exercises (`lib/features/nahw/`) both draw
// their questions with these, so a choice, a right / wrong mark, a progress strip and a result look the same in
// every module. Every widget takes plain values (no provider, no API call) and is checked by
// `test/ui/learn_kit_layout_test.dart` (320 × 640 and 1400 × 900, ar / en, text × 1.3).
//
// Public API (one import: `package:flutter_education_app/features/learn_kit/learn_kit.dart`):
//
//   grading (learn_grading.dart)
//     LearnMark                 idle · selected · correct · wrong · missed: how one option / item is drawn
//     learnStars(score, max)    0–3 stars, the server's rule (≥ 90 % 3 · ≥ 60 % 2 · ≥ 30 % 1); the server's own
//                               answer wins when there is one
//     learnPercent(score, max)  0..100, rounded
//     learnShuffle(list, {random, avoidIdentity})  a shuffled copy (never the original order when it can help it)
//     learnText(ar, en)         the text in the app's language, the other one when that one is empty
//
//   questions (learn_question.dart)
//     LearnPrompt(text:, caption:, icon:)                  the question card (the prompt in the section role)
//     LearnOptionTile(label:, mark:, onTap:, index:)       one answer row: letter well, text, a ✓ / ✗ glyph by mark
//     LearnOptionList(options:, marks:, onSelect:)         a column of LearnOptionTiles (marks[i] per option)
//     LearnChoiceChips(options:, marks:, onSelect:)        small wrapping choices (classify a word, place a step)
//     LearnFeedback(correct:, title:, explanation:, actionLabel:, onAction:)
//                                                          the right / wrong panel with ONE action (Next, Finish)
//
//   progress (learn_progress.dart)
//     LearnProgressHeader(current:, total:, label:, score:)  "Question 3 of 8" + a filled bar (+ the score so far)
//     LearnStars(stars:, size:)                              three stars, the earned ones gold; read as "2 of 3 stars"
//
//   result (learn_result.dart)
//     LearnResultView(score:, max:, stars:, title:, badges:, pointsAwarded:, onReplay:, onDone:, saving:,
//                     saveError:, onRetrySave:, note:)     the end screen: stars, the score, what was earned, and
//                                                          a save state (saving / failed with a retry) for a result
//                                                          the server has not answered yet
//     LearnEarned(icon:, label:)                           one thing earned (a badge) for LearnResultView
//     LearnBadgeChip(icon:, label:, earned:, caption:)     a badge, earned (gold well) or still locked (muted)
library;

export 'learn_grading.dart';
export 'learn_progress.dart';
export 'learn_question.dart';
export 'learn_result.dart';
