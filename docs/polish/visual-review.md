# Visual review of the home screens (2026-10-28)

This review is based on what the screens look like on screen. The layout harness only checks that nothing overflows; this one checks how the screens look.

**Renders.** `test/visual/home_screens_golden_test.dart` (tag `visual`, not part of CI) draws 8 screens: the super admin home, the org admin home, the org member home, the student home, the teacher home, the parent Today tab, the RAG chat with its conversations panel, and the RAG console Health block. Each screen is drawn at 390×844 and 1440×900, in Arabic and English, in light and dark mode. That gives 64 PNGs in `test/visual/goldens/`. They use the app's real fonts, loaded from the `fonts:` section of `pubspec.yaml`, plus Roboto and MaterialIcons from the SDK, and real shadows. A page taller than the window is drawn whole. Student and teacher bodies are drawn inside the max width their screens use (1000 and 1100).

To regenerate them: `flutter test test/visual --update-goldens`. The times follow the clock, so the PNGs are for reading, not for diffing.

**Severity.**
- P1: broken, or wrong data.
- P2: clearly hurts reading, hierarchy or contrast.
- P3: polish.

**Status.** "fixed" means fixed in this pass and checked in a new render. "open" means still to do. "report" means outside this pass's files: RAG is owned by another agent, and the theme is server-driven.

Before / after pairs for the three worst issues are in `docs/polish/visual/`:
- `1-typography_*`
- `2-section-titles-rtl_*`
- `3-member-desktop_*`

## Findings

| # | Screen | Size | Lang | Theme | Issue | Sev | Fix | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | every screen | all | all | all | The family `tajawal` only had `Tajawal-Regular.ttf`, declared `style: italic`. Flutter does not synthesise bold, so every `w600`–`w900` (names at 26 w900, figures, section titles, card titles) drew as Regular. The kit's whole type scale was flat. | P1 | Register Medium 500, Bold 700, ExtraBold 800 and Black 900 (600 resolves to Bold) from `assets/fonts/tajawal/` in `pubspec.yaml`. The Regular is now `normal` style. | fixed |
| 2 | admin home | all | all | all | The "Revenue by currency" donut centre added EGP and SAR together ("643380"). | P1 | The centre shows the main currency's share ("98% · EGP") (`_CurrencyShare`). | fixed |
| 3 | every home (`HomeSectionTitle`) | 390 / 1440 | all | all | A `Flexible` title next to a `Spacer` split the row in two. Titles were cut at half width ("Continue learn…", "Today's ses…", "الإدارات والأ…") and the action ("See all", "Full timetable") floated mid-row, not at the end. | P2 | The title is `Expanded` and the action sits at the end. The title also takes an optional `subtitle`. | fixed |
| 4 | every home (`HomeActionCard`) | all | all | all | Same `Spacer` + `Flexible` pair: the count sat mid-card instead of in the end corner. | P2 | `Expanded` + `Align(topEnd)`. | fixed |
| 5 | admin, org, RAG health (`AppTrendTile`) | all | ar | all | Signed deltas drew in reverse in RTL ("40.7%+", "0.3%-"). | P2 | The delta text is LTR. | fixed |
| 6 | admin (AI card) | all | ar | all | "11.4 s" drew as "s 11.4". | P2 | Wrapped in an LTR isolate. | fixed |
| 7 | every home | all | all | dark | Primary indigo `#2F3E9E` used as text or icon on the dark card `#1E2342` is about 1.6:1: section actions, count chips, shortcut and hub icons, the blue counts ("26", "7"), "Open the console", the play buttons. | P2 | New `appInk(context, tone)` in `app_charts.dart`: a tone used as ink is lifted to OKLab L ≥ 0.72 on dark and darkened to L ≤ 0.56 on light, hue kept. Fills and tints keep the raw tone. Applied in `HomeSectionTitle`, `HomeActionCard`, `HomeShortcuts`, `AppTrendTile` delta, `OrgPill`, the org attention action, the admin AI card, the course progress row and parent session times. | fixed (kit + homes) |
| 8 | org home, student, member | all | all | light | Warning orange `#F2A93B` as text on white or on its own tint is about 2:1: "Review", "Open time…", the "3 waiting" pills, "Due soon". | P2 | `appInk` on `OrgPill` and the attention action. The inbox "Due soon" pills (`unified_inbox.dart`) still use the raw tone. | fixed / open (inbox pill) |
| 9 | member home | 1440 | all | all | One 1400 px column. Every row was a thin strip and two thirds of each card were blank. Mixed headings: three plain `AppSectionTitle`s flush to x = 4, the rest with the accent bar. | P2 | At ≥ 1000 px (`Breakpoints.desktop`): two columns, today and what needs you on one side, decisions, what you manage and quick actions on the other, max 1240 px. Every heading is a `HomeSectionTitle` (16 px gutter). | fixed |
| 10 | student home | 1440 | all | all | A 1000 px single column: a 5-row agenda and a 5-row week each stretched over the full width. | P2 | New `HomeSplit` in `home_kit.dart` puts Today and This week side by side from 900 px. | fixed |
| 11 | admin home | 1440 / 390 | all | all | "Activity & health" tiles cut every label ("Live even…", "مهام فش…"). | P2 | `AppStatTile` (`OrgStatTile`) label is 2 lines. The admin health grid is `minTile` 160, so 2 per row. | fixed |
| 12 | admin home | all | all | all | Revenue "631785 EGP" had no digit grouping. | P2 | "631,785 EGP" (`_money`). | fixed |
| 13 | org home | 1440 | en | light | The attention action was cut at 96 px ("Open time…") on an 820 px card. | P2 | Cap 160 px from 600 px wide; 96 px stays on phones. | fixed |
| 14 | parent Today | all | ar / en | all | The session mode showed the raw keyword ("offline", "online") in Arabic too. | P2 | "حضوري / أونلاين", "In person / Online". | fixed |
| 15 | student home | all | all | all | Course progress used the grade traffic light, so 22 % drew in alarm red. | P3 | Brand colour while under way, success at 100 %. | fixed |
| 16 | every `HomeActionGrid` | 1440 | all | all | 5 cards in 4 columns left one card alone on the last row. | P3 | The column count steps down to avoid a lone last card (5 → 3 + 2). | fixed |
| 17 | org home | all | all | all | "Last 30 days" heads tiles labelled "· 7 days". | P3 | Renamed "Trends · 30 days" (7-day figures over a 30-day sparkline). | fixed |
| 18 | theme (all) | all | all | light / dark | `textLight` `#8A8EA8` on white (3.3:1) and `darkTextLight` `#6B7099` on `#1E2342` (≈ 2.9:1) fail AA for the small captions that use them ("Last 7 days", agenda end times, "No lecture scheduled yet"). | P2 | Theme tokens (`app_theme.dart` defaults + server theme): darken `textLight` to about `#6E7290` and lighten `darkTextLight` to about `#8C91B8`. | report |
| 19 | RAG chat | 1440 | all | all | The answer card runs the full 1100 px column; Arabic and English lines exceed 120 characters. | P2 | Cap the answer column at about 760 px, centred, in `rag_chat_screen.dart`. | report |
| 20 | RAG console Health | all | ar | all | Units reversed in RTL in the path table ("ms 70", "s 14.0"). | P2 | LTR isolate or `textDirection: ltr` on the value cells in `rag_admin_console.dart`. | report |
| 21 | RAG chat | all | all | dark | The citation marker "[1]", the "New chat" icon and the active row icon are primary-on-dark (about 1.6:1). | P2 | Use `appInk(context, c.primary)` for ink (the helper now exists). | report |
| 22 | RAG console Health | 1440 | all | all | The four tiles stop at 950 px. The path table spreads 4 columns across 1400 px, so labels and figures sit far apart. | P3 | Cap the table width (about 720 px) or use a 2-column layout. | report |
| 23 | RAG console Health | 390 | ar | all | Tile label "إجابات معتمدة مباشـ…" is cut. | P3 | 2-line label or shorter copy. | report |
| 24 | teacher home | all | all | all | "Upcoming sessions" is the older `ScheduleQueueList`: a red "Live" slab, its own radii, a lowercase raw day label and a "Weekly Schedule" sub-heading. It does not match the kit and repeats today's agenda. | P3 | Restyle on `HomeAgenda` / `AppCard`, or drop it when the agenda already lists the same sessions (`teacher/sessions/...`). | open |
| 25 | admin home | 1440 | all | all | The left column ends about 300 px above the right one: a blank block under the bar chart. | P3 | Move the AI card under the chart when the right column is taller. | open |
| 26 | admin / parent | all | all | all | "Needs you" draws zero cards ("To do 0 · You're all caught up", "Link requests 0") among real alerts. | P3 | Hide zero cards when another card has a count; keep a single "all clear" when none do. | open |
| 27 | member / org | 1440 | all | all | The stat strip (4 × 190 px) and the org trend tiles (3 in 2 columns) leave a gap or a lone tile. | P3 | Fill the row (4 equal columns), or 3 columns for 3 tiles. | open |
| 28 | member home | all | all | all | Decision and manage tiles (`AppActionCard`) are a heavy gradient wash. A tile without a subtitle has its title top-aligned, not centred. | P3 | Use a lighter tint, and centre the single line. | open |
| 29 | admin home | 390 | ar | all | "(24 ساعة)" wraps after "(24": the bidi of a number inside parentheses. | P3 | Translation: "مهام فشلت خلال 24 ساعة". | open |
| 30 | teacher home | 390 | all | all | The hero figure label "Earnings this …" is cut. | P3 | A shorter key ("This month") or 2 lines. | open |

## Checked and fine

- **RTL mirroring.** Chevrons point the reading way. Bar charts and sparklines read from the reading start (in Arabic the oldest day is on the right and the newest marker on the left). The y-axis is on the reading-end side. The timeline rail and the "now" marker sit on the start side. Progress bars fill from the start.
- **Dark surfaces.** Cards (`#1E2342`) on the page (`#0F1224`) separate well. Hero gradients keep white ink. Chart series are snapped into the dark lightness band.
- **Spacing.** The 8 · 16 · 24 · 32 rhythm holds between sections (28 between home blocks). Card padding is 14–16.
- **Overflow.** No overflow or exception in any of the 64 renders.

## Changed files

- `pubspec.yaml`: the Tajawal weights.
- `lib/design/app_charts.dart`: `appInk`, and the LTR delta.
- `lib/design/home_kit.dart`: `HomeSectionTitle`, `HomeActionCard`, `HomeActionGrid`, `HomeShortcuts` ink, and the new `HomeSplit`.
- `lib/features/org/org_ui.dart`: `OrgStatTile` 2-line label, `OrgPill` ink.
- `lib/features/org/org_dashboard_home.dart`: attention action ink and width, trend title.
- `lib/features/org/org_member_dashboard.dart`: two columns and section titles.
- `lib/features/admin/admin_home_body.dart`: currency centre, grouped money, LTR unit, ink, health grid.
- `lib/features/student/home/home_screen.dart`: `HomeSplit`.
- `lib/features/student/home/home_event_rows.dart`: progress colour and ink.
- `lib/features/parent/parent_overview_page.dart`: mode label and time ink.
- `lib/features/admin/admin_finance_page.dart` and `lib/features/admin/admin_income_breakdown.dart`: two unused imports from HEAD removed. They were analyzer warnings already in `fe9492e`.
