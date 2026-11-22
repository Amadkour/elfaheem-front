# Games v3: analysis (2026-11-22)

The owner asked for:
- more graphics in games: items that move, colours that change, connector lines in the matching game;
- daily and weekly champions;
- discounts for champions and for people whose shares or referrals pass a number;
- sounds (decided yes on 2026-11-22).

This file covers what other apps do and what we take from them; `PLAN.md` is the build plan. **[web]** marks facts checked by search on 2026-11-22. **[known]** marks general product knowledge that was not re-verified.

## Where we stand (production be975f36 / 56098f66)

| Area | Exists | Gap |
|---|---|---|
| Engines `lib/features/games/engines/` | quiz, match, order, memory, fill_blank, word_puzzle; tap only; state through `LearnMark` colours | no drag, connectors, shake/pulse or memory flip |
| Shell `shell/game_shell.dart` | header, steps bar, `AppBump` score, a 16-particle burst, stars, haptic cue, mute toggle | no combo, no rank on the finish view, no sound |
| Motion kit `lib/design/` | `AppMotion.of` fast 180 / base 220 / slow 300 (0 under Reduce motion), `AppEase.out`, `AppBump`, `AppPopIn`, `AppReveal`, `AppFill`, `syncMotionLoop` | nothing game-specific |
| Scoring `back/features/games/games_service.py` | the CLIENT grades; the server only checks `0 <= score <= max` | a board that pays discounts can't trust this |
| Leaderboard | per game, week/all, "First L.", no avatar, opt-out | no winners, no periods |
| Points | wallet + ledger, game points with a daily cap | not a discount |
| Discounts | `Course.discount_percentage`, `Package.discount_percent`; 3 checkouts (`PaymentService._calc_fees`, `package_service.enroll`, `store/orders.create_order`) | **no coupon or promo code anywhere** |
| Sharing | `/c/<id>?ref=<uid>` → `course_share_clicks` | `ref` is never attached to a sign-up |
| Jobs | APScheduler ticks; `live_claims.claim_many` | no games job |

## Per app: what we adopt and what we avoid

**Duolingo** (the reference loop)
- What it does: weekly leagues of about 30 ranked by XP [web], Friends Quest [web], correct = green + bounce and wrong = red + shake [known].
- Adopt: a weekly period with a fixed reset, small boards, a combo after a run of right answers, and rewards that are more product, never cash.
- Avoid: demotion, loss-framed pushes and streak guilt.
- Watch out: XP farming is a known problem [web]. Ours is worth money, so the server grades.

**Kahoot!**
- What it does: points = max × (1 − (t ÷ timer) ÷ 2), and an answer streak adds no points [web].
- Adopt: a bounded speed bonus, colour + icon for every state, a podium for the top 3.
- Avoid: speed scoring on Quran and tajweed, loud countdown music.

**Quizlet Match** [known]
- What it does: a race against the clock; matched pairs fade away.
- Adopt: matched pairs settle visually; time is only a tie-break.
- Avoid: time as the only score.

**Blooket / Gimkit** [web]
- What they do: many modes on one question set; mystery boxes and point stealing.
- Adopt: one content set in many engines (we already have this).
- Avoid: chance-for-reward mechanics. They are gambling-like, wrong for children and wrong for an Islamic-context product.

**Wordwall** [known]
- What it does: one list rendered as many templates, each with its own leaderboard.
- Adopt: per-game options.
- Avoid: dated stock sound effects.

**Prodigy** [known]
- What it does: membership upsell inside the game, which was criticised.
- Avoid: selling inside a round.

**Khan Academy Kids** [known]
- What it does: calm, large targets, no public ranking for small children.
- Adopt: 48 px targets, the parental consent rule (D-1371) and the opt-out.

**Tarteel / Itqan Ayah** [web]
- What they do: streaks, badges, hifz points.
- Adopt: rank Quran by accuracy and consistency, not speed.
- Avoid: drawing any effect over ayat.

**Elevate / Lumosity** [known]
- What they do: a short daily set of games and calm, premium visuals.
- Adopt: a minimum activity of 3 different games for a daily champion.

**Referral practice** [web]
- Common practice:
  - reward only after real activity, with a delay;
  - block self-referral;
  - cap referrals per user;
  - match device and IP;
  - give coupons an expiry.
- Adopt all of it. A `ref` in a link does not survive a store install, so sign-up gets an optional "Invited by @username" (D-071).

## Decisions taken into the plan

- **Feedback:** colour + icon + one short move (180–300 ms, tokens only).
- **Matching:** bezier connector lines, plus a live line that follows the finger.
- **Drag:** added next to tap, never instead of it.
- **Combo:** a ×3 chip; it adds no points.
- **Ranked rounds:** graded by the server from an answer trace.
- **Champions:** daily and weekly, platform time zone.
- **Score:** the best ranked round per game per day, summed over different games; speed adds at most +20 %, and none for Quran and tajweed.
- **Rewards:** a personal single-use coupon paid by the platform.
- **Referrals:** qualified by real activity, capped, reviewed.
- **Tone:** modest, no music, first name + initial, no loss pushes.
- **Never:** loot boxes, wagers or steals.

## Notification cadence

- **Winner:** one push plus in-app (the linked parent too).
- **Coupon:** when it is issued, and 3 days before it expires.
- **Referral:** when a friend qualifies.
- **Never:**
  - "you lost your place";
  - more than one games push per user per day;
  - anything between 21:00 and 08:00 platform time (queued to the morning).

Sources: blog.duolingo.com (leagues, friends quests, friend streak), kotaku.com (Duolingo cheating), support.kahoot.com (points), medium.com/inside-kahoot (streaks), jotform.com (Blooket vs Gimkit), tarteel.ai, fingerprint.com / blog.smile.io / voucherify.io (referral fraud).
