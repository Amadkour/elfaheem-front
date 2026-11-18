// lib/features/org/workspace/ws_units.dart
//
// The Management and Membership tabs of the teacher workspace (D-1151 / D-1152, docs/teacher-org/PLAN.md): the
// units I manage (scope 'management' → home.managed) or belong to (scope 'membership' → home.memberOf), in one of
// two displays remembered per scope (WsPrefs.display):
//   Boxes — a responsive grid of unit cards; a tap pushes that unit's people (WsUnitPeople).
//   Tabs  — a scrollable strip of units on top, the chosen unit's people below. "Set as main" (star) makes one unit
//           per scope the one it opens on (WsPrefs.mainUnit); Focus mode (WsPrefs.focus) hides the strip and the
//           switch so the list gets the whole page, with a clear button back.
// Every unit offers Pin to dashboard (a `unit:<id>` pin, the Pinned tab) and Open department page (the full D-103
// department page, openDepartmentDashboard).
//
// The unit card is a plain-value widget ([WsUnitCard]) for the layout harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_department_dashboard.dart' show openDepartmentDashboard;
import '../org_join_pages.dart' show unitKindIcon;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_page_kit.dart' show OrgSegmented;
import 'ws_models.dart';
import 'ws_people.dart';
import 'ws_person.dart' show wsCallText, wsPushPage;
import 'ws_shell.dart' show WsController;

String wsRoleLabel(WsUnitRole r) => switch (r) {
      WsUnitRole.head => t('رئيس', 'Head'),
      WsUnitRole.manager => t('مدير', 'Manager'),
      WsUnitRole.member => t('عضو', 'Member'),
    };

AppTone _roleTone(WsUnitRole r) => switch (r) {
      WsUnitRole.head => AppTone.gold,
      WsUnitRole.manager => AppTone.brand,
      WsUnitRole.member => AppTone.neutral,
    };

WsPin wsUnitPin(WsUnit u) => WsPin('unit', '${u.id}', labelAr: u.nameAr, labelEn: u.nameEn);

class WsUnitsTab extends StatefulWidget {
  const WsUnitsTab({super.key, required this.scope});

  /// 'management' or 'membership'.
  final String scope;

  @override
  State<WsUnitsTab> createState() => _WsUnitsTabState();
}

class _WsUnitsTabState extends State<WsUnitsTab> {
  /// The unit chosen in the Tabs display (null = the main one, else the first).
  int? _selected;

  String get _scope => widget.scope;

  List<WsUnit> _units(WsHome h) => _scope == 'management' ? h.managed : h.memberOf;

  void _openUnit(WsController ws, WsUnit u) => wsPushPage<void>(
        context,
        ws,
        OrgPushedPage(title: u.name, subtitle: wsRoleLabel(u.role), child: WsUnitPeople(unit: u)),
      );

  void _openDepartment(WsUnit u) => openDepartmentDashboard(context, unitType: u.unitType, unitId: u.id);

  void _toggleMain(WsController ws, WsUnit u) => ws.prefs.update((p) {
        final m = {...p.mainUnit};
        if (m[_scope] == u.id) {
          m.remove(_scope);
        } else {
          m[_scope] = u.id;
        }
        return p.copyWith(mainUnit: m);
      });

  void _togglePin(WsController ws, WsUnit u) {
    final was = ws.prefs.prefs.pinned(wsUnitPin(u));
    ws.prefs.update((p) => p.togglePin(wsUnitPin(u)));
    showAppNotice(was ? t('أُزيل من المثبّتة', 'Unpinned') : t('ثُبّت في لوحتك', 'Pinned to your dashboard'));
  }

  Future<void> _unitActions(WsController ws, WsUnit u) async {
    final p = ws.prefs.prefs;
    final isMain = p.mainUnit[_scope] == u.id;
    final pinned = p.pinned(wsUnitPin(u));
    await showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: u.name,
        icon: unitKindIcon(u.unitType),
        children: [
          ListTile(
            minTileHeight: AppTouch.min,
            leading: Icon(isMain ? Icons.star_rounded : Icons.star_outline_rounded),
            title: Text(isMain ? t('إلغاء التعيين كرئيسي', 'Remove as main') : t('تعيين كرئيسي', 'Set as main')),
            subtitle: Text(t('يُفتح عليه عرض التبويبات', 'The tabs view opens on it')),
            onTap: () {
              Navigator.pop(ctx);
              _toggleMain(ws, u);
            },
          ),
          ListTile(
            minTileHeight: AppTouch.min,
            leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
            title: Text(pinned ? t('إلغاء التثبيت', 'Unpin from dashboard') : t('تثبيت في اللوحة', 'Pin to dashboard')),
            onTap: () {
              Navigator.pop(ctx);
              _togglePin(ws, u);
            },
          ),
          ListTile(
            minTileHeight: AppTouch.min,
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(t('فتح صفحة القسم', 'Open department page')),
            onTap: () {
              Navigator.pop(ctx);
              _openDepartment(u);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final h = ws.home;
    if (h == null) {
      if (ws.error != null && !ws.loading) return AppErrorState(message: wsCallText(ws.error!), onRetry: () => ws.load());
      return const AppListSkeleton(items: 4);
    }
    final units = _units(h);
    if (units.isEmpty) {
      return AppRefresh(
        onRefresh: () => ws.load(quiet: true),
        scrollable: false,
        child: AppEmpty(
          icon: _scope == 'management' ? Icons.admin_panel_settings_outlined : Icons.groups_2_outlined,
          title: _scope == 'management' ? t('لا تدير أي قسم', "You don't manage a department") : t('لست عضوًا في أي قسم', "You aren't in a department"),
          message: t('ستظهر الأقسام هنا عندما تُضاف إليها.', 'Departments show here once you are added to one.'),
        ),
      );
    }
    final prefs = ws.prefs.prefs;
    final display = prefs.displayOf(_scope);
    final toolbar = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: Row(children: [
        Expanded(
          child: OrgSegmented<WsDisplay>(
            value: display,
            options: [(WsDisplay.boxes, t('مربعات', 'Boxes')), (WsDisplay.tabs, t('تبويبات', 'Tabs'))],
            onChanged: (d) => ws.prefs.update((p) => p.copyWith(display: {...p.display, _scope: d})),
          ),
        ),
        if (display == WsDisplay.tabs)
          AppIconButton(
            icon: Icons.fullscreen_rounded,
            tooltip: t('وضع التركيز', 'Focus mode'),
            onPressed: () => ws.prefs.update((p) => p.copyWith(focus: true)),
          ),
      ]),
    );
    if (display == WsDisplay.boxes) return Column(children: [toolbar, Expanded(child: _boxes(ws, units, prefs))]);
    return _tabs(ws, units, prefs, toolbar);
  }

  Widget _boxes(WsController ws, List<WsUnit> units, WsPrefs prefs) => AppRefresh(
        onRefresh: () => ws.load(quiet: true),
        child: LayoutBuilder(builder: (context, box) {
          const gap = AppSpace.sm;
          final inner = box.maxWidth - 2 * AppSpace.md;
          final cols = (inner / 300).floor().clamp(1, 4);
          final w = (inner - gap * (cols - 1)) / cols;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
            children: [
              Wrap(spacing: gap, runSpacing: gap, children: [
                for (final u in units)
                  SizedBox(
                    width: w,
                    child: WsUnitCard(
                      unit: u,
                      isMain: prefs.mainUnit[_scope] == u.id,
                      pinned: prefs.pinned(wsUnitPin(u)),
                      onTap: () => _openUnit(ws, u),
                      onMore: () => _unitActions(ws, u),
                    ),
                  ),
              ]),
            ],
          );
        }),
      );

  Widget _tabs(WsController ws, List<WsUnit> units, WsPrefs prefs, Widget toolbar) {
    final ids = [for (final u in units) u.id];
    final id = (_selected != null && ids.contains(_selected)) ? _selected! : prefs.openUnit(_scope, ids)!;
    final unit = units.firstWhere((u) => u.id == id);
    final isMain = prefs.mainUnit[_scope] == id;
    final focus = prefs.focus;
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AnimatedSize(
        duration: motion.base,
        curve: AppMotion.curve,
        alignment: AlignmentDirectional.topStart,
        child: focus
            ? Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, 0),
                child: Row(children: [
                  Icon(unitKindIcon(unit.unitType), size: AppIconSize.md, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(unit.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
                  AppButton(
                    key: const ValueKey('ws.focus.exit'),
                    label: t('إنهاء التركيز', 'Exit focus'),
                    icon: Icons.fullscreen_exit_rounded,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: () => ws.prefs.update((p) => p.copyWith(focus: false)),
                  ),
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                toolbar,
                const SizedBox(height: AppSpace.xs),
                WsUnitStrip(
                  units: units,
                  selectedId: id,
                  mainId: prefs.mainUnit[_scope],
                  onSelect: (u) => setState(() => _selected = u),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, 0),
                  child: Row(children: [
                    Expanded(
                      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        AppStatusBadge(label: wsRoleLabel(unit.role), tone: _roleTone(unit.role), dense: true),
                        if (unit.waiting > 0)
                          AppStatusBadge(label: _waitingText(unit.waiting), tone: AppTone.warning, dense: true),
                      ]),
                    ),
                    AppIconButton(
                      icon: isMain ? Icons.star_rounded : Icons.star_outline_rounded,
                      tooltip: isMain ? t('إلغاء التعيين كرئيسي', 'Remove as main') : t('تعيين كرئيسي', 'Set as main'),
                      variant: isMain ? AppIconButtonVariant.tonal : AppIconButtonVariant.standard,
                      onPressed: () => _toggleMain(ws, unit),
                    ),
                    AppIconButton(icon: Icons.more_horiz_rounded, tooltip: t('المزيد', 'More'), onPressed: () => _unitActions(ws, unit)),
                  ]),
                ),
              ]),
      ),
      Expanded(child: WsUnitPeople(key: ValueKey('ws.people.${unit.id}'), unit: unit)),
    ]);
  }
}

String _waitingText(int n) =>
    countText(n, ar1: 'طلب واحد بانتظارك', ar2: 'طلبان بانتظارك', arFew: '$n طلبات بانتظارك', arMany: '$n طلبًا بانتظارك', en1: '1 waiting', en: '$n waiting');

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value parts
// ═════════════════════════════════════════════════════════════════════════════

/// One unit in the Boxes display: icon in the unit's colour, name, my role, people / team, waiting requests.
class WsUnitCard extends StatelessWidget {
  const WsUnitCard({super.key, required this.unit, this.isMain = false, this.pinned = false, this.onTap, this.onMore});

  final WsUnit unit;
  final bool isMain, pinned;
  final VoidCallback? onTap, onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = unit;
    final tint = hexColor(u.color, c.primary);
    final people = countText(u.people, ar1: 'شخص واحد', ar2: 'شخصان', arFew: '${u.people} أشخاص', arMany: '${u.people} شخصًا', ar0: 'لا أحد', en1: '1 person', en: '${u.people} people');
    final team = countText(u.team, ar1: 'عضو فريق', ar2: 'عضوا فريق', arFew: '${u.team} أعضاء فريق', arMany: '${u.team} عضو فريق', en1: '1 on the team', en: '${u.team} on the team');
    return Semantics(
      button: onTap != null,
      child: AppCard(
        onTap: onTap,
        onLongPress: onMore,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: AppTouch.min - AppSpace.xxs,
              height: AppTouch.min - AppSpace.xxs,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: AppRadius.controlAll),
              child: Icon(unitKindIcon(u.unitType), color: tint, size: AppIconSize.lg),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AppStatusBadge(label: wsRoleLabel(u.role), tone: _roleTone(u.role), dense: true),
                  if (isMain) Icon(Icons.star_rounded, size: AppIconSize.sm, color: c.warning, semanticLabel: t('رئيسي', 'Main')),
                  if (pinned) Icon(Icons.push_pin_rounded, size: AppIconSize.sm, color: c.textMedium, semanticLabel: t('مثبّت', 'Pinned')),
                ]),
              ]),
            ),
            if (onMore != null) AppIconButton(icon: Icons.more_horiz_rounded, tooltip: t('المزيد', 'More'), onPressed: onMore),
          ]),
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Fact(icon: Icons.groups_rounded, text: people),
            _Fact(icon: Icons.badge_outlined, text: team),
            if (u.waiting > 0) AppStatusBadge(label: _waitingText(u.waiting), tone: AppTone.warning, icon: Icons.hourglass_top_rounded, dense: true),
          ]),
        ]),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: AppIconSize.sm, color: c.textMedium),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, style: AppType.meta(context).copyWith(color: c.textMedium))),
    ]);
  }
}

/// The Tabs display's strip: one chip per unit, horizontal scroll; the main unit wears a star.
class WsUnitStrip extends StatelessWidget {
  const WsUnitStrip({super.key, required this.units, required this.selectedId, this.mainId, required this.onSelect});

  final List<WsUnit> units;
  final int selectedId;
  final int? mainId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
        child: Row(children: [
          for (final (i, u) in units.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Semantics(
              selected: u.id == selectedId,
              child: AppChoiceChip(
                label: u.waiting > 0 ? '${u.name} · ${u.waiting}' : u.name,
                icon: u.id == mainId ? Icons.star_rounded : unitKindIcon(u.unitType),
                selected: u.id == selectedId,
                onTap: () => onSelect(u.id),
              ),
            ),
          ],
        ]),
      );
}
