// lib/features/shared/data_lab/student_analytics_profile_screen.dart
// The student's analytics profile — ONE screen used by both sides:
//   • the student opens his own  (StudentAnalyticsProfileScreen.forStudent)
//   • the teacher opens a student's (StudentAnalyticsProfileScreen.forTeacher) from the Data Lab sheet
// Shows progress, attendance, exam scores, review / read flags and the Data Lab columns the teacher published
// (the teacher sees every column), for all courses or one course.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show EmptyState, ErrorRetry;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../teacher/data_lab/data_lab_api.dart';
import '../../../teacher/data_lab/data_lab_models.dart';
import '../../../teacher/data_lab/data_lab_widgets.dart';

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
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_loading && _profile == null) {
      body = const Center(child: AppLoadingIndicator());
    } else if (_error != null && _profile == null) {
      body = ErrorRetry(message: _error!, onRetry: _load);
    } else if (_profile == null || _profile!.courses.isEmpty) {
      body = EmptyState('dl_profile_empty'.tr, icon: Icons.insights_rounded);
    } else {
      final p = _profile!;
      final blocks = _scope == null ? p.courses : p.courses.where((b) => b.courseId == _scope).toList();
      final single = blocks.length == 1;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
          children: [
            _hero(p, blocks),
            const SizedBox(height: 12),
            if (widget.teacherMode && widget.courseId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, children: [
                  DlChoiceChip(label: 'dl_scope_this_course'.tr, selected: !_allMine, onTap: () {
                    if (_allMine) {
                      _allMine = false;
                      _scope = widget.courseId;
                      _load();
                    }
                  }),
                  DlChoiceChip(label: 'dl_scope_all_mine'.tr, selected: _allMine, onTap: () {
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
                    DlChoiceChip(label: 'dl_scope_all'.tr, selected: _scope == null, onTap: () => setState(() => _scope = null)),
                    for (final b in p.courses)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: DlChoiceChip(label: b.title, selected: _scope == b.courseId, onTap: () => setState(() => _scope = b.courseId)),
                      ),
                  ]),
                ),
              ),
            _RingsCard(
              progress: single ? blocks.first.progress : p.progress,
              attendance: single ? blocks.first.attendance : p.attendance,
              exams: single ? blocks.first.examAvg : p.examAvg,
            ),
            const SizedBox(height: 12),
            if (single)
              _CourseDetail(block: blocks.first, teacherMode: widget.teacherMode)
            else
              for (final b in blocks) _CourseCompact(block: b, onTap: () => setState(() => _scope = b.courseId)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(widget.teacherMode ? 'dl_profile_teacher_note'.tr : 'dl_profile_student_note'.tr,
                  textAlign: TextAlign.center, style: dlText(11, c: c.textLight, h: 1.5)),
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

  Widget _hero(DlProfile p, List<DlCourseBlock> blocks) {
    final single = blocks.length == 1;
    final prog = single ? blocks.first.progress : p.progress;
    final att = single ? blocks.first.attendance : p.attendance;
    final ex = single ? blocks.first.examAvg : p.examAvg;
    final name = p.name.isEmpty ? (widget.studentName ?? '') : p.name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.colors.radiusLarge),
        gradient: LinearGradient(
          colors: [context.colors.primary, context.colors.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: context.colors.primaryShadow,
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
          child: DlAvatar(name: name, url: p.imageUrl, size: 58),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(19, w: FontWeight.w800, c: Colors.white)),
            const SizedBox(height: 4),
            Text(_insight(prog, att, ex), style: dlText(12.5, c: Colors.white70, h: 1.5)),
          ]),
        ),
      ]),
    );
  }

  /// One warm sentence about the strongest / weakest area.
  String _insight(double? prog, double? att, double? ex) {
    final m = <String, double>{
      if (prog != null) 'dl_progress'.tr: prog,
      if (att != null) 'dl_attendance'.tr: att,
      if (ex != null) 'dl_exams'.tr: ex,
    };
    if (m.isEmpty) return 'dl_insight_empty'.tr;
    final best = m.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final worst = m.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final mine = !widget.teacherMode;
    if (m.length == 1 || best.key == worst.key || worst.value >= 75) {
      return (mine ? 'dl_insight_great_me' : 'dl_insight_great_other').tr.replaceAll('{a}', best.key);
    }
    return '${(mine ? 'dl_insight_best_me' : 'dl_insight_best_other').tr.replaceAll('{a}', best.key)} '
        '${'dl_insight_focus'.tr.replaceAll('{a}', worst.key)}';
  }
}

class _RingsCard extends StatelessWidget {
  const _RingsCard({this.progress, this.attendance, this.exams});

  final double? progress, attendance, exams;

  @override
  Widget build(BuildContext context) => DlCard(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      DlRing(value: progress, label: 'dl_progress'.tr),
      DlRing(value: attendance, label: 'dl_attendance'.tr),
      DlRing(value: exams, label: 'dl_exams'.tr),
    ]),
  );
}

class _CourseCompact extends StatelessWidget {
  const _CourseCompact({required this.block, required this.onTap});

  final DlCourseBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget line(String label, double? v) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(width: 78, child: Text(label, style: dlText(11.5, c: c.textMedium))),
        Expanded(child: DlBar(value: v, height: 6)),
        SizedBox(width: 44, child: Text(v == null ? '–' : '${v.round()}%', textAlign: TextAlign.end, style: dlText(12, w: FontWeight.w800, c: dlScoreColor(context, v)))),
      ]),
    );
    return DlCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(block.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(14.5, w: FontWeight.w800, c: c.textDark))),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extra = block.extraColumns;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // attendance sentence
      if (block.held > 0)
        DlCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(Icons.event_available_rounded, color: c.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${'dl_attended'.tr} ${block.attended} ${'dl_of'.tr} ${block.held} ${'dl_sessions_held'.tr}',
                  style: dlText(13, w: FontWeight.w700, c: c.textDark, h: 1.4)),
            ),
          ]),
        ),
      // Data Lab columns
      if (extra.isNotEmpty) ...[
        DlSectionTitle('dl_profile_marks'.tr, subtitle: teacherMode ? null : 'dl_profile_marks_sub'.tr),
        DlCard(
          child: Column(children: [
            for (var i = 0; i < extra.length; i++) ...[
              if (i > 0) Divider(color: c.divider, height: 22),
              _MarkRow(col: extra[i], teacherMode: teacherMode),
            ],
          ]),
        ),
      ],
      // exams
      if (block.exams.isNotEmpty) ...[
        DlSectionTitle('dl_exams'.tr),
        DlCard(
          child: Column(children: [
            for (var i = 0; i < block.exams.length; i++) ...[
              if (i > 0) Divider(color: c.divider, height: 22),
              _ExamRow(exam: block.exams[i]),
            ],
          ]),
        ),
      ],
      // flags
      DlSectionTitle('dl_flags_title'.tr, subtitle: 'dl_flags_sub'.tr),
      Row(children: [
        Expanded(child: _FlagTile(icon: Icons.bookmark_rounded, color: c.warning, value: block.reviewFlags, label: 'dl_review_flags'.tr)),
        const SizedBox(width: 10),
        Expanded(child: _FlagTile(icon: Icons.flag_rounded, color: c.danger, value: block.readFlags, label: 'dl_read_flags'.tr)),
      ]),
    ]);
  }
}

class _MarkRow extends StatelessWidget {
  const _MarkRow({required this.col, required this.teacherMode});

  final DlProfileColumn col;
  final bool teacherMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = dlNum(col.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(col.label, style: dlText(13.5, w: FontWeight.w700, c: c.textDark))),
        if (teacherMode && !col.visibleToStudents) Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Tooltip(message: 'dl_hidden_from_student'.tr, child: Icon(Icons.visibility_off_rounded, size: 15, color: c.textLight)),
        ),
        Text(dlFmt(col.value), style: dlText(15, w: FontWeight.w800, c: col.isNumber ? dlScoreColor(context, n == null ? null : n / (col.maxValue == 0 ? 100 : col.maxValue) * 100) : c.textDark)),
      ]),
      if (col.isNumber && n != null) ...[
        const SizedBox(height: 6),
        DlBar(value: n, max: col.maxValue, marker: col.classAvg),
        if (col.classAvg != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('${'dl_class_avg'.tr}: ${dlFmt(col.classAvg)}', style: dlText(10.5, c: c.textLight)),
          ),
      ],
    ]);
  }
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
          Text(exam.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13.5, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 2),
          Text(exam.attempts == 0 ? 'dl_not_attempted'.tr : '${exam.attempts} ${'dl_attempts'.tr}', style: dlText(11, c: c.textLight)),
        ]),
      ),
      if (exam.passed != null) Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: DlTag(exam.passed! ? 'dl_passed'.tr : 'dl_not_passed'.tr, exam.passed! ? c.success : c.danger),
      ),
      Text(exam.best == null ? '–' : '${dlFmt(exam.best)}%', style: dlText(15, w: FontWeight.w800, c: dlScoreColor(context, exam.best))),
    ]);
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 24),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: dlText(20, w: FontWeight.w800, c: color)),
          Text(label, style: dlText(11, c: context.colors.textMedium, h: 1.3)),
        ]),
      ),
    ]),
  );
}
