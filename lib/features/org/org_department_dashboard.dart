// lib/features/org/org_department_dashboard.dart
//
// The department dashboard — what opens when anyone taps a department. One screen for BOTH kinds:
//   unitType "dept"     operational / service department (OrgDepartment): staff = its team (OrgDeptMember),
//                       users = people who joined it (OrgUnitMember)
//   unitType "program"  academic department (OrgProgram): staff = teachers / assistants of that department,
//                       users = its students (OrgStudentAcademic), requests = joins + "choose your department"
// One call: GET …/units/{type}/{id}/dashboard, typed once as OrgUnitData (org_dashboard_model.dart; the last payload
// stays on screen when a reload fails). Every block and action is gated by the server's `can` map (the viewer's
// effective rights IN THIS department), so a head, an approver and the org admin each see what they may do.
//
// Layout: hero (identity · manager · stats; a stat the viewer may not see reads "—") → quick actions → trend tiles
// the day the server sends `series` → tabs Requests · Users · Members (+ Overview on phones). On wide screens the
// overview (governance, announcements, sub-departments, contact card) sits in a side column.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'org_dashboard_home.dart' show OrgTrendRow;
import 'org_dashboard_model.dart' show OrgUnitData;
import 'org_departments_page.dart' show DeptLogo, OrgDepartmentHub, showDepartmentWizard;
import 'org_join_pages.dart' show OrgUnitJoinHub;
import 'org_providers.dart';
import 'org_services_pages.dart' show OrgComplaintsPage, OrgFormsPage, OrgMaterialsPage;
import 'org_ui.dart' show deptIcon, memberRoleLabels, orgNameOf, orgText;
import 'org_v3.dart' show orgCall, orgParseUtc;
import 'governance/gov_dashboard.dart' show GovDashboardCard;
import 'governance/gov_delegations_page.dart' show GovDelegationsPage;
import 'governance/gov_wiring.dart' show govDeptItemsTab, govEnabled, govOpenCouncilOfDept;

/// Opens the dashboard of one department, carrying the current organization session.
Future<void> openDepartmentDashboard(BuildContext context,
    {required String unitType, required int unitId, Map<String, dynamic>? seed}) {
  final s = context.read<OrgSession>();
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
          value: s, child: OrgDepartmentDashboard(unitType: unitType, unitId: unitId, seed: seed))));
}

class OrgDepartmentDashboard extends StatefulWidget {
  const OrgDepartmentDashboard({super.key, required this.unitType, required this.unitId, this.seed});
  final String unitType; // dept | program
  final int unitId;
  final Map<String, dynamic>? seed; // the list row: instant title / colour while the dashboard loads

  @override
  State<OrgDepartmentDashboard> createState() => _OrgDepartmentDashboardState();
}

enum _Load { loading, ready, forbidden, failed }

class _OrgDepartmentDashboardState extends State<OrgDepartmentDashboard> {
  OrgUnitData? _d;
  _Load _state = _Load.loading;
  String? _error;

  bool get _isDept => widget.unitType == 'dept';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    try {
      final r = await ApiClient().get('${s.base}/units/${widget.unitType}/${widget.unitId}/dashboard',
          queryParams: {'preview': 50});
      if (!mounted) return;
      setState(() {
        final d = OrgUnitData.fromJson(r);
        if (d != null) _d = d;                   // a bad answer keeps the last payload on screen
        _state = _d == null ? _Load.failed : _Load.ready;
      });
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      setState(() {
        _state = err.statusCode == 403 ? _Load.forbidden : (_d == null ? _Load.failed : _Load.ready);
        _error = err.message;
      });
      if (_d != null) toast(err.message, error: true);
    }
  }

  Map<String, dynamic> get _unit => (_d?.unit.isEmpty ?? true) ? (widget.seed ?? const {}) : _d!.unit;
  bool _cap(String k) => _d?.cap(k) ?? false;

  Future<void> _push(String title, Widget child) async {
    final s = context.read<OrgSession>();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
            value: s, child: BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: title), child: child))));
    if (mounted) _load();
  }

  Future<void> _openHub() async {
    final s = context.read<OrgSession>();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgDepartmentHub(dept: _unit))));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = orgNameOf(_unit);
    final editable = _isDept && (_cap('edit_unit') || _cap('edit_card'));
    return BasePage(
      useWebCard: true,
      maxWith: 1240,
      appBar: ScreenAppBar(title: name.isEmpty ? t('القسم', 'Department') : name, actions: [
        const ContextExitButton(), // one tap back to the personal space from inside a department
        if (_state == _Load.ready)
          IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        if (_state == _Load.ready && editable)
          IconButton(
            tooltip: t('تعديل الإدارة', 'Edit department'),
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final s = context.read<OrgSession>();
              final full = await OrgApi.i.getMap('${s.base}/departments/${widget.unitId}');
              if (full == null || !context.mounted) return;
              if (await showDepartmentWizard(context, edit: full)) _load();
            },
          ),
      ]),
      child: switch (_state) {
        _Load.loading => const AppListSkeleton(items: 5),
        _Load.forbidden => AppEmpty(
            icon: Icons.lock_outline_rounded,
            title: t('هذا القسم خارج صلاحياتك', 'This department is outside your access'),
            message: t('اطلب من مدير المؤسسة أو رئيس القسم إضافتك إلى فريقه إن كنت تحتاج إليه.',
                'Ask the organization admin or the department head to add you to its team if you need it.'),
          ),
        _Load.failed => ErrorRetry(message: _error ?? t('تعذّر تحميل القسم', 'Could not load the department'), onRetry: _load),
        _Load.ready => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 980;
            final tabs = _tabs(wide);
            final header = <Widget>[
              _UnitHero(d: _d!, seed: widget.seed),
              _QuickActions(actions: _actions()),
              if (_d!.trends.isNotEmpty) OrgTrendRow(trends: _d!.trends),
            ];
            Widget main;
            if (tabs.isEmpty) {
              main = ListView(padding: const EdgeInsets.only(bottom: 40), children: [...header, ..._overview(wide: false)]);
            } else {
              main = DefaultTabController(
                length: tabs.length,
                child: NestedScrollView(
                  headerSliverBuilder: (_, _) => [
                    for (final h in header) SliverToBoxAdapter(child: h),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabBarDelegate(
                        TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          labelColor: c.primary,
                          indicatorColor: c.primary,
                          unselectedLabelColor: c.textMedium,
                          dividerColor: c.divider,
                          labelStyle: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800),
                          unselectedLabelStyle: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w600),
                          tabs: [for (final tb in tabs) Tab(child: _TabLabel(icon: tb.$2, label: tb.$1, badge: tb.$3))],
                        ),
                        c.cardBg,
                      ),
                    ),
                  ],
                  body: TabBarView(children: [for (final tb in tabs) tb.$4]),
                ),
              );
            }
            if (!wide) return main;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main),
              SizedBox(
                width: 360,
                child: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 8, 40), children: _overview(wide: true)),
              ),
            ]);
          }),
      },
    );
  }

  // ── tabs: (label, icon, badge, body) ──
  List<(String, IconData, int, Widget)> _tabs(bool wide) {
    final waiting = _d?.waiting ?? 0;
    final showRequests = _cap('decide_requests') || _cap('configure_join') || _cap('view_forms') || _cap('decide_program_choices');
    return [
      if (!wide) (t('نظرة عامة', 'Overview'), Icons.space_dashboard_rounded, 0, _TabList(onRefresh: _load, children: _overview(wide: false))),
      if (showRequests) (t('الطلبات', 'Requests'), Icons.inbox_rounded, waiting, _RequestsTab(d: _d!, unitType: widget.unitType, unitId: widget.unitId, onChanged: _load, onSeeAll: _seeAllRequests)),
      // governance (D-057): every item routed to / submitted to this entity
      if (_isDept && _govOn)
        (t('المعاملات', 'Items'), Icons.account_tree_rounded, 0, govDeptItemsTab(context, context.read<OrgSession>().currentId ?? 0, widget.unitId)),
      if (_cap('view_users'))
        (_isDept ? t('المنضمّون', 'Users') : t('الطلاب', 'Students'), Icons.people_alt_rounded, 0,
            _UsersTab(d: _d!, unitType: widget.unitType, unitId: widget.unitId, onChanged: _load)),
      if (_cap('view_team'))
        (_isDept ? t('الفريق', 'Members') : t('هيئة القسم', 'Faculty'), Icons.badge_rounded, 0,
            _TeamTab(d: _d!, isDept: _isDept, onManage: _cap('manage_team') ? _openHub : null, onRefresh: _load)),
    ];
  }

  /// Items · council · delegations of this entity (D-057): staff with `workflow` rights, the team, or org admins.
  bool get _govOn {
    if (!govEnabled()) return false;
    final s = context.read<OrgSession>();
    return s.isOrgAdmin || s.can('workflow', 'view', widget.unitId) || _cap('view_team') || _cap('manage_team');
  }

  void _seeAllRequests() => _push(t('الانضمام', 'Joining'),
      OrgUnitJoinHub(unitType: widget.unitType, unitId: widget.unitId, title: orgNameOf(_unit),
          features: _isDept ? _asList(_unit['features']) : null, embedded: true));

  List<String> _asList(dynamic v) => v is List ? v.map((e) => '$e').toList() : const [];

  // ── quick actions, only those the viewer may use ──
  List<(IconData, String, Color?, VoidCallback)> _actions() {
    final c = context.colors;
    final id = widget.unitId;
    final f = (_d?.features ?? const <String>[]).toSet();
    return [
      if (_cap('configure_join'))
        (Icons.how_to_reg_rounded, t('إعداد الانضمام', 'Joining rules'), c.primary, _seeAllRequests),
      if (_isDept) (Icons.event_rounded, t('التقويم', 'Calendar'), c.primary, () => Navigator.of(context).pushNamed('/calendar', arguments: {'dept_id': id})),
      if (_isDept && _cap('post_announcements') && f.contains('announcements'))
        (Icons.campaign_rounded, t('إعلان جديد', 'Post news'), c.accent, _openHub),
      if (_isDept && _cap('view_forms') && f.contains('forms'))
        (Icons.assignment_rounded, t('النماذج', 'Forms'), c.purple, () => _push(t('النماذج', 'Forms'), OrgFormsPage(deptId: id))),
      if (_isDept && _cap('view_complaints') && f.contains('complaints'))
        (Icons.support_agent_rounded, t('الشكاوى', 'Complaints'), c.danger,
            () => _push(t('الشكاوى', 'Complaints'), OrgComplaintsPage(deptId: id))),
      if (_isDept && _cap('view_materials') && f.contains('materials'))
        (Icons.folder_copy_rounded, t('المكتبة', 'Library'), c.accent2,
            () => _push(t('المكتبة', 'Library'), OrgMaterialsPage(deptId: id))),
      if (_isDept && _govOn && _unit['council_id'] != null)
        (Icons.gavel_rounded, t('مجلس القسم', 'Department council'), c.purple,
            () => govOpenCouncilOfDept(context, context.read<OrgSession>().currentId ?? 0, asInt(_unit['council_id']))),
      if (_isDept && _govOn && _cap('manage_team'))
        (Icons.assignment_ind_rounded, t('التفويضات', 'Delegations'), c.warning,
            () => _push(t('التفويضات', 'Delegations'), GovDelegationsPage(id, embedded: true, orgId: context.read<OrgSession>().currentId))),
      if (_cap('manage_team')) (Icons.person_add_alt_1_rounded, t('إضافة للفريق', 'Add staff'), c.success, _openHub),
      if (_isDept && (_cap('edit_unit') || _cap('view_team') || _cap('view_forms')))
        (Icons.apps_rounded, t('كل أدوات الإدارة', 'All department tools'), null, _openHub),
    ];
  }

  // ── overview blocks (side column on wide screens, first tab on phones) ──
  List<Widget> _overview({required bool wide}) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final subs = _d?.subUnits ?? const <Map<String, dynamic>>[];
    final u = _unit;
    final pad = wide ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16);
    final card = [u['location'], u['office_hours'], u['email'], u['phone']].any((x) => '${x ?? ''}'.trim().isNotEmpty);
    return [
      // governance (D-057): pending · waiting for a decision · overdue · decided, for this entity
      if (_isDept && s.currentId != null && _govOn) ...[
        _Title(t('المعاملات', 'Items')),
        Padding(padding: pad, child: GovDashboardCard(deptId: widget.unitId, orgId: s.currentId, compact: true)),
        const SizedBox(height: 16),
      ],
      if (_isDept && s.currentId != null) ...[
        _Title(t('إعلانات القسم', 'Department news')),
        Padding(
          padding: pad,
          child: OrgAnnouncementFeed(orgId: s.currentId!, deptId: widget.unitId, limit: 3, compact: true),
        ),
      ],
      if (subs.isNotEmpty) ...[
        _Title(t('الإدارات الفرعية', 'Sub-departments'), subtitle: t('${subs.length} تابعة لهذه الإدارة', '${subs.length} under this department')),
        Padding(
          padding: pad,
          child: Column(children: [
            for (final x in subs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppActionCard(
                  icon: deptIcon(x['icon']),
                  color: hexColor(x['color'], c.primary),
                  title: orgNameOf(x),
                  subtitle: x['can_open'] == true ? t('افتح لوحة الإدارة', 'Open its dashboard') : t('خارج صلاحياتك', 'Outside your access'),
                  onTap: x['can_open'] == true
                      ? () => openDepartmentDashboard(context, unitType: 'dept', unitId: asInt(x['id']), seed: x)
                      : null,
                ),
              ),
          ]),
        ),
      ],
      if (_isDept) ...[
        _Title(t('بطاقة الإدارة', 'Department card'), subtitle: t('هكذا يراها الطلاب في الدليل', 'How students see it in the directory')),
        Padding(
          padding: pad,
          child: AppCard(
            child: card
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AppInfoRow(Icons.place_rounded, '${u['location'] ?? ''}'),
                    AppInfoRow(Icons.schedule_rounded, '${u['office_hours'] ?? ''}'),
                    AppInfoRow(Icons.alternate_email_rounded, '${u['email'] ?? ''}', ltr: true),
                    AppInfoRow(Icons.phone_rounded, '${u['phone'] ?? ''}', ltr: true),
                  ])
                : Text(t('أضف المكان ومواعيد العمل ليعرف الطلاب كيف يصلون إليكم.', 'Add the place and office hours so students know how to reach you.'),
                    style: orgText(context, size: 12.5, color: c.warning)),
          ),
        ),
      ] else ...[
        _Title(t('عن القسم', 'About')),
        Padding(
          padding: pad,
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ('${u['description'] ?? ''}'.trim().isNotEmpty)
                Text('${u['description']}', style: orgText(context, color: c.textMedium)),
              AppInfoRow(Icons.tag_rounded, '${u['code'] ?? ''}', ltr: true),
              if (u['capacity'] != null)
                AppInfoRow(Icons.event_seat_rounded, t('السعة: ${u['capacity']} طالب', 'Capacity: ${u['capacity']} students')),
              if (asInt(u['min_electives']) > 0)
                AppInfoRow(Icons.alt_route_rounded, t('اختياريات مطلوبة: ${u['min_electives']}', 'Electives required: ${u['min_electives']}')),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 24),
    ];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Hero
// ═════════════════════════════════════════════════════════════════════════════

class _UnitHero extends StatelessWidget {
  const _UnitHero({required this.d, this.seed});
  final OrgUnitData d;
  final Map<String, dynamic>? seed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = d.unit;
    final mgr = d.manager;
    final isDept = d.isDept;
    final col = hexColor(u['color'] ?? seed?['color'], c.primary);
    final parent = asMap(u['parent']);
    String n(String key) => d.hidden(key) ? '—' : '${d.stat(key)}';   // a stat I may not see is null on the server
    final stats = <AppHeroStat>[
      AppHeroStat(icon: Icons.people_alt_rounded, value: n('users'), label: isDept ? t('منضمّون', 'Users') : t('طلاب', 'Students')),
      AppHeroStat(icon: Icons.badge_rounded, value: n('staff'), label: isDept ? t('الفريق', 'Team') : t('الهيئة', 'Faculty')),
      AppHeroStat(icon: Icons.menu_book_rounded, value: n('courses'), label: t('مقررات', 'Courses')),
      AppHeroStat(icon: Icons.inbox_rounded, value: '${d.waiting}', label: t('تنتظر', 'Waiting')),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [col, c.heroEnd(col, 0.28)],
        ),
        boxShadow: [BoxShadow(color: col.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(18)),
            child: isDept
                ? DeptLogo(d: {...u, 'color': u['color'] ?? seed?['color']}, size: 50)
                : SizedBox(width: 50, height: 50, child: Icon(Icons.school_rounded, color: c.onHero, size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(orgNameOf(u), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: appText(19, w: FontWeight.w800, c: c.onHero)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _GlassTag(isDept ? Icons.apartment_rounded : Icons.school_rounded,
                    isDept ? t('إدارة خدمية', 'Service department') : t('قسم علمي', 'Academic department')),
                if ('${u['code'] ?? ''}'.isNotEmpty) _GlassTag(Icons.tag_rounded, '${u['code']}'),
                if (parent.isNotEmpty) _GlassTag(Icons.subdirectory_arrow_left_rounded, t('تابعة لـ ${orgNameOf(parent)}', 'Part of ${orgNameOf(parent)}')),
                if (u['is_active'] == false) _GlassTag(Icons.archive_rounded, t('مؤرشفة', 'Archived')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (mgr.isNotEmpty) ...[
            AdminAvatar(name: '${mgr['name'] ?? ''}', url: mgr['image_url'] as String?, size: 28),
            const SizedBox(width: 8),
          ] else ...[
            Icon(Icons.person_off_rounded, color: c.onHeroMuted, size: 18),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              mgr.isEmpty
                  ? t('لم يُعيَّن مدير بعد', 'No manager yet')
                  : (isDept ? t('الرئيس: ${mgr['name']}', 'Head: ${mgr['name']}') : t('المدير: ${mgr['name']}', 'Manager: ${mgr['name']}')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(12.5, w: FontWeight.w600, c: c.onHero.withValues(alpha: 0.92)),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth >= 420) {
            return Row(children: [
              for (var i = 0; i < stats.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: stats[i])],
            ]);
          }
          return Column(children: [
            Row(children: [Expanded(child: stats[0]), const SizedBox(width: 10), Expanded(child: stats[1])]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: stats[2]), const SizedBox(width: 10), Expanded(child: stats[3])]),
          ]);
        }),
      ]),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.heroGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.heroGlassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c.onHero),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: appText(11, w: FontWeight.w700, c: c.onHero)),
          ),
        ]),
      );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});
  final List<(IconData, String, Color?, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in actions) AppPill(icon: a.$1, label: a.$2, color: a.$3, onTap: a.$4),
      ]),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label, this.badge = 0});
  final IconData icon;
  final String label;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Text(label),
      if (badge > 0) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(10)),
          child: Text(badge > 99 ? '99+' : '$badge',
              style: TextStyle(color: c.onHero, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ),
      ],
    ]);
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar, this.background);
  final TabBar tabBar;
  final Color background;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar || old.background != background;
}

/// A tab body: scrollable, pull-to-refresh, safe bottom padding.
class _TabList extends StatelessWidget {
  const _TabList({required this.children, required this.onRefresh});
  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => AppRefresh(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.only(top: 6, bottom: 48), children: children),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests: joins · forms · department choices — decided right here
// ═════════════════════════════════════════════════════════════════════════════

class _RequestsTab extends StatefulWidget {
  const _RequestsTab({required this.d, required this.unitType, required this.unitId, required this.onChanged, required this.onSeeAll});
  final OrgUnitData d;
  final String unitType;
  final int unitId;
  final Future<void> Function() onChanged;
  final VoidCallback onSeeAll;

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  final Set<String> _busy = {};

  Future<void> _act(String key, Future<dynamic> Function() fn, String ok) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    final r = await orgCall(fn, ok: ok);
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (r.ok || r.error?.statusCode == 409) await widget.onChanged();
  }

  Future<String?> _reason({required bool required}) async {
    final note = await askText(context,
        title: required ? t('سبب الرفض', 'Why is it declined?') : t('ملاحظة لصاحب الطلب (اختياري)', 'A note for the person (optional)'),
        hint: t('اكتب بلطف ما الذي ينقص', 'Kindly say what is missing'),
        multiline: true);
    if (note == null) return null;            // cancelled
    if (required && note.trim().isEmpty) {
      toast(t('اكتب سبب الرفض ليفهم صاحب الطلب ما المطلوب', 'Write a reason so the person knows what to fix'), error: true);
      return null;
    }
    return note.trim();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final api = ApiClient();
    final joins = widget.d.requests;
    final forms = widget.d.forms;
    final choices = widget.d.programChoices;
    final decide = widget.d.cap('decide_requests');
    final review = widget.d.cap('review_forms');
    final children = <Widget>[];

    // join requests
    if (decide || widget.d.cap('configure_join')) {
      final total = widget.d.stat('pending_join_requests');
      children.add(_Title(t('طلبات الانضمام', 'Join requests'),
          subtitle: total == 0 ? t('لا أحد ينتظر', 'No one is waiting') : t('$total ينتظرون ردّك', '$total waiting for you'),
          trailing: TextButton(onPressed: widget.onSeeAll, child: Text(t('الكل والإعداد', 'All & settings')))));
      if (!decide && joins.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AppBanner(icon: Icons.info_outline_rounded,
              text: t('يقرّر في هذه الطلبات مدير القسم أو المعاونون المحددون في سياسة الانضمام.',
                  'The department manager or the assistants named in the join policy decide these requests.')),
        ));
      }
      for (final r in joins) {
        final user = asMap(r['user']);
        final rid = asInt(r['id']);
        final answers = asMap(r['answers']).entries.where((e) => '${e.value}'.trim().isNotEmpty).take(2).toList();
        children.add(_RequestCard(
          avatarName: '${user['name'] ?? '—'}',
          avatarUrl: user['image_url'] as String?,
          title: '${user['name'] ?? '—'}',
          subtitle: [
            if ('${user['email'] ?? ''}'.isNotEmpty) '${user['email']}',
            relTime(r['created_at']),
          ].join(' · '),
          tags: [
            if (r['via'] == 'code') (t('بالكود', 'By code'), c.accent),
            if (r['needs_verification'] == true) (t('يحتاج تحقّقاً', 'Needs checking'), c.warning),
          ],
          lines: [for (final a in answers) '${a.key}: ${a.value}'],
          busy: _busy.contains('j$rid'),
          onApprove: decide
              ? () => _act('j$rid', () => api.post('${s.base}/join-requests/$rid/approve', body: {}), t('تم القبول 🎉', 'Accepted 🎉'))
              : null,
          onReject: decide
              ? () async {
                  final note = await _reason(required: false);
                  if (note == null) return;
                  await _act('j$rid', () => api.post('${s.base}/join-requests/$rid/reject', body: {if (note.isNotEmpty) 'note': note}),
                      t('تم الرفض', 'Declined'));
                }
              : null,
        ));
      }
    }

    // forms submitted within this department
    if (widget.d.cap('view_forms')) {
      final total = widget.d.stat('pending_forms');
      children.add(_Title(t('نماذج وطلبات للمراجعة', 'Forms to review'),
          subtitle: total == 0 ? t('كل الطلبات تمت مراجعتها', 'Everything is reviewed') : t('$total بانتظار المراجعة', '$total waiting for review'),
          trailing: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                      value: s,
                      child: BasePage(useWebCard: true, maxWith: 1100, appBar: ScreenAppBar(title: t('النماذج', 'Forms')),
                          child: OrgFormsPage(deptId: widget.unitId))))),
              child: Text(t('كل النماذج', 'All forms')))));
      for (final r in forms) {
        final user = asMap(r['user']);
        final rid = asInt(r['id']);
        children.add(_RequestCard(
          avatarName: '${user['name'] ?? '—'}',
          avatarUrl: user['image_url'] as String?,
          title: '${r['form_title'] ?? t('طلب', 'Request')}',
          subtitle: [if (user.isNotEmpty) '${user['name']}', '${r['ref'] ?? ''}', relTime(r['created_at'])]
              .where((x) => x.isNotEmpty)
              .join(' · '),
          tags: [(statusLabel('${r['status']}'), statusColor(context, '${r['status']}'))],
          lines: [
            for (final a in asMap(r['answers']).entries.where((e) => '${e.value}'.trim().isNotEmpty).take(2)) '${a.key}: ${a.value}'
          ],
          busy: _busy.contains('f$rid'),
          onApprove: review
              ? () => _act('f$rid', () => api.put('${s.base}/form-responses/$rid', body: {'status': 'approved'}),
                  t('تمت الموافقة ✅', 'Approved ✅'))
              : null,
          onReject: review
              ? () async {
                  final note = await _reason(required: true);
                  if (note == null) return;
                  await _act('f$rid', () => api.put('${s.base}/form-responses/$rid', body: {'status': 'rejected', 'note': note}),
                      t('أُعيد الطلب لصاحبه', 'Sent back to the person'));
                }
              : null,
        ));
      }
    }

    // academic: "choose your department" requests
    if (widget.d.cap('decide_program_choices')) {
      final total = widget.d.stat('pending_program_choices');
      children.add(_Title(t('طلبات اختيار القسم', 'Department choices'),
          subtitle: total == 0 ? t('لا طلبات معلّقة', 'Nothing pending') : t('$total طالب اختار هذا القسم', '$total students chose this department')));
      for (final r in choices) {
        final user = asMap(r['user']);
        final uid = asInt(r['user_id']);
        children.add(_RequestCard(
          avatarName: '${user['name'] ?? '—'}',
          avatarUrl: user['image_url'] as String?,
          title: '${user['name'] ?? '—'}',
          subtitle: [if ('${user['email'] ?? ''}'.isNotEmpty) '${user['email']}', relTime(r['requested_at'])].join(' · '),
          tags: const [],
          lines: const [],
          busy: _busy.contains('p$uid'),
          onApprove: () => _act('p$uid', () => api.post('${s.base}/academic/students/$uid/request/approve', body: {}),
              t('انضم الطالب للقسم 🎉', 'The student joined the department 🎉')),
          onReject: () async {
            final note = await _reason(required: false);
            if (note == null) return;
            await _act('p$uid', () => api.post('${s.base}/academic/students/$uid/request/reject', body: {if (note.isNotEmpty) 'note': note}),
                t('تم الرفض', 'Declined'));
          },
        ));
      }
    }

    final nothing = joins.isEmpty && forms.isEmpty && choices.isEmpty;
    if (nothing) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AppBanner(
          icon: Icons.spa_rounded,
          color: c.success,
          text: t('لا شيء ينتظرك في هذا القسم — كل شيء على ما يرام 🌿', 'Nothing is waiting in this department — all good 🌿'),
        ),
      ));
    }
    return _TabList(onRefresh: widget.onChanged, children: children);
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.avatarName,
    required this.avatarUrl,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.lines,
    required this.busy,
    this.onApprove,
    this.onReject,
  });
  final String avatarName, title, subtitle;
  final String? avatarUrl;
  final List<(String, Color)> tags;
  final List<String> lines;
  final bool busy;
  final VoidCallback? onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = onApprove != null || onReject != null;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AdminAvatar(name: avatarName, url: avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 14, w: FontWeight.w800)),
              if (subtitle.isNotEmpty)
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 11.5, color: c.textLight)),
            ]),
          ),
        ]),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final tg in tags) AppBadgePill(tg.$1, color: tg.$2)]),
        ],
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
          ),
        if (actions) ...[
          const SizedBox(height: 10),
          if (busy)
            const Align(alignment: AlignmentDirectional.centerEnd, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
          else
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
              if (onReject != null)
                OutlinedButton.icon(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger.withValues(alpha: 0.4))),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(t('رفض', 'Decline')),
                ),
              if (onApprove != null)
                FilledButton.icon(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(backgroundColor: c.success),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(t('قبول', 'Accept')),
                ),
            ]),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Users (joined) · Members (staff)
// ═════════════════════════════════════════════════════════════════════════════

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.d, required this.unitType, required this.unitId, required this.onChanged});
  final OrgUnitData d;
  final String unitType;
  final int unitId;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final rows = d.users;
    final total = d.stat('users');
    final canRemove = d.cap('remove_users');
    final isDept = unitType == 'dept';
    if (rows.isEmpty) {
      return _TabList(onRefresh: onChanged, children: [
        AppEmpty(
          icon: Icons.people_outline_rounded,
          title: isDept ? t('لم ينضم أحد بعد', 'No one has joined yet') : t('لا طلاب في هذا القسم بعد', 'No students in this department yet'),
          message: isDept
              ? t('افتح الانضمام من "إعداد الانضمام" ليصل الطلاب إلى هذه الإدارة.', 'Open joining from "Joining rules" so students can reach this department.')
              : t('يظهر هنا كل طالب يلتحق بالقسم عبر المسار الأكاديمي.', 'Every student who joins through the academic path appears here.'),
        ),
      ]);
    }
    return _TabList(onRefresh: onChanged, children: [
      _Title(isDept ? t('المنضمّون للإدارة', 'People who joined') : t('طلاب القسم', 'Students of the department'),
          subtitle: total > rows.length ? t('أحدث ${rows.length} من $total', 'Latest ${rows.length} of $total') : t('$total شخص', '$total people')),
      for (final r in rows)
        _PersonRow(
          user: asMap(r['user']),
          caption: [
            if (r['stage'] != null) r['stage'] == 'graduated' ? t('خريج', 'Graduate') : t('طالب بالقسم', 'In the department'),
            if (r['joined_via'] != null) _via('${r['joined_via']}'),
            if (orgParseUtc(r['joined_at']) != null) t('منذ ${AppTime.date(orgParseUtc(r['joined_at'])!.toUtc())}', 'since ${AppTime.date(orgParseUtc(r['joined_at'])!.toUtc())}'),
          ].join(' · '),
          trailing: canRemove && isDept
              ? IconButton(
                  tooltip: t('إنهاء العضوية', 'Remove'),
                  icon: Icon(Icons.person_remove_rounded, color: c.danger),
                  onPressed: () async {
                    final uid = asInt(asMap(r['user'])['id']);
                    if (!await appConfirm(context,
                        message: t('إنهاء عضوية ${asMap(r['user'])['name']} في هذه الإدارة؟', 'End ${asMap(r['user'])['name']}\'s membership here?'),
                        danger: true)) {
                      return;
                    }
                    final res = await orgCall(() => ApiClient().delete('${s.base}/units/$unitType/$unitId/members/$uid'),
                        ok: t('تم', 'Done'));
                    if (res.ok) await onChanged();
                  },
                )
              : null,
        ),
      if (total > rows.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: AppBanner(icon: Icons.list_alt_rounded,
              text: t('القائمة الكاملة وأدوات الإزالة في "إعداد الانضمام".', 'The full list and removal tools are in "Joining rules".')),
        ),
    ]);
  }

  static String _via(String v) => switch (v) {
        'auto' => t('انضمام مباشر', 'Joined directly'),
        'approval' => t('بموافقة', 'Approved'),
        'code' => t('بكود', 'With a code'),
        _ => t('أضافه فريق الإدارة', 'Added by staff'),
      };
}

class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.d, required this.isDept, required this.onManage, required this.onRefresh});
  final OrgUnitData d;
  final bool isDept;
  final VoidCallback? onManage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = d.team;
    final total = d.stat('staff');
    return _TabList(onRefresh: onRefresh, children: [
      _Title(isDept ? t('فريق الإدارة', 'Department team') : t('هيئة التدريس بالقسم', 'Department faculty'),
          subtitle: isDept
              ? t('صلاحياتهم تنطبق على هذه الإدارة فقط', 'Their rights apply to this department only')
              : t('المدرسون والمعيدون المنتسبون للقسم', 'Teachers and assistants affiliated with it'),
          trailing: onManage == null
              ? null
              : TextButton.icon(onPressed: onManage, icon: const Icon(Icons.manage_accounts_rounded, size: 18), label: Text(t('إدارة الفريق', 'Manage team')))),
      if (rows.isEmpty)
        AppEmpty(
          icon: Icons.badge_outlined,
          title: isDept ? t('الفريق فارغ', 'No team yet') : t('لا أعضاء هيئة بعد', 'No faculty yet'),
          message: isDept
              ? t('أضف رئيس الإدارة والموظفين — تُمنح صلاحياتهم لهذه الإدارة فقط.', 'Add the head and staff — their rights apply here only.')
              : t('حدّد القسم العلمي للمدرسين من صفحة الأعضاء.', 'Set teachers\' academic department from the People page.'),
          actionLabel: onManage == null ? null : t('إضافة للفريق', 'Add staff'),
          onAction: onManage,
        )
      else
        for (final r in rows)
          _PersonRow(
            user: asMap(r['user']),
            caption: [
              if ('${r['title'] ?? ''}'.isNotEmpty) '${r['title']}',
              if (r['role'] != null) memberRoleLabels()['${r['role']}'] ?? '${r['role']}',
            ].join(' · '),
            trailing: r['is_head'] == true
                ? AppBadgePill(isDept ? t('الرئيس', 'Head') : t('المدير', 'Manager'), color: c.warning, icon: Icons.star_rounded)
                : null,
          ),
      if (total > rows.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(t('و${total - rows.length} آخرون', 'and ${total - rows.length} more'), style: orgText(context, color: c.textMedium)),
        ),
    ]);
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user, required this.caption, this.trailing});
  final Map<String, dynamic> user;
  final String caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        AdminAvatar(name: '${user['name'] ?? '—'}', url: user['image_url'] as String?, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${user['name'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
            Text(caption.isEmpty ? '${user['email'] ?? ''}' : caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: orgText(context, size: 11.5, color: c.textLight)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// Section title with the page's side gutter.
class _Title extends StatelessWidget {
  const _Title(this.title, {this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AppSectionTitle(title, subtitle: subtitle, trailing: trailing),
      );
}
