// lib/features/shared/course_profile/course_profile_actions.dart
//
// What staff DO from the course profile, in as few taps as possible:
//   CpStaffActions        one "Open attendance" button (the lesson happening now, else the picker — the existing
//                         code / classmate-relay / location window) + "Mark by hand", then the course's tools
//   showCpManualAttendance  tick who came to one session (same attendance rows as every check-in)
//   CpVersionsCard        the course's runs (terms): the current one + earlier ones, read-only
// The server decides every capability (CpCaps) and enforces it on each call.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../org/org_academic_pages.dart' show CourseArchiveScreen;
import '../../teacher/analysis/exam/teacher_exam_hub_screen.dart';
import '../attendance/attendance_course_entry.dart' show TeacherAttendanceCourseEntry;
import '../attendance/teacher_attendance_launcher.dart' show LauncherSession;
import 'course_profile_models.dart';
import 'course_profile_parts.dart' show openCourseStudio, orgParseUtcLocal;
import 'course_profile_screen.dart' show cpCall, cpErrorMessage, openCourseProfile;

const _base = '/api/v1/course-profile';

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: attendance first, then the course's tools
// ═════════════════════════════════════════════════════════════════════════════

class CpStaffActions extends StatelessWidget {
  const CpStaffActions({super.key, required this.profile, required this.onOpenTab, required this.onChanged, this.merged = false});
  final CourseProfile profile;

  /// On the course page itself (D-111): no "Content & settings" pill (that is this page).
  final bool merged;
  final ValueChanged<String> onOpenTab;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final canAttend = p.caps.anyAttend && !p.readOnly && !p.closed;
    final sessions = p.attendableSessions;
    final target = p.attendanceTarget;
    final tools = <Widget>[
      if (p.caps.anyManage && !p.readOnly && !merged)
        AppPill(
            icon: p.caps.courseSettings ? Icons.tune_rounded : Icons.edit_note_rounded,
            label: p.caps.courseSettings ? t('المحتوى والإعدادات', 'Content & settings') : t('رفع وتعديل المواد', 'Upload & edit material'),
            onTap: () async {
              await openCourseStudio(context, p.id);
              await onChanged();
            }),
      if (p.role == 'instructor' && !p.readOnly)          // the exam routes are the course teacher's
        AppPill(
            icon: Icons.quiz_rounded,
            label: t('الاختبارات', 'Exams'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TeacherExamHubScreen(courseId: p.id, courseTitle: p.name(AppConfig.lang == 'ar'))))),
      if (p.caps.announce && !p.readOnly)
        AppPill(icon: Icons.campaign_rounded, label: t('إعلان للطلاب', 'Announce'), onTap: () => onOpenTab('announcements')),
      if (p.caps.archiveCourse && p.isOrg)
        AppPill(
            icon: Icons.inventory_2_rounded,
            color: c.warning,
            label: t('إنهاء الفصل والأرشفة', 'End term & archive'),
            onTap: () async {
              final orgId = (p.course['org'] is Map ? (p.course['org'] as Map)['id'] : null) as num?;
              if (orgId == null) return;
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CourseArchiveScreen(orgId: orgId.toInt(), courseId: p.id, canManage: true)));
              await onChanged();
            }),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (canAttend) ...[
        // on the course page the spotlight already carries "Start attendance" (one entry per page)
        if (!merged)
          TeacherAttendanceCourseEntry(
          padding: EdgeInsets.zero,
          target: target == null ? null : LauncherSession(id: target.id, number: 0, name: target.name),
          sessions: [for (var i = 0; i < sessions.length; i++) LauncherSession(id: sessions[i].id, number: i + 1, name: sessions[i].name, date: sessions[i].scheduledAt)],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => showCpManualAttendance(context, p, session: target, onChanged: onChanged),
            icon: const Icon(Icons.fact_check_rounded, size: 18),
            label: Text(t('تسجيل الحضور يدوياً', 'Mark attendance by hand')),
          ),
        ),
      ],
      if (tools.isNotEmpty || p.role == 'ta')
        AppCard(
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ...tools,
            if (p.role == 'ta')
              AppBadgePill(
                  p.caps.manageLecture
                      ? t('مسموح لك بتعديل المحاضرات', 'You may edit lectures')
                      : t('صلاحيتك: السكاشن والمعامل', 'Your part: sections & labs'),
                  icon: Icons.badge_rounded),
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Manual attendance
// ═════════════════════════════════════════════════════════════════════════════

/// Sessions that can be marked by hand: started (or starting within the hour), newest first.
List<CpSession> cpMarkableSessions(CourseProfile p, {DateTime? now}) {
  final limit = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 1));
  return p.attendableSessions.where((s) => s.scheduledAt == null || !s.scheduledAt!.toUtc().isAfter(limit)).toList()
    ..sort((a, b) => (b.scheduledAt ?? DateTime(0)).compareTo(a.scheduledAt ?? DateTime(0)));
}

/// Opens the roster of [session] (or asks which session first) and lets staff tick who came.
Future<void> showCpManualAttendance(BuildContext context, CourseProfile p,
    {CpSession? session, int? sessionId, Future<void> Function()? onChanged}) async {
  var id = session?.id ?? sessionId;
  if (id == null) {
    final list = cpMarkableSessions(p);
    if (list.isEmpty) {
      appToast(t('لا جلسات بدأت بعد', 'No session has started yet'));
      return;
    }
    id = await showAppSheet<int>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(t('اختر الجلسة', 'Choose the session')),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final s in list)
                ListTile(
                  leading: Icon(s.track == 'section' ? Icons.science_rounded : Icons.co_present_rounded,
                      color: s.track == 'section' ? ctx.colors.purple : ctx.colors.primary),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(s.scheduledAt == null ? t('بدون موعد', 'No date') : AppTime.dateTime(s.scheduledAt!),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(ctx).pop(s.id),
                ),
            ]),
          ),
        ]));
  }
  if (id == null || !context.mounted) return;
  final changed = await showAppSheet<bool>(context, (_) => CpManualAttendanceSheet(courseId: p.id, sessionId: id!));
  if (changed == true && onChanged != null) await onChanged();
}

class CpManualAttendanceSheet extends StatefulWidget {
  const CpManualAttendanceSheet({super.key, required this.courseId, required this.sessionId, this.initial});
  final int courseId, sessionId;

  /// Preloaded roster (tests).
  final Map<String, dynamic>? initial;

  @override
  State<CpManualAttendanceSheet> createState() => _CpManualAttendanceSheetState();
}

class _CpManualAttendanceSheetState extends State<CpManualAttendanceSheet> {
  Map<String, dynamic>? _session;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  String _q = '';
  bool _changed = false;
  final Set<int> _busy = {};

  String get _path => '$_base/${widget.courseId}/sessions/${widget.sessionId}/attendance';

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _take(widget.initial!);
    } else {
      _load();
    }
  }

  void _take(Map<String, dynamic> r) {
    _session = r['session'] is Map ? Map<String, dynamic>.from(r['session'] as Map) : {};
    _rows = (r['students'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get(_path);
      if (mounted) setState(() => _take(Map<String, dynamic>.from(r as Map)));
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  int _uid(Map<String, dynamic> row) => ((row['user'] as Map?)?['id'] as num?)?.toInt() ?? 0;

  Future<void> _set(Map<String, dynamic> row, bool present) async {
    final uid = _uid(row);
    setState(() => _busy.add(uid));
    final r = await cpCall(() => ApiClient().put('$_path/$uid', body: {'present': present}));
    if (!mounted) return;
    setState(() {
      _busy.remove(uid);
      if (r != null) {
        row['present'] = present;
        row['manual'] = present;
        _changed = true;
      }
    });
  }

  Future<void> _allPresent() async {
    for (final row in [...?_rows].where((r) => r['present'] != true)) {
      await _set(row, true);
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    final present = rows?.where((r) => r['present'] == true).length ?? 0;
    final shown = rows == null
        ? const <Map<String, dynamic>>[]
        : rows.where((r) => _q.isEmpty || '${(r['user'] as Map?)?['name'] ?? ''}'.toLowerCase().contains(_q)).toList();
    final when = orgParseUtcLocal(_session?['scheduled_at']);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('الحضور اليدوي', 'Attendance by hand'),
            trailing: rows == null ? null : AppBadgePill('$present / ${rows.length}', color: c.success)),
        if (_session != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                [('${_session!['name'] ?? ''}'), if (when != null) AppTime.dateTime(when)].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
          ),
        if (_error != null)
          AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: () {
            setState(() => _error = null);
            _load();
          })
        else if (rows == null)
          const SizedBox(height: 220, child: AppListSkeleton(items: 4))
        else if (rows.isEmpty)
          AppEmpty(icon: Icons.people_outline_rounded, title: t('لا طلاب مسجلين', 'No students enrolled'))
        else ...[
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: t('ابحث عن طالب', 'Search a student'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: present == rows.length ? null : _allPresent, child: Text(t('الكل حاضر', 'All present'))),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final r in shown) _row(context, r),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        AppPrimaryButton(icon: Icons.check_rounded, label: t('تم', 'Done'), onPressed: () => Navigator.of(context).pop(_changed)),
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final u = r['user'] is Map ? Map<String, dynamic>.from(r['user'] as Map) : const <String, dynamic>{};
    final on = r['present'] == true;
    final busy = _busy.contains(_uid(r));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: busy ? null : () => _set(r, !on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          AppAvatar(name: '${u['name'] ?? ''}', url: u['image_url']?.toString(), size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              Text(on ? (r['manual'] == true ? t('حاضر (يدوي)', 'Present (by hand)') : t('حاضر', 'Present')) : t('غائب', 'Absent'),
                  style: appText(11.5, c: on ? c.success : c.textLight)),
            ]),
          ),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: on ? c.success : c.textLight),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Versions (runs / terms)
// ═════════════════════════════════════════════════════════════════════════════

class CpVersionsCard extends StatelessWidget {
  const CpVersionsCard({super.key, required this.profile});
  final CourseProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('نسخ المقرر', 'Course versions'),
            subtitle: t('كل فصل نسخة — افتح نسخة سابقة لمراجعة محتواها وحضورها', 'One version per term — open an earlier one to review its material and attendance')),
        const SizedBox(height: 8),
        if (p.versions.isEmpty)
          Text(t('لا نسخ بعد', 'No versions yet'), style: appText(13, c: c.textLight))
        else
          for (final v in p.versions)
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: v.current ? null : () => openCourseProfile(context, p.id, runId: v.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(children: [
                    Icon(v.current ? Icons.play_circle_rounded : Icons.history_rounded, color: v.current ? c.success : c.textMedium),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v.term.isEmpty ? '#${v.id}' : cpTermLabel(v.term, ar), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                        Text(
                            v.archived
                                ? t('مؤرشفة · ${v.passed} / ${v.students} ناجح', 'Archived · ${v.passed} / ${v.students} passed')
                                : (v.status == 'finished' ? t('انتهت', 'Finished') : t('جارية', 'Running')),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textLight)),
                      ]),
                    ),
                    if (v.current)
                      AppBadgePill(t('الحالية', 'Current'), color: c.success)
                    else
                      Icon(Icons.chevron_right_rounded, color: c.textLight),
                  ]),
                ),
              ),
            ),
      ]),
    );
  }
}
