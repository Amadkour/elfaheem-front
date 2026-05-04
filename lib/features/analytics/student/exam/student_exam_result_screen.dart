// features/student/exam/student_exam_result_screen.dart
//
// Shown immediately after submission.  Uses the server result (StudentMyResult)
// when available; falls back gracefully if the fetch failed.

import 'package:flutter/material.dart';
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
  State<StudentExamResultScreen> createState() =>
      _StudentExamResultScreenState();
}

class _StudentExamResultScreenState extends State<StudentExamResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scoreAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _scoreAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Computed values ────────────────────────────────────────────────────────
  QuizSession get s => widget.session;

  double get _pct {
    if (s.result?.percentage != null) return s.result!.percentage;
    final total = s.questions.fold(0.0, (acc, q) => acc + q.marks);
    if (total == 0) return 0;
    // Without server result we can only guess (MCQ auto-grade via serverResponses)
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

  Color get _color => _passed ? context.colors.success : Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: _color,
          automaticallyImplyLeading: false,
          title: const Text(
            'نتيجة الاختبار',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            // ── Submit error warning ──────────────────────────────────────────
            if (s.submitError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'تعذّر إرسال بعض الإجابات: ${s.submitError}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.orange),
                  )),
                ]),
              ),
            ],

            // ── Animated score ring ───────────────────────────────────────────
            AnimatedBuilder(
              animation: _scoreAnim,
              builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 170,
                      height: 170,
                      child: CircularProgressIndicator(
                        value: _scoreAnim.value * (_pct / 100),
                        strokeWidth: 13,
                        backgroundColor: Colors.grey.shade100,
                        color: _color,
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        '${(_scoreAnim.value * _pct).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: _color),
                      ),
                      Text(
                        _passed ? 'ناجح ✓' : 'راسب ✗',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _color),
                      ),
                    ]),
                  ]),
            ),

            const SizedBox(height: 24),

            Text(
              _passed
                  ? 'تهانينا! اجتزت الاختبار بنجاح 🎉'
                  : 'لم تجتز الاختبار هذه المرة، حاول مجدداً',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _color),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // ── Stats card ────────────────────────────────────────────────────
            _StatsCard(
              pct: _pct,
              marksObtained: _marksObtained,
              totalMarks: _totalMarks,
              answered: s.answeredCount,
              total: s.questions.length,
              passingScore: s.exam.passingScore ?? 60,
              color: _color,
            ),

            const SizedBox(height: 20),

            // ── Per-question breakdown ────────────────────────────────────────
            if (s.serverResponses.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'تفصيل الأسئلة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
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
            ],

            const SizedBox(height: 24),

            // ── Exit button ───────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onExit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('العودة للرئيسية',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Stats card ─────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final double pct, marksObtained, totalMarks, passingScore;
  final int answered, total;
  final Color color;

  const _StatsCard({
    required this.pct,
    required this.marksObtained,
    required this.totalMarks,
    required this.answered,
    required this.total,
    required this.passingScore,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10)
          ],
        ),
        child: Column(children: [
          _StatRow('درجتك',
              '${marksObtained.toStringAsFixed(1)} / ${totalMarks.toStringAsFixed(0)}',
              color),
          const Divider(height: 20),
          _StatRow(
              'الأسئلة المجابة', '$answered / $total', Colors.teal),
          const Divider(height: 20),
          _StatRow('درجة النجاح', '${passingScore.toInt()}%',
              Colors.orange),
        ]),
      );
}

class _StatRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 14, color: Colors.grey)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color)),
      ]);
}

// ── Question breakdown tile ───────────────────────────────────────────────────

class _QuestionBreakdownTile extends StatelessWidget {
  final int index;
  final dynamic question; // Question
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
    final marksObtained =
        (serverResponse?['marks_obtained'] as num?)?.toDouble();
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
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              'السؤال ${index + 1}: ${question.title}',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              answer != null ? 'إجابتك: $answer' : 'لم تُجب على هذا السؤال',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: color),
            ),
          ]),
        ),
        if (hasResult && marksObtained != null)
          Text(
            '${marksObtained.toStringAsFixed(1)} / ${question.marks.toStringAsFixed(0)}',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color),
          ),
      ]),
    );
  }
}
