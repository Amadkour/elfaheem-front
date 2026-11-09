// lib/features/org/org_registrar_staff.dart — the registrar for org staff (API: /orgs/{org}/registrar/…).
//
// OrgRegistrarPage (Academics → Registrar), one chip per part:
//   Decisions    every case the server could not settle alone (or settled and wants reviewed): recommendation,
//                alternatives, risk → accept / choose an alternative / reject
//   Terms        generated calendar (edit any date) · sections synced from the active timetable (capacity) ·
//                registration report · grade approval per course · attendance run
//   Courses      credit hours, type, contact hours, offered terms, expected enrolment · requisites
//   Programs     system type · total credits · minimum CGPA · requirement groups · curriculum
//   Staff        academic rank + weekly cap (the timetable enforces both)
//   Rules        grade scale, load limits, levels by hours, retake, waitlist, attendance, graduation
//   Graduation   candidates (degree audit) · at-risk students
library;

import 'org_page_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart';
import 'org_registrar.dart';
import 'org_registrar_member.dart' show OrgRecordScreen, staffGradesScreen;
import 'org_v3.dart';
import 'org_page_kit.dart' show OrgPartPicker;
import 'package:flutter_education_app/design/app_tokens.dart';

String _courseTitle(Map<String, dynamic>? c) {
  if (c == null) return '';
  final name = t('${c['name_ar'] ?? c['name_en'] ?? ''}', '${c['name_en'] ?? c['name_ar'] ?? ''}');
  return c['code'] == null ? name : '${c['code']} · $name';
}

class OrgRegistrarPage extends StatefulWidget {
  const OrgRegistrarPage({super.key});

  @override
  State<OrgRegistrarPage> createState() => _OrgRegistrarPageState();
}

class _OrgRegistrarPageState extends State<OrgRegistrarPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, IconData, Widget)>[
      (t('القرارات', 'Decisions'), Icons.gavel_rounded, const _DecisionsTab()),
      (t('الفصول', 'Terms'), Icons.date_range_rounded, const _TermsTab()),
      (t('المقررات', 'Courses'), Icons.menu_book_rounded, const _CoursesTab()),
      (t('الأقسام والتخرج', 'Programs'), Icons.account_tree_rounded, const _ProgramsTab()),
      (t('هيئة التدريس', 'Staff'), Icons.badge_rounded, const _StaffTab()),
      (t('اللائحة', 'Rules'), Icons.rule_rounded, const _RulesTab()),
      (t('التخرج والمتعثرون', 'Graduation & at risk'), Icons.school_rounded, const _GraduationTab()),
    ];
    // the page anatomy (D-103, org_page_kit.dart): the parts as ONE part picker — chips that fit, else one
    // "part ▾" button; a part is built when chosen (as before)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xs),
        child: OrgPartPicker(parts: [for (final x in tabs) (x.$1, x.$2)], index: _tab, onChanged: (i) => setState(() => _tab = i)),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: tabs[_tab].$3)),
    ]);
  }
}

/// load → map, with the usual skeleton / retry around it.
mixin _Loads<T extends StatefulWidget> on State<T> {
  Map<String, dynamic>? data;
  bool failed = false;
  OrgSession get session => context.read<OrgSession>();
  String get reg => '${session.base}/registrar';

  Future<Map<String, dynamic>?> fetch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  Future<void> reload() async {
    final m = await fetch();
    if (!mounted) return;
    setState(() {
      if (m != null) data = m;
      failed = m == null && data == null;
    });
  }

  Future<Map<String, dynamic>?> getMap(String path, [Map<String, dynamic>? q]) async {
    final r = await orgCall(() => session.api.get(path, queryParams: q), quiet: true);
    return r.ok ? r.map : null;
  }

  Widget frame(Widget Function(Map<String, dynamic>) body) => data == null && !failed
      ? const AppListSkeleton()
      : AppAsync(loading: false, failed: failed, onRetry: reload, child: data == null ? const SizedBox() : body(data!));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Decisions
// ═════════════════════════════════════════════════════════════════════════════

class _DecisionsTab extends StatefulWidget {
  const _DecisionsTab();

  @override
  State<_DecisionsTab> createState() => _DecisionsTabState();
}

class _DecisionsTabState extends State<_DecisionsTab> with _Loads {
  String _status = 'open';

  @override
  Future<Map<String, dynamic>?> fetch() => getMap('$reg/decisions', {'status': _status});

  Future<void> _decide(Map<String, dynamic> d, String verdict, {Map<String, dynamic>? action}) async {
    final note = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(verdict == 'reject' ? t('رفض', 'Reject') : t('تنفيذ', 'Apply'),
                subtitle: verdict == 'reject' ? null : decisionActionText(action ?? asMap(d['recommendation']))),
            AppField(controller: note, label: t('ملاحظة (تُحفظ في السجل)', 'Note (kept in the audit log)'), maxLines: 2),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('تأكيد', 'Confirm'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true) return;
    final r = await orgCall(
        () => session.api.post('$reg/decisions/${d['id']}/$verdict', body: {'note': note.text.trim(), 'action': ?action}),
        ok: t('تم', 'Done'));
    if (r.ok) reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return frame((m) {
      final users = asMap(m['users']);
      final courses = asMap(m['courses']);
      final items = asMapList(m['items']);
      final counts = asMap(m['counts']);
      return AppRefresh(
        onRefresh: reload,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, label) in [('open', t('مفتوحة', 'Open')), ('accepted', t('مقبولة', 'Accepted')), ('edited', t('معدّلة', 'Edited')), ('rejected', t('مرفوضة', 'Rejected'))])
                AppChoiceChip(label: '$label ${asInt(counts[k])}', selected: _status == k, onTap: () {
                  setState(() => _status = k);
                  reload();
                }),
            ]),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            AppEmpty(icon: Icons.task_alt_rounded, title: t('لا توجد قرارات هنا', 'Nothing here'),
                message: _status == 'open' ? t('كل ما ولّده النظام أو حسمه تلقائياً يظهر هنا للمراجعة', 'Everything the system generated or settled shows here for review') : null),
          for (final d in items)
            AppCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // wraps on a phone (the risk text is long): a Row ran off a 320 px screen
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(decisionKindText('${d['kind']}'), style: appText(12, c: c.textMedium)),
                  if (d['auto_applied'] == true) AppBadgePill(t('طُبّق تلقائياً', 'Applied automatically'), color: c.primary),
                  AppBadgePill(riskText('${d['risk']}'), color: d['risk'] == 'false_positive' ? c.danger : d['risk'] == 'false_negative' ? c.warning : c.success),
                ]),
                const SizedBox(height: 6),
                Text('${d['title']}', style: appText(15, w: FontWeight.w700)),
                if ('${d['description'] ?? ''}'.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d['description']}', style: appText(13, c: c.textMedium))),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final u in (asMap(d['affected'])['students'] as List? ?? const []).take(8))
                    AppBadgePill('${asMap(users['$u'])['name'] ?? '#$u'}', icon: Icons.person_rounded),
                  for (final cid in (asMap(d['affected'])['courses'] as List? ?? const []))
                    AppBadgePill(_courseTitle(asMap(courses['$cid'])).isEmpty ? '#$cid' : '${asMap(courses['$cid'])['code'] ?? cid}', icon: Icons.menu_book_rounded),
                  for (final b in (asMap(d['affected'])['blocks'] as List? ?? const []))
                    AppBadgePill(registrarCodeText('$b'), color: c.warning),
                ]),
                const SizedBox(height: 8),
                AppBanner(icon: Icons.recommend_rounded,
                    text: '${t('التوصية', 'Recommended')}: ${decisionActionText(asMap(d['recommendation']))}'),
                if (d['status'] == 'open') ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                    AppPill(icon: Icons.check_rounded, label: t('قبول التوصية', 'Accept'), color: c.success, onTap: () => _decide(d, 'accept')),
                    for (final a in asMapList(d['alternatives']))
                      AppPill(icon: Icons.alt_route_rounded, label: decisionActionText(a), onTap: () => _decide(d, 'edit', action: a)),
                    AppPill(icon: Icons.close_rounded, label: t('رفض', 'Reject'), color: c.danger, onTap: () => _decide(d, 'reject')),
                  ]),
                ] else if ('${d['note'] ?? ''}'.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('${d['note']}', style: appText(12, c: c.textLight))),
              ]),
            ),
        ]),
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Terms: calendar · sections · report · grades
// ═════════════════════════════════════════════════════════════════════════════

class _TermsTab extends StatefulWidget {
  const _TermsTab();

  @override
  State<_TermsTab> createState() => _TermsTabState();
}

class _TermsTabState extends State<_TermsTab> with _Loads {
  int? _termId;
  Map<String, dynamic>? _cal, _report;
  List<Map<String, dynamic>>? _sections;
  Map<String, dynamic> _courses = {};

  @override
  Future<Map<String, dynamic>?> fetch() => getMap('${session.base}/academic/terms');

  @override
  Future<void> reload() async {
    await super.reload();
    final terms = asMapList(data?['items']);
    if (_termId == null && terms.isNotEmpty) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final cur = terms.where((x) => '${x['end_date']}'.compareTo(today) >= 0).firstOrNull ?? terms.last;
      _termId = asInt(cur['id']);
    }
    if (_termId != null) _loadTerm();
  }

  Future<void> _loadTerm() async {
    final id = _termId;
    final res = await Future.wait([
      getMap('$reg/terms/$id/calendar'),
      getMap('$reg/terms/$id/sections'),
      getMap('$reg/terms/$id/report'),
    ]);
    if (!mounted || id != _termId) return;
    setState(() {
      _cal = res[0];
      _sections = asMapList(res[1]?['items']);
      _courses = asMap(res[1]?['courses']);
      _report = res[2];
    });
  }

  Future<void> _generate() async {
    if (_cal?['calendar'] != null &&
        !await appConfirm(context, message: t('إعادة توليد كل التواريخ من بداية ونهاية الفصل؟', 'Regenerate every date from the term start / end?'))) {
      return;
    }
    final r = await orgCall(() => session.api.post('$reg/terms/$_termId/calendar/generate'), ok: t('تم توليد التقويم', 'Calendar generated'));
    if (r.ok) _loadTerm();
  }

  Future<void> _editDate(String k) async {
    final cal = Map<String, dynamic>.from(asMap(_cal?['calendar'] ?? _cal?['preview']));
    final cur = DateTime.tryParse('${cal[k]}') ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null) return;
    cal[k] = d.toIso8601String().substring(0, 10);
    final r = await orgCall(() => session.api.put('$reg/terms/$_termId/calendar', body: {'calendar': cal}), ok: t('حُفظ', 'Saved'));
    if (r.ok) _loadTerm();
  }

  Future<void> _sync() async {
    final r = await orgCall(() => session.api.post('$reg/terms/$_termId/sections/sync'));
    if (r.ok) {
      toast(t('شعب جديدة ${r.map['created']} · معدّلة ${r.map['updated']} · ملغاة ${r.map['cancelled']}',
          'New ${r.map['created']} · updated ${r.map['updated']} · cancelled ${r.map['cancelled']}'));
      _loadTerm();
    }
  }

  Future<void> _capacity(Map<String, dynamic> s) async {
    final ctrl = TextEditingController(text: '${s['capacity']}');
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('سعة الشعبة', 'Section capacity'), subtitle: '${_courseTitle(asMap(_courses['${s['course_id']}']))} · ${sectionLabel(s)}'),
            if (s['room_capacity'] != null)
              AppBanner(icon: Icons.meeting_room_rounded, text: t('سعة القاعة ${s['room_capacity']}', 'Room capacity ${s['room_capacity']}')),
            const SizedBox(height: 8),
            OrgNumberField(controller: ctrl, label: t('السعة', 'Capacity'), gap: false),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('حفظ', 'Save'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    final v = int.tryParse(ctrl.text.trim());
    if (ok != true || v == null || !mounted) return;
    if (s['room_capacity'] != null && v > asInt(s['room_capacity']) &&
        !await appConfirm(context, message: t('السعة أكبر من القاعة — متأكد؟', 'Capacity exceeds the room — sure?'), danger: true)) {
      return;
    }
    final r = await orgCall(() => session.api.put('$reg/sections/${s['id']}', body: {'capacity': v}), ok: t('حُفظ', 'Saved'));
    if (r.ok) _loadTerm();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return frame((m) {
      final terms = asMapList(m['items']);
      if (terms.isEmpty) {
        return AppEmpty(icon: Icons.date_range_rounded, title: t('لا توجد فصول', 'No terms'),
            message: t('أضف الفصول من الهيكل الأكاديمي أولاً', 'Add terms in the academic structure first'));
      }
      final cal = asMap(_cal?['calendar']);
      final preview = asMap(_cal?['preview']);
      final rep = asMap(_report);
      final seats = asMap(rep['seats']);
      final byCourse = <int, List<Map<String, dynamic>>>{};
      for (final s in _sections ?? const <Map<String, dynamic>>[]) {
        byCourse.putIfAbsent(asInt(s['course_id']), () => []).add(s);
      }
      return AppRefresh(
        onRefresh: _loadTerm,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final x in terms)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: AppChoiceChip(label: termTitle(x), selected: asInt(x['id']) == _termId, onTap: () {
                    setState(() {
                      _termId = asInt(x['id']);
                      _cal = _report = null;
                      _sections = null;
                    });
                    _loadTerm();
                  }),
                ),
            ]),
          ),
          if (_report != null)
            AppGrid(padding: const EdgeInsets.all(16), children: [
              AppStatTile(icon: Icons.how_to_reg_rounded, label: t('مسجلون', 'Registered'), value: asInt(asMap(rep['registrations'])['registered'])),
              AppStatTile(icon: Icons.hourglass_top_rounded, label: t('قوائم انتظار', 'Waitlisted'), value: asInt(asMap(rep['registrations'])['waitlisted']), color: c.warning),
              AppStatTile(icon: Icons.event_seat_rounded, label: t('إشغال المقاعد %', 'Seat use %'), value: seats['utilisation'] ?? '—'),
              AppStatTile(icon: Icons.gavel_rounded, label: t('قرارات مفتوحة', 'Open decisions'), value: asInt(rep['open_decisions']),
                  color: asInt(rep['open_decisions']) > 0 ? c.danger : c.success),
            ]),
          AppSectionTitle(t('التقويم الأكاديمي', 'Academic calendar'),
              subtitle: cal.isEmpty ? t('لم يُولَّد بعد — هذه معاينة', 'Not generated yet — preview') : windowText('${_cal?['window']}'),
              trailing: AppPill(icon: Icons.auto_awesome_rounded, label: cal.isEmpty ? t('توليد', 'Generate') : t('إعادة التوليد', 'Regenerate'), onTap: _generate)),
          AppCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (final k in registrarMilestones)
                InkWell(
                  onTap: cal.isEmpty ? null : () => _editDate(k),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(milestoneLabel(k), style: appText(13))),
                      Text('${cal[k] ?? preview[k] ?? '—'}',
                          style: appText(13, w: FontWeight.w700, c: cal.isEmpty ? c.textLight : null)),
                      if (cal.isNotEmpty) ...[const SizedBox(width: 6), Icon(Icons.edit_calendar_rounded, size: 16, color: c.textLight)],
                    ]),
                  ),
                ),
            ]),
          ),
          AppSectionTitle(t('الشعب', 'Sections'), subtitle: t('تُنشأ من الجدول الدراسي المعتمد للفصل', "Built from the term's active timetable"),
              trailing: Wrap(spacing: 8, children: [
                AppPill(icon: Icons.sync_rounded, label: t('مزامنة', 'Sync'), onTap: _sync),
                AppPill(icon: Icons.groups_rounded, label: t('تسجيل الدفعات', 'Enrol cohorts'), onTap: () async {
                  final r = await orgCall(() => session.api.post('$reg/terms/$_termId/cohort-enrol', body: {}));
                  if (r.ok) {
                    toast(t('سُجِّل ${r.map['registered']} · متخلف ${r.map['carry']} · تعارض ${r.map['conflicts']}',
                        'Registered ${r.map['registered']} · carry-over ${r.map['carry']} · conflicts ${r.map['conflicts']}'));
                    _loadTerm();
                  }
                }),
              ])),
          if ((_sections ?? const []).isEmpty)
            AppEmpty(icon: Icons.view_week_rounded, title: t('لا توجد شعب بعد', 'No sections yet'),
                message: t('اعتمد جدول الفصل ثم اضغط مزامنة', "Publish the term's timetable, then press Sync")),
          for (final e in byCourse.entries)
            AppCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(_courseTitle(asMap(_courses['${e.key}'])), style: appText(14, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  AppPill(icon: Icons.grading_rounded, label: t('الدرجات', 'Grades'), onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => staffGradesScreen(session.currentId!, _termId!, e.key)))),
                ]),
                for (final s in e.value)
                  InkWell(
                    onTap: () => _capacity(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                          child: Text('${sectionLabel(s)} · ${[for (final x in asMapList(s['meetings'])) meetingText(x)].join('، ')}',
                              style: appText(12, c: s['status'] == 'cancelled' ? c.danger : c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text('${s['enrolled']}/${s['capacity']}', style: appText(13, w: FontWeight.w700,
                            c: asInt(s['enrolled']) >= asInt(s['capacity']) ? c.warning : null)),
                        if (asInt(s['waitlisted']) > 0) ...[
                          const SizedBox(width: 6),
                          AppBadgePill('+${s['waitlisted']}', color: c.warning),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
          if (_termId != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppPill(icon: Icons.fact_check_rounded, label: t('حساب الغياب والحرمان الآن', 'Run absence & denial now'), onTap: () async {
                final r = await orgCall(() => session.api.post('$reg/terms/$_termId/attendance/run'));
                if (r.ok) toast(t('تنبيهات ${r.map['warned']} · حرمان ${r.map['denied']}', 'Warnings ${r.map['warned']} · denials ${r.map['denied']}'));
              }),
            ),
        ]),
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Courses
// ═════════════════════════════════════════════════════════════════════════════

class _CoursesTab extends StatefulWidget {
  const _CoursesTab();

  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> with _Loads {
  @override
  Future<Map<String, dynamic>?> fetch() => getMap('$reg/courses');

  Future<void> _edit(Map<String, dynamic> course) async {
    final saved = await showAppSheet<bool>(context, (_) => _CourseSheet(course: course, all: asMapList(data?['items']), reg: reg));
    if (saved == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return frame((m) {
      final items = asMapList(m['items']);
      final missing = items.where((x) => x['credits'] == null).length;
      return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppBanner(icon: Icons.warning_amber_rounded, color: c.warning,
                text: t('$missing مقرر بلا ساعات معتمدة — لا يمكن التسجيل فيها', '$missing course(s) have no credit hours — they cannot be registered')),
          ),
        if (items.isEmpty) AppEmpty(icon: Icons.menu_book_rounded, title: t('لا توجد مقررات', 'No courses')),
        for (final x in items)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppActionCard(
              icon: Icons.menu_book_rounded,
              color: x['credits'] == null ? c.warning : c.primary,
              title: _courseTitle(x),
              subtitle: [
                x['credits'] == null ? t('بلا ساعات', 'No credits') : t('${asDouble(x['credits']).toStringAsFixed(0)} ساعات', '${asDouble(x['credits']).toStringAsFixed(0)} credits'),
                courseKindText('${x['kind']}'),
                if (asMapList(x['requisites']).isNotEmpty) t('${asMapList(x['requisites']).length} متطلب', '${asMapList(x['requisites']).length} requisite(s)'),
              ].join(' · '),
              onTap: () => _edit(x),
            ),
          ),
      ]);
    });
  }
}

class _CourseSheet extends StatefulWidget {
  const _CourseSheet({required this.course, required this.all, required this.reg});
  final Map<String, dynamic> course;
  final List<Map<String, dynamic>> all;
  final String reg;

  @override
  State<_CourseSheet> createState() => _CourseSheetState();
}

class _CourseSheetState extends State<_CourseSheet> {
  late final _credits = TextEditingController(text: _n(widget.course['credits']));
  late final _lec = TextEditingController(text: _n(widget.course['lecture_hours']));
  late final _lab = TextEditingController(text: _n(widget.course['lab_hours']));
  late final _tut = TextEditingController(text: _n(widget.course['tutorial_hours']));
  late final _exp = TextEditingController(text: _n(widget.course['expected_enrollment']));
  late String _kind = '${widget.course['kind'] ?? 'theory'}';
  late final Set<String> _terms = {for (final x in (widget.course['offered_terms'] as List? ?? const [])) '$x'};
  late final List<Map<String, dynamic>> _reqs = [for (final r in asMapList(widget.course['requisites'])) Map<String, dynamic>.from(r)];
  bool _busy = false;

  static String _n(dynamic v) => v == null ? '' : (v is double && v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');
  static double? _d(TextEditingController c) => double.tryParse(c.text.trim());

  OrgSession get _s => context.read<OrgSession>();

  Future<void> _save() async {
    setState(() => _busy = true);
    final id = widget.course['id'];
    final r1 = await orgCall(() => _s.api.put('${widget.reg}/courses/$id', body: {
          'credit_hours': _d(_credits), 'course_kind': _kind, 'lecture_hours': _kind == 'lab' ? null : _d(_lec),
          'lab_hours': _kind == 'theory' ? null : _d(_lab), 'tutorial_hours': _d(_tut),
          'offered_terms': _terms.isEmpty ? null : _terms.toList(), 'expected_enrollment': int.tryParse(_exp.text.trim()),
        }));
    final r2 = r1.ok ? await orgCall(() => _s.api.put('${widget.reg}/courses/$id/requisites', body: {'items': _reqs})) : r1;
    if (!mounted) return;
    setState(() => _busy = false);
    if (r1.ok && r2.ok) {
      toast(t('حُفظ', 'Saved'));
      Navigator.pop(context, true);
    } else if (r2.code == 'requisite_cycle') {
      toast(registrarCodeText('requisite_cycle'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final others = widget.all.where((x) => x['id'] != widget.course['id']).toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(_courseTitle(widget.course)),
        AppDropdown<String>(
          value: _kind,
          decoration: InputDecoration(labelText: t('نوع المقرر', 'Course type')),
          items: [for (final k in const ['theory', 'theory_lab', 'lab']) DropdownMenuItem(value: k, child: Text(courseKindText(k)))],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        const SizedBox(height: 10),
        OrgNumberField(controller: _credits, label: t('الساعات المعتمدة', 'Credit hours'), gap: false),
        const SizedBox(height: 10),
        Row(children: [
          if (_kind != 'lab') Expanded(child: OrgNumberField(controller: _lec, label: t('محاضرة/أسبوع', 'Lecture h/wk'), gap: false)),
          if (_kind != 'lab' && _kind != 'theory') const SizedBox(width: 8),
          if (_kind != 'theory') Expanded(child: OrgNumberField(controller: _lab, label: t('معمل/أسبوع', 'Lab h/wk'), gap: false)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OrgNumberField(controller: _tut, label: t('تمارين/أسبوع', 'Tutorial h/wk'), gap: false)),
          const SizedBox(width: 8),
          Expanded(child: OrgNumberField(controller: _exp, label: t('العدد المتوقع', 'Expected students'), gap: false)),
        ]),
        const SizedBox(height: 10),
        Text(t('يُطرح في', 'Offered in'), style: appText(13, c: c.textMedium)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final k in const ['term1', 'term2', 'summer'])
            AppChoiceChip(label: termKindText(k), selected: _terms.contains(k),
                onTap: () => setState(() => _terms.contains(k) ? _terms.remove(k) : _terms.add(k))),
        ]),
        if (_terms.length == 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('يُطرح مرة واحدة سنوياً — سيُنبَّه الطلاب المعرضون للتأخير', 'Offered once a year — students at risk of delay will be warned'),
                style: appText(12, c: c.warning)),
          ),
        AppSectionTitle(t('المتطلبات', 'Requisites'),
            trailing: AppPill(icon: Icons.add_rounded, label: t('إضافة', 'Add'), onTap: others.isEmpty ? null : () => setState(() =>
                _reqs.add({'course_id': others.first['id'], 'mode': 'passed', 'min_grade': null})))),
        for (var i = 0; i < _reqs.length; i++)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              AppDropdown<int>(
                value: asInt(_reqs[i]['course_id']),
                items: [for (final o in others) DropdownMenuItem(value: asInt(o['id']), child: Text(_courseTitle(o), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _reqs[i]['course_id'] = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: AppDropdown<String>(
                    value: '${_reqs[i]['mode'] ?? 'passed'}',
                    items: [for (final k in const ['passed', 'concurrent', 'coreq']) DropdownMenuItem(value: k, child: Text(reqModeText(k)))],
                    onChanged: (v) => setState(() => _reqs[i]['mode'] = v),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: AppDropdown<String?>(
                    value: _reqs[i]['min_grade'] as String?,
                    hint: Text(t('أي نجاح', 'Any pass')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(t('أي نجاح', 'Any pass'))),
                      for (final g in const ['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'D']) DropdownMenuItem<String?>(value: g, child: Text(g)),
                    ],
                    onChanged: (v) => setState(() => _reqs[i]['min_grade'] = v),
                  ),
                ),
                IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () => setState(() => _reqs.removeAt(i))),
              ]),
            ]),
          ),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Programs (graduation requirements)
// ═════════════════════════════════════════════════════════════════════════════

class _ProgramsTab extends StatefulWidget {
  const _ProgramsTab();

  @override
  State<_ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends State<_ProgramsTab> with _Loads {
  @override
  Future<Map<String, dynamic>?> fetch() => getMap('${session.base}/academic/programs');

  Future<void> _open(Map<String, dynamic> p) async {
    final full = await getMap('$reg/programs/${p['id']}');
    final courses = await getMap('$reg/courses');
    final levels = await getMap('${session.base}/academic/levels');
    final terms = await getMap('${session.base}/academic/terms');
    if (!mounted || full == null) return;
    final saved = await showAppSheet<bool>(context, (_) => _ProgramSheet(
        program: full, courses: asMapList(courses?['items']), reg: reg,
        levels: [for (final l in asMapList(levels?['levels'])) '${l['key']}'], terms: asMapList(terms?['items'])));
    if (saved == true) reload();
  }

  Future<void> _allocate() async {
    final plan = await orgCall(() => session.api.post('$reg/allocation', body: {'apply': false}));
    if (!plan.ok || !mounted) return;
    final n = asMapList(plan.map['plan']).length;
    final ties = asMapList(plan.map['ties']).length;
    if (n == 0) {
      toast(t('لا توجد طلبات معلقة يمكن قبولها', 'No pending requests can be admitted'));
      return;
    }
    final msg = t('سيُقبل $n طالب حسب المعدل ثم الساعات ثم وقت الطلب، ضمن السعة.${ties > 0 ? ' $ties حالة تساوٍ ستُعرض كقرار.' : ''}',
        '$n student(s) will be admitted by GPA, then hours, then request time, within capacity.${ties > 0 ? ' $ties tie(s) become decisions.' : ''}');
    if (!await appConfirm(context, message: msg)) return;
    await orgCall(() => session.api.post('$reg/allocation', body: {'apply': true}), ok: t('تم التوزيع', 'Allocated'));
  }

  @override
  Widget build(BuildContext context) => frame((m) {
        final items = asMapList(m['items']);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              AppPill(icon: Icons.leaderboard_rounded, label: t('توزيع الطلبات بالجدارة', 'Allocate requests by merit'), onTap: _allocate),
              AppPill(icon: Icons.support_rounded, label: t('توزيع المرشدين تلقائياً', 'Assign advisors automatically'), onTap: () async {
                final r = await orgCall(() => session.api.post('$reg/advisors/auto', body: {}));
                if (r.ok) toast(t('أُسند مرشد لـ ${r.map['assigned']} طالب', 'Advisor assigned to ${r.map['assigned']} student(s)'));
              }),
            ]),
          ),
          if (items.isEmpty)
            AppEmpty(icon: Icons.account_tree_rounded, title: t('لا توجد أقسام علمية', 'No academic departments'),
                message: t('أضفها من الهيكل الأكاديمي', 'Add them in the academic structure')),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppActionCard(
                icon: Icons.account_tree_rounded,
                title: '${p['code']} · ${t('${p['name_ar'] ?? ''}', '${p['name_en'] ?? p['name_ar'] ?? ''}')}',
                subtitle: t('متطلبات التخرج والخطة الدراسية', 'Graduation requirements & curriculum'),
                onTap: () => _open(p),
              ),
            ),
        ]);
      });
}

class _ProgramSheet extends StatefulWidget {
  const _ProgramSheet({required this.program, required this.courses, required this.reg, this.levels = const [], this.terms = const []});
  final Map<String, dynamic> program;
  final List<Map<String, dynamic>> courses;
  final String reg;
  final List<String> levels;
  final List<Map<String, dynamic>> terms;

  @override
  State<_ProgramSheet> createState() => _ProgramSheetState();
}

class _ProgramSheetState extends State<_ProgramSheet> {
  late String _system = '${widget.program['system_type'] ?? 'credit_hour'}';
  late final _total = TextEditingController(text: widget.program['total_credits'] == null ? '' : asDouble(widget.program['total_credits']).toStringAsFixed(0));
  late final _gpa = TextEditingController(text: widget.program['min_cgpa'] == null ? '' : '${widget.program['min_cgpa']}');
  late final _entry = TextEditingController(text: '${widget.program['entry_level'] ?? ''}');
  late final _carry = TextEditingController(text: widget.program['max_carry'] == null ? '' : '${widget.program['max_carry']}');
  late final List<Map<String, dynamic>> _groups = [for (final g in asMapList(widget.program['requirement_groups'])) Map<String, dynamic>.from(g)];
  late final Map<int, Map<String, dynamic>> _cur = {
    for (final c in asMapList(widget.program['curriculum'])) asInt(c['course_id']): Map<String, dynamic>.from(c),
  };
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await orgCall(() => context.read<OrgSession>().api.put('${widget.reg}/programs/${widget.program['id']}', body: {
          'system_type': _system,
          'total_credits': double.tryParse(_total.text.trim()),
          'min_cgpa': double.tryParse(_gpa.text.trim()),
          'entry_level': _entry.text.trim().isEmpty ? null : _entry.text.trim(),
          if (_system == 'traditional') 'max_carry': int.tryParse(_carry.text.trim()),
          'requirement_groups': [
            for (final g in _groups) {'key': g['key'], 'label_ar': g['label_ar'], 'label_en': g['label_en'], 'min_credits': asDouble(g['min_credits'])},
          ],
          'curriculum': [
            for (final e in _cur.entries)
              {'course_id': e.key, 'kind': e.value['required'] == false ? 'elective' : 'required', 'group_key': e.value['group_key'],
                'level_key': e.value['level_key'], 'term_kind': e.value['term_kind']},
          ],
        }), ok: t('حُفظ', 'Saved'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) Navigator.pop(context, true);
  }

  OrgSession get _s => context.read<OrgSession>();

  Future<void> _promote() async {
    final base = '${widget.reg}/programs/${widget.program['id']}/promote';
    final r = await orgCall(() => _s.api.post(base, body: {'dry_run': true}));
    if (!r.ok || !mounted) return;
    final m = r.map;
    int n(String k) => (m[k] as List? ?? const []).length;
    final msg = t('ينتقل ${n('promoted')} · ينتقل بمواد متخلفة ${n('carry')} · يعيد السنة ${n('repeat')} · ينتظر نتائج ${n('waiting')} · خريجون ${n('graduate')}',
        'Promoted ${n('promoted')} · with carry-over ${n('carry')} · repeat ${n('repeat')} · waiting for grades ${n('waiting')} · graduating ${n('graduate')}');
    if (!await appConfirm(context, message: msg, confirmLabel: t('تنفيذ الترحيل', 'Promote'))) return;
    await orgCall(() => _s.api.post(base, body: {'dry_run': false}), ok: t('تم الترحيل', 'Promoted'));
  }

  Future<void> _makeup() async {
    if (widget.terms.isEmpty) return;
    final term = await showAppSheet<int>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          AppSectionTitle(t('فصل الدور الثاني', 'Make-up term')),
          for (final x in widget.terms)
            ListTile(title: Text(termTitle(x)), onTap: () => Navigator.pop(ctx, asInt(x['id']))),
        ]));
    if (term == null) return;
    final r = await orgCall(() => _s.api.post('${widget.reg}/programs/${widget.program['id']}/makeup', body: {'term_id': term}));
    if (r.ok) toast(t('سُجِّل ${r.map['registered']} مقرر للدور الثاني', '${r.map['registered']} course registration(s) for the make-up round'));
  }

  Future<void> _addGroup() async {
    final key = TextEditingController(), ar = TextEditingController(), en = TextEditingController(), min = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('مجموعة متطلبات', 'Requirement group'),
                subtitle: t('مثال: university · faculty · major · elective · free', 'e.g. university · faculty · major · elective · free')),
            AppField(controller: key, label: t('المفتاح', 'Key'), ltr: true),
            const SizedBox(height: 8),
            AppField(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            const SizedBox(height: 8),
            AppField(controller: en, label: t('الاسم بالإنجليزية', 'English name')),
            const SizedBox(height: 8),
            OrgNumberField(controller: min, label: t('الحد الأدنى للساعات', 'Minimum credits'), gap: false),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('إضافة', 'Add'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true || key.text.trim().isEmpty) return;
    setState(() => _groups.add({'key': key.text.trim(), 'label_ar': ar.text.trim(), 'label_en': en.text.trim(), 'min_credits': double.tryParse(min.text.trim()) ?? 0}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keys = [for (final g in _groups) '${g['key']}'];
    final sum = _groups.fold<double>(0, (a, g) => a + asDouble(g['min_credits']));
    final total = double.tryParse(_total.text.trim());
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle('${widget.program['code']}'),
        AppDropdown<String>(
          value: _system,
          decoration: InputDecoration(labelText: t('نظام الدراسة', 'Academic system')),
          items: [
            DropdownMenuItem(value: 'credit_hour', child: Text(t('الساعات المعتمدة', 'Credit hours'))),
            DropdownMenuItem(value: 'traditional', child: Text(t('النظام التقليدي (الفرق)', 'Traditional (years)'))),
          ],
          onChanged: (v) => setState(() => _system = v ?? _system),
        ),
        if (_system == 'traditional')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning,
                text: t('في النظام التقليدي يكون التسجيل تلقائياً حسب الفرقة، ولا يسجل الطالب بنفسه.', 'In the traditional system registration is automatic by year; students do not self-register.')),
          ),
        if (_system == 'traditional') ...[
          const SizedBox(height: 10),
          OrgNumberField(controller: _carry, label: t('أقصى عدد مقررات متخلفة مع النقل (فارغ = اللائحة)', 'Max carry-over courses to still be promoted (empty = rules)'), gap: false),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppPill(icon: Icons.trending_up_rounded, label: t('ترحيل الطلاب للفرقة التالية', 'Promote students'), onTap: _promote),
            AppPill(icon: Icons.replay_rounded, label: t('الدور الثاني', 'Make-up round'), onTap: _makeup),
          ]),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppField(controller: _total, label: t('ساعات التخرج', 'Graduation credits'), keyboard: TextInputType.number, ltr: true, onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: OrgNumberField(controller: _gpa, label: t('أدنى معدل للتخرج', 'Minimum CGPA'), decimals: 2, gap: false)),
        ]),
        const SizedBox(height: 10),
        AppField(controller: _entry, label: t('يبدأ القسم من المستوى (مفتاح)', 'Department starts at level (key)'), ltr: true),
        AppSectionTitle(t('مجموعات المتطلبات', 'Requirement groups'),
            subtitle: total != null && sum > total ? t('مجموع الحدود الدنيا أكبر من ساعات التخرج', 'Group minimums exceed the graduation credits') : null,
            trailing: AppPill(icon: Icons.add_rounded, label: t('إضافة', 'Add'), onTap: _addGroup)),
        for (var i = 0; i < _groups.length; i++)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text('${t('${_groups[i]['label_ar'] ?? ''}', '${_groups[i]['label_en'] ?? ''}')} (${_groups[i]['key']})', style: appText(13, w: FontWeight.w700))),
              Text('≥ ${asDouble(_groups[i]['min_credits']).toStringAsFixed(0)}', style: appText(13)),
              IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () => setState(() => _groups.removeAt(i))),
            ]),
          ),
        AppSectionTitle(t('الخطة الدراسية', 'Curriculum'), subtitle: t('اختر المقررات ومجموعتها ومستواها', 'Pick the courses, their group and level')),
        for (final course in widget.courses)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AppSwitch(value: _cur.containsKey(asInt(course['id'])), onChanged: (v) => setState(() => v
                    ? _cur[asInt(course['id'])] = {'course_id': course['id'], 'required': true, 'group_key': keys.firstOrNull}
                    : _cur.remove(asInt(course['id'])))),
                const SizedBox(width: 8),
                Expanded(child: Text(_courseTitle(course), style: appText(13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              if (_cur.containsKey(asInt(course['id']))) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: AppDropdown<bool>(
                      value: _cur[asInt(course['id'])]!['required'] != false,
                      items: [
                        DropdownMenuItem(value: true, child: Text(t('إجباري', 'Required'))),
                        DropdownMenuItem(value: false, child: Text(t('اختياري', 'Elective'))),
                      ],
                      onChanged: (v) => setState(() => _cur[asInt(course['id'])]!['required'] = v ?? true),
                    ),
                  ),
                  if (widget.levels.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String?>(
                        value: widget.levels.contains(_cur[asInt(course['id'])]!['level_key']) ? '${_cur[asInt(course['id'])]!['level_key']}' : null,
                        hint: Text(_system == 'traditional' ? t('الفرقة', 'Year') : t('المستوى', 'Level')),
                        items: [for (final k in widget.levels) DropdownMenuItem<String?>(value: k, child: Text(k))],
                        onChanged: (v) => setState(() => _cur[asInt(course['id'])]!['level_key'] = v),
                      ),
                    ),
                  ],
                  if (_system == 'traditional') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String?>(
                        value: _cur[asInt(course['id'])]!['term_kind'] as String?,
                        hint: Text(t('الفصل', 'Term')),
                        items: [for (final k in const ['term1', 'term2', 'summer']) DropdownMenuItem<String?>(value: k, child: Text(termKindText(k)))],
                        onChanged: (v) => setState(() => _cur[asInt(course['id'])]!['term_kind'] = v),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  if (keys.isNotEmpty && _system != 'traditional')
                    Expanded(
                      child: AppDropdown<String>(
                        value: keys.contains(_cur[asInt(course['id'])]!['group_key']) ? '${_cur[asInt(course['id'])]!['group_key']}' : keys.first,
                        items: [for (final k in keys) DropdownMenuItem(value: k, child: Text(k))],
                        onChanged: (v) => setState(() => _cur[asInt(course['id'])]!['group_key'] = v),
                      ),
                    ),
                ]),
              ],
            ]),
          ),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff ranks
// ═════════════════════════════════════════════════════════════════════════════

class _StaffTab extends StatefulWidget {
  const _StaffTab();

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> with _Loads {
  @override
  Future<Map<String, dynamic>?> fetch() => getMap('${session.base}/members', {'role': 'teacher,teacher_assistant', 'size': '100'});

  Future<void> _edit(Map<String, dynamic> m) async {
    String? rank = m['academic_rank'] as String?;
    final cap = TextEditingController(text: m['max_weekly_hours'] == null ? '' : '${m['max_weekly_hours']}');
    final ok = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle('${asMap(m['user'])['name'] ?? ''}'),
            AppDropdown<String?>(
              value: rank,
              decoration: InputDecoration(labelText: t('الدرجة الوظيفية', 'Academic rank')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(rankText(null))),
                for (final r in const ['professor', 'associate_professor', 'assistant_professor', 'lecturer', 'assistant_lecturer', 'demonstrator'])
                  DropdownMenuItem<String?>(value: r, child: Text(rankText(r))),
              ],
              onChanged: (v) => set(() => rank = v),
            ),
            if (rank == 'demonstrator' || rank == 'assistant_lecturer')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppBanner(icon: Icons.science_rounded, text: t('هذه الدرجة تُسند لها السكاشن والمعامل فقط', 'This rank is given labs / sections only')),
              ),
            const SizedBox(height: 8),
            OrgNumberField(controller: cap, label: t('الحد الأسبوعي (فترات) — فارغ = حسب الدرجة', 'Weekly cap (periods) — empty = by rank'), gap: false),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('حفظ', 'Save'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        )));
    if (ok != true) return;
    final r = await orgCall(() => session.api.put('$reg/members/${m['id']}/rank',
        body: {'academic_rank': rank, 'max_weekly_hours': int.tryParse(cap.text.trim())}), ok: t('حُفظ', 'Saved'));
    if (r.ok) reload();
  }

  @override
  Widget build(BuildContext context) => frame((m) {
        final items = asMapList(m['items']);
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (items.isEmpty) AppEmpty(icon: Icons.badge_rounded, title: t('لا يوجد أعضاء هيئة تدريس', 'No teaching staff')),
          for (final x in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppActionCard(
                icon: x['role'] == 'teacher' ? Icons.co_present_rounded : Icons.science_rounded,
                title: '${asMap(x['user'])['name'] ?? ''}',
                subtitle: [rankText(x['academic_rank'] as String?), if (x['max_weekly_hours'] != null) t('حد ${x['max_weekly_hours']} فترة', 'cap ${x['max_weekly_hours']}')].join(' · '),
                onTap: () => _edit(x),
              ),
            ),
        ]);
      });
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rules
// ═════════════════════════════════════════════════════════════════════════════

class _RulesTab extends StatefulWidget {
  const _RulesTab();

  @override
  State<_RulesTab> createState() => _RulesTabState();
}

/// (path inside the rules, label, decimal?) of every number the screen edits.
final _numFields = <(List<String>, String Function(), bool)>[
  (['load', 'regular', 'min'], () => t('أدنى عبء للفصل العادي', 'Regular term: minimum load'), false),
  (['load', 'regular', 'max'], () => t('أقصى عبء للفصل العادي', 'Regular term: maximum load'), false),
  (['load', 'summer', 'max'], () => t('أقصى عبء للفصل الصيفي', 'Summer: maximum load'), false),
  (['load', 'first_term_max'], () => t('أقصى عبء للطالب الجديد', 'First term: maximum load'), false),
  (['load', 'graduating_extra'], () => t('ساعات إضافية للمتوقع تخرجه', 'Extra hours for graduating students'), false),
  (['level_step'], () => t('ساعات كل مستوى (افتراضي)', 'Hours per level (default)'), false),
  (['standing', 'probation_below'], () => t('الإنذار تحت معدل', 'Probation below CGPA'), true),
  (['standing', 'honours_term_gpa'], () => t('قائمة الشرف من معدل فصلي', "Dean's list from term GPA"), true),
  (['retake', 'max_attempts'], () => t('أقصى مرات لدراسة المقرر', 'Maximum attempts per course'), false),
  (['waitlist', 'max_per_section'], () => t('أقصى قائمة انتظار للشعبة', 'Waitlist size per section'), false),
  (['attendance', 'deny_at'], () => t('نسبة الغياب للحرمان %', 'Absence % for exam denial'), true),
  (['graduation', 'min_cgpa'], () => t('أدنى معدل للتخرج', 'Minimum CGPA to graduate'), true),
];

class _RulesTabState extends State<_RulesTab> with _Loads {
  final Map<String, TextEditingController> _ctrl = {};
  Map<String, dynamic>? _rules;
  bool _busy = false;

  @override
  Future<Map<String, dynamic>?> fetch() => getMap('$reg/rules');

  @override
  Future<void> reload() async {
    await super.reload();
    final r = asMap(data?['rules']);
    _rules = jsonCopy(r);
    for (final (path, _, _) in _numFields) {
      dynamic v = r;
      for (final p in path) {
        v = asMap(v)[p] ?? (v is Map ? v[p] : null);
      }
      _ctrl.putIfAbsent(path.join('.'), TextEditingController.new).text = v == null ? '' : '$v';
    }
    if (mounted) setState(() {});
  }

  Future<void> _editGrade(int? i) async {
    final scale = asMapList(_rules?['grade_scale']);
    final g = i == null ? <String, dynamic>{} : scale[i];
    final letter = TextEditingController(text: '${g['letter'] ?? ''}');
    final min = TextEditingController(text: '${g['min'] ?? ''}');
    final pts = TextEditingController(text: '${g['points'] ?? ''}');
    var pass = i != null && '${_rules?['pass_letter']}' == '${g['letter']}';
    final res = await showAppSheet<String>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('تقدير', 'Letter grade')),
            AppField(controller: letter, label: t('الحرف', 'Letter'), ltr: true),
            const SizedBox(height: 8),
            OrgNumberField(controller: min, label: t('من نسبة %', 'From percent'), gap: false),
            const SizedBox(height: 8),
            OrgNumberField(controller: pts, label: t('النقاط', 'Points'), decimals: 2, gap: false),
            AppSwitchTile(title: t('أدنى تقدير للنجاح', 'Lowest passing letter'), value: pass, onChanged: (v) => set(() => pass = v)),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('تم', 'Done'), onPressed: () => Navigator.pop(ctx, 'save')),
            if (i != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(t('حذف', 'Delete'), style: TextStyle(color: context.colors.danger))),
          ]),
        )));
    if (res == null) return;
    setState(() {
      final list = [for (final x in scale) Map<String, dynamic>.from(x)];
      if (res == 'delete') {
        list.removeAt(i!);
      } else {
        final row = {'letter': letter.text.trim(), 'min': double.tryParse(min.text.trim()) ?? 0, 'points': double.tryParse(pts.text.trim()) ?? 0};
        if (row['letter'] == '') return;
        i == null ? list.add(row) : list[i] = row;
        if (pass) _rules!['pass_letter'] = row['letter'];
      }
      list.sort((a, b) => asDouble(b['min']).compareTo(asDouble(a['min'])));
      _rules!['grade_scale'] = list;
    });
  }

  static Map<String, dynamic> jsonCopy(Map<String, dynamic> m) =>
      {for (final e in m.entries) e.key: e.value is Map ? jsonCopy(asMap(e.value)) : e.value is List ? List.of(e.value as List) : e.value};

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final r = jsonCopy(_rules ?? const {});
    for (final (path, _, dec) in _numFields) {
      final txt = _ctrl[path.join('.')]?.text.trim() ?? '';
      final v = dec ? double.tryParse(txt) : int.tryParse(txt);
      if (v == null) continue;
      Map<String, dynamic> node = r;
      for (final p in path.take(path.length - 1)) {
        node = (node[p] ??= <String, dynamic>{}) as Map<String, dynamic>;
      }
      node[path.last] = v;
    }
    setState(() => _busy = true);
    final res = await orgCall(() => session.api.put('$reg/rules', body: {'rules': r}), ok: t('حُفظت اللائحة', 'Rules saved'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return frame((m) {
      final r = _rules ?? const <String, dynamic>{};
      final retake = asMap(r['retake']);
      final reg = asMap(r['registration']);
      final wl = asMap(r['waitlist']);
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        if (m['inherited_from'] != null)
          AppBanner(icon: Icons.account_tree_rounded, text: t('اللائحة موروثة من المؤسسة الأم — الحفظ هنا ينشئ لائحة خاصة', 'Inherited from the parent organization — saving here creates this organization\'s own rules')),
        AppSectionTitle(t('سلم التقديرات', 'Grade scale'),
            subtitle: t('من الأعلى للأدنى، وآخر تقدير يبدأ من 0', 'Highest first; the last letter starts at 0'),
            trailing: AppPill(icon: Icons.add_rounded, label: t('تقدير', 'Letter'), onTap: () => _editGrade(null))),
        AppCard(
          child: Column(children: [
            for (var i = 0; i < asMapList(r['grade_scale']).length; i++)
              InkWell(
                onTap: () => _editGrade(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(width: 48, child: Text('${asMapList(r['grade_scale'])[i]['letter']}', style: appText(14, w: FontWeight.w700))),
                    Expanded(child: Text('≥ ${asMapList(r['grade_scale'])[i]['min']}%', style: appText(13))),
                    Text('${asMapList(r['grade_scale'])[i]['points']}', style: appText(13, w: FontWeight.w700, c: c.primary)),
                    if ('${r['pass_letter']}' == '${asMapList(r['grade_scale'])[i]['letter']}') ...[
                      const SizedBox(width: 8),
                      AppBadgePill(t('أدنى نجاح', 'Lowest pass'), color: c.success),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
        AppSectionTitle(t('الأرقام', 'Numbers')),
        for (final (path, label, dec) in _numFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppField(controller: _ctrl[path.join('.')] ?? TextEditingController(), label: label(),
                keyboard: dec ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number, ltr: true),
          ),
        AppSectionTitle(t('السياسات', 'Policies')),
        AppDropdown<String>(
          value: '${retake['count'] ?? 'latest'}',
          decoration: InputDecoration(labelText: t('عند إعادة المقرر يُحتسب', 'When a course is retaken, count')),
          items: [
            DropdownMenuItem(value: 'latest', child: Text(t('آخر تقدير', 'The latest grade'))),
            DropdownMenuItem(value: 'highest', child: Text(t('أعلى تقدير', 'The highest grade'))),
          ],
          onChanged: (v) => setState(() => (_rules!['retake'] as Map)['count'] = v),
        ),
        const SizedBox(height: 8),
        AppSwitchTile(
          title: t('السماح بالتسجيل والمتطلب قيد الدراسة', 'Allow registration while the prerequisite is in progress'),
          subtitle: t('يُقبل بشرط، ويُراجع تلقائياً بعد إعلان النتائج', 'Allowed with a condition, re-checked automatically when results are out'),
          value: reg['allow_pending_prereq'] != false,
          onChanged: (v) => setState(() => (_rules!['registration'] as Map)['allow_pending_prereq'] = v),
        ),
        AppSwitchTile(
          title: t('قوائم الانتظار', 'Waitlists'),
          value: wl['enabled'] != false,
          onChanged: (v) => setState(() => (_rules!['waitlist'] as Map)['enabled'] = v),
        ),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('حفظ اللائحة', 'Save rules'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
      ]);
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Graduation · at risk
// ═════════════════════════════════════════════════════════════════════════════

class _GraduationTab extends StatefulWidget {
  const _GraduationTab();

  @override
  State<_GraduationTab> createState() => _GraduationTabState();
}

class _GraduationTabState extends State<_GraduationTab> with _Loads {
  List<Map<String, dynamic>>? _risk;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    final res = await Future.wait([getMap('$reg/graduation/candidates'), getMap('$reg/at-risk')]);
    _risk = asMapList(res[1]?['items']);
    return res[0];
  }

  String _reason(Map<String, dynamic> r) => switch (r['code']) {
        'probation' => t('إنذار (${gpaText(r['cgpa'])})', 'Probation (${gpaText(r['cgpa'])})'),
        'low_gpa' => t('معدل منخفض (${gpaText(r['cgpa'])})', 'Low GPA (${gpaText(r['cgpa'])})'),
        'absence' => r['denied'] == true ? t('محروم (${r['pct']}%)', 'Denied (${r['pct']}%)') : t('غياب ${r['pct']}%', 'Absence ${r['pct']}%'),
        'delayed' => t('متأخر عن الخطة', 'Behind the plan'),
        _ => '${r['code']}',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return frame((m) {
      final cands = asMapList(m['items']);
      return AppRefresh(
        onRefresh: reload,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          AppSectionTitle(t('مستوفو متطلبات التخرج', 'Meet graduation requirements'), subtitle: t('حسب التدقيق الآلي للخطة', 'By the automatic degree audit')),
          if (cands.isEmpty) AppEmpty(icon: Icons.school_rounded, title: t('لا يوجد مرشحون الآن', 'No candidates now')),
          for (final x in cands)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppActionCard(
                icon: Icons.school_rounded,
                color: c.success,
                title: '${asMap(x['student'])['name'] ?? '#${x['student_id']}'}',
                subtitle: '${t('المعدل', 'CGPA')} ${gpaText(x['cgpa'])} · ${asDouble(x['earned']).toStringAsFixed(0)} ${t('ساعة', 'credits')}',
                trailing: AppPill(icon: Icons.verified_rounded, label: t('اعتماد', 'Approve'), color: c.success, onTap: () async {
                  if (!await appConfirm(context, message: t('اعتماد تخرج الطالب؟', 'Approve this graduation?'))) return;
                  final r = await orgCall(() => session.api.post('$reg/graduation/${x['student_id']}', body: {}), ok: t('تم اعتماد التخرج', 'Graduation approved'));
                  if (r.ok) reload();
                }),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrgRecordScreen(orgId: session.currentId!, studentId: asInt(x['student_id'])))),
              ),
            ),
          AppSectionTitle(t('طلاب معرضون للتعثر', 'Students at risk')),
          if ((_risk ?? const []).isEmpty) AppEmpty(icon: Icons.health_and_safety_rounded, title: t('لا يوجد', 'None')),
          for (final x in _risk ?? const <Map<String, dynamic>>[])
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppActionCard(
                icon: Icons.warning_amber_rounded,
                color: c.warning,
                title: '${asMap(x['student'])['name'] ?? '#${x['student_id']}'}',
                subtitle: [for (final r in asMapList(x['reasons'])) _reason(r)].join(' · '),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrgRecordScreen(orgId: session.currentId!, studentId: asInt(x['student_id'])))),
              ),
            ),
        ]),
      );
    });
  }
}
