// lib/design/app_kit.dart
//
// THE premium component kit of the whole app — one import for every role (student · teacher · parent · admin ·
// organization):
//
//     import 'package:flutter_education_app/design/app_kit.dart';
//
// It is the Data Lab design language (theme radii & shadows, gradient hero with glass stats, tinted pills,
// calm banners, skeleton shimmer instead of spinners) + the organization kit (cards, stat tiles, empty states,
// picker, audience/permission inputs), under role-neutral names. Everything reads the LIVE theme
// (context.colors), and raw Material widgets are styled by ThemeConfigProvider.materialTheme(), so a screen built
// from these pieces looks the same in every role and follows the theme the super admin picks.
//
// The full system (tokens, type scale, gradient rules, every component with examples): lib/design/README.md.
//
// Rule of thumb for new screens:
//   dashboard page   → AppPageHeader + AppSection      records       → AppDataTable (cards on phones by itself)
//   actions          → AppButton.primary / secondary / tonal / ghost / danger · AppIconButton
//   KPIs             → AppKpiGrid(AppKpiCard …, one highlight: true)   status → AppStatusBadge(tone:)
//   tabs             → AppTabs / AppUnderlineTabs      side panel    → showAppDrawer · dialog → showAppDialog
//   load / error     → AppStateView / AppErrorState (appErrorMessage(e), never '$e') · AppUnsavedGuard on forms
//   page header      → AppHeader (Scaffold / BasePage appBar: gradient, collapses by itself) · AppBackButton
//   big intro card   → AppHero(+ AppHeroStat)        section title → AppSectionTitle
//   any number       → AppNumberField(controller:, label:, min:, max:, step:)   gradient → AppGradients / AppMeshSurface
//   content block    → AppCard (paper: tone + warm hairline, radius 16, no shadow) · AppActionCard (icon, title,
//                      one sentence, a count) — a tinted container for one subject is AppBlock (radius 24)
//   numbers          → AppStatTile in an AppGrid (paper) · the page's ONE key figure → AppKpiCard(highlight: true)
//   nothing yet      → AppEmpty (a drawn plate, an editorial headline, one action; app_states.dart)
//   loading          → AppListSkeleton / AppSkeletonBox in an AppShimmer (warm bones, never a spinner)
//   tip / warning    → AppBanner                       quick actions → AppPill
//   form             → AppField / AppPicker / AppSwitchRow / AppPrimaryButton
//   on/off toggle    → AppSwitch / AppSwitchTile (the ONLY switch look in the app — never Switch/SwitchListTile)
//   any time / date  → AppTime.time / date / dateTime (UTC instant) · AppTime.clock("HH:MM") (12h/24h + timezone)
//   sheet / confirm  → showAppSheet / appConfirm       status        → AppBadgePill
//   sheet content    → AppSheetContent(title:, children: […])  (header + side-padded, scrolling body; showAppSheet
//                      itself draws no padding)
//   table export     → showAppExportSheet(context, AppTableExport(...))  (Excel · Word · PDF + column picker)
//   wide table/grid  → AppHScroll(child: …)  (draggable scrollbar · mouse drag · shift+wheel)
//   pull-to-refresh  → AppRefresh(onRefresh: provider.load, child: ListView(…)) + AppRefreshAction(onRefresh: …)
//                      in the app bar for mouse users (app_refresh.dart) — never a RefreshIndicator by hand
//   "needs attention"→ AttentionBadge(tabKey: AttentionTabs.x, child: …) (count + deep links, GET /me/attention)
//   role dashboard   → AppShell(width:, currentIndex:, onTap:, items: [DashboardItem(…, attentionKeys:)]) — the one
//                      sidebar / rail / bottom-bar shell, badges resolved at the leaf (app_shell.dart, D-062)
//   chart / trend    → AppTrendTile(label:, value:, delta:, spark:) · AppBarChart(series:, labels:) · AppDonut(parts:)
//                      · AppSparkline(values) · AppLegend — pure CustomPaint, theme palette (app_charts.dart, D-063)
//   More / settings  → AppSettingsPage(header: AppSettingsHeader(…), groups: [AppSettingsGroup(children: [AppSettingsTile(…)])])
//                      (search past 8 tiles, kill-switch per tile; app_settings.dart)
//   keyboard (web)   → nothing to do: Enter walks a form and presses its primary button, Ctrl+Enter submits a
//                      multi-line field, Esc leaves it, Ctrl+K / "/" jumps to the search box (app_keyboard.dart).
//                      EnterSubmits(onSubmit: …) / EnterSubmits.none decide it by hand for the fields inside.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_badges.dart';
import 'app_motion_kit.dart';
import 'app_tokens.dart';
import '../features/admin/admin_common.dart' as admin;
import '../features/org/org_ui.dart' as org;
import '../features/teacher/data_lab/data_lab_widgets.dart' as dl;

// The design system (D-180, lib/design/README.md): tokens, the gradient rules and the components added on top of
// the Data Lab / org kits below.
export 'app_tokens.dart';
export 'app_blocks.dart';
export 'app_gradients.dart';
export 'app_buttons.dart';
export 'app_badges.dart';
export 'app_tabs.dart';
export 'app_search_field.dart';
export 'app_pagination.dart';
export 'app_data_table.dart';
export 'app_states.dart';
export 'app_overlays.dart';
export 'app_kpi.dart';
export 'app_page_header.dart';
export 'app_header.dart';
export 'app_back_button.dart';
export 'app_side_sheet.dart';
export 'app_depth.dart';
export 'app_focus_mode.dart';
export 'app_number_field.dart';
export 'app_notice.dart' show showAppNotice;
export 'app_switch.dart';
export 'app_refresh.dart';
export 'app_shell.dart';
export 'app_charts.dart';
export 'app_settings.dart';
export 'app_keyboard.dart' show EnterSubmits;
export 'attention_badge.dart';
export '../core/attention/attention_service.dart' show AttentionService, AttentionTabs, AttentionItem;
export 'app_hscroll.dart';
export 'app_responsive.dart' show AppWidthBox;
export 'app_table_export.dart' show showAppExportSheet, exportAppTable, AppTableExport, AppExportColumn, AppColType, AppColAlign, AppTotal, AppExportFormat, AppStatusTone, bilingualExport;
export '../core/app_time.dart';
export '../features/org/org_ui.dart'
    show hexColor, statusColor, statusLabel, priorityColor, priorityLabel, relTime, permsFromJson, permsToJson,
        fileSizeLabel;

// ── Data Lab language ───────────────────────────────────────────────────────
typedef AppHero = dl.DlHero;
typedef AppHeroStat = dl.DlHeroStat;
typedef AppPill = dl.DlActionPill;
typedef AppProgressBar = dl.DlBar;
typedef AppRing = dl.DlRing;
typedef AppAvatar = dl.DlAvatar;
typedef AppTag = dl.DlTag;
typedef AppSectionTitle = dl.DlSectionTitle;
typedef AppPrimaryButton = dl.DlPrimaryButton;
typedef AppField = dl.DlField;
typedef AppChoiceChip = dl.DlChoiceChip;
typedef AppStatChip = dl.DlStatChip;
typedef AppShimmer = dl.DlShimmer;
typedef AppBanner = dl.DlBanner;

/// One text style helper for the whole app (same as the Data Lab's).
TextStyle appText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) => dl.dlText(size, w: w, c: c, h: h);

/// Traffic-light colour for 0–100 (grades, completion, attendance …).
Color appScoreColor(BuildContext context, double? v) => dl.dlScoreColor(context, v);

// ── Organization kit (role-neutral names) ──────────────────────────────────
typedef AppGrid = org.OrgGrid;
typedef AppBadgePill = org.OrgPill;
typedef AppInfoRow = org.OrgInfoRow;
typedef AppAsync = org.OrgAsync;
typedef AppSwitchRow = org.OrgSwitchRow;
typedef AppPicker<T> = org.OrgPickField<T>;
typedef AppAudiencePicker = org.OrgAudiencePicker;

// ── Sheets, confirmations, toasts ──────────────────────────────────────────
Future<T?> showAppSheet<T>(BuildContext context, Widget Function(BuildContext) builder) =>
    admin.showAdminSheet<T>(context, builder);

Future<bool> appConfirm(BuildContext context, {required String message, bool danger = false, String? confirmLabel}) =>
    admin.confirm(context, message: message, danger: danger, confirmLabel: confirmLabel);

void appToast(String message, {bool error = false}) => admin.toast(message, error: error);

typedef AppSheetHeader = admin.SheetHeader;

/// A sheet's whole content: its [AppSheetHeader] and a body with the kit's side padding (in line with the header's
/// title) that scrolls when it is taller than the sheet. `showAppSheet` draws no padding of its own — a body put
/// straight under the header touches the sheet's edges — so a sheet is `showAppSheet(context, (_) =>
/// AppSheetContent(title: …, children: […]))`. Pumped on its own (a layout test, unbounded height) the body simply
/// takes its height.
class AppSheetContent extends StatelessWidget {
  const AppSheetContent({super.key, required this.title, required this.children, this.headerTrailing});

  final String title;
  final List<Widget> children;
  final Widget? headerTrailing;

  /// The body's padding: the header title's start inset on both sides, a section gap under the last widget.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(AppSpace.md + AppSpace.xxs, 0, AppSpace.md + AppSpace.xxs, AppSpace.lg);

  @override
  Widget build(BuildContext context) {
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return LayoutBuilder(builder: (context, box) {
      final header = AppSheetHeader(title, trailing: headerTrailing);
      if (!box.maxHeight.isFinite) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Padding(padding: padding, child: body),
        ]);
      }
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Flexible(child: SingleChildScrollView(padding: padding, child: body)),
      ]);
    });
  }
}

// ── Cards (Warm Editorial, system.md §4: paper on a warm hairline, radius 16, no resting shadow) ───────────────

/// The paper card: the card surface on a warm hairline (depth is tone first, D-612 — a resting card casts no
/// shadow), corner radius `card`. A tappable card presses in (D-582) and ripples.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpace.card,
    this.margin,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// A long press (e.g. starts a selection); null: none.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tappable = onTap != null || onLongPress != null;
    final body = Padding(padding: padding, child: child);
    return AppPressScale(
      enabled: tappable,
      child: Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: tappable ? InkWell(onTap: onTap, onLongPress: onLongPress, child: body) : body,
        ),
      ),
    );
  }
}

/// A tappable card that leads somewhere: a tinted icon, a title, one human sentence, a count. The icon's tint
/// carries the colour (never a wash over the card), the chevron mirrors by itself.
class AppActionCard extends StatelessWidget {
  const AppActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.badge = 0,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The icon's tone (the primary by default).
  final Color? color;

  /// A count over the icon (0 = none).
  final int badge;
  final VoidCallback? onTap;

  /// Replaces the chevron (a pill, a switch); at most 150 px wide.
  final Widget? trailing;

  static const double _iconBox = AppTouch.min - AppSpace.xxs;
  static const double _trailingMax = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final tint = appTintOn(context, col);
    final iconBox = Container(
      width: _iconBox,
      height: _iconBox,
      decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
      child: Icon(icon, size: AppIconSize.lg, color: appInkOn(context, col, tint)),
    );
    return AppCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppCountBadge(count: badge, child: iconBox),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs / 2),
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
        if (trailing != null)
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: _trailingMax), child: trailing) // a long pill ellipsizes
        else
          Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    );
  }
}

/// A small counter tile on paper (two per row on phones, a strip on wide screens): a tinted icon, the figure
/// (counts up once, D-581) and a two-line label. The page's one key figure is an [AppKpiCard] with `highlight`.
class AppStatTile extends StatelessWidget {
  const AppStatTile({super.key, required this.icon, required this.label, required this.value, this.color, this.onTap});

  final IconData icon;
  final String label;

  /// A number or an already formatted string.
  final dynamic value;

  /// The icon's tone (the primary by default).
  final Color? color;
  final VoidCallback? onTap;

  static const double _iconBox = AppIconSize.hero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final tint = appTintOn(context, col);
    final text = '${value ?? 0}';
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$label: $text',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.sm + 2),
        child: Row(children: [
          Container(
            width: _iconBox,
            height: _iconBox,
            decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
            child: Icon(icon, size: AppIconSize.md + 2, color: appInkOn(context, col, tint)),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: AppCountUp(text, memoryKey: 'stat:$label', style: AppType.figureLarge(context)),
              ),
              const SizedBox(height: AppSpace.xxs / 2),
              // two lines: one cut "Live even…" / "مهام فش…" on every 3-up strip (docs/polish/visual-review.md)
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Skeletons (warm bones; the page does not jump when data arrives) ───────

/// One bone of a skeleton: a rounded bar in a warm tone (the input surface pulled toward the hairline), pulsed by
/// the [AppShimmer] around it.
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({super.key, this.width, this.height = 12, this.radius = AppSpace.xs});

  final double? width;
  final double height, radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(c.inputBg, c.divider, 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The calm shape of a list while it loads — the page does not jump when data arrives. Shrink-wrapped, so it also
/// works inside another scroll view (a chat's ListView) where the height is unbounded.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({super.key, this.items = 6, this.withAvatar = true, this.padding});
  final int items;
  final bool withAvatar;
  final EdgeInsetsGeometry? padding;

  static const double _avatar = AppTouch.min - AppSpace.xxs;
  static const double _boneTitle = 12, _boneMeta = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppShimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
        itemCount: items,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(AppSpace.sm + 2),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: Row(children: [
            if (withAvatar) ...[
              const AppSkeletonBox(width: _avatar, height: _avatar, radius: AppRadius.chip),
              AppSpace.gapSm,
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppSkeletonBox(width: 120.0 + (i * 37) % 90, height: _boneTitle),
                const SizedBox(height: AppSpace.xs),
                AppSkeletonBox(width: 70.0 + (i * 23) % 60, height: _boneMeta),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Dropdown: ONE look for every "choose one" field in the app ─────────────
/// Drop-in replacement for DropdownButtonFormField / DropdownButton (same `items`, `onChanged`, `decoration`,
/// `initialValue` / `value`, `hint`): looks like every other field (input theme), opens a bottom sheet with
/// the items (search when the list is long), a check on the current one, safe-area and RTL/LTR aware.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.value,
    this.decoration,
    this.hint,
    this.isExpanded = true,
    this.enabled = true,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final T? value;
  final InputDecoration? decoration;
  final Widget? hint;
  final bool isExpanded; // kept for API compatibility (always full width)
  final bool enabled;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  late T? _value = widget.value ?? widget.initialValue;

  @override
  void didUpdateWidget(covariant AppDropdown<T> old) {
    super.didUpdateWidget(old);
    final v = widget.value ?? widget.initialValue;
    if (v != (old.value ?? old.initialValue)) _value = v;
  }

  String _plain(Widget w) => w is Text ? (w.data ?? w.textSpan?.toPlainText() ?? '') : '';

  Future<void> _open() async {
    final items = widget.items ?? const [];
    final label = widget.decoration?.labelText ?? widget.decoration?.hintText ?? '';
    var query = '';
    final picked = await showAppSheet<_Pick<T>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final shown = items
              .where((i) => query.isEmpty || _plain(i.child).toLowerCase().contains(query.toLowerCase()))
              .toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (label.isNotEmpty) AppSheetHeader(label),
              if (items.length > 8)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    onChanged: (q) => set(() => query = q),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final i in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(type: MaterialType.transparency, child: ListTile(
                        enabled: i.enabled,
                        onTap: () => Navigator.pop(ctx, _Pick<T>(i.value)),
                        title: DefaultTextStyle.merge(
                          style: appText(14, w: i.value == _value ? FontWeight.w800 : FontWeight.w500, c: c.textDark),
                          child: i.child,
                        ),
                        trailing: i.value == _value ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
                        tileColor: i.value == _value ? c.primary.withValues(alpha: 0.07) : null,
                      )),
                    ),
                ]),
              ),
            ]),
          );
        }));
    if (picked == null || !mounted) return;
    setState(() => _value = picked.value);
    widget.onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = widget.items ?? const [];
    final sel = items.where((i) => i.value == _value).toList();
    final enabled = widget.enabled && widget.onChanged != null && items.isNotEmpty;
    final deco = (widget.decoration ?? const InputDecoration()).copyWith(
      suffixIcon: Icon(Icons.expand_more_rounded, color: c.textLight),
      enabled: enabled,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? _open : null,
      child: InputDecorator(
        decoration: deco,
        isEmpty: sel.isEmpty && widget.hint == null,
        child: DefaultTextStyle.merge(
          style: appText(14, w: FontWeight.w600, c: c.textDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: sel.isNotEmpty ? sel.first.child : (widget.hint ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

class _Pick<T> {
  const _Pick(this.value);
  final T? value;
}
