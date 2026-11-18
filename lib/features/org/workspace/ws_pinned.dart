// lib/features/org/workspace/ws_pinned.dart
//
// The workspace's ONE Pinned tab (D-1151, docs/teacher-org/PLAN.md): a horizontal chip strip of my pins (the ones
// still live: a unit I left drops out, wsLivePins) and the chosen pin's content below it —
//   tab pin   a card naming the tab with "Open" (ws.go)
//   unit pin  that unit's people (WsUnitPeople)
//   box pin   that Overview box on its own (wsOverviewBox)
//   section   an admin's organization page (OrgTabs.sections, looked up by its sub key, D-1160); gone → Unpin
// Every chip unpins (with Undo). Past wsPinStripMax pins the strip still scrolls and ends with "All pinned (n)": a
// sheet with search (a grid of the matches) and drag-to-reorder (prefs.movePin). The chosen pin lives in this
// widget's state only. WsPinStrip is plain values (tested in test/org/ws_alerts_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_dashboard_screen.dart' show OrgSub, OrgTabs;
import 'ws_models.dart';
import 'ws_overview.dart' show wsOverviewBox, wsOverviewBoxes;
import 'ws_people.dart' show WsUnitPeople;
import 'ws_shell.dart' show WsController;
import 'ws_units.dart' show wsFindSection;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure helpers
// ═════════════════════════════════════════════════════════════════════════════

/// The shell key ([WsTabs]) a tab pin opens: `tab:management` → `ws_management`.
String wsPinTabKey(WsPin p) => p.ref.startsWith('ws_') ? p.ref : 'ws_${p.ref}';

String _tabName(String ref) => switch (ref.startsWith('ws_') ? ref.substring(3) : ref) {
      'overview' => t('لمحة', 'Overview'),
      'management' => t('الإدارة', 'Management'),
      'membership' => t('العضوية', 'Membership'),
      'alerts' => t('التنبيهات', 'Alerts'),
      'profile' => t('الملف الشخصي', 'Profile'),
      _ => ref,
    };

/// A pin's name now: the unit's current name, the box's / tab's label, the organization page's label (when
/// [sections] is given and still holds it); the label saved with the pin otherwise.
String wsPinLabel(WsPin p, WsHome? home, {Map<String, List<OrgSub>>? sections}) {
  switch (p.kind) {
    case 'section':
      final x = sections == null ? null : wsFindSection(sections, p.ref);
      if (x != null) return x.$2.$2;
    case 'unit':
      final u = p.unitId == null ? null : home?.unit(p.unitId!);
      if (u != null && u.name.isNotEmpty) return u.name;
    case 'box':
      for (final b in wsOverviewBoxes) {
        if (b.$1 == p.ref) return t(b.$2, b.$3);
      }
    case 'tab':
      return _tabName(p.ref);
  }
  return p.label.isNotEmpty ? p.label : p.ref;
}

IconData wsPinIcon(WsPin p) => switch (p.kind) {
      'unit' => Icons.account_tree_rounded,
      'box' => Icons.dashboard_customize_rounded,
      'section' => Icons.domain_rounded,
      _ => Icons.tab_rounded,
    };

/// The pins whose label contains [q] (case-insensitive); all of them for an empty query.
List<WsPin> wsSearchPins(List<WsPin> pins, String q, String Function(WsPin) label) {
  final n = q.trim().toLowerCase();
  if (n.isEmpty) return pins;
  return [for (final p in pins) if (label(p).toLowerCase().contains(n)) p];
}

// ═════════════════════════════════════════════════════════════════════════════
//  The strip (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class WsPinStrip extends StatelessWidget {
  const WsPinStrip({
    super.key,
    required this.pins,
    required this.selectedId,
    required this.labelOf,
    required this.onSelect,
    required this.onUnpin,
    this.onAll,
  });

  final List<WsPin> pins;
  final String? selectedId;
  final String Function(WsPin) labelOf;
  final ValueChanged<WsPin> onSelect;
  final ValueChanged<WsPin> onUnpin;

  /// Opens "All pinned"; drawn as the strip's last chip once there are more than [wsPinStripMax] pins.
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Row(children: [
        for (final p in pins) ...[
          InputChip(
            key: ValueKey('ws-pin-${p.id}'),
            avatar: Icon(wsPinIcon(p), size: AppIconSize.sm),
            label: Text(labelOf(p), maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: p.id == selectedId,
            showCheckmark: false,
            onSelected: (_) => onSelect(p),
            onDeleted: () => onUnpin(p),
            deleteIcon: const Icon(Icons.push_pin_outlined, size: AppIconSize.sm),
            deleteButtonTooltipMessage: t('إلغاء التثبيت', 'Unpin'),
          ),
          AppSpace.gapXs,
        ],
        if (onAll != null && pins.length > wsPinStripMax)
          ActionChip(
            key: const ValueKey('ws-pin-all'),
            avatar: Icon(Icons.grid_view_rounded, size: AppIconSize.sm, color: c.primary),
            label: Text(t('كل المثبّتة (${pins.length})', 'All pinned (${pins.length})')),
            onPressed: onAll,
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab
// ═════════════════════════════════════════════════════════════════════════════

class WsPinnedTab extends StatefulWidget {
  const WsPinnedTab({super.key});
  @override
  State<WsPinnedTab> createState() => _WsPinnedTabState();
}

class _WsPinnedTabState extends State<WsPinnedTab> {
  String? _selected;

  /// The organization's pages (admins' `section:` pins); empty outside the dashboard.
  static Map<String, List<OrgSub>> _sections(BuildContext context) {
    try {
      return context.watch<OrgTabs>().sections;
    } catch (_) {
      return const {};
    }
  }

  static List<WsPin> _live(WsController ws) {
    final h = ws.home;
    final pins = ws.prefs.prefs.pins;
    // before the units load every pin stays (a unit pin is not dropped for a list that has not arrived)
    return h == null ? pins : wsLivePins(pins, {for (final u in h.all) u.id});
  }

  void _unpin(WsController ws, WsPin p) {
    ws.prefs.update((x) => x.togglePin(p));
    showAppNotice(
      t('أُلغي التثبيت', 'Unpinned'),
      icon: Icons.push_pin_outlined,
      actionLabel: t('تراجع', 'Undo'),
      onAction: () {
        if (!ws.prefs.prefs.pinned(p)) ws.prefs.update((x) => x.togglePin(p));
      },
    );
  }

  Future<void> _all(WsController ws) async {
    final sections = context.read<OrgTabs>().sections;
    final picked = await showAppSheet<WsPin>(context, (ctx) => _AllPinsSheet(ws: ws, labelOf: (p) => wsPinLabel(p, ws.home, sections: sections)));
    if (picked != null && mounted) setState(() => _selected = picked.id);
  }

  Widget _content(WsController ws, WsPin p) {
    final c = context.colors;
    switch (p.kind) {
      case 'unit':
        final h = ws.home;
        if (h == null) return const AppListSkeleton(items: 5);
        final u = h.unit(p.unitId ?? -1);
        if (u == null) {
          return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
            AppEmpty(
              icon: Icons.link_off_rounded,
              title: t('لم تعد في هذه الوحدة', 'You are no longer in this unit'),
              actionLabel: t('إلغاء التثبيت', 'Unpin'),
              onAction: () => _unpin(ws, p),
            ),
          ]);
        }
        return WsUnitPeople(key: ValueKey('ws-pinned-unit-${u.id}'), unit: u);
      case 'section':
        final x = wsFindSection(_sections(context), p.ref);
        if (x == null) {
          return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
            AppEmpty(
              icon: Icons.link_off_rounded,
              title: t('هذه الصفحة لم تعد متاحة لك', 'This page is no longer available to you'),
              actionLabel: t('إلغاء التثبيت', 'Unpin'),
              onAction: () => _unpin(ws, p),
            ),
          ]);
        }
        return KeyedSubtree(key: ValueKey('ws-pinned-section-${p.ref}'), child: x.$2.$4);
      case 'box':
        return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl), children: [
          KeyedSubtree(key: ValueKey('ws-pinned-box-${p.ref}'), child: wsOverviewBox(context, p.ref)),
        ]);
      default:
        final name = wsPinLabel(p, ws.home, sections: _sections(context));
        return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          AppCard(
            child: Row(children: [
              Container(
                width: AppIconSize.hero,
                height: AppIconSize.hero,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(wsPinIcon(p), size: AppIconSize.md, color: appInk(context, c.primary)),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
                  Text(t('تبويب مثبّت', 'Pinned tab'), style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
              ),
              AppSpace.gapXs,
              AppButton.tonal(
                label: t('فتح', 'Open'),
                trailingIcon: Icons.arrow_forward_rounded,
                size: AppButtonSize.sm,
                onPressed: () {
                  if (!ws.go(wsPinTabKey(p))) showAppNotice(t('هذا التبويب غير متاح الآن', 'This tab is not available right now'));
                },
              ),
            ]),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final pins = _live(ws);
    if (pins.isEmpty) {
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        AppEmpty(
          icon: Icons.push_pin_outlined,
          title: t('لا شيء مثبّت', 'Nothing pinned'),
          message: ws.admin
              ? t('ثبّت صفحة من المؤسسة أو وحدة أو مربعاً من اللمحة ليظهر هنا.', 'Pin an organization page, a unit or an Overview box to keep it here.')
              : t('ثبّت وحدة أو مربعاً من اللمحة ليظهر هنا.', 'Pin a unit or an Overview box to keep it here.'),
        ),
      ]);
    }
    final sel = pins.where((p) => p.id == _selected).firstOrNull ?? pins.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WsPinStrip(
        pins: pins,
        selectedId: sel.id,
        labelOf: (p) => wsPinLabel(p, ws.home, sections: _sections(context)),
        onSelect: (p) => setState(() => _selected = p.id),
        onUnpin: (p) => _unpin(ws, p),
        onAll: () => _all(ws),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey('ws-pinned-${sel.id}'), child: _content(ws, sel))),
    ]);
  }
}

/// The narrowest tile of the search grid (four touch targets wide).
const double _pinTileMin = AppTouch.min * 4;

/// "All pinned": search (a grid of the matches, one tap opens) or, with no query, the pins in order with drag
/// handles (prefs.movePin). Pops the chosen pin.
class _AllPinsSheet extends StatefulWidget {
  const _AllPinsSheet({required this.ws, required this.labelOf});
  final WsController ws;
  final String Function(WsPin) labelOf;

  @override
  State<_AllPinsSheet> createState() => _AllPinsSheetState();
}

class _AllPinsSheetState extends State<_AllPinsSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.ws.prefs,
        builder: (context, _) {
          final c = context.colors;
          final ws = widget.ws;
          final all = ws.prefs.prefs.pins;
          final live = _WsPinnedTabState._live(ws);
          final shown = wsSearchPins(live, _q, widget.labelOf);
          Widget tile(WsPin p, {Widget? trailing}) => ListTile(
                key: ValueKey('ws-all-${p.id}'),
                leading: Icon(wsPinIcon(p), color: c.primary),
                title: Text(widget.labelOf(p), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: trailing,
                onTap: () => Navigator.of(context).pop(p),
              );
          return AppSheetContent(
            title: t('كل المثبّتة (${live.length})', 'All pinned (${live.length})'),
            icon: Icons.push_pin_rounded,
            children: [
              AppSearchField(hint: t('ابحث في المثبّتة', 'Search pins'), debounce: Duration.zero, onChanged: (v) => setState(() => _q = v)),
              AppSpace.gapSm,
              if (_q.trim().isNotEmpty)
                shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Text(t('لا نتائج', 'No matches'), textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
                      )
                    : LayoutBuilder(builder: (context, box) {
                        final cols = (box.maxWidth / _pinTileMin).floor().clamp(1, 4);
                        final w = (box.maxWidth - AppSpace.xs * (cols - 1)) / cols;
                        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                          for (final p in shown)
                            SizedBox(
                              width: w,
                              child: AppCard(
                                padding: const EdgeInsets.all(AppSpace.sm),
                                onTap: () => Navigator.of(context).pop(p),
                                child: Row(children: [
                                  Icon(wsPinIcon(p), size: AppIconSize.md, color: c.primary),
                                  AppSpace.gapXs,
                                  Expanded(child: Text(widget.labelOf(p), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                                ]),
                              ),
                            ),
                        ]);
                      })
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) {
                    // [to] is the final index (the moved pin already taken out); pins of units I left keep their
                    // place after the live ones
                    final order = [...live];
                    order.insert(to.clamp(0, order.length - 1), order.removeAt(from));
                    ws.prefs.update((x) => x.copyWith(pins: [...order, for (final p in all) if (!order.contains(p)) p]));
                  },
                  children: [
                    for (var i = 0; i < live.length; i++)
                      tile(live[i],
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: Semantics(
                              label: t('اسحب لإعادة الترتيب', 'Drag to reorder'),
                              child: const SizedBox(
                                width: AppTouch.min,
                                height: AppTouch.min,
                                child: Icon(Icons.drag_indicator_rounded),
                              ),
                            ),
                          )),
                  ],
                ),
            ],
          );
        },
      );
}
