// lib/features/org/org_schedule_exams.dart — midterm and final exam timetables of a term.
//
//   GET  …/exam-schedules/window?term_id&kind     the proposed window from the term's dates
//   GET|POST …/exam-schedules · GET|PUT|DELETE …/exam-schedules/{id} · POST …/{id}/generate · PUT …/{id}/slots/{sid}
//   POST …/{id}/activate | deactivate            (back: services/organization/schedule_exams.py)
//
// One exam per course on a date of the window, in one of the day's sittings ("HH:MM" of the organization, shown
// through AppTime). Never: two exams at once for students sharing courses, a room holding two exams, a room too small
// (several rooms are used together), an invigilator in two places or at a time they are unavailable.
//
// Pure (unit-tested): proposeExamWindow (mirrors the server) · examsByDate · examReasonText.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';
import '../shared/exam_engine/exam_authoring.dart' show ExamAuthoringApi;
import '../shared/exam_engine/exam_quick.dart' show examsBySlot;
import '../shared/exam_engine/exam_quick_screen.dart' show showSlotExamSheet;
import 'org_my_exams.dart' show examPauseText;
import 'org_providers.dart';
import 'org_schedule_copies.dart' show timetableNamesOf;
import 'org_schedule_export.dart' show showExamExport;
import 'org_page_header.dart' show OrgPageRefresh;
import 'org_schedule_planning.dart' show kOrgSchedulingMocks, orgStudioPage;
import 'org_schedule_versions.dart';
import 'org_timetable_time.dart';
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

const examKinds = ['midterm', 'final'];
const defaultExamDays = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday'];
const defaultSittings = [
  {'start_time': '09:00', 'end_time': '11:00'},
  {'start_time': '12:00', 'end_time': '14:00'},
];

String examKindLabel(String k) => k == 'midterm' ? t('امتحانات منتصف الفصل', 'Midterm exams') : t('الامتحانات النهائية', 'Final exams');

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Same rule as the server (schedule_exams.propose_window): midterm ≈ term days / 14 (5–10 days) centred on the
/// midpoint; final ≈ term days / 8 (5–14 days) ending on the last day. Always inside the term.
(DateTime, DateTime) proposeExamWindow(DateTime start, DateTime end, String kind) {
  final s = _day(start), e = _day(end);
  final days = e.difference(s).inDays + 1 < 1 ? 1 : e.difference(s).inDays + 1;
  if (kind == 'midterm') {
    final length = (days ~/ 14).clamp(5, 10).clamp(1, days);
    final mid = s.add(Duration(days: (days - 1) ~/ 2));
    var a = mid.subtract(Duration(days: (length - 1) ~/ 2));
    final latest = e.subtract(Duration(days: length - 1));
    if (a.isAfter(latest)) a = latest;
    if (a.isBefore(s)) a = s;
    return (a, a.add(Duration(days: length - 1)));
  }
  final length = (days ~/ 8).clamp(5, 14).clamp(1, days);
  return (e.subtract(Duration(days: length - 1)), e);
}

/// Exams grouped by date (ISO "yyyy-mm-dd"), dates ascending, each day by start time then course.
Map<String, List<Map<String, dynamic>>> examsByDate(List<Map<String, dynamic>> exams) {
  final sorted = [...exams]
    ..sort((a, b) {
      final k = '${a['date']} ${a['start_time']}'.compareTo('${b['date']} ${b['start_time']}');
      return k != 0 ? k : asInt(a['course_id']).compareTo(asInt(b['course_id']));
    });
  final out = <String, List<Map<String, dynamic>>>{};
  for (final x in sorted) {
    out.putIfAbsent('${x['date']}'.substring(0, '${x['date']}'.length.clamp(0, 10)), () => []).add(x);
  }
  return out;
}

String examReasonText(String r) => switch (r) {
      'students_clash' => t('طلابه لديهم امتحان آخر في كل الأوقات المتاحة', 'Its students have another exam at every free time'),
      'max_per_day' => t('تجاوز الحد الأقصى لامتحانات الطالب في اليوم', 'Over the most exams a student may sit in a day'),
      'no_room_capacity' => t('كل الأماكن معاً لا تكفي عدد الطلاب', 'All rooms together can\'t seat its students'),
      'rooms_busy' => t('الأماكن الكافية محجوزة في كل الأوقات', 'Rooms big enough are taken at every time'),
      'no_invigilator' => t('لا يوجد مراقبون متاحون بالعدد المطلوب', 'Not enough invigilators are free'),
      'no_exam_dates' => t('لا توجد أيام امتحان في الفترة المحددة', 'No exam days in the chosen window'),
      _ => r,
    };

String examConflictText(String type) => switch (type) {
      'students_clash' => t('امتحانان لطلاب مشتركين في الوقت نفسه', 'Two exams at once for the same students'),
      'room_double_booked' => t('مكان عليه امتحانان في الوقت نفسه', 'A room holds two exams at once'),
      'room_too_small' => t('الأماكن لا تكفي عدد الطلاب', 'The rooms can\'t seat all students'),
      'practical_exam_room' => t('امتحان عملي في غير معمله', 'A practical exam outside its lab'),
      'invigilator_double_booked' => t('مراقب في امتحانين في الوقت نفسه', 'An invigilator in two exams at once'),
      'invigilator_unavailable' => t('مراقب في وقت غير متاح له', 'An invigilator at a time they are unavailable'),
      'missing_invigilator' => t('مراقب واحد على الأقل لكل مكان', 'At least one invigilator per room'),
      'max_per_day' => t('امتحانات كثيرة للطالب في يوم واحد', 'Too many exams in one day for a student'),
      _ => type,
    };

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String termLabelOf(Map<String, dynamic> term) => '${t('${term['label_ar'] ?? term['kind']}', '${term['label_en'] ?? term['kind']}')} ${term['year_label'] ?? ''}'.trim();

// ═════════════════════════════════════════════════════════════════════════════
//  Server
// ═════════════════════════════════════════════════════════════════════════════

abstract class ExamApi {
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>> window(int termId, String kind);
  Future<Map<String, dynamic>> create(Map<String, dynamic> body);
  Future<Map<String, dynamic>> get(int id);
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body);
  Future<void> delete(int id);
  Future<Map<String, dynamic>> generate(int id, {int? version});
  Future<Map<String, dynamic>> editSlot(int id, int slotId, Map<String, dynamic> body, {bool dryRun = false});
  Future<Map<String, dynamic>> publish(int id, bool on);
}

class RemoteExamApi implements ExamApi {
  RemoteExamApi(this.api, this.base);
  final ApiClient api;
  final String base;
  String get _e => '$base/exam-schedules';

  @override
  Future<List<Map<String, dynamic>>> list() async => asMapList(asMap(await api.get(_e))['items']);
  @override
  Future<Map<String, dynamic>> window(int termId, String kind) async => asMap(await api.get('$_e/window', queryParams: {'term_id': termId, 'kind': kind}));
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async => asMap(await api.post(_e, body: body));
  @override
  Future<Map<String, dynamic>> get(int id) async => asMap(await api.get('$_e/$id'));
  @override
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body) async => asMap(await api.put('$_e/$id', body: body));
  @override
  Future<void> delete(int id) async => api.delete('$_e/$id');
  @override
  Future<Map<String, dynamic>> generate(int id, {int? version}) async => asMap(await api.post('$_e/$id/generate', body: {'keep_locked': true, 'expected_version': ?version}));
  @override
  Future<Map<String, dynamic>> editSlot(int id, int slotId, Map<String, dynamic> body, {bool dryRun = false}) async =>
      asMap(await api.put('$_e/$id/slots/$slotId', body: body, queryParams: dryRun ? {'dry_run': true} : null));
  @override
  Future<Map<String, dynamic>> publish(int id, bool on) async => asMap(await api.post('$_e/$id/${on ? 'activate' : 'deactivate'}'));
}

/// Development only (ORG_SCHEDULING_MOCKS): keeps exam timetables in memory and places one exam per course per
/// sitting in order — enough to work on the screens without the server route.
class MockExamApi implements ExamApi {
  MockExamApi(this.p);
  final OrgScheduleProvider p;
  final _store = <int, Map<String, dynamic>>{};
  var _next = 1;

  @override
  Future<List<Map<String, dynamic>>> list() async => _store.values.toList();
  @override
  Future<Map<String, dynamic>> window(int termId, String kind) async {
    final term = p.terms.firstWhere((x) => asInt(x['id']) == termId, orElse: () => const {});
    final w = proposeExamWindow(DateTime.parse('${term['start_date']}'), DateTime.parse('${term['end_date']}'), kind);
    return {'start_date': _iso(w.$1), 'end_date': _iso(w.$2), 'days': defaultExamDays, 'sittings': defaultSittings};
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final w = body['start_date'] == null ? await window(asInt(body['term_id']), '${body['kind']}') : body;
    final id = _next++;
    return _store[id] = {
      ...body, 'id': id, 'status': 'draft', 'version': 0, 'items': <Map<String, dynamic>>[], 'conflicts': const [],
      'name': body['name'] ?? examKindLabel('${body['kind']}'), 'start_date': w['start_date'], 'end_date': w['end_date'],
      'days': body['days'] ?? defaultExamDays, 'sittings': body['sittings'] ?? defaultSittings,
    };
  }

  @override
  Future<Map<String, dynamic>> get(int id) async => _store[id] ?? (throw const ApiException(statusCode: 404, message: 'exam_schedule_not_found'));
  @override
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> body) async => _store[id] = {...await get(id), ...body};
  @override
  Future<void> delete(int id) async => _store.remove(id);
  @override
  Future<Map<String, dynamic>> generate(int id, {int? version}) async {
    final e = await get(id);
    final sit = asMapList(e['sittings']);
    var d = DateTime.parse('${e['start_date']}');
    var k = 0;
    final items = <Map<String, dynamic>>[];
    for (final l in p.loads.where((l) => l['kind'] == null || l['kind'] == 'lecture')) {
      final s = sit[k % sit.length];
      items.add({'id': items.length + 1, 'course_id': l['course_id'], 'date': _iso(d), ...s, 'room_ids': const [], 'invigilator_ids': const [], 'students': 0, 'locked': false});
      if (++k % sit.length == 0) d = d.add(const Duration(days: 1));
    }
    return _store[id] = {...e, 'items': items, 'version': asInt(e['version']) + 1, 'result': {'status': 'feasible', 'stats': {'exams_required': items.length, 'exams_placed': items.length}}};
  }

  @override
  Future<Map<String, dynamic>> editSlot(int id, int slotId, Map<String, dynamic> body, {bool dryRun = false}) async {
    final e = await get(id);
    if (!dryRun) {
      e['items'] = [for (final x in asMapList(e['items'])) asInt(x['id']) == slotId ? {...x, ...body} : x];
    }
    return {'conflicts': const []};
  }

  @override
  Future<Map<String, dynamic>> publish(int id, bool on) async => _store[id] = {...await get(id), 'status': on ? 'active' : 'draft'};
}

MockExamApi? _mockExams;
ExamApi examApi(OrgScheduleProvider p) => kOrgSchedulingMocks ? (_mockExams ??= MockExamApi(p)) : RemoteExamApi(p.api, p.base);

String _err(Object e) {
  final x = ApiException.from(e);
  return orgEndpointMissing(x) ? t('جداول الامتحانات تحتاج تحديث الخادم.', 'Exam timetables need a server update.') : orgErrorText(x);
}

// ═════════════════════════════════════════════════════════════════════════════
//  UI · list (per term: midterm + final)
// ═════════════════════════════════════════════════════════════════════════════

Future<void> openExamTimetables(BuildContext context, OrgScheduleProvider p, {bool canEdit = false, bool canApprove = false, bool canExport = false}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => orgStudioPage(
              ctx,
              title: t('جداول الامتحانات', 'Exam timetables'),
              subtitle: t('منتصف الفصل والنهائية', 'Midterm & final'),
              child: _ExamListPage(p: p, api: examApi(p), canEdit: canEdit, canApprove: canApprove, canExport: canExport),
            )));

class _ExamListPage extends StatefulWidget {
  const _ExamListPage({required this.p, required this.api, required this.canEdit, required this.canApprove, required this.canExport});
  final OrgScheduleProvider p;
  final ExamApi api;
  final bool canEdit, canApprove, canExport;

  @override
  State<_ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<_ExamListPage> {
  List<Map<String, dynamic>>? items;
  String? error;
  OrgPageRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _load);
    _load();
  }

  @override
  void dispose() {
    _refresh?.unregister(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.list();
      if (mounted) {
        setState(() {
          items = r;
          error = null;
        });
        _refresh?.markUpdated();
      }
    } catch (e) {
      if (mounted) setState(() => error = _err(e));
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => orgStudioPage(
              ctx,
              title: t('جدول الامتحانات', 'Exam timetable'),
              child: _ExamPage(p: widget.p, api: widget.api, id: id, canEdit: widget.canEdit, canApprove: widget.canApprove, canExport: widget.canExport),
            )));
    await _load();
  }

  Future<void> _create(Map<String, dynamic> term, String kind) async {
    final id = await showExamSettingsSheet(context, widget.p, widget.api, term: term, kind: kind);
    if (id != null) await _open(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final terms = [...widget.p.terms]..sort((a, b) => '${b['start_date']}'.compareTo('${a['start_date']}'));
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
      AppHero(
        icon: Icons.assignment_rounded,
        title: t('امتحانات منتصف الفصل والنهائية', 'Midterm and final exams'),
        subtitle: t('نقترح فترة الامتحانات من تواريخ الفصل، ثم نضع كل امتحان دون أن يجتمع امتحانان لنفس الطلاب، مع أماكن تكفيهم ومراقبين متاحين.',
            'We propose the exam window from the term\'s dates, then place every exam so no students sit two at once, with rooms that seat them and invigilators who are free.'),
        stats: [
          AppHeroStat(icon: Icons.calendar_month_rounded, value: '${terms.length}', label: t('فصول', 'terms')),
          AppHeroStat(icon: Icons.assignment_turned_in_rounded, value: '${items?.length ?? '—'}', label: t('جداول امتحانات', 'exam timetables')),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      if (error != null)
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger, action: TextButton(onPressed: _load, child: Text(t('أعد المحاولة', 'Try again'))))
      else if (items == null)
        const SizedBox(height: 300, child: AppListSkeleton(items: 3, withAvatar: false))
      else if (terms.isEmpty)
        AppEmpty(
            icon: Icons.event_note_rounded,
            title: t('لا توجد فصول دراسية بعد', 'No terms yet'),
            message: t('أضف الفصل الدراسي بتاريخ بدايته ونهايته من الإعدادات الأكاديمية، ثم عد هنا.', 'Add the term with its start and end dates in the academic settings, then come back.'))
      else
        for (final term in terms) ...[
          AppSectionTitle(termLabelOf(term), subtitle: '${calendarDate(term['start_date'], pattern: 'd MMM y')} – ${calendarDate(term['end_date'], pattern: 'd MMM y')}'),
          LayoutBuilder(builder: (context, box) {
            final tiles = [
              for (final k in examKinds)
                _KindTile(
                  kind: k,
                  exam: items!.where((x) => asInt(x['term_id']) == asInt(term['id']) && x['kind'] == k).firstOrNull,
                  term: term,
                  onOpen: _open,
                  onCreate: widget.canEdit ? () => _create(term, k) : null,
                ),
            ];
            if (box.maxWidth < 560) return Column(children: [for (final w in tiles) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: w)]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tiles[0]), const SizedBox(width: AppSpace.sm), Expanded(child: tiles[1])]);
          }),
          const SizedBox(height: AppSpace.xs),
        ],
    ]);
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.exam, required this.term, required this.onOpen, this.onCreate});
  final String kind;
  final Map<String, dynamic>? exam, term;
  final ValueChanged<int> onOpen;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    final st = asMap(asMap(e?['result'])['stats']);
    final w = term == null || term!['start_date'] == null
        ? null
        : proposeExamWindow(DateTime.parse('${term!['start_date']}'), DateTime.parse('${term!['end_date']}'), kind);
    return AppCard(
      onTap: e == null ? onCreate : () => onOpen(asInt(e['id'])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(kind == 'midterm' ? Icons.timelapse_rounded : Icons.flag_circle_rounded, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(examKindLabel(kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          if (e != null) AppBadgePill(e['status'] == 'active' ? t('منشور', 'Published') : t('مسودة', 'Draft'), color: e['status'] == 'active' ? c.success : c.warning),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (e != null) ...[
          Text('${calendarDate(e['start_date'])} – ${calendarDate(e['end_date'])}', style: AppType.label(context).copyWith(color: c.textMedium)),
          if (st.isNotEmpty) Text(t('${st['exams_placed']} من ${st['exams_required']} امتحان', '${st['exams_placed']} of ${st['exams_required']} exams'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
        ] else ...[
          if (w != null)
            Text('${t('الفترة المقترحة', 'Suggested window')}: ${calendarDate(_iso(w.$1))} – ${calendarDate(_iso(w.$2))}', style: AppType.label(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.xs),
          if (onCreate != null)
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: Text(t('أنشئ', 'Create')))),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  UI · settings sheet (create / edit)
// ═════════════════════════════════════════════════════════════════════════════

/// Returns the exam timetable id once saved.
Future<int?> showExamSettingsSheet(BuildContext context, OrgScheduleProvider p, ExamApi api,
    {required Map<String, dynamic> term, required String kind, Map<String, dynamic>? existing}) async {
  final ts = DateTime.parse('${term['start_date']}'), te = DateTime.parse('${term['end_date']}');
  final w = proposeExamWindow(ts, te, kind);
  DateTime start = existing == null ? w.$1 : DateTime.parse('${existing['start_date']}');
  DateTime end = existing == null ? w.$2 : DateTime.parse('${existing['end_date']}');
  final days = <String>{...(existing?['days'] as List? ?? defaultExamDays).map((x) => '$x')};
  final sittings = [for (final s in (existing?['sittings'] as List? ?? defaultSittings)) Map<String, dynamic>.from(s as Map)];
  bool cohorts = existing?['cohort_source'] == 'timetables';
  int? maxPerDay = existing?['max_per_day'] == null ? null : asInt(existing!['max_per_day']);
  bool pauseWeekly = existing?['pause_weekly'] != false; // default on (server default too)
  final name = TextEditingController(text: '${existing?['name'] ?? ''}');
  bool busy = false;
  String? error;
  int? out;
  final labels = dayLabelsPlain();
  await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> pick(bool isStart) async {
          final d = await showDatePicker(context: ctx, firstDate: ts, lastDate: te, initialDate: isStart ? start : end);
          if (d != null) set(() => isStart ? start = d : end = d);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg), // showAppSheet already lifts the sheet above the keyboard
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader('${examKindLabel(kind)} · ${termLabelOf(term)}'),
            Field(controller: name, label: t('الاسم (اختياري)', 'Name (optional)')),
            AppSectionTitle(t('فترة الامتحانات', 'Exam window'),
                subtitle: t('مقترحة من تواريخ الفصل — ${kind == 'midterm' ? 'حول منتصفه' : 'في نهايته'}', 'Suggested from the term\'s dates — ${kind == 'midterm' ? 'around its midpoint' : 'at its end'}')),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.event_rounded, size: AppIconSize.md), label: Text(calendarDate(_iso(start)), maxLines: 1, overflow: TextOverflow.ellipsis))),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.event_available_rounded, size: AppIconSize.md), label: Text(calendarDate(_iso(end)), maxLines: 1, overflow: TextOverflow.ellipsis))),
            ]),
            const SizedBox(height: AppSpace.sm),
            Text(t('أيام الامتحانات', 'Exam days'), style: AppType.bodyStrong(ctx)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in orgDaysOrder)
                FilterChip(
                  label: Text(labels[d] ?? d),
                  selected: days.contains(d),
                  onSelected: (v) => set(() => v ? days.add(d) : days.remove(d)),
                ),
            ]),
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              Expanded(child: Text(t('فترات الامتحان في اليوم', 'Sittings per day'), style: AppType.bodyStrong(ctx))),
              if (sittings.length < 8)
                TextButton.icon(
                  onPressed: () => set(() => sittings.add({'start_time': '15:00', 'end_time': '17:00'})),
                  icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
                  label: Text(t('إضافة', 'Add')),
                ),
            ]),
            for (var i = 0; i < sittings.length; i++)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClockField(label: t('تبدأ', 'Starts'), value: '${sittings[i]['start_time']}', onChanged: (v) => set(() => sittings[i]['start_time'] = v))),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: ClockField(label: t('تنتهي', 'Ends'), value: '${sittings[i]['end_time']}', onChanged: (v) => set(() => sittings[i]['end_time'] = v))),
                IconButton(
                  tooltip: t('حذف', 'Remove'),
                  onPressed: sittings.length > 1 ? () => set(() => sittings.removeAt(i)) : null,
                  icon: Icon(Icons.remove_circle_outline_rounded, color: c.danger),
                ),
              ]),
            AppSwitchTile(
              title: t('اعتبر كل جدول أسبوعي دفعة واحدة', 'Treat each weekly timetable as one class group'),
              subtitle: t('مفيد قبل تسجيل الطلاب: مقررات الجدول الواحد لا تجتمع امتحاناتها في وقت واحد.',
                  'Useful before students enrol: courses of one weekly timetable never have exams at the same time.'),
              value: cohorts,
              onChanged: (v) => set(() => cohorts = v),
            ),
            AppSwitchTile(
              icon: Icons.event_busy_rounded,
              title: t('إيقاف المحاضرات الأسبوعية أثناء الامتحانات', 'Pause weekly classes during exams'),
              subtitle: t('بعد النشر لا تُعقد محاضرات الجدول الأسبوعي لهذا الفصل في أيام فترة الامتحانات (دون حذف أي محاضرة).',
                  'Once published, the weekly timetable of this term holds no classes on the dates of the exam window (nothing is deleted).'),
              value: pauseWeekly,
              onChanged: (v) => set(() => pauseWeekly = v),
            ),
            Text(t('أقصى عدد امتحانات للطالب في اليوم', 'Most exams a student sits in one day'), style: AppType.bodyStrong(ctx)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in const [null, 1, 2, 3])
                ChoiceChip(label: Text(n == null ? t('بلا حد', 'No limit') : '$n'), selected: maxPerDay == n, onSelected: (_) => set(() => maxPerDay = n)),
            ]),
            if (error != null) ...[const SizedBox(height: AppSpace.sm), AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger)],
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(
              label: existing == null ? t('إنشاء جدول الامتحانات', 'Create the exam timetable') : t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: busy,
              onPressed: busy || days.isEmpty
                  ? null
                  : () async {
                      if (end.isBefore(start)) return set(() => error = t('تاريخ النهاية قبل البداية', 'The end date is before the start'));
                      set(() => (busy, error) = (true, null));
                      final body = {
                        'term_id': asInt(term['id']),
                        'kind': kind,
                        if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
                        'start_date': _iso(start),
                        'end_date': _iso(end),
                        'days': [for (final d in orgDaysOrder) if (days.contains(d)) d],
                        'sittings': sittings,
                        'cohort_source': cohorts ? 'timetables' : 'enrollments',
                        'max_per_day': maxPerDay,
                        'pause_weekly': pauseWeekly,
                        // the PUT replaces every field: keep the course list this form doesn't edit
                        if (existing != null) 'course_ids': existing['course_ids'],
                        if (existing != null) 'expected_version': existing['version'],
                      };
                      try {
                        final r = existing == null ? await api.create(body) : await api.update(asInt(existing['id']), body);
                        out = asInt(r['id']);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        set(() => (busy, error) = (false, _err(e)));
                      }
                    },
            ),
          ]),
        );
      }));
  return out;
}

const orgDaysOrder = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

// ═════════════════════════════════════════════════════════════════════════════
//  UI · one exam timetable
// ═════════════════════════════════════════════════════════════════════════════

class _ExamPage extends StatefulWidget {
  const _ExamPage({required this.p, required this.api, required this.id, required this.canEdit, required this.canApprove, required this.canExport});
  final OrgScheduleProvider p;
  final ExamApi api;
  final int id;
  final bool canEdit, canApprove, canExport;

  @override
  State<_ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<_ExamPage> {
  Map<String, dynamic>? e;
  String? error;
  bool busy = false;
  OrgPageRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _load);
    _load();
  }

  @override
  void dispose() {
    _refresh?.unregister(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get(widget.id);
      if (mounted) {
        setState(() {
          e = r;
          error = null;
        });
        _refresh?.markUpdated();
      }
      if (_made.isEmpty) _loadMade();
    } catch (x) {
      if (mounted) setState(() => error = _err(x));
    }
  }

  Future<void> _run(Future<Map<String, dynamic>?> Function() fn, {String? ok}) async {
    setState(() => busy = true);
    try {
      final r = await fn();
      if (r != null && r['items'] != null && mounted) setState(() => e = r);
      if (ok != null) appToast(ok);
      if (r == null || r['items'] == null) await _load();
    } catch (x) {
      final ex = ApiException.from(x);
      appToast(_err(x), error: true);
      if (ex.code == 'stale_version') await _load();
    }
    if (mounted) setState(() => busy = false);
  }

  /// Engine exams made from this timetable's slots (settings.schedule_slot_id); empty when the engine is not routed.
  Map<int, Map<String, dynamic>> _made = {};

  Future<void> _loadMade() async {
    final r = await ExamAuthoringApi().exams(orgId: widget.p.session.currentId);
    if (mounted && r.ok) setState(() => _made = examsBySlot(asMapList(r.map['items'])));
  }

  /// Tapping an exam: create it now (or not), open the one already made, or change its time.
  Future<void> _slot(Map<String, dynamic> x, {required bool editable}) async {
    DateTime? at(String? hhmm) {
      final d = DateTime.tryParse('${x['date']}');
      final p = (hhmm ?? '').split(':');
      if (d == null || p.length < 2) return null;
      return AppTime.fromZone(DateTime(d.year, d.month, d.day, int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0));
    }

    final created = await showSlotExamSheet(context,
        courseName: timetableNamesOf(widget.p).course(x['course_id']),
        courseId: asInt(x['course_id']),
        orgId: widget.p.session.currentId,
        slotId: asInt(x['id']),
        kind: '${e?['kind'] ?? 'final'}',
        startsAt: at('${x['start_time']}'),
        endsAt: at('${x['end_time']}'),
        exam: _made[asInt(x['id'])],
        onChangeTime: editable ? () => _move(x) : null);
    if (created) _loadMade();
  }

  Future<void> _move(Map<String, dynamic> x) async {
    final ex = e!;
    DateTime date = DateTime.parse('${x['date']}');
    var sit = asMapList(ex['sittings']).indexWhere((s) => s['start_time'] == x['start_time']);
    if (sit < 0) sit = 0;
    final sittings = asMapList(ex['sittings']);
    List<Map<String, dynamic>> conflicts = const [];
    bool checking = false;
    final names = timetableNamesOf(widget.p);
    final saved = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          Map<String, dynamic> body() => {'date': _iso(date), ...sittings[sit], 'expected_version': ex['version']};
          Future<void> check() async {
            set(() => checking = true);
            try {
              final r = await widget.api.editSlot(asInt(ex['id']), asInt(x['id']), body(), dryRun: true);
              set(() => conflicts = asMapList(r['conflicts']));
            } catch (_) {}
            set(() => checking = false);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader('${t('نقل امتحان', 'Move the exam of')} ${names.course(x['course_id'])}'),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(calendarDate(_iso(date))),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime.parse('${ex['start_date']}'), lastDate: DateTime.parse('${ex['end_date']}'), initialDate: date);
                  if (d != null) {
                    set(() => date = d);
                    await check();
                  }
                },
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < sittings.length; i++)
                  ChoiceChip(
                    label: Text(periodRange(sittings[i])),
                    selected: sit == i,
                    onSelected: (_) async {
                      set(() => sit = i);
                      await check();
                    },
                  ),
              ]),
              const SizedBox(height: AppSpace.sm),
              if (checking) const LinearProgressIndicator(),
              for (final k in conflicts)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: AppBanner(icon: Icons.warning_amber_rounded, text: examConflictText('${k['type']}'), color: c.danger),
                ),
              const SizedBox(height: AppSpace.sm),
              AppPrimaryButton(
                label: conflicts.isEmpty ? t('نقل', 'Move') : t('نقل رغم التعارض', 'Move despite the clash'),
                icon: Icons.check_rounded,
                onPressed: () async {
                  if (conflicts.isNotEmpty && !await appConfirm(ctx, message: t('سيبقى التعارض ظاهراً ويمنع النشر حتى يُحل. متابعة؟', 'The clash stays visible and blocks publishing until fixed. Continue?'), danger: true)) {
                    return;
                  }
                  try {
                    await widget.api.editSlot(asInt(ex['id']), asInt(x['id']), {...body(), 'force': conflicts.isNotEmpty});
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (err) {
                    appToast(_err(err), error: true);
                  }
                },
              ),
            ]),
          );
        }));
    if (saved == true) await _load();
  }

  void _export(String by) {
    final ex = e!;
    showExamExport(context,
        title: '${ex['name']}',
        exams: asMapList(ex['items']),
        names: timetableNamesOf(widget.p),
        by: by,
        meta: ['${calendarDate(ex['start_date'])} – ${calendarDate(ex['end_date'])}', examKindLabel('${ex['kind']}')]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = e;
    if (error != null && ex == null) {
      return Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger, action: TextButton(onPressed: _load, child: Text(t('أعد المحاولة', 'Try again')))));
    }
    if (ex == null) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 5, withAvatar: false));
    final names = timetableNamesOf(widget.p);
    final items = asMapList(ex['items']);
    final res = asMap(ex['result']);
    final st = asMap(res['stats']);
    final conflicts = asMapList(ex['conflicts']);
    final hard = conflicts.where((x) => x['severity'] == 'error').length;
    final unplaced = asMapList(res['unscheduled']);
    final active = ex['status'] == 'active';
    final editable = widget.canEdit && !active && !busy;
    final term = widget.p.terms.where((x) => asInt(x['id']) == asInt(ex['term_id'])).firstOrNull;
    final byDate = examsByDate(items);
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
        AppHero(
          icon: ex['kind'] == 'midterm' ? Icons.timelapse_rounded : Icons.flag_circle_rounded,
          title: '${ex['name']}',
          subtitle: '${calendarDate(ex['start_date'])} – ${calendarDate(ex['end_date'])}'
              '${term == null ? '' : ' · ${termLabelOf(term)}'} · ${asMapList(ex['sittings']).map(periodRange).join(' / ')}',
          stats: [
            AppHeroStat(icon: Icons.assignment_turned_in_rounded, value: st.isEmpty ? '—' : '${st['exams_placed']}/${st['exams_required']}', label: t('امتحانات مجدولة', 'exams placed')),
            AppHeroStat(icon: Icons.calendar_month_rounded, value: '${byDate.length}', label: t('أيام', 'days')),
            AppHeroStat(icon: Icons.warning_amber_rounded, value: '$hard', label: t('تعارضات', 'clashes')),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (active)
          AppBanner(icon: Icons.verified_rounded, text: t('منشور — يراه الطلاب والمراقبون. أوقف النشر لتعديله.', 'Published — students and invigilators see it. Unpublish to edit it.'), color: c.success)
        else if (items.isEmpty)
          AppBanner(icon: Icons.auto_awesome_rounded, text: t('الخطوة التالية: ولّد الجدول — يأخذ ثوانٍ.', 'Next step: generate the timetable — it takes seconds.'))
        else if (unplaced.isNotEmpty)
          AppBanner(
              icon: Icons.info_outline_rounded,
              text: t('${unplaced.length} امتحان بلا موعد — مدّ الفترة أو أضف فترة امتحان أو مكاناً، ثم ولّد من جديد.',
                  '${unplaced.length} exam(s) have no time — widen the window or add a sitting or a room, then generate again.'),
              color: c.warning)
        else if (hard > 0)
          AppBanner(icon: Icons.error_outline_rounded, text: t('حُرّك امتحان يدوياً فسبّب تعارضاً — انقله أو ولّد من جديد.', 'A hand move caused a clash — move it or generate again.'), color: c.danger)
        else
          AppBanner(icon: Icons.check_circle_rounded, text: t('كل الامتحانات في أماكنها دون تعارض — جاهز للنشر.', 'Every exam is placed with no clash — ready to publish.'), color: c.success),
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          icon: ex['pause_weekly'] == false ? Icons.event_repeat_rounded : Icons.event_busy_rounded,
          text: ex['pause_weekly'] == false
              ? t('المحاضرات الأسبوعية تستمر أثناء الامتحانات.', 'Weekly classes continue during the exams.')
              : '${examPauseText(ex)}${active ? '' : t(' (بعد النشر)', ' (once published)')}',
          color: ex['pause_weekly'] == false ? c.textMedium : c.primary,
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (widget.canEdit && !active)
            AppPrimaryButton(
              label: items.isEmpty ? t('ولّد الجدول', 'Generate') : t('ولّد من جديد', 'Generate again'),
              icon: Icons.auto_awesome_rounded,
              busy: busy,
              onPressed: editable ? () => _run(() => widget.api.generate(asInt(ex['id']), version: asInt(ex['version'])), ok: t('تم التوليد', 'Generated')) : null,
            ),
          if (widget.canEdit && !active && term != null)
            OutlinedButton.icon(
              onPressed: editable
                  ? () async {
                      final id = await showExamSettingsSheet(context, widget.p, widget.api, term: term, kind: '${ex['kind']}', existing: ex);
                      if (id != null) await _load();
                    }
                  : null,
              icon: const Icon(Icons.tune_rounded, size: AppIconSize.md),
              label: Text(t('الإعدادات', 'Settings')),
            ),
          if (widget.canExport && items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: _export,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'date', child: Text(t('الجدول كاملاً (حسب اليوم)', 'Whole timetable (by day)'))),
                PopupMenuItem(value: 'invigilator', child: Text(t('لكل مراقب', 'Per invigilator'))),
                PopupMenuItem(value: 'room', child: Text(t('لكل مكان', 'Per room'))),
              ],
              child: Chip(avatar: Icon(Icons.file_download_rounded, size: AppIconSize.md, color: c.primary), label: Text(t('تصدير: إكسل · وورد · PDF', 'Export: Excel · Word · PDF'))),
            ),
          if (widget.canApprove && items.isNotEmpty)
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!active && hard > 0) return appToast(t('عالج التعارضات قبل النشر', 'Fix the clashes before publishing'), error: true);
                      if (active && !await appConfirm(context, message: t('إيقاف نشر جدول الامتحانات؟', 'Unpublish the exam timetable?'))) return;
                      await _run(() => widget.api.publish(asInt(ex['id']), !active), ok: active ? t('أوقف النشر', 'Unpublished') : t('نُشر الجدول', 'Published'));
                    },
              icon: Icon(active ? Icons.unpublished_rounded : Icons.publish_rounded, size: AppIconSize.md),
              label: Text(active ? t('إيقاف النشر', 'Unpublish') : t('نشر', 'Publish')),
            ),
          if (widget.canEdit && !active)
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await appConfirm(context, message: t('حذف جدول الامتحانات؟', 'Delete this exam timetable?'), danger: true)) return;
                      try {
                        await widget.api.delete(asInt(ex['id']));
                        if (context.mounted) Navigator.of(context).pop();
                      } catch (x) {
                        appToast(_err(x), error: true);
                      }
                    },
              icon: Icon(Icons.delete_outline_rounded, color: c.danger, size: AppIconSize.md),
              label: Text(t('حذف', 'Delete'), style: TextStyle(color: c.danger)),
            ),
        ]),
        if (unplaced.isNotEmpty) ...[
          AppSectionTitle(t('بلا موعد ولماذا', 'Without a time, and why')),
          for (final u in unplaced)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                child: Row(children: [
                  Icon(Icons.event_busy_rounded, color: c.warning),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(names.course(u['course_id']), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                    Text(examReasonText('${u['reason']}'), style: AppType.label(context).copyWith(color: c.textMedium)),
                  ])),
                ]),
              ),
            ),
        ],
        if (conflicts.isNotEmpty) ...[
          AppSectionTitle(t('تعارضات', 'Clashes')),
          for (final k in conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppBanner(
                  icon: k['severity'] == 'error' ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                  text: '${examConflictText('${k['type']}')} · ${calendarDate(k['date'])} · ${(k['course_ids'] as List? ?? const []).map(names.course).join('، ')}',
                  color: k['severity'] == 'error' ? c.danger : c.warning),
            ),
        ],
        for (final d in byDate.entries) ...[
          AppSectionTitle(calendarDate(d.key, pattern: 'EEEE d MMMM y'), subtitle: t('${d.value.length} امتحان', '${d.value.length} exam(s)')),
          for (final x in d.value)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                onTap: () => _slot(x, editable: editable),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 92,
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xs),
                    decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)),
                    child: Column(children: [
                      Text(clockOf(x['start_time']), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
                      Text(clockOf(x['end_time']), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                    ]),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(names.course(x['course_id']), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                      const SizedBox(height: AppSpace.xxs),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        AppBadgePill(t('${x['students']} طالب', '${x['students']} students'), icon: Icons.people_alt_rounded, color: c.purple),
                        _made.containsKey(asInt(x['id']))
                            ? AppBadgePill(t('الاختبار جاهز', 'Exam created'), icon: Icons.task_alt_rounded, color: c.success)
                            : AppBadgePill(t('لم يُنشأ الاختبار', 'Exam not created'), icon: Icons.edit_note_rounded, color: c.textLight),
                        for (final r in (x['room_ids'] as List? ?? const [])) AppBadgePill(names.room(r), icon: Icons.meeting_room_rounded),
                        for (final u in (x['invigilator_ids'] as List? ?? const [])) AppBadgePill(names.person(u), icon: Icons.visibility_rounded, color: c.accent2),
                      ]),
                    ]),
                  ),
                  if (widget.canEdit && !active)
                    IconButton(
                      tooltip: x['locked'] == true ? t('مثبّت — لن يتغير عند التوليد', 'Pinned — kept when generating') : t('ثبّت الموعد', 'Pin this time'),
                      icon: Icon(x['locked'] == true ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: x['locked'] == true ? c.primary : c.textLight),
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                                await widget.api.editSlot(asInt(ex['id']), asInt(x['id']), {'locked': x['locked'] != true, 'expected_version': ex['version']});
                                return null;
                              }),
                    ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
