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

## 2. The gradient — `app_gradients.dart`, `app_mesh.dart` (D-136, D-180, D-622)

The brand gradient is ONE family — `primary_light → primary → primary_dark`, derived from the live primary so every
preset keeps working; no hue turn at either end, no gold glow (D-622) — and every stop keeps white ink at WCAG AA.
The mesh (`AppMeshSurface`) is the same family with soft lights of
that one hue, never a second colour. It is a **touch**:

- ✓ key chart series, a hero surface a screen still asks for (`AppGradientSurface`)
- ✗ a role home's greeting / welcome hero: that is a tinted **block** (`HomeHeader` = `AppBlock(hero: true)`, peach
  for students and parents, sky for instructors, admins and organizations, charcoal ink, the name in `AppType.display`)
- ✗ not the page headers any more (D-614): `AppHeader` / `AppPageHeader` sit on the canvas with a 2 px SOLID primary
  `AppHeaderStrip`, and the selected pill tab is solid primary; the primary button is solid emerald (§3a) and the ONE
  highlighted KPI is a block (D-612); the shell's sidebar is paper with a solid emerald pill on the open tab
- ✗ never behind body text, forms, lists or tables · never two gradient fills side by side · never the legacy
  accent / teal / gold gradient getters in new UI
- ✓ D-1081 (the soft wash, owner pick A2), two deliberate exceptions read from `AppBrandLayer`: every `AppStatCard`
  wears its tone's tint (emerald · peach · sky · gold) fading into the card (`statWash`), and the ONE main card of a
  screen gets a thin primary → gold edge (`AppCard(highlight: true)` / `AppHighlightEdge`, `highlightEdge`) — never
  two highlighted cards on a screen, never a wash behind a list, form, table or settings row

```dart
HomeHeader(name: user.name, subtitle: homeDaySummary(…), actions: [...])  // the hero block; tone: from the role
AppGradientSurface(child: Text('Revenue', style: AppType.section(context)))  // ONE highlighted KPI, onHero ink
const AppAccentStrip()                                    // 3 px brand line on top of a header / card
AppGradientText('12,480')                                 // ONE key figure (plain primary in high contrast)
AppGradients.chart(context)                               // a bar / area fill
```

The boot splash (`boot_splash.dart`) follows the same rule: the native cream canvas (emerald in dark mode, frame 1
equals the OS splash), the app's name as an editorial wordmark under the mark, warm emerald / gold / peach lights,
charcoal ink — no blue, no mint.

## 3. Components

| Need | Use | File |
|---|---|---|
| page header (D-614) | `AppPageHeader(title:, subtitle:, icon:, primaryAction:, actions:, search:, onRefresh:, updatedAt:, bottom:)` — an editorial masthead on the canvas: `AppHeaderStrip` (2 px primary) · title in `AppType.pageTitle` in ink, 24 above / 16 below (8 / 8 collapsed) · back and chrome as paper chips · the ONE primary action bare, secondary actions on an `AppHeaderTray` · `AppHeaderRule` under it (underline tabs close it themselves) | `app_page_header.dart` |
| app bar | `AppHeader(title:, subtitle:, actions:, bottom:, color:, compact:)` — the same masthead as a `Scaffold.appBar`, collapsing with the body's scroll; `color:` is the strip's colour; a `leading:` sits on the canvas, so draw it in ink or as a `ChromePlate` | `app_header.dart` |
| section | `AppSection(title:, subtitle:, trailing:, child:, spaceAbove:)` — brings its own `AppSpace.sectionHead` rhythm (32 above the heading, 12 under it): put NO gap before it; `spaceAbove: false` for the first section of a surface with its own top padding | `app_page_header.dart` |
| chrome chip | `ChromePlate(onTap:, child:)` (40 px paper plate in a 48 px target, glass inside a `ChromeBar` or with `onHero: true`, press depth) · `ChromeIconButton(icon:, label:, onTap:, badge:, busy:)` · `AppBackButton(onPressed:, onHero:)` | `chrome_button.dart`, `app_back_button.dart` |
| refresh | `AppRefresh(onRefresh:, child:)` (pull, emerald on paper) · `AppRefreshAction(onRefresh:, always:)` (the 48 px icon button for mouse platforms; a spinner while it runs) | `app_refresh.dart` |
| buttons | `AppButton.primary / secondary / tonal / ghost / danger(label:, onPressed:, icon:, busy:)` · `AppIconButton(icon:, tooltip:, badge:)` · `AppButtonRow(primary:, secondary:)` — see §3a | `app_buttons.dart` |
| text input | `AppField(controller:, label:, hint:, icon:, helper:, errorText:)` · `AppEmailField` / `AppPasswordField` / `AppPhoneField` / `AppUrlField` · `AppFieldLabel` + `appFieldDecoration` for a raw `TextFormField` — see §3a | `app_inputs.dart` |
| search | `AppSearchField(onChanged:)` (350 ms debounce, clear, Esc; found by Ctrl+K and "/") | `app_search_field.dart` |
| select | `AppDropdown<T>(decoration: InputDecoration(labelText:), items:, value:, onChanged:)` · `AppPicker<T>(label:, value:, options:, onChanged:)` — one pick sheet | `app_kit.dart` |
| on/off | `AppSwitch` · `AppSwitchTile` (never `Switch`) | `app_switch.dart` |
| table | `AppDataTable<T>(columns:, rows:, state:, onSearch:, filters:, sortKey:, onSort:, pagination:, rowActions:)` — on wide screens one paper surface: the header in the label role, rows parted by warm hairlines, the input tone under the pointer, the primary tint on a selected row; on phones every row is its own paper card on the canvas (D-612) | `app_data_table.dart` |
| pagination | `AppPagination(page:, pageCount:, onPage:, total:, pageSize:)` — pills: the current page filled with the primary, previous / next outlined | `app_pagination.dart` |
| card (D-612) | `AppCard(child:, padding:, onTap:)` · `AppActionCard(icon:, title:, subtitle:, badge:, trailing:)` — paper: the card surface on a warm hairline, radius `card`, no resting shadow, a tappable card presses in; the icon's tint carries the colour, never a wash | `app_kit.dart` |
| block (D-613) | `AppBlock(tone: AppBlockTone.peach / sky / gold / emerald / paper, child:, hero:, onTap:)` · `AppBlockTone.forKey(id)` · `AppBlock.colorsOf(context)` (ink, muted, faint, `accentInk(c)`) | `app_blocks.dart` |
| home hero (D-622) | `HomeHeader(name:, subtitle:, actions:, shellActions:, contextSwitcher:, tone:)` · `HomeHeroCard(child:, tone:)` with `HomeHeroTag` / `HomeDayRibbon` / `HomeHeroFigure` in the block's ink (`homeOnHero`) | `home_kit.dart` |
| KPI | `AppKpiCard(label:, value:, icon:, delta:, spark:, highlight:, tone:)` in an `AppKpiGrid` — the ONE `highlight` is an `AppBlock` (peach by default; `tone:` gold for a streak / top score, emerald for something completed) whose figure rolls (`AppOdometer`) and leans under the pointer (`AppTilt.subtle`); the others are paper and count up once · `AppStatTile(icon:, label:, value:)` (paper, two per row on phones) · `AppTrendTile` | `app_kpi.dart`, `app_kit.dart`, `app_charts.dart` |
| status | `AppStatusBadge(label:, tone: AppTone.success)` (a full pill on an opaque tint, the label flexes; `success` = emerald, `gold` = achievements / top marks only) · `AppCountBadge(count:)` · `AppBadgePill` · `appTintOn(context, tone)` / `appInkOn(context, tone, tint)` for a tone as text on its own tint (AA, hue kept; small marks) · `c.primaryWash` / `appWashOn(context, tone)` behind a LARGE surface: a selected card or row, a note, a summary box (D-728, never a raw primary alpha) | `app_badges.dart` |
| tabs | `AppTabs(items:, index:, onChanged:, expand:)` (a pill track on the input surface; the chosen pill solid primary with the on-hero ink, never the gradient's teal) · `AppUnderlineTabs` (page sections: labels in ink, a 2 px ink rule under the chosen one); arrow keys move the selection, the track shows the focus ring | `app_tabs.dart` |
| drawer | `showAppDrawer(context, title:, builder:, actions:)` — a floating paper panel (radius 28, editorial headline, the warm scrim) that slides in from the end edge on wide windows, a sheet on phones | `app_overlays.dart` |
| dialog / confirm | `showAppDialog(context, title:, body:, actions:, icon:, danger:)` · `appConfirm(context, message:, danger:, confirmLabel:)` — paper, radius 28, the warm scrim, `AppPopIn`; the dialog has an editorial headline beside a tinted mark, the confirm a centred mark, the message and Cancel · Confirm | `app_overlays.dart`, `app_kit.dart` |
| sheet | `showAppSheet(context, (_) => AppSheetContent(title:, tone:, icon:, children:))` — sized to its content: a centred paper dialog on wide windows (at most 85 % high, scrolls inside), a bottom sheet with a drag handle on phones (D-710); `mode: AppSheetMode.side` keeps the full-height end-side panel for real editors / detail panels only (`dialog` / `bottom` force one place). The header (`AppSheetHeader`, admin `SheetHeader`) is a tinted band in a tone — `brand` (default) · `info` (imports, exports, details: violet) · `success` · `warning` · `danger` (delete) · `neutral` (filters) — with an optional icon well (D-711). `showAppModalSheet(context:, builder:)` takes `showModalBottomSheet`'s arguments and keeps the kit's corners, scrim (`appScrimColor`) and motion | `app_kit.dart`, `app_side_sheet.dart`, `app_sheet_header.dart` |
| unsaved changes | `AppUnsavedGuard(dirty: _dirty, child: …)` | `app_overlays.dart` |
| toast | `showAppNotice(text, error:, actionLabel:, onAction:)` (never a SnackBar) — ink on paper with an emerald / danger mark; slides down from the top edge and leaves the same way; a drag up or a flick dismisses it | `app_notice.dart` |
| charts | `AppBarChart` · `AppDonut` · `AppSparkline(values, surface:)` · `AppTrendTile` · `AppLegend` — `appChartPalette` is emerald · peach · sage · gold · terracotta from the live theme (never the `purple` role, D-632), snapped into the lightness band; every chart draws in once (`AppDrawIn`) | `app_charts.dart` |
| loading / error / empty | `AppStateView<T>(loading:, error:, data:, builder:)` · `AppLoadingState(shape:)` · `AppErrorState(onRetry:)` · `AppEmpty(icon:, title:, message:, actionLabel:, onAction:, tone:)` — a drawn plate (`AppStatePlate`, CustomPaint in the theme's colours, never stock art or emoji), an editorial headline (`AppType.section`), one line of direction and ONE action · `AppListSkeleton` / `AppSkeletonBox` (warm bones) | `app_states.dart`, `app_kit.dart` |
| error text | `appErrorMessage(e)` (the server's message, never `'$e'`) | `app_states.dart` |
| settings page | `AppSettingsPage(header:, groups:, footer:)` + `AppSettingsGroup(title:, icon:, children:, danger:)` (an editorial group heading — `AppType.section` in ink, a quiet glyph — with 32 above it over the white card: one soft shadow, hairline dividers, D-632) / `AppSettingsTile(icon:, label:, subtitle:, color:, badge:, trailing:, onTap:)` (48 px rows, a faint icon well) · `AppSettingsHeader` (the profile hero: the page's one tinted block, peach) | `app_settings.dart` |
| role dashboard | `AppShell(items: [DashboardItem(…, badgeTone: ShellBadgeTone.reward)])` | `app_shell.dart` |
| pins + tab colours | nothing to add: every `AppHeader` / `AppPageHeader` / `OrgPageHeader` on a page opened inside a tab draws `ShellPinButton(title:)`; `AppShell(pinScope:)` names an organization's dashboard, `DashboardItem.prefKey` a stable key for a translated label (D-1170) | `shell_pins.dart` |
| greeting hero (D-631) | `AppGreetingHero(greeting:, summary:, avatar:, initials:, ring:, cta: AppGreetingHeroButton(label:, onTap:, icon:), actions:, illustration:, footer:, centered:)` — the forest card of a home (time chip, avatar in a progress ring, the greeting in the display face, one line, ONE paper pill); `HomeHeader(…, greetingHero: true, ring:, cta:, centered:)` draws a home's header as one | `app_dashboard_kit.dart`, `home_kit.dart` |
| stat card (D-631, soft wash D-1081) | `AppStatCard(icon:, value:, label:, tone:, footer:, delta:, bars:, barsCaption:, warn:)` — the tone's tint fading into the card, the icon chip and label on top, the figure (danger ink with `warn`, muted at 0) with its hint line, an optional `AppMiniBars` of the last 8 values at the end; four in an `AppKpiGrid` | `app_dashboard_kit.dart` |
| KPI · ring (D-631) | `AppKpiSpark(label:, value:, values:, icon:, delta:, tone:)` (figure + sparkline) · `AppRingStat(label:, value:, progress:, caption:, delta:, tone:)` (text + a ring with its percentage) | `app_dashboard_kit.dart` |
| shortcuts (D-631) | `AppShortcutGrid(children: [AppShortcutTile(icon:, label:, onTap:, tone:, badge:, subtitle:)])` — label on top, a large soft icon in a tinted disc at the bottom end; 2 columns on phones, 4 wide | `app_dashboard_kit.dart` |
| section card (D-631) | `AppSectionCard(title:, subtitle:, actions:, tabs: AppTabs(…), child:)` — a paper card with a header row and a period-tabs slot · `AppBreadcrumb(parts:)` (text only) | `app_dashboard_kit.dart` |
| where am I | `ContextSwitcher()` · `ContextPill(icon:, tone:, label:, onTap:)` · `showContextSwitcherSheet` | `context_switcher.dart` |
| roadmap / journey (D-994) | `AppRoadmap(nodes: [AppRoadmapNode(title:, state: AppRoadmapState.done / current / todo / warn, subtitle:, caption:, actionLabel:, onAction:, onTap:)], dense:, axis:, label:)` — connected nodes on one rail (the course roadmap's language): vertical on phones, a row on a box ≥ 720 with ≤ 6 nodes; a state is icon + colour + word, never colour alone; the next node (first current → warn → to do) is the path's one emerald block with its button, the nodes after it quieter; the walked line fills in once (`AppFill`, still under Reduce motion); each node reads "Step 2 of 5, Departments, Done" · `AppStatusPath.request(reached: 0..2, times:)` (one request: submitted → reviewed → decided, three dots on a line) | `app_roadmap.dart` |
| attention count | `AttentionBadge(tabKey: AttentionTabs.x, child: …)` (tappable, opens the items) | `attention_badge.dart` |
| language | `AppLanguageTile()` · `AppLanguageSegmented(current:, onChanged:)` | `app_language_switch.dart` |
| table export | `showAppExportSheet(context, AppTableExport(…))` | `app_table_export.dart` |

**Premium dashboard (D-631).** The wide shell now draws the sidebar's tabs in two groups ("General": the home tab;
"Workspace": the rest), each under a soft tinted header with one line, the open tab a TINTED pill (an opaque blend of
the primary into the paper) in the primary ink with its count, and a ghost button that folds the sidebar to its icons
(`appSidebarCollapsed`). The top bar is a paper band: the search box (only when the screen has an
`AppCommandPaletteScope`, and it opens that palette), ghost chrome buttons (`ChromeGhost`) with small counts, a hairline
and the signed-in person (avatar, name, role). Under it the page head: the tab's title in `AppType.pageTitle` at the
start, `AppBreadcrumb` at the end from 640 px. The phone's open tab is a tinted pill with the primary ink. Headings
are Amiri (Arabic) and Playfair Display (Latin), figures stay in the sans. The text below describes the shell before
D-631 where it differs.

**The canvas** (`app_canvas.dart`, D-949): `BasePage` paints a light tint of the sidebar colour (`AppCanvas.sidebarColour`, the
colour `BrandLayer` paints the sidebar with) under a whisper of the sidebar's diamond lattice; dark mode is a deep tint of
the same hue. `context.colors.background` IS that tint. A header block must step off it, not match it: the identity block
starts on `AppCanvas.raised`, a washed header ends on the paper, and tinted blocks keep a hairline of their tone.

**The role shell** (`app_shell.dart`, D-062) wears the editorial theme like this: the page is the canvas; the
sidebar (wide) and the rail (tablet) are a PAPER column (`cardBg`) set off by one warm hairline — never a gradient
and never a dark slab that would compete with the page's hero block; the open tab is an emerald pill (`primary`,
on-hero ink) at 48 px; the top bar is the canvas itself with the tab's title in `AppType.pageTitle` and the chrome
buttons as paper squares (`ChromeIconButton` outside a `ChromeBar`); the phone's bottom bar is paper with a hairline,
the open tab an emerald 56 × 32 pill under its label, no shadow. A tab's count is a small pill in the colour of its
meaning (`ShellBadgeTone.attention` = danger, `reward` = the gold tint with gold ink); on the open tab it turns to
glass so red never sits on green; it pops once when the number changes (`AppBump`). The context pill is paper with a
hairline (the organization's colour lives in its mark only), its "Personal" exit an emerald-tinted pill; the language
switch is a track in `inputBg` with an emerald thumb.

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
2. Content on white `AppCard`s on the tinted page (one soft shadow, no visible border, D-632); colour in `AppBlock`s, at most two or three tones a screen; the gradient only where §2 allows.
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
| sheet | `showAppSheet` | 280 ms in / 200 ms out (`AppEase.sheet`), drag catches it mid-way, fling dismisses; the drawer and the side panel slide the same 280 / 200 on `AppEase.out`; the dialog sheet fades and grows from 96 % in 220 ms |
| dialog / confirm | `showAppDialog` · `appConfirm` | the panel settles from 96 % (`AppPopIn`, 240 ms) while the route fades the warm scrim |
| toast | `showAppNotice` | 260 ms down from the top edge on `AppEase.out`, 180 ms back up; a drag follows the finger 1:1 (friction below rest) and a flick or half its height dismisses it |

```dart
AppFlip3D(flipped: _revealed, front: _QuestionCard(q), back: _AnswerCard(q))
AppExpandCard(header: Text(lesson.title, style: AppType.row(context)), child: _LessonBody(lesson))
Stack(children: [list, Align(alignment: Alignment.bottomCenter, child: AppSlideIn(visible: _checked, child: _Feedback(ok)))])
AspectRatio(aspectRatio: 16 / 9, child: AppParallaxImage(image: Image.network(url, fit: BoxFit.cover)))
AppOdometer('$points', memoryKey: 'home.points', style: AppType.figureLarge(context))
```

## 7. The redesign kit (phase 1, D-1811, `docs/redesign/KIT_SPEC.md`)

- **Colours.** `context.colors.kit` (`KitColors`, `lib/config/theme/kit_palette.dart`) carries the roles the old theme
  lacks: `area(AppArea.x)` / `role(AppRoleAccent.x)` (a `KitSet`: hero stops, button stops and ink, tint, ink),
  `accent(AppAccent.x)`, `subject(key)` (`subjectColors(context, serverSubject)`, `app_subject_colors.dart`), `live`,
  `ok`, `warn`, `error`, `lock`, `well`, `track`, `line`, `fieldEdge`. The values come from the theme response's
  `colors.kit`, else `kKitPaletteDefaults` (copied from `tool/redesign/kit_palette.json`). Old getters keep their
  meaning; never search-and-replace `c.primary` with `c.kit.primary`.
- **Scope.** A page (or shell tab) sets ONE `AppAreaScope(area: …)` (student) or `AppAreaScope.role(role: …)`; the hero,
  buttons, selected states, empty plates and the motion budget read `AppAreaScope.of(context)`. `AppShell` sets the
  role scope from the signed-in role.
- **Components.** `AppHero` (+ `AppHeroStat`, `AppHeroSurface`, `AppHeroOverlap`), `AppCard(variant:)`,
  `AppButton.hot` (the forward button, one per student screen), `AppTile` / `AppIconBox` / `AppRules`,
  `AppProgressRing`, `AppCountdown`, `AppChip`, `AppSuccess`, `AppLiveTag`, `AppLiveBanner`.
- **Motion M1–M16** (`lib/design/motion/`, exported through `app_motion_kit.dart`): `AppFlipIn`, `AppInkPath` /
  `AppInkRing` / `AppInkCheck`, `AppPop`, `AppSlap`, `AppDeal`, `AppWipe` / `AppWipeSwitcher`, `AppSquiggle`,
  `AppBreathe`, `AppJelly`, `AppOdometer` (M10), `AppBurst.fire`, `AppWobble`, `AppMorphPill`, `appPeekSheetStyle`,
  `AppFeedback`, `AppDriftShapes`, and the `.mFlip(i)`-style shorthands. Each one-shot move plays once per route,
  asks the screen's `AppMotionBudget` (one hero-move kind, 12 / 24 entries, 1.2 s window, 3 loops) and draws its end
  state under Reduce motion; the playful moves only run under a student area scope.
- **Gallery.** `/kit_gallery` (super admin / developer; every role in debug builds; kill switch `admin.kit_gallery`)
  shows every role, component and move under switchable area, role, dark, direction, Reduce motion, text scale and
  width.
- **Gate.** `test/ui/kit_rules_test.dart` also counts colour literals in `lib/design/**` against
  `test/ui/kit_hex_baseline.json` (only down; zero in a new file). Hex lives in `kit_palette_defaults.dart` and
  `app_theme.dart` only.
