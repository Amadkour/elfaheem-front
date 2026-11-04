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
| `AppSpace` | xxs 4 · xs 8 · sm 12 · md 16 · lg 24 · xl 32 · xxl 48 · `gutter(width)` | padding, gaps (`AppSpace.gapMd`) |
| `AppRadius` | chip 10 · card 16 · sheet 24 · hero 32 | corners (`AppRadius.cardAll`) |
| `AppElevation.of(context, level)` | 0 flat · 1 card · 2 raised · 3 overlay · 4 modal | shadows; `AppElevation.border` adds the dark-mode hairline |
| `AppShadow` | card · raised | the theme's two named shadows |
| `AppMotion.of(context)` | fast 180 · base 220 · slow 300 ms, zero under Reduce motion | every animation |
| `AppTouch` | min 48 · primary 56 | hit areas |
| `AppIconSize` | xs 14 · sm 16 · md 20 · lg 24 · xl 32 · hero 40 | icons |
| `AppBorder` | hairline 1 · strong 1.5 · focus 2 | borders, focus rings |
| `AppType` | see below | text |

**Type scale** (`AppType.x(context)`; weights w400–w600, D-102; Arabic and English share sizes, the theme gives Arabic
body text its taller line):

| Role | Size / weight | For |
|---|---|---|
| `display` | 28 · 600 | a dashboard greeting |
| `headline` | 22 · 600 | a hero title |
| `pageTitle` | 20 · 600 | the page header |
| `section` | 16 · 600 | section headings, card titles |
| `body` / `bodyStrong` | 14 · 400 / 600 | paragraphs |
| `row` | 14 · 500 | list and table rows |
| `label` | 13 · 500 | field labels, buttons sm |
| `meta` | 12 · 400 muted | secondary lines, timestamps |
| `overline` | 11 · 600 | small caps-like labels above a figure |
| `figure` / `figureLarge` | 17 / 28 · 600, tabular digits | numbers in tiles / KPI cards |

**Colours** are roles on `context.colors`: surfaces (`background`, `surface`, `cardBg`, `cardBg2`, `inputBg`,
`divider`), ink (`textDark`, `textMedium`, `textLight`), brand (`primary`, `primaryDark`, `primaryLight`,
`accent`, `accent2`), status (`success`, `warning`, `danger` + `*Tint`), on-gradient ink (`onHero`,
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
| buttons | `AppButton.primary / secondary / tonal / ghost / danger(label:, onPressed:, icon:, busy:)` · `AppIconButton(icon:, tooltip:, badge:)` · `AppButtonRow(primary:, secondary:)` | `app_buttons.dart` |
| text input | `AppField` · `AppEmailField` / `AppPasswordField` / `AppPhoneField` / `AppUrlField` | `app_kit.dart`, `app_inputs.dart` |
| search | `AppSearchField(onChanged:)` (350 ms debounce, clear, Esc; found by Ctrl+K and "/") | `app_search_field.dart` |
| select | `AppDropdown<T>` · `AppPicker<T>` | `app_kit.dart` |
| on/off | `AppSwitch` · `AppSwitchTile` (never `Switch`) | `app_switch.dart` |
| table | `AppDataTable<T>(columns:, rows:, state:, onSearch:, filters:, sortKey:, onSort:, pagination:, rowActions:)` — a real table on wide screens, cards on phones | `app_data_table.dart` |
| pagination | `AppPagination(page:, pageCount:, onPage:, total:, pageSize:)` | `app_pagination.dart` |
| card | `AppCard` · `AppActionCard` | `app_kit.dart` |
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
