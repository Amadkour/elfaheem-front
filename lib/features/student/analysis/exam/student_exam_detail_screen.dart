// student_exam_detail_screen.dart — Premium redesign (analytics style)
//
// Entry gate: shows exam info, score history, then launches quiz.
// Shows "Try Again" when maxSubmissions allows more rounds.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../../utils/widget/base_page.dart';
import 'exam_tr.dart';
import 'exam_ui.dart';
import 'student_exam_api.dart';
import 'student_exam_frozen_screen.dart';
import 'student_exam_provider.dart';
import 'student_exam_quiz_screen.dart';

class StudentExamDetailScreen extends StatefulWidget {
  final StudentExamListItem exam;

  const StudentExamDetailScreen({super.key, required this.exam});

  @override
  State<StudentExamDetailScreen> createState() =>
      _StudentExamDetailScreenState();
}

class _StudentExamDetailScreenState extends State<StudentExamDetailScreen> {
  bool _starting = false;
  String? _entryError;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _entryError = null;
    });
    final prov = context.read<StudentExamProvider>();
    final ok = await prov.startExam(widget.exam);
    if (!mounted) return;
    setState(() => _starting = false);
    if (!ok) {
      setState(() => _entryError =
          prov.questionsError ?? tx('exam_load_questions_failed'));
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: prov,
          child: const StudentExamQuizScreen(),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    if (exam.isFrozen && !exam.isSubmitted) {
      return StudentExamFrozenScreen(
        exam: exam,
        onBack: () => Navigator.pop(context),
      );
    }

    final c = context.colors;
    final isDone = exam.isSubmitted;
    final canRetry = exam.canRetry && isDone;
    final isScheduled =
        exam.startDate != null && exam.startDate!.isAfter(DateTime.now());

    final Color accent;
    if (isDone) {
      accent = exam.passed == true ? c.success : kDanger;
    } else if (isScheduled) {
      accent = kAmber;
    } else {
      accent = c.primary;
    }

    final heroColors = isDone || isScheduled
        ? [Color.lerp(accent, Colors.black, .35)!, accent]
        : [kDeep, c.primary];

    final remaining = exam.computedRemainingSubmissions ?? 0;

    return BasePage( useWebCard: true,maxWith: 1100, child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [
          // ── Hero ────────────────────────────────────────────────────────
          ExamHero(
            colors: heroColors,
            child: Column(children: [
              ExamHeroBar(
                title: exam.courseName ?? tx('exam_exams'),
                subtitle: tx('exam_n_questions', {'n': exam.questionCount}),
              ),
              const SizedBox(height: 22),
              if (isDone && exam.percentage != null)
                ExamRing(
                  value: exam.percentage!,
                  size: 128,
                  stroke: 10,
                  center: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${exam.percentage!.toStringAsFixed(0)}%',
                        style:
                        examT(30, w: FontWeight.w800, c: Colors.white)),
                    Text(
                        exam.passed == true
                            ? tx('exam_passed_mark')
                            : tx('exam_failed_mark'),
                        style: examT(12, c: Colors.white70)),
                  ]),
                )
              else
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                  ),
                  child: Icon(
                    isScheduled ? Icons.schedule_rounded : Icons.quiz_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              const SizedBox(height: 16),
              Text(exam.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: examT(19, w: FontWeight.w800, c: Colors.white, h: 1.4)),
              if (exam.description != null && exam.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(exam.description!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: examT(12.5, c: Colors.white70, h: 1.6)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                HeroStat(
                  icon: Icons.timer_outlined,
                  color: const Color(0xFF80D8FF),
                  value: tx('exam_n_minutes', {'n': exam.duration ?? 0}),
                  label: tx('exam_duration'),
                ),
                if (exam.passingScore != null) ...[
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.star_rounded,
                    color: const Color(0xFFFFD740),
                    value: '${exam.passingScore!.toInt()}%',
                    label: tx('exam_passing_score'),
                  ),
                ],
                if (exam.totalMarks != null) ...[
                  const SizedBox(width: 10),
                  HeroStat(
                    icon: Icons.grade_rounded,
                    color: const Color(0xFF69F0AE),
                    value: '${exam.totalMarks!.toInt()}',
                    label: tx('exam_total_marks'),
                  ),
                ],
              ]),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            child: Column(children: [
              if (isDone) ...[
                _ScoreCard(exam: exam),
                const SizedBox(height: 16),
              ],
              if (isScheduled && !isDone) ...[
                _CountdownCard(target: exam.startDate!),
                const SizedBox(height: 16),
              ],

              // Schedule & attempts
              if (exam.startDate != null ||
                  exam.endDate != null ||
                  (exam.maxSubmissions != null && exam.maxSubmissions! > 0))
                ExamCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    if (exam.startDate != null)
                      ExamInfoRow(Icons.schedule_rounded,
                          tx('exam_start_time'), _fmtDate(exam.startDate!), kAmber),
                    if (exam.endDate != null) ...[
                      if (exam.startDate != null) const _Gap(),
                      ExamInfoRow(
                        Icons.hourglass_bottom_rounded,
                        tx('exam_deadline'),
                        _fmtDate(exam.endDate!),
                        exam.isDeadlineFrozen ? kDanger : kAmber,
                      ),
                    ],
                    if (exam.maxSubmissions != null &&
                        exam.maxSubmissions! > 0) ...[
                      if (exam.startDate != null || exam.endDate != null)
                        const _Gap(),
                      ExamInfoRow(
                          Icons.repeat_rounded,
                          tx('exam_used_attempts'),
                          '${exam.submissionCount} / ${exam.maxSubmissions}',
                          kViolet),
                      const _Gap(),
                      ExamInfoRow(
                        Icons.replay_circle_filled_rounded,
                        tx('exam_remaining_attempts'),
                        '$remaining',
                        remaining > 0 ? c.success : kDanger,
                      ),
                    ],
                  ]),
                ),
              if (exam.startDate != null ||
                  exam.endDate != null ||
                  (exam.maxSubmissions != null && exam.maxSubmissions! > 0))
                const SizedBox(height: 16),

              if (_entryError != null) ...[
                ExamBanner(
                    icon: Icons.error_outline_rounded,
                    color: kDanger,
                    text: _entryError!),
                const SizedBox(height: 16),
              ],

              if ((!isDone && !isScheduled) || canRetry) ...[
                ExamBanner(
                    icon: Icons.warning_amber_rounded,
                    color: kAmber,
                    text: tx('exam_start_warning')),
                const SizedBox(height: 18),
              ],

              if (!isScheduled) ...[
                if (!isDone)
                  GradientButton(
                    loading: _starting,
                    loader: const SizedBox(
                        width: 26, height: 26, child: AppLoadingIndicator()),
                    label: tx('exam_start_now'),
                    icon: Icons.play_arrow_rounded,
                    onTap: _start,
                  )
                else ...[
                  if (canRetry) ...[
                    GradientButton(
                      loading: _starting,
                      label: tx('exam_retry'),
                      icon: Icons.replay_rounded,
                      color: kViolet,
                      subtitle: tx('exam_n_attempts_left', {'n': remaining}),
                      onTap: _start,
                    ),
                    const SizedBox(height: 12),
                  ],
                  SoftButton(
                    label: tx('exam_back'),
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(
        height: 1, color: context.colors.divider.withValues(alpha: 0.6)),
  );
}

// ── Score card ────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final StudentExamListItem exam;
  const _ScoreCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = exam.passed == true ? c.success : kDanger;
    final pct = exam.percentage ?? 0;

    return ExamSectionCard(
      icon: Icons.emoji_events_rounded,
      accent: color,
      title: tx('exam_best_score'),
      trailing: ExamBadge(
        exam.passed == true ? tx('exam_passed_mark') : tx('exam_failed_mark'),
        color,
      ),
      child: Column(children: [
        ExamBar(pct: pct, color: color, height: 9),
        const SizedBox(height: 14),
        Row(children: [
          ExamStatBox('${pct.toStringAsFixed(1)}%', tx('exam_percentage'), color),
          const SizedBox(width: 10),
          ExamStatBox(
            '${exam.marksObtained?.toStringAsFixed(0) ?? 0} / ${exam.totalMarks?.toStringAsFixed(0) ?? 0}',
            tx('exam_grade'),
            c.primary,
          ),
          const SizedBox(width: 10),
          ExamStatBox('${exam.answeredCount} / ${exam.questionCount}',
              tx('exam_you_answered'), Colors.blueGrey),
        ]),
        if (exam.submissionCount > 0) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.repeat_rounded, size: 14, color: c.textMedium),
            const SizedBox(width: 5),
            Text(tx('exam_submitted_n_times', {'n': exam.submissionCount}),
                style: examT(12, c: c.textMedium)),
          ]),
        ],
      ]),
    );
  }
}

// ── Countdown card ────────────────────────────────────────────────────────────

class _CountdownCard extends StatefulWidget {
  final DateTime target;
  const _CountdownCard({required this.target});

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  late final Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final r = widget.target.difference(DateTime.now());
    setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExamSectionCard(
    icon: Icons.hourglass_top_rounded,
    accent: kAmber,
    title: tx('exam_starts_in'),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _TimeBox(_remaining.inHours.toString().padLeft(2, '0'),
          tx('exam_hours')),
      const _Colon(),
      _TimeBox((_remaining.inMinutes % 60).toString().padLeft(2, '0'),
          tx('exam_minutes')),
      const _Colon(),
      _TimeBox((_remaining.inSeconds % 60).toString().padLeft(2, '0'),
          tx('exam_seconds')),
    ]),
  );
}

class _TimeBox extends StatelessWidget {
  final String value, label;
  const _TimeBox(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [kAmber.withValues(alpha: 0.22), kAmber.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAmber.withValues(alpha: 0.25)),
      ),
      child: Center(
        child: Text(value, style: examT(25, w: FontWeight.w900, c: kAmber)),
      ),
    ),
    const SizedBox(height: 6),
    Text(label, style: examT(11, c: context.colors.textMedium)),
  ]);
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 22),
    child: Text(':', style: examT(26, w: FontWeight.w900, c: kAmber)),
  );
}