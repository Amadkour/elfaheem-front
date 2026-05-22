// student_exam_result_screen.dart — Premium redesign
//
// Shows immediately after submission.
// NEW:
//  • "Best Score" gold crown badge when current = best
//  • Remaining attempts indicator
//  • "Try Again" button that calls provider.retryExam()
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'student_exam_provider.dart';

class StudentExamResultScreen extends StatefulWidget {
  final QuizSession session;
  final VoidCallback onExit;

  const StudentExamResultScreen({
    super.key,
    required this.session,
    required this.onExit,
  });

  @override
  State<StudentExamResultScreen> createState() => _StudentExamResultScreenState();
}

class _StudentExamResultScreenState extends State<StudentExamResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scoreAnim, _fadeAnim, _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _scoreAnim = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 1, curve: Curves.easeIn));
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 1, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  QuizSession get s => widget.session;

  double get _pct {
    if (s.result?.percentage != null) return s.result!.percentage;
    final total = s.questions.fold(0.0, (acc, q) => acc + q.marks);
    if (total == 0) return 0;
    final obtained = s.serverResponses.values
        .fold(0.0, (acc, r) => acc + ((r['marks_obtained'] as num?)?.toDouble() ?? 0));
    return (obtained / total * 100).clamp(0, 100);
  }

  double get _marksObtained =>
      s.result?.marksObtained ??
          s.serverResponses.values
              .fold(0.0, (acc, r) => acc + ((r['marks_obtained'] as num?)?.toDouble() ?? 0));

  double get _totalMarks =>
      s.result?.totalMarks ??
          s.questions.fold(0.0, (acc, q) => acc + q.marks);

  bool get _passed =>
      s.result?.passed ?? (_pct >= (s.exam.passingScore ?? 60));

  bool get _isBestEver => s.isCurrentBest;

  Color get _primary => _passed ? AppTheme.success : Colors.redAccent;
  Color get _secondary => _passed ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canRetry = s.canRetry;
    final remaining = s.remainingSubmissions;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Gradient App Bar ─────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: _primary,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_primary, _secondary],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        // Animated score ring
                        AnimatedBuilder(
                          animation: _scoreAnim,
                          builder: (_, __) => Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 110, height: 110,
                                child: CircularProgressIndicator(
                                  value: _scoreAnim.value * (_pct / 100),
                                  strokeWidth: 10,
                                  backgroundColor: Colors.white.withValues(alpha: .25),
                                  color: Colors.white,
                                ),
                              ),
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  '${(_scoreAnim.value * _pct).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontFamily: 'bahji',
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _passed ? 'ناجح ✓' : 'راسب ✗',
                                  style: const TextStyle(
                                    fontFamily: 'bahji',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.exam.name,
                          style: const TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: const Text(
                'نتيجة الاختبار',
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
                    _WarningBanner(message: 'تعذّر إرسال بعض الإجابات: ${s.submitError}'),
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
                    _SectionHeader(title: 'تفصيل الأسئلة', icon: Icons.list_alt_rounded),
                    const SizedBox(height: 10),
                    ...s.questions.asMap().entries.map((e) => _QuestionBreakdownTile(
                      index: e.key,
                      question: e.value,
                      answer: s.answers[e.key],
                      serverResponse: s.serverResponses[e.key],
                    )),
                    const SizedBox(height: 16),
                  ],

                  // ── Actions ───────────────────────────────────────────────
                  // Retry button (only when student has remaining attempts)
                  if (canRetry) ...[
                    _RetryButton(
                      remaining: remaining,
                      onTap: () async {
                        final prov = context.read<StudentExamProvider>();
                        final ok = await prov.retryExam();
                        if (!ok || !context.mounted) return;
                        // retryExam creates a new session; QuizScreen will
                        // rebuild automatically via Consumer/watch.
                        Navigator.of(context).pop(); // close result screen
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Exit button
                  _GradBtn(
                    label: _passed ? 'ابدأ التعلم الآن' : 'العودة للرئيسية',
                    c1: _primary, c2: _secondary,
                    onTap: widget.onExit,
                  ),
                ]),
              ),
            ),
          ],
        ),
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
    final color = passed ? c.success : Colors.redAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .10), color.withValues(alpha: .04)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: .7)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Icon(
            passed ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
            color: Colors.white, size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  passed ? 'تهانينا! اجتزت الاختبار 🎉' : 'لم تجتز الاختبار هذه المرة',
                  style: TextStyle(
                    fontFamily: 'bahji', fontSize: 15,
                    fontWeight: FontWeight.w800, color: color,
                  ),
                ),
              ),
              if (isBestEver && passed) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 3),
                    Text('أفضل نتيجة', style: TextStyle(
                      fontFamily: 'bahji', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white,
                    )),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              passed
                  ? 'حققت ${pct.toStringAsFixed(1)}% وهو أعلى من حد النجاح (${passingScore.toInt()}%)'
                  : 'حققت ${pct.toStringAsFixed(1)}% وحد النجاح ${passingScore.toInt()}%',
              style: TextStyle(fontFamily: 'bahji', fontSize: 12, color: color.withValues(alpha: .8)),
            ),
          ]),
        ),
      ]),
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
      child: Column(children: [
        _StatRow('درجتك',
            '${marksObtained.toStringAsFixed(1)} / ${totalMarks.toStringAsFixed(0)}',
            color, Icons.grade_rounded),
        _div(),
        _StatRow('الأسئلة المجابة', '$answered / $total', Colors.teal, Icons.help_outline_rounded),
        _div(),
        _StatRow('درجة النجاح', '${passingScore.toInt()}%', Colors.orange, Icons.star_outline_rounded),
        _div(),
        _StatRow('رقم المحاولة', '$submissionCount${maxSubmissions != null ? ' / $maxSubmissions' : ''}',
            Colors.purple, Icons.repeat_rounded),
        if (remaining != null && maxSubmissions != null) ...[
          _div(),
          _StatRow(
            'محاولات متبقية',
            '$remaining',
            remaining! > 0 ? Colors.green : Colors.redAccent,
            Icons.replay_rounded,
          ),
        ],
      ]),
    );
  }

  Widget _div() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Divider(height: 20, color: Colors.grey.shade100),
  );
}

class _StatRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatRow(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 8),
    Text(label, style: const TextStyle(fontFamily: 'bahji', fontSize: 13, color: Colors.grey)),
    const Spacer(),
    Text(value, style: TextStyle(
      fontFamily: 'bahji', fontSize: 15, fontWeight: FontWeight.w800, color: color,
    )),
  ]);
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
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF8E44AD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C5CE7).withValues(alpha: .4),
            blurRadius: 18, offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.replay_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('حاول مرة أخرى', style: TextStyle(
            fontFamily: 'bahji', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white,
          )),
          if (remaining != null)
            Text('متبقي $remaining محاولة', style: const TextStyle(
              fontFamily: 'bahji', fontSize: 10, color: Colors.white70,
            )),
        ]),
      ]),
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
    final marksObtained = (serverResponse?['marks_obtained'] as num?)?.toDouble();
    final hasResult = serverResponse != null;

    Color color;
    IconData icon;
    if (!hasResult || answer == null) {
      color = Colors.grey;
      icon = Icons.remove_circle_outline_rounded;
    } else if (isCorrect == true) {
      color = context.colors.success;
      icon = Icons.check_circle_rounded;
    } else {
      color = Colors.redAccent;
      icon = Icons.cancel_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'السؤال ${index + 1}: ${question.title}',
              style: const TextStyle(fontFamily: 'bahji', fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              answer != null ? 'إجابتك: $answer' : 'لم تُجب على هذا السؤال',
              style: TextStyle(fontFamily: 'bahji', fontSize: 12, color: color),
            ),
          ]),
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
              style: TextStyle(fontFamily: 'bahji', fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
      ]),
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
    return Row(children: [
      Icon(icon, size: 18, color: c.primary),
      const SizedBox(width: 8),
      Text(title, style: c.h3.copyWith(fontSize: 15)),
    ]);
  }
}

class _GradBtn extends StatelessWidget {
  final String label;
  final Color c1, c2;
  final VoidCallback onTap;
  const _GradBtn({required this.label, required this.c1, required this.c2, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: c1.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 7))],
      ),
      child: Center(
        child: Text(label, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, fontFamily: 'bahji',
        )),
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
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(children: [
      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontFamily: 'bahji', fontSize: 12, color: Colors.orange))),
    ]),
  );
}