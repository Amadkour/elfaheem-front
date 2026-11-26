# Design system: rules, motion and colour

Taken from the design review plan. CSS lives in `D:/platform/redesign-ref/design/kit.css`; the Flutter column says how to build each pattern. In the app these become tokens and widgets in `lib/design/` (see START.md, phase 1).

### 1.1 The five rules every student screen must pass ("the 5-second test")
1. **One main action.** Exactly one filled button (`.k-btn` or `.k-btn.hot`) is visible above the fold on phone. Everything else is ghost, a link, or behind "المزيد".
2. **Max 12 words before the action.** Hero = one headline (≤ 7 words) + optional one line (≤ 9 words). No paragraph before the main button. No card whose only job is to explain how the screen works ("كيف تنفتح الجلسات؟", "وش يحسب في العداد؟", "شروط المعلم", "حالات اختبار الدرس", "قواعد الاختبار"). Rules become **3 icon rows max** (icon + ≤ 4 words each) or are deleted.
3. **Phone hero ≤ 190 px tall** on list/content screens. The four `k-stat` tiles leave the phone hero (they stay on web, 1 row). The first real content card must start within the first 260 px on a 390×844 phone.
4. **No system words.** Never show: الخادم، توقيت الخادم، البلوتوث، GPS، إشارات قريبة، حزمة مشفّرة، الاستوديو، رمز الاسترداد، المصادقة، نسخة ٣، ID codes like `#C-20418`. Say what the student gets: "حضورك تسجّل", "إجاباتك محفوظة".
5. **No demo controls in the UI.** State pickers used for artboards (segments like "قيد المراجعة / مرفوض / تمت الموافقة", "يكتب / كود غلط / موقوف", the "حالات اختبار الدرس" list) must be driven by props only and never rendered.

Vocabulary (apply everywhere, all roles): حصة = a live meeting with the teacher (50 minutes); درس = a recorded/reading item; دورة = the product; مادة = the school subject page. Do not use "جلسة" in student UI (currently mixed with حصة/درس). "عن بعد" (never "أونلاين"), "حضوري", "مجموعة", "فردي". Digits Arabic-Indic everywhere including "٢٤/٧", times and PINs.

### 1.2 Privacy contract (student-facing surfaces)
A student never sees: a count of who is inside a live room, avatars/initials/names of other students of his group, "زميلك/زميلتك في <مادة>", typing indicators of classmates, a course group chat with student authors, classmates' attendance, invitee lists that contain classmates suggested by the app, "تظلون في نفس الدورة". Allowed: the teacher (name/avatar), "أنت", anonymous leaderboards in Games that are platform-wide (not per group), a reviewer's first name + grade on public reviews, and people the student himself invited by username/phone to his own private meeting (he typed them; the app never suggests classmates).
Replacement patterns: live room shows `أنت والمعلمة` only; prejoin shows `الحصة شغّالة` + teacher avatar; course "group chat" becomes a one-way **إعلانات المعلم** thread (only teacher messages are visible, student replies go privately to the teacher); attendance shows only the student's own row.

### 1.3 Motion language — "ورق، حبر، ونبض" (paper, ink and pulse)
Today 90 % of motion is `kRise` (translateY 16px + fade, staggered). The new language keeps `kRise` only for admin tables. Student screens get **signature moves tied to meaning**: paper things flip/unfold, progress is drawn with ink, rewards pop with springs, live things breathe. All are transform/opacity/clip-path/stroke-dashoffset only (cheap, Flutter-friendly). Durations 180–700 ms, one "hero" animation per screen, the rest ≤ 300 ms. Every pattern is disabled under `prefers-reduced-motion` (already global in kit.css).

All classes live in `kit.css` (prefix `m-`), added by WP0. Delay via `--d`, index via `--i`.

| # | Name / class | What the student sees | Where it is used |
|---|---|---|---|
| M1 | **Page flip-in** `.m-flip` | cards swing in like a notebook page turning on its right edge (RTL spine) | Subject page cards, lesson list, دفتر المادة, library shelf items |
| M2 | **Ink draw** `.m-ink` | SVG path/ring draws itself, then the number counts up | progress rings, path "مسارك", chart lines, the check mark on success |
| M3 | **Spring pop** `.m-pop` | scale .6→1.08→1 overshoot with slight rotate | badges, coins, stickers, selected option, counters in bnav |
| M4 | **Sticker slap** `.m-slap` | element drops from scale 1.6/rotate −12°, lands with a 2-frame squash | "مباشر" tag, "جديد", result grade stamp, achievement stamps |
| M5 | **Tilt-stack deal** `.m-deal` | list cards are dealt from a stack: each starts rotated ±6° and offset, snaps straight | course cards (دوراتي), store items, games grid, teacher list |
| M6 | **Curtain wipe** `.m-wipe` | content revealed by a diagonal clip-path wipe (right→left for RTL) | hero bands on entry, tab content change, booking step change |
| M7 | **Elastic underline** `.m-squig` | a hand-drawn squiggle draws under the key word of the hero | one keyword per hero (student home, landing, exam result) |
| M8 | **Breathing live halo** `.m-breathe` | 2 concentric rings expand/fade around a live avatar/button + soft scale 1→1.03 | live banner, "ادخل الحصة", prejoin avatar, recording dot |
| M9 | **Jelly press** `.m-jelly` (on `:active`) | button squashes 0.94×1.04 and rebounds | every primary button and option tile on student screens |
| M10 | **Ticker roll** `.m-roll` | digits roll vertically slot-machine style to their value | prices in booking footer, points/coins wallet, countdown, exam score |
| M11 | **Confetti burst (bounded)** `.m-burst` | 10 small shapes shoot out once from a point and fade (pure CSS, 900 ms) | ONLY: booking confirmed, exam passed, level up, attendance done |
| M12 | **Shelf slide & wobble** `.m-wobble` | item slides on, then a tiny ±3° pendulum that decays | library books, wardrobe items, trophies, the spiral book hint |
| M13 | **Morph tab pill** `.m-pill` | selected pill background slides/stretches between tabs (width+translate) | `k-seg`, bottom nav active blob, filter chips |
| M14 | **Peek sheet** `.m-sheet` | bottom sheet rises with overshoot (translateY 100%→−8px→0) while backdrop blurs in | all student sheets/drawers on phone |
| M15 | **Shake-no / nod-yes** `.m-shake`, `.m-nod` | wrong: 3 quick horizontal shakes + coral flash; right: one vertical nod + green glow | exam answers in practice, PIN inputs, login error, game answers |
| M16 | **Parallax blobs** `.m-drift-a/b/c` | hero background shapes (circle, squircle, plus sign) drift at 3 speeds, and shift on scroll in Flutter | all student heroes (replaces the two identical blurred glows) |

CSS sketches (WP0 puts these in kit.css exactly; tune only timings):
```css
/* M1 */ @keyframes mFlip{from{opacity:0;transform:perspective(900px) rotateY(-70deg)}60%{opacity:1;transform:perspective(900px) rotateY(8deg)}to{transform:none}}
.m-flip{transform-origin:100% 50%;animation:mFlip .6s cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--i,0)*70ms)}
/* M2 */ .m-ink{stroke-dasharray:var(--len,300);stroke-dashoffset:var(--len,300);animation:mInk .9s cubic-bezier(.6,0,.2,1) .2s forwards}
@keyframes mInk{to{stroke-dashoffset:var(--to,0)}}
/* M3 */ @keyframes mPop{0%{opacity:0;transform:scale(.6) rotate(-6deg)}60%{opacity:1;transform:scale(1.08) rotate(2deg)}100%{transform:none}}
.m-pop{animation:mPop .45s cubic-bezier(.3,1.4,.5,1) both;animation-delay:var(--d,0s)}
/* M4 */ @keyframes mSlap{0%{opacity:0;transform:scale(1.6) rotate(-12deg)}55%{opacity:1;transform:scale(.94) rotate(-3deg)}75%{transform:scale(1.04,.96) rotate(-3deg)}100%{transform:rotate(-3deg)}}
.m-slap{animation:mSlap .42s cubic-bezier(.3,.9,.4,1) both;animation-delay:var(--d,.3s)}
/* M5 */ @keyframes mDeal{from{opacity:0;transform:translate(calc(var(--dx,40px)*-1),30px) rotate(var(--r,6deg)) scale(.92)}to{opacity:1;transform:none}}
.m-deal{animation:mDeal .5s cubic-bezier(.2,.9,.3,1.1) both;animation-delay:calc(var(--i,0)*60ms)}
.m-deal:nth-child(even){--r:-6deg;--dx:-40px}
/* M6 */ @keyframes mWipe{from{clip-path:polygon(100% 0,100% 0,100% 100%,100% 100%)}to{clip-path:polygon(-20% 0,100% 0,100% 100%,0 100%)}}
.m-wipe{animation:mWipe .55s cubic-bezier(.6,0,.2,1) both}
/* M7 */ .m-squig{position:relative;white-space:nowrap}
.m-squig svg{position:absolute;inset:auto 0 -8px 0;width:100%;height:10px;overflow:visible}
.m-squig path{fill:none;stroke:var(--s-sun);stroke-width:4;stroke-linecap:round;stroke-dasharray:240;stroke-dashoffset:240;animation:mInk .7s ease-out .5s forwards}
/* M8 */ .m-breathe{position:relative;animation:mBreathe 2.4s ease-in-out infinite}
.m-breathe::before,.m-breathe::after{content:"";position:absolute;inset:-4px;border-radius:inherit;border:2px solid var(--s-live);opacity:0;animation:mHalo 2.4s ease-out infinite}
.m-breathe::after{animation-delay:1.2s}
@keyframes mBreathe{50%{transform:scale(1.03)}} @keyframes mHalo{0%{opacity:.55;transform:scale(1)}100%{opacity:0;transform:scale(1.35)}}
/* M9 */ .m-jelly{transition:transform .18s cubic-bezier(.3,1.6,.5,1)} .m-jelly:active{transform:scale(.94,1.04)}
/* M10 */ .m-roll{display:inline-flex;overflow:hidden;height:1.3em;line-height:1.3}
.m-roll i{display:flex;flex-direction:column;font-style:normal;transform:translateY(calc(var(--v)*-1.3em));animation:mRoll .9s cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--i,0)*80ms)}
@keyframes mRoll{from{transform:translateY(0)}}
/* M11 */ .m-burst{position:absolute;inset:50% auto auto 50%;width:0;height:0;pointer-events:none}
.m-burst i{position:absolute;width:8px;height:8px;border-radius:2px;background:var(--c);animation:mBurst .9s cubic-bezier(.1,.7,.3,1) forwards;animation-delay:.15s;opacity:0}
@keyframes mBurst{0%{opacity:1;transform:translate(0,0) rotate(0)}100%{opacity:0;transform:translate(var(--x),var(--y)) rotate(var(--rot,220deg))}}
/* M12 */ @keyframes mWobble{0%{opacity:0;transform:translateX(40px) rotate(8deg)}40%{opacity:1;transform:translateX(0) rotate(-4deg)}65%{transform:rotate(3deg)}85%{transform:rotate(-1.5deg)}100%{transform:none}}
.m-wobble{transform-origin:50% 100%;animation:mWobble .8s ease-out both;animation-delay:calc(var(--i,0)*60ms)}
/* M13 */ .m-pill{position:relative} .m-pill>.m-pill-bg{position:absolute;top:4px;bottom:4px;right:var(--x,4px);width:var(--w,25%);border-radius:19px;background:#fff;box-shadow:0 4px 12px rgba(ref-ink,.12);transition:right .35s cubic-bezier(.3,1.3,.5,1),width .35s cubic-bezier(.3,1.3,.5,1)}
/* M14 */ @keyframes mSheet{0%{transform:translateY(100%)}70%{transform:translateY(-8px)}100%{transform:none}}
@media (max-width:760px){.k-drawer.m-sheet,.m-sheet{animation:mSheet .5s cubic-bezier(.2,.8,.2,1) both}}
/* M15 */ @keyframes mShake{20%,60%{transform:translateX(-7px)}40%,80%{transform:translateX(7px)}} .m-shake{animation:mShake .36s linear}
@keyframes mNod{40%{transform:translateY(5px)}70%{transform:translateY(-2px)}} .m-nod{animation:mNod .36s ease-out}
/* M16 */ .m-drift-a{animation:mDriftA 11s ease-in-out infinite}.m-drift-b{animation:mDriftA 15s ease-in-out infinite reverse}.m-drift-c{animation:mSpinSlow 28s linear infinite}
@keyframes mDriftA{50%{transform:translate(22px,-18px) rotate(8deg)}} @keyframes mSpinSlow{to{transform:rotate(360deg)}}
```

Flutter equivalents (so the build team is never blocked):
| Pattern | Flutter |
|---|---|
| M1 flip-in | `AnimationController` + `Transform(alignment: Alignment.centerRight, transform: Matrix4.identity()..setEntry(3,2,0.0011)..rotateY(v))`, staggered with `Interval` (or `flutter_animate`: `.flipH(alignment: centerRight)`) |
| M2 ink draw | `CustomPainter` with `PathMetric.extractPath(0, len*t)`; rings = `TweenAnimationBuilder<double>` + `CircularProgressIndicator`/arc painter; count-up = `TweenAnimationBuilder<int>` |
| M3 pop / M4 slap | `ScaleTransition` + `RotationTransition` with `Curves.elasticOut` / `Curves.easeOutBack`; slap = `TweenSequence` (1.6→.94→1.04→1) |
| M5 deal | `AnimatedList`/staggered `SlideTransition`+`RotationTransition` per index (`Interval(i*0.06, …)`) |
| M6 wipe | `ClipPath` with a custom clipper driven by an `Animation<double>` (or `ShaderMask` with a linear gradient stop) |
| M7 squiggle | same `CustomPainter` path-draw as M2 under a `Stack` |
| M8 breathe | repeating `AnimationController`, two `Container` rings with `Opacity`+`Transform.scale` |
| M9 jelly | `GestureDetector(onTapDown/Up)` + `AnimatedScale` with `Curves.easeOutBack` (non-uniform via `Transform.scale(scaleX:, scaleY:)`) |
| M10 roll | `AnimatedSwitcher` per digit with `SlideTransition`, or the `AnimatedFlipCounter` package |
| M11 burst | 10 `Positioned` children animated by one controller (`Tween<Offset>` + fade); or a single Lottie file |
| M12 wobble | `TweenSequence<double>` rotation with `alignment: Alignment.bottomCenter` |
| M13 pill | `AnimatedPositionedDirectional` + `AnimatedContainer` behind a `Row` (or `CupertinoSlidingSegmentedControl`) |
| M14 sheet | `showModalBottomSheet` with custom `AnimationController` curve `Curves.easeOutBack`; `BackdropFilter` blur |
| M15 shake/nod | `TweenSequence` on `Transform.translate` triggered by a controller `forward(from:0)` |
| M16 parallax | `AnimatedBuilder` on a repeating controller for drift + `ScrollController` offset × factor for parallax |

Motion budget per screen: 1 hero move (M1/M5/M6/M12) + M2/M10 for numbers + M9 on taps. M11 only in the four listed places. Never animate more than ~12 elements at entry on phone. Loops (M8, M16) only on ≤ 3 elements per screen.

Per-area signature (so areas feel different, not the same stagger):
- Home: M6 hero wipe + M7 squiggle under the key word, live banner M8, "كمّل" cards M5, shelf M12.
- Subject page / lessons / دفتر: M1 everywhere, book M12, path M2.
- Booking: step change M6, option tiles M3 on select + M9, price M10, success M2 check + M11.
- Exams: questions slide like cards from a deck (M5 single), answer select M3, result stamp M4 + M10 score (+M11 on pass only).
- Games / rewards / wallet: M3, M4, M10, M12 (most playful area; loops allowed on the mascot only).
- Quran / Nahw: calm — M2 for progress, M6 for content, no M11 except day completed.
- Auth: M14 sheets, M15 on errors, M2 check on success.
- Live / prejoin / attendance: M8 only + M2 check when attendance is done.
- Chat / inbox: bubbles M3 with `transform-origin` at the bubble tail; unread badge M4.
- Parent / teacher / admin / super: keep current restrained motion; adopt M13, M14, M9, M10 only.

### 1.4 Color system for student screens
Brand base is unchanged (navy/blue/cyan + apricot/coral). Students get six playful **subject/area accents**, each with a soft tint and an ink (text-on-tint) colour, all AA on white for text ≥ 14 px bold. WP0 adds these tokens to `:root` in kit.css.

| Token | Hex | Tint (bg) | Ink (text on tint) | Role |
|---|---|---|---|---|
| `--k-navy` | `ref` | — | — | text on light, dark heroes base |
| `--k-deep` | `ref` | — | — | hero end stop, player/exam chrome |
| `--k-blue` | `ref` | `ref` | `ref` | primary action, links |
| `--k-cyan` | `ref` | `ref` | `ref` | gradients, focus ring, info |
| `--k-apricot` | `ref` | `ref` | `ref` | warm highlight, "next step" |
| `--k-coral` | `ref` | `ref` | `ref` | live, urgent, hot CTA end stop |
| `--s-sun` (new) | `#FFC53D` | `#FFF4CC` | `#7A5200` | rewards, points, stars, squiggle |
| `--s-mint` (new) | `#19C29B` | `#D9F7EE` | `#0C6B55` | success, done, attendance |
| `--s-grape` (new) | `#7A4DF0` | `#ECE5FF` | `#4A28B8` | games, challenges, AI helper |
| `--s-pink` (new) | `#FF5FA2` | `#FFE3EF` | `#A81E5E` | social/messages, stickers, favourites |
| `--s-lime` (new) | `#9BD728` | `#EEF9D2` | `#4C6B05` | streaks, Nahw, "new" |
| `--s-sky` (new) | `#3DA5FF` | `#E0F0FF` | `#0F5CA8` | schedule, calendar |
| `--s-live` (alias) | `ref` | | | live halo colour |

Usage rules:
- **Each student area owns one accent** (set on the root via a modifier class that overrides `--k-acc`/`--k-acc2` and adds `--area`,`--area-tint`,`--area-ink`):
  `.k.a-home` blue→cyan · `.k.a-learn` (دوراتي/المادة/الدروس) apricot→coral · `.k.a-exam` grape→blue · `.k.a-games` grape→pink · `.k.a-store` sun→apricot · `.k.a-quran` mint→`#0F6E6D` · `.k.a-nahw` lime→mint · `.k.a-sched` sky→cyan · `.k.a-chat` pink→apricot · `.k.a-money` sun→mint · `.k.a-me` blue→grape.
- **Hero** on student screens stops being the same navy radial everywhere: `background: radial-gradient(120% 160% at 85% -30%, var(--k-acc) 0%, color-mix(in srgb, var(--k-acc) 35%, `ref`) 45%, `ref` 100%)` plus three M16 shapes tinted `--k-acc2`, `--s-sun`, `#fff` at 10–20 % opacity. (Flutter: precomputed gradient stops per area; do not rely on color-mix at runtime — WP0 writes the resolved hex per area in a comment table in kit.css.)
- **Subject colours** (one per subject, used for book covers, course cards, calendar dots; same subject = same colour on every screen): الرياضيات `#FF7A59` · الفيزياء `#7A4DF0` · الكيمياء `#19C29B` · الأحياء `#2FB5A8` · الإنجليزي `#07B8EE` · العربي/لغتي `#0F6E6D` · القدرات/التحصيلي `#FFB020` · البرمجة `#1979C1` · القرآن `#1D9A63` · الدراسات الإسلامية `#B7791F`. WP0 exposes them as `--sub-math` … and a helper class `.sub-math` etc. that sets `--sub`.
- 60/30/10: 60 % neutral (page `ref`, white cards), 30 % area accent (hero, selected states, icons), 10 % contrast accent (the one main button uses `.hot` apricot→coral **only when the action moves the student forward**: ادخل الحصة، كمّل، ابدأ الاختبار، أكّد وادفع; everything else uses the area gradient).
- Status colours never change with the area: live = coral, success = mint, warning = sun, locked = `#C9D6E6`, error = `#C2410C`.
- Other roles keep their current single accent (teacher purple, parent teal, admin blue/amber, super gold).

---


## Owner decisions already taken
| # | Question | Default used |
|---|---|---|
| O-1 | Which purchase flows are real? (monthly subject booking, course enroll with 1/3/4-month plans, teacher packs with waitlist, platform subscription, activation fee, points) | Keep all, make them look like the booking flow and use the same example prices. |
| O-2 | Student-hosted meetings with friends ("اجتماعات خاصة مع أصحابك", meeting links, daily minutes plan): keep? They conflict in spirit with the privacy rule. | Keep; the app never suggests classmates, guests never see each other, no conflict hints. If the owner prefers, WP5/WP8 delete the feature (about 8 boards). |
| O-3 | Leaderboards in games show real full names of minors. | Nicknames + avatar; platform/grade-wide only; no class-section board. |
| O-4 | Teacher asking a student for his national ID inside the exams list. | Removed from the student exam list; if needed it goes through the parent. |
| O-5 | Course group chat. | Replaced by a teacher-only announcements thread. |
| O-6 | Peer-assisted attendance ("عبر زميل"). | Mechanism may stay in the product but is invisible to the student. |
