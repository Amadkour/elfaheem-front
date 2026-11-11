// lib/features/org/org_schedule_planning.dart — per-timetable enrollment estimates and lecture / lab groups.
//
//   CoursePlan            one course in one timetable: expected students, group sizes, groups, per-group staff
//   planCourse            pure: groups needed, balanced group sizes, weekly periods, problems (rooms too small, …)
//   CoursePlanApi         Remote (GET/PUT …/schedules/{sid}/course-plans) · Mock (dev only, in memory)
//   openCoursePlans       the "Enrollment & groups" page of a timetable
//
// The server has these routes (routers/organization/org_schedule_router.py). An older server answers a bare 404/405: the
// remote API then reports `unsupported` and the page shows the numbers as a read-only preview. The mock is compiled in only for debug / profile
// builds started with --dart-define=ORG_SCHEDULING_MOCKS=true and can never run in a release build.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_providers.dart';
import 'org_timetable_parts.dart' show courseName, showLoadForm;
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'package:flutter_education_app/design/app_tokens.dart';

const bool kOrgSchedulingMocks = !kReleaseMode && bool.fromEnvironment('ORG_SCHEDULING_MOCKS');

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

/// Who teaches one group. Null = the course's own staff from its requirements (teacher / any of its assistants).
class GroupStaff {
  const GroupStaff({required this.kind, required this.groupNo, this.teacherId, this.assistantId});
  final String kind; // lecture | lab
  final int groupNo; // 1-based
  final int? teacherId, assistantId;

  factory GroupStaff.fromJson(Map<String, dynamic> j) => GroupStaff(
        kind: j['kind'] == 'lab' ? 'lab' : 'lecture',
        groupNo: asInt(j['group_no'], 1),
        teacherId: j['teacher_id'] == null ? null : asInt(j['teacher_id']),
        assistantId: j['assistant_id'] == null ? null : asInt(j['assistant_id']),
      );

  Map<String, dynamic> toJson() => {'kind': kind, 'group_no': groupNo, 'teacher_id': teacherId, 'assistant_id': assistantId};
}

/// The most recent completed offering of a course — a suggested starting estimate, never authoritative.
class PlanHistory {
  const PlanHistory({required this.students, this.yearLabel, this.termKind});
  final int students;
  final String? yearLabel, termKind;

  static PlanHistory? fromJson(Object? j) {
    final m = asMap(j);
    return m['students'] == null ? null : PlanHistory(students: asInt(m['students']), yearLabel: m['year_label'] as String?, termKind: m['term_kind'] as String?);
  }

  Map<String, dynamic> toJson() => {'students': students, 'year_label': yearLabel, 'term_kind': termKind};
}

class CoursePlan {
  const CoursePlan({
    required this.courseId,
    this.enrolledStudents = 0,
    this.expectedStudents,
    this.lectureGroupSize,
    this.labGroupSize,
    this.lectureGroups,
    this.labGroups,
    this.groupStaff = const [],
    this.countSource,
    this.history,
  });

  final int courseId;
  final int enrolledStudents; // server-side count of active enrollments (read-only)
  final int? expectedStudents; // the planner's estimate; null = use enrolledStudents
  final int? lectureGroupSize, labGroupSize; // max students per group; null = one group
  final int? lectureGroups, labGroups; // explicit counts; null = derived from the sizes
  final List<GroupStaff> groupStaff;
  final String? countSource; // enrolled | manual | history — where expectedStudents came from
  final PlanHistory? history; // read-only, from the server

  int get students => expectedStudents ?? enrolledStudents;

  factory CoursePlan.fromJson(Map<String, dynamic> j) {
    int? opt(String k) => j[k] == null ? null : asInt(j[k]);
    return CoursePlan(
      courseId: asInt(j['course_id']),
      enrolledStudents: asInt(j['enrolled_students']),
      expectedStudents: opt('expected_students'),
      lectureGroupSize: opt('lecture_group_size'),
      labGroupSize: opt('lab_group_size'),
      lectureGroups: opt('lecture_groups'),
      labGroups: opt('lab_groups'),
      groupStaff: asMapList(j['group_staff']).map(GroupStaff.fromJson).toList(),
      countSource: j['count_source'] as String?,
      history: PlanHistory.fromJson(j['history']),
    );
  }

  /// PUT body — a full replacement, so every field is sent.
  Map<String, dynamic> toBody() => {
        'expected_students': expectedStudents,
        'lecture_group_size': lectureGroupSize,
        'lab_group_size': labGroupSize,
        'lecture_groups': lectureGroups,
        'lab_groups': labGroups,
        'group_staff': [for (final g in groupStaff) g.toJson()],
        if (countSource != null) 'count_source': countSource,
      };

  Map<String, dynamic> toJson() => {'course_id': courseId, 'enrolled_students': enrolledStudents, ...toBody(), if (history != null) 'history': history!.toJson()};

  /// The same plan with another student count: `enrolled` (the subscribed students — no estimate is sent) or
  /// `manual` with [count]. Group sizes, counts and staff are kept.
  CoursePlan withCount(String source, int? count) => CoursePlan(
        courseId: courseId,
        enrolledStudents: enrolledStudents,
        expectedStudents: source == 'manual' ? count : null,
        lectureGroupSize: lectureGroupSize,
        labGroupSize: labGroupSize,
        lectureGroups: lectureGroups,
        labGroups: labGroups,
        groupStaff: groupStaff,
        countSource: source,
        history: history,
      );
}

/// The plans to save when the wizard sets one student count for every selected course; [existing] keeps each
/// course's other planning fields (a PUT replaces the whole plan).
List<CoursePlan> applyStudentCount(Map<int, CoursePlan> existing, Iterable<int> courseIds, {required String source, int? count}) =>
    [for (final id in courseIds) (existing[id] ?? CoursePlan(courseId: id)).withCount(source, count)];

/// The courses planned for [termId] (org course `term_id`, GET /orgs/{id}/courses).
Set<int> termCourseIds(List<Map<String, dynamic>> courses, int termId) => {
      for (final c in courses)
        if (c['term_id'] != null && asInt(c['term_id']) == termId) asInt(c['id'])
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Planner (pure)
// ═════════════════════════════════════════════════════════════════════════════

/// Groups needed so no group exceeds [size]. No size or no students → one group.
int groupsNeeded(int students, int? size) => size == null || size <= 0 || students <= 0 ? 1 : (students + size - 1) ~/ size;

/// [students] split into [groups] as evenly as possible, larger groups first: 70 / 3 → [24, 23, 23].
List<int> splitGroups(int students, int groups) {
  if (groups <= 0) return const [];
  final base = students ~/ groups, extra = students % groups;
  return [for (var i = 0; i < groups; i++) base + (i < extra ? 1 : 0)];
}

class PlanIssue {
  const PlanIssue(this.severity, this.code, this.text);
  final String severity; // error | warning | info
  final String code;
  final String text;
}

class CoursePlanResult {
  const CoursePlanResult({required this.lectureSizes, required this.labSizes, required this.weeklyPeriods, required this.issues, this.autoLectureSize, this.autoLabSize});
  final List<int> lectureSizes, labSizes;
  final int weeklyPeriods; // every group's sessions × periods
  final int? autoLectureSize, autoLabSize; // group size taken from the largest suitable room (no size set); saved so the server agrees
  final List<PlanIssue> issues;

  int get lectureGroups => lectureSizes.length;
  int get labGroups => labSizes.length;
  bool get hasErrors => issues.any((i) => i.severity == 'error');
}

/// Largest capacity among active rooms of [kind] (null = any teaching room). 0 = none.
int largestRoom(List<Map<String, dynamic>> rooms, String? kind) => rooms
    .where((r) => r['is_active'] != false && r['kind'] != 'office' && (kind == null || r['kind'] == kind))
    .fold(0, (m, r) => asInt(r['capacity']) > m ? asInt(r['capacity']) : m);

/// What [plan] means for one course whose requirements are [load] (the `/loads` row) given the organization's [rooms].
/// Groups needed = ceil(students / maximum group size). With no size set, the maximum is the capacity of the largest
/// suitable active room (lab capacity for labs): 500 students and a 200-seat hall → 3 lecture groups, never one group
/// of 500. An explicit group count is kept as given and reported when its groups do not fit.
CoursePlanResult planCourse(CoursePlan plan, Map<String, dynamic> load, List<Map<String, dynamic>> rooms) {
  final n = plan.students;
  final hasLab = asInt(load['lab_sessions_per_week']) > 0;
  final lecRoom = load['room_kind'] as String?, labRoom = (load['lab_room_kind'] as String?) ?? 'lab';
  int? byRoom(String? kind) {
    final cap = largestRoom(rooms, kind);
    return cap > 0 ? cap : null;
  }

  final autoLec = plan.lectureGroupSize == null && plan.lectureGroups == null ? byRoom(lecRoom) : null;
  final autoLab = hasLab && plan.labGroupSize == null && plan.lectureGroupSize == null && plan.labGroups == null ? byRoom(labRoom) : null;
  final lecN = plan.lectureGroups ?? groupsNeeded(n, plan.lectureGroupSize ?? autoLec);
  final labN = hasLab ? (plan.labGroups ?? groupsNeeded(n, plan.labGroupSize ?? plan.lectureGroupSize ?? autoLab)) : 0;
  final lec = splitGroups(n, lecN), lab = splitGroups(n, labN);
  final issues = <PlanIssue>[];

  if (n == 0) {
    issues.add(PlanIssue('info', 'no_students',
        t('لا يوجد طلاب مسجلون ولا تقدير — أدخل العدد المتوقع ليُحسب عدد المجموعات.', 'No enrolled students and no estimate — enter the expected number to size the groups.')));
  } else if (plan.expectedStudents != null && plan.countSource != 'enrolled') {
    issues.add(PlanIssue('info', 'estimate',
        t('العدد ($n) تقدير${plan.countSource == 'history' ? ' من آخر طرح مكتمل' : ''} وليس التسجيل الفعلي (${plan.enrolledStudents}).',
            'The count ($n) is an estimate${plan.countSource == 'history' ? ' from the last completed offering' : ''}, not the actual enrollment (${plan.enrolledStudents}).')));
  }
  if (n > 0 && autoLec != null && lecN > 1) {
    issues.add(PlanIssue('info', 'sized_by_room',
        t('لا حد محدد للمجموعة — قُسّمت المحاضرة إلى $lecN مجموعات حسب أكبر مكان مناسب ($autoLec مقعد).', 'No group size set — the lecture is split into $lecN groups by the largest suitable room ($autoLec seats).')));
  }
  if (n > 0 && autoLab != null && labN > 1) {
    issues.add(PlanIssue('info', 'sized_by_room',
        t('السكشن قُسّم إلى $labN مجموعات حسب سعة المعمل ($autoLab).', 'The lab is split into $labN groups by the lab capacity ($autoLab).')));
  }
  void overfull(String kind, int? size, List<int> sizes) {
    if (size != null && sizes.isNotEmpty && sizes.first > size) {
      issues.add(PlanIssue('warning', 'groups_overfull',
          t('مجموعات $kind أكبر من الحد ($size): ${sizes.first} طالب — زد عدد المجموعات إلى ${groupsNeeded(n, size)}.',
              '$kind groups exceed the limit ($size): ${sizes.first} students — raise them to ${groupsNeeded(n, size)}.')));
    }
  }

  overfull(t('المحاضرة', 'Lecture'), plan.lectureGroupSize, lec);
  if (hasLab) overfull(t('السكشن', 'Lab'), plan.labGroupSize ?? plan.lectureGroupSize, lab);

  void roomFits(String kind, String? roomKind, List<int> sizes) {
    if (sizes.isEmpty || sizes.first == 0) return;
    final cap = largestRoom(rooms, roomKind);
    if (cap < sizes.first) {
      issues.add(PlanIssue('error', 'no_room_fits',
          cap == 0
              ? t('لا يوجد مكان نشط من نوع ${roomKindLabel(roomKind ?? 'lecture')} لـ$kind.', 'No active ${roomKindLabel(roomKind ?? 'lecture')} room for the $kind.')
              : t('أكبر مكان متاح يسع $cap ومجموعة $kind ${sizes.first} — قسّمها أو أضف مكاناً أكبر.',
                  'The largest room holds $cap but a $kind group has ${sizes.first} — split it or add a bigger room.')));
    }
  }

  roomFits(t('المحاضرة', 'lecture'), load['room_kind'] as String?, lec);
  if (hasLab) roomFits(t('السكشن', 'lab'), (load['lab_room_kind'] as String?) ?? 'lab', lab);

  final asstCount = ((load['assistant_ids'] as List?) ?? const []).length;
  final namedLab = plan.groupStaff.where((g) => g.kind == 'lab' && g.groupNo <= labN && g.assistantId != null).length;
  if (hasLab && labN > 1 && asstCount + namedLab == 0) {
    issues.add(PlanIssue('warning', 'lab_staff', t('$labN مجموعات سكشن بلا معيد محدد.', '$labN lab groups with no assistant set.')));
  }

  final weekly = lecN * asInt(load['sessions_per_week'], 1) * asInt(load['periods_per_session'], 1) +
      labN * asInt(load['lab_sessions_per_week']) * asInt(load['lab_periods_per_session'], 1);
  return CoursePlanResult(lectureSizes: lec, labSizes: lab, weeklyPeriods: weekly, issues: issues, autoLectureSize: autoLec, autoLabSize: autoLab);
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class CoursePlanList {
  const CoursePlanList(this.items, {this.unsupported = false, this.mock = false});
  final Map<int, CoursePlan> items; // course id → plan
  final bool unsupported; // the server has no course-plans route yet
  final bool mock; // development data, not saved on the server
}

abstract class CoursePlanApi {
  Future<CoursePlanList> list(int scheduleId);

  /// Returns the saved plan, or throws [ApiException] (server text in `message`).
  Future<CoursePlan> save(int scheduleId, CoursePlan plan);

  /// All or nothing (PUT …/course-plans): every plan is validated, then all are saved together.
  Future<List<CoursePlan>> saveAll(int scheduleId, List<CoursePlan> plans);
}

class RemoteCoursePlanApi implements CoursePlanApi {
  RemoteCoursePlanApi(this.api, this.base);
  final ApiClient api;
  final String base; // /orgs/{id}

  @override
  Future<CoursePlanList> list(int scheduleId) async {
    try {
      final r = await api.get('$base/schedules/$scheduleId/course-plans');
      return CoursePlanList({for (final j in asMapList(asMap(r)['items'])) asInt(j['course_id']): CoursePlan.fromJson(j)});
    } catch (e) {
      final err = ApiException.from(e);
      if (orgEndpointMissing(err)) return const CoursePlanList({}, unsupported: true);
      rethrow;
    }
  }

  @override
  Future<CoursePlan> save(int scheduleId, CoursePlan plan) async =>
      CoursePlan.fromJson(asMap(await api.put('$base/schedules/$scheduleId/course-plans/${plan.courseId}', body: plan.toBody())));

  @override
  Future<List<CoursePlan>> saveAll(int scheduleId, List<CoursePlan> plans) async {
    final r = await api.put('$base/schedules/$scheduleId/course-plans', body: {
      'items': [for (final p in plans) {'course_id': p.courseId, ...p.toBody()}]
    });
    return asMapList(asMap(r)['items']).map(CoursePlan.fromJson).toList();
  }
}

/// In-memory stand-in for development. Keeps what is saved until the app restarts.
class MockCoursePlanApi implements CoursePlanApi {
  final _store = <int, Map<int, CoursePlan>>{};

  @override
  Future<CoursePlanList> list(int scheduleId) async => CoursePlanList(Map.of(_store[scheduleId] ?? const {}), mock: true);

  @override
  Future<CoursePlan> save(int scheduleId, CoursePlan plan) async {
    for (final v in [plan.expectedStudents, plan.lectureGroupSize, plan.labGroupSize]) {
      if (v != null && v < 1) throw ApiException(statusCode: 422, message: t('القيم يجب أن تكون 1 أو أكثر', 'Values must be 1 or more'), code: 'bad_plan');
    }
    return (_store[scheduleId] ??= {})[plan.courseId] = plan;
  }

  @override
  Future<List<CoursePlan>> saveAll(int scheduleId, List<CoursePlan> plans) async {
    for (final p in plans) {
      if (p.expectedStudents != null && p.expectedStudents! < 1) {
        throw ApiException(statusCode: 422, message: t('القيم يجب أن تكون 1 أو أكثر', 'Values must be 1 or more'), code: 'bad_plan');
      }
    }
    return [for (final p in plans) await save(scheduleId, p)];
  }
}

final _mockApi = MockCoursePlanApi();

CoursePlanApi coursePlanApi(OrgScheduleProvider p) => kOrgSchedulingMocks ? _mockApi : RemoteCoursePlanApi(p.api, p.base);

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

/// A page pushed from the timetable studio (D-103): the dashboard's own header (OrgPushedPage: Back · title ·
/// subtitle · [primaryAction] · Refresh · calendar · bell · switcher) when I work in the organization; else (the member
/// dashboard's managed pages before the session lists it) the older bar with its exit button, exactly as before.
/// The page under it registers its loader with OrgPageRefresh.register so Refresh reloads it in place.
Widget orgStudioPage(BuildContext context,
    {required String title, String? subtitle, Widget? primaryAction, double? maxWidth, bool webCard = true, required Widget child}) {
  if (!orgUsesDashboardHeader(context, null)) {
    return BasePage(
      useWebCard: webCard,
      maxWith: maxWidth,
      appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
      child: child,
    );
  }
  return OrgPushedPage(title: title, subtitle: subtitle, primaryAction: primaryAction, maxWidth: maxWidth, child: child);
}

/// The open timetable's name, for a pushed page's subtitle (null when it has none).
String? studioSubtitle(OrgScheduleProvider p) {
  final name = '${p.schedule?['name'] ?? ''}'.trim();
  return name.isEmpty ? null : name;
}

Future<void> openCoursePlans(BuildContext context, OrgScheduleProvider p, {bool canEdit = false}) => Navigator.of(context).push(MaterialPageRoute(
    builder: (ctx) => orgStudioPage(
          ctx,
          title: t('الطلاب والمجموعات', 'Enrollment & groups'),
          subtitle: studioSubtitle(p),
          child: TimetableCoursesView(p: p, canEdit: canEdit, ownsRefresh: true),
        )));

/// The courses that enter the timetable (its scope; group sizes = min(course max group, room capacity), overflow goes
/// to another group, never dropped): enrolment, lecture / lab groups, lab type, issues, and edit links (the plan of
/// this timetable · the course requirements). Embedded in the studio's "Courses" view and in openCoursePlans.
class TimetableCoursesView extends StatefulWidget {
  const TimetableCoursesView({super.key, required this.p, required this.canEdit, this.api, this.ownsRefresh = false});
  final OrgScheduleProvider p;
  final CoursePlanApi? api;
  final bool canEdit;

  /// A page of its own (openCoursePlans): the header's Refresh reloads it. Embedded in the studio it leaves the
  /// studio's Refresh alone.
  final bool ownsRefresh;

  @override
  State<TimetableCoursesView> createState() => _CoursePlansPageState();
}

class _CoursePlansPageState extends State<TimetableCoursesView> {
  late final CoursePlanApi api = widget.api ?? coursePlanApi(widget.p);

  CoursePlanList? data;
  String? error;

  int get sid => asInt(widget.p.schedule?['id']);

  /// The timetable's own courses (null course_ids = every course of the organization).
  List<Map<String, dynamic>> get loads {
    final only = (widget.p.schedule?['course_ids'] as List?)?.map(asInt).toSet();
    return [for (final l in widget.p.loads) if (only == null || only.contains(asInt(l['course_id']))) l];
  }

  OrgPageRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    if (widget.ownsRefresh) _refresh = OrgPageRefresh.register(context, _load);
    _load();
  }

  @override
  void dispose() {
    _refresh?.unregister(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final r = await api.list(sid);
      if (mounted) setState(() => data = r);
      if (mounted) _refresh?.markUpdated();
    } catch (e) {
      if (mounted) setState(() => error = orgErrorText(ApiException.from(e)));
    }
  }

  CoursePlan _plan(int cid) => data?.items[cid] ?? CoursePlan(courseId: cid);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (error != null) return ErrorRetry(message: error!, onRetry: _load);
    final d = data;
    if (d == null) return const AppListSkeleton();
    final results = {for (final l in loads) asInt(l['course_id']): planCourse(_plan(asInt(l['course_id'])), l, widget.p.rooms)};
    final students = loads.fold<int>(0, (s, l) => s + _plan(asInt(l['course_id'])).students);
    final groups = results.values.fold<int>(0, (s, r) => s + r.lectureGroups + r.labGroups);
    final periods = results.values.fold<int>(0, (s, r) => s + r.weeklyPeriods);
    final blocking = results.values.where((r) => r.hasErrors).length;
    final editable = widget.canEdit && !d.unsupported;

    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
        if (d.unsupported)
          RowCard(
              accent: c.warning,
              child: Text(t('حفظ أعداد الطلاب والمجموعات يحتاج تحديثاً في الخادم. الأرقام أدناه معاينة محسوبة من متطلبات المقررات ولا يستخدمها المولّد بعد.',
                  'Saving enrollment and groups needs a server update. The numbers below are a preview from the course requirements; the generator does not use them yet.'))),
        if (d.mock)
          RowCard(
              accent: c.purple,
              child: Text(t('وضع تجريبي (للتطوير فقط): التعديلات محفوظة في الذاكرة ولا تصل إلى الخادم.', 'Development mock: changes stay in memory and never reach the server.'))),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          _stat(context, t('طلاب (تقديري)', 'Students (est.)'), '$students', Icons.groups_rounded, c.primary),
          _stat(context, t('مجموعات', 'Groups'), '$groups', Icons.workspaces_rounded, c.purple),
          _stat(context, t('فترات أسبوعياً', 'Periods / week'), '$periods', Icons.schedule_rounded, c.accent2),
          _stat(context, t('تحتاج حلاً', 'Need a fix'), '$blocking', Icons.error_outline_rounded, blocking > 0 ? c.danger : c.success),
        ]),
        const SizedBox(height: AppSpace.md),
        if (loads.isEmpty) Padding(padding: const EdgeInsets.all(AppSpace.md), child: Text(t('لا مقررات في هذا الجدول.', 'No courses in this timetable.'))),
        for (final l in loads) _courseCard(context, l, results[asInt(l['course_id'])]!, editable),
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, String value, IconData icon, Color color) => Container(
        width: 160,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpace.xs),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: AppType.section(context)),
            Text(label, style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
          ])),
        ]),
      );

  Widget _courseCard(BuildContext context, Map<String, dynamic> l, CoursePlanResult r, bool editable) {
    final c = context.colors;
    final plan = _plan(asInt(l['course_id']));
    String sizes(List<int> s) => s.isEmpty ? '—' : (s.toSet().length == 1 ? '${s.length} × ${s.first}' : s.join(' / '));
    return RowCard(
      accent: r.hasErrors ? c.danger : (r.issues.any((i) => i.severity == 'warning') ? c.warning : null),
      onTap: editable ? () => _edit(l) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(courseName(l), style: AppType.bodyStrong(context))),
          if (widget.canEdit)
            IconButton(
              tooltip: t('تعديل متطلبات المقرر', 'Edit the course requirements'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: () async {
                if (await showLoadForm(context, widget.p, l) && mounted) setState(() {});
              },
            ),
          if (editable) const Icon(Icons.chevron_right_rounded),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(
            [
              plan.expectedStudents != null
                  ? t('${plan.expectedStudents} متوقع (${plan.enrolledStudents} مسجل)', '${plan.expectedStudents} expected (${plan.enrolledStudents} enrolled)')
                  : t('${plan.enrolledStudents} مسجل', '${plan.enrolledStudents} enrolled'),
              '${t('محاضرات', 'Lectures')}: ${sizes(r.lectureSizes)}',
              if (r.labGroups > 0) '${t('سكاشن', 'Labs')}: ${sizes(r.labSizes)} (${roomKindLabel('${l['lab_room_kind'] ?? 'lab'}')})',
              t('${r.weeklyPeriods} فترة/أسبوع', '${r.weeklyPeriods} periods/week'),
            ].join(' · '),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        for (final i in r.issues)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i.severity == 'error' ? Icons.error_rounded : (i.severity == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline_rounded),
                  size: AppIconSize.sm, color: i.severity == 'error' ? c.danger : (i.severity == 'warning' ? c.warning : c.textLight)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(i.text, style: AppType.meta(context).copyWith(color: context.colors.textDark))),
            ]),
          ),
      ]),
    );
  }

  Future<void> _edit(Map<String, dynamic> l) async {
    final saved = await showCoursePlanSheet(context, widget.p, api, sid, l, _plan(asInt(l['course_id'])));
    if (saved != null && mounted) setState(() => data = CoursePlanList({...data!.items, saved.courseId: saved}, mock: data!.mock));
  }
}

/// Edits one course's plan. Returns the saved plan, or null when cancelled.
Future<CoursePlan?> showCoursePlanSheet(BuildContext context, OrgScheduleProvider p, CoursePlanApi api, int scheduleId, Map<String, dynamic> load, CoursePlan plan) async {
  final hasLab = asInt(load['lab_sessions_per_week']) > 0;
  final expected = TextEditingController(text: plan.expectedStudents?.toString() ?? '');
  final lecSize = TextEditingController(text: plan.lectureGroupSize?.toString() ?? '');
  final labSize = TextEditingController(text: plan.labGroupSize?.toString() ?? '');
  int? lecGroups = plan.lectureGroups, labGroups = plan.labGroups;
  String? source = plan.countSource == 'history' ? 'history' : null; // set only by the "last offering" chip
  final staff = {for (final g in plan.groupStaff) '${g.kind}${g.groupNo}': g};
  bool busy = false;
  String? err;
  CoursePlan? out;

  int? num(TextEditingController c) => int.tryParse(c.text.trim());
  CoursePlan draft() => CoursePlan(
        courseId: plan.courseId,
        enrolledStudents: plan.enrolledStudents,
        expectedStudents: num(expected),
        lectureGroupSize: num(lecSize),
        labGroupSize: hasLab ? num(labSize) : null,
        lectureGroups: lecGroups,
        labGroups: hasLab ? labGroups : null,
        groupStaff: const [],
        countSource: num(expected) == null ? 'enrolled' : (source ?? 'manual'),
      );

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final r = planCourse(draft(), load, p.rooms);
        Widget field(String label, TextEditingController ctl, String hint) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: label, helperText: hint),
                onChanged: (_) => set(() {
                  if (ctl == expected) source = null;
                }),
              ),
            );
        Widget groupsRow(String label, int derived, int? value, ValueChanged<int?> on) => Row(children: [
              Expanded(
                  child: Text(value == null ? '$label: $derived ${t('(تلقائي)', '(auto)')}' : '$label: $value',
                      style: AppType.bodyStrong(ctx))),
              IconButton(tooltip: t('تقليل', 'Decrease'), onPressed: (value ?? derived) > 1 ? () => set(() => on((value ?? derived) - 1)) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
              IconButton(tooltip: t('زيادة', 'Increase'), onPressed: (value ?? derived) < 40 ? () => set(() => on((value ?? derived) + 1)) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
              if (value != null) TextButton(onPressed: () => set(() => on(null)), child: Text(t('تلقائي', 'Auto'))),
            ]);
        Widget staffPick(String kind, int no, int size) {
          final key = '$kind$no', g = staff[key];
          final role = kind == 'lab' ? 'teacher_assistant' : 'teacher';
          final v = kind == 'lab' ? g?.assistantId : g?.teacherId;
          return OrgPickField<int>(
            label: '${kind == 'lab' ? t('سكشن', 'Lab') : t('محاضرة', 'Lecture')} $no · ${t('$size طالب', '$size students')}',
            icon: kind == 'lab' ? Icons.science_rounded : Icons.person_rounded,
            value: v,
            allowNone: true,
            noneLabel: t('طاقم المقرر', 'Course staff'),
            options: {for (final u in p.staffOf(role)) asInt(u['id']): '${u['name']}'},
            onChanged: (id) => set(() => staff[key] = GroupStaff(kind: kind, groupNo: no, teacherId: kind == 'lab' ? null : id, assistantId: kind == 'lab' ? id : null)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(courseName(load)),
            field(t('العدد المتوقع للطلاب', 'Expected students'), expected,
                t('فارغ = عدد المسجلين حالياً (${plan.enrolledStudents})', 'Empty = currently enrolled (${plan.enrolledStudents})')),
            if (plan.history != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: ActionChip(
                  avatar: Icon(source == 'history' ? Icons.check_rounded : Icons.history_rounded, size: AppIconSize.md),
                  label: Text(t('آخر فصل مكتمل${plan.history!.yearLabel == null ? '' : ' (${plan.history!.yearLabel})'}: ${plan.history!.students} طالب — تقدير مبدئي',
                      'Last completed offering${plan.history!.yearLabel == null ? '' : ' (${plan.history!.yearLabel})'}: ${plan.history!.students} students — a starting estimate')),
                  onPressed: () => set(() {
                    expected.text = '${plan.history!.students}';
                    source = 'history';
                  }),
                ),
              ),
            field(t('أقصى عدد في مجموعة المحاضرة', 'Max students per lecture group'), lecSize, t('فارغ = مجموعة واحدة', 'Empty = one group')),
            groupsRow(t('مجموعات المحاضرة', 'Lecture groups'), groupsNeeded(draft().students, num(lecSize)), lecGroups, (v) => lecGroups = v),
            if (hasLab) ...[
              field(t('أقصى عدد في مجموعة السكشن', 'Max students per lab group'), labSize, t('فارغ = مثل المحاضرة', 'Empty = same as the lecture')),
              groupsRow(t('مجموعات السكشن', 'Lab groups'), groupsNeeded(draft().students, num(labSize) ?? num(lecSize)), labGroups, (v) => labGroups = v),
            ],
            if (r.lectureGroups > 1 || r.labGroups > 1) ...[
              const SizedBox(height: AppSpace.xs),
              Text(t('من يدرّس كل مجموعة', 'Who teaches each group'), style: AppType.bodyStrong(ctx)),
              const SizedBox(height: AppSpace.xs),
              for (var i = 0; i < r.lectureGroups && r.lectureGroups > 1; i++) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: staffPick('lecture', i + 1, r.lectureSizes[i])),
              for (var i = 0; i < r.labGroups && r.labGroups > 1; i++) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: staffPick('lab', i + 1, r.labSizes[i])),
            ],
            for (final i in r.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text('• ${i.text}', style: AppType.label(ctx).copyWith(color: i.severity == 'error' ? c.danger : (i.severity == 'warning' ? c.warning : c.textMedium))),
              ),
            if (err != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(err!, style: AppType.row(ctx).copyWith(color: c.danger))),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                final d = draft();
                final keep = [
                  for (final g in staff.values)
                    if ((g.teacherId ?? g.assistantId) != null && g.groupNo <= (g.kind == 'lab' ? r.labGroups : r.lectureGroups)) g
                ];
                set(() {
                  busy = true;
                  err = null;
                });
                try {
                  final saved = await api.save(
                      scheduleId,
                      CoursePlan(
                        courseId: d.courseId,
                        enrolledStudents: d.enrolledStudents,
                        expectedStudents: d.expectedStudents,
                        lectureGroupSize: d.lectureGroupSize ?? r.autoLectureSize,
                        labGroupSize: d.labGroupSize ?? r.autoLabSize,
                        lectureGroups: d.lectureGroups,
                        labGroups: d.labGroups,
                        groupStaff: keep,
                        countSource: d.countSource,
                      ));
                  out = saved;
                  if (ctx.mounted) Navigator.pop(ctx);
                  toast(t('تم الحفظ', 'Saved'));
                } catch (e) {
                  final x = ApiException.from(e);
                  set(() {
                    busy = false;
                    err = orgEndpointMissing(x) ? t('الخادم لا يدعم حفظ المجموعات بعد.', 'The server cannot save groups yet.') : orgErrorText(x);
                  });
                }
              },
            ),
          ]),
        );
      }));
  return out;
}