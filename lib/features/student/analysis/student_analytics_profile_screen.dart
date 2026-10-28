// lib/features/student/analysis/student_analytics_profile_screen.dart
// The analytics profile — ONE screen used by both sides, now part of the student analytics module:
//   • the student opens his own   (StudentAnalyticsProfileScreen.forStudent)  — from the hub / a course report
//   • the teacher opens a student (StudentAnalyticsProfileScreen.forTeacher)  — from the Data Lab sheet
// All courses or one: progress, attendance, exams, the marks the teacher published (each with the class average),
// "you vs the class", and the saved review / read flags.
// For the student every course leads to its full report (attendance list, exams, trend) and the flags open the banks.
//
// The old path lib/features/student/courses/details/student_analytics_profile_screen.dart re-exports this file,
// so existing imports keep working.
library;

import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../teacher/data_lab/data_lab_api.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import '../../teacher/data_lab/data_lab_widgets.dart' show DlAvatar;
import 'flags/student_flags_screen.dart';
import 'student_analytics_provider.dart';
import 'student_analytics_widgets.dart';
import 'student_course_analytics_screen.dart';

class StudentAnalyticsProfileScreen extends StatefulWidget {
  const StudentAnalyticsProfileScreen._({this.studentId, this.studentName, this.courseId, required this.teacherMode});

  /// The signed-in student's own profile. [courseId] opens it on one course.
  factory StudentAnalyticsProfileScreen.forStudent({int? courseId}) =>
      StudentAnalyticsProfileScreen._(courseId: courseId, teacherMode: false);

  /// A teacher looking at a student of his course.
  factory StudentAnalyticsProfileScreen.forTeacher({required int studentId, required String studentName, int? courseId}) =>
      StudentAnalyticsProfileScreen._(studentId: studentId, studentName: studentName, courseId: courseId, teacherMode: true);

  final int? studentId, courseId;
  final String? studentName;
  final bool teacherMode;

  @override
  State<StudentAnalyticsProfileScreen> createState() => _State();
}

class _State extends State<StudentAnalyticsProfileScreen> {
  final _api = DataLabApi();
  DlProfile? _profile;
  bool _loading = true;
  String? _error;
  int? _scope; // course id, null = every course
  bool _allMine = false; // teacher: "all my courses" instead of this one

  @override
  void initState() {
    super.initState();
    _scope = widget.courseId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = widget.teacherMode
          ? await _api.studentProfile(widget.studentId!, courseId: _allMine ? null : widget.courseId, lang: AppConfig.lang)
          : await _api.myProfile(lang: AppConfig.lang);
      if (!mounted) return;
      setState(() {
        _profile = p;
        if (_scope != null && !p.courses.any((b) => b.courseId == _scope)) _scope = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(ApiException.from(e)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setScope(int? id) => setState(() => _scope = id);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_loading && _profile == null) {
      body = const AppListSkeleton();
    } else if (_error != null && _profile == null) {
      body = AnErrorRetry(message: _error!, onRetry: _load);
    } else if (_profile == null || _profile!.courses.isEmpty) {
      body = AnEmpty(icon: Icons.insights_rounded, title: 'dl_profile_empty'.tr);
    } else {
      final p = _profile!;
      final blocks = _scope == null ? p.courses : p.courses.where((b) => b.courseId == _scope).toList();
      final single = blocks.length == 1;
      final prog = single ? blocks.first.progress : p.progress;
      final att = single ? blocks.first.attendance : p.attendance;
      final ex = single ? blocks.first.examAvg : p.examAvg;
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
          children: [
            _hero(p, prog, att, ex),
            const SizedBox(height: 12),
            if (widget.teacherMode && widget.courseId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, children: [
                  _ScopeChip(label: 'dl_scope_this_course'.tr, selected: !_allMine, onTap: () {
                    if (_allMine) {
                      _allMine = false;
                      _scope = widget.courseId;
                      _load();
                    }
                  }),
                  _ScopeChip(label: 'dl_scope_all_mine'.tr, selected: _allMine, onTap: () {
                    if (!_allMine) {
                      _allMine = true;
                      _scope = null;
                      _load();
                    }
                  }),
                ]),
              ),
            if (p.courses.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _ScopeChip(label: 'dl_scope_all'.tr, selected: _scope == null, onTap: () => _setScope(null)),
                    for (final b in p.courses)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: _ScopeChip(label: b.title, selected: _scope == b.courseId, onTap: () => _setScope(b.courseId)),
                      ),
                  ]),
                ),
              ),
            AnCard(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                AnRing(value: prog, label: 'dl_progress'.tr),
                AnRing(value: att, label: 'dl_attendance'.tr),
                AnRing(value: ex, label: 'dl_exams'.tr),
              ]),
            ),
            const SizedBox(height: 12),
            if (single)
              _CourseDetail(block: blocks.first, teacherMode: widget.teacherMode)
            else
              for (final b in blocks) _CourseCompact(block: b, onTap: () => _setScope(b.courseId)),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(widget.teacherMode ? 'dl_profile_teacher_note'.tr : 'dl_profile_student_note'.tr,
                  textAlign: TextAlign.center, style: anText(11, c: c.textLight, h: 1.5)),
            ),
          ],
        ),
      );
    }
    return BasePage(
      key: const ValueKey('dl_profile'),
      useWebCard: true,
      appBar: ScreenAppBar(title: 'dl_profile_title'.tr),
      child: body,
    );
  }

  Widget _hero(DlProfile p, double? prog, double? att, double? ex) {
    final name = p.name.isEmpty ? (widget.studentName ?? '') : p.name;
    final overall = anOverall(progress: prog, attendance: att, exams: ex);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: anHeroDecoration(context, roundAll: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.heroGlassBorder),
            child: DlAvatar(name: name, url: p.imageUrl, size: 58),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(19, w: FontWeight.w800, c: context.colors.onHero)),
              const SizedBox(height: 4),
              Text(anInsightSentence(prog, att, ex, mine: !widget.teacherMode), style: anText(12.5, c: context.colors.onHeroMuted, h: 1.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (overall != null) AnGlassPill(icon: Icons.auto_awesome_rounded, label: '${anLevel(overall)} · ${anPct(overall)}'),
          AnGlassPill(icon: Icons.menu_book_rounded, label: '${p.courses.length} ${anTr('an_courses', 'Courses')}'),
          if (p.reviewFlags + p.readFlags > 0)
            AnGlassPill(icon: Icons.bookmarks_rounded, label: '${p.reviewFlags + p.readFlags} ${anTr('an_saved_flags', 'saved flags')}'),
        ]),
      ]),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: anText(12.5, w: FontWeight.w700, c: selected ? c.onHero : c.textDark)),
      selectedColor: c.primary,
      backgroundColor: c.cardBg,
      side: BorderSide(color: selected ? c.primary : c.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (_) => onTap(),
    );
  }
}

class _CourseCompact extends StatelessWidget {
  const _CourseCompact({required this.block, required this.onTap});

  final DlCourseBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final attention = anNeedsAttention(attendance: block.attendance, exams: block.examAvg);
    Widget line(String label, double? v) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(width: 84, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(11.5, c: c.textMedium))),
        Expanded(child: AnBar(value: v, height: 6)),
        SizedBox(
          width: 44,
          child: Text(anPct(v), textAlign: TextAlign.end, style: anText(12, w: FontWeight.w800, c: anScoreColor(context, v))),
        ),
      ]),
    );
    return AnCard(
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: attention ? c.warning.withValues(alpha: 0.45) : null,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(block.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(14.5, w: FontWeight.w800, c: c.textDark))),
          if (attention) ...[AnTag(anTr('an_needs_attention', 'Needs attention'), c.warning), const SizedBox(width: 4)],
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
        line('dl_progress'.tr, block.progress),
        line('dl_attendance'.tr, block.attendance),
        line('dl_exams'.tr, block.examAvg),
      ]),
    );
  }
}

class _CourseDetail extends StatelessWidget {
  const _CourseDetail({required this.block, required this.teacherMode});

  final DlCourseBlock block;
  final bool teacherMode;

  double? _avg(String key) {
    for (final col in block.columns) {
      if (col.key == key) return col.classAvg;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extra = block.extraColumns;
    final vsRows = <(String, double?, double?)>[
      ('dl_progress'.tr, block.progress, _avg('progress')),
      ('dl_attendance'.tr, block.attendance, _avg('attendance')),
      ('dl_exams'.tr, block.examAvg, _avg('exam_avg')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // the student goes on to the full report of the course
      if (!teacherMode)
        AnCard(
          margin: const EdgeInsets.only(bottom: 12),
          borderColor: c.primary.withValues(alpha: 0.3),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentCourseAnalyticsScreen(courseId: block.courseId, courseTitle: block.title, initialBlock: block),
            ),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.assessment_rounded, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(anTr('an_open_report', 'Open the full course report'), style: anText(13.5, w: FontWeight.w800, c: c.textDark)),
                Text(anTr('an_open_report_sub', 'Every session, every exam and your progress over time'),
                    style: anText(11.5, c: c.textMedium, h: 1.4)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.primary),
          ]),
        ),
      if (block.held > 0)
        AnCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(Icons.event_available_rounded, color: c.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${'dl_attended'.tr} ${block.attended} ${'dl_of'.tr} ${block.held} ${'dl_sessions_held'.tr}',
                  style: anText(13, w: FontWeight.w700, c: c.textDark, h: 1.4)),
            ),
          ]),
        ),
      if (vsRows.any((r) => r.$2 != null && r.$3 != null)) ...[
        AnSectionTitle(anTr('an_vs_class', 'You and your class'), icon: Icons.groups_rounded),
        AnVsClassCard(rows: vsRows),
      ],
      if (extra.isNotEmpty) ...[
        AnSectionTitle('dl_profile_marks'.tr, icon: Icons.workspace_premium_rounded, subtitle: teacherMode ? null : 'dl_profile_marks_sub'.tr),
        AnCard(
          child: Column(children: [
            for (var i = 0; i < extra.length; i++) ...[
              if (i > 0) Divider(color: c.divider, height: 24),
              AnMarkRow(col: extra[i], teacherMode: teacherMode),
            ],
          ]),
        ),
      ],
      if (block.exams.isNotEmpty) ...[
        AnSectionTitle('dl_exams'.tr, icon: Icons.quiz_rounded),
        AnCard(
          child: Column(children: [
            for (var i = 0; i < block.exams.length; i++) ...[
              if (i > 0) Divider(color: c.divider, height: 22),
              _ExamRow(exam: block.exams[i]),
            ],
          ]),
        ),
      ],
      AnSectionTitle('dl_flags_title'.tr, icon: Icons.bookmarks_rounded, subtitle: 'dl_flags_sub'.tr),
      Row(children: [
        Expanded(
          child: AnFlagTile(
            icon: Icons.bookmark_rounded,
            color: c.warning,
            value: block.reviewFlags,
            label: 'dl_review_flags'.tr,
            onTap: teacherMode ? null : () => _openFlags(context, 0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnFlagTile(
            icon: Icons.menu_book_rounded,
            color: c.danger,
            value: block.readFlags,
            label: 'dl_read_flags'.tr,
            onTap: teacherMode ? null : () => _openFlags(context, 1),
          ),
        ),
      ]),
    ]);
  }

  void _openFlags(BuildContext context, int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: block.courseId, courseTitle: block.title, initialTab: tab)),
  );
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.exam});

  final DlExam exam;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exam.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13.5, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 2),
          Text(exam.attempts == 0 ? 'dl_not_attempted'.tr : '${exam.attempts} ${'dl_attempts'.tr}', style: anText(11, c: c.textLight)),
        ]),
      ),
      if (exam.passed != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: AnTag(exam.passed! ? 'dl_passed'.tr : 'dl_not_passed'.tr, exam.passed! ? c.success : c.danger),
        ),
      Text(exam.best == null ? '–' : '${dlFmt(exam.best)}%', style: anText(15, w: FontWeight.w800, c: anScoreColor(context, exam.best))),
    ]);
  }
}
