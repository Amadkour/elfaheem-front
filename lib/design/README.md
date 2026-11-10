# NextBrain design system

One import gives a screen everything: `import 'package:flutter_education_app/design/app_kit.dart';`

Everything reads the LIVE theme (`context.colors`, from the server palette the super admin picks), follows the
person's font choice (D-072), mirrors in Arabic, has a dark mode, and turns its motion off under Reduce motion.
The rules below are checked by tests (`test/ui/rtl_icons_test.dart`, `app_fonts_guard_test.dart`,
`a11y_guidelines_test.dart`, `brand_gradient_test.dart`) and by review.

## 1. Tokens — `app_tokens.dart`

Never write a raw number for these in a screen.

| Token | Values | Use |
|---|---|---|
| `AppSpace` | xxs 4 · xs 8 · sm 12 · md 16 · lg 24 · xl 32 · xxl 48 · xxxl 64 · `gutter(width)` · `sectionHead` (32 above, 12 below) · `hero` / `block` paddings | padding, gaps (`AppSpace.gapMd`) |
| `AppRadius` (D-612) | chip 10 · control 14 (button, input) · card 16 · block 24 · sheet 28 · hero 32 · pill | corners by hierarchy (`AppRadius.cardAll`), never one radius on everything |
| `AppElevation.of(context, level)` | 0 flat · 1 card (a whisper) · 2 raised · 3 overlay · 4 modal | shadows in the warm `shadowTone`; a resting card is tone + hairline (D-612); `AppElevation.border` adds the dark-mode hairline |
| `AppShadow` | card · raised | the theme's two named shadows |
| `AppMotion.of(context)` | fast 180 · base 220 · slow 300 ms, zero under Reduce motion | every animation |
| `AppTouch` | min 48 · primary 56 | hit areas |
| `AppIconSize` | xs 14 · sm 16 · md 20 · lg 24 · xl 32 · hero 40 | icons |
| `AppBorder` | hairline 1 · strong 1.5 · focus 2 | borders, focus rings |
| `AppType` | see below | text |
| `AppWidth` (D-304) | form 600 · reading 860 · content 1120 · wide 1440 · full; `inside(available)` | page-body width: `BasePage(useWebCard: true, width: AppWidth.wide)`, `AppWidthBox`, `AdminPage(width:)` |

**Type scale** (`AppType.x(context)`; weights w400–w600, D-102). The four heading roles are EDITORIAL (D-611): Markazi
Text (`AppFonts.editorial`) at an OPTICAL size, drawn at 1.3 × (Latin) / 1.25 × (Arabic) because its letters are
small on their body; with Display & reading › Headings › Same as text they use the text font at the sans size. The
theme's `display*` / `headline*` / `titleLarge` (app bar, dialog titles) follow.

| Role | Size / weight | For |
|---|---|---|
| `display` | editorial 32 (sans 28) · 600 | a dashboard greeting |
| `headline` | editorial 24 (sans 22) · 600 | a hero title, the home greeting |
| `pageTitle` | editorial 22 (sans 20) · 600 | the page header |
| `section` | editorial 18 (sans 16) · 600 | section headings, card titles, `AppSectionTitle` |
| `body` / `bodyStrong` | 14 · 400 / 600 | paragraphs |
| `row` | 14 · 500 | list and table rows |
| `label` | 13 · 500 | field labels, buttons sm |
| `meta` | 12 · 400 muted | secondary lines, timestamps |
| `overline` | 11 · 600 | small caps-like labels above a figure |
| `figure` / `figureLarge` | 17 / 28 · 600, tabular digits | numbers in tiles / KPI cards |

**Colours** are roles on `context.colors` (default palette: Warm Editorial, D-610): surfaces (`background`, `surface`,
`cardBg`, `cardBg2`, `inputBg`, `divider`), ink (`textDark`, `textMedium`, `textLight`), brand (`primary`,
`primaryDark`, `primaryLight`, `accent` = peach, `accent2` = gold, `accent3` = sky), blocks (`blockPeach`,
`blockSky`, `blockGold`, `blockEmerald`, `blockInk`, `blockMuted(b)`, `blockFaint(b)`, `blockAccentInk(c, b)`),
`shadowTone`, status (`success`, `warning`, `danger` + `*Tint`), on-gradient ink (`onHero`,
`onHeroMuted`, `heroGlass`, `heroGlassBorder`). Never `Colors.white` / `Colors.black` / a hex in a screen.

## 2. The gradient — `app_gradients.dart` (D-136, D-180)

The brand gradient is derived from the primary family; every stop keeps white ink at WCAG AA. It is a **touch**:

- ✓ page / section headers (`AppPageHeader`'s accent strip, `AppGradientSurface`), the ONE primary button of a
  screen, the selected tab or pill, the active sidebar item, key chart series, ONE highlighted KPI
- ✗ never behind body text, forms, lists or tables · never two gradient fills side by side · never the legacy
  accent / teal / gold gradient getters in new UI

```dart
AppGradientSurface(child: Text('Good morning', style: AppType.display(context)))  // onHero ink inside
const AppAccentStrip()                                    // 3 px brand line on top of a header / card
AppGradientText('12,480')                                 // ONE key figure (plain primary in high contrast)
AppGradients.chart(context)                               // a bar / area fill
```

## 3. Components

| Need | Use | File |
|---|---|---|
| page header | `AppPageHeader(title:, subtitle:, icon:, primaryAction:, actions:, search:, onRefresh:, updatedAt:, bottom:)` | `app_page_header.dart` |
| section | `AppSection(title:, trailing:, child:)` | `app_page_header.dart` |
| buttons | `AppButton.primary / secondary / tonal / ghost / danger(label:, onPressed:, icon:, busy:)` · `AppIconButton(icon:, tooltip:, badge:)` · `AppButtonRow(primary:, secondary:)` — see §3a | `app_buttons.dart` |
| text input | `AppField(controller:, label:, hint:, icon:, helper:, errorText:)` · `AppEmailField` / `AppPasswordField` / `AppPhoneField` / `AppUrlField` · `AppFieldLabel` + `appFieldDecoration` for a raw `TextFormField` — see §3a | `app_inputs.dart` |
| search | `AppSearchField(onChanged:)` (350 ms debounce, clear, Esc; found by Ctrl+K and "/") | `app_search_field.dart` |
| select | `AppDropdown<T>(decoration: InputDecoration(labelText:), items:, value:, onChanged:)` · `AppPicker<T>(label:, value:, options:, onChanged:)` — one pick sheet | `app_kit.dart` |
| on/off | `AppSwitch` · `AppSwitchTile` (never `Switch`) | `app_switch.dart` |
| table | `AppDataTable<T>(columns:, rows:, state:, onSearch:, filters:, sortKey:, onSort:, pagination:, rowActions:)` — a real table on wide screens, cards on phones | `app_data_table.dart` |
| pagination | `AppPagination(page:, pageCount:, onPage:, total:, pageSize:)` | `app_pagination.dart` |
| card | `AppCard` · `AppActionCard` | `app_kit.dart` |
| block (D-613) | `AppBlock(tone: AppBlockTone.peach / sky / gold / emerald / paper, child:, hero:, onTap:)` · `AppBlockTone.forKey(id)` · `AppBlock.colorsOf(context)` (ink, muted, faint, `accentInk(c)`) | `app_blocks.dart` |
| KPI | `AppKpiCard(label:, value:, icon:, delta:, spark:, highlight:)` in an `AppKpiGrid` · `AppStatTile` · `AppTrendTile` | `app_kpi.dart`, `app_charts.dart` |
| status | `AppStatusBadge(label:, tone: AppTone.success)` · `AppCountBadge(count:)` · `AppBadgePill` | `app_badges.dart` |
| tabs | `AppTabs(items:, index:, onChanged:)` (pill, gradient selection) · `AppUnderlineTabs` (page sections) | `app_tabs.dart` |
| drawer | `showAppDrawer(context, title:, builder:, actions:)` — end-side panel on wide, sheet on phones | `app_overlays.dart` |
| dialog / confirm | `showAppDialog(context, title:, body:, actions:)` · `appConfirm(context, message:, danger:)` | `app_overlays.dart`, `app_kit.dart` |
| bottom sheet | `showAppSheet(context, (_) => AppSheetContent(title:, children:))` | `app_kit.dart` |
| unsaved changes | `AppUnsavedGuard(dirty: _dirty, child: …)` | `app_overlays.dart` |
| toast | `showAppNotice(text, error:)` (never a SnackBar) | `app_notice.dart` |
| charts | `AppBarChart` · `AppDonut` · `AppSparkline` · `AppTrendTile` · `AppLegend` | `app_charts.dart` |
| loading / error / empty | `AppStateView<T>(loading:, error:, data:, builder:)` · `AppLoadingState(shape:)` · `AppErrorState(onRetry:)` · `AppEmpty` · `AppListSkeleton` | `app_states.dart`, `app_kit.dart` |
| error text | `appErrorMessage(e)` (the server's message, never `'$e'`) | `app_states.dart` |
| settings page | `AppSettingsPage` + `AppSettingsGroup` / `AppSettingsTile` | `app_settings.dart` |
| role dashboard | `AppShell(items: [DashboardItem(…)])` | `app_shell.dart` |
| table export | `showAppExportSheet(context, AppTableExport(…))` | `app_table_export.dart` |

### 3a. Controls — the field and button language (system.md §4)

Buttons (`app_buttons.dart`): 48 high (`sm` 40 with a 48 hit area, `lg` 56 for a phone's hero action), radius 14,
24 px padding, the label at 15 · 600, icon 20. `primary` is the SOLID emerald (never a blue, never a decorative
gradient, no shadow), `secondary` paper with an ink hairline, `tonal` the emerald tint with emerald ink, `ghost` text
only, `danger` the danger fill (`dangerOutline:` paper + danger hairline). A press scales to 0.97 (`AppPressScale`),
keyboard focus draws `appFocusRing` — a crisp 2 px ring OUTSIDE the control with a canvas gap — and `busy:` keeps the
width (the spinner sits over the label). A disabled filled button is a flat neutral well; the others fade to 45 %.
The theme styles raw Material buttons the same way, `FilledButton.tonal` included (emerald tint, emerald ink).

Fields (`app_inputs.dart`): the label ABOVE the well (`AppFieldLabel`, 13 · 500, `required:` adds the mark), the
well = `appFieldDecoration` (warm `inputBg` fill, radius 14, hairline at rest, the 2 px ring on focus, danger hairline
on error, 48 px prefix / suffix boxes), helper and error UNDER the well, the typed text in `appFieldTextStyle` (15).
Every kit field — `AppField`, the identity fields, `AppNumberField`, `AppSearchField`, `AppDropdown` (its
`labelText` is drawn above), `AppPicker` — draws from these three, so a form is one row of wells; a raw
`TextFormField` joins by using them too. The older `MyTextField` / `MyPasswordTextField` / `MySearchBar` /
`PrimaryButton` wear the same look (their one `label` stays the placeholder because their screens draw the label).

```dart
AppField(controller: _name, label: 'name_label'.tr, hint: 'name_hint'.tr, icon: Icons.person_rounded, required: true)
AppDropdown<int>(decoration: InputDecoration(labelText: 'grade'.tr), items: items, value: grade, onChanged: setGrade)
AppSwitchTile(title: 'reminders'.tr, subtitle: 'ten_minutes_before'.tr, icon: Icons.notifications_active_rounded, value: on, onChanged: setOn)
AppButtonRow(primary: AppButton.primary(label: 'send'.tr, busy: sending, onPressed: send), secondary: [AppButton.ghost(label: 'cancel'.tr, onPressed: close)])
```

Switches: the solid emerald track when on, the hairline tone off, a paper knob with a check; a 48 × 48 target, Space /
Enter toggle it, `AppSwitchTile` is the one Tab stop of its row. Visual review: `flutter test
test/visual/kit_controls_golden_test.dart --update-goldens` renders every control and state.

## 4. Examples

A list page with server paging:

```dart
AppPageHeader(
  title: 'Payouts', icon: Icons.account_balance_wallet_rounded,
  onRefresh: p.reload, updatedAt: p.loadedAt,
  primaryAction: AppButton.primary(label: 'Export', icon: Icons.ios_share_rounded, onPressed: _export),
),
Expanded(
  child: AppDataTable<Withdrawal>(
    state: p.error != null ? AppTableState.error : p.loading ? AppTableState.loading : AppTableState.ready,
    errorText: appErrorMessage(p.error), onRetry: p.reload,
    rows: p.items,
    columns: [
      AppTableColumn.text(key: 'teacher', label: 'Teacher', text: (w) => w.teacher, primary: true, sortable: true),
      AppTableColumn.text(key: 'amount', label: 'Amount', text: (w) => money(w.amount, w.currency), numeric: true),
      AppTableColumn(key: 'status', label: 'Status', cell: (_, w) => AppStatusBadge(label: w.statusLabel, tone: w.tone)),
    ],
    onSearch: p.search, sortKey: p.sort, sortAscending: p.asc, onSort: p.setSort,
    pagination: AppPagination(page: p.page, pageCount: p.pages, onPage: p.goTo, total: p.total),
    rowActions: (w) => [AppRowAction(icon: Icons.check_rounded, label: 'Approve', onTap: () => _approve(w))],
  ),
),
```

A settings page:

```dart
AppUnsavedGuard(
  dirty: _dirty,
  child: ListView(children: [
    AppPageHeader(title: 'Devices', primaryAction: AppButton.primary(label: 'save'.tr, busy: _saving, onPressed: _dirty ? _save : null)),
    AppSection(title: 'Limits', child: AppCard(child: …)),
  ]),
)
```

A dashboard KPI row:

```dart
AppKpiGrid(children: [
  AppKpiCard(label: 'Revenue · 30 days', value: '12,480', icon: Icons.payments_rounded, delta: 0.12, spark: s, highlight: true),
  AppKpiCard(label: 'Students', value: '1,204', icon: Icons.school_rounded, delta: 0.04),
  AppKpiCard(label: 'Pending payouts', value: '3', icon: Icons.account_balance_wallet_rounded, onTap: openPayouts),
])
```

Loading, error and data in one place (a failed refresh keeps the data and shows a slim banner):

```dart
AppStateView<Overview>(loading: p.loading, error: p.error, data: p.data, onRetry: p.load,
    loadingShape: AppLoadingShape.kpis, builder: (context, d) => _Body(d))
```

## 5. Checklist for a new screen

1. `AppPageHeader` (or the role shell's header) — one title, one primary action.
2. Content on `cardBg` cards; the gradient only where §2 allows.
3. Lists of records → `AppDataTable` (wide) / cards (phone, automatic).
4. Loading = skeleton, error = `AppErrorState` with the server's message, empty = `AppEmpty`.
5. Destructive or platform-wide changes → `appConfirm(danger: true)`; settings forms → `AppUnsavedGuard`.
6. `expectNoLayoutErrors` (320 × 640 and 1400 × 900, ar + en, text × 1.3) in a test.

## 6. Motion — `app_motion_kit.dart`, `app_depth.dart` (D-580 .. D-586, D-620, D-621)

Everything plays once and stops, is driven from where it is on screen (a second toggle turns it around, never a
jump), keeps the transform the identity at rest, and parks under Reduce motion and the Super Admin's
`app.animations` switch (`appMotionOff(context)`). Curves: `AppEase.out` for entrances and exits, `AppEase.drawer` for
sheets; never ease-in on UI. One orchestrated entrance per screen, not a fade-up on every section.

| Need | Use | Notes |
|---|---|---|
| a number | `AppCountUp(value, memoryKey:)` | counts once, glides on a change, the reader hears the final value |
| a key figure (streak, points, score) | `AppOdometer(value, memoryKey:)` = `AppCountUp(roll: true)` | digits roll with a drum perspective, tabular, one per block |
| progress / chart / press | `AppFill` · `AppDrawIn` · `AppPressScale` | |
| list entrance | `AppReveal(index:, group:)` | first 8 items, once per route |
| hero surface 3D | `AppTilt(glare: true)` + `AppTiltLayer` | hero blocks only |
| a card in a scrolling list | `AppTilt.subtle(child:)` | 2°, no glare, touch = press depth only, no layout while moving |
| a cover in a list | `AppParallaxImage(image:)` | ≤ 8 px drift, paint only; give it a bounded box and a `BoxFit.cover` picture |
| quiz answer / flashcard | `AppFlip3D(front:, back:, flipped:)` | spring, turns toward the reading end, the reader hears the visible face; crossfade under Reduce motion |
| lesson / accordion | `AppExpandCard(header:, child:, expanded:, onExpandedChanged:)` | 48 px header button with expanded state, Enter / Space |
| feedback panel | `AppSlideIn(visible:, child:, from: AppSlideFrom.bottom)` | 260 ms in, 180 ms out; put it where it may overlap |
| sheet | `showAppSheet` | 280 ms in / 200 ms out (`AppEase.sheet`), drag catches it mid-way, fling dismisses |

```dart
AppFlip3D(flipped: _revealed, front: _QuestionCard(q), back: _AnswerCard(q))
AppExpandCard(header: Text(lesson.title, style: AppType.row(context)), child: _LessonBody(lesson))
Stack(children: [list, Align(alignment: Alignment.bottomCenter, child: AppSlideIn(visible: _checked, child: _Feedback(ok)))])
AspectRatio(aspectRatio: 16 / 9, child: AppParallaxImage(image: Image.network(url, fit: BoxFit.cover)))
AppOdometer('$points', memoryKey: 'home.points', style: AppType.figureLarge(context))
```
