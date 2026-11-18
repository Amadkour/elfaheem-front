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
// Organization admins (D-1160, WsController.admin): Management leads with the ORGANIZATION'S SECTIONS (OrgTabs.
// sections: people · academics · timetable · services, already only what I hold a right to), then the units.
//   Boxes — an "Organization" group (a small heading per section with its attention badge, a card per page; a tap
//           pushes the page with orgPushPage), then the "Units" group.
//   Tabs  — the strip lists the pages then the units; a page is drawn in place and kept alive once opened (like
//           the D-103 _SectionHub). The star works for both: a page main is WsPrefs.mainSection (one main per scope).
// Every page offers Pin to dashboard (a `section:<sub key>` pin).
//
// The unit card, the section card and the admin grid are plain-value widgets ([WsUnitCard], [WsSectionCard],
// [WsAdminBoxes]) for the layout harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_dashboard_home.dart' show orgPushPage;
import '../org_dashboard_screen.dart' show OrgSub, OrgTabs;
import '../org_department_dashboard.dart' show openDepartmentDashboard;
import '../org_join_pages.dart' show unitKindIcon;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_page_kit.dart' show OrgSegmented;
import '../org_providers.dart' show OrgDashController, OrgSession;
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

// ═════════════════════════════════════════════════════════════════════════════
//  Organization sections (admins, D-1160)
// ═════════════════════════════════════════════════════════════════════════════

/// The order an admin's Management lists the organization's sections in.
const wsOrgSectionOrder = ['people', 'academics', 'timetable', 'services'];

String wsOrgSectionName(String key) => switch (key) {
      'people' => t('الأشخاص', 'People'),
      'academics' => t('الشؤون الأكاديمية', 'Academics'),
      'timetable' => t('الجدول', 'Timetable'),
      'services' => t('الخدمات', 'Services'),
      _ => key,
    };

IconData wsOrgSectionIcon(String key) => switch (key) {
      'people' => Icons.groups_rounded,
      'academics' => Icons.school_rounded,
      'timetable' => Icons.calendar_month_rounded,
      'services' => Icons.forum_rounded,
      _ => Icons.domain_rounded,
    };

/// The attention tab (GET /me/attention) whose count a section's heading wears; null = none.
String? wsOrgSectionAttention(String key) => switch (key) {
      'people' => AttentionTabs.orgPeople,
      'academics' => AttentionTabs.orgAcademics,
      'timetable' => AttentionTabs.orgTimetable,
      'services' => AttentionTabs.orgServices,
      _ => null,
    };

/// The sections with at least one page, in [wsOrgSectionOrder] (unknown keys last, in their own order).
List<(String, List<OrgSub>)> wsOrderedSections(Map<String, List<OrgSub>> sections) => [
      for (final k in [...wsOrgSectionOrder, ...sections.keys.where((k) => !wsOrgSectionOrder.contains(k))])
        if ((sections[k] ?? const <OrgSub>[]).isNotEmpty) (k, sections[k]!),
    ];

/// The organization page a `section:<sub key>` pin opens: (section key, page), or null when it is gone (the right
/// was taken away, the page was switched off).
(String, OrgSub)? wsFindSection(Map<String, List<OrgSub>> sections, String sub) {
  for (final e in sections.entries) {
    for (final x in e.value) {
      if (x.$1 == sub) return (e.key, x);
    }
  }
  return null;
}

/// A page's pin. Its label is saved as shown now; the Pinned tab shows the live label while the page exists.
WsPin wsSectionPin(OrgSub x) => WsPin('section', x.$1, labelAr: x.$2, labelEn: x.$2);

/// The tabs display's item keys: `section:<sub key>` / `unit:<id>`.
String _secKey(String sub) => 'section:$sub';
String _unitKey(int id) => 'unit:$id';

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

  /// The admin Tabs display's chosen item ([_secKey] / [_unitKey]); null = the main one, else the first.
  String? _selectedKey;

  /// The organization pages opened in the admin Tabs display (kept alive afterwards).
  final Set<String> _seenSections = {};

  String get _scope => widget.scope;

  List<WsUnit> _units(WsHome h) => _scope == 'management' ? h.managed : h.memberOf;

  void _openUnit(WsController ws, WsUnit u) => wsPushPage<void>(
        context,
        ws,
        OrgPushedPage(title: u.name, subtitle: wsRoleLabel(u.role), child: WsUnitPeople(unit: u)),
      );

  void _openDepartment(WsUnit u) => openDepartmentDashboard(context, unitType: u.unitType, unitId: u.id);

  void _openSection(OrgSub x) => orgPushPage(context,
      session: context.read<OrgSession>(), dash: context.read<OrgDashController>(), tabs: context.read<OrgTabs>(), title: x.$2, page: x.$4);

  void _toggleMain(WsController ws, WsUnit u) => ws.prefs.update((p) =>
      p.mainUnit[_scope] == u.id ? p.copyWith(mainUnit: {...p.mainUnit}..remove(_scope)) : p.setMainUnit(_scope, u.id));

  void _toggleMainSection(WsController ws, String sub) => ws.prefs.update((p) =>
      p.mainSection[_scope] == sub ? p.copyWith(mainSection: {...p.mainSection}..remove(_scope)) : p.setMainSection(_scope, sub));

  void _togglePinOf(WsController ws, WsPin pin) {
    final was = ws.prefs.prefs.pinned(pin);
    ws.prefs.update((p) => p.togglePin(pin));
    showAppNotice(was ? t('أُزيل من المثبّتة', 'Unpinned') : t('ثُبّت في لوحتك', 'Pinned to your dashboard'));
  }

  void _togglePin(WsController ws, WsUnit u) => _togglePinOf(ws, wsUnitPin(u));

  ListTile _mainTile(BuildContext ctx, bool isMain, VoidCallback onTap) => ListTile(
        minTileHeight: AppTouch.min,
        leading: Icon(isMain ? Icons.star_rounded : Icons.star_outline_rounded),
        title: Text(isMain ? t('إلغاء التعيين كرئيسي', 'Remove as main') : t('تعيين كرئيسي', 'Set as main')),
        subtitle: Text(t('يُفتح عليه عرض التبويبات', 'The tabs view opens on it')),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );

  ListTile _pinTile(BuildContext ctx, bool pinned, VoidCallback onTap) => ListTile(
        minTileHeight: AppTouch.min,
        leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
        title: Text(pinned ? t('إلغاء التثبيت', 'Unpin from dashboard') : t('تثبيت في اللوحة', 'Pin to dashboard')),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );

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
          _mainTile(ctx, isMain, () => _toggleMain(ws, u)),
          _pinTile(ctx, pinned, () => _togglePin(ws, u)),
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

  Future<void> _sectionActions(WsController ws, OrgSub x) async {
    final p = ws.prefs.prefs;
    final isMain = p.mainSection[_scope] == x.$1;
    final pinned = p.pinned(wsSectionPin(x));
    await showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: x.$2,
        icon: x.$3,
        children: [
          _mainTile(ctx, isMain, () => _toggleMainSection(ws, x.$1)),
          _pinTile(ctx, pinned, () => _togglePinOf(ws, wsSectionPin(x))),
          ListTile(
            minTileHeight: AppTouch.min,
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(t('فتح الصفحة', 'Open page')),
            onTap: () {
              Navigator.pop(ctx);
              _openSection(x);
            },
          ),
        ],
      ),
    );
  }

  Widget _toolbar(WsController ws, WsDisplay display) => Padding(
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

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    if (ws.admin && _scope == 'management') {
      final sections = wsOrderedSections(context.watch<OrgTabs>().sections);
      if (sections.isNotEmpty) return _admin(ws, sections);
    }
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
    final toolbar = _toolbar(ws, display);
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tabsHeader(
        ws,
        prefs.focus,
        icon: unitKindIcon(unit.unitType),
        title: unit.name,
        toolbar: toolbar,
        strip: WsUnitStrip(
          units: units,
          selectedId: id,
          mainId: prefs.mainUnit[_scope],
          onSelect: (u) => setState(() => _selected = u),
        ),
        badges: _unitBadges(unit),
        isMain: isMain,
        onMain: () => _toggleMain(ws, unit),
        onMore: () => _unitActions(ws, unit),
      ),
      Expanded(child: WsUnitPeople(key: ValueKey('ws.people.${unit.id}'), unit: unit)),
    ]);
  }

  List<Widget> _unitBadges(WsUnit unit) => [
        AppStatusBadge(label: wsRoleLabel(unit.role), tone: _roleTone(unit.role), dense: true),
        if (unit.waiting > 0) AppStatusBadge(label: _waitingText(unit.waiting), tone: AppTone.warning, dense: true),
      ];

  /// The Tabs display's top: the switch, the strip and the chosen item's row (badges · star · more), or in Focus
  /// mode only the chosen item's name with "Exit focus".
  Widget _tabsHeader(
    WsController ws,
    bool focus, {
    required IconData icon,
    required String title,
    required Widget toolbar,
    required Widget strip,
    required List<Widget> badges,
    required bool isMain,
    required VoidCallback onMain,
    required VoidCallback onMore,
  }) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return AnimatedSize(
      duration: motion.base,
      curve: AppMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: focus
          ? Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, 0),
              child: Row(children: [
                Icon(icon, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
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
              strip,
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, 0),
                child: Row(children: [
                  Expanded(
                    child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: badges),
                  ),
                  AppIconButton(
                    icon: isMain ? Icons.star_rounded : Icons.star_outline_rounded,
                    tooltip: isMain ? t('إلغاء التعيين كرئيسي', 'Remove as main') : t('تعيين كرئيسي', 'Set as main'),
                    variant: isMain ? AppIconButtonVariant.tonal : AppIconButtonVariant.standard,
                    onPressed: onMain,
                  ),
                  AppIconButton(icon: Icons.more_horiz_rounded, tooltip: t('المزيد', 'More'), onPressed: onMore),
                ]),
              ),
            ]),
    );
  }

  // ── Admins (D-1160) ─────────────────────────────────────────────────────────

  Widget _admin(WsController ws, List<(String, List<OrgSub>)> sections) {
    final h = ws.home;
    final units = h?.managed ?? const <WsUnit>[];
    final prefs = ws.prefs.prefs;
    final display = prefs.displayOf(_scope);
    final toolbar = _toolbar(ws, display);
    final mainKey = _adminMainKey(prefs, sections, units);
    if (display == WsDisplay.boxes) {
      final oid = context.read<OrgSession>().currentId;
      return Column(children: [
        toolbar,
        Expanded(
          child: AppRefresh(
            onRefresh: () => ws.load(quiet: true),
            child: WsAdminBoxes(
              sections: sections,
              units: units,
              unitsLoading: h == null && ws.error == null,
              mainKey: mainKey,
              isPinned: prefs.pinned,
              badge: (section, child) {
                final tab = wsOrgSectionAttention(section);
                return tab == null ? child : AttentionBadge(tabKey: tab, orgId: oid, child: child);
              },
              onSection: _openSection,
              onSectionMore: (x) => _sectionActions(ws, x),
              onUnit: (u) => _openUnit(ws, u),
              onUnitMore: (u) => _unitActions(ws, u),
            ),
          ),
        ),
      ]);
    }
    return _adminTabs(ws, sections, units, prefs, toolbar, mainKey);
  }

  /// The admin's main item: the main page while it is listed, else the main unit while it is listed.
  String? _adminMainKey(WsPrefs prefs, List<(String, List<OrgSub>)> sections, List<WsUnit> units) {
    final ms = prefs.mainSection[_scope];
    if (ms != null && sections.any((s) => s.$2.any((x) => x.$1 == ms))) return _secKey(ms);
    final mu = prefs.mainUnit[_scope];
    if (mu != null && units.any((u) => u.id == mu)) return _unitKey(mu);
    return null;
  }

  Widget _adminTabs(WsController ws, List<(String, List<OrgSub>)> sections, List<WsUnit> units, WsPrefs prefs, Widget toolbar, String? mainKey) {
    final subs = [for (final s in sections) for (final x in s.$2) (s.$1, x)];
    final items = <WsStripItem>[
      for (final (_, x) in subs) (_secKey(x.$1), x.$2, x.$3),
      for (final u in units) (_unitKey(u.id), u.waiting > 0 ? '${u.name} · ${u.waiting}' : u.name, unitKindIcon(u.unitType)),
    ];
    final keys = [for (final i in items) i.$1];
    final key = (_selectedKey != null && keys.contains(_selectedKey)) ? _selectedKey! : (mainKey ?? keys.first);
    final si = subs.indexWhere((e) => _secKey(e.$2.$1) == key);
    final unit = si >= 0 ? null : units.firstWhere((u) => _unitKey(u.id) == key);
    if (si >= 0) _seenSections.add(subs[si].$2.$1);
    final isMain = key == mainKey;
    final strip = WsScopeStrip(items: items, selectedKey: key, mainKey: mainKey, onSelect: (k) => setState(() => _selectedKey = k));
    final Widget header;
    if (unit != null) {
      header = _tabsHeader(
        ws,
        prefs.focus,
        icon: unitKindIcon(unit.unitType),
        title: unit.name,
        toolbar: toolbar,
        strip: strip,
        badges: _unitBadges(unit),
        isMain: isMain,
        onMain: () => _toggleMain(ws, unit),
        onMore: () => _unitActions(ws, unit),
      );
    } else {
      final (section, x) = subs[si];
      header = _tabsHeader(
        ws,
        prefs.focus,
        icon: x.$3,
        title: x.$2,
        toolbar: toolbar,
        strip: strip,
        badges: [AppStatusBadge(label: wsOrgSectionName(section), tone: AppTone.brand, icon: wsOrgSectionIcon(section), dense: true)],
        isMain: isMain,
        onMain: () => _toggleMainSection(ws, x.$1),
        onMore: () => _sectionActions(ws, x),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(
        child: IndexedStack(index: si >= 0 ? si : subs.length, children: [
          for (final (_, x) in subs)
            _seenSections.contains(x.$1) ? KeyedSubtree(key: ValueKey('ws.section.${x.$1}'), child: x.$4) : const SizedBox.shrink(),
          unit == null ? const SizedBox.shrink() : WsUnitPeople(key: ValueKey('ws.people.${unit.id}'), unit: unit),
        ]),
      ),
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

/// One organization page in an admin's Management (D-1160): a tinted icon well, the page's name, its section, the
/// main star / pin marks, and More (or a direction-aware chevron without it).
class WsSectionCard extends StatelessWidget {
  const WsSectionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.section,
    this.isMain = false,
    this.pinned = false,
    this.onTap,
    this.onMore,
  });

  final String label;
  final IconData icon;

  /// The section key ('people', 'academics', …), named under the label.
  final String section;
  final bool isMain, pinned;
  final VoidCallback? onTap, onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      child: AppCard(
        onTap: onTap,
        onLongPress: onMore,
        child: Row(children: [
          Container(
            width: AppTouch.min - AppSpace.xxs,
            height: AppTouch.min - AppSpace.xxs,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: AppRadius.controlAll),
            child: Icon(icon, color: appInk(context, c.primary), size: AppIconSize.lg),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(wsOrgSectionName(section), style: AppType.meta(context).copyWith(color: c.textMedium)),
                if (isMain) Icon(Icons.star_rounded, size: AppIconSize.sm, color: c.warning, semanticLabel: t('رئيسي', 'Main')),
                if (pinned) Icon(Icons.push_pin_rounded, size: AppIconSize.sm, color: c.textMedium, semanticLabel: t('مثبّت', 'Pinned')),
              ]),
            ]),
          ),
          if (onMore != null)
            AppIconButton(icon: Icons.more_horiz_rounded, tooltip: t('المزيد', 'More'), onPressed: onMore)
          else
            ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: c.textMedium)),
        ]),
      ),
    );
  }
}

/// An admin's Management in the Boxes display (D-1160): the "Organization" group (a small heading per section,
/// wrapped by [badge] for its attention count, then a card per page), then the "Units" group. Plain values.
class WsAdminBoxes extends StatelessWidget {
  const WsAdminBoxes({
    super.key,
    required this.sections,
    required this.units,
    this.unitsLoading = false,
    this.mainKey,
    this.isPinned,
    this.badge,
    this.onSection,
    this.onSectionMore,
    this.onUnit,
    this.onUnitMore,
  });

  final List<(String, List<OrgSub>)> sections;
  final List<WsUnit> units;
  final bool unitsLoading;

  /// `section:<sub key>` / `unit:<id>` of the main item.
  final String? mainKey;
  final bool Function(WsPin)? isPinned;
  final Widget Function(String section, Widget child)? badge;
  final ValueChanged<OrgSub>? onSection, onSectionMore;
  final ValueChanged<WsUnit>? onUnit, onUnitMore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const gap = AppSpace.sm;
        final inner = box.maxWidth - 2 * AppSpace.md;
        final cols = (inner / 300).floor().clamp(1, 4);
        final w = (inner - gap * (cols - 1)) / cols;
        bool pinned(WsPin p) => isPinned?.call(p) ?? false;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
          children: [
            _GroupTitle(icon: Icons.domain_rounded, text: t('المؤسسة', 'Organization')),
            for (final (section, subs) in sections) ...[
              _SectionHeading(section: section, badge: badge),
              Wrap(spacing: gap, runSpacing: gap, children: [
                for (final x in subs)
                  SizedBox(
                    width: w,
                    child: WsSectionCard(
                      key: ValueKey('ws.section.card.${x.$1}'),
                      label: x.$2,
                      icon: x.$3,
                      section: section,
                      isMain: mainKey == _secKey(x.$1),
                      pinned: pinned(wsSectionPin(x)),
                      onTap: onSection == null ? null : () => onSection!(x),
                      onMore: onSectionMore == null ? null : () => onSectionMore!(x),
                    ),
                  ),
              ]),
            ],
            if (units.isNotEmpty || unitsLoading) ...[
              const SizedBox(height: AppSpace.lg),
              _GroupTitle(icon: Icons.account_tree_rounded, text: t('الوحدات', 'Units')),
              if (units.isEmpty)
                const LinearProgressIndicator()
              else
                Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final u in units)
                    SizedBox(
                      width: w,
                      child: WsUnitCard(
                        unit: u,
                        isMain: mainKey == _unitKey(u.id),
                        pinned: pinned(wsUnitPin(u)),
                        onTap: onUnit == null ? null : () => onUnit!(u),
                        onMore: onUnitMore == null ? null : () => onUnitMore!(u),
                      ),
                    ),
                ]),
            ],
          ],
        );
      });
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: appInk(context, c.primary)),
          AppSpace.gapXs,
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark))),
        ]),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.section, this.badge});
  final String section;
  final Widget Function(String section, Widget child)? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget mark = Icon(wsOrgSectionIcon(section), size: AppIconSize.sm, color: c.textMedium);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpace.md, bottom: AppSpace.xs),
        child: Row(children: [
          badge == null ? mark : badge!(section, mark),
          AppSpace.gapXs,
          Expanded(
            child: Text(wsOrgSectionName(section),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
          ),
        ]),
      ),
    );
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
  Widget build(BuildContext context) => WsScopeStrip(
        items: [for (final u in units) (_unitKey(u.id), u.waiting > 0 ? '${u.name} · ${u.waiting}' : u.name, unitKindIcon(u.unitType))],
        selectedKey: _unitKey(selectedId),
        mainKey: mainId == null ? null : _unitKey(mainId!),
        onSelect: (k) => onSelect(int.parse(k.substring(5))),
      );
}

/// One chip of [WsScopeStrip]: (key, label, icon).
typedef WsStripItem = (String, String, IconData);

/// A strip of chips over keyed items (an admin's Management: the organization pages then the units); the main
/// item wears a star.
class WsScopeStrip extends StatelessWidget {
  const WsScopeStrip({super.key, required this.items, required this.selectedKey, this.mainKey, required this.onSelect});

  final List<WsStripItem> items;
  final String selectedKey;
  final String? mainKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
        child: Row(children: [
          for (final (i, x) in items.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Semantics(
              selected: x.$1 == selectedKey,
              child: AppChoiceChip(
                label: x.$2,
                icon: x.$1 == mainKey ? Icons.star_rounded : x.$3,
                selected: x.$1 == selectedKey,
                onTap: () => onSelect(x.$1),
              ),
            ),
          ],
        ]),
      );
}
