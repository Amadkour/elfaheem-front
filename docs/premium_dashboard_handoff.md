# Premium dashboard handoff (D-631, branch `feature/premium-dashboard`)

Shared pieces are in `lib/design/app_dashboard_kit.dart`, exported from `app_kit.dart`. Visual reference: `test/visual/premium_dashboard_golden_test.dart` (`_SampleHome`).

- `AppGreetingHero(greeting:, summary:, avatar:, initials:, ring: 0..1, cta:, actions: [ChromeIconButton…], illustration:, footer:, centered:)` is the forest card. `cta` takes `AppGreetingHeroButton(label:, onTap:, icon:)`. Use `centered: true` on desktop and leave it false on phones. The greeting line comes from `HomeHeader.greetingLine(name)`.
- `HomeHeader(…existing args…, greetingHero: true, ring:, cta:, avatar:, centered:)` draws the header as the hero with the same data and buttons. `leading`, the buttons and `contextSwitcher` stay where they were. `wideTrailing` still sits beside the hero on desktop.
- `AppStatCard(icon:, value:, label:, tone: AppBlockTone.x, footer:, delta: 0.12, deltaGoodWhenUp:, onTap:)` shows a big tone figure, an icon chip and a tinted footer band. Put 4 of them in an `AppKpiGrid`.
- `AppKpiSpark(label:, value:, values: [..], icon:, delta:, tone:)` and `AppRingStat(label:, value:, progress:, caption:, delta:, tone:)` fill the side column.
- `AppShortcutGrid(maxColumns: 2|4, children: [AppShortcutTile(icon:, label:, onTap:, tone:, badge:, subtitle:)])` is the 2×2 grid on phones.
- `AppSectionCard(title:, subtitle:, actions: [AppButton.ghost…], tabs: AppTabs(…), child:)` is the card for any section. `AppBreadcrumb(parts:)` is text only.
- `CourseListCard` keeps its parameters; only its look changed (inset cover, price in the primary ink).
- Tones: emerald = primary/done, peach = learning, sky = schedule, gold = achievements only. Red is only for live items, errors and unread counts.

Desktop home layout (the wide shell already draws the title and breadcrumb, so do not add another page title):
1. `IntrinsicHeight(Row[Expanded(flex 5: hero centered), gap lg, Expanded(flex 6: side AppSectionCard — today/agenda/calendar)])`
2. `AppKpiGrid` with 4 `AppStatCard`s
3. `Row[Expanded(flex 7: AppSectionCard with tabs + chart/list), gap lg, Expanded(flex 4: Column[AppKpiSpark, AppRingStat])]`
4. Section cards for lists, for example the courses as `CourseListCard` tiles.

Phone home layout: the hero (split layout), then `AppShortcutGrid` (2 columns), then section titles (`AppType.section`) over horizontal `ListView`s of `CourseListCard` tiles (width 220, height `CourseListCard.tileHeight`), then the stat grid.

Rules: map only data you already have, and never add a request, a route or a provider. Keep every ValueKey, featureKey and callback. Write fractions and mixed numbers through `ltrIsolate`. Digits stay Latin. Test each new layout with `expectNoLayoutErrors`. Avoid `LayoutBuilder` inside anything that will sit in an `IntrinsicHeight` row.
