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
// Rule of thumb for new screens:
//   page header      → AppHero(+ AppHeroStat)        section title → AppSectionTitle
//   content block    → AppCard / AppActionCard        numbers       → AppStatTile in an AppGrid
//   nothing yet      → AppEmpty                        loading       → AppListSkeleton (not a spinner)
//   tip / warning    → AppBanner                       quick actions → AppPill
//   form             → AppField / AppPicker / AppSwitchRow / AppPrimaryButton
//   on/off toggle    → AppSwitch / AppSwitchTile (the ONLY switch look in the app — never Switch/SwitchListTile)
//   any time / date  → AppTime.time / date / dateTime (UTC instant) · AppTime.clock("HH:MM") (12h/24h + timezone)
//   sheet / confirm  → showAppSheet / appConfirm       status        → AppBadgePill
//   table export     → showAppExportSheet(context, AppTableExport(...))  (Excel · Word · PDF + column picker)
//   wide table/grid  → AppHScroll(child: …)  (draggable scrollbar · mouse drag · shift+wheel)
//   "needs attention"→ AttentionBadge(tabKey: AttentionTabs.x, child: …) (count + deep links, GET /me/attention)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../features/admin/admin_common.dart' as admin;
import '../features/org/org_ui.dart' as org;
import '../features/teacher/data_lab/data_lab_widgets.dart' as dl;

export 'app_switch.dart';
export 'attention_badge.dart';
export '../core/attention/attention_service.dart' show AttentionService, AttentionTabs, AttentionItem;
export 'app_hscroll.dart';
export 'app_table_export.dart' show showAppExportSheet, exportAppTable, AppTableExport, AppExportColumn, AppColType, AppColAlign, AppTotal, AppExportFormat, AppStatusTone;
export '../core/app_time.dart';
export '../features/org/org_ui.dart'
    show hexColor, statusColor, statusLabel, priorityColor, priorityLabel, relTime, permsFromJson, permsToJson,
        fileSizeLabel;

// ── Data Lab language ───────────────────────────────────────────────────────
typedef AppCard = dl.DlCard;
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
typedef AppSkeletonBox = dl.DlSkeletonBox;
typedef AppBanner = dl.DlBanner;

/// One text style helper for the whole app (same as the Data Lab's).
TextStyle appText(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) => dl.dlText(size, w: w, c: c, h: h);

/// Traffic-light colour for 0–100 (grades, completion, attendance …).
Color appScoreColor(BuildContext context, double? v) => dl.dlScoreColor(context, v);

// ── Organization kit (role-neutral names) ──────────────────────────────────
typedef AppEmpty = org.OrgEmpty;
typedef AppStatTile = org.OrgStatTile;
typedef AppActionCard = org.OrgActionCard;
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

// ── New: list skeleton (premium loading for any list / feed / grid page) ───
/// The calm shape of a list while it loads — the page does not jump when data arrives. Shrink-wrapped, so it also
/// works inside another scroll view (a chat's ListView) where the height is unbounded.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({super.key, this.items = 6, this.withAvatar = true, this.padding});
  final int items;
  final bool withAvatar;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return dl.DlShimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 0),
        itemCount: items,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(c.radiusLarge - 4),
            border: Border.all(color: c.divider),
          ),
          child: Row(children: [
            if (withAvatar) ...[const dl.DlSkeletonBox(width: 44, height: 44, radius: 14), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                dl.DlSkeletonBox(width: 120.0 + (i * 37) % 90, height: 12),
                const SizedBox(height: 8),
                dl.DlSkeletonBox(width: 70.0 + (i * 23) % 60, height: 10),
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
