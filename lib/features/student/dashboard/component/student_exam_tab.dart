
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../config/app_theme.dart';
import '../../../../core/api_client.dart';

class StudentExamsTab extends StatefulWidget {
  const StudentExamsTab({super.key});

  @override
  State<StudentExamsTab> createState() => _StudentExamsTabState();
}

class _StudentExamsTabState extends State<StudentExamsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ApiClient _api = ApiClient();
  List<_StudentExamEntry> _exams = [];
  List<_UpcomingExam> _upcoming = [];
  bool _loading = true;
  String? _error;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _startNotifPolling();
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }

  void _startNotifPolling() {
    _pollUpcoming();
    _notifTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _pollUpcoming());
  }

  Future<void> _pollUpcoming() async {
    try {
      final data = await _api.get('/api/v1/student/exams/upcoming');
      if (!mounted) return;
      final list = (data as List? ?? [])
          .map((e) => _UpcomingExam.fromJson(e as Map<String, dynamic>))
          .toList();
      for (final exam in list) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
          backgroundColor: context.colors.accent.withValues(alpha: 0.95),
          content: Row(children: [
            const Icon(Icons.alarm_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    'اختبار "${exam.name}" في ${exam.courseName} يبدأ بعد ${exam.minutesLeft} دقيقة!',
                    style: const TextStyle(
                        fontFamily: 'bahji',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13))),
          ]),
          actions: [
            TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('إغلاق',
                    style: TextStyle(color: Colors.white, fontFamily: 'bahji')))
          ],
        ));
        break;
      }
      if (mounted) if(mounted) setState(() => _upcoming = list);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/api/v1/student/exams');
      setState(() {
        _exams = (data as List? ?? [])
            .map((e) => _StudentExamEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            backgroundColor: context.colors.background,
            body: SafeArea(
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                   Text('اختباراتي', style: context.colors.h1),
                                  if (!_loading)
                                    Text('${_exams.length} اختبار',
                                        style: context.colors.caption),
                                ])),
                        if (!_loading && _exams.isNotEmpty)
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: context.colors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                  '${_exams.where((e) => e.isSubmitted).length} / ${_exams.length} مكتمل',
                                  style: context.colors.label
                                      .copyWith(color: context.colors.primary))),
                      ])),
                  if (_upcoming.isNotEmpty)
                    Container(
                        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: context.colors.accent.withValues(alpha: 0.08),
                            borderRadius:
                            BorderRadius.circular(context.colors.radiusMedium),
                            border: Border.all(
                                color: context.colors.accent.withValues(alpha: 0.3))),
                        child: Row(children: [
                           Icon(Icons.schedule_rounded,
                              color: context.colors.accent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  _upcoming.length == 1
                                      ? 'اختبار "${_upcoming.first.name}" يبدأ بعد ${_upcoming.first.minutesLeft} دقيقة'
                                      : '${_upcoming.length} اختبارات قادمة قريباً',
                                  style: context.colors.label
                                      .copyWith(color: context.colors.accent))),
                        ])),
                  const SizedBox(height: 12),
                  Expanded(
                      child: _loading
                          ?  Center(
                          child: CircularProgressIndicator(
                              valueColor:
                              AlwaysStoppedAnimation(context.colors.primary)))
                          : _error != null
                          ? Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                 Icon(Icons.error_outline,
                                    size: 48, color: context.colors.danger),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    style: context.colors.body,
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                    onPressed: _load,
                                    child: const Text('إعادة المحاولة',
                                        style:
                                        TextStyle(fontFamily: 'bahji'))),
                              ]))
                          : _exams.isEmpty
                          ?  Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.quiz_outlined,
                                    size: 64, color: context.colors.textLight),
                                SizedBox(height: 12),
                                Text('لا توجد اختبارات متاحة حالياً',
                                    style: context.colors.body),
                                SizedBox(height: 6),
                                Text(
                                    'سيظهر هنا الاختبارات بعد نشرها من قِبل المعلم',
                                    style: context.colors.caption,
                                    textAlign: TextAlign.center),
                              ]))
                          : RefreshIndicator(
                          color: context.colors.primary,
                          onRefresh: _load,
                          child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 4, 20, 32),
                              physics: const BouncingScrollPhysics(),
                              itemCount: _exams.length,
                              separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                              itemBuilder: (_, i) =>
                                  _ExamCard(exam: _exams[i])))),
                ]))));
  }
}

class _ExamCard extends StatelessWidget {
  final _StudentExamEntry exam;

  const _ExamCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    final pct = exam.percentage;
    final passed = exam.passed;
    final sub = exam.isSubmitted;
    final color =
    sub ? (passed ? context.colors.success : context.colors.danger) : context.colors.primary;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            boxShadow: context.colors.cardShadow,
            border:
            Border.all(color: color.withValues(alpha: 0.25), width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                    sub
                        ? (passed
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded)
                        : Icons.quiz_rounded,
                    color: color,
                    size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exam.name,
                          style: context.colors.h3.copyWith(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('📚 ${exam.courseName}',
                          style: context.colors.caption.copyWith(fontSize: 11)),
                    ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(sub ? (passed ? 'ناجح' : 'راسب') : 'لم يُؤَدَّ',
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color))),
          ]),
          if (sub && pct != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: pct / 100,
                          backgroundColor: context.colors.divider,
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 6))),
              const SizedBox(width: 10),
              Text('${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontFamily: 'bahji',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ]),
            const SizedBox(height: 4),
            Text('أجبت عن ${exam.answeredCount} / ${exam.questionCount} سؤال',
                style: context.colors.caption.copyWith(fontSize: 11)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            if (exam.duration != null)
              _Chip(Icons.timer_outlined, '${exam.duration} دقيقة'),
            if (exam.totalMarks != null)
              _Chip(Icons.grade_outlined,
                  '${exam.totalMarks!.toStringAsFixed(0)} درجة'),
            if (!sub) _Chip(Icons.help_outline, '${exam.questionCount} سؤال'),
          ]),
        ]));
  }
}

class _Chip extends StatelessWidget {
  final IconData i;
  final String l;

  const _Chip(this.i, this.l);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 12, color: context.colors.textLight),
        const SizedBox(width: 3),
        Text(l, style: context.colors.caption)
      ]);
}
class _StudentExamEntry {
  final int id;
  final String name;
  final String? description;
  final String courseName;
  final int courseId;
  final int? duration;
  final double? totalMarks;
  final double? passingScore;
  final String? startDate;
  final bool isSubmitted;
  final int answeredCount;
  final int questionCount;
  final Map<String, dynamic>? score;

  const _StudentExamEntry(
      {required this.id,
        required this.name,
        required this.courseName,
        required this.courseId,
        required this.isSubmitted,
        required this.answeredCount,
        required this.questionCount,
        this.description,
        this.duration,
        this.totalMarks,
        this.passingScore,
        this.startDate,
        this.score});

  factory _StudentExamEntry.fromJson(Map<String, dynamic> j) =>
      _StudentExamEntry(
          id: j['id'] as int,
          name: j['name'] as String,
          description: j['description'] as String?,
          courseName: j['course_name'] as String,
          courseId: j['course_id'] as int,
          duration: j['duration'] as int?,
          totalMarks: (j['total_marks'] as num?)?.toDouble(),
          passingScore: (j['passing_score'] as num?)?.toDouble(),
          startDate: j['start_date'] as String?,
          isSubmitted: j['is_submitted'] as bool? ?? false,
          answeredCount: j['answered_count'] as int? ?? 0,
          questionCount: j['question_count'] as int? ?? 0,
          score: j['score'] as Map<String, dynamic>?);

  bool get passed => isSubmitted && (score?['passed'] as bool? ?? false);

  double? get percentage =>
      isSubmitted ? (score?['percentage'] as num?)?.toDouble() : null;
}

class _UpcomingExam {
  final int id;
  final String name;
  final String courseName;
  final int minutesLeft;

  const _UpcomingExam(
      {required this.id,
        required this.name,
        required this.courseName,
        required this.minutesLeft});

  factory _UpcomingExam.fromJson(Map<String, dynamic> j) => _UpcomingExam(
      id: j['id'] as int,
      name: j['name'] as String,
      courseName: j['course_name'] as String,
      minutesLeft: j['minutes_left'] as int? ?? 0);
}
