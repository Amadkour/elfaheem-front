
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:flutter_education_app/features/student/analysis/exam/student_exam_api.dart';

class StudentExamFrozenScreen extends StatefulWidget {
  final StudentExamListItem exam;
  final VoidCallback onBack;

  const StudentExamFrozenScreen({
    super.key,
    required this.exam,
    required this.onBack,
  });

  @override
  State<StudentExamFrozenScreen> createState() =>
      _StudentExamFrozenScreenState();
}

class _StudentExamFrozenScreenState extends State<StudentExamFrozenScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _ctrl.forward();

    // If deadline hasn't passed yet (submissions used up) still show countdown
    if (widget.exam.endDate != null && !widget.exam.isDeadlineFrozen) {
      _remaining = widget.exam.endDate!.difference(DateTime.now());
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _remaining = widget.exam.endDate!.difference(DateTime.now());
          if (_remaining.isNegative) _remaining = Duration.zero;
        });
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  StudentExamListItem get e => widget.exam;

  bool get _isDeadline => e.isDeadlineFrozen;
  bool get _isSubmissions => e.isSubmissionsFrozen;
  bool get _hasScore =>
      e.isSubmitted && e.percentage != null;

  Color get _accent =>
      _hasScore ? (e.passed == true ? AppTheme.success : Colors.redAccent) : Colors.blueGrey;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded),
            onPressed: widget.onBack,
          ),
          title: Text(e.name,
              style: const TextStyle(
                  fontFamily: 'bahji', fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            // ── Freeze icon ─────────────────────────────────────────────────
            FadeTransition(
              opacity: _ctrl,
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withValues(alpha: 0.1),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.3), width: 3),
                  ),
                  child: Icon(
                    _isDeadline
                        ? Icons.event_busy_rounded
                        : Icons.block_rounded,
                    size: 52,
                    color: _accent,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Freeze reason ───────────────────────────────────────────────
            Text(
              _isDeadline
                  ? 'انتهى الموعد النهائي للاختبار'
                  : 'استنفدت جميع محاولاتك',
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _accent),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              _isDeadline
                  ? 'لم يعد بالإمكان تقديم هذا الاختبار.\nتواصل مع المعلم إذا كنت بحاجة لمهلة إضافية.'
                  : 'لقد قدّمت هذا الاختبار ${e.submissionCount} مرة وهو الحد المسموح به.',
              style: const TextStyle(
                  fontFamily: 'bahji', fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // ── Deadline passed timestamp ────────────────────────────────────
            if (_isDeadline && e.endDate != null)
              _InfoCard(children: [
                _InfoRow(
                  icon: Icons.event_busy_rounded,
                  label: 'الموعد النهائي',
                  value:
                      '${e.endDate!.day}/${e.endDate!.month}/${e.endDate!.year}  '
                      '${e.endDate!.hour.toString().padLeft(2, '0')}:${e.endDate!.minute.toString().padLeft(2, '0')}',
                  color: Colors.redAccent,
                ),
              ]),

            // ── Submissions info ─────────────────────────────────────────────
            if (_isSubmissions)
              _InfoCard(children: [
                _InfoRow(
                  icon: Icons.repeat_rounded,
                  label: 'المحاولات المستخدمة',
                  value: '${e.submissionCount} / ${e.maxSubmissions}',
                  color: Colors.purple,
                ),
              ]),

            // ── Score summary if submitted ───────────────────────────────────
            if (_hasScore) ...[
              const SizedBox(height: 12),
              _ScoreSummaryCard(exam: e, accent: _accent),
            ],

            // ── Exam meta ────────────────────────────────────────────────────
            const SizedBox(height: 12),
            _InfoCard(children: [
              if (e.duration != null)
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'مدة الاختبار',
                  value: '${e.duration} دقيقة',
                  color: Colors.teal,
                ),
              if (e.questionCount > 0)
                _InfoRow(
                  icon: Icons.help_outline_rounded,
                  label: 'عدد الأسئلة',
                  value: '${e.questionCount}',
                  color: context.colors.primary,
                ),
              if (e.passingScore != null)
                _InfoRow(
                  icon: Icons.star_outline_rounded,
                  label: 'درجة النجاح',
                  value: '${e.passingScore!.toInt()}%',
                  color: Colors.amber.shade700,
                ),
            ]),

            const SizedBox(height: 28),

            // ── Back button ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: Colors.white),
                label: const Text('العودة للاختبارات',
                    style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Score summary card ────────────────────────────────────────────────────────

class _ScoreSummaryCard extends StatelessWidget {
  final StudentExamListItem exam;
  final Color accent;
  const _ScoreSummaryCard({required this.exam, required this.accent});

  @override
  Widget build(BuildContext context) {
    final pct = exam.percentage!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10)
        ],
      ),
      child: Column(children: [
        Text('نتيجتك الأخيرة',
            style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                color: Colors.grey)),
        const SizedBox(height: 12),
        // Mini ring
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 9,
              backgroundColor: Colors.grey.shade100,
              color: accent,
            ),
          ),
          Text('${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: accent)),
        ]),
        const SizedBox(height: 12),
        Text(
          exam.passed == true ? 'ناجح ✓' : 'راسب ✗',
          style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: accent),
        ),
        if (exam.marksObtained != null && exam.totalMarks != null) ...[
          const SizedBox(height: 4),
          Text(
            '${exam.marksObtained!.toStringAsFixed(1)} / ${exam.totalMarks!.toStringAsFixed(0)} درجة',
            style: const TextStyle(
                fontFamily: 'bahji', fontSize: 13, color: Colors.grey),
          ),
        ],
      ]),
    );
  }
}

// ── Shared micro widgets ──────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8)
          ],
        ),
        child: Column(
          children: children
              .expand((w) => [
                    w,
                    if (w != children.last) const Divider(height: 16)
                  ])
              .toList(),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontFamily: 'bahji', fontSize: 13, color: Colors.grey)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color)),
      ]);
}
