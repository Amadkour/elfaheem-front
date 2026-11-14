// lib/features/courses/course_profile/course_profile_parts.dart
//
// The tabs of the course profile: overview · lectures · sections/labs · attendance · certificates · team · archive.
// The overview is per role: staff get one "Open attendance" button and their tools (course_profile_actions.dart),
// students a review page (check-in when attendance is open · progress · attendance · grade · next session).
// Material opens with the app's secured player (VideoPlayerScreen calls POST …/play itself); uploads and edits stay in
// the existing course studio (TeacherSessionsScreen), opened from here.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse;
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart' show TeacherCourseScreenProvider;
import 'package:flutter_education_app/features/student/analysis/student_course_analytics_screen.dart';
import 'package:flutter_education_app/features/shared/attendance/attendance_course_entry.dart' show AttendanceCourseEntry;
import 'package:flutter_education_app/features/shared/attendance/attendance_widgets.dart' show showTeacherAttendanceSheet;
import 'package:flutter_education_app/features/sessions/material/components/session_material_grid.dart' show MaterialImageViewerDialog;
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/video/video_player_screen.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_actions.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_announcements.dart' show CpAnnouncementCard;
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show cpCall, cpErrorMessage;

const _base = '/api/v1/course-profile';
String _pct(dynamic v) => v is num ? '${v.round()}%' : '—';
double? _num(dynamic v) => v is num ? v.toDouble() : null;
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _when(DateTime? d) => d == null ? t('بدون موعد', 'No date') : AppTime.dateTime(d);

/// Opens the existing course studio (sessions · material upload / edit · attendance) for staff.
Future<void> openCourseStudio(BuildContext context, int courseId) async {
  final r = await cpCall(() => ApiClient().get('/api/v1/courses/$courseId'));
  if (r is! Map || !context.mounted) return;
  final course = TeacherCourse.fromJson(Map<String, dynamic>.from(r));
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => TeacherCourseScreenProvider(initialCourse: course),
      child: deferredTeacherSessionsScreen(),
    ),
  ));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

class CpOverviewTab extends StatelessWidget {
  const CpOverviewTab({super.key, required this.profile, required this.onOpenTab, required this.onChanged, this.withRail = false,
      this.merged = false});
  final CourseProfile profile;
  final ValueChanged<String> onOpenTab;
  final Future<void> Function() onChanged;

  /// Inside the one course page (D-111): its hero, About tab and spotlight already show the description, the
  /// check-in, the next session and the announcements; the studio is the page itself.
  final bool merged;

  /// The side rail (wide screens) already shows the next session and the announcements.
  final bool withRail;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final a = p.analytics;
    final next = _map(a['next_session']);
    final ar = AppConfig.lang == 'ar';
    final desc = '${(ar ? p.course['description_ar'] : p.course['description_en']) ?? p.course['description_ar'] ?? ''}'.trim();
    final children = <Widget>[];

    if (p.isStudent && !p.closed && !merged) {
      // shown only while the teacher has attendance open (online, or offline through a nearby classmate)
      children.add(AttendanceCourseEntry(courseId: p.id, title: p.name(ar)));
    }

    if (p.isStudent && p.caps.viewMaterial) {
      final pr = p.progress;
      final cont = cpContinue(p);
      final ms = cpMaterialStats(p);
      children.add(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionTitle(t('تقدّمك', 'Your progress'),
              subtitle: t('${ms.done} من ${ms.materials} مادة مكتملة', '${ms.done} of ${ms.materials} items done')),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, alignment: WrapAlignment.center, children: [
            AppRing(value: _num(pr['overall']) ?? 0, label: t('الإجمالي', 'Overall')),
            if (pr['lecture'] != null) AppRing(value: _num(pr['lecture']), label: t('المحاضرات', 'Lectures')),
            if (pr['section'] != null) AppRing(value: _num(pr['section']), label: t('السكاشن', 'Sections')),
          ]),
          if (cont != null && !p.readOnly) ...[
            const SizedBox(height: AppSpace.md),
            AppButton.primary(expand: true, 
              icon: Icons.play_arrow_rounded,
              label: t('تابع: ${cont.name}', 'Continue: ${cont.name}'),
              onPressed: () => onOpenTab(cont.track),
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.ghost(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => StudentCourseAnalyticsScreen(courseId: p.id, courseTitle: p.name(ar)))),
              icon: Icons.insights_rounded,
              size: AppButtonSize.sm,
              label: t('تحليلاتي في المقرر', 'My course analytics'),
            ),
          ),
        ]),
      ));
    }
    if (p.isStudent) {
      if ((a['expected'] ?? 0) is num && (a['expected'] ?? 0) > 0) {
        final absence = _num(a['absence_pct']) ?? 0;
        children.add(AppCard(
          onTap: p.readOnly ? null : () => onOpenTab('attendance'),
          child: Row(children: [
            Icon(Icons.how_to_reg_rounded, color: appScoreColor(context, 100 - absence), size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('حضرت ${a['attended']} من ${a['expected']}', 'Attended ${a['attended']} of ${a['expected']}'),
                    style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xs),
                AppProgressBar(value: 100 - absence, color: appScoreColor(context, 100 - absence)),
              ]),
            ),
            const SizedBox(width: AppSpace.sm),
            AppBadgePill(t('غياب ${_pct(absence)}', 'Absent ${_pct(absence)}'), color: appScoreColor(context, 100 - absence)),
          ]),
        ));
      }
      final g = p.grade;
      if (g != null) children.add(_GradeCard(grade: g));
    }

    if (p.isStaff) {
      if (!p.readOnly) children.add(CpStaffActions(profile: p, onOpenTab: onOpenTab, onChanged: onChanged, merged: merged));
      children.add(AppGrid(minTile: 150, children: [
        AppStatTile(icon: Icons.people_alt_rounded, label: t('الطلاب', 'Students'), value: a['students'] ?? 0),
        AppStatTile(icon: Icons.trending_up_rounded, label: t('متوسط التقدم', 'Avg progress'), value: _pct(a['avg_progress'])),
        AppStatTile(icon: Icons.verified_rounded, label: t('أكملوا', 'Completed'), value: a['completed'] ?? 0, color: c.success),
        AppStatTile(
            icon: Icons.how_to_reg_rounded,
            label: t('نسبة الحضور', 'Attendance'),
            value: _pct(a['attendance_rate']),
            onTap: p.caps.viewAttendance ? () => onOpenTab('attendance') : null),
        AppStatTile(
            icon: Icons.warning_amber_rounded,
            label: t('معرّضون للحرمان', 'At risk'),
            value: a['at_risk'] ?? 0,
            color: c.warning,
            onTap: p.caps.viewAttendance ? () => onOpenTab('attendance') : null),
        AppStatTile(
            icon: Icons.event_busy_rounded,
            label: t('جلسات لم تُعقد', 'Sessions not held'),
            value: a['missed_by_staff'] ?? 0,
            color: c.danger,
            onTap: p.caps.viewAttendance ? () => onOpenTab('attendance') : null),
      ]));
    }

    if (!withRail && !p.pastVersion && !merged) {
      if (next.isNotEmpty) children.add(_NextSessionCard(next: next));
      if (p.announcements.isNotEmpty) children.add(_AnnouncementsPreview(profile: p, onOpenTab: onOpenTab));
    }

    final term = _map(p.course['term']);
    if (!merged) children.add(AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppSectionTitle(t('عن المقرر', 'About the course')),
        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(desc, style: AppType.body(context).copyWith(height: 1.6)),
          ),
        if (p.instructor != null) AppInfoRow(Icons.person_rounded, '${t('أستاذ المقرر', 'Instructor')}: ${p.instructor!['name']}'),
        if (p.course['credit_hours'] != null) AppInfoRow(Icons.timer_outlined, '${t('الساعات المعتمدة', 'Credit hours')}: ${p.course['credit_hours']}'),
        if (term.isNotEmpty)
          AppInfoRow(Icons.date_range_rounded, '${t('الفصل', 'Term')}: ${_termRange(term)}'),
      ]),
    ));

    return Column(children: [for (final w in children) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: w)]);
  }
}

/// The student's approved grade for this run (registrar): the letter set in the editorial face on a peach block
/// (a learning result), the percentage rolling in as the key figure.
class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.grade});
  final Map<String, dynamic> grade;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = _num(grade['percent']);
    final letter = '${grade['letter'] ?? ''}'.trim();
    return AppBlock(
      tone: AppBlockTone.peach,
      padding: AppSpace.card,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(children: [
          Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll),
            child: Text(letter.isEmpty ? '—' : letter, style: AppType.headline(context).copyWith(color: b.ink)),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('درجتك في المقرر', 'Your grade'), style: AppType.meta(context).copyWith(color: b.muted)),
              pct == null
                  ? Text('—', style: AppType.figureLarge(context).copyWith(color: b.ink))
                  : AppOdometer(_pct(pct), memoryKey: 'cp.grade', style: AppType.figureLarge(context).copyWith(color: b.ink)),
            ]),
          ),
          if (grade['denied'] == true) AppBadgePill(t('محروم', 'Denied'), color: c.danger),
        ]);
      }),
    );
  }
}

String _termRange(Map<String, dynamic> term) {
  final a = DateTime.tryParse('${term['start_date'] ?? ''}'), b = DateTime.tryParse('${term['end_date'] ?? ''}');
  return [
    cpTermLabel(term, AppConfig.lang == 'ar'),
    if (a != null && b != null) '${AppTime.date(a)} → ${AppTime.date(b)}',
  ].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// The next session: a sky block (schedule blocks are sky, system.md §5) with the session's kind on a paper plate,
/// its name in the editorial face and the time in the block's ink.
class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.next});
  final Map<String, dynamic> next;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final section = next['track'] == 'section';
    return AppBlock(
      tone: AppBlockTone.sky,
      padding: AppSpace.card,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.controlAll),
            child: Icon(section ? Icons.science_rounded : Icons.co_present_rounded, color: b.ink, size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('الجلسة القادمة', 'Next session'), style: AppType.meta(context).copyWith(color: b.muted)),
              Text('${next['name']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppType.section(context).copyWith(color: b.ink)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(_when(orgParseUtcLocal(next['scheduled_at'])), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: b.ink, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _AnnouncementsPreview extends StatelessWidget {
  const _AnnouncementsPreview({required this.profile, required this.onOpenTab});
  final CourseProfile profile;
  final ValueChanged<String> onOpenTab;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('آخر الإعلانات', 'Latest announcements'),
            trailing: AppButton.ghost(
                label: t('الكل', 'All'), size: AppButtonSize.sm, onPressed: () => onOpenTab('announcements'))),
        const SizedBox(height: AppSpace.xs),
        for (final a in profile.announcements.take(2))
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: CpAnnouncementCard(item: a, compact: true)),
      ]);
}

/// Wide screens: what stays useful whatever tab is open — next session, announcements, the teaching team.
class CpSideRail extends StatelessWidget {
  const CpSideRail({super.key, required this.profile, required this.onOpenTab});
  final CourseProfile profile;
  final ValueChanged<String> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final next = _map(p.analytics['next_session']);
    final ins = p.instructor;
    Widget person(String name, dynamic url, String role) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(children: [
            AppAvatar(name: name, url: url?.toString(), size: AppIconSize.xl),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                Text(role, style: AppType.meta(context)),
              ]),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (next.isNotEmpty && !p.pastVersion) ...[_NextSessionCard(next: next), const SizedBox(height: AppSpace.md)],
      if (p.announcements.isNotEmpty) ...[
        _AnnouncementsPreview(profile: p, onOpenTab: onOpenTab),
        const SizedBox(height: AppSpace.xs),
      ] else if (p.caps.announce && !p.readOnly && !p.pastVersion) ...[
        AppCard(
          onTap: () => onOpenTab('announcements'),
          child: Row(children: [
            Icon(Icons.campaign_rounded, color: c.textMedium, size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(t('انشر إعلاناً لطلابك', 'Post an announcement'), style: AppType.bodyStrong(context))),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (ins != null || p.assistants.isNotEmpty)
        AppCard(
          onTap: p.caps.manageStaff || p.role == 'ta' ? () => onOpenTab('team') : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSectionTitle(t('فريق التدريس', 'Teaching team')),
            const SizedBox(height: AppSpace.xs),
            if (ins != null) person('${ins['name'] ?? ''}', ins['image_url'], t('أستاذ المقرر', 'Instructor')),
            for (final a in p.assistants.take(4))
              person('${_map(a['user'])['name'] ?? ''}', _map(a['user'])['image_url'], t('معيد', 'Assistant')),
            if (p.assistants.length > 4)
              Text(t('+${p.assistants.length - 4} آخرين', '+${p.assistants.length - 4} more'),
                  style: AppType.meta(context)),
          ]),
        ),
    ]);
  }
}

DateTime? orgParseUtcLocal(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Lectures / Sections & labs
// ═════════════════════════════════════════════════════════════════════════════

class CpTrackTab extends StatefulWidget {
  const CpTrackTab({super.key, required this.profile, required this.track, required this.onChanged});
  final CourseProfile profile;
  final String track;
  final Future<void> Function() onChanged;

  @override
  State<CpTrackTab> createState() => _CpTrackTabState();
}

class _CpTrackTabState extends State<CpTrackTab> {
  bool _reorder = false;
  late List<CpSession> _items = widget.profile.track(widget.track);
  int? _open;

  @override
  void didUpdateWidget(covariant CpTrackTab old) {
    super.didUpdateWidget(old);
    _items = widget.profile.track(widget.track);
  }

  Future<void> _saveOrder() async {
    final r = await cpCall(
        () => ApiClient().put('$_base/${widget.profile.id}/reorder',
            body: {'track': widget.track, 'session_ids': [for (final s in _items) s.id]}),
        ok: t('تم حفظ الترتيب', 'Order saved'));
    if (r != null) {
      setState(() => _reorder = false);
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final canManage = p.caps.manage(widget.track) && !p.readOnly;
    final c = context.colors;
    final header = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AppBadgePill(t('${_items.length} جلسة', '${_items.length} sessions'),
          icon: widget.track == 'lecture' ? Icons.co_present_rounded : Icons.science_rounded,
          color: widget.track == 'lecture' ? c.primary : c.purple),
      if (canManage && _items.length > 1)
        AppPill(
            icon: _reorder ? Icons.check_rounded : Icons.swap_vert_rounded,
            label: _reorder ? t('حفظ الترتيب', 'Save order') : t('إعادة الترتيب', 'Reorder'),
            onTap: _reorder ? _saveOrder : () => setState(() => _reorder = true)),
      if (canManage)
        AppPill(
            icon: Icons.upload_file_rounded,
            label: t('رفع وتعديل المواد', 'Upload & edit material'),
            onTap: () async {
              await openCourseStudio(context, p.id);
              await widget.onChanged();
            }),
    ]);
    if (_items.isEmpty) {
      return Column(children: [
        header,
        const SizedBox(height: AppSpace.sm),
        AppEmpty(
          icon: widget.track == 'lecture' ? Icons.co_present_rounded : Icons.science_rounded,
          title: widget.track == 'lecture' ? t('لا محاضرات بعد', 'No lectures yet') : t('لا سكاشن أو معامل بعد', 'No sections or labs yet'),
          message: p.isOrg
              ? t('تظهر الجلسات تلقائياً عند نشر الجدول الدراسي', 'Sessions appear automatically when the timetable is published')
              : null,
        ),
      ]);
    }
    if (_reorder) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: AppSpace.sm),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: true,
          itemCount: _items.length,
          onReorderItem: (a, b) => setState(() {
            final s = _items.removeAt(a);
            _items.insert(b, s);
          }),
          itemBuilder: (_, i) => Padding(
            key: ValueKey(_items[i].id),
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              child: Row(children: [
                Icon(Icons.drag_indicator_rounded, color: c.textLight),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(_items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700))),
              ]),
            ),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: AppSpace.sm),
      for (var i = 0; i < _items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: _SessionCard(
            profile: p,
            session: _items[i],
            number: i + 1,
            open: _open == _items[i].id,
            onToggle: () => setState(() => _open = _open == _items[i].id ? null : _items[i].id),
            onChanged: widget.onChanged,
          ),
        ),
    ]);
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.profile, required this.session, required this.number, required this.open,
      required this.onToggle, required this.onChanged});
  final CourseProfile profile;
  final CpSession session;
  final int number;
  final bool open;
  final VoidCallback onToggle;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = session;
    final p = profile;
    final tone = s.track == 'lecture' ? c.primary : c.purple;
    final canAttend = (s.track == 'lecture' ? p.caps.attendLecture : p.caps.attendSection);
    final status = <Widget>[
      if (s.liveNow && p.caps.live) AppTag(t('مباشر الآن', 'Live now'), c.danger, icon: Icons.sensors_rounded),
      if (s.groupNo != null) AppTag(t('مجموعة ${s.groupNo}', 'Group ${s.groupNo}'), c.textMedium),
      if (s.done == true) AppTag(t('مكتملة', 'Done'), c.success, icon: Icons.check_circle_rounded),
      if (s.attended == true) AppTag(t('حضرت', 'Attended'), c.success, icon: Icons.how_to_reg_rounded),
      if (s.upcoming) AppTag(t('قادمة', 'Upcoming'), c.accent),
      if (s.materialsCount > 0) AppTag(t('${s.materialsCount} مادة', '${s.materialsCount} items'), tone, icon: Icons.attach_file_rounded),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(c.radiusLarge - 4),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text('$number', style: appText(15, w: FontWeight.w800, c: tone)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 2),
                  Text(_when(s.scheduledAt) + (s.durationMinutes != null ? ' · ${s.durationMinutes} ${t('د', 'min')}' : ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Wrap(spacing: 6, runSpacing: 6, children: status),
                  ],
                ]),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.textLight),
            ]),
          ),
        ),
        if (open) ...[
          Divider(height: 1, color: c.divider),
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if ((s.description ?? '').trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(s.description!, style: appText(13, c: c.textMedium))),
              if (!p.caps.viewMaterial)
                AppBanner(icon: Icons.lock_rounded, text: t('المحتوى مقفل', 'Material is locked'))
              else if (s.materials.isEmpty)
                Text(t('لا مواد في هذه الجلسة بعد', 'No material in this session yet'), style: appText(13, c: c.textLight))
              else
                for (final m in s.materials) _MaterialTile(material: m, siblings: s.materials, profile: p),
              if (canAttend && !p.closed && !p.readOnly) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AppPill(
                      icon: Icons.qr_code_2_rounded,
                      label: t('فتح الحضور', 'Open attendance'),
                      onTap: () async {
                        await showTeacherAttendanceSheet(context, s.id, title: s.name);
                        await onChanged();
                      }),
                  if (!s.upcoming || s.liveNow)
                    AppPill(
                        icon: Icons.fact_check_rounded,
                        label: t('يدوياً', 'By hand'),
                        onTap: () => showCpManualAttendance(context, p, session: s, onChanged: onChanged)),
                ]),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({required this.material, required this.siblings, required this.profile});
  final Map<String, dynamic> material;
  final List<Map<String, dynamic>> siblings;
  final CourseProfile profile;

  IconData get _icon => switch ('${material['type']}') {
        'video' || 'recorded' || 'recording' => Icons.play_circle_fill_rounded,
        'pdf' => Icons.picture_as_pdf_rounded,
        'image' => Icons.image_rounded,
        'link' => Icons.link_rounded,
        _ => Icons.description_rounded,
      };

  Future<void> _open(BuildContext context) async {
    final m = SessionMaterialModel.fromJson(material);
    if (m.type == SessionMaterialType.video || m.type == SessionMaterialType.recorded) {
      final list = <SessionMaterialModel>[];
      for (final raw in siblings) {
        try {
          list.add(SessionMaterialModel.fromJson(raw));
        } catch (_) {}
      }
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(material: m, playlist: list)));
      return;
    }
    final url = (material['url'] ?? '').toString();
    if (url.isEmpty) {
      appToast(t('المادة غير متاحة', 'Not available'), error: true);
      return;
    }
    if (m.type == SessionMaterialType.image) {
      await showDialog<void>(context: context, builder: (_) => MaterialImageViewerDialog(url: url, title: m.name));
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    if (profile.isStudent && !profile.readOnly && material['completed'] != true) {
      try {
        await ApiClient().post('/api/v1/sessions/${m.sessionId}/materials/${m.id}/complete');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = material['completed'] == true;
    final dur = material['duration_seconds'];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Material(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
            child: Row(children: [
              Icon(_icon, color: c.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('${material['name']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
              ),
              if (dur is num && dur > 0) ...[
                const SizedBox(width: AppSpace.xs),
                Text('${(dur ~/ 60)}:${(dur % 60).toInt().toString().padLeft(2, '0')}', style: appText(12, c: c.textLight)),
              ],
              if (done) ...[const SizedBox(width: AppSpace.xs), Icon(Icons.check_circle_rounded, size: 18, color: c.success)],
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Attendance
// ═════════════════════════════════════════════════════════════════════════════

class CpAttendanceTab extends StatefulWidget {
  const CpAttendanceTab({super.key, required this.profile, this.initial, this.onChanged});
  final CourseProfile profile;
  final Map<String, dynamic>? initial;

  /// After marking by hand (reloads the profile's numbers).
  final Future<void> Function()? onChanged;

  @override
  State<CpAttendanceTab> createState() => _CpAttendanceTabState();
}

class _CpAttendanceTabState extends State<CpAttendanceTab> {
  CpAttendance? _a;
  String? _error;
  String _view = 'sessions';
  String _track = 'all';

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _a = CpAttendance(widget.initial!);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final p = widget.profile;
      final r = await ApiClient().get('$_base/${p.id}/attendance',
          queryParams: p.pastVersion && p.runId != null ? {'run_id': p.runId} : null);
      if (mounted) setState(() => _a = CpAttendance(Map<String, dynamic>.from(r as Map)));
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    }
  }

  Future<void> _afterMark() async {
    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _export() async {
    final a = _a!;
    await showAppExportSheet(
      context,
      bilingualExport(() => AppTableExport(
        id: 'course_profile.attendance',
        title: t('الحضور', 'Attendance'),
        subtitle: widget.profile.name(AppConfig.lang == 'ar'),
        columns: [
          AppExportColumn('name', t('الطالب', 'Student'), locked: true),
          AppExportColumn('attended', t('حضر', 'Attended'), type: AppColType.integer),
          AppExportColumn('expected', t('المطلوب', 'Expected'), type: AppColType.integer),
          AppExportColumn('absent', t('غاب', 'Absent'), type: AppColType.integer),
          AppExportColumn('absence_pct', t('نسبة الغياب %', 'Absence %'), type: AppColType.number),
        ],
        rows: [
          for (final r in a.byRisk)
            {
              'name': _map(r['user'])['name'] ?? '',
              'attended': r['attended'],
              'expected': r['expected'],
              'absent': r['absent'],
              'absence_pct': r['absence_pct'],
            }
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final c = context.colors;
    if (a == null) {
      return _error != null
          ? AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const SizedBox(height: 320, child: AppListSkeleton(items: 4));
    }
    final p = widget.profile;
    final staff = p.isStaff;
    final sessions = a.filtered(_track);
    final head = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (staff) ...[
        AppChoiceChip(label: t('الجلسات', 'Sessions'), selected: _view == 'sessions', onTap: () => setState(() => _view = 'sessions')),
        AppChoiceChip(label: t('الطلاب', 'Students'), selected: _view == 'students', onTap: () => setState(() => _view = 'students')),
      ],
      if (_view == 'sessions' && p.hasSections) ...[
        for (final k in const ['all', 'lecture', 'section'])
          AppChoiceChip(
              label: switch (k) { 'lecture' => t('محاضرات', 'Lectures'), 'section' => t('سكاشن', 'Sections'), _ => t('الكل', 'All') },
              selected: _track == k,
              onTap: () => setState(() => _track = k)),
      ],
      if (staff && a.students.isNotEmpty) AppPill(icon: Icons.ios_share_rounded, label: t('تصدير', 'Export'), onTap: _export),
      if (staff && p.caps.anyAttend && !p.readOnly && !p.closed)
        AppPill(
            icon: Icons.fact_check_rounded,
            label: t('تسجيل يدوي', 'Mark by hand'),
            onTap: () => showCpManualAttendance(context, p, onChanged: _afterMark)),
    ]);
    final summary = Wrap(spacing: 8, runSpacing: 8, children: [
      AppStatChip(icon: Icons.event_available_rounded, value: '${a.held}', label: t('عُقدت', 'Held'), color: c.success),
      if (staff)
        AppStatChip(icon: Icons.event_busy_rounded, value: '${a.missedByStaff}', label: t('لم تُعقد', 'Not held'), color: c.danger),
      if (!staff && a.students.isNotEmpty)
        AppStatChip(
            icon: Icons.person_off_rounded,
            value: _pct(a.students.first['absence_pct']),
            label: t('غيابك', 'Your absence'),
            color: appScoreColor(context, 100 - (_num(a.students.first['absence_pct']) ?? 0))),
    ]);
    final body = <Widget>[];
    if (_view == 'students' && staff) {
      if (a.students.isEmpty) {
        body.add(AppEmpty(icon: Icons.people_outline_rounded, title: t('لا طلاب مسجلين', 'No students enrolled')));
      }
      for (final r in a.byRisk) {
        final u = _map(r['user']);
        final abs = _num(r['absence_pct']) ?? 0;
        body.add(AppCard(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            AppAvatar(name: '${u['name'] ?? ''}', url: u['image_url']?.toString(), size: 36),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                const SizedBox(height: AppSpace.xxs),
                AppProgressBar(value: 100 - abs, color: appScoreColor(context, 100 - abs)),
              ]),
            ),
            const SizedBox(width: AppSpace.sm),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${r['attended']}/${r['expected']}', style: appText(13, w: FontWeight.w800, c: c.textDark)),
              Text(t('غياب ${_pct(abs)}', 'absent ${_pct(abs)}'), style: appText(11.5, c: appScoreColor(context, 100 - abs))),
            ]),
          ]),
        ));
      }
    } else {
      if (sessions.isEmpty) {
        body.add(AppEmpty(icon: Icons.event_note_rounded, title: t('لا جلسات سابقة بعد', 'No past sessions yet')));
      }
      for (final s in sessions.reversed) {
        final held = s['held'] == true;
        final missed = s['missed_by_staff'] == true;
        final me = s['me']?.toString();
        final exp = (s['expected'] as num?)?.toInt() ?? 0;
        final pres = (s['present'] as num?)?.toInt() ?? 0;
        final mark = staff && p.caps.attend('${s['track']}') && !p.readOnly && !p.closed;
        body.add(AppCard(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          onTap: mark
              ? () => showCpManualAttendance(context, p, sessionId: (s['id'] as num?)?.toInt(), onChanged: _afterMark)
              : null,
          child: Row(children: [
            Icon(s['track'] == 'section' ? Icons.science_rounded : Icons.co_present_rounded,
                color: s['track'] == 'section' ? c.purple : c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                Text(_when(orgParseUtcLocal(s['scheduled_at'])), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: appText(12, c: c.textLight)),
                if (staff && held) ...[
                  const SizedBox(height: AppSpace.xs),
                  AppProgressBar(value: exp == 0 ? 0 : 100.0 * pres / exp, color: appScoreColor(context, exp == 0 ? 0 : 100.0 * pres / exp)),
                ],
                if (staff && missed && s['staff'] is Map)
                  Text(t('المسؤول: ${(s['staff'] as Map)['name']}', 'Assigned: ${(s['staff'] as Map)['name']}'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            if (me != null)
              AppBadgePill(
                  switch (me) { 'present' => t('حاضر', 'Present'), 'absent' => t('غائب', 'Absent'), _ => t('لم تُعقد', 'Not held') },
                  color: switch (me) { 'present' => c.success, 'absent' => c.danger, _ => c.textLight })
            else if (missed)
              AppBadgePill(t('لم تُعقد', 'Not held'), color: c.danger, icon: Icons.event_busy_rounded)
            else
              Text('$pres/$exp', style: appText(13, w: FontWeight.w800, c: c.textDark)),
          ]),
        ));
      }
    }
    return AppRefresh(
      onRefresh: _load,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        const SizedBox(height: AppSpace.sm),
        summary,
        const SizedBox(height: AppSpace.sm),
        ...body,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Certificates
// ═════════════════════════════════════════════════════════════════════════════

class CpCertificatesTab extends StatelessWidget {
  const CpCertificatesTab({super.key, required this.profile, required this.onChanged});
  final CourseProfile profile;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p.certificates.isEmpty) {
      return AppEmpty(
        icon: Icons.workspace_premium_outlined,
        title: t('لا شهادات لهذا المقرر', 'No certificates for this course'),
        message: p.caps.manageCertificates
            ? t('أنشئ شهادة من إعدادات المقرر ثم حدّد هنا جزءها وطريقة إرسالها',
                'Create a certificate in the course settings, then choose its part and sending here')
            : null,
      );
    }
    return Column(children: [
      for (final cert in p.certificates)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: p.caps.manageCertificates
              ? _StaffCertificate(profile: p, cert: cert, onChanged: onChanged)
              : _StudentCertificate(cert: cert),
        ),
    ]);
  }
}

class _StudentCertificate extends StatelessWidget {
  const _StudentCertificate({required this.cert});
  final Map<String, dynamic> cert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final issued = cert['issued'] == true;
    final scope = cpScopeLabel('${cert['scope']}');
    final prog = _num(cert['progress']) ?? 0;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.workspace_premium_rounded, color: issued ? c.accent : c.textLight, size: 30),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${cert['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.textDark)),
              Text(t('عن: ${scope.$1}', 'For: ${scope.$2}'), style: appText(12, c: c.textLight)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        if (issued)
          Wrap(spacing: 8, runSpacing: 8, children: [
            if ((cert['url'] ?? '').toString().isNotEmpty)
              AppPill(icon: Icons.download_rounded, label: t('تحميل (English)', 'Download (English)'),
                  onTap: () => launchUrl(Uri.parse('${cert['url']}'), mode: LaunchMode.externalApplication)),
            if ((cert['url_ar'] ?? '').toString().isNotEmpty)
              AppPill(icon: Icons.download_rounded, label: t('تحميل (عربي)', 'Download (Arabic)'),
                  onTap: () => launchUrl(Uri.parse('${cert['url_ar']}'), mode: LaunchMode.externalApplication)),
          ])
        else ...[
          AppProgressBar(value: prog, color: appScoreColor(context, prog)),
          const SizedBox(height: AppSpace.xs),
          Text(
              cert['auto_send'] == true
                  ? t('تُرسل تلقائياً عند إكمال ${scope.$1} (${_pct(prog)} الآن)', 'Sent automatically at 100% of ${scope.$2} (${_pct(prog)} now)')
                  : t('يرسلها الأستاذ (${_pct(prog)} الآن)', 'Sent by the instructor (${_pct(prog)} now)'),
              style: appText(12.5, c: c.textMedium)),
        ],
      ]),
    );
  }
}

class _StaffCertificate extends StatelessWidget {
  const _StaffCertificate({required this.profile, required this.cert, required this.onChanged});
  final CourseProfile profile;
  final Map<String, dynamic> cert;
  final Future<void> Function() onChanged;

  Future<void> _rule(String scope, bool auto) async {
    final r = await cpCall(() => ApiClient().put('$_base/${profile.id}/certificates/${cert['id']}',
        body: {'scope': scope, 'auto_send': auto}), ok: t('تم الحفظ', 'Saved'));
    if (r != null) await onChanged();
  }

  Future<void> _send(BuildContext context, {List<int>? ids, bool completers = false}) async {
    final r = await cpCall(() => ApiClient().post('$_base/${profile.id}/certificates/${cert['id']}/send',
        body: {'student_ids': ids, 'completers_only': completers}));
    if (r is Map) {
      final sent = (r['sent'] as List?)?.length ?? 0, skipped = (r['skipped'] as List?)?.length ?? 0;
      appToast(t('أُرسلت $sent · تُخطّي $skipped', 'Sent $sent · skipped $skipped'));
      await onChanged();
    }
  }

  Future<void> _pick(BuildContext context) async {
    final r = await cpCall(() => ApiClient().get('$_base/${profile.id}/students'));
    if (r is! Map || !context.mounted) return;
    final rows = (r['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final scope = '${cert['scope']}';
    final chosen = <int>{};
    final ids = await showAppSheet<List<int>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(t('اختر الطلاب', 'Choose students')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final row in rows)
                  Builder(builder: (_) {
                    final u = _map(row['user']);
                    final id = (u['id'] as num).toInt();
                    final has = (row['certificates'] as List? ?? []).contains(cert['id']);
                    final pr = _map(row['progress']);
                    final v = scope == 'both'
                        ? [pr['lecture'], pr['section']].whereType<num>().fold<double?>(null, (m, x) => m == null || x < m ? x.toDouble() : m)
                        : _num(pr[scope]);
                    return CheckboxListTile(
                      value: has || chosen.contains(id),
                      onChanged: has ? null : (on) => set(() => on == true ? chosen.add(id) : chosen.remove(id)),
                      title: Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(has ? t('لديه الشهادة', 'Already issued') : t('التقدم ${_pct(v)}', 'Progress ${_pct(v)}'),
                          style: appText(12, c: has ? c.success : c.textLight)),
                    );
                  }),
              ]),
            ),
            const SizedBox(height: AppSpace.sm),
            AppButton.primary(expand: true, 
              icon: Icons.send_rounded,
              label: t('إرسال (${chosen.length})', 'Send (${chosen.length})'),
              onPressed: chosen.isEmpty ? null : () => Navigator.of(ctx).pop(chosen.toList()),
            ),
          ]);
        }));
    if (ids != null && ids.isNotEmpty && context.mounted) await _send(context, ids: ids);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scope = '${cert['scope'] ?? 'both'}';
    final auto = cert['auto_send'] != false;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.workspace_premium_rounded, color: c.accent, size: 28),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text('${cert['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.textDark))),
          AppBadgePill(t('صدرت ${cert['issued_count'] ?? 0}', '${cert['issued_count'] ?? 0} issued'), color: c.success),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(t('تُمنح عن', 'Certifies'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in const ['lecture', 'section', 'both'])
            AppChoiceChip(
                label: AppConfig.lang == 'ar' ? cpScopeLabel(s).$1 : cpScopeLabel(s).$2,
                selected: scope == s,
                onTap: () => _rule(s, auto)),
        ]),
        AppSwitchTile(
          title: t('إرسال تلقائي عند الإكمال 100%', 'Send automatically at 100%'),
          subtitle: t('وإلا يرسلها الأستاذ يدوياً', 'Otherwise the instructor sends it manually'),
          value: auto,
          onChanged: (v) => _rule(scope, v),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppPill(icon: Icons.verified_rounded, label: t('إرسال للمكملين', 'Send to completers'),
              onTap: () => _send(context, completers: true)),
          AppPill(icon: Icons.checklist_rounded, label: t('اختيار طلاب', 'Choose students'), onTap: () => _pick(context)),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Team (instructor + assistants with their grants)
// ═════════════════════════════════════════════════════════════════════════════

class CpTeamTab extends StatelessWidget {
  const CpTeamTab({super.key, required this.profile, required this.onChanged});
  final CourseProfile profile;
  final Future<void> Function() onChanged;

  Future<void> _grant(Map<String, dynamic> a, {bool? edit, bool? att}) async {
    final uid = _map(a['user'])['id'];
    final r = await cpCall(
        () => ApiClient().put('$_base/${profile.id}/staff/$uid', body: {
              'lecture_edit': edit ?? a['lecture_edit'] == true,
              'lecture_attendance': att ?? a['lecture_attendance'] == true,
            }),
        ok: t('تم تحديث الصلاحيات', 'Permissions updated'));
    if (r != null) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = context.colors;
    final ins = p.instructor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ins != null)
        AppCard(
          child: Row(children: [
            AppAvatar(name: '${ins['name'] ?? ''}', url: ins['image_url']?.toString(), size: 44),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${ins['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w800, c: c.textDark)),
                Text(t('أستاذ المقرر — كل الصلاحيات', 'Instructor — full access'), style: appText(12, c: c.textLight)),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: AppSpace.sm),
      AppSectionTitle(t('المعيدون', 'Teaching assistants'),
          subtitle: t('السكاشن والمعامل افتراضياً — امنح صلاحيات المحاضرات عند الحاجة',
              'Sections & labs by default — grant lecture rights when needed')),
      const SizedBox(height: AppSpace.xs),
      if (p.assistants.isEmpty)
        AppEmpty(icon: Icons.person_add_alt_rounded, title: t('لا معيدين لهذا المقرر', 'No assistants for this course')),
      for (final a in p.assistants)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AppAvatar(name: '${_map(a['user'])['name'] ?? ''}', url: _map(a['user'])['image_url']?.toString(), size: 38),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('${_map(a['user'])['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                ),
              ]),
              AppSwitchTile(
                title: t('تعديل محتوى المحاضرات', 'Edit lecture content'),
                subtitle: t('رفع وتعديل وترتيب مواد المحاضرات، والإعلان لكل الطلاب',
                    'Upload, edit and reorder lecture material, and announce to all students'),
                value: a['lecture_edit'] == true,
                onChanged: p.caps.manageStaff ? (v) => _grant(a, edit: v) : null,
              ),
              AppSwitchTile(
                title: t('تسجيل حضور المحاضرات (بديل)', 'Take lecture attendance (substitute)'),
                value: a['lecture_attendance'] == true,
                onChanged: p.caps.manageStaff ? (v) => _grant(a, att: v) : null,
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Archive
// ═════════════════════════════════════════════════════════════════════════════

class CpArchiveTab extends StatefulWidget {
  const CpArchiveTab({super.key, required this.profile, required this.onChanged});
  final CourseProfile profile;
  final Future<void> Function() onChanged;

  @override
  State<CpArchiveTab> createState() => _CpArchiveTabState();
}

class _CpArchiveTabState extends State<CpArchiveTab> {
  final _code = TextEditingController();
  final _reason = TextEditingController();
  List<Map<String, dynamic>>? _requests;

  CourseProfile get p => widget.profile;

  @override
  void initState() {
    super.initState();
    if (p.caps.approveArchive) _loadRequests();
  }

  @override
  void dispose() {
    _code.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      final r = await ApiClient().get('$_base/${p.id}/archive/requests');
      if (mounted && r is Map) {
        setState(() => _requests = (r['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _requests = []);
    }
  }

  Future<void> _decide(int id, bool approve) async {
    final r = await cpCall(() => ApiClient().post('$_base/${p.id}/archive/requests/$id/${approve ? 'approve' : 'reject'}',
        body: {'days': 30}), ok: approve ? t('تمت الموافقة', 'Approved') : t('تم الرفض', 'Rejected'));
    if (r != null) await _loadRequests();
  }

  Future<void> _policy(String mode, {bool newCode = false}) async {
    final r = await cpCall(() => ApiClient().put('$_base/${p.id}/archive-policy', body: {'mode': mode, 'new_code': newCode}),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final out = <Widget>[];
    if (p.isStudent && p.closed) out.add(_studentView(context));
    if (p.caps.viewVersions) out.add(CpVersionsCard(profile: p));
    if (p.caps.manageArchive) {
      final pol = p.archivePolicy ?? const {};
      final mode = '${pol['mode'] ?? 'request'}';
      out.add(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSectionTitle(t('الوصول إلى الأرشيف', 'Archive access'),
              subtitle: t('بعد إغلاق المقرر يفتح الطلاب المحتوى للقراءة فقط', 'After the course closes, students open the material read-only')),
          if (pol['open_access'] != true)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppBanner(
                  icon: Icons.admin_panel_settings_rounded,
                  color: c.warning,
                  text: t('الوصول المفتوح غير مفعّل في المؤسسة — كل وصول يحتاج موافقة المسؤول',
                      'Open archive access is off in the organization — every access needs admin approval')),
            ),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in const ['auto', 'request', 'code'])
              AppChoiceChip(
                  label: AppConfig.lang == 'ar' ? cpArchiveModeLabel(m).$1 : cpArchiveModeLabel(m).$2,
                  selected: mode == m,
                  onTap: () => _policy(m)),
          ]),
          if (mode == 'code' && pol['code'] != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              Expanded(
                child: SelectableText('${pol['code']}',
                    style: appText(22, w: FontWeight.w800, c: c.primary).copyWith(letterSpacing: 4)),
              ),
              IconButton(
                  tooltip: t('نسخ', 'Copy'),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${pol['code']}'));
                    appToast(t('تم النسخ', 'Copied'));
                  }),
              IconButton(tooltip: t('كود جديد', 'New code'), icon: const Icon(Icons.autorenew_rounded),
                  onPressed: () => _policy('code', newCode: true)),
            ]),
          ],
        ]),
      ));
    }
    if (p.caps.approveArchive) {
      out.add(AppSectionTitle(t('طلبات فتح الأرشيف', 'Archive requests')));
      if (_requests == null) {
        out.add(const SizedBox(height: 160, child: AppListSkeleton(items: 2)));
      } else if (_requests!.isEmpty) {
        out.add(AppEmpty(icon: Icons.inbox_rounded, title: t('لا طلبات معلّقة', 'No pending requests')));
      } else {
        for (final r in _requests!) {
          final u = _map(r['student']);
          out.add(AppCard(
            child: Row(children: [
              AppAvatar(name: '${u['name'] ?? ''}', url: u['image_url']?.toString(), size: 36),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${u['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                  if ((r['reason'] ?? '').toString().isNotEmpty)
                    Text('${r['reason']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ]),
              ),
              IconButton(tooltip: t('رفض', 'Reject'), icon: Icon(Icons.close_rounded, color: c.danger),
                  onPressed: () => _decide((r['id'] as num).toInt(), false)),
              IconButton(tooltip: t('موافقة 30 يوماً', 'Approve 30 days'), icon: Icon(Icons.check_rounded, color: c.success),
                  onPressed: () => _decide((r['id'] as num).toInt(), true)),
            ]),
          ));
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final w in out) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: w),
    ]);
  }

  Widget _studentView(BuildContext context) {
    final c = context.colors;
    final a = p.archive ?? const {};
    final state = p.archiveState;
    if (state == 'granted') {
      final until = orgParseUtcLocal(a['until']);
      return AppBanner(
          icon: Icons.lock_open_rounded,
          color: c.success,
          text: until == null
              ? t('لديك وصول للقراءة فقط', 'You have read-only access')
              : t('لديك وصول للقراءة فقط حتى ${AppTime.date(until)}', 'Read-only access until ${AppTime.date(until)}'));
    }
    if (state == 'pending') {
      return AppBanner(icon: Icons.hourglass_top_rounded, color: c.warning, text: t('طلبك قيد المراجعة', 'Your request is under review'));
    }
    final mode = p.archiveEffectiveMode;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('افتح أرشيف المقرر', 'Open the course archive'),
            subtitle: AppConfig.lang == 'ar' ? cpArchiveModeLabel(mode).$1 : cpArchiveModeLabel(mode).$2),
        const SizedBox(height: AppSpace.sm),
        if (mode == 'code') ...[
          AppField(controller: _code, label: t('كود الأرشيف', 'Archive code'), ltr: true),
          const SizedBox(height: AppSpace.sm),
          AppButton.primary(expand: true, 
            icon: Icons.key_rounded,
            label: t('فتح', 'Unlock'),
            onPressed: () async {
              final r = await cpCall(() => ApiClient().post('$_base/${p.id}/archive/unlock', body: {'code': _code.text.trim()}),
                  ok: t('تم فتح الأرشيف', 'Archive unlocked'));
              if (r != null) await widget.onChanged();
            },
          ),
        ] else ...[
          AppField(controller: _reason, label: t('السبب (اختياري)', 'Reason (optional)'), maxLines: 2),
          const SizedBox(height: AppSpace.sm),
          AppButton.primary(expand: true, 
            icon: Icons.send_rounded,
            label: t('اطلب الوصول', 'Request access'),
            onPressed: a['took_it'] == true
                ? () async {
                    final r = await cpCall(() => ApiClient().post('$_base/${p.id}/archive/request', body: {'reason': _reason.text.trim()}),
                        ok: t('أُرسل الطلب', 'Request sent'));
                    if (r != null) await widget.onChanged();
                  }
                : null,
          ),
        ],
      ]),
    );
  }
}
