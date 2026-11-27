# Screen agent brief (phases 2–6)

Every screen agent reads this file first, then its own prompt (group, screens, files).

## Read

1. `docs/redesign/START.md`, `RULES.md`, `DESIGN_SYSTEM.md`, `BRANDS.md`, `KIT_SPEC.md` (the kit you build with),
   `CAST.md`.
2. Your rows in `SCREEN_MAP.md` (every design screen of your group, with today's Flutter file and status) and in
   `PARITY_TABLE.md` (every feature you must keep).
3. Root `CLAUDE.md`, `lib/design/README.md`, `docs/guides/ui-kit.md`, `docs/guides/testing.md`, and the guide of
   your area (`docs/guides/*.md`, the folder `CLAUDE.md` files).
4. The API contracts in `docs/redesign/api/*.md` that your screens use (privacy, booking, international, child_code,
   games, notebook, meetings_bot, payments, demand). The backend is already built on `feature/redesign` in
   `D:/platform/nextbrain/_wt/rd-back` (read-only for you); `test/contract/api_paths.json` is refreshed from it.

## The reference

- HTML: `D:/platform/redesign-ref/design/<File>.dc.html?<props>`; serve with
  `py -3.12 -m http.server 8765` from that folder if you need to click through states.
- Screenshots: `D:/platform/redesign-ref/ref/<section>/…phone.png` (390×844 @2) and `…web.png` (1360×900);
  `D:/platform/redesign-ref/ref/index.json` maps each SCREENS.md row to its two files. Open them with the Read tool.
- The reference wears another product's logo, name and blue/navy/apricot palette. NEVER copy those: NextBrain uses its
  own logo and name, and colours only through `context.colors` and the kit roles (green / gold). Layout, spacing,
  hierarchy, type, icons, states, copy and motion must match.

## Build rules (binding)

- Rebuild each screen from the reference with the kit (`lib/design/`): `AppAreaScope` for the student area accent,
  kit hero / cards / buttons / pill / sheets / states, the motion library M1–M16 exactly as DESIGN_SYSTEM.md §1.3
  assigns them per area (one hero move per screen, M9 on taps, loops ≤ 3 and parked under Reduce motion).
- Keep every behaviour, API call, provider, kill switch (`ParentComponent(featureKey:)` / `BasePage` keys) and
  route of the screens you rebuild (`PARITY_TABLE.md`). A feature the design does not draw is kept and restyled where
  the design's navigation would put it (usually "More"). Nothing is deleted; anything you think conflicts with
  RULES.md goes in your report for the owner.
- A page the design does not draw gets a design of yours in the same language (kit, area accent, motion), never the
  old look.
- Copy: the approved Arabic from the reference, exactly, plus English. RULES.md §1 vocabulary (دورة, عن بعد, فردي,
  حصة/درس, no "جلسة" in student UI, no "لحالك", no "كشكول" → دفتر). The 5-second rules (DESIGN_SYSTEM §1.1): one
  filled button above the fold, ≤ 12 words before it, phone hero ≤ 190 px, no system words, no demo state pickers.
- International (RULES §3): never assume a country. Currency, payment methods, grades, curricula, weekend, VAT and
  in-person availability come from the server; Saudi-only items show only when the country is Saudi Arabia. Phones
  through the country-code picker (any country, E.164). Times through `AppTime` (viewer's time zone).
- Privacy (DESIGN_SYSTEM §1.2): a student never sees classmates, counts of who is inside, or classmates' attendance.
  Teachers still see everything. Follow `api/privacy.md`.
- Repo rules: tokens only (no raw numbers or `maxWidth` pixels), `context.colors` only, `appText`, `AppTime`,
  `countText` for counts, `showAppNotice`, `AppDropdown` / `AppSwitch`, `DirIcons` for RTL icons, no chart package,
  no `dart format` on existing files (new files hand-formatted), deferred screens stay deferred.
- Pages are pushed with `MaterialPageRoute` (D-081). If you need a new URL route, a new global provider, a kit piece
  or a change in a shared file, do not edit it: write the request in your report.

## Files

- You edit only the files your prompt gives you. Never: `lib/main.dart`, `lib/core/**`, `lib/config/**`,
  `lib/design/**`, `lib/utils/**`, `lib/features/org/**` (layout), `pubspec.*`, `test/contract/*.json`,
  `test/support/fake_api.dart`, `homeBudgets`, `AttentionTabs`.
- Strings: add new keys directly to `assets/translation.json` (`{ "key": { "en": "…", "ar": "…" } }`), prefixed
  with your group (`sa_`, `sb_`, `sc_`, `sd_`, `bk_`, `pa_`, `t1_`, `t2_`, `a1_`, `a2_`). Add only; never change or
  delete an existing key (if existing copy must change, list it in your report). The lead merges the file by key.
- Test fakes: put your fake endpoints in `test/support/redesign/<group>_fakes.dart` on top of `FakeApi` (do not edit
  `fake_api.dart`).

## Acceptance (before you report)

1. `flutter analyze --no-fatal-infos --fatal-warnings` exits 0 for the whole project.
2. Tests: every new widget through `expectNoLayoutErrors` (320×640 and 1400×900, ar/en, textScaler 1.3); the existing
   suites covering your folders; `test/perf/` home budgets if you touched a home; `test/ui/` rules tests
   (`kit_rules`, `rtl_icons`, `a11y_guidelines`, `help_ids`).
3. Goldens: `test/visual/redesign/<group>/` (tag `visual`) renders each of your screens/states with CAST.md demo data at
   390×844 and 1360×900, Arabic (and English for the main states). Open every PNG next to its reference screenshot and
   fix every difference in layout, spacing, size, copy, icon, missing element or state. Colour/logo differ by brand only.
4. Motion: each screen uses the M-pattern its area is given, and Reduce motion turns loops off (test it).
5. Commit in small steps, one screen group per commit, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   Do not push, do not merge.

## Report (final reply, ≤ 250 words)

Files changed (grouped); new string keys (count); new routes / providers / kit pieces / shared-file changes
you need from the lead; parity rows kept (count) and anything moved; differences from the reference you could not fix,
and why; owner questions.
