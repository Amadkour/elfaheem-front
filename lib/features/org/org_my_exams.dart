// lib/features/org/org_my_exams.dart — "My exams": a member's exams from PUBLISHED exam timetables, and the
// "weekly classes paused for exams" rule as the app shows it.
//
//   GET /api/v1/org/public/me/exams[?org_id]   (back: services/organization/member_exams.py, routers/…/org_me_router.py)
//       students: the exams of the courses they are enrolled in · staff: the exams they invigilate (role=invigilator)
//       starts_at / ends_at are naive UTC; every time is shown through AppTime (the org's timezone and 12h/24h).
//
//   Weekly pause: a published exam timetable with `pause_weekly` suspends the weekly sessions of its term on the dates
//   of its window. Timetable replies carry `exam_pauses` [{exam_schedule_id, name, kind, start_date, end_date}] (and
//   `paused_today` on /schedule/me); [examPauseOn] / [examPauseBanner] leave those dates out of "today" / "next".
//
// Opened from the member dashboard / member space, the inbox's "exam" items and the "exam timetable published"
// notification (AppNavigator module `org_exams`).
//
// Pure (unit-tested): MyExam · nextExam · groupExamsByDay · examCountdown · examPauseOn · activeExamPauses.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show ExamAuthoringApi;
import 'package:flutter_education_app/features/exams/exam_quick.dart' show examForSlot;
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart' show showSlotExamSheet;
import 'org_schedule_versions.dart' show calendarDate;
import 'org_v3.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

/// One exam of the caller, as GET /me/exams returns it.
class MyExam {
  MyExam(this.raw)
      : id = asInt(raw['id']),
        orgId = asInt(raw['org_id']),
        courseId = asInt(raw['course_id']),
        kind = '${raw['kind'] ?? 'final'}',
        role = '${raw['role'] ?? 'student'}',
        start = orgParseUtc(raw['starts_at'])?.toUtc(),
        end = orgParseUtc(raw['ends_at'])?.toUtc(),
        course = asMap(raw['course']),
        organization = asMap(raw['organization']),
        rooms = asMapList(raw['rooms']),
        invigilators = asMapList(raw['invigilators']),
        myRoomId = raw['my_room_id'] == null ? null : asInt(raw['my_room_id']);

  final Map<String, dynamic> raw;
  final int id, orgId, courseId;
  final String kind, role;
  final DateTime? start, end;
  final Map<String, dynamic> course, organization;
  final List<Map<String, dynamic>> rooms, invigilators;
  final int? myRoomId;

  bool get invigilating => role == 'invigilator';
  bool get teaching => role == 'teacher';

  String get courseName => _pick(course) ?? '#$courseId';
  String get orgName => _pick(organization) ?? '';
  List<String> get roomNames => [for (final r in rooms) if ('${r['name'] ?? ''}'.isNotEmpty) '${r['name']}'];
  List<String> get invigilatorNames => [for (final u in invigilators) if ('${u['name'] ?? ''}'.isNotEmpty) '${u['name']}'];
  String? get myRoomName {
    final r = rooms.where((x) => asInt(x['id']) == myRoomId).firstOrNull;
    return r == null ? null : '${r['name'] ?? ''}';
  }

  static String? _pick(Map<String, dynamic> m) {
    final ar = '${m['name_ar'] ?? ''}'.trim(), en = '${m['name_en'] ?? ''}'.trim();
    final s = AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
    return s.isEmpty ? null : s;
  }
}

List<MyExam> parseMyExams(Object? reply) {
  final out = [for (final x in asMapList(asMap(reply)['items'])) MyExam(x)].where((e) => e.start != null).toList();
  out.sort((a, b) {
    final k = a.start!.compareTo(b.start!);
    return k != 0 ? k : a.courseId.compareTo(b.courseId);
  });
  return out;
}

/// The exam running now or the first one still ahead (exams are sorted by start); null when all are over.
MyExam? nextExam(List<MyExam> exams, DateTime nowUtc) {
  for (final e in exams) {
    final end = e.end ?? e.start!;
    if (end.isAfter(nowUtc)) return e;
  }
  return null;
}

/// Exams grouped by their day on the wall clock [toWall] gives (AppTime.toZone in the app), days ascending.
List<(DateTime, List<MyExam>)> groupExamsByDay(List<MyExam> exams, DateTime Function(DateTime utc) toWall) {
  final map = <DateTime, List<MyExam>>{};
  for (final e in exams) {
    if (e.start == null) continue;
    final w = toWall(e.start!);
    map.putIfAbsent(DateTime(w.year, w.month, w.day), () => []).add(e);
  }
  final days = map.keys.toList()..sort();
  return [for (final d in days) (d, map[d]!..sort((a, b) => a.start!.compareTo(b.start!)))];
}

/// Time left until [e] starts: (running now, days, hours, minutes, seconds). A running exam has zero left.
(bool, int, int, int, int) examCountdown(MyExam e, DateTime nowUtc) {
  final left = e.start!.difference(nowUtc);
  if (left.isNegative || left == Duration.zero) return (true, 0, 0, 0, 0);
  return (false, left.inDays, left.inHours % 24, left.inMinutes % 60, left.inSeconds % 60);
}

/// `exam_pauses` of a timetable reply (GET …/schedules/{sid}, /schedule/me items, distributed copies).
List<Map<String, dynamic>> examPausesOf(Map<String, dynamic>? timetable) => asMapList(timetable?['exam_pauses']);

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The exam window that pauses the weekly timetable on [day] (a calendar date), or null.
Map<String, dynamic>? examPauseOn(DateTime day, List<Map<String, dynamic>> pauses) {
  final d = _isoDay(day);
  for (final p in pauses) {
    final a = '${p['start_date'] ?? ''}', b = '${p['end_date'] ?? ''}';
    if (a.isNotEmpty && b.isNotEmpty && a.compareTo(d) <= 0 && d.compareTo(b) <= 0) return p;
  }
  return null;
}

/// Windows not over yet on [today] (running first, then by start).
List<Map<String, dynamic>> activeExamPauses(List<Map<String, dynamic>> pauses, DateTime today) {
  final d = _isoDay(today);
  return pauses.where((p) => '${p['end_date'] ?? ''}'.compareTo(d) >= 0).toList()
    ..sort((a, b) => '${a['start_date']}'.compareTo('${b['start_date']}'));
}

/// "Classes paused for exams from X to Y".
String examPauseText(Map<String, dynamic> p) {
  final a = calendarDate(p['start_date'], pattern: 'EEE d MMM'), b = calendarDate(p['end_date'], pattern: 'EEE d MMM');
  return t('المحاضرات الأسبوعية متوقفة للامتحانات من $a إلى $b', 'Classes paused for exams from $a to $b');
}

/// Today in the effective timezone (AppTime), as a calendar date.
DateTime appToday() {
  final w = AppTime.toZone(DateTime.now().toUtc());
  return DateTime(w.year, w.month, w.day);
}

/// The banner(s) for a timetable's exam pauses — nothing when no window is running or ahead.
Widget examPauseBanner(BuildContext context, List<Map<String, dynamic>> pauses,
    {EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: AppSpace.sm), bool myExamsAction = true}) {
  final shown = activeExamPauses(pauses, appToday());
  if (shown.isEmpty) return const SizedBox.shrink();
  final c = context.colors;
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final p in shown)
      Padding(
        padding: padding,
        child: AppBanner(
          icon: Icons.event_busy_rounded,
          text: examPauseText(p),
          color: examPauseOn(appToday(), [p]) != null ? c.warning : c.primary,
          action: myExamsAction
              ? TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredMyExams())),
                  child: Text(t('امتحاناتي', 'My exams')),
                )
              : null,
        ),
      ),
  ]);
}

String myExamKindLabel(String k) => k == 'midterm' ? t('منتصف الفصل', 'Midterm') : t('نهائي', 'Final');

// ═════════════════════════════════════════════════════════════════════════════
//  Screen
// ═════════════════════════════════════════════════════════════════════════════

/// Opens My exams (optionally one organization's).
Future<void> openMyExams(BuildContext context, {int? orgId}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredMyExams(orgId: orgId)));

class MyExamsScreen extends StatelessWidget {
  const MyExamsScreen({super.key, this.orgId});
  final int? orgId;

  @override
  Widget build(BuildContext context) => BasePage(
        useWebCard: true,
        maxWith: 820,
        appBar: ScreenAppBar(title: t('امتحاناتي', 'My exams')),
        child: _MyExamsView(orgId: orgId),
      );
}

class _MyExamsView extends StatefulWidget {
  const _MyExamsView({this.orgId});
  final int? orgId;

  @override
  State<_MyExamsView> createState() => _MyExamsViewState();
}

class _MyExamsViewState extends State<_MyExamsView> {
  List<MyExam>? exams;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (exams == null && error != null) setState(() => error = null);
    try {
      final r = await ApiClient().get('/api/v1/org/public/me/exams', queryParams: {if (widget.orgId != null) 'org_id': widget.orgId});
      if (mounted) {
        setState(() {
          exams = parseMyExams(r);
          error = null;
        });
      }
    } catch (e) {
      final x = ApiException.from(e);
      final msg = orgEndpointMissing(x) ? t('عرض الامتحانات يحتاج تحديث الخادم.', 'My exams needs a server update.') : x.message;
      if (mounted) setState(() => error = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = exams;
    if (list == null && error == null) return const AppListSkeleton(items: 5);
    return AppRefresh(
      onRefresh: _load,
      child: ValueListenableBuilder<int>(
        valueListenable: AppTime.version,
        builder: (context, _, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxl),
          children: [
            if (error != null)
              AppBanner(
                icon: Icons.error_outline_rounded,
                text: error!,
                color: c.danger,
                action: TextButton(onPressed: _load, child: Text(t('أعد المحاولة', 'Try again'))),
              )
            else if (list!.isEmpty)
              AppEmpty(
                icon: Icons.event_available_rounded,
                title: t('لا امتحانات قادمة', 'No upcoming exams'),
                message: t('تظهر هنا امتحاناتك عند نشر جدول الامتحانات.', 'Your exams appear here once the exam timetable is published.'),
                actionLabel: t('تحديث', 'Refresh'),
                onAction: _load,
              )
            else ...[
              _NextExamHero(exams: list),
              for (final (day, items) in groupExamsByDay(list, AppTime.toZone)) ...[
                AppSectionTitle(
                  _dayTitle(day),
                  subtitle: t('${items.length} امتحان', items.length == 1 ? '1 exam' : '${items.length} exams'),
                ),
                for (final e in items) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: _ExamCard(e: e)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _dayTitle(DateTime day) {
    final today = appToday();
    final diff = day.difference(today).inDays;
    final date = calendarDate(_isoDay(day), pattern: 'EEEE d MMMM');
    if (diff == 0) return '${t('اليوم', 'Today')} · $date';
    if (diff == 1) return '${t('غداً', 'Tomorrow')} · $date';
    return date;
  }
}

/// The countdown to the next exam (ticks every second).
class _NextExamHero extends StatefulWidget {
  const _NextExamHero({required this.exams});
  final List<MyExam> exams;

  @override
  State<_NextExamHero> createState() => _NextExamHeroState();
}

class _NextExamHeroState extends State<_NextExamHero> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final next = nextExam(widget.exams, now);
    if (next == null) {
      return AppHero(
        icon: Icons.verified_rounded,
        title: t('انتهت امتحاناتك', 'Your exams are over'),
        subtitle: t('بالتوفيق في النتائج!', 'Good luck with the results!'),
      );
    }
    final (running, d, h, m, s) = examCountdown(next, now);
    final when = '${AppTime.date(next.start!, pattern: 'EEEE d MMM')} · ${AppTime.time(next.start!)} – ${AppTime.time(next.end ?? next.start!)}';
    final where = next.invigilating ? (next.myRoomName ?? next.roomNames.join('، ')) : next.roomNames.join('، ');
    return AppHero(
      icon: running ? Icons.edit_note_rounded : Icons.hourglass_top_rounded,
      title: running
          ? t('امتحان ${next.courseName} الآن', '${next.courseName} exam is on now')
          : t('امتحانك القادم: ${next.courseName}', 'Next exam: ${next.courseName}'),
      subtitle: [when, if (where.isNotEmpty) where].join('\n'),
      stats: running
          ? [
              AppHeroStat(icon: Icons.timer_off_rounded, value: AppTime.time(next.end ?? next.start!), label: t('ينتهي', 'ends')),
              AppHeroStat(icon: Icons.assignment_rounded, value: '${widget.exams.length}', label: t('امتحانات', 'exams')),
            ]
          : [
              AppHeroStat(icon: Icons.calendar_today_rounded, value: '$d', label: t('يوم', 'days')),
              AppHeroStat(icon: Icons.schedule_rounded, value: '$h', label: t('ساعة', 'hours')),
              AppHeroStat(icon: Icons.timer_rounded, value: m.toString().padLeft(2, '0'), label: t('دقيقة', 'min')),
              AppHeroStat(icon: Icons.av_timer_rounded, value: s.toString().padLeft(2, '0'), label: t('ثانية', 'sec')),
            ],
    );
  }
}

/// A teacher's timetabled exam: create the engine exam now (or not), or open the one already made from this slot.
Future<void> openTeacherSlotExam(BuildContext context, MyExam e) async {
  final scope = await ExamAuthoringApi().resolveScope(e.courseId, orgId: e.orgId);
  if (!context.mounted) return;
  if (scope.list.unavailable) return appToast(t('الاختبارات الإلكترونية تحتاج تحديث الخادم', 'Online exams need a server update'), error: true);
  await showSlotExamSheet(context,
      courseName: e.courseName,
      courseId: e.courseId,
      orgId: scope.orgId,
      slotId: e.id,
      kind: e.kind,
      startsAt: e.start,
      endsAt: e.end,
      exam: scope.list.ok ? examForSlot(asMapList(scope.list.map['items']), e.id) : null);
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.e});
  final MyExam e;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now().toUtc();
    final over = (e.end ?? e.start!).isBefore(now);
    final running = !over && !e.start!.isAfter(now);
    final accent = over ? c.textLight : (e.kind == 'midterm' ? c.primary : c.warning);
    return AppCard(
      onTap: e.teaching ? () => openTeacherSlotExam(context, e) : null,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Column(children: [
            Text(AppTime.time(e.start!), textAlign: TextAlign.center, style: AppType.bodyStrong(context).copyWith(color: accent)),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(AppTime.time(e.end ?? e.start!), textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(e.courseName, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppType.section(context).copyWith(color: over ? c.textMedium : c.textDark)),
              ),
              const SizedBox(width: AppSpace.xs),
              AppTag(myExamKindLabel(e.kind), accent),
            ]),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              if (running) AppTag(t('جارٍ الآن', 'On now'), c.success, icon: Icons.circle),
              if (e.invigilating) AppTag(t('أنت مراقب', 'You invigilate'), c.primaryDark, icon: Icons.visibility_rounded),
              if (e.teaching) AppTag(t('مقررك — اضغط لإنشاء الاختبار', 'Your course — tap to create the exam'), c.primary, icon: Icons.edit_note_rounded),
              if (over) AppTag(t('انتهى', 'Over'), c.textLight),
            ]),
            if (e.roomNames.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              _line(context, Icons.meeting_room_rounded,
                  e.invigilating && e.myRoomName != null
                      ? '${t('مكانك', 'Your room')}: ${e.myRoomName}${e.roomNames.length > 1 ? ' · ${t('كل الأماكن', 'all rooms')}: ${e.roomNames.join('، ')}' : ''}'
                      : e.roomNames.join('، ')),
            ],
            if (e.invigilatorNames.isNotEmpty)
              _line(context, Icons.badge_rounded, '${t('المراقبون', 'Invigilators')}: ${e.invigilatorNames.join('، ')}'),
            if (e.orgName.isNotEmpty) _line(context, Icons.apartment_rounded, e.orgName),
          ]),
        ),
      ]),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.xs, color: c.textLight),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.label(context).copyWith(color: c.textMedium))),
      ]),
    );
  }
}
