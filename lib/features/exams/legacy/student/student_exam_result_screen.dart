// student_exam_result_screen.dart — Premium redesign
//
// Shows immediately after submission.
// NEW:
//  • "Best Score" gold crown badge when current = best
//  • Remaining attempts indicator
//  • "Try Again" button that calls provider.retryExam()
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_quiz_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/exam_tr.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

class StudentExamResultScreen extends StatefulWidget {
  final QuizSession session;
  final VoidCallback onExit;

  const StudentExamResultScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  @override
  State<StudentExamResultScreen> createState() =>
      _StudentExamResultScreenState();
}

class _StudentExamResultScreenState extends State<StudentExamResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scoreAnim, _fadeAnim, _scaleAnim;

  // Kept so dispose() can reach the provider without a BuildContext.
  late final StudentExamProvider _examProv;
  // True while this screen is replaced by a new attempt (retry): the exam
  // flow is NOT finished then, so the "after exam" hook must not fire.
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _examProv = context.read<StudentExamProvider>();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _scoreAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.7, curve: Curves.easeOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 1, curve: Curves.easeIn),
    );
    _scaleAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.4, 1, curve: Curves.elasticOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    // Result screen closed (exit button or system back) → exam flow is over.
    if (!_retrying) _examProv.finishFlow();
    super.dispose();
  }

  QuizSession get s => widget.session;

  double get _pct {
    if (s.result?.percentage != null) return s.result!.percentage;
    final total = s.questions.fold(0.0, (acc, q) => acc + q.marks);
    if (total == 0) return 0;
    final obtained = s.serverResponses.values.fold(
      0.0,
          (acc, r) => acc + ((r['marks_obtained'] as num?)?.toDouble() ?? 0),
    );
    return (obtained / total * 100).clamp(0, 100);
  }

  double get _marksObtained =>
      s.result?.marksObtained ??
          s.serverResponses.values.fold(
            0.0,
                (acc, r) => acc + ((r['marks_obtained'] as num?)?.toDouble() ?? 0),
          );

  double get _totalMarks =>
      s.result?.totalMarks ?? s.questions.fold(0.0, (acc, q) => acc + q.marks);

  bool get _passed => s.result?.passed ?? (_pct >= (s.exam.passingScore ?? 60));

  bool get _isBestEver => s.isCurrentBest;

  Color get _primary => _passed ? context.colors.success : context.colors.danger;

  Color get _secondary =>
      _passed ? context.colors.success : context.colors.danger;

  // the exam area (redesign S-C): the kit hero, the forward button and the area accent
  @override
  Widget build(BuildContext context) => AppAreaScope(area: AppArea.exam, child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final canRetry = s.canRetry;
    final remaining = s.remainingSubmissions;

    return BasePage(
      useWebCard: true,
      width: AppWidth.reading,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Gradient App Bar ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: _primary,
            flexibleSpace: FlexibleSpaceBar(
              background: AppMeshSurface(
                color: _primary,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      // Animated score ring
                      AnimatedBuilder(
                        animation: _scoreAnim,
                        builder: (_, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 110,
                              height: 110,
                              child: CircularProgressIndicator(
                                value: _scoreAnim.value * (_pct / 100),
                                strokeWidth: 10,
                                backgroundColor: context.colors.onHero.withValues(
                                  alpha: .25,
                                ),
                                color: context.colors.onHero,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(_scoreAnim.value * _pct).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: context.colors.onHero,
                                  ),
                                ),
                                Text(
                                  _passed
                                      ? tx('exam_passed_mark')
                                      : tx('exam_failed_mark'),
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.onHero,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.exam.name,
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 14,
                          color: context.colors.onHeroMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            title: Text(
              tx('exam_result_title'),
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
                color: context.colors.onHero,
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Submit error warning
                if (s.submitError != null) ...[
                  _WarningBanner(
                    message: tx('exam_result_submit_warning', {
                      'error': s.submitError,
                    }),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Best score / pass banner ──────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: _ResultBanner(
                      passed: _passed,
                      isBestEver: _isBestEver,
                      pct: _pct,
                      passingScore: s.exam.passingScore ?? 60,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Stats card ────────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: _StatsCard(
                    pct: _pct,
                    marksObtained: _marksObtained,
                    totalMarks: _totalMarks,
                    answered: s.answeredCount,
                    total: s.questions.length,
                    passingScore: s.exam.passingScore ?? 60,
                    submissionCount: s.result?.submissionCount ?? 1,
                    maxSubmissions: s.exam.maxSubmissions,
                    remaining: remaining,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Per-question breakdown ────────────────────────────────
                if (s.serverResponses.isNotEmpty) ...[
                  _SectionHeader(
                    title: tx('exam_result_breakdown'),
                    icon: Icons.list_alt_rounded,
                  ),
                  const SizedBox(height: 10),
                  ...s.questions.asMap().entries.map(
                        (e) => _QuestionBreakdownTile(
                      index: e.key,
                      question: e.value,
                      answer: s.answers[e.key],
                      serverResponse: s.serverResponses[e.key],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Actions ───────────────────────────────────────────────
                // Retry button (only when student has remaining attempts)
                if (canRetry) ...[
                  _RetryButton(
                    remaining: remaining,
                    onTap: () async {
                      final prov = context.read<StudentExamProvider>();
                      final nav = Navigator.of(context);
                      final ok = await prov.retryExam();
                      if (!ok || !context.mounted) return;
                      _retrying = true; // new attempt → flow continues
                      // retryExam created a fresh session: open the quiz again.
                      nav.pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider.value(
                            value: prov,
                            child: const StudentExamQuizScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Exit button
                _GradBtn(
                  label: _passed
                      ? tx('exam_result_start_learning')
                      : tx('exam_result_back_course'),
                  c1: _primary,
                  c2: _secondary,
                  onTap: widget.onExit,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result banner ─────────────────────────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final bool passed, isBestEver;
  final double pct, passingScore;

  const _ResultBanner({
    required this.passed,
    required this.isBestEver,
    required this.pct,
    required this.passingScore,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = passed ? c.success : context.colors.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: AppGradients.blend(context, color: color),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              passed
                  ? Icons.emoji_events_rounded
                  : Icons.sentiment_dissatisfied_rounded,
              color: c.onHero,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        passed
                            ? tx('exam_result_congrats')
                            : tx('exam_result_not_passed'),
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    if (isBestEver && passed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppGradients.blend(context, color: c.accent2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: c.onHero,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              tx('exam_best_score'),
                              style: TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: c.onHero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  passed
                      ? tx('exam_result_pass_detail', {
                    'pct': pct.toStringAsFixed(1),
                    'passing': passingScore.toInt(),
                  })
                      : tx('exam_result_fail_detail', {
                    'pct': pct.toStringAsFixed(1),
                    'passing': passingScore.toInt(),
                  }),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 12,
                    color: color.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final double pct, marksObtained, totalMarks, passingScore;
  final int answered, total, submissionCount;
  final int? maxSubmissions, remaining;
  final Color color;

  const _StatsCard({
    required this.pct,
    required this.marksObtained,
    required this.totalMarks,
    required this.answered,
    required this.total,
    required this.passingScore,
    required this.submissionCount,
    required this.maxSubmissions,
    required this.remaining,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        children: [
          _StatRow(
            tx('exam_your_score'),
            '${marksObtained.toStringAsFixed(1)} / ${totalMarks.toStringAsFixed(0)}',
            color,
            Icons.grade_rounded,
          ),
          _div(context),
          _StatRow(
            tx('exam_answered_questions'),
            '$answered / $total',
            context.colors.success,
            Icons.help_outline_rounded,
          ),
          _div(context),
          _StatRow(
            tx('exam_passing_score'),
            '${passingScore.toInt()}%',
            context.colors.warning,
            Icons.star_outline_rounded,
          ),
          _div(context),
          _StatRow(
            tx('exam_attempt_number'),
            '$submissionCount${maxSubmissions != null ? ' / $maxSubmissions' : ''}',
            context.colors.purple,
            Icons.repeat_rounded,
          ),
          if (remaining != null && maxSubmissions != null) ...[
            _div(context),
            _StatRow(
              tx('exam_remaining_attempts_short'),
              '$remaining',
              remaining! > 0 ? context.colors.success : context.colors.danger,
              Icons.replay_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _div(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Divider(height: 20, color: context.colors.divider),
  );
}

class _StatRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;

  const _StatRow(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 13,
          color: context.colors.textLight,
        ),
      ),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );
}

// ── Retry button ──────────────────────────────────────────────────────────────

class _RetryButton extends StatelessWidget {
  final int? remaining;
  final VoidCallback onTap;

  const _RetryButton({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: AppGradients.brand(context),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: context.colors.primaryLight.withValues(alpha: .4),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.replay_rounded, color: context.colors.onHero, size: 20),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tx('exam_retry'),
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.colors.onHero,
                ),
              ),
              if (remaining != null)
                Text(
                  tx('exam_attempts_remaining_n', {'n': remaining}),
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 10,
                    color: context.colors.onHeroMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ── Question breakdown tile ───────────────────────────────────────────────────

class _QuestionBreakdownTile extends StatelessWidget {
  final int index;
  final dynamic question;
  final String? answer;
  final Map<String, dynamic>? serverResponse;

  const _QuestionBreakdownTile({
    required this.index,
    required this.question,
    required this.answer,
    required this.serverResponse,
  });

  @override
  Widget build(BuildContext context) {
    final isCorrect = serverResponse?['is_correct'] as bool?;
    final marksObtained = (serverResponse?['marks_obtained'] as num?)
        ?.toDouble();
    final hasResult = serverResponse != null;

    Color color;
    IconData icon;
    if (!hasResult || answer == null) {
      color = context.colors.textLight;
      icon = Icons.remove_circle_outline_rounded;
    } else if (isCorrect == true) {
      color = context.colors.success;
      icon = Icons.check_circle_rounded;
    } else {
      color = context.colors.danger;
      icon = Icons.cancel_rounded;
    }

    return Directionality(
      textDirection: Helpers.textDirOf(question.title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx('exam_result_q_title', {
                      'n': index + 1,
                      'title': question.title,
                    }),
                    textDirection: Helpers.textDirOf('${question.title}'),
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    answer != null
                        ? tx('exam_your_answer', {'answer': answer})
                        : tx('exam_not_answered'),
                    textDirection: Helpers.textDirOf(answer ?? tx('exam_not_answered')),
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (hasResult && marksObtained != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${marksObtained.toStringAsFixed(1)} / ${question.marks.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Shared micro-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 18, color: c.primary),
        const SizedBox(width: 8),
        Text(title, style: c.h3.copyWith(fontSize: 15)),
      ],
    );
  }
}

class _GradBtn extends StatelessWidget {
  final String label;
  final Color c1, c2;
  final VoidCallback onTap;

  const _GradBtn({
    required this.label,
    required this.c1,
    required this.c2,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: AppGradients.blend(context, color: c1),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: c1.withValues(alpha: .4),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.onHero,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            fontFamily: AppFonts.display,
          ),
        ),
      ),
    ),
  );
}

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.colors.warning,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.colors.warning),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: context.colors.warning, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 12,
              color: context.colors.warning,
            ),
          ),
        ),
      ],
    ),
  );
}