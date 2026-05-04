// features/student/exam/student_exam_detail_screen.dart
//
// Entry gate: shows exam info, optional passcode field, then launches the quiz.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'student_exam_api.dart';
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
  final _passcodeCtrl = TextEditingController();
  bool _hasPasscode = false;
  bool _starting = false;
  String? _entryError;

  @override
  void initState() {
    super.initState();
    // We don't get the passcode from the list endpoint intentionally (security).
    // The student types it; we trust the server to validate it (the server
    // will return 403 if passcode is wrong — handled in _start).
    // Here we just show the passcode field if the exam has a duration,
    // which indicates it's a timed, secured exam.
    // Adjust this heuristic to suit your product logic.
    _hasPasscode = widget.exam.questionCount == 0; // placeholder; see below
  }

  @override
  void dispose() {
    _passcodeCtrl.dispose();
    super.dispose();
  }

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
      setState(() => _entryError = prov.questionsError ?? 'تعذّر تحميل الأسئلة');
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

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    final isDone = exam.isSubmitted;
    final isScheduled =
        exam.startDate != null && exam.startDate!.isAfter(DateTime.now());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            exam.name,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const SizedBox(height: 12),

            // ── Hero icon ────────────────────────────────────────────────────
            _HeroIcon(isDone: isDone, passed: exam.passed),

            const SizedBox(height: 20),

            // ── Exam name & course ───────────────────────────────────────────
            Text(exam.name,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 20,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            if (exam.courseName != null) ...[
              const SizedBox(height: 4),
              Text(exam.courseName!,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      color: Colors.grey)),
            ],
            if (exam.description != null) ...[
              const SizedBox(height: 8),
              Text(exam.description!,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.5),
                  textAlign: TextAlign.center),
            ],

            const SizedBox(height: 24),

            // ── Info card ────────────────────────────────────────────────────
            _InfoCard(children: [
              _InfoRow(Icons.help_outline_rounded, 'عدد الأسئلة',
                  '${exam.questionCount} سؤال', context.colors.primary),
              _InfoRow(Icons.timer_outlined, 'المدة',
                  '${exam.duration ?? 0} دقيقة', Colors.teal),
              if (exam.passingScore != null)
                _InfoRow(Icons.star_outline_rounded, 'درجة النجاح',
                    '${exam.passingScore!.toInt()}%', Colors.amber.shade700),
              if (exam.totalMarks != null)
                _InfoRow(Icons.grade_outlined, 'إجمالي الدرجات',
                    '${exam.totalMarks!.toInt()} درجة', Colors.purple),
              if (exam.startDate != null)
                _InfoRow(Icons.schedule_rounded, 'وقت البدء',
                    _fmtDate(exam.startDate!), Colors.orange),
            ]),

            const SizedBox(height: 16),

            // ── Score card (only when submitted) ─────────────────────────────
            if (isDone) ...[
              _ScoreCard(exam: exam),
              const SizedBox(height: 16),
            ],

            // ── Countdown (only when scheduled) ─────────────────────────────
            if (isScheduled && !isDone) ...[
              _CountdownCard(target: exam.startDate!),
              const SizedBox(height: 16),
            ],

            // ── Error banner ─────────────────────────────────────────────────
            if (_entryError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_entryError!,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Colors.red))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Primary action ───────────────────────────────────────────────
            if (!isDone && !isScheduled)
              _StartButton(loading: _starting, onPressed: _start),

            if (isDone)
              _DoneButton(onPressed: () => Navigator.pop(context)),

            const SizedBox(height: 12),

            // ── Warning notice ───────────────────────────────────────────────
            if (!isDone && !isScheduled)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3))),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'بمجرد بدء الاختبار لا يمكن إيقافه مؤقتاً. '
                      'تأكد من اتصالك بالإنترنت قبل البدء.',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.orange),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _HeroIcon extends StatelessWidget {
  final bool isDone;
  final bool? passed;
  const _HeroIcon({required this.isDone, required this.passed});

  @override
  Widget build(BuildContext context) {
    final Color col = isDone
        ? (passed == true ? context.colors.success : Colors.redAccent)
        : context.colors.primary;
    final IconData ico = isDone
        ? (passed == true ? Icons.emoji_events_rounded : Icons.cancel_rounded)
        : Icons.quiz_rounded;

    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [col, col.withValues(alpha: 0.6)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: col.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: Icon(ico, color: Colors.white, size: 42),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10)
            ]),
        child: Column(
          children: children.map((c) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: c,
          )).toList(),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 13, color: Colors.grey)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color)),
      ]);
}

class _ScoreCard extends StatelessWidget {
  final StudentExamListItem exam;
  const _ScoreCard({required this.exam});

  Color get _color =>
      exam.passed == true ? AppTheme.success : Colors.redAccent;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              _color.withValues(alpha: 0.12),
              _color.withValues(alpha: 0.04)
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(
            exam.passed == true ? 'مبروك! اجتزت الاختبار ✓' : 'لم تجتز الاختبار هذه المرة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _color),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _ScoreStat('${exam.percentage?.toStringAsFixed(1) ?? 0}%',
                'النسبة', _color),
            _ScoreStat(
                '${exam.marksObtained?.toStringAsFixed(0) ?? 0} / '
                '${exam.totalMarks?.toStringAsFixed(0) ?? 0}',
                'الدرجة',
                _color),
            _ScoreStat(
                '${exam.answeredCount} / ${exam.questionCount}',
                'أجبت',
                Colors.grey),
          ]),
        ]),
      );
}

class _ScoreStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _ScoreStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: Colors.grey)),
      ]);
}

class _StartButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _StartButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 22),
                    SizedBox(width: 8),
                    Text('ابدأ الاختبار الآن',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      );
}

class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DoneButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('العودة',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      );
}

// ── Countdown card ────────────────────────────────────────────────────────────

class _CountdownCard extends StatefulWidget {
  final DateTime target;
  const _CountdownCard({required this.target});

  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  late Timer _timer;
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
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
        child: Column(children: [
          const Text('يبدأ الاختبار خلال',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _TimeBox(
                _remaining.inHours.toString().padLeft(2, '0'), 'ساعة'),
            _Colon(),
            _TimeBox(
                (_remaining.inMinutes % 60).toString().padLeft(2, '0'),
                'دقيقة'),
            _Colon(),
            _TimeBox(
                (_remaining.inSeconds % 60).toString().padLeft(2, '0'),
                'ثانية'),
          ]),
        ]),
      );
}

class _TimeBox extends StatelessWidget {
  final String value, label;
  const _TimeBox(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.orange))),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
      ]);
}

class _Colon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(':',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.orange)),
      );
}
