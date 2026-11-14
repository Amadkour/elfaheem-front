// lib/features/org/org_home_tab.dart
//
// The student / teacher home in two calm tabs — "My courses" | "My organization" (members only):
//   HomeTabsBar   the premium segmented switch (hidden for people outside any organization)
//   OrgHomeTab    the organization, organized: who / what needs me / today / news / departments (each showing ONLY
//                 the services that department enabled) / quick links
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';
import 'org_availability_pages.dart' show AvailabilityRequestScreen;
import 'org_common.dart';
import 'org_departments_page.dart' show DeptLogo, featureLabels;
import 'org_member_parts.dart';
import 'org_member_space.dart' show OrgFormFillScreen, showComplaintComposer;
import 'org_my_exams.dart' show appToday, examPauseBanner, examPauseOn, examPausesOf;
import 'org_providers.dart' show orgBase;
import 'org_ui.dart';
import 'home_org_mix.dart' show academicPathRoute, showPlatformRequirement;

/// 0 = my courses · 1 = my organization (kept while the app runs)
final ValueNotifier<int> homeTab = ValueNotifier(0);
final ValueNotifier<bool> homeInOrg = ValueNotifier(false);
final Listenable homeTabs = Listenable.merge([homeTab, homeInOrg]);

Map<String, dynamic>? _mixCache;

Future<Map<String, dynamic>?> _mix({bool refresh = false}) async {
  if (_mixCache != null && !refresh) return _mixCache;
  try {
    final r = await ApiClient().get('/api/v1/home/mix');
    if (r is Map) {
      _mixCache = Map<String, dynamic>.from(r);
      homeInOrg.value = AppConfig.orgsEnabled && asMapList(_mixCache!['organizations']).isNotEmpty;
    }
  } catch (_) {}
  return _mixCache;
}

class HomeTabsBar extends StatefulWidget {
  const HomeTabsBar({super.key, this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.sm)});
  final EdgeInsetsGeometry padding;

  @override
  State<HomeTabsBar> createState() => _HomeTabsBarState();
}

class _HomeTabsBarState extends State<HomeTabsBar> {
  @override
  void initState() {
    super.initState();
    _mix(refresh: true).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homeTabs,
      builder: (context, _) {
        if (!AppConfig.orgsEnabled || AppConfig.disableList.contains('home.org_tab')) {
          // organizations switched off by the platform: drop the tab and fall back to "My courses"
          if (homeInOrg.value || homeTab.value != 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              homeTab.value = 0;
              homeInOrg.value = false;
            });
          }
          return const SizedBox.shrink();
        }
        if (!homeInOrg.value) return const SizedBox.shrink();
        final org = asMapList(_mixCache?['organizations']).firstOrNull ?? const {};
        return Padding(
          padding: widget.padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AppTabs(
                expand: true,
                index: homeTab.value,
                onChanged: (i) => homeTab.value = i,
                items: [
                  AppTabItem(t('كورساتي', 'My courses'), icon: Icons.auto_stories_rounded),
                  AppTabItem(org.isEmpty ? t('مؤسستي', 'My organization') : orgNameOf(org), icon: Icons.account_balance_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class OrgHomeTab extends StatefulWidget {
  const OrgHomeTab({super.key});

  @override
  State<OrgHomeTab> createState() => _OrgHomeTabState();
}

class _OrgHomeTabState extends State<OrgHomeTab> {
  Map<String, dynamic>? _mixData;
  int? _orgId;
  List<Map<String, dynamic>> _news = const [], _depts = const [], _week = const [], _extras = const [];
  List<Map<String, dynamic>> _scheds = const []; // /schedule/me timetables (their exam_pauses)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final m = await _mix(refresh: true);
    final orgs = asMapList(m?['organizations']);
    _orgId ??= orgs.isEmpty ? null : asInt(orgs.first['id']);
    final id = _orgId;
    if (id == null) {
      if (mounted) {
        setState(() {
          _mixData = m; // null = the mix failed (the tab shows a Retry); a map without organizations = not a member
          _loading = false;
        });
      }
      return;
    }
    final res = await Future.wait([
      _get('$orgBase/public/me/feed', {'size': 20}),
      _get('$orgBase/public/$id/departments'),
      _get('$orgBase/public/schedule/me', {'org_id': id}),
    ]);
    if (!mounted) return;
    final sched = asMapList(res[2]?['items']);
    setState(() {
      _mixData = m;
      _news = asMapList(res[0]?['items']).where((n) => asInt(asMap(n['organization'])['id'], id) == id).take(3).toList();
      _depts = asMapList(res[1]?['items']);
      _week = [for (final s in sched) ...asMapList(s['items'])];
      _scheds = sched;
      _extras = [for (final s in sched) ...asMapList(s['extras'])];
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _get(String path, [Map<String, dynamic>? q]) async {
    try {
      final r = await ApiClient().get(path, queryParams: q);
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> get _org => asMapList(_mixData?['organizations']).firstWhere((o) => asInt(o['id']) == _orgId, orElse: () => const {});

  void _openSpace([int tab = 0]) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => deferredOrgMemberSpace(org: _org, initialTab: tab)))
      .then((_) => _load());

  Future<void> _openRequired(Map<String, dynamic> r) async {
    final nav = Navigator.of(context);
    switch ('${r['kind']}') {
      case 'form':
        await nav.push(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(r['id']))));
      case 'availability':
        await nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AvailabilityRequestScreen(requestId: asInt(r['id']))));
      case 'platform':
        await showPlatformRequirement(context, r);
      case 'department_choice':
        await nav.push(academicPathRoute(asInt(r['org_id'])));
      default:
        _openSpace(4);                                   // regulations
    }
    _load();
  }

  String _today() => const ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'][appToday().weekday - 1]; // the AppTime day (org timezone)

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading && _mixData == null) {
      return const SizedBox(height: 300, child: AppListSkeleton(items: 3));
    }
    final org = _org;
    if (org.isEmpty) {
      // the mix never arrived (offline / server error): a slim Retry instead of an empty tab; no organization → nothing
      return _mixData != null
          ? const SizedBox.shrink()
          : Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppErrorState(compact: true, onRetry: _load));
    }
    final orgs = asMapList(_mixData?['organizations']);
    final req = asMapList(_mixData?['required']).where((r) => asInt(r['org_id'], _orgId ?? 0) == _orgId).toList();
    // weekly sessions of a timetable whose term is in a published exam window today are paused (member_exams.py)
    final day = appToday();
    final today = [
      for (final s in _scheds)
        if (examPauseOn(day, examPausesOf(s)) == null) ...asMapList(s['items']).where((x) => x['day'] == _today()),
    ]..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
    final pauses = {for (final s in _scheds) for (final p in examPausesOf(s)) asInt(p['exam_schedule_id']): p}.values.toList();
    final todayStr = day.toIso8601String().substring(0, 10); // the AppTime day, like the classes above
    final todayExtras = _extras.where((e) => e['date'] == todayStr).toList();
    final upcoming = _extras.where((e) => '${e['date']}'.compareTo(todayStr) > 0).take(3).toList();
    final logo = '${org['logo_url'] ?? ''}';
    final col = orgColor(context, org);
    return AppRefresh(
      onRefresh: _load,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── who: a calm card (the tab above already names it; the gradient belongs to the page header) ──
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: AppTouch.primary,
                      height: AppTouch.primary,
                      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.card)),
                      clipBehavior: Clip.antiAlias,
                      child: logo.isEmpty
                          ? Icon(orgTypeIcons[org['type']] ?? Icons.account_balance_rounded, color: col)
                          : Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.account_balance_rounded, color: col)),
                    ),
                    AppSpace.gapSm,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(orgNameOf(org), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                        if ((orgTypeLabels()[org['type']] ?? '').isNotEmpty)
                          Text(orgTypeLabels()[org['type']] ?? '', style: AppType.meta(context)),
                      ]),
                    ),
                    if (orgs.length > 1)
                      PopupMenuButton<int>(
                        tooltip: t('تبديل المؤسسة', 'Switch organization'),
                        icon: Icon(Icons.swap_horiz_rounded, color: c.textMedium),
                        onSelected: (v) {
                          _orgId = v;
                          _load();
                        },
                        itemBuilder: (_) => [for (final o in orgs) PopupMenuItem(value: asInt(o['id']), child: Text(orgNameOf(o)))],
                      ),
                  ]),
                  AppSpace.gapSm,
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppPill(
                      label: t('فتح مساحة المؤسسة', 'Open the organization space'),
                      icon: Icons.apartment_rounded,
                      onTap: () => _openSpace(),
                    ),
                  ),
                ]),
              ),
              // ── what needs me ──
              if (req.isNotEmpty) ...[
                AppSpace.gapLg,
                AppSection(
                  title: t('مطلوب منك', 'Needs your action'),
                  child: Column(children: [
                    for (final r in req)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: MemberRow(
                          icon: {'form': Icons.edit_document, 'availability': Icons.event_available_rounded,
                            'department_choice': Icons.how_to_vote_rounded}['${r['kind']}'] ?? Icons.gavel_rounded,
                          tone: c.warning,
                          title: '${r['title']}',
                          subtitle: {'form': t('نموذج إلزامي', 'Mandatory form'), 'availability': t('أرسل مواعيدك المتاحة', 'Send your available periods'),
                            'department_choice': t('اختر قسمك العلمي', 'Choose your department')}['${r['kind']}'] ?? t('لائحة تحتاج موافقتك', 'Needs your agreement'),
                          onTap: () => _openRequired(r),
                        ),
                      ),
                  ]),
                ),
              ],
              // ── today ──
              AppSpace.gapLg,
              AppSection(
                title: t('اليوم', 'Today'),
                trailing: _week.isEmpty
                    ? null
                    : AppPill(icon: Icons.calendar_view_week_rounded, label: t('الأسبوع كاملاً', 'Full week'), onTap: () => _weekSheet(context)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  examPauseBanner(context, pauses),
                  if (today.isEmpty && todayExtras.isEmpty)
                    MemberNote(t('لا محاضرات اليوم — استمتع بيومك', 'No classes today — enjoy your day'), icon: Icons.wb_sunny_rounded)
                  else ...[
                    for (final x in todayExtras) _slot(context, x, special: true),
                    for (final x in today) _slot(context, x),
                  ],
                  for (final x in upcoming) _slot(context, x, special: true, showDate: true),
                ]),
              ),
              // ── news ──
              AppSpace.gapLg,
              AppSection(
                title: t('الأخبار والإعلانات', 'News & announcements'),
                trailing: AppPill(icon: Icons.campaign_rounded, label: t('كل الأخبار', 'All news'), onTap: () => _openSpace(0)),
                child: _news.isEmpty
                    ? MemberNote(t('لا جديد الآن', 'Nothing new right now'), icon: Icons.campaign_outlined)
                    : Column(children: [
                        for (final n in _news)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.xs),
                            child: AppCard(
                              onTap: () => _openSpace(0),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (n['pinned'] == true)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                                    child: Icon(Icons.push_pin_rounded, size: AppIconSize.sm, color: c.warning),
                                  ),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${n['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                                    if ('${n['body'] ?? ''}'.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                                        child: Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: AppType.body(context).copyWith(color: c.textMedium)),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: AppSpace.xs),
                                      child: Text('${n['department'] == null ? '' : '${orgNameOf(asMap(n['department']))} · '}${relTime(n['publish_at'])}',
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                      ]),
              ),
              // ── departments ──
              if (_depts.isNotEmpty) ...[
                AppSpace.gapLg,
                AppSection(
                  title: t('الإدارات والخدمات', 'Departments & services'),
                  child: LayoutBuilder(builder: (context, box) {
                    final cols = box.maxWidth > 760 ? 4 : (box.maxWidth > 480 ? 3 : 2);
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpace.xs,
                      crossAxisSpacing: AppSpace.xs,
                      childAspectRatio: 1.4,
                      children: [
                        for (final d in _depts)
                          AppCard(
                            onTap: () => _deptSheet(context, d),
                            padding: const EdgeInsets.all(AppSpace.sm),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              DeptLogo(d: d, size: 40),
                              AppSpace.gapXs,
                              Flexible(
                                child: Text(t('${d['name_ar'] ?? d['name_en']}', '${d['name_en'] ?? d['name_ar']}'),
                                    maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                              ),
                            ]),
                          ),
                      ],
                    );
                  }),
                ),
              ],
              // ── quick links ──
              AppSpace.gapLg,
              AppSection(
                title: t('روابط سريعة', 'Quick links'),
                child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  AppPill(icon: Icons.assignment_rounded, label: t('طلباتي', 'My requests'), onTap: () => _openSpace(2)),
                  AppPill(icon: Icons.support_agent_rounded, label: t('شكاواي', 'My complaints'), onTap: () => _openSpace(3)),
                  AppPill(icon: Icons.gavel_rounded, label: t('اللوائح', 'Regulations'), onTap: () => _openSpace(4)),
                  AppPill(icon: Icons.route_rounded, label: t('مساري الأكاديمي', 'My academic path'), onTap: () => _openSpace(5)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One slot of the day (a weekly slot, a dated extra, an upcoming extra with its date).
  Widget _slot(BuildContext context, Map<String, dynamic> x, {bool special = false, bool showDate = false}) {
    final c = context.colors;
    final lab = x['kind'] == 'lab';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: MemberSlotTile(
        start: AppTime.clock(x['start_time']?.toString()),
        end: AppTime.clock(x['end_time']?.toString()),
        title: '${x['title'] ?? x['course'] ?? ''}',
        accent: special ? c.accent2 : (lab ? c.purple : c.primary),
        where: [
          if (special) (showDate ? shortDate('${x['date']}') : t('موعد إضافي', 'Extra session')),
          if (x['title'] != null && x['course'] != null) '${x['course']}',
          if (x['room'] != null) '${x['room']}',
          if (x['teacher'] != null) '${x['teacher']}',
        ].join(' · '),
        tags: [
          if (lab) AppStatusBadge(label: t('سكشن', 'Lab'), tone: AppTone.brand, dense: true),
          if (special) AppStatusBadge(label: t('خاص', 'Special'), tone: AppTone.info, dense: true),
        ],
      ),
    );
  }

  Future<void> _weekSheet(BuildContext context) async {
    final days = const ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
    final names = {'saturday': t('السبت', 'Saturday'), 'sunday': t('الأحد', 'Sunday'), 'monday': t('الاثنين', 'Monday'),
      'tuesday': t('الثلاثاء', 'Tuesday'), 'wednesday': t('الأربعاء', 'Wednesday'), 'thursday': t('الخميس', 'Thursday'), 'friday': t('الجمعة', 'Friday')};
    await showAppSheet<void>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg), children: [
          AppSheetHeader(t('جدولي الأسبوعي', 'My week')),
          for (final d in days)
            if (_week.any((x) => x['day'] == d)) ...[
              Padding(padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.sm, AppSpace.xxs, AppSpace.xs), child: Text(names[d]!, style: AppType.label(ctx))),
              for (final x in (_week.where((x) => x['day'] == d).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'))))
                _slot(ctx, x),
            ],
        ]));
  }

  /// A department's services — ONLY what that department switched on.
  Future<void> _deptSheet(BuildContext context, Map<String, dynamic> d) async {
    final f = {...((d['features'] as List?) ?? const []).map((e) => '$e')};
    final labels = featureLabels();
    await showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final actions = <Widget>[
        if (f.contains('forms'))
          MemberRow(icon: Icons.assignment_rounded, tone: c.purple, title: t('الطلبات والاستبيانات', 'Requests & questionnaires'),
              subtitle: t('قدّم طلباً أو أجب عن استبيان', 'Send a request or answer a questionnaire'), onTap: () { Navigator.pop(ctx); _openSpace(2); }),
        if (f.contains('complaints'))
          MemberRow(icon: Icons.support_agent_rounded, tone: c.danger, title: t('شكوى لهذه الإدارة', 'A complaint to this department'),
              subtitle: t('تصل مباشرة لفريقها', 'Goes straight to its team'), onTap: () async {
                Navigator.pop(ctx);
                await showComplaintComposer(context, _org, dept: d);
              }),
        if (f.contains('announcements'))
          MemberRow(icon: Icons.campaign_rounded, tone: c.accent2, title: labels['announcements'] ?? '',
              subtitle: t('أخبار وإعلانات الإدارة', 'Its news and announcements'), onTap: () { Navigator.pop(ctx); _openSpace(0); }),
        if (f.contains('materials'))
          MemberRow(icon: Icons.folder_copy_rounded, tone: c.primary, title: labels['materials'] ?? '',
              subtitle: t('ملفات وروابط الإدارة', 'Its files and links'), onTap: () { Navigator.pop(ctx); _openSpace(1); }),
      ];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DeptLogo(d: d, size: 48),
            AppSpace.gapSm,
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('${d['name_ar'] ?? d['name_en']}', '${d['name_en'] ?? d['name_ar']}'), style: AppType.section(ctx)),
              if ('${d['office_hours'] ?? ''}'.isNotEmpty) Text('${d['office_hours']}', style: AppType.meta(ctx)),
            ])),
          ]),
          if ('${d['description'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text('${d['description']}', style: AppType.body(ctx).copyWith(color: c.textMedium))),
          AppSpace.gapSm,
          if (actions.isEmpty)
            MemberNote(t('لا خدمات متاحة من هذه الإدارة حالياً', 'This department offers no services right now'))
          else
            for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: a),
        ]),
      );
    });
  }
}
