import 'package:flutter_education_app/core/app_time.dart';
import 'dart:async';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/student/analysis/exam/student_exam_api.dart';
import 'package:flutter_education_app/features/student/analysis/exam/exam_tr.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

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
      _hasScore ? (e.passed == true ? AppTheme.success : context.colors.danger) : context.colors.textMedium;

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('exam_frozen'),
      useWebCard: true,
      width: AppWidth.reading,
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: context.colors.onHero,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
        title: Text(e.name,
            style: TextStyle(
                fontFamily: AppFonts.display, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
      ),
      child: SingleChildScrollView(
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
                ? tx('exam_frozen_deadline_title')
                : tx('exam_frozen_attempts_title'),
            style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _accent),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            _isDeadline
                ? tx('exam_frozen_deadline_msg')
                : tx('exam_frozen_attempts_msg', {'count': e.submissionCount}),
            style: TextStyle(
                fontFamily: AppFonts.display, fontSize: 14, color: context.colors.textLight),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // ── Deadline passed timestamp ────────────────────────────────────
          if (_isDeadline && e.endDate != null)
            _InfoCard(children: [
              _InfoRow(
                icon: Icons.event_busy_rounded,
                label: tx('exam_deadline'),
                value: AppTime.dateTime(e.endDate!),
                color: context.colors.danger,
              ),
            ]),

          // ── Submissions info ─────────────────────────────────────────────
          if (_isSubmissions)
            _InfoCard(children: [
              _InfoRow(
                icon: Icons.repeat_rounded,
                label: tx('exam_used_attempts'),
                value: '${e.submissionCount} / ${e.maxSubmissions}',
                color: context.colors.purple,
              ),
            ]),

          // ── Score summary if submitted ───────────────────────────────────
          if (_hasScore) ...[
            const SizedBox(height: 12),
            ParentComponent(featureKey: 'exam_frozen.score', child: _ScoreSummaryCard(exam: e, accent: _accent)),
          ],

          // ── Exam meta ────────────────────────────────────────────────────
          const SizedBox(height: 12),
          ParentComponent(
              featureKey: 'exam_frozen.meta',
              child: _InfoCard(children: [
                if (e.duration != null)
                  _InfoRow(
                    icon: Icons.timer_outlined,
                    label: tx('exam_exam_duration'),
                    value: tx('exam_n_minutes', {'n': e.duration}),
                    color: context.colors.success,
                  ),
                if (e.questionCount > 0)
                  _InfoRow(
                    icon: Icons.help_outline_rounded,
                    label: tx('exam_question_count'),
                    value: '${e.questionCount}',
                    color: context.colors.primary,
                  ),
                if (e.passingScore != null)
                  _InfoRow(
                    icon: Icons.star_outline_rounded,
                    label: tx('exam_passing_score'),
                    value: '${e.passingScore!.toInt()}%',
                    color: context.colors.warning,
                  ),
              ])),

          const SizedBox(height: 28),

          // ── Back button ──────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onBack,
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 16, color: context.colors.onHero),
              label: Text(tx('exam_back_to_exams'),
                  style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: context.colors.onHero,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ]),
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
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: context.colors.heroShade.withValues(alpha: 0.04),
              blurRadius: 10)
        ],
      ),
      child: Column(children: [
        Text(tx('exam_last_result'),
            style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 13,
                color: context.colors.textLight)),
        const SizedBox(height: 12),
        // Mini ring
        Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 9,
              backgroundColor: context.colors.inputBg,
              color: accent,
            ),
          ),
          Text('${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: accent)),
        ]),
        const SizedBox(height: 12),
        Text(
          exam.passed == true ? tx('exam_passed_mark') : tx('exam_failed_mark'),
          style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: accent),
        ),
        if (exam.marksObtained != null && exam.totalMarks != null) ...[
          const SizedBox(height: 4),
          Text(
            tx('exam_marks_of_total', {'obtained': exam.marksObtained!.toStringAsFixed(1), 'total': exam.totalMarks!.toStringAsFixed(0)}),
            style: TextStyle(
                fontFamily: AppFonts.display, fontSize: 13, color: context.colors.textLight),
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
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.04),
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
        style: TextStyle(
            fontFamily: AppFonts.display, fontSize: 13, color: context.colors.textLight)),
    const Spacer(),
    Text(value,
        style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color)),
  ]);
}