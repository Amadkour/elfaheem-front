// lib/features/org/org_home_tab.dart
//
// The student / teacher home in two calm tabs — "My courses" | "My organization" (members only):
//   HomeTabsBar   the premium segmented switch (hidden for people outside any organization)
//   OrgHomeTab    the organization, organized: who / what needs me / today / news / departments (each showing ONLY
//                 the services that department enabled) / quick links
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart';
import 'org_academic_pages.dart' show MyAcademicPathPage;
import 'org_availability_pages.dart' show AvailabilityRequestScreen;
import 'org_common.dart';
import 'org_departments_page.dart' show DeptLogo, featureLabels;
import 'org_member_space.dart' show OrgFormFillScreen, OrgMemberSpace, showComplaintComposer;
import 'org_providers.dart' show orgBase;
import 'org_ui.dart';
import 'home_org_mix.dart' show showPlatformRequirement;

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
  const HomeTabsBar({super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 14)});
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
        final c = context.colors;
        final org = asMapList(_mixCache?['organizations']).firstOrNull ?? const {};
        Widget tab(int i, IconData icon, String label) {
          final on = homeTab.value == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => homeTab.value = i,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: on ? LinearGradient(colors: [c.primary, c.primaryDark]) : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: on ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))] : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 19, color: on ? Colors.white : c.textMedium),
                  const SizedBox(width: 8),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: on ? Colors.white : c.textMedium))),
                ]),
              ),
            ),
          );
        }
        return Padding(
          padding: widget.padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.divider), boxShadow: c.cardShadow),
                child: Row(children: [
                  tab(0, Icons.auto_stories_rounded, t('كورساتي', 'My courses')),
                  tab(1, Icons.account_balance_rounded, org.isEmpty ? t('مؤسستي', 'My organization') : orgNameOf(org)),
                ]),
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
      if (mounted) setState(() => _loading = false);
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
      .push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: _org, initialTab: tab)))
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
        await nav.push(MaterialPageRoute(builder: (_) => BasePage(useWebCard: true, maxWith: 760,
            appBar: ScreenAppBar(title: t('مساري الأكاديمي', 'My academic path')), child: MyAcademicPathPage(orgId: asInt(r['org_id'])))));
      default:
        _openSpace(4);                                   // regulations
    }
    _load();
  }

  String _today() => const ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'][DateTime.now().weekday - 1];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading && _mixData == null) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    final org = _org;
    if (org.isEmpty) return const SizedBox.shrink();
    final orgs = asMapList(_mixData?['organizations']);
    final req = asMapList(_mixData?['required']).where((r) => asInt(r['org_id'], _orgId ?? 0) == _orgId).toList();
    final today = _week.where((x) => x['day'] == _today()).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final todayExtras = _extras.where((e) => e['date'] == todayStr).toList();
    final upcoming = _extras.where((e) => '${e['date']}'.compareTo(todayStr) > 0).take(3).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── who ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd,
                      colors: [orgColor(context, org), Color.lerp(orgColor(context, org), Colors.black, 0.35)!]),
                ),
                child: Row(children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    clipBehavior: Clip.antiAlias,
                    child: '${org['logo_url'] ?? ''}'.isEmpty
                        ? Icon(orgTypeIcons[org['type']] ?? Icons.account_balance_rounded, color: orgColor(context, org))
                        : Image.network('${org['logo_url']}', fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(Icons.account_balance_rounded, color: orgColor(context, org))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(orgNameOf(org), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(orgTypeLabels()[org['type']] ?? '', style: TextStyle(fontFamily: 'tajawal', color: Colors.white.withValues(alpha: 0.85))),
                  ])),
                  if (orgs.length > 1)
                    PopupMenuButton<int>(
                      icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
                      onSelected: (v) {
                        _orgId = v;
                        _load();
                      },
                      itemBuilder: (_) => [for (final o in orgs) PopupMenuItem(value: asInt(o['id']), child: Text(orgNameOf(o)))],
                    ),
                  IconButton(onPressed: () => _openSpace(), icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                      tooltip: t('مساحة المؤسسة', 'Organization space')),
                ]),
              ),
              // ── what needs me ──
              if (req.isNotEmpty) ...[
                _title(t('مطلوب منك', 'Needs your action'), Icons.notification_important_rounded, c.warning),
                for (final r in req)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OrgActionCard(
                      icon: {'form': Icons.edit_document, 'availability': Icons.event_available_rounded,
                        'department_choice': Icons.how_to_vote_rounded}['${r['kind']}'] ?? Icons.gavel_rounded,
                      color: c.warning,
                      title: '${r['title']}',
                      subtitle: {'form': t('نموذج إلزامي', 'Mandatory form'), 'availability': t('أرسل مواعيدك المتاحة', 'Send your available periods'),
                        'department_choice': t('اختر قسمك العلمي', 'Choose your department')}['${r['kind']}'] ?? t('لائحة تحتاج موافقتك', 'Needs your agreement'),
                      onTap: () => _openRequired(r),
                    ),
                  ),
              ],
              // ── today ──
              _title(t('اليوم', 'Today'), Icons.today_rounded, c.primary,
                  action: _week.isEmpty ? null : (t('الأسبوع كاملاً', 'Full week'), () => _weekSheet(context))),
              if (today.isEmpty && todayExtras.isEmpty)
                _soft(Icons.wb_sunny_rounded, t('لا محاضرات اليوم — استمتع بيومك 🌿', 'No classes today — enjoy your day 🌿'))
              else ...[
                for (final x in todayExtras) _slotTile(context, x, special: true),
                for (final x in today) _slotTile(context, x),
              ],
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final x in upcoming) _slotTile(context, x, special: true, showDate: true),
              ],
              // ── news ──
              _title(t('الأخبار والإعلانات', 'News & announcements'), Icons.campaign_rounded, c.accent2,
                  action: (t('الكل', 'All'), () => _openSpace(0))),
              if (_news.isEmpty)
                _soft(Icons.campaign_outlined, t('لا جديد الآن', 'Nothing new right now'))
              else
                for (final n in _news)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.divider)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (n['pinned'] == true) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Icon(Icons.push_pin_rounded, size: 16, color: c.warning)),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${n['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
                        if ('${n['body'] ?? ''}'.isNotEmpty)
                          Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5, color: c.textMedium)),
                        const SizedBox(height: 4),
                        Text('${asMap(n['department'])['name_ar'] ?? asMap(n['department'])['name_en'] ?? ''}${n['department'] == null ? '' : ' · '}${relTime(n['publish_at'])}',
                            style: orgText(context, size: 11.5, color: c.textLight)),
                      ])),
                    ]),
                  ),
              // ── departments ──
              if (_depts.isNotEmpty) ...[
                _title(t('الإدارات والخدمات', 'Departments & services'), Icons.apartment_rounded, c.purple),
                LayoutBuilder(builder: (context, box) {
                  final cols = box.maxWidth > 760 ? 4 : (box.maxWidth > 480 ? 3 : 2);
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [
                      for (final d in _depts)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _deptSheet(context, d),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: hexColor(d['color'], c.primary).withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: hexColor(d['color'], c.primary).withValues(alpha: 0.22)),
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              DeptLogo(d: d, size: 40),
                              const SizedBox(height: 8),
                              Text(t('${d['name_ar'] ?? d['name_en']}', '${d['name_en'] ?? d['name_ar']}'), maxLines: 2, textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis, style: orgText(context, size: 12.5, w: FontWeight.w800)),
                            ]),
                          ),
                        ),
                    ],
                  );
                }),
              ],
              // ── quick links ──
              _title(t('روابط سريعة', 'Quick links'), Icons.bolt_rounded, c.primary),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(avatar: const Icon(Icons.assignment_rounded, size: 18), label: Text(t('طلباتي', 'My requests')), onPressed: () => _openSpace(2)),
                ActionChip(avatar: const Icon(Icons.support_agent_rounded, size: 18), label: Text(t('شكاواي', 'My complaints')), onPressed: () => _openSpace(3)),
                ActionChip(avatar: const Icon(Icons.gavel_rounded, size: 18), label: Text(t('اللوائح', 'Regulations')), onPressed: () => _openSpace(4)),
                ActionChip(avatar: const Icon(Icons.route_rounded, size: 18), label: Text(t('مساري الأكاديمي', 'My academic path')), onPressed: () => _openSpace(5)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _title(String text, IconData icon, Color col, {(String, VoidCallback)? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: col),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: orgText(context, size: 16, w: FontWeight.w800))),
          if (action != null) TextButton(onPressed: action.$2, child: Text(action.$1)),
        ]),
      );

  Widget _soft(IconData icon, String text) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Icon(icon, color: c.textLight),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: orgText(context, color: c.textMedium))),
      ]),
    );
  }

  Widget _slotTile(BuildContext context, Map<String, dynamic> x, {bool special = false, bool showDate = false}) {
    final c = context.colors;
    final lab = x['kind'] == 'lab';
    final tone = special ? c.accent2 : (lab ? c.purple : c.primary);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: tone.withValues(alpha: 0.25))),
      child: Row(children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('${x['start_time'] ?? ''}', style: orgText(context, size: 13, w: FontWeight.w800, color: tone)),
            Text('${x['end_time'] ?? ''}', style: orgText(context, size: 11, color: c.textMedium)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${x['title'] ?? x['course'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
          Text([
            if (special) (showDate ? shortDate('${x['date']}') : t('موعد إضافي', 'Extra session')),
            if (x['title'] != null && x['course'] != null) '${x['course']}',
            if (x['room'] != null) '${x['room']}',
            if (x['teacher'] != null) '${x['teacher']}',
          ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
        ])),
        if (lab) OrgPill(t('سكشن', 'Lab'), color: c.purple),
        if (special) OrgPill(t('خاص', 'Special'), color: c.accent2),
      ]),
    );
  }

  Future<void> _weekSheet(BuildContext context) async {
    final days = const ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
    final names = {'saturday': t('السبت', 'Saturday'), 'sunday': t('الأحد', 'Sunday'), 'monday': t('الاثنين', 'Monday'),
      'tuesday': t('الثلاثاء', 'Tuesday'), 'wednesday': t('الأربعاء', 'Wednesday'), 'thursday': t('الخميس', 'Thursday'), 'friday': t('الجمعة', 'Friday')};
    await showAdminSheet<void>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SheetHeader(t('جدولي الأسبوعي', 'My week')),
          for (final d in days)
            if (_week.any((x) => x['day'] == d)) ...[
              Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 6), child: Text(names[d]!, style: orgText(ctx, w: FontWeight.w800))),
              for (final x in (_week.where((x) => x['day'] == d).toList()..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'))))
                _slotTile(ctx, x),
            ],
        ]));
  }

  /// A department's services — ONLY what that department switched on.
  Future<void> _deptSheet(BuildContext context, Map<String, dynamic> d) async {
    final f = {...((d['features'] as List?) ?? const []).map((e) => '$e')};
    final labels = featureLabels();
    await showAdminSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final actions = <Widget>[
        if (f.contains('forms'))
          OrgActionCard(icon: Icons.assignment_rounded, color: c.purple, title: t('الطلبات والاستبيانات', 'Requests & questionnaires'),
              subtitle: t('قدّم طلباً أو أجب عن استبيان', 'Send a request or answer a questionnaire'), onTap: () { Navigator.pop(ctx); _openSpace(2); }),
        if (f.contains('complaints'))
          OrgActionCard(icon: Icons.support_agent_rounded, color: c.danger, title: t('شكوى لهذه الإدارة', 'A complaint to this department'),
              subtitle: t('تصل مباشرة لفريقها', 'Goes straight to its team'), onTap: () async {
                Navigator.pop(ctx);
                await showComplaintComposer(context, _org, dept: d);
              }),
        if (f.contains('announcements'))
          OrgActionCard(icon: Icons.campaign_rounded, color: c.accent2, title: labels['announcements'] ?? '',
              subtitle: t('أخبار وإعلانات الإدارة', 'Its news and announcements'), onTap: () { Navigator.pop(ctx); _openSpace(0); }),
        if (f.contains('materials'))
          OrgActionCard(icon: Icons.folder_copy_rounded, color: c.primary, title: labels['materials'] ?? '',
              subtitle: t('ملفات وروابط الإدارة', 'Its files and links'), onTap: () { Navigator.pop(ctx); _openSpace(1); }),
      ];
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DeptLogo(d: d, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('${d['name_ar'] ?? d['name_en']}', '${d['name_en'] ?? d['name_ar']}'), style: orgText(ctx, size: 17, w: FontWeight.w800)),
              if ('${d['office_hours'] ?? ''}'.isNotEmpty) Text('${d['office_hours']}', style: orgText(ctx, size: 12, color: c.textMedium)),
            ])),
          ]),
          if ('${d['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${d['description']}', style: orgText(ctx, color: c.textMedium))),
          const SizedBox(height: 14),
          if (actions.isEmpty)
            Text(t('لا خدمات متاحة من هذه الإدارة حالياً', 'This department offers no services right now'), style: orgText(ctx, color: c.textMedium))
          else
            for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
        ]),
      );
    });
  }
}
